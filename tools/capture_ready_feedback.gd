extends "res://tools/screenshots.gd"
## Staged QA only: exercise the production ready panel, not store footage.

func _process(_delta: float) -> bool:
	RenderingServer.force_draw.call_deferred(false, 1.0 / 60.0)
	return false


func _build_shots() -> void:
	root.set_disable_input(true)
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("READY CAPTURE FAIL: deadline exceeded")
		quit(1))
	shots = [{"name": "solo-holding", "build": _solo, "dress": _holding}]
	if OS.get_environment("READY_BASELINE") != "1":
		shots.append_array([
			{"name": "solo-released", "build": _solo, "dress": _released},
			{"name": "coop-split", "build": _shot_shop, "dress": _split},
			{"name": "coop-both-large", "build": _shot_shop, "dress": _both},
			{"name": "coop-rescue", "build": _shot_shop, "dress": _rescue},
		])


func _solo() -> SimWorld:
	var sw := SimWorld.new(3, 1, "endless")
	sw.wave = 1
	sw.intermission_ticks = 180
	return sw


func _holding(m: Node2D) -> void:
	m._motion = 0.0
	m._hint_t = 0.0
	m._banners.clear()
	m._last_inputs.clear()
	for i in m.sim.players.size():
		var input := SimInput.new()
		input.revive = true
		m._last_inputs.append(input)
	m.sim.ready_hold = SimWorld.READY_HOLD_TICKS / 2


func _released(m: Node2D) -> void:
	_holding(m)
	m._last_inputs[0].revive = false
	m.sim.ready_hold = 0


func _split(m: Node2D) -> void:
	_holding(m)
	m._last_inputs[1].revive = false
	m.sim.ready_hold = 0


func _both(m: Node2D) -> void:
	_holding(m)
	m._set_text_scale(200)


func _rescue(m: Node2D) -> void:
	_holding(m)
	m.sim.players[1]["alive"] = false
	m.sim.ready_hold = 0
