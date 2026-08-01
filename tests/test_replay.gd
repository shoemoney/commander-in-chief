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
	var bad := {"magic": Replay.MAGIC, "ruleset": Replay.CURRENT_RULESET_VERSION,
		"seed": 1, "mode": "campaign", "players": 1,
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


func test_decode_clamps_hostile_axes_and_survives_short_payload() -> void:
	## SimInput.decode is a trust boundary — it eats bytes from a remote lockstep peer
	## and from replay files people mail in with bug reports. Unclamped axes reach
	## `inp.move_x * 256` -> Fixed.length, which overflows int64 past ~2^24, and a short
	## payload used to index data[4] and throw mid-sim.step(). Neither desyncs (both
	## peers consume the same bytes), so nothing downstream would ever notice.
	var wild := SimInput.decode([1 << 40, -(1 << 40), 999999, -999999, 0])
	Runner.T.eq(wild.move_x, SimInput.AXIS_MAX, "huge move_x clamped to AXIS_MAX")
	Runner.T.eq(wild.move_y, -SimInput.AXIS_MAX, "huge negative move_y clamped")
	Runner.T.eq(wild.aim_x, SimInput.AXIS_MAX, "huge aim_x clamped")
	Runner.T.eq(wild.aim_y, -SimInput.AXIS_MAX, "huge negative aim_y clamped")
	var short := SimInput.decode([1, 2])
	Runner.T.eq(short.move_x, 0, "short payload yields neutral input, not a crash")
	Runner.T.eq(short.buy, 0, "short payload presses nothing")
	# In-range values still round-trip exactly.
	var ok_in := SimInput.new()
	ok_in.move_x = 256
	ok_in.move_y = -128
	ok_in.aim_x = -256
	ok_in.aim_y = 7
	ok_in.fire = true
	ok_in.buy = 5
	var rt := SimInput.decode(ok_in.encode())
	Runner.T.eq(rt.move_x, 256, "in-range move_x survives")
	Runner.T.eq(rt.move_y, -128, "in-range move_y survives")
	Runner.T.eq(rt.aim_x, -256, "in-range aim_x survives")
	Runner.T.ok(rt.fire and rt.buy == 5, "flags and buy survive the clamp path")


func test_grenade_and_revive_bits_are_independent_on_replay_wire() -> void:
	# These actions once shared a physical key, but they are distinct protocol
	# bits. Prove every combination so a future mask edit cannot couple them.
	for case in [
		{"grenade": true, "revive": false, "name": "grenade only"},
		{"grenade": false, "revive": true, "name": "revive only"},
		{"grenade": true, "revive": true, "name": "grenade and revive"},
	]:
		var inp := SimInput.new()
		inp.grenade = case["grenade"]
		inp.revive = case["revive"]
		var decoded := SimInput.decode(inp.encode())
		Runner.T.eq(decoded.grenade, case["grenade"], "%s preserves grenade bit" % case["name"])
		Runner.T.eq(decoded.revive, case["revive"], "%s preserves revive bit" % case["name"])


func _repair_scenario_fixture(sim: SimWorld) -> Dictionary:
	## A compact deterministic battlefield containing all three repaired state
	## families. The fixture itself is rebuilt on both sides; only player input
	## crosses the replay wire below.
	sim.enemies.clear()
	sim.tanks.clear()
	sim.sandbags.clear()
	var y: int = sim.camera_top + 220 * SimWorld.F_ONE
	var driver := sim.players[0]
	var builder := sim.players[1]
	driver["x"] = 100 * SimWorld.F_ONE
	driver["y"] = y
	builder["x"] = 520 * SimWorld.F_ONE
	builder["y"] = y
	builder["aim_x"] = SimWorld.F_ONE
	builder["aim_y"] = 0
	# Creation derives a rightward facing from the then-nearest builder.
	sim._spawn_special(320 * SimWorld.F_ONE, y, "shield")
	var initial_face_x: int = sim.enemies[0]["face_x"]
	# Move the builder behind the shield. Both players are now left of it, so
	# normal enemy stepping must turn the persistent plate instead of snapping.
	builder["x"] = 250 * SimWorld.F_ONE
	var tank := {
		"x": driver["x"], "y": driver["y"], "alive": true, "burning": true,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": SimWorld.TANK_BAIL_TICKS,
		"crew_ring_ticks": SimWorld.TANK_IGNITION_GRACE_TICKS,
		"fire_cd": 0, "occupant": 0,
	}
	sim.tanks.append(tank)
	driver["in_tank"] = 0
	return {"face_x": initial_face_x, "ring": tank["crew_ring_ticks"]}


func _play_repair_scenario(rep: Replay) -> Dictionary:
	var sim := SimWorld.new(rep.seed_value, rep.player_count, rep.mode)
	rep.apply_config(sim)
	var initial := _repair_scenario_fixture(sim)
	for frame in rep.frames:
		var inputs: Array = []
		for enc in frame:
			inputs.append(SimInput.decode(enc))
		sim.step(inputs)
	return {"sim": sim, "initial": initial}


func test_repaired_state_fields_each_move_checksum() -> void:
	# Direct state-delta sentinels: each new field must independently perturb the
	# hash, or replay/lockstep can agree while silently ignoring divergent rules.
	var shield_a := SimWorld.new(0xC1A217, 1)
	var shield_b := SimWorld.new(0xC1A217, 1)
	shield_a._spawn_special(320 * SimWorld.F_ONE, -200 * SimWorld.F_ONE, "shield")
	shield_b._spawn_special(320 * SimWorld.F_ONE, -200 * SimWorld.F_ONE, "shield")
	Runner.T.eq(shield_a.checksum(), shield_b.checksum(), "matching shield fixtures begin checksum-identical")
	shield_b.enemies[0]["face_x"] += 1
	Runner.T.ok(shield_a.checksum() != shield_b.checksum(), "shield face_x changes checksum")
	shield_b.enemies[0]["face_x"] = shield_a.enemies[0]["face_x"]
	shield_b.enemies[0]["face_y"] += 1
	Runner.T.ok(shield_a.checksum() != shield_b.checksum(), "shield face_y changes checksum")

	var tank_a := SimWorld.new(0xC1A217, 1)
	var tank_b := SimWorld.new(0xC1A217, 1)
	var hull := {"x": 100, "y": 200, "alive": true, "burning": true,
		"fuel": 300, "burn_ticks": 60, "crew_ring_ticks": 12, "fire_cd": 0, "occupant": 0}
	tank_a.tanks.append(hull.duplicate())
	tank_b.tanks.append(hull.duplicate())
	Runner.T.eq(tank_a.checksum(), tank_b.checksum(), "matching tank fixtures begin checksum-identical")
	tank_b.tanks[0]["crew_ring_ticks"] = 11
	Runner.T.ok(tank_a.checksum() != tank_b.checksum(), "tank crew_ring_ticks changes checksum")

	var bags_a := SimWorld.new(0xC1A217, 1)
	var bags_b := SimWorld.new(0xC1A217, 1)
	bags_a.sandbags.append({"x": 100, "y": 200, "player": 1, "vertical": 1})
	bags_b.sandbags.append({"x": 100, "y": 200, "player": 0, "vertical": 1})
	Runner.T.ok(bags_a.checksum() != bags_b.checksum(), "sandbag player ownership changes checksum")
	bags_b.sandbags[0]["player"] = 1
	bags_b.sandbags[0]["vertical"] = 0
	Runner.T.ok(bags_a.checksum() != bags_b.checksum(), "sandbag vertical orientation changes checksum")


func test_repaired_scenario_survives_same_ruleset_replay_roundtrip() -> void:
	var rep := Replay.new()
	rep.seed_value = 0x51A7E
	rep.mode = "campaign"
	rep.player_count = 2
	rep.start_chest = 100
	for tick in 16:
		var driver := SimInput.new()
		var builder := SimInput.new()
		if tick == 0:
			builder.buy = 5   # wheel slot 5 -> two-segment sandbag nest
		rep.record_tick([driver, builder])
	var live := _play_repair_scenario(rep)
	var live_sim: SimWorld = live["sim"]
	Runner.T.eq(live_sim.sandbags.size(), 2, "scenario bought one complete sandbag nest")
	Runner.T.ok(live_sim.sandbags.all(func(sb): return sb.get("player", 0) == 1 and sb.get("vertical", 0) == 1),
		"eastward wheel purchase created two player-owned vertical segments")
	Runner.T.ok(live_sim.enemies[0]["face_x"] != live["initial"]["face_x"],
		"scenario advanced the shield's capped turn")
	Runner.T.ok(live_sim.tanks[0]["crew_ring_ticks"] < live["initial"]["ring"]
		and live_sim.players[0]["in_tank"] == 0,
		"scenario advanced an occupied tank's ignition grace")

	var path := "user://tmp_repair_scenario_replay.json"
	Runner.T.eq(rep.save(path), OK, "repair scenario replay saved")
	var loaded := Replay.load_from(path)
	Runner.T.ok(loaded != null, "repair scenario replay loaded under the current ruleset")
	Runner.T.eq(loaded.to_dict()["ruleset"], Replay.CURRENT_RULESET_VERSION,
		"round-trip retained the shared current ruleset")
	var replayed := _play_repair_scenario(loaded)
	var replayed_sim: SimWorld = replayed["sim"]
	Runner.T.eq(replayed_sim.checksum(), live_sim.checksum(),
		"same-build replay reproduced the repaired scenario bit-for-bit")
	Runner.T.eq(replayed_sim.enemies[0]["face_x"], live_sim.enemies[0]["face_x"],
		"replay reproduced shield facing")
	Runner.T.eq(replayed_sim.tanks[0]["crew_ring_ticks"], live_sim.tanks[0]["crew_ring_ticks"],
		"replay reproduced the tank crew deadline")
	Runner.T.eq(replayed_sim.sandbags, live_sim.sandbags, "replay reproduced vertical player sandbags")
