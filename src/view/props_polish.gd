class_name PropsPolish
extends RefCounted
## VIEW-ONLY prop volume: one sun for the whole game (north-west, the same side as
## main.gd's key rim), so every prop throws a soft elongated shadow to the SOUTH-EAST
## whose length follows its height, COVER wears a heavy dark base lip + contact core,
## DECOR does not, and per-instance tint keeps repeated props from reading as stamps.
## Pure draw helpers; nothing here reads or writes sim state.

const SUN_FROM := Vector2(-0.70710678, -0.70710678)
const SHADOW_DIR := Vector2(0.70710678, 0.70710678)
const SHADOW_ANGLE := PI / 4.0
const INK := Color(0.05, 0.04, 0.03)
const COVER_LIP_ALPHA := 0.62
const HEIGHT_ROCK := 13.0
const HEIGHT_SLAB := 9.0
const HEIGHT_WRECK := 20.0
const HEIGHT_BAG := 8.0
const HEIGHT_BUNKER := 16.0
const HEIGHT_BARREL := 9.0
const HEIGHT_CRATE := 6.0


## Centre and size of the cast-shadow card for a prop of half-width `hw` and height `h`.
static func shadow_rect(pos: Vector2, hw: float, h: float) -> Rect2:
	var length := hw * 1.4 + h * 1.7
	var width := maxf(hw * 1.1, 4.0)
	var centre := pos + Vector2(0.0, hw * 0.15) + SHADOW_DIR * (h * 0.8)
	return Rect2(centre - Vector2(length, width) * 0.5, Vector2(length, width))


## Soft directional cast shadow: a soft spot rotated onto the sun bearing.
static func cast_shadow(canvas: CanvasItem, pos: Vector2, hw: float, h: float, alpha := 0.40) -> void:
	var r := shadow_rect(pos, hw, h)
	var centre := r.position + r.size * 0.5
	canvas.draw_set_transform(centre.round(), SHADOW_ANGLE, Vector2.ONE)
	canvas.draw_texture_rect(Art.tex("fx_softspot"), Rect2(-r.size * 0.6, r.size * 1.2), false,
		Color(0.02, 0.03, 0.01, alpha * 0.9))
	canvas.draw_set_transform(centre.round(), SHADOW_ANGLE, r.size * 0.5 * 0.82)
	canvas.draw_colored_polygon(_unit_ellipse(), Color(0.02, 0.03, 0.01, alpha * 0.55))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static var _ellipse := PackedVector2Array()


static func _unit_ellipse() -> PackedVector2Array:
	if _ellipse.is_empty():
		for i in 14:
			var a := TAU * float(i) / 14.0
			_ellipse.append(Vector2(cos(a), sin(a)))
	return _ellipse


## COVER marker, drawn under the sprite: dark contact core + heavy base lip.
static func cover_base_round(canvas: CanvasItem, pos: Vector2, r: float, fade := 1.0) -> void:
	Art.circle(canvas, pos + Vector2(0.0, r * 0.28), r * 0.82, Color(INK.r, INK.g, INK.b, 0.30 * fade))
	Art.arc(canvas, pos + Vector2(0.0, 1.0), r, 0.05 * PI, 0.95 * PI, 14,
		Color(INK.r, INK.g, INK.b, 0.85 * fade), 3.0)


static func cover_base_rect(canvas: CanvasItem, rect: Rect2, fade := 1.0) -> void:
	var lip := Color(INK.r, INK.g, INK.b, COVER_LIP_ALPHA * fade)
	canvas.draw_rect(Rect2(rect.position + Vector2(-1.0, rect.size.y - 1.0), Vector2(rect.size.x + 2.0, 3.0)), lip)
	canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1.0, 1.0), Vector2(2.0, rect.size.y)),
		Color(INK.r, INK.g, INK.b, 0.4 * fade))
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, -1.0), Vector2(rect.size.x, 1.0)),
		Color(0.98, 0.95, 0.82, 0.25 * fade))


## Per-instance value/warmth multiplier so repeats are never identical (alpha stays 1).
static func tint_variant(h: int) -> Color:
	var v := 0.92 + float((h >> 3) % 9) * 0.015
	var warm := float((h >> 9) % 5) * 0.012
	return Color(v + warm, v, v - warm, 1.0)


## Vegetation sway angle (radians). Static (0) under reduce-motion.
static func sway(h: int, frames: int, motion: float, amp := 0.08) -> float:
	if motion < 0.5:
		return 0.0
	return sin(float(frames) * 0.035 + float(h % 1000) * 0.01) * amp * motion


## True for kinds that stop bullets and so get the heavy cover treatment.
static func is_cover_kind(kind: int) -> bool:
	return kind != 1
