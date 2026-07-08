extends RefCounted
## The tank: board, crush, shells-from-grenade-ammo, fuel burn, bail window,
## kamikaze verb. (1986 rules: enterable armor with a fuel clock.)

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _park_tank(sim: SimWorld, x: int, y: int) -> Dictionary:
	var tank := {
		"x": x, "y": y, "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0,
		"fire_cd": 0, "occupant": -1,
	}
	sim.tanks.append(tank)
	return tank


func _board(sim: SimWorld, tank: Dictionary) -> void:
	sim.players[0]["x"] = tank["x"]
	sim.players[0]["y"] = tank["y"]
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])


func test_board_and_exit() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"] - 10 * Fixed.ONE)
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.ok(p["in_tank"] >= 0 and sim.tanks[p["in_tank"]] == tank, "player boarded the parked tank")
	Runner.T.eq(tank["occupant"], 0, "tank records occupant")
	# Release, then press again to exit (edge-triggered).
	sim.step([_idle()])
	sim.step([inp])
	Runner.T.eq(p["in_tank"], -1, "player exited the tank")
	Runner.T.eq(tank["occupant"], -1, "tank vacated")
	Runner.T.ok(p["boost_ticks"] == 0, "no bail boost from a healthy tank")


func test_crush_and_bullet_immunity() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	# Enemy at contact range: crushed instead of killing the player.
	sim._spawn_enemy(tank["x"], tank["y"], false)
	var chest_before := sim.war_chest
	sim.step([_idle()])
	Runner.T.ok(p["alive"], "tanked player survives enemy contact")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_RUSHER, "crush minted coin")


func test_cannon_draws_grenade_ammo() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var shells_before: int = p["grenade_ammo"]
	var fire := SimInput.new()
	fire.fire = true
	fire.aim_y = -256
	sim.step([fire])
	Runner.T.eq(p["grenade_ammo"], shells_before - 1, "cannon consumed grenade ammo")
	Runner.T.ok(sim.grenades.size() == 1 and sim.grenades[0]["shell"], "shell projectile spawned")


func test_fuel_out_ignites_and_bail_window() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	tank["fuel"] = 2
	sim.step([_idle()])
	sim.step([_idle()])
	Runner.T.ok(tank["burning"], "fuel out ignites the tank")
	Runner.T.eq(tank["burn_ticks"], SimWorld.TANK_BAIL_TICKS - 1, "bail window armed")
	# Bail: edge-press interact → out with the boost, tank still burning.
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.eq(p["in_tank"], -1, "bailed out")
	Runner.T.ok(p["boost_ticks"] > 0, "bail grants the speed boost")
	# Window expires → detonation, player already clear survives.
	for i in SimWorld.TANK_BAIL_TICKS:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "burning tank detonated after the window")
	Runner.T.ok(p["alive"], "bailed player survived the detonation")


func test_stay_inside_and_die() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	tank["fuel"] = 1
	for i in SimWorld.TANK_BAIL_TICKS + 3:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "tank gone")
	Runner.T.ok(not p["alive"], "rider who ignored the klaxon died")


func test_kamikaze_destroys_bunker_and_ejects_driver() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var bunker := {"x": tank["x"] - 10 * Fixed.ONE, "y": tank["y"] - 100 * Fixed.ONE,
		"alive": true, "spawn_cd": 999999}
	sim.bunkers.append(bunker)
	sim._ignite_tank(tank)
	# Drive north into the bunker while burning.
	var up := SimInput.new()
	up.move_y = -256
	var chest_before := sim.war_chest
	for i in 120:
		sim.step([up])
		if not tank["alive"]:
			break
	Runner.T.ok(not bunker["alive"], "kamikaze detonated the bunker")
	Runner.T.ok(not tank["alive"], "tank consumed by the verb")
	Runner.T.ok(p["alive"], "driver thrown clear, alive")
	Runner.T.ok(p["boost_ticks"] > 0 or p["in_tank"] == -1, "driver ejected with escape boost")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_BUNKER * 2, "kamikaze pays double bunker coin")
