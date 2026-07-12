class_name GameMenu
extends Control
## Title + pause overlay (Modern Menus sprites). Lives on the HUD CanvasLayer;
## while visible, main.gd simply doesn't step the sim — the deterministic core
## knows nothing about menus. Keyboard (W/S + Enter, Esc) and pad
## (dpad + A, Start) navigation.

enum Mode { HIDDEN, TITLE, PAUSE }

const BTN := Vector2(190, 36)

var mode: int = Mode.TITLE
var sel := 0
var main: Node2D
var _confirm := -1   # index of a destructive item awaiting a 2nd press


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int) -> void:
	mode = m
	sel = 0
	_confirm = -1
	queue_redraw()


func _bus_off(name: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(name))


func _items() -> Array:
	if mode == Mode.TITLE:
		return ["CAMPAIGN", "ENDLESS WAR",
			"CO-OP: %s" % ("ON" if main._two_players else "OFF"), "QUIT"]
	var reduced: bool = main._motion < 0.5
	return ["RESUME",
		"SFX: %s" % ("OFF" if _bus_off("SFX") else "ON"),
		"MUSIC: %s" % ("OFF" if _bus_off("Music") else "ON"),
		"REDUCE MOTION: %s" % ("ON" if reduced else "OFF"), "RESTART", "TITLE SCREEN"]


# Pause-menu indices that discard the run and need a confirm press.
func _is_destructive(i: int) -> bool:
	if mode == Mode.TITLE:
		return i == 3   # QUIT
	return i == 4 or i == 5   # RESTART / TITLE SCREEN


func _unhandled_input(ev: InputEvent) -> void:
	var move := 0
	var act := false
	var back := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_W, KEY_UP: move = -1
			KEY_S, KEY_DOWN: move = 1
			KEY_ENTER, KEY_SPACE: act = true
			KEY_ESCAPE: back = true
	elif ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_DPAD_UP: move = -1
			JOY_BUTTON_DPAD_DOWN: move = 1
			JOY_BUTTON_A: act = true
			JOY_BUTTON_START: back = true

	if mode == Mode.HIDDEN:
		if back:
			open(Mode.PAUSE)
			main._sfx.play("tank_board", -8.0)
		return
	if move != 0:
		sel = wrapi(sel + move, 0, _items().size())
		_confirm = -1
		main._sfx.play("pickup", -14.0, 1.3)
	elif act:
		# Destructive items need a second press (mis-press guard on a run).
		if _is_destructive(sel) and _confirm != sel:
			_confirm = sel
			main._sfx.play("deny", -8.0)
		else:
			_confirm = -1
			_activate()
	elif back and mode == Mode.PAUSE:
		mode = Mode.HIDDEN
	queue_redraw()


func _toggle_bus(name: String) -> void:
	var b := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(b, not AudioServer.is_bus_mute(b))


func _activate() -> void:
	main._sfx.play("buy", -8.0)
	if mode == Mode.TITLE:
		match sel:
			0: main.start_game(false)
			1: main.start_game(true)
			2: main._two_players = not main._two_players
			3: get_tree().quit()
	else:
		match sel:
			0: mode = Mode.HIDDEN
			1: _toggle_bus("SFX")
			2: _toggle_bus("Music")
			3: main._motion = 0.0 if main._motion >= 0.5 else 1.0
			4:
				main._reset()
				mode = Mode.HIDDEN
			5:
				main._endless = false   # attract showcases the campaign
				main._reset()
				open(Mode.TITLE)


func _draw() -> void:
	if mode == Mode.HIDDEN:
		return
	draw_rect(Rect2(0, 0, 640, 360),
		Color(0.02, 0.05, 0.02, 0.42 if mode == Mode.TITLE else 0.6))
	if mode == Mode.TITLE:
		_center_text("PROJECT IKARI", 88, 34, Color(1.0, 0.85, 0.3))
		_center_text("ONE HIT. ONE WAR CHEST. NO MERCY.", 112, 10, Color(0.85, 0.9, 0.8, 0.85))
		if main.best_score > 0:
			_center_text("BEST — SCORE %d · WAVE %d · %dm" % [main.best_score,
				main.best_wave, main.best_dist], 132, 9, Color(1.0, 0.92, 0.55, 0.85))
	else:
		_center_text("PAUSED", 78, 22, Color(0.95, 0.95, 0.85))
		# Pause doubles as a status check — the run so far.
		if main.sim != null:
			var s: SimWorld = main.sim
			var opened := 0
			for g in s.gates:
				if g["open"]:
					opened += 1
			var line := "WAVE %d" % s.wave if s.mode == "endless" \
				else "SECTOR %d/5  ·  %dm" % [mini(opened + 1, 5), -Fixed.to_int(s.camera_top) / 10]
			_center_text("SCORE %d  ·  CHEST %d  ·  %s" % [s.score, s.war_chest, line],
				100, 10, Color(0.8, 0.85, 0.72))
	var items := _items()
	# Compress spacing so the 6-item pause menu fits the 360px screen.
	var top := 120.0 if mode == Mode.PAUSE else 150.0
	var gap := 34.0 if items.size() > 4 else 46.0
	for k in items.size():
		var r := Rect2(Vector2(320 - BTN.x / 2.0, top + k * gap), BTN)
		var selected := k == sel
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		draw_texture_rect(Art.tex("ui_menu_button"), r, false,
			Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8))
		if selected:
			draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false,
				Color(1.0, 0.9, 0.4, 0.95))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		var label: String = items[k]
		if _confirm == k:
			label = "PRESS AGAIN TO CONFIRM"
			col = Color(1.0, 0.5, 0.4)
		_center_text(label, r.position.y + gap / 2.0 + 4.0, 11, col)
	if mode == Mode.TITLE:
		_center_text("WASD MOVE · ARROWS AIM · SPACE FIRE · SHIFT GRENADE · C ROLL", 332, 8,
			Color(0.75, 0.8, 0.7, 0.75))
		_center_text("F INTERACT · E REVIVE · Q SUPPLY WHEEL · ENTER SELECT", 344, 8,
			Color(0.75, 0.8, 0.7, 0.6))


func _center_text(txt: String, y: float, size: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, Vector2(320 - w / 2.0 + 1, y + 1), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(320 - w / 2.0, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
