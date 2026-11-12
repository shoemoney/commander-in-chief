extends RefCounted
## HUD POLISH: the solid plate, icon trays, divider and keycap geometry, proven through the REAL
## HudIcons draw paths (via their emit seams) and the pure HudPolish helpers.

const Runner := preload("res://tests/run_tests.gd")
const HudTests := preload("res://tests/test_hud.gd")


class _PolishHud extends HudIcons:
	var solids: Array = []
	var rects: Array = []
	func _emit_plate_solid(r: Rect2, c: Color) -> void:
		solids.append({"r": r, "c": c})
	func _emit_plate_rect(_id: String, _d: Rect2, _t: RID, _s: Rect2, _c: Color) -> void:
		pass
	func _emit_plate_border(_p: PackedVector2Array, _c: PackedColorArray) -> void:
		pass
	func _emit_icon(_icon: String, _r: Rect2, _m := Color.WHITE) -> void:
		pass
	func _emit_hud_text(_t: String, _p: Vector2, _c: Color) -> void:
		pass
	func _emit_rect(r: Rect2, c: Color) -> void:
		rects.append({"r": r, "c": c})
	func _emit_glyph(_a: String, _c: Vector2, _s: float, _col: Color) -> void:
		pass
	func _emit_label(_t: String, _p: Vector2, _c: Color) -> void:
		pass


func _hud() -> _PolishHud:
	var h := _PolishHud.new()
	h.main = HudTests._RowMain.new()
	h._plate_r = 260.0
	return h


func _free(h: _PolishHud) -> void:
	h.main.free()
	h.free()


func test_plate_is_a_solid_near_opaque_fill() -> void:
	Runner.T.ok(HudPolish.PLATE_FILL.a >= 0.68 and HudPolish.PLATE_FILL.a <= 0.80, "plate fill is see-through (0.68-0.80) so enemies entering under it stay visible")
	var h := _hud()
	h._draw_plate(40.0)
	Runner.T.ok(h.solids.size() >= 1, "_draw_plate emits the solid fill through the polish seam")
	var fill: Rect2 = h.solids[0]["r"]
	Runner.T.eq(fill.position, Vector2(2, 2), "fill starts at the plate origin")
	Runner.T.ok(absf(fill.size.x - 260.0) < 0.01 and absf(fill.size.y - 40.0) < 0.01, "fill covers the whole plate")
	Runner.T.ok(h.solids[0]["c"] == HudPolish.PLATE_FILL, "fill uses the declared colour")
	_free(h)


func test_stat_icons_get_a_tray_under_the_plate() -> void:
	var h := _hud()
	h._polish.begin_frame()
	h._stat("icon_ammo", "64", 20.0, 30.0)
	Runner.T.eq(h._polish.trays().size(), 1, "a painted _stat queues one icon tray")
	h._draw_plate(60.0)
	var want := Rect2(20.0, 30.0, HudIcons.ICON, HudIcons.ICON).grow(1.0)
	var edge := false
	var inner := false
	for s in h.solids:
		if s["r"] == want and s["c"] == HudPolish.TRAY_EDGE:
			edge = true
		if s["r"] == want.grow(-1.0) and s["c"] == HudPolish.TRAY_FILL:
			inner = true
	Runner.T.ok(edge and inner, "the tray keyline and fill land around the icon rect")
	h._polish.begin_frame()
	h._measure = true
	h._stat("icon_ammo", "64", 20.0, 30.0)
	h._measure = false
	Runner.T.eq(h._polish.trays().size(), 0, "the measure pass queues no tray")
	_free(h)


func test_tray_queue_is_bounded_and_resets() -> void:
	var p := HudPolish.new()
	for i in HudPolish.TRAY_CAP + 20:
		p.queue_tray(Rect2(i, 0, 13, 13))
	Runner.T.eq(p.trays().size(), HudPolish.TRAY_CAP, "queue is capped")
	p.begin_frame()
	Runner.T.eq(p.trays().size(), 0, "begin_frame empties it")


func test_keycap_geometry_is_whole_pixel_and_contains_the_legend() -> void:
	var g := HudPolish.keycap_geometry(Vector2(100.3, 50.6), 12.85, 13.0)
	var face: Rect2 = g["face"]
	var rim_b: Rect2 = g["rim_b"]
	Runner.T.ok(face.position == face.position.floor() and face.size == face.size.floor(), "face is on whole pixels")
	Runner.T.ok(rim_b.encloses(face), "rim encloses the face")
	Runner.T.ok(face.size.y >= 8.0, "face is tall enough for the 8px legend (%.1f)" % face.size.y)
	var f := Art.font()
	var lw := f.get_string_size("C", HORIZONTAL_ALIGNMENT_LEFT, -1, HudPolish.KEY_FONT).x
	Runner.T.ok(lw <= face.size.x, "a one-letter legend fits the face width")


func test_keycap_is_used_on_keyboard_only() -> void:
	var was: bool = Art.use_pad
	Art.use_pad = false
	Runner.T.ok(HudPolish.uses_keycap(false), "keyboard draws the procedural keycap")
	Runner.T.ok(not HudPolish.uses_keycap(true), "forced pad (P2) keeps the baked pad art")
	Art.use_pad = true
	Runner.T.ok(not HudPolish.uses_keycap(false), "pad device keeps the baked pad art")
	Art.use_pad = was


func test_hud_glyph_seams_route_through_the_polish_module() -> void:
	var src: String = (load("res://src/view/hud.gd") as GDScript).source_code
	Runner.T.eq(src.count("HudPolish.draw_act_glyph("), 3, "all three glyph seams draw through HudPolish")
	Runner.T.ok(src.find("_polish.queue_tray(") >= 0, "_stat queues icon trays")
	Runner.T.ok(src.find("_polish_plate_under(") >= 0, "_draw_plate lays the polish under-layer")


func test_prompt_rail_has_a_keyline_and_a_solid_plate() -> void:
	var h := _hud()
	h._verb_show = 300.0
	h._verb_legend()
	Runner.T.eq(h.rects.size(), 2, "rail emits keyline then plate")
	var edge: Rect2 = h.rects[0]["r"]
	var plate: Rect2 = h.rects[1]["r"]
	Runner.T.ok(edge == plate.grow(1.0), "keyline is the plate itself, the fill sits one pixel inside")
	Runner.T.ok(float(h.rects[1]["c"].a) >= 0.9, "rail plate is near-opaque")
	_free(h)


func test_unlit_states_are_no_longer_ghosts() -> void:
	Runner.T.ok(HudIcons.VITALS_OFF >= 0.4, "an unlit vest pip stays readable")
