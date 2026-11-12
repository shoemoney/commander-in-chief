class_name GroundPolish
extends RefCounted
## VIEW-ONLY ground richness: a structured macro tone field plus per-biome micro-detail
## (grass tufts, pebbles, cracks, grit) stamped on a world-anchored hash grid.
##
## Everything is a pure function of (camera y, biome lookup, lane anchors) and Art.cell_hash,
## so it scrolls with the world, never shimmers and never touches the sim. All marks are
## low-alpha FLAT paint kept calmer than any unit: the ground is texture, never cover.
##
## Cost: two cached textures built once (a 64px noise field and a 40x40 stamp atlas),
## then roughly 4 tone quads and ~150 same-texture stamp draws per frame.

enum Kind { TUFT, PEBBLE, CRACK, SPECK }

const CELL_PX := 26.0            # stamp grid pitch (world px); shares no period with 64/96/40/48/80
const COLS := 26                 # 26 * 26 = 676 >= 640 plus overscan
const ROWS := 16
const STAMP := 10                # atlas cell size (px)
const VARIANTS := 4
const TONE_SRC := 64             # periodic noise lattice resolution
const TONE_TEX := 256            # texture size (drawn at 2x => 512px world period)
const TONE_PERIOD := 512.0
const TONE_ALPHA := 0.46         # global multiplier on the baked tone alpha
const STAMP_ALPHA_CAP := 0.5     # nothing on the ground is louder than this
const TRACK_STEP := 6.0
const TRACK_RIM_A := 0.36        # worn ground, not a wall: well under sandbag contrast
const TRACK_LIP_A := 0.30
const TRACK_RIM_W := 2.0

static var _atlas: Texture2D = null
static var _tone: Texture2D = null
static var last_stamp_count := 0   # probe: stamps drawn by the last paint()
static var _patches_installed := false
static var plan_builds := 0        # probe/test: how many times the cached layer was (re)built
static var _layer_key: Array = []
static var _layer: Dictionary = {}


static func _h(a: int, b: int) -> int:
	return Art.cell_hash(a, b)


# --- palette ---------------------------------------------------------------------------

## [tuft, pebble, crack, speck] colours of a biome (1 jungle .. 6 slag). The atlas greys
## shade them, so each colour is the LIT value; the body lands darker. Alpha is the stamp's
## base opacity.
static func palette(biome: int) -> Array:
	match biome:
		2: return [Color(0.46, 0.55, 0.30, 0.50), Color(0.55, 0.55, 0.46, 0.45), Color(0.10, 0.12, 0.07, 0.40), Color(0.60, 0.66, 0.50, 0.28)]
		3: return [Color(0.50, 0.50, 0.44, 0.30), Color(0.62, 0.60, 0.55, 0.42), Color(0.07, 0.07, 0.06, 0.50), Color(0.70, 0.68, 0.62, 0.22)]
		4: return [Color(0.56, 0.50, 0.36, 0.45), Color(0.68, 0.62, 0.52, 0.50), Color(0.12, 0.10, 0.07, 0.40), Color(0.74, 0.68, 0.56, 0.30)]
		5: return [Color(0.40, 0.40, 0.42, 0.28), Color(0.56, 0.56, 0.60, 0.42), Color(0.02, 0.02, 0.03, 0.50), Color(0.62, 0.62, 0.66, 0.25)]
		6: return [Color(0.36, 0.26, 0.22, 0.30), Color(0.52, 0.40, 0.34, 0.45), Color(0.80, 0.34, 0.14, 0.34), Color(0.58, 0.42, 0.34, 0.25)]
		_: return [Color(0.50, 0.62, 0.30, 0.50), Color(0.66, 0.62, 0.50, 0.50), Color(0.14, 0.10, 0.05, 0.38), Color(0.78, 0.74, 0.46, 0.34)]


## Per-biome stamp mix: [tuft, pebble, crack] weights out of 100 (the rest is speck) and the
## chance (out of 100) that a grid cell carries a stamp at all.
static func mix(biome: int) -> Array:
	match biome:
		2: return [40, 8, 0, 62]
		3: return [0, 14, 46, 52]
		4: return [3, 54, 6, 58]
		5: return [0, 20, 46, 50]
		6: return [0, 24, 38, 54]
		_: return [46, 14, 0, 64]


# --- cached textures -------------------------------------------------------------------

static func atlas_image() -> Image:
	var img := Image.create_empty(STAMP * VARIANTS, STAMP * 4, false, Image.FORMAT_RGBA8)
	for v in VARIANTS:
		_stamp_tuft(img, v)
		_stamp_pebble(img, v)
		_stamp_crack(img, v)
		_stamp_speck(img, v)
	return img


static func _px(img: Image, ox: int, oy: int, x: int, y: int, g: float, a: float) -> void:
	if x < 0 or y < 0 or x >= STAMP or y >= STAMP:
		return
	img.set_pixel(ox + x, oy + y, Color(g, g, g, a))


static func _stamp_tuft(img: Image, v: int) -> void:
	var ox := v * STAMP
	var oy := int(Kind.TUFT) * STAMP
	var blades := 3 + v % 3
	for b in blades:
		var hb := _h(v * 13 + b, 901)
		var lean := float((hb % 5) - 2) * 0.35
		var length := 4 + (hb >> 3) % 4
		var bx := 3.0 + float(b) * (4.0 / float(blades)) + float(hb % 3) * 0.3
		for s in length:
			var f := float(s) / float(length)
			var x := int(round(bx + lean * f * float(length) * 0.5))
			var y := 9 - s
			_px(img, ox, oy, x, y, lerpf(0.5, 1.0, f), 1.0)
	_px(img, ox, oy, 3, 9, 0.35, 0.8)   # the tuft's own dark root
	_px(img, ox, oy, 5, 9, 0.35, 0.8)
	_px(img, ox, oy, 4, 9, 0.3, 0.9)


static func _stamp_pebble(img: Image, v: int) -> void:
	var ox := v * STAMP
	var oy := int(Kind.PEBBLE) * STAMP
	var w := 3 + v % 2
	var hgt := 2 + (v / 2) % 2
	var x0 := 3
	var y0 := 4
	for y in hgt:
		for x in w:
			var g := 0.66
			if x == 0 and y == 0 or (y == 0 and x < w - 1):
				g = 1.0                      # lit top-left
			elif y == hgt - 1 or x == w - 1:
				g = 0.38                      # shaded lower-right
			_px(img, ox, oy, x0 + x, y0 + y, g, 1.0)
	for x in w:
		_px(img, ox, oy, x0 + x + 1, y0 + hgt, 0.15, 0.55)   # contact shadow
	if v >= 2:   # a second small pebble beside the first
		_px(img, ox, oy, 7, 7, 0.9, 1.0)
		_px(img, ox, oy, 8, 7, 0.45, 1.0)


static func _stamp_crack(img: Image, v: int) -> void:
	var ox := v * STAMP
	var oy := int(Kind.CRACK) * STAMP
	var x := 0
	var y := 2 + v % 4
	var step := 0
	while x < STAMP - 1 and step < 12:
		var hc := _h(v * 7 + step, 902)
		_px(img, ox, oy, x, y, 0.25, 1.0)
		_px(img, ox, oy, x, y + 1, 0.9, 0.35)   # pale lip under the groove
		x += 1
		var d := (hc % 3) - 1
		y = clampi(y + d, 1, STAMP - 3)
		if hc % 5 == 0 and x < STAMP - 2:   # a short branch
			_px(img, ox, oy, x, clampi(y + 1, 0, STAMP - 2), 0.3, 0.9)
		step += 1


static func _stamp_speck(img: Image, v: int) -> void:
	var ox := v * STAMP
	var oy := int(Kind.SPECK) * STAMP
	for i in 2 + v % 3:
		var hs := _h(v * 5 + i, 903)
		_px(img, ox, oy, 1 + hs % 8, 1 + (hs >> 4) % 8, 1.0 if i % 2 == 0 else 0.45, 1.0)


## Replacement for the grey dressing-patch atlas (the "lens dirt" smudges): earthy, ragged-edged
## bare-earth patches with grain and a darker core, 4 variants in a 2x2 grid of 128px cells.
## `wet` leans olive-brown (jungle/marsh); dry leans tan. Alpha is deliberately modest.
static func patch_image(wet: bool) -> Image:
	var out := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	var base := Color(0.86, 0.74, 0.42) if wet else Color(0.90, 0.78, 0.56)
	var dark := Color(0.62, 0.52, 0.30) if wet else Color(0.70, 0.58, 0.40)
	for v in 4:
		var o := Vector2i((v % 2) * 128, (v / 2) * 128)
		var ph := float(_h(v, 4411) % 628) / 100.0
		for y in 128:
			for x in 128:
				var u := (float(x) + 0.5 - 64.0) / 64.0
				var w := (float(y) + 0.5 - 64.0) / 64.0
				var d := sqrt(u * u + w * w)
				var th := atan2(w, u)
				var rb := 0.84 + 0.035 * sin(3.0 * th + ph) + 0.02 * sin(7.0 * th + ph * 2.0) \
					+ 0.015 * sin(11.0 * th + ph * 3.0)
				var grain := float(_h(x + v * 131, y * 3 + 17) % 100) / 100.0
				var edge := 1.0 - smoothstep(rb - 0.55, rb, d)
				if edge <= 0.0:
					continue
				var core := 1.0 - smoothstep(0.0, rb, d)
				var c := base.lerp(dark, core * (0.35 + grain * 0.65))
				if grain > 0.94:
					c = c.lightened(0.22)   # a pebble fleck
				out.set_pixel(o.x + x, o.y + y, Color(c.r, c.g, c.b, edge))
	return out


## Put the calmed patch atlas in the shared cache so ground_dressing_tex() serves it. Only when
## the cache is still empty (it is a lazy static), so tests that already built the stock one keep it.
static func install_patches(cache: Array) -> void:
	if _patches_installed:
		return
	_patches_installed = true
	cache.clear()
	cache.append(ImageTexture.create_from_image(patch_image(false)))
	cache.append(ImageTexture.create_from_image(patch_image(true)))


## The worn track: a faint ragged rim, a pale lip just inside it, a packed-earth centre and two
## wheel ruts. Worn ground, never a wall: every edge stays at or under 0.4 alpha and 2px, so
## sandbags and cover are always the louder thing on the field. World-anchored (rows are 6px of
## world y). `water_fn(sx, sy)` skips rows that sit in a river.
static func paint_track(canvas: CanvasItem, cam_y: float, anc: Array, biome: int, water_fn: Callable) -> void:
	if anc.is_empty():
		return
	var wy0 := floorf(cam_y / TRACK_STEP) * TRACK_STEP
	var runs := track_runs(wy0, int(ceil(360.0 / TRACK_STEP)) + 2, anc,
		func(cx: float, wy: float) -> bool: return water_fn.call(cx, wy - cam_y))
	canvas.draw_set_transform(Vector2(0.0, -cam_y), 0.0, Vector2.ONE)
	draw_track_runs(canvas, runs, biome)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Runs of consecutive dry rows in WORLD coordinates: [L, R, innerL, innerR, rutL, rutR] each.
## `skip_fn(cx, wy) -> bool` breaks the track (a river band, however the ford column is treated).
static func track_runs(wy0: float, rows: int, anc: Array, skip_fn: Callable) -> Array:
	var segs: Array = []
	var pts: Array[PackedVector2Array] = _blank_run()
	for i in rows:
		var wy := wy0 + float(i) * TRACK_STEP
		var cx := GroundStructure.lane_x(anc, wy)
		var hwl := GroundStructure.lane_half_w(wy, -1.0) * 0.74
		var hwr := GroundStructure.lane_half_w(wy, 1.0) * 0.74
		if skip_fn.call(cx, wy):
			if pts[0].size() >= 2:
				segs.append(pts)
			pts = _blank_run()
			continue
		var jl := (float(_h(int(wy / TRACK_STEP), 8101) % 100) / 100.0 - 0.5) * 5.0
		var jr := (float(_h(int(wy / TRACK_STEP), 8102) % 100) / 100.0 - 0.5) * 5.0
		var xl := floorf(cx - hwl + jl)
		var xr := floorf(cx + hwr + jr)
		pts[0].append(Vector2(xl, wy))
		pts[1].append(Vector2(xr, wy))
		pts[2].append(Vector2(xl + 3.0, wy))
		pts[3].append(Vector2(xr - 3.0, wy))
		pts[4].append(Vector2(floorf(cx - hwl * 0.36), wy))
		pts[5].append(Vector2(floorf(cx + hwr * 0.36), wy))
	if pts[0].size() >= 2:
		segs.append(pts)
	return segs


static func track_colors(biome: int) -> Array:
	var rim_c := Color(0.10, 0.07, 0.03, TRACK_RIM_A)
	var lip_c := Color(0.90, 0.80, 0.55, TRACK_LIP_A)
	var mid_c := Color(0.72, 0.60, 0.40, 0.22)
	var rut_c := Color(0.14, 0.09, 0.04, 0.30)
	match biome:
		2: rim_c = Color(0.08, 0.09, 0.04, TRACK_RIM_A); lip_c = Color(0.66, 0.70, 0.48, TRACK_LIP_A); mid_c = Color(0.52, 0.50, 0.34, 0.18)
		3: rim_c = Color(0.07, 0.07, 0.06, TRACK_RIM_A); lip_c = Color(0.74, 0.72, 0.66, TRACK_LIP_A); mid_c = Color(0.60, 0.58, 0.52, 0.16)
		4: rim_c = Color(0.10, 0.08, 0.06, TRACK_RIM_A); lip_c = Color(0.82, 0.72, 0.58, TRACK_LIP_A); mid_c = Color(0.66, 0.58, 0.46, 0.16)
		5: rim_c = Color(0.03, 0.03, 0.04, TRACK_RIM_A); lip_c = Color(0.56, 0.56, 0.62, TRACK_LIP_A); mid_c = Color(0.40, 0.40, 0.46, 0.18)
		6: rim_c = Color(0.10, 0.04, 0.03, TRACK_RIM_A); lip_c = Color(0.78, 0.40, 0.22, TRACK_LIP_A); mid_c = Color(0.40, 0.22, 0.16, 0.18)
	return [rim_c, lip_c, mid_c, rut_c]


static func draw_track_runs(canvas: CanvasItem, segs: Array, biome: int) -> void:
	var col := track_colors(biome)
	for sg in segs:
		var L: PackedVector2Array = sg[0]
		var R: PackedVector2Array = sg[1]
		var n := L.size()
		if n < 2:
			continue
		for i in n - 1:
			canvas.draw_colored_polygon(PackedVector2Array([L[i], R[i], R[i + 1], L[i + 1]]), col[2])
		canvas.draw_polyline(sg[4], col[3], 2.0)
		canvas.draw_polyline(sg[5], col[3], 2.0)
		canvas.draw_polyline(sg[2], col[1], 1.0)
		canvas.draw_polyline(sg[3], col[1], 1.0)
		canvas.draw_polyline(L, col[0], TRACK_RIM_W)
		canvas.draw_polyline(R, col[0], TRACK_RIM_W)


static func _blank_run() -> Array[PackedVector2Array]:
	var r: Array[PackedVector2Array] = []
	for i in 6:
		r.append(PackedVector2Array())
	return r


static func atlas() -> Texture2D:
	if _atlas == null:
		_atlas = ImageTexture.create_from_image(atlas_image())
	return _atlas


## Periodic value noise in [0, 1] on a TONE_SRC torus (exact wrap, so the tile has no seam).
static func _pnoise(x: float, y: float, freq: int, salt: int) -> float:
	var u := x * float(freq)
	var v := y * float(freq)
	var i := int(floor(u))
	var j := int(floor(v))
	var fx := u - float(i)
	var fy := v - float(j)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := float(_h(posmod(i, freq), posmod(j, freq) * 5 + salt) % 1000) / 999.0
	var b := float(_h(posmod(i + 1, freq), posmod(j, freq) * 5 + salt) % 1000) / 999.0
	var c := float(_h(posmod(i, freq), posmod(j + 1, freq) * 5 + salt) % 1000) / 999.0
	var d := float(_h(posmod(i + 1, freq), posmod(j + 1, freq) * 5 + salt) % 1000) / 999.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## The macro tone field as an RGBA image: light warm haze where the field is high, near-black
## where it is low, alpha proportional to distance from the middle. Periodic in both axes.
static func tone_image() -> Image:
	var src := Image.create_empty(TONE_SRC, TONE_SRC, false, Image.FORMAT_RGBA8)
	for y in TONE_SRC:
		for x in TONE_SRC:
			var u := float(x) / float(TONE_SRC)
			var w := float(y) / float(TONE_SRC)
			var n := _pnoise(u, w, 2, 11) * 0.5 + _pnoise(u, w, 4, 12) * 0.3 + _pnoise(u, w, 8, 13) * 0.2
			var d := clampf((n - 0.5) * 3.0, -1.0, 1.0)   # contrast: broad plateaus with soft shores
			if d >= 0.0:
				src.set_pixel(x, y, Color(1.0, 1.0, 1.0, d))
			else:
				src.set_pixel(x, y, Color(0.04, 0.03, 0.0, -d * 0.55))
	# Wrap-safe upscale: pad by tiling, bilinear resize, crop the centre.
	var pad := Image.create_empty(TONE_SRC * 3, TONE_SRC * 3, false, Image.FORMAT_RGBA8)
	for ty in 3:
		for tx in 3:
			pad.blit_rect(src, Rect2i(0, 0, TONE_SRC, TONE_SRC), Vector2i(tx * TONE_SRC, ty * TONE_SRC))
	pad.resize(TONE_TEX * 3, TONE_TEX * 3, Image.INTERPOLATE_BILINEAR)
	return pad.get_region(Rect2i(TONE_TEX, TONE_TEX, TONE_TEX, TONE_TEX))


## Tint of the field's light plateaus per biome (the dark ones stay near-black); the hue
## leans saturated toward the card so the lift reads as sun-struck ground, not haze.
static func tone_tint(biome: int) -> Color:
	match biome:
		2: return Color(0.56, 0.68, 0.34, TONE_ALPHA)
		3: return Color(0.82, 0.78, 0.68, TONE_ALPHA)
		4: return Color(0.88, 0.76, 0.54, TONE_ALPHA)
		5: return Color(0.62, 0.62, 0.70, TONE_ALPHA)
		6: return Color(0.80, 0.40, 0.22, TONE_ALPHA)
		_: return Color(0.66, 0.82, 0.28, TONE_ALPHA)


static func tone() -> Texture2D:
	if _tone == null:
		_tone = ImageTexture.create_from_image(tone_image())
	return _tone


# --- planning --------------------------------------------------------------------------

## Lane anchors cached by gate/water counts (they only change when a gate or ford appears).
static func lane_anchors(gates: Array, waters: Array, water_h_px: float, scale: float) -> Array:
	# Keyed on gate and ford POSITIONS (GroundStructure's memo), not on counts: a new run that
	# lays the same number of gates and rivers elsewhere must not inherit the last run's lane.
	return GroundStructure.cached_anchors(gates, waters, water_h_px, scale)


## One frame's stamps: [screen_pos, kind, variant, biome, scale]. Pure in its arguments.
## `biome_fn(world_y) -> int`, `water_fn(sx, sy) -> bool`; `anc` threads the worn track so
## grass never sprouts on it (it takes pebbles and grit instead).
static func plan(cam_y: float, biome_fn: Callable, water_fn: Callable, anc: Array) -> Array:
	var out: Array = []
	var iy0 := int(floor(cam_y / CELL_PX))
	var oy := -fposmod(cam_y, CELL_PX)
	for ty in ROWS:
		var sy0 := oy + float(ty) * CELL_PX
		var wy_row := cam_y + sy0 + CELL_PX * 0.5
		var biome: int = biome_fn.call(wy_row)
		var mx := mix(biome)
		var lane_cx := GroundStructure.lane_x(anc, wy_row) if not anc.is_empty() else 320.0
		var lane_hw := GroundStructure.lane_half_w(wy_row, 1.0)
		for tx in COLS:
			var h := _h(tx * 7 + 3, iy0 + ty + 5003)
			if h % 100 >= int(mx[3]):
				continue
			var hh := _h(h, 77)
			var sx := float(tx) * CELL_PX + float(hh % int(CELL_PX))
			var sy := sy0 + float((hh >> 8) % int(CELL_PX))
			if water_fn.call(sx, sy):
				continue
			var roll := (h >> 7) % 100
			var kind := int(Kind.SPECK)
			if roll < int(mx[0]):
				kind = int(Kind.TUFT)
			elif roll < int(mx[0]) + int(mx[1]):
				kind = int(Kind.PEBBLE)
			elif roll < int(mx[0]) + int(mx[1]) + int(mx[2]):
				kind = int(Kind.CRACK)
			var on_lane := absf(sx - lane_cx) < lane_hw * 0.78
			if on_lane and kind == int(Kind.TUFT):
				kind = int(Kind.PEBBLE) if (h >> 3) % 2 == 0 else int(Kind.SPECK)
			var sc := 2.0 if ((kind == int(Kind.TUFT) and (h >> 13) % 2 == 0) or (kind == int(Kind.PEBBLE) and (h >> 13) % 4 == 0)) else 1.0
			out.append([Vector2(floorf(sx), floorf(sy)), kind, (hh >> 16) % VARIANTS, biome, sc])
	return out


# --- painting --------------------------------------------------------------------------

## Draws the macro tone tiles (world-anchored; the field is periodic so tiles join exactly) and the
## stamps. `motion` is unused: the ground never animates, so reduce-motion changes nothing.
static func paint(canvas: CanvasItem, cam_y: float, stamps: Array, biome: int = 1, anc: Array = [], water_fn: Callable = Callable()) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex := tone()
	var ty0 := int(floor(cam_y / TONE_PERIOD))
	for ty in range(ty0, ty0 + 3):
		var y := float(ty) * TONE_PERIOD - cam_y
		if y > 360.0 or y + TONE_PERIOD < 0.0:
			continue
		for tx in 2:
			var r := Rect2(Vector2(float(tx) * TONE_PERIOD, y), Vector2(TONE_PERIOD, TONE_PERIOD))
			canvas.draw_texture_rect(tex, r, false, tone_tint(biome))
	if not anc.is_empty() and water_fn.is_valid():
		paint_track(canvas, cam_y, anc, biome, water_fn)
	var at := atlas()
	last_stamp_count = stamps.size()
	for s in stamps:
		var pal: Array = palette(int(s[3]))
		var col: Color = pal[int(s[1])]
		col.a = minf(col.a, STAMP_ALPHA_CAP)
		var sc: float = s[4]
		var pos: Vector2 = s[0]
		canvas.draw_texture_rect_region(at, Rect2(pos, Vector2(STAMP, STAMP) * sc),
			Rect2(float(int(s[2]) * STAMP), float(int(s[1]) * STAMP), float(STAMP), float(STAMP)), col)



# --- cached layer ----------------------------------------------------------------------
# The ground never animates, so the plan, the track geometry and the water bands are built once
# per 26px camera row (world coordinates) and replayed; the camera only translates them.

## Build the atlas and tone textures now (boot/splash) so the first gameplay frame does not hitch.
static func warm() -> void:
	atlas()
	tone()


static func layer_cached(cam_y: float, key: Array) -> bool:
	return not _layer.is_empty() and _layer_key == [int(floor(cam_y / CELL_PX))] + key


## `water_fn(sx, world_y)`; `bands` = [[y0, y1], ...] world-px river bands (the WHOLE band, ford
## included): no stamp, tone or track is drawn inside one. `key` must change whenever the
## inputs of biome_fn / water_fn / anc / bands change (the camera row is added here).
static func build_layer(cam_y: float, key: Array, biome_fn: Callable, water_fn: Callable,
		anc: Array, bands: Array) -> void:
	var iy0 := int(floor(cam_y / CELL_PX))
	var snap := float(iy0) * CELL_PX
	plan_builds += 1
	var in_band := func(wy: float) -> bool:
		for b in bands:
			if wy >= b[0] and wy <= b[1]:
				return true
		return false
	var stamps := plan(snap, biome_fn,
		func(sx: float, sy: float) -> bool: return in_band.call(snap + sy) or water_fn.call(sx, snap + sy), anc)
	for s in stamps:
		s[0] = (s[0] as Vector2) + Vector2(0.0, snap)
	var runs: Array = []
	if not anc.is_empty():
		var wy0 := floorf(snap / TRACK_STEP) * TRACK_STEP
		runs = track_runs(wy0, int(ceil((float(ROWS) * CELL_PX + CELL_PX) / TRACK_STEP)) + 2, anc,
			func(cx: float, wy: float) -> bool: return in_band.call(wy) or water_fn.call(cx, wy))
	_layer = {"stamps": stamps, "runs": runs, "bands": bands}
	_layer_key = [iy0] + key


static func paint_layer(canvas: CanvasItem, cam_y: float, biome: int) -> void:
	if _layer.is_empty():
		return
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_paint_tone(canvas, cam_y, biome, _layer["bands"])
	canvas.draw_set_transform(Vector2(0.0, -floorf(cam_y)), 0.0, Vector2.ONE)
	draw_track_runs(canvas, _layer["runs"], biome)
	var at := atlas()
	var stamps: Array = _layer["stamps"]
	last_stamp_count = stamps.size()
	for s in stamps:
		var pal: Array = palette(int(s[3]))
		var col: Color = pal[int(s[1])]
		col.a = minf(col.a, STAMP_ALPHA_CAP)
		var pos: Vector2 = s[0]
		canvas.draw_texture_rect_region(at, Rect2(pos, Vector2(STAMP, STAMP) * float(s[4])),
			Rect2(float(int(s[2]) * STAMP), float(int(s[1]) * STAMP), float(STAMP), float(STAMP)), col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tone tiles minus the river bands (cut as source-region strips).
static func _paint_tone(canvas: CanvasItem, cam_y: float, biome: int, bands: Array) -> void:
	var tex := tone()
	var tint := tone_tint(biome)
	var ty0 := int(floor(cam_y / TONE_PERIOD))
	var k := float(TONE_TEX) / TONE_PERIOD
	for ty in range(ty0, ty0 + 3):
		var wy := float(ty) * TONE_PERIOD
		if wy - cam_y > 360.0 or wy + TONE_PERIOD - cam_y < 0.0:
			continue
		var spans: Array = [[wy, wy + TONE_PERIOD]]
		for b in bands:
			var nxt: Array = []
			for sp in spans:
				if b[1] <= sp[0] or b[0] >= sp[1]:
					nxt.append(sp)
					continue
				if b[0] > sp[0]:
					nxt.append([sp[0], b[0]])
				if b[1] < sp[1]:
					nxt.append([b[1], sp[1]])
			spans = nxt
		for sp in spans:
			for tx in 2:
				canvas.draw_texture_rect_region(tex,
					Rect2(float(tx) * TONE_PERIOD, sp[0] - cam_y, TONE_PERIOD, sp[1] - sp[0]),
					Rect2(0.0, (sp[0] - wy) * k, float(TONE_TEX), (sp[1] - sp[0]) * k), tint)
