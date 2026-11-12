class_name WaterPolish
extends RefCounted
## View-only river polish helpers (nothing here touches the sim).
##
## The water body itself is water.gdshader; this module owns the geometry the shader
## cannot draw because it sits ON TOP of the shader quad: the irregular shoreline the
## sand bank is cut from, and the wet-sand band between bank and water.

const SHORE_STEPS := 128                  # sand polygon samples across 640px (5px apart)
const JIT_AMP := Vector2(1.1, 0.6)        # px; must equal the literals in water.gdshader
const JIT_FREQ := Vector2(41.0, 63.0)     # rad across the screen width; ditto
const JIT_PHASE := Vector2(3.1, 5.3)      # phase multipliers; ditto
const MAX_JITTER := JIT_AMP.x + JIT_AMP.y


static func bank_jitter(u: float, phase: float, top: bool) -> float:
	## The high-frequency, per-band-phased irregularity both the shader's waterline and
	## the sand polygon's edge add on top of the two slow sines. Static in time on
	## purpose: the sand cannot animate, so the water edge must not either.
	var ph := phase + (0.0 if top else 2.1)
	return JIT_AMP.x * sin(u * JIT_FREQ.x + ph * JIT_PHASE.x) \
		+ JIT_AMP.y * sin(u * JIT_FREQ.y + ph * JIT_PHASE.y)


static func shore_offset(u: float, phase: float, top: bool, amp: Vector2, freq: Vector2) -> float:
	## Full px displacement of a shore INTO the band (same convention as
	## Main._bank_offset, plus the jitter). Bounded by amp.x + amp.y + MAX_JITTER.
	var ph := phase + (0.0 if top else 2.1)
	return amp.x * sin(u * freq.x + ph) + amp.y * sin(u * freq.y + ph * 1.7) \
		+ bank_jitter(u, phase, top)


static func surge_halfw(band_idx: int) -> float:
	## UV half-width of the real crossing, pushed so the shader can paint the flood wash
	## over exactly the span the sim wades you through while the ford is closed.
	return float(SimWorld.ford_half_w(band_idx)) / float(Fixed.ONE) / 640.0


static func shore_points(wy: float, wh: float, phase: float, top: bool,
		amp: Vector2, freq: Vector2) -> PackedVector2Array:
	## Waterline polyline across the screen for one shore, SHORE_STEPS + 1 points.
	var pts := PackedVector2Array()
	for s in SHORE_STEPS + 1:
		var u := float(s) / float(SHORE_STEPS)
		var off := shore_offset(u, phase, top, amp, freq)
		pts.append(Vector2(u * 640.0, (wy + off) if top else (wy + wh - off)))
	return pts


static func wet_width(u: float, phase: float) -> float:
	## How far (px) the damp band reaches up the bank at u. Irregular: tongues of wet sand
	## where the water has recently washed further up.
	return 3.0 + 2.6 * (0.5 + 0.5 * sin(u * 23.0 + phase * 2.3)) \
		+ 1.6 * (0.5 + 0.5 * sin(u * 57.0 + phase * 4.1 + 1.3))


static func wet_strip(edge: PackedVector2Array, top: bool, phase: float, tint: Color) -> Dictionary:
	## A vertex-coloured strip along `edge` reaching onto the DRY side: dark damp sand at
	## the waterline fading to nothing. Returns {"pts": PackedVector2Array,
	## "cols": PackedColorArray} ready for draw_polygon, or empty arrays for a bad edge.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := edge.size()
	if n < 2:
		return {"pts": pts, "cols": cols}
	var near := Color(tint.r, tint.g, tint.b, 0.62)
	var far := Color(tint.r, tint.g, tint.b, 0.0)
	for i in n:
		pts.append(edge[i])
		cols.append(near)
	for i in range(n - 1, -1, -1):
		var u := edge[i].x / 640.0
		var w := wet_width(u, phase)
		pts.append(edge[i] + Vector2(0.0, -w if top else w))
		cols.append(far)
	return {"pts": pts, "cols": cols}


static func wet_tint(bank_col: Color) -> Color:
	## Damp sand: the bank colour pushed darker and slightly cooler/greener.
	var d := bank_col.darkened(0.55)
	return Color(d.r * 0.92, d.g * 0.98, d.b * 1.02, 1.0)
