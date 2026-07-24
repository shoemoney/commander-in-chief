extends RefCounted
## The Mortar Observer — the pacing whip. Stall and he appears; stall longer
## and shells track you; kill him or push forward and the pressure lifts.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _stall_until_observer(sim: SimWorld) -> void:
	var guard := SimWorld.OBSERVER_STALL_TICKS + 10
	while sim.observer.is_empty() and guard > 0:
		sim.step([_idle()])
		guard -= 1


func test_observer_spawns_on_stall() -> void:
	var sim := SimWorld.new(11, 1)
	# Clear field pressure so the idle player isn't killed before the stall
	# threshold (enemy contact death would reset nothing — but a corpse can't
	# stall). Kill switch: park the player in a fresh tank; contact-immune.
	var tank := {"x": sim.players[0]["x"], "y": sim.players[0]["y"], "alive": true,
		"burning": false, "fuel": 1 << 40, "fire_cd": 0, "burn_ticks": 0, "occupant": -1}
	sim.tanks.append(tank)
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.ok(sim.players[0]["in_tank"] >= 0, "player parked in tank for the stall")
	_stall_until_observer(sim)
	Runner.T.ok(not sim.observer.is_empty(), "observer spawned after sustained stall")
	Runner.T.ok(sim.stall_ticks >= SimWorld.OBSERVER_STALL_TICKS, "stall counter reached threshold")


func test_strike_tracks_and_kills_staller() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.enemies.clear()
	# Force the observer directly; stand still and take the hit.
	sim.observer = {"x": p["x"], "strike_cd": 1, "spawn_cam": sim.camera_top}
	sim.step([_idle()])
	Runner.T.eq(sim.strikes.size(), 1, "strike called on the staller")
	for i in SimWorld.STRIKE_TELEGRAPH_TICKS + 1:
		sim.step([_idle()])
		if not p["alive"]:
			break
	Runner.T.ok(not p["alive"], "standing in the telegraph is death")


func test_roll_iframes_survive_strike() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.observer = {"x": p["x"], "strike_cd": 999999, "spawn_cam": sim.camera_top}
	# Strike landing this tick, player mid-roll.
	sim.strikes.append({"x": p["x"], "y": p["y"], "ticks": 1})
	var roll := SimInput.new()
	roll.roll = true
	roll.move_x = 256
	sim.step([roll])
	Runner.T.ok(p["roll_ticks"] > 0, "roll triggered")
	Runner.T.ok(p["alive"], "i-frames beat the mortar strike")


func test_kill_observer_cancels_only_his_strikes() -> void:
	# Design-loop iter1: strikes[] is shared by the observer, grenadiers, drones
	# and boss volleys — killing the spotter must defuse ONLY the obs-tagged
	# barrage, not hand out a free field-wide defuse of everyone else's shots.
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.observer = {"x": p["x"], "strike_cd": 999999, "spawn_cam": sim.camera_top}
	sim._add_strike(p["x"] + 100 * Fixed.ONE, p["y"], true)    # the observer's own
	sim._add_strike(p["x"] - 100 * Fixed.ONE, p["y"])          # a grenadier's lob
	sim.stall_ticks = 400
	var chest_before := sim.war_chest
	sim._kill_observer()
	Runner.T.ok(sim.observer.is_empty(), "observer down")
	Runner.T.eq(sim.strikes.size(), 1, "observer strikes cancelled, the grenadier's lob still falls")
	Runner.T.ok(not sim.strikes[0].get("obs", false), "the surviving strike is the non-observer one")
	# Downing the spotter now HALVES the stall clock instead of zeroing it — the
	# anti-camp valve must not fully re-arm the window it exists to punish.
	Runner.T.eq(sim.stall_ticks, SimWorld.OBSERVER_STALL_TICKS / 2,
		"stall pressure halved, not fully reset")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_ELITE * 2, "observer bounty minted")


func test_strike_ignites_tank_not_infantry() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	var tank := {"x": p["x"] + 200 * Fixed.ONE, "y": p["y"], "alive": true,
		"burning": false, "fuel": 100, "fire_cd": 0, "burn_ticks": 0, "occupant": -1}
	sim.tanks.append(tank)
	sim._spawn_enemy(tank["x"], tank["y"], false)
	sim.strikes.append({"x": tank["x"], "y": tank["y"], "ticks": 1})
	sim.step([_idle()])
	Runner.T.ok(tank["burning"], "mortar strike ignites armor")
	var enemy_alive := false
	for e in sim.enemies:
		if e["alive"]:
			enemy_alive = true
	Runner.T.ok(enemy_alive, "mortar fire is harmless to enemy infantry")
