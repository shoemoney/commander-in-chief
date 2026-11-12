class_name MenuPolish
extends RefCounted
## One menu identity: a single steel-olive base with ONE brass accent, shared by every
## framed screen (pause, options, accessibility, rebind, chapters, how-to, hall, record).
## VIEW-ONLY. Pure palette + geometry helpers; menu.gd calls them from its draw functions,
## so every screen that draws a row, a back plate or a header wears the same kit.

const BRASS := Color(0.96, 0.82, 0.42)          # the one accent: focus, rules, trim
const BRASS_HI := Color(1.0, 0.95, 0.72)        # focus ring core / specular
const BRASS_DIM := Color(0.62, 0.52, 0.28, 0.85)  # resting trim
const CHROME_TINT := Color(0.70, 0.62, 0.42)    # multiplied into the frame + ambience on EVERY screen
const PLATE_REST := Color(0.36, 0.43, 0.36, 0.9)  # resting button slab: darker steel-green than the old lime
const HI_EDGE := Color(1.0, 1.0, 0.92, 0.26)    # bevel light edge
const LO_EDGE := Color(0.0, 0.0, 0.0, 0.38)     # bevel shade edge
const DROP := Color(0.0, 0.0, 0.0, 0.42)        # 1px contact shadow under a plate


## True while the player is physically pressing the focused control (Enter/pad A held, or
## the left mouse button held). Drives the sunken "pressed" bevel.
static func is_pressed() -> bool:
	return Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Bevel rects for a plate: raised normally, sunken when pressed. Pure so a test can read
## the geometry. Each entry is {"r": Rect2, "c": Color}. `b` is the plate's outer rect.
static func bevel_rects(b: Rect2, selected: bool, pressed: bool, disabled: bool) -> Array:
	var out: Array = []
	var inner := Rect2(b.position.round(), b.size.round()).grow(-1.0)
	if inner.size.x < 12.0 or inner.size.y < 6.0:
		return out
	var ch := 3.0
	var k := 0.5 if disabled else 1.0
	var hi := Color(HI_EDGE.r, HI_EDGE.g, HI_EDGE.b, HI_EDGE.a * k * (1.35 if selected else 1.0))
	var lo := Color(LO_EDGE.r, LO_EDGE.g, LO_EDGE.b, LO_EDGE.a * k)
	if pressed and not disabled:
		var t := hi
		hi = lo
		lo = Color(t.r, t.g, t.b, t.a * 0.6)
	var w := inner.size.x - 2.0 * ch
	out.append({"r": Rect2(inner.position.x + ch, inner.position.y, w, 1.0), "c": hi})
	out.append({"r": Rect2(inner.position.x, inner.position.y + ch, 1.0, inner.size.y - 2.0 * ch), "c": hi})
	out.append({"r": Rect2(inner.position.x + ch, inner.end.y - 2.0, w, 1.0), "c": lo})
	out.append({"r": Rect2(inner.end.x - 1.0, inner.position.y + ch, 1.0, inner.size.y - 2.0 * ch), "c": lo})
	return out


## Contact shadow under the plate: sells the raised slab. Dropped when pressed (it is flush).
static func shadow_rect(b: Rect2, pressed: bool) -> Rect2:
	if pressed:
		return Rect2()
	return Rect2(b.position.x + 3.0, b.end.y, b.size.x - 6.0, 1.0)


static func draw_plate_depth(ci: CanvasItem, b: Rect2, selected: bool, pressed: bool, disabled: bool) -> void:
	var sh := shadow_rect(b, pressed)
	if sh.size.x > 0.0:
		ci.draw_rect(sh, DROP)
	for e in bevel_rects(b, selected, pressed, disabled):
		ci.draw_rect(e["r"], e["c"])


## The unmistakable focus state: a 2px brass ring hugging the plate plus two pointer
## wedges in the margins. `breath` is 0..1 (0 under reduce-motion = a steady, full-strength cue).
static func focus_cue(b: Rect2, breath: float) -> Dictionary:
	var a := 0.85 + 0.15 * breath
	var cy := floorf(b.position.y + b.size.y / 2.0)
	var h := minf(5.0, floorf(b.size.y / 3.0))
	return {
		"ring": b.grow(1.0),
		"ring_col": Color(BRASS.r, BRASS.g, BRASS.b, a),
		"core_col": Color(BRASS_HI.r, BRASS_HI.g, BRASS_HI.b, a),
		"left": PackedVector2Array([Vector2(b.position.x - 8.0, cy - h), Vector2(b.position.x - 8.0, cy + h),
			Vector2(b.position.x - 3.0, cy)]),
		"right": PackedVector2Array([Vector2(b.end.x + 8.0, cy - h), Vector2(b.end.x + 8.0, cy + h),
			Vector2(b.end.x + 3.0, cy)]),
	}


static func draw_focus(ci: CanvasItem, b: Rect2, breath: float, pointers := true) -> void:
	var f := focus_cue(b, breath)
	var rr: Rect2 = f["ring"]
	ci.draw_rect(rr, f["ring_col"], false, 2.0)
	ci.draw_rect(b, f["core_col"], false, 1.0)
	if pointers:
		ci.draw_colored_polygon(f["left"], f["ring_col"])
		ci.draw_colored_polygon(f["right"], f["ring_col"])


## Header ornament: a hairline brass rule with a centre diamond, seated under the header
## block so every screen's title shares one treatment. `a` is the open-settle alpha.
static func header_rule_rects(cx: float, y: float, half_w: float, a: float, compact := false) -> Array:
	var out: Array = []
	var gap := 6.0
	var c := Color(BRASS.r, BRASS.g, BRASS.b, 0.75 * a)
	var d := Color(BRASS_DIM.r, BRASS_DIM.g, BRASS_DIM.b, a)
	out.append({"r": Rect2(cx - half_w, y, half_w - gap, 1.0), "c": d})
	out.append({"r": Rect2(cx + gap, y, half_w - gap, 1.0), "c": d})
	out.append({"r": Rect2(cx - half_w, y - 1.0, 3.0, 3.0), "c": c})
	out.append({"r": Rect2(cx + half_w - 3.0, y - 1.0, 3.0, 3.0), "c": c})
	if not compact:   # dense OPTS/REBIND headers have no room for the centre diamond
		out.append({"r": Rect2(cx - 1.0, y - 2.0, 2.0, 5.0), "c": c})
		out.append({"r": Rect2(cx - 2.0, y - 1.0, 5.0, 3.0), "c": c})
	return out


## Open/close ease for the settle alpha: cubic-out, and flat 1.0 under reduce-motion.
static func ease_open(t: float, motion: float) -> float:
	if motion < 0.5:
		return 1.0
	var u := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)
