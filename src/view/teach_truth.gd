class_name TeachTruth
extends RefCounted
## View-only helpers that keep what the screen says in step with what the sim does.
##
## GUNNER PIPS: riflemen ("rusher") and elites that are winding up a shot while OFF
## the frame. The sim only lets a gun OPEN fire from inside the player's band in Y
## (_in_fire_band), not in X, so a flank-door squad standing past the left/right edge
## can still wind up a shot at you. The sniper/grenadier/... pips never covered them.
## Pure functions of sim state: no new sim fields, nothing hashed.

const GUNNER_KINDS := ["rusher", "elite"]
const CLUSTER_CELL := 56.0   # screen px: gunners whose edge points fall in one cell share a pip
const MAX_PIPS := 3          # a whole breach squad never carpets an edge


## Up to MAX_PIPS dictionaries {edge, dir, count, left}, soonest-to-fire first. `to_screen`
## maps a sim (x, y) to a screen Vector2; plate_r / panel_b keep the pip out from under the
## opaque HUD corner plate, exactly as the other pips do.
static func gunner_pips(enemies: Array, to_screen: Callable, w: float, h: float,
		plate_r: float, panel_b: float) -> Array:
	var cells := {}
	for e in enemies:
		if not e["alive"] or int(e.get("windup", 0)) <= 0:
			continue
		if not GUNNER_KINDS.has(String(e["kind"])):
			continue
		var sp: Vector2 = to_screen.call(e["x"], e["y"])
		if sp.x >= 0.0 and sp.x <= w and sp.y >= 0.0 and sp.y <= h:
			continue   # on-screen: the body telegraph already covers it
		var edge := Vector2(clampf(sp.x, 12.0, w - 12.0), clampf(sp.y, 12.0, h - 12.0))
		if edge.x < plate_r and edge.y < panel_b:
			edge.y = panel_b
		var dir := (sp - edge).normalized()
		if dir == Vector2.ZERO:
			continue
		var key := Vector2i(int(edge.x / CLUSTER_CELL), int(edge.y / CLUSTER_CELL))
		var left := int(e["windup"])
		if cells.has(key):
			var c: Dictionary = cells[key]
			c["count"] = int(c["count"]) + 1
			c["left"] = mini(int(c["left"]), left)
		else:
			cells[key] = {"edge": edge, "dir": dir, "count": 1, "left": left}
	var out: Array = cells.values()
	out.sort_custom(func(a, b): return int(a["left"]) < int(b["left"]))
	if out.size() > MAX_PIPS:
		out.resize(MAX_PIPS)
	return out
