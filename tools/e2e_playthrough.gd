extends SceneTree
# E2E playthrough QA tool — complements the unit suite by driving the WHOLE game like a
# player. Run:  Godot --headless --path . -s res://tools/e2e_playthrough.gd
# (exit 0 = all green, 1 = a check failed).
#
# It instantiates the real main scene and drives every menu (TITLE / SETUP / MODES /
# CHAPTERS / OPTS / REBIND / PAUSE) by SYNTHESIZED MOUSE CLICKS through the real
# _unhandled_input hit-test path — so a dead/misaligned row or a broken transition fails
# here the way it would under a real cursor. It also exercises the destructive two-press
# confirm, the pause→resume "stays live" regression, and a 240-frame gameplay drive.
# Reports [E2E] lines; any [E2E FAIL] is a bug. SCRIPT ERRORs surface on stderr (grep them).

var GM: Script
var fails: Array[String] = []
var main

func rec(cond: bool, msg: String) -> void:
	if cond:
		_oks += 1
		print("[E2E] ok: ", msg)
	else:
		fails.append(msg)
		print("[E2E FAIL] ", msg)

func idx_of(menu, id: String) -> int:
	var items: Array = menu._menu_items()
	for i in items.size():
		if String(items[i].get("id", "")) == id:
			return i
	return -1

# Synthesize a real LMB click at the drawn center of row `id`. Returns the hit-tested
# row index (should equal the target row) or -2 if the id isn't present in this mode.
func click_id(menu, id: String) -> int:
	var k := idx_of(menu, id)
	if k < 0:
		return -2
	menu._open_t = 1.0   # settle so geometry is at rest (deterministic)
	var g: Dictionary = menu._row_geometry()
	var r: Rect2 = menu.row_rect(g, k)
	var c: Vector2 = r.position + r.size * 0.5
	var hit: int = menu._row_at(c)
	rec(hit == k, "row '%s' (idx %d) click-center hit-tests to itself (got %d)" % [id, k, hit])
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c
	menu._unhandled_input(ev)
	return hit

func open(menu, mode: int) -> void:
	menu.open(mode)
	menu._open_t = 1.0

func _init() -> void:
	GM = load("res://src/view/menu.gd")
	var scene: PackedScene = load("res://src/main.tscn")
	main = scene.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var menu = main._menu

	# --- Boot: splash up, menu HIDDEN, then reveal TITLE ---
	rec(main._splash_layer != null and main._splash_layer.visible, "boot: splash overlay up")
	main._end_splash()
	rec(menu.mode == GM.Mode.TITLE, "after splash: TITLE revealed")

	# --- Hit-test EVERY row of EVERY menu mode (catches dead/misaligned rows) ---
	# Just enter each mode and click every row-center back to itself (no activation side effects tested here).
	for mode_name in ["TITLE", "SETUP", "MODES", "OPTS", "PAUSE"]:
		var m: int = GM.Mode[mode_name]
		# PAUSE needs a live run behind it
		if mode_name == "PAUSE":
			main.start_game(false)
		open(menu, m)
		var n: int = menu._items().size()
		rec(n > 0, "%s: has %d rows" % [mode_name, n])
		var g: Dictionary = menu._row_geometry()
		for k in n:
			var r: Rect2 = menu.row_rect(g, k)
			var c: Vector2 = r.position + r.size * 0.5
			rec(menu._row_at(c) == k, "%s row %d ('%s') center hit-tests to itself" % [mode_name, k, String(menu._menu_items()[k].get("id",""))])

	# --- TITLE transitions ---
	open(menu, GM.Mode.TITLE)
	click_id(menu, "campaign")
	rec(menu.mode == GM.Mode.HIDDEN and main.sim != null and main.sim.mode == "campaign", "TITLE > CAMPAIGN starts a campaign run")

	open(menu, GM.Mode.TITLE)
	click_id(menu, "endless")
	rec(menu.mode == GM.Mode.HIDDEN and main.sim.mode == "endless", "TITLE > ENDLESS starts an endless run")

	open(menu, GM.Mode.TITLE)
	click_id(menu, "setup")
	rec(menu.mode == GM.Mode.SETUP, "TITLE > SETUP opens SETUP")

	# --- SETUP transitions ---
	click_id(menu, "modes")
	rec(menu.mode == GM.Mode.MODES, "SETUP > MODES opens MODES")

	open(menu, GM.Mode.SETUP)
	click_id(menu, "options")
	rec(menu.mode == GM.Mode.OPTS, "SETUP > OPTIONS opens OPTS")

	open(menu, GM.Mode.SETUP)
	click_id(menu, "info")
	rec(menu.mode == GM.Mode.INFO, "SETUP > INFO opens INFO")

	open(menu, GM.Mode.SETUP)
	click_id(menu, "back")
	rec(menu.mode == GM.Mode.TITLE, "SETUP > BACK returns to TITLE")

	# --- MODES transitions ---
	open(menu, GM.Mode.MODES)
	click_id(menu, "boss_rush")
	rec(menu.mode == GM.Mode.HIDDEN and main.sim != null, "MODES > BOSS RUSH starts a run")

	open(menu, GM.Mode.MODES)
	click_id(menu, "arcade")
	rec(menu.mode == GM.Mode.HIDDEN and main.sim != null, "MODES > ARCADE starts a run")

	open(menu, GM.Mode.MODES)
	var chres := click_id(menu, "chapter_select")
	if chres != -2:
		rec(menu.mode == GM.Mode.CHAPTERS, "MODES > CHAPTER SELECT opens CHAPTERS")
		# chapter 1
		open(menu, GM.Mode.CHAPTERS)
		var c1 := click_id(menu, "ch1")
		rec(c1 == -2 or menu.mode == GM.Mode.HIDDEN, "CHAPTERS > CH1 starts a run (or no chapters defined)")

	open(menu, GM.Mode.MODES)
	click_id(menu, "back")
	rec(menu.mode == GM.Mode.SETUP, "MODES > BACK returns to SETUP")

	# --- OPTS: controls submenu + back ---
	open(menu, GM.Mode.OPTS)
	click_id(menu, "controls")
	rec(menu.mode == GM.Mode.REBIND, "OPTS > CONTROLS opens REBIND")
	open(menu, GM.Mode.REBIND)
	click_id(menu, "back")
	rec(menu.mode != GM.Mode.REBIND, "REBIND > BACK leaves REBIND")

	# --- PAUSE flow: THE regression — resume must actually resume and STAY resumed ---
	main.start_game(false)
	var tick0: int = main.sim.tick_count
	open(menu, GM.Mode.PAUSE)
	rec(menu.mode == GM.Mode.PAUSE, "PAUSE opens over a live run")
	click_id(menu, "resume")
	rec(menu.mode == GM.Mode.HIDDEN, "PAUSE > RESUME hides the menu (run resumes)")
	# drive a few physics frames; must stay resumed and advance
	for i in 8:
		main._physics_process(1.0 / 60.0)
	rec(menu.mode == GM.Mode.HIDDEN, "after RESUME + 8 frames the run stays live (no phantom re-pause)")
	rec(main.sim.tick_count > tick0, "sim advanced after RESUME (tick %d > %d)" % [main.sim.tick_count, tick0])

	# PAUSE > OPTIONS
	open(menu, GM.Mode.PAUSE)
	click_id(menu, "options")
	rec(menu.mode == GM.Mode.OPTS, "PAUSE > OPTIONS opens OPTS")

	# PAUSE > destructive QUIT TO TITLE (arm then confirm = two clicks)
	open(menu, GM.Mode.PAUSE)
	click_id(menu, "title")
	click_id(menu, "title")
	rec(menu.mode == GM.Mode.TITLE, "PAUSE > QUIT TO TITLE (two-press confirm) returns to TITLE")

	# --- Real gameplay drive: 240 physics frames, no crash, sim advances ---
	open(menu, GM.Mode.TITLE)
	click_id(menu, "campaign")
	var g0: int = main.sim.tick_count
	for i in 240:
		main._physics_process(1.0 / 60.0)
	rec(main.sim.tick_count >= g0 + 200, "gameplay: 240 frames advanced the sim (%d ticks)" % (main.sim.tick_count - g0))
	rec(main.sim.players.size() > 0, "gameplay: player(s) present after the drive")

	# --- Report ---
	print("")
	print("[E2E] === %d checks, %d FAIL ===" % [_total(), fails.size()])
	for f in fails:
		print("[E2E FAIL] " + f)
	main.free()
	quit(1 if fails.size() > 0 else 0)

var _oks := 0
func _total() -> int:
	return _oks + fails.size()
