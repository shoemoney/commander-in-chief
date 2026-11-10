extends RefCounted
## FAIRNESS package: places where the simulation broke a promise it makes to the player.
## Each test was written to fail on the unmodified code for the stated reason.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")   # no class_name; same alias test_main.gd uses


func _idle() -> SimInput:
	return SimInput.new()


# --- 1. Rifleman telegraph ------------------------------------------------------------

func test_rifleman_tell_lasts_the_reaction_floor_before_the_round_leaves() -> void:
	## Measured, not read from a constant: count ticks from the windup event to the
	## enemy bullet actually appearing.
	var sim := SimWorld.new(17, 1, "campaign")
	sim.camera_top = 0
	sim.enemies.clear()
	sim.pickups.clear()
	sim.rocks.clear()
	var p := sim.players[0]
	p["x"] = 320 * Fixed.ONE
	p["y"] = 260 * Fixed.ONE
	var g := {"x": p["x"], "y": p["y"] - 100 * Fixed.ONE, "alive": true, "elite": false,
		"kind": "rusher", "skin": 1, "fire_cd": 0, "windup": 0}
	sim.enemies.append(g)
	var armed_at := -1
	var fired_at := -1
	for t in 400:
		g["x"] = p["x"]
		g["y"] = p["y"] - 100 * Fixed.ONE   # hold the gunman at his standoff
		sim.step([_idle()])
		if armed_at < 0 and g["windup"] > 0:
			armed_at = t
		if armed_at >= 0 and not sim.enemy_bullets.is_empty():
			fired_at = t
			break
		if not p["alive"]:
			break
	Runner.T.ok(armed_at >= 0 and fired_at > armed_at, "the gunman telegraphed then fired")
	Runner.T.ok(fired_at - armed_at >= 24,
		"the rifleman's tell lasts at least the 24-tick reaction floor (%d ticks)" % (fired_at - armed_at))


# --- 2. Riot shield flank -------------------------------------------------------------

func _circle_trial(range_px: int, start_deg: int, dir: int) -> int:
	## Player circles the shield at run speed at a held radius. First tick a shot would
	## be unblocked, or -1.
	var sim := SimWorld.new(1, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var p: Dictionary = sim.players[0]
	var ex := 320 * Fixed.ONE
	var ey := -400 * Fixed.ONE
	var a := deg_to_rad(float(start_deg))
	p["x"] = ex + int(cos(a) * range_px * Fixed.ONE)
	p["y"] = ey + int(sin(a) * range_px * Fixed.ONE)
	sim._spawn_special(ex, ey, "shield")
	var e: Dictionary = sim.enemies[0]
	var spd := float(SimWorld.PLAYER_SPEED) / Fixed.ONE
	var sh := float(SimWorld.SHIELD_SPEED) / Fixed.ONE
	var dth := sqrt(spd * spd - sh * sh) / float(range_px) * float(dir)
	var ang := a
	for t in 400:
		sim._step_enemies()
		ang += dth
		p["x"] = e["x"] + int(cos(ang) * range_px * Fixed.ONE)
		p["y"] = e["y"] + int(sin(ang) * range_px * Fixed.ONE)
		if not sim._shield_blocks(e, {"vx": e["x"] - p["x"], "vy": e["y"] - p["y"]}):
			return t
	return -1


func test_a_deliberate_solo_circle_earns_the_shield_flank_at_real_range() -> void:
	## The banner says FLANK OR BLOW IT OPEN. A player running a circle at 90/120/150 px
	## must get an unblocked round in; at 1/32 rad/tick this was 0 of 16 at those ranges.
	for r in [90, 120, 150]:
		var ok := 0
		for s in [0, 90, 180, 270]:
			for d in [1, -1]:
				if _circle_trial(r, s, d) >= 0:
					ok += 1
		Runner.T.eq(ok, 8, "circling at %d px opens the rear arc in 8 of 8 trials" % r)


func test_a_player_who_stands_and_shoots_never_gets_past_the_shield() -> void:
	var sim := SimWorld.new(1, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var p: Dictionary = sim.players[0]
	p["x"] = 320 * Fixed.ONE
	p["y"] = -300 * Fixed.ONE
	sim._spawn_special(320 * Fixed.ONE, -450 * Fixed.ONE, "shield")
	var e: Dictionary = sim.enemies[0]
	var open := 0
	for t in 120:
		sim._step_enemies()
		if not sim._shield_blocks(e, {"vx": e["x"] - p["x"], "vy": e["y"] - p["y"]}):
			open += 1
	Runner.T.eq(open, 0, "a frontal shot is blocked on every tick of a straight approach")


func test_shield_safe_arc_drawn_matches_the_arc_the_sim_leaves_open() -> void:
	## View honesty: sweep shooter bearings around a shield facing +X; a round gets
	## through exactly when the bearing lies inside the drawn rear SAFE arc.
	var sim := SimWorld.new(1, 1)
	var half := Main.shield_safe_half_angle()
	var e := {"x": 0, "y": 0, "face_x": Fixed.ONE, "face_y": 0}
	var mismatches := 0
	var open := 0
	for deg in range(0, 360, 3):
		var th := deg_to_rad(float(deg))
		var bearing_off_rear: float = absf(wrapf(th - PI, -PI, PI))
		var drawn_safe := bearing_off_rear < half - 0.03
		var drawn_front := bearing_off_rear > half + 0.03
		var shot := {"vx": -int(cos(th) * Fixed.ONE), "vy": -int(sin(th) * Fixed.ONE)}
		var blocked := sim._shield_blocks(e, shot)
		if not blocked:
			open += 1
		if (drawn_safe and blocked) or (drawn_front and not blocked):
			mismatches += 1
	Runner.T.eq(mismatches, 0, "the green arc and the real open arc agree at every 3 degrees")
	Runner.T.ok(open > 30, "the sweep actually saw open bearings (%d)" % open)


# --- 3. Rooted guns never spawn behind the player ------------------------------------

func test_rooted_spawn_rows_are_never_south_of_the_front_most_living_player() -> void:
	var bad := 0
	var checked := 0
	for prow in [60, 100, 160, 220, 300]:
		var sim := SimWorld.new(7, 2)
		sim.players[0]["y"] = sim.camera_top + prow * Fixed.ONE
		sim.players[1]["y"] = sim.camera_top + (prow + 40) * Fixed.ONE
		for px in range(24, 617, 4):
			sim.tick_count += 1
			var ry: int = sim._rooted_spawn_y(px * Fixed.ONE)
			checked += 1
			if ry > sim.players[0]["y"]:
				bad += 1
	Runner.T.ok(checked > 500, "swept %d spawn draws" % checked)
	Runner.T.eq(bad, 0, "no rooted spawn lands south of the northernmost living player")


func test_a_dead_player_does_not_pin_the_rooted_spawn_row() -> void:
	var sim := SimWorld.new(7, 2)
	sim.players[0]["alive"] = false
	sim.players[0]["y"] = sim.camera_top + 20 * Fixed.ONE
	sim.players[1]["y"] = sim.camera_top + 300 * Fixed.ONE
	var rows := {}
	for px in range(24, 617, 4):
		sim.tick_count += 1
		rows[(sim._rooted_spawn_y(px * Fixed.ONE) - sim.camera_top) / Fixed.ONE] = 1
	Runner.T.ok(rows.size() >= 20, "the draw still spreads over many rows (%d)" % rows.size())


# --- 4. Tank cook-off ---------------------------------------------------------------

func _burning_tank(sim: SimWorld) -> Dictionary:
	var p: Dictionary = sim.players[0]
	var tank := {"x": p["x"], "y": p["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": -1}
	sim.tanks.append(tank)
	sim._ignite_tank(tank)
	return tank


func test_cook_off_hurts_a_player_left_standing_on_the_hull() -> void:
	var sim := SimWorld.new(3, 1)
	var p: Dictionary = sim.players[0]
	var tank := _burning_tank(sim)
	p["vest"] = false
	for i in SimWorld.TANK_BAIL_TICKS + 2:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "the burning tank detonated")
	Runner.T.ok(not p["alive"], "a player who never left the blast radius is killed, as BAIL OUT! says")


func test_cook_off_costs_a_vest_not_a_life_when_one_is_worn() -> void:
	var sim := SimWorld.new(3, 1)
	var p: Dictionary = sim.players[0]
	_burning_tank(sim)
	p["vest"] = true
	for i in SimWorld.TANK_BAIL_TICKS + 2:
		sim.step([_idle()])
	Runner.T.ok(p["alive"] and not p["vest"], "the vest eats the cook-off hit, same as a barrel")


func test_a_player_who_bails_and_runs_is_safe() -> void:
	var sim := SimWorld.new(3, 1)
	var p: Dictionary = sim.players[0]
	var tank := {"x": p["x"], "y": p["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": -1}
	sim.tanks.append(tank)
	var board := SimInput.new()
	board.interact = true
	sim.step([board])
	Runner.T.eq(p["in_tank"], 0, "boarded")
	p["vest"] = false
	sim._ignite_tank(tank)
	sim.step([_idle()])
	sim.step([board])   # bail
	Runner.T.eq(p["in_tank"], -1, "bailed")
	var run := SimInput.new()
	run.move_y = 256
	for i in 40:
		sim.step([run])
	for i in SimWorld.TANK_BAIL_TICKS:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "the hull cooked off")
	Runner.T.ok(p["alive"], "the player who bailed in time and ran lives")


# --- 5. Trench camping --------------------------------------------------------------

func _trench_spot(sim: SimWorld) -> Vector2i:
	for y in range(-9000, -3000, 8):
		for x in range(100, 560, 8):
			if sim._in_trench(x * Fixed.ONE, y * Fixed.ONE) and not sim._in_grass({"x": x * Fixed.ONE, "y": y * Fixed.ONE}):
				return Vector2i(x, y)
	return Vector2i(0, 0)


func test_camping_a_trench_with_an_enemy_near_draws_the_flush_grenade() -> void:
	var sim := SimWorld.new(5, 1)
	sim.enemies.clear()
	sim.rocks.clear()
	var spot := _trench_spot(sim)
	Runner.T.ok(spot != Vector2i(0, 0), "found a trench tile to stand in")
	var p: Dictionary = sim.players[0]
	p["x"] = spot.x * Fixed.ONE
	p["y"] = spot.y * Fixed.ONE
	Runner.T.ok(sim._concealed(p), "the trench conceals (the premise)")
	sim.enemies.append({"x": p["x"], "y": p["y"] - 60 * Fixed.ONE, "alive": true, "elite": false,
		"kind": "rusher", "skin": 1, "fire_cd": 99999, "windup": 0})
	sim.strikes.clear()
	for i in SimWorld.FLUSH_CD_TICKS + 2:
		sim._step_grass_flush()
	Runner.T.ok(sim.strikes.size() >= 1, "a flush strike was lobbed onto the trench camper")


func test_a_trench_with_no_enemy_nearby_is_never_flushed() -> void:
	var sim := SimWorld.new(5, 1)
	sim.enemies.clear()
	var spot := _trench_spot(sim)
	var p: Dictionary = sim.players[0]
	p["x"] = spot.x * Fixed.ONE
	p["y"] = spot.y * Fixed.ONE
	sim.strikes.clear()
	for i in SimWorld.FLUSH_CD_TICKS * 2:
		sim._step_grass_flush()
	Runner.T.eq(sim.strikes.size(), 0, "cover is still free when nobody is near")
