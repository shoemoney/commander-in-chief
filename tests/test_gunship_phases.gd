extends RefCounted
## The Bridge Gunship's three HP-third acts (src/sim/gunship_phases.gd): phase
## thresholds, act order, every new attack's telegraph length and geometry,
## 1P/2P scaling, Endless inheritance, and the view naming what the sim does.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")

const R := SimWorld.GRENADE_RADIUS


func _boss_sim(players := 1, mode := "campaign") -> Array:
	var sim := SimWorld.new(41, players, mode)
	var gy: int = sim.camera_top + 100 * Fixed.ONE
	var hp: int = sim._scaled_boss_hp(SimWorld.BOSS_HP)
	var boss := {"alive": true, "hp": hp, "max_hp": hp, "x": 320 * Fixed.ONE,
		"dir": 1, "phase_t": 0, "gate_y": gy}
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	return [sim, boss]


## Step the boss from t0 up to and including t1 and return the strikes it called
## (strike dicts as they were appended, before they tick down).
func _strikes_over(sim: SimWorld, boss: Dictionary, hp: int, t0: int, t1: int) -> Array:
	boss["hp"] = hp
	boss["phase_t"] = t0 - 1
	sim.strikes.clear()
	var out: Array = []
	for t in range(t0, t1 + 1):
		var n := sim.strikes.size()
		sim._step_one_boss(boss)
		for i in range(n, sim.strikes.size()):
			out.append({"t": t, "x": sim.strikes[i]["x"], "y": sim.strikes[i]["y"],
				"ticks": sim.strikes[i]["ticks"]})
	return out


func test_phase_thresholds_follow_hp_thirds_of_the_stored_max() -> void:
	for mx in [40, 64, 90]:
		Runner.T.eq(GunshipPhases.phase_of(mx, mx), 1, "full HP of %d is act 1" % mx)
		Runner.T.eq(GunshipPhases.phase_of(mx * 2 / 3 + 1, mx), 1, "just above two thirds of %d is act 1" % mx)
		Runner.T.eq(GunshipPhases.phase_of(mx * 2 / 3, mx), 2, "two thirds of %d is act 2" % mx)
		Runner.T.eq(GunshipPhases.phase_of(mx / 3 + 1, mx), 2, "just above one third of %d is act 2" % mx)
		Runner.T.eq(GunshipPhases.phase_of(mx / 3, mx), 3, "one third of %d is act 3" % mx)
		Runner.T.eq(GunshipPhases.phase_of(1, mx), 3, "a sliver of %d is act 3" % mx)
	# The cut points are the arena-crack edges _damage_boss already uses.
	var s: Array = _boss_sim()
	Runner.T.eq(s[1]["max_hp"], 40, "1P campaign gunship pool")
	var s2: Array = _boss_sim(2)
	Runner.T.eq(s2[1]["max_hp"], 64, "2P gunship pool scales +60%")
	Runner.T.eq(GunshipPhases.phase_of(43, 64), 1, "2P: 43/64 is still act 1")
	Runner.T.eq(GunshipPhases.phase_of(42, 64), 2, "2P: act 2 starts at 42 (2/3 of 64), not at the 1P 26")
	Runner.T.eq(GunshipPhases.phase_of(21, 64), 3, "2P: act 3 starts at 21")


func test_act_order_one_adds_nothing_two_adds_salvo_three_adds_carpet() -> void:
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	var mx: int = boss["max_hp"]
	sim.players[0]["x"] = 300 * Fixed.ONE
	sim.players[0]["y"] = boss["gate_y"] + 300 * Fixed.ONE
	var strafe1 := _strikes_over(sim, boss, mx, 1, SimWorld.BOSS_STRAFE_TICKS - 1)
	Runner.T.eq(strafe1.size(), 0, "act 1 strafe: no strike (the original fight is untouched)")
	var volley1 := _strikes_over(sim, boss, mx, SimWorld.BOSS_STRAFE_TICKS, SimWorld.BOSS_CYCLE_TICKS - 1)
	Runner.T.eq(volley1.size(), SimWorld.BOSS_MORTAR_TICKS.size() + 1,
		"act 1 mortar act: the 3 shells + the campaign cover-rotation strike, no carpet")
	# Act 2: the salvo lands INSIDE the strafe act, on top of act 1's behaviour.
	var strafe2 := _strikes_over(sim, boss, mx * 2 / 3, 1, SimWorld.BOSS_STRAFE_TICKS - 1)
	Runner.T.eq(strafe2.size(), GunshipPhases.SALVO_TICKS.size(), "act 2 strafe: exactly the salvo")
	for i in strafe2.size():
		Runner.T.eq(strafe2[i]["t"], GunshipPhases.SALVO_TICKS[i], "salvo strike %d lands on its tick" % i)
	var volley2 := _strikes_over(sim, boss, mx * 2 / 3, SimWorld.BOSS_STRAFE_TICKS, SimWorld.BOSS_CYCLE_TICKS - 1)
	Runner.T.eq(volley2.size(), volley1.size(), "act 2 mortar act is act 1's volley (no carpet yet)")
	# Act 3: carpet in the mortar act.
	var volley3 := _strikes_over(sim, boss, mx / 3, SimWorld.BOSS_STRAFE_TICKS, SimWorld.BOSS_CYCLE_TICKS - 1)
	Runner.T.eq(volley3.size(), volley1.size() + GunshipPhases.CARPET_COUNT,
		"act 3 mortar act: the volley + a %d-strike carpet" % GunshipPhases.CARPET_COUNT)
	var strafe3 := _strikes_over(sim, boss, mx / 3, 1, SimWorld.BOSS_STRAFE_TICKS - 1)
	Runner.T.eq(strafe3.size(), GunshipPhases.SALVO_TICKS.size(), "act 3 keeps the act-2 salvo")


func test_every_new_strike_telegraphs_for_at_least_the_reaction_floor() -> void:
	Runner.T.ok(SimWorld.STRIKE_TELEGRAPH_TICKS >= GunshipPhases.MIN_TELEGRAPH_TICKS,
		"the strike telegraph (%d) is at or above the 24-tick reaction floor" % SimWorld.STRIKE_TELEGRAPH_TICKS)
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	sim.players[0]["x"] = 300 * Fixed.ONE
	sim.players[0]["y"] = boss["gate_y"] + 300 * Fixed.ONE
	var all := _strikes_over(sim, boss, boss["max_hp"] / 3, 1, SimWorld.BOSS_CYCLE_TICKS - 1)
	Runner.T.ok(all.size() >= 2 + GunshipPhases.CARPET_COUNT, "act 3 called its full kit (%d strikes)" % all.size())
	for st in all:
		Runner.T.ok(st["ticks"] >= GunshipPhases.MIN_TELEGRAPH_TICKS,
			"strike at t=%d warns for %d ticks" % [st["t"], st["ticks"]])
	# The warn event is raised in the same call as the strike (one funnel).
	sim.events.clear()
	boss["hp"] = boss["max_hp"] / 3
	boss["phase_t"] = GunshipPhases.SALVO_TICKS[0] - 1
	sim.strikes.clear()
	sim._step_one_boss(boss)
	var warns := 0
	for ev in sim.events:
		if ev["t"] == "strike_warn":
			warns += 1
	Runner.T.eq(warns, sim.strikes.size(), "every salvo strike raised its strike_warn")


func test_salvo_lands_on_the_cover_the_player_hides_behind() -> void:
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	var bag: Array = SimWorld.GUNSHIP_COVER_BAGS[0]
	var bx: int = int(bag[0]) * Fixed.ONE
	var by: int = boss["gate_y"] + int(bag[1]) * Fixed.ONE
	# Standing 20 px behind the first bag: the salvo shells the BAG, not his feet.
	sim.players[0]["x"] = bx
	sim.players[0]["y"] = by + 20 * Fixed.ONE
	var hit := _strikes_over(sim, boss, boss["max_hp"] * 2 / 3, GunshipPhases.SALVO_TICKS[0], GunshipPhases.SALVO_TICKS[0])
	Runner.T.eq(hit.size(), 1, "one salvo strike")
	Runner.T.eq(hit[0]["x"], bx, "the salvo is centered on the bag's x")
	Runner.T.eq(hit[0]["y"], by, "the salvo is centered on the bag's y")
	var px: int = sim.players[0]["x"]
	var py: int = sim.players[0]["y"]
	Runner.T.ok(Fixed.length(px - hit[0]["x"], py - hit[0]["y"]) < R,
		"the player's cover spot IS inside the drawn kill radius - he must relocate")
	# Far from every bag (and in Endless, which has none): the strike is his feet.
	sim.players[0]["x"] = 320 * Fixed.ONE
	sim.players[0]["y"] = boss["gate_y"] + 330 * Fixed.ONE
	var feet := _strikes_over(sim, boss, boss["max_hp"] * 2 / 3, GunshipPhases.SALVO_TICKS[0], GunshipPhases.SALVO_TICKS[0])
	Runner.T.eq(feet[0]["x"], sim.players[0]["x"], "no cover nearby: the salvo lands on his x")
	Runner.T.eq(feet[0]["y"], sim.players[0]["y"], "no cover nearby: the salvo lands on his y")


func test_carpet_geometry_is_a_row_with_walkable_gaps() -> void:
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	var py: int = boss["gate_y"] + 250 * Fixed.ONE
	sim.players[0]["x"] = 300 * Fixed.ONE
	sim.players[0]["y"] = py
	var ticks: Array = GunshipPhases.carpet_ticks()
	Runner.T.eq(ticks.size(), GunshipPhases.CARPET_COUNT, "carpet tick table size")
	Runner.T.ok(ticks[0] >= SimWorld.BOSS_STRAFE_TICKS and ticks[ticks.size() - 1] < SimWorld.BOSS_CYCLE_TICKS,
		"the carpet sits inside the mortar act")
	Runner.T.ok(ticks[0] > int(SimWorld.boss_mortar_ticks(0)[SimWorld.boss_mortar_ticks(0).size() - 1]),
		"the carpet follows the base volley instead of stacking on a shell")
	for dir in [1, -1]:
		boss["dir"] = dir
		var strikes := _strikes_over(sim, boss, boss["max_hp"] / 3, ticks[0], ticks[ticks.size() - 1])
		Runner.T.eq(strikes.size(), GunshipPhases.CARPET_COUNT, "dir %d: five carpet strikes (no shell in that window)" % dir)
		var prev_x := -1
		for i in strikes.size():
			Runner.T.eq(strikes[i]["y"], py, "carpet strike %d is on the player's row" % i)
			Runner.T.eq(strikes[i]["t"], ticks[i], "carpet strike %d is on its tick" % i)
			if prev_x >= 0:
				var gap: int = absi(strikes[i]["x"] - prev_x)
				Runner.T.ok(gap > 2 * R + 16 * Fixed.ONE,
					"neighbouring columns leave a walkable gap (%.0f px apart, rings are %.0f px wide)"
					% [gap / float(Fixed.ONE), 2 * R / float(Fixed.ONE)])
				Runner.T.ok((strikes[i]["x"] - prev_x) * dir > 0, "the sweep runs the way the hull drifts (dir %d)" % dir)
			prev_x = strikes[i]["x"]
			Runner.T.ok(strikes[i]["x"] >= SimWorld.WORLD_LEFT and strikes[i]["x"] <= SimWorld.WORLD_RIGHT,
				"carpet column %d is inside the world" % i)


func test_act_three_is_faster_but_not_unfair() -> void:
	var base := SimWorld.BOSS_SPEED
	Runner.T.eq(GunshipPhases.speed(1, base), base, "act 1 drift unchanged")
	Runner.T.eq(GunshipPhases.speed(2, base), base, "act 2 drift unchanged")
	Runner.T.ok(GunshipPhases.speed(3, base) > base, "act 3 drifts faster")
	Runner.T.ok(GunshipPhases.speed(3, base) <= base * 3 / 2,
		"...but under 1.5x: measured, 1.5x made the hull un-leadable (duelist fight 18.7s -> 35s)")
	for tier in [0, 1, 2, 3]:
		var b := SimWorld.boss_spray_interval(tier)
		Runner.T.eq(GunshipPhases.spray_interval(2, b), b, "act 2 spray cadence unchanged (tier %d)" % tier)
		Runner.T.ok(GunshipPhases.spray_interval(3, b) < b, "act 3 sprays faster (tier %d)" % tier)
		Runner.T.ok(GunshipPhases.spray_interval(3, b) >= 4, "...never below the 4-tick floor")
	# And it really moves faster in the sim.
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	sim.players[0]["y"] = boss["gate_y"] + 300 * Fixed.ONE
	boss["phase_t"] = 0
	var x0: int = boss["x"]
	sim._step_one_boss(boss)
	Runner.T.eq(boss["x"] - x0, SimWorld.BOSS_SPEED, "act 1 steps BOSS_SPEED")
	boss["hp"] = boss["max_hp"] / 3
	boss["x"] = x0
	sim._step_one_boss(boss)
	Runner.T.eq(boss["x"] - x0, GunshipPhases.speed(3, SimWorld.BOSS_SPEED), "act 3 steps the enraged speed")


func test_endless_minibosses_inherit_the_acts_and_scale_by_wave() -> void:
	for wave in [5, 10, 15]:
		var sim := SimWorld.new(41, 1, "endless")
		sim.wave = wave - 1   # _start_wave increments
		sim._start_wave()
		var eb: Dictionary = sim.endless_boss
		Runner.T.ok(not eb.is_empty(), "wave %d spawned its miniboss" % wave)
		var want_hp: int = sim._scaled_boss_hp(SimWorld.BOSS_HP + (wave / 5 - 1) * (SimWorld.BOSS_HP / 2))
		Runner.T.eq(eb["max_hp"], want_hp, "wave %d pool is the existing depth scaling" % wave)
		# Thresholds scale with the pool.
		Runner.T.eq(GunshipPhases.phase_of(eb["max_hp"] * 2 / 3, eb["max_hp"]), 2, "wave %d act 2 edge" % wave)
		Runner.T.eq(GunshipPhases.phase_of(eb["max_hp"] / 3, eb["max_hp"]), 3, "wave %d act 3 edge" % wave)
		# The miniboss runs the same acts: a salvo with no bags -> the player's feet.
		eb["phase_t"] = GunshipPhases.SALVO_TICKS[0] - 1
		eb["hp"] = eb["max_hp"] * 2 / 3
		sim.strikes.clear()
		sim._step_one_boss(eb)
		Runner.T.eq(sim.strikes.size(), 1, "wave %d: the act-2 salvo fires" % wave)
		var p: Dictionary = sim.players[0]
		Runner.T.eq(sim.strikes[0]["x"], p["x"], "wave %d: Endless has no cover bags, so the salvo takes his x" % wave)
		Runner.T.eq(sim.strikes[0]["y"], p["y"], "wave %d: ...and his y" % wave)
		eb["hp"] = eb["max_hp"] / 3
		var carpet := _strikes_over(sim, eb, eb["max_hp"] / 3, GunshipPhases.carpet_ticks()[0], GunshipPhases.carpet_ticks()[4])
		var carpet_n := 0
		for st in carpet:
			if st["y"] == p["y"]:
				carpet_n += 1
		Runner.T.ok(carpet_n >= GunshipPhases.CARPET_COUNT, "wave %d: the act-3 carpet fires" % wave)


func test_plate_names_each_act_and_matches_the_sim_boundaries() -> void:
	var names: Array = Main.GUNSHIP_PHASE_NAMES_BY_HP
	Runner.T.eq(names.size(), 3, "one name pair per HP third")
	Runner.T.eq(names[0], Main.GUNSHIP_PHASE_NAMES, "act 1 keeps its two original names")
	var seen := {}
	for hp_phase in [1, 2, 3]:
		for pt in [0, SimWorld.BOSS_STRAFE_TICKS - 1, SimWorld.BOSS_STRAFE_TICKS, SimWorld.BOSS_CYCLE_TICKS - 1]:
			var lbl: String = Main.gunship_phase_label("GUNSHIP", pt, hp_phase)
			var want: String = names[hp_phase - 1][0 if pt < SimWorld.BOSS_STRAFE_TICKS else 1]
			Runner.T.eq(lbl, "GUNSHIP — %s" % want, "act %d at t=%d" % [hp_phase, pt])
			seen[lbl] = true
	Runner.T.ok(seen.size() >= 5, "the plate tells the acts apart (%d distinct labels)" % seen.size())
	Runner.T.ok(Main.gunship_phase_label("GUNSHIP", -10, 3).contains("INBOUND"), "the fly-in is still INBOUND at any HP")
	Runner.T.eq(Main.gunship_phase_label("GUNSHIP", 5), "GUNSHIP — STRAFING RUN", "the 2-arg call is act 1 (old callers)")


func test_view_telegraph_is_the_strike_the_sim_resolves() -> void:
	## VIEW HONESTY: the new attacks add no private view state - they are strikes,
	## and the strike ring the view draws must be the radius and the clock the sim
	## resolves. Pin the drawing source to the sim's constants, and pin the sim's
	## detonation to that same radius by standing a victim on the ring edge.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("func _draw_telegraphs()")
	var body := src.substr(i, 2400)
	Runner.T.ok(body.contains("SimWorld.GRENADE_RADIUS * PX"), "the ring is drawn at the sim's GRENADE_RADIUS")
	Runner.T.ok(body.contains("SimWorld.STRIKE_TELEGRAPH_TICKS"), "the timer disc fills over the sim's STRIKE_TELEGRAPH_TICKS")
	var s: Array = _boss_sim()
	var sim: SimWorld = s[0]
	var boss: Dictionary = s[1]
	sim.players[0]["x"] = 320 * Fixed.ONE
	sim.players[0]["y"] = boss["gate_y"] + 330 * Fixed.ONE
	var hit := _strikes_over(sim, boss, boss["max_hp"] * 2 / 3, GunshipPhases.SALVO_TICKS[0], GunshipPhases.SALVO_TICKS[0])
	Runner.T.eq(hit.size(), 1, "a salvo strike to resolve")
	# Resolve the strike for real: a victim 4 px inside the drawn ring is hurt, one
	# 4 px outside is untouched (ring radius == blast radius, on the sim's clock).
	var hurt := {}
	for side in [-1, 1]:
		sim.strikes.clear()
		sim.strikes.append({"x": hit[0]["x"], "y": hit[0]["y"], "ticks": hit[0]["ticks"], "obs": false})
		var p: Dictionary = sim.players[0]
		p["alive"] = true
		p["roll_iframe"] = false
		p["x"] = hit[0]["x"] + R - side * 4 * Fixed.ONE
		p["y"] = hit[0]["y"]
		var before: int = p.hash()
		for _k in SimWorld.STRIKE_TELEGRAPH_TICKS - 1:
			sim._resolve_strikes()
		Runner.T.eq(p.hash(), before, "nothing resolves before the %d-tick clock runs out" % SimWorld.STRIKE_TELEGRAPH_TICKS)
		sim._resolve_strikes()
		hurt[side] = p.hash() != before
	Runner.T.ok(hurt[1], "4 px inside the drawn ring when the clock runs out is lethal")
	Runner.T.ok(not hurt[-1], "4 px outside the drawn ring is safe")
