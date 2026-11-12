extends RefCounted
## AtmospherePolish: cloud shadows, pollen, light shafts and the vignette, plus proof main wires them.

const Runner := preload("res://tests/run_tests.gd")


func test_polish_adds_no_second_cloud_shimmer_or_smoke() -> void:
	# Atmosphere owns cloud shadows, shimmer and smoke/mist; the polish must not double them.
	var src := FileAccess.get_file_as_string("res://src/view/atmosphere_polish.gd")
	Runner.T.ok(not src.contains("func plan_clouds") and not src.contains("func plan_shimmer"), "no polish cloud or shimmer system")
	for s in AtmospherePolish.SECTORS:
		for def in AtmospherePolish.AIR[s]:
			Runner.T.ok(def["size"].x < 60.0, "sector %d polish air has no smoke/mist banks" % s)


func test_shafts_in_open_sky_sectors_and_clear_of_the_hud() -> void:
	Runner.T.ok(AtmospherePolish.plan_shafts(0, 100, 1.0).size() >= 6, "dawn jungle has light shafts")
	Runner.T.ok(AtmospherePolish.plan_shafts(1, 100, 1.0).size() >= 4, "marsh haze has shafts")
	Runner.T.ok(AtmospherePolish.plan_shafts(2, 100, 1.0).size() >= 4, "bridge sky has shafts")
	for s in [3, 4, 5]:
		Runner.T.eq(AtmospherePolish.plan_shafts(s, 100, 1.0).size(), 0, "sector %d has no shafts" % s)
	for e in AtmospherePolish.plan_shafts(0, 100, 1.0):
		Runner.T.eq(e["cols"][0].a, 0.0, "shaft is transparent at its top edge")
		Runner.T.eq(e["cols"][3].a, 0.0, "shaft fades out at the bottom")
		Runner.T.ok(e["cols"][2].a <= 0.06, "shaft stays faint")
		Runner.T.eq(e["cols"][0].a + e["cols"][4].a + e["cols"][5].a, 0.0, "shaft outer edge is feathered to zero alpha")
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


func test_vignette_is_subtle_and_bounded() -> void:
	# Base game tuned its edge vignette to 0.04 so corner luma loss stays under 5%. The sector tint
	# may add a little, but edge luma loss (card alpha is 1 at the corners) must stay under 8%.
	for s in AtmospherePolish.SECTORS:
		var c := AtmospherePolish.vignette_color(s)
		Runner.T.ok(c.a >= 0.03 and c.a <= 0.08, "sector %d vignette is faint (%.2f)" % [s, c.a])
		var loss := c.a * (1.0 - c.v)   # luma fraction lost on a mid-bright edge pixel at full card alpha
		Runner.T.ok(loss < 0.08, "sector %d vignette loses under 8%% edge luma" % s)


func test_cost_stays_bounded() -> void:
	for s in AtmospherePolish.SECTORS:
		var n := AtmospherePolish.plan_air(s, 77, 1.0, 40.0).size() \
			+ AtmospherePolish.plan_shafts(s, 77, 1.0).size()
		Runner.T.ok(n <= 90, "sector %d adds at most 90 draw calls (%d)" % [s, n])


func test_main_wires_the_polish() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var g := src.find("func _draw_atmosphere_ground()")
	var gend := src.find("func _draw_atmosphere_over()")
	Runner.T.ok(g > 0 and src.substr(g, gend - g).contains("AtmospherePolish.draw_ground("), "ground pass calls the polish")
	var o := src.find("func _draw_atmosphere_over()")
	var oend := src.find("func _atmosphere_sector()")
	Runner.T.ok(o > 0 and src.substr(o, oend - o).contains("AtmospherePolish.draw_vignette("), "over pass draws the vignette after the actors")
	var d := src.find("func _draw_field_dim()")
	Runner.T.ok(d > 0 and not src.substr(d, 600).contains("AtmospherePolish.draw_vignette("), "field-dim pass (before projectiles) no longer draws it")


func _sig_ops(ops: Array) -> Array:
	var out: Array = []
	for o in ops:
		out.append([o["tex"], o["r"], o["c"]])
	return out


func test_cached_base_layers_match_atmosphere_plan_exactly() -> void:
	AtmospherePolish.reset_cache()
	var bad := 0
	for s in range(-1, AtmospherePolish.SECTORS + 1):
		for layer in [Atmosphere.Layer.UNDER, Atmosphere.Layer.MID, Atmosphere.Layer.OVER]:
			for motion in [0.0, 1.0]:
				for f in [0, 1, 59, 333, 12345]:
					for cam in [0.0, 41.5, 900.25]:
						var rec: Array = []
						AtmospherePolish.draw_base(null, s, f, motion, cam, layer, rec)
						if rec != _sig_ops(Atmosphere.plan(s, f, motion, cam, layer)):
							bad += 1
	Runner.T.eq(bad, 0, "draw_base paints exactly what Atmosphere.plan plans")


func test_cached_air_matches_plan_air_and_follows_the_sector() -> void:
	AtmospherePolish.reset_cache()
	var bad := 0
	for s in AtmospherePolish.SECTORS:
		for motion in [0.0, 1.0]:
			for f in [0, 7, 200, 4001]:
				var rec: Array = []
				AtmospherePolish.draw_air(null, s, f, motion, 63.0, rec)
				if rec != _sig_ops(AtmospherePolish.plan_air(s, f, motion, 63.0)):
					bad += 1
	Runner.T.eq(bad, 0, "draw_air paints exactly what plan_air plans")
	var rec0: Array = []
	var rec1: Array = []
	AtmospherePolish.draw_air(null, 0, 50, 1.0, 0.0, rec0)
	AtmospherePolish.draw_air(null, 3, 50, 1.0, 0.0, rec1)
	AtmospherePolish.draw_air(null, 0, 50, 1.0, 0.0, rec0)
	Runner.T.ok(rec0.size() > 0 and rec0 != rec1, "a sector change is not served the previous sector's table")
	var again: Array = []
	AtmospherePolish.draw_air(null, 0, 50, 1.0, 0.0, again)
	Runner.T.eq(again, rec0.slice(rec0.size() / 2), "returning to the first sector reproduces it")


func test_cached_shafts_match_plan_exactly() -> void:
	AtmospherePolish.reset_cache()
	var bad := 0
	for s in AtmospherePolish.SECTORS:
		for motion in [0.0, 1.0]:
			for f in range(0, 60000, 997):
				var rec: Array = []
				AtmospherePolish.draw_shafts(null, s, f, motion, rec)
				var plan := AtmospherePolish.plan_shafts(s, f, motion)
				if rec.size() != plan.size():
					bad += 1
					continue
				for i in plan.size():
					if rec[i][0] != plan[i]["pts"] or rec[i][1] != plan[i]["cols"]:
						bad += 1
	Runner.T.eq(bad, 0, "draw_shafts builds exactly the planned polygons")
