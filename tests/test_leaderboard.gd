extends RefCounted
## Replay-validated leaderboards: the score attached to a saved replay must
## match what the deterministic sim actually produces when the recorded
## inputs are re-simulated from scratch -- the anti-cheat gate a Daily/Endless
## leaderboard submission has to clear. tools/validate_replay.gd runs this
## same check offline against a replay file submitted from elsewhere.
##
## Trust boundary (also documented in docs/PLAN.md "Leaderboard anti-cheat",
## and in src/main.gd _apply_score_verdict for anyone reading the gate itself):
## this catches score tampering (a hex-edited save, a memory-poked sim.score)
## because replaying the RECORDED INPUTS always recomputes the true score. It
## does NOT catch a crafted/bot-perfect input sequence, or one player replaying
## another player's legitimately-recorded inputs as their own -- closing that
## gap needs server-side replay storage with a per-account signed submission,
## which has no backend to attach to yet (see the item's "Likely files" scope:
## a standalone validator tool, not a netcode/account-system rewrite).

const Runner := preload("res://tests/run_tests.gd")
const Det := preload("res://tests/test_determinism.gd")
const MainScript := preload("res://src/main.gd")


func _recorded_run() -> Replay:
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
	return rep


func _cleanup(path: String) -> void:
	# GDScript has no try/finally -- called both BEFORE a test writes its fixture
	# (so a previous run that died mid-assertion never leaves a stale file behind
	# to confuse the next run) and AFTER (so a clean run doesn't litter user://).
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_genuine_replay_verifies() -> void:
	var rep := _recorded_run()
	Runner.T.ok(rep.verify_score(rep.claimed_score),
		"a genuine run's attached score verifies against its own replay")


func test_tampered_score_fails_verification() -> void:
	var rep := _recorded_run()
	var tampered := rep.claimed_score + 999999
	Runner.T.ok(not rep.verify_score(tampered),
		"a score bumped after the run does NOT verify -- the exploit this system exists to catch")


func test_score_round_trips_through_save_load() -> void:
	var rep := _recorded_run()
	var path := "user://tmp_test_leaderboard.json"
	_cleanup(path)
	Runner.T.eq(Replay.save_dict(rep.to_dict(), path), OK, "replay+score saved")
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null, "replay loaded back")
	Runner.T.eq(loaded.claimed_score, rep.claimed_score, "attached score survived the save/load round trip")
	Runner.T.ok(loaded.verify_score(rep.claimed_score), "loaded replay still verifies its own score")
	_cleanup(path)


func test_pre_existing_replay_defaults_score_zero() -> void:
	# Back-compat: a replay file saved before this system existed has no "score"
	# key. load_from must not crash, and must not silently claim a nonzero score.
	var path := "user://tmp_test_leaderboard_legacy.json"
	_cleanup(path)
	var legacy := {"magic": Replay.MAGIC, "seed": 1, "mode": "campaign", "players": 1, "frames": []}
	Runner.T.eq(Replay.save_dict(legacy, path), OK, "legacy (score-less) replay written")
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null, "legacy replay still loads")
	Runner.T.eq(loaded.claimed_score, 0, "missing score field defaults to 0, not a crash")
	_cleanup(path)


func test_validate_file_exit_codes() -> void:
	# The CLI decision logic (tools/validate_replay.gd) factored into a plain
	# static function so its 0/1/2 exit-code paths are unit-testable without
	# spawning a nested Godot process for every assertion.
	var rep := _recorded_run()

	var path_ok := "user://tmp_test_validate_ok.json"
	_cleanup(path_ok)
	Runner.T.eq(Replay.save_dict(rep.to_dict(), path_ok), OK, "genuine fixture saved")
	Runner.T.eq(Replay.validate_file(path_ok)["code"], 0, "validate_file: genuine replay -> exit 0 (VALID)")
	_cleanup(path_ok)

	Runner.T.eq(Replay.validate_file("user://tmp_test_validate_missing.json")["code"], 1,
		"validate_file: missing file -> exit 1 (can't even attempt verification)")

	var tampered := rep.to_dict()
	tampered["score"] = rep.claimed_score + 777
	var path_cheat := "user://tmp_test_validate_cheat.json"
	_cleanup(path_cheat)
	Runner.T.eq(Replay.save_dict(tampered, path_cheat), OK, "tampered fixture saved")
	var result := Replay.validate_file(path_cheat)
	Runner.T.eq(result["code"], 2, "validate_file: tampered score -> exit 2 (CHEAT DETECTED)")
	Runner.T.eq(result["actual"], rep.claimed_score, "validate_file reports the TRUE (replayed) score, not the claimed one")
	_cleanup(path_cheat)


func test_save_and_verify_flags_a_hex_edited_file() -> void:
	# Simulates the actual cheat vector: the JSON on disk claims a score the
	# recorded inputs never earned (a hand-edited save, or a poked sim.score
	# that got stamped into the snapshot). save_and_verify still writes the
	# file (it's advisory, not a write-blocker) but the score fails its own
	# replay check -- exactly what tools/validate_replay.gd catches offline,
	# and what main.gd's synchronous pre-check (_track_bests) now refuses to
	# bank into the Hall of Fame or upload to Steam in the first place.
	var rep := _recorded_run()
	var d := rep.to_dict()
	d["score"] = rep.claimed_score + 12345
	var path := "user://tmp_test_leaderboard_tampered.json"
	_cleanup(path)
	Runner.T.eq(Replay.save_and_verify(d, path), OK, "tampered file still saves to disk")
	var loaded := Replay.load_from(path)
	Runner.T.ok(not loaded.verify_score(loaded.claimed_score), "hex-edited on-disk score fails verification")
	Runner.T.ok(not loaded.verified, "save_and_verify corrected the on-disk 'verified' flag to false")
	_cleanup(path)


func test_save_and_verify_self_corrects_wrong_verified_flag() -> void:
	# The caller (main.gd) stamps "verified" from its OWN pre-write check --
	# save_and_verify must not blindly trust that flag. If it disagrees with
	# what the disk-read-back replay actually proves, the file gets corrected.
	var rep := _recorded_run()
	var d := rep.to_dict()
	d["verified"] = true   # a caller wrongly claiming this tampered run was clean
	d["score"] = rep.claimed_score + 42
	var path := "user://tmp_test_leaderboard_selfcorrect.json"
	_cleanup(path)
	Replay.save_and_verify(d, path)
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null and not loaded.verified,
		"a wrongly-true 'verified' flag gets corrected to false on disk once the replay disproves it")
	_cleanup(path)



# --- the actual main.gd GATE (not just Replay.verify_score()) -----------------
# _apply_score_verdict is the exact method _track_bests calls at the debrief
# transition (src/main.gd) -- extracted so it's overridable here. Subclassing
# the real main.gd script (rather than duck-typing a from-scratch stub, as
# test_menu_layout.gd's _StubMain does for the menu) means these tests exercise
# the REAL _apply_score_verdict body, not a parallel copy that could drift from
# it -- only _record_run()/show_banner() (the two side effects being gated) are
# overridden, so a passing test proves the actual gate, not a re-implementation
# of it. Never add_child'd, so Node2D._ready() never fires -- __init has no
# heavy setup either, so .new() alone is safe headless.

class _StubMainGate extends MainScript:
	var record_run_calls := 0
	var last_recorded_score := -1
	var banners: Array = []
	var banner_cols: Array = []
	func _record_run(score: int) -> void:
		record_run_calls += 1   # never touches sim/hall/Steam -- the gate is what's under test, not the bank itself
		last_recorded_score = score
	func show_banner(text: String, col := GameMenu.BANNER_COL_DEFAULT, _icon := "") -> void:
		banners.append(text)
		banner_cols.append(col)


func test_gate_banks_and_stays_silent_when_score_verifies() -> void:
	var stub := _StubMainGate.new()
	stub._apply_score_verdict(12345, true)
	Runner.T.eq(stub.record_run_calls, 1, "a verified score must bank exactly once (_record_run, which also uploads to Steam)")
	Runner.T.eq(stub.last_recorded_score, 12345, "_record_run receives the exact verified score as an explicit arg, not a re-read of live sim.score")
	Runner.T.ok(stub.banners.is_empty(), "a verified score must not raise the deny banner")
	stub.free()


func test_gate_suppresses_bank_and_shows_deny_banner_when_score_fails() -> void:
	var stub := _StubMainGate.new()
	stub._apply_score_verdict(99999, false)
	Runner.T.eq(stub.record_run_calls, 0, "a failed verification must NEVER bank into the Hall of Fame or upload to Steam")
	Runner.T.eq(stub.banners, ["SCORE NOT VERIFIED"], "a failed verification must show the deny banner")
	Runner.T.eq(stub.banner_cols, [GameMenu.BANNER_COL_FAIL], "the deny banner must carry the fail tint, not the default")
	stub.free()


func test_gate_wired_to_a_real_verify_score_call() -> void:
	# End-to-end through the SAME two calls _track_bests makes: compute
	# verified from a real Replay.verify_score(), then feed it straight into
	# the real gate -- proves the wiring, not just each half in isolation.
	var rep := _recorded_run()
	var stub := _StubMainGate.new()

	stub._apply_score_verdict(rep.claimed_score, rep.verify_score(rep.claimed_score))
	Runner.T.eq(stub.record_run_calls, 1, "genuine claimed score -> verify_score true -> gate banks")
	Runner.T.ok(stub.banners.is_empty(), "genuine claimed score -> no deny banner")

	var tampered_score := rep.claimed_score + 777
	stub._apply_score_verdict(tampered_score, rep.verify_score(tampered_score))
	Runner.T.eq(stub.record_run_calls, 1, "tampered score -> verify_score false -> gate must NOT bank a 2nd time")
	Runner.T.eq(stub.banners, ["SCORE NOT VERIFIED"], "tampered score -> gate shows the deny banner")
	stub.free()
