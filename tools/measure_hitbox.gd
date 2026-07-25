extends SceneTree
## Hitbox-fairness measuring tape (dev tool, not part of the suite).
##
##   godot --headless --path . -s res://tools/measure_hitbox.gd
##
## Prints, for every gameplay sprite, the size the player ACTUALLY sees:
## imported texture px x art.gd SCALE x the main.gd call-site spr_scale, and —
## the number that matters — the OPAQUE alpha bbox, since these bakes are mostly
## transparent padding and the canvas overstates every silhouette by ~1.7x.
## Sim world units are screen px 1:1, so a `N * F_ONE` radius in sim_world.gd
## compares directly against the half-extents printed here.
##
## tests/test_hitbox_fairness.gd asserts the ratios; this is for eyeballing them
## and for re-deriving a SCALE row after a sprite is re-baked or re-imported.
const Art = preload("res://src/view/art.gd")
func _init():
	var calls := {
		"player1": 0.52, "player2": 0.52,
		"enemy_smg": 0.5, "enemy_assault": 0.62, "enemy_sniper": 0.5,
		"enemy_shotgun": 0.5, "enemy_lmg": 0.5,
		"frogman": 0.5, "frogman_speargun": 0.4,
		"ghillie": 0.5, "sapper": 0.5, "courier": 0.5,
		"m_soldier2": 0.52, "m_bombsuit": 0.55, "m_drone": 0.5,
		"m_technical": 0.55, "tank_body": 0.62, "tank_hulk": 0.62,
		"colossus_body": 1.9, "gunship_body": 1.0,
		"bunker": 0.78, "bunker2": 0.78,
		"wep_claymore": 1.05, "m_radar_tank": 0.5,
	}
	for k in calls:
		if not Art.TEX.has(k):
			print("%-20s MISSING" % k)
			continue
		var t: Texture2D = Art.tex(k)
		if t == null:
			print("%-20s NULL" % k)
			continue
		var sz := t.get_size()
		var s: float = calls[k] * Art.draw_scale(k)
		var img := t.get_image()
		var x0 := int(sz.x)
		var y0 := int(sz.y)
		var x1 := -1
		var y1 := -1
		for y in int(sz.y):
			for x in int(sz.x):
				if img.get_pixel(x, y).a > 0.35:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		var ow := (x1 - x0 + 1) * s
		var oh := (y1 - y0 + 1) * s
		print("%-20s tex=%dx%d scale=%.4f canvas=%.1fx%.1f OPAQUE=%.1fx%.1f half=%.1f/%.1f" % [
			k, sz.x, sz.y, s, sz.x * s, sz.y * s, ow, oh, ow / 2.0, oh / 2.0])
	quit()
