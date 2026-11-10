extends RefCounted
## review-fixes: six defects an independent review found in merged work. VET perks are their
## own tag (never ASSIST) and can be switched off; a retried arcade run can return to a ranked
## campaign; the P2 banner plate follows the font; slow-mo never outlives its scene.
## Everything runs through the REAL main.gd / menu.gd (same patterns as test_campaign_meta.gd).

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const Meta := preload("res://src/view/campaign_meta.gd")
const Layout := preload("res://tests/test_menu_layout.gd")


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


func _dead_campaign(main: Node2D, opened: int) -> void:
	main._endless = false
	main._boss_rush = false
	main._arcade_chapter = -1
	main._reset()
	for i in opened:
		main.sim.gates.append({"open": true})
	main._menu.mode = GameMenu.Mode.HIDDEN
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


func _perks() -> Dictionary:
	return {MainScript.PERK_VEST: 1, MainScript.PERK_CHEST: 2, MainScript.PERK_TOKEN: 1}


# --- 1. VET perks: switchable, and their own tag ---------------------------------------------

func test_vet_perks_off_starts_a_clean_unperked_campaign() -> void:
	var main := _main()
	main._perk_levels = _perks()
	main._vet_perks_on = false
	_dead_campaign(main, 0)
	for p in main.sim.players:
		Runner.T.ok(not p["vest"], "VET PERKS OFF: no vest on a Campaign start")
	Runner.T.eq(main.sim.war_chest, 0, "VET PERKS OFF: chest stays 0")
	Runner.T.eq(main.sim.tokens, 0, "VET PERKS OFF: no token")
	Runner.T.eq(main.run_board_tags().size(), 0, "VET PERKS OFF: the run carries no tags at all")
	main.free()
	main = _main()
	main._perk_levels = _perks()
	main._vet_perks_on = false
	main._arcade_chapter = 3
	main._reset()
	Runner.T.eq(main.sim.war_chest, 0, "VET PERKS OFF applies to Arcade too")
	Runner.T.eq(main.run_board_tags().size(), 0, "...and Arcade stays untagged")
	main.free()


func test_vet_perks_on_tags_vet_not_assist() -> void:
	var s := _stash_save(".rf1")
	var main := _main()
	main._perk_levels = _perks()
	main._vet_perks_on = true
	_dead_campaign(main, 0)
	Runner.T.eq(main.sim.war_chest, main.PERK_CHEST_BONUS * 2, "VET PERKS ON: perks apply")
	Runner.T.eq(main.run_board_tags(), ["vet"], "the run is tagged vet")
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.ok(main.hall_latest.get("vet", false), "the Hall entry carries vet")
	Runner.T.ok(not main.hall_latest.get("assist", true), "...and is NOT an ASSIST run")
	Runner.T.ok("vest" in main.hall_latest.get("assist_tags", []),
		"...while the Steam tags still route it off the clean board (vest bit, unchanged)")
	main.free()
	_restore_save(s)


func test_assist_setting_run_is_still_tagged_assist() -> void:
	var s := _stash_save(".rf2")
	var main := _main()
	main._vet_perks_on = true   # nothing owned: only the accessibility vest applies
	main._assist = true
	_dead_campaign(main, 0)
	Runner.T.ok("vest" in main.run_board_tags() and "vet" not in main.run_board_tags(),
		"ASSIST alone: tagged vest, not vet: %s" % [main.run_board_tags()])
	main._recorder = null
	main._apply_score_verdict(0, true)
	Runner.T.ok(main.hall_latest.get("assist", false), "an ASSIST-setting run is filed assist")
	Runner.T.ok(not main.hall_latest.get("vet", false), "...and is not vet")
	main.free()
	_restore_save(s)


func test_endless_ignores_the_vet_switch() -> void:
	var main := _main()
	main._perk_levels = _perks()
	main._vet_perks_on = false
	main._endless = true
	main._reset()
	Runner.T.eq(main.sim.war_chest, main.PERK_CHEST_BONUS * 2, "Endless still takes owned perks with the switch OFF")
	Runner.T.eq(main.run_board_tags().size(), 0, "...and stays untagged, exactly as before")
	main.free()
	Runner.T.ok(Meta.perks_apply("endless", false, false), "perks_apply: endless unaffected by the switch")
	Runner.T.ok(not Meta.perks_apply("campaign", false, false), "perks_apply: campaign honours the switch")
	Runner.T.ok(not Meta.perks_apply("arcade", false, false), "perks_apply: arcade honours the switch")
	Runner.T.ok(Meta.perks_apply("campaign", false, true), "perks_apply: campaign ON")
	Runner.T.ok(not Meta.perks_apply("campaign", true, true), "perks_apply: never the daily")


func test_vet_switch_persists_and_old_saves_load_as_on() -> void:
	var s := _stash_save(".rf3")
	var fresh := _main()
	fresh._load_bests()
	Runner.T.ok(fresh._vet_perks_on, "no save at all: ON (a new player's progression is felt)")
	fresh.free()
	var cf := ConfigFile.new()
	cf.set_value("meta", "vp", 12)   # an old save: [meta] exists, the switch does not
	cf.save(MainScript.SAVE_PATH)
	var old := _main()
	old._load_bests()
	Runner.T.eq(old.vet_points, 12, "sanity: the old save loaded")
	Runner.T.ok(old._vet_perks_on, "an old save without the setting loads as ON")
	old.set_vet_perks(false)
	old.free()
	var back := _main()
	back._load_bests()
	Runner.T.ok(not back._vet_perks_on, "OFF survives a relaunch")
	Runner.T.eq(back.vet_points, 12, "...without disturbing the banked VP")
	back.free()
	_restore_save(s)


func test_setup_row_toggles_and_perks_copy_states_the_rule() -> void:
	var stub := Layout._StubMain.new()
	var m: Control = GameMenu.new()
	m.main = stub
	m.mode = GameMenu.Mode.SETUP
	var row := {}
	for r in m._menu_items():
		if r["id"] == "vet_perks":
			row = r
	Runner.T.ok(not row.is_empty(), "SETUP has a VET PERKS row")
	Runner.T.ok(String(row.get("label", "")).contains("ON"), "...default ON: %s" % row.get("label", ""))
	Runner.T.ok("vet_perks" in GameMenu._TOGGLES, "the row is a toggle (arrows and Enter agree)")
	var help := GameMenu.setting_help("vet_perks")
	Runner.T.ok(help.contains("*VET") and help.contains("CAMPAIGN") and help.contains("ARCADE"),
		"the row help states where perks apply and the *VET board: %s" % help)
	for id in ["perk_vest", "perk_chest", "perk_token"]:
		var h := GameMenu.setting_help(id)
		Runner.T.ok(h.contains("ENDLESS") and h.contains("CAMPAIGN") and h.contains("*VET"),
			"the perks screen copy for %s says where perks apply and the VET board: %s" % [id, h])
	m.free()
	stub.free()


func test_hall_tag_text_says_vet_never_assist_for_a_vet_run() -> void:
	var vet := {"assist": false, "vet": true, "daily": false, "hard": false}
	Runner.T.eq(Meta.hall_tags(vet, false), "  *VET", "a vet run prints *VET")
	Runner.T.eq(Meta.hall_tags(vet, true), "  *V", "...abbreviated *V")
	var both := {"assist": true, "vet": true, "daily": true, "hard": true}
	Runner.T.eq(Meta.hall_tags(both, false), "  *DAILY  *ASSIST  *VET  *HARD", "every tag, fixed order")
	Runner.T.eq(Meta.hall_tags(both, true), "  *D  *A  *V  *H", "...and abbreviated")
	Runner.T.eq(Meta.hall_tags({"assist": true}, false), "  *ASSIST", "a plain assist run is unchanged")
	Runner.T.eq(Meta.hall_tags({}, false), "", "an untagged run prints nothing")


func test_debrief_names_a_vet_run() -> void:
	var main := _main()
	main._perk_levels = _perks()
	_dead_campaign(main, 0)
	Runner.T.ok(_has(main._debrief_meta_rows(1.0), "*VET"), "the debrief of a perked run says *VET")
	main.free()
	main = _main()
	main._perk_levels = _perks()
	main._vet_perks_on = false
	_dead_campaign(main, 0)
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "*VET"), "...and a perks-off run says nothing")
	main.free()


# --- 2. retry no longer strands the player in Arcade -----------------------------------------

func test_retried_arcade_run_offers_retry_again_and_a_ranked_campaign() -> void:
	var main := _main()
	_dead_campaign(main, 3)   # died in sector 4
	main._unhandled_key_input(_key(KEY_T))
	Runner.T.eq(main.sim.mode, "arcade", "sanity: the retry is an arcade run")
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._debrief = true
	main._result_t = 1.0
	var rows: Array = main._debrief_meta_rows(1.0)
	Runner.T.ok(_has(rows, "RETRY SECTOR 4"), "the retried run's debrief offers RETRY SECTOR 4 again")
	Runner.T.ok(_has(rows, "RANKED CAMPAIGN"), "...and a clearly labelled row back to a fresh RANKED CAMPAIGN")
	Runner.T.ok(main.redeploy_label().contains("SECTOR 4") and main.redeploy_label().contains("UNRANKED"),
		"the default REDEPLOY row says it re-runs the unranked sector: %s" % main.redeploy_label())
	main._unhandled_key_input(_key(KEY_N))
	Runner.T.eq(main.sim.mode, "campaign", "the ranked-campaign row starts a Campaign")
	Runner.T.eq(main._arcade_chapter, -1, "...and clears the arcade chapter, so REDEPLOY stays ranked")
	main._debrief = true
	main._result_t = 1.0
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "RANKED CAMPAIGN"), "the way-back row is gone once back")
	Runner.T.eq(main.redeploy_label(), "REDEPLOY", "plain REDEPLOY again")
	main.free()


func test_menu_started_arcade_is_not_a_retry_and_pad_returns() -> void:
	var main := _main()
	main.start_arcade(3)
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._debrief = true
	main._result_t = 1.0
	Runner.T.ok(not _has(main._debrief_meta_rows(1.0), "RANKED CAMPAIGN"), "a plain ARCADE pick offers no way-back row")
	Runner.T.eq(main.redeploy_label(), "REDEPLOY", "...and keeps the plain label")
	main.free()
	main = _main()
	_dead_campaign(main, 1)
	main._unhandled_key_input(_key(KEY_T))
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._debrief = true
	main._result_t = 1.0
	var ev := InputEventJoypadButton.new()
	ev.button_index = Meta.NEW_CAMPAIGN_PAD_BUTTON
	ev.pressed = true
	var was_pad := Art.use_pad
	var was_brand := Art.pad_brand
	main._input(ev)
	Art.use_pad = was_pad
	Art.pad_brand = was_brand
	Runner.T.eq(main.sim.mode, "campaign", "the pad button also returns to a ranked campaign")
	main.free()


# --- 3. the P2 banner plate follows the font -------------------------------------------------

func test_p2_banner_plate_encloses_its_text_at_large_text() -> void:
	var was := Art.text_scale
	for scale_v in [1.0, 2.0]:
		Art.text_scale = scale_v
		var stub := Layout._StubMain.new()
		var cap := Layout._CaptureMenu.new()
		cap.main = stub
		cap.mode = GameMenu.Mode.TITLE
		cap._p2_banner = "TWO PLAYERS - P2 JOINED"
		cap._p2_banner_t = 1.0
		cap._draw_title_p2_banner()
		var plate := Rect2()
		var ink := Rect2()
		for op in cap.ops:
			if op.get("k", "") == "rect" and op.has("box"):
				plate = op["box"]
			elif String(op.get("id", "")) == "TWO PLAYERS - P2 JOINED" and op.has("box"):
				ink = op["box"]
		Runner.T.ok(plate.size.y > 0.0 and ink.size.y > 0.0, "x%.1f: both plate and text were drawn" % scale_v)
		Runner.T.ok(plate.position.y <= ink.position.y and plate.end.y >= ink.end.y,
			"x%.1f: the plate (%s) encloses the text box (%s) vertically" % [scale_v, plate, ink])
		cap.free()
		stub.free()
	Art.text_scale = was


# --- 6. a scene freed mid-beat never leaves audio slowed -------------------------------------

func test_freeing_main_mid_beat_restores_audio_pitch() -> void:
	var was_enabled := TimeFx.enabled
	TimeFx.enabled = true
	AudioServer.playback_speed_scale = 1.0
	var main := _main()
	Runner.T.ok(main._time_fx.start("boss", 1.0), "sanity: a beat started")
	main._time_fx.advance(false)
	main._time_fx.advance(false)
	Runner.T.ok(AudioServer.playback_speed_scale < 0.99, "sanity: pitch is dipped mid-beat (%.3f)" % AudioServer.playback_speed_scale)
	main.free()
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "freeing main mid-beat restores the global scale to exactly 1.0")
	AudioServer.playback_speed_scale = 1.0
	TimeFx.enabled = was_enabled


func test_exit_tree_restores_audio_pitch() -> void:
	var was_enabled := TimeFx.enabled
	TimeFx.enabled = true
	AudioServer.playback_speed_scale = 1.0
	var main := _main()
	main._time_fx.start("boss", 1.0)
	main._time_fx.advance(false)
	main._time_fx.advance(false)
	Runner.T.ok(AudioServer.playback_speed_scale < 0.99, "sanity: pitch dipped before the tree exit")
	main._restore_global_audio()   # the exact hook _exit_tree and PREDELETE both call
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "the shared teardown hook restores 1.0")
	main.free()
	AudioServer.playback_speed_scale = 1.0
	TimeFx.enabled = was_enabled
