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
