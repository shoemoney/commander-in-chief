extends "res://tools/screenshots.gd"
## QA-only staged setups; each refusal is produced by actual input/simulation.

func _build_shots() -> void:
	shots = [
		{"name": "cannon-empty", "build": func(): return _tank_state(0, 0), "dress": _attempt},
		{"name": "cannon-reloading", "build": func(): return _tank_state(4, 30), "dress": _attempt},
		{"name": "cannon-ready", "build": func(): return _tank_state(4, 0), "dress": _attempt},
	]


func _tank_state(ammo: int, cooldown: int) -> SimWorld:
	var sw := SimWorld.new(7, 1, "campaign")
	var p := sw.players[0]
	p["grenade_ammo"] = ammo
	p["in_tank"] = sw.tanks.size()
	sw.tanks.append({"x": p["x"], "y": p["y"], "alive": true,
		"burning": false, "fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0,
		"crew_ring_ticks": -1, "fire_cd": cooldown, "occupant": 0})
	return sw


func _attempt(m: Node2D) -> void:
	m._motion = 0.0
	m._hint_t = 0.0
	m._grenade_dry.fill(0)
	m._dry_grenade_frame.fill(-100)
	var inp := SimInput.new()
	inp.grenade = true
	inp.aim_y = -256
	m.sim.step([inp])
	m._consume_events()
	print("CANNON CAPTURE events=", m.sim.events, " flash=", m._grenade_dry)
