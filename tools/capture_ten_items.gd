extends "res://tools/screenshots.gd"
## Targeted real-render acceptance poses; use SHOT_DIR and GL compatibility.

func _build_shots() -> void:
	shots = [
		{"name": "ready-one-seat", "build": _shot_shop, "dress": _ready_one},
		{"name": "ready-both-large", "build": _shot_shop, "dress": _ready_both},
		{"name": "partial-refill", "build": _shot_shop, "dress": _partial},
		{"name": "remote-rally", "build": _shot_shop, "dress": _rally},
		{"name": "manual-large", "build": _shot_shop, "dress": _dress_howto},
	]

func _ready_one(m: Node2D) -> void:
	m._last_inputs.clear()
	var first := SimInput.new()
	first.revive = true
	m._last_inputs.append(first)
	m._last_inputs.append(SimInput.new())

func _ready_both(m: Node2D) -> void:
	_ready_one(m)
	m._last_inputs[1].revive = true
	m.sim.ready_hold = SimWorld.READY_HOLD_TICKS / 2
	m._set_text_scale(200)

func _partial(m: Node2D) -> void:
	m._last_inputs.clear()
	m.sim.players[0]["mg_ammo"] = SimWorld.MG_AMMO_MAX - 1
	m.sim.players[1]["mg_ammo"] = SimWorld.MG_AMMO_MAX - 1
	m._wheel[0] = {"open": true, "sel": 4}

func _rally(m: Node2D) -> void:
	m._last_inputs.clear()
	m.sim.players[1]["alive"] = false
	m.sim.players[1]["y"] = m.sim.players[0]["y"] - 1000 * F
