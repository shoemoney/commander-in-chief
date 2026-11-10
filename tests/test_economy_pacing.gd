extends RefCounted
## ECONOMY AND PACING: the Triple Shot ammo surcharge, the endless revive price cap,
## and the kill-streak ladder past 20. Each was a measured defect (see the commit body).

const Runner := preload("res://tests/run_tests.gd")


func _fire() -> SimInput:
	var i := SimInput.new()
	i.fire = true
	return i


## Ticks of held fire until the magazine is dry, from a full 99.
func _ticks_to_empty(spread: bool, triple: bool) -> int:
	var sim := SimWorld.new(5, 1)
	var p: Dictionary = sim.players[0]
	p["spread_ticks"] = 100000 if spread else 0
	p["triple"] = triple
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	var t := 0
	while p["mg_ammo"] > 0 and t < 5000:
		p["hurt_iframes"] = 9999
		sim.step([_fire()])
		t += 1
	return t


func test_fan_upgrades_do_not_stack_their_ammo_surcharge() -> void:
	var base := _ticks_to_empty(false, false)
	var trench := _ticks_to_empty(true, false)
	var triple := _ticks_to_empty(false, true)
	var both := _ticks_to_empty(true, true)
	Runner.T.ok(trench < base and triple < base, "a fan still costs something (base %d, trench %d, triple %d)" % [base, trench, triple])
	Runner.T.eq(both, trench, "owning BOTH fans burns no faster than one (both %d vs trench %d)" % [both, trench])
	Runner.T.eq(both, triple, "the dearer purchase never makes the cheaper one worse")


func test_burn_multiplier_is_exposed_from_the_sim() -> void:
	var sim := SimWorld.new(5, 1)
	var p: Dictionary = sim.players[0]
	Runner.T.eq(SimWorld.ammo_burn(p), 1, "plain gun burns 1 round per shot")
	p["triple"] = true
	Runner.T.eq(SimWorld.ammo_burn(p), 2, "Triple burns 2")
	p["spread_ticks"] = 50
	Runner.T.eq(SimWorld.ammo_burn(p), 2, "Triple + Trench still 2, not 3")
	p["triple"] = false
	Runner.T.eq(SimWorld.ammo_burn(p), 2, "Trench alone 2")


func test_endless_revive_multiplier_is_capped() -> void:
	var sim := SimWorld.new(9, 2, "endless")
	var p: Dictionary = sim.players[0]
	var cap := SimWorld.REVIVE_BASE_COST * SimWorld.REVIVE_MULT_CAP
	for w in [5, 10, 15, 20, 40, 80]:
		sim.wave = w
		for d in [1, 3, 8, 22]:
			p["deaths"] = d
			Runner.T.ok(sim.revive_cost(p) <= cap,
				"w%d d%d: 2P revive %d stays <= %d" % [w, d, sim.revive_cost(p), cap])
	# below the cap nothing moved
	sim.wave = 10
	p["deaths"] = 1
	Runner.T.eq(sim.revive_cost(p), 50 * 3, "wave 10 first death: 150, as before")
	sim.wave = 15
	p["deaths"] = 22
	Runner.T.eq(sim.revive_cost(p), cap, "the 2,200 revive of wave 15 now sits at the cap")


func _kill_n(sim: SimWorld, n: int) -> int:
	## Kills n rushers back to back; returns the score gained by the LAST one.
	var last := 0
	for k in n:
		var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
		sim.enemies.append(e)
		var s0: int = sim.score
		sim._kill_enemy(e)
		last = sim.score - s0
	return last


func test_streak_ladder_extends_past_20() -> void:
	var sim := SimWorld.new(7, 1)
	var base := SimWorld.COIN_RUSHER * 10
	Runner.T.eq(_kill_n(sim, 20), base * 2, "kill 20 pays +100%")
	Runner.T.eq(_kill_n(sim, 19), base * 2, "kills 21-39 stay at +100%")
	Runner.T.eq(_kill_n(sim, 1), base * 5 / 2, "kill 40 pays +150%")
	Runner.T.eq(_kill_n(sim, 39), base * 5 / 2, "kills 41-79 stay at +150%")
	Runner.T.eq(_kill_n(sim, 1), base * 3, "kill 80 pays +200%")
	Runner.T.eq(_kill_n(sim, 30), base * 3, "and it holds there")


func test_each_new_tier_has_its_own_event() -> void:
	var sim := SimWorld.new(7, 1)
	var seen: Array = []
	for k in 85:
		var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
		sim.enemies.append(e)
		sim.events.clear()
		sim._kill_enemy(e)
		for ev in sim.events:
			if ev["t"] == "streak_tier":
				seen.append([k + 1, ev["tier"]])
	Runner.T.eq(seen, [[40, 40], [80, 80]], "one streak_tier event at each of 40 and 80, none repeated")
	Runner.T.eq(SimWorld.streak_tier(79), 40, "tier lookup for the view")
	Runner.T.eq(SimWorld.streak_bonus_pct(80), 200, "bonus lookup for the view")


func test_hud_ammo_numeral_shows_the_sim_burn_multiplier() -> void:
	var HudScript: Script = load("res://src/view/hud.gd")
	var sim := SimWorld.new(5, 1)
	var p: Dictionary = sim.players[0]
	p["mg_ammo"] = 42
	Runner.T.eq(HudScript._ammo_str(p), "42", "a plain gun shows the bare numeral")
	p["triple"] = true
	Runner.T.eq(HudScript._ammo_str(p), "42x2", "a fan upgrade shows its x2 burn, driven from SimWorld.ammo_burn")
	p["spread_ticks"] = 30
	Runner.T.eq(HudScript._ammo_str(p), "42x2", "both fans still read x2, never x3")
