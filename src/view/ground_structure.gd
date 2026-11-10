class_name GroundStructure
extends RefCounted
## VIEW-ONLY ground structure: sector biome lookup by WORLD y, feathered biome
## seams, a worn wandering track, gate aprons, ford-bank planking, mud-bank texture.
##
## Everything here is a pure function of (sim geometry, camera). It reads the
## sim's gates / waters READ-ONLY and never feeds SimWorld.checksum().
##
## HONESTY RULE: every mark is FLAT ground paint at low alpha (the track is a
## vertex-coloured soft mesh, ruts are short dashes, planks are 1px seams, aprons
## are soft blobs). Nothing here has an edge, a height or a shadow that could read
## as cover or a wall, and it is painted onto the ground layer, so mines,
## telegraphs, pickups and actors all draw on top of it.
##
## THE TRACK is one continuous function `cover()` of (centre, half-widths, world
## pos): a noise-displaced, feathered edge (never a ruler line), a lighter worn
## centre, and per-biome dressing. The painter samples that function at mesh
## vertices; the test compositor samples it per pixel, so both measure the same ground.

const GATE_SPACING_PX := 1000.0       # SimWorld.GATE_SPACING / F_ONE
const SECTORS := 6
const FEATHER_HALF_PX := 96.0         # blend zone = 192px = two 96px ground bands
const FEATHER_SLICES := 8             # 12px slices per 96px band
const ROW_PX := 6.0                   # lane mesh row height
const LANE_COLS := 13                 # vertices across the track (u = -1.35 .. +1.35)
const LANE_U_MAX := 1.35
const RUT_CELL := 34.0                # world px per rut dash cell
const DETAIL_CELL := 96.0             # world px per puddle / joint / pothole cell
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


## [worn-edge colour, peak alpha, lighter worn-centre colour] of a lane kind.
## Both colours stay inside the biome's own palette; alpha is capped well under 0.4.
static func lane_tint(kind: int) -> Array:
	match kind:
		LaneKind.DIRT: return [Color(0.40, 0.32, 0.21), 0.30, Color(0.70, 0.60, 0.42)]
		LaneKind.MUD: return [Color(0.29, 0.28, 0.21), 0.32, Color(0.50, 0.47, 0.35)]
		LaneKind.PLANK: return [Color(0.26, 0.25, 0.23), 0.28, Color(0.62, 0.60, 0.56)]
		LaneKind.GRAVEL: return [Color(0.38, 0.34, 0.28), 0.30, Color(0.64, 0.58, 0.48)]
		LaneKind.ROAD: return [Color(0.05, 0.05, 0.07), 0.30, Color(0.34, 0.34, 0.38)]
		_: return [Color(0.24, 0.13, 0.11), 0.32, Color(0.44, 0.27, 0.22)]


## Soft-blob colour of the churned ground in front of a gate, per lane kind.
static func apron_tint(kind: int) -> Color:
	match kind:
		LaneKind.DIRT: return Color(0.26, 0.19, 0.10)
		LaneKind.MUD: return Color(0.15, 0.17, 0.10)
		LaneKind.PLANK: return Color(0.17, 0.16, 0.15)
		LaneKind.GRAVEL: return Color(0.24, 0.21, 0.17)
		LaneKind.ROAD: return Color(0.06, 0.06, 0.08)
		_: return Color(0.22, 0.11, 0.09)


## The churned mud-bank colour (the half-speed strips either side of a river) in a
## biome's own palette. The old fixed (0.42, 0.32, 0.20) read as a flat saturated
## orange slab on every sector; this keeps it earthy but desaturated toward the card.
static func mud_bank_color(biome: int) -> Color:
	match biome:
		1: return Color(0.30, 0.32, 0.23)
		2: return Color(0.27, 0.29, 0.21)
		3: return Color(0.36, 0.34, 0.31)
		4: return Color(0.38, 0.34, 0.29)
		5: return Color(0.30, 0.30, 0.34)
		6: return Color(0.38, 0.28, 0.25)
		_: return Color(0.40, 0.34, 0.26)


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


# --- noise ------------------------------------------------------------------

## Smooth 1D value noise in [-1, 1]: one hash per `period` px, eased between.
static func _vn(t: float, period: float, salt: int) -> float:
	var u := t / period
	var i := int(floor(u))
	var f := _smooth(u - float(i))
	var a := float(Art.cell_hash(i, salt) % 2001) / 1000.0 - 1.0
	var b := float(Art.cell_hash(i + 1, salt) % 2001) / 1000.0 - 1.0
	return lerpf(a, b, f)


## Smooth 2D value noise in [-1, 1] on a `cell`-px grid.
static func _vn2(x: float, y: float, cell: float, salt: int) -> float:
	var u := x / cell
	var v := y / cell
	var i := int(floor(u))
	var j := int(floor(v))
	var fx := _smooth(u - float(i))
	var fy := _smooth(v - float(j))
	var a := float(Art.cell_hash(i, j * 7 + salt) % 2001) / 1000.0 - 1.0
	var b := float(Art.cell_hash(i + 1, j * 7 + salt) % 2001) / 1000.0 - 1.0
	var c := float(Art.cell_hash(i, (j + 1) * 7 + salt) % 2001) / 1000.0 - 1.0
	var d := float(Art.cell_hash(i + 1, (j + 1) * 7 + salt) % 2001) / 1000.0 - 1.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


# --- the track --------------------------------------------------------------

static func _base_x(anc: Array, wy: float) -> float:
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


## Lane centre x at world y: eased between the surrounding anchors, plus a gentle
## side-to-side meander that is windowed to ZERO at every gate / ford so the track
## still threads the real crossings.
static func lane_x(anc: Array, wy: float) -> float:
	if anc.is_empty():
		return 320.0
	var near := 1.0e9
	for a in anc:
		near = minf(near, absf((a as Vector2).y - wy))
	var win := _smooth(near / 130.0)
	var m := 27.0 * _vn(wy, 260.0, 3) + 10.0 * _vn(wy, 97.0, 4)
	return _base_x(anc, wy) + m * win


## Left / right half-widths (px): the track is 58-90px wide and breathes along its length.
static func lane_half_w(wy: float, side: float) -> float:
	var salt := 11 if side < 0.0 else 13
	return 43.0 + 7.0 * _vn(wy, 150.0, salt) + 2.0 * _vn(wy, 31.0, salt + 1)


## Track coverage at world (wx, wy): Vector2(alpha01, worn01). `alpha01` is a feathered,
## noise-displaced profile (ragged edge, patchy fade); `worn01` is the lighter,
## uneven centre. Pure.
static func cover(cx: float, hwl: float, hwr: float, wx: float, wy: float) -> Vector2:
	var dx := wx - cx
	var hw := hwl if dx < 0.0 else hwr
	var t := 1.0 - absf(dx) / hw
	t += 0.14 * _vn2(wx, wy, 9.0, 21) + 0.07 * _vn2(wx, wy, 5.0, 24)
	var a := _smooth((t - 0.02) / 0.40)
	a *= 0.78 + 0.22 * (0.5 + 0.5 * _vn2(wx, wy, 23.0, 22))
	var worn := _smooth((t - 0.42) / 0.45) * (0.65 + 0.35 * (0.5 + 0.5 * _vn2(wx, wy, 15.0, 23)))
	return Vector2(a, worn)


static func _lane_color(kind: int, cov: Vector2) -> Color:
	var tint := lane_tint(kind)
	var c: Color = (tint[0] as Color).lerp(tint[2] as Color, cov.y)
	return Color(c.r, c.g, c.b, float(tint[1]) * cov.x)


## One mesh row of the track at world y `wy` (screen y `sy`).
static func _lane_row(anc: Array, wy: float, sy: float, kind: int) -> Dictionary:
	var cx := lane_x(anc, wy)
	var hwl := lane_half_w(wy, -1.0)
	var hwr := lane_half_w(wy, 1.0)
	var vx := PackedFloat32Array()
	var vc := PackedColorArray()
	for c in LANE_COLS:
		var u := -LANE_U_MAX + 2.0 * LANE_U_MAX * float(c) / float(LANE_COLS - 1)
		var x := cx + u * (hwl if u < 0.0 else hwr)
		vx.append(x)
		vc.append(_lane_color(kind, cover(cx, hwl, hwr, x, wy)))
	return {"y": sy, "wy": wy, "cx": cx, "hwl": hwl, "hwr": hwr, "kind": kind,
		"a": float(lane_tint(kind)[1]), "vx": vx, "vc": vc}


static func _line(x0: float, y0: float, x1: float, y1: float, w: float, color: Color) -> Dictionary:
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "w": w, "color": color}


static func _blob(x: float, y: float, w: float, h: float, color: Color) -> Dictionary:
	return {"x": x, "y": y, "w": w, "h": h, "color": color}


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
	var details: Array = []
	var wy_top := floorf(cam_y / ROW_PX) * ROW_PX - ROW_PX
	var wy := wy_top
	while wy - cam_y < 360.0 + ROW_PX * 2.0:
		lane.append(_lane_row(anc, wy, wy - cam_y, lane_kind(sector_for_y(wy + ROW_PX * 0.5))))
		wy += ROW_PX
	_dress_lane(anc, cam_y, ruts, seams, dashes, details)
	for gy in gate_ys:
		var sy := float(gy) - cam_y
		if sy < -APRON_DEPTH or sy > 360.0 + 40.0:
			continue
		aprons.append(_apron(float(gy), sy))
	for w in waters:
		var wsy := float(w["y"]) * (1.0 / float(Fixed.ONE)) - cam_y
		if wsy > 360.0 + FORD_PLANK_DEPTH or wsy + water_h_px < -FORD_PLANK_DEPTH:
			continue
		var wwy := float(w["y"]) * (1.0 / float(Fixed.ONE))
		var band := int(absf(wwy) / GATE_SPACING_PX)
		var hw: float = float(ford_half_w_fn.call(band)) * (1.0 / float(Fixed.ONE))
		var fx := float(w["ford_x"]) * (1.0 / float(Fixed.ONE))
		_planks(planks, fx, hw, wsy, water_h_px, int(wwy), lane_kind(sector_for_y(wwy)))
	return {"lane": lane, "ruts": ruts, "seams": seams, "dashes": dashes,
		"aprons": aprons, "planks": planks, "details": details}


## Ruts (broken, uneven dashes), joints, centre-line fragments, puddles, potholes,
## pebbles: everything the track carries besides its soft body. World-cell hashed, so
## the dressing is stable under scrolling.
static func _dress_lane(anc: Array, cam_y: float, ruts: Array, seams: Array,
		dashes: Array, details: Array) -> void:
	var span_lo := cam_y - RUT_CELL * 2.0
	var span_hi := cam_y + 360.0 + RUT_CELL * 2.0
	var k0 := int(floor(span_lo / RUT_CELL))
	var k1 := int(floor(span_hi / RUT_CELL))
	for k in range(k0, k1 + 1):
		var kind := lane_kind(sector_for_y(float(k) * RUT_CELL + RUT_CELL * 0.5))
		for side: float in [-1.0, 1.0]:
			var h := Art.cell_hash(k, 40 + (0 if side < 0.0 else 1))
			if kind == LaneKind.PLANK:
				continue
			var slag := kind == LaneKind.SLAG
			if h % (16 if slag else 9) == 0:
				continue
			var y0 := float(k) * RUT_CELL + float((h >> 3) % 10)
			var ln := (24.0 + float((h >> 7) % 10)) if slag else (10.0 + float((h >> 7) % 20))
			var y1 := y0 + ln
			var off := (0.30 if not slag else 0.34)
			var jit := 1.6 * _vn(y0, 41.0, 6 + int(side))
			var hw0 := (lane_half_w(y0, side))
			var hw1 := (lane_half_w(y1, side))
			var x0 := lane_x(anc, y0) + side * off * hw0 + jit
			var x1 := lane_x(anc, y1) + side * off * hw1 + jit
			var al := 0.16 + float((h >> 13) % 10) / 100.0
			var col := Color(0.0, 0.0, 0.0, al)
			if kind == LaneKind.MUD:
				col = Color(0.08, 0.06, 0.03, al + 0.04)
			elif slag:
				col = Color(0.04, 0.01, 0.01, 0.28)
			var w := 2.0 + float((h >> 11) % 2) + (1.0 if slag else 0.0)
			ruts.append(_line(x0, y0 - cam_y, x1, y1 - cam_y, w, col))
			if slag:   # a thin warm lip beside the groove, so it reads as a worn channel
				ruts.append(_line(x0 + 2.0, y0 - cam_y, x1 + 2.0, y1 - cam_y, 1.0, Color(0.55, 0.30, 0.20, 0.12)))
	var d0 := int(floor(span_lo / DETAIL_CELL))
	var d1 := int(floor(span_hi / DETAIL_CELL))
	for k in range(d0, d1 + 1):
		var cwy := float(k) * DETAIL_CELL
		var kind := lane_kind(sector_for_y(cwy + DETAIL_CELL * 0.5))
		var h := Art.cell_hash(k, 50)
		var py := cwy + float((h >> 5) % int(DETAIL_CELL))
		var cx := lane_x(anc, py)
		var px := cx + float(h % 50) - 25.0
		var sy := py - cam_y
		match kind:
			LaneKind.MUD:
				if h % 3 != 0:
					var pw := 22.0 + float((h >> 9) % 22)
					var ph := 8.0 + float((h >> 13) % 8)
					details.append(_blob(px, sy, pw * 1.3, ph * 1.3, Color(0.12, 0.10, 0.05, 0.14)))
					details.append(_blob(px, sy, pw, ph, Color(0.20, 0.27, 0.28, 0.30)))
					details.append(_blob(px - pw * 0.15, sy - ph * 0.15, pw * 0.5, ph * 0.4, Color(0.55, 0.62, 0.60, 0.12)))
			LaneKind.PLANK:
				# expansion joints: partial lines across the slab, with a gap and a light lip
				var jy := cwy + float(h % 40)
				var jcx := lane_x(anc, jy)
				var l0 := jcx - lane_half_w(jy, -1.0) * (0.45 + float((h >> 3) % 50) / 100.0)
				var r0 := jcx + lane_half_w(jy, 1.0) * (0.45 + float((h >> 9) % 50) / 100.0)
				var gap := lerpf(l0, r0, 0.3 + float((h >> 15) % 40) / 100.0)
				seams.append({"x0": l0, "x1": gap - 3.0, "y": jy - cam_y, "color": Color(0.05, 0.04, 0.03, 0.26)})
				seams.append({"x0": gap + 4.0, "x1": r0, "y": jy - cam_y, "color": Color(0.05, 0.04, 0.03, 0.26)})
				seams.append({"x0": l0, "x1": gap - 3.0, "y": jy - cam_y + 1.0, "color": Color(0.85, 0.83, 0.78, 0.08)})
				if h % 2 == 0:
					details.append(_blob(px, sy, 24.0 + float((h >> 9) % 22), 12.0 + float((h >> 13) % 14),
						Color(0.10, 0.09, 0.08, 0.16)))
			LaneKind.ROAD:
				if h % 4 == 0:
					var pw2 := 10.0 + float((h >> 9) % 8)
					details.append(_blob(px, sy, pw2 * 1.5, pw2 * 0.9, Color(0.55, 0.55, 0.58, 0.07)))
					details.append(_blob(px, sy, pw2, pw2 * 0.6, Color(0.02, 0.02, 0.03, 0.30)))
				if (h >> 3) % 5 == 0:
					details.append(_blob(px, sy, 44.0, 22.0, Color(0.0, 0.0, 0.0, 0.10)))
			LaneKind.GRAVEL, LaneKind.DIRT:
				for i in 4:
					var hp := Art.cell_hash(k * 11 + i, 51)
					var rr := 2.0 + float(hp % 3)
					details.append(_blob(cx + float(hp % 70) - 35.0, sy + float((hp >> 7) % 40) - 20.0, rr * 2.0, rr * 1.6,
						Color(0.14, 0.12, 0.09, 0.22) if kind == LaneKind.GRAVEL else Color(0.55, 0.47, 0.34, 0.20)))
			_:
				pass
	if true:   # ROAD centre-line fragments + SLAG sleepers ride finer cells than the details
		var f0 := int(floor(span_lo / 40.0))
		var f1 := int(floor(span_hi / 40.0))
		for k in range(f0, f1 + 1):
			var kind := lane_kind(sector_for_y(float(k) * 40.0 + 20.0))
			var h := Art.cell_hash(k, 60)
			if kind == LaneKind.ROAD and h % 100 >= 36:
				var ds := float(k) * 40.0 + float(h % 14)
				var de := ds + 6.0 + float((h >> 7) % 11)
				dashes.append({"x": lane_x(anc, (ds + de) * 0.5) + 1.0, "y0": ds - cam_y, "y1": de - cam_y,
					"color": Color(0.82, 0.76, 0.52, 0.12 + float((h >> 11) % 12) / 100.0)})
			elif kind == LaneKind.SLAG and h % 3 != 0:
				var sy2 := float(k) * 40.0 + float(h % 30)
				var scx := lane_x(anc, sy2)
				var shw := lane_half_w(sy2, 1.0) * 0.34
				seams.append({"x0": scx - shw, "x1": scx + shw, "y": sy2 - cam_y, "color": Color(0.05, 0.02, 0.02, 0.14)})


## A gate apron: churned ground in front of the wall as ~24 overlapping soft blobs and a
## scatter of dark / pale flecks in the sector's own palette. No flat fill, no hard edge.
static func _apron(gy: float, sy: float) -> Dictionary:
	var kind := lane_kind(sector_for_y(gy - 40.0))
	var tint := apron_tint(kind)
	var gh := Art.cell_hash(int(gy), 17)
	var blobs: Array = []
	for i in 24:
		var h := Art.cell_hash(int(gy) + i * 31, 23)
		var bx := 320.0 + (float(h % 360) - 180.0) * (0.55 + 0.45 * float((h >> 9) % 100) / 100.0)
		var by := sy + 18.0 + float((h >> 5) % int(APRON_DEPTH - 44.0))
		var bw := 26.0 + float((h >> 13) % 54)
		var bh := 12.0 + float((h >> 17) % 18)
		var shade := 0.7 + 0.6 * float((h >> 21) % 100) / 100.0
		blobs.append(_blob(bx, by, bw, bh, Color(tint.r * shade, tint.g * shade, tint.b * shade, 0.10 + float((h >> 25) % 9) / 100.0)))
	for i in 18:
		var h2 := Art.cell_hash(int(gy) + i * 53, 29)
		var fx := 320.0 + float(h2 % 380) - 190.0
		var fy := sy + 20.0 + float((h2 >> 9) % int(APRON_DEPTH - 50.0))
		var fr := 1.5 + float((h2 >> 17) % 3)
		var light := (h2 >> 21) % 3 == 0
		blobs.append(_blob(fx, fy, fr * 2.0, fr * 1.5,
			Color(0.80, 0.76, 0.66, 0.14) if light else Color(0.03, 0.03, 0.03, 0.22)))
	return {"cx": 320.0, "cy": sy + 14.0 + APRON_DEPTH * 0.5, "rx": 200.0, "ry": APRON_DEPTH * 0.55,
		"color": Color(tint.r, tint.g, tint.b, 0.20), "blobs": blobs, "seed": gh, "kind": kind}


## Ford-bank approach planking: irregular boards, frayed ends, broken seams, in the
## sector's own earth tones rather than a flat orange-brown.
static func _planks(out: Array, fx: float, hw: float, wsy: float, water_h_px: float,
		seed_y: int, kind: int) -> void:
	var tint := lane_tint(kind)
	var dark: Color = tint[0]
	var light: Color = tint[2]
	for bank in [-1, 1]:
		var by0: float = wsy - FORD_PLANK_DEPTH if bank < 0 else wsy + water_h_px
		var r := 0.0
		var row := 0
		while r < FORD_PLANK_DEPTH:
			var h := Art.cell_hash(seed_y + row * 17 + bank * 5, 71)
			var x := fx - hw - float(h % 5)
			var xe := fx + hw + float((h >> 5) % 5)
			var pi := 0
			while x < xe:
				var hs := Art.cell_hash(seed_y + row * 29 + pi * 7 + bank, 73)
				var ln := 10.0 + float(hs % 17)
				var x1 := minf(x + ln, xe)
				var plank_row := int(r / 4.0) % 2 == 0
				var col := dark.lerp(light, 0.25 + float((hs >> 6) % 60) / 100.0) if plank_row \
					else Color(dark.r * 0.35, dark.g * 0.35, dark.b * 0.35, 1.0)
				out.append({"y": by0 + r, "x0": x, "x1": x1 - float((hs >> 12) % 2) * 2.0,
					"color": Color(col.r, col.g, col.b, 0.30 + float((hs >> 14) % 8) / 100.0 if plank_row else 0.20)})
				x = x1 + float((hs >> 17) % 3)
				pi += 1
			r += 4.0
			row += 1


## Soft blobs of a mud bank (the half-speed strips beside a river) in LOCAL coords of a
## `size` rect: churned dark and pale patches on a biome-tinted base. Centres are held so
## a blob overhangs the rect by at most 3px. Deterministic per `seed`.
static func mud_bank_plan(biome: int, seed: int, size: Vector2, soot: float) -> Dictionary:
	var base := mud_bank_color(biome).lerp(Color(0.26, 0.23, 0.20), soot)
	var blobs: Array = []
	for i in 40:
		var h := Art.cell_hash(seed + i * 13, 81)
		var bw := 18.0 + float(h % 46)
		var bh := 6.0 + float((h >> 6) % 11)
		var cx := float((h >> 10) % int(size.x))
		var cy := lerpf(bh * 0.5 - 3.0, size.y - bh * 0.5 + 3.0, float((h >> 20) % 100) / 100.0)
		var dark := (h >> 28) % 3 != 0
		var c := base.darkened(0.45) if dark else base.lightened(0.30)
		blobs.append(_blob(cx, cy, bw, bh, Color(c.r, c.g, c.b, 0.42 if dark else 0.30)))
	var v := 0.64 - 0.14 * soot
	return {"base": Color(base.r, base.g, base.b, 0.92), "blobs": blobs, "tex_mod": Color(v, v, v, 0.92)}


# --- painting -----------------------------------------------------------------

static func _paint_blobs(canvas: CanvasItem, blobs: Array, offset: Vector2) -> void:
	var soft: Texture2D = Art.tex("fx_softspot")
	for b in blobs:
		var sz := Vector2(b["w"], b["h"])
		canvas.draw_texture_rect(soft, Rect2(Vector2(b["x"], b["y"]) + offset - sz * 0.5, sz), false, b["color"])


## Mud-bank blobs, drawn over the bank's base fill by main.gd's _draw_water.
static func paint_mud_bank(canvas: CanvasItem, p: Dictionary, origin: Vector2) -> void:
	_paint_blobs(canvas, p["blobs"], origin)


## The track as vertex-coloured quads (one draw_polygon per cell; Gouraud across each).
static func _paint_lane(canvas: CanvasItem, rows: Array) -> void:
	for i in rows.size() - 1:
		var r0: Dictionary = rows[i]
		var r1: Dictionary = rows[i + 1]
		var x0: PackedFloat32Array = r0["vx"]
		var x1: PackedFloat32Array = r1["vx"]
		var c0: PackedColorArray = r0["vc"]
		var c1: PackedColorArray = r1["vc"]
		var y0: float = r0["y"]
		var y1: float = r1["y"]
		for c in LANE_COLS - 1:
			if c0[c].a + c0[c + 1].a + c1[c].a + c1[c + 1].a < 0.004:
				continue
			canvas.draw_polygon(
				PackedVector2Array([Vector2(x0[c], y0), Vector2(x0[c + 1], y0), Vector2(x1[c + 1], y1), Vector2(x1[c], y1)]),
				PackedColorArray([c0[c], c0[c + 1], c1[c + 1], c1[c]]))


## Draw a plan onto `canvas` (the ground layer): the track as vertex-coloured quads, then ruts / joints / fragments as short strokes, then soft blobs.
static func paint(canvas: CanvasItem, p: Dictionary) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for a in p["aprons"]:
		_paint_blobs(canvas, a["blobs"], Vector2.ZERO)
	_paint_lane(canvas, p["lane"])
	_paint_blobs(canvas, p["details"], Vector2.ZERO)
	for r in p["ruts"]:
		canvas.draw_line(Vector2(r["x0"], r["y0"]), Vector2(r["x1"], r["y1"]), r["color"], r["w"])
	for s in p["seams"]:
		canvas.draw_line(Vector2(s["x0"], s["y"]), Vector2(s["x1"], s["y"]), s["color"], 1.0)
	for d in p["dashes"]:
		canvas.draw_line(Vector2(d["x"], d["y0"]), Vector2(d["x"], d["y1"]), d["color"], 2.0)
	for q in p["planks"]:
		canvas.draw_line(Vector2(q["x0"], q["y"] + 1.0), Vector2(q["x1"], q["y"] + 1.0), q["color"], 2.0)


# --- test compositor ----------------------------------------------------------

static func _over(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), 1.0))


## Soft-blob rasteriser matching fx_softspot's radial falloff closely enough to measure.
static func composite_blobs(img: Image, blobs: Array, offset: Vector2) -> void:
	for b in blobs:
		var col: Color = b["color"]
		var hw := float(b["w"]) * 0.5
		var hh := float(b["h"]) * 0.5
		var cx := float(b["x"]) + offset.x
		var cy := float(b["y"]) + offset.y
		for y in range(maxi(0, int(floor(cy - hh))), mini(img.get_height(), int(ceil(cy + hh)) + 1)):
			for x in range(maxi(0, int(floor(cx - hw))), mini(img.get_width(), int(ceil(cx + hw)) + 1)):
				var rr := Vector2((float(x) + 0.5 - cx) / hw, (float(y) + 0.5 - cy) / hh).length()
				if rr < 1.0:
					_over(img, x, y, col, col.a * (1.0 - _smooth(rr)))


## CPU compositor for tests: lays the plan's track (per-pixel, via the same cover()
## the mesh vertices sample), ruts and soft blobs onto `img` (pixel row 0 = screen y 0).
static func composite(img: Image, p: Dictionary) -> void:
	for a in p["aprons"]:
		composite_blobs(img, a["blobs"], Vector2.ZERO)
	var rows: Array = p["lane"]
	if rows.size() > 1:
		var y_first: float = rows[0]["y"]
		for y in range(maxi(0, int(floor(y_first))), mini(img.get_height(), int(ceil(float(rows[rows.size() - 1]["y"]))))):
			var f := (float(y) + 0.5 - y_first) / ROW_PX
			var i := clampi(int(floor(f)), 0, rows.size() - 2)
			var t := f - float(i)
			var r0: Dictionary = rows[i]
			var r1: Dictionary = rows[i + 1]
			var cx := lerpf(float(r0["cx"]), float(r1["cx"]), t)
			var hwl := lerpf(float(r0["hwl"]), float(r1["hwl"]), t)
			var hwr := lerpf(float(r0["hwr"]), float(r1["hwr"]), t)
			var wy := lerpf(float(r0["wy"]), float(r1["wy"]), t)
			var kind: int = r0["kind"]
			for x in range(maxi(0, int(cx - hwl * LANE_U_MAX)), mini(img.get_width(), int(cx + hwr * LANE_U_MAX) + 1)):
				var c := _lane_color(kind, cover(cx, hwl, hwr, float(x) + 0.5, wy))
				if c.a > 0.0:
					_over(img, x, y, c, c.a)
	composite_blobs(img, p["details"], Vector2.ZERO)
	for r in p["ruts"]:
		var rc: Color = r["color"]
		for y in range(maxi(0, int(floor(r["y0"]))), mini(img.get_height(), int(ceil(r["y1"])))):
			var t2 := clampf((float(y) + 0.5 - float(r["y0"])) / maxf(0.001, float(r["y1"]) - float(r["y0"])), 0.0, 1.0)
			var x2 := int(round(lerpf(float(r["x0"]), float(r["x1"]), t2)))
			if x2 >= 0 and x2 < img.get_width():
				_over(img, x2, y, rc, rc.a)
