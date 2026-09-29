extends SceneTree
## Paired policy probe, not a human balance verdict. Both runs use the same
## seed and bot; the foot policy suppresses boarding while retaining other verbs.
const SEEDS := [1, 2, 3, 4]
const LIMIT := 20000

func _init() -> void:
	var driver: Script = load("res://src/main.gd")
	print("policy,seed,ticks,victory,downs,kills,tank_ticks")
	for sd in SEEDS:
		for allow_tank in [false, true]:
			var sim := SimWorld.new(sd, 1, "campaign")
			var downs := 0
			var kills := 0
			var tank_ticks := 0
			var elapsed := 0
			for tick in LIMIT:
				var input: SimInput = driver.demo_input(tick, sim)
				if not allow_tank and sim.players[0]["in_tank"] < 0:
					for tank in sim.tanks:
						if tank["alive"] and sim._dist_lte(sim.players[0]["x"], sim.players[0]["y"],
								tank["x"], tank["y"], SimWorld.TANK_BOARD_RADIUS):
							input.interact = false
				if sim.players[0]["in_tank"] >= 0:
					tank_ticks += 1
				sim.step([input])
				for event in sim.events:
					if event["t"] == "player_down": downs += 1
					if event["t"] == "kill": kills += 1
				elapsed = tick + 1
				if sim.victory or sim.wiped: break
			print("%s,%d,%d,%s,%d,%d,%d" % ["tank" if allow_tank else "foot", sd,
				elapsed, str(sim.victory), downs, kills, tank_ticks])
	quit()
