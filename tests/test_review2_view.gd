extends RefCounted
## SECOND-REVIEW FIXES, VIEW AND PERFORMANCE. Three defects an independent review measured:
##   1. the flame cone was drawn whenever the flame was held and fire_cd > 0 -- but the MG writes
##      the same fire_cd, so a held flame with no target drew the cone on 600 of 600 ticks;
##   2. GroundStructure.plan rebuilt ~62 rows x 13 vertices (and ~730 draw_polygon commands) on
##      every scrolling frame (4.4 ms per frame measured);
##   3. the endless HUD recomputed EndlessRoster.wave_budget on every draw.
## Everything is asserted on measured output or on WORK DONE (rows computed, commands issued),
## never on wall-clock time, so the blocking suite stays timing-free.

const Runner := preload("res://tests/run_tests.gd")
const Hud := preload("res://src/view/hud.gd")
const F := Fixed.ONE


# --- 1. the flame cone is drawn only after a real flame burst ---------------------------------

func _flame_sim() -> SimWorld:
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.bunkers.clear()
	sim.rocks.clear()
	sim.barrels.clear()
	var p: Dictionary = sim.players[0]
	p["x"] = 320 * F
	p["y"] = sim.camera_top + 250 * F
	sim._apply_supply(p, Weapons.TABLE[Weapons.FLAME]["kind"])
	return sim


## One tick with fire held, exactly as the view sees it: step, feed events, ask the draw predicate.
func _view_tick(sim: SimWorld) -> Dictionary:
	var inp := SimInput.new()
	inp.fire = true
	inp.aim_x = 0
	inp.aim_y = -256
	sim.step([inp])
	var flames := 0
	for ev in sim.events:
		WeaponFx.note_event(ev, sim)
		if ev["t"] == "flame":
			flames += 1
	return {"drawn": WeaponFx.flame_drawn(sim, 0), "flames": flames}


func test_held_flame_with_no_target_never_draws_the_cone() -> void:
	WeaponFx.reset()
	var sim := _flame_sim()
	var drawn := 0
	var flames := 0
	var mg_cd_ticks := 0
	for _i in 120:
		var r := _view_tick(sim)
		drawn += 1 if r["drawn"] else 0
		flames += r["flames"]
		mg_cd_ticks += 1 if sim.players[0]["fire_cd"] > 0 else 0
	Runner.T.eq(flames, 0, "no target: the sim emitted no flame event")
	Runner.T.ok(mg_cd_ticks > 20, "the MG really did keep fire_cd non-zero (%d of 120 ticks) -- the old draw condition" % mg_cd_ticks)
	Runner.T.eq(drawn, 0, "...and the cone was drawn on none of 120 ticks")


func test_a_real_burst_draws_the_cone_for_its_cooldown_window_only() -> void:
	WeaponFx.reset()
	var sim := _flame_sim()
	var p: Dictionary = sim.players[0]
	sim.enemies.append({"x": p["x"], "y": p["y"] - 40 * F, "alive": true, "elite": false, "kind": "rusher"})
	var cd: int = Weapons.TABLE[Weapons.FLAME]["cd"]
	var r := _view_tick(sim)
	Runner.T.eq(r["flames"], 1, "a target in the cone: one real flame burst")
	Runner.T.ok(r["drawn"], "the cone is drawn on the burst tick")
	var window := 1
	for _i in cd + 6:
		r = _view_tick(sim)
		if r["flames"] > 0:
			continue
		if r["drawn"]:
			window += 1
	Runner.T.ok(window <= cd, "drawn for at most the %d-tick burst cooldown, not for as long as the weapon is held (%d)" % [cd, window])
	r = _view_tick(sim)
	Runner.T.ok(not r["drawn"] and r["flames"] == 0, "target dead, no new burst: the cone is gone")


func test_a_new_sim_inherits_no_burst_state() -> void:
	WeaponFx.reset()
	var a := _flame_sim()
	var pa: Dictionary = a.players[0]
	a.enemies.append({"x": pa["x"], "y": pa["y"] - 40 * F, "alive": true, "elite": false, "kind": "rusher"})
	_view_tick(a)
	Runner.T.ok(WeaponFx.flame_drawn(a, 0), "sim A: burst drawn")
	var b := _flame_sim()
	b.players[0]["fire_cd"] = 3     # a restarted run that happens to have a live cooldown
	Runner.T.ok(not WeaponFx.flame_drawn(b, 0), "a restarted sim does not inherit the old run's burst")


func test_draw_world_routes_through_the_predicate() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/weapon_fx.gd")
	Runner.T.ok(src.contains("if flame_drawn(sim, pi):"), "draw_world draws the cone only through flame_drawn")
	var m := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(m.contains("WeaponFx.note_event(ev, sim)"), "main feeds every event to WeaponFx")
	Runner.T.ok(m.contains("WeaponFx.reset()"), "a restart clears the burst state")


# --- 2. the ground track is cached and batched ------------------------------------------------

func _world(extra_gate := false) -> Dictionary:
	var gates: Array = []
	for k in range(1, 7):
		gates.append({"y": -k * 1000 * F})
	if extra_gate:
		gates.append({"y": -7 * 1000 * F})
	var waters: Array = [{"y": -1500 * F, "ford_x": 480 * F}]
	return {"gates": gates, "waters": waters}


func _plan(w: Dictionary, cam_y: float) -> Dictionary:
	var gys: Array = []
	for g in w["gates"]:
		gys.append(float(g["y"]) / float(F))
	var anc := GroundStructure.anchors(w["gates"], w["waters"], 80.0, 1.0 / float(F))
	return GroundStructure.plan(anc, gys, w["waters"], cam_y, 80.0,
		func(b: int) -> int: return SimWorld.ford_half_w(b))


func _fresh_plan(w: Dictionary, cam_y: float) -> Dictionary:
	GroundStructure.cache_enabled = false
	var p := _plan(w, cam_y)
	GroundStructure.cache_enabled = true
	return p


func test_cached_plan_is_identical_to_a_cold_plan_across_a_long_scroll() -> void:
	var w := _world()
	GroundStructure.cache_enabled = true
	_plan(w, 0.0)
	var mismatches := 0
	var cams := 0
	# 2400 px of scroll at an awkward 3.7 px step, through the gate at y=-1000, the biome seam
	# around it and the ford at y=-1500.
	var cam := -700.0
	while cam > -3100.0:
		var hot := _plan(w, cam)
		var cold := _fresh_plan(w, cam)
		if var_to_str(hot) != var_to_str(cold):
			mismatches += 1
		cams += 1
		cam -= 3.7
	Runner.T.ok(cams > 600, "the sweep covered %d camera positions" % cams)
	Runner.T.eq(mismatches, 0, "cached plan == cold plan (lane rows, tris, ruts, aprons, planks) at every position")


func test_cache_never_leaks_a_previous_runs_track() -> void:
	var a := _world(false)
	var b := _world(true)
	b["gates"][0] = {"y": -900 * F}   # a different run: the first gate moved, so the track bends elsewhere
	_plan(a, -950.0)
	var hot := _plan(b, -950.0)
	var cold := _fresh_plan(b, -950.0)
	Runner.T.ok(var_to_str(hot) == var_to_str(cold), "new anchors (restart / new gate): the old rows are not served")
	Runner.T.ok(var_to_str(_plan(a, -950.0)) == var_to_str(_fresh_plan(a, -950.0)), "...and back again")


func test_scrolling_computes_only_the_rows_that_enter_the_viewport() -> void:
	var w := _world()
	GroundStructure.cache_enabled = true
	_plan(w, -2000.0)
	Runner.T.ok(GroundStructure.rows_computed >= 60, "a cold plan builds the whole viewport (%d rows)" % GroundStructure.rows_computed)
	var worst := 0
	var total := 0
	var cam := -2000.0
	for _i in 300:
		cam -= 1.5
		_plan(w, cam)
		worst = maxi(worst, GroundStructure.rows_computed)
		total += GroundStructure.rows_computed
	Runner.T.ok(worst <= 2, "a 1.5 px scroll builds at most 2 new rows (worst %d)" % worst)
	Runner.T.ok(total <= int(300.0 * 1.5 / GroundStructure.ROW_PX) + 3, "300 frames of scroll built %d rows in total (450 px = 75 rows; the old code built ~18900)" % total)
	_plan(w, cam)
	Runner.T.eq(GroundStructure.rows_computed, 0, "a frame that does not scroll builds nothing")


func test_cache_stays_bounded() -> void:
	var w := _world()
	var cam := 0.0
	for _i in 400:
		cam -= 24.0   # 4 rows a frame for 400 frames = 9600 px
		_plan(w, cam)
	Runner.T.ok(GroundStructure._row_cache.size() <= 160, "evicted rows that left the viewport (%d cached)" % GroundStructure._row_cache.size())


## The old painter, restated here independently: one quad per cell, dropped when effectively
## transparent. The batched triangle list must be exactly these quads, as triangles.
func test_batched_triangles_are_exactly_the_old_per_cell_quads() -> void:
	var w := _world()
	var p := _fresh_plan(w, -1010.0)
	var rows: Array = p["lane"]
	var want_pts := PackedVector2Array()
	var want_cols := PackedColorArray()
	for i in rows.size() - 1:
		var r0: Dictionary = rows[i]
		var r1: Dictionary = rows[i + 1]
		for c in GroundStructure.LANE_COLS - 1:
			var c0: PackedColorArray = r0["vc"]
			var c1: PackedColorArray = r1["vc"]
			if c0[c].a + c0[c + 1].a + c1[c].a + c1[c + 1].a < 0.004:
				continue
			var x0: PackedFloat32Array = r0["vx"]
			var x1: PackedFloat32Array = r1["vx"]
			var a := Vector2(x0[c], r0["wy"])
			var b := Vector2(x0[c + 1], r0["wy"])
			var d := Vector2(x1[c + 1], r1["wy"])
			var e := Vector2(x1[c], r1["wy"])
			want_pts.append_array(PackedVector2Array([a, b, d, a, d, e]))
			want_cols.append_array(PackedColorArray([c0[c], c0[c + 1], c1[c + 1], c0[c], c1[c + 1], c1[c]]))
	var got_pts := PackedVector2Array()
	var got_cols := PackedColorArray()
	for i in rows.size() - 1:
		got_pts.append_array(rows[i]["tp"])
		got_cols.append_array(rows[i]["tc"])
	Runner.T.ok(want_pts.size() > 600, "the strip has real geometry (%d vertices)" % want_pts.size())
	Runner.T.ok(got_pts == want_pts, "triangle positions == the old quads, vertex for vertex")
	Runner.T.ok(got_cols == want_cols, "triangle colours == the old quads, vertex for vertex")


func test_the_lane_is_one_batched_draw() -> void:
	var w := _world()
	var p := _plan(w, -1500.0)
	var canvas := Node2D.new()
	GroundStructure._paint_lane(canvas, p["lane"])
	canvas.free()
	Runner.T.ok(GroundStructure.lane_vertex_count > 600, "the lane painted real geometry (%d vertices)" % GroundStructure.lane_vertex_count)
	Runner.T.ok(GroundStructure.lane_commands > 0 and GroundStructure.lane_commands <= 3,
		"the whole lane costs %d canvas commands (was ~730 draw_polygon calls)" % GroundStructure.lane_commands)
	var src := FileAccess.get_file_as_string("res://src/view/ground_structure.gd")
	var body := src.substr(src.find("static func _paint_lane"), 1400)
	Runner.T.ok(not body.contains("draw_polygon"), "_paint_lane no longer issues per-cell draw_polygon calls")


# --- 3. the endless HUD caches the wave budget ------------------------------------------------

func test_wave_budget_is_computed_once_per_wave() -> void:
	var hud := Hud.new()
	var first := hud._wave_budget_cached(8)
	for _i in 50:
		Runner.T.eq(hud._wave_budget_cached(8), first, "same wave, same budget")
	Runner.T.eq(hud.wave_budget_calls, 1, "50 draws at wave 8 ran the real function once")
	Runner.T.eq(hud._wave_budget_cached(9), EndlessRoster.wave_budget(9), "a new wave recomputes and matches the roster")
	Runner.T.eq(hud.wave_budget_calls, 2, "...exactly once more")
	var src := FileAccess.get_file_as_string("res://src/view/hud.gd")
	Runner.T.eq(src.count("EndlessRoster.wave_budget(sim.wave)"), 0, "no per-draw call to the roster remains in the HUD")
	hud.free()
