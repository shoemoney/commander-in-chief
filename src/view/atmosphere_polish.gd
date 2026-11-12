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
const CLOUD := {"size": Vector2(300, 160), "vel": Vector2(6, 2.2), "par": 0.5}
const CLOUD_COUNT := [3, 2, 3, 2, 3, 2]
const CLOUD_ALPHA := [0.24, 0.22, 0.2, 0.19, 0.24, 0.26]
const CLOUD_TINT := [Color(0.0, 0.05, 0.02), Color(0.0, 0.05, 0.07), Color(0.04, 0.04, 0.05),
	Color(0.05, 0.03, 0.03), Color(0.03, 0.03, 0.04), Color(0.05, 0.03, 0.03)]

## Pollen / glint specks: sector -> count. Soft 5 px sparkles that twinkle.
const POLLEN_COUNT := [9, 0, 0, 0, 0, 0]
const POLLEN_COL := Color(1.0, 0.98, 0.84, 0.30)

## Light shafts: only the dawn jungle and the marsh haze call for them.
const SHAFTS := {
	0: {"n": 4, "alpha": 0.17, "tint": Color(1.0, 0.97, 0.82)},
	1: {"n": 3, "alpha": 0.09, "tint": Color(0.82, 0.92, 0.95)},
}

## Vignette tint/strength per sector; the shared ui_vignette card is clear in the centre half.
const VIGNETTE := [Color(0.0, 0.05, 0.02, 0.42), Color(0.0, 0.05, 0.07, 0.42),
	Color(0.05, 0.04, 0.03, 0.3), Color(0.05, 0.03, 0.03, 0.34),
	Color(0.03, 0.03, 0.04, 0.38), Color(0.05, 0.02, 0.03, 0.42)]


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


## Pollen glints (tex rects), riding the camera at 0.9 parallax. Under reduce-motion they hang still.
static func plan_pollen(sector: int, frames: int, motion: float, cam_px: float) -> Array:
	var s := _sec(sector)
	var ops: Array = []
	var t := _time(frames, motion)
	var span_x := W + 20.0
	var span_y := H + 20.0
	for i in int(POLLEN_COUNT[s]):
		var h1 := Art.cell_hash(i * 7 + 401, s + 3)
		var h2 := Art.cell_hash(i * 11 + 13, s * 5 + 17)
		var u := float(h1 % 1000) / 1000.0
		var v := float(h2 % 1000) / 1000.0
		var x := fposmod(u * span_x + 9.0 * t * (0.6 + float((h1 / 1000) % 4) * 0.2), span_x) - 10.0
		var y := fposmod(v * span_y - 6.0 * t - cam_px * 0.9 + sin(t * 1.3 + float(h1 % 628) / 100.0) * 5.0, span_y) - 10.0
		var a := POLLEN_COL.a * (0.5 + 0.5 * sin(t * 2.2 + float(h2 % 628) / 100.0))
		if motion < 0.5:
			a = POLLEN_COL.a * 0.6
		var r := Rect2(Vector2(x, y).round(), Vector2(5, 5))
		if r.end.x <= 0.0 or r.position.x >= W or r.end.y <= 0.0 or r.position.y >= H:
			continue
		ops.append({"k": "pollen", "tex": true, "r": r, "c": Color(POLLEN_COL.r, POLLEN_COL.g, POLLEN_COL.b, a)})
	return ops


## Light shafts as fading parallelograms: {"pts": PackedVector2Array, "cols": PackedColorArray}.
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
	for i in n:
		var h := Art.cell_hash(i * 19 + 77, s + 29)
		var x0 := 70.0 + float(i) * (W - 140.0) / float(maxi(n - 1, 1)) + float(h % 40) - 20.0
		x0 += sin(t * 0.12 + float(i) * 1.7) * 14.0
		var wid := 20.0 + float((h / 64) % 22)
		var slant := 190.0
		var breathe := 0.75 + 0.25 * sin(t * 0.35 + float(i) * 2.1)
		var a := float(def["alpha"]) * breathe
		var top := Color(tint.r, tint.g, tint.b, a)
		var bot := Color(tint.r, tint.g, tint.b, 0.0)
		out.append({
			"pts": PackedVector2Array([Vector2(x0, -4), Vector2(x0 + wid, -4),
				Vector2(x0 + wid - slant, H + 4), Vector2(x0 - slant - wid * 0.4, H + 4)]),
			"cols": PackedColorArray([top, top, bot, bot])})
	return out


## Everything laid down under the actors (called from main._draw_atmosphere_ground).
static func draw_ground(ci: CanvasItem, sector: int, frames: int, motion: float, cam_px: float) -> void:
	if not Atmosphere.enabled:
		return
	Atmosphere.draw(ci, plan_clouds(sector, frames, motion, cam_px))
	for sh in plan_shafts(sector, frames, motion):
		ci.draw_polygon(sh["pts"], sh["cols"])
	Atmosphere.draw(ci, plan_pollen(sector, frames, motion, cam_px))


## Screen-space edge vignette. The caller has already cancelled the shake transform.
static func draw_vignette(ci: CanvasItem, sector: int) -> void:
	if not Atmosphere.enabled:
		return
	ci.draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, W, H), false, vignette_color(sector))
