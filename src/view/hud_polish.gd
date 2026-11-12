class_name HudPolish
extends RefCounted
## HUD POLISH: the solid status plate, icon trays and crisp keycaps. View-only.
##
## The corner plate used to be a 65%-alpha texture over the terrain, its icons sat straight on that
## smoke, and the prompt-rail keycaps were a scaled 256px key texture with a 6px letter. This module
## owns the pure geometry/colours for the replacement; hud.gd routes its draw seams through it.
## Everything here is immediate-mode friendly: static helpers, no allocation beyond small arrays.

const PLATE_FILL := Color(0.045, 0.06, 0.05, 0.74)    # see-through body: enemies entering under the plate stay readable; text keeps its outline/shadow
const PLATE_GRAIN := Color(1, 1, 1, 0.16)             # the old metal texture, kept only as faint grain
const EDGE_HI := Color(0.66, 0.74, 0.62, 0.95)        # outer rule
const EDGE_LO := Color(0.0, 0.0, 0.0, 0.55)           # inner shade just inside the rule
const DIVIDER := Color(0.55, 0.64, 0.52, 0.30)        # hairline between the header and the player rows
const TRAY_FILL := Color(0.02, 0.03, 0.025, 0.92)
const TRAY_EDGE := Color(0.42, 0.50, 0.40, 0.75)
const TRAY_CAP := 48                                  # per-frame ceiling on queued trays

const KEY_RIM := Color(0.05, 0.055, 0.045)
const KEY_FACE := Color(0.96, 0.95, 0.88)
const KEY_SIDE := Color(0.62, 0.61, 0.54)
const KEY_INK := Color(0.07, 0.08, 0.06)
const KEY_FONT := 8       # the bitmap face's native em: the only size whose strokes land on whole pixels
const KEY_EXTRA_H := 2.0  # the cap stands this much taller than its reserved slot so the legend has margin

## Chip trays queued during the row passes and flushed under the plate texture, so each icon sits
## on a dark tile with a keyline rather than on translucent smoke.
var _trays: Array[Rect2] = []


func begin_frame() -> void:
	_trays.clear()


func queue_tray(icon_rect: Rect2) -> void:
	if _trays.size() < TRAY_CAP:
		_trays.append(icon_rect.grow(1.0))


func trays() -> Array[Rect2]:
	return _trays


## The plate's solid fill rects for a header/body union. `body` is a zero-area rect when absent.
static func fill_rects(header: Rect2, body: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = [header]
	if body.has_area():
		out.append(body)
	return out


## Where the hairline between the header block and the player rows sits.
static func divider_y(rows_top: float) -> float:
	return rows_top - 3.0


## Pure keycap geometry for a cap `w` x `h` centred on `center`. Four rects: the dark rim (an
## octagon-ish union of two rects so the corners read as rounded), the face, the face's lower side
## (the key's 3D depth) and the ink baseline y for the legend.
static func keycap_geometry(center: Vector2, w: float, h: float) -> Dictionary:
	var x := roundf(center.x - w / 2.0)
	var y := roundf(center.y - h / 2.0)
	var wi := roundf(w)
	var hi := roundf(h)
	return {
		"rim_a": Rect2(x + 1.0, y, wi - 2.0, hi),
		"rim_b": Rect2(x, y + 1.0, wi, hi - 2.0),
		"face": Rect2(x + 1.0, y + 1.0, wi - 2.0, hi - 4.0),
		"side": Rect2(x + 1.0, y + hi - 3.0, wi - 2.0, 2.0),
		"mid_x": x + wi / 2.0,
		"face_mid_y": y + 1.0 + (hi - 4.0) / 2.0,
	}


## Draw a keyboard keycap with a legible legend. `mod` carries alpha/dim from the caller.
static func draw_keycap(ci: CanvasItem, center: Vector2, w: float, h: float, letter: String, mod: Color) -> void:
	var g := keycap_geometry(center, w, h)
	ci.draw_rect(g["rim_a"], Color(KEY_RIM.r, KEY_RIM.g, KEY_RIM.b, mod.a))
	ci.draw_rect(g["rim_b"], Color(KEY_RIM.r, KEY_RIM.g, KEY_RIM.b, mod.a))
	var side: Rect2 = g["side"]
	ci.draw_rect(side, KEY_SIDE * Color(mod.r, mod.g, mod.b, mod.a))
	ci.draw_rect(g["face"], KEY_FACE * Color(mod.r, mod.g, mod.b, mod.a))
	if letter == "":
		return
	var f := Art.font()
	var fs := KEY_FONT
	var lw := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := roundf(float(g["face_mid_y"]) + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0)
	ci.draw_string(f, Vector2(roundf(float(g["mid_x"]) - lw / 2.0), base), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(KEY_INK.r, KEY_INK.g, KEY_INK.b, mod.a))


## True when the glyph should be the procedural keycap (keyboard devices); pad buttons keep the
## baked textures, which are already legible.
static func uses_keycap(force_pad: bool) -> bool:
	return not (Art.use_pad or force_pad)


## Draw an act glyph centred on `center`: procedural keycap on keyboard, baked pad art otherwise.
## The cap width is Art.glyph_cap_w's, so every caller's reserved advance is unchanged.
static func draw_act_glyph(ci: CanvasItem, act: String, center: Vector2, size: float, mod: Color,
		force_pad: bool, keycode: int, pad_button: int) -> void:
	if not uses_keycap(force_pad):
		Art.draw_glyph(ci, act, center, size, mod, force_pad, keycode, pad_button)
		return
	var w := Art.glyph_cap_w(act, size, keycode, pad_button, force_pad)
	draw_keycap(ci, center, w, size + KEY_EXTRA_H, Art._glyph_letter(act, keycode), mod)
