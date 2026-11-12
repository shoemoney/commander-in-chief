class_name ProjectilesPolish
extends RefCounted
## View-only projectile readability. In a one-hit-kill shooter enemy fire has to be the
## most legible thing on screen: dark outline + saturated body + hot core + halo for
## hostile rounds, tapered hot-core tracers for the player's, an exhaust plume for
## rockets and a dotted arc to the landing point for grenades. Nothing here touches the
## sim; every size is a pure function of sim state the caller already read.

const PX := 1.0 / Fixed.ONE
const OUTLINE := Color(0.02, 0.01, 0.02, 0.92)
const ENEMY_BODY := Color(1.0, 0.22, 0.82)
const ENEMY_CORE := Color(1.0, 0.93, 0.55)
const SNIPER_CORE := Color(1.0, 0.98, 0.85)

## Hostile glow halo radius in px. It reaches out to the lethal radius so the lit area a
## player sees is never smaller than the area that kills; the solid body stays inside it.
static func enemy_halo_radius(fast: bool) -> float:
	return maxf(float(SimWorld.ENEMY_BULLET_HIT_RADIUS) * PX, 8.0 if fast else 7.0)


static func enemy_body_radius(fast: bool) -> float:
	return 3.4 if fast else 3.0


## Streak length behind a hostile round; faster rounds read proportionally longer.
static func enemy_tail(speed_ratio: float) -> float:
	return 7.0 + maxf(0.0, speed_ratio - 1.0) * 8.0


## Pass 1 (under the card): the halo, as wide as the lethal radius.
static func draw_enemy_halo(c: CanvasItem, pos: Vector2, speed_ratio: float, frame: int, motion: float) -> void:
	var halo := enemy_halo_radius(speed_ratio > 1.4)
	var pulse := 1.0 if motion < 0.5 else 0.88 + 0.12 * sin(float(frame) * 0.5)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * halo, Vector2.ONE * halo * 2.0),
		false, Color(1.0, 0.22, 0.82, 0.8 * pulse))


## Pass 2 (over the card): tapered wake, dark outline, saturated body, hot core.
static func draw_enemy_body(c: CanvasItem, pos: Vector2, dir: Vector2, speed_ratio: float) -> void:
	var fast := speed_ratio > 1.4
	var body := enemy_body_radius(fast)
	if dir.length() > 0.5:
		var tail := enemy_tail(speed_ratio)
		line_px(c, pos - dir * tail * 0.45, pos, ENEMY_BODY, body * 1.6)
	Art.circle(c, pos, body + 1.4, OUTLINE)
	Art.circle(c, pos, body, ENEMY_BODY)
	Art.circle(c, pos, body * 0.55, SNIPER_CORE if fast else ENEMY_CORE)


## Four tapering segments, tail to head: [from, to, width, alpha].
static func tracer_segments(pos: Vector2, dir: Vector2, length: float) -> Array:
	var out: Array = []
	for k in 4:
		var t0 := float(k) / 4.0
		var t1 := float(k + 1) / 4.0
		out.append([pos - dir * length * (1.0 - t0), pos - dir * length * (1.0 - t1),
			1.4 + t1 * 2.2, 0.3 + 0.75 * t1])
	return out


## Per-segment widths and alphas of the tracer taper (the same expressions tracer_segments() uses).
static var _tr_w := PackedFloat64Array()
static var _tr_a := PackedFloat64Array()


static func draw_player_tracer(c: CanvasItem, pos: Vector2, dir: Vector2, length: float, heat: float, piercing: bool) -> void:
	if _tr_w.is_empty():
		for k in 4:
			var t1 := float(k + 1) / 4.0
			_tr_w.append(1.4 + t1 * 2.2)
			_tr_a.append(0.3 + 0.75 * t1)
	var glow := Color(0.35, 0.9, 1.0) if piercing else Color(1.0, 0.7, 0.2).lerp(Color(1.0, 0.95, 0.6), heat)
	var hot := Color(0.85, 1.0, 1.0) if piercing else Color(1.0, 0.98, 0.85)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * 4.5, Vector2.ONE * 9.0), false,
		Color(glow.r, glow.g, glow.b, 0.7))
	# The same four tapering segments tracer_segments() describes, without the per-bullet arrays.
	var p0 := pos - dir * length * 1.0
	var p1 := pos - dir * length * 0.75
	var p2 := pos - dir * length * 0.5
	var p3 := pos - dir * length * 0.25
	var p4 := pos - dir * length * 0.0
	line_px(c, p0, p1, Color(0.02, 0.02, 0.04, 0.4 * _tr_a[0]), _tr_w[0] + 1.6)
	line_px(c, p1, p2, Color(0.02, 0.02, 0.04, 0.4 * _tr_a[1]), _tr_w[1] + 1.6)
	line_px(c, p2, p3, Color(0.02, 0.02, 0.04, 0.4 * _tr_a[2]), _tr_w[2] + 1.6)
	line_px(c, p3, p4, Color(0.02, 0.02, 0.04, 0.4 * _tr_a[3]), _tr_w[3] + 1.6)
	line_px(c, p0, p1, Color(glow.r, glow.g, glow.b, _tr_a[0]), _tr_w[0])
	line_px(c, p1, p2, Color(glow.r, glow.g, glow.b, _tr_a[1]), _tr_w[1])
	line_px(c, p2, p3, Color(glow.r, glow.g, glow.b, _tr_a[2]), _tr_w[2])
	line_px(c, p3, p4, Color(glow.r, glow.g, glow.b, _tr_a[3]), _tr_w[3])
	line_px(c, pos - dir * length * 0.4, pos, hot, 1.8)
	Art.circle(c, pos, 2.0, hot)


## Underlay for a rocket: a long fading exhaust plume, drawn BEFORE the weapon_fx body.
static func draw_rocket_exhaust(c: CanvasItem, pos: Vector2, dir: Vector2, frame: int, motion: float) -> void:
	var flick := 0.0 if motion < 0.5 else float(frame % 3) * 0.8
	var n := Vector2(-dir.y, dir.x)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - dir * 6.0 - Vector2.ONE * 7.0, Vector2.ONE * 14.0), false,
		Color(1.0, 0.55, 0.15, 0.5))
	for k in 6:
		var t := float(k) / 6.0
		var p := pos - dir * (5.0 + t * 20.0) + n * sin(float(frame) * 0.3 + float(k)) * 0.5 * motion
		Art.circle(c, p, 3.2 - t * 1.8 + flick * 0.2, Color(1.0, 0.75 - t * 0.35, 0.2, 0.55 * (1.0 - t)))


## Dotted arc from the airborne frag to its landing point, bulging upward mid-flight.
static func grenade_arc(body: Vector2, land: Vector2, n := 6) -> Array:
	var pts: Array = []
	var bulge := minf(body.distance_to(land) * 0.15, 10.0)
	for k in range(1, n + 1):
		var t := float(k) / float(n + 1)
		pts.append(body.lerp(land, t) - Vector2(0.0, sin(PI * t) * bulge))
	return pts


static func draw_grenade_arc(c: CanvasItem, body: Vector2, land: Vector2) -> void:
	var pts := grenade_arc(body, land)
	for i in pts.size():
		var a := 0.75 * (1.0 - float(i) / float(pts.size()) * 0.6)
		Art.circle(c, pts[i], 1.5, Color(0.02, 0.02, 0.04, a * 0.6))
		Art.circle(c, pts[i], 0.9, Color(1.0, 0.95, 0.7, a))


## Cached line shapes keyed by (dx, dy, width): Bresenham is translation-invariant, so the strip
## list for a delta is computed once and replayed at any origin. Entry: [rects, uses, tex, ox, oy, w, h].
static var _line_cache := {}
const _LINE_CACHE_CAP := 1024
const _PROMOTE_USES := 6


## Pixel-identical stand-in for Art.line for short on-screen lines: the same Bresenham strips,
## with neighbouring strips on one row/column merged into a single rect (strips never overlap, so
## the coverage and the blended pixels are unchanged). A shape that keeps recurring is promoted to
## a one-draw white-pixel texture (nearest filter, 1:1, so modulate colour and blending match the
## rects exactly). Anything touching the screen edge defers to Art.line and its clip.
static func line_px(ci: CanvasItem, from: Vector2, to: Vector2, color: Color, width := 1.0) -> void:
	var x0 := roundi(from.x)
	var y0 := roundi(from.y)
	var x1 := roundi(to.x)
	var y1 := roundi(to.y)
	var w := maxi(1, roundi(width))
	if x0 < 0 or x0 > 640 or x1 < 0 or x1 > 640 or y0 < 0 or y0 > 360 or y1 < 0 or y1 > 360 or w > 200:
		Art.line(ci, from, to, color, width)
		return
	var key := ((x1 - x0 + 1024) << 20) | ((y1 - y0 + 1024) << 8) | w
	var e = _line_cache.get(key)
	if e == null:
		e = [_build_line(x1 - x0, y1 - y0, w), 0, null, 0.0, 0.0, 0.0, 0.0]
		if _line_cache.size() >= _LINE_CACHE_CAP:
			_line_cache.clear()
		_line_cache[key] = e
	var tex = e[2]
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(float(x0) + e[3], float(y0) + e[4], e[5], e[6]), false, color)
		return
	var rects: PackedFloat32Array = e[0]
	e[1] += 1
	if e[1] >= _PROMOTE_USES:
		_promote_rects(e, rects, 4)
	var n: int = rects.size()
	var i := 0
	while i < n:
		ci.draw_rect(Rect2(float(x0) + rects[i], float(y0) + rects[i + 1], rects[i + 2], rects[i + 3]), color)
		i += 4


## Fills e[2..6] with a texture of the rect list ([x, y, w, h] each, `stride` floats per rect, h=1
## when stride is 3 as arc runs are [x, y, w]) so later draws are a single textured quad.
static func _promote_rects(e: Array, rects: PackedFloat32Array, stride: int) -> void:
	var x_lo := 1 << 30
	var y_lo := 1 << 30
	var x_hi := -(1 << 30)
	var y_hi := -(1 << 30)
	var i := 0
	while i < rects.size():
		var rh := int(rects[i + 3]) if stride == 4 else 1
		x_lo = mini(x_lo, int(rects[i]))
		y_lo = mini(y_lo, int(rects[i + 1]))
		x_hi = maxi(x_hi, int(rects[i]) + int(rects[i + 2]))
		y_hi = maxi(y_hi, int(rects[i + 1]) + rh)
		i += stride
	if x_hi <= x_lo or y_hi <= y_lo:
		return
	var img := Image.create_empty(x_hi - x_lo, y_hi - y_lo, false, Image.FORMAT_RGBA8)
	i = 0
	while i < rects.size():
		var rh2 := int(rects[i + 3]) if stride == 4 else 1
		img.fill_rect(Rect2i(int(rects[i]) - x_lo, int(rects[i + 1]) - y_lo, int(rects[i + 2]), rh2), Color.WHITE)
		i += stride
	e[2] = ImageTexture.create_from_image(img)
	e[3] = float(x_lo)
	e[4] = float(y_lo)
	e[5] = float(x_hi - x_lo)
	e[6] = float(y_hi - y_lo)


static func clear_line_cache() -> void:
	_line_cache.clear()


## Strip rects of Art.line's walk from (0,0) to (ddx,ddy), merged along the major axis:
## flat [x, y, w, h, ...] relative to the start pixel.
static func _build_line(ddx: int, ddy: int, w: int) -> PackedFloat32Array:
	var dx := absi(ddx)
	var dy := -absi(ddy)
	var sx := 1 if ddx > 0 else -1
	var sy := 1 if ddy > 0 else -1
	var err := dx + dy
	var half := floori((w - 1) / 2.0)
	var x_major := dx >= -dy
	var x := 0
	var y := 0
	var out := PackedFloat32Array()
	var cur := Rect2i()
	var have := false
	while true:
		var r := Rect2i(x, y - half, 1, w) if x_major else Rect2i(x - half, y, w, 1)
		if have and x_major and r.position.y == cur.position.y and r.position.x == cur.end.x:
			cur.size.x += 1
		elif have and x_major and r.position.y == cur.position.y and r.end.x == cur.position.x:
			cur.position.x -= 1
			cur.size.x += 1
		elif have and (not x_major) and r.position.x == cur.position.x and r.position.y == cur.end.y:
			cur.size.y += 1
		elif have and (not x_major) and r.position.x == cur.position.x and r.end.y == cur.position.y:
			cur.position.y -= 1
			cur.size.y += 1
		else:
			if have:
				out.append_array(PackedFloat32Array([cur.position.x, cur.position.y, cur.size.x, cur.size.y]))
			cur = r
			have = true
		if x == ddx and y == ddy:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	if have:
		out.append_array(PackedFloat32Array([cur.position.x, cur.position.y, cur.size.x, cur.size.y]))
	return out
