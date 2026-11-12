extends RefCounted
## AtmospherePolish: cloud shadows, pollen, light shafts and the vignette, plus proof main wires them.

const Runner := preload("res://tests/run_tests.gd")


func test_clouds_exist_drift_and_freeze_under_reduce_motion() -> void:
	for s in AtmospherePolish.SECTORS:
		var a := AtmospherePolish.plan_clouds(s, 0, 1.0, 0.0)
		var b := AtmospherePolish.plan_clouds(s, 600, 1.0, 0.0)
		var c := AtmospherePolish.plan_clouds(s, 600, 0.0, 0.0)
		var d := AtmospherePolish.plan_clouds(s, 0, 0.0, 0.0)
		Runner.T.ok(a.size() >= 1, "sector %d has cloud shadows" % s)
		Runner.T.ok(str(a) != str(b), "sector %d clouds drift over time" % s)
		Runner.T.eq(str(c), str(d), "sector %d clouds are static under reduce-motion" % s)
		for op in a:
			Runner.T.ok(op["c"].a <= 0.3 and op["c"].a >= 0.1, "cloud alpha subtle but visible")
			Runner.T.ok(Rect2(0, 0, 640, 360).intersects(op["r"]), "cloud culled to viewport")


func test_shafts_only_where_the_sector_calls_for_them() -> void:
	Runner.T.ok(AtmospherePolish.plan_shafts(0, 100, 1.0).size() >= 3, "dawn jungle has light shafts")
	Runner.T.ok(AtmospherePolish.plan_shafts(1, 100, 1.0).size() >= 2, "marsh haze has shafts")
	for s in [2, 3, 4, 5]:
		Runner.T.eq(AtmospherePolish.plan_shafts(s, 100, 1.0).size(), 0, "sector %d has no shafts" % s)
	for e in AtmospherePolish.plan_shafts(0, 100, 1.0):
		Runner.T.ok(e["cols"][0].a <= 0.18 and e["cols"][2].a == 0.0, "shaft fades out and stays faint")
	Runner.T.eq(str(AtmospherePolish.plan_shafts(0, 5, 0.0)), str(AtmospherePolish.plan_shafts(0, 900, 0.0)),
		"shafts hold still under reduce-motion")


func test_pollen_only_in_the_jungle() -> void:
	var n := 0
	for f in [0, 90, 200, 333]:
		n = maxi(n, AtmospherePolish.plan_pollen(0, f, 1.0, 0.0).size())
	Runner.T.ok(n >= 4, "jungle has pollen glints (%d)" % n)
	Runner.T.eq(AtmospherePolish.plan_pollen(4, 90, 1.0, 0.0).size(), 0, "ash sector has no pollen")


func test_vignette_is_dark_and_bounded() -> void:
	for s in AtmospherePolish.SECTORS:
		var c := AtmospherePolish.vignette_color(s)
		Runner.T.ok(c.a > 0.2 and c.a <= 0.5, "sector %d vignette strength in range" % s)
		Runner.T.ok(c.v < 0.12, "sector %d vignette is dark" % s)


func test_main_wires_the_polish() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var g := src.find("func _draw_atmosphere_ground()")
	var gend := src.find("func _draw_atmosphere_over()")
	Runner.T.ok(g > 0 and src.substr(g, gend - g).contains("AtmospherePolish.draw_ground("), "ground pass calls the polish")
	var d := src.find("func _draw_field_dim()")
	Runner.T.ok(d > 0 and src.substr(d, 600).contains("AtmospherePolish.draw_vignette("), "field-dim pass draws the vignette")
