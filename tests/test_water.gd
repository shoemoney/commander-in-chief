extends RefCounted
## Water grammar: wading is slow, rolls are dry-land only, armor stays out,
## and submerged frogmen answer only to grenades.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _add_water_under_player(sim: SimWorld) -> Dictionary:
	# Band covering the player's row; ford far away on the right edge.
	var w := {"y": sim.players[0]["y"] - 40 * Fixed.ONE, "ford_x": 600 * Fixed.ONE}
	sim.waters.append(w)
	return w


func test_wading_halves_speed() -> void:
	var dry := SimWorld.new(31, 1)
	var wet := SimWorld.new(31, 1)
	_add_water_under_player(wet)
	Runner.T.ok(wet._in_water(wet.players[0]["x"], wet.players[0]["y"]), "player starts in the band")
	var left := SimInput.new()
	left.move_x = -256
	for i in 10:
		dry.step([left])
		wet.step([left])
	var dry_dist: int = (280 * Fixed.ONE) - dry.players[0]["x"]
	var wet_dist: int = (280 * Fixed.ONE) - wet.players[0]["x"]
	Runner.T.eq(wet_dist * 2, dry_dist, "water exactly halves walk speed")


func test_ford_is_dry() -> void:
	var sim := SimWorld.new(31, 1)
	var w := _add_water_under_player(sim)
	Runner.T.ok(not sim._in_water(w["ford_x"], sim.players[0]["y"]), "the ford gap is dry land")


func test_no_rolling_in_water() -> void:
	var sim := SimWorld.new(31, 1)
	_add_water_under_player(sim)
	var roll := SimInput.new()
	roll.roll = true
	roll.move_x = 256
	sim.step([roll])
	Runner.T.eq(sim.players[0]["roll_ticks"], 0, "roll refused while wading")


func test_tank_walled_out_of_water() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	# Water strip just north of the tank.
	sim.waters.append({"y": p["y"] - 120 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	var tank := {"x": p["x"], "y": p["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": -1}
	sim.tanks.append(tank)
	var board := SimInput.new()
	board.interact = true
	sim.step([board])
	Runner.T.ok(p["in_tank"] >= 0, "boarded")
	var up := SimInput.new()
	up.move_y = -256
	for i in 60:
		sim.step([up])
	Runner.T.ok(not sim._in_water(tank["x"], tank["y"]), "tank never entered the water")
	Runner.T.ok(tank["y"] >= p["y"] - 120 * Fixed.ONE - SimWorld.WATER_H, "tank held at the bank")


func test_frogman_submerged_immune_to_bullets_grenades_kill() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	sim.waters.append({"y": p["y"] - 200 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	sim._spawn_frogman(p["x"], p["y"] - 170 * Fixed.ONE)   # outside notice radius
	var frog := sim.enemies[sim.enemies.size() - 1]
	# Hose it with bullets: passes clean over.
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	for i in 60:
		sim.step([fire])
	Runner.T.ok(frog["alive"] and frog["submerged"], "bullets pass over the submerged frogman")
	# One grenade: gone. (Lob range ~96 px; walk close enough first.)
	p["y"] = frog["y"] + 80 * Fixed.ONE
	var toss := SimInput.new()
	toss.aim_y = -256
	toss.grenade = true
	for i in 60:
		sim.step([toss if i == 0 else _idle()])
		if not frog["alive"]:
			break
	Runner.T.ok(not frog["alive"], "grenade kills the submerged frogman")


func test_frogman_surfacing_is_telegraphed_and_harmless() -> void:
	# One-hit-death fairness: a noticing frogman is rooted and harmless for the
	# whole FROGMAN_SURFACE_TICKS wind-up, and only kills once it lunges.
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	sim.waters.append({"y": p["y"] - 60 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	sim._spawn_frogman(p["x"], p["y"] - 4 * Fixed.ONE)   # point-blank ambush
	var frog := sim.enemies[sim.enemies.size() - 1]
	sim.step([_idle()])
	Runner.T.ok(not frog["submerged"], "frogman noticed and began surfacing")
	Runner.T.ok(frog["surface_ticks"] > 0, "surface wind-up is running")
	var fy: int = frog["y"]
	for i in SimWorld.FROGMAN_SURFACE_TICKS - 1:
		sim.step([_idle()])
	Runner.T.ok(p["alive"], "player unharmed through the whole surface telegraph")
	Runner.T.eq(frog["y"], fy, "surfacing frogman is rooted in place")
	for i in 5:
		sim.step([_idle()])
	Runner.T.ok(not p["alive"], "after the wind-up the point-blank lunge kills")


func test_frogman_surfaces_and_is_shootable() -> void:
	var sim := SimWorld.new(31, 1)
	var p := sim.players[0]
	sim.waters.append({"y": p["y"] - 60 * Fixed.ONE, "ford_x": -500 * Fixed.ONE})
	sim._spawn_frogman(p["x"], p["y"] - 40 * Fixed.ONE)   # inside notice radius
	var frog := sim.enemies[sim.enemies.size() - 1]
	sim.step([_idle()])
	Runner.T.ok(not frog["submerged"], "frogman surfaced to lunge")
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	for i in 20:
		sim.step([fire])
		if not frog["alive"]:
			break
	Runner.T.ok(not frog["alive"], "surfaced frogman is bullet-vulnerable")

func test_deep_bands_earn_second_fords_and_islands() -> void:
	# LVL-4 (8v): every 3rd band gets a permanent second ford, every 4th
	# deep band a dry mid-river island with 20px wet lips. Band 1 (torture)
	# hits neither — byte-identical by construction.
	var sim := SimWorld.new(31, 1)
	var w2 := {"y": -2500 * Fixed.ONE, "ford_x": 200 * Fixed.ONE}   # idx 2 -> second ford
	sim.waters.append(w2)
	var ford2_x: int = SimWorld.ford2_x(w2["ford_x"], 2)
	Runner.T.ok(not sim._in_water(ford2_x, w2["y"] + 40 * Fixed.ONE), "second ford center is dry")
	Runner.T.ok(sim._in_water(ford2_x + 40 * Fixed.ONE, w2["y"] + 40 * Fixed.ONE), "33px past the second ford is wet")
	var w4 := {"y": -4000 * Fixed.ONE, "ford_x": 200 * Fixed.ONE}   # idx 4 -> island
	sim.waters.append(w4)
	var isl_x: int = 80 * Fixed.ONE + ((w4["ford_x"] - 80 * Fixed.ONE) + 120 * Fixed.ONE) % (480 * Fixed.ONE)
	Runner.T.ok(not sim._in_water(isl_x, w4["y"] + 40 * Fixed.ONE), "island core is dry")
	Runner.T.ok(sim._in_water(isl_x, w4["y"] + 10 * Fixed.ONE), "the wet lip above the island still wades")
	var w1 := {"y": -1500 * Fixed.ONE, "ford_x": 200 * Fixed.ONE}   # torture band: untouched
	sim.waters.append(w1)
	Runner.T.ok(sim._in_water(500 * Fixed.ONE, w1["y"] + 40 * Fixed.ONE), "band 1 behavior unchanged")


func _tick_for_ford_phase(band_idx: int, phase: int) -> int:
	return posmod(phase - band_idx * SimWorld.FORD_PHASE_STEP, SimWorld.FORD_CYCLE_TICKS)


func test_foot_reads_main_and_permanent_fords_truthfully_at_every_phase_edge() -> void:
	var sim := SimWorld.new(31, 1)
	var band_idx := 2
	var band_y := -(band_idx * SimWorld.GATE_SPACING)
	var ford_x := 210 * Fixed.ONE
	var second_x := SimWorld.ford2_x(ford_x, band_idx)
	sim.waters.append({"y": band_y, "ford_x": ford_x})
	var edges := [
		SimWorld.FORD_OPEN_TICKS - SimWorld.FORD_WARN_TICKS,
		SimWorld.FORD_OPEN_TICKS - 1,
		SimWorld.FORD_OPEN_TICKS,
		SimWorld.FORD_CYCLE_TICKS - 1,
		0,
	]
	for phase: int in edges:
		sim.tick_count = _tick_for_ford_phase(band_idx, phase)
		var main_is_dry: bool = not sim._in_water(ford_x, band_y + SimWorld.WATER_H / 2)
		Runner.T.eq(main_is_dry, phase < SimWorld.FORD_OPEN_TICKS,
			"foot: main ford phase %d matches its open/closed edge" % phase)
		Runner.T.ok(not sim._in_water(second_x, band_y + SimWorld.WATER_H / 2),
			"foot: permanent second ford stays dry at phase %d" % phase)


func _tank_clears_band_at(sim: SimWorld, x: int, band_y: int, start_tick: int) -> bool:
	var p := sim.players[0]
	var tank := {"x": x, "y": band_y, "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "crew_ring_ticks": -1,
		"fire_cd": 0, "occupant": 0}
	sim.tanks.clear()
	sim.tanks.append(tank)
	p["x"] = x
	p["y"] = band_y
	p["in_tank"] = 0
	sim.camera_top = band_y - 100 * Fixed.ONE
	sim.tick_count = start_tick
	var drive := SimInput.new()
	drive.move_y = 256
	for i in SimWorld.FORD_WARN_TICKS:
		sim._drive_tank(0, p, drive, false, false)
		sim.tick_count += 1
	return tank["y"] > band_y + SimWorld.WATER_H


func test_tank_can_commit_on_warning_and_permanent_ford_survives_closed_phase() -> void:
	# Measured contract: ceil(80 / 1.92) = 42 movement ticks. The 45-tick
	# warning leaves three ticks of input/edge margin for the game's slowest actor.
	var crossing_ticks := ceili(float(SimWorld.WATER_H) / float(SimWorld.TANK_SPEED))
	Runner.T.eq(crossing_ticks, 42, "tank's full river-band crossing is measured at 42 ticks")
	Runner.T.ok(SimWorld.FORD_WARN_TICKS >= crossing_ticks + 3,
		"warning covers one full tank crossing plus three ticks of commitment margin")
	var sim := SimWorld.new(31, 1)
	var band_idx := 2
	var band_y := -(band_idx * SimWorld.GATE_SPACING)
	var ford_x := 210 * Fixed.ONE
	sim.waters.append({"y": band_y, "ford_x": ford_x})
	var warn_phase := SimWorld.FORD_OPEN_TICKS - SimWorld.FORD_WARN_TICKS
	Runner.T.ok(_tank_clears_band_at(sim, ford_x, band_y,
		_tick_for_ford_phase(band_idx, warn_phase)),
		"tank committing when the warning starts clears the main ford before washout")
	var second_x := SimWorld.ford2_x(ford_x, band_idx)
	Runner.T.ok(_tank_clears_band_at(sim, second_x, band_y,
		_tick_for_ford_phase(band_idx, SimWorld.FORD_OPEN_TICKS)),
		"tank crosses the permanent second ford while the main ford is washed out")


# --- THE DRAWN RIVER vs THE SIMULATED RIVER --------------------------------
#
# main.gd's water block and water.gdshader each used to re-derive, by hand, a number
# sim_world.gd owns. The old comment said so out loud ("Formulas copied from
# sim_world.gd _in_water … keep in sync with those lines"), and by the time it was
# measured the copies had drifted three separate ways at once. These four tests pin
# the SEAM, not the symptoms: everything below is computed from Main.ford_visual()
# and Main.water_shader_params(), which are built only from SimWorld's own helpers.

const Main := preload("res://src/main.gd")
const PXF := 1.0 / Fixed.ONE


func _cycle_ticks() -> Array[int]:
	# The whole 600-tick cycle at 10-tick resolution, plus every phase boundary and
	# the warn edges. Window = FORD_CYCLE_TICKS (600); the longest contiguous CLOSED
	# run this has to catch is FORD_CYCLE_TICKS - FORD_OPEN_TICKS = 420 ticks, so the
	# window is 1.43x the defect it pins.
	var ts: Array[int] = []
	for t in range(0, SimWorld.FORD_CYCLE_TICKS, 10):
		ts.append(t)
	for t in [149, 150, 179, 180, 419, 420, 599]:
		if not ts.has(t):
			ts.append(t)
	return ts


func _campaign_water_bands() -> Dictionary:
	## band_idx -> ford_x, DERIVED by dragging a real campaign world past the streamer
	## rather than typed as a literal list, so a change to the water cadence widens or
	## narrows this test's domain by itself.
	var sim := SimWorld.new(0xC0FFEE, 1)
	var bands := {}
	# Only the water GEOMETRY is under test, not how fast the camera can reach it — so drive
	# camera_top DIRECTLY rather than marching a player and waiting for the rate-limited ratchet
	# to follow. Walking it cost 14,000 _step_camera calls (MAX_CAM_STEP per tick) and doubled
	# the whole suite's wall clock, 10s -> 20.8s, a tax every sibling and CI run pays to
	# re-measure a rate limit that tests/test_gates.gd already owns.
	for i in 200:
		for g in sim.gates:
			g["open"] = true          # only the geometry is under test, not reachability
		# Move the camera AND the player together so _step_camera's rate limit is already
		# satisfied and it falls straight through to the streaming half, which is the only
		# part this helper needs.
		sim.camera_top -= 320 * Fixed.ONE
		sim.players[0]["y"] = sim.camera_top + 60 * Fixed.ONE
		sim._step_camera()
		for w in sim.waters:
			bands[absi(w["y"] / SimWorld.GATE_SPACING)] = w["ford_x"]
	return bands


func _drawn_dry(fv: Dictionary, px_x: float, px_y: float) -> bool:
	# Inclusive containment on purpose: _in_water's own comparisons are `>=`/`<=`, and
	# every ford edge lands on a whole pixel, so the two agree exactly at the boundary.
	for r: Rect2 in fv["dry_rects"]:
		if px_x >= r.position.x and px_x <= r.position.x + r.size.x \
				and px_y >= r.position.y and px_y <= r.position.y + r.size.y:
			return true
	return false


func test_drawn_ford_geometry_equals_the_simulated_ford_every_tick_of_the_cycle() -> void:
	## THE class ratchet. For every campaign river band, every sampled tick of the full
	## 600-tick collapse cycle and every probed pixel: what main.gd draws as DRY GROUND
	## is exactly what the sim answers `not _in_water` for.
	##
	## Before ford_visual() existed the deck, its ramps, its support beams, its shadow
	## and its caustics were drawn UNCONDITIONALLY — a painted bridge over 420 of every
	## 600 ticks in which _drive_tank reverts an armour move outright (measured: 230px
	## travelled over 120 ticks with the ford OPEN vs 38px with it CLOSED).
	var bands := _campaign_water_bands()
	Runner.T.ok(bands.size() >= 5, "the campaign streams at least 5 river bands (got %d)" % bands.size())
	var ticks := _cycle_ticks()
	var sim := SimWorld.new(0xC0FFEE, 1)
	var probes := 0
	var bad := 0
	var first := ""
	for band_idx: int in bands.keys():
		var ford_x: int = bands[band_idx]
		var band_y: int = -(band_idx * SimWorld.GATE_SPACING)
		sim.waters.clear()
		sim.waters.append({"y": band_y, "ford_x": ford_x})
		for t: int in ticks:
			sim.tick_count = t
			var fv := Main.ford_visual(band_idx, ford_x, t)
			# Edge-weighted x set: every rect boundary +-1px, every rect centre, plus a
			# coarse full-width sweep so a rect drawn where the sim has none is caught too.
			var xs: Array[float] = []
			for r: Rect2 in fv["dry_rects"]:
				for e in [r.position.x - 1.0, r.position.x, r.position.x + 1.0,
						r.position.x + r.size.x - 1.0, r.position.x + r.size.x,
						r.position.x + r.size.x + 1.0, r.position.x + r.size.x * 0.5]:
					xs.append(floorf(e))
			for sx in range(0, 641, 16):
				xs.append(float(sx))
			for py in [5.0, 40.0, 75.0]:
				for px_x: float in xs:
					probes += 1
					var drawn := _drawn_dry(fv, px_x, py)
					var wet: bool = sim._in_water(int(px_x) * Fixed.ONE, band_y + int(py) * Fixed.ONE)
					if drawn == wet:
						bad += 1
						if first == "":
							first = "band %d tick %d at (%d, +%d): drawn %s, sim says %s" % [
								band_idx, t, int(px_x), int(py),
								"DRY" if drawn else "water", "water" if wet else "DRY"]
	Runner.T.ok(probes > 20000, "the geometry sweep actually ran (%d probes)" % probes)
	Runner.T.eq(bad, 0, "every drawn-dry pixel is dry in the sim (%d/%d mismatches; first: %s)"
		% [bad, probes, first if first != "" else "none"])


func test_shader_ford_halfw_is_the_width_this_band_actually_fords() -> void:
	## The shader punches a transparent gap through the water at `ford_halfw`. main.gd
	## pushed a flat SimWorld.FORD_HALF_W on every band while the sim tightens the
	## crossing 4px per band: 32/28/24/20/16/16 on bands 1-6. On bands 5-6 that is
	## exactly DOUBLE the real crossing, before the shader's own ~19px smoothstep fade.
	var expected := [32, 28, 24, 20, 16, 16]
	for i in expected.size():
		var band_idx := i + 1
		var got: float = float(Main.water_shader_params(band_idx, 300 * Fixed.ONE, 0, false)["ford_halfw"]) * 640.0
		Runner.T.eq(int(round(got)), expected[i],
			"band %d: shader ford_halfw %.1fpx == the sim's %dpx crossing" % [band_idx, got, expected[i]])
		Runner.T.eq(int(round(got)), int(round(SimWorld.ford_half_w(band_idx) * PXF)),
			"band %d: the pushed width IS ford_half_w(), not a second copy of it" % band_idx)
	# ...and now the CLOSED half of the push, which no test ever exercised. A washed-out
	# crossing must punch NO hole at all, and ford_halfw = 0.0 does not achieve that: the
	# shader fades with smoothstep(ford_halfw, ford_halfw + 0.03, df), so zero still leaves
	# a 0.03-UV (~19px) ramp bleeding the river to transparent over the crossing — and with
	# the sand strip correctly gone while closed, what shows through is bare terrain (the
	# reviewer measured a warm-grey (81,87,83) core against a (75,109,109) river at band 3).
	# df carries a jitter of (fbm-0.5)*0.012, so it bottoms out at -0.006; the pushed closed
	# half-width therefore has to sit a full fade-width BELOW that for alpha to be 1 anywhere
	# on the strip. Both magic numbers are pinned to the shader source right here.
	var sh := FileAccess.get_file_as_string("res://src/view/water.gdshader")
	Runner.T.ok(sh.contains("smoothstep(ford_halfw, ford_halfw + 0.03, df)"),
		"the shader still fades the ford over a 0.03-UV ramp above ford_halfw")
	Runner.T.ok(sh.contains("- 0.5) * 0.012"),
		"the shader's ford-edge jitter is still +-0.006 UV")
	for band_idx in range(1, 7):
		var cl: float = Main.water_shader_params(band_idx, 300 * Fixed.ONE, 0, true)["ford_halfw"]
		Runner.T.ok(cl + 0.03 <= -0.006,
			"band %d CLOSED: ford_halfw %.3f leaves no transparent margin (must be <= -0.036)"
			% [band_idx, cl])


func test_the_shader_push_feeds_the_sims_own_flow_and_phase_not_a_literal() -> void:
	## water_shader_params() takes flow_dir and closed as ARGUMENTS, so asserting on what
	## it returns is a tautology — it can only prove the dict hands back what the test
	## handed in. The seam that can actually drift is the ONE call site in _sync_water:
	## nothing above would notice if it started pushing a literal 1 / false again, which
	## is exactly the bug (hardcoded +x streaks, unconditional dry ford) this pass fixed.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find(":= water_shader_params(")
	Runner.T.ok(at > 0, "_sync_water still calls water_shader_params()")
	var call := src.substr(at, 220)
	Runner.T.ok(call.contains("sim.ford_flow_dir("),
		"the pushed flow_dir comes from sim.ford_flow_dir(), not a literal:\n%s" % call)
	Runner.T.ok(call.contains("ford_closed(sim.tick_count"),
		"the pushed `closed` comes from SimWorld.ford_closed(sim.tick_count, ...):\n%s" % call)


func test_drawn_current_points_the_way_the_sim_shoves_you() -> void:
	## water.gdshader's flow streaks were hardcoded drifting +x. _ford_current shoves a
	## wader FORD_CURRENT/tick in a per-band hashed direction, and at the shipped seed
	## that is -1 on half the reachable bands — so the river was drawn running backwards
	## against a real 0.5 px/tick push on bands 2 and 4.
	var sim := SimWorld.new(0xC0FFEE, 1)
	for band_idx in range(1, 7):
		var want: int = sim.ford_flow_dir(band_idx)
		var got: float = Main.water_shader_params(band_idx, 300 * Fixed.ONE, want, false)["flow_dir"]
		Runner.T.eq(int(signf(got)), signi(want),
			"band %d: streaks drift %+d, the current pushes %+d" % [band_idx, int(signf(got)), want])
		# ...and the direction is the SAME function the shove is, not a re-derivation.
		var band_y: int = -(band_idx * SimWorld.GATE_SPACING)
		sim.waters.clear()
		sim.waters.append({"y": band_y, "ford_x": 300 * Fixed.ONE})
		var shove: int = sim._ford_current(band_y + 40 * Fixed.ONE)
		Runner.T.eq(signi(shove), signi(want),
			"band %d: ford_flow_dir agrees with the shove _ford_current actually applies" % band_idx)


func test_tank_ford_label_never_says_FORD_over_water_armour_cannot_cross() -> void:
	## The green "FORD" flag is drawn FOR the tank driver, at the one span a tank can
	## take. It was unconditional, so for 420 of every 600 ticks it labelled a hard
	## armour wall as the crossing — while the red "you can't drive here" hatching
	## deliberately SKIPPED that same span, painting the impassable strip as the safe one.
	var sim := SimWorld.new(0xC0FFEE, 1)
	var ford_x: int = 300 * Fixed.ONE
	var lied := 0
	var checked := 0
	for band_idx in range(2, 6):
		var band_y: int = -(band_idx * SimWorld.GATE_SPACING)
		sim.waters.clear()
		sim.waters.append({"y": band_y, "ford_x": ford_x})
		for t: int in _cycle_ticks():
			sim.tick_count = t
			checked += 1
			var fv := Main.ford_visual(band_idx, ford_x, t)
			var dry: bool = not sim._in_water(ford_x, band_y + 40 * Fixed.ONE)
			if (fv["label"] == "FORD") != dry:
				lied += 1
	Runner.T.ok(checked >= 200, "the label sweep covered the cycle on every cycling band (%d samples)" % checked)
	Runner.T.eq(lied, 0, '"FORD" is shown exactly when the crossing is dry (%d/%d lying ticks)' % [lied, checked])
	# The washed-out label must also be READABLE where it sits: over the sand strip it
	# labels, at AA-normal. Same idiom as test_menu_layout.gd's contrast fixture.
	# Band 3 at tick 0: phase = (0 + 3*150) % 600 = 450 >= 180, i.e. washed out.
	Runner.T.ok(SimWorld.ford_closed(0, 3), "band 3 is washed out at tick 0 (sanity for the row below)")
	var closed := Main.ford_visual(3, ford_x, 0)
	Runner.T.ok(closed["label"] != "FORD", "a washed-out crossing is named something else")
	var sand := Color(0.76, 0.66, 0.45)   # Art "sand" mid-tone the flag sits over
	var ratio := _contrast(closed["label_col"], sand)
	# Band 3 phase is open on t in [150, 330) — 200 sits mid-window.
	var open_ratio := _contrast(Main.ford_visual(3, ford_x, 200)["label_col"], sand)
	Runner.T.ok(not SimWorld.ford_closed(200, 3), "band 3 is crossable at tick 200 (sanity)")
	Runner.T.ok(ratio >= 3.0,
		"the WASHED OUT flag contrasts %.2f against the sand it sits on (>=3.0 large-text AA)" % ratio)
	Runner.T.ok(ratio > open_ratio,
		"...and out-reads the FORD flag it replaces (%.2f vs %.2f)" % [ratio, open_ratio])


func test_permanent_ford_is_named_and_reopening_has_a_short_truthful_settle() -> void:
	var band_idx := 2
	var ford_x := 300 * Fixed.ONE
	var closed_tick := _tick_for_ford_phase(band_idx, SimWorld.FORD_OPEN_TICKS)
	var closed := Main.ford_visual(band_idx, ford_x, closed_tick)
	Runner.T.eq(closed["second_label"], "PERMANENT FORD",
		"the always-open alternative uses explicit reliability language")
	Runner.T.ok(float(closed["second_x"]) >= 0.0,
		"the view exposes the permanent crossing's exact marked center")
	Runner.T.eq(float(closed["deck_alpha"]), 0.0,
		"main deck is absent on the first closed tick")
	Runner.T.eq(float(closed["reopen"]), 1.0,
		"closed state does not pretend a reopen transition is active")
	var open0 := Main.ford_visual(band_idx, ford_x, _tick_for_ford_phase(band_idx, 0))
	var open_last := Main.ford_visual(band_idx, ford_x,
		_tick_for_ford_phase(band_idx, Main.FORD_REOPEN_VIEW_TICKS - 1))
	var settled := Main.ford_visual(band_idx, ford_x,
		_tick_for_ford_phase(band_idx, Main.FORD_REOPEN_VIEW_TICKS))
	Runner.T.eq(float(open0["deck_alpha"]), 1.0,
		"sim-open ford is drawn dry immediately; transition never lies about collision")
	Runner.T.ok(float(open0["reopen"]) > 0.0 and float(open0["reopen"]) < 1.0,
		"first reopened frame begins the view-only wash recession")
	Runner.T.eq(float(open_last["reopen"]), 1.0,
		"reopen transition reaches full clarity on its last configured tick")
	Runner.T.eq(float(settled["reopen"]), 1.0,
		"reopened ford remains settled after the short transition")
	# The reduced-motion contract is structural: the renderer's legibility cues are
	# static text + frame, while only the translucent receding fill is motion-scaled.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains('Art.text(self, "FORD OPEN"'),
		"reopen state has a static text cue, independent of movement")
	Runner.T.ok(src.contains('fv["second_label"]'),
		"permanent reliability label is actually consumed by the renderer")


func _contrast(a: Color, b: Color) -> float:
	var la := _rel_lum(a)
	var lb := _rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _rel_lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(ch: float) -> float:
	return ch / 12.92 if ch <= 0.03928 else pow((ch + 0.055) / 1.055, 2.4)
