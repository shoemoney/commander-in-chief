extends "res://tools/screenshots.gd"
## Staged edge-case QA, not marketing gameplay evidence.

func _build_shots() -> void:
	shots = [
		{"name": "north-edge", "build": func(): return _edge(1, 16)},
		{"name": "under-readouts", "build": func(): return _edge(1, 42)},
		{"name": "coop-edges", "build": func(): return _edge(2, 32)},
		{"name": "clear-of-hud", "build": func(): return _edge(1, 200)},
	]
	for shot in shots:
		shot["dress"] = func(m: Node2D): m._hud_icons._sync_visibility()

func _edge(count: int, y: int) -> SimWorld:
	var sw := SimWorld.new(3, count, "endless")
	sw.tick_count = 120
	for i in count:
		var p: Dictionary = sw.players[i]
		p["x"] = (170 + i * 220) * F
		p["y"] = sw.camera_top + y * F
		p["aim_x"] = 0
		p["aim_y"] = -F
	return sw
