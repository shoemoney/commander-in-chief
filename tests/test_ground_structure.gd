extends RefCounted
## GROUND STRUCTURE — six biomes, a lane, gate aprons, feathered seams.
##
## Every assertion measures OUTPUT: pixels of the real strip images the painter
## binds, composited with the real plan records; returned layers and rects. Nothing
## here restates a constant that was just edited.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")
const MainScript := preload("res://src/main.gd")
const GS := preload("res://src/view/ground_structure.gd")


func _mean_rgb(img: Image) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	return acc / float(n) * 255.0


func _luma_stats(img: Image) -> Dictionary:
	var vals: Array = []
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			vals.append(img.get_pixel(x, y).get_luminance() * 255.0)
	vals.sort()
	var m := 0.0
	for v in vals:
		m += v
	m /= float(vals.size())
	var s := 0.0
	for v in vals:
		s += (v - m) * (v - m)
	return {"mean": m, "std": sqrt(s / float(vals.size())), "p95": vals[int(vals.size() * 0.95)]}


func _rendered_strip(biome: int) -> Image:
	## What the player sees of a biome: the real strip, times the real shade (and the
	## sand ramp for biome 0, which is the only path that still carries a tint).
	var img: Image = MainScript.ground_biome_strip_image(biome, 0) if biome >= 1 \
		else MainScript.ground_base_strip_image(0)
	var shade := MainScript.GROUND_SHADE
	var tint := Color.WHITE
	if biome == 0:
		var c: Color = (MainScript._ground_stops("campaign")[0] as Array)[0]
		tint = Color(c.r, c.g, c.b)
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var p := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(p.r * shade * tint.r, p.g * shade * tint.g, p.b * shade * tint.b, 1.0))
	return out


func _biome_map() -> Array:
	var m: Array = []
	for s in 6:
		m.append(MainScript.ground_biome(s))
	return m


func test_six_sectors_six_distinct_ground_cards() -> void:
	var map := _biome_map()
	var seen := {}
	for b in map:
		seen[b] = true
	Runner.T.eq(seen.size(), 6, "six sectors map to six distinct biomes %s" % [map])
	var means: Array = []
	for b in map:
		means.append(_mean_rgb(_rendered_strip(b)))
	for i in 5:
		var d: float = (means[i] as Vector3).distance_to(means[i + 1])
		print("    [ground] sector %d -> %d rendered mean colour %s -> %s  distance %.1f" % [
			i, i + 1, (means[i] as Vector3).round(), (means[i + 1] as Vector3).round(), d])
		Runner.T.ok(d >= 12.0, "sector %d and %d ground differ by >= 12/255 in mean colour (%.1f)" % [i, i + 1, d])


func test_every_biome_source_is_a_distinct_registered_card() -> void:
	var keys := {}
	for b in _biome_map():
		var k: String = MainScript.ground_biome_source(b)
		keys[k] = true
		Runner.T.ok(Art.TEX.has(k), "biome %d source '%s' is a registered texture" % [b, k])
	Runner.T.eq(keys.size(), 6, "six sources, no biome shares a card")


func test_new_ground_is_no_louder_than_the_sand_it_replaces() -> void:
	## Actors must pop. Baseline = the campaign sand ramp the late sectors used to
	## wear. A new biome may not be brighter or busier than it.
	var base := _luma_stats(_rendered_strip(0))
	print("    [ground] baseline sand: mean %.1f std %.2f p95 %.1f" % [base["mean"], base["std"], base["p95"]])
	for b in range(2, 7):
		var st := _luma_stats(_rendered_strip(b))
		print("    [ground] biome %d: mean %.1f std %.2f p95 %.1f" % [b, st["mean"], st["std"], st["p95"]])
		Runner.T.ok(st["p95"] <= base["p95"] + 0.5, "biome %d p95 luma %.1f is not above sand's %.1f" % [b, st["p95"], base["p95"]])
		Runner.T.ok(st["std"] <= base["std"] + 0.5, "biome %d luma std %.2f is not busier than sand's %.2f" % [b, st["std"], base["std"]])


func test_biome_seam_is_feathered_over_two_bands() -> void:
	var map := _biome_map()
	var yb := -1000.0
	var covered_px := 0.0
	for i in 12:   # walk the bands around the gate-1 boundary
		var top := -1200.0 + float(i) * 96.0
		var layers := GS.band_layers(true, 1, top, 96.0, map)
		Runner.T.eq(float(layers[0]["a"]), 1.0, "the base layer is opaque")
		for l in layers.slice(1):
			Runner.T.eq(int(l["b"]), int(map[1]), "incoming slices are the NORTH sector's biome")
			Runner.T.ok(float(l["a"]) > 0.0 and float(l["a"]) <= 1.0, "slice alpha in (0,1]")
			covered_px += 12.0
	var prev := -1.0
	var first_a := -1.0
	var last_a := -1.0
	for i in 41:
		var wy := yb + 120.0 - float(i) * 6.0
		var w := GS.feather_weight(wy, yb)
		Runner.T.ok(w >= prev - 1e-6, "feather weight is monotonic northward (%.3f at %.0f)" % [w, wy])
		prev = w
		if i == 0:
			first_a = w
		last_a = w
	Runner.T.eq(first_a, 0.0, "fully outgoing well south of the seam")
	Runner.T.eq(last_a, 1.0, "fully incoming well north of the seam")
	Runner.T.ok(covered_px > 0.0 and covered_px <= 12.0 * 8.0 * 3.0,
		"only the bands around the seam carry slices (%.0f px)" % covered_px)
	var far := GS.band_layers(true, 1, -500.0, 96.0, map)
	Runner.T.eq(far.size(), 1, "mid-sector bands are one plain layer")
	var flat := GS.band_layers(false, 3, -1000.0, 96.0, map)
	Runner.T.eq(flat.size(), 1, "non-campaign worlds never feather")
	Runner.T.eq(int(flat[0]["b"]), 3, "non-campaign worlds keep their uniform biome")


func _fake_world() -> Dictionary:
	var gates: Array = []
	for k in range(1, 4):
		gates.append({"y": -k * 1000 * Fixed.ONE})
	var waters: Array = [{"y": -1500 * Fixed.ONE, "ford_x": 480 * Fixed.ONE}]
	return {"gates": gates, "waters": waters}


func _anchors() -> Array:
	var w := _fake_world()
	return GS.anchors(w["gates"], w["waters"], 80.0, 1.0 / float(Fixed.ONE))


func _plan_for(cam_y: float) -> Dictionary:
	var w := _fake_world()
	var gys: Array = []
	for g in w["gates"]:
		gys.append(float(g["y"]) / float(Fixed.ONE))
	return GS.plan(_anchors(), gys, w["waters"], cam_y, 80.0,
		func(b: int) -> int: return SimWorld.ford_half_w(b))


func test_the_lane_threads_gates_and_fords() -> void:
	var anc := _anchors()
	Runner.T.ok(absf(GS.lane_x(anc, -1000.0) - 320.0) < 0.01, "the lane runs through the centre of gate 1")
	Runner.T.ok(absf(GS.lane_x(anc, -1500.0 + 40.0) - 480.0) < 0.01, "the lane runs through the ford of the river")
	var worst := 0.0
	var y := -2000.0
	while y < 0.0:
		worst = maxf(worst, absf(GS.lane_x(anc, y + 24.0) - GS.lane_x(anc, y)))
		y += 24.0
	print("    [ground] steepest lane slide %.1f px per 24px" % worst)
	Runner.T.ok(worst <= 24.0, "the lane never turns steeper than 45 degrees (%.1f px / 24)" % worst)


func test_the_lane_is_present_in_a_composited_ground_strip() -> void:
	var cam := -1260.0
	var plan := _plan_for(cam)
	var ground: Image = MainScript.ground_biome_strip_image(2, 0)
	var comp := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
	for y in 360:
		for x in 640:
			var g := ground.get_pixel(x % 128, y % 128)
			comp.set_pixel(x, y, Color(g.r * MainScript.GROUND_SHADE, g.g * MainScript.GROUND_SHADE,
				g.b * MainScript.GROUND_SHADE, 1.0))
	var before := comp.duplicate() as Image
	GS.composite(comp, plan)
	var cx := GS.lane_x(_anchors(), cam + 200.0)
	var xc := int(cx) + 1
	var on := comp.get_pixel(xc, 200).get_luminance() * 255.0
	var on_before := before.get_pixel(xc, 200).get_luminance() * 255.0
	var off_x := int(cx) + 200 if cx < 320.0 else int(cx) - 200
	var off := comp.get_pixel(off_x, 200).get_luminance() * 255.0
	var off_before := before.get_pixel(off_x, 200).get_luminance() * 255.0
	print("    [ground] lane centre luma %.1f (was %.1f), off-lane %.1f (was %.1f)" % [on, on_before, off, off_before])
	Runner.T.ok(absf(off - off_before) < 0.01, "pixels well off the lane are untouched")
	Runner.T.ok(absf(on - on_before) >= 6.0, "the lane visibly changes the ground at its centre (%.1f luma)" % absf(on - on_before))
	var d_c := absf(comp.get_pixel(xc, 200).get_luminance() - before.get_pixel(xc, 200).get_luminance())
	var d_e := absf(comp.get_pixel(xc + 22, 200).get_luminance() - before.get_pixel(xc + 22, 200).get_luminance())
	Runner.T.ok(d_c > d_e, "lane tint falls off toward its verge (soft edge, not a wall)")


func test_gate_apron_sits_in_front_of_the_gate_and_stays_flat() -> void:
	var cam := -1100.0   # gate 1 (world -1000) at screen y 100
	var plan := _plan_for(cam)
	Runner.T.eq((plan["aprons"] as Array).size(), 1, "one apron for the visible gate")
	var a: Dictionary = plan["aprons"][0]
	Runner.T.ok(float(a["cy"]) - float(a["ry"]) >= 100.0, "the apron starts at the wall and extends SOUTH, in front of it")
	Runner.T.ok(float(a["cy"]) + float(a["ry"]) <= 100.0 + GS.APRON_DEPTH + 40.0, "the apron is a bounded stretch in front of the gate")
	var worst := 0.0
	for l in plan["lane"]:
		worst = maxf(worst, float(l["a"]))
	for r in plan["aprons"]:
		worst = maxf(worst, (r["color"] as Color).a)
	for k in ["ruts", "seams", "dashes", "planks"]:
		for r in plan[k]:
			worst = maxf(worst, (r["color"] as Color).a)
	Runner.T.ok(worst <= 0.4, "every structure mark is <= 0.4 alpha ground paint, nothing reads as cover (%.2f)" % worst)


func test_ford_banks_get_plank_approaches_only_where_there_is_a_river() -> void:
	var near := _plan_for(-1560.0)
	Runner.T.ok((near["planks"] as Array).size() > 0, "ford-bank planking is planned for a visible river")
	for p in near["planks"]:
		Runner.T.ok(absf(((p["x0"] as float) + (p["x1"] as float)) * 0.5 - 480.0) < 0.5, "planks are centred on the sim's ford x")
		break
	var far := _plan_for(-300.0)
	Runner.T.eq((far["planks"] as Array).size(), 0, "no planking where no river is in frame")


func test_paint_bg_is_wired_to_the_structure_and_the_feather() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("func _paint_bg(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	Runner.T.ok(body.contains("GroundStructure.band_layers("), "_paint_bg paints biome layers through band_layers (the feather)")
	Runner.T.ok(body.contains("_paint_ground_structure("), "_paint_bg paints the lane/apron plan")
	Runner.T.ok(src.contains("GroundStructure.paint(canvas,"), "the hook hands the plan to GroundStructure.paint")
	Runner.T.ok(body.find("_paint_ground_structure(") < body.find("var glt := _ground_light()"),
		"the structure is laid down BEFORE the sky-light grade so it grades as one surface")
