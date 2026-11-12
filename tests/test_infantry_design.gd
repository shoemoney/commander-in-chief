extends RefCounted
## The infantry are DESIGNED top-down at native size (tools/gen_infantry.py).
## Everything here is measured off the textures Art serves (times the tint the
## draw path applies), never off a constant the generator wrote.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")

const HOSTILE_KEYS := ["enemy_assault", "enemy_smg", "enemy_shotgun", "enemy_lmg", "enemy_sniper"]


func _style(k: String) -> String:
	return "enemy_assault" if k == "enemy_elite" else k   # the elite draws as enemy_assault


func _img(t: Texture2D) -> Image:
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	return img


## Mean luma and mean (r-b) of the opaque, non-ink pixels AFTER the draw-time tint.
func _tinted_stats(t: Texture2D, key: String) -> Vector2:
	var img := _img(t)
	var tint: Color = Art.tint(key)
	var luma := 0.0
	var warm := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var r := minf(c.r * tint.r, 1.0)
			var g := minf(c.g * tint.g, 1.0)
			var b := minf(c.b * tint.b, 1.0)
			var l := 0.299 * r + 0.587 * g + 0.114 * b
			if l < 0.12:
				continue   # the ink keyline / boots do not describe the uniform
			luma += l
			warm += r - b
			n += 1
	return Vector2(luma / maxf(n, 1), warm / maxf(n, 1))


func _row_width(img: Image, y: int) -> int:
	var n := 0
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.5:
			n += 1
	return n


func _top_row(img: Image) -> int:
	for y in img.get_height():
		if _row_width(img, y) > 0:
			return y
	return -1


func test_hero_reads_apart_from_every_hostile_by_value_and_hue() -> void:
	var hero := _tinted_stats(Art.player_anim("idle"), "player1")
	for k in HOSTILE_KEYS + ["enemy_elite"]:
		var key: String = "enemy_assault" if k == "enemy_elite" else k
		var s := _tinted_stats(Art.enemy_anim(k, "idle"), key)
		Runner.T.ok(hero.x > s.x + 0.04,
			"hero is brighter than %s by >0.04 (%.2f vs %.2f mean luma)" % [k, hero.x, s.x])
		if k == "enemy_sniper":
			# The sniper is cold steel-blue (the lethal-bolt magenta is reserved), so it
			# separates from the hero by being clearly bluer, not warmer.
			Runner.T.ok(s.y < hero.y - 0.05 and hero.y < 0.0,
				"%s is bluer (r-b %.2f) than the hero (r-b %.2f)" % [k, s.y, hero.y])
			continue
		Runner.T.ok(s.y > 0.12 and hero.y < 0.0,
			"%s is warm (r-b %.2f) while the hero is cool (r-b %.2f)" % [k, s.y, hero.y])


func test_every_idle_pose_pokes_a_narrow_barrel_toward_the_facing_edge() -> void:
	# The facing is the TOP of the image. A soldier whose topmost opaque row is a
	# wide blob has no readable gun; a designed one ends in a 3-5px barrel.
	for k in HOSTILE_KEYS + ["enemy_elite"]:
		var img := _img(Art.enemy_anim(k, "idle"))
		var top := _top_row(img)
		var w := _row_width(img, top + 1)
		Runner.T.ok(w <= 5, "%s barrel tip is narrow at the facing edge (%d px wide)" % [k, w])
	var himg := _img(Art.player_anim("idle"))
	Runner.T.ok(_row_width(himg, _top_row(himg) + 1) <= 5, "hero barrel tip is narrow at the facing edge")


func test_the_head_band_carries_a_bright_highlight() -> void:
	# The head sits over the shoulders (middle of the sprite's height) and holds
	# a highlight at least 60% as bright as the brightest pixel anywhere.
	for k in HOSTILE_KEYS + ["enemy_elite"]:
		var img := _img(Art.enemy_anim(k, "idle"))
		var h := img.get_height()
		var best := 0.0
		var band := 0.0
		for y in h:
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var l := c.get_luminance()
				best = maxf(best, l)
				if float(y) / float(h) >= 0.3 and float(y) / float(h) <= 0.65:
					band = maxf(band, l)
		Runner.T.ok(band >= best * 0.6, "%s head band highlight %.2f vs global max %.2f" % [k, band, best])


func test_walk_frames_actually_alternate() -> void:
	for k in HOSTILE_KEYS + ["enemy_elite"]:
		var a := _img(Art.enemy_anim(k, "move_0"))
		var b := _img(Art.enemy_anim(k, "move_1"))
		var diff := 0
		for y in mini(a.get_height(), b.get_height()):
			for x in mini(a.get_width(), b.get_width()):
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					diff += 1
		Runner.T.ok(diff >= 6, "%s move_0/move_1 differ in %d px (boots alternate)" % [k, diff])


func test_firing_pose_adds_a_muzzle_flash_pixel_at_the_tip() -> void:
	for k in HOSTILE_KEYS + ["enemy_elite"]:
		var img := _img(Art.enemy_anim(k, "shoot"))
		var top := _top_row(img)
		var bright := false
		for y in range(top, top + 4):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.r * Art.tint(_style(k)).r > 0.95 and c.g * Art.tint(_style(k)).g > 0.7:
					bright = true
		Runner.T.ok(bright, "%s shoot pose shows a muzzle flash within 4 rows of the tip" % k)
