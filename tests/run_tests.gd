extends SceneTree
## Headless test runner: godot --headless --path . -s res://tests/run_tests.gd
##
## Zero-dependency (no GUT addon needed in P0). Each test script extends
## RefCounted and exposes methods named test_*; assertions go through T.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/test_fixed.gd",
	"res://tests/test_sim_rng.gd",
	"res://tests/test_gameplay.gd",
	"res://tests/test_archetypes.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_war_chest.gd",
	"res://tests/test_shop.gd",
	"res://tests/test_tank.gd",
	"res://tests/test_observer.gd",
	"res://tests/test_gates.gd",
	"res://tests/test_mechanics.gd",
	"res://tests/test_water.gd",
	"res://tests/test_biomes.gd",
	"res://tests/test_boss.gd",
	"res://tests/test_lockstep.gd",
	"res://tests/test_endless.gd",
	"res://tests/test_mutators.gd",
	"res://tests/test_colossus.gd",
	"res://tests/test_determinism.gd",
	"res://tests/test_checksum_coverage.gd",
	"res://tests/test_event_coverage.gd",
	"res://tests/test_replay.gd",
	"res://tests/test_leaderboard.gd",
	"res://tests/test_endless_meta.gd",
	"res://tests/test_robustness.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_main.gd",
	"res://tests/test_steam_bridge.gd",
	"res://tests/test_menu_layout.gd",
	"res://tests/test_localization.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_stub_parity.gd",
	"res://tests/test_perf.gd",
	"res://tests/test_soak.gd",
]

## Opt-in only: suites whose assertions are wall-clock timings. A shared CI
## runner is a noisy neighbour, so these fail for reasons unrelated to the
## commit, and a gate that reddens at random stops being read. Excluded from the
## default full run; still runnable (and run by CI's advisory `perf` job) via
## SUITE=perf.
const OPT_IN_SUITES: Array[String] = [
	"res://tests/test_perf.gd",
]


## ENGINE-ERROR GATE.
##
## Godot's own `ERROR:` lines never fail anything: they aren't assertions, and CI only greps for
## `SCRIPT ERROR`. The suite was printing ~400 of them per run while reporting PASS. That matters
## because an engine error is often the ONLY evidence of a silently-green bug — a stub missing a
## field the view reads logs "Invalid access to property or key" and abandons the rest of the call,
## so the row under test measures as absent and every assertion still passes (see the c4-18 note on
## test_menu_layout.gd's _StubMain).
##
## GDScript can't intercept the engine's error stream, so the runner reads its OWN log back instead
## — hence debug/file_logging in project.godot. The run tags its log with a unique marker so a
## concurrent Godot on the same project (parallel worktrees) can't hand us someone else's file.
const LOG_DIR := "user://logs"

## Engine ERROR substrings that are ALLOWED, each with the reason it can't be fixed at the cause.
## Keep this SHORT — every entry is a class of real failure the suite can no longer see. Adding one
## needs a justification here, not just a red run.
##
## (Empty on purpose: as of the gate landing, all three historical clusters were fixed at the cause
## — the headless DisplayServer keyboard-layout call in menu.gd, the null-default ConfigFile reads
## in test_menu_layout.gd, and the un-seamed HUD draws that the capture stubs couldn't intercept.
## "N resources still in use at exit" is emitted AFTER quit(), so it never reaches this gate.)
const ERROR_ALLOW: Array[String] = []


class T:
	static var failures: Array[String] = []
	static var checks := 0

	static func ok(cond: bool, msg: String) -> void:
		checks += 1
		if not cond:
			failures.append(msg)
			push_error("FAIL: " + msg)

	static func eq(a, b, msg: String) -> void:
		ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])


func _init() -> void:
	# printerr (not print) so the logger flushes it: the marker must be on disk before the first
	# engine error, and only error-class writes are flushed immediately.
	var marker := "engine-error-gate-marker-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	printerr(marker)
	var suite_filter := OS.get_environment("SUITE")
	var scripts: Array[String] = TEST_SCRIPTS.filter(
		func(p: String) -> bool:
			if suite_filter.is_empty():
				return not OPT_IN_SUITES.has(p)
			return p.contains(suite_filter))
	var total_methods := 0
	for path in scripts:
		var script: GDScript = load(path)
		var suite: RefCounted = script.new()
		for m in suite.get_method_list():
			if m["name"].begins_with("test_"):
				total_methods += 1
				print("  • %s :: %s" % [path.get_file(), m["name"]])
				suite.call(m["name"])
	_gate_engine_errors(marker)
	print("")
	if T.failures.is_empty():
		print("PASS — %d test methods, %d assertions, 0 failures" % [total_methods, T.checks])
		quit(0)
	else:
		print("FAIL — %d of %d assertions failed:" % [T.failures.size(), T.checks])
		for f in T.failures:
			print("   ✗ " + f)
		quit(1)


## Fail the run for every un-allowlisted engine `ERROR:` line this process logged. Fails CLOSED:
## if the log can't be found the gate itself is the failure, so it can never silently stop running.
func _gate_engine_errors(marker: String) -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		T.ok(false, "engine-error gate: %s is missing — is debug/file_logging enabled in project.godot?" % LOG_DIR)
		return
	for file_name in dir.get_files():
		var text := FileAccess.get_file_as_string(LOG_DIR.path_join(file_name))
		if not text.contains(marker):
			continue   # another process's log (rotation renames ours out from under the path)
		for line in text.split("\n"):
			if not line.begins_with("ERROR:"):
				continue
			if line.begins_with("ERROR: FAIL: "):
				continue   # T.ok's own push_error — already counted as an assertion failure
			var allowed := false
			for a in ERROR_ALLOW:
				if line.contains(a):
					allowed = true
					break
			if not allowed:
				T.ok(false, "engine error logged during the run (nothing else fails on these): " + line)
		return
	T.ok(false, "engine-error gate: no log in %s carried this run's marker — the gate did not run" % LOG_DIR)
