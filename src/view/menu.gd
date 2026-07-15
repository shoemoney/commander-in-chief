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
var _open_t := 0.0      # menu-open settle envelope (backdrop fade + row drop-in)
var _stick_held := 0    # analog-stick nav latch: -1/1 while pushed, 0 when centered


func _process(_delta: float) -> void:
	if mode != Mode.HIDDEN:
		_open_t = lerpf(_open_t, 1.0, 0.3)
		queue_redraw()   # pulse + glide + open-settle animate every frame while open


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int) -> void:
	mode = m
	sel = 0
	_confirm = -1
	_sel_y = -1.0   # highlight starts on the new menu's first row, no cross-menu glide
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
			JOY_BUTTON_B: back = true       # console convention: B = back/cancel
			JOY_BUTTON_START: back = true
	elif ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_LEFT_Y or ev.axis == JOY_AXIS_LEFT_X):
		# Analog-stick menu nav: fire ONE step when the axis crosses the threshold,
		# re-arm when it returns to center — a held stick doesn't machine-gun.
		var v: float = ev.axis_value
		if absf(v) < 0.3:
			_stick_held = 0
		elif absf(v) > 0.55 and _stick_held == 0:
			_stick_held = 1 if v > 0.0 else -1
			if ev.axis == JOY_AXIS_LEFT_Y:
				move = _stick_held
			else:
				hmove = _stick_held

	if mode == Mode.HIDDEN:
		if back:
			open(Mode.PAUSE)
			main._sfx.play("tank_board", -8.0)
		return
	# Hall of Fame: left/right cycles the mode filter (ALL / CAMPAIGN / ENDLESS).
	if mode == Mode.HALL and hmove != 0:
		_hall_filter = wrapi(_hall_filter + hmove, 0, 3)
		main._sfx.play("pickup", -14.0, 1.3)
		queue_redraw()
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
	elif back and (mode == Mode.HALL or mode == Mode.HOWTO):
		open(Mode.TITLE)
	if move != 0 or hmove != 0 or act or back:
		accept_event()
	queue_redraw()


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
	if mode == Mode.HALL:
		_draw_hall()
		_draw_back_button()
		return
	if mode == Mode.HOWTO:
		_draw_howto()
		_draw_back_button()
		return
	if mode == Mode.TITLE:
		_center_text("PROJECT IKARI", 88, 34, Color(1.0, 0.85, 0.3))
		_center_text("ONE HIT. ONE WAR CHEST. NO MERCY.", 112, 10, Color(0.85, 0.9, 0.8, 0.85))
		if main.best_score > 0:
			_center_text("BEST — SCORE %d · WAVE %d · %dm" % [main.best_score,
				main.best_wave, main.best_dist], 132, 9, Color(1.0, 0.92, 0.55, 0.85))
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
	var items := _items()
	# Fit-to-height: gap derives from the item count so long lists (title = up to
	# 10 rows, pause = 9) always land above the y=332 legend instead of running
	# off the 360px screen — the old fixed gap drew PAUSE's last row at y=358.
	var many: bool = items.size() > 4
	var top := 118.0 if mode == Mode.PAUSE else (150.0 if not many else 156.0)
	# Open settle: rows drop the last 12px into place as the scrim fades in
	# (skipped under reduce-motion — the fade alone still smooths the cut).
	if main._motion >= 0.5:
		top += (1.0 - _open_t) * 12.0
	# 310 budget = last row TOP; its ~18px cell bottom then clears the y=332 legend.
	var gap := minf(30.0 if many else 46.0, (310.0 - top) / maxf(1.0, float(items.size() - 1)))
	# Cell height tracks the gap so metal frames stop overprinting each other.
	var bh := minf(BTN.y, gap - 3.0)
	for k in items.size():
		var r := Rect2(Vector2(320 - BTN.x / 2.0, top + k * gap), Vector2(BTN.x, bh))
		var selected := k == sel
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		draw_texture_rect(Art.tex("ui_menu_button"), r, false,
			Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8))
		if selected:
			# Breathing selection glow that GLIDES between rows instead of teleporting.
			# Both are stilled under REDUCE MOTION — the pause menu is where a
			# motion-sensitive player spends the most time.
			var ty := top + k * gap
			if _sel_y < 0.0 or main._motion < 0.5:
				_sel_y = ty
			_sel_y = lerpf(_sel_y, ty, 0.35)
			var gr := Rect2(Vector2(320 - BTN.x / 2.0, _sel_y), Vector2(BTN.x, bh))
			var mp := 0.0 if main._motion < 0.5 else Art.pulse(0.2)
			draw_texture_rect(Art.tex("ui_menu_button_sel"), gr.grow(3.0 + mp * 1.5), false,
				Color(1.0, 0.9, 0.4, 0.7 + mp * 0.3))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		var label: String = items[k]
		if _confirm == k:
			label = "PRESS AGAIN TO CONFIRM"
			col = Color(1.0, 0.5, 0.4)
		# Center on the actual cell, not the gap (the two drifted apart in the
		# spacious few-items layout).
		_center_text(label, r.position.y + bh / 2.0 + 4.0, 11, col)
	if mode == Mode.TITLE:
		# Legend adapts to the last-used device (was hardcoded keyboard, wrong
		# for the pad-driven 2P audience).
		# Near-opaque: 8px text over the live attract firefight was ~0.6 alpha —
		# well under readable contrast on sunlit grass.
		if Art.use_pad:
			_center_text("LS MOVE · RS AIM · RT FIRE · L1 GRENADE · B ROLL", 332, 8,
				Color(0.82, 0.87, 0.77, 1.0))
			_center_text("X INTERACT · Y REVIVE · BACK SUPPLY WHEEL · A SELECT", 344, 8,
				Color(0.82, 0.87, 0.77, 0.9))
		else:
			_center_text("WASD MOVE · MOUSE/ARROWS AIM · LMB/SPACE FIRE · RMB/SHIFT GRENADE · C ROLL", 332, 8,
				Color(0.82, 0.87, 0.77, 1.0))
			_center_text("F INTERACT · E REVIVE · Q SUPPLY WHEEL · ENTER SELECT", 344, 8,
				Color(0.82, 0.87, 0.77, 0.9))


func _draw_back_button() -> void:
	var r := Rect2(Vector2(320 - BTN.x / 2.0, 316), BTN * Vector2(1, 0.7))
	draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
	draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false, Color(1.0, 0.9, 0.4, 0.95))
	_center_text("BACK", r.position.y + 16.0, 11, Color(1.0, 0.95, 0.75))


func _draw_hall() -> void:
	var names := ["ALL", "CAMPAIGN", "ENDLESS"]
	_center_text("HALL OF FAME", 38, 22, Color(1.0, 0.85, 0.3))
	_center_text("◄  %s  ►" % names[_hall_filter], 64, 10, Color(0.85, 0.88, 0.68))
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
	# Fixed x offsets per column — ThemeDB.fallback_font is proportional, so
	# space-padded strings stagger; each column draws at its own x instead.
	var col_x := [112, 148, 226, 306, 396]
	var headers := ["#", "SCORE", "MODE", "REACHED", "STREAK"]
	for c in headers.size():
		Art.text(self, headers[c], Vector2(col_x[c], 92), 10, Color(0.7, 0.75, 0.6))
	for i in mini(rows.size(), 8):
		var run: Dictionary = rows[i]
		var mode_s: String = "ENDLESS" if run["mode"] == "endless" else "CAMPAIGN"
		var reached: String = "WAVE %d" % run["wave"] if run["mode"] == "endless" \
			else ("VICTORY" if run.get("won", false) else "SECTOR %d" % run["sector"])
		var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.9, 0.82)
		var tag: String = "  *DAILY" if run.get("daily", false) else ""
		var y := 112 + i * 24
		var cells := [str(i + 1), str(run["score"]), mode_s, reached, "x%d%s" % [run["streak"], tag]]
		for c in cells.size():
			Art.text(self, cells[c], Vector2(col_x[c], y), 11, col)


func _draw_howto() -> void:
	_center_text("HOW TO PLAY", 34, 22, Color(1.0, 0.85, 0.3))
	var lines := [
		["ONE HIT AND YOU DROP. The War Chest — shared coin from kills —", Color(1.0, 0.9, 0.6)],
		["pays to REVIVE you or BUY supplies (hold Q). That's the choice.", Color(0.85, 0.9, 0.8)],
		["", Color.WHITE],
		["GRENADES crack armor — bunkers, bosses, the Colossus. Bullets don't.", Color(0.9, 0.92, 0.8)],
		["ROLL to dodge (brief invulnerability). BOARD tanks for crush + shells.", Color(0.9, 0.92, 0.8)],
		["", Color.WHITE],
	]
	for i in lines.size():
		Art.text(self, lines[i][0], Vector2(60, 70 + i * 18), 11, lines[i][1])
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
		"SHIELD — front blocks bullets. Flank it or grenade it."]
	for i in special.size():
		Art.text(self, special[i], Vector2(72, 274 + i * 15), 10, Color(0.88, 0.9, 0.8))


func _center_text(txt: String, y: float, size: int, col: Color) -> void:
	Art.text_center(self, txt, 320.0, y, size, col)
