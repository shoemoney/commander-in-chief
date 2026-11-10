extends RefCounted
## The infantry sprites are BAKED to their on-screen size (tools/bake_sprites.py)
## and drawn at NET scale 1.0. These tests measure the textures Art actually
## serves and the scale the draw path actually applies; nothing here reads a
## number that this change edited and then compares it to itself.
##
## Footprint table (px at the 640x360 viewport, alpha>0.35 bbox of the idle pose):
##   hero 26x30, rifleman skins ~16x26, sniper 12x26, elite 18x32.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")

## key -> [canonical call scale read off main.gd, min w, max w, min h, max h]
## (bounds bracket the measured idle footprint by about +-3px so a re-bake
## that drifts is caught, while an unrelated re-export is not).
const FOOTPRINT := {
	"player1": [0.52, 23, 31, 27, 36],
	"enemy_assault": [0.52, 13, 20, 23, 31],
	"enemy_smg": [0.52, 11, 18, 23, 31],
	"enemy_shotgun": [0.52, 13, 20, 23, 31],
	"enemy_lmg": [0.52, 13, 20, 23, 31],
	"enemy_sniper": [0.5, 9, 16, 23, 31],
}


func _opaque_bbox(img: Image) -> Vector2i:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Vector2i(x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Vector2i.ZERO


func _image(t: Texture2D) -> Image:
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	return img


func test_baked_keys_draw_at_net_scale_one() -> void:
	var ms: Dictionary = load("res://src/main.gd").get_script_constant_map()
	var rifle: float = ms["LIVE_RIFLEMAN_SCALE"]
	Runner.T.eq(rifle, 0.52, "the rifleman call scale the bake assumes")
	for key in FOOTPRINT:
		var call: float = FOOTPRINT[key][0]
		if key.begins_with("enemy_") and key != "enemy_sniper":
			call = rifle
		Runner.T.ok(absf(call * Art.draw_scale(key) - 1.0) < 1e-6,
			"%s draws at net scale 1.0 (call %.2f x SCALE %.4f)" % [key, call, Art.draw_scale(key)])
	Runner.T.ok(absf(Art.draw_scale("player2") - Art.draw_scale("player1")) < 1e-9,
		"P2 shares the hero bake, so it shares the hero scale")
	for key in ["frogman", "frogman_speargun"]:
		Runner.T.ok(absf(0.5 * Art.draw_scale(key) - 1.0) < 1e-6, "%s draws at net scale 1.0" % key)
	Runner.T.eq(float(ms["PLAYER_POSE_X_STRETCH"]), 1.0,
		"the hero's x-stretch is baked in; a runtime stretch would resample the bake")


func test_baked_footprint_is_measured_off_the_served_textures() -> void:
	for key in FOOTPRINT:
		var f: Array = FOOTPRINT[key]
		var t: Texture2D = Art.player_anim("idle") if key == "player1" else Art.enemy_anim(key, "idle")
		Runner.T.ok(t.resource_path.contains("/assets/baked/"),
			"%s idle pose is served from assets/baked (%s)" % [key, t.resource_path])
		var bb := _opaque_bbox(_image(t))
		Runner.T.ok(bb.x >= f[1] and bb.x <= f[2] and bb.y >= f[3] and bb.y <= f[4],
			"%s idle footprint %dx%d px inside %d-%d x %d-%d" % [key, bb.x, bb.y, f[1], f[2], f[3], f[4]])


func test_elite_has_its_own_larger_bake() -> void:
	Runner.T.ok(Art.ENEMY_ANIM.has("enemy_elite"), "the elite has its own pose set")
	var e := _opaque_bbox(_image(Art.enemy_anim("enemy_elite", "idle")))
	var r := _opaque_bbox(_image(Art.enemy_anim("enemy_assault", "idle")))
	Runner.T.ok(e.y > r.y and e.x > r.x,
		"elite (%dx%d) is drawn larger than the rifleman (%dx%d)" % [e.x, e.y, r.x, r.y])
	var ratio := float(e.y) / float(r.y)
	Runner.T.ok(ratio > 1.1 and ratio < 1.3, "elite is ~1.19x the rifleman (%.2f)" % ratio)


func test_every_baked_pose_has_a_hard_alpha_edge_and_a_small_palette() -> void:
	var sets: Array = []
	for pose in Art.PLAYER_ANIM:
		sets.append(["hero/" + pose, Art.PLAYER_ANIM[pose]])
	for key in Art.ENEMY_ANIM:
		for pose in Art.ENEMY_ANIM[key]:
			sets.append([key + "/" + pose, Art.ENEMY_ANIM[key][pose]])
	for key in ["player1", "enemy_smg", "frogman", "frogman_speargun"]:
		sets.append([key + "/base", Art.tex(key)])
	for row in sets:
		var img := _image(row[1])
		var soft := 0
		var colors := {}
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.01 and c.a < 0.99:
					soft += 1
				if c.a > 0.5:
					colors[c.to_rgba32()] = true
		Runner.T.eq(soft, 0, "%s has no semi-transparent pixels" % row[0])
		Runner.T.ok(colors.size() <= 48, "%s uses %d colours (<=48)" % [row[0], colors.size()])
		Runner.T.ok(maxi(img.get_width(), img.get_height()) <= 48,
			"%s canvas is screen-sized, not a master (%dx%d)" % [row[0], img.get_width(), img.get_height()])
