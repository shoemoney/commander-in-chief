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
	sim.colossus = {"alive": true, "hp": 40, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 1, "sweep_cd": 1}
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
	sim2.colossus = {"alive": true, "hp": 40, "x": SimWorld.SCREEN_CX, "y": gy,
		"spray_cd": 999, "volley_cd": 999, "spawn_cd": 999,
		"core_cd": 999, "core_open": 0, "pv": 1, "sweep_cd": 1}
	sim2.last_stand = true
	sim2.players[0]["x"] = SimWorld.SCREEN_CX
	sim2.players[0]["y"] = sim2.camera_top + 200 * SimWorld.F_ONE
	var s2_0: int = sim2.strikes.size()
	for i in 200:
		sim2._step_colossus()
	Runner.T.eq(sim2.strikes.size(), s2_0, "center-lane play draws no sweep (the retreat stays fair)")
