extends RefCounted
## The replay recorder must reproduce a live run bit-for-bit, and survive a
## save/load round-trip — the foundation for desync-repro + audited seeds.

const Runner := preload("res://tests/run_tests.gd")
const Det := preload("res://tests/test_determinism.gd")


func _live_run(sample_every: int) -> Array[int]:
	# A live run using the determinism torture script, recording as it goes.
	var rep := Replay.new()
	rep.seed_value = 0xABCDEF
	rep.mode = "campaign"
	rep.player_count = 2
	var sim := SimWorld.new(rep.seed_value, rep.player_count, rep.mode)
	var live: Array[int] = []
	for tick in 600:
		var inputs := [Det.scripted_input(tick, 0), Det.scripted_input(tick, 1)]
		rep.record_tick(inputs)
		sim.step(inputs)
		if (tick + 1) % sample_every == 0:
			live.append(sim.checksum())
	_last_replay = rep
	return live


var _last_replay: Replay


func test_replay_reproduces_live_run() -> void:
	var live := _live_run(100)
	var replayed := _last_replay.play(100)
	Runner.T.eq(replayed.size(), live.size(), "replay produced the same sample count")
	for i in live.size():
		Runner.T.eq(replayed[i], live[i], "replay checksum diverged from live at sample %d" % i)


func _live_run_cfg(sample_every: int, assist: bool, hard: bool) -> Array[int]:
	# Same torture run, but seeded with assist/hard config the way main.gd does.
	var rep := Replay.new()
	rep.seed_value = 0xABCDEF
	rep.mode = "campaign"
	rep.player_count = 2
	rep.assist = assist
	rep.hard = hard
	var sim := SimWorld.new(rep.seed_value, rep.player_count, rep.mode)
	sim.assist_mode = assist
	sim.hard = hard
	if assist:
		for pl in sim.players:
			pl["vest"] = true
	var live: Array[int] = []
	for tick in 600:
		var inputs := [Det.scripted_input(tick, 0), Det.scripted_input(tick, 1)]
		rep.record_tick(inputs)
		sim.step(inputs)
		if (tick + 1) % sample_every == 0:
			live.append(sim.checksum())
	_last_replay = rep
	return live


func test_replay_reproduces_assist_hard_run() -> void:
	# Regression: play() must restore assist_mode/hard/vest. Without it an ASSIST or NG+ HARD
	# run replays as a vanilla sim — both flags feed checksum() and hard diverts the RNG stream,
	# so the first sample already diverges. Also assert the config actually moves the checksum,
	# so this test can't pass vacuously.
	var live := _live_run_cfg(100, true, true)
	var replayed := _last_replay.play(100)
	Runner.T.eq(replayed.size(), live.size(), "assist+hard replay sample count")
	for i in live.size():
		Runner.T.eq(replayed[i], live[i], "assist+hard replay diverged at sample %d" % i)
	var vanilla := _live_run_cfg(100, false, false)
	Runner.T.ok(live != vanilla, "assist+hard run differs from vanilla (flags affect the sim)")


func test_replay_save_load_preserves_cfg() -> void:
	_live_run_cfg(100, true, true)
	var path := "user://tmp_test_replay_cfg.json"
	Runner.T.eq(_last_replay.save(path), OK, "cfg replay saved")
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null, "cfg replay loaded")
	Runner.T.ok(loaded.assist and loaded.hard, "assist+hard survived the save/load round-trip")
	var a := _last_replay.play(200)
	var b := loaded.play(200)
	Runner.T.eq(a, b, "loaded assist+hard replay reproduces the run")


func test_replay_load_rejects_malformed_frame() -> void:
	# Trust boundary: a well-typed but malformed frame (short encoded input) must be rejected
	# at load, not crash later in SimInput.decode.
	var path := "user://tmp_test_replay_bad.json"
	var bad := {"magic": Replay.MAGIC, "seed": 1, "mode": "campaign", "players": 1,
		"frames": [[[0, 0, 0]]]}   # 3-element enc, decode indexes [4]
	Runner.T.eq(Replay.save_dict(bad, path), OK, "bad replay written")
	Runner.T.ok(Replay.load_from(path) == null, "malformed-frame replay rejected at load")


func test_replay_save_load_roundtrip() -> void:
	_live_run(100)
	var path := "user://tmp_test_replay.json"
	Runner.T.eq(_last_replay.save(path), OK, "replay saved")
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null, "replay loaded back")
	Runner.T.eq(loaded.seed_value, _last_replay.seed_value, "seed survived round-trip")
	Runner.T.eq(loaded.frames.size(), _last_replay.frames.size(), "frame count survived")
	# The loaded replay reproduces the same run.
	var a := _last_replay.play(200)
	var b := loaded.play(200)
	Runner.T.eq(a, b, "loaded replay reproduces the original run")
