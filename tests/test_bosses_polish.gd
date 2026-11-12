extends RefCounted
## Bosses and vehicles presentation (src/view/bosses_polish.gd): damage stages, tread marks,
## helicopter shadow, boss bar pips/heat, and proof the real draw functions call it.

const Runner := preload("res://tests/run_tests.gd")
const F := 65536


func _body(path: String, fn: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var i := src.find("func " + fn + "(")
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 5)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func test_damage_stages_escalate_smoke_then_fire() -> void:
	Runner.T.eq(BossesPolish.damage_stage(0.0), 0, "pristine")
	Runner.T.eq(BossesPolish.damage_stage(0.3), 1, "smoking")
	Runner.T.eq(BossesPolish.damage_stage(0.8), 2, "burning")
	Runner.T.eq(BossesPolish.fire_count(0.3), 0, "no fire while only smoking")
	Runner.T.ok(BossesPolish.fire_count(0.9) > BossesPolish.fire_count(0.61), "more fires as HP falls")
	Runner.T.ok(BossesPolish.smoke_count(0.9) > BossesPolish.smoke_count(0.3), "more smoke as HP falls")
	Runner.T.eq(BossesPolish.smoke_count(0.1), 0, "healthy hull is clean")


func test_tank_wound_follows_fuel_and_fire() -> void:
	var t := {"burning": false, "occupant": 0, "fuel": SimWorld.TANK_FUEL_TICKS}
	Runner.T.eq(BossesPolish.tank_wound(t), 0.0, "full tank, clean")
	t["fuel"] = 100
	Runner.T.ok(BossesPolish.tank_wound(t) > BossesPolish.SMOKE_START, "low fuel smokes")
	t["occupant"] = -1
	Runner.T.eq(BossesPolish.tank_wound(t), 0.0, "parked tank is not strained")
	t["burning"] = true
	Runner.T.ok(BossesPolish.tank_wound(t) >= BossesPolish.FIRE_START, "burning hull shows fire")


func test_tread_marks_sample_by_distance_and_cap() -> void:
	BossesPolish.reset()
	BossesPolish.push_track("k", 0, 0, 0.0)
	BossesPolish.push_track("k", 2 * F, 0, 0.0)
	Runner.T.eq(BossesPolish.track_count("k"), 1, "sub-step motion adds no sample")
	for i in 40:
		BossesPolish.push_track("k", (i + 1) * 6 * F, 0, 0.0)
	Runner.T.eq(BossesPolish.track_count("k"), BossesPolish.TRAIL_MAX, "trail is capped")
	BossesPolish.push_track("k", 5000 * F, 0, 0.0)
	Runner.T.eq(BossesPolish.track_count("k"), 1, "teleport restarts the streak")
	BossesPolish.reset()


func test_heli_shadow_travels_and_reduce_motion_freezes_it() -> void:
	var a := BossesPolish.shadow_offset(0.0, 1.0)
	var b := BossesPolish.shadow_offset(1.5, 1.0)
	Runner.T.ok(a.distance_to(b) > 1.0, "shadow moves with the drift")
	Runner.T.eq(BossesPolish.shadow_offset(0.0, 0.0), BossesPolish.shadow_offset(2.0, 0.0), "reduce-motion holds it still")


func test_bar_pips_and_heat() -> void:
	Runner.T.ok(BossesPolish.pip_lit(2, 3, 0.5), "below the 2/3 mark the pip is burned through")
	Runner.T.ok(not BossesPolish.pip_lit(1, 3, 0.9), "above the mark it is not")
	var hot := BossesPolish.fill_color(0.1)
	var cool := BossesPolish.fill_color(1.0)
	Runner.T.ok(hot.g > cool.g, "fill heats toward orange when nearly dead")


func test_real_draw_functions_call_the_module() -> void:
	var m := "res://src/main.gd"
	for fn in ["_draw_tanks", "_draw_one_gunship", "_draw_colossus", "_draw_foundry_arena", "_draw_bar"]:
		Runner.T.ok(_body(m, fn).contains("BossesPolish."), fn + " calls BossesPolish")
	Runner.T.ok(_body(m, "_draw_one_gunship").contains("draw_rotor"), "gunship uses the blur rotor")
	Runner.T.ok(_body(m, "_draw_one_gunship").contains("draw_heli_shadow"), "gunship casts the moving shadow")
	Runner.T.ok(_body(m, "_draw_tanks").contains("push_track"), "driven tanks lay tread marks")
	Runner.T.ok(FileAccess.get_file_as_string("res://src/view/siege_view.gd").contains("BossesPolish.draw_damage"),
		"siege tank shows damage states")


func test_presentation_is_bold_enough_for_640x360() -> void:
	Runner.T.ok(BossesPolish.SCRIM_COL.a >= 0.7, "arena scrim crushes the red decor wash")
	Runner.T.ok(BossesPolish.SCRIM_COL.r < 0.1 and BossesPolish.SCRIM_COL.b > BossesPolish.SCRIM_COL.r, "scrim is cool, not red")
	Runner.T.ok(BossesPolish.ROTOR_DISC_ALPHA >= 0.3, "rotor blur disc is visible at native size")
	Runner.T.ok(BossesPolish.SHADOW_ALPHA >= 0.5, "heli ground shadow reads")
	Runner.T.ok(BossesPolish.shadow_offset(0.0, 1.0).y >= 40.0, "shadow sits well off the hull for altitude")
	var m := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(not _body("res://src/main.gd", "_draw_bar").contains("ui_bar_frame"), "bar frame sprite no longer smothers the styled bar")
	Runner.T.ok(m.contains("BossesPolish.draw_damage(self, cbody"), "colossus draws damage smoke and fire")
