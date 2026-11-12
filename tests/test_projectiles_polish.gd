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
