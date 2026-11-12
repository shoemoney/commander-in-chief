extends RefCounted
## GROUND POLISH - the tone field, the per-biome micro-detail stamps and the worn track's edge.
##
## Measures output: atlas / tone pixels, the stamp plan a frame would draw, the real
## GroundStructure.plan records, and (for wiring) the real src/main.gd source of _draw_terrain.

const Runner := preload("res://tests/run_tests.gd")
const GP := preload("res://src/view/ground_polish.gd")
const GS := preload("res://src/view/ground_structure.gd")


func _plan(cam_y: float, biome: int, water: Callable = Callable(), anc: Array = []) -> Array:
	var w: Callable = water if water.is_valid() else func(_x: float, _y: float) -> bool: return false
	return GP.plan(cam_y, func(_wy: float) -> int: return biome, w, anc)


func _kind_count(stamps: Array, kind: int) -> int:
	var n := 0
	for s in stamps:
		if int(s[1]) == kind:
			n += 1
	return n


func test_atlas_has_every_kind_and_variant() -> void:
	var img := GP.atlas_image()
	Runner.T.eq(img.get_width(), GP.STAMP * GP.VARIANTS, "atlas width")
	var sigs := {}
	for k in 4:
		for v in GP.VARIANTS:
			var n := 0
			var sig := ""
			for y in GP.STAMP:
				for x in GP.STAMP:
					var c := img.get_pixel(v * GP.STAMP + x, k * GP.STAMP + y)
					if c.a > 0.0:
						n += 1
						sig += "%d,%d;" % [x, y]
			Runner.T.ok(n >= 2, "kind %d variant %d has painted pixels (%d)" % [k, v, n])
			sigs["%d_%s" % [k, sig]] = true
	Runner.T.ok(sigs.size() >= 14, "stamps are individually distinct (%d unique of 16)" % sigs.size())


func test_tone_field_wraps_and_stays_quiet() -> void:
	var img := GP.tone_image()
	var n := img.get_width()
	var wrap := 0.0
	var inner := 0.0
	var light := 0
	var dark := 0
	var amax := 0.0
	for y in range(0, n, 4):
		wrap += absf(img.get_pixel(0, y).a * (1.0 if img.get_pixel(0, y).r > 0.5 else -1.0) \
			- img.get_pixel(n - 1, y).a * (1.0 if img.get_pixel(n - 1, y).r > 0.5 else -1.0))
		inner += absf(img.get_pixel(100, y).a - img.get_pixel(101, y).a)
	for y in range(0, n, 8):
		for x in range(0, n, 8):
			var c := img.get_pixel(x, y)
			amax = maxf(amax, c.a)
			if c.a > 0.2:
				if c.r > 0.5:
					light += 1
				else:
					dark += 1
	Runner.T.ok(wrap <= inner * 3.0 + 0.5, "tone tile wraps without a seam (wrap %.3f vs interior %.3f)" % [wrap, inner])
	Runner.T.ok(light > 20 and dark > 20, "the field has both lit and shaded plateaus (%d/%d)" % [light, dark])
	Runner.T.ok(amax * GP.TONE_ALPHA <= 0.35, "the tone field is a whisper (peak %.2f)" % (amax * GP.TONE_ALPHA))


func test_plan_is_deterministic_and_world_anchored() -> void:
	var a := _plan(1234.0, 1)
	var b := _plan(1234.0, 1)
	Runner.T.eq(a.size(), b.size(), "same camera, same stamps")
	Runner.T.ok(a.size() > 60 and a.size() < 320, "a calm frame budget (%d stamps)" % a.size())
	# Scroll by exactly one grid pitch: every stamp must reappear exactly one pitch higher.
	var c := _plan(1234.0 + GP.CELL_PX, 1)
	var seen := {}
	for s in c:
		seen[s[0]] = int(s[1])
	var matched := 0
	for s in a:
		var moved: Vector2 = (s[0] as Vector2) - Vector2(0.0, GP.CELL_PX)
		if seen.has(moved) and seen[moved] == int(s[1]):
			matched += 1
	Runner.T.ok(matched >= a.size() - 2 * GP.COLS, "stamps ride the world, not the screen (%d of %d)" % [matched, a.size()])


func test_biomes_wear_their_own_detail() -> void:
	var jungle := _plan(500.0, 1)
	var deck := _plan(500.0, 3)
	var gravel := _plan(500.0, 4)
	Runner.T.ok(_kind_count(jungle, GP.Kind.TUFT) > 20, "jungle grows grass tufts")
	Runner.T.eq(_kind_count(deck, GP.Kind.TUFT), 0, "a concrete deck grows none")
	Runner.T.ok(_kind_count(deck, GP.Kind.CRACK) > 8, "the deck is cracked")
	Runner.T.ok(_kind_count(gravel, GP.Kind.PEBBLE) > _kind_count(jungle, GP.Kind.PEBBLE), "gravel is pebble-heavy")


func test_water_and_track_are_respected() -> void:
	var dry := _plan(0.0, 1)
	var wet := _plan(0.0, 1, func(sx: float, _sy: float) -> bool: return sx < 320.0)
	Runner.T.ok(wet.size() < dry.size(), "stamps are culled over water")
	for s in wet:
		Runner.T.ok((s[0] as Vector2).x >= 320.0 - 1.0, "no stamp left in the water half")
	var anc := [Vector2(320.0, 0.0)]
	var lane := _plan(0.0, 1, Callable(), anc)
	var on_track_tufts := 0
	for s in lane:
		var p: Vector2 = s[0]
		if int(s[1]) == int(GP.Kind.TUFT) and absf(p.x - 320.0) < 22.0:
			on_track_tufts += 1
	Runner.T.eq(on_track_tufts, 0, "grass never sprouts in the middle of the worn track")


func test_ground_stays_quieter_than_actors() -> void:
	for b in range(1, 7):
		for c in GP.palette(b):
			Runner.T.ok((c as Color).a <= GP.STAMP_ALPHA_CAP, "biome %d stamp alpha %.2f stays under the cap" % [b, (c as Color).a])
		Runner.T.ok(GP.tone_tint(b).a <= 0.5, "biome %d tone is faint" % b)


func test_track_has_a_defined_edge() -> void:
	var p := GS.plan([Vector2(320.0, 0.0)], [], [], 0.0, 160.0, func(_b: int) -> int: return 0)
	Runner.T.eq((p["edges"] as Array).size(), 4, "two sides x (rim + lip)")
	for e in p["edges"]:
		Runner.T.ok((e["pts"] as PackedVector2Array).size() >= 50, "an edge runs the full view height")
		for c in (e["cols"] as PackedColorArray):
			Runner.T.ok(c.a <= 0.3, "edge paint stays flat ground paint (alpha %.2f)" % c.a)
	var left: PackedVector2Array = p["edges"][0]["pts"]
	var right: PackedVector2Array = p["edges"][2]["pts"]
	Runner.T.ok(right[10].x - left[10].x > 60.0, "the two rims bound a real track width")


func test_main_ground_layer_actually_calls_the_polish() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var a := src.find("func _paint_ground_polish(")
	var b := src.find("\n## The lane / gate aprons", a)
	Runner.T.ok(a > 0 and b > a, "found _paint_ground_polish")
	var body := src.substr(a, b - a)
	Runner.T.ok(body.contains("GroundPolish.build_layer(") and body.contains("GroundPolish.paint_layer("), "the cached ground layer plans and paints the polish")
	Runner.T.ok(body.contains("layer_cached(") and body.contains("_in_wbands"), "rebuilds only on a miss, culled by the water snapshot")
	var pb := src.find("func _paint_bg(")
	var pe := src.find("\n## The lane / gate aprons", pb)
	Runner.T.ok(src.substr(pb, pe - pb).contains("_paint_ground_polish(canvas, cam_y)"), "_paint_bg (the cached layer, under the water) paints it")
	var dt := src.find("func _draw_terrain()")
	var de := src.find("\nfunc _in_wbands(", dt)
	Runner.T.ok(not src.substr(dt, de - dt).contains("GroundPolish."), "_draw_terrain no longer rebuilds it every frame")
	var gs := FileAccess.get_file_as_string("res://src/view/ground_structure.gd")
	Runner.T.ok(gs.contains("draw_polyline_colors(e[\"pts\"]"), "paint() draws the track edge")


func test_layer_is_not_rebuilt_when_the_camera_has_not_moved() -> void:
	var biome := func(_wy: float) -> int: return 1
	var dry := func(_sx: float, _wy: float) -> bool: return false
	var anc := [Vector2(320.0, 0.0)]
	var key := [1, 0, 0, 1, true]
	GP._layer.clear()
	var n0: int = GP.plan_builds
	Runner.T.ok(not GP.layer_cached(1000.0, key), "empty cache misses")
	GP.build_layer(1000.0, key, biome, dry, anc, [])
	Runner.T.eq(GP.plan_builds, n0 + 1, "first call builds")
	Runner.T.ok(GP.layer_cached(1000.0, key), "same camera hits")
	Runner.T.ok(GP.layer_cached(1000.0 + 5.0, key), "a sub-row scroll still hits (rows are 26px)")
	Runner.T.ok(not GP.layer_cached(1000.0 + GP.CELL_PX, key), "a new camera row misses")
	Runner.T.ok(not GP.layer_cached(1000.0, [2, 0, 0, 1, true]), "a changed world (key) misses")
	GP._layer.clear()


func test_track_and_stamps_break_across_the_whole_river_band() -> void:
	var biome := func(_wy: float) -> int: return 1
	var dry := func(_sx: float, _wy: float) -> bool: return false   # the sim water test calls the ford column dry
	var anc := [Vector2(320.0, -2000.0), Vector2(320.0, 2000.0)]
	var band := [1100.0, 1180.0]
	GP.build_layer(1000.0, [9], biome, dry, anc, [band])
	var runs: Array = GP._layer["runs"]
	Runner.T.ok(runs.size() >= 2, "the track is cut in two by the band (%d runs)" % runs.size())
	for sg in runs:
		for v in (sg[0] as PackedVector2Array):
			Runner.T.ok(v.y < band[0] or v.y > band[1], "no track row inside the band (y %.0f)" % v.y)
	for s in GP._layer["stamps"]:
		var py: float = (s[0] as Vector2).y
		Runner.T.ok(py < band[0] or py > band[1], "no stamp inside the band")
	GP._layer.clear()


func test_track_edge_reads_as_worn_ground_not_a_wall() -> void:
	Runner.T.ok(GP.TRACK_RIM_A <= 0.4 and GP.TRACK_LIP_A <= 0.4, "edge alpha stays under 0.4")
	Runner.T.ok(GP.TRACK_RIM_W <= 2.0, "edge is at most 2px")
	for b in range(1, 7):
		var c := GP.track_colors(b)
		Runner.T.ok((c[0] as Color).a <= 0.4 and (c[1] as Color).a <= 0.4 and (c[3] as Color).a <= 0.4, "biome %d track edge/ruts are quiet" % b)


func test_dressing_patches_are_earthy_not_grey_smudges() -> void:
	for wet in [false, true]:
		var img: Image = GP.patch_image(wet)
		Runner.T.eq(img.get_size(), Vector2i(256, 256), "patch atlas is a 2x2 grid of 128px cells")
		var r := 0.0
		var b := 0.0
		var n := 0
		for y in 256:
			for x in 256:
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					r += c.r
					b += c.b
					n += 1
		Runner.T.ok(n > 4000, "patches carry real ink (wet=%s)" % wet)
		Runner.T.ok(r / n > b / n + 0.2, "patches are warm earth, not neutral grey (wet=%s)" % wet)
		Runner.T.eq(img.get_pixel(0, 0).a, 0.0, "cell corners stay clear")
	var cache: Array = []
	GP._patches_installed = false
	GP.install_patches(cache)
	Runner.T.eq(cache.size(), 2, "install_patches fills the desert and jungle slots")
	GP._patches_installed = false


# --- the world-space structure cache (renderer path) -----------------------------------------------

const _F := 65536


func _world_inputs(ford_x: int = 480) -> Dictionary:
	var gates: Array = []
	for k in range(1, 7):
		gates.append({"y": -k * 1000 * _F})
	var ws: Array = [{"y": -1500 * _F, "ford_x": ford_x * _F}]
	var gys: Array = []
	for g in gates:
		gys.append(float(g["y"]) / float(_F))
	return {"gates": gates, "waters": ws, "gys": gys,
		"anc": GS.anchors(gates, ws, 80.0, 1.0 / float(_F))}


func _wplan(w: Dictionary, cam_y: float) -> Dictionary:
	return GS.world_plan(w["anc"], w["gys"], w["waters"], cam_y, 80.0,
		func(b: int) -> int: return SimWorld.ford_half_w(b))


func _splan(w: Dictionary, cam_y: float) -> Dictionary:
	return GS.plan(w["anc"], w["gys"], w["waters"], cam_y, 80.0,
		func(b: int) -> int: return SimWorld.ford_half_w(b))


func _lane_tris(p: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for blk in p["blocks"]:
		out.append_array(blk["tp"])
	return out


func test_world_plan_is_the_screen_plan_shifted_by_the_camera() -> void:
	GS.cache_enabled = true
	GS.reset_cache()
	var w := _world_inputs()
	for cam_y in [-100.0, -1337.4, -1500.0, -1555.25, -3001.0]:
		var wp := _wplan(w, cam_y)
		var sp := _splan(w, cam_y)
		var ra: Array = wp["ruts"]
		var rb: Array = sp["ruts"]
		Runner.T.eq(ra.size(), rb.size(), "ruts: same record count at cam %.2f" % cam_y)
		for i in mini(ra.size(), rb.size()):
			Runner.T.ok(absf(float(ra[i]["y0"]) - cam_y - float(rb[i]["y0"])) < 1e-6
				and absf(float(ra[i]["x0"]) - float(rb[i]["x0"])) < 1e-6, "rut %d is the screen record shifted" % i)
		var da: Array = wp["dashes"]
		var db: Array = sp["dashes"]
		Runner.T.eq(da.size(), db.size(), "dashes: same count at cam %.2f" % cam_y)
		var wd: Array = wp["details"]
		var sd: Array = sp["details"]
		Runner.T.eq(wd.size(), sd.size(), "details: same blob count at cam %.2f" % cam_y)
		for i in mini(wd.size(), sd.size()):
			Runner.T.ok(absf(float(wd[i]["y"]) - cam_y - float(sd[i]["y"])) < 1e-6 and wd[i]["color"] == sd[i]["color"],
				"detail %d matches" % i)
		Runner.T.eq((wp["seams"] as Array).size(), (sp["seams"] as Array).size(), "seams: same count at cam %.2f" % cam_y)
		Runner.T.eq((wp["planks"] as Array).size(), (sp["planks"] as Array).size(), "planks: same count at cam %.2f" % cam_y)
		Runner.T.eq((wp["aprons"] as Array).size(), (sp["aprons"] as Array).size(), "aprons: same count at cam %.2f" % cam_y)
		# the lane: the cached blocks carry the screen plan's triangles, vertex for vertex (world px)
		var want := PackedVector2Array()
		var rows: Array = sp["lane"]
		for i in rows.size() - 1:
			var r: Dictionary = rows[i]
			if not r.has("tp"):
				GS._attach_tris(r, rows[i + 1])
			want.append_array(r["tp"])
		var got := _lane_tris(wp)
		Runner.T.ok(want.size() > 0 and got.size() >= want.size(), "the blocks cover the viewport lane at cam %.2f" % cam_y)
		var run := false
		for at in got.size() - want.size() + 1:
			if got[at] == want[0] and got.slice(at, at + want.size()) == want:
				run = true
				break
		Runner.T.ok(run, "the viewport's triangles are a contiguous run of the blocks")
		var edges: Array = sp["edges"]
		for e in 4:
			var ep := PackedVector2Array()
			var ec := PackedColorArray()
			for blk in wp["blocks"]:
				ep.append_array((blk["ep"] as Array)[e])
				ec.append_array((blk["ec"] as Array)[e])
			var spts: PackedVector2Array = edges[e]["pts"]
			var scol: PackedColorArray = edges[e]["cols"]
			var first := Vector2(spts[0].x, spts[0].y + cam_y)
			var j := -1
			for q in ep.size():
				if absf(ep[q].x - first.x) < 1e-4 and absf(ep[q].y - first.y) < 1e-4:
					j = q
					break
			var same := j >= 0 and j + spts.size() <= ep.size()
			if same:
				for q in spts.size():
					if absf(ep[j + q].x - spts[q].x) > 1e-4 or absf(ep[j + q].y - cam_y - spts[q].y) > 1e-4 or ec[j + q] != scol[q]:
						same = false
						break
			Runner.T.ok(same, "edge line %d is the screen plan's polyline in world px" % e)
	GS.reset_cache()


func test_world_cache_builds_once_then_scrolls_free() -> void:
	GS.cache_enabled = true
	GS.reset_cache()
	var w := _world_inputs()
	_wplan(w, -1600.0)
	var b0 := GS.blocks_built
	var c0 := GS.cells_built
	Runner.T.ok(b0 >= 3 and c0 > 10, "a cold frame builds blocks (%d) and cells (%d)" % [b0, c0])
	_wplan(w, -1600.0)
	_wplan(w, -1601.5)
	Runner.T.eq(GS.blocks_built, b0, "a re-draw and a sub-block scroll build no block")
	Runner.T.ok(GS.cells_built - c0 <= 2, "a 1.5px scroll builds at most the one new dressing cell")
	_wplan(w, -1600.0 - GS.BLOCK_PX * 3.0)
	Runner.T.ok(GS.blocks_built > b0, "a scroll into new world builds the new blocks")
	GS.reset_cache()


func test_world_cache_drops_on_a_changed_world_and_a_reset() -> void:
	GS.cache_enabled = true
	GS.reset_cache()
	var a := _world_inputs(480)
	var b := _world_inputs(150)
	var tri_a := _lane_tris(_wplan(a, -1500.0))
	# same gate/water COUNTS, different ford: the cache must not serve world A's ground
	var tri_b := _lane_tris(_wplan(b, -1500.0))
	Runner.T.ok(tri_a != tri_b, "a re-laid world (same counts, other ford x) gets its own lane")
	GS.cache_enabled = false
	var tri_f := _lane_tris(_wplan(b, -1500.0))
	GS.cache_enabled = true
	Runner.T.ok(tri_b == tri_f, "the cached lane equals a cold, uncached build of the same world")
	GS.reset_cache()
	var b1 := GS.blocks_built
	_wplan(b, -1500.0)
	Runner.T.ok(GS.blocks_built > b1, "reset_cache() forces a rebuild (the restart path)")
	var ca := GS.cached_anchors(a["gates"], a["waters"], 80.0, 1.0 / float(_F))
	var cb := GS.cached_anchors(b["gates"], b["waters"], 80.0, 1.0 / float(_F))
	Runner.T.ok(ca != cb, "cached_anchors keys on positions, not just counts")
	Runner.T.eq(cb, b["anc"], "cached_anchors equals a fresh anchors() call")
	GS.reset_cache()


func test_main_paints_the_structure_through_the_world_cache() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("func _paint_ground_structure(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	Runner.T.ok(body.contains("GroundStructure.world_plan(") and body.contains("GroundStructure.cached_anchors("),
		"the ground layer paints the cached world plan and memoised anchors")
	Runner.T.ok(not body.contains("GroundStructure.plan("), "and no longer rebuilds the screen plan every scroll frame")
