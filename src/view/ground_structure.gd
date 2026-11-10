class_name GroundStructure
extends RefCounted
## VIEW-ONLY ground structure: sector biome lookup by WORLD y, feathered biome
## seams, a worn lane running north, gate aprons, ford-bank planking.
##
## Everything here is a pure function of (sim geometry, camera). It reads the
## sim's gates / waters READ-ONLY and never feeds SimWorld.checksum().
##
## HONESTY RULE: every mark is FLAT ground paint at low alpha (the lane is a
## tent-profile tint, ruts are 2px lines, planks are 1px seams). Nothing here has
## an edge, a height or a shadow that could read as cover or a wall, and it is
## painted onto the ground layer, so mines, telegraphs, pickups and actors all draw
## on top of it.

const GATE_SPACING_PX := 1000.0       # SimWorld.GATE_SPACING / F_ONE
const SECTORS := 6
const FEATHER_HALF_PX := 96.0         # blend zone = 192px = two 96px ground bands
const FEATHER_SLICES := 8             # 12px slices per 96px band
const LANE_SEG_PX := 24.0
const LANE_HALF_W := 28.0
const RUT_OFFSET := 10.0
const APRON_DEPTH := 112.0
const FORD_PLANK_DEPTH := 20.0

enum LaneKind { DIRT, MUD, PLANK, GRAVEL, ROAD, SLAG }


## 0-based sector of a world y (px). Gate k stands at y = -k * GATE_SPACING and ends
## sector k-1, so the sector is floor(-y / spacing), clamped to the six zones.
static func sector_for_y(wy: float) -> int:
	if wy >= 0.0:
		return 0
	return clampi(int(floor(-wy / GATE_SPACING_PX)), 0, SECTORS - 1)


## Biome of a world y. `campaign` false (endless / boss rush) keeps the old uniform
## per-run biome; `biome_map` is [ground_biome(0) .. ground_biome(5)].
static func biome_at(campaign: bool, fallback: int, wy: float, biome_map: Array) -> int:
	if not campaign:
		return fallback
	return int(biome_map[sector_for_y(wy)])


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Weight (0..1) of the INCOMING (northern) biome at world y `wy` around a boundary
## at `boundary_y`. 0 south of the zone, 1 north of it, smooth between.
static func feather_weight(wy: float, boundary_y: float) -> float:
	return _smooth((boundary_y + FEATHER_HALF_PX - wy) / (2.0 * FEATHER_HALF_PX))


## Draw layers for ONE 96px ground band whose top is at world y `wy_top`: an Array of
## {b: biome, a: alpha, r0, r1: source rows 0..128}. First layer is always the whole
## band, opaque; later layers are the incoming biome's slices over a boundary.
static func band_layers(campaign: bool, fallback: int, wy_top: float, pitch: float,
		biome_map: Array) -> Array:
	var center := wy_top + pitch * 0.5
	if not campaign:
		return [{"b": fallback, "a": 1.0, "r0": 0, "r1": 128}]
	var k := int(round(-center / GATE_SPACING_PX))
	var yb := -float(k) * GATE_SPACING_PX
	if k < 1 or k > SECTORS - 1 or absf(center - yb) > FEATHER_HALF_PX + pitch * 0.5:
		return [{"b": int(biome_map[sector_for_y(center)]), "a": 1.0, "r0": 0, "r1": 128}]
	var out: Array = [{"b": int(biome_map[k - 1]), "a": 1.0, "r0": 0, "r1": 128}]
	var rows := 128 / FEATHER_SLICES
	var slice_px := pitch / float(FEATHER_SLICES)
	for s in FEATHER_SLICES:
		var sy := wy_top + (float(s) + 0.5) * slice_px
		var t := feather_weight(sy, yb)
		if t > 0.01:
			out.append({"b": int(biome_map[k]), "a": t, "r0": s * rows, "r1": (s + 1) * rows})
	return out


## Multiplier for the bare-earth dressing patches on a biome's rows: a neutral grey
## leaned toward the card's own hue, so the patches read as worn ground of THAT biome
## and not as the warm desert-ramp orange the old dressing used everywhere.
static func dressing_tint(biome: int) -> Color:
	match biome:
		2: return Color(0.78, 0.84, 0.66)
		3: return Color(0.86, 0.86, 0.84)
		4: return Color(0.92, 0.86, 0.76)
		5: return Color(0.74, 0.74, 0.80)
		6: return Color(0.90, 0.70, 0.64)
		_: return Color.WHITE


static func lane_kind(sector: int) -> int:
	return [LaneKind.DIRT, LaneKind.MUD, LaneKind.PLANK, LaneKind.GRAVEL,
		LaneKind.ROAD, LaneKind.SLAG][clampi(sector, 0, SECTORS - 1)]


## [colour, alpha] of a lane kind's tent fill.
static func lane_tint(kind: int) -> Array:
	match kind:
		LaneKind.DIRT: return [Color(0.55, 0.47, 0.30), 0.28]
		LaneKind.MUD: return [Color(0.45, 0.40, 0.26), 0.30]
		LaneKind.PLANK: return [Color(0.50, 0.37, 0.22), 0.30]
		LaneKind.GRAVEL: return [Color(0.50, 0.46, 0.38), 0.30]
		LaneKind.ROAD: return [Color(0.03, 0.03, 0.04), 0.30]
		_: return [Color(0.42, 0.30, 0.26), 0.30]


## Anchor points the lane threads through: the centre of every gate and the ford of
## every river, as Vector2(x_px, world_y_px), sorted north (most negative y) first.
static func anchors(gates: Array, waters: Array, water_h_px: float, scale: float) -> Array:
	var a: Array = [Vector2(320.0, 0.0)]
	for g in gates:
		a.append(Vector2(320.0, float(g["y"]) * scale))
	for w in waters:
		a.append(Vector2(float(w["ford_x"]) * scale, float(w["y"]) * scale + water_h_px * 0.5))
	a.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.y < q.y)
	return a


## Lane centre x at world y: cosine-eased between the two surrounding anchors.
static func lane_x(anc: Array, wy: float) -> float:
	if anc.is_empty():
		return 320.0
	if wy <= (anc[0] as Vector2).y:
		return (anc[0] as Vector2).x
	for i in range(anc.size() - 1):
		var n: Vector2 = anc[i]
		var s: Vector2 = anc[i + 1]
		if wy <= s.y:
			var span := s.y - n.y
			if span < 1.0:
				return s.x
			return lerpf(n.x, s.x, _smooth((wy - n.y) / span))
	return (anc[anc.size() - 1] as Vector2).x


## Lane tent alpha at horizontal offset `dx` from the centre: peak at the middle,
## zero at LANE_HALF_W. THE profile both the painter's vertex colours and the test
## compositor use.
static func lane_profile(dx: float) -> float:
	return clampf(1.0 - absf(dx) / LANE_HALF_W, 0.0, 1.0)


## The whole structure for one frame, as screen-space records. `cam_y` is the camera
## top in world px. Pure: same inputs, same records.
static func plan(anc: Array, gate_ys: Array, waters: Array, cam_y: float,
		water_h_px: float, ford_half_w_fn: Callable) -> Dictionary:
	var lane: Array = []
	var ruts: Array = []
	var seams: Array = []
	var dashes: Array = []
	var aprons: Array = []
	var planks: Array = []
	var y0 := floorf(cam_y / LANE_SEG_PX) * LANE_SEG_PX - LANE_SEG_PX
	var wy := y0
	while wy - cam_y < 360.0 + LANE_SEG_PX * 2.0:
		var wy1 := wy + LANE_SEG_PX
		var sector := sector_for_y(wy + LANE_SEG_PX * 0.5)
		var kind := lane_kind(sector)
		var cx0 := lane_x(anc, wy)
		var cx1 := lane_x(anc, wy1)
		var tint := lane_tint(kind)
		lane.append({"y0": wy - cam_y, "y1": wy1 - cam_y, "cx0": cx0, "cx1": cx1,
			"hw": LANE_HALF_W, "color": tint[0], "a": tint[1], "kind": kind})
		if kind != LaneKind.PLANK:
			for side in [-1.0, 1.0]:
				ruts.append({"y0": wy - cam_y, "y1": wy1 - cam_y,
					"x0": cx0 + side * RUT_OFFSET, "x1": cx1 + side * RUT_OFFSET,
					"w": 2.0, "color": Color(0.0, 0.0, 0.0, 0.24)})
		else:
			var py := wy
			while py < wy1:
				var cxp := lane_x(anc, py)
				seams.append({"y": py - cam_y, "x0": cxp - LANE_HALF_W * 0.8,
					"x1": cxp + LANE_HALF_W * 0.8, "color": Color(0.05, 0.03, 0.01, 0.26)})
				py += 8.0
		if kind == LaneKind.ROAD:
			var dy := floorf(wy / 24.0) * 24.0
			dashes.append({"y0": dy - cam_y, "y1": dy - cam_y + 10.0,
				"x": lane_x(anc, dy + 5.0), "color": Color(0.82, 0.76, 0.52, 0.24)})
		wy = wy1
	for gy in gate_ys:
		var sy := float(gy) - cam_y
		if sy < -APRON_DEPTH or sy > 360.0 + 40.0:
			continue
		var gh := Art.cell_hash(int(gy), 17)
		var spots: Array = []
		for i in 9:
			var h := Art.cell_hash(int(gy) + i * 31, 23)
			spots.append({"x": 320.0 + float(h % 360) - 180.0,
				"y": sy + 18.0 + float((h / 7) % int(APRON_DEPTH - 30.0)),
				"r": 14.0 + float((h / 13) % 22)})
		aprons.append({"cx": 320.0, "cy": sy + 14.0 + APRON_DEPTH * 0.5, "rx": 200.0,
			"ry": APRON_DEPTH * 0.55, "color": Color(0.10, 0.07, 0.03, 0.20), "spots": spots,
			"seed": gh})
	for w in waters:
		var wsy := float(w["y"]) * (1.0 / float(Fixed.ONE)) - cam_y
		if wsy > 360.0 + FORD_PLANK_DEPTH or wsy + water_h_px < -FORD_PLANK_DEPTH:
			continue
		var band := int(absf(float(w["y"]) * (1.0 / float(Fixed.ONE))) / GATE_SPACING_PX)
		var hw: float = float(ford_half_w_fn.call(band)) * (1.0 / float(Fixed.ONE))
		var fx := float(w["ford_x"]) * (1.0 / float(Fixed.ONE))
		for bank in [-1, 1]:
			var by0: float = wsy - FORD_PLANK_DEPTH if bank < 0 else wsy + water_h_px
			var r := 0.0
			while r < FORD_PLANK_DEPTH:
				planks.append({"y": by0 + r, "x0": fx - hw, "x1": fx + hw,
					"color": Color(0.35, 0.25, 0.14, 0.34) if int(r / 4.0) % 2 == 0
						else Color(0.05, 0.03, 0.01, 0.22)})
				r += 4.0
	return {"lane": lane, "ruts": ruts, "seams": seams, "dashes": dashes,
		"aprons": aprons, "planks": planks}


## Draw a plan onto `canvas` (the ground layer). Vertex-coloured tent polygons for
## the lane, thin lines for ruts / seams / dashes, soft spots for aprons.
static func paint(canvas: CanvasItem, p: Dictionary) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for a in p["aprons"]:
		var c: Color = a["color"]
		var soft: Texture2D = Art.tex("fx_softspot")
		var sz := Vector2(a["rx"] * 2.0, a["ry"] * 2.0)
		canvas.draw_texture_rect(soft, Rect2(Vector2(a["cx"], a["cy"]) - sz * 0.5, sz), false, c)
		for s in a["spots"]:
			var d := Vector2(s["r"] * 2.0, s["r"] * 1.2)
			canvas.draw_texture_rect(soft, Rect2(Vector2(s["x"], s["y"]) - d * 0.5, d), false,
				Color(c.r, c.g, c.b, 0.16))
	for l in p["lane"]:
		var col: Color = l["color"]
		var mid := Color(col.r, col.g, col.b, l["a"])
		var edge := Color(col.r, col.g, col.b, 0.0)
		var hw: float = l["hw"]
		for side in [-1.0, 1.0]:
			canvas.draw_polygon(
				PackedVector2Array([
					Vector2(l["cx0"], l["y0"]), Vector2(l["cx0"] + side * hw, l["y0"]),
					Vector2(l["cx1"] + side * hw, l["y1"]), Vector2(l["cx1"], l["y1"])]),
				PackedColorArray([mid, edge, edge, mid]))
	for r in p["ruts"]:
		canvas.draw_line(Vector2(r["x0"], r["y0"]), Vector2(r["x1"], r["y1"]), r["color"], r["w"])
	for s in p["seams"]:
		canvas.draw_line(Vector2(s["x0"], s["y"]), Vector2(s["x1"], s["y"]), s["color"], 1.0)
	for d in p["dashes"]:
		canvas.draw_line(Vector2(d["x"], d["y0"]), Vector2(d["x"], d["y1"]), d["color"], 2.0)
	for q in p["planks"]:
		canvas.draw_line(Vector2(q["x0"], q["y"] + 1.0), Vector2(q["x1"], q["y"] + 1.0), q["color"], 2.0)


## CPU compositor for tests: lays the plan's lane tent + ruts onto `img` (an Image
## whose pixel row 0 is screen y 0) with the same formulas the painter uses.
static func composite(img: Image, p: Dictionary) -> void:
	for l in p["lane"]:
		var col: Color = l["color"]
		for y in range(maxi(0, int(floor(l["y0"]))), mini(img.get_height(), int(ceil(l["y1"])))):
			var t := clampf((float(y) + 0.5 - float(l["y0"])) / (float(l["y1"]) - float(l["y0"])), 0.0, 1.0)
			var cx := lerpf(float(l["cx0"]), float(l["cx1"]), t)
			for x in range(maxi(0, int(cx - LANE_HALF_W)), mini(img.get_width(), int(cx + LANE_HALF_W) + 1)):
				var al: float = float(l["a"]) * lane_profile(float(x) + 0.5 - cx)
				var o := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(lerpf(o.r, col.r, al), lerpf(o.g, col.g, al), lerpf(o.b, col.b, al), 1.0))
	for r in p["ruts"]:
		var rc: Color = r["color"]
		for y in range(maxi(0, int(floor(r["y0"]))), mini(img.get_height(), int(ceil(r["y1"])))):
			var t := clampf((float(y) + 0.5 - float(r["y0"])) / (float(r["y1"]) - float(r["y0"])), 0.0, 1.0)
			var x := int(round(lerpf(float(r["x0"]), float(r["x1"]), t)))
			if x >= 0 and x < img.get_width():
				var o := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(lerpf(o.r, rc.r, rc.a), lerpf(o.g, rc.g, rc.a), lerpf(o.b, rc.b, rc.a), 1.0))
