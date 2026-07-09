extends RefCounted
## Water grammar: wading is slow, rolls are dry-land only, armor stays out,
## and submerged frogmen answer only to grenades.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _add_water_under_player(sim: SimWorld) -> Dictionary:
	# Band covering the player's row; ford far away on the right edge.
	var w := {"y": sim.players[0]["y"] - 40 * Fixed.ONE, "ford_x": 600 * Fixed.ONE}
	sim.waters.append(w)
	return w


func test_wading_halves_speed() -> void:
	var dry := SimWorld.new(31, 1)
	var wet := SimWorld.new(31, 1)
	_add_water_under_player(wet)
	Runner.T.ok(wet._in_water(wet.players[0]["x"], wet.players[0]["y"]), "player starts in the band")
	var left := SimInput.new()
	left.move_x = -256
	for i in 10:
		dry.step([left])
		wet.step([left])
	var dry_dist: int = (280 * Fixed.ONE) - dry.players[0]["x"]
	var wet_dist: int = (280 * Fixed.ONE) - wet.players[0]["x"]
	Runner.T.eq(wet_dist * 2, dry_dist, "water exactly halves walk speed")


func test_ford_is_dry() -> void:
	var sim := SimWorld.new(31, 1)
	var w := _add_water_under_player(sim)
	Runner.T.ok(not sim._in_water(w["ford_x"], sim.players[0]["y"]), "the ford gap is dry land")


func test_no_rolling_in_water() -> void:
	var sim := SimWorld.new(31, 1)
	_add_water_under_player(sim)
	var roll := SimInput.new()
	roll.roll = true
	roll.move_x = 256
	sim.step([roll])
	Runner.T.eq(sim.players[0]["roll_ticks"], 0, "roll refused while wading")


func test_tank_walled_out_of_water() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	# Water strip just north of the tank.
	sim.waters.append({"y": p["y"] - 120 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	var tank := {"x": p["x"], "y": p["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": -1}
	sim.tanks.append(tank)
	var board := SimInput.new()
	board.interact = true
	sim.step([board])
	Runner.T.ok(p["in_tank"] >= 0, "boarded")
	var up := SimInput.new()
	up.move_y = -256
	for i in 60:
		sim.step([up])
	Runner.T.ok(not sim._in_water(tank["x"], tank["y"]), "tank never entered the water")
	Runner.T.ok(tank["y"] >= p["y"] - 120 * Fixed.ONE - SimWorld.WATER_H, "tank held at the bank")


func test_frogman_submerged_immune_to_bullets_grenades_kill() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	sim.waters.append({"y": p["y"] - 200 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	sim._spawn_frogman(p["x"], p["y"] - 170 * Fixed.ONE)   # outside notice radius
	var frog := sim.enemies[sim.enemies.size() - 1]
	# Hose it with bullets: passes clean over.
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	for i in 60:
		sim.step([fire])
	Runner.T.ok(frog["alive"] and frog["submerged"], "bullets pass over the submerged frogman")
	# One grenade: gone. (Lob range ~96 px; walk close enough first.)
	p["y"] = frog["y"] + 80 * Fixed.ONE
	var toss := SimInput.new()
	toss.aim_y = -256
	toss.grenade = true
	for i in 60:
		sim.step([toss if i == 0 else _idle()])
		if not frog["alive"]:
			break
	Runner.T.ok(not frog["alive"], "grenade kills the submerged frogman")


func test_frogman_surfaces_and_is_shootable() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	sim.waters.append({"y": p["y"] - 60 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	sim._spawn_frogman(p["x"], p["y"] - 40 * Fixed.ONE)   # inside notice radius
	var frog := sim.enemies[sim.enemies.size() - 1]
	sim.step([_idle()])
	Runner.T.ok(not frog["submerged"], "frogman surfaced to lunge")
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	for i in 20:
		sim.step([fire])
		if not frog["alive"]:
			break
	Runner.T.ok(not frog["alive"], "surfaced frogman is bullet-vulnerable")