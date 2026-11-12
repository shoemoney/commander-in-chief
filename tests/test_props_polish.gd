extends RefCounted
## Props polish: one sun, volume shadows, cover vs decor, variation, sway, and wiring.

const Runner := preload("res://tests/run_tests.gd")
const MAIN_SRC := "res://src/main.gd"


func test_shadow_falls_south_east_and_grows_with_height() -> void:
	var p := Vector2(100, 100)
	var lo := PropsPolish.shadow_rect(p, 10.0, 4.0)
	var hi := PropsPolish.shadow_rect(p, 10.0, 20.0)
	Runner.T.ok(lo.get_center().x > p.x and lo.get_center().y > p.y, "shadow centre is south-east of the prop")
	Runner.T.ok(hi.get_center().x > lo.get_center().x, "taller prop throws further")
	Runner.T.ok(hi.size.x > lo.size.x, "taller prop throws longer")
	Runner.T.ok(PropsPolish.SHADOW_DIR.dot(PropsPolish.SUN_FROM) < -0.99, "shadow opposes the sun")


func test_variants_differ_and_sway_respects_reduce_motion() -> void:
	var seen := {}
	for h in 40:
		seen[PropsPolish.tint_variant(h * 37).to_html()] = true
	Runner.T.ok(seen.size() >= 6, "tint varies across instances")
	Runner.T.eq(PropsPolish.sway(77, 500, 0.0), 0.0, "static under reduce-motion")
	Runner.T.ok(absf(PropsPolish.sway(77, 500, 1.0)) > 0.0 or absf(PropsPolish.sway(77, 530, 1.0)) > 0.0, "sways when motion on")
	Runner.T.ok(not PropsPolish.is_cover_kind(1) and PropsPolish.is_cover_kind(0), "grass is decor, rocks are cover")


func test_unit_ellipse_is_cached_and_closed() -> void:
	var e := PropsPolish._unit_ellipse()
	Runner.T.eq(e.size(), 14, "14-point ellipse")
	Runner.T.ok(is_equal_approx(e[0].length(), 1.0), "unit radius")


func test_draw_functions_are_wired_to_module() -> void:
	var src := FileAccess.get_file_as_string(MAIN_SRC)
	for fn in ["func _draw_rocks", "func _draw_sandbags", "func _draw_barrels", "func _draw_pickups"]:
		var i := src.find(fn)
		Runner.T.ok(i >= 0, fn + " exists")
		var j := src.find("\nfunc ", i + 10)
		Runner.T.ok(src.substr(i, j - i).contains("PropsPolish."), fn + " calls PropsPolish")
	var b := src.find("for bk in sim.bunkers:")
	Runner.T.ok(b >= 0 and src.substr(b, 3500).contains("PropsPolish.cover_base_rect"), "bunker loop calls PropsPolish")



func test_cover_is_legibly_heavier_than_decor() -> void:
	Runner.T.ok(PropsPolish.SHADOW_GAIN >= 1.5 and PropsPolish.LEN_GAIN >= 1.25, "shadows are store-screenshot strong")
	Runner.T.ok(PropsPolish.COVER_LIP_ALPHA >= 0.85, "cover lip is near-opaque ink")
	var r := PropsPolish.shadow_rect(Vector2.ZERO, 12.0, PropsPolish.HEIGHT_ROCK)
	Runner.T.ok(r.size.x >= 40.0, "boulder shadow is long enough to read at 640x360")


func test_ellipse_triangulation_is_computed_once_and_valid() -> void:
	var pts := PropsPolish._unit_ellipse()
	PropsPolish._ellipse_idx = PackedInt32Array()
	var n := Node2D.new()
	PropsPolish._fill_ellipse(n, Color.WHITE)
	Runner.T.eq(PropsPolish._ellipse_idx, Geometry2D.triangulate_polygon(pts), "cached indices are the engine's own ear-clip")
	Runner.T.eq(PropsPolish._ellipse_idx.size(), (pts.size() - 2) * 3, "a 14-gon is 12 triangles")
	var held := PropsPolish._ellipse_idx
	PropsPolish._fill_ellipse(n, Color.BLACK)
	Runner.T.eq(PropsPolish._ellipse_idx, held, "a second fill reuses it")
	n.free()
