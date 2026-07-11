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


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int) -> void:
	mode = m
	sel = 0
	queue_redraw()


func _items() -> Array:
	if mode == Mode.TITLE:
		return ["CAMPAIGN", "ENDLESS WAR",
			"CO-OP: %s" % ("ON" if main._two_players else "OFF"), "QUIT"]
	return ["RESUME", "RESTART", "TITLE SCREEN"]


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
		main._sfx.play("pickup", -14.0, 1.3)
	elif act:
		_activate()
	elif back and mode == Mode.PAUSE:
		mode = Mode.HIDDEN
	queue_redraw()


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
			1:
				main._reset()
				mode = Mode.HIDDEN
			2:
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
	else:
		_center_text("PAUSED", 100, 24, Color(0.95, 0.95, 0.85))
	var items := _items()
	for k in items.size():
		var r := Rect2(Vector2(320 - BTN.x / 2.0, 150 + k * 46), BTN)
		var selected := k == sel
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		draw_texture_rect(Art.tex("ui_menu_button"), r, false,
			Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8))
		if selected:
			draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false,
				Color(1.0, 0.9, 0.4, 0.95))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		_center_text(items[k], r.position.y + 24.0, 12, col)
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
