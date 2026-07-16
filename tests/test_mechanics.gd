extends RefCounted
## Correctness coverage for mechanics that so far only had determinism
## (reproducibility) coverage: revive cost curve, flawless-streak compounding,
## avenge bounty, kill-streak surge, and boss/observer kill-event kind tags.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_revive_cost_scales_with_deaths_and_caps_at_three() -> void:
	var sim := SimWorld.new(1, 2)   # 2P campaign: no solo halving, no endless surcharge
	var p := sim.players[0]
	p["deaths"] = 0
	Runner.T.eq(sim.revive_cost(p), 50, "0 deaths costs the base 50")
	p["deaths"] = 1
	Runner.T.eq(sim.revive_cost(p), 50, "1 death still the base 50 (50*1)")
	p["deaths"] = 2
	Runner.T.eq(sim.revive_cost(p), 100, "2 deaths costs 50*2")
	p["deaths"] = 3
	Runner.T.eq(sim.revive_cost(p), 150, "3 deaths costs 50*3")
	p["deaths"] = 9
	Runner.T.eq(sim.revive_cost(p), 150, "deaths past 3 stay capped at 50*3")


func test_revive_cost_solo_halves() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["deaths"] = 0
	Runner.T.eq(sim.revive_cost(p), 25, "solo floors at half the base cost")
	p["deaths"] = 2
	Runner.T.eq(sim.revive_cost(p), 50, "solo halves the deaths-scaled cost (100/2)")


func test_revive_cost_endless_adds_wave_surcharge() -> void:
	var sim := SimWorld.new(1, 2, "endless")
	var p := sim.players[0]
	p["deaths"] = 1
	sim.wave = 9
	Runner.T.eq(sim.revive_cost(p), 70, "wave 9 adds (9/5)*20 = 20 to the base 50")
	sim.wave = 25
	Runner.T.eq(sim.revive_cost(p), 150, "wave 25 adds (25/5)*20 = 100 to the base 50")


func test_flawless_streak_compounds_and_caps_at_3x() -> void:
	var sim := SimWorld.new(2, 1, "campaign")
	var y := 100 * Fixed.ONE
	for i in 4:
		sim.gates.clear()
		sim.gates.append({"y": y, "open": false,
			"b1": {"alive": false}, "b2": {"alive": false}, "boss": {}})
		sim.deaths_since_gate = 0
		var chest0 := sim.war_chest
		var score0 := sim.score
		sim._step_gates()
		var expect_mult: int = mini(i + 1, 3)
		Runner.T.eq(sim.flawless_streak, i + 1, "flawless_streak increments on clear %d" % (i + 1))
		Runner.T.eq(sim.war_chest - chest0, 50 * expect_mult, "chest bonus compounds (clear %d)" % (i + 1))
		Runner.T.eq(sim.score - score0, 2000 * expect_mult, "score bonus compounds (clear %d)" % (i + 1))
	# 4th clear above already proved the cap holds at 3x past 3 clears.


func test_death_resets_flawless_streak() -> void:
	var sim := SimWorld.new(3, 1, "campaign")
	sim.flawless_streak = 2
	sim._kill_player(sim.players[0])
	Runner.T.eq(sim.flawless_streak, 0, "a death zeroes the compounding flawless streak")


func test_avenge_bounty_only_near_a_downed_ally() -> void:
	var sim := SimWorld.new(4, 2, "campaign")
	var ally := sim.players[1]
	sim._kill_player(ally)   # downs player 2, leaves a body at their last position
	# Kill next to the downed ally: +5 avenge on top of the flat rusher coin.
	var near_enemy := {"x": ally["x"], "y": ally["y"], "alive": true, "elite": false, "kind": "rusher"}
	var chest0 := sim.war_chest
	sim._kill_enemy(near_enemy)
	Runner.T.eq(sim.war_chest - chest0, SimWorld.COIN_RUSHER + 5, "kill beside a downed ally pays the +5 avenge bounty")
	var saw_avenge := false
	for e in sim.events:
		if e["t"] == "avenge":
			saw_avenge = true
	Runner.T.ok(saw_avenge, "avenge event fired for the close kill")
	# Kill far from the downed ally: flat coin only, no avenge.
	var far_enemy := {"x": ally["x"], "y": ally["y"] - 2000 * Fixed.ONE, "alive": true,
		"elite": false, "kind": "rusher"}
	var chest1 := sim.war_chest
	sim._kill_enemy(far_enemy)
	Runner.T.eq(sim.war_chest - chest1, SimWorld.COIN_RUSHER, "a distant kill pays no avenge bounty")
	for e in sim.events:
		Runner.T.ok(e["t"] != "avenge" or e["x"] == near_enemy["x"], "no avenge event for the distant kill")


func test_kill_streak_surge_at_20_boosts_alive_players() -> void:
	var sim := SimWorld.new(5, 1, "campaign")
	var p := sim.players[0]
	Runner.T.eq(p["boost_ticks"], 0, "no boost before the streak")
	for i in 20:
		var e := {"x": 0, "y": -5000 * Fixed.ONE, "alive": true, "elite": false, "kind": "rusher"}
		sim._kill_enemy(e)
	Runner.T.eq(sim.kill_streak, 20, "20 consecutive kills land the streak")
	Runner.T.eq(p["boost_ticks"], SimWorld.BAIL_BOOST_TICKS * 2, "the 20-streak surge boosts the alive player")
	var saw_surge := false
	for e in sim.events:
		if e["t"] == "surge":
			saw_surge = true
	Runner.T.ok(saw_surge, "surge event fired on the 20th kill")


func test_boss_and_observer_kills_carry_their_kind() -> void:
	var sim := SimWorld.new(6, 1)
	var boss := {"hp": 5, "alive": true, "x": 0, "gate_y": 0}
	sim._damage_boss(boss, 99)
	var boss_kind := ""
	for e in sim.events:
		if e["t"] == "kill" and e.get("kind", "") == "boss":
			boss_kind = e["kind"]
	Runner.T.eq(boss_kind, "boss", "boss kill event carries kind == boss")

	var sim2 := SimWorld.new(7, 1)
	sim2.observer = {"x": 100 * Fixed.ONE}
	sim2._kill_observer()
	var observer_kind := ""
	for e in sim2.events:
		if e["t"] == "kill" and e.get("kind", "") == "observer":
			observer_kind = e["kind"]
	Runner.T.eq(observer_kind, "observer", "observer kill event carries kind == observer")


func test_rend_rounds_punch_through_the_shield_block() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	# Shield ABOVE the player: its facing (toward the nearest player) points
	# south, so a bullet travelling north arrives square into the front arc.
	sim._spawn_special(320 * Fixed.ONE, p["y"] - 100 * Fixed.ONE, "shield")
	var e := sim.enemies[0]
	sim.bullets.append({"x": e["x"], "y": e["y"] + 6 * Fixed.ONE,
		"vx": 0, "vy": -Fixed.ONE, "ttl": 10, "owner": 0})
	sim._step_bullets()
	Runner.T.ok(e["alive"], "without Rend the front arc blocks the round")
	Runner.T.eq(sim.bullets.size(), 0, "the blocked round dies on the shield")
	p["rend_ticks"] = 100
	sim.bullets.append({"x": e["x"], "y": e["y"] + 6 * Fixed.ONE,
		"vx": 0, "vy": -Fixed.ONE, "ttl": 10, "owner": 0})
	sim._step_bullets()
	Runner.T.ok(not e["alive"], "with Rend the same round punches through the block")


func test_claymore_plants_on_interact_and_consumes_a_charge() -> void:
	var sim := SimWorld.new(12, 1)
	var p := sim.players[0]
	sim._apply_supply(p, 8)
	sim._apply_supply(p, 8)
	Runner.T.eq(p["claymores"], 2, "capsule grants carried charges")
	sim.step([SimInput.new()])   # let the initial world-stream settle
	var before := sim.mines.size()
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.eq(sim.mines.size(), before + 1, "INTERACT on foot plants an armed mine")
	Runner.T.eq(p["claymores"], 1, "the plant consumes one charge")
	var m: Dictionary = sim.mines[sim.mines.size() - 1]
	Runner.T.ok(m["armed"], "the planted claymore is armed")
	Runner.T.ok(not sim._dist_lte(p["x"], p["y"], m["x"], m["y"], SimWorld.MINE_TRIGGER_RADIUS),
		"the plant lands outside its own trigger radius")


func test_smoke_blinds_ranged_fire_but_not_pathing() -> void:
	# Design-loop iter1: smoke denies the FIRE-COMMIT (windup/paint starts),
	# never the pathing — blinding _nearest_alive_player wholesale froze the
	# entire field (and the colossus finale) into a free-kill printer.
	var sim := SimWorld.new(13, 1)
	var p := sim.players[0]
	p["smoke_ticks"] = 100
	sim._spawn_enemy(p["x"] + 60 * Fixed.ONE, p["y"], true)   # elite inside standoff
	var e := sim.enemies[0]
	e["fire_cd"] = 0
	sim._step_enemies()
	Runner.T.eq(e.get("windup", 0), 0, "elite cannot start a windup into smoke")
	sim._spawn_enemy(p["x"], p["y"] - 150 * Fixed.ONE, false)   # rusher above
	var r: Dictionary = sim.enemies[1]
	var ry0: int = r["y"]
	sim._step_enemies()
	Runner.T.ok(r["y"] != ry0, "rusher still closes on a smoked player")
	p["smoke_ticks"] = 0
	sim._step_enemies()
	Runner.T.ok(e.get("windup", 0) > 0, "elite opens fire once the smoke clears")


func test_flashbang_stuns_field_enemies_then_releases() -> void:
	var sim := SimWorld.new(14, 1)
	var p := sim.players[0]
	sim._spawn_enemy(320 * Fixed.ONE, p["y"] - 120 * Fixed.ONE, false)
	var e := sim.enemies[0]
	var y0: int = e["y"]
	sim._apply_supply(p, 10)
	Runner.T.eq(sim.flash_ticks, SimWorld.FLASH_STUN_TICKS, "flashbang arms the stun window")
	sim.step([SimInput.new()])
	Runner.T.eq(e["y"], y0, "stunned rusher holds position")
	sim.flash_ticks = 0
	sim.step([SimInput.new()])
	Runner.T.ok(e["y"] != y0, "released rusher advances again")


func test_drone_paints_a_tracked_strike() -> void:
	var sim := SimWorld.new(15, 1, "endless")
	var p := sim.players[0]
	sim._spawn_special(320 * Fixed.ONE, p["y"] - 60 * Fixed.ONE, "drone")
	var e := sim.enemies[0]
	e["fire_cd"] = 0
	var painted := false
	for t in 120:
		sim.step([SimInput.new()])
		if not sim.strikes.is_empty():
			painted = true
			break
	Runner.T.ok(painted, "the drone paints a tracked mortar strike within one cycle")
