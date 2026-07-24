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
	"res://tests/test_robustness.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_main.gd",
	"res://tests/test_menu_layout.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_perf.gd",
	"res://tests/test_soak.gd",
]


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
	var suite_filter := OS.get_environment("SUITE")
	var scripts: Array[String] = TEST_SCRIPTS if suite_filter.is_empty() else \
		TEST_SCRIPTS.filter(func(p: String) -> bool: return p.contains(suite_filter))
	var total_methods := 0
	for path in scripts:
		var script: GDScript = load(path)
		var suite: RefCounted = script.new()
		for m in suite.get_method_list():
			if m["name"].begins_with("test_"):
				total_methods += 1
				print("  • %s :: %s" % [path.get_file(), m["name"]])
				suite.call(m["name"])
	print("")
	if T.failures.is_empty():
		print("PASS — %d test methods, %d assertions, 0 failures" % [total_methods, T.checks])
		quit(0)
	else:
		print("FAIL — %d of %d assertions failed:" % [T.failures.size(), T.checks])
		for f in T.failures:
			print("   ✗ " + f)
		quit(1)
