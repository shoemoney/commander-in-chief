class_name TitlePolish
extends RefCounted
## View-only title/splash dressing: the logo lockup (faceted star-and-chevron emblem built in
## code, extruded + outlined + shimmering wordmark layers), the composed backdrop (vignette,
## top shade, searchlight sweep, drifting smoke) and the version/copyright footer.
##
## Everything is a PLAN: pure functions return an Array of op dictionaries, and paint() draws
## them. Plans are plain data, so tests assert on them without a GL surface; paint() draws only
## when the canvas item is inside a SceneTree (a bare Control cannot draw), and remembers the
## last plan in last_ops so a test can prove the real menu/splash code reached this module.
## REDUCE MOTION (motion < 0.5): no smoke drift, no beam sweep, no shimmer, no pulse.

const WORD := "COMMANDER IN CHIEF"
const COPYRIGHT := "(C) 2026 BIG IT GAME STUDIOS"
const EMBLEM_W := 300
const EMBLEM_H := 56
const EMBLEM_TOP := 4.0
const SHIMMER_PERIOD := 7.0
const SHIMMER_SECS := 1.3

const GOLD_HI := Color(1.0, 0.95, 0.62)
const GOLD := Color(1.0, 0.85, 0.3)
const GOLD_LO := Color(0.8, 0.52, 0.12)
const INK := Color(0.05, 0.035, 0.02)
const EXTRUDE := Color(0.42, 0.15, 0.06)

static var last_ops: Array = []
static var _emblem: ImageTexture


static func version_text() -> String:
	return "V" + str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


static func paint(ci: CanvasItem, ops: Array) -> void:
	last_ops = ops
	if ci == null or not ci.is_inside_tree():
		return
	var f := Art.font()
	for op in ops:
		match String(op["k"]):
			"text":
				ci.draw_string(f, op["pos"], op["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(op["size"]), op["col"])
			"outline":
				ci.draw_string_outline(f, op["pos"], op["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(op["size"]), int(op["w"]), op["col"])
			"tex":
				ci.draw_texture_rect(op["tex"], op["rect"], false, op["col"])
			"tri":
				ci.draw_polygon(op["pts"], op["cols"])
			"ptex":
				ci.draw_polygon(op["pts"], PackedColorArray([op["col"]]), op["uvs"], op["tex"])
			"circle":
				ci.draw_circle(op["c"], float(op["r"]), op["col"])
			"rect":
				ci.draw_rect(op["rect"], op["col"])


static func _text_x(txt: String, cx: float, size: int) -> float:
	return floorf(cx - Art.tw(txt, size) / 2.0)


# ---- wordmark ----

## Layers drawn BEFORE the flat gold face: hard outline, stepped extrusion, top highlight.
static func wordmark_under(cx: float, base: float, size: int, a: float) -> Array:
	var pos := Vector2(_text_x(WORD, cx, size), floorf(base))
	var ops: Array = []
	ops.append({"k": "outline", "txt": WORD, "pos": pos + Vector2(0, 2), "size": size, "w": 4,
		"col": Color(INK, a * 0.95)})
	for dy in [3, 2, 1]:
		ops.append({"k": "text", "txt": WORD, "pos": pos + Vector2(0, dy), "size": size,
			"col": Color(EXTRUDE, a)})
	ops.append({"k": "text", "txt": WORD, "pos": pos + Vector2(0, -1), "size": size,
		"col": Color(GOLD_HI, a)})
	return ops


## Light band sweeping across the face, one letter at a time. Empty when static or idle.
static func wordmark_over(cx: float, base: float, size: int, a: float, t: float, motion: float) -> Array:
	var ops: Array = []
	if motion < 0.5:
		return ops
	var phase := fposmod(t, SHIMMER_PERIOD) / SHIMMER_SECS
	if phase > 1.0:
		return ops
	var f := Art.font()
	var x0 := _text_x(WORD, cx, size)
	var span := Art.tw(WORD, size)
	var sx := x0 - 20.0 + phase * (span + 40.0)
	for i in WORD.length():
		var ch := WORD.substr(i, 1)
		if ch == " ":
			continue
		var px := x0 + f.get_string_size(WORD.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var mid := px + f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
		var k := clampf(1.0 - absf(mid - sx) / 16.0, 0.0, 1.0)
		if k > 0.02:
			ops.append({"k": "text", "txt": ch, "pos": Vector2(px, floorf(base)), "size": size,
				"col": Color(1.0, 1.0, 0.92, 0.85 * k * a)})
	return ops


## The whole lockup in one plan (splash beat): under + flat face + shimmer.
static func wordmark_full(cx: float, base: float, size: int, a: float, t: float, motion: float) -> Array:
	var ops := wordmark_under(cx, base, size, a)
	ops.append({"k": "text", "txt": WORD, "pos": Vector2(_text_x(WORD, cx, size), floorf(base)),
		"size": size, "col": Color(GOLD, a)})
	ops.append_array(wordmark_over(cx, base, size, a, t, motion))
	return ops


## Gold rule with a centred diamond, used under the splash wordmark and flanking the tagline.
static func rule(cx: float, y: float, half: float, a: float) -> Array:
	var ops: Array = []
	var gap := 6.0
	for s: float in [-1.0, 1.0]:
		var x0 := cx + gap if s > 0.0 else cx - gap - half
		ops.append({"k": "rect", "rect": Rect2(x0, y, half, 1.0), "col": Color(GOLD, 0.7 * a)})
		ops.append({"k": "rect", "rect": Rect2(x0 + (0.0 if s > 0.0 else 0.0), y + 1.0, half, 1.0),
			"col": Color(INK, 0.5 * a)})
	for r in [Rect2(cx - 1, y - 2, 2, 2), Rect2(cx - 3, y, 6, 1), Rect2(cx - 1, y + 1, 2, 2)]:
		ops.append({"k": "rect", "rect": r, "col": Color(GOLD_HI, a)})
	return ops


# ---- emblem ----

static func emblem_rect() -> Rect2:
	return Rect2(320.0 - EMBLEM_W / 2.0, EMBLEM_TOP, EMBLEM_W, EMBLEM_H)


static func emblem_plan(t: float, motion: float, a: float) -> Array:
	var ops: Array = []
	var r := emblem_rect()
	var c := r.position + Vector2(EMBLEM_W / 2.0, EMBLEM_H / 2.0)
	var pulse := 0.5 if motion < 0.5 else 0.5 + 0.5 * sin(t * 2.2)
	for i in 4:
		ops.append({"k": "circle", "c": c, "r": 46.0 - float(i) * 9.0,
			"col": Color(1.0, 0.8, 0.3, (0.025 + 0.022 * pulse) * a)})
	ops.append({"k": "tex", "tex": emblem_tex(), "rect": r, "col": Color(1, 1, 1, a)})
	return ops


static func emblem_tex() -> Texture2D:
	if _emblem == null:
		_emblem = ImageTexture.create_from_image(build_emblem_image())
	return _emblem


static func _dim(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)


static func _blend(img: Image, x: int, y: int, col: Color, cov: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or cov <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var sa := col.a * cov
	var oa := sa + dst.a * (1.0 - sa)
	if oa <= 0.0:
		return
	var rgb := (Vector3(col.r, col.g, col.b) * sa + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - sa)) / oa
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, oa))


static func _fill_poly(img: Image, poly: PackedVector2Array, top: Color, bottom: Color) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := maxf(hi.y - lo.y, 1.0)
	for y in range(int(floor(lo.y)), int(ceil(hi.y)) + 1):
		for x in range(int(floor(lo.x)), int(ceil(hi.x)) + 1):
			var n := 0
			for sy in 2:
				for sx in 2:
					if Geometry2D.is_point_in_polygon(Vector2(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy), poly):
						n += 1
			if n > 0:
				_blend(img, x, y, top.lerp(bottom, clampf((y - lo.y) / span, 0.0, 1.0)), float(n) / 4.0)


static func _fill_ring(img: Image, c: Vector2, r_in: float, r_out: float, top: Color, bottom: Color) -> void:
	for y in range(int(c.y - r_out) - 1, int(c.y + r_out) + 2):
		for x in range(int(c.x - r_out) - 1, int(c.x + r_out) + 2):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var cov := clampf(r_out - d + 0.5, 0.0, 1.0) * clampf(d - r_in + 0.5, 0.0, 1.0)
			if cov > 0.0:
				_blend(img, x, y, top.lerp(bottom, clampf((y - (c.y - r_out)) / (2.0 * r_out), 0.0, 1.0)), cov)


## Band chevron whose arms open toward `ti` (+1 arms go right "<", -1 arms go left ">").
static func _chevron(apex: Vector2, ti: float) -> PackedVector2Array:
	var arm := 12.0
	var th := 5.0
	return PackedVector2Array([apex, apex + Vector2(ti * arm, -arm), apex + Vector2(ti * (arm + th), -arm),
		apex + Vector2(ti * th, 0.0), apex + Vector2(ti * (arm + th), arm), apex + Vector2(ti * arm, arm)])


static func build_emblem_image() -> Image:
	var body := Image.create(EMBLEM_W, EMBLEM_H, false, Image.FORMAT_RGBA8)
	var c := Vector2(EMBLEM_W / 2.0, EMBLEM_H / 2.0)
	# wings: three nested chevrons each side, dimming outward
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var apex := Vector2(c.x + side * (32.0 + 17.0 * float(k)), c.y)
			var poly := _chevron(apex, -side)
			var f := 1.0 - 0.16 * float(k)
			_fill_poly(body, poly, _dim(GOLD_HI, f), _dim(GOLD_LO, f))
	# end rules with a diamond cap
	for side: float in [-1.0, 1.0]:
		var x0 := c.x + side * 92.0
		var x1 := c.x + side * 146.0
		_fill_poly(body, PackedVector2Array([Vector2(minf(x0, x1), c.y - 1.0), Vector2(maxf(x0, x1), c.y - 1.0),
			Vector2(maxf(x0, x1), c.y + 1.0), Vector2(minf(x0, x1), c.y + 1.0)]), GOLD, GOLD_LO)
	# ring + dark disc
	_fill_ring(body, c, 0.0, 22.0, Color(0.1, 0.15, 0.09), Color(0.05, 0.08, 0.05))
	_fill_ring(body, c, 19.5, 24.5, GOLD_HI, GOLD_LO)
	# faceted star
	var pts: Array[Vector2] = []
	for i in 10:
		var ang := -PI / 2.0 + PI * float(i) / 5.0
		var rad := 16.0 if i % 2 == 0 else 6.6
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	for i in 10:
		var tri := PackedVector2Array([c, pts[i], pts[(i + 1) % 10]])
		var lit := (i % 2 == 0)
		_fill_poly(body, tri, GOLD_HI if lit else GOLD, GOLD if lit else GOLD_LO)
	# outline + drop shadow from the body's alpha
	var out := Image.create(EMBLEM_W, EMBLEM_H, false, Image.FORMAT_RGBA8)
	for y in EMBLEM_H:
		for x in EMBLEM_W:
			var al := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px := x + dx
					var py := y + dy
					if px >= 0 and py >= 0 and px < EMBLEM_W and py < EMBLEM_H:
						al = maxf(al, body.get_pixel(px, py).a)
			if al > 0.0:
				out.set_pixel(x, y, Color(INK, al))
	var final := Image.create(EMBLEM_W, EMBLEM_H, false, Image.FORMAT_RGBA8)
	for y in EMBLEM_H:
		for x in EMBLEM_W:
			var sa := 0.0
			if x >= 1 and y >= 2:
				sa = out.get_pixel(x - 1, y - 2).a * 0.5
			if sa > 0.0:
				final.set_pixel(x, y, Color(0, 0, 0, sa))
	for y in EMBLEM_H:
		for x in EMBLEM_W:
			var o := out.get_pixel(x, y)
			if o.a > 0.0:
				_blend(final, x, y, o, 1.0)
	for y in EMBLEM_H:
		for x in EMBLEM_W:
			var b := body.get_pixel(x, y)
			if b.a > 0.0:
				_blend(final, x, y, b, 1.0)
	return final


# ---- backdrop ----

## Vignette + top shade: legibility for the lockup and a framed, composed edge.
static func vignette(a: float) -> Array:
	var ops: Array = []
	var edge := Color(0, 0, 0, 0.5 * a)
	var clear := Color(0, 0, 0, 0.0)
	var d := 90.0
	ops.append({"k": "tri", "pts": PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 70), Vector2(0, 70)]),
		"cols": PackedColorArray([Color(0.02, 0.03, 0.02, 0.6 * a), Color(0.02, 0.03, 0.02, 0.6 * a), clear, clear])})
	ops.append({"k": "tri", "pts": PackedVector2Array([Vector2(0, 360), Vector2(640, 360), Vector2(640, 360 - d), Vector2(0, 360 - d)]),
		"cols": PackedColorArray([edge, edge, clear, clear])})
	ops.append({"k": "tri", "pts": PackedVector2Array([Vector2(0, 0), Vector2(d, 0), Vector2(d, 360), Vector2(0, 360)]),
		"cols": PackedColorArray([edge, clear, clear, edge])})
	ops.append({"k": "tri", "pts": PackedVector2Array([Vector2(640, 0), Vector2(640 - d, 0), Vector2(640 - d, 360), Vector2(640, 360)]),
		"cols": PackedColorArray([edge, clear, clear, edge])})
	return ops


static func beam_angle(i: int, t: float, motion: float) -> float:
	var base := -1.12 if i == 0 else -2.02   # radians, up-right / up-left from the bottom corners
	if motion < 0.5:
		return base
	return base + 0.32 * sin(t * 0.37 + float(i) * 2.1)


const SMOKE := [[40.0, 120.0, 90.0, 9.0], [260.0, 300.0, 110.0, 6.0], [470.0, 70.0, 80.0, 11.0],
	[600.0, 250.0, 100.0, 7.0], [150.0, 210.0, 70.0, 12.0]]   # x, y, radius, drift px/s


static var _scene: ImageTexture


static func _fill_rect_img(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for yy in range(maxi(y, 0), mini(y + h, img.get_height())):
		for xx in range(maxi(x, 0), mini(x + w, img.get_width())):
			img.set_pixel(xx, yy, col)


static func _fill_tri_img(img: Image, cx: int, top: int, hw: int, h: int, col: Color) -> void:
	for yy in h:
		var half := int(round(float(hw) * float(yy + 1) / float(h)))
		_fill_rect_img(img, cx - half, top + yy, half * 2 + 1, 1, col)


static func ridge_y(x: float, far: bool) -> float:
	if far:
		return 226.0 + 10.0 * sin(x * 0.012 + 1.0) + 6.0 * sin(x * 0.031) + 3.0 * sin(x * 0.07)
	return 268.0 + 8.0 * sin(x * 0.02 + 2.0) + 4.0 * sin(x * 0.05)


## The static composed scene baked ONCE: dusk sky with stars and a low sun glow, two ridgelines,
## and a silhouetted skyline (watchtower, pines, a tank on the near ridge). One 640x360 texture.
static func build_scene_image() -> Image:
	var img := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	var sky_top := Color(0.02, 0.04, 0.06)
	var sky_mid := Color(0.12, 0.17, 0.2)
	var sky_hz := Color(0.78, 0.46, 0.2)
	for y in 360:
		var k := clampf(float(y) / 236.0, 0.0, 1.0)
		var col := sky_top.lerp(sky_mid, minf(k * 1.6, 1.0)).lerp(sky_hz, pow(k, 3.2))
		for x in 640:
			img.set_pixel(x, y, col)
	var sun := Vector2(330.0, 236.0)
	for y in range(90, 260):
		for x in range(110, 560):
			var d := Vector2(x, y).distance_to(sun)
			if d < 150.0:
				var g := pow(1.0 - d / 150.0, 2.2) * 0.55
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, c.lerp(Color(1.0, 0.72, 0.34), g))
	for i in 60:
		var sx := (i * 97 + 31) % 640
		var sy := (i * 53 + 7) % 130
		img.set_pixel(sx, sy, Color(0.85, 0.9, 1.0) if i % 3 != 0 else Color(0.6, 0.7, 0.8))
	var far_c := Color(0.13, 0.17, 0.15)
	var near_c := Color(0.035, 0.05, 0.04)
	for x in 640:
		var fy := int(ridge_y(float(x), true))
		for y in range(fy, 360):
			var t := clampf(float(y - fy) / 50.0, 0.0, 1.0)
			img.set_pixel(x, y, far_c.lerp(Color(0.07, 0.09, 0.08), t))
	# far skyline details: haze-grey chimneys of a distant factory
	for cx in [88, 96, 540, 552]:
		_fill_rect_img(img, cx, int(ridge_y(float(cx), true)) - 16, 3, 16, far_c.darkened(0.25))
	for x in 640:
		var ny := int(ridge_y(float(x), false))
		for y in range(ny, 360):
			var t := clampf(float(y - ny) / 90.0, 0.0, 1.0)
			img.set_pixel(x, y, near_c.lerp(Color(0.02, 0.03, 0.025), t))
	# near silhouettes: watchtower, pines, a tank, sandbags
	_fill_rect_img(img, 60, int(ridge_y(60.0, false)) - 34, 3, 34, near_c)
	_fill_rect_img(img, 70, int(ridge_y(70.0, false)) - 34, 3, 34, near_c)
	_fill_rect_img(img, 56, int(ridge_y(60.0, false)) - 42, 21, 9, near_c)
	_fill_tri_img(img, 66, int(ridge_y(60.0, false)) - 50, 14, 8, near_c)
	for px in [24, 40, 150, 168, 575, 596, 618]:
		var by := int(ridge_y(float(px), false))
		_fill_rect_img(img, px, by - 6, 2, 8, near_c)
		_fill_tri_img(img, px, by - 30, 8, 26, near_c)
		_fill_tri_img(img, px, by - 20, 11, 16, near_c)
	var ty := int(ridge_y(470.0, false))
	_fill_rect_img(img, 452, ty - 8, 40, 8, near_c)
	_fill_rect_img(img, 458, ty - 15, 22, 8, near_c)
	_fill_rect_img(img, 480, ty - 13, 26, 3, near_c)
	_fill_rect_img(img, 450, ty - 3, 44, 3, Color(0.0, 0.0, 0.0))
	for bx in [264, 280, 296]:
		_fill_rect_img(img, bx, int(ridge_y(float(bx), false)) - 4, 14, 5, near_c)
	return img


## icon.png ships on an opaque near-white square; this outline (icon pixel space) hugs the
## rounded tile plus the shield apex/tip so the badge draws with no white box around it.
const ICON_OUTLINE := [Vector2(98, 132), Vector2(112, 88), Vector2(152, 72), Vector2(430, 72),
	Vector2(512, 48), Vector2(594, 72), Vector2(872, 72), Vector2(912, 88), Vector2(924, 132),
	Vector2(924, 876), Vector2(910, 902), Vector2(872, 914), Vector2(600, 928), Vector2(512, 972),
	Vector2(424, 928), Vector2(152, 914), Vector2(114, 902), Vector2(98, 876)]


static func icon_ops(tex: Texture2D, rect: Rect2, a: float) -> Array:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for q: Vector2 in ICON_OUTLINE:
		var u := q / 1024.0
		uvs.append(u)
		pts.append(rect.position + u * rect.size)
	return [{"k": "ptex", "pts": pts, "uvs": uvs, "tex": tex, "col": Color(1, 1, 1, a)}]


static func scene_tex() -> Texture2D:
	if _scene == null:
		_scene = ImageTexture.create_from_image(build_scene_image())
	return _scene


## Searchlight beams rise from the near ridge; bright enough to read against the dusk sky.
static func searchlights(t: float, motion: float, a: float) -> Array:
	var ops: Array = []
	for i in 2:
		var o := Vector2(96.0, 262.0) if i == 0 else Vector2(544.0, 262.0)
		var ang := beam_angle(i, t, motion)
		var far := 420.0
		var spread := 0.085
		var p1 := o + Vector2(cos(ang - spread), sin(ang - spread)) * far
		var p2 := o + Vector2(cos(ang + spread), sin(ang + spread)) * far
		var tip := Color(1.0, 0.96, 0.8, 0.0)
		ops.append({"k": "tri", "pts": PackedVector2Array([o, p1, p2]),
			"cols": PackedColorArray([Color(1.0, 0.96, 0.8, 0.4 * a), tip, tip])})
		ops.append({"k": "circle", "c": o, "r": 6.0, "col": Color(1.0, 0.95, 0.7, 0.35 * a)})
		ops.append({"k": "circle", "c": o, "r": 3.0, "col": Color(1.0, 1.0, 0.9, 0.7 * a)})
	return ops


static func smoke(t: float, motion: float, a: float) -> Array:
	var ops: Array = []
	for s in SMOKE:
		var x: float = s[0] if motion < 0.5 else fposmod(float(s[0]) + t * float(s[3]) + 140.0, 780.0) - 140.0
		for i in 4:
			ops.append({"k": "circle", "c": Vector2(x, float(s[1]) * 0.8 + 30.0 + sin(t * 0.2 + float(s[0])) * (0.0 if motion < 0.5 else 4.0)),
				"r": float(s[2]) * (1.0 - 0.22 * float(i)), "col": Color(0.05, 0.06, 0.06, 0.07 * a)})
	return ops


static func backdrop(t: float, motion: float, a: float) -> Array:
	var ops: Array = [{"k": "tex", "tex": scene_tex(), "rect": Rect2(0, 0, 640, 360), "col": Color(1, 1, 1, a)}]
	ops.append_array(searchlights(t, motion, a))
	ops.append_array(smoke(t, motion, a))
	ops.append_array(vignette(a))
	return ops


## Footer plates: version bottom-left, copyright bottom-right (micro text, baseline y).
static func footer_items(size: int) -> Array:
	var cr := COPYRIGHT.replace("(C)", "©") if Art.font().has_char(0xA9) else COPYRIGHT
	return [{"txt": version_text(), "x": 8.0},
		{"txt": cr, "x": 640.0 - 8.0 - Art.tw(cr, size)}]
