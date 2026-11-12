extends RefCounted
## Title/splash polish: the logo lockup, composed backdrop and footer (src/view/title_polish.gd)
## are plain-data plans; these tests pin their content and prove the REAL menu header and the
## REAL main.gd splash source reach them.

const Runner := preload("res://tests/run_tests.gd")


class _Main extends Node2D:
	var _motion := 1.0
	var best_score := 0
	var _life_runs := 0


class _Menu extends GameMenu:
	var stamps: Array = []
	var rects := 0
	var faces: Array = []
	func _center_text(txt: String, _y: float, _size: int, _col: Color) -> void:
		faces.append(txt)
	func _emit_rect(_r: Rect2, _c: Color) -> void:
		rects += 1
	func _emit_stamp(txt: String, pos: Vector2, _c: Color, _size: int) -> void:
		stamps.append({"txt": txt, "pos": pos})


func _title(motion: float) -> _Menu:
	var m := _Menu.new()
	var mn := _Main.new()
	mn._motion = motion
	m.main = mn
	m.mode = GameMenu.Mode.TITLE
	m._open_t = 1.0
	m._amb_t = 0.5
	return m


func _kinds(ops: Array) -> Dictionary:
	var d := {}
	for op in ops:
		d[op["k"]] = int(d.get(op["k"], 0)) + 1
	return d


func test_real_title_header_reaches_the_polish_module() -> void:
	TitlePolish.last_ops = []
	var m := _title(1.0)
	m._draw_title_header()
	var k := _kinds(TitlePolish.last_ops)
	Runner.T.ok(int(k.get("tex", 0)) >= 1, "header plan carries the emblem texture")
	Runner.T.ok(int(k.get("outline", 0)) >= 1 and int(k.get("text", 0)) >= 4, "header plan carries the outlined/extruded wordmark underlay")
	Runner.T.ok(int(k.get("tri", 0)) >= 6, "header plan carries vignette + searchlight polygons")
	Runner.T.ok(int(k.get("circle", 0)) >= 20, "header plan carries drifting smoke")
	Runner.T.ok("COMMANDER IN CHIEF" in m.faces, "the real wordmark face is still drawn through the text seam")
	var ver := TitlePolish.version_text()
	var seen := false
	for s in m.stamps:
		if s["txt"] == ver:
			seen = true
	Runner.T.ok(seen, "the footer stamps the version %s" % ver)
	Runner.T.ok(m.stamps.size() >= 2, "footer stamps version and copyright")
	m.main.free()
	m.free()


func test_footer_stays_on_canvas() -> void:
	for it in TitlePolish.footer_items(8):
		var w := Art.tw(String(it["txt"]), 8)
		Runner.T.ok(float(it["x"]) >= 4.0 and float(it["x"]) + w <= 636.0, "footer '%s' inside the canvas" % it["txt"])


func test_version_matches_project_setting() -> void:
	Runner.T.eq(TitlePolish.version_text(), "V" + str(ProjectSettings.get_setting("application/config/version")), "version text tracks project.godot")


func test_reduce_motion_is_static() -> void:
	Runner.T.eq(TitlePolish.wordmark_over(320.0, 90.0, 32, 1.0, 0.4, 0.0).size(), 0, "no shimmer under reduce motion")
	Runner.T.eq(TitlePolish.beam_angle(0, 1.0, 0.0), TitlePolish.beam_angle(0, 9.0, 0.0), "beams do not sweep under reduce motion")
	Runner.T.eq(str(TitlePolish.smoke(1.0, 0.0, 1.0)), str(TitlePolish.smoke(30.0, 0.0, 1.0)), "smoke does not drift under reduce motion")
	Runner.T.ok(TitlePolish.beam_angle(0, 1.0, 1.0) != TitlePolish.beam_angle(0, 9.0, 1.0), "beams sweep with motion on")
	Runner.T.ok(str(TitlePolish.smoke(1.0, 1.0, 1.0)) != str(TitlePolish.smoke(30.0, 1.0, 1.0)), "smoke drifts with motion on")


func test_shimmer_runs_only_inside_its_window() -> void:
	Runner.T.ok(TitlePolish.wordmark_over(320.0, 90.0, 32, 1.0, 0.65, 1.0).size() > 0, "shimmer lights letters mid-sweep")
	Runner.T.eq(TitlePolish.wordmark_over(320.0, 90.0, 32, 1.0, 4.0, 1.0).size(), 0, "shimmer idles between sweeps")


func test_emblem_is_a_real_picture() -> void:
	var img := TitlePolish.build_emblem_image()
	Runner.T.eq(img.get_width(), TitlePolish.EMBLEM_W, "emblem width")
	var opaque := 0
	var gold := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.9:
				opaque += 1
				if c.r > 0.7 and c.g > 0.5 and c.b < 0.5:
					gold += 1
	Runner.T.ok(opaque > 1500, "emblem has solid body (%d px)" % opaque)
	Runner.T.ok(gold > 400, "emblem carries gold facets/chevrons (%d px)" % gold)
	Runner.T.ok(img.get_pixel(0, 0).a < 0.01, "emblem corners are transparent")


func test_splash_title_beat_uses_the_lockup() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var a := src.find("func _draw_splash_title")
	var b := src.find("func _draw_splash_hero")
	Runner.T.ok(a > 0 and b > a and src.substr(a, b - a).contains("TitlePolish.wordmark_full"),
		"splash title beat paints the shared wordmark lockup")
	var s := src.find("func _draw_splash()")
	Runner.T.ok(src.substr(s, 900).contains("TitlePolish.vignette"), "splash frames itself with the shared vignette")


func test_wordmark_full_layers_in_order() -> void:
	var ops := TitlePolish.wordmark_full(320.0, 90.0, 32, 1.0, 0.0, 0.0)
	Runner.T.eq(String(ops[0]["k"]), "outline", "outline first")
	Runner.T.ok(ops[ops.size() - 1]["col"].is_equal_approx(Color(TitlePolish.GOLD, 1.0)), "flat gold face last when static")


func test_backdrop_is_a_solid_composed_scene_not_dimmed_gameplay() -> void:
	var img := TitlePolish.build_scene_image()
	Runner.T.eq(img.get_size(), Vector2i(640, 360), "scene bakes at native size")
	var opaque := true
	for p in [Vector2i(0, 0), Vector2i(639, 0), Vector2i(320, 180), Vector2i(0, 359), Vector2i(639, 359)]:
		opaque = opaque and img.get_pixelv(p).a >= 0.999
	Runner.T.ok(opaque, "every sampled backdrop pixel is fully opaque (no gameplay shows through)")
	Runner.T.ok(img.get_pixel(320, 20).get_luminance() < img.get_pixel(330, 232).get_luminance(), "sky brightens toward the horizon glow")
	Runner.T.ok(TitlePolish.ridge_y(100.0, true) < TitlePolish.ridge_y(100.0, false), "far ridge sits above the near ridge")
	var bd := TitlePolish.backdrop(1.0, 1.0, 1.0)
	Runner.T.ok(bd[0]["k"] == "tex" and bd[0]["rect"] == Rect2(0, 0, 640, 360), "backdrop leads with the full-screen scene texture")


func test_searchlight_beams_are_bright_enough_to_read() -> void:
	var ops := TitlePolish.searchlights(0.0, 1.0, 1.0)
	var peak := 0.0
	for op in ops:
		if op["k"] == "tri":
			peak = maxf(peak, op["cols"][0].a)
	Runner.T.ok(peak >= 0.3, "beam base alpha %.2f is clearly visible" % peak)


func test_splash_icon_is_masked_to_the_badge() -> void:
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var ops := TitlePolish.icon_ops(tex, Rect2(100, 50, 100, 100), 1.0)
	Runner.T.eq(ops.size(), 1, "one masked polygon")
	var pts: PackedVector2Array = ops[0]["pts"]
	var r := Rect2(100, 50, 100, 100)
	var inside := true
	for p in pts:
		inside = inside and r.grow(0.1).has_point(p)
	Runner.T.ok(inside and pts.size() >= 12, "mask polygon stays inside the rect (no square white corners)")
	var corner_cut := true
	for p in pts:
		corner_cut = corner_cut and not (p.x - r.position.x < 8.0 and p.y - r.position.y < 8.0)
	Runner.T.ok(corner_cut, "the top-left corner of the white square is excluded")


func test_wordmark_has_no_slab_behind_it() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/menu.gd")
	var a := src.find("func _draw_title_header(")
	var body := src.substr(a, 2600)
	Runner.T.ok(body.find("wplate") == -1, "no translucent plate behind COMMANDER IN CHIEF")


func test_world_draw_is_skipped_behind_the_opaque_backdrop() -> void:
	Runner.T.ok(TitlePolish.hides_world(1.0), "settled title hides the world")
	Runner.T.ok(not TitlePolish.hides_world(0.6), "a fading-in title does not")
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var w := src.find("_wash_load = 0.0   # fresh")
	var s := src.find("_sync_water()\n", w)
	var g := src.find("TitlePolish.hides_world(", w)
	Runner.T.ok(g != -1 and g < s, "the guard sits before the world draw")
