extends Node2D
## Greybox view over the deterministic sim. All floats live here, never in src/sim.
##
## Controls (P0):
##   P1 — WASD move, arrow keys aim, Space fire, Shift grenade, E revive
##   Gamepad (either player) — LS move, RS aim, RT/R1 fire, L1 grenade, Y revive
##   F2 toggles a second local player.

const PX := 1.0 / Fixed.ONE

var sim: SimWorld
var _two_players := false

@onready var hud: Label = $HUD/Label


func _ready() -> void:
	_reset()


func _reset() -> void:
	sim = SimWorld.new(0xC0FFEE, 2 if _two_players else 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_two_players = not _two_players
			_reset()
		elif event.keycode == KEY_R:
			_reset()


func _physics_process(_delta: float) -> void:
	sim.step(_gather_inputs())
	queue_redraw()
	_update_hud()


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
	# Bunkers: armor — grenades only.
	for bk in sim.bunkers:
		if bk["alive"]:
			var tl := _to_screen(bk["x"], bk["y"])
			draw_rect(Rect2(tl, Vector2(48, 32)), Color(0.35, 0.32, 0.28))
			draw_rect(Rect2(tl, Vector2(48, 32)), Color(0.6, 0.55, 0.45), false, 2.0)
	# Pickups.
	for pk in sim.pickups:
		var c := Color(0.9, 0.75, 0.2) if pk["kind"] == 0 else Color(0.4, 0.8, 0.3)
		draw_rect(Rect2(_to_screen(pk["x"], pk["y"]) - Vector2(5, 5), Vector2(10, 10)), c)
	# Enemies.
	for e in sim.enemies:
		if e["alive"]:
			var col := Color(0.85, 0.25, 0.2) if e["elite"] else Color(0.7, 0.5, 0.3)
			draw_circle(_to_screen(e["x"], e["y"]), 7.0, col)
	# Grenades (fake-Z shadow + body).
	for g in sim.grenades:
		var base := _to_screen(g["x"], g["y"])
		draw_circle(base, 3.0, Color(0, 0, 0, 0.4))
		draw_circle(base - Vector2(0, g["z"] * PX * 0.5), 3.5, Color(0.3, 0.6, 0.3))
	# Bullets.
	for b in sim.bullets:
		draw_circle(_to_screen(b["x"], b["y"]), 2.0, Color(1.0, 0.9, 0.5))
	# Players + aim line.
	for i in sim.players.size():
		var p := sim.players[i]
		var pos := _to_screen(p["x"], p["y"])
		var col := Color(0.3, 0.7, 1.0) if i == 0 else Color(1.0, 0.6, 0.2)
		if p["alive"]:
			draw_circle(pos, 8.0, col)
			draw_line(pos, pos + Vector2(p["aim_x"] * PX, p["aim_y"] * PX) * 18.0, col.lightened(0.4), 2.0)
		else:
			draw_arc(pos, 9.0, 0, TAU, 24, col.darkened(0.3), 2.0)


func _update_hud() -> void:
	var lines: Array[String] = []
	lines.append("WAR CHEST %d   SCORE %d   DIST %dm" % [sim.war_chest, sim.score, -Fixed.to_int(sim.camera_top) / 10])
	for i in sim.players.size():
		var p := sim.players[i]
		if p["alive"]:
			lines.append("P%d  MG %02d  GRN %02d" % [i + 1, p["mg_ammo"], p["grenade_ammo"]])
		else:
			lines.append("P%d  DOWN — revive costs %d [E/Y]" % [i + 1, sim.revive_cost(p)])
	hud.text = "\n".join(lines)
