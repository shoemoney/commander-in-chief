class_name AtmospherePolish
extends RefCounted
## Depth and life on top of Atmosphere: bigger drifting cloud shadows, sector pollen glints,
## canopy light shafts (dawn jungle, marsh haze) and a gentle edge vignette. VIEW ONLY and
## stateless: every value is a pure function of (sector, frame, motion, camera), so a fixed-frame
## capture is byte-reproducible. Reduce-motion (motion < 0.5) freezes time; the vignette and the
## shadows stay (static light, not motion).
## Colours are near-grey or cool and alphas are tiny: nothing here touches the lethal red/amber band.

const W := 640.0
const H := 360.0
const SECTORS := 6

## Big, slow cloud shadows. Same op shape as Atmosphere.plan so Atmosphere.draw paints them.
const CLOUD := {"size": Vector2(340, 190), "vel": Vector2(7, 2.4), "par": 0.5}
const CLOUD_COUNT := [4, 3, 4, 3, 4, 3]
const CLOUD_ALPHA := [0.36, 0.34, 0.32, 0.30, 0.34, 0.36]
const CLOUD_TINT := [Color(0.0, 0.06, 0.02), Color(0.0, 0.05, 0.08), Color(0.03, 0.04, 0.07),
	Color(0.05, 0.03, 0.03), Color(0.03, 0.03, 0.05), Color(0.05, 0.03, 0.04)]

## Per-sector air: kind -> {n, size, vel (px/s), par (camera share), col, twinkle, wob}.
## Soft fx_softspot sparkles; pale/cool tints only, never the lethal red/amber band.
const AIR := [
	[{"n": 18, "size": Vector2(8, 8), "vel": Vector2(9, -6), "par": 0.9, "wob": 6.0, "tw": true,
		"col": Color(1.0, 0.98, 0.8, 0.8)}],                                           # S1 pollen
	[{"n": 14, "size": Vector2(10, 10), "vel": Vector2(6, -4), "par": 0.9, "wob": 10.0, "tw": true,
		"col": Color(0.78, 1.0, 0.7, 0.85)},                                             # S2 fireflies
	 {"n": 4, "size": Vector2(130, 30), "vel": Vector2(8, 0), "par": 0.8, "wob": 0.0, "tw": false,
		"col": Color(0.85, 0.93, 0.95, 0.12)}],                                          # S2 low mist
	[{"n": 12, "size": Vector2(34, 3), "vel": Vector2(240, 18), "par": 0.2, "wob": 0.0, "tw": false,
		"col": Color(0.92, 0.88, 0.8, 0.32), "moving": true},                            # S3 wind dust streaks
	 {"n": 6, "size": Vector2(90, 40), "vel": Vector2(70, 8), "par": 0.4, "wob": 0.0, "tw": false,
		"col": Color(0.85, 0.8, 0.72, 0.14)}],                                           # S3 dust puffs
	[{"n": 14, "size": Vector2(9, 9), "vel": Vector2(6, -34), "par": 0.8, "wob": 6.0, "tw": true,
		"col": Color(1.0, 0.94, 0.84, 0.85)},                                              # S4 sparks
	 {"n": 4, "size": Vector2(80, 70), "vel": Vector2(5, -12), "par": 0.9, "wob": 0.0, "tw": false,
		"col": Color(0.2, 0.2, 0.22, 0.22)}],                                            # S4 smoke
	[{"n": 22, "size": Vector2(7, 7), "vel": Vector2(-8, 26), "par": 0.7, "wob": 7.0, "tw": false,
		"col": Color(0.86, 0.84, 0.82, 0.8)},                                             # S5 ash fall
	 {"n": 4, "size": Vector2(100, 70), "vel": Vector2(6, -6), "par": 0.9, "wob": 0.0, "tw": false,
		"col": Color(0.18, 0.18, 0.2, 0.22)}],                                           # S5 smoke
	[{"n": 20, "size": Vector2(10, 10), "vel": Vector2(5, -46), "par": 0.8, "wob": 8.0, "tw": true,
		"col": Color(0.96, 0.9, 0.82, 0.9)},                                            # S6 rising embers
	 {"n": 4, "size": Vector2(110, 80), "vel": Vector2(6, -10), "par": 0.9, "wob": 0.0, "tw": false,
		"col": Color(0.15, 0.14, 0.16, 0.24)}],                                          # S6 smoke
]

## Heat shimmer: wavy pale ribbons, only the forge sectors (S4 and S6) call for them.
const SHIMMER := {3: {"n": 6, "alpha": 0.11}, 5: {"n": 7, "alpha": 0.14}}

## Light shafts: dawn jungle, marsh haze and the bridge's open sky call for them.
## Soft stepped width, fading in from the top (clear of the HUD) and out toward the bottom.
const SHAFTS := {
	0: {"n": 4, "alpha": 0.20, "tint": Color(1.0, 0.97, 0.82)},
	1: {"n": 3, "alpha": 0.13, "tint": Color(0.82, 0.92, 0.95)},
	2: {"n": 3, "alpha": 0.12, "tint": Color(0.95, 0.94, 0.88)},
}
const SHAFT_TOP_Y := 36.0   ## below the HUD band

## Vignette tint/strength per sector; the shared ui_vignette card is clear in the centre half.
const VIGNETTE := [Color(0.0, 0.05, 0.02, 0.7), Color(0.0, 0.05, 0.07, 0.7),
	Color(0.04, 0.04, 0.05, 0.6), Color(0.05, 0.03, 0.03, 0.66),
	Color(0.03, 0.03, 0.04, 0.7), Color(0.05, 0.02, 0.03, 0.72)]


static func _sec(sector: int) -> int:
	return clampi(sector, 0, SECTORS - 1)


static func _time(frames: int, motion: float) -> float:
	return 0.0 if motion < 0.5 else float(frames) / 60.0


static func vignette_color(sector: int) -> Color:
	return VIGNETTE[_sec(sector)]


## Cloud-shadow ops (tex rects), culled to the viewport.
static func plan_clouds(sector: int, frames: int, motion: float, cam_px: float) -> Array:
	var s := _sec(sector)
	var ops: Array = []
	var t := _time(frames, motion)
	var size: Vector2 = CLOUD["size"]
	var vel: Vector2 = CLOUD["vel"]
	var span_x := W + size.x * 2.0
	var span_y := H + size.y * 2.0
	var tint: Color = CLOUD_TINT[s]
	for i in int(CLOUD_COUNT[s]):
		var h1 := Art.cell_hash(i * 13 + 91, s + 7)
		var h2 := Art.cell_hash(i * 29 + 5, s * 3 + 11)
		var u := float(h1 % 1000) / 1000.0
		var v := float(h2 % 1000) / 1000.0
		var spd := 0.7 + float((h1 / 1000) % 4) * 0.2
		var x := fposmod(u * span_x + vel.x * t * spd, span_x) - size.x
		var y := fposmod(v * span_y + vel.y * t * spd - cam_px * float(CLOUD["par"]), span_y) - size.y
		var r := Rect2(Vector2(x, y).round(), size)
		if r.end.x <= 0.0 or r.position.x >= W or r.end.y <= 0.0 or r.position.y >= H:
			continue
		ops.append({"k": "cloudbank", "tex": true, "r": r,
			"c": Color(tint.r, tint.g, tint.b, float(CLOUD_ALPHA[s]))})
	return ops


## Sector air (tex rects): pollen, fireflies, dust, sparks, ash, embers, smoke banks. Frozen
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


## Heat-shimmer ribbons as wobbling polylines: [{"pts": PackedVector2Array, "c": Color}].
static func plan_shimmer(sector: int, frames: int, motion: float) -> Array:
	var s := _sec(sector)
	var out: Array = []
	if not SHIMMER.has(s):
		return out
	var def: Dictionary = SHIMMER[s]
	var t := _time(frames, motion)
	var n := int(def["n"])
	for i in n:
		var h := Art.cell_hash(i * 23 + 5, s + 41)
		var y0 := 60.0 + (float(i) + 0.5) * (H - 90.0) / float(n) + float(h % 14) - 7.0
		var x0 := float(h / 16 % 200) - 40.0
		var len := 190.0 + float(h % 120)
		var pts := PackedVector2Array()
		for j in 9:
			var fx := float(j) / 8.0
			pts.append(Vector2(x0 + fx * len, y0 + sin(fx * 7.0 + t * 1.6 + float(i)) * 3.0))
		out.append({"pts": pts, "c": Color(1.0, 0.97, 0.9, float(def["alpha"]) * (0.6 + 0.4 * sin(t * 0.9 + float(i) * 1.9)))})
	return out


## Light shafts as three nested fading parallelograms (soft edge): {"pts", "cols"}.
## Empty for sectors that do not call for them. Alpha is 0 at the top (clear of the HUD) and bottom.
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
	for i in n:
		var h := Art.cell_hash(i * 19 + 77, s + 29)
		var x0 := 120.0 + float(i) * (W - 160.0) / float(maxi(n - 1, 1)) + float(h % 40) - 20.0
		x0 += sin(t * 0.12 + float(i) * 1.7) * 14.0
		var wid := 34.0 + float((h / 64) % 22)
		var breathe := 0.75 + 0.25 * sin(t * 0.35 + float(i) * 2.1)
		for layer in 3:
			var w := wid * (1.0 - float(layer) * 0.34)
			var a := float(def["alpha"]) * breathe * 0.5
			var c0 := Color(tint.r, tint.g, tint.b, 0.0)
			var c1 := Color(tint.r, tint.g, tint.b, a)
			var xm := x0 - slant * (ym - SHAFT_TOP_Y) / (y1 - SHAFT_TOP_Y)
			var xb := x0 - slant
			out.append({
				"pts": PackedVector2Array([Vector2(x0, SHAFT_TOP_Y), Vector2(x0 + w, SHAFT_TOP_Y),
					Vector2(xm + w, ym), Vector2(xb + w, y1), Vector2(xb, y1), Vector2(xm, ym)]),
				"cols": PackedColorArray([c0, c0, c1, c0, c0, c1])})
	return out


## Everything laid down under the actors (called from main._draw_atmosphere_ground).
static func draw_ground(ci: CanvasItem, sector: int, frames: int, motion: float, cam_px: float) -> void:
	if not Atmosphere.enabled:
		return
	Atmosphere.draw(ci, plan_clouds(sector, frames, motion, cam_px))
	for sh in plan_shafts(sector, frames, motion):
		ci.draw_polygon(sh["pts"], sh["cols"])
	for rb in plan_shimmer(sector, frames, motion):
		ci.draw_polyline(rb["pts"], rb["c"], 2.0)
	Atmosphere.draw(ci, plan_air(sector, frames, motion, cam_px))


## Screen-space edge vignette. The caller has already cancelled the shake transform.
static func draw_vignette(ci: CanvasItem, sector: int) -> void:
	if not Atmosphere.enabled:
		return
	ci.draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, W, H), false, vignette_color(sector))
