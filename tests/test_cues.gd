extends RefCounted
## CUES NOT WORDS. Pins: the 3-state CAPTIONS setting and its bool migration, the SMART fade (and
## the muted-bus exception that keeps it an accessibility feature), the compact SFX-cue chip, the
## first-2-then-icon pickup rule, the flank chevron, and the one-shot armor/grenade hint re-arm.

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")


# --- the setting -------------------------------------------------------------------------------

func test_bool_captions_migrate_to_the_three_states() -> void:
	Runner.T.eq(CuePolicy.migrate_caption_mode(true), CuePolicy.CAP_ALL, "saved true -> ALL")
	Runner.T.eq(CuePolicy.migrate_caption_mode(false), CuePolicy.CAP_OFF, "saved false -> OFF")
	Runner.T.eq(CuePolicy.migrate_caption_mode(CuePolicy.CAP_SMART), CuePolicy.CAP_SMART, "SMART survives a round trip")
	Runner.T.eq(CuePolicy.migrate_caption_mode(99), CuePolicy.CAP_ALL, "an out-of-range int falls to the safe side, ALL")
	Runner.T.eq(CuePolicy.migrate_caption_mode("junk"), CuePolicy.CAP_ALL, "a wrong-typed value falls to ALL")
	var seen := {}
	var m := CuePolicy.CAP_ALL
	for i in 3:
		m = CuePolicy.next_mode(m)
		seen[m] = true
	Runner.T.eq(m, CuePolicy.CAP_ALL, "the row cycles ALL -> SMART -> OFF -> ALL")
	Runner.T.eq(seen.size(), 3, "...through all three states")


func _stash(tag: String) -> Dictionary:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var s := {"path": path, "bak": bak, "stash": path + tag, "stashb": bak + tag}
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, s["stash"])
	if FileAccess.file_exists(bak):
		DirAccess.rename_absolute(bak, s["stashb"])
	return s


func _unstash(s: Dictionary) -> void:
	for p in [s["path"], s["bak"]]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if FileAccess.file_exists(s["stash"]):
		DirAccess.rename_absolute(s["stash"], s["path"])
	if FileAccess.file_exists(s["stashb"]):
		DirAccess.rename_absolute(s["stashb"], s["bak"])


func test_a_real_save_load_migrates_and_persists_the_counters() -> void:
	var s := _stash(".cues1")
	for case in [[true, CuePolicy.CAP_ALL], [false, CuePolicy.CAP_OFF], [1, CuePolicy.CAP_SMART]]:
		var cf := ConfigFile.new()
		cf.set_value("settings", "captions", case[0])
		cf.set_value("seen", "cues", {"cap:strike_warn": 2, "pk:4": 1})
		cf.save(MainScript.SAVE_PATH)
		var main := MainScript.new()
		main._load_bests()
		Runner.T.eq(main._caption_mode, case[1], "saved %s loads as mode %d" % [str(case[0]), case[1]])
		Runner.T.eq(main._captions, case[1] != CuePolicy.CAP_OFF, "the derived on/off bool agrees")
		Runner.T.eq(int(main._cue_seen.get("cap:strike_warn", 0)), 2, "exposure counters load beside _seen")
		main.free()
	var legacy := ConfigFile.new()
	legacy.save(MainScript.SAVE_PATH)
	var fresh := MainScript.new()
	fresh._load_bests()
	Runner.T.eq(fresh._caption_mode, CuePolicy.CAP_ALL, "a save with no captions key defaults to ALL")
	Runner.T.eq(MainScript.SETTINGS_DEFAULTS["captions"], CuePolicy.CAP_ALL, "the shipped default is ALL")
	Runner.T.eq(fresh._settings_snapshot()["captions"], CuePolicy.CAP_ALL, "the snapshot writes the mode, not a bool")
	fresh.free()
	_unstash(s)


# --- SMART fade --------------------------------------------------------------------------------

func _fire(sfx: Sfx, key: String) -> String:
	sfx.clear_captions()
	sfx._sfx_cap_next.clear()
	sfx.caption_sfx(key)
	return String(sfx.active_caption()["text"])


func test_smart_fades_a_cue_after_three_exposures() -> void:
	var sfx := Sfx.new()
	sfx.caption_mode = CuePolicy.CAP_SMART
	sfx.sfx_step = 10
	for i in 3:
		Runner.T.eq(_fire(sfx, "strike_warn"), Sfx.SFX_CAPTIONS["strike_warn"], "SMART exposure %d still captions" % (i + 1))
	Runner.T.eq(_fire(sfx, "strike_warn"), "", "the 4th exposure of the same cue is silent")
	Runner.T.eq(_fire(sfx, "sniper_paint"), Sfx.SFX_CAPTIONS["sniper_paint"], "the fade is per cue key, not global")
	Runner.T.eq(int(sfx.cue_counts["cap:strike_warn"]), 3, "the counter stops at the exposures it actually showed")
	sfx.free()


func test_smart_never_fades_when_the_sfx_bus_is_muted_or_quiet() -> void:
	for step in [0, 1]:
		var sfx := Sfx.new()
		sfx.caption_mode = CuePolicy.CAP_SMART
		sfx.sfx_step = step
		for i in 8:
			_fire(sfx, "rear_warn")
		Runner.T.eq(_fire(sfx, "rear_warn"), Sfx.SFX_CAPTIONS["rear_warn"],
			"SFX step %d (under 20%%): the caption is the only warning, so it never fades" % step)
		sfx.free()
	var loud := Sfx.new()
	loud.caption_mode = CuePolicy.CAP_SMART
	loud.sfx_step = 2
	for i in 3:
		_fire(loud, "rear_warn")
	Runner.T.eq(_fire(loud, "rear_warn"), "", "at 20%% volume the fade is allowed")
	loud.free()


func test_all_mode_is_unchanged_and_off_shows_nothing() -> void:
	var sfx := Sfx.new()
	sfx.caption_mode = CuePolicy.CAP_ALL
	sfx.sfx_step = 10
	for i in 12:
		Runner.T.eq(_fire(sfx, "armor_block"), Sfx.SFX_CAPTIONS["armor_block"], "ALL: exposure %d" % (i + 1))
	for key in Sfx.SFX_CAPTIONS:
		Runner.T.eq(_fire(sfx, key), Sfx.SFX_CAPTIONS[key], "ALL shows every cue (%s)" % key)
	sfx.free()
	Runner.T.ok(not CuePolicy.caption_allowed(CuePolicy.CAP_OFF, 0, 10), "OFF allows no cue")


# --- the chip ----------------------------------------------------------------------------------

func test_every_sfx_cue_has_a_short_chip_and_voice_lines_have_none() -> void:
	var sfx := Sfx.new()
	sfx.caption_mode = CuePolicy.CAP_ALL
	for key in Sfx.SFX_CAPTIONS:
		_fire(sfx, key)
		var cap: Dictionary = sfx.active_caption()
		var chip := String(cap.get("chip", ""))
		Runner.T.ok(chip != "" and chip.length() <= 9, "%s has a chip word of <=9 chars (%s)" % [key, chip])
		Runner.T.ok(chip.length() < String(cap["text"]).length() / 2, "%s chip is far shorter than its bracket line" % key)
	sfx.clear_captions()
	sfx._arm_caption("COMMANDER: \"Man down!\"", null, false, true)
	Runner.T.eq(String(sfx.active_caption().get("chip", "")), "", "voice-line subtitles keep their full text, no chip")
	sfx.free()


class _CapMain extends Node2D:
	var sim: SimWorld = null
	var _debrief := false
	var _menu = null
	var _motion := 1.0
	var _captions := true
	var _sfx = null
	var _grenade_dry: Array = [0, 0]
	var _token_loss_t := 0.0
	var best_score := 0
	var best_wave := 0
	var _record_fired := false
	func bind_for_glyph(_a: String) -> int: return 0
	func pad_bind_for_glyph(_a: String, _device := 0) -> int: return -1


func test_the_cue_chip_is_a_slim_scrim_with_a_glyph() -> void:
	var stub := _CapMain.new()
	stub._sfx = Sfx.new()
	var hud := HudIcons.new()
	hud.main = stub
	stub._sfx.caption_sfx("strike_warn")
	var chip: Dictionary = hud.caption_layout()
	Runner.T.ok(not chip.is_empty(), "a cue caption lays out")
	var old_line := HudIcons.caption_line(Sfx.SFX_CAPTIONS["strike_warn"])
	var old_w := Art.font().get_string_size(old_line, HORIZONTAL_ALIGNMENT_LEFT, -1, Art.fs(HudIcons.FONT_SIZE)).x
	var y_bottom := HudIcons.VERB_LEGEND_Y - 20.0 - HudIcons.bottom_band_lift(null)
	var old_bg := HudIcons.caption_bg_rect(1, old_w, y_bottom)
	var bg: Rect2 = chip["bg"]
	Runner.T.ok(bg.size.x < old_bg.size.x * 0.55,
		"chip scrim is far narrower than the bracket line's (%.0f vs %.0f px)" % [bg.size.x, old_bg.size.x])
	Runner.T.ok(bg.size.y < old_bg.size.y, "...and slimmer (%.0f vs %.0f px)" % [bg.size.y, old_bg.size.y])
	Runner.T.ok(chip.has("icon") and bg.encloses(chip["icon"]), "the glyph sits inside the scrim")
	Runner.T.ok(absf(bg.get_center().x - 320.0) < 0.6, "still centred where the arbiters reserve it")
	Runner.T.eq(bg.end.y, old_bg.end.y, "the chip hangs from the same baseline as the old strip")
	var rail := hud.bottom_rail_rects()
	Runner.T.ok(not rail.is_empty() and (rail[0] as Rect2).encloses(bg), "the arbiter's rail reservation covers the chip")
	stub._sfx.clear_captions()
	stub._sfx._arm_caption("SPOTTER: \"Gunship inbound!\"", null, true, false)
	var vo: Dictionary = hud.caption_layout()
	Runner.T.ok(not vo.has("icon"), "voice subtitles draw as before, no glyph")
	hud.free()
	stub._sfx.free()
	stub.free()


# --- pickups: first two get the word, then an icon ---------------------------------------------

func _floats(m: Object) -> Array:
	var out: Array = []
	for f in m._fx:
		if f.get("kind", "") == "floattext":
			out.append(f)
	return out


func test_pickup_word_shows_for_the_first_two_grabs_then_an_icon() -> void:
	var m := _playing_main()
	m.sim = SimWorld.new(3, 1)
	var words: Array = []
	for i in 4:
		m._fx.clear()
		m.sim.events.assign([{"t": "pickup", "kind": 4, "x": 100 * Fixed.ONE, "y": 100 * Fixed.ONE, "cost": 0}])
		m._consume_events()
		var callout := {}
		for f in _floats(m):
			if String(f["text"]).begins_with("PIERC"):
				callout = f
		words.append(callout)
	Runner.T.ok(not words[0].is_empty() and not words[0].has("icon"), "grab 1 spells the word")
	Runner.T.ok(not words[1].is_empty() and not words[1].has("icon"), "grab 2 spells the word")
	Runner.T.ok(words[2].has("icon") and words[3].has("icon"), "grab 3 and 4 are an icon")
	Runner.T.eq(int(m._cue_seen.get("pk:4", 0)), 4, "the per-kind counter is persisted state")
	m._fx.clear()
	m.sim.events.assign([{"t": "pickup", "kind": 5, "x": 100 * Fixed.ONE, "y": 100 * Fixed.ONE, "cost": 0}])
	m._consume_events()
	var other: Array = _floats(m)
	Runner.T.ok(not other.is_empty() and not other[0].has("icon"), "a different kind starts its own count")
	m.free()


func test_armor_up_is_an_icon_after_two_boardings() -> void:
	var m := _playing_main()
	m.sim = SimWorld.new(3, 1)
	var icons: Array = []
	for i in 3:
		m._fx.clear()
		m.sim.events.assign([{"t": "tank_board", "x": 100 * Fixed.ONE, "y": 100 * Fixed.ONE}])
		m._consume_events()
		var any_icon := false
		var any_word := false
		for f in _floats(m):
			if f["text"] == "ARMOR UP":
				any_word = true
				any_icon = any_icon or f.has("icon")
		Runner.T.ok(any_word, "boarding %d still raises the armor toast entry" % (i + 1))
		icons.append(any_icon)
	Runner.T.eq(icons, [false, false, true], "word, word, icon")
	m.free()


func test_flank_breach_points_an_edge_chevron_instead_of_the_word() -> void:
	var m := MainScript.new()
	m.sim = SimWorld.new(3, 1)
	m.sim.events.assign([{"t": "flank_breach", "x": 40 * Fixed.ONE, "y": 100 * Fixed.ONE}])
	m._consume_events()
	var chev := 0
	for f in m._fx:
		Runner.T.ok(f.get("text", "") != "FLANKS!", "no FLANKS! word is raised")
		if f.get("kind", "") == "edge_chev":
			chev += 1
	Runner.T.eq(chev, 1, "exactly one edge chevron is raised for the breach")
	m.free()


func test_chevron_geometry_pins_to_the_edge_nearest_the_breach() -> void:
	var left := CuePolicy.edge_chevron(Vector2(-120.0, 180.0))
	Runner.T.ok(absf(left["pos"].x - CuePolicy.EDGE_INSET) < 0.01, "a breach off the left edge pins to the left margin")
	Runner.T.ok(absf(left["angle"] - PI) < 0.01, "...pointing left")
	var right := CuePolicy.edge_chevron(Vector2(900.0, 180.0))
	Runner.T.ok(absf(right["pos"].x - (640.0 - CuePolicy.EDGE_INSET)) < 0.01 and absf(right["angle"]) < 0.01, "right side points right")
	var top := CuePolicy.edge_chevron(Vector2(320.0, -300.0))
	Runner.T.ok(absf(top["angle"] + PI / 2.0) < 0.01 and absf(top["pos"].y - CuePolicy.EDGE_INSET) < 0.01, "above points up")
	var inside := CuePolicy.edge_chevron(Vector2(330.0, 170.0))
	Runner.T.ok(inside["pos"].distance_to(Vector2(330.0, 170.0)) < 0.01, "an on-screen breach is marked in place")


# --- the armor/grenade mastery re-arm ----------------------------------------------------------

func _playing_main() -> Node:
	## A bare Main boots on the TITLE (attract) menu, where _hint and the mastery counters stand down.
	var m := MainScript.new()
	m._menu.mode = GameMenu.Mode.HIDDEN
	return m


func test_armor_hint_rearms_exactly_once_for_a_player_who_never_throws() -> void:
	var m := _playing_main()
	m._seen["armor"] = true            # the original teach line was delivered once
	var fired := 0
	for i in 12:
		if m._note_armor_block():
			fired += 1
		m._seen["armor"] = true        # whatever was re-queued is delivered, as _start_next_hint records it
	Runner.T.eq(fired, 1, "twelve armor blocks re-arm the hint exactly once")
	Runner.T.eq(int(m._cue_seen[CuePolicy.KEY_ARMOR_BLOCKS]), 12, "every armor block is counted")
	m.free()


func test_armor_rearm_needs_three_blocks_and_no_grenade() -> void:
	var m := _playing_main()
	m._seen["armor"] = true
	Runner.T.ok(not m._note_armor_block() and not m._note_armor_block(), "two blocks are not enough")
	Runner.T.ok(m._seen.get("armor", false), "...and the hint stays retired")
	Runner.T.ok(m._note_armor_block(), "the third block re-arms it")
	Runner.T.ok(not m._seen.has("armor"), "re-armed: _hint('armor') may fire again")
	m.free()
	var thrower := _playing_main()
	thrower._seen["armor"] = true
	thrower.sim = SimWorld.new(3, 1)
	thrower.sim.events.assign([{"t": "throw", "x": 0, "y": 0, "i": 0}])
	thrower._consume_events()
	for i in 6:
		Runner.T.ok(not thrower._note_armor_block(), "a player who has thrown a grenade is never re-taught")
	thrower.free()
	var unread := _playing_main()
	for i in 6:
		Runner.T.ok(not unread._note_armor_block(), "no re-arm while the first hint has not been delivered")
	unread.free()


func test_the_rearm_sits_right_before_the_armor_hint_call() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("_hint(\"armor\", ")
	Runner.T.ok(at > 0, "found the armor hint call")
	var before := src.substr(maxi(0, at - 400), 400)
	Runner.T.ok(before.contains("_note_armor_block()"), "the re-arm is evaluated immediately before the hint call")
	Runner.T.ok(src.contains("_caption_cue(kind)") and src.contains("_caption_cue(\"armor_block\")"),
		"both caption call sites route through the policy-syncing wrapper")
