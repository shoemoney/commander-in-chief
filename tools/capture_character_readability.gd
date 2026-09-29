extends "res://tools/screenshots.gd"
## Staged QA scenes rendered by the real game. These are not gameplay screenshots.
## Cardinal aim, committed enemy lanes, and redraw-stable forward/backward poses.

const MainView := preload("res://src/main.gd")


func _build_shots() -> void:
	shots = [
		{"name": "aim-north", "build": func(): return _arena(Vector2.UP), "dress": _dress_aim},
		{"name": "aim-east", "build": func(): return _arena(Vector2.RIGHT), "dress": _dress_aim},
		{"name": "aim-south", "build": func(): return _arena(Vector2.DOWN), "dress": _dress_aim},
		{"name": "aim-west", "build": func(): return _arena(Vector2.LEFT), "dress": _dress_aim},
		{"name": "forward-step-a", "build": func(): return _arena(Vector2.UP, 120), "dress": _dress_forward},
		{"name": "forward-step-b", "build": func(): return _arena(Vector2.UP, 126), "dress": _dress_forward},
		{"name": "backward-step-a", "build": func(): return _arena(Vector2.UP, 120), "dress": _dress_backward},
		{"name": "backward-step-b", "build": func(): return _arena(Vector2.UP, 126), "dress": _dress_backward},
	]


func _arena(aim: Vector2, tick: int = 120) -> SimWorld:
	var sw := SimWorld.new(7, 1, "campaign")
	sw.tick_count = tick
	sw.rocks.clear()
	sw.tanks.clear()
	sw.pickups.clear()
	var p: Dictionary = sw.players[0]
	p["x"] = 320 * F
	p["y"] = sw.camera_top + 240 * F
	p["aim_x"] = int(aim.x * F)
	p["aim_y"] = int(aim.y * F)
	p["fire_cd"] = SimWorld.FIRE_COOLDOWN_TICKS
	sw._spawn_enemy(220 * F, sw.camera_top + 120 * F, false)
	sw._spawn_enemy(420 * F, sw.camera_top + 120 * F, true)
	for e in sw.enemies:
		# The player stands off to the side of both locked, straight-down lanes.
		e["windup"] = 12
		e["aim_lx"] = 0
		e["aim_ly"] = 150 * F
	for i in 3:
		sw.bullets.append({"x": p["x"] + int(aim.x * (25 + i * 24)) * F,
			"y": p["y"] + int(aim.y * (25 + i * 24)) * F,
			"vx": int(aim.x * 6) * F, "vy": int(aim.y * 6) * F, "ttl": 60, "owner": 0})
	return sw


func _dress_aim(m: Node2D) -> void:
	m._player_motion.clear()
	m._enemy_pos_prev.clear()
	m._enemy_face.clear()
	m._motion = 1.0
	m._player_face[0] = m._aim_angle(m.sim.players[0])
	m._hint_text = ""
	m._hint_t = 0.0
	m._hitstop_frames = 0


func _dress_stride(m: Node2D, travel: Vector2i) -> void:
	_dress_aim(m)
	var p: Dictionary = m.sim.players[0]
	var at := Vector2i(p["x"], p["y"])
	p["x"] = at.x - travel.x
	p["y"] = at.y - travel.y
	MainView.sample_character_motion(m._player_motion, 0, p, m.sim.tick_count - 1)
	p["x"] = at.x
	p["y"] = at.y
	# Every settle redraw samples the same tick: a walk must survive all of them.
	MainView.sample_character_motion(m._player_motion, 0, p, m.sim.tick_count)


func _dress_forward(m: Node2D) -> void:
	_dress_stride(m, Vector2i(0, -2 * F))


func _dress_backward(m: Node2D) -> void:
	_dress_stride(m, Vector2i(0, 2 * F))
