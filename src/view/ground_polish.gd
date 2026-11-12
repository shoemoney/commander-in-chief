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
const TONE_ALPHA := 0.30         # global multiplier on the baked tone alpha
const STAMP_ALPHA_CAP := 0.5     # nothing on the ground is louder than this

static var _atlas: Texture2D = null
static var _tone: Texture2D = null
static var last_stamp_count := 0   # probe: stamps drawn by the last paint()
static var _anc_key := -1
static var _anc_cache: Array = []


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
				src.set_pixel(x, y, Color(0.04, 0.03, 0.0, -d))
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
	var key := gates.size() * 1000 + waters.size()
	if key != _anc_key or _anc_cache.is_empty():
		_anc_key = key
		_anc_cache = GroundStructure.anchors(gates, waters, water_h_px, scale)
	return _anc_cache


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
			var sc := 2.0 if (kind == int(Kind.TUFT) and (h >> 13) % 4 == 0) else 1.0
			out.append([Vector2(floorf(sx), floorf(sy)), kind, (hh >> 16) % VARIANTS, biome, sc])
	return out


# --- painting --------------------------------------------------------------------------

## Draws the macro tone tiles (world-anchored; the field is periodic so tiles join exactly) and the
## stamps. `motion` is unused: the ground never animates, so reduce-motion changes nothing.
static func paint(canvas: CanvasItem, cam_y: float, stamps: Array, biome: int = 1) -> void:
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
