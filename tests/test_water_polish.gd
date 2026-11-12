extends RefCounted
## Water & riverbanks polish: the irregular shoreline shared by shader and sand polygon,
## the wet-sand strip, and the washed-out-ford flood wash that replaced a flat rectangle.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")


func test_jitter_stays_inside_the_bank_polygons_clearance() -> void:
	var worst := 0.0
	for i in 400:
		var u := float(i) / 399.0
		for top in [true, false]:
			var off := WaterPolish.shore_offset(u, 3.7 + float(i % 7), top, Main.BANK_AMP, Main.BANK_FREQ)
			worst = maxf(worst, absf(off))
	Runner.T.ok(worst <= Main.BANK_AMP.x + Main.BANK_AMP.y + WaterPolish.MAX_JITTER + 0.001,
		"shore offset is bounded by the slow sines plus the jitter")
	Runner.T.ok(Main.BANK_AMP.x + Main.BANK_AMP.y + WaterPolish.MAX_JITTER < Main.BANK_BASE,
		"jittered shore can never cross the dry edge of the bank polygon")


func test_shoreline_is_irregular_not_just_two_sines() -> void:
	var rough := 0.0
	for s in 128:
		var u := float(s) / 128.0
		var base: float = Main._bank_offset(u, 1.3, true)
		var full := WaterPolish.shore_offset(u, 1.3, true, Main.BANK_AMP, Main.BANK_FREQ)
		rough = maxf(rough, absf(full - base))
	Runner.T.ok(rough > 0.5, "the high-frequency jitter really moves the edge (%.2f px)" % rough)
	var pts := WaterPolish.shore_points(100.0, 80.0, 1.3, true, Main.BANK_AMP, Main.BANK_FREQ)
	Runner.T.eq(pts.size(), WaterPolish.SHORE_STEPS + 1, "shore sampled at 5px")
	Runner.T.ok(absf(pts[0].x) < 0.001 and absf(pts[pts.size() - 1].x - 640.0) < 0.001, "spans the screen")


func test_shader_jitter_literals_match_the_module() -> void:
	var sh := FileAccess.get_file_as_string("res://src/view/water.gdshader")
	Runner.T.ok(sh.contains("%.1f * sin(u * %.1f + phase * %.1f)" % [WaterPolish.JIT_AMP.x,
		WaterPolish.JIT_FREQ.x, WaterPolish.JIT_PHASE.x]),
		"shader jitter term 1 mirrors WaterPolish")
	Runner.T.ok(sh.contains("%.1f * sin(u * %.1f + phase * %.1f)" % [WaterPolish.JIT_AMP.y,
		WaterPolish.JIT_FREQ.y, WaterPolish.JIT_PHASE.y]),
		"shader jitter term 2 mirrors WaterPolish")
	Runner.T.ok(not sh.contains("edge_n"), "no time-varying edge noise the sand cannot follow")
	Runner.T.ok(sh.contains("uniform float surge") and sh.contains("uniform float surge_halfw"),
		"shader exposes the flood-wash uniforms")


func test_wet_strip_is_a_dark_fade_on_the_dry_side() -> void:
	for top in [true, false]:
		var edge := WaterPolish.shore_points(200.0, 80.0, 2.0, top, Main.BANK_AMP, Main.BANK_FREQ)
		var strip := WaterPolish.wet_strip(edge, top, 2.0, Color(0.2, 0.15, 0.1))
		var pts: PackedVector2Array = strip["pts"]
		var cols: PackedColorArray = strip["cols"]
		Runner.T.eq(pts.size(), edge.size() * 2, "strip has an edge row and a dry-side row")
		Runner.T.eq(cols.size(), pts.size(), "one colour per vertex")
		Runner.T.ok(cols[0].a > 0.4 and cols[cols.size() - 1].a == 0.0, "opaque at the water, gone up the bank")
		var reach := 0.0
		for i in edge.size():
			var dy: float = pts[edge.size() * 2 - 1 - i].y - edge[i].y
			Runner.T.ok((dy < 0.0) == top and absf(dy) > 1.0, "wet band reaches onto the dry side")
			reach = maxf(reach, absf(dy))
		Runner.T.ok(reach < Main.BANK_BASE + 4.0, "wet band stays near the bank, not across the ground")
	Runner.T.ok(WaterPolish.wet_tint(Color(0.9, 0.85, 0.7)).get_luminance() < 0.4, "damp sand is dark")


func test_surge_halfw_follows_the_sims_tightening_crossing() -> void:
	var prev := 9.0
	for band in range(1, 8):
		var h := WaterPolish.surge_halfw(band)
		Runner.T.ok(h <= prev and h > 0.0, "band %d half-width %.3f never widens" % [band, h])
		Runner.T.eq(h, float(SimWorld.ford_half_w(band)) / float(Fixed.ONE) / 640.0, "band %d matches the sim" % band)
		prev = h


func test_real_sync_water_pushes_the_flood_wash_only_while_closed() -> void:
	## Through the real src/main.gd _sync_water with a hand-built one-slot pool.
	var m: Node2D = (load("res://src/main.gd") as Script).new()
	m._water_shader = load("res://src/view/water.gdshader")
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = m._water_shader
	rect.material = mat
	m._water_rects.append(rect)
	m._water_pushed.append(m._water_pushed_row())
	m.sim = SimWorld.new(0xC0FFEE, 1)
	var band_y: int = -2 * SimWorld.GATE_SPACING
	m.sim.camera_top = band_y - 40 * Fixed.ONE
	m.sim.waters.clear()
	m.sim.waters.append({"y": band_y, "ford_x": 300 * Fixed.ONE})
	var closed_tick := -1
	var open_tick := -1
	for t in 2000:
		if SimWorld.ford_closed(t, 2):
			closed_tick = t if closed_tick < 0 else closed_tick
		elif open_tick < 0:
			open_tick = t
	Runner.T.ok(closed_tick >= 0 and open_tick >= 0, "band 2 both opens and washes out")
	m.sim.tick_count = closed_tick
	m._sync_water()
	Runner.T.eq(float(mat.get_shader_parameter("surge")), 1.0, "washed-out ford turns the surge on")
	Runner.T.eq(float(mat.get_shader_parameter("surge_halfw")), WaterPolish.surge_halfw(2),
		"surge spans the sim's real crossing")
	m.sim.tick_count = open_tick
	m._sync_water()
	Runner.T.eq(float(mat.get_shader_parameter("surge")), 0.0, "open ford has no surge")
	rect.free()
	m._sfx.free()
	m.free()


func test_draw_water_is_wired_to_the_module_and_dropped_the_flat_boxes() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("func _draw_water() -> void:")
	var end := src.find("static func ford_visual", at)
	var body := src.substr(at, end - at)
	Runner.T.ok(body.contains("WaterPolish.shore_points("), "_draw_water cuts the bank from the shared shoreline")
	Runner.T.ok(body.contains("WaterPolish.wet_strip("), "_draw_water paints the wet-sand strip")
	Runner.T.ok(not body.contains("for fi in 4:"), "the stacked flat flood rectangles are gone")
