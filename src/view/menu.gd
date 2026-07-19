class_name GameMenu
extends Control
## Title + pause overlay (Modern Menus sprites). Lives on the HUD CanvasLayer;
## while visible, main.gd simply doesn't step the sim — the deterministic core
## knows nothing about menus. Keyboard (W/S + Enter, Esc) and pad
## (dpad + A, Start) navigation.

enum Mode { HIDDEN, TITLE, PAUSE, HALL, HOWTO, OPTS }

# 222 = 30px icon gutter + the widest pause label ("ASSIST (2-HIT): OFF") at
# 11px pixel-font + padding — 190 ellipsized toggle VALUES once the gutter landed.
const BTN := Vector2(222, 36)

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
var _key_move := 0      # held up/down key direction (hold-repeat, mirrors stick)
var _key_rep := 0.0     # countdown to the next held-key auto-repeat step
var _lockout := 0.0     # post-disconnect confirm lockout (flailing pad guard)
var _has_replay := false   # user://last_run.replay existence, sampled in open()
var _tab_hover := -1    # hall filter tab under the mouse (-1 = none) — hover cue parity with rows

# Row ids that flip on left/right without a confirm press.
const _TOGGLES := ["coop", "hard", "sfx", "music", "motion", "colorblind", "rumble", "assist"]


func _ready() -> void:
	# Pad yanked mid-run = pause. The sim only steps while no menu is visible,
	# so opening PAUSE from here is the whole fix — no main.gd surgery.
	Input.joy_connection_changed.connect(_on_joy_changed)


func _on_joy_changed(_device: int, connected: bool) -> void:
	if connected:
		return
	# A pad yanked while the stick is deflected emits no further motion events,
	# so the <0.45 re-arm can never fire — clear the latches or _process
	# auto-repeats _nav every 0.12s forever (endless scroll + sfx loop).
	_stick_x = 0
	_stick_y = 0
	_nav_frame = -1
	if mode == Mode.HIDDEN and main != null and main.sim != null:
		open(Mode.PAUSE)
		# A pad yanked mid-flail can spray phantom presses — ignore
		# confirm/activate for a beat so nothing destructive can fire.
		_lockout = 0.25


func _process(delta: float) -> void:
	if mode != Mode.HIDDEN:
		# Armed RESTART/TITLE/QUIT rows disarm after 2.5 s — a stale confirm
		# must not end a run on a press that lands minutes later.
		if _confirm >= 0:
			_confirm_t -= delta
			if _confirm_t <= 0.0:
				_confirm = -1
		_lockout = maxf(0.0, _lockout - delta)
		# Tab flash is pure animation — reduce-motion snaps it off entirely.
		_filter_pulse = 0.0 if main._motion < 0.5 else maxf(0.0, _filter_pulse - delta * 3.0)
		# Held-stick auto-repeat: first step fired in _unhandled_input, then
		# after 0.35 s held it steps every 0.12 s (framerate-independent).
		if _stick_x != 0 or _stick_y != 0:
			_stick_rep -= delta
			if _stick_rep <= 0.0:
				_stick_rep = 0.12
				# Auto-repeat drives VERTICAL nav and HALL filter cycling only.
				# A held sideways stick used to machine-gun toggle activation ~8×/s
				# (buy sfx spam + bus mute flip + a settings disk-write every step);
				# the deliberate first flip still fires on the press edge in _unhandled_input.
				_nav(_stick_y, _stick_x if mode == Mode.HALL else 0)
		# Held up/down KEYS get the same repeat cadence as the stick.
		if _key_move != 0:
			_key_rep -= delta
			if _key_rep <= 0.0:
				_key_rep = 0.12
				_nav(_key_move, 0)
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
				if absf(_sel_y - _sel_target) < 1.0:
					_sel_y = _sel_target   # snap: sub-pixel drift shimmers the pixel font
		queue_redraw()   # pulse + glide + open-settle animate every frame while open


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int, select_id := "") -> void:
	# Menu-to-menu keeps ~60% scrim — a full _open_t reset dipped the backdrop
	# to ~0 for a frame and flashed the live attract firefight between screens.
	# Only entering from gameplay replays the full fade + drop-in.
	_open_t = 0.0 if mode == Mode.HIDDEN else 0.6
	mode = m
	sel = 0
	_confirm = -1
	_sel_y = -1.0   # highlight starts on the new menu's first row, no cross-menu glide
	_sel_target = -1.0
	_key_move = 0   # a key held across the transition must not auto-repeat here
	# Same discipline for the stick: pausing via START with the move-stick
	# deflected (the normal mid-combat case) used to auto-scroll 0.35s later —
	# and the first step UP wrapped focus from RESUME straight onto a
	# destructive row. Mirrors the _on_joy_changed clear.
	_stick_x = 0
	_stick_y = 0
	_nav_frame = -1
	_tab_hover = -1   # stale hall-tab hover must not survive a menu hop
	_has_replay = FileAccess.file_exists("user://last_run.replay")   # hoisted: _menu_items ran this disk stat ~180x/s while TITLE was open
	# Any menu opening freezes the sim mid-hold — cancel open supply wheels, or a
	# hold+pick released WHILE paused commits a stale buy on the first resumed
	# frame (the release the player meant as an abort).
	if main != null:
		for w in main._wheel:
			w["open"] = false
			w["sel"] = -1
	# Backing out of a submenu re-selects the row that opened it — landing on
	# CAMPAIGN after OPTIONS broke muscle memory (and risks a misfired start).
	if select_id != "":
		var mi := _menu_items()
		for k in mi.size():
			if mi[k]["id"] == select_id:
				sel = k
				break
	queue_redraw()


func _bus_off(name: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(name))


func _menu_items() -> Array[Dictionary]:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return [{"id": "back", "label": "BACK", "destructive": false}]
	if mode == Mode.TITLE:
		# "grp" drives the divider rules in _draw: start-verbs / run-config
		# toggles / meta screens / quit each read as their own block.
		var titems: Array[Dictionary] = [
			{"id": "campaign", "label": "CAMPAIGN", "destructive": false, "grp": 0},
			{"id": "endless", "label": "ENDLESS WAR", "destructive": false, "grp": 0},
			{"id": "daily", "label": "DAILY RUN", "destructive": false, "grp": 0},
			{"id": "paste_seed", "label": "CHALLENGE SEED", "destructive": false, "grp": 0},
			{"id": "coop", "label": "CO-OP: %s" % ("ON" if main._two_players else "OFF"), "destructive": false, "on": main._two_players, "grp": 1},
			{"id": "hard", "label": "NG+ HARD: %s" % ("ON" if main._hard else "OFF"), "destructive": false, "on": main._hard, "grp": 1},
			{"id": "hall", "label": "HALL OF FAME", "destructive": false, "grp": 2},
			{"id": "howto", "label": "HOW TO PLAY", "destructive": false, "grp": 2},
		]
		titems.append({"id": "options", "label": "OPTIONS", "destructive": false, "grp": 2})
		if _has_replay:
			titems.append({"id": "watch", "label": "WATCH LAST RUN", "destructive": false, "grp": 2})
		titems.append({"id": "quit", "label": "QUIT", "destructive": true, "grp": 3})
		return titems
	if mode == Mode.OPTS:
		# Settings reachable BEFORE a run: reduce-motion/colorblind/assist lived
		# only in PAUSE while the title played a live, flashing attract fight —
		# exactly the players who need them couldn't reach them.
		var oitems := _settings_rows()
		oitems.append({"id": "back", "label": "BACK", "destructive": false})
		return oitems
	var pitems: Array[Dictionary] = [{"id": "resume", "label": "RESUME", "destructive": false, "grp": 0}]
	pitems.append_array(_settings_rows())
	pitems.append({"id": "restart", "label": "RESTART", "destructive": true, "grp": 2})
	pitems.append({"id": "title", "label": "TITLE SCREEN", "destructive": true, "grp": 2})
	return pitems


func _settings_rows() -> Array[Dictionary]:
	# "on" drives the row's state dot (filled/hollow — position+shape carry it,
	# not hue alone) so toggle state reads without parsing the label tail.
	return [
		# SFX/MUSIC are stepped 0..10 levels (8-of-9 panel consensus), not mute
		# toggles: "vol" drives a 10-segment bar where the state dot would sit.
		# grp 1 = the settings block (RESUME is grp 0, destructive exits grp 2).
		{"id": "sfx", "label": "SFX: %d" % main._bus_vol("SFX"), "destructive": false, "vol": main._bus_vol("SFX"), "grp": 1},
		{"id": "music", "label": "MUSIC: %d" % main._bus_vol("Music"), "destructive": false, "vol": main._bus_vol("Music"), "grp": 1},
		{"id": "motion", "label": "REDUCE MOTION: %s" % ("ON" if main._motion < 0.5 else "OFF"), "destructive": false, "on": main._motion < 0.5, "grp": 1},
		{"id": "colorblind", "label": "COLORBLIND: %s" % ("ON" if main.colorblind else "OFF"), "destructive": false, "on": main.colorblind, "grp": 1},
		{"id": "rumble", "label": "RUMBLE: %s" % ("ON" if main._rumble_on else "OFF"), "destructive": false, "on": main._rumble_on, "grp": 1},
		{"id": "assist", "label": "ASSIST (2-HIT): %s" % ("ON" if main._assist else "OFF"), "destructive": false, "on": main._assist, "grp": 1},
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
		"options": return "mi_settings"
		"restart": return "mi_reload"
		"title": return "mi_home"
		"rumble": return "mi_controller"
		"watch": return "mi_camera"
		"back": return "mi_back"
		"endless": return "mi_combat"
		"daily": return "mi_timer"
		"quit": return "mi_cancel"
	return ""


func _unhandled_input(ev: InputEvent) -> void:
	var move := 0
	var hmove := 0
	var act := false
	var back := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_W, KEY_UP:
				move = -1
				_key_move = -1
				_key_rep = 0.35   # same hold-repeat cadence as the stick
			KEY_S, KEY_DOWN:
				move = 1
				_key_move = 1
				_key_rep = 0.35
			KEY_A, KEY_LEFT: hmove = -1
			KEY_D, KEY_RIGHT: hmove = 1
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: act = true   # numpad Enter redeploys from the debrief; menus must match
			KEY_ESCAPE: back = true
	elif ev is InputEventKey and not ev.pressed:
		# Release clears the hold-repeat latch (repeat itself runs in _process).
		match ev.keycode:
			KEY_W, KEY_UP:
				if _key_move == -1:
					_key_move = 0
			KEY_S, KEY_DOWN:
				if _key_move == 1:
					_key_move = 0
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
		# Both axes back in the deadband = fresh gesture: clear the one-nav-per-
		# frame stamp so a released-then-repushed diagonal can't wedge nav.
		if _stick_x == 0 and _stick_y == 0:
			_nav_frame = -1

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
			# Hall filter tabs get hover feedback too — they were click-only,
			# the lone interactive surface with zero mouse cue (rows hover-select,
			# arrows pulse; the file's own parity invariant, line ~317).
			if mode == Mode.HALL:
				var ht := -1
				var tabs := _hall_tab_rects()
				for ti in tabs.size():
					if tabs[ti].has_point(ev.position):
						ht = ti
				if ht != _tab_hover:
					_tab_hover = ht
					queue_redraw()
			var hrow := _row_at(ev.position)
			if hrow >= 0 and hrow != sel:
				sel = hrow
				_confirm = -1
				queue_redraw()
		return
	if ev is InputEventMouseButton:
		# Menus swallow EVERY click, hit or miss, press or release — a stray
		# click through an open menu must never bleed into gameplay.
		get_viewport().set_input_as_handled()
		if not ev.pressed:
			return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			# Hall filter tabs are clickable — they were the one visible control
			# a mouse-only player couldn't operate (every other surface has
			# hover/click/wheel parity).
			if mode == Mode.HALL:
				var tabs := _hall_tab_rects()
				for ti in tabs.size():
					if tabs[ti].has_point(ev.position):
						if ti != _hall_filter:
							_hall_filter = ti
							_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
							main._sfx.play("pickup", -14.0, 1.3)
						queue_redraw()
						return
			var crow := _row_at(ev.position)
			if crow >= 0:
				sel = crow
				_press()
				queue_redraw()
			elif mode != Mode.HALL and mode != Mode.HOWTO \
					and _menu_items()[sel]["id"] in _TOGGLES:
				# The ◄/► cycle affordances draw OUTSIDE the row plate — without
				# their own hitbox a click on a visible, pulsing arrow was silently
				# swallowed (the same parity gap the hall tabs got fixed for).
				var g := _row_geometry()
				var ry := floorf(float(g["top"]) + float(sel) * float(g["gap"]))
				var ay := floorf(ry + float(g["bh"]) / 2.0) - 5.0   # same snap as _draw's cy
				var lx := 320.0 - BTN.x / 2.0
				var la := Rect2(lx - 23.0, ay, 10.0, 10.0).grow(3.0)
				var ra := Rect2(lx + BTN.x + 5.0, ay, 10.0, 10.0).grow(3.0)
				if la.has_point(ev.position) or ra.has_point(ev.position):
					# Side matters now: volume rows step down/up per arrow
					# (plain toggles flip either way, exactly as before).
					_nav(0, -1 if la.has_point(ev.position) else 1)
					queue_redraw()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var wdir := -1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if mode == Mode.HALL:
				_nav(0, wdir)   # HALL's only control is the filter — wheel cycles it instead of wrapping a 1-row list
			else:
				_nav(wdir, 0)
		return
	if move != 0 or hmove != 0:
		_nav(move, hmove)
	elif act:
		_press()
	elif back and mode == Mode.PAUSE:
		mode = Mode.HIDDEN
	elif back and (mode == Mode.HALL or mode == Mode.HOWTO or mode == Mode.OPTS):
		open(Mode.TITLE, {Mode.HALL: "hall", Mode.HOWTO: "howto", Mode.OPTS: "options"}[mode])
	if move != 0 or hmove != 0 or act or back:
		accept_event()
	queue_redraw()


# One nav step — shared by key/dpad/stick presses, the held-stick auto-repeat,
# and the mouse wheel, so every device gets identical wrap/snap/sfx behavior.
func _nav(move: int, hmove: int) -> void:
	# Hall of Fame: left/right cycles the mode filter (ALL / CAMPAIGN / ENDLESS).
	if mode == Mode.HALL and hmove != 0:
		_hall_filter = wrapi(_hall_filter + hmove, 0, 3)
		_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
		main._sfx.play("pickup", -14.0, 1.3)
		queue_redraw()
		return
	# ◄/► on a volume row steps the 0..10 level (Enter still mute-toggles, and
	# the bus keeps its volume_db through a mute, so unmute restores the level).
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] in ["sfx", "music"]:
		var bus: String = "SFX" if _menu_items()[sel]["id"] == "sfx" else "Music"
		var nv: int = clampi(main._bus_vol(bus) + hmove, 0, 10)
		if nv != main._bus_vol(bus):
			main._set_bus_vol(bus, nv)
			main._save_settings()
			# The tick doubles as a live level demo — pitch rides the new step.
			main._sfx.play("pickup", -14.0, 0.8 + 0.05 * float(nv))
		queue_redraw()
		return
	# Left/right on a toggle row flips it directly — no confirm press needed
	# (same activation path, so save/sfx behavior stays identical).
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] in _TOGGLES:
		_activate()
		queue_redraw()
		return
	if move == 0:
		return
	if _items().size() < 2:
		return   # 1-row menu (HOWTO's BACK): sel wraps 0→0 — no phantom nav sfx
	var prev := sel
	sel = wrapi(sel + move, 0, _items().size())
	if absi(sel - prev) > 1:
		_sel_y = -1.0   # wrap: snap to the far end instead of gliding the whole list
	_confirm = -1
	main._sfx.play("pickup", -14.0, 1.3)
	queue_redraw()


func _press() -> void:
	if _lockout > 0.0:
		return   # disconnect just auto-paused — swallow phantom confirms
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
	# OPTS gets its own top: the 156 floor exists to clear TITLE's tagline/BEST/
	# CAREER block, but OPTIONS has only a lone header at y88 — at 156 it left a
	# ~46px void, then squeezed its 7 rows to a 25px pitch. 120 seats them right
	# under the header at the full gap.
	var top := 118.0 if mode == Mode.PAUSE \
		else (120.0 if mode == Mode.OPTS else (150.0 if not many else 156.0))
	# TITLE's bottom bound clears the y~322 input legend strip — at 310 the QUIT
	# row sat flush against it (6/8 panel reviewers, unanimous top item).
	var bottom := 296.0 if mode == Mode.TITLE else 310.0
	var gap := minf(30.0 if many else 46.0, (bottom - top) / maxf(1.0, float(n - 1)))
	# Open-settle drop-in offset lives HERE (after the gap math it must not
	# perturb) so a click during the settle hits the same rows _draw renders.
	if main._motion >= 0.5:
		top += (1.0 - _open_t) * 12.0
	return {"top": top, "gap": gap, "bh": floorf(minf(BTN.y, gap - 3.0)), "n": n}   # floored HERE so _draw and the mouse hit-test share one height


func _row_at(p: Vector2) -> int:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return 0 if _back_rect().has_point(p) else -1
	if absf(p.x - 320.0) > BTN.x / 2.0:
		return -1
	var g := _row_geometry()
	# Extend each row's hit-box by half the row-to-row dead band so adjacent boxes
	# meet exactly — hovering the gap between plates used to fall through to -1 and
	# the highlight blinked out mid-move.
	var pad := maxf(0.0, (float(g["gap"]) - float(g["bh"])) / 2.0)
	for k in int(g["n"]):
		var ry := floorf(float(g["top"]) + float(k) * float(g["gap"]))   # same snap as _draw
		if p.y >= ry - pad and p.y < ry + float(g["bh"]) + pad:
			return k
	return -1


## Single source of truth for the HALL/HOWTO back button geometry — _row_at and
## _draw_back_button both read it, so a tweak to one can't drift the click target
## off the pixels (same discipline as _row_geometry / panel_bottom()).
func _back_rect() -> Rect2:
	# 320 (was 316): buys the HOWTO threat list its 7th row — the selected
	# plate's grow(3) top sits at 317, clear of the last baseline at 312.
	# Bottom lands at 345, inside the 360 canvas. Draw + hit-test share this.
	return Rect2(Vector2(320 - BTN.x / 2.0, 320), BTN * Vector2(1, 0.7))


func _toggle_bus(name: String) -> void:
	var b := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(b, not AudioServer.is_bus_mute(b))
	if name == "SFX":
		# The jingle "UI" bus slaves to the SFX mute — one user-facing toggle.
		AudioServer.set_bus_mute(AudioServer.get_bus_index("UI"), AudioServer.is_bus_mute(b))


func _activate() -> void:
	main._sfx.play("buy", -8.0)
	if mode == Mode.HALL or mode == Mode.HOWTO:
		open(Mode.TITLE, "hall" if mode == Mode.HALL else "howto")
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
			"options": open(Mode.OPTS)
			"quit": get_tree().quit()
	else:
		match id:
			"resume": mode = Mode.HIDDEN
			"back": open(Mode.TITLE, "options")   # OPTS returns to the title, cursor on OPTIONS
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


static func _content_well(scrim_mode: int) -> bool:
	# a3-02: HALL/HOWTO are bordered CONTENT screens — they get a solid dark interior
	# well behind the chrome frame so the attract firefight can't bleed through the
	# frame texture's transparent regions. PAUSE recedes via scrim ALONE (no well), so
	# the frozen run stays faintly readable behind the settings list.
	return scrim_mode == Mode.HALL or scrim_mode == Mode.HOWTO


static func _content_well_rect() -> Rect2:
	# The interior fill, inset inside the Rect2(20,8,600,344) chrome frame so the frame's
	# decorative border still draws over its own edge (chrome is drawn AFTER the well).
	return Rect2(30, 17, 580, 326)


static func _scrim_alpha(scrim_mode: int, motion: float) -> float:
	# The backdrop scrim for each menu screen (before the _open_t settle envelope).
	# TITLE keeps the attract fight mostly visible; the title stack near-blacks under
	# REDUCE MOTION (the live scroll/tracers are the biggest motion source on the exact
	# screen hosting that toggle). PAUSE keeps its frozen run readable.
	var sa := 0.55 if scrim_mode == Mode.TITLE else 0.6
	if scrim_mode != Mode.PAUSE and motion < 0.5:
		sa = 0.92
	# a3-02: HALL/HOWTO are dedicated content screens, not the attract stage — at the
	# default 0.6 scrim the live firefight (enemies/tracers/bunker) bled through the
	# frame behind the score table & instructions. Seal them near-opaque regardless of
	# motion. PAUSE recedes its frozen field harder (0.6->0.74) so it reads as its own
	# space, but stays legible enough to still study your run behind the menu.
	if scrim_mode == Mode.HALL or scrim_mode == Mode.HOWTO:
		sa = maxf(sa, 0.9)
	elif scrim_mode == Mode.PAUSE:
		sa = maxf(sa, 0.74)
	return sa


func _draw() -> void:
	if mode == Mode.HIDDEN:
		return
	# Scrim ≥0.55: 8px text over a LIVE firefight; fades in over the open settle.
	# REDUCE MOTION near-blacks the TITLE backdrop — the live attract fight
	# (scroll + tracers + explosions) is the biggest motion source on the exact
	# screen where the setting is toggled, and it isn't _motion-gated itself.
	var sa := _scrim_alpha(mode, main._motion)
	draw_rect(Rect2(0, 0, 640, 360), Color(0.02, 0.05, 0.02, sa * _open_t))
	if _content_well(mode):
		# Plate the bare text on the Apocalypse frame, debrief-style (underlay
		# darkens the well, frame carries the chrome).
		var fr := Rect2(20, 8, 600, 344)
		# a3-02: a SOLID desaturating dark well seals the frame INTERIOR before the
		# chrome — the _under frame texture has transparent regions the firefight showed
		# through even at a high scrim. Cool-dark near-opaque fill; the frame draws on top.
		draw_rect(_content_well_rect(), Color(0.035, 0.055, 0.05, 0.92 * _open_t))
		draw_texture_rect(Art.tex("ui_frame_lrg_under"), fr, false, Color(1, 1, 1, 0.9 * _open_t))
		draw_texture_rect(Art.tex("ui_frame_lrg"), fr, false, Color(0.85, 0.9, 0.75, _open_t))
		if mode == Mode.HALL:
			_draw_hall()
		else:
			_draw_howto()
		_draw_back_button()
		return
	if mode == Mode.TITLE:
		# a2-04 AD#3: the largest word was drawn BARE over the live attract firefight (a
		# red blast muddied the "I"); plate it like its tagline/BEST/CAREER siblings.
		var ttw := Art.font().get_string_size("SHOEMONEY SOLDIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_rect(Rect2(320.0 - ttw / 2.0 - 10.0, 60.0, ttw + 20.0, 32.0), Color(0.03, 0.05, 0.03, 0.55))   # a2-04 r2: match sibling plate alpha
		_center_text("SHOEMONEY SOLDIER", 86, 30, Color(1.0, 0.85, 0.3))
		# Studio byline, plated like the tagline below it (small text loses to the live
		# attract firefight no matter the alpha — the codebase's thrice-cited lesson).
		var byl := "by SHOEMONEY GAME STUDIOS"
		var bylw := Art.font().get_string_size(byl, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_rect(Rect2(320.0 - bylw / 2.0 - 4.0, 93.0, bylw + 8.0, 9.0), Color(0.03, 0.05, 0.03, 0.55))
		_center_text(byl, 100, 8, Color(0.85, 0.78, 0.55, 0.92))
		# Tagline + BEST get the same measured dark plate as their CAREER/legend/
		# seed-hint siblings — small text straight on the live attract firefight
		# loses to bright terrain no matter the alpha (the codebase's own thrice-
		# cited lesson; a white explosion drops the gold line under 2:1 contrast).
		var tagline := "ONE HIT. ONE WAR CHEST. NO MERCY."
		var tgw := Art.font().get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_rect(Rect2(320.0 - tgw / 2.0 - 4.0, 101.0, tgw + 8.0, 14.0),
			Color(0.03, 0.05, 0.03, 0.55))
		_center_text(tagline, 112, 10, Color(0.85, 0.9, 0.8, 0.85))
		# Read order: title → tagline → one BRIGHT record line → menu. CAREER stays
		# a dim whisper at 145 (clears the 156 first-row top since the c1 layout fix).
		if main.best_score > 0:
			# a2-04 HUD#8: only show the record fields that are non-zero (via a testable
			# helper) — a fresh best reads as a real record, not "WAVE 0 · 0m" debug dump.
			var best_line := _best_line(main.best_score, main.best_wave, main.best_dist)
			var bw := Art.font().get_string_size(best_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_rect(Rect2(320.0 - bw / 2.0 - 4.0, 122.0, bw + 8.0, 13.0),
				Color(0.03, 0.05, 0.03, 0.55))
			_center_text(best_line, 132, 9, Color(1.0, 0.92, 0.55, 1.0))
		if main._life_runs > 0:
			var wpct: int = main._life_wins * 100 / main._life_runs
			var career := "CAREER — %d RUNS · %d KILLS · %d%% WON" % [main._life_runs,
				main._life_kills, wpct]
			# Plated like the input legend: 8px dim text straight on the live
			# attract firefight loses to bright terrain no matter the alpha.
			var cpw := Art.font().get_string_size(career, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_rect(Rect2(320.0 - cpw / 2.0 - 4.0, 136.0, cpw + 8.0, 12.0),
				Color(0.03, 0.05, 0.03, 0.55))
			_center_text(career, 145, 8, Color(0.6, 0.72, 0.62, 0.7))
	elif mode == Mode.OPTS:
		_center_text("OPTIONS", 88, 22, Color(0.95, 0.95, 0.85))
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
		# floorf: fractional row pitch (gap 19.25/17.11) put every plate and its
		# pixel-font label on half-pixels — soft seams on an otherwise crisp UI.
		var r := Rect2(Vector2(320 - BTN.x / 2.0, floorf(top + k * gap)), Vector2(BTN.x, floorf(bh)))
		# Whole-pixel row center: bh is odd on PAUSE (21) and 11-row TITLE (11), so
		# every bh/2-derived y (label baseline, state dot, arrows, confirm glyph)
		# landed on .5 — the exact sub-pixel shimmer _sel_y snapping guards against.
		var cy := floorf(r.position.y + bh / 2.0)
		# Group divider: a faint rule in the gap above each "grp" boundary —
		# RESUME/settings/destructive on PAUSE, starts/toggles/meta/quit on TITLE —
		# hierarchy cue without touching the shared row geometry/hit-test.
		if k > 0 and k < mitems.size() \
				and mitems[k].get("grp", 0) != mitems[k - 1].get("grp", 0):
			var sy := floorf(top + k * gap) - floorf((gap - bh) / 2.0)
			draw_rect(Rect2(320 - BTN.x / 2.0 + 12.0, sy, BTN.x - 24.0, 1.0),
				Color(0.62, 0.66, 0.5, 0.55))
		var selected := k == sel
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		draw_texture_rect(Art.tex("ui_menu_button"), r, false,
			Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8))
		# Modern Menus ortho icon where a row has a clean match (toggles swap
		# by live state) — rows without one just stay text.
		var icon := _row_icon(mitems[k]["id"])
		if icon != "":
			# Floor at 8px: with WATCH LAST RUN present the TITLE list is 11 rows,
			# which drove bh-6 down to a ~5px illegible speck. 8px still centers
			# cleanly in an 11px row.
			var isz := clampf(bh - 6.0, 8.0, 16.0)
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
			# Fade the glow while it's still catching up to the row — a lagging box
			# at full alpha reads as misplaced; dimming it makes the glide read as motion.
			var lag := clampf(absf(_sel_y - _sel_target) / 40.0, 0.0, 1.0)
			draw_texture_rect(Art.tex("ui_menu_button_sel"), gr.grow(3.0 + mp * 1.5), false,
				Color(1.0, 0.9, 0.4, (0.7 + mp * 0.3) * (1.0 - 0.5 * lag)))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		# Destructive rows carry a warm tint BEFORE the first press — the warning
		# used to appear only after you'd already pressed once.
		if k < mitems.size() and mitems[k].get("destructive", false):
			col = Color(1.0, 0.78, 0.65) if selected else Color(0.9, 0.7, 0.6)
		var label: String = items[k]
		if k < mitems.size() and mitems[k].get("destructive", false):
			label += "  !"   # non-color destructive cue (hue alone fails protan players)
		var label_r := r.end.x - 8.0   # label right bound (shrinks for the confirm glyph)
		if _confirm == k:
			# "TO CONFIRM" is now said by the glyph + countdown bar — the full
			# string measured 197px and never actually fit the 190px button.
			label = "PRESS AGAIN"
			col = Color(1.0, 0.5, 0.4)
			# Armed state reads without the text: warm plate tint, a countdown
			# bar draining along the bottom edge, and the device confirm glyph.
			draw_rect(r.grow(-3), Color(0.75, 0.28, 0.12, 0.4))
			draw_rect(Rect2(r.position.x + 3.0, r.end.y - 5.0,
				(r.size.x - 6.0) * clampf(_confirm_t / 2.5, 0.0, 1.0), 2.0),
				Color(1.0, 0.62, 0.3, 0.95))
			var ct := Art.tex(Art.glyph_key("confirm"))
			var cw := 12.0 * float(ct.get_width()) / float(ct.get_height())
			draw_texture_rect(ct, Rect2(r.end.x - cw - 6.0, cy - 6.0, cw, 12.0), false)
			label_r = r.end.x - cw - 10.0
		# Fixed icon gutter: iconless rows indent the same, so every label
		# left-aligns to one column. Overlong labels ellipsize inside the button.
		var lx := r.position.x + 30.0
		Art.text(self, _ellipsize(label, 11, label_r - lx),
			Vector2(lx, cy + 4.0), 11, col)
		# Volume rows: a 10-step level bar where the toggle dot would sit —
		# level reads as fill COUNT (shape, not hue alone); 0 = all hollow.
		if mitems[k].has("vol"):
			var vv: int = mitems[k]["vol"]
			var vbx := r.end.x - 8.0 - 49.0   # 10 segments * 5px pitch - 1px, right-aligned with the dot slot
			for sgi in 10:
				var sr := Rect2(vbx + float(sgi) * 5.0, cy - 3.0, 4.0, 6.0)
				if sgi < vv:
					draw_rect(sr, Art.safe(Color(0.55, 0.95, 0.5, 1.0 if selected else 0.8)))
				else:
					draw_rect(sr, Color(0.55, 0.6, 0.5, 0.6), false, 1.0)
		# Toggle state dot at the row's right edge: filled = ON, hollow = OFF —
		# shape+fill carry the state (hue alone fails protan players).
		if mitems[k].has("on"):
			var dc := Vector2(r.end.x - 10.0, cy)
			if mitems[k]["on"]:
				draw_circle(dc, 3.0, Art.safe(Color(0.55, 0.95, 0.5)))
			else:
				draw_arc(dc, 3.0, 0, TAU, 10, Color(0.55, 0.6, 0.5, 0.8), 1.2)
		# Left/right cycle affordance on the selected toggle row — toggles flipped
		# silently and read identical to action rows. mi_arrow points RIGHT;
		# a negative rect width flips it for the left side.
		if selected and mitems[k]["id"] in _TOGGLES:
			var fcol := Color(1.0, 0.92, 0.55, 0.55 + 0.45 * (0.0 if main._motion < 0.5 else Art.pulse(0.2)))
			var at := Art.tex("mi_arrow")
			var ay := cy - 5.0
			draw_texture_rect(at, Rect2(r.position.x - 13.0, ay, -10.0, 10.0), false, fcol)
			draw_texture_rect(at, Rect2(r.end.x + 5.0, ay, 10.0, 10.0), false, fcol)
		if mitems[k]["id"] == "paste_seed":
			# Where the seed comes from — the row name alone didn't say. Plated:
			# it draws OUTSIDE the button over the live attract fight, and 8px
			# text loses to bright terrain (the input legend's own lesson).
			var apw := Art.font().get_string_size("(FROM CLIPBOARD)", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_rect(Rect2(r.end.x + 2.0, cy - 6.0, apw + 8.0, 12.0),
				Color(0.03, 0.05, 0.03, 0.55))
			Art.text(self, "(FROM CLIPBOARD)", Vector2(r.end.x + 6.0, cy + 3.0),
				8, Color(0.84, 0.86, 0.78, 0.75))
		if selected:
			# 1px focus ring on the actual row rect — always crisp and present,
			# independent of the glow glide, for keyboard/pad a11y.
			draw_rect(r, Color(1.0, 0.97, 0.88), false, 1.0)
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
	var r := _back_rect()
	draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
	draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false, Color(1.0, 0.9, 0.4, 0.95))
	draw_rect(r, Color(1.0, 0.97, 0.88), false, 1.0)   # focus ring (only row here)
	_center_text("BACK", r.position.y + 16.0, 11, Color(1.0, 0.95, 0.75))


func _hall_tab_rects() -> Array[Rect2]:
	# The same measured tab layout _draw_hall renders, as clickable rects —
	# keep the width math in lockstep with the loop below.
	var names := ["ALL", "CAMPAIGN", "ENDLESS"]
	var f := Art.font()
	var tw: Array[float] = []
	var total := -22.0
	for n in names:
		var w := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		tw.append(w)
		total += w + 22.0
	var x := 320.0 - total / 2.0
	var out: Array[Rect2] = []
	for i in names.size():
		out.append(Rect2(x - 4.0, 52.0, tw[i] + 8.0, 20.0))
		x += tw[i] + 22.0
	return out


func _draw_hall() -> void:
	var names := ["ALL", "CAMPAIGN", "ENDLESS"]
	_center_text("HALL OF FAME", 38, 22, Color(1.0, 0.85, 0.3))
	# Persistent filter tab row — the old single "◄ NAME ►" line hid the other
	# two choices, so nobody knew left/right cycled anything. Selected tab is
	# underlined and flashes briefly on change (_filter_pulse). Geometry comes
	# from _hall_tab_rects — the SAME rects the click/hover tests use — so a
	# tab rename or padding tweak can't drift the targets off the pixels
	# (same discipline as _row_geometry).
	var f := Art.font()
	var tabs := _hall_tab_rects()
	for i in names.size():
		var tr := tabs[i]
		var on := i == _hall_filter
		var col := Color(1.0, 0.95, 0.65) if on else Color(0.6, 0.66, 0.56, 0.8)
		if on and _filter_pulse > 0.0:
			col = col.lightened(_filter_pulse * 0.45)
		elif not on and i == _tab_hover:
			col = col.lightened(0.25)   # hover cue — same idiom as _filter_pulse
		if on:
			# Filled plate under the live tab — the underline alone read as
			# decoration, not state, next to two equally-bright neighbors.
			draw_rect(Rect2(tr.position.x, 54.0, tr.size.x, 16.0), Color(0.05, 0.08, 0.04, 0.9))
		Art.text(self, names[i], Vector2(tr.position.x + 4.0, 66), 10, col)
		if on:
			draw_rect(Rect2(tr.position.x + 2.0, 70.0, tr.size.x - 4.0, 2.0),
				Color(1.0, 0.9, 0.4, 0.9 + _filter_pulse * 0.1))
	# The cycle affordance itself: dpad art on pad, arrow text on keyboard.
	var left := tabs[0].position.x + 4.0
	var right := tabs[tabs.size() - 1].end.x - 4.0
	if Art.use_pad:
		var t := Art.tex("glyph_dpad_lr")
		var gw := 13.0 * float(t.get_width()) / float(t.get_height())
		draw_texture_rect(t, Rect2(left - gw - 12.0, 56.0, gw, 13.0), false)
	else:
		# mi_arrow points RIGHT; negative rect width flips it for the left side.
		var at := Art.tex("mi_arrow")
		var acol := Color(0.84, 0.86, 0.78)
		draw_texture_rect(at, Rect2(left - 19.0, 56.0, -11.0, 11.0), false, acol)
		draw_texture_rect(at, Rect2(right + 8.0, 56.0, 11.0, 11.0), false, acol)
	# Filter to the selected mode (ALL shows everything), keeping score order.
	var rows: Array = []
	for run in main.hall:
		# .get fallbacks everywhere a hall row is read — old save files
		# predate some keys and must not crash the board.
		if _hall_filter == 1 and run.get("mode", "campaign") == "endless":
			continue
		if _hall_filter == 2 and run.get("mode", "campaign") != "endless":
			continue
		rows.append(run)
	if rows.is_empty():
		_center_text("NO %s RUNS YET — GO EARN YOUR PLACE" % names[_hall_filter], 170, 11,
			Color(0.8, 0.84, 0.74))
		return
	# Measured column layout — Art.font() is proportional, so each column draws
	# at its own x. MODE/REACHED/STREAK x-starts come from the widest possible
	# header/cell at draw size + 14px gutters, after the right-aligned SCORE
	# column (right edge 214); hardcoded offsets drifted on every font change.
	var mode_w := f.get_string_size("MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	mode_w = maxf(mode_w, f.get_string_size("CAMPAIGN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	var reach_w := f.get_string_size("REACHED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	for s in ["SECTOR 9", "VICTORY", "WAVE 99"]:
		reach_w = maxf(reach_w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	var streak_x := 214.0 + 14.0 + mode_w + 14.0 + reach_w + 14.0
	var col_x := [112.0, 148.0, 214.0 + 14.0, 214.0 + 14.0 + mode_w + 14.0, streak_x]
	var headers := ["#", "SCORE", "MODE", "REACHED", "STREAK"]
	for c in headers.size():
		if c == 1:
			var hw := f.get_string_size(headers[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			Art.text(self, headers[c], Vector2(214.0 - hw, 92), 10, Color(1.0, 0.82, 0.4))
		else:
			Art.text(self, headers[c], Vector2(col_x[c], 92), 10, Color(1.0, 0.82, 0.4))
	# RANK header sits in the gap between the # and the right-aligned SCORE — drawn
	# outside the parallel header/col_x arrays so it doesn't reshuffle the columns.
	Art.text(self, "RANK", Vector2(130.0, 92), 10, Color(1.0, 0.82, 0.4))
	for i in mini(rows.size(), 8):
		var run: Dictionary = rows[i]
		var mode_s: String = "ENDLESS" if run.get("mode", "campaign") == "endless" else "CAMPAIGN"
		var reached: String = "WAVE %d" % run.get("wave", 0) if run.get("mode", "campaign") == "endless" \
			else ("VICTORY" if run.get("won", false) else "SECTOR %d" % run.get("sector", 0))
		var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.9, 0.82)
		var tag: String = "  *DAILY" if run.get("daily", false) else ""
		if run.get("assist", false):
			tag += "  *ASSIST"   # 2-hit runs compete on the same board — say so
		var streak_s := "x%d%s" % [run.get("streak", 0), tag]
		if streak_x + f.get_string_size(streak_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > 628.0:
			# Cell would run off the frame — abbreviate the tags for this row.
			tag = ("  *D" if run.get("daily", false) else "")
			if run.get("assist", false):
				tag += "  *A"
			streak_s = "x%d%s" % [run.get("streak", 0), tag]
		var y := 112 + i * 24
		var cells := [str(i + 1), Art.group_digits(int(run.get("score", 0))), mode_s, reached, streak_s]
		for c in cells.size():
			if c == 1:
				# Right-aligned numerals: a 6-digit endless score can't crowd MODE.
				var sw := Art.font().get_string_size(cells[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				Art.text(self, cells[c], Vector2(214.0 - sw, y), 11, col)
			else:
				Art.text(self, cells[c], Vector2(col_x[c], y), 11, col)
		# Earned run grade (S/A/B/C/D), colored by tier. Old saves predate the key —
		# guard with .get and only draw when present so the board never crashes.
		var gr: String = run.get("grade", "")
		if gr != "":
			var gcol: Color = {"S": Color(1.0, 0.85, 0.3), "A": Color(0.55, 0.9, 1.0),
				"B": Color(0.6, 0.9, 0.5), "C": Color(0.85, 0.85, 0.8)}.get(gr, Color(0.7, 0.7, 0.7))
			Art.text(self, gr, Vector2(132.0, y), 11, gcol)
			# Tier medal beside the letter (D=1 … S=5) — sprite is white-with-alpha,
			# tinted to the tier color so medal and letter read as one badge.
			var med: int = {"D": 1, "C": 2, "B": 3, "A": 4, "S": 5}.get(gr, 0)
			if med > 0:
				draw_texture_rect(Art.tex("mi_medal_%d" % med),
					Rect2(142.0, y - 10.0, 12.0, 12.0), false, gcol)


func _draw_howto() -> void:
	_center_text("HOW TO PLAY", 34, 22, Color(1.0, 0.85, 0.3))
	var hold_pre := "pays to REVIVE you or BUY supplies (hold"
	var lines := [
		["ONE HIT AND YOU DROP. The War Chest — shared coin from kills —", Color(1.0, 0.9, 0.6)],
		[hold_pre, Color(0.85, 0.9, 0.8)],
	]
	for i in lines.size():
		Art.text(self, lines[i][0], Vector2(60, 70 + i * 18), 11, lines[i][1])
	# Verb lines carry the actual input glyph inline (device-aware), like the
	# wheel line below — text-only verbs made players hunt the legend.
	# Re-wrapped for the wider pixel font: >64 chars clips at x=640.
	_verb_line(["@grenade", "GRENADES crack armor — bunkers, bosses, the Colossus."],
		124.0, Color(0.9, 0.92, 0.8))
	_verb_line(["Bullets don't. ", "@roll", "ROLL to dodge. ", "@interact",
		"BOARD tanks for crush + shells."], 142.0, Color(0.9, 0.92, 0.8))
	_verb_line(["@interact", "with no tank near PLANTS a carried claymore — it hurts BOTH sides."],
		158.0, Color(0.9, 0.92, 0.8))
	# The supply-wheel hold prompt is the DEVICE GLYPH, not a key-name string.
	var px := 60.0 + Art.font().get_string_size(hold_pre, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 9.0
	Art.draw_glyph(self, "wheel", Vector2(px, 84.0), 12.0)
	Art.text(self, "). That's the choice.", Vector2(px + 8.0, 88.0), 11, Color(0.85, 0.9, 0.8))
	# The enemy roster with live sprites.
	# sol-08: front the LIVE red-team sprites the player now sees (rusher/elite draw the pack enemy_* cel bakes).
	var roster := [["enemy_smg", "RUSHER — charges, touch kills"],
		["enemy_assault", "ELITE — keeps range, telegraphs one shot"],
		["frogman", "FROGMAN — lurks in water, grenades only"]]
	for i in roster.size():
		# 24px pitch (was 26): buys the ENDLESS header its clearance below —
		# last box bottom lands at 232, exactly the header's glyph top at y240.
		var yy := 174.0 + i * 24.0
		draw_texture_rect(Art.tex(roster[i][0]), Rect2(80, yy - 10, 20, 20), false, Art.tint(roster[i][0]))
		Art.text(self, roster[i][1], Vector2(108, yy + 3), 10, Color(0.9, 0.92, 0.82))
	# Endless War fields ranged specialists (wave 3+) — teach their counters.
	# 240 (was 244) + first special baseline 252: 12px header-to-row gap — at
	# 244 the header's descenders sat in GRENADIER's ascender row.
	Art.text(self, "ENDLESS WAR — RANGED THREATS:", Vector2(60, 240), 10, Color(1.0, 0.7, 0.4))
	# Each line fronts its LIVE sprite in its in-game tint (panel round: the top
	# roster teaches silhouettes, this block taught only names — a first-run
	# player couldn't match "GHILLIE" to the shape that kills them). Keyed
	# sprites carry the same modulate _draw_enemies uses; the p2 bakes ride
	# Art.tint like the roster above.
	var special := [
	["m_soldier2", Color(1.3, 1.1, 0.55), "GRENADIER — lobs a telegraphed blast on your spot. Keep moving."],
		["enemy_sniper", Art.tint("enemy_sniper"), "SNIPER — paints a laser line, then fires. Sidestep it."],   # sol-08: live red marksman
		["ghillie", Art.tint("ghillie"), "GHILLIE — hidden sniper; only its laser gives it away. Close in."],
		["sapper", Art.tint("sapper"), "SAPPER — seeds mines behind it. Don't chase over its trail."],
		["m_bombsuit", Color(0.85, 0.9, 1.0), "SHIELD — front blocks bullets. Flank it or grenade it."],
		["m_drone", Art.tint("m_drone"), "DRONE — flying spotter, calls mortars on your spot. Shoot it down."],
		["m_technical", Art.tint("m_technical"), "TECHNICAL — revs, then charges a LOCKED line. Step off it."]]
	for i in special.size():
		# SEVEN rows must fit between the header (baseline 244) and the BACK
		# plate: 252 start + 10px pitch puts baselines at 252..312 — 8px under
		# the header and clear of BACK (moved to y=320 for exactly this). The
		# two merged batches' layouts (12px pitch/6 rows vs 11px pitch/7 rows)
		# composed into header-overlap at 250 AND a 316 baseline inside BACK.
		var sy := 252.0 + i * 10.0
		# 26px box: the bakes carry wide transparent margins (~70% padding), so
		# the visible body is ~8px and neighboring boxes never actually touch —
		# smaller boxes rendered as unreadable specks. x=50 keeps the box off
		# the ui_frame chrome (46 sat on the border art).
		draw_texture_rect(Art.tex(special[i][0]), Rect2(50, sy - 17, 26, 26), false, special[i][1])
		Art.text(self, special[i][2], Vector2(76, sy), 10, Color(0.88, 0.9, 0.8))

static func _best_line(score: int, wave: int, dist: int) -> String:
	# a2-04 HUD#8: the title BEST line drops zero fields so it never advertises
	# "WAVE 0 · 0m" (a debug-dump read) on a fresh score-only best.
	var s := "BEST — SCORE %s" % Art.group_digits(score)   # a4-17: thousands separators
	if wave > 0:
		s += " · WAVE %d" % wave
	if dist > 0:
		s += " · %dm" % dist
	return s


func _center_text(txt: String, y: float, size: int, col: Color) -> void:
	Art.text_center(self, txt, 320.0, y, size, col)


# Trim a label to max_w with a trailing ellipsis (raw clipping ate whole glyphs
# mid-character; dynamic labels like the seed row can outgrow the button).
func _ellipsize(txt: String, size: int, max_w: float) -> String:
	var f := Art.font()
	if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return txt
	var ell := "…" if f.has_char(0x2026) else "..."
	while txt.length() > 1 and f.get_string_size(txt + ell, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		txt = txt.substr(0, txt.length() - 1)
	return txt + ell


# One howto line at x=60: "@action" segments draw the device glyph inline,
# plain segments draw as text; x flows left to right (same measure-then-place
# pattern as the wheel line above).
func _verb_line(segs: Array, base_y: float, col: Color) -> void:
	var f := Art.font()
	var x := 60.0
	for seg: String in segs:
		if seg.begins_with("@"):
			var action := seg.substr(1)
			if action == "grenade" or action == "fire":
				# No Art.draw_glyph entry for these — use the device hint art
				# (mouse button / trigger sprite), aspect preserved.
				var t := Art.tex(Art.glyph_key(action))
				var gw := 12.0 * float(t.get_width()) / float(t.get_height())
				draw_texture_rect(t, Rect2(x, base_y - 10.0, gw, 12.0), false)
				x += gw + 4.0
			else:
				Art.draw_glyph(self, action, Vector2(x + 6.0, base_y - 4.0), 12.0)
				x += 16.0
		else:
			Art.text(self, seg, Vector2(x, base_y), 11, col)
			x += f.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


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
