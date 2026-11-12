extends RefCounted
## Enemy infantry readability: role-distinct baked palettes + ground pad, wired into main.gd.

const Runner := preload("res://tests/run_tests.gd")

func _img(path: String) -> Image:
	return load(path).get_image()

func _mean_body(path: String, vmax := 1.01) -> Color:
	# Mean colour of the saturated body pixels (skips the ink keyline, boots, steel, skin-light).
	var im := _img(path)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a < 0.5 or c.s < 0.35 or c.v < 0.3 or c.v > vmax:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	return Color(r / maxf(n, 1), g / maxf(n, 1), b / maxf(n, 1)) if n > 8 else Color(0, 0, 0)

func test_rusher_family_is_hot_red_against_green() -> void:
	for k in ["enemy_assault", "enemy_smg", "enemy_shotgun", "enemy_lmg"]:
		var c := _mean_body("res://assets/baked/%s/idle.png" % k)
		Runner.T.ok(c.r > 0.4 and c.r > c.g * 1.4 and c.r > c.b * 1.4, "%s body is hot red (%s)" % [k, c])

func test_sniper_and_elite_read_apart_from_rushers() -> void:
	var rush := _mean_body("res://assets/baked/enemy_assault/idle.png", 0.62)
	var snip := _mean_body("res://assets/baked/enemy_sniper/idle.png")
	var elite := _mean_body("res://assets/baked/enemy_elite/idle.png", 0.62)
	Runner.T.ok(snip.b > rush.b + 0.25, "sniper carries a magenta blue channel the rushers lack")
	Runner.T.ok(elite.r < rush.r - 0.08, "elite body is a darker maroon than a rusher (%s vs %s)" % [elite, rush])

func test_pad_rules() -> void:
	Runner.T.ok(InfantryPolish.pad_alpha("rusher", false) >= 0.4, "rifleman gets a clearly visible pad")
	Runner.T.eq(InfantryPolish.pad_alpha("rusher", true), 0.0, "submerged gets none")
	Runner.T.eq(InfantryPolish.pad_alpha("frogman", false), 0.0, "frogman gets none")
	Runner.T.eq(InfantryPolish.pad_alpha("drone", false), 0.0, "drone gets none")

func test_wired_into_draw_enemies() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("func _draw_enemies()")
	Runner.T.ok(i >= 0, "_draw_enemies exists")
	var j := src.find("\nfunc ", i + 10)
	Runner.T.ok(src.substr(i, j - i).contains("InfantryPolish.draw_pad("), "_draw_enemies calls the pad")
