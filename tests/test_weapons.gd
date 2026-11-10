extends RefCounted
## Special weapons: flamethrower (close cone, kills infantry, burns cover, shrugged off by
## armor) and rocket launcher (slow, travelling, small splash that DOES hurt armor).

const Runner := preload("res://tests/run_tests.gd")
const F := Fixed.ONE


func _sim(wid: int) -> SimWorld:
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.bunkers.clear()
	sim.rocks.clear()
	sim.barrels.clear()
	var p: Dictionary = sim.players[0]
	p["x"] = 320 * F
	p["y"] = sim.camera_top + 250 * F
	p["aim_x"] = 0
	p["aim_y"] = -F
	if wid != Weapons.NONE:
		sim._apply_supply(p, Weapons.TABLE[wid]["kind"])
	return sim


func _foe(sim: SimWorld, dx_px: int, dy_px: int, kind := "rusher", hp := 0) -> Dictionary:
	var p: Dictionary = sim.players[0]
	var e := {"x": p["x"] + dx_px * F, "y": p["y"] + dy_px * F, "alive": true, "elite": false, "kind": kind}
	if hp > 0:
		e["hp"] = hp
	sim.enemies.append(e)
	return e


func _tick(sim: SimWorld, n := 1) -> void:
	var inp := SimInput.new()
	inp.fire = true
	inp.aim_x = 0
	inp.aim_y = -256
	for _i in n:
		sim.step([inp])


# --- flamethrower ------------------------------------------------------------------------

func test_flame_cone_reach_and_width() -> void:
	var sim := _sim(Weapons.FLAME)
	var near := _foe(sim, 0, -60)        # straight ahead, inside 70 px
	var far := _foe(sim, 0, -90)         # past the reach
	var wide := _foe(sim, 60, -40)       # ~56 deg off axis: outside the 25 deg half-angle
	sim._fire_special(sim.players[0], 0)
	Runner.T.ok(not near["alive"], "infantry 60 px ahead burns")
	Runner.T.ok(far["alive"], "infantry at 90 px is out of the 70 px reach")
	Runner.T.ok(wide["alive"], "infantry 56 degrees off the aim is outside the cone")


func test_flame_does_not_spend_fuel_on_an_empty_field() -> void:
	var sim := _sim(Weapons.FLAME)
	var before: int = sim.players[0]["wpn_ammo"]
	_foe(sim, 0, -120)
	sim._fire_special(sim.players[0], 0)
	Runner.T.eq(sim.players[0]["wpn_ammo"], before, "nothing in the cone: no fuel burnt")
	Runner.T.eq(sim.players[0]["fire_cd"], 0, "...and no cooldown spent")


func test_flame_is_useless_against_inherent_armor() -> void:
	var sim := _sim(Weapons.FLAME)
	var nest := _foe(sim, 0, -40, "mg_nest", 3)
	var before: int = sim.players[0]["wpn_ammo"]
	sim._fire_special(sim.players[0], 0)
	Runner.T.eq(sim.players[0]["wpn_ammo"], before, "a lone nest in the cone does not even trigger the flame")
	sim._flame_burst(sim.players[0], 0)
	Runner.T.ok(nest["alive"] and nest["hp"] == 3, "a forced burst leaves the nest at full hp")
	var tech := _foe(sim, 0, -30, "technical", 3)
	sim._flame_burst(sim.players[0], 0)
	Runner.T.eq(tech["hp"], 3, "technicals shrug fire too")


func test_flame_strips_veteran_armor_one_point_a_burst() -> void:
	var sim := _sim(Weapons.FLAME)
	var vet := _foe(sim, 0, -30, "rusher", 2)
	sim._flame_burst(sim.players[0], 0)
	Runner.T.ok(vet["alive"] and vet["hp"] == 1, "veteran bulk loses a point, survives the first burst")
	sim._flame_burst(sim.players[0], 0)
	Runner.T.ok(not vet["alive"], "and dies to the second")


func test_flame_burns_cover_and_reaches_infantry_behind_it() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	sim.sandbags.append({"x": p["x"], "y": p["y"] - 30 * F})
	var hugger := _foe(sim, 0, -38)      # pressed against the far face of the bag
	sim._fire_special(p, 0)
	Runner.T.ok(not hugger["alive"], "the cone is not stopped by the sandbag: the hugger burns")
	Runner.T.eq(sim.sandbags.size(), 1, "one burst does not burn the bag through")
	var need: int = Weapons.TABLE[Weapons.FLAME]["cover_hits"]
	for _i in need - 1:
		sim._flame_burst(p, 0)
	Runner.T.eq(sim.sandbags.size(), 0, "after %d bursts the sandbag is gone" % need)


func test_flame_costs_fuel_and_hands_back_the_mg_when_dry() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	var fuel: int = p["wpn_ammo"]
	_foe(sim, 0, -30)
	sim._fire_special(p, 0)
	Runner.T.eq(p["wpn_ammo"], fuel - 1, "a burst costs one fuel")
	Runner.T.eq(p["fire_cd"], Weapons.TABLE[Weapons.FLAME]["cd"], "and sets the flame cooldown")
	p["fire_cd"] = 0
	p["wpn_ammo"] = 1
	_foe(sim, 0, -30)
	sim._fire_special(p, 0)
	Runner.T.eq(p["weapon"], Weapons.NONE, "the last fuel gives the MG back")


func test_flame_burns_faster_than_the_mg_spends() -> void:
	var f: Dictionary = Weapons.TABLE[Weapons.FLAME]
	Runner.T.ok(f["cd"] < SimWorld.FIRE_COOLDOWN_TICKS, "flame fires faster than the MG")
	Runner.T.ok(f["grant"] * f["cd"] <= 60 * 7, "a full grant is at most ~7 s of continuous flame")


# --- rocket launcher ---------------------------------------------------------------------

func test_rocket_is_slow_and_travels_in_view() -> void:
	var sim := _sim(Weapons.ROCKET)
	_foe(sim, 0, -200)
	_tick(sim)
	Runner.T.eq(sim.rockets.size(), 1, "a target in the lane launches a rocket")
	var y0: int = sim.rockets[0]["y"]
	_tick(sim)
	Runner.T.eq(y0 - sim.rockets[0]["y"], Weapons.TABLE[Weapons.ROCKET]["speed"], "it advances the table speed (4 px) a tick")
	Runner.T.ok(Weapons.TABLE[Weapons.ROCKET]["speed"] < SimWorld.BULLET_SPEED, "slower than an MG round")
	Runner.T.ok(Weapons.TABLE[Weapons.ROCKET]["cd"] >= 4 * SimWorld.FIRE_COOLDOWN_TICKS, "fires at least 4x slower than the MG")


func test_rocket_needs_a_target_in_the_lane() -> void:
	var sim := _sim(Weapons.ROCKET)
	_foe(sim, 80, -100)     # well off the aim line
	_tick(sim)
	Runner.T.ok(sim.rockets.is_empty(), "no rocket for a target off the lane")
	Runner.T.eq(sim.players[0]["wpn_ammo"], Weapons.TABLE[Weapons.ROCKET]["grant"], "no ammo spent")


func test_rocket_blast_radius_is_the_table_radius() -> void:
	var sim := _sim(Weapons.ROCKET)
	var r: int = Weapons.TABLE[Weapons.ROCKET]["blast"]
	var inside := _foe(sim, 0, -100)
	inside["x"] = sim.players[0]["x"] + r - F
	var outside := _foe(sim, 0, -100)
	outside["x"] = sim.players[0]["x"] + r + 3 * F
	sim._rocket_blast(sim.players[0]["x"], sim.players[0]["y"] - 100 * F)
	Runner.T.ok(not inside["alive"], "a body just inside the blast ring dies")
	Runner.T.ok(outside["alive"], "a body just outside the ring lives")


func test_rocket_damages_armor_where_the_mg_cannot() -> void:
	var sim := _sim(Weapons.ROCKET)
	var nest := _foe(sim, 0, -150, "broadcast", 5)
	nest["windup"] = 0
	nest["fire_cd"] = 999
	_tick(sim, 1)
	var guard := 0
	while not sim.rockets.is_empty() and guard < 200:
		sim.step([SimInput.new()])
		guard += 1
	Runner.T.ok(nest["alive"] and nest["hp"] == 5 - Weapons.TABLE[Weapons.ROCKET]["armor_dmg"],
		"one rocket strips armor_dmg from the mast (hp now %d)" % nest["hp"])
	Runner.T.ok(sim.rockets.is_empty(), "the rocket detonated")


func test_one_rocket_kills_a_nest_and_a_technical() -> void:
	var sim := _sim(Weapons.ROCKET)
	var nest := _foe(sim, 0, -100, "mg_nest", 3)
	var truck := _foe(sim, 12, -100, "technical", 3)
	sim._rocket_blast(sim.players[0]["x"] + 6 * F, sim.players[0]["y"] - 100 * F)
	Runner.T.ok(not nest["alive"] and not truck["alive"], "a single rocket kills hp-3 armor (the MG needs 3 rounds)")


func test_rocket_blows_a_bunker_and_hurts_a_boss() -> void:
	var sim := _sim(Weapons.ROCKET)
	sim.bunkers.append({"x": 320 * F - 24 * F, "y": sim.players[0]["y"] - 120 * F, "alive": true})
	sim._rocket_blast(320 * F, sim.players[0]["y"] - 110 * F)
	Runner.T.ok(not sim.bunkers[0]["alive"], "a rocket opens a bunker")
	var boss := {"alive": true, "hp": 50, "x": 320 * F, "gate_y": sim.players[0]["y"] - 200 * F + SimWorld.BOSS_Y_OFFSET,
		"phase_t": 0, "dir": 1}
	sim.gates.append({"y": boss["gate_y"], "open": false, "boss": boss})
	sim._rocket_blast(320 * F, boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
	Runner.T.eq(boss["hp"], 50 - Weapons.TABLE[Weapons.ROCKET]["boss_dmg"], "boss takes the rocket's boss_dmg")


func test_rocket_never_hurts_the_shooter() -> void:
	var sim := _sim(Weapons.ROCKET)
	var p: Dictionary = sim.players[0]
	sim._rocket_blast(p["x"], p["y"])
	Runner.T.ok(p["alive"], "a blast on top of the shooter does not kill him (grenade rule)")


# --- shared rules -------------------------------------------------------------------------

func test_special_replaces_mg_fire_and_mods_go_dormant() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	p["triple"] = true
	p["pierce_ticks"] = 300
	_foe(sim, 0, -30)
	_tick(sim)
	Runner.T.ok(sim.bullets.is_empty(), "no MG round while the flamethrower is in hand")
	Runner.T.eq(p["mg_ammo"], SimWorld.MG_AMMO_MAX, "MG ammo untouched")
	Runner.T.ok(p["triple"] and p["pierce_ticks"] > 0, "MG mods keep their state (dormant, not stripped)")


func test_weapon_is_held_until_death() -> void:
	var sim := _sim(Weapons.ROCKET)
	var p: Dictionary = sim.players[0]
	Runner.T.eq(p["weapon"], Weapons.ROCKET, "pickup arms the launcher")
	sim._respawn(p, p["y"], 0)
	Runner.T.eq(p["weapon"], Weapons.NONE, "death hands the MG back")


func test_pickup_swaps_and_same_pickup_refills() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	p["wpn_ammo"] = 5
	sim._apply_supply(p, Weapons.KIND_FLAME)
	Runner.T.eq(p["wpn_ammo"], 5 + Weapons.TABLE[Weapons.FLAME]["grant"], "same weapon tops up")
	sim._apply_supply(p, Weapons.KIND_ROCKET)
	Runner.T.eq(p["weapon"], Weapons.ROCKET, "the other pickup replaces it")
	Runner.T.eq(p["wpn_ammo"], Weapons.TABLE[Weapons.ROCKET]["grant"], "with its own full grant")
	p["wpn_ammo"] = Weapons.TABLE[Weapons.ROCKET]["cap"]
	Runner.T.ok(sim._supply_full(p, Weapons.KIND_ROCKET), "a full launcher reports full (no billing for a no-op)")


func test_capsule_pool_gates_weapons_by_sector() -> void:
	var seen := {}
	for sector in 3:
		var sim := SimWorld.new(11 + sector, 1)
		# Advance the gate count so _sector_index reports `sector`.
		sim._gate_counter = sector + 1
		var kinds := {}
		for _n in 400:
			kinds[sim._pick_rare_kind()] = true
		seen[sector] = kinds
	Runner.T.ok(not seen[0].has(Weapons.KIND_FLAME) and not seen[0].has(Weapons.KIND_ROCKET), "sector 1 drops neither weapon")
	Runner.T.ok(seen[1].has(Weapons.KIND_FLAME) and not seen[1].has(Weapons.KIND_ROCKET), "sector 2 adds the flamethrower")
	Runner.T.ok(seen[2].has(Weapons.KIND_FLAME) and seen[2].has(Weapons.KIND_ROCKET), "sector 3 adds the rocket launcher")


func test_endless_shop_pool_sells_both_at_table_prices() -> void:
	var i_f := SimWorld.CRATE_POOL.find(Weapons.KIND_FLAME)
	var i_r := SimWorld.CRATE_POOL.find(Weapons.KIND_ROCKET)
	Runner.T.ok(i_f >= 0 and i_r >= 0, "both weapons are in the Endless crate pool")
	Runner.T.eq(SimWorld.CRATE_POOL_BASE[i_f], Weapons.TABLE[Weapons.FLAME]["shop"], "flame crate price = table")
	Runner.T.eq(SimWorld.CRATE_POOL_BASE[i_r], Weapons.TABLE[Weapons.ROCKET]["shop"], "rocket crate price = table")


func test_every_new_gameplay_field_is_in_the_checksum() -> void:
	var base := _sim(Weapons.NONE).checksum()
	Runner.T.eq(_sim(Weapons.NONE).checksum(), base, "baseline is stable")
	Runner.T.ok(_sim(Weapons.FLAME).checksum() != base, "holding a weapon changes the hash")
	var a := _sim(Weapons.FLAME)
	var b := _sim(Weapons.FLAME)
	b.players[0]["wpn_ammo"] -= 1
	Runner.T.ok(a.checksum() != b.checksum(), "wpn_ammo is hashed")
	var c := _sim(Weapons.NONE)
	c.rockets.append({"x": 5 * F, "y": 5 * F, "vx": 0, "vy": -F, "ttl": 10, "owner": 0})
	Runner.T.ok(c.checksum() != base, "a rocket in flight is hashed")
	var d := _sim(Weapons.NONE)
	d.rockets.append({"x": 5 * F, "y": 5 * F, "vx": 0, "vy": -F, "ttl": 9, "owner": 0})
	Runner.T.ok(c.checksum() != d.checksum(), "rocket ttl is hashed")
	var e := _sim(Weapons.NONE)
	e.sandbags.append({"x": 5 * F, "y": 5 * F})
	var g := _sim(Weapons.NONE)
	g.sandbags.append({"x": 5 * F, "y": 5 * F, "scorch": 3})
	Runner.T.ok(e.checksum() != g.checksum(), "sandbag scorch is hashed")


func test_two_runs_with_a_weapon_stay_bit_identical() -> void:
	var a := _sim(Weapons.FLAME)
	var b := _sim(Weapons.FLAME)
	for s in [a, b]:
		_foe(s, 0, -30)
		_foe(s, 5, -50)
		_tick(s, 40)
	Runner.T.eq(a.checksum(), b.checksum(), "same inputs, same hash")


# --- time-to-kill table (shared with tools/probe_weapons.gd, so the two cannot disagree) ----

const SCENARIOS := ["lone rusher @50", "lone rusher @200", "pack of 5 @50", "mg_nest hp3 @100", "broadcast hp5 @100", "bunker @100"]


func ttk(wid: int, scenario: String) -> Array:
	## [ticks until every target in the scenario is dead, ammo spent]; ticks = -1 if it never dies
	## within 600. Enemies are held still (only the player, bullet and rocket steppers run) so the
	## number is the weapon's, not the AI's.
	var sim := _sim(wid)
	var p: Dictionary = sim.players[0]
	var targets: Array = []
	var nest_like := func(kind: String, hp: int, dy: int) -> Dictionary:
		var e := _foe(sim, 0, dy, kind, hp)
		e["windup"] = 0
		e["fire_cd"] = 999
		return e
	match scenario:
		"lone rusher @200":
			targets.append(_foe(sim, 0, -200))
		"lone rusher @50":
			targets.append(_foe(sim, 0, -50))
		"pack of 5 @50":
			for k in 5:
				targets.append(_foe(sim, (k % 3 - 1) * 3, -50 - k * 4))
		"mg_nest hp3 @100":
			targets.append(nest_like.call("mg_nest", 3, -100))
		"broadcast hp5 @100":
			targets.append(nest_like.call("broadcast", 5, -100))
		"bunker @100":
			var bk := {"x": p["x"] - 24 * F, "y": p["y"] - 124 * F, "alive": true}
			sim.bunkers.append(bk)
			targets.append(bk)
	var inp := SimInput.new()
	inp.fire = true
	inp.aim_x = 0
	inp.aim_y = -256
	var ammo0: int = p["mg_ammo"] if wid == Weapons.NONE else p["wpn_ammo"]
	for t in 600:
		sim._step_players([inp])
		sim._step_bullets()
		sim._step_rockets()
		var all_dead := true
		for e in targets:
			if e["alive"]:
				all_dead = false
		if all_dead:
			var spent: int = ammo0 - (p["mg_ammo"] if wid == Weapons.NONE else p["wpn_ammo"])
			return [t + 1, spent]
	return [-1, ammo0 - (p["mg_ammo"] if wid == Weapons.NONE else p["wpn_ammo"])]


func test_neither_special_dominates_the_mg() -> void:
	var table := {}
	for wid in [Weapons.NONE, Weapons.FLAME, Weapons.ROCKET]:
		for sc in SCENARIOS:
			table[[wid, sc]] = ttk(wid, sc)[0]
	# Flame: best on a close pack, useless on armor (never kills the heavies), beaten by the MG at range.
	Runner.T.ok(table[[Weapons.FLAME, "pack of 5 @50"]] > 0 and table[[Weapons.FLAME, "pack of 5 @50"]] < table[[Weapons.NONE, "pack of 5 @50"]], "flame clears a close pack faster than the MG")
	Runner.T.eq(table[[Weapons.FLAME, "mg_nest hp3 @100"]], -1, "flame cannot touch a nest")
	Runner.T.eq(table[[Weapons.FLAME, "bunker @100"]], -1, "flame cannot open a bunker")
	# Rocket: the only non-grenade answer to a bunker; clears the pack; but loses to the MG on a lone grunt.
	Runner.T.eq(table[[Weapons.NONE, "bunker @100"]], -1, "the MG cannot open a bunker")
	Runner.T.ok(table[[Weapons.ROCKET, "bunker @100"]] > 0, "the rocket opens a bunker")
	Runner.T.ok(table[[Weapons.ROCKET, "pack of 5 @50"]] > 0, "the rocket's splash clears a tight pack")
	Runner.T.ok(table[[Weapons.ROCKET, "lone rusher @50"]] > table[[Weapons.NONE, "lone rusher @50"]], "...but a lone grunt is the MG's to kill: the rocket is slower to arrive")
	Runner.T.ok(table[[Weapons.ROCKET, "mg_nest hp3 @100"]] > 0, "the rocket kills a nest")


# --- view honesty: what is drawn is what the sim hit-tests ---------------------------------

func test_drawn_flame_cone_is_the_sims_cone() -> void:
	var wt: Dictionary = Weapons.TABLE[Weapons.FLAME]
	var aims := [Vector2(0, -1), Vector2(1, 0), Vector2(0.6, -0.8), Vector2(-0.8, 0.6)]
	var mismatches := 0
	var inside := 0
	for aim in aims:
		var poly := WeaponFx.flame_cone(Vector2.ZERO, aim)
		var ax := int(aim.x * F)
		var ay := int(aim.y * F)
		for gx in range(-100, 101, 2):
			for gy in range(-100, 101, 2):
				var sim_says := Weapons.in_cone(gx * F, gy * F, ax, ay, wt["reach"], wt["tan"], wt["pad"])
				var drawn := Geometry2D.is_point_in_polygon(Vector2(gx, gy), poly)
				if sim_says:
					inside += 1
				# Skip the 1 px band at the boundary: fixed-point truncation vs float edges.
				if sim_says != drawn and not _near_edge(Vector2(gx, gy), poly):
					mismatches += 1
	Runner.T.ok(inside > 400, "the sweep actually exercised the cone (%d inside samples)" % inside)
	Runner.T.eq(mismatches, 0, "no grid point disagrees between the drawn cone and Weapons.in_cone")


func _near_edge(pt: Vector2, poly: PackedVector2Array) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
		if closest.distance_to(pt) <= 1.0:
			return true
	return false


func test_drawn_cone_reach_matches_table_and_blast_ring_matches_splash() -> void:
	var poly := WeaponFx.flame_cone(Vector2.ZERO, Vector2(0, -1))
	var top := 0.0
	for v in poly:
		top = minf(top, v.y)
	var wt: Dictionary = Weapons.TABLE[Weapons.FLAME]
	Runner.T.ok(absf(-top - (float(wt["reach"] + wt["pad"]) / F)) < 0.01, "cone tip sits at reach + body pad (%.1f px)" % -top)
	Runner.T.ok(absf(WeaponFx.blast_radius_px() - 22.0) < 0.001, "rocket ring = the 22 px splash")
	var fx: Array = []
	WeaponFx.on_event({"t": "explosion", "x": 0, "y": 0, "src": "rocket"}, fx)
	Runner.T.eq(fx.size(), 1, "a rocket blast queues exactly one ring")
	Runner.T.ok(absf(fx[0]["sz"] - 22.0) < 0.001 and fx[0]["grow_px"] == 0.0, "the ring is born AT the splash radius and does not grow past it")
	var fx2: Array = []
	WeaponFx.on_event({"t": "explosion", "x": 0, "y": 0, "src": "airburst"}, fx2)
	Runner.T.ok(fx2.is_empty(), "a grenade burst does not get the rocket ring")
