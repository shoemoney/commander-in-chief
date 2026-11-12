class_name BannersPolish
extends RefCounted
## View-only look for the top-center message banners and the small in-world plates.
##
## Banners used to be bare gold glyphs on a feathered soft-edged smear that reached 6px past its
## own rect (under the HUD corner plate) and whose thin strokes the CRT scanlines striped. Now a
## banner is a crisp chamfered plate with accent end caps, a bold two-pass lettering and a
## wipe-open / wipe-closed entrance that never leaves the plate's own rect, so the band rows
## main.band_rows() deals are exactly the pixels that get painted.

const PLATE_FILL := Color(0.035, 0.04, 0.03, 0.93)
const CAP_W := 3.0           # inner inset kept clear at each end of the plate
const CAP_NOTCH_H := 4.0     # corner notch tick height
const ENTER_T := 0.92        # banner t (1 -> 0) above which the plate wipes open
const ENTER_DROP := 4.0      # px the banner rises into place
const EXIT_T := 0.14         # banner t below which the plate wipes closed
const ROW0_H := 24.0         # tallest alert plate (size 16 + 7 = 23) and a 1px gap: row 0's reserve
const LABEL_GAP := 3.0       # clear px kept between a banner plate and any world label
const LABEL_PIN := 4.0       # pointer triangle height


## Plate top edge -> text baseline. banner_plate_rect puts the plate top at baseline - size - 2,
## so a row whose TOP is `top` has its baseline here. (The rail used to hand out the BASELINE,
## which let the plate's top 18px reach up under the HUD corner plate.)
static func baseline_for_top(top: float, size: int) -> float:
	return top + float(size) + 2.0


## Entrance / exit state for a banner whose life fraction is `bt` (1 -> 0). Returns {r, a, dy}:
## r the plate's width fraction, a the plate/ink alpha, dy a small downward offset in px.
## Entrance: the banner is ALREADY readable on its first frame (a staged still at t = 1.0 shows
## the whole plate) and settles up into place from 4px low while the ink firms up. Exit: the
## plate wipes closed toward its centre while the ink fades. Reduce-motion is static: full
## width, fully opaque, until the banner is gone.
static func anim(bt: float, motion: float) -> Dictionary:
	if bt <= 0.01:
		return {"r": 0.0, "a": 0.0, "dy": 0.0}
	if motion < 0.5:
		return {"r": 1.0, "a": 1.0, "dy": 0.0}
	var e_in := clampf((1.0 - bt) / (1.0 - ENTER_T), 0.0, 1.0)
	e_in = 1.0 - pow(1.0 - e_in, 3.0)
	var e_out := 1.0 - pow(1.0 - clampf(bt / EXIT_T, 0.0, 1.0), 3.0)
	return {"r": e_out, "a": minf(lerpf(0.85, 1.0, e_in), clampf((e_out - 0.2) / 0.8, 0.0, 1.0)),
		"dy": roundf((1.0 - e_in) * ENTER_DROP)}


## The plate as painted at wipe fraction `r`: centered width scaling, whole pixels, and never
## outside `full` (so it can never exceed the footprint band_rows() reserved).
static func wiped_rect(full: Rect2, r: float) -> Rect2:
	var cx := full.position.x + full.size.x / 2.0
	var w := roundf(full.size.x * clampf(r, 0.0, 1.0))
	return Rect2(roundf(cx - w / 2.0), roundf(full.position.y), w, roundf(full.size.y))


static func _chamfer(ci: CanvasItem, b: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(b.position.x, b.position.y + 1.0, b.size.x, b.size.y - 2.0), col)
	ci.draw_rect(Rect2(b.position.x + 1.0, b.position.y, b.size.x - 2.0, 1.0), col)
	ci.draw_rect(Rect2(b.position.x + 1.0, b.end.y - 1.0, b.size.x - 2.0, 1.0), col)


## The banner plate: dark chamfered slab, accent keylines top and bottom, solid accent end caps.
## `a` scales every alpha. Whole-pixel rects only, so nothing resamples under the CRT pass.
static func draw_plate(ci: CanvasItem, full: Rect2, accent: Color, a: float, r := 1.0) -> void:
	if a <= 0.01:
		return
	var b := wiped_rect(full, r)
	if b.size.x < 8.0:
		return
	_chamfer(ci, b, Color(PLATE_FILL.r, PLATE_FILL.g, PLATE_FILL.b, PLATE_FILL.a * a))
	var rule := Color(accent.r, accent.g, accent.b, 0.75 * a)
	ci.draw_rect(Rect2(b.position.x + 1.0, b.position.y, b.size.x - 2.0, 1.0), rule)
	ci.draw_rect(Rect2(b.position.x + 1.0, b.end.y - 1.0, b.size.x - 2.0, 1.0), rule)
	# End treatment: four corner notches (a short accent tick tucked under the top rule and over
	# the bottom rule at each end), so the plate closes like a bracket, not a pipe character.
	var cap := Color(accent.r, accent.g, accent.b, 0.95 * a)
	var nh := CAP_NOTCH_H
	for nx in [b.position.x, b.end.x - 2.0]:
		ci.draw_rect(Rect2(nx, b.position.y + 1.0, 2.0, nh), cap)
		ci.draw_rect(Rect2(nx, b.end.y - 1.0 - nh, 2.0, nh), cap)
	var inner_w := b.size.x - 2.0 * CAP_W - 2.0
	ci.draw_rect(Rect2(b.position.x + CAP_W + 1.0, b.position.y + 1.0, inner_w, 1.0), Color(1, 1, 1, 0.12 * a))
	# accent-tinted upper half and a dim inner keyline: a lit enamel plate, not a flat slab
	ci.draw_rect(Rect2(b.position.x + CAP_W + 1.0, b.position.y + 2.0, inner_w, floorf((b.size.y - 4.0) / 2.0)),
		Color(accent.r, accent.g, accent.b, 0.14 * a))
	ci.draw_rect(Rect2(b.position.x + CAP_W + 1.0, b.end.y - 3.0, inner_w, 1.0),
		Color(accent.r, accent.g, accent.b, 0.30 * a))


## Solid lettering: a hard black rim, a drop row, then the colour drawn twice one pixel apart so
## every stroke is at least two pixels wide and the scanline pass cannot cut it into stripes.
static func draw_lettering(ci: CanvasItem, txt: String, cx: float, baseline: float, size: int,
		col: Color, a := 1.0) -> void:
	if a <= 0.01:
		return
	if Art.text_capture != null:
		Art.text_center(ci, txt, cx, baseline, size, Color(col.r, col.g, col.b, a))
		return
	var f := Art.font()
	var w := Art.tw(txt, size) + 1.0
	var p := Vector2(floorf(cx - w / 2.0), floorf(baseline))
	ci.draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 3, Color(0, 0, 0, 0.9 * a))
	ci.draw_string(f, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Color(0, 0, 0, 0.8 * a))
	ci.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Color(col.r, col.g, col.b, a))


## The small plate every in-world label, tally and marker shares: dark chamfered slab, a 1px
## accent keyline along the top and a 2px accent pip on the left. With `anchor` set, a pointer
## triangle drops from the plate (or rises, when the subject is above it) toward what it labels.
static func draw_label_plate(ci: CanvasItem, r: Rect2, accent: Color, anchor := Vector2.INF,
		a := 1.0) -> void:
	var b := Rect2(r.position.round(), r.size.round())
	_chamfer(ci, b, Color(PLATE_FILL.r, PLATE_FILL.g, PLATE_FILL.b, 0.92 * a))
	ci.draw_rect(Rect2(b.position.x + 1.0, b.position.y, b.size.x - 2.0, 1.0),
		Color(accent.r, accent.g, accent.b, 0.7 * a))
	ci.draw_rect(Rect2(b.position.x, b.position.y + 2.0, 2.0, maxf(b.size.y - 4.0, 1.0)),
		Color(accent.r, accent.g, accent.b, 0.95 * a))
	if anchor != Vector2.INF:
		draw_pointer(ci, b, anchor, accent, a)


## Pointer geometry: base on the plate edge nearest the anchor, tip LABEL_PIN px toward it,
## base x clamped inside the plate. Pure so a test can assert it.
static func pointer_points(b: Rect2, anchor: Vector2) -> PackedVector2Array:
	var below := anchor.y >= b.get_center().y
	var px := clampf(anchor.x, b.position.x + 4.0, b.end.x - 4.0)
	var y0 := b.end.y if below else b.position.y
	var dir := 1.0 if below else -1.0
	return PackedVector2Array([Vector2(px - 3.0, y0), Vector2(px + 3.0, y0),
		Vector2(px, y0 + dir * LABEL_PIN)])


static func draw_pointer(ci: CanvasItem, b: Rect2, anchor: Vector2, accent: Color, a := 1.0) -> void:
	var pts := pointer_points(b, anchor)
	ci.draw_colored_polygon(pts, Color(PLATE_FILL.r, PLATE_FILL.g, PLATE_FILL.b, 0.92 * a))
	var tip := pts[2]
	ci.draw_rect(Rect2(floorf(tip.x), floorf(tip.y), 1.0, 1.0), Color(accent.r, accent.g, accent.b, 0.9 * a))
