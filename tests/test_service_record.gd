extends RefCounted
## service-record: per-sector MEDALS, best rank per mode, the RECORD tab on the Hall and the
## "NEW MEDAL" debrief call-out. Everything goes through the real thing: the tracker reads a real
## SimWorld's events/chest, the bank goes through main._apply_score_verdict -> _record_run (the
## verified-run gate the Hall and Steam upload use), the save round-trips through the real
## [service] section of the save file, and the tab is drawn by the real menu code.

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const SR := preload("res://src/view/service_record.gd")


class _NullSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


## Records the menu's real ink + textures so the page can be audited without a GL surface.
class _RecMenu extends GameMenu:
	var ops: Array = []
	func _emit_tex(key: String, r: Rect2, _c: Color) -> void:
		ops.append({"k": "tex", "id": key, "box": r})
	func _emit_rect(r: Rect2, _c: Color) -> void:
		ops.append({"k": "rect", "id": "", "box": r})


func _stash_save(tag: String) -> Dictionary:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var stash := path + tag
	var stashb := bak + tag
	if FileAccess.file_exists(stash) and not FileAccess.file_exists(path):
		DirAccess.rename_absolute(stash, path)
	if FileAccess.file_exists(stashb) and not FileAccess.file_exists(bak):
		DirAccess.rename_absolute(stashb, bak)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, stash)
	if FileAccess.file_exists(bak):
		DirAccess.rename_absolute(bak, stashb)
	return {"path": path, "bak": bak, "stash": stash, "stashb": stashb}


func _restore_save(s: Dictionary) -> void:
	if FileAccess.file_exists(s["path"]):
		DirAccess.remove_absolute(s["path"])
	if FileAccess.file_exists(s["bak"]):
		DirAccess.remove_absolute(s["bak"])
	if FileAccess.file_exists(s["stash"]):
		DirAccess.rename_absolute(s["stash"], s["path"])
	if FileAccess.file_exists(s["stashb"]):
		DirAccess.rename_absolute(s["stashb"], s["bak"])


func _main() -> Node2D:
	var main: Node2D = MainScript.new()
	main._sfx.free()
	main._sfx = _NullSfx.new()
	return main


## A fresh campaign Main whose tracker is fed by hand-built sim events (the exact seam the live
## hook uses: svc.observe(sim) after each step).
func _campaign(main: Node2D) -> void:
	main._endless = false
	main._boss_rush = false
	main._arcade_chapter = -1
	main._daily = false
	main._reset()
	main._menu.mode = GameMenu.Mode.HIDDEN


func _tick(main: Node2D, tick: int, events: Array) -> void:
	main.sim.tick_count = tick
	main.sim.events.clear()
	main.sim.events.append_array(events)
	main.svc.observe(main.sim)


func _clear_gate(main: Node2D, tick: int) -> void:
	main.sim.gates.append({"open": true})
	_tick(main, tick, [{"t": "gate_open"}])


func _bank(main: Node2D, opened: int) -> void:
	main._recorder = null
	main._debrief = true
	main._result_t = 1.0
	main._apply_score_verdict(0, true)


func _texts(ops: Array) -> Array:
	var out: Array = []
	for o in ops:
		if o.get("k", "") == "text":
			out.append(String(o["id"]))
	return out


# --- the rules ---------------------------------------------------------------------

func test_medal_rules_each_earn_and_non_earn() -> void:
	var par := SR.par_ticks(3)
	Runner.T.eq(SR.medals_for_clear(3, par, 0, false), SR.FLAWLESS | SR.SWIFT | SR.HOARDER, "clean, at par, no spend = all three")
	Runner.T.eq(SR.medals_for_clear(3, par, 1, false) & SR.FLAWLESS, 0, "one knockdown loses FLAWLESS")
	Runner.T.eq(SR.medals_for_clear(3, par, 1, false) & SR.SWIFT, SR.SWIFT, "a knockdown does not touch SWIFT")
	Runner.T.eq(SR.medals_for_clear(3, par + 1, 0, false) & SR.SWIFT, 0, "one tick over par loses SWIFT")
	Runner.T.eq(SR.medals_for_clear(3, par, 0, true) & SR.HOARDER, 0, "spending the chest loses HOARDER")
	Runner.T.eq(SR.medals_for_clear(3, par, 0, true) & SR.FLAWLESS, SR.FLAWLESS, "spending does not touch FLAWLESS")


func test_pars_are_generous_against_measured_bot_clears() -> void:
	# Slowest god-mode bot clear per sector, seeds 1-5 (see ServiceRecord.PAR_TICKS). A recorded
	# snapshot, kept only for the "still a real time to beat" ceiling: the generosity FLOOR is now
	# measured live in test_review2_meta.gd. Sectors 5/6 re-measured 2026-11-10 with the Siege Tank
	# in the tree (S5 was 1860 on the tree that predated its boss).
	var measured := [553, 1024, 2803, 3092, 4886, 1827]
	for i in SR.SECTORS:
		Runner.T.ok(SR.PAR_TICKS[i] >= int(measured[i] * 1.5), "sector %d par leaves >=1.5x the slowest bot clear" % (i + 1))
		Runner.T.ok(SR.PAR_TICKS[i] <= measured[i] * 2, "sector %d par is still a real time to beat (<=2x)" % (i + 1))


func test_eligibility_follows_the_hall_separation() -> void:
	Runner.T.ok(SR.medals_eligible("campaign", false, false), "a plain campaign run can earn")
	Runner.T.ok(not SR.medals_eligible("campaign", false, true), "assisted / perked: no")
	Runner.T.ok(not SR.medals_eligible("campaign", true, false), "the daily: no")
	Runner.T.ok(not SR.medals_eligible("arcade", false, false), "arcade (and so RETRY SECTOR / chapter starts): no")
	Runner.T.ok(not SR.medals_eligible("endless", false, false), "endless: no")
	Runner.T.ok(not SR.medals_eligible("boss_rush", false, false), "boss rush: no")


# --- the tracker, on a real sim ------------------------------------------------------

func test_tracker_reads_knockdown_time_and_chest_per_sector() -> void:
	var s := _stash_save(".srtest1")
	var main := _main()
	_campaign(main)
	# Sector 1: a knockdown, fast, no spend.
	_tick(main, 100, [{"t": "player_down"}])
	_clear_gate(main, 500)
	# Sector 2: clean, but slower than par (par 1800).
	_clear_gate(main, 500 + SR.par_ticks(2) + 1)
	# Sector 3: clean + fast, but the chest is spent mid-sector.
	main.sim.war_chest = 400
	_tick(main, 3000, [])          # chest rises: not a spend
	main.sim.war_chest = 250
	_tick(main, 3010, [])          # chest drops: a spend
	_clear_gate(main, 3100)
	var e: Array[int] = main.svc.earned_this_run()
	Runner.T.eq(e[0], SR.SWIFT | SR.HOARDER, "S1: knockdown costs FLAWLESS only")
	Runner.T.eq(e[1], SR.FLAWLESS | SR.HOARDER, "S2: over par costs SWIFT only")
	Runner.T.eq(e[2], SR.FLAWLESS | SR.SWIFT, "S3: spending the chest costs HOARDER only")
	main.free()
	_restore_save(s)


func test_terminal_chest_bank_is_not_a_spend() -> void:
	var s := _stash_save(".srtest2")
	var main := _main()
	_campaign(main)
	for g in 5:
		_clear_gate(main, 100 * (g + 1))
	main.sim.war_chest = 900
	_tick(main, 700, [])
	main.sim.war_chest = 0   # the win pays the chest out
	_tick(main, 800, [{"t": "victory"}])
	var e: Array[int] = main.svc.earned_this_run()
	Runner.T.eq(e[5] & SR.HOARDER, SR.HOARDER, "the victory bank zeroing the chest is not a purchase")
	Runner.T.ok(e[5] & SR.FLAWLESS != 0 and e[5] & SR.SWIFT != 0, "sector 6 closes on victory")
	main.free()
	_restore_save(s)


func test_non_campaign_run_never_tracks() -> void:
	var s := _stash_save(".srtest3")
	var main := _main()
	main._endless = false
	main._boss_rush = false
	main._arcade_chapter = 3
	main._reset()
	_clear_gate(main, 100)
	Runner.T.eq(main.svc.earned_this_run()[0], 0, "an arcade start tracks nothing")
	main.free()
	_restore_save(s)


func test_live_hook_feeds_the_tracker_from_real_sim_steps() -> void:
	# The wiring itself: main._consume_events() -> svc.observe(sim). Real bot, real sim.
	var s := _stash_save(".srtest4")
	var main := _main()
	_campaign(main)
	main.sim.god_mode = true
	var t := 0
	while t < 2500 and main.svc.earned_this_run()[0] == 0:
		main.sim.step([MainScript.demo_input(t, main.sim)] as Array[SimInput])
		main._consume_events()
		t += 1
	Runner.T.ok(main.svc.earned_this_run()[0] & SR.SWIFT != 0,
		"the bot clears sector 1 in ~550 ticks, well under par - the hook recorded SWIFT (took %d ticks)" % t)
	main.free()
	_restore_save(s)


# --- the record path: bank, persist, honesty -------------------------------------------

func _earn_s1_s2_flawless(main: Node2D) -> void:
	_clear_gate(main, 400)
	_clear_gate(main, 900)


func test_verified_run_banks_medals_and_they_survive_a_restart() -> void:
	var s := _stash_save(".srtest5")
	var main := _main()
	_campaign(main)
	_earn_s1_s2_flawless(main)
	_bank(main, 2)
	Runner.T.eq(main.svc.medals[0], SR.FLAWLESS | SR.SWIFT | SR.HOARDER, "S1 medals banked")
	Runner.T.eq(main.svc.medals[1], SR.FLAWLESS | SR.SWIFT | SR.HOARDER, "S2 medals banked")
	Runner.T.eq(main.svc.medals[2], 0, "S3 was never cleared")
	var cf := ConfigFile.new()
	Runner.T.eq(cf.load(MainScript.SAVE_PATH), OK, "written to disk")
	Runner.T.eq(int(cf.get_value("service", "m1", -1)), 7, "[service] m1 persisted")
	main.free()
	# "restart": a brand-new Main reading the same file.
	var again := _main()
	again._load_bests()
	Runner.T.eq(again.svc.medals[0], 7, "S1 survives a restart")
	Runner.T.eq(again.svc.medals[1], 7, "S2 survives a restart")
	Runner.T.eq(again.svc.medal_total(), 6, "6 of 18 medals")
	Runner.T.ok(again.svc.best_grade.has("campaign"), "the campaign best rank survived too")
	again.free()
	_restore_save(s)


func test_unverified_run_banks_no_medals() -> void:
	var s := _stash_save(".srtest6")
	var main := _main()
	_campaign(main)
	_earn_s1_s2_flawless(main)
	main._recorder = null
	main._apply_score_verdict(0, false)
	Runner.T.eq(main.svc.medal_total(), 0, "a run that failed replay verification earns nothing")
	main.free()
	_restore_save(s)


func test_assisted_run_earns_no_medals_and_no_best_rank() -> void:
	var s := _stash_save(".srtest7")
	var main := _main()
	main._assist = true   # the 2-hit vest accessibility start: the Hall files it as *ASSIST
	_campaign(main)
	_earn_s1_s2_flawless(main)
	_bank(main, 2)
	Runner.T.eq(main.svc.medal_total(), 0, "assisted: no medals")
	Runner.T.ok(main.svc.best_grade.is_empty(), "assisted: no best rank")
	Runner.T.ok(main.hall[0].get("assist", false), "(the Hall did file this run as assisted)")
	main.free()
	_restore_save(s)


func test_perked_run_earns_no_medals_and_no_best_rank() -> void:
	var s := _stash_save(".srtest8")
	var main := _main()
	_campaign(main)
	_earn_s1_s2_flawless(main)
	main._run_perked = true   # purchased perks: the Hall files this run as assisted
	_bank(main, 2)
	Runner.T.eq(main.svc.medal_total(), 0, "perked: no medals")
	Runner.T.ok(main.svc.best_grade.is_empty(), "perked: no best rank either")
	Runner.T.ok(main.svc.callout_row().is_empty(), "perked: no call-out")
	main.free()
	_restore_save(s)


func test_arcade_retry_and_daily_earn_no_medals() -> void:
	for kind in ["arcade", "daily"]:
		var s := _stash_save(".srtest9" + kind)
		var main := _main()
		main._endless = false
		main._boss_rush = false
		main._arcade_chapter = 2 if kind == "arcade" else -1
		main._daily = kind == "daily"
		main._reset()
		main._menu.mode = GameMenu.Mode.HIDDEN
		_earn_s1_s2_flawless(main)
		_bank(main, 2)
		Runner.T.eq(main.svc.medal_total(), 0, "%s run: no medals" % kind)
		main.free()
		_restore_save(s)


func test_best_rank_is_kept_per_mode_and_only_ever_improves() -> void:
	var sr := SR.new()
	sr.commit_run(false, "campaign", "B", 3, false)
	sr.commit_run(false, "campaign", "D", 9, false)
	Runner.T.eq(sr.best_grade["campaign"], "B", "a worse grade never replaces the best")
	Runner.T.eq(sr.best_reach["campaign"], 9, "the deepest reach is kept independently")
	sr.commit_run(false, "campaign", "A", 2, false)
	Runner.T.eq(sr.best_grade["campaign"], "A", "a better grade replaces it")
	sr.commit_run(false, "endless", "C", 12, false)
	sr.commit_run(false, "daily", "S", 4, false)
	sr.commit_run(false, "arcade", "B", 5, false)
	sr.commit_run(false, "boss_rush", "A", 3, false)
	for k in SR.MODES:
		Runner.T.ok(sr.best_grade.has(k), "best rank tracked for " + k)
	sr.commit_run(false, "endless", "S", 99, true)
	Runner.T.eq(sr.best_grade["endless"], "C", "an assisted run never lifts a best")
	Runner.T.eq(SR.reach_text("endless", 12), "WAVE 12", "endless reach reads as a wave")
	Runner.T.eq(SR.reach_text("campaign", 7), "VICTORY", "a campaign win reads as VICTORY")
	Runner.T.eq(SR.reach_text("boss_rush", 2), "BOSS 2/3", "boss rush reads as gunships")


# --- save tolerance ----------------------------------------------------------------------

func test_old_and_corrupt_saves_load_clean() -> void:
	var sr := SR.new()
	sr.load_from(ConfigFile.new())
	Runner.T.eq(sr.medal_total(), 0, "a save with no [service] section = nothing earned")
	Runner.T.ok(sr.best_grade.is_empty() and sr.best_reach.is_empty(), "...and no bests")
	var cf := ConfigFile.new()
	cf.set_value("service", "m1", "garbage")
	cf.set_value("service", "m2", 9999)
	cf.set_value("service", "m3", -5)
	cf.set_value("service", "m4", [1, 2])
	cf.set_value("service", "rank_campaign", 42)
	cf.set_value("service", "rank_endless", "Z")
	cf.set_value("service", "reach_endless", "deep")
	cf.set_value("service", "reach_daily", -3)
	sr.load_from(cf)
	for i in SR.SECTORS:
		Runner.T.ok(sr.medals[i] >= 0 and sr.medals[i] <= 7, "sector %d mask stays inside the 3 medal bits" % (i + 1))
	Runner.T.eq(sr.medals[0], 0, "a non-number mask reads as nothing")
	Runner.T.ok(not sr.best_grade.has("campaign") and not sr.best_grade.has("endless"), "bad grades are dropped")
	Runner.T.ok(not sr.best_reach.has("endless") and not sr.best_reach.has("daily"), "bad reaches are dropped")


func test_a_totally_garbled_save_file_does_not_cost_the_service_record_load() -> void:
	var s := _stash_save(".srtest10")
	var f := FileAccess.open(MainScript.SAVE_PATH, FileAccess.WRITE)
	f.store_string("[service]\nm1=\n[[[ not a config")
	f.close()
	var main := _main()
	main._load_bests()
	Runner.T.eq(main.svc.medal_total(), 0, "an unreadable save boots with an empty record, no crash")
	main.free()
	_restore_save(s)


# --- the debrief call-out ------------------------------------------------------------------

func test_new_medal_callout_fires_once() -> void:
	var s := _stash_save(".srtest11")
	var main := _main()
	_campaign(main)
	_earn_s1_s2_flawless(main)
	Runner.T.ok(main._debrief_meta_rows(1.0).filter(func(r): return "NEW MEDAL" in String(r["text"])).is_empty(),
		"nothing is called out before the run is banked")
	_bank(main, 2)
	var rows: Array = main._debrief_meta_rows(1.0).filter(func(r): return "NEW MEDAL" in String(r["text"]))
	Runner.T.eq(rows.size(), 1, "exactly one call-out row")
	Runner.T.ok("S1 FLAWLESS" in String(rows[0]["text"]) and "+5" in String(rows[0]["text"]),
		"it names the first medal and counts the rest: " + String(rows[0]["text"]))
	Runner.T.ok(Art.TEX.has(rows[0]["icon"]), "its icon is a registered texture")
	# The same medals again are not new.
	_campaign(main)
	_earn_s1_s2_flawless(main)
	_bank(main, 2)
	Runner.T.ok(main._debrief_meta_rows(1.0).filter(func(r): return "NEW MEDAL" in String(r["text"])).is_empty(),
		"re-earning medals you already hold calls out nothing")
	# A strictly new one (S3) is called out alone.
	_campaign(main)
	_earn_s1_s2_flawless(main)
	_clear_gate(main, 1500)
	_bank(main, 3)
	var again: Array = main._debrief_meta_rows(1.0).filter(func(r): return "NEW MEDAL" in String(r["text"]))
	Runner.T.eq(again.size(), 1, "a genuinely new sector's medals are called out")
	Runner.T.ok("S3 FLAWLESS" in String(again[0]["text"]), "and it is the new one: " + String(again[0]["text"]))
	main.free()
	_restore_save(s)


# --- the RECORD tab ---------------------------------------------------------------------------

func test_record_page_is_reachable_from_info_and_draws_inside_the_content_well() -> void:
	var main := _main()
	main.svc.medals.assign([7, 3, 0, 0, 0, 0])
	main.svc.best_grade = {"campaign": "A", "endless": "S"}
	main.svc.best_reach = {"campaign": 4, "endless": 14}
	main.vet_points = 42
	var menu := _RecMenu.new()
	menu.main = main
	menu.mode = GameMenu.Mode.INFO
	var items: Array[Dictionary] = menu._menu_items()
	var idx := -1
	for i in items.size():
		if items[i]["id"] == "record":
			idx = i
	Runner.T.ok(idx >= 0, "INFO carries a SERVICE RECORD row")
	menu.sel = idx
	menu._activate()
	Runner.T.eq(menu.mode, GameMenu.Mode.HALL, "the row opens the Hall frame")
	Runner.T.ok(menu._record_view, "...in record view")
	Runner.T.eq(menu._mode_hint_segs({}), [], "no FILTER / PAGE hint on a page with nothing to filter")
	menu.open(GameMenu.Mode.HALL)
	Runner.T.ok(not menu._record_view, "opening the plain Hall always shows the board, never a stale record view")
	menu._record_view = true
	var prev = Art.text_capture
	Art.text_capture = menu.ops
	menu._draw_service_record()
	Art.text_capture = prev
	var tx := _texts(menu.ops)
	Runner.T.ok("MEDALS 5/18   \u00b7   42 VP BANKED" in tx, "summary shows medals + total VP: " + str(tx.slice(0, 2)))
	for s in range(1, 7):
		Runner.T.ok(("S%d" % s) in tx, "sector %d header" % s)
	for m in ["FLAWLESS", "SWIFT", "HOARDER"]:
		Runner.T.ok(m in tx, m + " row label")
	for k in SR.MODES:
		Runner.T.ok(SR.MODE_LABELS[k] in tx, SR.MODE_LABELS[k] + " rank cell")
	Runner.T.ok("WAVE 14" in tx and "SECTOR 4" in tx, "best reach text drawn")
	var icons := 0
	for o in menu.ops:
		if o["k"] == "tex" and String(o["id"]).begins_with("medal_"):
			icons += 1
	Runner.T.eq(icons, 18, "3 medals x 6 sectors = 18 icons (dim when unearned)")
	# every ink box sits inside the frame, below the title and above the PREV/NEXT band
	var top := GameMenu.CONTENT_TITLE_Y + 8.0
	var bottom: float = menu._hall_page_rects()[0].position.y
	for o in menu.ops:
		var b: Rect2 = o["box"]
		if o["k"] == "rect":
			continue
		Runner.T.ok(b.position.x >= 100.0 and b.end.x <= GameMenu.FRAME_INNER_R, "%s inside the frame width: %s" % [o["id"], str(b)])
		Runner.T.ok(b.position.y >= top and b.end.y <= bottom, "%s clear of title and pager (%.0f..%.0f): %s" % [o["id"], top, bottom, str(b)])
	menu.free()
	main.free()
