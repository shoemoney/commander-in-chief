extends RefCounted
## Endless War: escalating waves, the intermission shop, the Flak Vest, and
## the Fire Mission screen-clear.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_wave_one_spawns_and_escalates() -> void:
	var sim := SimWorld.new(51, 1, "endless")
	sim.step([_idle()])
	Runner.T.eq(sim.wave, 1, "wave 1 starts immediately")
	Runner.T.ok(sim.gates.is_empty() and sim.waters.is_empty() and sim.tanks.is_empty(),
		"endless arena streams no campaign world")
	var expected: int = SimWorld.WAVE_BASE_ENEMIES
	Runner.T.eq(sim.wave_pending + sim.enemies.size(), expected, "wave 1 budget staged")
	# Clear the wave by fiat; intermission should open the shop.
	for i in 600:
		sim.step([_idle()])
		for e in sim.enemies:
			e["alive"] = false
		if sim.intermission_ticks > 0:
			break
	Runner.T.ok(sim.intermission_ticks > 0, "intermission opened after the wave fell")
	var shop_crates := 0
	for pk in sim.pickups:
		if pk.get("cost", 0) > 0:
			shop_crates += 1
	Runner.T.eq(shop_crates, 4, "shop stocked four priced crates (ammo/grenade/vest/airstrike)")
	# Ride out the intermission: wave 2 with a bigger budget.
	for i in SimWorld.WAVE_INTERMISSION_TICKS + 2:
		sim.step([_idle()])
		if sim.wave == 2:
			break
	Runner.T.eq(sim.wave, 2, "wave 2 started after intermission")
	Runner.T.ok(sim.wave_pending + sim.enemies.size() >= expected + SimWorld.WAVE_ENEMIES_PER_WAVE,
		"wave 2 budget escalated")


func test_shop_purchase_spends_chest_and_refuses_broke() -> void:
	var sim := SimWorld.new(51, 1, "endless")
	var p := sim.players[0]
	# A vest crate directly on the player; broke first.
	sim.pickups.append({"x": p["x"], "y": p["y"], "kind": 2, "cost": SimWorld.SHOP_VEST_COST})
	sim.war_chest = 10
	sim.step([_idle()])
	Runner.T.ok(not p["vest"], "broke: crate refused")
	Runner.T.eq(sim.pickups.size(), 1, "crate stays on the ground")
	sim.war_chest = 100
	sim.step([_idle()])
	Runner.T.ok(p["vest"], "funded: vest bought")
	Runner.T.eq(sim.war_chest, 100 - SimWorld.SHOP_VEST_COST, "price paid from the shared chest")


func test_vest_absorbs_one_hit() -> void:
	var sim := SimWorld.new(51, 1, "endless")
	var p := sim.players[0]
	p["vest"] = true
	sim._spawn_enemy(p["x"], p["y"], false)
	sim.step([_idle()])
	Runner.T.ok(p["alive"], "vest absorbed the hit")
	Runner.T.ok(not p["vest"], "vest consumed")
	Runner.T.ok(p["hurt_iframes"] > 0, "mercy window armed")
	# After the mercy window, the next touch kills.
	for i in SimWorld.VEST_IFRAME_TICKS + 1:
		sim.step([_idle()])
		if not p["alive"]:
			break
	Runner.T.ok(not p["alive"], "no vest, no mercy: one-hit death is back")


func test_fire_mission_clears_surfaced_spares_submerged() -> void:
	var sim := SimWorld.new(51, 1, "endless")
	var p := sim.players[0]
	sim._spawn_enemy(p["x"] + 200 * Fixed.ONE, p["y"] - 100 * Fixed.ONE, false)
	sim._spawn_enemy(p["x"] - 200 * Fixed.ONE, p["y"] - 100 * Fixed.ONE, true)
	sim._spawn_frogman(p["x"], p["y"] - 200 * Fixed.ONE)
	sim.pickups.append({"x": p["x"], "y": p["y"], "kind": 3, "cost": 0})
	# Airstrike is now CALLED IN — it resolves after the telegraph window, so step
	# through the delay before checking the clear.
	for _t in SimWorld.STRIKE_TELEGRAPH_TICKS + 2:
		sim.step([_idle()])
	var surfaced_alive := 0
	var frog_alive := false
	for e in sim.enemies:
		if not e["alive"]:
			continue
		if e["kind"] == "frogman":
			frog_alive = true
		else:
			surfaced_alive += 1
	Runner.T.eq(surfaced_alive, 0, "fire mission cleared every surfaced enemy")
	Runner.T.ok(frog_alive, "the submerged frogman was spared (1986 rule)")

func test_endless_wipe_ends_run_when_party_down() -> void:
	# The fix for "Endless War can't be lost": a solo (all-down) party whose
	# broke-timer expires with no rescue wipes the run instead of free-respawning.
	var sim := SimWorld.new(9, 1, "endless")
	var p := sim.players[0]
	p["alive"] = false
	p["broke_timer"] = 1
	sim.war_chest = 0
	sim.step([SimInput.new()])
	Runner.T.ok(sim.wiped, "broke-timer expiry with the whole party down wipes the endless run")
	# Campaign still free-respawns instead of wiping.
	var camp := SimWorld.new(9, 1, "campaign")
	var cp := camp.players[0]
	cp["alive"] = false
	cp["broke_timer"] = 1
	camp.step([SimInput.new()])
	Runner.T.ok(not camp.wiped and cp["alive"], "campaign respawns at checkpoint, never wipes")


func test_endless_miniboss_spawns_holds_wave_and_pays() -> void:
	var sim := SimWorld.new(7, 1, "endless")
	sim.wave = 4
	sim._start_wave()   # -> wave 5, spawns the miniboss
	Runner.T.ok(not sim.endless_boss.is_empty() and sim.endless_boss["alive"], "wave 5 spawns the miniboss")
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.step([SimInput.new()])
	Runner.T.eq(sim.intermission_ticks, 0, "a live miniboss holds the wave open (shop stays shut)")
	var chest0 := sim.war_chest
	sim._damage_boss(sim.endless_boss, sim.endless_boss["hp"])
	Runner.T.eq(sim.war_chest - chest0, SimWorld.BOSS_BOUNTY, "killing the miniboss pays the boss bounty")
	sim.step([SimInput.new()])
	Runner.T.ok(sim.intermission_ticks > 0, "boss down + field clear opens the shop")


func test_clean_wave_and_payday_bonus() -> void:
	# PAYDAY doubles coin; a deathless wave clear pays the Clean Wave bonus.
	var sim := SimWorld.new(21, 1, "endless")
	sim.wave_mod = 4   # PAYDAY
	var chest0 := sim.war_chest
	var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
	sim.enemies.append(e)
	sim._kill_enemy(e)
	Runner.T.eq(sim.war_chest - chest0, SimWorld.COIN_RUSHER * 2, "PAYDAY doubles the coin")
	# Clean wave: force a wave>1 clear with zero deaths → bonus fires.
	sim.wave = 3
	sim.deaths_this_wave = 0
	sim.wave_pending = 0
	sim.enemies.clear()
	var score0 := sim.score
	sim.step([SimInput.new()])
	Runner.T.ok(sim.score - score0 >= 1500, "a deathless wave clear pays the Clean Wave bonus")


func test_courier_is_harmless_and_pays_a_fat_bounty() -> void:
	# The fleeing supply courier never touch-kills; caught, it drops 4× elite coin.
	var sim := SimWorld.new(55, 1, "endless")
	var p := sim.players[0]
	sim.enemies.clear()
	sim._spawn_courier()
	var c := sim.enemies[0]
	p["x"] = c["x"]
	p["y"] = c["y"]
	sim.step([SimInput.new()])
	Runner.T.ok(p["alive"], "the courier is harmless on contact (it flees, never attacks)")
	var chest0 := sim.war_chest
	sim._kill_enemy(c)
	Runner.T.eq(sim.war_chest - chest0, SimWorld.COIN_ELITE * 4, "a caught courier drops a 4× elite bounty")
