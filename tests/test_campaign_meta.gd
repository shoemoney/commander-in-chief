extends RefCounted
## retry-meta: campaign defeat offers RETRY SECTOR N (an unranked Arcade start at the
## sector the run died in), Campaign banks Veteran Points, and the purchased perks apply
## to Campaign starts. Everything runs through the REAL main.gd (same pattern as
## test_endless_meta.gd): the debrief rows come from main._debrief_meta_rows(), the retry is
## activated through the real keyboard / pad handlers, and the bank goes through the real
## _apply_score_verdict -> _record_run gate.

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const Meta := preload("res://src/view/campaign_meta.gd")


class _NullSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


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


## A campaign run that died with `opened` gates open (so the debrief reads sector opened+1).
func _dead_campaign(main: Node2D, opened: int) -> void:
	main._endless = false
	main._boss_rush = false
	main._arcade_chapter = -1
	main._reset()
	for i in opened:
		main.sim.gates.append({"open": true})
	main._menu.mode = GameMenu.Mode.HIDDEN   # a fresh Main boots on the title menu, which owns input
	main._debrief = true
	main._result_t = 1.0


func _has(rows: Array, needle: String) -> bool:
	for r in rows:
		if needle in String(r["text"]):
			return true
	return false


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func test_defeat_in_sector_k_offers_retry_sector_k() -> void:
	for k in [2, 5]:
		var main := _main()
		_dead_campaign(main, k - 1)
		var rows: Array = main._debrief_meta_rows(1.0)
		Runner.T.ok(_has(rows, "RETRY SECTOR %d" % k), "a death in sector %d offers RETRY SECTOR %d" % [k, k])
		Runner.T.ok(_has(rows, "UNRANKED"), "the retry row says honestly that the retried run is unranked")
		main.free()


func test_no_retry_row_for_sector_one_victory_or_other_modes() -> void:
	var main := _main()
	_dead_campaign(main, 0)
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "RETRY"), "sector 1 death: REDEPLOY already is the retry")
	main.free()
	main = _main()
	_dead_campaign(main, 3)
	main.sim.victory = true
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "RETRY"), "a win never offers a retry")
	main.free()
	main = _main()
	main._endless = true
	main._reset()
	main._debrief = true
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "RETRY"), "endless has no sectors to retry")
	main.free()


func test_activating_retry_starts_an_unranked_arcade_run_at_that_sector() -> void:
	var main := _main()
	_dead_campaign(main, 4)   # died in sector 5
	main._unhandled_key_input(_key(KEY_T))
	Runner.T.eq(main.sim.mode, "arcade", "RETRY starts an ARCADE run (the existing unranked chapter-start mode)")
	Runner.T.eq(main._arcade_chapter, 5, "...at the sector the run died in")
	main.free()


func test_retry_waits_for_the_card_and_enter_stays_redeploy() -> void:
	var main := _main()
	_dead_campaign(main, 4)
	main._result_t = 0.3
	main._unhandled_key_input(_key(KEY_T))
	Runner.T.eq(main.sim.mode, "campaign", "hammering the key during the card's entrance must not skip it")
	main._result_t = 1.0
	main._unhandled_key_input(_key(KEY_ENTER))
	Runner.T.eq(main.sim.mode, "campaign", "ENTER stays REDEPLOY: same mode, the default row")
	main.free()


func test_pad_y_retries_too() -> void:
	var main := _main()
	_dead_campaign(main, 2)
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_Y
	ev.pressed = true
	var was_pad := Art.use_pad   # _input flips the last-used-device globals; leave them as found
	var was_brand := Art.pad_brand
	main._input(ev)
	Art.use_pad = was_pad
	Art.pad_brand = was_brand
	Runner.T.eq(main.sim.mode, "arcade", "pad Y activates RETRY SECTOR")
	Runner.T.eq(main._arcade_chapter, 3, "...at sector 3")
	main.free()


func test_vp_formula_numbers() -> void:
	Runner.T.eq(Meta.vp_for_run("campaign", 0, 1, false, false), 2, "sector 1 reached: 2 VP")
	Runner.T.eq(Meta.vp_for_run("campaign", 0, 4, false, false), 8, "sector 4 reached: 8 VP")
	Runner.T.eq(Meta.vp_for_run("campaign", 0, 6, true, false), 22, "full clear: 6 sectors x2 + 10 win bonus")
	Runner.T.eq(Meta.vp_for_run("campaign", 0, 3, false, true), 0, "the daily stays a pure comparable run: no VP")
	Runner.T.eq(Meta.vp_for_run("arcade", 0, 5, false, false), 0, "an unranked retry banks nothing (no farming a sector)")
	Runner.T.eq(Meta.vp_for_run("endless", 9, 1, false, false), 9, "endless is unchanged: 1 VP per wave")
	Runner.T.eq(Meta.vp_for_run("boss_rush", 0, 3, true, false), 0, "boss rush banks nothing")


func test_campaign_run_banks_vp_and_the_debrief_shows_it() -> void:
	var s := _stash_save(".cmtest")
	var main := _main()
	_dead_campaign(main, 3)   # sector 4
	main.vet_points = 10
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.eq(main._run_vp_gain, 8, "sector 4 reached banks 8 VP")
	Runner.T.eq(main.vet_points, 18, "the pool grew by exactly the gain")
	var rows: Array = main._debrief_meta_rows(1.0)
	Runner.T.ok(_has(rows, "18 VP BANKED  (+8)"), "the debrief card shows the total and this run's gain")
	var cf := ConfigFile.new()
	Runner.T.eq(cf.load(MainScript.SAVE_PATH), OK, "the bank was written to disk")
	Runner.T.eq(int(cf.get_value("meta", "vp", -1)), 18, "VP persisted under meta/vp like Endless")
	main.free()
	_restore_save(s)


func test_unverified_campaign_run_banks_nothing() -> void:
	var main := _main()
	_dead_campaign(main, 3)
	main.vet_points = 10
	main._apply_score_verdict(0, false)
	Runner.T.eq(main.vet_points, 10, "failed replay verification banks no VP")
	main.free()


func test_endless_vp_unchanged() -> void:
	var s := _stash_save(".cmtest2")
	var main := _main()
	main._endless = true
	main._reset()
	main.sim.wave = 7
	main.vet_points = 0
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.eq(main.vet_points, 7, "endless still banks 1 VP per wave")
	main.free()
	_restore_save(s)


func test_owned_perks_apply_to_a_fresh_campaign_start() -> void:
	var main := _main()
	main._perk_levels = {MainScript.PERK_VEST: 1, MainScript.PERK_CHEST: 2, MainScript.PERK_TOKEN: 1}
	main._endless = false
	main._reset()
	Runner.T.eq(main.sim.mode, "campaign", "sanity: Campaign")
	for p in main.sim.players:
		Runner.T.ok(p["vest"], "VETERAN VEST applies to Campaign")
	Runner.T.eq(main.sim.war_chest, main.PERK_CHEST_BONUS * 2, "HEAD START applies to Campaign")
	Runner.T.eq(main.sim.tokens, 1, "SIGNAL FLARE applies to Campaign")
	Runner.T.eq(main._recorder.start_chest, main.PERK_CHEST_BONUS * 2,
		"the replay records the resolved loadout, so verification rebuilds the same run")
	main.free()


func test_daily_stays_perk_free() -> void:
	var main := _main()
	main._perk_levels = {MainScript.PERK_VEST: 1, MainScript.PERK_CHEST: 3}
	main._daily = true
	main._reset()
	Runner.T.eq(main.sim.war_chest, 0, "the daily seed is a shared comparable challenge: no perks")
	for p in main.sim.players:
		Runner.T.ok(not p["vest"], "no perk vest on the daily")
	main.free()


func test_perked_campaign_run_is_flagged_so_the_boards_stay_honest() -> void:
	var s := _stash_save(".cmtest3")
	var main := _main()
	main._perk_levels = {MainScript.PERK_CHEST: 1}
	_dead_campaign(main, 1)
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.ok(main.hall_latest.get("perked", false), "the Hall entry is stamped perked")
	Runner.T.ok(main.hall_latest.get("assist", false), "...and counted as assisted")
	Runner.T.ok("vest" in main.hall_latest.get("assist_tags", []), "...carrying the assisted-board tag Steam reads")
	main.free()
	_restore_save(s)
	var s2 := _stash_save(".cmtest4")
	var clean := _main()
	_dead_campaign(clean, 1)
	clean._recorder = null
	clean._apply_score_verdict(0, true)
	Runner.T.ok(not clean.hall_latest.get("perked", false), "no perks owned: the entry stays clean")
	clean.free()
	_restore_save(s2)


func test_victory_card_shows_vp_row() -> void:
	var s := _stash_save(".cmtest5")
	var main := _main()
	_dead_campaign(main, 5)
	main._debrief = false
	main.sim.victory = true
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.eq(main._run_vp_gain, 22, "a full clear banks 22 VP")
	Runner.T.ok(_has(main._debrief_meta_rows(1.0), "VP BANKED"), "the victory card shows the VP line")
	main.free()
	_restore_save(s)
