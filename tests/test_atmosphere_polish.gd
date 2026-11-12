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
			Runner.T.ok(op["c"].a <= 0.4 and op["c"].a >= 0.25, "cloud shadow clearly visible but capped")
			Runner.T.ok(Rect2(0, 0, 640, 360).intersects(op["r"]), "cloud culled to viewport")


func test_shafts_in_open_sky_sectors_and_clear_of_the_hud() -> void:
	Runner.T.ok(AtmospherePolish.plan_shafts(0, 100, 1.0).size() >= 9, "dawn jungle has light shafts")
	Runner.T.ok(AtmospherePolish.plan_shafts(1, 100, 1.0).size() >= 6, "marsh haze has shafts")
	Runner.T.ok(AtmospherePolish.plan_shafts(2, 100, 1.0).size() >= 6, "bridge sky has shafts")
	for s in [3, 4, 5]:
		Runner.T.eq(AtmospherePolish.plan_shafts(s, 100, 1.0).size(), 0, "sector %d has no shafts" % s)
	for e in AtmospherePolish.plan_shafts(0, 100, 1.0):
		Runner.T.eq(e["cols"][0].a, 0.0, "shaft is transparent at its top edge")
		Runner.T.eq(e["cols"][3].a, 0.0, "shaft fades out at the bottom")
		Runner.T.ok(e["cols"][2].a <= 0.12, "shaft stays soft")
		for pt in e["pts"]:
			Runner.T.ok(pt.y >= AtmospherePolish.SHAFT_TOP_Y, "shaft never starts inside the HUD band")
	Runner.T.eq(str(AtmospherePolish.plan_shafts(0, 5, 0.0)), str(AtmospherePolish.plan_shafts(0, 900, 0.0)),
		"shafts hold still under reduce-motion")


func test_every_sector_has_its_own_air() -> void:
	var sigs := {}
	for s in AtmospherePolish.SECTORS:
		var n := 0
		for f in [0, 90, 200, 333]:
			n = maxi(n, AtmospherePolish.plan_air(s, f, 1.0, 0.0).size())
		Runner.T.ok(n >= 6, "sector %d has ambient particles (%d)" % [s, n])
		sigs[str(AtmospherePolish.AIR[s][0]["col"]) + str(AtmospherePolish.AIR[s][0]["vel"])] = true
		var a := AtmospherePolish.plan_air(s, 10, 0.0, 0.0)
		var b := AtmospherePolish.plan_air(s, 999, 0.0, 0.0)
		Runner.T.eq(str(a), str(b), "sector %d air hangs still under reduce-motion" % s)
		Runner.T.ok(str(AtmospherePolish.plan_air(s, 10, 1.0, 0.0)) != str(AtmospherePolish.plan_air(s, 300, 1.0, 0.0)),
			"sector %d air moves" % s)
	Runner.T.eq(sigs.size(), AtmospherePolish.SECTORS, "each sector's air is distinct")


func test_heat_shimmer_only_in_the_forge_sectors() -> void:
	for s in [0, 1, 2, 4]:
		Runner.T.eq(AtmospherePolish.plan_shimmer(s, 50, 1.0).size(), 0, "sector %d has no shimmer" % s)
	for s in [3, 5]:
		var r := AtmospherePolish.plan_shimmer(s, 50, 1.0)
		Runner.T.ok(r.size() >= 5, "sector %d has heat shimmer ribbons" % s)
		Runner.T.ok(r[0]["c"].a <= 0.22, "shimmer is faint")
		Runner.T.eq(str(AtmospherePolish.plan_shimmer(s, 5, 0.0)), str(AtmospherePolish.plan_shimmer(s, 800, 0.0)),
			"shimmer is static under reduce-motion")


func test_vignette_is_dark_and_bounded() -> void:
	for s in AtmospherePolish.SECTORS:
		var c := AtmospherePolish.vignette_color(s)
		Runner.T.ok(c.a >= 0.55 and c.a <= 0.8, "sector %d vignette is clearly felt" % s)
		Runner.T.ok(c.v < 0.12, "sector %d vignette is dark" % s)


func test_cost_stays_bounded() -> void:
	for s in AtmospherePolish.SECTORS:
		var n := AtmospherePolish.plan_clouds(s, 77, 1.0, 40.0).size() + AtmospherePolish.plan_air(s, 77, 1.0, 40.0).size() \
			+ AtmospherePolish.plan_shafts(s, 77, 1.0).size() + AtmospherePolish.plan_shimmer(s, 77, 1.0).size()
		Runner.T.ok(n <= 90, "sector %d adds at most 90 draw calls (%d)" % [s, n])


func test_main_wires_the_polish() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var g := src.find("func _draw_atmosphere_ground()")
	var gend := src.find("func _draw_atmosphere_over()")
	Runner.T.ok(g > 0 and src.substr(g, gend - g).contains("AtmospherePolish.draw_ground("), "ground pass calls the polish")
	var d := src.find("func _draw_field_dim()")
	Runner.T.ok(d > 0 and src.substr(d, 600).contains("AtmospherePolish.draw_vignette("), "field-dim pass draws the vignette")
