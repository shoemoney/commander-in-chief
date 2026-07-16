class_name GameMenu
extends Control
## Title + pause overlay (Modern Menus sprites). Lives on the HUD CanvasLayer;
## while visible, main.gd simply doesn't step the sim — the deterministic core
## knows nothing about menus. Keyboard (W/S + Enter, Esc) and pad
## (dpad + A, Start) navigation.

enum Mode { HIDDEN, TITLE, PAUSE, HALL, HOWTO }

const BTN := Vector2(190, 36)

var mode: int = Mode.TITLE
var sel := 0
var main: Node2D
var _confirm := -1   # index of a destructive item awaiting a 2nd press
var _hall_filter := 0   # Hall of Fame view: 0 = ALL, 1 = CAMPAIGN, 2 = ENDLESS
var _sel_y := -1.0      # glided highlight y — the cursor slides between rows
var _sel_target := -1.0 # where the glide is headed (set by _draw's layout pass)
var _open_t := 0.0      # menu-open settle envelope (backdrop fade + row drop-in)
# Analog-stick nav latches — PER AXIS, so a diagonal push can't wedge the other
# axis, and a stick resting in the 0.45–0.55 deadband can't lock nav forever.
var _stick_x := 0       # -1/1 while pushed past 0.55, re-arms below 0.45
var _stick_y := 0
var _stick_rep := 0.0   # countdown to the next held-stick auto-repeat step
var _nav_frame := -1    # frame stamp: one stick nav per frame (diagonal guard)
var _confirm_t := 0.0   # armed destructive row disarms when this runs out
var _filter_pulse := 0.0   # hall filter tab flash on change


func _ready() -> void:
	# Pad yanked mid-run = pause. The sim only steps while no menu is visible,
	# so opening PAUSE from here is the whole fix — no main.gd surgery.
	Input.joy_connection_changed.connect(_on_joy_changed)


func _on_joy_changed(_device: int, connected: bool) -> void:
	if not connected and mode == Mode.HIDDEN and main != null and main.sim != null:
		open(Mode.PAUSE)


func _process(delta: float) -> void:
	if mode != Mode.HIDDEN:
		# Armed RESTART/TITLE/QUIT rows disarm after 2.5 s — a stale confirm
		# must not end a run on a press that lands minutes later.
		if _confirm >= 0:
			_confirm_t -= delta
			if _confirm_t <= 0.0:
				_confirm = -1
		_filter_pulse = maxf(0.0, _filter_pulse - delta * 3.0)
		# Held-stick auto-repeat: first step fired in _unhandled_input, then
		# after 0.35 s held it steps every 0.12 s (framerate-independent).
		if _stick_x != 0 or _stick_y != 0:
			_stick_rep -= delta
			if _stick_rep <= 0.0:
				_stick_rep = 0.12
				_nav(_stick_y, _stick_x)
		# Exp-decay easing: framerate-independent (per-frame lerpf ran ~2.4x
		# faster on a 144Hz display). Reduce-motion snaps both instantly.
		if main._motion < 0.5:
			_open_t = 1.0
			if _sel_target >= 0.0:
				_sel_y = _sel_target
		else:
			_open_t = lerpf(_open_t, 1.0, 1.0 - exp(-20.0 * delta))
			if _sel_target >= 0.0:
				_sel_y = lerpf(_sel_y, _sel_target, 1.0 - exp(-22.0 * delta))
		queue_redraw()   # pulse + glide + open-settle animate every frame while open


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int) -> void:
	mode = m
	sel = 0
	_confirm = -1
	_sel_y = -1.0   # highlight starts on the new menu's first row, no cross-menu glide
	_sel_target = -1.0
	_open_t = 0.0   # replay the open settle
	queue_redraw()


func _bus_off(name: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(name))


func _menu_items() -> Array[Dictionary]:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return [{"id": "back", "label": "BACK", "destructive": false}]
	if mode == Mode.TITLE:
		var titems: Array[Dictionary] = [
			{"id": "campaign", "label": "CAMPAIGN", "destructive": false},
			{"id": "endless", "label": "ENDLESS WAR", "destructive": false},
			{"id": "daily", "label": "DAILY RUN", "destructive": false},
			{"id": "paste_seed", "label": "CHALLENGE SEED", "destructive": false},
			{"id": "coop", "label": "CO-OP: %s" % ("ON" if main._two_players else "OFF"), "destructive": false},
			{"id": "hard", "label": "NG+ HARD: %s" % ("ON" if main._hard else "OFF"), "destructive": false},
			{"id": "hall", "label": "HALL OF FAME", "destructive": false},
			{"id": "howto", "label": "HOW TO PLAY", "destructive": false},
		]
		if FileAccess.file_exists("user://last_run.replay"):
			titems.append({"id": "watch", "label": "WATCH LAST RUN", "destructive": false})
		titems.append({"id": "quit", "label": "QUIT", "destructive": true})
		return titems
	var reduced: bool = main._motion < 0.5
	var cb: bool = main.colorblind
	return [
		{"id": "resume", "label": "RESUME", "destructive": false},
		{"id": "sfx", "label": "SFX: %s" % ("OFF" if _bus_off("SFX") else "ON"), "destructive": false},
		{"id": "music", "label": "MUSIC: %s" % ("OFF" if _bus_off("Music") else "ON"), "destructive": false},
		{"id": "motion", "label": "REDUCE MOTION: %s" % ("ON" if reduced else "OFF"), "destructive": false},
		{"id": "colorblind", "label": "COLORBLIND: %s" % ("ON" if cb else "OFF"), "destructive": false},
		{"id": "rumble", "label": "RUMBLE: %s" % ("ON" if main._rumble_on else "OFF"), "destructive": false},
		{"id": "assist", "label": "ASSIST (2-HIT): %s" % ("ON" if main._assist else "OFF"), "destructive": false},
		{"id": "restart", "label": "RESTART", "destructive": true},
		{"id": "title", "label": "TITLE SCREEN", "destructive": true},
	]


func _items() -> Array[String]:
	var out: Array[String] = []
	for item in _menu_items():
		out.append(item["label"])
	return out


# Pause-menu indices that discard the run and need a confirm press.
func _is_destructive(i: int) -> bool:
	return _menu_items()[i]["destructive"]


# Row id → Modern Menus icon key. Only clean matches — no icon beats a
# stretched metaphor. Sound toggles reflect their live bus state.
func _row_icon(id: String) -> String:
	match id:
		"resume", "campaign": return "mi_play"
		"hall": return "mi_trophy"
		"howto": return "mi_book"
		"sfx": return "mi_snd_off" if _bus_off("SFX") else "mi_snd_on"
		"music": return "mi_mus_off" if _bus_off("Music") else "mi_mus_on"
	return ""


func _unhandled_input(ev: InputEvent) -> void:
	var move := 0
	var hmove := 0
	var act := false
	var back := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_W, KEY_UP: move = -1
			KEY_S, KEY_DOWN: move = 1
			KEY_A, KEY_LEFT: hmove = -1
			KEY_D, KEY_RIGHT: hmove = 1
			KEY_ENTER, KEY_SPACE: act = true
			KEY_ESCAPE: back = true
	elif ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_DPAD_UP: move = -1
			JOY_BUTTON_DPAD_DOWN: move = 1
			JOY_BUTTON_DPAD_LEFT: hmove = -1
			JOY_BUTTON_DPAD_RIGHT: hmove = 1
			JOY_BUTTON_A: act = true
			JOY_BUTTON_B:
				# Console convention: B = back/cancel — but ONLY inside menus.
				# In gameplay B is ROLL; letting it through here made every dodge
				# open the pause menu (mode==HIDDEN + back → PAUSE).
				if mode != Mode.HIDDEN:
					back = true
			JOY_BUTTON_START:
				# START confirms on the title (redeploy muscle memory from the
				# debrief); elsewhere it stays the pause/back toggle.
				if mode == Mode.TITLE:
					act = true
				else:
					back = true
	elif ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_LEFT_Y or ev.axis == JOY_AXIS_LEFT_X):
		# Analog-stick menu nav: fire ONE step when the axis crosses 0.55, re-arm
		# below 0.45 (a stick resting at 0.3–0.55 used to lock nav). Latch is
		# per-axis; the frame stamp keeps a diagonal from firing both axes at once.
		var v: float = ev.axis_value
		var dir := 1 if v > 0.55 else (-1 if v < -0.55 else 0)
		var vertical: bool = ev.axis == JOY_AXIS_LEFT_Y
		var latch := _stick_y if vertical else _stick_x
		if absf(v) < 0.45:
			latch = 0
		elif dir != 0 and latch == 0:
			latch = dir
			_stick_rep = 0.35
			if Engine.get_process_frames() != _nav_frame:
				_nav_frame = Engine.get_process_frames()
				if vertical:
					move = dir
				else:
					hmove = dir
		if vertical:
			_stick_y = latch
		else:
			_stick_x = latch

	if mode == Mode.HIDDEN:
		if back:
			open(Mode.PAUSE)
			main._sfx.play("tank_board", -8.0)
		return
	# Mouse drives menus too: hover selects, LMB activates — mouse-aim players
	# shouldn't have to switch devices to press RESUME. Same geometry as _draw.
	if ev is InputEventMouseMotion:
		# Only REAL motion selects — a parked mouse must not fight pad/kb nav.
		if ev.relative.length() > 2.0:
			var hrow := _row_at(ev.position)
			if hrow >= 0 and hrow != sel:
				sel = hrow
				_confirm = -1
				queue_redraw()
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var crow := _row_at(ev.position)
			if crow >= 0:
				sel = crow
				_press()
				get_viewport().set_input_as_handled()
				queue_redraw()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_nav(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1, 0)
			get_viewport().set_input_as_handled()
		return
	if move != 0 or hmove != 0:
		_nav(move, hmove)
	elif act:
		_press()
	elif back and mode == Mode.PAUSE:
		mode = Mode.HIDDEN
	elif back and (mode == Mode.HALL or mode == Mode.HOWTO):
		open(Mode.TITLE)
	if move != 0 or hmove != 0 or act or back:
		accept_event()
	queue_redraw()


# One nav step — shared by key/dpad/stick presses, the held-stick auto-repeat,
# and the mouse wheel, so every device gets identical wrap/snap/sfx behavior.
func _nav(move: int, hmove: int) -> void:
	# Hall of Fame: left/right cycles the mode filter (ALL / CAMPAIGN / ENDLESS).
	if mode == Mode.HALL and hmove != 0:
		_hall_filter = wrapi(_hall_filter + hmove, 0, 3)
		_filter_pulse = 1.0
		main._sfx.play("pickup", -14.0, 1.3)
		queue_redraw()
		return
	if move == 0:
		return
	var prev := sel
	sel = wrapi(sel + move, 0, _items().size())
	if absi(sel - prev) > 1:
		_sel_y = -1.0   # wrap: snap to the far end instead of gliding the whole list
	_confirm = -1
	main._sfx.play("pickup", -14.0, 1.3)
	queue_redraw()


func _press() -> void:
	# Destructive items need a second press (mis-press guard on a run).
	if _is_destructive(sel) and _confirm != sel:
		_confirm = sel
		_confirm_t = 2.5   # auto-disarm window (decremented in _process)
		main._sfx.play("deny", -8.0)
	else:
		_confirm = -1
		_activate()


func _row_geometry() -> Dictionary:
	# Single source of truth for the button column layout — _draw and the mouse
	# hit-test must agree or hover selects the wrong row.
	var n := _items().size()
	var many := n > 4
	var top := 118.0 if mode == Mode.PAUSE else (150.0 if not many else 156.0)
	var gap := minf(30.0 if many else 46.0, (310.0 - top) / maxf(1.0, float(n - 1)))
	# Open-settle drop-in offset lives HERE (after the gap math it must not
	# perturb) so a click during the settle hits the same rows _draw renders.
	if main._motion >= 0.5:
		top += (1.0 - _open_t) * 12.0
	return {"top": top, "gap": gap, "bh": minf(BTN.y, gap - 3.0), "n": n}


func _row_at(p: Vector2) -> int:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		var r := Rect2(Vector2(320 - BTN.x / 2.0, 316), BTN * Vector2(1, 0.7))
		return 0 if r.has_point(p) else -1
	if absf(p.x - 320.0) > BTN.x / 2.0:
		return -1
	var g := _row_geometry()
	for k in int(g["n"]):
		var ry: float = float(g["top"]) + float(k) * float(g["gap"])
		if p.y >= ry and p.y <= ry + float(g["bh"]):
			return k
	return -1


func _toggle_bus(name: String) -> void:
	var b := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(b, not AudioServer.is_bus_mute(b))


func _activate() -> void:
	main._sfx.play("buy", -8.0)
	if mode == Mode.HALL or mode == Mode.HOWTO:
		open(Mode.TITLE)
		return
	var id: String = _menu_items()[sel]["id"]
	if mode == Mode.TITLE:
		match id:
			"campaign": main.start_game(false)
			"endless": main.start_game(true)
			"daily": main.start_daily()
			"watch": main.start_watch()
			"paste_seed": main.start_seed_from_clipboard()
			"coop": main._two_players = not main._two_players
			"hard": main._hard = not main._hard
			"hall": open(Mode.HALL)
			"howto": open(Mode.HOWTO)
			"quit": get_tree().quit()
	else:
		match id:
			"resume": mode = Mode.HIDDEN
			"sfx":
				_toggle_bus("SFX")
				main._save_settings()
			"music":
				_toggle_bus("Music")
				main._save_settings()
			"motion":
				main._motion = 0.0 if main._motion >= 0.5 else 1.0
				main._save_settings()
			"colorblind":
				main.colorblind = not main.colorblind
				main._save_settings()
			"rumble":
				main._rumble_on = not main._rumble_on
				main._save_settings()
			"assist":
				main._assist = not main._assist
				main._save_settings()
			"restart":
				main._reset()
				mode = Mode.HIDDEN
			"title":
				main._endless = false   # attract showcases the campaign
				main._reset()
				open(Mode.TITLE)


func _draw() -> void:
	if mode == Mode.HIDDEN:
		return
	draw_rect(Rect2(0, 0, 640, 360),
		Color(0.02, 0.05, 0.02, (0.55 if mode == Mode.TITLE else 0.6) * _open_t))   # scrim ≥0.55: 8px text over a LIVE firefight; fades in over the open settle
	if mode == Mode.HALL or mode == Mode.HOWTO:
		# Plate the bare text on the Apocalypse frame, debrief-style (underlay
		# darkens the well, frame carries the chrome).
		var fr := Rect2(20, 8, 600, 344)
		draw_texture_rect(Art.tex("ui_frame_lrg_under"), fr, false, Color(1, 1, 1, 0.9 * _open_t))
		draw_texture_rect(Art.tex("ui_frame_lrg"), fr, false, Color(0.85, 0.9, 0.75, _open_t))
		if mode == Mode.HALL:
			_draw_hall()
		else:
			_draw_howto()
		_draw_back_button()
		return
	if mode == Mode.TITLE:
		_center_text("PROJECT IKARI", 88, 34, Color(1.0, 0.85, 0.3))
		_center_text("ONE HIT. ONE WAR CHEST. NO MERCY.", 112, 10, Color(0.85, 0.9, 0.8, 0.85))
		# Read order: title → tagline → one BRIGHT record line → menu. CAREER stays
		# a dim whisper at 145 (clears the 156 first-row top since the c1 layout fix).
		if main.best_score > 0:
			_center_text("BEST — SCORE %d · WAVE %d · %dm" % [main.best_score,
				main.best_wave, main.best_dist], 132, 9, Color(1.0, 0.92, 0.55, 1.0))
		if main._life_runs > 0:
			var wpct: int = main._life_wins * 100 / main._life_runs
			_center_text("CAREER — %d RUNS · %d KILLS · %d%% WON" % [main._life_runs,
				main._life_kills, wpct], 145, 8, Color(0.6, 0.72, 0.62, 0.7))
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
			if main._current_seed > 0:
				_center_text("RUN #%d" % main._current_seed, 114, 8, Color(0.6, 0.66, 0.56, 0.75))
	var mitems := _menu_items()   # dicts: label + destructive flag for pre-press tinting
	var items := _items()
	# Fit-to-height layout via the shared helper (the mouse hit-test reads the
	# SAME numbers — drift here means hover selects the wrong row).
	var g := _row_geometry()
	var gap: float = g["gap"]
	var bh: float = g["bh"]
	# Open settle: rows drop the last 12px into place as the scrim fades in
	# (offset applied inside _row_geometry so the mouse hit-test tracks it).
	var top: float = g["top"]
	for k in items.size():
		var r := Rect2(Vector2(320 - BTN.x / 2.0, top + k * gap), Vector2(BTN.x, bh))
		var selected := k == sel
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		draw_texture_rect(Art.tex("ui_menu_button"), r, false,
			Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8))
		# Modern Menus ortho icon where a row has a clean match (toggles swap
		# by live state) — rows without one just stay text.
		var icon := _row_icon(mitems[k]["id"])
		if icon != "":
			var isz := minf(bh - 6.0, 16.0)
			draw_texture_rect(Art.tex(icon), Rect2(Vector2(r.position.x + 9.0,
				r.position.y + (bh - isz) / 2.0), Vector2(isz, isz)), false,
				Color(1, 1, 1, 1.0 if selected else 0.7))
		if selected:
			# Breathing selection glow that GLIDES between rows instead of teleporting
			# (the ease itself runs framerate-independent in _process). Stilled under
			# REDUCE MOTION — the pause menu is where a motion-sensitive player lives.
			var ty := top + k * gap
			_sel_target = ty
			if _sel_y < 0.0 or main._motion < 0.5:
				_sel_y = ty
			var gr := Rect2(Vector2(320 - BTN.x / 2.0, _sel_y), Vector2(BTN.x, bh))
			var mp := 0.0 if main._motion < 0.5 else Art.pulse(0.2)
			draw_texture_rect(Art.tex("ui_menu_button_sel"), gr.grow(3.0 + mp * 1.5), false,
				Color(1.0, 0.9, 0.4, 0.7 + mp * 0.3))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		# Destructive rows carry a warm tint BEFORE the first press — the warning
		# used to appear only after you'd already pressed once.
		if k < mitems.size() and mitems[k].get("destructive", false):
			col = Color(1.0, 0.78, 0.65) if selected else Color(0.9, 0.7, 0.6)
		var label: String = items[k]
		if k < mitems.size() and mitems[k].get("destructive", false):
			label += "  !"   # non-color destructive cue (hue alone fails protan players)
		if _confirm == k:
			label = "PRESS AGAIN TO CONFIRM"
			col = Color(1.0, 0.5, 0.4)
		# Center on the actual cell, not the gap (the two drifted apart in the
		# spacious few-items layout).
		_center_text(label, r.position.y + bh / 2.0 + 4.0, 11, col)
	if mode == Mode.TITLE:
		# Legend adapts to the last-used device and draws the REAL prompt art
		# (stick/trigger/mouse glyphs from the registry) beside each verb —
		# "RT"/"LMB" as text made every new player parse an acronym first.
		# Near-opaque dark plate: 8px text straight on the live attract
		# firefight loses to bright terrain and particles no matter the alpha.
		draw_rect(Rect2(0, 322, 640, 34), Color(0.03, 0.05, 0.03, 0.55))
		var row1: Array
		if Art.use_pad:
			row1 = [{"tex": "glyph_stick_l", "label": "MOVE"},
				{"tex": "glyph_stick_r", "label": "AIM"},
				{"tex": "glyph_rt", "label": "FIRE"},
				{"tex": "glyph_lb", "label": "GRENADE"},
				{"act": "roll", "label": "ROLL"}]
		else:
			row1 = [{"stamp": "WASD", "label": "MOVE"},
				{"label": "MOUSE AIM"},
				{"tex": "glyph_mouse_l", "label": "FIRE"},
				{"tex": "glyph_mouse_r", "label": "GRENADE"},
				{"act": "roll", "label": "ROLL"}]
		var row2: Array = [{"act": "interact", "label": "INTERACT"},
			{"act": "revive", "label": "REVIVE"},
			{"act": "wheel", "label": "SUPPLY WHEEL"},
			{"tex": Art.glyph_key("confirm"), "label": "SELECT"}]
		_legend_row(row1, 330.0, 1.0)
		_legend_row(row2, 346.0, 0.9)


func _draw_back_button() -> void:
	var r := Rect2(Vector2(320 - BTN.x / 2.0, 316), BTN * Vector2(1, 0.7))
	draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
	draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false, Color(1.0, 0.9, 0.4, 0.95))
	_center_text("BACK", r.position.y + 16.0, 11, Color(1.0, 0.95, 0.75))


func _draw_hall() -> void:
	var names := ["ALL", "CAMPAIGN", "ENDLESS"]
	_center_text("HALL OF FAME", 38, 22, Color(1.0, 0.85, 0.3))
	# Persistent filter tab row — the old single "◄ NAME ►" line hid the other
	# two choices, so nobody knew left/right cycled anything. Selected tab is
	# underlined and flashes briefly on change (_filter_pulse).
	var f := Art.font()
	var tw: Array[float] = []
	var total := -22.0
	for n in names:
		var w := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		tw.append(w)
		total += w + 22.0
	var x := 320.0 - total / 2.0
	for i in names.size():
		var on := i == _hall_filter
		var col := Color(1.0, 0.92, 0.55) if on else Color(0.6, 0.66, 0.56, 0.8)
		if on and _filter_pulse > 0.0:
			col = col.lightened(_filter_pulse * 0.45)
		Art.text(self, names[i], Vector2(x, 66), 10, col)
		if on:
			draw_rect(Rect2(x - 2.0, 70.0, tw[i] + 4.0, 2.0),
				Color(1.0, 0.9, 0.4, 0.9 + _filter_pulse * 0.1))
		x += tw[i] + 22.0
	# The cycle affordance itself: dpad art on pad, arrow text on keyboard.
	if Art.use_pad:
		var t := Art.tex("glyph_dpad_lr")
		var gw := 13.0 * float(t.get_width()) / float(t.get_height())
		draw_texture_rect(t, Rect2(320.0 - total / 2.0 - gw - 12.0, 56.0, gw, 13.0), false)
	else:
		Art.text(self, "◄", Vector2(320.0 - total / 2.0 - 18.0, 66), 10, Color(0.7, 0.75, 0.6))
		Art.text(self, "►", Vector2(320.0 + total / 2.0 + 8.0, 66), 10, Color(0.7, 0.75, 0.6))
	# Filter to the selected mode (ALL shows everything), keeping score order.
	var rows: Array = []
	for run in main.hall:
		if _hall_filter == 1 and run["mode"] == "endless":
			continue
		if _hall_filter == 2 and run["mode"] != "endless":
			continue
		rows.append(run)
	if rows.is_empty():
		_center_text("NO %s RUNS YET — GO EARN YOUR PLACE" % names[_hall_filter], 170, 11,
			Color(0.8, 0.84, 0.74))
		return
	# Fixed x offsets per column — Art.font() is proportional, so
	# space-padded strings stagger; each column draws at its own x instead.
	var col_x := [112, 148, 226, 306, 396]
	var headers := ["#", "SCORE", "MODE", "REACHED", "STREAK"]
	for c in headers.size():
		if c == 1:
			var hw := Art.font().get_string_size(headers[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			Art.text(self, headers[c], Vector2(214.0 - hw, 92), 10, Color(0.7, 0.75, 0.6))
		else:
			Art.text(self, headers[c], Vector2(col_x[c], 92), 10, Color(0.7, 0.75, 0.6))
	for i in mini(rows.size(), 8):
		var run: Dictionary = rows[i]
		var mode_s: String = "ENDLESS" if run["mode"] == "endless" else "CAMPAIGN"
		var reached: String = "WAVE %d" % run["wave"] if run["mode"] == "endless" \
			else ("VICTORY" if run.get("won", false) else "SECTOR %d" % run["sector"])
		var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.9, 0.82)
		var tag: String = "  *DAILY" if run.get("daily", false) else ""
		if run.get("assist", false):
			tag += "  *ASSIST"   # 2-hit runs compete on the same board — say so
		var y := 112 + i * 24
		var cells := [str(i + 1), str(run["score"]), mode_s, reached, "x%d%s" % [run["streak"], tag]]
		for c in cells.size():
			if c == 1:
				# Right-aligned numerals: a 6-digit endless score can't crowd MODE.
				var sw := Art.font().get_string_size(cells[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				Art.text(self, cells[c], Vector2(214.0 - sw, y), 11, col)
			else:
				Art.text(self, cells[c], Vector2(col_x[c], y), 11, col)


func _draw_howto() -> void:
	_center_text("HOW TO PLAY", 34, 22, Color(1.0, 0.85, 0.3))
	var hold_pre := "pays to REVIVE you or BUY supplies (hold"
	var lines := [
		["ONE HIT AND YOU DROP. The War Chest — shared coin from kills —", Color(1.0, 0.9, 0.6)],
		[hold_pre, Color(0.85, 0.9, 0.8)],
		["", Color.WHITE],
		["GRENADES crack armor — bunkers, bosses, the Colossus. Bullets don't.", Color(0.9, 0.92, 0.8)],
		["ROLL to dodge (brief invulnerability). BOARD tanks for crush + shells.", Color(0.9, 0.92, 0.8)],
		["", Color.WHITE],
	]
	for i in lines.size():
		Art.text(self, lines[i][0], Vector2(60, 70 + i * 18), 11, lines[i][1])
	# The supply-wheel hold prompt is the DEVICE GLYPH, not a key-name string.
	var px := 60.0 + Art.font().get_string_size(hold_pre, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 9.0
	Art.draw_glyph(self, "wheel", Vector2(px, 84.0), 12.0)
	Art.text(self, "). That's the choice.", Vector2(px + 8.0, 88.0), 11, Color(0.85, 0.9, 0.8))
	# The enemy roster with live sprites.
	var roster := [["rusher", "RUSHER — charges, touch kills"],
		["elite", "ELITE — keeps range, telegraphs one shot"],
		["frogman", "FROGMAN — lurks in water, grenades only"]]
	for i in roster.size():
		var yy := 176.0 + i * 26.0
		draw_texture_rect(Art.tex(roster[i][0]), Rect2(80, yy - 10, 20, 20), false, Art.tint(roster[i][0]))
		Art.text(self, roster[i][1], Vector2(108, yy + 3), 10, Color(0.9, 0.92, 0.82))
	# Endless War fields ranged specialists (wave 3+) — teach their counters.
	Art.text(self, "ENDLESS WAR — RANGED THREATS:", Vector2(60, 258), 10, Color(1.0, 0.7, 0.4))
	var special := [
		"GRENADIER — lobs a telegraphed blast on your spot. Keep moving.",
		"SNIPER — paints a laser line, then fires. Sidestep it.",
		"GHILLIE — hidden sniper; only its laser gives it away. Close in.",
		"SAPPER — seeds mines behind it. Don't chase over its trail.",
		"SHIELD — front blocks bullets. Flank it or grenade it."]
	for i in special.size():
		Art.text(self, special[i], Vector2(72, 274 + i * 15), 10, Color(0.88, 0.9, 0.8))


func _center_text(txt: String, y: float, size: int, col: Color) -> void:
	Art.text_center(self, txt, 320.0, y, size, col)


const _LEG_H := 11.0   # legend glyph height (aspect preserved per sprite)


# Legend glyph width for a segment: "tex" = registry sprite, "stamp" = letters
# on the wide keycap, "act" = Art.draw_glyph's square prompt, none = text-only.
func _glyph_w(seg: Dictionary) -> float:
	if seg.has("act"):
		return _LEG_H
	var key: String = seg.get("tex", "glyph_key_wide" if seg.has("stamp") else "")
	if key == "":
		return 0.0
	var t := Art.tex(key)
	return _LEG_H * float(t.get_width()) / float(t.get_height())


# One centered legend line of [glyph + verb] segments; y is the glyph center.
func _legend_row(segs: Array, y: float, a: float) -> void:
	var f := Art.font()
	var total := -14.0   # segments separated by 14px; first one has no gap
	for seg in segs:
		var gw := _glyph_w(seg)
		total += gw + (3.0 if gw > 0.0 else 0.0) \
			+ f.get_string_size(seg.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 14.0
	var x := 320.0 - total / 2.0
	for seg in segs:
		var gw := _glyph_w(seg)
		if gw > 0.0:
			if seg.has("act"):
				Art.draw_glyph(self, seg["act"], Vector2(x + gw / 2.0, y), _LEG_H)
			else:
				var key: String = seg.get("tex", "glyph_key_wide")
				draw_texture_rect(Art.tex(key), Rect2(x, y - _LEG_H / 2.0, gw, _LEG_H),
					false, Color(1, 1, 1, a))
				if seg.has("stamp"):
					var st: String = seg["stamp"]
					var sw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
					draw_string(f, Vector2(x + (gw - sw) / 2.0, y + 2.0), st,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.15, 0.16, 0.12, a))
			x += gw + 3.0
		var label: String = seg.get("label", "")
		Art.text(self, label, Vector2(x, y + 3.0), 8, Color(0.82, 0.87, 0.77, a))
		x += f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 14.0
