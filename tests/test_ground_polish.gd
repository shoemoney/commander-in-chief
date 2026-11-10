extends RefCounted
## GROUND POLISH — the lane has to look drawn, not ruled; the cards must not be
## blocky; aprons and mud banks must carry texture in their biome's own palette.
##
## Every assertion measures OUTPUT: pixels of composited images, computed rects,
## values the shipped functions return. The calibration fixtures are the two cards
## this package replaced (tests/fixtures, .gdignore'd so Godot does not import them):
## they MUST fail the blockiness gate, or the gate could never have caught anything.

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const GS := preload("res://src/view/ground_structure.gd")

const BLOCKY_MAX := 1.6          # old marsh 3.07 / old slag 3.05; organic cards land 0.7-1.4
const CARDS := ["marsh", "deck", "gravel", "asphalt", "slag"]


func _fake_world() -> Dictionary:
	var gates: Array = []
	for k in range(1, 7):
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


## Lane paint alone, composited over a flat mid-grey: returns per-row [left_x, right_x]
## where the lane's visible footprint (>= 25% of that row's peak change) starts and ends.
func _lane_edges(cam: float) -> Array:
	var comp := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0.5, 0.5, 0.5, 1.0))
	var p := _plan_for(cam)
	var only := {"lane": p["lane"], "ruts": [], "seams": [], "dashes": [], "aprons": [], "planks": [], "details": []}
	GS.composite(comp, only)
	var rows: Array = []
	for y in range(8, 352):
		var peak := 0.0
		var d: Array = []
		for x in 640:
			var v := absf(comp.get_pixel(x, y).get_luminance() - 0.5)
			d.append(v)
			peak = maxf(peak, v)
		if peak < 0.004:
			continue
		var l := -1
		var r := -1
		for x in 640:
			if d[x] >= peak * 0.25:
				if l < 0:
					l = x
				r = x
		rows.append([l, r])
	return rows


func test_the_lane_is_a_wide_wandering_track_not_a_ruler() -> void:
	# cam values land the screen between gates, in different sectors / lane kinds
	for cam in [-560.0, -1260.0, -2480.0, -3480.0, -4560.0]:
		var rows := _lane_edges(cam)
		Runner.T.ok(rows.size() > 300, "lane is present down the whole frame at cam %d (%d rows)" % [cam, rows.size()])
		if rows.size() < 300:
			continue
		var wmin := 9999
		var wmax := 0
		var lmin := 9999
		var lmax := -9999
		var run := 1
		var longest := 1
		for i in rows.size():
			var w: int = rows[i][1] - rows[i][0]
			wmin = mini(wmin, w)
			wmax = maxi(wmax, w)
			lmin = mini(lmin, rows[i][0])
			lmax = maxi(lmax, rows[i][0])
			if i > 0 and rows[i][0] == rows[i - 1][0]:
				run += 1
				longest = maxi(longest, run)
			else:
				run = 1
		print("    [lane] cam %d width %d..%d, left edge x %d..%d, longest identical-edge run %d rows" % [cam, wmin, wmax, lmin, lmax, longest])
		Runner.T.ok(wmin >= 50 and wmax <= 104, "lane is roughly 56-90px wide (%d..%d) at cam %d" % [wmin, wmax, cam])
		Runner.T.ok(wmax - wmin >= 8, "lane width varies along its length (%d px spread) at cam %d" % [wmax - wmin, cam])
		Runner.T.ok(lmax - lmin >= 10, "left edge x wanders (%d px range) instead of a constant x at cam %d" % [lmax - lmin, cam])
		Runner.T.ok(longest <= 16, "no run of identical edge pixels longer than 16 rows (%d) at cam %d (old lane: 100-344)" % [longest, cam])
		# a smooth wobble can sit on a local extremum for a few rows, but no 40-row stretch may be a ruled line
		var flattest := 9999
		for i in range(0, rows.size() - 40, 8):
			var lo := 9999
			var hi := -9999
			for j in range(i, i + 40):
				lo = mini(lo, rows[j][0])
				hi = maxi(hi, rows[j][0])
			flattest = mini(flattest, hi - lo)
		Runner.T.ok(flattest >= 3, "every 40-row stretch of the edge moves at least 3px (flattest %d) at cam %d" % [flattest, cam])


func test_the_lane_bends_between_gates_but_still_threads_them() -> void:
	var anc := _anchors()
	var far := 0.0
	var y := -950.0
	while y < -50.0:
		far = maxf(far, absf(GS.lane_x(anc, y) - 320.0))
		y += 10.0
	print("    [lane] largest drift off the gate axis between gates 0 and 1: %.1f px" % far)
	Runner.T.ok(far >= 20.0, "the lane drifts at least 20px off-axis between gates (%.1f)" % far)
	Runner.T.ok(absf(GS.lane_x(anc, -1000.0) - 320.0) < 0.01, "and is back on the gate centre at gate 1")
	Runner.T.ok(absf(GS.lane_x(anc, -1460.0) - 480.0) < 0.01, "and on the ford centre at the river")


func test_ruts_are_broken_uneven_dashes() -> void:
	var p := _plan_for(-1260.0)
	var ruts: Array = p["ruts"]
	Runner.T.ok(ruts.size() >= 10, "ruts exist as many short dashes (%d)" % ruts.size())
	var lens := {}
	var covered := 0.0
	for r in ruts:
		var ln := absf(float(r["y1"]) - float(r["y0"]))
		lens[int(ln)] = true
		covered += ln
	print("    [lane] %d rut dashes, %d distinct lengths, %.0f px covered of 720" % [ruts.size(), lens.size(), covered])
	Runner.T.ok(lens.size() >= 4, "dash lengths are uneven (%d distinct)" % lens.size())
	Runner.T.ok(covered < 720.0 * 0.85, "the ruts have real gaps (%.0f of 720px covered)" % covered)


# --- cards ------------------------------------------------------------------

func _luma_grid(img: Image) -> Array:
	var n := img.get_width()
	var g: Array = []
	for y in n:
		var row := PackedFloat32Array()
		row.resize(n)
		for x in n:
			var c := img.get_pixel(x, y)
			row[x] = (c.r + c.g + c.b) / 3.0 * 255.0
		g.append(row)
	return g


## Mean spectral power on the kx/ky AXES over the DIAGONALS across periods ~5-32px.
## Same definition as tools/gen_ground.py::axis_blockiness. ~1 = isotropic organic.
func axis_blockiness(img: Image, lo: int = 4, hi: int = 28) -> float:
	var n := img.get_width()
	var v := _luma_grid(img)
	var colsum := PackedFloat64Array()
	var rowsum := PackedFloat64Array()
	var dsum := PackedFloat64Array()
	var asum := PackedFloat64Array()
	for a in [colsum, rowsum, dsum, asum]:
		a.resize(n)
	for y in n:
		var row: PackedFloat32Array = v[y]
		for x in n:
			var s := row[x]
			colsum[x] += s
			rowsum[y] += s
			dsum[(x + y) % n] += s
			asum[posmod(x - y, n)] += s
	var ax := 0.0
	var na := 0
	for k in range(lo, hi):
		ax += _bin_power(colsum, k) + _bin_power(rowsum, k)
		na += 2
	var dg := 0.0
	var nd := 0
	for j in range(int(lo / 1.414) + 1, int(hi / 1.414)):
		dg += _bin_power(dsum, j) + _bin_power(asum, j)
		nd += 2
	return (ax / float(na)) / (dg / float(nd))


func _bin_power(s: PackedFloat64Array, k: int) -> float:
	var n := s.size()
	var re := 0.0
	var im := 0.0
	for i in n:
		var a := TAU * float(k) * float(i) / float(n)
		re += s[i] * cos(a)
		im -= s[i] * sin(a)
	return re * re + im * im


func _load_card(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func test_blockiness_gate_fails_the_cards_it_replaced() -> void:
	for f in ["res://tests/fixtures/ground_marsh_blocky_v1.png", "res://tests/fixtures/ground_slag_blocky_v1.png"]:
		var b := axis_blockiness(_load_card(f))
		print("    [card] OLD %s blockiness %.2f" % [f.get_file(), b])
		Runner.T.ok(b > BLOCKY_MAX, "the gate rejects the old blocky card %s (%.2f > %.1f)" % [f.get_file(), b, BLOCKY_MAX])


func test_every_shipped_ground_card_is_organic_not_blocky() -> void:
	for n in CARDS:
		var img := _load_card("res://assets/art/ground/ground_%s.png" % n)
		var b := axis_blockiness(img)
		print("    [card] %s blockiness %.2f" % [n, b])
		Runner.T.ok(b <= BLOCKY_MAX, "ground_%s is not axis-blocky (%.2f <= %.1f)" % [n, b, BLOCKY_MAX])


# --- aprons, mud banks, decor, contrast ------------------------------------------

func _hsv(c: Color) -> Vector3:
	return Vector3(c.h, c.s, c.v)


func _luma_std(img: Image, rect: Rect2i) -> float:
	var vals: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			vals.append(img.get_pixel(x, y).get_luminance() * 255.0)
	var m := 0.0
	for v in vals:
		m += v
	m /= float(vals.size())
	var s := 0.0
	for v in vals:
		s += (v - m) * (v - m)
	return sqrt(s / float(vals.size()))


func _mean_color(img: Image, rect: Rect2i) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1.0
	return Color(r / n, g / n, b / n, 1.0)


func test_mud_banks_are_textured_and_earthy_not_flat_orange() -> void:
	# the OLD bank: one flat Color(0.42, 0.32, 0.20, 0.92) rect. Measure it the same way.
	var old_col := Color(0.42, 0.32, 0.20, 1.0)
	print("    [bank] OLD flat bank saturation %.2f, luma std 0.00" % old_col.s)
	for biome in range(1, 7):
		var p := GS.mud_bank_plan(biome, 7, Vector2(640.0, 40.0), 0.0)
		var img := Image.create_empty(640, 40, false, Image.FORMAT_RGBA8)
		var base: Color = p["base"]
		img.fill(Color(base.r, base.g, base.b, 1.0))
		GS.composite_blobs(img, p["blobs"], Vector2.ZERO)
		var sd := _luma_std(img, Rect2i(0, 6, 640, 28))
		var mean := _mean_color(img, Rect2i(0, 6, 640, 28))
		var card := MainScript.ground_biome_strip_image(biome, 0) if biome >= 1 else null
		var card_mean := _mean_color(card, Rect2i(0, 0, 128, 128))
		print("    [bank] biome %d luma std %.1f, mean sat %.2f hue %.2f (card hue %.2f sat %.2f)" % [biome, sd, mean.s, mean.h, card_mean.h, card_mean.s])
		Runner.T.ok(sd >= 3.0, "biome %d mud bank carries texture (luma std %.1f >= 3.0)" % [biome, sd])
		Runner.T.ok(mean.s <= 0.36, "biome %d mud bank is not a saturated slab (sat %.2f <= 0.36; old flat was %.2f)" % [biome, mean.s, old_col.s])
		var dh := absf(mean.h - card_mean.h)
		dh = minf(dh, 1.0 - dh)
		Runner.T.ok(dh <= 0.14 or mean.s < 0.12 or card_mean.s < 0.12,
			"biome %d mud bank stays in its card's hue family (dh %.2f)" % [biome, dh])
		# a blob never pokes more than 3px past the bank's rect (the half-speed edge must read honestly)
		var worst := 0.0
		for b in p["blobs"]:
			worst = maxf(worst, maxf(float(b["h"]) * 0.5 - float(b["y"]), float(b["y"]) + float(b["h"]) * 0.5 - 40.0))
		Runner.T.ok(worst <= 3.01, "biome %d mud blobs overhang the bank by <= 3px (%.1f)" % [biome, worst])


func test_gate_apron_is_soft_textured_biome_ground() -> void:
	for cam in [-1100.0, -2100.0, -3100.0, -5100.0]:
		var p := _plan_for(cam)
		Runner.T.eq((p["aprons"] as Array).size(), 1, "one apron at cam %d" % cam)
		var a: Dictionary = p["aprons"][0]
		var blobs: Array = a["blobs"]
		var worst_a := 0.0
		for b in blobs:
			worst_a = maxf(worst_a, (b["color"] as Color).a)
		Runner.T.ok(blobs.size() >= 20, "apron is many overlapping blobs, not one fill (%d)" % blobs.size())
		Runner.T.ok(worst_a <= 0.4, "every apron blob is faint ground paint (%.2f)" % worst_a)
		var img := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
		var ground := Color(0.42, 0.40, 0.36, 1.0)
		img.fill(ground)
		var gy := int(a["cy"] - a["ry"])
		GS.composite_blobs(img, blobs, Vector2.ZERO)
		var rect := Rect2i(160, clampi(gy + 8, 0, 300), 320, 56)
		var sd := _luma_std(img, rect)
		var mean := _mean_color(img, rect)
		print("    [apron] cam %d luma std %.1f, mean %s" % [cam, sd, mean])
		Runner.T.ok(sd >= 2.0, "apron region has texture (luma std %.1f >= 2.0) at cam %d" % [sd, cam])
		# stays neutral-earthy over a neutral ground: no flat saturated orange
		Runner.T.ok(mean.s <= 0.30, "apron keeps the ground's hue family, no orange slab (sat %.2f) at cam %d" % [mean.s, cam])


func test_ford_planks_are_broken_boards_in_the_biome_palette() -> void:
	var p := _plan_for(-1560.0)
	var planks: Array = p["planks"]
	var lens := {}
	var worst_a := 0.0
	var max_sat := 0.0
	for q in planks:
		lens[int(float(q["x1"]) - float(q["x0"]))] = true
		worst_a = maxf(worst_a, (q["color"] as Color).a)
		max_sat = maxf(max_sat, (q["color"] as Color).s)
	print("    [planks] %d boards, %d distinct lengths, max sat %.2f" % [planks.size(), lens.size(), max_sat])
	Runner.T.ok(lens.size() >= 6, "boards have uneven lengths (%d distinct), not one ruled bar" % lens.size())
	Runner.T.ok(worst_a <= 0.4, "planking stays faint paint (%.2f)" % worst_a)
	Runner.T.ok(max_sat <= 0.36, "plank colours stay desaturated earth (%.2f)" % max_sat)


func test_lane_and_apron_never_pull_the_ground_toward_actor_luma() -> void:
	# Actors pop because the ground is dim and quiet. The structure may texture it, never lift it.
	for biome_sector in [[2, 1], [3, 2], [4, 3], [5, 4], [6, 5]]:
		var biome: int = biome_sector[0]
		var cam := -1000.0 * float(biome_sector[1]) - 600.0
		var ground: Image = MainScript.ground_biome_strip_image(biome, 0)
		var comp := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
		for y in 360:
			for x in 640:
				var g := ground.get_pixel(x % 128, y % 128)
				comp.set_pixel(x, y, Color(g.r * MainScript.GROUND_SHADE, g.g * MainScript.GROUND_SHADE, g.b * MainScript.GROUND_SHADE, 1.0))
		var before := comp.duplicate() as Image
		GS.composite(comp, _plan_for(cam))
		var mb := _mean_color(before, Rect2i(0, 0, 640, 360)).get_luminance() * 255.0
		var ma := _mean_color(comp, Rect2i(0, 0, 640, 360)).get_luminance() * 255.0
		var hi := 0.0
		for y in range(0, 360, 3):
			for x in range(0, 640, 3):
				hi = maxf(hi, comp.get_pixel(x, y).get_luminance() - before.get_pixel(x, y).get_luminance())
		print("    [contrast] biome %d mean luma %.1f -> %.1f, brightest local lift %.1f" % [biome, mb, ma, hi * 255.0])
		Runner.T.ok(absf(ma - mb) <= 8.0, "biome %d: whole-frame mean luma moves <= 8 (%.1f)" % [biome, ma - mb])
		Runner.T.ok(hi * 255.0 <= 34.0, "biome %d: no pixel is lifted more than 34 luma by the structure (%.1f)" % [biome, hi * 255.0])


func test_decor_follows_the_biome_and_is_wired_into_the_cactus_grid() -> void:
	var G := preload("res://src/view/ground_decor.gd")
	Runner.T.ok(not G.replaces_cactus(0) and not G.replaces_cactus(1), "sand and jungle keep their cacti / scrub")
	Runner.T.eq(G.family(2), "reeds", "the marsh gets reeds")
	Runner.T.eq(G.family(3), "rubble", "the bridge deck gets rubble and rebar")
	Runner.T.eq(G.family(4), "scrap", "the foundry works get scrap")
	Runner.T.eq(G.family(6), "scrap", "the foundry core gets scrap")
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("GroundDecor.replaces_cactus(")
	Runner.T.ok(at > 0, "the cactus grid asks GroundDecor before it plants a cactus")
	var tail := src.substr(at, 260)
	Runner.T.ok(tail.contains("GroundDecor.paint(") and tail.contains("continue"), "and then skips the cactus for that cell")
