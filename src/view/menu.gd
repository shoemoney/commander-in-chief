class_name GameMenu
extends Control
## Title + pause overlay (Modern Menus sprites). Lives on the HUD CanvasLayer;
## while visible, main.gd simply doesn't step the sim — the deterministic core
## knows nothing about menus. Keyboard (W/S + Enter, Esc) and pad
## (dpad + A, Start) navigation.

enum Mode { HIDDEN, TITLE, PAUSE, HALL, HOWTO, OPTS, SETUP, INFO }

# 222 = 30px icon gutter + the widest pause label ("ASSIST (2-HIT): OFF") at
# 11px pixel-font + padding — 190 ellipsized toggle VALUES once the gutter landed.
const BTN := Vector2(222, 36)
# c1-12: ◄/► cycle-arrow layout — shared by _draw and the mouse hit-test via
# toggle_arrow_rects so the glyph and its click target can never drift apart.
const ARROW_SZ := 10.0        # arrow glyph box edge (px)
const ARROW_L_OFF := 23.0     # left arrow's far (outer) edge, left of the plate
const ARROW_R_GAP := 5.0      # right arrow's near edge, right of the plate
# c1-13: HALL rows per page. The board holds far more runs than fit on one screen,
# so _draw_hall pages HALL_PAGE_ROWS at a time and up/down turns the page.
const HALL_PAGE_ROWS := 8
# c1-13: recency messaging sits in a TOP band (under the tab underline @y72, above
# the column headers @y96), giving it a vertical region distinct from the paging
# counter (~y306) and the BACK plate (~y310) at the bottom — the four never overlap.
# y82 @size9 spans box [74,84] (PixelOperator ascent 8 / descent 2, measured): its
# bottom clears the y96 headers' box top (87) by 3px and the y72 underline by 2px, so
# the recency line and the headers never collide at the real font metrics (attempt 3
# put it at y85 — box [77,87] — which OVERLAPPED the old y92 headers' [83,94] by 4px).
const HALL_RECENCY_Y := 82.0
# c1-13: how many runs the board retains — the SINGLE SOURCE for the cap. main.gd's
# _record_run passes THIS const into _hall_capped, and the top status band states it on
# screen, so the retention limit the Hall enforces and the one it advertises can't drift.
# (The just-banked run is pinned even past it, so paging always reaches it.)
const HALL_KEEP := 40

var mode: int = Mode.TITLE
var sel := 0
var main: Node2D
var _confirm := -1   # index of a destructive item awaiting a 2nd press
var _hall_filter := 0   # Hall of Fame view: 0 = ALL, 1 = CAMPAIGN, 2 = ENDLESS
var _hall_page := 0     # c1-13: which page of HALL_PAGE_ROWS-run pages is shown (up/down pages)
var _hall_seen_hid := -1  # c1-13: hid of the latest run we've already auto-jumped to — once surfaced, reopening HALL keeps the player's chosen filter/page instead of snapping back
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
var _reset_flash := 0.0 # c1-09: "DEFAULTS RESTORED" success banner countdown after RESET DEFAULTS fires
var _reset_flash_anim := true   # c1-09: whether that banner fades — captured from the PRE-reset reduce-motion state (reset itself re-enables motion, so reading it live would never snap)
var _opts_parent := Mode.TITLE   # c1-09: which screen OPTIONS was opened from (TITLE or PAUSE) — drives BACK
var _filter_pulse := 0.0   # hall filter tab flash on change
var _rail_pulse := 0.0     # volume row bounced off a rail (0/MUTED or 10) — brief end-segment flash
var _rail_dir := 0         # which rail the bounce hit: -1 = muted floor, +1 = max ceiling
var _rail_row := -1        # sel index that bounced — the flash only lights its own row
var _key_move := 0      # held up/down key direction (hold-repeat, mirrors stick)
var _key_rep := 0.0     # countdown to the next held-key auto-repeat step
var _key_hmove := 0     # held ◄/► key direction — auto-repeats the volume step (volume rows only)
var _key_hrep := 0.0    # countdown to the next held-◄/► auto-repeat step
var _lockout := 0.0     # post-disconnect confirm lockout (flailing pad guard)
var _has_replay := false   # user://last_run.replay existence, sampled in open()
var _tab_hover := -1    # hall filter tab under the mouse (-1 = none) — hover cue parity with rows
var _page_hover := -1   # hall PREV/NEXT button under the mouse (0 = prev, 1 = next, -1 = none) — pointer-owned
var _page_press := 0.0  # hall page-button press flash (decays in _process) — click feedback beyond dimming
var _page_press_side := -1  # which page button flashed (0 = prev, 1 = next); cleared when the flash fades
var _last_ptr := Vector2(-1.0, -1.0)  # last mouse position seen — lets a page/filter change re-evaluate the hover under a STILL cursor

# Row ids that flip on left/right without a confirm press.
const _TOGGLES := ["coop", "hard", "sfx", "music", "motion", "colorblind", "rumble", "assist", "display"]

# c1-08 destructive-row palette — the SINGLE source shared by _draw and the contrast
# test, so the two can't drift. Plates are DARK warm so the LIGHT warm labels over
# them clear AA-normal (4.5:1) contrast; a mid warm plate washed the label out. The
# armed flood is a deep red the near-white armed label reads on. (Alpha on the
# unselected plate rides the button texture; contrast is checked on rgb — the
# in-situ composite over the dark base only raises the ratio.)
const DESTR_PLATE_SEL := Color(0.64, 0.32, 0.22)          # pre-armed, selected
const DESTR_PLATE_UNSEL := Color(0.5, 0.26, 0.2, 0.9)     # pre-armed, unselected
const DESTR_TEXT_SEL := Color(1.0, 0.95, 0.9)
const DESTR_TEXT_UNSEL := Color(0.95, 0.85, 0.8)
const DESTR_ARMED_FLOOD := Color(0.8, 0.18, 0.09)         # red flood base (alpha applied at draw)
const DESTR_ARMED_TEXT := Color(1.0, 0.95, 0.88)
# The armed underplate sits BENEATH the near-opaque flood, so it is kept DARK red:
# a bright underplate would lighten the flood composite at the pulse trough and drop
# the label contrast below AA-normal. Dark under dark keeps the composite ~= flood.
const DESTR_ARMED_PLATE_SEL := Color(0.55, 0.14, 0.07)
const DESTR_ARMED_PLATE_UNSEL := Color(0.45, 0.12, 0.06)

# c1-04: y (top) of the SELECT/BACK input-legend footer strip drawn on EVERY
# non-TITLE screen (PAUSE / OPTS / SETUP / HALL / HOWTO). One shared position so
# _footer_legend, _row_geometry's drop-in cap, and the layout test all agree the
# selected-row glow can never reach into it.
const FOOTER_Y := 341.0


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
		# c1-09: the "DEFAULTS RESTORED" success banner fades after RESET DEFAULTS fires.
		_reset_flash = maxf(0.0, _reset_flash - delta)
		_lockout = maxf(0.0, _lockout - delta)
		# Tab flash is pure animation — reduce-motion snaps it off entirely.
		_filter_pulse = 0.0 if main._motion < 0.5 else maxf(0.0, _filter_pulse - delta * 3.0)
		# Page-button press flash decays like the tab pulse; reduce-motion snaps it off.
		_page_press = 0.0 if main._motion < 0.5 else maxf(0.0, _page_press - delta * 3.5)
		if _page_press <= 0.0:
			_page_press_side = -1
		_rail_pulse = 0.0 if main._motion < 0.5 else maxf(0.0, _rail_pulse - delta * 3.5)
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
		# Held ◄/► KEYS auto-repeat, matching the held stick: in HALL it cycles the
		# filter (stick does the same at line ~95), on a volume row it steps the
		# level. Toggles get NO repeat — a held key would machine-gun the flip.
		if _key_hmove != 0:
			_key_hrep -= delta
			if _key_hrep <= 0.0:
				_key_hrep = 0.12
				if mode == Mode.HALL or _menu_items()[sel]["id"] in ["sfx", "music"]:
					_nav(0, _key_hmove)
				else:
					_key_hmove = 0   # not a HALL/volume context: drop the latch, no auto-repeat
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
	_rail_pulse = 0.0   # a fresh screen starts with no lingering rail-bounce flash
	_rail_row = -1
	_sel_y = -1.0   # highlight starts on the new menu's first row, no cross-menu glide
	_sel_target = -1.0
	_key_move = 0   # a key held across the transition must not auto-repeat here
	_key_hmove = 0  # nor a held ◄/► volume key
	# Same discipline for the stick: pausing via START with the move-stick
	# deflected (the normal mid-combat case) used to auto-scroll 0.35s later —
	# and the first step UP wrapped focus from RESUME straight onto a
	# destructive row. Mirrors the _on_joy_changed clear.
	_stick_x = 0
	_stick_y = 0
	_nav_frame = -1
	_tab_hover = -1   # stale hall-tab hover must not survive a menu hop
	_page_hover = -1  # ditto the PREV/NEXT hover — a menu hop must not leave a button lit
	if m == Mode.HALL:
		# Auto-jump to the run you just finished — but ONLY the first time the board
		# is opened after it was banked. Once surfaced (hid recorded), reopening HALL
		# preserves the filter/page the player last chose instead of yanking them back.
		var lr: Variant = main.get("hall_latest") if main != null else null
		var lh := -1
		if lr != null and not (lr as Dictionary).is_empty():
			lh = int((lr as Dictionary).get("hid", -1))
		if lh != -1 and lh != _hall_seen_hid:
			# A stale opposite-mode filter (e.g. CAMPAIGN) would hide an ENDLESS run —
			# widen to ALL ONLY when the current filter actually hides it; a filter
			# that already shows it is left alone, respecting the player's choice.
			if _hall_latest_index(_hall_rows()) < 0:
				_hall_filter = 0
			_hall_page = _hall_latest_page()
			_hall_seen_hid = lh
		else:
			# Already surfaced (or no fresh run): keep the player's place, only
			# clamping the page in case a filter change shrank the list underneath it.
			_hall_page = clampi(_hall_page, 0, _hall_pages(_hall_rows().size()) - 1)
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
	# The single source of truth for "is this bus muted" — the row label, the
	# segment bar, and the volume stepper all read mute through here. Guards a
	# missing bus (index -1) instead of feeding it to is_bus_mute.
	var i := AudioServer.get_bus_index(name)
	return i >= 0 and AudioServer.is_bus_mute(i)


func _menu_items() -> Array[Dictionary]:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return [{"id": "back", "label": "BACK", "destructive": false}]
	if mode == Mode.TITLE:
		# "grp" drives the divider rules in _draw: start-verbs / run-config
		# toggles / meta screens / quit each read as their own block.
		# c1-02: the 11-row crush is gone. RUN SETUP (a submenu holding CO-OP / NG+
		# HARD) sits right beside the start verbs it configures — a pre-run choice
		# stays one press from CAMPAIGN, not buried in settings. To hold TITLE at its
		# comfortable 8-row cap (>=20px plates, 16px icons), the meta screens moved
		# down a level: HALL OF FAME and HOW TO PLAY now live under the INFO screen. The
		# old list wedged config between the start verbs and the meta screens, driving bh
		# to ~11px with 8px speck icons and seating NG+/CO-OP right where a mis-nav
		# off CAMPAIGN landed.
		var titems: Array[Dictionary] = [
			{"id": "campaign", "label": "CAMPAIGN", "destructive": false, "grp": 0},
			{"id": "endless", "label": "ENDLESS WAR", "destructive": false, "grp": 0},
			{"id": "daily", "label": "DAILY RUN", "destructive": false, "grp": 0},
			{"id": "paste_seed", "label": "CHALLENGE SEED", "destructive": false, "grp": 0},
			# grp 1: run-config gets its own block (a divider splits it from the start
			# verbs above and the meta screens below). The row carries its own live
			# config tail — players and an EXPLICIT NORMAL/HARD difficulty — so a stale
			# CO-OP or NG+ choice can't ride hidden into the next deploy.
			{"id": "run_setup", "label": "RUN SETUP: %s  %s" % ["2P" if main._two_players else "1P",
				"HARD" if main._hard else "NORMAL"], "destructive": false, "grp": 1, "submenu": true},
		]
		# c1-09: the meta block is two focused rows — OPTIONS (settings ONLY, no info
		# links) and INFO (HALL OF FAME / HOW TO PLAY / WATCH LAST RUN). Splitting them
		# lets OPTIONS be a genuinely dedicated settings screen while INFO gathers the
		# look-back screens. WATCH LAST RUN moved off TITLE onto INFO (it belongs with
		# the records), so the meta block is a CONSTANT two rows and TITLE holds at its
		# 8-row cap whether or not a replay exists.
		titems.append({"id": "options", "label": "OPTIONS", "destructive": false, "grp": 2, "submenu": true})
		titems.append({"id": "info", "label": "INFO", "destructive": false, "grp": 2, "submenu": true})
		titems.append({"id": "quit", "label": "QUIT", "destructive": true, "grp": 3})
		return titems
	if mode == Mode.SETUP:
		# c1-02: CO-OP / NG+ HARD live on their own labeled RUN SETUP screen (reached
		# from TITLE, beside the start verbs) so pre-run choices read as a distinct
		# step and never crowd the settings toggles. Two rows + BACK => big plates.
		return [
			{"id": "coop", "label": "CO-OP: %s" % ("ON" if main._two_players else "OFF"), "destructive": false, "on": main._two_players, "grp": 0},
			{"id": "hard", "label": "NG+ HARD: %s" % ("ON" if main._hard else "OFF"), "destructive": false, "on": main._hard, "grp": 0},
			{"id": "back", "label": "BACK", "destructive": false, "grp": 2},
		]
	if mode == Mode.INFO:
		# c1-09: the look-back screens, split off OPTIONS so settings stand alone. HALL
		# OF FAME + HOW TO PLAY + (when a replay exists) WATCH LAST RUN, then BACK. All
		# reached from TITLE's INFO row; each climbs back here.
		var iitems: Array[Dictionary] = [
			{"id": "hall", "label": "HALL OF FAME", "destructive": false, "grp": 0, "submenu": true},
			{"id": "howto", "label": "HOW TO PLAY", "destructive": false, "grp": 0, "submenu": true},
		]
		if _has_replay:
			iitems.append({"id": "watch", "label": "WATCH LAST RUN", "destructive": false, "grp": 0})
		iitems.append({"id": "back", "label": "BACK", "destructive": false, "grp": 2})
		return iitems
	if mode == Mode.OPTS:
		# c1-09: the ONE dedicated SETTINGS screen — nothing but settings now (HALL OF
		# FAME / HOW TO PLAY moved to the INFO screen). Reached from TITLE and from
		# PAUSE's single OPTIONS row. The settings sit in four labelled blocks — AUDIO
		# (grp 1) / HAPTICS (grp 2) / ACCESSIBILITY (grp 3) / DISPLAY (grp 4) — then
		# RESET DEFAULTS (grp 5, a two-press confirm that recovers a bad choice), then
		# BACK (grp 6). group_header() names each settings block.
		var oitems: Array[Dictionary] = _settings_rows()
		# RESET DEFAULTS is a focusable, destructive-styled row: Enter/A arms it, a
		# second press reverts every persisted setting — the recover path the screen
		# lacked (immediate writes with no rollback). Two-press guards a stray press.
		oitems.append({"id": "reset_defaults", "label": "RESET DEFAULTS", "destructive": true, "grp": 5})
		oitems.append({"id": "back", "label": "BACK", "destructive": false, "grp": 6})
		return oitems
	# c1-09: PAUSE no longer duplicates the settings rows — it fronts them through ONE
	# OPTIONS row that opens the dedicated screen (which then BACKs to PAUSE). RESUME /
	# OPTIONS / RESTART / TITLE, each its own group so the dividers separate them.
	var pitems: Array[Dictionary] = [
		{"id": "resume", "label": "RESUME", "destructive": false, "grp": 0},
		{"id": "options", "label": "OPTIONS", "destructive": false, "grp": 1, "submenu": true},
	]
	pitems.append({"id": "restart", "label": "RESTART", "destructive": true, "grp": 2})
	pitems.append({"id": "title", "label": "TITLE SCREEN", "destructive": true, "grp": 2})
	return pitems


# Pure, view-free helpers for the SFX/MUSIC volume model — one place the label,
# the segment bar, and both input paths agree on. A muted bus is level 0 no
# matter its stored volume_db; steps are clamped to 0..10 (0 == MUTED), so no
# input can ever wrap a nudge into an accidental mute. Extracted so the headless
# test can pin the mute-aware + boundary behavior without an AudioServer.
static func effective_vol(muted: bool, level: int) -> int:
	return 0 if muted else clampi(level, 0, 10)


static func vol_label(muted: bool, level: int) -> String:
	# 0 == MUTED is the whole contract, so a level of 0 reads MUTED even if the
	# mute flag hasn't been stamped yet (belt-and-suspenders with effective_vol).
	return "MUTED" if muted or level <= 0 else str(clampi(level, 0, 10))


static func step_level(cur: int, delta: int) -> int:
	return clampi(cur + delta, 0, 10)


func _settings_rows() -> Array[Dictionary]:
	# "on" drives the row's state dot (filled/hollow — position+shape carry it,
	# not hue alone) so toggle state reads without parsing the label tail.
	# SFX/MUSIC are stepped 0..10 levels (8-of-9 panel consensus), not mute
	# toggles: "vol" drives a 10-segment bar where the state dot would sit.
	# The row is mute-AWARE at the source of truth (AudioServer.is_bus_mute), not
	# inferred from the number: a muted bus reads "MUTED" with an EMPTY bar (vol 0)
	# even if its volume_db is still nonzero, so the surface can never show a full
	# green bar while the game is silent. Enter and ◄/► both move this one value.
	var sfx_muted: bool = _bus_off("SFX")
	var mus_muted: bool = _bus_off("Music")
	var sv: int = effective_vol(sfx_muted, main._bus_vol("SFX"))
	var mv: int = effective_vol(mus_muted, main._bus_vol("Music"))
	# c1-09: four labelled groups — AUDIO (grp 1), HAPTICS (grp 2), ACCESSIBILITY
	# (grp 3), DISPLAY (grp 4) — so the divider rules + group_header captions read as
	# sections. REDUCE MOTION and COLORBLIND carry their ON/OFF in the row label AND the
	# state dot, and are echoed in the header a11y summary, so their live state reads in
	# both places. DISPLAY is a real toggle row now (not F11-only): every persisted
	# setting can be reviewed AND changed from the dedicated screen.
	return [
		{"id": "sfx", "label": "SFX: %s" % vol_label(sfx_muted, sv), "destructive": false, "vol": sv, "grp": 1},
		{"id": "music", "label": "MUSIC: %s" % vol_label(mus_muted, mv), "destructive": false, "vol": mv, "grp": 1},
		{"id": "rumble", "label": "RUMBLE: %s" % ("ON" if main._rumble_on else "OFF"), "destructive": false, "on": main._rumble_on, "grp": 2},
		{"id": "motion", "label": "REDUCE MOTION: %s" % ("ON" if main._motion < 0.5 else "OFF"), "destructive": false, "on": main._motion < 0.5, "grp": 3},
		{"id": "colorblind", "label": "COLORBLIND: %s" % ("ON" if main.colorblind else "OFF"), "destructive": false, "on": main.colorblind, "grp": 3},
		{"id": "assist", "label": "ASSIST (2-HIT): %s" % ("ON" if main._assist else "OFF"), "destructive": false, "on": main._assist, "grp": 3},
		{"id": "display", "label": "FULLSCREEN: %s" % ("ON" if main._fullscreen else "OFF"), "destructive": false, "on": main._fullscreen, "grp": 4},
	]


func _items() -> Array[String]:
	var out: Array[String] = []
	for item in _menu_items():
		out.append(item["label"])
	return out


# Pause-menu indices that discard the run and need a confirm press.
func _is_destructive(i: int) -> bool:
	return _menu_items()[i]["destructive"]


# c1-08: the on-plate wording for a destructive (run-ending) row, chosen against
# the ACTUAL drawable width `avail` (px) so the cue can never ellipsize away on the
# ~190px plate. Pure + static so a layout test can pin the fit for every row.
#   pre-armed: "<NAME>  PRESS TWICE" — states the two-press contract up front and
#              keeps the action name (was a lone "!" that read like plain emphasis).
#   armed:     "<VERB>  PRESS AGAIN" where it fits — the verb keeps WHICH action is
#              one press from firing — degrading (single space -> "<VERB>: AGAIN" ->
#              bare "PRESS AGAIN") only as far as the plate forces.
# Each candidate is tried widest-first; the first that fits `avail` wins.
static func destructive_label(name: String, verb: String, armed: bool, font: Font, avail: float) -> String:
	# Candidates run widest -> narrowest; the first that FITS `avail` wins. Both the
	# action identity (name/verb, always LEADING) and the explicit two-press cue
	# ("PRESS TWICE" pre-armed / "PRESS AGAIN" armed) ride every tier until the plate
	# is too tight for both — and the CUE is the last thing dropped, so it is never
	# ellipsized to nonsense. The abbreviated tiers keep the tail genuinely fitting on
	# a narrow plate instead of returning an overflowing string. On the real ~190px
	# plate a name/verb + full-cue tier always wins (RESTART/TITLE/QUIT verified in
	# the layout test) — "PRESS TWICE" states the contract outright, unlike the old
	# lone "!" that read like emphasis and made the row look single-press.
	var short_name := name.split(" ")[0]   # "TITLE SCREEN" -> "TITLE" before dropping identity
	var forms: Array[String]
	if armed:
		# The verb rides with the cue as long as it fits ("<VERB>: AGAIN" is terse but
		# unambiguous WITH the verb present). The floor is the full "PRESS AGAIN"
		# instruction — never a bare "AGAIN", which alone reads ambiguously.
		forms = ["%s  PRESS AGAIN" % verb, "%s PRESS AGAIN" % verb, "%s: AGAIN" % verb, "PRESS AGAIN"]
	else:
		forms = ["%s  PRESS TWICE" % name, "%s PRESS TWICE" % name]
		if short_name != name:
			forms.append("%s PRESS TWICE" % short_name)
		forms.append("PRESS TWICE")
	if font == null:
		return forms[0]
	for f in forms:
		if font.get_string_size(f, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= avail:
			return f
	# MINIMUM SUPPORTED WIDTH: the narrowest form is the bare cue ("PRESS TWICE" ~102px
	# / "PRESS AGAIN" ~99px at 11px). The only caller draws on the fixed BTN.x=222 plate
	# (avail 184 pre / 170 armed), so a fitting identity+cue tier ALWAYS wins there and
	# this floor is never reached in production. Below ~102px avail the cue is returned
	# as-is and _ellipsize would trim its tail — an unsupported, sub-word plate.
	return forms[forms.size() - 1]


# Row id → Modern Menus icon key. Only clean matches — no icon beats a
# stretched metaphor. Sound toggles reflect their live bus state.
func _row_icon(id: String) -> String:
	match id:
		"resume", "campaign": return "mi_play"
		"hall": return "mi_trophy"
		"howto": return "mi_book"
		"run_setup", "hard": return "mi_combat"
		"coop": return "mi_controller"
		"sfx": return "mi_snd_off" if _bus_off("SFX") else "mi_snd_on"
		"music": return "mi_mus_off" if _bus_off("Music") else "mi_mus_on"
		"options": return "mi_settings"
		"info": return "mi_book"
		"display": return "mi_camera"
		"restart", "reset_defaults": return "mi_reload"
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
			# ◄/► (A/D or arrows) feed hmove -> _nav: on a SFX/MUSIC row it steps
			# the volume down/up, and in HALL it cycles the ALL/CAMPAIGN/ENDLESS
			# filter — full parity with the pad d-pad (keyboard moves the level and
			# the Hall filter, not just the cursor).
			KEY_A, KEY_LEFT:
				hmove = -1
				_key_hmove = -1
				_key_hrep = 0.35   # held left auto-repeats the step (volume rows only)
			KEY_D, KEY_RIGHT:
				hmove = 1
				_key_hmove = 1
				_key_hrep = 0.35
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
			KEY_A, KEY_LEFT:
				if _key_hmove == -1:
					_key_hmove = 0
			KEY_D, KEY_RIGHT:
				if _key_hmove == 1:
					_key_hmove = 0
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
		# Gate on any nonzero delta, not length > 2: a parked pointer emits
		# zero-delta events (still ignored), but a slow deliberate drag moves
		# ~1px/event and used to be swallowed, locking a mouse-only player out of
		# selecting one row at a time.
		if ev.relative != Vector2.ZERO:
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
				# PREV/NEXT hover parity with the tabs (shared with _refresh_page_hover so a
				# page/filter change re-evaluates a still cursor the same way a move does).
				_last_ptr = ev.position
				var ph := _page_hover_at(ev.position)
				if ph != _page_hover:
					_page_hover = ph
					queue_redraw()
			var hrow := _row_at(ev.position)
			if hrow >= 0 and hrow != sel:
				# Full feedback parity: funnel the hover through _nav so it plays
				# the nav sfx, clears the rail pulse, and disarms an armed _confirm
				# audibly, exactly like pad/kb/wheel. The old inline sel = hrow
				# silently yanked selection and killed a QUIT/RESTART arm on a
				# bumped mouse, with no sound and no cue.
				_nav(hrow - sel, 0)
		return
	if ev is InputEventMouseButton:
		# Menus swallow EVERY click, hit or miss, press or release — a stray
		# click through an open menu must never bleed into gameplay. (Guarded so a
		# not-in-tree menu — the headless input tests — is a no-op here, not a crash.)
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		if not ev.pressed:
			return
		_last_ptr = ev.position   # keep the pointer fresh so a click-driven page change refreshes hover correctly
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
							_hall_page = 0   # fresh filtered list starts on its top page
							_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
							_refresh_page_hover()   # page reset to 0 disables PREV under a still cursor
							main._sfx.play("pickup", -14.0, 1.3)
						queue_redraw()
						return
			if mode == Mode.HALL and _hall_pages(_hall_rows().size()) > 1:
				# Prev/next page buttons: route through _nav so paging, sfx, and the
				# boundary clamp match the d-pad exactly. A click on a boundary-
				# disabled arrow lands in the clamp and no-ops (no page change).
				var pr := _hall_page_rects()
				if pr[0].has_point(ev.position):
					if _hall_page > 0:
						_page_press = 0.0 if main._motion < 0.5 else 1.0
						_page_press_side = 0
					_nav(-1, 0)
					return
				if pr[1].has_point(ev.position):
					if _hall_page < _hall_pages(_hall_rows().size()) - 1:
						_page_press = 0.0 if main._motion < 0.5 else 1.0
						_page_press_side = 1
					_nav(1, 0)
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
				var arows := toggle_arrow_rects(g, sel)   # same source _draw renders from
				var la := arows[0].grow(3.0)
				var ra := arows[1].grow(3.0)
				if la.has_point(ev.position) or ra.has_point(ev.position):
					# Side matters now: volume rows step down/up per arrow, so a
					# mouse-only player has BOTH directions (the ◄ arrow lowers and
					# mutes at 0) — clicking the plate only nudges up.
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
	elif back and not _parent(mode).is_empty():
		var d := _parent(mode)   # one level up; OPTIONS climbs to its opener (TITLE or PAUSE)
		open(d["mode"], d["sel"])
	if (move != 0 or hmove != 0 or act or back) and is_inside_tree():
		accept_event()   # is_inside_tree guard: a not-in-tree menu (headless tests) skips it
	queue_redraw()


# One nav step — shared by key/dpad/stick presses, the held-stick auto-repeat,
# and the mouse wheel, so every device gets identical wrap/snap/sfx behavior.
func _nav(move: int, hmove: int) -> void:
	# Hall of Fame: left/right cycles the mode filter (ALL / CAMPAIGN / ENDLESS).
	# Every device funnels here — keyboard A/D + arrows (via _unhandled_input hmove
	# and the held-key repeat above), pad d-pad, analog stick, and mouse wheel — so
	# no input class is locked out of the filters the way the pad once wasn't.
	# Up/down turns the HALL page (the board is deeper than one screen). HALL has
	# no row list to scroll, so vertical nav owns paging — clamped, never wraps.
	if mode == Mode.HALL and move != 0:
		var pages := _hall_pages(_hall_rows().size())
		var np := clampi(_hall_page + move, 0, pages - 1)
		if np != _hall_page:
			_hall_page = np
			_refresh_page_hover()   # the new page may flip a boundary — re-light/dim under a still cursor
			main._sfx.play("pickup", -14.0, 1.3)
			queue_redraw()
		return   # HALL vertical nav OWNS paging — always consume it, even at a boundary, so it never falls through to the 1-row list nav below
	if mode == Mode.HALL and hmove != 0:
		_hall_filter = wrapi(_hall_filter + hmove, 0, 3)
		_hall_page = 0   # a new filter is a fresh list — start at its top page
		_refresh_page_hover()   # page reset to 0 disables PREV — drop a stale hover on it
		# _tab_hover is pointer-owned — leave it. It tracks where the cursor
		# physically rests (only mouse motion moves it), so cycling by kb/pad/wheel
		# must not wipe a hover cue while the pointer is still over a tab. If the
		# cursor sits on the tab we just selected, _draw_hall's `not on` gate hides
		# the hover automatically, so no double-treatment slips through either.
		_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
		main._sfx.play("pickup", -14.0, 1.3)
		queue_redraw()
		return
	# ◄/► on a volume row nudges the 0..10 level, clamped — the SAME shared stepper
	# Enter/click drives. 0 == MUTED, so mute is just the bottom of the one model.
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] in ["sfx", "music"]:
		_step_vol("SFX" if _menu_items()[sel]["id"] == "sfx" else "Music", hmove)
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
	if sel != prev:
		_rail_pulse = 0.0   # left the row that bounced — don't flash a rail we moved off
		_rail_row = -1
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


# c1-09: OPTIONS climbs BACK to whichever screen opened it — TITLE normally, but
# PAUSE when reached mid-run (so backing out of settings returns to the paused run,
# not the title). back_dest stays the single source for the fixed parents (HALL/
# HOWTO/SETUP); only OPTIONS has two possible openers, tracked in _opts_parent.
func _parent(m: int) -> Dictionary:
	if m == Mode.OPTS and _opts_parent == Mode.PAUSE:
		return {"mode": Mode.PAUSE, "sel": "options"}
	return back_dest(m)


# c1-09: group caption for the OPTIONS settings block — the settings rows carry
# grp ids 1/2/3 (audio / haptics / accessibility) and the first row of each group
# draws this label in the left margin, so the screen reads as three labelled
# sections, not one flat list. Non-settings groups (meta/reset/back) have none.
static func group_header(grp: int) -> String:
	match grp:
		1: return "AUDIO"
		2: return "HAPTICS"
		3: return "ACCESSIBILITY"
		4: return "DISPLAY"
	return ""


# c1-09: the single settings-state readout for the OPTIONS screen — DISPLAY mode
# first, then EVERY accessibility aid with its EXPLICIT ON/OFF state (not just the
# active ones) so a player reviews the COMPLETE configuration in one place at a
# glance — "MOTION OFF  COLORBLIND ON  ASSIST OFF  RUMBLE ON" — instead of inferring
# what's off from an omission. DISPLAY is ALWAYS shown (fullscreen has no on-screen
# toggle — it's F11 — so this is the only place its state reads), which is also what
# makes RESET DEFAULTS honest: it restores DISPLAY to WINDOWED as a VISIBLE change
# here, not a silent flip. Pure + static so a headless test can pin the wording alone.
static func a11y_summary(reduce_motion: bool, colorblind: bool, assist: bool, rumble: bool, fullscreen: bool) -> String:
	return "DISPLAY: %s   REDUCE MOTION %s  COLORBLIND %s  ASSIST %s  RUMBLE %s" % [
		"FULLSCREEN" if fullscreen else "WINDOWED",
		"ON" if reduce_motion else "OFF",
		"ON" if colorblind else "OFF",
		"ON" if assist else "OFF",
		"ON" if rumble else "OFF",
	]


# Pure, view-free layout math for the button column — extracted so a headless
# regression test can pin the decompressed TITLE geometry (>=20px plates, 16px
# icons, header/legend clearance) without standing up a Control, Art, or `main`.
# `head_bottom` is the y of the lowest header plate the caller actually drew
# (TITLE varies it by which BEST/CAREER lines are present); other modes pass -1.
static func compute_geometry(mode_id: int, n: int, head_bottom: float) -> Dictionary:
	var many := n > 4
	# OPTS/SETUP get their own top: the 156 floor exists to clear TITLE's record
	# block, but they carry only a lone header at ~y88 — 120 seats rows right
	# under it at the full gap.
	# c1-09: OPTS is settings-only now (7 settings + RESET DEFAULTS + BACK = 9 rows),
	# under a compact 2-line header — top 102 keeps that count at a >=20px plate.
	# SETUP and INFO carry only a few rows, so 120 seats them right under a lone header.
	var top := 118.0 if mode_id == Mode.PAUSE \
		else (102.0 if mode_id == Mode.OPTS \
		else (120.0 if (mode_id == Mode.SETUP or mode_id == Mode.INFO) else (150.0 if not many else 156.0)))
	var gap: float
	if mode_id == Mode.TITLE:
		# top tracks whichever header lines are actually present (head_bottom) — a
		# fresh install (no BEST/CAREER) starts ~24px higher, so the list decompresses
		# into real height instead of a fixed 156 that crushed bh to ~11px + 8px specks.
		top = head_bottom + 2.0
		# Spread across the WHOLE band down to the y322 input legend. Dividing by
		# n (not n-1) reserves the final row's own height, so QUIT self-clears the
		# legend without the old hardcoded 296 bottom bound that left dead air.
		gap = minf(46.0, (318.0 - top) / maxf(1.0, float(n)))
	else:
		# PAUSE/OPTS: bottom clears the y~322 legend strip — at 310 the QUIT row
		# sat flush against it (6/8 panel reviewers, unanimous top item).
		gap = minf(30.0 if many else 46.0, (310.0 - top) / maxf(1.0, float(n - 1)))
	# TITLE plates take a 2px inter-row inset (vs 3px elsewhere) so the reclaimed
	# band converts to taller clickable plates, not just wider dead gaps.
	var inset := 2.0 if mode_id == Mode.TITLE else 3.0
	return {"top": top, "gap": gap, "bh": floorf(minf(BTN.y, gap - inset)), "n": n}   # floored HERE so _draw and the mouse hit-test agree


# The lowest header-plate baseline TITLE draws, given which record lines show —
# single source shared by compute_geometry and _draw so the column top can't
# drift off the header block. Non-TITLE modes have no record header (returns -1).
static func title_head_bottom(has_best: bool, has_career: bool) -> float:
	if has_career:
		return 139.0   # CAREER whisper plate bottom (implies the whole stack)
	if has_best:
		return 127.0   # BEST line plate bottom
	return 115.0       # tagline plate bottom (always drawn)


# Where BACK / Esc goes from each screen — one level up. HALL and HOW TO PLAY
# live under the INFO screen, so they climb to INFO; INFO, RUN SETUP and OPTIONS
# hang off TITLE. Pure + single-sourced so _unhandled_input and _activate can't
# drift their back-nav targets apart. Screens with no parent (TITLE/PAUSE/HIDDEN) => {}.
static func back_dest(mode_id: int) -> Dictionary:
	match mode_id:
		Mode.HOWTO: return {"mode": Mode.INFO, "sel": "howto"}
		Mode.HALL: return {"mode": Mode.INFO, "sel": "hall"}
		Mode.INFO: return {"mode": Mode.TITLE, "sel": "info"}
		Mode.SETUP: return {"mode": Mode.TITLE, "sel": "run_setup"}
		Mode.OPTS: return {"mode": Mode.TITLE, "sel": "options"}
		_: return {}


# Open-settle drop-in: the whole column starts up to 12px LOW and rises to rest.
# CAP the push so that even mid-open (open_t -> 0) the last plate never dips past
# `max_bottom` — on TITLE that is the y322 input legend (the only screen that
# draws it), which the fullest state settles just ~5px clear of, so an uncapped
# +12 briefly overlapped it. Other screens have no legend, so `max_bottom` is the
# canvas floor and the full drop-in survives. Pure + testable.
static func settle_offset(g: Dictionary, open_t: float, motion: float, max_bottom: float) -> float:
	if motion < 0.5:
		return 0.0
	var last_bottom := floorf(float(g["top"]) + float(int(g["n"]) - 1) * float(g["gap"])) + float(g["bh"])
	return minf((1.0 - open_t) * 12.0, maxf(0.0, max_bottom - last_bottom))


func _row_geometry() -> Dictionary:
	# Single source of truth for the button column layout — _draw and the mouse
	# hit-test must agree or hover selects the wrong row.
	var head := title_head_bottom(main.best_score > 0, main._life_runs > 0)
	var g := compute_geometry(mode, _items().size(), head)
	# Drop-in offset lives HERE (after the pure gap math it must not perturb) so a
	# click during the settle hits the same rows _draw renders. TITLE clears its
	# y322 legend; every other screen now carries the FOOTER_Y nav legend, so cap
	# the drop 5px above it — the selected-row glow (grow ~4.5) stays clear of the
	# footer even at the low point of the open animation, not just at rest.
	var floor_y := 321.0 if mode == Mode.TITLE else FOOTER_Y - 5.0
	g["top"] = float(g["top"]) + settle_offset(g, _open_t, main._motion, floor_y)
	return g


# Which row a point falls in, given a geometry dict — pure so the hit-test is
# unit-checkable. Extends each box by half the dead band so adjacent plates meet
# exactly (a gap point used to fall through to -1 and blink the highlight out).
static func hit_row(g: Dictionary, y: float) -> int:
	var pad := maxf(0.0, (float(g["gap"]) - float(g["bh"])) / 2.0)
	for k in int(g["n"]):
		var ry := row_rect(g, k).position.y   # same source _draw / the arrow hit-test build from
		if y >= ry - pad and y < ry + float(g["bh"]) + pad:
			return k
	return -1


# c1-04: lowest pixel a selected row's breathing glow can touch — its last-row
# rect bottom plus the max grow (3.0 + Art.pulse*1.5, pulse<=1). Pure so the
# layout test can prove it never reaches FOOTER_Y on the fullest PAUSE/OPTS list.
static func max_glow_bottom(g: Dictionary) -> float:
	return float(g["top"]) + float(int(g["n"]) - 1) * float(g["gap"]) + float(g["bh"]) + 4.5


# c1-12: single source of truth for a row's plate rect — _draw and the mouse
# hit-test both build the toggle-arrow boxes off this, so the x/width/height a
# horizontal-layout change touches lives in ONE place, not re-hardcoded per call
# site. Same floorf snapping _draw has always used (crisp pixel-font seams).
static func row_rect(g: Dictionary, k: int) -> Rect2:
	return Rect2(Vector2(320.0 - BTN.x / 2.0, floorf(float(g["top"]) + float(k) * float(g["gap"]))),
		Vector2(BTN.x, floorf(float(g["bh"]))))


# c1-12: single source of truth for the ◄/► cycle-arrow boxes on a toggle/volume
# row — _draw and the mouse hit-test both read this, so a layout tweak can't drift
# the visible arrow off its click target (same discipline as _row_geometry /
# _back_rect). Returns [left, right] as normalized visual rects (the left arrow is
# drawn flipped via a negative width, but its bounds are these). Takes the geometry
# dict + row index and derives EVERYTHING from it — the row rect via row_rect and
# the raw (unfloored) box height for the y-snap — so no caller can pass a bh that
# has drifted from the rect it belongs to.
static func toggle_arrow_rects(g: Dictionary, k: int) -> Array[Rect2]:
	var r := row_rect(g, k)
	var ay := floorf(r.position.y + float(g["bh"]) / 2.0) - ARROW_SZ / 2.0   # centered on cy, raw-bh snap == _draw
	var out: Array[Rect2] = [
		Rect2(r.position.x - ARROW_L_OFF, ay, ARROW_SZ, ARROW_SZ),
		Rect2(r.end.x + ARROW_R_GAP, ay, ARROW_SZ, ARROW_SZ),
	]
	return out


func _row_at(p: Vector2) -> int:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return 0 if _back_rect().has_point(p) else -1
	if absf(p.x - 320.0) > BTN.x / 2.0:
		return -1
	return hit_row(_row_geometry(), p.y)


## Single source of truth for the HALL/HOWTO back button geometry — _row_at and
## _draw_back_button both read it, so a tweak to one can't drift the click target
## off the pixels (same discipline as _row_geometry / panel_bottom()).
func _back_rect() -> Rect2:
	# 310 (was 320): pulled up so a real SELECT/BACK footer legend fits BELOW the
	# button (its glow bottom ~338, footer glyphs ~343). The HOWTO threat list's
	# pitch is DERIVED from this y (see _draw_howto), so it just tightens to ~14px
	# — still above its readable floor. Bottom lands at 335. Draw + hit-test share.
	return Rect2(Vector2(320 - BTN.x / 2.0, 310), BTN * Vector2(1, 0.7))


func _step_vol(bus: String, delta: int) -> void:
	# Single source for EVERY volume change: ◄/► AND Enter/click both flow through
	# here, so SFX/MUSIC share ONE model — a clamped 0..10 level where 0 == MUTED.
	# A muted bus counts as level 0 regardless of its stored volume_db (effective_
	# vol), so a step always lifts it off mute instead of sticking at a hidden 10.
	# _set_bus_vol maps 0 -> mute and keeps the UI+VO buses in lockstep (the old
	# direct mute-toggle only muted UI, leaving the radio VO blaring).
	var cur: int = effective_vol(_bus_off(bus), main._bus_vol(bus))
	var nv: int = step_level(cur, delta)
	if nv == cur:
		# Already at a rail (0/MUTED or 10). Not a silent no-op: flash the pinned
		# end segment so the press reads as "held at the limit," not "ignored." The
		# floor's own "deny" tick would be swallowed (SFX is muted there), so the
		# visual bounce is the reliable feedback — the top rail keeps its audible cue.
		_rail_dir = -1 if delta < 0 else 1
		_rail_row = sel
		_rail_pulse = 0.0 if main._motion < 0.5 else 1.0
		if delta > 0:
			main._sfx.play("deny", -16.0)   # top rail: SFX is audible, so a soft tick lands
		queue_redraw()
		return
	_rail_pulse = 0.0   # a real step lands — clear any stale bounce flash
	_rail_row = -1
	main._set_bus_vol(bus, nv)
	main._save_settings()
	# The tick doubles as a live level demo — pitch rides the new step.
	main._sfx.play("pickup", -14.0, 0.8 + 0.05 * float(nv))


func _activate() -> void:
	main._sfx.play("buy", -8.0)
	if mode == Mode.HALL or mode == Mode.HOWTO:
		# The lone BACK plate on the HALL/HOWTO content screens climbs to INFO.
		var d := _parent(mode)
		open(d["mode"], d["sel"])
		return
	var id: String = _menu_items()[sel]["id"]
	if mode == Mode.TITLE:
		match id:
			"campaign": main.start_game(false)
			"endless": main.start_game(true)
			"daily": main.start_daily()
			"watch": main.start_watch()
			"paste_seed": main.start_seed_from_clipboard()
			"run_setup": open(Mode.SETUP)   # run-config submenu, beside the start verbs
			"options":
				_opts_parent = Mode.TITLE   # BACK returns to TITLE
				open(Mode.OPTS)
			"info": open(Mode.INFO)   # the look-back screens (HALL / HOW TO / WATCH)
			"quit": get_tree().quit()
	else:
		match id:
			"resume": mode = Mode.HIDDEN
			"options":
				# c1-09: PAUSE fronts settings through ONE dedicated OPTIONS screen (the
				# six a11y/audio rows no longer live on the pause list). BACK returns here.
				_opts_parent = Mode.PAUSE
				open(Mode.OPTS)
			"back":
				# BACK climbs one level: OPTIONS returns to its opener, SETUP to TITLE.
				var d := _parent(mode)
				open(d["mode"], d["sel"])
			"hall": open(Mode.HALL)   # INFO screen link
			"watch": main.start_watch()   # WATCH LAST RUN lives on the INFO screen now
			"coop": main._two_players = not main._two_players   # run-setup toggle (SETUP); left/right + Enter share this path
			"hard": main._hard = not main._hard
			"howto": open(Mode.HOWTO)   # help screen under INFO; back returns here
			"sfx":
				# Enter/click nudges the SAME clamped 0..10 level as ◄/► (+1, stops at
				# 10) — one model, and it can never surprise-mute a player who meant to
				# nudge. Deliberate mute is stepping ◄ down to 0 (which reads MUTED).
				_step_vol("SFX", 1)
			"music":
				_step_vol("Music", 1)
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
			"display":
				# c1-09: the DISPLAY row flips fullscreen through the SAME path as the
				# F11/Alt+Enter shortcut (persist + cursor rebake), so the two agree.
				main._toggle_fullscreen()
			"reset_defaults":
				# c1-09: the two-press confirm already fired (destructive row → _press
				# arms, a second press lands here) — revert the shown settings to their
				# ship defaults and raise the "DEFAULTS RESTORED" banner as success feedback.
				# The rows below regenerate from state, so they show the restored values at once.
				# Snapshot reduce-motion BEFORE the reset (which re-enables motion): a
				# motion-sensitive player still gets a snapped, non-animated banner.
				_reset_flash_anim = main._motion >= 0.5
				main._reset_settings()
				_reset_flash = 1.6
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
		_footer_legend()
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
		# Height 13 (was 14): its 101..114 span now abuts the BEST plate's 114 top
		# instead of overlapping it by 1px — a double-darkened seam under the record.
		draw_rect(Rect2(320.0 - tgw / 2.0 - 4.0, 101.0, tgw + 8.0, 13.0),
			Color(0.03, 0.05, 0.03, 0.55))
		_center_text(tagline, 112, 10, Color(0.85, 0.9, 0.8, 0.85))
		# Read order: title → tagline → BRIGHT record line → dim CAREER → menu.
		# c1-02: the record block was pulled UP into a tight two-line stack (BEST
		# baseline 124, CAREER 136) from the old 132/145 spread — freeing ~14px so
		# the button column starts higher and every TITLE state clears a >=20px plate
		# instead of the old crush. _row_geometry's TITLE top tracks these baselines.
		if main.best_score > 0:
			# a2-04 HUD#8: only show the record fields that are non-zero (via a testable
			# helper) — a fresh best reads as a real record, not "WAVE 0 · 0m" debug dump.
			var best_line := _best_line(main.best_score, main.best_wave, main.best_dist)
			var bw := Art.font().get_string_size(best_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_rect(Rect2(320.0 - bw / 2.0 - 4.0, 114.0, bw + 8.0, 13.0),
				Color(0.03, 0.05, 0.03, 0.55))
			_center_text(best_line, 124, 9, Color(1.0, 0.92, 0.55, 1.0))
		if main._life_runs > 0:
			var wpct: int = main._life_wins * 100 / main._life_runs
			var career := "CAREER — %d RUNS · %d KILLS · %d%% WON" % [main._life_runs,
				main._life_kills, wpct]
			# Plated like the input legend: 8px dim text straight on the live
			# attract firefight loses to bright terrain no matter the alpha.
			var cpw := Art.font().get_string_size(career, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_rect(Rect2(320.0 - cpw / 2.0 - 4.0, 127.0, cpw + 8.0, 12.0),
				Color(0.03, 0.05, 0.03, 0.55))
			_center_text(career, 136, 8, Color(0.6, 0.72, 0.62, 0.7))
	elif mode == Mode.OPTS:
		_draw_opts_header()
	elif mode == Mode.INFO:
		_center_text("INFO", 84, 22, Color(0.95, 0.95, 0.85))
		# The look-back screens: records, the field manual, and your last run.
		_center_text("RECORDS · HOW TO PLAY · REPLAY", 104, 8, Color(0.8, 0.85, 0.72))
	elif mode == Mode.SETUP:
		_center_text("RUN SETUP", 84, 22, Color(0.95, 0.95, 0.85))
		# Say what the screen is for — the two toggles below decide the run you deploy.
		_center_text("PLAYERS & DIFFICULTY FOR YOUR NEXT DEPLOY", 104, 8,
			Color(0.8, 0.85, 0.72))
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
		var r := row_rect(g, k)
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
		if mode == Mode.OPTS and (k == 0 or mitems[k].get("grp", 0) != mitems[k - 1].get("grp", 0)):
			_emit_group_caption(mitems, k, cy)
		var selected := k == sel
		var destr: bool = k < mitems.size() and mitems[k].get("destructive", false)
		# armed REQUIRES destr: a stale/desynced _confirm landing on a non-destructive
		# row must never enter the armed render path (which reserves the confirm glyph
		# and floods red) — that would draw a null glyph. destr guarantees armed_glyph.
		var armed := destr and _confirm == k
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		# Destructive rows (RESTART / TITLE / QUIT) tint the WHOLE plate warm, not
		# just the label — so they never read as a plain single-press action beside
		# CAMPAIGN / RESUME. The tint is DARK warm on purpose: light warm label text
		# over it clears an AA-normal (4.5:1) contrast target (a mid warm plate washed the
		# warm label out — see test_destructive_text_contrast). Arming floods red.
		var plate := Color(1.0, 0.92, 0.55) if selected else Color(0.55, 0.62, 0.45, 0.8)
		if destr:
			if selected:
				plate = DESTR_ARMED_PLATE_SEL if armed else DESTR_PLATE_SEL
			else:
				plate = DESTR_ARMED_PLATE_UNSEL if armed else DESTR_PLATE_UNSEL
		draw_texture_rect(Art.tex("ui_menu_button"), r, false, plate)
		if armed:
			# Armed red flood drawn FIRST — before the bracket, icon and selection
			# glow — so those cues layer ON TOP of the wash instead of being washed
			# out by it. A strong (near-opaque) fill: the old 0.4 wash over the whole
			# thing barely shifted the plate. Slow pulse pulls the eye; reduce-motion
			# snaps it steady. The countdown bar + confirm glyph land later, on top.
			# Alpha stays high across the pulse (0.82..0.98) so the near-white armed
			# label keeps its measured contrast over the flood at BOTH pulse extremes,
			# not just the trough — the underplate barely reads through either way.
			var apulse := 0.0 if main._motion < 0.5 else Art.pulse(0.25)
			var flood := DESTR_ARMED_FLOOD
			flood.a = 0.82 + 0.16 * apulse
			draw_rect(r.grow(-3), flood)
		if destr:
			# A warm bracket outlines destructive rows even BEFORE arming — a shape
			# cue (not hue alone) that this row discards the run, unlike its
			# neighbors. It thickens and brightens once armed.
			draw_rect(r.grow(-2), Color(1.0, 0.55, 0.35, 0.95 if armed else 0.55),
				false, 2.0 if armed else 1.0)
		# Modern Menus ortho icon where a row has a clean match (toggles swap
		# by live state) — rows without one just stay text.
		var icon := _row_icon(mitems[k]["id"])
		if icon != "":
			# Track the row: a taller decompressed row earns a bigger icon instead
			# of pinning to an 8px speck. bh-3 keeps a 1px breath each side; 9px
			# floor still centers cleanly in the worst-case 11px crush row.
			var isz := clampf(bh - 3.0, 9.0, 16.0)
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
			# Skip the AMBER glow while armed: the red flood + bright bracket already
			# mark the armed row hard, and the amber wash on top would fight (and dull)
			# the red danger treatment. Selection still tracked above for the glide.
			if not armed:
				draw_texture_rect(Art.tex("ui_menu_button_sel"), gr.grow(3.0 + mp * 1.5), false,
					Color(1.0, 0.9, 0.4, (0.7 + mp * 0.3) * (1.0 - 0.5 * lag)))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		var label: String = items[k]
		var label_r := r.end.x - 8.0   # label right bound (shrinks for the confirm glyph)
		var armed_glyph: Texture2D = null
		var cw := 0.0
		if destr:
			# LIGHT warm label so it stays legible on the dark warm plate (a warm-dim
			# label on a warm plate failed the contrast target). The dark plate + warm
			# label together read "danger" while staying readable.
			col = DESTR_TEXT_SEL if selected else DESTR_TEXT_UNSEL
			if armed:
				col = DESTR_ARMED_TEXT   # near-white reads over the red flood below
				# Reserve the right-edge confirm-glyph slot BEFORE choosing wording so
				# the label is fit to the real drawable width, not an optimistic one.
				armed_glyph = Art.tex(Art.glyph_key("confirm"))
				cw = 12.0 * float(armed_glyph.get_width()) / float(armed_glyph.get_height())
				label_r = r.end.x - cw - 10.0
			# Pick the widest wording that actually fits the plate (measured), so the
			# cue never ellipsizes to nonsense: "<NAME>  PRESS TWICE" states the two-press
			# contract pre-armed; armed keeps the VERB alongside "PRESS AGAIN" where it
			# fits, degrading only as far as needed. See destructive_label.
			label = destructive_label(items[k], String(mitems[k]["id"]).to_upper().replace("_", " "),
				armed, Art.font(), label_r - (r.position.x + 30.0))
		if armed:
			# The armed affordances that ride ON TOP of the red flood (drawn above):
			# a countdown bar draining along the bottom edge showing the disarm
			# window, and the device confirm glyph in its reserved right slot.
			draw_rect(Rect2(r.position.x + 3.0, r.end.y - 5.0,
				(r.size.x - 6.0) * clampf(_confirm_t / 2.5, 0.0, 1.0), 2.0),
				Color(1.0, 0.62, 0.3, 0.95))
			draw_texture_rect(armed_glyph, Rect2(r.end.x - cw - 6.0, cy - 6.0, cw, 12.0), false)
		# Rows that open a screen reserve a right-edge slot for the > chevron so a
		# long label ellipsizes clear of it instead of colliding.
		if mitems[k].get("submenu", false):
			label_r = minf(label_r, r.end.x - 20.0)
		# Fixed icon gutter: iconless rows indent the same, so every label
		# left-aligns to one column. Overlong labels ellipsize inside the button.
		var lx := r.position.x + 30.0
		Art.text(self, _ellipsize(label, 11, label_r - lx),
			Vector2(lx, cy + 4.0), 11, col)
		# Submenu affordance: a right-pointing chevron marks rows that OPEN a screen
		# (RUN SETUP / OPTIONS / INFO / HALL / HOW TO PLAY) so they don't read as a
		# direct action or an in-place toggle. mi_arrow already points right.
		if mitems[k].get("submenu", false):
			draw_texture_rect(Art.tex("mi_arrow"), Rect2(r.end.x - 17.0, cy - 5.0, 10.0, 10.0),
				false, Color(1.0, 0.92, 0.55) if selected else Color(0.72, 0.77, 0.62, 0.85))
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
			# Rail bounce: a nudge past the limit (mute floor or max ceiling) flashes
			# the pinned end segment amber+wider so the press reads as "held at the
			# rail," not dropped. Decays in _process; reduce-motion snaps it off.
			if selected and k == _rail_row and _rail_pulse > 0.0:
				var rseg := 9 if _rail_dir > 0 else 0   # ceiling = last cell, floor = first
				var rr := Rect2(vbx + float(rseg) * 5.0, cy - 3.0, 4.0, 6.0).grow(_rail_pulse * 1.5)
				draw_rect(rr, Color(1.0, 0.72, 0.3, 0.85 * _rail_pulse), false, 1.0)
			# STATIC rail cap: whenever the selected row SITS at a limit (MUTED or 10),
			# bracket the pinned end segment. Non-animated, so it reads even with
			# Reduce Motion on — where the bounce above is snapped off, a further
			# press at the rail would otherwise be an invisible (and, at the muted
			# floor, silent) no-op. This makes "you're at the limit" always legible.
			if selected and (vv == 0 or vv == 10):
				var cseg := 9 if vv == 10 else 0
				draw_rect(Rect2(vbx + float(cseg) * 5.0, cy - 4.0, 4.0, 8.0),
					Color(1.0, 0.72, 0.3, 0.7), false, 1.0)
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
			var arows := toggle_arrow_rects(g, k)   # shared with the mouse hit-test
			var lft := arows[0]
			# left arrow drawn flipped: start at its right edge, negative width
			draw_texture_rect(at, Rect2(lft.position.x + lft.size.x, lft.position.y, -lft.size.x, lft.size.y), false, fcol)
			draw_texture_rect(at, arows[1], false, fcol)
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
	else:
		# c1-04: PAUSE/OPTS/SETUP get the same SELECT/BACK footer (HALL/HOWTO are
		# handled in the content-well branch, which returns before this point).
		_footer_legend()


func _draw_back_button() -> void:
	var r := _back_rect()
	draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
	draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false, Color(1.0, 0.9, 0.4, 0.95))
	draw_rect(r, Color(1.0, 0.97, 0.88), false, 1.0)   # focus ring (only row here)
	_center_text("BACK", r.position.y + 16.0, 11, Color(1.0, 0.95, 0.75))


# Pure per-tab visual treatment for the HALL filter row — text color plus whether
# a plate and an underline are drawn, and their colors/height. Selected = full cue
# (dark plate + 2px live underline), hover = dimmer plate + 1px preview underline +
# brightened text, idle = neither (transparent plate, 0 height). Single-sourced so
# _draw_hall and the render test can't drift; static + view-free so it runs headless.
static func hall_tab_style(on: bool, hov: bool, filter_pulse: float) -> Dictionary:
	var col := Color(1.0, 0.95, 0.65) if on else Color(0.6, 0.66, 0.56, 0.8)
	if on and filter_pulse > 0.0:
		col = col.lightened(filter_pulse * 0.45)
	elif hov and not on:
		col = Color(0.95, 0.98, 0.82)   # hover lifts text to near-selected brightness
	var out := {"text": col, "plate": Color(0, 0, 0, 0), "underline": Color(0, 0, 0, 0), "underline_h": 0.0}
	if on:
		out["plate"] = Color(0.05, 0.08, 0.04, 0.9)
		out["underline"] = Color(1.0, 0.9, 0.4, 0.9 + filter_pulse * 0.1)
		out["underline_h"] = 2.0
	elif hov:
		out["plate"] = Color(0.14, 0.19, 0.12, 0.7)   # dimmer echo of the selected plate
		out["underline"] = Color(0.9, 0.85, 0.5, 0.55)
		out["underline_h"] = 1.0
	return out


static func hall_rank_text(over_cap: bool, index: int) -> String:
	# The exact rank string _draw_hall stamps in the "#" column. A run pinned past
	# the cap (over_cap) has no exact rank — discarded runs may sit above it, and
	# under a mode filter a global "41+" would clash with the per-filter row numbers
	# — so it reads as an unranked dash, never a false slot. Pure so draw + test agree.
	return "--" if over_cap else str(index + 1)


static func hall_latest_dir(latest_idx: int, page: int, rows_per_page: int) -> int:
	# Which page-button leads toward the latest run when it's OFF the current page:
	# -1 = earlier page (PREV), +1 = later page (NEXT), 0 = on this page or no latest.
	# Drives the paged-away marker so the run you opened the board for is never lost —
	# once you page off it, an arrow points the way back. Pure so draw + test agree.
	if latest_idx < 0:
		return 0
	@warning_ignore("integer_division")
	var lp := latest_idx / rows_per_page
	return -1 if lp < page else (1 if lp > page else 0)


static func hall_latest_legend(over_cap: bool) -> String:
	# The exact recency-ribbon legend text. An over-cap run spells out OUTSIDE TOP 40
	# so its "--" rank reads as unranked, not blank. Single-sourced with the draw.
	return ("= YOUR LATEST RUN (OUTSIDE TOP %d)" % HALL_KEEP) if over_cap else "= YOUR LATEST RUN"


static func hall_page_window(page: int, total: int) -> Vector2i:
	# [start, stop) row indices _draw_hall draws on `page`. The final page is a
	# partial window — stop clamps to `total`. Single-sourced so the draw loop, the
	# latest-on-page legend gate, and the render test all read one windowing rule.
	var start := page * HALL_PAGE_ROWS
	return Vector2i(start, mini(start + HALL_PAGE_ROWS, total))


static func hall_page_rects() -> Array[Rect2]:
	# Clickable PREV/NEXT page targets flanking the centered "- PAGE x / y -" footer
	# at baseline y306. Static + view-free (fixed pixel geometry) so _draw_hall, the
	# click hit-test, and the render test all read ONE source and can't drift.
	# [prev, next], centers 213/427 — mirror-symmetric about the 320 counter axis so
	# the pair frames the page count evenly. 50x16 (was a cramped 30x16 that only
	# covered the word); the bottom edge (y306) clears the HALL BACK button's DRAWN
	# plate (its texture is _back_rect.grow(3), top y307), so the two clickable controls
	# never overlap. Both clear the ~95px centered counter (edges 238/402).
	return [Rect2(188.0, 290.0, 50.0, 16.0), Rect2(402.0, 290.0, 50.0, 16.0)]


static func hall_page_style(enabled: bool, hov: bool, press: float) -> Dictionary:
	# PREV/NEXT button visual state, single-sourced so _draw_hall and a headless test
	# read ONE truth (same idiom as hall_tab_style). A boundary button is dim with no
	# plate ("can't go further"); an enabled one carries a resting fill so it reads as a
	# real target, brightens on hover, and flashes on press.
	if not enabled:
		return {"text": Color(0.45, 0.47, 0.42, 0.55), "plate": Color(0, 0, 0, 0)}
	var text := Color(0.9, 0.86, 0.5)
	var plate := Color(0.14, 0.19, 0.12, 0.55)   # resting fill so the target reads as a button
	if press > 0.0:
		text = Color(1.0, 1.0, 0.88).lightened(press * 0.1)   # punchiest state — brightest text + plate
		plate = Color(0.3, 0.36, 0.18, 0.9)
	elif hov:
		text = Color(0.98, 0.98, 0.82)
		plate = Color(0.2, 0.26, 0.16, 0.78)
	return {"text": text, "plate": plate}


func _hall_page_rects() -> Array[Rect2]:
	return hall_page_rects()


func _page_hover_at(pos: Vector2) -> int:
	# Which page button (0 = PREV, 1 = NEXT, -1 = none) a pointer at `pos` hovers — only
	# when the board pages and only over an ENABLED button, so a boundary button never
	# lights. One source for the live motion hover AND the still-cursor refresh below.
	if mode != Mode.HALL:
		return -1
	var pages := _hall_pages(_hall_rows().size())
	if pages <= 1:
		return -1
	var prc := _hall_page_rects()
	if prc[0].has_point(pos) and _hall_page > 0:
		return 0
	if prc[1].has_point(pos) and _hall_page < pages - 1:
		return 1
	return -1


func _refresh_page_hover() -> void:
	# A page or filter change flips which buttons are boundary-disabled; re-evaluate the
	# hover against the LAST pointer position so a STILL cursor immediately gains the cue
	# on a button that just became enabled and loses it on one that just became a boundary
	# — without waiting for the next mouse move.
	var ph := _page_hover_at(_last_ptr)
	if ph != _page_hover:
		_page_hover = ph
		queue_redraw()


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
		var hov := not on and i == _tab_hover
		# Text color + plate/underline treatment come from ONE pure helper so the
		# selected/hover/idle cues are single-sourced and a headless test can pin
		# the hover plate+underline without a GL surface (same idiom as the pure
		# geometry statics above).
		var st := hall_tab_style(on, hov, _filter_pulse)
		var plate: Color = st["plate"]
		if plate.a > 0.0:
			# Filled plate under the live tab (the underline alone read as decoration,
			# not state) — a dimmer echo for the hover preview so the pointer's target
			# reads as a real button, not just tinted text.
			draw_rect(Rect2(tr.position.x, 54.0, tr.size.x, 16.0), plate)
		Art.text(self, names[i], Vector2(tr.position.x + 4.0, 66), 10, st["text"])
		var uh: float = st["underline_h"]
		if uh > 0.0:
			# Underline: 2px live rule for the selected tab, a fainter 1px preview on
			# hover so it clearly reads as "click to make this the live filter".
			draw_rect(Rect2(tr.position.x + 2.0, 70.0, tr.size.x - 4.0, uh), st["underline"])
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
	var rows := _hall_rows()
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
	# Headers at y96 (was y92): dropped 4px so the y82 recency band above clears them
	# at the real font metrics (see HALL_RECENCY_Y) — the two lines no longer collide.
	for c in headers.size():
		if c == 1:
			var hw := f.get_string_size(headers[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			Art.text(self, headers[c], Vector2(214.0 - hw, 96), 10, Color(1.0, 0.82, 0.4))
		else:
			Art.text(self, headers[c], Vector2(col_x[c], 96), 10, Color(1.0, 0.82, 0.4))
	# RANK header sits in the gap between the # and the right-aligned SCORE — drawn
	# outside the parallel header/col_x arrays so it doesn't reshuffle the columns.
	Art.text(self, "RANK", Vector2(130.0, 96), 10, Color(1.0, 0.82, 0.4))
	# Page the board: HALL_PAGE_ROWS rows per screen, up/down turns the page. The
	# clamp catches a page stranded past the end after the filter shrank the list.
	var pages := _hall_pages(rows.size())
	_hall_page = clampi(_hall_page, 0, pages - 1)
	var win := hall_page_window(_hall_page, rows.size())
	var start: int = win.x
	var stop: int = win.y   # last page is a partial window (clamped to the row count)
	var latest_idx := _hall_latest_index(rows)   # which row (if any) is the just-banked run — hid-matched
	# Status band at the TOP (its own band, clear of the paging counter and BACK): it
	# both flags the just-banked run AND states the board's retention outright, so the
	# TOP-<HALL_KEEP> cutoff is exposed here rather than silently dropping older runs off
	# the bottom. Full width, so the long combined variants never clip. The bottom counter
	# has no room for the cap (it'd collide with the PREV/NEXT buttons), so it lives here.
	var keep_note := "KEEPS TOP %d" % HALL_KEEP
	if latest_idx >= 0:
		@warning_ignore("integer_division")
		var lpage := latest_idx / HALL_PAGE_ROWS
		if lpage == _hall_page:
			var over: bool = (rows[latest_idx] as Dictionary).get("over_cap", false)
			# The over-cap legend already spells out "(OUTSIDE TOP N)"; the in-cap one
			# doesn't, so pin the retention beside it either way.
			var msg := hall_latest_legend(over)
			if not over:
				msg += "   ·   " + keep_note
			_center_text(msg, HALL_RECENCY_Y, 9, Color(1.0, 0.86, 0.55))
		else:
			var dir := "<<" if lpage < _hall_page else ">>"
			_center_text("%s YOUR LATEST RUN IS ON PAGE %d %s   ·   %s" % [dir, lpage + 1, dir, keep_note],
				HALL_RECENCY_Y, 9, Color(1.0, 0.82, 0.4))
	else:
		# No fresh run to flag — the band states the retention rule so a returning player
		# still sees the cutoff (paging resolves hidden entries; it doesn't hide the cap).
		_center_text("BOARD KEEPS YOUR TOP %d RUNS" % HALL_KEEP, HALL_RECENCY_Y, 9,
			Color(0.82, 0.86, 0.72))
	for i in range(start, stop):
		var run: Dictionary = rows[i]
		var row := i - start   # 0..HALL_PAGE_ROWS-1 within this page (drives the y baseline)
		var is_latest := i == latest_idx
		var mode_s: String = "ENDLESS" if run.get("mode", "campaign") == "endless" else "CAMPAIGN"
		var reached: String = "WAVE %d" % run.get("wave", 0) if run.get("mode", "campaign") == "endless" \
			else ("VICTORY" if run.get("won", false) else "SECTOR %d" % run.get("sector", 0))
		var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.9, 0.82)
		if is_latest:
			col = Color(1.0, 0.86, 0.5)   # the run you just finished — warm recency tint
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
		var y := 112 + row * 24   # rows stay at 112 (header @96 already clears row0's box top 102 by 4px); pushing them down crowds the 8th row's glow into the page buttons
		if is_latest:
			# Glow band + a warm ribbon down the left edge so the run you opened the
			# board for reads instantly, wherever it ranks. Drawn under the cells.
			draw_rect(Rect2(100.0, y - 12.0, 528.0, 20.0), Color(1.0, 0.7, 0.2, 0.15))
			draw_rect(Rect2(100.0, y - 12.0, 3.0, 20.0), Color(1.0, 0.75, 0.25, 0.95))
			# A right-pointing caret in the left gutter (x104..110, the gap before the #
			# column @112) — a SHAPE marker so the highlighted row is identifiable without
			# relying on the warm tint alone (the top-band "= YOUR LATEST RUN" legend reads
			# this same "=" idea), keeping the cue legible to color-blind players.
			draw_colored_polygon(PackedVector2Array([Vector2(104.0, y - 6.0),
				Vector2(110.0, y - 2.0), Vector2(104.0, y + 2.0)]),
				Color(1.0, 0.8, 0.35, 0.95))
		var rank_s := hall_rank_text(run.get("over_cap", false), i)
		var cells := [rank_s, Art.group_digits(int(run.get("score", 0))), mode_s, reached, streak_s]
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
	# Footer: a single compact page-counter row framed by the PREV/NEXT buttons, only
	# when the board spills past one page (a single-page board needs no paging chrome).
	# The whole paging line sits on ONE row at y306 — clear of the BACK plate (top y310)
	# below it. The old second "UP/DOWN TO TURN THE PAGE" hint line lived at y322, INSIDE
	# the BACK plate band; the labeled PREV/NEXT buttons + the counter now carry the
	# affordance without a hint line that collided with the primary exit control.
	if pages > 1:
		# Compact page counter (the retention cap is stated in the top status band — it
		# won't fit here without colliding with the flanking PREV/NEXT buttons).
		_center_text("- PAGE %d / %d -" % [_hall_page + 1, pages], 306, 11, Color(1.0, 0.85, 0.4))
		# Mouse-clickable page buttons flanking the counter — the mouse had no way to page
		# (wheel cycles the filter here). Each carries a VERTICAL arrow glyph, not just a
		# word: paging is bound to UP/DOWN (left/right is the filter), so a horizontal cue
		# would read as the wrong axis. UP = earlier page (0), DOWN = later page (1) — the
		# same mapping the keyboard/pad up/down nav uses. Symmetric plates frame the
		# counter; each carries a resting fill, brightens on hover, and flashes on press —
		# a boundary button stays dim and plate-less so it reads as "can't go further".
		var pr := _hall_page_rects()
		var pen := [_hall_page > 0, _hall_page < pages - 1]
		var plbl := ["PREV", "NEXT"]
		for pi in 2:
			var pst := hall_page_style(pen[pi], _page_hover == pi,
				_page_press if _page_press_side == pi else 0.0)
			var pcol: Color = pst["text"]
			var pplate: Color = pst["plate"]
			if pplate.a > 0.0:
				draw_rect(pr[pi], pplate)
			# Vertical arrow glyph + label, centered as a unit in the rect. The triangle
			# (up for PREV, down for NEXT) is the primary axis cue; the word confirms it.
			var lw := f.get_string_size(plbl[pi], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			var gw := 7.0
			var bx := pr[pi].position.x + (pr[pi].size.x - lw - gw - 2.0) / 2.0
			var ay := 302.0
			var pts := PackedVector2Array()
			if pi == 0:   # up-triangle: apex at top
				pts = PackedVector2Array([Vector2(bx + gw / 2.0, ay - 6.0),
					Vector2(bx, ay - 1.0), Vector2(bx + gw, ay - 1.0)])
			else:         # down-triangle: apex at bottom
				pts = PackedVector2Array([Vector2(bx, ay - 6.0),
					Vector2(bx + gw, ay - 6.0), Vector2(bx + gw / 2.0, ay - 1.0)])
			draw_colored_polygon(pts, pcol)
			Art.text(self, plbl[pi], Vector2(bx + gw + 2.0, ay), 9, pcol)
			# Paged AWAY from your latest run: a warm dot on the button that leads back to
			# it (the top-band "ON PAGE n" cue names the page) so the run you opened the
			# board for is never simply gone — the recency payoff survives a full board.
			var ldir := hall_latest_dir(latest_idx, _hall_page, HALL_PAGE_ROWS)
			if ldir != 0 and pi == (0 if ldir < 0 else 1):
				draw_rect(Rect2(pr[pi].get_center().x - 2.0, pr[pi].position.y - 3.0, 4.0, 4.0),
					Color(1.0, 0.75, 0.25, 0.95))


func _hall_rows() -> Array:
	# The score-ordered runs visible under the current filter (ALL shows all). The
	# .get fallbacks guard old save rows that predate the "mode" key. Single-sourced
	# so paging math (_hall_pages / _nav) and _draw_hall can't disagree on the count.
	var rows: Array = []
	for run in main.hall:
		if _hall_filter == 1 and run.get("mode", "campaign") == "endless":
			continue
		if _hall_filter == 2 and run.get("mode", "campaign") != "endless":
			continue
		rows.append(run)
	return rows


func _hall_pages(n: int) -> int:
	return maxi(1, (n + HALL_PAGE_ROWS - 1) / HALL_PAGE_ROWS)


func _hall_latest_page() -> int:
	# Page index holding the run just banked into the Hall (main.hall_latest), so
	# opening the board lands on it. 0 when there's no fresh run or it's off-board.
	var idx := _hall_latest_index(_hall_rows())
	return idx / HALL_PAGE_ROWS if idx >= 0 else 0


func _hall_latest_index(rows: Array) -> int:
	# Index of the just-banked run within `rows`, or -1 when it isn't shown. Matched
	# by its unique "hid" — value-equal twins (same score/sector) are common on the
	# board, so deep-equality (`in` / Array.has) would highlight the wrong row; hid
	# pins the EXACT run. Falls back to reference identity for a pre-hid latest.
	# Object.get() (not `.`) so a headless stub without the field returns null,
	# not a crash — the guard short-circuits before reading rows.
	var latest: Variant = main.get("hall_latest") if main != null else null
	if latest == null or (latest as Dictionary).is_empty():
		return -1
	var ld: Dictionary = latest
	var has_hid: bool = ld.has("hid")
	for i in rows.size():
		var r: Dictionary = rows[i]
		if has_hid:
			if r.has("hid") and int(r["hid"]) == int(ld["hid"]):
				return i
		elif is_same(r, ld):
			return i
	return -1


func _draw_howto() -> void:
	_center_text("HOW TO PLAY", 34, 22, Color(1.0, 0.85, 0.3))
	# The whole screen runs off ONE downward y cursor instead of ~20 hand-tuned
	# baselines, so editing a row can't silently overlap its neighbour. The one
	# hard constraint — the ranged-threat block must clear the BACK plate — is
	# DERIVED from _back_rect() below (pitch + box size fall out of it) rather
	# than pinned to a magic number, so it survives roster edits.
	var y := 60.0
	var hold_pre := "pays to REVIVE you or BUY supplies (hold"
	var intro := [
		["ONE HIT AND YOU DROP. The War Chest — shared coin from kills —", Color(1.0, 0.9, 0.6)],
		[hold_pre, Color(0.85, 0.9, 0.8)],
	]
	for row in intro:
		Art.text(self, row[0], Vector2(60, y), 11, row[1])
		y += 15.0
	# The supply-wheel hold prompt is the DEVICE GLYPH, not a key-name string —
	# it sits at the end of the second intro line (baseline y - 15).
	var wy := y - 15.0
	var px := 60.0 + Art.font().get_string_size(hold_pre, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 9.0
	Art.draw_glyph(self, "wheel", Vector2(px, wy - 4.0), 12.0)
	Art.text(self, "). That's the choice.", Vector2(px + 8.0, wy), 11, Color(0.85, 0.9, 0.8))
	y += 10.0
	# Verb lines carry the actual input glyph inline (device-aware) — text-only
	# verbs made players hunt the legend. Re-wrapped for the wider pixel font:
	# >64 chars clips at x=640.
	_verb_line(["@grenade", "GRENADES crack armor — bunkers, bosses, the Colossus."],
		y, Color(0.9, 0.92, 0.8))
	y += 15.0
	_verb_line(["Bullets don't. ", "@roll", "ROLL to dodge. ", "@interact",
		"BOARD tanks for crush + shells."], y, Color(0.9, 0.92, 0.8))
	y += 15.0
	_verb_line(["@interact", "with no tank near PLANTS a carried claymore — it hurts BOTH sides."],
		y, Color(0.9, 0.92, 0.8))
	y += 16.0
	# The enemy roster with live sprites.
	# sol-08: front the LIVE red-team sprites the player now sees (rusher/elite draw the pack enemy_* cel bakes).
	var roster := [["enemy_smg", "RUSHER — charges, touch kills"],
		["enemy_assault", "ELITE — keeps range, telegraphs one shot"],
		["frogman", "FROGMAN — lurks in water, grenades only"]]
	for r in roster:
		_draw_sprite_fit(r[0], Rect2(80, y - 15, 20, 18), Art.tint(r[0]))
		Art.text(self, r[1], Vector2(108, y), 10, Color(0.9, 0.92, 0.82), 612.0 - 108.0)
		y += 18.0
	y += 4.0
	# Endless War fields ranged specialists (wave 3+) — teach their counters.
	Art.text(self, "ENDLESS WAR — RANGED THREATS:", Vector2(60, y), 10, Color(1.0, 0.7, 0.4))
	y += 13.0
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
	# Threat rows are the tight spot, so their pitch is DERIVED, not typed: fit
	# every row's text baseline between here (`y`) and the last baseline the BACK
	# plate allows (its grow(3) top, less the box's +3 overhang and a 1px margin).
	# Pitch is the fit value capped at 18 and NEVER clamped upward, so the last
	# baseline lands at-or-below the limit for ANY roster size — a grown roster
	# just tightens the pitch, it can never push a row into BACK. floorf keeps it
	# on whole pixels (a fractional pitch smears pixel-art rows). The box is sized
	# `pitch - 1`, so consecutive boxes always keep a >=1px gap — the collision
	# the old fixed 26px box at 10px pitch baked in cannot recur. Sprites draw
	# cropped to their opaque bounds (see _draw_sprite_fit), so even a tight box
	# shows a full body instead of the old ~7px speck the padded bakes gave.
	var last_max := _back_rect().position.y - 7.0
	var readable := 13.0   # 10px text needs ~3px leading to stay legible
	var pitch := 18.0
	if special.size() > 1:
		pitch = floorf(minf(18.0, (last_max - y) / float(special.size() - 1)))
	# Two invariants, checked for BOTH the seven authored rows and any grown
	# roster: the block never collides with BACK (pure fit, no upward clamp), and
	# it never teaches below a legible pitch. If a future roster overflows, the
	# readable assert trips in debug — the signal to paginate rather than to
	# silently shrink rows to specks. Release strips asserts; the pure-fit pitch
	# still can't collide, it just tightens.
	assert(y + float(special.size() - 1) * pitch <= last_max)
	assert(pitch >= readable)
	var box: float = maxf(1.0, pitch - 1.0)
	# Descriptions are width-clamped to the frame interior so a long tip clips
	# with an ellipsis instead of bleeding through the chrome at x=640.
	var text_w := 612.0 - 76.0
	for i in special.size():
		var sy := y + i * pitch
		_draw_sprite_fit(special[i][0], Rect2(50, sy - box + 3.0, box, box), special[i][1])
		Art.text(self, special[i][2], Vector2(76, sy), 10, Color(0.88, 0.9, 0.8), text_w)


# The bakes carry huge transparent margins (a 64px sprite whose body is ~18px),
# so draw_texture_rect stretches mostly-empty texture into a box and the visible
# body collapses to a speck. Cache each sprite's opaque bounds once and draw
# ONLY that region, aspect-preserved and centered — a small box then shows a
# full body. Cache is keyed by sprite name (bakes are immutable at runtime).
static var _trim_cache := {}


func _visible_region(key: String) -> Rect2:
	if not _trim_cache.has(key):
		var t := Art.tex(key)
		var img := t.get_image() if t != null else null
		var full := Rect2(Vector2.ZERO, t.get_size()) if t != null else Rect2()
		if img != null:
			var used := img.get_used_rect()
			_trim_cache[key] = Rect2(used) if used.size.x > 0 and used.size.y > 0 else full
		else:
			_trim_cache[key] = full
	return _trim_cache[key]


# Draw a sprite's opaque region cropped and centered inside `box`, aspect kept.
func _draw_sprite_fit(key: String, box: Rect2, mod: Color) -> void:
	var t := Art.tex(key)
	if t == null:
		return
	var reg := _visible_region(key)
	var s := minf(box.size.x / reg.size.x, box.size.y / reg.size.y)
	# Snap size and position to whole pixels — fractional dst rects blur pixel art.
	var dst := (Vector2(reg.size.x, reg.size.y) * s).round()
	var pos := (box.position + (box.size - dst) / 2.0).round()
	draw_texture_rect_region(t, Rect2(pos, dst), reg, mod)


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


# c1-09: the OPTIONS screen header — a compact 2-line block (title y80 / summary y94)
# so the 8-row settings list seats at top=102 and still clears a >=20px plate. Extracted
# so a headless capture test can invoke the REAL header draw (through _center_text, which
# a test subclass records) and prove it renders, at what y, and with what text — not just
# that some string fits some width. Settings ONLY now: HALL OF FAME / HOW TO PLAY moved
# to the INFO screen, so this header is a plain "OPTIONS".
func _draw_opts_header() -> void:
	_center_text("OPTIONS", 80, 18, Color(0.95, 0.95, 0.85))
	# After RESET DEFAULTS fires, the summary line briefly becomes a success banner;
	# otherwise it's the single place to review live settings state — the DISPLAY mode
	# (no on-screen toggle) and EVERY accessibility aid's explicit ON/OFF state.
	if _reset_flash > 0.0:
		# A player who HAD reduce-motion on when they reset gets the banner at steady
		# full alpha (no fade ramp) — captured pre-reset, since the reset itself turns
		# motion back on. It still clears on its timer; only the animation is snapped.
		var ba := clampf(_reset_flash / 0.6, 0.0, 1.0) if _reset_flash_anim else 1.0
		_center_text("DEFAULTS RESTORED", 94, 9, Color(0.55, 0.95, 0.5, ba))
	elif _menu_items()[sel]["id"] == "reset_defaults":
		# When focus is on RESET DEFAULTS, the summary line names EXACTLY what the
		# two-press confirm will wipe — every settings group at once — so the player
		# knows the blast radius BEFORE the second press, not just "this is destructive".
		_center_text("RESET RESTORES AUDIO / HAPTICS / ACCESSIBILITY / DISPLAY TO DEFAULTS",
			94, 8, Color(0.95, 0.72, 0.42))
	else:
		_center_text(a11y_summary(main._motion < 0.5, main.colorblind, main._assist,
			main._rumble_on, main._fullscreen), 94, 8, Color(0.8, 0.85, 0.72))


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
# Static so the layout test can measure the ACTUAL device-dependent glyph widths.
static func _glyph_w(seg: Dictionary) -> float:
	if seg.has("act"):
		return _LEG_H
	var key: String = seg.get("tex", "glyph_key_wide" if seg.has("stamp") else "")
	if key == "":
		return 0.0
	var t := Art.tex(key)
	return _LEG_H * float(t.get_width()) / float(t.get_height())


# c1-04: pure geometry of a centered legend row — [left_x, total_width]. The SAME
# measure _legend_row's draw loop uses (single source), so a headless test can pin
# the ACTUAL on-screen footer/verb bounds — which depend on the last-used device,
# since pad button glyphs and keyboard keycaps differ in width — instead of a
# re-derived approximation.
static func legend_extent(segs: Array) -> Array:
	var f := Art.font()
	var total := -14.0   # segments separated by 14px; first one has no gap
	for seg in segs:
		var gw := _glyph_w(seg)
		total += gw + (3.0 if gw > 0.0 else 0.0) \
			+ f.get_string_size(seg.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 14.0
	return [320.0 - total / 2.0, total]


# c1-04: the EXACT drawn boxes of a legend row — one entry per segment carrying its
# glyph rect (empty for text-only), its label text rect, and the source seg. This
# is the single list _legend_row iterates to draw, so it IS the actual render result
# (glyph AND rendered label/font footprints), not a re-derivation — a headless test
# reads these boxes to prove nothing clips 640x360 or overlaps, in either device
# mode. `y` is the glyph center; label baseline sits at y+3 (8px font, ~8px ascent).
static func legend_primitives(segs: Array, y: float) -> Array:
	var f := Art.font()
	var ext := legend_extent(segs)
	var x: float = ext[0]
	var out: Array = []
	for seg in segs:
		var gw := _glyph_w(seg)
		var grect := Rect2()
		if gw > 0.0:
			grect = Rect2(x, y - _LEG_H / 2.0, gw, _LEG_H)
			x += gw + 3.0
		var lsz := f.get_string_size(seg.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		# Real font metrics (measured width + ascent/height), not a hard-coded 8/9px
		# box: Art.text places the baseline at y+3, so the ink spans up by the ascent.
		var lrect := Rect2(x, y + 3.0 - f.get_ascent(8), lsz.x, lsz.y)
		out.append({"seg": seg, "glyph": grect, "label": lrect})
		x += lsz.x + 14.0
	return out


# c1-04: draw seams — every native draw the footer/legend emits routes through one of
# these one-line indirections, so a headless test subclass can OVERRIDE them to CAPTURE
# the exact draw commands _footer_legend/_legend_row actually issue (proving they run,
# and with what geometry) without a live draw context. Default impls do the real draw.
func _emit_rect(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
func _emit_tex(key: String, r: Rect2, c: Color) -> void:
	draw_texture_rect(Art.tex(key), r, false, c)
func _emit_glyph(act: String, center: Vector2, size: float, c: Color) -> void:
	Art.draw_glyph(self, act, center, size, c)
func _emit_stamp(txt: String, pos: Vector2, c: Color) -> void:
	draw_string(Art.font(), pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)
func _emit_label(txt: String, pos: Vector2, c: Color) -> void:
	Art.text(self, txt, pos, 8, c)


# c1-09: OPTIONS settings groups get a named caption (AUDIO / HAPTICS / ACCESSIBILITY)
# at the first row of each group, right-aligned in the left margin — its right edge at
# plate_left-25, clear of the selected-row cycle arrow (drawn at plate_left-13) — so the
# screen reads as three labelled sections, not one flat list. Routed through _emit_label
# so a headless capture test can invoke this REAL caption draw and inspect the exact box.
func _emit_group_caption(mitems: Array, k: int, cy: float) -> void:
	var ghdr := group_header(mitems[k].get("grp", 0))
	if ghdr == "":
		return
	var gw := Art.font().get_string_size(ghdr, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_emit_label(ghdr, Vector2((320 - BTN.x / 2.0) - 25.0 - gw, cy + 3.0), Color(0.66, 0.72, 0.56, 0.85))


# One centered legend line of [glyph + verb] segments; y is the glyph center. Emits
# straight off legend_primitives (through the seams above) so the pixels land exactly
# where the test measures — and the capture test sees the real commands.
func _legend_row(segs: Array, y: float, a: float) -> void:
	var f := Art.font()
	for p in legend_primitives(segs, y):
		var seg: Dictionary = p["seg"]
		var grect: Rect2 = p["glyph"]
		if grect.size.x > 0.0:
			if seg.has("act"):
				# Pass the row alpha so action glyphs fade with the texture glyphs and
				# labels (they used to draw at full opacity, off from the rest of the row).
				_emit_glyph(seg["act"], grect.get_center(), _LEG_H, Color(1, 1, 1, a))
			else:
				_emit_tex(seg.get("tex", "glyph_key_wide"), grect, Color(1, 1, 1, a))
				if seg.has("stamp"):
					var st: String = seg["stamp"]
					var sw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
					_emit_stamp(st, Vector2(grect.position.x + (grect.size.x - sw) / 2.0, y + 2.0),
						Color(0.15, 0.16, 0.12, a))
		_emit_label(seg.get("label", ""), Vector2(p["label"].position.x, y + 3.0),
			Color(0.82, 0.87, 0.77, a))


# c1-04: input legend BEYOND the TITLE screen. One SELECT/BACK footer on EVERY
# non-TITLE screen (PAUSE / OPTS / SETUP / HALL / HOWTO), drawn with the real
# device-aware prompt art (Enter/A, Esc/B) — so keyboard/pad players don't lose
# nav discovery after first launch. One shared strip position (FOOTER_Y), pinned
# clear of the selected-row glow (see _row_geometry's drop cap + the layout test).
# PAUSE additionally carries the PERMANENT ROLL/WHEEL/REVIVE reference (footer_segs),
# so the in-run HUD reminder can stay purely transient without those bindings
# becoming unrecoverable mid-run.
func _footer_legend() -> void:
	_emit_rect(Rect2(0, FOOTER_Y, 640, 17), Color(0.03, 0.05, 0.03, 0.55))
	var segs := footer_segs(mode)
	# c1-13: when the Hall spills past one page, the footer strip carries an EXPLICIT
	# UP/DOWN = PAGE key hint. The PREV/NEXT plates flank the counter left/right, but the
	# input axis is vertical (left/right cycles the FILTER), so the control strip states
	# the real key here — the one place players read for bindings. Only in HALL and only
	# when it actually pages; guarded on main so the headless capture menu (no board) skips.
	if mode == Mode.HALL and main != null and _hall_pages(_hall_rows().size()) > 1:
		segs = footer_page_segs() + segs
	_legend_row(segs, FOOTER_Y + 8.0, 0.9)


# c1-04: the SELECT / BACK footer segments, device-aware via Art.glyph_key (the
# same registry the TITLE SELECT glyph uses): Enter / Esc keycaps on keyboard
# (BACK stamped ESC, like the WASD/MOVE cap), A / B buttons on a pad. Pulled out
# so a headless test can prove the kb<->pad glyph swap without a Control or draw.
static func footer_nav_segs() -> Array:
	var nav: Array = [{"tex": Art.glyph_key("confirm"), "label": "SELECT"},
		{"tex": Art.glyph_key("back"), "label": "BACK"}]
	if not Art.use_pad:
		nav[1]["stamp"] = "ESC"   # kb back is a bare keycap; stamp it like WASD/MOVE
	return nav


# c1-04: the PERMANENT ROLL / WHEEL / REVIVE reference. The in-run HUD reminder is
# TRANSIENT now (it fades out so it never continuously overlays the playfield), so
# PAUSE — the one menu reachable mid-run — carries these bindings permanently: a
# player who forgot them pauses and re-reads them. "act" keys resolve device-aware
# through Art.draw_glyph, same as the TITLE legend's verb row.
static func footer_verb_segs() -> Array:
	return [{"act": "roll", "label": "ROLL"},
		{"act": "wheel", "label": "SUPPLY WHEEL"},
		{"act": "revive", "label": "REVIVE"}]


# c1-04: the full footer legend a screen draws — SELECT/BACK nav on every non-TITLE
# screen, with the gameplay-verb reference prepended on PAUSE (the mid-run recovery
# screen). Pure so the render test can pin the exact drawn segments and their bounds.
static func footer_segs(mode_id: int) -> Array:
	if mode_id == Mode.PAUSE:
		return footer_verb_segs() + footer_nav_segs()
	return footer_nav_segs()


# c1-13: the explicit paging key hint for the Hall footer — a wide keycap stamped with
# the up/down axis and a PAGE label. Both keyboard arrows and pad dpad page on up/down,
# so one axis-stamped cap reads on either device. Static so a headless test can pin it.
static func footer_page_segs() -> Array:
	return [{"tex": "glyph_key_wide", "stamp": "UP/DN", "label": "PAGE"}]
