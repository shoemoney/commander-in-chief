extends RefCounted
## FRONT DOOR package: co-op one press away on the title, a splash that respects repeat
## launches, a daily that feels daily, and CHAPTER SELECT surfaced once it is earned.
## Everything runs through the REAL Menu / Main code (stubs only where the suite already uses
## them); the pure rules live in src/view/front_door.gd and are driven with explicit clocks.

const Runner := preload("res://tests/run_tests.gd")
const Menu := preload("res://src/view/menu.gd")
const MainScript := preload("res://src/main.gd")
const Layout := preload("res://tests/test_menu_layout.gd")

const DAY := 86400


func _row(m: Control, id: String) -> Dictionary:
	for r in m._menu_items():
		if r["id"] == id:
			return r
	return {}


func _title(stub: Node) -> Control:
	var m: Control = Menu.new()
	m.main = stub
	m.mode = Menu.Mode.TITLE
	return m


func _start_press(device: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = JOY_BUTTON_START
	ev.pressed = true
	return ev


# --- pure rules -------------------------------------------------------------------------

func test_streak_rules_grow_hold_and_reset_honestly() -> void:
	Runner.T.eq(FrontDoor.streak_after_play(-1, 0, 100), 1, "first ever daily starts a streak of 1")
	Runner.T.eq(FrontDoor.streak_after_play(99, 4, 100), 5, "playing the day after extends the streak")
	Runner.T.eq(FrontDoor.streak_after_play(100, 4, 100), 4, "a second deal the same day does not double count")
	Runner.T.eq(FrontDoor.streak_after_play(97, 9, 100), 1, "a gap restarts the streak at 1")
	Runner.T.eq(FrontDoor.live_streak(99, 4, 100), 4, "yesterday's streak is still alive today")
	Runner.T.eq(FrontDoor.live_streak(98, 4, 100), 0, "a streak last played two days ago already reads as broken")


func test_countdown_and_score_text() -> void:
	Runner.T.eq(FrontDoor.countdown_text(5 * 3600 + 13 * 60 + 59), "5H13M", "countdown reads hours + minutes")
	Runner.T.eq(FrontDoor.countdown_text(-5), "0H00M", "a negative remainder clamps")
	Runner.T.eq(FrontDoor.score_text(1234567), "1,234,567", "scores get thousands separators")
	Runner.T.eq(FrontDoor.seconds_to_next_board(5 * DAY + 18 * 3600 + 47 * 60), 5 * 3600 + 13 * 60,
		"seconds to the next board count down to local midnight")


func test_unlock_and_splash_length_rules() -> void:
	Runner.T.ok(not FrontDoor.chapters_unlocked(1), "sector 1 does not unlock CHAPTER SELECT")
	Runner.T.ok(FrontDoor.chapters_unlocked(2), "sector 2 unlocks it")
	Runner.T.eq(FrontDoor.splash_length(false, 16.0), 16.0, "first boot plays the full intro")
	Runner.T.eq(FrontDoor.splash_length(true, 16.0), FrontDoor.SPLASH_SHORT, "repeat boots get the short card")
	Runner.T.ok(FrontDoor.SPLASH_SHORT <= 3.0 and FrontDoor.SPLASH_SHORT > MainScript.SPLASH_SKIP_ARM,
		"the short card is <= 3 s and outlasts the skip arming second")


# --- (a) P2 join on the title -----------------------------------------------------------

func test_second_pad_start_toggles_two_player_and_badges_the_rows() -> void:
	var stub := Layout._StubMain.new()
	var m := _title(stub)
	Runner.T.eq(String(_row(m, "campaign").get("badge", "")), "", "1P: no badge on CAMPAIGN")
	# START from pad 0 is the normal confirm: it must NOT flip co-op.
	m._unhandled_input(_start_press(0))
	Runner.T.ok(not stub._two_players, "START on pad 0 does not toggle two-player")
	stub._starts.clear()   # pad 0's START is the normal confirm and launched the focused row
	m.sel = 0
	m._unhandled_input(_start_press(1))
	Runner.T.ok(stub._two_players, "START on the second pad joins P2")
	Runner.T.eq(stub._starts.size(), 0, "joining never launches the focused row")
	m._mark_dirty()
	Runner.T.eq(String(_row(m, "campaign").get("badge", "")), "2P", "CAMPAIGN carries the 2P badge")
	Runner.T.eq(String(_row(m, "endless").get("badge", "")), "2P", "ENDLESS WAR carries the 2P badge")
	Runner.T.ok(m._p2_banner_t > 0.0 and m._p2_banner.contains("P2 JOINED"), "a join banner is armed")
	m._unhandled_input(_start_press(1))
	Runner.T.ok(not stub._two_players, "a second press on the second pad leaves co-op again")
	m._mark_dirty()
	Runner.T.eq(String(_row(m, "campaign").get("badge", "")), "", "...and the badge goes away")
	# Title only: no join from another screen.
	m.mode = Menu.Mode.PAUSE
	m._unhandled_input(_start_press(1))
	Runner.T.ok(not stub._two_players, "no drop-in outside the title")
	m.free()
	stub.free()


func test_p2_hint_and_banner_are_drawn_on_screen() -> void:
	var stub := Layout._StubMain.new()
	var cap := Layout._CaptureMenu.new()
	cap.main = stub
	cap.mode = Menu.Mode.TITLE
	var seg: Dictionary = cap.title_p2_seg()
	Runner.T.eq(seg["label"], "P2 JOIN", "1P: the hint offers to join")
	cap._legend_row([seg], 330.0, 0.9)
	var hint := _label_box(cap.ops, "P2 JOIN")
	Runner.T.ok(hint.size.x > 0.0 and Rect2(0, 0, 640, 360).encloses(hint), "the P2 hint is measured on screen: %s" % hint)
	Runner.T.ok(_has_stamp(cap.ops), "the hint carries a stamped START cap (glyph-aware)")
	stub._two_players = true
	Runner.T.eq(cap.title_p2_seg()["label"], "P2 LEAVE", "2P: the hint offers to leave")
	cap.ops.clear()
	cap._p2_banner = "TWO PLAYERS - P2 JOINED"
	cap._p2_banner_t = 1.0
	cap._draw_title_p2_banner()
	var ban := _label_box(cap.ops, "TWO PLAYERS - P2 JOINED")
	Runner.T.ok(ban.size.x > 0.0 and Rect2(0, 0, 640, 360).encloses(ban) and ban.position.y >= 339.0,
		"the banner is drawn below the legend strip, on screen: %s" % ban)
	cap.free()
	stub.free()


func _label_box(ops: Array, text: String) -> Rect2:
	for op in ops:
		if String(op.get("id", "")) == text and op.has("box"):
			return op["box"]
	return Rect2()


func _has_stamp(ops: Array) -> bool:
	for op in ops:
		if op.get("k", "") == "stamp":
			return true
	return false


# --- (b) splash respects repeat launches -------------------------------------------------

func _stash_save() -> Array:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var moved := []
	for f in [path, bak]:
		if FileAccess.file_exists(f):
			DirAccess.rename_absolute(f, f + ".fd")
			moved.append(f)
	return moved


func _restore_save(moved: Array) -> void:
	for f in [MainScript.SAVE_PATH, MainScript.SAVE_BAK]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	for f in moved:
		DirAccess.rename_absolute(f + ".fd", f)


func _new_main() -> Node2D:
	var main: Node2D = MainScript.new()
	main._sfx.free()
	main._sfx = Layout._NullSfx.new()
	return main


func test_second_boot_uses_the_short_splash_and_full_intro_replays() -> void:
	var moved := _stash_save()
	var first := _new_main()
	first._load_bests()
	first._setup_splash()
	Runner.T.eq(first._splash_len, MainScript.SPLASH_DUR, "first boot plays the full intro")
	Runner.T.eq(first._splash_t, MainScript.SPLASH_DUR, "...with the full timer")
	Runner.T.ok(first.front.intro_seen, "the intro is marked seen")

	var second := _new_main()
	second._load_bests()
	Runner.T.ok(second.front.intro_seen, "the seen flag survived the relaunch (persisted)")
	second._setup_splash()
	Runner.T.eq(second._splash_len, FrontDoor.SPLASH_SHORT, "second boot uses the short splash")
	Runner.T.eq(second._splash_t, FrontDoor.SPLASH_SHORT, "...with the short timer")
	# Still skippable once armed, still dead before it (the c-title-sting guarantee).
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	second._splash_t = FrontDoor.SPLASH_SHORT - 0.4
	Runner.T.ok(not second._splash_is_skip(key), "a press in the first second is still swallowed")
	second._splash_t = FrontDoor.SPLASH_SHORT - 1.2
	Runner.T.ok(second._splash_is_skip(key), "after the arming second the short splash is skippable")
	# WATCH INTRO restores the full cinematic.
	second.replay_intro()
	Runner.T.eq(second._splash_t, MainScript.SPLASH_DUR, "WATCH INTRO re-arms the full 16 s intro")
	Runner.T.ok(second._splash_layer.visible, "...and shows the overlay")
	first.free()
	second.free()
	_restore_save(moved)


func test_info_screen_hosts_watch_intro() -> void:
	var stub := Layout._StubMain.new()
	var m := _title(stub)
	m.mode = Menu.Mode.INFO
	var row := _row(m, "intro")
	Runner.T.ok(not row.is_empty(), "INFO lists a WATCH INTRO row")
	m.sel = m._menu_items().find(row)
	m._activate()
	Runner.T.eq(stub._replays, 1, "activating it replays the intro")
	m.free()
	stub.free()


func test_pre_front_saves_count_as_seen_and_recover_sector_from_the_hall() -> void:
	var moved := _stash_save()
	var cf := ConfigFile.new()
	cf.set_value("life", "runs", 12)
	cf.set_value("hall", "runs", [{"score": 100, "sector": 3, "hid": 0}])
	cf.save(MainScript.SAVE_PATH)
	var main := _new_main()
	main._load_bests()
	Runner.T.ok(main.front.intro_seen, "a veteran save (runs on record) is not shown the full intro again")
	Runner.T.eq(main.front.max_sector, 3, "furthest sector is recovered from the hall")
	main.free()
	_restore_save(moved)


# --- (c) the daily row -------------------------------------------------------------------

func test_daily_row_locked_open_streak_and_broken() -> void:
	var day := 20000
	FrontDoor.clock_override = day * DAY + 18 * 3600 + 47 * 60   # 5h13m before the next board
	var stub := Layout._StubMain.new()
	var m := _title(stub)
	# Open, no streak: plain.
	var r := _row(m, "daily")
	Runner.T.eq(r["label"], "DAILY RUN", "open daily with no streak is plain")
	# Open with a live streak: the chip rides the label.
	stub.front.streak = 3
	stub.front.streak_day = day - 1
	m._mark_dirty()
	Runner.T.eq(_row(m, "daily")["label"], "DAILY RUN x3", "a live streak shows as a chip")
	# Locked with a banked score: score + grade + countdown.
	stub._daily_done = true
	stub.front.note_daily_score(day, 12340, "A")
	m._mark_dirty()
	r = _row(m, "daily")
	Runner.T.eq(String(r["badge"]), "12,340 A  5H13M", "locked row shows today's score, grade and the countdown")
	Runner.T.ok(r.get("disabled", false), "...and stays locked")
	# Locked but yesterday's score must not be shown as today's.
	stub.front.note_daily_score(day - 1, 999, "S")
	m._mark_dirty()
	Runner.T.eq(String(_row(m, "daily")["badge"]), "COMPLETED  5H13M", "a stale score is not shown as today's")
	# Broken streak: two days since the last play => chip is gone.
	stub.front.streak_day = day - 2
	m._mark_dirty()
	Runner.T.eq(_row(m, "daily")["label"], "DAILY RUN", "a broken streak resets honestly (no chip)")
	FrontDoor.clock_override = -1
	m.free()
	stub.free()


func test_dealing_the_daily_advances_and_persists_the_streak() -> void:
	var moved := _stash_save()
	var main := _new_main()
	main._daily = true
	main._reset()   # the real start path: spends the attempt and advances the streak
	var today := FrontDoor.today()
	Runner.T.eq(main.front.streak, 1, "first daily dealt starts the streak")
	Runner.T.eq(main.front.streak_day, today, "...stamped with today")
	var reload := _new_main()
	reload._load_bests()
	Runner.T.eq(reload.front.streak, 1, "the streak survives a relaunch")
	Runner.T.eq(reload.front.streak_day, today, "...and its day")
	main._record_run(main.sim.score)
	reload._load_bests()
	Runner.T.eq(reload.front.daily_day, today, "the banked daily score is dated today")
	Runner.T.eq(reload.front.daily_score, main.sim.score, "...and persisted")
	main.free()
	reload.free()
	_restore_save(moved)


# --- (d) CHAPTER SELECT surfaces once earned ---------------------------------------------

func test_chapter_select_row_appears_only_after_sector_two() -> void:
	var stub := Layout._StubMain.new()
	var m := _title(stub)
	Runner.T.ok(_row(m, "chapter_select").is_empty(), "fresh player: no CHAPTER SELECT on the title")
	stub.front.max_sector = 2
	m._mark_dirty()
	var rows: Array = m._menu_items()
	var ci := -1
	var si := -1
	for i in rows.size():
		if rows[i]["id"] == "chapter_select":
			ci = i
		if rows[i]["id"] == "setup":
			si = i
	Runner.T.ok(ci >= 0, "after reaching sector 2 the row appears")
	Runner.T.ok(ci < si, "...inside the DEPLOY block, before SETUP")
	Runner.T.eq(int(rows[ci]["grp"]), 0, "...as a DEPLOY row")
	var prev := -1
	for row in rows:
		Runner.T.ok(int(row["grp"]) >= prev, "TITLE rows stay grouped in order")
		prev = int(row["grp"])
	# Activating opens the picker and BACK returns to the title row.
	m.sel = ci
	m._activate()
	Runner.T.eq(m.mode, Menu.Mode.CHAPTERS, "activating opens the chapter picker")
	var back: Dictionary = m._parent(Menu.Mode.CHAPTERS)
	Runner.T.eq(back["mode"], Menu.Mode.TITLE, "BACK returns to the title")
	Runner.T.eq(back["sel"], "chapter_select", "...with the row refocused")
	m.free()
	stub.free()


func test_title_with_the_new_row_stays_single_column_and_clears_the_legend() -> void:
	for has_best in [false, true]:
		var head: float = Menu.title_head_bottom(has_best, true)
		var g: Dictionary = Menu.compute_geometry(Menu.Mode.TITLE, 6, head, 4, Menu.TITLE_BLOCK_GAP)
		Runner.T.eq(int(g["cols"]), 1, "6 title rows (chapter row unlocked) stay one column (best=%s)" % has_best)
		Runner.T.ok(Menu.row_rect(g, 5).end.y < Menu.LEGEND_Y, "...and the last plate clears the legend")
