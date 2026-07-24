extends SceneTree
## replay-validated-leaderboards: end-to-end CLI smoke test for the REAL
## anti-cheat entry point, not just its decision logic. tests/test_leaderboard.gd
## unit-tests Replay.validate_file() directly; this script instead shells out to
## the actual `godot --headless -s res://tools/validate_replay.gd -- <path>`
## invocation a player/CI would run, so the arg-parsing (OS.get_cmdline_user_args)
## and quit(code) exit-status plumbing get exercised too, against a known-good
## AND a tampered replay, checking both documented exit codes end to end.
##
## Run:  godot --headless -s res://tools/smoke_validate_replay.gd
## Prints "SMOKE OK" and exits 0 on success; exits 1 with a printed reason on failure.

const Det := preload("res://tests/test_determinism.gd")

const OK_FILE := "smoke_validate_ok.replay"
const CHEAT_FILE := "smoke_validate_cheat.replay"


func _initialize() -> void:
	var godot_bin := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")

	var rep := Replay.new()
	rep.seed_value = 0x5EED
	rep.mode = "campaign"
	rep.player_count = 1
	var sim := SimWorld.new(rep.seed_value, rep.player_count, rep.mode)
	for tick in 300:
		var inputs := [Det.scripted_input(tick, 0)]
		rep.record_tick(inputs)
		sim.step(inputs)
	rep.claimed_score = sim.score

	Replay.save_dict(rep.to_dict(), "user://%s" % OK_FILE)
	var tampered := rep.to_dict()
	tampered["score"] = rep.claimed_score + 424242   # the exploit this whole system exists to catch
	Replay.save_dict(tampered, "user://%s" % CHEAT_FILE)

	var ok_path := ProjectSettings.globalize_path("user://%s" % OK_FILE)
	var cheat_path := ProjectSettings.globalize_path("user://%s" % CHEAT_FILE)
	var ok_code := _run_validator(godot_bin, project_path, ok_path)
	var cheat_code := _run_validator(godot_bin, project_path, cheat_path)

	DirAccess.remove_absolute(ok_path)
	DirAccess.remove_absolute(cheat_path)

	if ok_code != 0:
		printerr("SMOKE FAIL: genuine replay -> exit %d, expected 0 (VALID)" % ok_code)
		quit(1)
		return
	if cheat_code != 2:
		printerr("SMOKE FAIL: tampered replay -> exit %d, expected 2 (CHEAT DETECTED)" % cheat_code)
		quit(1)
		return
	print("SMOKE OK: tools/validate_replay.gd exit 0 (genuine) / exit 2 (tampered) confirmed end-to-end")
	quit(0)


func _run_validator(godot_bin: String, project_path: String, replay_path: String) -> int:
	var args := ["--headless", "--path", project_path, "-s", "res://tools/validate_replay.gd", "--", replay_path]
	return OS.execute(godot_bin, args, [], false)
