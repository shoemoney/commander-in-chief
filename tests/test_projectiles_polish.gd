extends RefCounted
## Projectile readability: the polish module's geometry and its wiring into the real draw.

const Runner := preload("res://tests/run_tests.gd")


func test_enemy_halo_is_never_smaller_than_the_lethal_radius() -> void:
	var hit := float(SimWorld.ENEMY_BULLET_HIT_RADIUS) / float(Fixed.ONE)
	Runner.T.ok(ProjectilesPolish.enemy_halo_radius(false) >= hit, "standard halo covers the hitbox")
	Runner.T.ok(ProjectilesPolish.enemy_halo_radius(true) >= hit, "sniper halo covers the hitbox")
	Runner.T.ok(ProjectilesPolish.enemy_body_radius(false) + 1.4 < ProjectilesPolish.enemy_halo_radius(false),
		"solid body sits inside the halo")


func test_fast_rounds_read_longer() -> void:
	Runner.T.ok(ProjectilesPolish.enemy_tail(2.0) > ProjectilesPolish.enemy_tail(1.0) + 4.0, "sniper tail is longer")


func test_tracer_tapers_toward_a_hot_head() -> void:
	var segs := ProjectilesPolish.tracer_segments(Vector2(100, 100), Vector2.DOWN, 12.0)
	Runner.T.eq(segs.size(), 4, "four segments")
	Runner.T.ok(segs[3][2] > segs[0][2] and segs[3][3] > segs[0][3], "head is wider and brighter than tail")
	Runner.T.ok(segs[3][1].is_equal_approx(Vector2(100, 100)), "head ends on the sim position")


func test_grenade_arc_ends_before_landing_and_bulges_up() -> void:
	var pts := ProjectilesPolish.grenade_arc(Vector2(0, 100), Vector2(100, 100))
	Runner.T.eq(pts.size(), 6, "six dots")
	Runner.T.ok(pts[3].y < 100.0, "mid arc rises above the chord")
	Runner.T.ok(pts[5].x < 100.0, "last dot short of the landing marker")


func test_wired_into_the_real_draw() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("func _draw_projectiles()")
	var j := src.find("static func _player_ident_color", i)
	var body := src.substr(i, j - i)
	for call in ["draw_enemy_halo", "draw_enemy_body", "draw_player_tracer", "draw_rocket_exhaust", "draw_grenade_arc"]:
		Runner.T.ok(body.contains("ProjectilesPolish." + call), "_draw_projectiles calls " + call)


## Art.line's Bresenham walk, restated as a pixel list, to pin the merged-rect replay against it.
static func _reference_line_pixels(ddx: int, ddy: int, w: int) -> Dictionary:
	var out := {}
	var dx := absi(ddx)
	var dy := -absi(ddy)
	var sx := 1 if 0 < ddx else -1
	var sy := 1 if 0 < ddy else -1
	var err := dx + dy
	var half := floori((w - 1) / 2.0)
	var x_major := dx >= -dy
	var x := 0
	var y := 0
	while true:
		if x_major:
			for k in w:
				out[Vector2i(x, y - half + k)] = out.get(Vector2i(x, y - half + k), 0) + 1
		else:
			for k in w:
				out[Vector2i(x - half + k, y)] = out.get(Vector2i(x - half + k, y), 0) + 1
		if x == ddx and y == ddy:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out


func test_line_px_rects_cover_exactly_the_pixels_art_line_stamps() -> void:
	var bad := 0
	for ddx in range(-14, 15, 2):
		for ddy in range(-14, 15, 3):
			for w in [1, 2, 3, 4, 5]:
				var ref := _reference_line_pixels(ddx, ddy, w)
				var rects := ProjectilesPolish._build_line(ddx, ddy, w)
				var got := {}
				var i := 0
				while i < rects.size():
					for xx in int(rects[i + 2]):
						for yy in int(rects[i + 3]):
							var k := Vector2i(int(rects[i]) + xx, int(rects[i + 1]) + yy)
							got[k] = got.get(k, 0) + 1
					i += 4
				if got != ref:
					bad += 1
	Runner.T.eq(bad, 0, "merged line rects cover the same pixels exactly once, like Art.line")


func test_line_px_cache_is_keyed_on_the_delta_and_width_and_clears() -> void:
	ProjectilesPolish.clear_line_cache()
	var a := ProjectilesPolish._build_line(6, 2, 3)
	var b := ProjectilesPolish._build_line(6, 2, 4)
	var c := ProjectilesPolish._build_line(-6, 2, 3)
	Runner.T.ok(a != b and a != c, "width and direction change the rects")
	ProjectilesPolish._line_cache[Vector3i(1, 1, 1)] = PackedFloat32Array()
	Runner.T.eq(ProjectilesPolish._line_cache.size(), 1, "cache holds an entry")
	ProjectilesPolish.clear_line_cache()
	Runner.T.eq(ProjectilesPolish._line_cache.size(), 0, "clear_line_cache empties it")


func test_promoted_line_texture_matches_its_rects() -> void:
	var bad := 0
	for d in [Vector2i(9, 3), Vector2i(-7, 11), Vector2i(0, 6), Vector2i(12, 0), Vector2i(-5, -5)]:
		for w in [1, 3, 4]:
			var rects := ProjectilesPolish._build_line(d.x, d.y, w)
			var e: Array = [rects, 0, null, 0.0, 0.0, 0.0, 0.0]
			ProjectilesPolish._promote_rects(e, rects, 4)
			var img: Image = e[2].get_image()
			var want := {}
			var i := 0
			while i < rects.size():
				for xx in int(rects[i + 2]):
					for yy in int(rects[i + 3]):
						want[Vector2i(int(rects[i]) + xx, int(rects[i + 1]) + yy)] = true
				i += 4
			var got := {}
			for yy in img.get_height():
				for xx in img.get_width():
					if img.get_pixel(xx, yy).a > 0.0:
						got[Vector2i(xx + int(e[3]), yy + int(e[4]))] = true
			if got != want or img.get_width() != int(e[5]) or img.get_height() != int(e[6]):
				bad += 1
	Runner.T.eq(bad, 0, "a promoted line texture holds exactly the rect pixels")
