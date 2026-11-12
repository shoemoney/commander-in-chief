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


const _GEO_CAP := 64
const _UV_XF := Transform2D(Vector2(1.0 / 64.0, 0.0), Vector2(0.0, 1.0 / 64.0), Vector2.ZERO)
static var _geo: Dictionary = {}


static var _mud: Dictionary = {}
static var _notch: Dictionary = {}


static func clear_cache() -> void:
	_geo.clear()
	_mud.clear()
	_notch.clear()


static func cache_size() -> int:
	return _geo.size() + _mud.size() + _notch.size()


static func mud_plan(biome: int, seed: int, size: Vector2, soot: float) -> Dictionary:
	## GroundStructure.mud_bank_plan is a pure function of these four arguments but builds
	## 40 blob dictionaries; it was being rebuilt per band per frame. Keyed on all four.
	var key := [biome, seed, size, soot]
	var hit = _mud.get(key)
	if hit != null:
		return hit
	if _mud.size() >= _GEO_CAP:
		_mud.clear()
	var plan := GroundStructure.mud_bank_plan(biome, seed, size, soot)
	_mud[key] = plan
	return plan


static func notch_hashes(mseed: int) -> PackedInt64Array:
	## The 12 mud-lip notch hashes for a band seed (Art.cell_hash is pure), cached.
	var hit = _notch.get(mseed)
	if hit != null:
		return hit
	if _notch.size() >= _GEO_CAP:
		_notch.clear()
	var out := PackedInt64Array()
	for mk in 12:
		out.append(Art.cell_hash(mseed + mk * 31, mk))
	_notch[mseed] = out
	return out


static func band_geometry(phase: float, top: bool, wh: float, bank_base: float,
		amp: Vector2, freq: Vector2, bank_col: Color) -> Dictionary:
	## The camera-independent half of one shore, built ONCE and reused every frame. Everything
	## is local to the shore's own edge (top: y = 0 is the band top; bottom: y = 0 is the band bottom); the caller translates by that edge's
	## screen y with a C++ Transform2D * PackedVector2Array. Pure function of its arguments
	## (the key holds every one of them, `bank_col` through the wet tint), so there is nothing
	## to go stale across run restarts or sector changes; the cap just bounds memory.
	## Returns {"shore", "dry" (the two halves of the sand polygon), "wet_pts", "wet_cols"}.
	var tint := wet_tint(bank_col)
	var key := [phase, top, wh, bank_base, amp, freq, bank_col]
	var hit = _geo.get(key)
	if hit != null:
		return hit
	if _geo.size() >= _GEO_CAP:
		_geo.clear()
	var shore := shore_points(0.0, 0.0, phase, top, amp, freq)
	var poly := PackedVector2Array(shore)
	var dry := PackedVector2Array()   # the dry edge, y = 0: the caller translates it by its own exact y
	for s in range(SHORE_STEPS, -1, -1):
		dry.append(Vector2(float(s) / float(SHORE_STEPS) * 640.0, 0.0))
	var wet := wet_strip(shore, top, phase, tint)
	# Godot ear-clips every draw_colored_polygon / draw_polygon on the CPU, every frame
	# (O(n^2) on 258 points). Triangulation is translation invariant, so do it ONCE here
	# and submit the indexed triangles directly (paint_shore).
	var whole := PackedVector2Array(shore)   # dry edge at its true offset from the shore, else the polygon self-intersects
	for dp in dry:
		whole.append(Vector2(dp.x, -bank_base if top else bank_base))
	var sand_cols := PackedColorArray()
	sand_cols.resize(whole.size())
	sand_cols.fill(bank_col)
	var geo := {"shore": shore, "dry": dry, "wet_pts": wet["pts"], "wet_cols": wet["cols"],
		"sand_idx": Geometry2D.triangulate_polygon(whole), "sand_cols": sand_cols,
		"wet_idx": Geometry2D.triangulate_polygon(wet["pts"])}
	_geo[key] = geo
	return geo


static func paint_shore(canvas: CanvasItem, geo: Dictionary, shore_y: float, dry_y: float,
		sand: Texture2D) -> void:
	## One shore's sand polygon (sand-textured, bank_col modulated) and its wet-sand strip,
	## from the cached geometry: translate by the two exact screen ys, submit pre-triangulated.
	## Same canvas commands draw_colored_polygon / draw_polygon would record, minus the ear-clip.
	var pts: PackedVector2Array = Transform2D(0.0, Vector2(0.0, shore_y)) * geo["shore"]
	pts.append_array(Transform2D(0.0, Vector2(0.0, dry_y)) * geo["dry"])
	var ci := canvas.get_canvas_item()
	if not geo["sand_idx"].is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, geo["sand_idx"], pts, geo["sand_cols"],
			uv_of(pts), PackedInt32Array(), PackedFloat32Array(), sand.get_rid())
	if not geo["wet_idx"].is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, geo["wet_idx"],
			Transform2D(0.0, Vector2(0.0, shore_y)) * geo["wet_pts"], geo["wet_cols"])


static func uv_of(world_pts: PackedVector2Array) -> PackedVector2Array:
	## Sand-texture UVs for a polygon already in screen space: pos / 64 (exact, a power of 2).
	return _UV_XF * world_pts
