class_name InfantryPolish
extends RefCounted
## View-only enemy-infantry readability. The sprites carry a baked ink keyline plus a pale
## inner rim (tools/gen_infantry.py); this adds the ground side: a pale contact pad under a
## hostile so a dark-brown soldier is lifted off dark grass and sand alike.

const PAD_KINDS := ["rusher", "smg", "shotgun", "lmg", "sniper", "grenadier", "elite", "sapper", "ghillie"]
const PAD_SIZE := Vector2(26.0, 16.0)
const PAD_OFFSET := Vector2(-13.0, -5.0)
const PAD_COL := Color(1.0, 0.82, 0.55)


static func pad_alpha(kind: String, submerged: bool) -> float:
	if submerged or not PAD_KINDS.has(kind):
		return 0.0
	return 0.55 if kind == "sniper" or kind == "ghillie" else 0.45


static func pad_rect(pos: Vector2) -> Rect2:
	return Rect2(pos + PAD_OFFSET, PAD_SIZE)


## Draws the pad on `canvas` (the main node). Returns true when something was drawn.
static func draw_pad(canvas: CanvasItem, tex: Texture2D, pos: Vector2, kind: String,
		submerged: bool) -> bool:
	var a := pad_alpha(kind, submerged)
	if a <= 0.0 or tex == null:
		return false
	canvas.draw_texture_rect(tex, pad_rect(pos), false, Color(PAD_COL.r, PAD_COL.g, PAD_COL.b, a))
	return true
