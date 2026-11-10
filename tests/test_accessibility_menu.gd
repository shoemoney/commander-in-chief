extends RefCounted

const Runner := preload("res://tests/run_tests.gd")
const Menu := preload("res://src/view/menu.gd")
const Layout := preload("res://tests/test_menu_layout.gd")
const MainScript := preload("res://src/main.gd")
const PAGES := [Menu.Mode.ACCESSIBILITY, Menu.Mode.ACCESS_AIM,
	Menu.Mode.ACCESS_ACTIONS, Menu.Mode.ACCESS_EFFECTS]
const KEYS := ["single_stick_p1", "single_stick_p2", "aim_assist",
	"classic_aim_p1", "classic_aim_p2", "toggle_grenade", "toggle_roll",
	"toggle_interact", "toggle_revive", "toggle_buy", "slow_mode",
	"shake_level", "flash_level"]


func _row(menu: GameMenu, id: String) -> int:
	var items := menu._menu_items()
	for i in items.size():
		if items[i]["id"] == id:
			return i
	return -1


func _press(menu: GameMenu, id: String) -> void:
	menu.sel = _row(menu, id)
	Runner.T.ok(menu.sel >= 0, "reachable menu row %s" % id)
	if menu.sel >= 0:
		menu._press()


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_accessibility_pages_reachable_and_back_restores_focus() -> void:
	for parent in [Menu.Mode.SETUP, Menu.Mode.PAUSE]:
		var stub := Layout._StubMain.new()
		var menu := Menu.new()
		menu.main = stub
		menu.open(parent)
		_press(menu, "options")
		Runner.T.eq(menu.mode, Menu.Mode.OPTS, "OPTIONS opens from its real parent")
		_press(menu, "accessibility")
		Runner.T.eq(menu.mode, Menu.Mode.ACCESSIBILITY, "OPTIONS opens ACCESSIBILITY")
		Runner.T.eq(menu._menu_items().size(), 9, "accessibility hub has nine readable rows")
		for route in [["access_aim", Menu.Mode.ACCESS_AIM],
				["access_actions", Menu.Mode.ACCESS_ACTIONS],
				["access_effects", Menu.Mode.ACCESS_EFFECTS]]:
			_press(menu, route[0])
			Runner.T.eq(menu.mode, route[1], "submenu opens through its visible row")
			Runner.T.ok(menu._menu_items().size() <= 7, "accessibility detail page stays short")
			_press(menu, "back")
			Runner.T.eq(menu.mode, Menu.Mode.ACCESSIBILITY, "detail BACK returns to accessibility")
			Runner.T.eq(menu._menu_items()[menu.sel]["id"], route[0], "BACK restores opener focus")
		_press(menu, "back")
		Runner.T.eq(menu.mode, Menu.Mode.OPTS, "accessibility BACK returns to OPTIONS")
		Runner.T.eq(menu._menu_items()[menu.sel]["id"], "accessibility", "OPTIONS focus returns to accessibility")
		_press(menu, "back")
		Runner.T.eq(menu.mode, parent, "clean OPTIONS BACK returns to its real parent")
		menu.free()
		stub.free()


func test_every_accessibility_setting_is_reachable_and_changes_live() -> void:
	var stub := Layout._StubMain.new()
	var menu := Menu.new()
	menu.main = stub
	menu.open(Menu.Mode.OPTS)
	var seen := {}
	for page in PAGES:
		menu.open(page)
		var items := menu._menu_items()
		for i in items.size():
			var row: Dictionary = items[i]
			if not row.has("a11y_key"):
				continue
			var key: String = row["a11y_key"]
			seen[key] = true
			menu.sel = i
			var before: Variant = stub.accessibility_setting(key)
			var dir := -1 if row["a11y_kind"] == "level" else 1
			menu._nav(0, dir)
			var expected: Variant = not bool(before) if row["a11y_kind"] in ["bool", "hold"] else int(before) + dir
			Runner.T.eq(stub.accessibility_setting(key), expected, "%s responds to focused horizontal navigation" % key)
			Runner.T.ok(menu._opts_dirty, "%s changes the pending settings snapshot" % key)
			Runner.T.eq(stub._saved, 0, "%s preview does not write settings" % key)
			Runner.T.ok(menu._row_cyclable(menu._menu_items()[i]), "%s has a visible adjustment affordance" % key)
	for key in KEYS:
		Runner.T.ok(seen.has(key), "%s has a reachable player control" % key)
	Runner.T.eq(seen.size(), KEYS.size(), "all promised local settings are represented once")
	menu._exit_opts(false)
	for key in KEYS:
		Runner.T.eq(stub.accessibility_setting(key), MainScript.SETTINGS_DEFAULTS[key], "%s discards back to the entry default" % key)
	menu.free()
	stub.free()


func test_tier_and_effect_sliders_clamp_and_confirm_steps() -> void:
	for spec in [[Menu.Mode.ACCESS_AIM, "aim_assist", 2],
			[Menu.Mode.ACCESS_EFFECTS, "shake_level", 10],
			[Menu.Mode.ACCESS_EFFECTS, "flash_level", 10]]:
		var stub := Layout._StubMain.new()
		var menu := Menu.new()
		menu.main = stub
		stub.set_accessibility_setting(spec[1], 0)
		menu.open(Menu.Mode.OPTS)
		menu.open(spec[0], spec[1])
		menu._nav(0, -1)
		Runner.T.eq(stub.accessibility_setting(spec[1]), 0, "left at the minimum does not wrap")
		Runner.T.ok(not menu._opts_dirty, "railed input leaves the snapshot clean")
		menu._press()
		Runner.T.eq(stub.accessibility_setting(spec[1]), 1, "confirm steps the same control upward")
		for _i in int(spec[2]) + 2:
			menu._nav(0, 1)
		Runner.T.eq(stub.accessibility_setting(spec[1]), spec[2], "right clamps at the maximum")
		menu._press()
		Runner.T.eq(stub.accessibility_setting(spec[1]), spec[2], "confirm also clamps at the maximum")
		Runner.T.eq(stub._saved, 0, "slider preview stays unsaved")
		menu.free()
		stub.free()


func test_new_settings_back_route_keeps_save_and_discard_explicit() -> void:
	for save in [false, true]:
		var stub := Layout._StubMain.new()
		var menu := Menu.new()
		menu.main = stub
		menu.open(Menu.Mode.SETUP)
		_press(menu, "options")
		_press(menu, "accessibility")
		_press(menu, "access_actions")
		_press(menu, "toggle_revive")
		Runner.T.ok(stub.accessibility_setting("toggle_revive"), "revive toggle changes live")
		Runner.T.ok("UNSAVED" in menu._list_caption(), "dirty detail page identifies unsaved changes")
		Runner.T.ok("SAVE OR DISCARD" in menu._list_caption(), "dirty page names the exit choices")
		_press(menu, "back")
		Runner.T.ok(menu._opts_dirty, "detail BACK keeps the pending preview")
		_press(menu, "back")
		Runner.T.ok(menu._opts_dirty, "accessibility BACK keeps the pending preview")
		Runner.T.ok(_row(menu, "opts_save") >= 0 and _row(menu, "opts_discard") >= 0,
			"OPTIONS presents both SAVE and DISCARD")
		_press(menu, "opts_save" if save else "opts_discard")
		Runner.T.eq(stub.accessibility_setting("toggle_revive"), save, "exit commits or reverts the preview")
		Runner.T.eq(stub._saved, 1 if save else 0, "only explicit SAVE writes settings")
		Runner.T.ok(not menu._opts_dirty, "either exit clears pending edits")
		Runner.T.eq(menu.mode, Menu.Mode.SETUP, "either exit restores the settings opener")
		menu.free()
		stub.free()


func test_paused_dirty_pages_block_help_escape_and_cancel_discards() -> void:
	var stub := Layout._StubMain.new()
	var menu := Menu.new()
	menu.main = stub
	menu.open(Menu.Mode.PAUSE)
	_press(menu, "options")
	_press(menu, "accessibility")
	_press(menu, "access_aim")
	_press(menu, "single_stick_p2")
	menu._unhandled_input(_key(Menu.HELP_KEY))
	Runner.T.eq(menu.mode, Menu.Mode.ACCESS_AIM, "HELP cannot orphan a dirty paused session")
	menu._unhandled_input(_key(KEY_ESCAPE))
	Runner.T.eq(menu.mode, Menu.Mode.ACCESSIBILITY, "cancel climbs to accessibility")
	Runner.T.eq(menu._menu_items()[menu.sel]["id"], "access_aim", "cancel restores the aim opener focus")
	menu._unhandled_input(_key(KEY_ESCAPE))
	Runner.T.eq(menu.mode, Menu.Mode.OPTS, "second cancel climbs to OPTIONS")
	Runner.T.ok(menu._opts_dirty, "pending edits survive the nested cancel route")
	menu._unhandled_input(_key(KEY_ESCAPE))
	Runner.T.eq(menu.mode, Menu.Mode.PAUSE, "cancel from OPTIONS returns to the paused run")
	Runner.T.ok(not stub.accessibility_setting("single_stick_p2"), "OPTIONS cancel discards the live change")
	Runner.T.eq(stub._saved, 0, "nested cancel never writes settings")
	menu.free()
	stub.free()


func test_new_setting_roundtrip_clears_dirty_before_back() -> void:
	var stub := Layout._StubMain.new()
	var menu := Menu.new()
	menu.main = stub
	menu.open(Menu.Mode.OPTS)
	menu.open(Menu.Mode.ACCESS_AIM, "aim_assist")
	menu._nav(0, 1)
	Runner.T.ok(menu._opts_dirty, "changing the aim tier makes the session dirty")
	menu._nav(0, -1)
	Runner.T.ok(not menu._opts_dirty, "restoring the tier clears the dirty session")
	menu.open(Menu.Mode.OPTS)
	Runner.T.eq(_row(menu, "opts_save"), -1, "restored settings need no SAVE row")
	Runner.T.ok(_row(menu, "back") >= 0, "clean settings have the normal BACK row")
	menu.free()
	stub.free()


func test_reset_defaults_restores_every_new_setting_after_confirmation() -> void:
	var stub := Layout._StubMain.new()
	var menu := Menu.new()
	menu.main = stub
	for key in KEYS:
		var baseline: Variant = MainScript.SETTINGS_DEFAULTS[key]
		stub.set_accessibility_setting(key, not bool(baseline) if baseline is bool else 0 if int(baseline) > 0 else 1)
	menu.open(Menu.Mode.OPTS, "reset_defaults")
	menu._press()
	Runner.T.eq(stub._saved, 0, "one reset press only arms confirmation")
	Runner.T.ok(stub.accessibility_setting("single_stick_p1"), "first reset press leaves the changed settings live")
	menu._press()
	for key in KEYS:
		Runner.T.eq(stub.accessibility_setting(key), MainScript.SETTINGS_DEFAULTS[key], "%s is restored by the confirmed reset" % key)
	Runner.T.eq(stub._saved, 1, "confirmed reset saves once")
	Runner.T.ok(not menu._opts_dirty, "reset establishes a clean saved baseline")
	Runner.T.ok(menu._menu_items()[menu.sel].get("disabled", false), "reset reports AT DEFAULTS after applying")
	menu.free()
	stub.free()


func test_all_new_pages_keep_large_text_inside_header_rows_and_footer() -> void:
	var old_scale := Art.text_scale
	var old_pad := Art.use_pad
	var stub := Layout._StubMain.new()
	stub._motion = 0.0
	var menu := Layout._CaptureMenu.new()
	menu.main = stub
	menu._open_t = 1.0
	for scale in [1.0, 2.0]:
		Art.text_scale = scale
		for pad in [false, true]:
			Art.use_pad = pad
			for dirty in [false, true]:
				menu._opts_dirty = dirty
				for page in PAGES:
					menu.mode = page
					for selected in menu._menu_items().size():
						menu.sel = selected
						menu.ops.clear()
						menu.centered.clear()
						menu._draw_mode_header()
						var header_ops := menu.ops.duplicate()
						menu.ops.clear()
						menu._footer_legend()
						var footer_ops := menu.ops.duplicate()
						var geometry := menu._row_geometry()
						var row_rect := Menu.row_rect(geometry, selected)
						Runner.T.ok(row_rect.size.x > 0.0 and row_rect.position.y >= 0.0,
							"selected row remains visible at the chosen text size")
						Runner.T.ok(row_rect.size.y >= Art.font().get_height(Menu.ROW_LABEL_SIZE) + 4.0,
							"selected row encloses the 20px displayed body label")
						var footer_top: float = footer_ops[0]["box"].position.y
						Runner.T.ok(Menu.max_glow_bottom(geometry) < footer_top,
							"last visible row glow clears the complete help footer")
						for op in header_ops + footer_ops:
							if op.has("size"):
								Runner.T.ok(int(op["size"]) * Art.MIN_WINDOW_SCALE >= 18,
									"every emitted header/help/keycap font meets the displayed minimum")
							var box: Rect2 = op["box"]
							Runner.T.ok(box.position.x >= 0.0 and box.end.x <= Menu.CANVAS_WIDTH
								and box.position.y >= 0.0 and box.end.y <= 360.0,
								"actual header and footer draw commands remain on canvas")
						for op in header_ops:
							Runner.T.ok((op["box"] as Rect2).end.y < row_rect.position.y,
								"actual header ink clears the selected row")
	menu.free()
	stub.free()
	Art.text_scale = old_scale
	Art.use_pad = old_pad


func test_accessibility_help_explains_manual_override_toggle_reset_and_save() -> void:
	for key in KEYS:
		var help := Menu.setting_help(key)
		Runner.T.ok("SAVE IN OPTIONS" in help, "%s names the deliberate save route" % key)
		Runner.T.ok(not help.contains("AUTOMATICALLY"), "%s does not promise an automatic save" % key)
	for key in ["single_stick_p1", "single_stick_p2"]:
		Runner.T.ok("MANUAL AIM TAKES PRIORITY" in Menu.setting_help(key), "single-stick help explains manual aim override")
	for key in ["toggle_grenade", "toggle_roll", "toggle_interact", "toggle_revive", "toggle_buy"]:
		Runner.T.ok("PRESS AGAIN" in Menu.setting_help(key) and "MENUS RESET IT" in Menu.setting_help(key),
			"toggle help explains cancellation and menu reset")
