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
	Runner.T.ok(snip.b > snip.r + 0.15 and snip.b > rush.b + 0.25, "sniper reads cold blue-steel, not rusher warm (%s)" % snip)
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


func _hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)

func test_no_enemy_role_wears_the_lethal_bolt_hue() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var rx := RegEx.create_from_string("const LETHAL_BOLT := Color\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	var m := rx.search(src)
	Runner.T.ok(m != null, "LETHAL_BOLT constant found")
	var bolt := Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
	Runner.T.ok(ProjectilesPolish.ENEMY_BODY.is_equal_approx(bolt), "hostile bullet body is the reserved lethal colour")
	var window := 40.0 / 360.0
	for k in ["enemy_assault", "enemy_smg", "enemy_shotgun", "enemy_lmg", "enemy_sniper", "enemy_elite"]:
		var im := _img("res://assets/baked/%s/idle.png" % k)
		var bad := 0
		for y in im.get_height():
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				if c.a < 0.5 or c.s < 0.3 or c.v < 0.3:
					continue
				if _hue_gap(c.h, bolt.h) < window:
					bad += 1
		Runner.T.eq(bad, 0, "%s has no saturated pixel within 40 degrees of the lethal bolt hue" % k)
