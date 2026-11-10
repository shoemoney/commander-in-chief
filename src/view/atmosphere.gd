class_name Atmosphere
extends RefCounted
## Per-sector weather and drifting light. VIEW ONLY: no sim state, no engine RNG,
## no Time.* -- every particle is a pure function of (sector, frame, motion, camera),
## so a screenshot taken at a fixed frame is byte-reproducible.
##
## Split into a pure PLANNER (plan() -> Array of ops, measurable with no draw
## context) and a thin painter (draw()). Three layers:
##   UNDER  slow cloud-shadow blotches over the ground, below every actor
##   MID    ground-level air: mist, fog, rain, dust, smoke, ash, sparks, embers
##   OVER   a handful of faint foreground specks above the actors
## Colours obey the readability contract: either near-grey (low saturation) or
## cool blue. Never the lethal red/amber band that bullets, mines and role rims
## own. Alpha is capped (MAX_ALPHA) and the whole frame is budgeted to MAX_OPS
## draw calls, culled to the viewport.

enum Layer { UNDER, MID, OVER }

const W := 640.0
const H := 360.0
const MAX_OPS := 36        ## + the 3 legacy ember flecks in main = ~40 draws/frame
const MAX_ALPHA := 0.6
const SECTORS := 6

## kind -> geometry/motion. size is the drawn size in px; vel is px/second;
## par is the share of camera scroll the particle follows (1 = pinned to ground).
## tex = stretched fx_softspot card, otherwise a plain rect.
const KINDS := {
	"cloud": {"layer": Layer.UNDER, "tex": true, "size": Vector2(190, 100), "vel": Vector2(9, 3),
		"par": 0.55, "col": Color(0.02, 0.04, 0.08, 0.13)},
	"mist": {"layer": Layer.MID, "tex": true, "size": Vector2(150, 26), "vel": Vector2(10, -1),
		"par": 0.8, "col": Color(0.88, 0.92, 0.95, 0.10)},
	"fog": {"layer": Layer.MID, "tex": true, "size": Vector2(230, 46), "vel": Vector2(6, 0),
		"par": 0.9, "col": Color(0.72, 0.8, 0.78, 0.11)},
	"smoke": {"layer": Layer.MID, "tex": true, "size": Vector2(70, 60), "vel": Vector2(8, -14),
		"par": 0.9, "col": Color(0.3, 0.3, 0.32, 0.2)},
	"shimmer": {"layer": Layer.MID, "tex": false, "size": Vector2(70, 1), "vel": Vector2(4, 0),
		"par": 1.0, "col": Color(1.0, 1.0, 1.0, 0.045), "wobble": 3.0},
	"mote": {"layer": Layer.MID, "tex": false, "size": Vector2(1, 1), "vel": Vector2(7, -5),
		"par": 0.9, "col": Color(0.92, 0.9, 0.78, 0.40), "twinkle": true},
	"insect": {"layer": Layer.MID, "tex": false, "size": Vector2(1, 1), "vel": Vector2(14, 6),
		"par": 0.9, "col": Color(0.14, 0.14, 0.13, 0.50), "wobble": 9.0},
	"rain": {"layer": Layer.MID, "tex": false, "size": Vector2(1, 5), "vel": Vector2(-18, 240),
		"par": 0.0, "col": Color(0.75, 0.82, 0.9, 0.22), "motion_only": true},
	"dust": {"layer": Layer.MID, "tex": false, "size": Vector2(13, 1), "vel": Vector2(210, 14),
		"par": 0.2, "col": Color(0.82, 0.78, 0.7, 0.20), "motion_only": true},
	"ash": {"layer": Layer.MID, "tex": false, "size": Vector2(2, 2), "vel": Vector2(-9, 22),
		"par": 0.7, "col": Color(0.7, 0.68, 0.66, 0.42), "twinkle": true},
	"spark": {"layer": Layer.MID, "tex": false, "size": Vector2(1, 1), "vel": Vector2(5, -60),
		"par": 0.8, "col": Color(0.95, 0.88, 0.78, 0.55), "fade": true, "motion_only": true},
	"ember": {"layer": Layer.MID, "tex": false, "size": Vector2(2, 2), "vel": Vector2(4, -52),
		"par": 0.8, "col": Color(0.85, 0.78, 0.7, 0.6), "fade": true},
	"fg_mote": {"layer": Layer.OVER, "tex": true, "size": Vector2(5, 5), "vel": Vector2(16, -9),
		"par": 1.3, "col": Color(0.94, 0.92, 0.82, 0.10), "motion_only": true},
	"fg_drop": {"layer": Layer.OVER, "tex": false, "size": Vector2(1, 4), "vel": Vector2(-30, 320),
		"par": 1.3, "col": Color(0.8, 0.86, 0.92, 0.12), "motion_only": true},
	"fg_dust": {"layer": Layer.OVER, "tex": false, "size": Vector2(18, 1), "vel": Vector2(340, 20),
		"par": 1.3, "col": Color(0.85, 0.8, 0.72, 0.10), "motion_only": true},
	"fg_ash": {"layer": Layer.OVER, "tex": true, "size": Vector2(4, 4), "vel": Vector2(-14, 34),
		"par": 1.3, "col": Color(0.66, 0.64, 0.62, 0.12), "motion_only": true},
}

## sector -> {kind: count}. Totals stay under MAX_OPS (asserted by the tests).
const PROFILES := [
	{"cloud": 2, "mist": 5, "mote": 10, "fg_mote": 3},                       # S1 dawn mist + pollen
	{"cloud": 2, "fog": 5, "rain": 9, "insect": 6, "fg_drop": 3},            # S2 marsh fog + rain
	{"cloud": 2, "dust": 13, "mist": 3, "fg_dust": 3},                       # S3 wind-driven bridge dust
	{"cloud": 1, "shimmer": 6, "smoke": 5, "spark": 8, "fg_ash": 3},         # S4 heat, smoke, sparks
	{"smoke": 7, "ash": 16, "fg_ash": 3},                                    # S5 smoke + falling ash
	{"smoke": 4, "ember": 14, "ash": 5, "fg_ash": 3},                        # S6 embers intensified
]


## The atmosphere a run is breathing. Campaign/arcade: the sector march (0..1) that
## already drives the ground palette; Endless: the wave tier.
static func sector_for(march: float, endless: bool, wave: int) -> int:
	if endless:
		return clampi(wave / 2, 0, SECTORS - 1)
	return clampi(roundi(march * 5.0), 0, SECTORS - 1)


static func _wrap(v: float, span: float) -> float:
	return fposmod(v, span)


## Pure planner. cam_px is the world scroll in screen px (camera_top * PX).
## motion < 0.5 (reduce-motion) freezes time and drops every kind that only
## reads as weather when it moves (rain, streaks, sparks, foreground specks).
static func plan(sector: int, frames: int, motion: float, cam_px: float, layer: int) -> Array:
	var ops: Array = []
	var prof: Dictionary = PROFILES[clampi(sector, 0, SECTORS - 1)]
	var calm := motion < 0.5
	var t := 0.0 if calm else float(frames) / 60.0
	var kind_id := 0
	for kind in prof:
		kind_id += 1
		var def: Dictionary = KINDS[kind]
		if def["layer"] != layer:
			continue
		if calm and def.get("motion_only", false):
			continue
		var size: Vector2 = def["size"]
		var vel: Vector2 = def["vel"]
		var span_x := W + size.x * 2.0
		var span_y := H + size.y * 2.0 + 40.0
		for i in int(prof[kind]):
			var h1 := Art.cell_hash(i * 31 + kind_id, sector + 1)
			var h2 := Art.cell_hash(i * 17 + 3, kind_id * 5 + sector)
			var u := float(h1 % 1000) / 1000.0
			var v := float(h2 % 1000) / 1000.0
			var spd := 0.6 + float((h1 / 1000) % 5) * 0.2
			var x := _wrap(u * span_x + vel.x * t * spd, span_x) - size.x
			var y := _wrap(v * span_y + vel.y * t * spd - cam_px * float(def["par"]), span_y) - size.y - 20.0
			var wob: float = def.get("wobble", 0.0)
			if wob > 0.0:
				y += sin(t * 2.3 + float(h1 % 628) / 100.0) * wob
			var col: Color = def["col"]
			var a := col.a
			if def.get("twinkle", false):
				a *= 0.55 + 0.45 * sin(t * 3.1 + float(h2 % 628) / 100.0)
			if def.get("fade", false):
				a *= clampf(sin(PI * _wrap(v + t * 0.18 * spd, 1.0)), 0.0, 1.0)
			a = minf(a, MAX_ALPHA)
			var r := Rect2(Vector2(x, y).round(), size)
			if r.end.x <= 0.0 or r.position.x >= W or r.end.y <= 0.0 or r.position.y >= H:
				continue   # cull to the viewport
			if a < 0.01:
				continue
			ops.append({"k": kind, "tex": def["tex"], "r": r, "c": Color(col.r, col.g, col.b, a)})
			if ops.size() >= MAX_OPS:
				return ops
	return ops


## Capture tools that need a still frame turn the whole layer off here. The air is driven by
## Engine.get_physics_frames() like every other ambient view animation, so it keeps drifting
## while a tool holds the sim frozen — which is right for the game and wrong for a probe that
## compares two "identical" frames. plan() stays pure; only the painting is gated.
static var enabled := true


static func draw(ci: CanvasItem, ops: Array) -> void:
	if not enabled:
		return
	for op in ops:
		if op["tex"]:
			ci.draw_texture_rect(Art.tex("fx_softspot"), op["r"], false, op["c"])
		else:
			ci.draw_rect(op["r"], op["c"])
