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
	Runner.T.eq(shop_crates, 3, "shop stocked three priced crates (ammo/grenade/vest; airstrike is wheel-only)")
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


func test_c2_arena_mutation_cadence() -> void:
	# Dynamic arena geometry (c2 4v): waves 3/6 each crater one rock forever
	# and drop a _mix-derived 3-bag L — the kiting loop goes stale on cadence.
	var sim := SimWorld.new(11, 1, "endless")
	var rocks0: int = sim.rocks.size()
	while sim.wave < 7:
		sim._start_wave()
	Runner.T.eq(sim.rocks.size(), rocks0 - 2, "waves 3 and 6 each cratered exactly one rock")
	# The wave-3 L (first mutation, slots clear by construction) lands its
	# anchor bag at the exact derivation — evidence, not adverbs.
	var amix3 := SimWorld._mix(3, 11)
	var slot3: Array = SimWorld.ARENA_L_SLOTS[(amix3 >> 8) % SimWorld.ARENA_L_SLOTS.size()]
	var found := false
	for sb in sim.sandbags:
		if sb["x"] == slot3[0] * SimWorld.F_ONE and sb["y"] == slot3[1] * SimWorld.F_ONE:
			found = true
	Runner.T.ok(found, "the wave-3 anchor bag sits exactly at the _mix-derived slot")
	# Decorrelation: the wave-3 slot pick varies across seeds.
	var picks := {}
	for sd in [1, 2, 3, 4, 5]:
		picks[(SimWorld._mix(3, sd) >> 8) % SimWorld.ARENA_L_SLOTS.size()] = true
	Runner.T.ok(picks.size() >= 2, "wave-3 slot picks vary across seeds (got %d distinct)" % picks.size())
	# Twin same-seed sims agree after 7 mutated waves.
	var a := SimWorld.new(23, 1, "endless")
	var b := SimWorld.new(23, 1, "endless")
	for i in 7:
		a._start_wave()
		b._start_wave()
	Runner.T.eq(a.checksum(), b.checksum(), "twin sims checksum-match after 7 mutated waves")


func test_c2_arena_rock_floor() -> void:
	# The scar never strips the arena naked: ARENA_ROCK_FLOOR holds under a
	# long run (25 waves = 8 mutation beats > the 4 excess rocks).
	var sim := SimWorld.new(7, 1, "endless")
	while sim.wave < 25:
		sim._start_wave()
	Runner.T.ok(sim.rocks.size() >= SimWorld.ARENA_ROCK_FLOOR,
		"25 waves later the rock floor holds (%d >= %d)" % [sim.rocks.size(), SimWorld.ARENA_ROCK_FLOOR])


func test_c2_arena_slots_clear_hull() -> void:
	# Static pin: every authored L slot keeps >= HULL_CLEARANCE from the arena
	# walls and every static quadrant-rock coord (squared ints, no floats).
	var hc_px: int = SimWorld.HULL_CLEARANCE / SimWorld.F_ONE
	for slot in SimWorld.ARENA_L_SLOTS:
		Runner.T.ok(slot[0] >= 16 + hc_px and slot[0] <= 624 - hc_px, "slot x %d clears the side walls" % slot[0])
		Runner.T.ok(slot[1] <= -hc_px and slot[1] >= -360 + hc_px, "slot y %d clears top/bottom" % slot[1])
		for qr in [[80, -300], [560, -300], [80, -60], [560, -60], [210, -320], [430, -50]]:
			var dx: int = slot[0] - qr[0]
			var dy: int = slot[1] - qr[1]
			Runner.T.ok(dx * dx + dy * dy >= hc_px * hc_px,
				"slot %s vs rock %s clears the hull" % [str(slot), str(qr)])
