class_name HudIcons
extends Control
## Icon HUD drawn on the shake-immune CanvasLayer. Replaces the P3 plain-text
## readout: War Chest coin, score medal, and per-player ammo/grenade/vest/
## fuel/skull states render as baked legacy art icons (assets/legacy-art/icons/).

const ICON := 13.0
const FONT_SIZE := 10

var main: Node2D
var _prev_chest := 0
var _chest_pulse := 0.0   # gold flash on the counter when coin comes in


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: SimWorld = main.sim

	# Scavenged-metal panel backing the whole readout.
	draw_texture_rect(Art.tex("ui_panel"),
		Rect2(2, 2, 262, 26 + sim.players.size() * 16), false, Color(1, 1, 1, 0.9))

	# Row 0: the shared economy — the twist the whole game hangs on.
	if sim.war_chest > _prev_chest:
		_chest_pulse = 1.0
	_prev_chest = sim.war_chest
	_chest_pulse = maxf(0.0, _chest_pulse - 0.05)
	var x := 8.0
	var y := 6.0
	x = _stat("icon_coin", str(sim.war_chest), x, y,
		Color(0.95, 0.96, 0.9).lerp(Color(1.0, 0.85, 0.3), _chest_pulse))
	x = _stat("icon_medal", str(sim.score), x, y)
	if sim.mode == "endless":
		if sim.intermission_ticks > 0:
			x = _text("SHOP OPEN %ds" % [sim.intermission_ticks / 60], x, y + ICON - 3.0,
				Color(1.0, 0.9, 0.5)) + 10.0
		else:
			x = _text("WAVE %d" % sim.wave, x, y + ICON - 3.0) + 10.0
	else:
		x = _text("%dm" % [-Fixed.to_int(sim.camera_top) / 10], x, y + ICON - 3.0) + 10.0
	# Discoverability: the supply wheel exists (hold to open).
	Art.draw_glyph(self, "wheel", Vector2(x + 5.0, y + ICON / 2.0), 11.0)
	_text("SUPPLIES", x + 13.0, y + ICON - 3.0, Color(0.75, 0.78, 0.7, 0.8))

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
				var tx := _text("REVIVE %d" % sim.revive_cost(p), px, ry + ICON - 3.0,
					Color(1.0, 0.85, 0.4) if blink else Color(0.85, 0.65, 0.35))
				Art.draw_glyph(self, "revive", Vector2(tx + 9.0, ry + ICON / 2.0), 11.0)
		elif p["in_tank"] >= 0:
			var t: Dictionary = sim.tanks[p["in_tank"]]
			px = _fuel_dial(t, px, ry)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry)
			if t["burning"] and (Engine.get_physics_frames() / 8) % 2 == 0:
				var bx := _text("BAIL OUT!", px, ry + ICON - 3.0, Color(1.0, 0.3, 0.2))
				Art.draw_glyph(self, "interact", Vector2(bx + 9.0, ry + ICON / 2.0), 11.0)
		else:
			# Low-ammo escalation: amber under 20, blinking red when dry.
			var ammo: int = p["mg_ammo"]
			var acol := Color(0.95, 0.96, 0.9)
			if ammo == 0:
				acol = Color(1.0, 0.25, 0.2) if (Engine.get_physics_frames() / 10) % 2 == 0 \
					else Color(0.6, 0.2, 0.18)
			elif ammo <= 20:
				acol = Color(1.0, 0.75, 0.35)
			px = _stat("icon_ammo", "%02d" % ammo, px, ry, acol)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry)
			if p["vest"]:
				draw_texture_rect(Art.tex("icon_vest"), Rect2(px, ry, ICON, ICON), false)
		ry += 16.0


func _fuel_dial(t: Dictionary, x: float, y: float) -> float:
	# Fuel-cap gauge: ring frames an arc that drains green → red.
	var frac := clampf(float(t["fuel"]) / float(SimWorld.TANK_FUEL_TICKS), 0.0, 1.0)
	var c := Vector2(x + ICON / 2.0, y + ICON / 2.0)
	draw_circle(c, ICON * 0.34, Color(0.08, 0.07, 0.06))
	if frac > 0.0:
		draw_arc(c, ICON * 0.27, -PI / 2, -PI / 2 + TAU * frac, 20,
			Color(0.9 - frac * 0.7, 0.15 + frac * 0.65, 0.12), 2.5)
	draw_texture_rect(Art.tex("ui_dial_fuel"), Rect2(x - 1, y - 1, ICON + 2, ICON + 2), false)
	return _text("%ds" % maxi(0, t["fuel"] / 60), x + ICON + 3.0, y + ICON - 3.0) + 10.0


func _stat(icon: String, txt: String, x: float, y: float,
		col := Color(0.95, 0.96, 0.9)) -> float:
	draw_texture_rect(Art.tex(icon), Rect2(x, y, ICON, ICON), false)
	return _text(txt, x + ICON + 3.0, y + ICON - 3.0, col) + 10.0


func _text(txt: String, x: float, y: float, col := Color(0.95, 0.96, 0.9)) -> float:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(x + 1, y + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		Color(0, 0, 0, 0.65))
	draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
	return x + f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
