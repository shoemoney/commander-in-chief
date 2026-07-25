extends RefCounted
## Edge/robustness paths: replay-file trust boundary, the checksum/events
## decoupling seam, and infinite-spawn + roll-invincibility grammar.

const Runner := preload("res://tests/run_tests.gd")


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


func test_replay_load_rejects_corrupt_input() -> void:
	var bad_magic := "user://tmp_test_bad_magic.json"
	_write_json(bad_magic, {"magic": "NOT_IKARI", "seed": 0, "mode": "campaign",
		"players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(bad_magic) == null, "wrong magic header rejected")

	var missing_frames := "user://tmp_test_missing_frames.json"
	_write_json(missing_frames, {"magic": Replay.MAGIC, "seed": 0, "mode": "campaign",
		"players": 1})
	Runner.T.ok(Replay.load_from(missing_frames) == null, "missing 'frames' field rejected")

	var bad_frames_type := "user://tmp_test_bad_frames_type.json"
	_write_json(bad_frames_type, {"magic": Replay.MAGIC, "seed": 0, "mode": "campaign",
		"players": 1, "frames": "nope"})
	Runner.T.ok(Replay.load_from(bad_frames_type) == null, "non-array 'frames' field rejected")

	var not_a_dict := "user://tmp_test_not_a_dict.json"
	var f := FileAccess.open(not_a_dict, FileAccess.WRITE)
	f.store_string(JSON.stringify(["just", "an", "array"]))
	f.close()
	Runner.T.ok(Replay.load_from(not_a_dict) == null, "non-dictionary top-level JSON rejected")


func test_replay_load_rejects_version_mismatch() -> void:
	# Replay has no separate format_version field — MAGIC itself encodes the
	# format version (bumped to a new string on a breaking change). A file
	# stamped with a different version's magic, or with no magic at all,
	# must be rejected the same as a fully bogus file.
	var future := "user://tmp_test_future_version.json"
	_write_json(future, {"magic": "IKARI_REPLAY_2", "seed": 0, "mode": "campaign",
		"players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(future) == null, "mismatched format-version magic rejected")

	var no_magic := "user://tmp_test_no_magic.json"
	_write_json(no_magic, {"seed": 0, "mode": "campaign", "players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(no_magic) == null, "missing magic key entirely rejected")


func test_checksum_excludes_events_but_hashes_state() -> void:
	var sim := SimWorld.new(7, 1)
	var before := sim.checksum()
	sim.events.append({"t": "test_event", "x": 0, "y": 0})
	Runner.T.eq(sim.checksum(), before,
		"appending to events[] does not change checksum (view-only seam, checksum-excluded)")
	sim.war_chest += 50
	Runner.T.ok(sim.checksum() != before,
		"mutating a hashed field (war_chest) changes checksum")


func test_bunker_infinite_spawn_and_seal() -> void:
	var sim := SimWorld.new(4, 1)
	var bunker := {"x": 300 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true, "spawn_cd": 1}
	sim.bunkers.clear()
	sim.bunkers.append(bunker)
	sim.enemies.clear()
	var before: int = sim.enemies.size()

	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 1, "bunker spawned infantry once its cooldown hit 0")
	Runner.T.eq(bunker["spawn_cd"], SimWorld.BUNKER_SPAWN_INTERVAL_TICKS,
		"spawn_cd reset to the full interval after spawning")

	for i in SimWorld.BUNKER_SPAWN_INTERVAL_TICKS - 1:
		sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 1, "no new spawn before the interval elapses again")
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 2,
		"bunker spawns again once the interval elapses — the 1986 infinite-spawn grammar")

	# Seal it: destroy the bunker, spawning stops even across many more intervals.
	bunker["alive"] = false
	for i in SimWorld.BUNKER_SPAWN_INTERVAL_TICKS * 3:
		sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 2, "a destroyed bunker never spawns again")


func test_passed_by_bunker_stops_spawning_and_is_pruned() -> void:
	## Budget leak: `bunkers` was never removed from and _step_bunkers had no
	## on-screen gate, so every passed-but-unsealed bunker kept spawning infantry
	## behind the camera — rushers that eat the shared MAX_ENEMIES budget and get
	## culled the next tick, starving the real front-line spawner on deep runs.
	var sim := SimWorld.new(4, 1)
	sim.bunkers.clear()
	sim.enemies.clear()
	var behind := {"x": 300 * Fixed.ONE, "y": sim.camera_top + 500 * Fixed.ONE,
		"alive": true, "spawn_cd": 1}
	sim.bunkers.append(behind)
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), 0, "a bunker below the live band spawns nothing")
	Runner.T.ok(sim.bunkers.is_empty(), "and is swept out of the array")

	# Band edge: the sweep uses the same +420 test as the enemy cull, so a bunker
	# still on screen keeps its 1986 infinite spawn.
	var edge := {"x": 300 * Fixed.ONE, "y": sim.camera_top + 420 * Fixed.ONE,
		"alive": true, "spawn_cd": 1}
	sim.bunkers.append(edge)
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), 1, "a bunker inside the band still spawns")
	Runner.T.eq(sim.bunkers.size(), 1, "and survives the sweep")


func test_mine_roll_safety() -> void:
	var sim := SimWorld.new(9, 1)
	var p := sim.players[0]
	p["roll_ticks"] = 5
	p["roll_iframe"] = true   # mid-roll i-frame guard now keys off this, not roll_ticks
	var mine := {"x": p["x"], "y": p["y"], "armed": true}
	sim.mines.clear()
	sim.mines.append(mine)

	sim._step_mines()
	Runner.T.ok(p["alive"], "a rolling player survives standing directly on an armed mine")
	Runner.T.ok(mine["armed"], "mine stays armed — the roll dodges the trigger, doesn't disarm it")
	Runner.T.eq(sim.mines.size(), 1, "mine is not removed (still armed, within despawn range)")
