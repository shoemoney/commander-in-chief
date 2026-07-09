extends Node2D
## Greybox view over the deterministic sim. All floats live here, never in src/sim.
##
## Controls (P1):
##   P1 — WASD move, arrow keys aim, Space fire, Shift grenade, C roll,
##        F interact (board/exit tank), E revive
##   Gamepad — LS move, RS aim, RT/R1 fire, L1 grenade, B roll, X interact, Y revive
##   F2 toggles a second local player. R restarts.

const PX := 1.0 / Fixed.ONE

var sim: SimWorld
var _two_players := false
var _endless := false
# Feel stack v0 (view-only; the sim never sees any of this).
var _trauma := 0.0
var _hitstop_frames := 0
var _flash_alpha := 0.0

@onready var hud: Label = $HUD/Label


func _ready() -> void:
	_reset()


func _reset() -> void:
	sim = SimWorld.new(0xC0FFEE, 2 if _two_players else 1, "endless" if _endless else "campaign")
	_trauma = 0.0
	_hitstop_frames = 0
	_flash_alpha = 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_two_players = not _two_players
			_reset()
		elif event.keycode == KEY_F3:
			_endless = not _endless
			_reset()
		elif event.keycode == KEY_R:
			_reset()


func _physics_process(_delta: float) -> void:
	# Hit-stop: freeze the sim (and therefore the world) for a few frames on
	# explosions only. View-layer pacing; determinism untouched.
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
	else:
		sim.step(_gather_inputs())
		_consume_events()
	_update_feel()
	queue_redraw()
	_update_hud()


func _consume_events() -> void:
	for ev in sim.events:
		match ev["t"]:
			"explosion":
				_trauma = minf(1.0, _trauma + 0.35)
				_hitstop_frames = maxi(_hitstop_frames, 4)   # ~66 ms at 60 Hz
			"kill":
				_flash_alpha = maxf(_flash_alpha, 0.25)
			"gate_open":
				_trauma = minf(1.0, _trauma + 0.2)
			"vest_break":
				_flash_alpha = maxf(_flash_alpha, 0.35)
			"colossus_engage":
				_trauma = 1.0
				_hitstop_frames = maxi(_hitstop_frames, 8)
			"victory":
				_trauma = 1.0
				_flash_alpha = 0.6


func _update_feel() -> void:
	# Trauma-based shake with quadratic falloff; offset the world root only
	# (the HUD lives on a CanvasLayer and stays put).
	_trauma = maxf(0.0, _trauma - 0.03)
	_flash_alpha = maxf(0.0, _flash_alpha - 0.08)
	var mag := _trauma * _trauma * 6.0
	if mag > 0.01:
		# Deterministic-ish wobble from the frame counter — pure view cosmetics.
		var t := float(Engine.get_physics_frames())
		position = Vector2(sin(t * 1.7) * mag, cos(t * 2.3) * mag)
	else:
		position = Vector2.ZERO


func _gather_inputs() -> Array:
	var inputs: Array = []
	var p1 := SimInput.new()
	var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var ky := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
	var ax := (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
	var ay := (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0)
	var pad_move := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if pad_move.length() > 0.2:
		kx = pad_move.x
		ky = pad_move.y
	if pad_aim.length() > 0.25:
		ax = pad_aim.x
		ay = pad_aim.y
	p1.move_x = _quantize_axis(kx)
	p1.move_y = _quantize_axis(ky)
	p1.aim_x = _quantize_axis(ax)
	p1.aim_y = _quantize_axis(ay)
	p1.fire = Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	p1.grenade = Input.is_physical_key_pressed(KEY_SHIFT) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	p1.roll = Input.is_physical_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	p1.interact = Input.is_physical_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	p1.revive = Input.is_physical_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	inputs.append(p1)

	if _two_players:
		var p2 := SimInput.new()
		p2.move_x = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_LEFT_X))
		p2.move_y = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_LEFT_Y))
		p2.aim_x = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_RIGHT_X))
		p2.aim_y = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_RIGHT_Y))
		p2.fire = Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
			or Input.is_joy_button_pressed(1, JOY_BUTTON_RIGHT_SHOULDER)
		p2.grenade = Input.is_joy_button_pressed(1, JOY_BUTTON_LEFT_SHOULDER)
		p2.roll = Input.is_joy_button_pressed(1, JOY_BUTTON_B)
		p2.interact = Input.is_joy_button_pressed(1, JOY_BUTTON_X)
		p2.revive = Input.is_joy_button_pressed(1, JOY_BUTTON_Y)
		inputs.append(p2)
	return inputs


func _quantize_axis(v: float) -> int:
	## The float→int boundary: the sim only ever sees quantized [-256, 256].
	return clampi(int(round(v * 256.0)), -256, 256)


func _to_screen(fx: int, fy: int) -> Vector2:
	return Vector2(fx * PX, (fy - sim.camera_top) * PX)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.10, 0.13, 0.09))
	# Rivers: band with a dry ford gap.
	for w in sim.waters:
		var wy := _to_screen(0, w["y"]).y
		var wh := SimWorld.WATER_H * PX
		draw_rect(Rect2(0, wy, 640, wh), Color(0.13, 0.22, 0.30))
		var ford_left: float = (w["ford_x"] - SimWorld.FORD_HALF_W) * PX
		draw_rect(Rect2(ford_left, wy, SimWorld.FORD_HALF_W * 2.0 * PX, wh), Color(0.25, 0.23, 0.16))
	# Gates: closed = solid wall; open = broken stumps at the flanks.
	for g in sim.gates:
		var gy := _to_screen(0, g["y"]).y
		if not g["open"]:
			draw_rect(Rect2(0, gy - 5, 640, 10), Color(0.28, 0.26, 0.22))
			draw_rect(Rect2(0, gy - 5, 640, 10), Color(0.55, 0.5, 0.4), false, 1.5)
		else:
			draw_rect(Rect2(0, gy - 4, 40, 8), Color(0.22, 0.2, 0.17))
			draw_rect(Rect2(600, gy - 4, 40, 8), Color(0.22, 0.2, 0.17))
	# Bunkers: armor — grenades only.
	for bk in sim.bunkers:
		if bk["alive"]:
			var tl := _to_screen(bk["x"], bk["y"])
			draw_rect(Rect2(tl, Vector2(48, 32)), Color(0.35, 0.32, 0.28))
			draw_rect(Rect2(tl, Vector2(48, 32)), Color(0.6, 0.55, 0.45), false, 2.0)
	# Tanks.
	for t in sim.tanks:
		if not t["alive"]:
			continue
		var c := _to_screen(t["x"], t["y"])
		var body := Color(0.30, 0.38, 0.28)
		if t["burning"]:
			# Klaxon flash: alternate hot frames during the bail window.
			body = Color(0.8, 0.3, 0.1) if (t["burn_ticks"] / 6) % 2 == 0 else Color(0.5, 0.25, 0.1)
		draw_rect(Rect2(c - Vector2(14, 10), Vector2(28, 20)), body)
		draw_rect(Rect2(c - Vector2(14, 10), Vector2(28, 20)), Color(0.7, 0.75, 0.6), false, 2.0)
		if t["occupant"] < 0 and not t["burning"]:
			draw_string(ThemeDB.fallback_font, c + Vector2(-10, -14), "[F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.9, 0.7))
	# Mortar strike telegraphs: shrinking target circles.
	for s in sim.strikes:
		var sp := _to_screen(s["x"], s["y"])
		var frac: float = float(s["ticks"]) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
		draw_arc(sp, 6.0 + 22.0 * frac, 0, TAU, 24, Color(1.0, 0.35, 0.2, 0.9), 2.0)
		draw_circle(sp, 2.0, Color(1.0, 0.35, 0.2))
	# Observer: pinned at the top edge, waving a marker flag.
	if not sim.observer.is_empty():
		var op := _to_screen(sim.observer["x"], sim.camera_top + SimWorld.OBSERVER_Y_OFFSET)
		draw_circle(op, 6.0, Color(0.95, 0.8, 0.2))
		draw_line(op, op + Vector2(0, -10), Color(0.95, 0.8, 0.2), 2.0)
	# Pickups (shop crates show a price tag).
	for pk in sim.pickups:
		var ppos := _to_screen(pk["x"], pk["y"])
		var c: Color
		match pk["kind"]:
			0: c = Color(0.9, 0.75, 0.2)
			1: c = Color(0.4, 0.8, 0.3)
			2: c = Color(0.5, 0.6, 0.95)
			_: c = Color(0.95, 0.4, 0.15)
		draw_rect(Rect2(ppos - Vector2(5, 5), Vector2(10, 10)), c)
		if pk.get("cost", 0) > 0:
			draw_string(ThemeDB.fallback_font, ppos + Vector2(-10, -8), "%d¢" % pk["cost"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.9, 0.6))
	# The Foundry Colossus.
	if not sim.colossus.is_empty() and sim.colossus["alive"]:
		var cpos := _to_screen(sim.colossus["x"], sim.colossus["y"])
		var phase := sim.colossus_phase()
		var hull := Color(0.32, 0.30, 0.34) if phase < 3 else Color(0.5, 0.25, 0.2)
		draw_rect(Rect2(cpos - Vector2(30, 22), Vector2(60, 44)), hull)
		draw_rect(Rect2(cpos - Vector2(30, 22), Vector2(60, 44)), Color(0.75, 0.7, 0.6), false, 2.5)
		draw_circle(cpos, 8.0, Color(0.85, 0.3, 0.2))
		var cfrac: float = float(sim.colossus["hp"]) / float(SimWorld.COLOSSUS_HP)
		draw_rect(Rect2(Vector2(170, 8), Vector2(300, 6)), Color(0.2, 0.2, 0.2))
		draw_rect(Rect2(Vector2(170, 8), Vector2(300.0 * cfrac, 6)), Color(0.9, 0.25, 0.2))
	# Enemies (submerged frogmen are just a ripple).
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var epos := _to_screen(e["x"], e["y"])
		if e["kind"] == "frogman":
			if e["submerged"]:
				draw_arc(epos, 5.0, 0, TAU, 12, Color(0.5, 0.75, 0.85, 0.5), 1.5)
			else:
				draw_circle(epos, 7.0, Color(0.2, 0.55, 0.5))
		else:
			var col := Color(0.85, 0.25, 0.2) if e["elite"] else Color(0.7, 0.5, 0.3)
			draw_circle(epos, 7.0, col)
	# Bridge Gunship bosses + HP bars.
	for g in sim.gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		var boss: Dictionary = g["boss"]
		var bpos := _to_screen(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
		draw_rect(Rect2(bpos - Vector2(18, 8), Vector2(36, 16)), Color(0.45, 0.2, 0.2))
		draw_rect(Rect2(bpos - Vector2(18, 8), Vector2(36, 16)), Color(0.9, 0.5, 0.4), false, 2.0)
		draw_line(bpos + Vector2(-22, 0), bpos + Vector2(22, 0), Color(0.3, 0.3, 0.3), 1.0)
		var frac: float = float(boss["hp"]) / float(SimWorld.BOSS_HP)
		draw_rect(Rect2(bpos + Vector2(-18, -14), Vector2(36.0 * frac, 3)), Color(0.9, 0.25, 0.2))
	# Enemy fire.
	for b in sim.enemy_bullets:
		draw_circle(_to_screen(b["x"], b["y"]), 2.5, Color(1.0, 0.45, 0.25))
	# Grenades and tank shells (fake-Z shadow + body).
	for g in sim.grenades:
		var base := _to_screen(g["x"], g["y"])
		draw_circle(base, 3.0, Color(0, 0, 0, 0.4))
		var body_col := Color(0.85, 0.65, 0.25) if g.get("shell", false) else Color(0.3, 0.6, 0.3)
		draw_circle(base - Vector2(0, g["z"] * PX * 0.5), 3.5, body_col)
	# Bullets.
	for b in sim.bullets:
		draw_circle(_to_screen(b["x"], b["y"]), 2.0, Color(1.0, 0.9, 0.5))
	# Players + aim line.
	for i in sim.players.size():
		var p := sim.players[i]
		if p["in_tank"] >= 0:
			continue   # rendered as the tank
		var pos := _to_screen(p["x"], p["y"])
		var col := Color(0.3, 0.7, 1.0) if i == 0 else Color(1.0, 0.6, 0.2)
		if p["alive"]:
			if p["roll_ticks"] > 0:
				draw_circle(pos, 8.0, col.lightened(0.5))   # i-frame shimmer
			else:
				draw_circle(pos, 8.0, col)
			if p["vest"]:
				draw_arc(pos, 11.0, 0, TAU, 24, Color(0.6, 0.7, 1.0), 2.0)   # vest ring
			draw_line(pos, pos + Vector2(p["aim_x"] * PX, p["aim_y"] * PX) * 18.0, col.lightened(0.4), 2.0)
		else:
			draw_arc(pos, 9.0, 0, TAU, 24, col.darkened(0.3), 2.0)
	# Kill flash overlay.
	if _flash_alpha > 0.01:
		draw_rect(Rect2(0, 0, 640, 360), Color(1, 1, 1, _flash_alpha))
	# Victory / Last Stand banners.
	if sim.victory:
		draw_rect(Rect2(160, 150, 320, 60), Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(238, 186), "V I C T O L Y !",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.3))
	elif sim.last_stand:
		draw_string(ThemeDB.fallback_font, Vector2(250, 350), "LAST STAND — NO REVIVES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.4, 0.3))


func _update_hud() -> void:
	var lines: Array[String] = []
	if sim.mode == "endless":
		var wave_state := "INTERMISSION %ds — SHOP OPEN" % [sim.intermission_ticks / 60] if sim.intermission_ticks > 0 else "WAVE %d" % sim.wave
		lines.append("ENDLESS WAR — %s   CHEST %d   SCORE %d" % [wave_state, sim.war_chest, sim.score])
	else:
		lines.append("WAR CHEST %d   SCORE %d   DIST %dm" % [sim.war_chest, sim.score, -Fixed.to_int(sim.camera_top) / 10])
	for i in sim.players.size():
		var p := sim.players[i]
		if not p["alive"]:
			lines.append("P%d  DOWN — revive costs %d [E/Y]" % [i + 1, sim.revive_cost(p)])
		elif p["in_tank"] >= 0:
			var t := sim.tanks[p["in_tank"]]
			var state := "BAIL OUT! [F]" if t["burning"] else "fuel %ds" % [t["fuel"] / 60]
			lines.append("P%d  TANK — shells %02d  %s" % [i + 1, p["grenade_ammo"], state])
		else:
			lines.append("P%d  MG %02d  GRN %02d" % [i + 1, p["mg_ammo"], p["grenade_ammo"]])
	hud.text = "\n".join(lines)
