extends SceneTree
## Staged presentation review through the real GL renderer. This is not a gameplay
## completion test. The coordinator owns serial execution and the isolated profile.
## Required environment:
##   COMPLETION_CAPTURE_DIR=/absolute/output/directory
## Use tools/playtest_newcomer.sh for its canonical private profile, or provide
## COMPLETION_CAPTURE_PROFILE=/canonical/private/profile/root when launching
## through another isolated-profile harness.
## Launch with a GL context, --fixed-fps 60 and --rendering-method gl_compatibility.
## The profile guard runs before main.tscn can read or write user://.

const Shots := preload("res://tools/screenshots.gd")
const Quiesce := preload("res://tools/quiesce.gd")
const SfxScript := preload("res://src/view/sfx.gd")
const DESIGN_SIZE := Vector2i(640, 360)
const SETTLE_FRAMES := 12
const ACCESSIBILITY_PAGES := {
	"accessibility-hub": {"mode": GameMenu.Mode.ACCESSIBILITY, "opener": "", "title": "ACCESSIBILITY"},
	"accessibility-aim": {"mode": GameMenu.Mode.ACCESS_AIM, "opener": "access_aim", "title": "AIM & STICKS"},
	"accessibility-actions": {"mode": GameMenu.Mode.ACCESS_ACTIONS, "opener": "access_actions", "title": "HOLD / TOGGLE"},
	"accessibility-effects": {"mode": GameMenu.Mode.ACCESS_EFFECTS, "opener": "access_effects", "title": "SHAKE & FLASH"},
}
const ACCESSIBILITY_PREVIEW := {
	"single_stick_p1": true, "single_stick_p2": true, "aim_assist": 2,
	"classic_aim_p1": true, "classic_aim_p2": true,
	"toggle_grenade": true, "toggle_roll": true, "toggle_interact": true,
	"toggle_revive": true, "toggle_buy": true, "slow_mode": true,
	"shake_level": 4, "flash_level": 6,
}

var main: Node2D
var output_dir := ""
var cases: Array[Dictionary] = []
var evidence: Array[Dictionary] = []
var failures: Array[String] = []
var digests: Dictionary = {}


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_reject("A real GL framebuffer is required; --headless cannot capture presentation.")
		return
	var profile := OS.get_environment("COMPLETION_CAPTURE_PROFILE").trim_suffix("/")
	if profile.is_empty():
		var newcomer_profile := OS.get_environment("HOME").trim_suffix("/")
		if newcomer_profile.get_file().begins_with("cic-newcomer."):
			profile = newcomer_profile
	var userdata := OS.get_user_data_dir()
	if profile.is_empty() or not profile.is_absolute_path() \
			or not userdata.begins_with(profile + "/"):
		_reject("The isolated profile guard failed before boot: user:// must be inside COMPLETION_CAPTURE_PROFILE.")
		return
	output_dir = OS.get_environment("COMPLETION_CAPTURE_DIR")
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		_reject("COMPLETION_CAPTURE_DIR must name an absolute output directory.")
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		_reject("The presentation output directory could not be created.")
		return
	TranslationServer.set_locale("en")
	seed(0xC0FFEE)
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	root.set_disable_input(true)
	main.no_autopause = true
	_run()


func _process(_delta: float) -> bool:
	# Capture windows may be unfocused. Request a rendered frame explicitly so
	# frame_post_draw remains the source of pixels on desktop GL.
	RenderingServer.force_draw.call_deferred(false, 1.0 / 60.0)
	return false


func _reject(message: String) -> void:
	push_error("presentation capture: " + message)
	print("PRESENTATION CAPTURE FAILED — " + message)
	quit(1)


func _run() -> void:
	for _i in 6:
		await RenderingServer.frame_post_draw
	Shots._kill_splash(main)
	Shots._freeze_physics(main)
	_freeze_process(main)
	_build_cases()
	for i in cases.size():
		var spec: Dictionary = cases[i]
		_pose(spec)
		for _frame in SETTLE_FRAMES:
			Shots._redraw_all(main)
			await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := output_dir.path_join("%03d-%s.png" % [i + 1, spec["name"]])
		if img == null or img.is_empty():
			_fail(spec, "No framebuffer pixels were returned.")
			continue
		if img.save_png(path) != OK:
			_fail(spec, "The PNG could not be saved.")
			continue
		if not Shots._frame_is_live(img):
			_fail(spec, "The saved frame is blank or nearly flat.")
			continue
		var digest := FileAccess.get_md5(path)
		if digests.has(digest):
			_fail(spec, "The frame duplicates " + str(digests[digest]) + ".")
		digests[digest] = spec["name"]
		# Record measured commands only AFTER saving the live text-bearing frame.
		# Art.text_capture deliberately suppresses drawing and must never be armed
		# while the evidence PNG is taken.
		var ops: Array = []
		Art.text_capture = ops
		Shots._redraw_all(main)
		await RenderingServer.frame_post_draw
		Art.text_capture = null
		var record := _record(spec, path, img, ops)
		evidence.append(record)
		var record_file := FileAccess.open(path.trim_suffix(".png") + ".json", FileAccess.WRITE)
		if record_file == null:
			_fail(spec, "The per-frame geometry report could not be saved.")
		else:
			record_file.store_string(JSON.stringify(record, "\t"))
		print("PRESENTATION FRAME %s — %d text operations, minimum %.0f displayed pixels" %
			[spec["name"], record["text_operations"], record["minimum_displayed_font_pixels"]])
		Shots._redraw_all(main)
		await RenderingServer.frame_post_draw
	Art.text_capture = null
	Art.text_scale = 1.0
	var summary := {"kind": "staged real-renderer presentation review", "renderer": DisplayServer.get_name(),
		"profile_guard": true, "user_data_dir": OS.get_user_data_dir(), "cases": evidence,
		"failures": failures, "case_count": cases.size(), "captured_count": evidence.size(),
		"notes": ["PNG dimensions describe the engine framebuffer. Displayed font pixels use the actual client size and the configured integer/keep viewport projection.",
			"These staged frames verify presentation; gameplay completion is verified by the separate full-run controller."]}
	var summary_file := FileAccess.open(output_dir.path_join("capture-report.json"), FileAccess.WRITE)
	if summary_file == null:
		failures.append("The aggregate capture report could not be saved.")
	else:
		summary_file.store_string(JSON.stringify(summary, "\t"))
	await Quiesce.teardown(self, main)
	main = null
	if failures.is_empty() and evidence.size() == cases.size():
		print("PRESENTATION CAPTURE PASS — %d live unique frames; visual review required" % evidence.size())
		quit(0)
	else:
		print("PRESENTATION CAPTURE FAILED — %d problems; see capture-report.json" % failures.size())
		quit(1)


static func _freeze_process(node: Node) -> void:
	# Keep CanvasItem redraw enabled, while fixing the view clocks and timers.
	node.set_process(false)
	for child in node.get_children():
		_freeze_process(child)


func _add(name: String, kind: String, scale: float, extra: Dictionary = {}) -> void:
	var spec := {"name": "%d-%s" % [int(scale * 100), name], "kind": kind, "scale": scale}
	spec.merge(extra)
	cases.append(spec)


func _build_cases() -> void:
	for scale in [1.0, 2.0]:
		Art.text_scale = scale
		_add("title-records", "title", scale, {"expected": "CAREER"})
		_add("options-first", "options", scale, {"focus": "accessibility", "expected": "OPTIONS"})
		_add("options-last-dirty", "options", scale, {"last": true, "dirty": true, "expected": "OPTIONS"})
		_add("options-save-dirty", "options", scale,
			{"focus": "opts_save", "dirty": true, "expected": "OPTIONS", "expected_all": ["SAVE", "DISCARD"]})
		for kind in ACCESSIBILITY_PAGES:
			for dirty in [false, true]:
				for last in [false, true]:
					var extra := {"dirty": dirty, "last": last, "expected": ACCESSIBILITY_PAGES[kind]["title"]}
					if dirty:
						extra["expected_all"] = ["UNSAVED", "SAVE OR DISCARD"]
					_add("%s-%s-%s" % [kind, "dirty" if dirty else "clean", "last" if last else "first"],
						kind, scale, extra)
		_add("display", "display", scale, {"expected": "DISPLAY"})
		for tab in 4:
			_add("rebind-tab-%d-first" % (tab + 1), "rebind", scale, {"tab": tab, "expected": "CONTROLS"})
			_add("rebind-tab-%d-last" % (tab + 1), "rebind", scale, {"tab": tab, "last": true, "expected": "CONTROLS"})
		_add("rebind-player-two", "rebind", scale, {"tab": 2, "player": 1, "expected": "PLAYER 2"})
		_add("rebind-listening", "rebind", scale, {"tab": 1, "listen": "roll", "expected": "PRESS"})
		_add("hall-populated", "hall", scale, {"latest": false, "page": 0, "expected": "BOARD KEEPS"})
		_add("hall-latest", "hall", scale, {"latest": true, "page": 0, "expected": "YOUR LATEST"})
		_add("hall-latest-offpage", "hall", scale, {"latest": true, "page": 2, "expected": "YOUR LATEST RUN IS ON PAGE"})
		_add("hall-empty", "hall", scale, {"empty": true, "expected": "NO RUNS YET"})
		for tab in 5:
			main._menu.mode = GameMenu.Mode.HOWTO
			var leaf_count: int = main._menu._howto_large_pages(tab).size() if scale > 1.0 else (2 if tab == 4 else 1)
			for leaf in leaf_count:
				_add("manual-tab-%d-leaf-%d" % [tab + 1, leaf + 1], "manual", scale,
					{"tab": tab, "leaf": leaf, "leaves": leaf_count, "expected": "HOW TO PLAY"})
		_add("hud-teaching-caption", "hud", scale, {"state": "teaching", "expected": "SPOTTER"})
		_add("hud-supply-wheel", "hud", scale, {"state": "wheel", "expected": "RELEASE TO BUY"})
		_add("hud-ready", "hud", scale, {"state": "ready", "expected": "READY"})
		_add("hud-recovery", "hud", scale, {"state": "recovery", "expected": "REVIVE"})


func _pose(spec: Dictionary) -> void:
	Art.text_scale = float(spec["scale"])
	Art.use_pad = false
	main._text_scale = int(round(Art.text_scale * 100))
	main._motion = 0.0
	main._set_colorblind(false)
	main._captions = true
	main._debrief = false
	main._splash_t = 0.0
	main.position = Vector2.ZERO
	main.rotation = 0.0
	main._hint_text = ""
	main._hint_t = 0.0
	main._hint_id = ""
	main._hint_queue.clear()
	main._banners.clear()
	main._sfx.clear_captions()
	main._wheel.clear()
	main._wheel.append({"open": false, "sel": -1})
	main._wheel.append({"open": false, "sel": -1})
	main._last_inputs.clear()
	main._two_players = true
	main._assist = false
	for key in main.ACCESSIBILITY_KEYS:
		main.set_accessibility_setting(key, main.SETTINGS_DEFAULTS[key])
	main.sim = SimWorld.new(0xC0FFEE, 2, "campaign")
	main.sim.war_chest = 120
	main.sim.score = 12500
	main._hud_icons._disp_chest = 120.0
	main._hud_icons._disp_score = 12500.0
	main._hud_icons.verb_begin_run(main.sim.get_instance_id(), "keyboard", {})
	main.best_score = 12500
	main.best_wave = 12
	main.best_dist = 4800
	main._life_runs = 123
	main._life_kills = 4567
	main._life_wins = 42
	main.hall.clear()
	main.hall_latest.clear()
	main._menu._opts_dirty = false
	main._menu._items_valid = false
	main._hud_icons.visible = false
	match str(spec["kind"]):
		"title":
			main._menu.open(GameMenu.Mode.TITLE)
		"options":
			main._menu.open(GameMenu.Mode.OPTS)
			if bool(spec.get("dirty", false)):
				_stage_accessibility_preview()
			_focus_menu_row(str(spec.get("focus", "")))
		"display":
			main._menu.open(GameMenu.Mode.DISP)
		"rebind":
			main._menu.open(GameMenu.Mode.REBIND)
			main._menu._rebind_tab = int(spec["tab"])
			main._menu._rebind_pad_dev = int(spec.get("player", 0))
			main._menu._rebind_action = spec.get("listen", "")
		"hall":
			if not bool(spec.get("empty", false)):
				for i in 40:
					main.hall.append({"hid": i + 1, "score": 12500 - i * 200, "mode": "campaign",
						"sector": 4, "ticks": 18000, "grade": "A", "streak": 12,
						"won": i < 3, "daily": i == 1, "assist": i == 2, "hard": i == 3})
				if bool(spec.get("latest", false)):
					main.hall_latest = main.hall[3].duplicate()
			main._menu._hall_seen_hid = -1
			main._menu._hall_filter = 0
			main._menu.open(GameMenu.Mode.HALL)
			main._menu._hall_page = int(spec.get("page", 0))
		"manual":
			main._menu.open(GameMenu.Mode.HOWTO)
			main._menu._howto_page = int(spec["tab"])
			main._menu._howto_endless_page = int(spec["leaf"])
		"hud":
			_pose_hud(str(spec["state"]))
		_:
			if ACCESSIBILITY_PAGES.has(str(spec["kind"])):
				_pose_accessibility(spec)
	if bool(spec.get("last", false)):
		main._menu._items_valid = false
		main._menu.sel = main._menu._menu_items().size() - 1
	main._menu._items_valid = false
	main._menu._open_t = 1.0
	main._menu._sel_y = -1.0
	main._menu._sel_target = -1.0
	main._menu._amb_t = 0.0
	main._hud_icons._dirty = true


func _focus_menu_row(id: String) -> void:
	if id.is_empty():
		return
	main._menu._items_valid = false
	var rows: Array = main._menu._menu_items()
	for i in rows.size():
		if rows[i]["id"] == id:
			main._menu.sel = i
			return
	failures.append("The staged menu route has no visible row named " + id + ".")


func _stage_accessibility_preview() -> void:
	for key in ACCESSIBILITY_PREVIEW:
		main.set_accessibility_setting(key, ACCESSIBILITY_PREVIEW[key])
	main._menu._stage_opts()
	main._menu._mark_dirty()


func _pose_accessibility(spec: Dictionary) -> void:
	main._menu.open(GameMenu.Mode.OPTS)
	if bool(spec.get("dirty", false)):
		_stage_accessibility_preview()
	_focus_menu_row("accessibility")
	main._menu._press()
	var page: Dictionary = ACCESSIBILITY_PAGES[str(spec["kind"])]
	if not str(page["opener"]).is_empty():
		_focus_menu_row(page["opener"])
		main._menu._press()
	if main._menu.mode != int(page["mode"]):
		_fail(spec, "The visible menu route did not reach the requested accessibility page.")
	if main._menu._opts_dirty != bool(spec.get("dirty", false)):
		_fail(spec, "The settings snapshot did not match the staged clean or unsaved state.")


func _pose_hud(state: String) -> void:
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._hud_icons.visible = true
	main.sim.players[0]["y"] = -130 * Fixed.ONE
	main.sim.players[1]["y"] = -150 * Fixed.ONE
	match state:
		"teaching":
			main._hint_text = "GRENADE THE BUNKER — CLEAR YOUR LANDING ZONE"
			main._hint_id = "bunker"
			main._hint_t = 6.0
			main._sfx._arm_caption(SfxScript._VO_CAPTIONS["vo_airstrike"], null, true, true, SfxScript.CaptionTier.OBJECTIVE)
		"wheel":
			main.sim = SimWorld.new(0xC0FFEE, 2, "endless")
			main.sim.war_chest = 250
			main.sim.intermission_ticks = 300
			main._wheel[0] = {"open": true, "sel": 0, "center": Vector2(320, 220)}
			main._hud_icons._disp_chest = 250.0
			main._hud_icons._disp_score = 0.0
		"ready":
			main.sim = SimWorld.new(0xC0FFEE, 2, "endless")
			main.sim.intermission_ticks = 300
			main.sim.ready_hold = SimWorld.READY_HOLD_TICKS / 2
			var input_one := SimInput.new()
			input_one.revive = true
			main._last_inputs.append(input_one)
			main._last_inputs.append(SimInput.new())
			main._hud_icons._disp_chest = 0.0
			main._hud_icons._disp_score = 0.0
		"recovery":
			main.sim.players[1]["alive"] = false
			main.sim.players[1]["deaths"] = 1
			main.sim.players[1]["broke_timer"] = 120
			main._hint_id = "revive"
			main._hint_t = 6.0
			main._sfx.caption_sfx("rear_warn")


func _record(spec: Dictionary, path: String, img: Image, ops: Array) -> Dictionary:
	var client := DisplayServer.window_get_size()
	# project.godot uses viewport/integer/keep. This is the actual native client
	# projection, independent of the framebuffer's internal render resolution.
	var projection := floorf(minf(float(client.x) / DESIGN_SIZE.x, float(client.y) / DESIGN_SIZE.y))
	if projection < Art.MIN_WINDOW_SCALE:
		_fail(spec, "The client is smaller than the supported 2x presentation floor.")
	var min_font := 999
	var ink: Array[Dictionary] = []
	var ids: Array[String] = []
	for op in ops:
		if float(op.get("alpha", 1.0)) <= 0.0 or str(op.get("id", "")).is_empty():
			continue
		var size := int(op["size"])
		min_font = mini(min_font, size)
		var box: Rect2 = op["box"]
		ids.append(str(op["id"]))
		ink.append({"text": str(op["id"]), "logical_font_pixels": size,
			"displayed_font_pixels": size * projection, "box": _rect(box)})
	if min_font == 999:
		_fail(spec, "No readable text was measured from the real drawing path.")
		min_font = 0
	if min_font < 9 or float(min_font) * projection < 18.0:
		_fail(spec, "Readable text fell below the 18 displayed pixel floor.")
	var expected := str(spec.get("expected", ""))
	if not expected.is_empty() and not " ".join(ids).contains(expected):
		_fail(spec, "Expected content was absent from the drawn text: " + expected)
	for required in spec.get("expected_all", []):
		if not " ".join(ids).contains(str(required)):
			_fail(spec, "Expected content was absent from the drawn text: " + str(required))
	var controls: Array[Dictionary] = []
	var page_info: Dictionary = {}
	var settings_preview: Dictionary = {}
	if str(spec["kind"]) in ["title", "options", "display", "rebind"] or ACCESSIBILITY_PAGES.has(str(spec["kind"])):
		var g: Dictionary = main._menu._row_geometry()
		var rows: Array = main._menu._menu_items()
		var first := int(g.get("first_row", 0))
		var visible := int(g.get("visible_rows", rows.size()))
		page_info = {"first_row": first, "visible_rows": visible, "total_rows": rows.size(), "selected_row": main._menu.sel}
		if str(spec["kind"]) == "options" or ACCESSIBILITY_PAGES.has(str(spec["kind"])):
			if main._menu.sel < first or main._menu.sel >= first + visible:
				_fail(spec, "The focused settings row was outside the visible page.")
			var focused_footer: Dictionary = main._menu._focused_footer()
			var footer_top: float = GameMenu.footer_layout(focused_footer["help"], focused_footer["segs"])["top"]
			if GameMenu.max_glow_bottom(g) >= footer_top:
				_fail(spec, "The visible settings rows reached the complete help footer.")
			var selected_action: String = rows[main._menu.sel]["id"]
			settings_preview = {"dirty": main._menu._opts_dirty, "selected_action": selected_action,
				"settings": main._settings_snapshot(), "entry_baseline": main._menu._opts_snapshot}
			if main._menu._opts_dirty != bool(spec.get("dirty", false)):
				_fail(spec, "The recorded settings snapshot did not match the requested dirty state.")
			if str(spec.get("focus", "")) != "" and selected_action != str(spec["focus"]):
				_fail(spec, "The requested settings action was not the actual focused row.")
		for i in range(first, first + visible):
			var box := GameMenu.row_rect(g, i)
			if ACCESSIBILITY_PAGES.has(str(spec["kind"])) and box.size.y < Art.font().get_height(GameMenu.ROW_LABEL_SIZE) + 4.0:
				_fail(spec, "An accessibility row did not enclose its readable body label.")
			var center_hits: bool = main._menu._row_at(box.get_center()) == i
			if not center_hits:
				_fail(spec, "A visible row center did not target its drawn action.")
			controls.append({"action": str(rows[i]["id"]), "box": _rect(box),
				"displayed_size": [box.size.x * projection, box.size.y * projection],
				"center_hits_row": center_hits})
	elif str(spec["kind"]) == "hall":
		var rows: Array = main._menu._hall_rows()
		page_info = {"page": main._menu._hall_page + 1, "page_size": GameMenu.hall_page_size(), "total_rows": rows.size()}
		for box in main._menu._hall_page_rects():
			controls.append({"action": "hall page", "box": _rect(box)})
	elif str(spec["kind"]) == "manual":
		page_info = {"tab": spec["tab"], "leaf": int(spec["leaf"]) + 1, "leaves": spec["leaves"]}
	return {"name": spec["name"], "kind": spec["kind"], "text_percent": int(float(spec["scale"]) * 100),
		"png": path, "md5": FileAccess.get_md5(path), "framebuffer_size": [img.get_width(), img.get_height()],
		"client_size": [client.x, client.y], "integer_projection": projection,
		"minimum_logical_font_pixels": min_font, "minimum_displayed_font_pixels": min_font * projection,
		"text_operations": ink.size(), "frame_stats": Shots.frame_stats(img),
		"page": page_info, "controls": controls, "text": ink, "settings_preview": settings_preview}


static func _rect(box: Rect2) -> Array:
	return [box.position.x, box.position.y, box.size.x, box.size.y]


func _fail(spec: Dictionary, message: String) -> void:
	var text := str(spec["name"]) + ": " + message
	failures.append(text)
	push_error("presentation capture: " + text)
