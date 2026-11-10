class_name GroundDecor
extends RefCounted
## VIEW-ONLY biome dressing that replaces the desert cacti where a cactus is a lie:
## reeds and driftwood in the marsh, rubble and rebar on the bridge deck, scrap in the
## foundry / convoy / core. Pure draw helpers; the placement grid (and so every
## position) stays main.gd's cactus grid, which is view-only (it never reads or writes
## sim state, and none of it blocks anything).
##
## HONESTY RULE: all of it is FLAT, small (<= ~14px) and low-contrast, with no rim, no
## shadow and no sprite outline, so none of it can read as cover. The real cover props
## (rocks, wrecks, sandbags, the flat dead cactus) are drawn by other code and untouched.

const MARSH := 2
const DECK := 3


## True where the desert cactus grid should be dressed as something else.
static func replaces_cactus(biome: int) -> bool:
	return biome >= MARSH


## Which dressing family a biome gets: "reeds", "rubble" or "scrap".
static func family(biome: int) -> String:
	if biome == MARSH:
		return "reeds"
	if biome == DECK:
		return "rubble"
	return "scrap"


static func _f(h: int, shift: int, span: int) -> float:
	return float((h >> shift) % span)


## Draw one dressing item at screen `pos`, shaped by hash `h`.
static func paint(canvas: CanvasItem, biome: int, pos: Vector2, h: int) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match family(biome):
		"reeds":
			if h % 5 == 0:
				_stick(canvas, pos, h)
			else:
				_reeds(canvas, pos, h)
		"rubble":
			_rubble(canvas, pos, h)
			if h % 3 == 0:
				_rebar(canvas, pos + Vector2(_f(h, 5, 9) - 4.0, _f(h, 9, 7) - 3.0), h)
		_:
			_scrap(canvas, pos, h, biome)


static func _reeds(canvas: CanvasItem, pos: Vector2, h: int) -> void:
	canvas.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2(8.0, 4.0), Vector2(16.0, 8.0)), false,
		Color(0.04, 0.06, 0.03, 0.22))
	var n := 7 + h % 3
	for i in n:
		var a := TAU * (float(i) + _f(h, 3 + i, 10) / 14.0) / float(n)
		var ln := 5.0 + _f(h, 7 + i, 5)
		var col := Color(0.34, 0.41, 0.21, 0.85) if (h >> (i + 2)) % 3 != 0 else Color(0.50, 0.52, 0.28, 0.85)
		canvas.draw_line(pos, pos + Vector2(cos(a), sin(a) * 0.8) * ln, col, 1.0)


## A thin pale stick of driftwood: flat, 3px, half transparent. Debris, not a barrier.
static func _stick(canvas: CanvasItem, pos: Vector2, h: int) -> void:
	var a := float(h % 628) / 100.0
	var half := Vector2(cos(a), sin(a)) * (9.0 + _f(h, 4, 7))
	canvas.draw_line(pos - half, pos + half, Color(0.30, 0.24, 0.16, 0.55), 3.0)
	canvas.draw_line(pos - half + Vector2(0.0, -1.0), pos + half + Vector2(0.0, -1.0), Color(0.46, 0.40, 0.30, 0.35), 1.0)


static func _rubble(canvas: CanvasItem, pos: Vector2, h: int) -> void:
	for i in 6:
		var hi := Art.cell_hash(h + i * 7, 91)
		var c := pos + Vector2(_f(hi, 2, 17) - 8.0, _f(hi, 6, 11) - 5.0)
		var r := 1.5 + _f(hi, 10, 3)
		var g := 0.42 + _f(hi, 13, 18) / 100.0
		var pts := PackedVector2Array([c + Vector2(-r, 0.3 * r), c + Vector2(-0.2 * r, -r), c + Vector2(r, -0.3 * r),
			c + Vector2(0.4 * r, r)])
		canvas.draw_colored_polygon(pts, Color(g * 0.9, g * 0.9, g * 0.92, 0.80))
		canvas.draw_line(c + Vector2(-r, 0.3 * r), c + Vector2(0.4 * r, r), Color(0.10, 0.10, 0.11, 0.35), 1.0)


static func _rebar(canvas: CanvasItem, pos: Vector2, h: int) -> void:
	for i in 2 + h % 2:
		var a := float(Art.cell_hash(h + i * 5, 92) % 628) / 100.0
		var half := Vector2(cos(a), sin(a)) * (6.0 + _f(h, 3 + i, 6))
		canvas.draw_line(pos - half, pos + half, Color(0.34, 0.20, 0.14, 0.85), 1.0)
		canvas.draw_rect(Rect2(pos + half - Vector2(0.5, 0.5), Vector2(1.5, 1.5)), Color(0.55, 0.32, 0.20, 0.9))


static func _scrap(canvas: CanvasItem, pos: Vector2, h: int, biome: int) -> void:
	var steel := Color(0.26, 0.26, 0.28, 0.88) if biome != 6 else Color(0.20, 0.17, 0.17, 0.88)
	for i in 3 + h % 3:
		var hi := Art.cell_hash(h + i * 11, 93)
		var c := pos + Vector2(_f(hi, 2, 19) - 9.0, _f(hi, 6, 11) - 5.0)
		var a := float(hi % 628) / 100.0
		var u := Vector2(cos(a), sin(a)) * (2.5 + _f(hi, 9, 4))
		var v := Vector2(-u.y, u.x) * 0.55
		var pts := PackedVector2Array([c - u - v, c + u - v * 0.4, c + u * 0.6 + v, c - u * 0.7 + v])
		var rust := (hi >> 14) % 3 == 0
		canvas.draw_colored_polygon(pts, Color(0.42, 0.22, 0.13, 0.85) if rust else steel)
		canvas.draw_line(c - u - v, c + u - v * 0.4, Color(0.62, 0.60, 0.58, 0.30), 1.0)
