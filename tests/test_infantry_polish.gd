extends RefCounted
## Enemy infantry readability: baked pale inner rim + ground pad, wired into main.gd.

const Runner := preload("res://tests/run_tests.gd")

func _img(path: String) -> Image:
	return load(path).get_image()

func test_baked_rim_lighter_than_body() -> void:
	# Hostile sprite: the pixels touching the keyline must be lighter than the interior mean.
	var im := _img("res://assets/baked/enemy_assault/idle.png")
	var edge := 0.0
	var inner := 0.0
	var ne := 0
	var ni := 0
	for y in range(1, im.get_height() - 1):
		for x in range(1, im.get_width() - 1):
			var c := im.get_pixel(x, y)
			if c.a < 0.5 or c.v < 0.12:
				continue
			var touches_ink := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := im.get_pixel(x + d.x, y + d.y)
				if n.a < 0.5 or n.v < 0.12:
					touches_ink = true
			if touches_ink:
				edge += c.v
				ne += 1
			else:
				inner += c.v
				ni += 1
	Runner.T.ok(ne > 10 and ni > 10, "sprite has rim and body pixels")
	Runner.T.ok(edge / maxf(ne, 1) > inner / maxf(ni, 1) + 0.05, "rim pixels read lighter than the body")

func test_pad_rules() -> void:
	Runner.T.ok(InfantryPolish.pad_alpha("rusher", false) > 0.0, "rifleman gets a pad")
	Runner.T.eq(InfantryPolish.pad_alpha("rusher", true), 0.0, "submerged gets none")
	Runner.T.eq(InfantryPolish.pad_alpha("frogman", false), 0.0, "frogman gets none")
	Runner.T.eq(InfantryPolish.pad_alpha("drone", false), 0.0, "drone gets none")

func test_wired_into_draw_enemies() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("func _draw_enemies()")
	Runner.T.ok(i >= 0, "_draw_enemies exists")
	var j := src.find("\nfunc ", i + 10)
	Runner.T.ok(src.substr(i, j - i).contains("InfantryPolish.draw_pad("), "_draw_enemies calls the pad")
