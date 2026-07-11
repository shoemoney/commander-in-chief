class_name HudIcons
extends Control
## Icon HUD drawn on the shake-immune CanvasLayer. Replaces the P3 plain-text
## readout: War Chest coin, score medal, and per-player ammo/grenade/vest/
## fuel/skull states render as baked legacy art icons (assets/legacy-art/icons/).

const ICON := 13.0
const FONT_SIZE := 10

var main: Node2D


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: SimWorld = main.sim

	# Row 0: the shared economy — the twist the whole game hangs on.
	var x := 8.0
	var y := 6.0
	x = _stat("icon_coin", str(sim.war_chest), x, y)
	x = _stat("icon_medal", str(sim.score), x, y)
	if sim.mode == "endless":
		if sim.intermission_ticks > 0:
			_text("SHOP OPEN %ds" % [sim.intermission_ticks / 60], x, y + ICON - 3.0,
				Color(1.0, 0.9, 0.5))
		else:
			_text("WAVE %d" % sim.wave, x, y + ICON - 3.0)
	else:
		_text("%dm" % [-Fixed.to_int(sim.camera_top) / 10], x, y + ICON - 3.0)

	# Player rows.
	var ry := y + 17.0
	for i in sim.players.size():
		var p := sim.players[i]
		var px := 8.0
		var pcol := Color(0.75, 0.95, 0.7) if i == 0 else Color(0.95, 0.85, 0.6)
		px = _text("P%d" % (i + 1), px, ry + ICON - 3.0, pcol) + 7.0
		if not p["alive"]:
			px = _stat("icon_skull", "x%d" % p["deaths"], px, ry)
			if sim.last_stand:
				_text("K.I.A.", px, ry + ICON - 3.0, Color(0.9, 0.35, 0.3))
			else:
				var blink := (Engine.get_physics_frames() / 20) % 2 == 0
				_text("REVIVE %d [E/Y]" % sim.revive_cost(p), px, ry + ICON - 3.0,
					Color(1.0, 0.85, 0.4) if blink else Color(0.85, 0.65, 0.35))
		elif p["in_tank"] >= 0:
			var t: Dictionary = sim.tanks[p["in_tank"]]
			px = _stat("icon_fuel", "%ds" % maxi(0, t["fuel"] / 60), px, ry)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry)
			if t["burning"] and (Engine.get_physics_frames() / 8) % 2 == 0:
				_text("BAIL OUT! [F]", px, ry + ICON - 3.0, Color(1.0, 0.3, 0.2))
		else:
			px = _stat("icon_ammo", "%02d" % p["mg_ammo"], px, ry)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry)
			if p["vest"]:
				draw_texture_rect(Art.tex("icon_vest"), Rect2(px, ry, ICON, ICON), false)
		ry += 16.0


func _stat(icon: String, txt: String, x: float, y: float) -> float:
	draw_texture_rect(Art.tex(icon), Rect2(x, y, ICON, ICON), false)
	return _text(txt, x + ICON + 3.0, y + ICON - 3.0) + 10.0


func _text(txt: String, x: float, y: float, col := Color(0.95, 0.96, 0.9)) -> float:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(x + 1, y + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		Color(0, 0, 0, 0.65))
	draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
	return x + f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
