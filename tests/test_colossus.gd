extends RefCounted
## The Foundry Colossus: the finale. Grenades-only armor, an inverted scroll,
## the Last Stand rule, and the VICTOLY payout.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _engage(sim: SimWorld) -> Dictionary:
	## Inject the final gate into view and step once to trigger engagement.
	sim.gates.append({"y": sim.camera_top + 80 * Fixed.ONE, "open": false,
		"b1": {}, "b2": {}, "boss": {}, "final": true})
	sim.step([_idle()])
	return sim.colossus


func test_final_gate_ends_the_world() -> void:
	var sim := SimWorld.new(61, 1)
	sim.camera_top = -(SimWorld.FINAL_GATE_INDEX * 1000 + 500) * Fixed.ONE
	sim.step([_idle()])
	var final_gates := 0
	var last_y := 0
	for g in sim.gates:
		if g.get("final", false):
			final_gates += 1
			last_y = g["y"]
	Runner.T.eq(final_gates, 1, "exactly one final gate streams")
	Runner.T.eq(last_y, -SimWorld.FINAL_GATE_INDEX * SimWorld.GATE_SPACING, "final gate at the Foundry line")
	Runner.T.ok(sim._world_ended, "nothing streams past the Foundry")


func test_engage_triggers_last_stand_and_blocks_revives() -> void:
	var sim := SimWorld.new(61, 2)
	var col := _engage(sim)
	Runner.T.ok(not col.is_empty() and col["alive"], "colossus engaged when the gate came into view")
	Runner.T.ok(sim.last_stand, "Last Stand active")
	# Kill P1 with a fat chest: revive must be refused, timer must not arm.
	sim.war_chest = 10000
	sim._kill_player(sim.players[0])
	var revive := SimInput.new()
	revive.revive = true
	for i in 5:
		sim.step([revive, revive])
	Runner.T.ok(not sim.players[0]["alive"], "no revives past the final gate")
	Runner.T.eq(sim.war_chest, 10000, "the dead coin reader took nothing")
	Runner.T.eq(sim.players[0]["broke_timer"], 0, "broke fallback disabled too")


func test_bullets_useless_grenades_hurt() -> void:
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	var hp_before: int = col["hp"]
	# Bullets: pure armor, no effect (they don't even stop).
	var fake_bullet := {"x": col["x"], "y": col["y"]}
	sim._bullet_hits_boss(fake_bullet)   # gunship path must not apply either
	Runner.T.eq(col["hp"], hp_before, "bullets do nothing to the Colossus")
	# Grenade burst: chunks it.
	sim._explode(col["x"], col["y"])
	Runner.T.eq(col["hp"], hp_before - SimWorld.COLOSSUS_GRENADE_DAMAGE, "grenades damage the Colossus")


func test_phases_escalate() -> void:
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	Runner.T.eq(sim.colossus_phase(), 1, "full HP = phase 1")
	col["hp"] = SimWorld.COLOSSUS_HP / 2
	Runner.T.eq(sim.colossus_phase(), 2, "mid HP = phase 2 (volleys)")
	col["hp"] = SimWorld.COLOSSUS_HP / 4
	Runner.T.eq(sim.colossus_phase(), 3, "low HP = phase 3 (enraged)")
	# Phase 2 volley: cross the cooldown and expect a tracked strike.
	col["hp"] = SimWorld.COLOSSUS_HP / 2
	col["volley_cd"] = 1
	var strikes_before := sim.strikes.size()
	sim.step([_idle()])
	Runner.T.ok(sim.strikes.size() > strikes_before, "phase 2 called a mortar strike")


func test_descends_and_sprays() -> void:
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	var y0: int = col["y"]
	for i in 40:
		sim.step([_idle()])
	Runner.T.ok(col["y"] > y0, "the Colossus advances DOWN the map (inverted scroll)")
	Runner.T.ok(sim.enemy_bullets.size() > 0 or not sim.players[0]["alive"], "turret spray active")


func test_death_pays_out_and_wins() -> void:
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	sim.war_chest = 300
	var score_before := sim.score
	sim._damage_colossus(SimWorld.COLOSSUS_HP)
	Runner.T.ok(not col["alive"], "colossus down")
	Runner.T.ok(sim.victory, "VICTOLY")
	Runner.T.eq(sim.war_chest, 0, "Last Stand: remaining chest converted")
	Runner.T.ok(sim.score >= score_before + 300 * 10 + 5000, "chest paid out as score + victory bonus")
	var final_open := false
	for g in sim.gates:
		if g.get("final", false) and g["open"]:
			final_open = true
	Runner.T.ok(final_open, "the Foundry gate fell")

func test_c3_lane_sweep_punishes_parking() -> void:
	# c3 3v: parking in a Foundry side lane during the colossus fight draws a
	# telegraphed lane-sweep mortar; camping center (the honest fight) does not.
	var sim := SimWorld.new(7, 1)
	var gy := sim.camera_top - 3 * SimWorld.GATE_SPACING
	sim.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 1, "sweep_cd": 1}   # full HP -> phase 1 -> no c4 rise sweep
	sim.last_stand = true
	var p: Dictionary = sim.players[0]
	p["x"] = 16 * SimWorld.F_ONE   # parked at the LEFT wall (inside the margin lane)
	p["y"] = sim.camera_top + 200 * SimWorld.F_ONE
	var strikes0: int = sim.strikes.size()
	for i in 200:
		sim._step_colossus()
	Runner.T.ok(sim.strikes.size() > strikes0, "camping the side lane draws a lane-sweep mortar")
	# Every sweep strike lands in a margin lane (the retreat corridor), not center.
	for s in sim.strikes:
		Runner.T.ok(s["x"] < SimWorld.ARENA_MARGIN or s["x"] > SimWorld.SCREEN_W_FP - SimWorld.ARENA_MARGIN,
			"the sweep only hits the side lanes")
	# Center camping draws NO sweep strike (the honest fight; retreat stays fair).
	var sim2 := SimWorld.new(7, 1)
	sim2.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 1, "sweep_cd": 1}
	sim2.last_stand = true
	sim2.players[0]["x"] = SimWorld.SCREEN_CX
	sim2.players[0]["y"] = sim2.camera_top + 200 * SimWorld.F_ONE
	var s2_0: int = sim2.strikes.size()
	for i in 200:
		sim2._step_colossus()
	Runner.T.eq(sim2.strikes.size(), s2_0, "center-lane play draws no sweep (the retreat stays fair)")


func test_c3_colossus_collapses_parapets() -> void:
	# c3 2v: the Foundry floor MUTATES mid-fight — each colossus phase rise
	# collapses the trench-parapet column nearest the boss (2 rises + 2 columns),
	# so the arena the player learned in phase 1 is gone by the finish. Only
	# parapet-tagged bags collapse; other world cover is untouched.
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	# Stamp the two tagged trench-parapet columns (as the Foundry stream does).
	for tcx in [220, 420]:
		for ti in 5:
			sim.sandbags.append({"x": tcx * Fixed.ONE,
				"y": col["y"] + (280 + ti * 14) * Fixed.ONE, "world": 1, "parapet": tcx})
	# A decoy non-parapet world bag must SURVIVE both collapses.
	sim.sandbags.append({"x": SimWorld.SCREEN_CX * Fixed.ONE, "y": col["y"] + 40 * Fixed.ONE, "world": 1})
	var cols := {}
	for sb in sim.sandbags:
		if sb.has("parapet"):
			cols[sb["parapet"]] = true
	Runner.T.eq(cols.size(), 2, "two trench-parapet columns guard the Foundry")
	# Phase 1 -> 2: the nearest column collapses — a lane the player learned
	# opens up, and a dedicated parapet_collapse event fires for the view juice.
	col["hp"] = SimWorld.COLOSSUS_HP / 2
	sim.step([_idle()])
	var cols2 := {}
	for sb in sim.sandbags:
		if sb.has("parapet"):
			cols2[sb["parapet"]] = true
	Runner.T.eq(cols2.size(), 1, "the phase-2 rise collapses one parapet column")
	# The collapsed column's lane is now clear (an occupancy change, not just a count).
	var gone_col: int = 220 if not cols2.has(220) else 420
	var bags_at_gone := 0
	for sb in sim.sandbags:
		if sb["x"] == gone_col * Fixed.ONE:
			bags_at_gone += 1
	Runner.T.eq(bags_at_gone, 0, "the collapsed column's lane is fully cleared")
	var collapse_fired := false
	for ev in sim.events:
		if ev.get("t", "") == "parapet_collapse":
			collapse_fired = true
	Runner.T.ok(collapse_fired, "a dedicated parapet_collapse event fires for the view")
	# Phase 2 -> 3: the last column collapses.
	col["hp"] = SimWorld.COLOSSUS_HP / 4
	sim.step([_idle()])
	var parapets_left := 0
	var decoy_alive := false
	for sb in sim.sandbags:
		if sb.has("parapet"):
			parapets_left += 1
		elif sb["x"] == SimWorld.SCREEN_CX * Fixed.ONE:
			decoy_alive = true
	Runner.T.eq(parapets_left, 0, "the phase-3 rise collapses the last parapet column")
	Runner.T.ok(decoy_alive, "non-parapet cover is left untouched by the collapse")


func test_c4_colossus_rotating_rings() -> void:
	# c4 2v: the colossus arena's safe ANNULUS migrates OUTWARD each phase rise —
	# both ring radii grow, so a fixed camp spot flips from safe to inner-ring
	# danger and a player parked in the grown inner ring eats a telegraphed strike.
	# Colossus torture-unreachable -> goldens byte-identical.
	var sim := SimWorld.new(7, 1)
	var gy := sim.camera_top - 3 * SimWorld.GATE_SPACING
	sim.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999, "core_cd": 999, "core_open": 0, "pv": 3, "sweep_cd": 999}
	var r1: Array = sim._colossus_ring_radii()
	sim.colossus["hp"] = SimWorld.COLOSSUS_HP / 2
	var r2: Array = sim._colossus_ring_radii()
	sim.colossus["hp"] = SimWorld.COLOSSUS_HP / 4
	var r3: Array = sim._colossus_ring_radii()
	Runner.T.ok(r2[0] > r1[0] and r3[0] > r2[0], "the inner-ring radius grows across phases 1->2->3")
	Runner.T.ok(r2[1] > r1[1] and r3[1] > r2[1], "the safe annulus migrates outward each phase")
	# _colossus_ring classifies distance into 0/1/2.
	Runner.T.eq(sim._colossus_ring(10 * SimWorld.F_ONE), 0, "close to the boss = inner (melee-risk) ring")
	Runner.T.eq(sim._colossus_ring(300 * SimWorld.F_ONE), 2, "far = the outer kite rim")
	# A player parked in the grown (phase-3) inner ring eats a telegraphed strike.
	sim.last_stand = true
	var p: Dictionary = sim.players[0]
	p["x"] = SimWorld.SCREEN_CX + 40 * SimWorld.F_ONE
	p["y"] = gy
	sim.tick_count = 0
	var s0: int = sim.strikes.size()
	sim._step_colossus()
	Runner.T.ok(sim.strikes.size() > s0, "camping the grown inner ring draws a telegraphed strike")


func test_colossus_mortars_lead_a_moving_target() -> void:
	# Every colossus mortar (phase-2 volley, lane sweep, inner-ring punisher) now
	# routes through _colossus_strike, which projects the target's velocity one
	# telegraph forward. Aimed at the tile you STAND on, a 45t warn + 28px ring
	# never catches a 2.4px/tick walker (108px of travel), so the whole escalation
	# ladder was a free auto-dodge for anyone who kept walking.
	var sim := SimWorld.new(7, 1)
	var gy := sim.camera_top - 3 * SimWorld.GATE_SPACING
	sim.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP / 2,   # phase 2 -> volleys
		"x": SimWorld.SCREEN_CX, "y": gy, "spray_cd": 999, "volley_cd": 1, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 2, "sweep_cd": 999}
	sim.last_stand = true
	var p: Dictionary = sim.players[0]
	p["x"] = 120 * SimWorld.F_ONE
	p["y"] = gy + 200 * SimWorld.F_ONE   # outside the crush/inner ring; the 0.5px/t boss can't close
	sim.tick_count = 1
	var strike := {}
	var fire_x := 0
	for i in 130:   # two volleys 120t apart: the first samples, the second leads
		var n: int = sim.strikes.size()
		sim._step_colossus()
		if sim.strikes.size() > n:
			strike = sim.strikes[sim.strikes.size() - 1]
			fire_x = p["x"]
		p["x"] = p["x"] + SimWorld.PLAYER_SPEED   # walking right at full speed
		sim.tick_count += 1
	Runner.T.ok(not strike.is_empty(), "the phase-2 volley fired")
	var impact_x: int = fire_x + SimWorld.STRIKE_TELEGRAPH_TICKS * SimWorld.PLAYER_SPEED
	Runner.T.ok(strike["x"] > fire_x + 90 * SimWorld.F_ONE,
		"the strike lands AHEAD of the walker, not on their current tile")
	Runner.T.ok(sim._dist_lte(strike["x"], strike["y"], impact_x, p["y"], SimWorld.GRENADE_RADIUS),
		"the led strike is inside its kill radius when the walker arrives")
	Runner.T.ok(not sim._dist_lte(fire_x, p["y"], impact_x, p["y"], SimWorld.GRENADE_RADIUS),
		"the old current-position aim would have whiffed by more than the blast radius")
	# A camper has zero delta, so the lead is a no-op — still struck dead-on.
	var sim2 := SimWorld.new(7, 1)
	sim2.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP / 2, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 1, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 2, "sweep_cd": 999}
	sim2.last_stand = true
	var p2: Dictionary = sim2.players[0]
	p2["x"] = 120 * SimWorld.F_ONE
	p2["y"] = gy + 200 * SimWorld.F_ONE
	sim2.tick_count = 1
	for i in 130:
		sim2._step_colossus()
		sim2.tick_count += 1
	Runner.T.ok(sim2.strikes.size() >= 2, "the camper drew both volleys")
	var last2: Dictionary = sim2.strikes[sim2.strikes.size() - 1]
	Runner.T.eq(last2["x"], p2["x"], "a stationary target is still struck exactly where they stand")
	Runner.T.eq(last2["y"], p2["y"], "...on both axes")

func test_core_window_is_the_payoff() -> void:
	# The finale spends its whole UI budget on "ARMORED — WAIT FOR THE CORE" then
	# "CORE EXPOSED — OPEN FIRE". That teach is only honest if the core window is
	# also the best damage in the fight. Pin the relationship in raw uptime terms:
	# one full open window vs a full cycle of ungated grenades. (Grenade AMMO —
	# 12 carried, +4 per 300t siege drop — widens the real gap further; this is
	# the floor of the guarantee, not the ceiling.)
	var cycle: int = SimWorld.COLOSSUS_CORE_CYCLE_TICKS + SimWorld.COLOSSUS_CORE_OPEN_TICKS
	var core_dmg: int = (SimWorld.COLOSSUS_CORE_OPEN_TICKS / SimWorld.FIRE_COOLDOWN_TICKS) \
		* SimWorld.COLOSSUS_BULLET_DAMAGE
	var nade_dmg: int = (cycle / SimWorld.GRENADE_COOLDOWN_TICKS) * SimWorld.COLOSSUS_GRENADE_DAMAGE
	Runner.T.ok(core_dmg > nade_dmg,
		"one core window out-damages a whole cycle of grenades (%d vs %d)" % [core_dmg, nade_dmg])
	# ...and grenades stay a real answer to sealed plating, not a token one.
	Runner.T.ok(nade_dmg * 2 > core_dmg, "grenades still matter while the plating is sealed")
	# The boss has to outlive one window or the teach never gets a second beat.
	Runner.T.ok(SimWorld.COLOSSUS_HP > core_dmg, "the Colossus survives a single core window")
	# Behaviour, not just arithmetic: a bullet on the hull is armor while sealed
	# and COLOSSUS_BULLET_DAMAGE while the core is open.
	var sim := SimWorld.new(61, 1)
	var col := _engage(sim)
	col["y"] = sim.camera_top + 200 * SimWorld.F_ONE   # mid-screen: bullets there aren't culled off-band
	col["core_open"] = 0
	col["core_cd"] = 999
	var hp0: int = col["hp"]
	sim.bullets.append({"x": col["x"], "y": col["y"], "vx": 0, "vy": 0,
		"ttl": SimWorld.BULLET_TTL_TICKS, "owner": 0})
	sim.step([_idle()])
	Runner.T.eq(col["hp"], hp0, "sealed: bullets plink off")
	sim.bullets.clear()   # the plinked round is still in flight — retire it
	col["core_open"] = 60
	sim.bullets.append({"x": col["x"], "y": col["y"], "vx": 0, "vy": 0,
		"ttl": SimWorld.BULLET_TTL_TICKS, "owner": 0})
	sim.step([_idle()])
	Runner.T.eq(col["hp"], hp0 - SimWorld.COLOSSUS_BULLET_DAMAGE, "core open: bullets bite for real")


func test_standoff_closes_over_the_phases() -> void:
	# The crush used to be opt-in: a flat 60px standoff meant the treads could
	# never reach a player who simply stood still. The standoff now shrinks with
	# the phase, so by phase 3 the fortress drives onto your y-line.
	for spec in [[SimWorld.COLOSSUS_HP, 60], [SimWorld.COLOSSUS_HP / 4, 0]]:
		var sim := SimWorld.new(7, 1)
		var p: Dictionary = sim.players[0]
		p["y"] = sim.camera_top + 200 * SimWorld.F_ONE
		p["x"] = SimWorld.SCREEN_CX
		p["hurt_iframes"] = 9999   # measure the closure, don't measure the kill
		sim.colossus = {"alive": true, "hp": spec[0], "x": SimWorld.SCREEN_CX,
			"y": p["y"] - 100 * SimWorld.F_ONE,
			"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999,
			"core_cd": 999, "core_open": 0, "pv": 3, "sweep_cd": 999}
		sim.last_stand = true
		for i in 300:
			sim._step_colossus()
		var gap: int = (p["y"] - sim.colossus["y"]) / SimWorld.F_ONE
		Runner.T.eq(gap, spec[1], "phase standoff settles at %dpx" % spec[1])
	Runner.T.ok(SimWorld.COLOSSUS_CRUSH_RADIUS > 0, "phase 3 parks inside the crush radius")


func test_spray_cooldown_stays_bounded_under_smoke() -> void:
	# The spray is an AIMED shot, so concealment cancels it ("concealment beats
	# AIM, not AREA" — the mortar volley below it is deliberately exempt). But the
	# decrement ran unconditionally, so under sustained smoke spray_cd counted
	# down without limit: -595 after ten seconds. main.gd draws the barrel-tip
	# warm-up glow as `1 - spray_cd / COLOSSUS_SPRAY_CD_TICKS`, so that runaway
	# rendered a warm factor of 20.83 — an ever-brighter "about to fire" telegraph
	# for a shot being cancelled every single tick. Clamped at 0: the telegraph
	# tops out at "loaded", which is TRUE, and the gun still fires the instant the
	# lock comes back. Measured by running the stepper, not by reading the const.
	var sim := SimWorld.new(7, 1)
	var p: Dictionary = sim.players[0]
	p["x"] = SimWorld.SCREEN_CX
	p["y"] = sim.camera_top + 200 * SimWorld.F_ONE
	p["hurt_iframes"] = 99999
	sim.colossus = {"alive": true, "hp": SimWorld.COLOSSUS_HP, "x": SimWorld.SCREEN_CX,
		"y": sim.camera_top - 3 * SimWorld.GATE_SPACING,
		"spray_cd": 5, "volley_cd": 99999, "spawn_cd": 99999,
		"core_cd": 99999, "core_open": 0, "pv": 1, "sweep_cd": 99999}
	sim.last_stand = true
	var worst := 0
	var shots := 0
	for i in 600:
		p["smoke_ticks"] = 600   # sustained concealment: every spray is cancelled
		var ev0: int = sim.events.size()
		sim._step_colossus()
		for e in range(ev0, sim.events.size()):
			if sim.events[e]["t"] == "enemy_shot":
				shots += 1
		worst = mini(worst, sim.colossus["spray_cd"])
	Runner.T.eq(shots, 0, "10s of smoke: concealment cancels every aimed spray")
	Runner.T.eq(worst, 0, "and spray_cd floors at 0 instead of running unbounded negative")
	# The telegraph the view draws off it therefore stays inside [0, 1].
	var warm := 1.0 - float(sim.colossus["spray_cd"]) / float(SimWorld.COLOSSUS_SPRAY_CD_TICKS)
	Runner.T.ok(warm >= 0.0 and warm <= 1.0,
		"the barrel-tip warm-up glow stays truthful (%.2f must be within [0,1])" % warm)
	# Concealment beats AIM, it does not disarm: the shot lands the tick it lifts.
	p["smoke_ticks"] = 0
	var ev1: int = sim.events.size()
	sim._step_colossus()
	var fired := false
	for e in range(ev1, sim.events.size()):
		if sim.events[e]["t"] == "enemy_shot":
			fired = true
	Runner.T.ok(fired, "the held-back spray fires on the first un-smoked tick")
	Runner.T.eq(sim.colossus["spray_cd"], SimWorld.COLOSSUS_SPRAY_CD_TICKS,
		"and re-arms to a full cooldown — smoke banked no extra shots")
