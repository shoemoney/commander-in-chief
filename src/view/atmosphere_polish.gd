class_name AtmospherePolish
extends RefCounted
## Depth and life on top of Atmosphere: sector pollen glints, canopy light shafts (dawn jungle,
## marsh haze) and a barely-there edge vignette. Cloud shadows, heat shimmer, smoke and mist belong
## to Atmosphere alone: this file must not add a second copy of any of them. VIEW ONLY and
## stateless: every value is a pure function of (sector, frame, motion, camera), so a fixed-frame
## capture is byte-reproducible. Reduce-motion (motion < 0.5) freezes time; the vignette and the
## shadows stay (static light, not motion).
## Colours are near-grey or cool and alphas are tiny: nothing here touches the lethal red/amber band.

const W := 640.0
const H := 360.0
const SECTORS := 6

## Per-sector air: kind -> {n, size, vel (px/s), par (camera share), col, twinkle, wob}.
## Soft fx_softspot sparkles; pale/cool tints only, never the lethal red/amber band.
const AIR := [
	[{"n": 18, "size": Vector2(8, 8), "vel": Vector2(9, -6), "par": 0.9, "wob": 6.0, "tw": true,
		"col": Color(1.0, 0.98, 0.8, 0.8)}],                                           # S1 pollen
	[{"n": 14, "size": Vector2(10, 10), "vel": Vector2(6, -4), "par": 0.9, "wob": 10.0, "tw": true,
		"col": Color(0.78, 1.0, 0.7, 0.85)}],                                            # S2 fireflies
	[{"n": 12, "size": Vector2(34, 3), "vel": Vector2(240, 18), "par": 0.2, "wob": 0.0, "tw": false,
		"col": Color(0.92, 0.88, 0.8, 0.32), "moving": true}],                           # S3 wind dust streaks
	[{"n": 14, "size": Vector2(9, 9), "vel": Vector2(6, -34), "par": 0.8, "wob": 6.0, "tw": true,
		"col": Color(1.0, 0.94, 0.84, 0.85)}],                                             # S4 sparks
	[{"n": 22, "size": Vector2(7, 7), "vel": Vector2(-8, 26), "par": 0.7, "wob": 7.0, "tw": false,
		"col": Color(0.86, 0.84, 0.82, 0.8)}],                                            # S5 ash fall
	[{"n": 20, "size": Vector2(10, 10), "vel": Vector2(5, -46), "par": 0.8, "wob": 8.0, "tw": true,
		"col": Color(0.96, 0.9, 0.82, 0.9)}],                                           # S6 rising embers
]

## Light shafts: dawn jungle, marsh haze and the bridge's open sky call for them.
## Feathered: each shaft is two halves whose outer edges are transparent. Fades in from the top (clear of the HUD) and out toward the bottom.
const SHAFTS := {
	0: {"n": 4, "alpha": 0.20, "tint": Color(1.0, 0.97, 0.82)},
	1: {"n": 3, "alpha": 0.13, "tint": Color(0.82, 0.92, 0.95)},
	2: {"n": 3, "alpha": 0.12, "tint": Color(0.95, 0.94, 0.88)},
}
const SHAFT_TOP_Y := 36.0   ## below the HUD band

## Vignette tint/strength per sector. Deliberately faint (the base game's own edge card is 0.04 so
## corner luma loss stays under 5% and snipers stay visible); this only adds a sector tint.
const VIGNETTE := [Color(0.0, 0.05, 0.02, 0.06), Color(0.0, 0.05, 0.07, 0.06),
	Color(0.04, 0.04, 0.05, 0.05), Color(0.05, 0.03, 0.03, 0.06),
	Color(0.03, 0.03, 0.04, 0.06), Color(0.05, 0.02, 0.03, 0.06)]


static func _sec(sector: int) -> int:
	return clampi(sector, 0, SECTORS - 1)


static func _time(frames: int, motion: float) -> float:
	return 0.0 if motion < 0.5 else float(frames) / 60.0


static func vignette_color(sector: int) -> Color:
	return VIGNETTE[_sec(sector)]


## Sector air (tex rects): pollen, fireflies, dust, sparks, ash, embers. Frozen
## (twinkle held at 60 percent, no drift) under reduce-motion.
static func plan_air(sector: int, frames: int, motion: float, cam_px: float) -> Array:
	var s := _sec(sector)
	var ops: Array = []
	var t := _time(frames, motion)
	var k := 0
	for def in AIR[s]:
		k += 1
		var size: Vector2 = def["size"]
		var vel: Vector2 = def["vel"]
		var col: Color = def["col"]
		var span_x := W + size.x * 2.0
		var span_y := H + size.y * 2.0
		for i in int(def["n"]):
			var h1 := Art.cell_hash(i * 7 + 401 * k, s + 3)
			var h2 := Art.cell_hash(i * 11 + 13 * k, s * 5 + 17)
			var spd := 0.6 + float((h1 / 1000) % 4) * 0.2
			var u := float(h1 % 1000) / 1000.0
			var v := float(h2 % 1000) / 1000.0
			var ph := float(h1 % 628) / 100.0
			var x := fposmod(u * span_x + vel.x * t * spd, span_x) - size.x
			var y := fposmod(v * span_y + vel.y * t * spd - cam_px * float(def["par"]), span_y) - size.y
			x += sin(t * 1.1 + ph) * float(def["wob"])
			var a := col.a
			if def["tw"]:
				a *= 0.6 if motion < 0.5 else 0.45 + 0.55 * sin(t * 2.4 + float(h2 % 628) / 100.0)
			var r := Rect2(Vector2(x, y).round(), size)
			if r.end.x <= 0.0 or r.position.x >= W or r.end.y <= 0.0 or r.position.y >= H or a < 0.02:
				continue
			ops.append({"k": "air", "tex": true, "r": r, "c": Color(col.r, col.g, col.b, a)})
			if size.x <= 10.0:   # a crisp core so small motes read against busy ground
				var cs := 3.0 if size.x >= 9.0 else 2.0
				ops.append({"k": "core", "tex": false, "c": Color(col.r, col.g, col.b, minf(a * 1.2, 0.95)),
					"r": Rect2(r.position + (size - Vector2(cs, cs)) * 0.5, Vector2(cs, cs)).abs()})
	return ops


## Kept for callers that only want the jungle glints.
static func plan_pollen(sector: int, frames: int, motion: float, cam_px: float) -> Array:
	return plan_air(sector, frames, motion, cam_px) if _sec(sector) == 0 else []


## Light shafts as feathered parallelograms: {"pts", "cols"}. Each shaft is two halves meeting on
## the centre line; the outer edges, the top and the bottom are alpha 0, so no hard long edge.
## Empty for sectors that do not call for them.
static func plan_shafts(sector: int, frames: int, motion: float) -> Array:
	var s := _sec(sector)
	var out: Array = []
	if not SHAFTS.has(s):
		return out
	var def: Dictionary = SHAFTS[s]
	var t := _time(frames, motion)
	var tint: Color = def["tint"]
	var n := int(def["n"])
	var slant := 150.0
	var y1 := H + 4.0
	var ym := 130.0
	var c0 := Color(tint.r, tint.g, tint.b, 0.0)
	for i in n:
		var h := Art.cell_hash(i * 19 + 77, s + 29)
		var x0 := 120.0 + float(i) * (W - 160.0) / float(maxi(n - 1, 1)) + float(h % 40) - 20.0
		x0 += sin(t * 0.12 + float(i) * 1.7) * 14.0
		var wid := 34.0 + float((h / 64) % 22)
		var breathe := 0.75 + 0.25 * sin(t * 0.35 + float(i) * 2.1)
		var c1 := Color(tint.r, tint.g, tint.b, float(def["alpha"]) * breathe * 0.25)
		var xm := x0 - slant * (ym - SHAFT_TOP_Y) / (y1 - SHAFT_TOP_Y)
		var xb := x0 - slant
		for half in 2:
			var edge_x := x0 if half == 0 else x0 + wid
			var edge_m := xm if half == 0 else xm + wid
			var edge_b := xb if half == 0 else xb + wid
			var cx := x0 + wid * 0.5
			var cxm := xm + wid * 0.5
			var cxb := xb + wid * 0.5
			out.append({
				"pts": PackedVector2Array([Vector2(edge_x, SHAFT_TOP_Y), Vector2(cx, SHAFT_TOP_Y),
					Vector2(cxm, ym), Vector2(cxb, y1), Vector2(edge_b, y1), Vector2(edge_m, ym)]),
				"cols": PackedColorArray([c0, c0, c1, c0, c0, c0])})
	return out


## Everything laid down under the actors (called from main._draw_atmosphere_ground).
static func draw_ground(ci: CanvasItem, sector: int, frames: int, motion: float, cam_px: float) -> void:
	if not Atmosphere.enabled:
		return
	draw_shafts(ci, sector, frames, motion)
	draw_air(ci, sector, frames, motion, cam_px)


## Screen-space edge vignette. The caller has already cancelled the shake transform.
static func draw_vignette(ci: CanvasItem, sector: int) -> void:
	if not Atmosphere.enabled:
		return
	ci.draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, W, H), false, vignette_color(sector))


## Per (sector, layer) static particle tables for draw_base(): everything Atmosphere.plan() derives
## from cell_hash and the kind tables, which never changes for a sector. Time, camera and motion
## stay per-frame inputs, so there is nothing to invalidate; reset_cache() exists for tests.
static var _base_cache := {}


static func reset_cache() -> void:
	_base_cache.clear()
	_air_cache.clear()
	_shaft_cache.clear()


static func _base_tables(sector: int, layer: int) -> Array:
	var sec := clampi(sector, 0, Atmosphere.SECTORS - 1)
	var key := sector * 8 + layer
	var hit = _base_cache.get(key)
	if hit != null:
		return hit
	var out: Array = []
	var prof: Dictionary = Atmosphere.PROFILES[sec]
	var kind_id := 0
	for kind in prof:
		kind_id += 1
		var def: Dictionary = Atmosphere.KINDS[kind]
		if def["layer"] != layer:
			continue
		var size: Vector2 = def["size"]
		var span_x := Atmosphere.W + size.x * 2.0
		var span_y := Atmosphere.H + size.y * 2.0 + 40.0
		var n := int(prof[kind])
		var pt := PackedFloat64Array()   # per particle: u*span_x, v*span_y, spd, h1 phase, h2 phase, v
		pt.resize(n * 6)
		for i in n:
			var h1 := Art.cell_hash(i * 31 + kind_id, sector + 1)
			var h2 := Art.cell_hash(i * 17 + 3, kind_id * 5 + sector)
			var u := float(h1 % 1000) / 1000.0
			var v := float(h2 % 1000) / 1000.0
			pt[i * 6] = u * span_x
			pt[i * 6 + 1] = v * span_y
			pt[i * 6 + 2] = 0.6 + float((h1 / 1000) % 5) * 0.2
			pt[i * 6 + 3] = float(h1 % 628) / 100.0
			pt[i * 6 + 4] = float(h2 % 628) / 100.0
			pt[i * 6 + 5] = v
		out.append({"tex": def["tex"], "size": size, "vel": def["vel"], "span_x": span_x, "span_y": span_y,
			"par": float(def["par"]), "wob": float(def.get("wobble", 0.0)), "tw": def.get("twinkle", false),
			"fade": def.get("fade", false), "calm_skip": def.get("motion_only", false),
			"col": def["col"], "n": n, "pt": pt})
	_base_cache[key] = out
	return out


## The cached equivalent of Atmosphere.draw(Atmosphere.plan(...)) for one layer: the same particles,
## rects and colours (pinned against plan() in the tests), painted straight to the canvas with no op
## dictionaries. `rec`, when given, collects [tex, rect, colour] instead of drawing.
static func draw_base(ci: CanvasItem, sector: int, frames: int, motion: float, cam_px: float, layer: int,
		rec = null) -> void:
	if not Atmosphere.enabled:
		return
	var calm := motion < 0.5
	var t := 0.0 if calm else float(frames) / 60.0
	var soft := Art.tex("fx_softspot")
	var count := 0
	for e in _base_tables(sector, layer):
		if calm and e["calm_skip"]:
			continue
		var size: Vector2 = e["size"]
		var vel: Vector2 = e["vel"]
		var span_x: float = e["span_x"]
		var span_y: float = e["span_y"]
		var par_cam: float = cam_px * e["par"]
		var wob: float = e["wob"]
		var tw: bool = e["tw"]
		var fade: bool = e["fade"]
		var col: Color = e["col"]
		var is_tex: bool = e["tex"]
		var pt: PackedFloat64Array = e["pt"]
		for i in int(e["n"]):
			var b := i * 6
			var spd := pt[b + 2]
			var x := fposmod(pt[b] + vel.x * t * spd, span_x) - size.x
			var y := fposmod(pt[b + 1] + vel.y * t * spd - par_cam, span_y) - size.y - 20.0
			if wob > 0.0:
				y += sin(t * 2.3 + pt[b + 3]) * wob
			var a := col.a
			if tw:
				a *= 0.55 + 0.45 * sin(t * 3.1 + pt[b + 4])
			if fade:
				a *= clampf(sin(PI * fposmod(pt[b + 5] + t * 0.18 * spd, 1.0)), 0.0, 1.0)
			a = minf(a, Atmosphere.MAX_ALPHA)
			var r := Rect2(Vector2(x, y).round(), size)
			if r.end.x <= 0.0 or r.position.x >= Atmosphere.W or r.end.y <= 0.0 or r.position.y >= Atmosphere.H:
				continue
			if a < 0.01:
				continue
			var c := Color(col.r, col.g, col.b, a)
			if rec != null:
				rec.append([is_tex, r, c])
			elif is_tex:
				ci.draw_texture_rect(soft, r, false, c)
			else:
				ci.draw_rect(r, c)
			count += 1
			if count >= Atmosphere.MAX_OPS:
				return


static var _air_cache := {}
static var _shaft_cache := {}


## Static per-sector tables for draw_air(): the hashed phases never change, only time and camera do.
static func _air_tables(sector: int) -> Array:
	var s := _sec(sector)
	var hit = _air_cache.get(s)
	if hit != null:
		return hit
	var out: Array = []
	var k := 0
	for def in AIR[s]:
		k += 1
		var size: Vector2 = def["size"]
		var span_x := W + size.x * 2.0
		var span_y := H + size.y * 2.0
		var n := int(def["n"])
		var pt := PackedFloat64Array()   # per particle: u*span_x, v*span_y, spd, wobble phase, twinkle phase
		pt.resize(n * 5)
		for i in n:
			var h1 := Art.cell_hash(i * 7 + 401 * k, s + 3)
			var h2 := Art.cell_hash(i * 11 + 13 * k, s * 5 + 17)
			pt[i * 5] = float(h1 % 1000) / 1000.0 * span_x
			pt[i * 5 + 1] = float(h2 % 1000) / 1000.0 * span_y
			pt[i * 5 + 2] = 0.6 + float((h1 / 1000) % 4) * 0.2
			pt[i * 5 + 3] = float(h1 % 628) / 100.0
			pt[i * 5 + 4] = float(h2 % 628) / 100.0
		out.append({"size": size, "vel": def["vel"], "span_x": span_x, "span_y": span_y, "par": float(def["par"]),
			"wob": float(def["wob"]), "tw": def["tw"], "col": def["col"], "n": n, "pt": pt})
	_air_cache[s] = out
	return out


## plan_air() painted straight to the canvas from cached tables (same rects, colours and order;
## pinned against plan_air in the tests). `rec` collects [tex, rect, colour] instead of drawing.
static func draw_air(ci: CanvasItem, sector: int, frames: int, motion: float, cam_px: float, rec = null) -> void:
	var t := _time(frames, motion)
	var soft := Art.tex("fx_softspot")
	for e in _air_tables(sector):
		var size: Vector2 = e["size"]
		var vel: Vector2 = e["vel"]
		var span_x: float = e["span_x"]
		var span_y: float = e["span_y"]
		var par_cam: float = cam_px * e["par"]
		var wob: float = e["wob"]
		var tw: bool = e["tw"]
		var col: Color = e["col"]
		var pt: PackedFloat64Array = e["pt"]
		var core_sz := 0.0
		if size.x <= 10.0:
			core_sz = 3.0 if size.x >= 9.0 else 2.0
		for i in int(e["n"]):
			var b := i * 5
			var spd := pt[b + 2]
			var x := fposmod(pt[b] + vel.x * t * spd, span_x) - size.x
			var y := fposmod(pt[b + 1] + vel.y * t * spd - par_cam, span_y) - size.y
			x += sin(t * 1.1 + pt[b + 3]) * wob
			var a := col.a
			if tw:
				a *= 0.6 if motion < 0.5 else 0.45 + 0.55 * sin(t * 2.4 + pt[b + 4])
			var r := Rect2(Vector2(x, y).round(), size)
			if r.end.x <= 0.0 or r.position.x >= W or r.end.y <= 0.0 or r.position.y >= H or a < 0.02:
				continue
			if rec != null:
				rec.append([true, r, Color(col.r, col.g, col.b, a)])
			else:
				ci.draw_texture_rect(soft, r, false, Color(col.r, col.g, col.b, a))
			if core_sz > 0.0:
				var cs := core_sz
				var cr := Rect2(r.position + (size - Vector2(cs, cs)) * 0.5, Vector2(cs, cs)).abs()
				var cc := Color(col.r, col.g, col.b, minf(a * 1.2, 0.95))
				if rec != null:
					rec.append([false, cr, cc])
				else:
					ci.draw_rect(cr, cc)


## Static per-sector shaft tables. The polygons are still handed to draw_polygon: their hexagon
## shapes drift with time, and the engine's ear-clip picks different diagonals on different
## frames (measured), so the triangulation cannot be cached without changing the picture.
static func _shaft_tables(sector: int) -> Dictionary:
	var s := _sec(sector)
	var hit = _shaft_cache.get(s)
	if hit != null:
		return hit
	var out := {"n": 0}
	if SHAFTS.has(s):
		var n := int(SHAFTS[s]["n"])
		var base := PackedFloat64Array()   # per shaft: x0 before sway, wid
		base.resize(n * 2)
		for i in n:
			var h := Art.cell_hash(i * 19 + 77, s + 29)
			base[i * 2] = 120.0 + float(i) * (W - 160.0) / float(maxi(n - 1, 1)) + float(h % 40) - 20.0
			base[i * 2 + 1] = 34.0 + float((h / 64) % 22)
		out = {"n": n, "base": base}
	_shaft_cache[s] = out
	return out


## plan_shafts() painted without the per-shaft dictionaries and hash lookups.
static func draw_shafts(ci: CanvasItem, sector: int, frames: int, motion: float, rec = null) -> void:
	var s := _sec(sector)
	var tb := _shaft_tables(s)
	var n: int = tb["n"]
	if n == 0:
		return
	var def: Dictionary = SHAFTS[s]
	var base: PackedFloat64Array = tb["base"]
	var t := _time(frames, motion)
	var tint: Color = def["tint"]
	var slant := 150.0
	var y1 := H + 4.0
	var ym := 130.0
	var c0 := Color(tint.r, tint.g, tint.b, 0.0)
	for i in n:
		var x0 := base[i * 2] + sin(t * 0.12 + float(i) * 1.7) * 14.0
		var wid := base[i * 2 + 1]
		var breathe := 0.75 + 0.25 * sin(t * 0.35 + float(i) * 2.1)
		var c1 := Color(tint.r, tint.g, tint.b, float(def["alpha"]) * breathe * 0.25)
		var xm := x0 - slant * (ym - SHAFT_TOP_Y) / (y1 - SHAFT_TOP_Y)
		var xb := x0 - slant
		for half in 2:
			var edge_x := x0 if half == 0 else x0 + wid
			var edge_m := xm if half == 0 else xm + wid
			var edge_b := xb if half == 0 else xb + wid
			var cx := x0 + wid * 0.5
			var cxm := xm + wid * 0.5
			var cxb := xb + wid * 0.5
			var pts := PackedVector2Array([Vector2(edge_x, SHAFT_TOP_Y), Vector2(cx, SHAFT_TOP_Y),
				Vector2(cxm, ym), Vector2(cxb, y1), Vector2(edge_b, y1), Vector2(edge_m, ym)])
			var cols := PackedColorArray([c0, c0, c1, c0, c0, c0])
			if rec != null:
				rec.append([pts, cols])
			else:
				ci.draw_polygon(pts, cols)
