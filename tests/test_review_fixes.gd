extends RefCounted
## Review fixes (sim): a special weapon must not silence the MG when it has nothing to hit,
## rockets must connect with a drifting hull, the flame stops at stone and wrecks (sim AND
## drawn cone), the two weapon pickups leave the lethal hue band, and the Siege Tank can never
## starve the player of the only things that hurt it.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")
const F := Fixed.ONE


func _sim(wid: int) -> SimWorld:
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.bunkers.clear()
	sim.rocks.clear()
	sim.barrels.clear()
	sim.pickups.clear()
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
		e["windup"] = 0
		e["fire_cd"] = 9999
	sim.enemies.append(e)
	return e


func _inp() -> SimInput:
	var inp := SimInput.new()
	inp.fire = true
	inp.aim_x = 0
	inp.aim_y = -256
	return inp


## One player-phase tick (no enemy AI, no spawner): the fire branch and its projectiles only.
func _fire_tick(sim: SimWorld) -> void:
	sim._step_players([_inp()])
	sim._step_bullets()
	sim._step_rockets()


# --- 1. a special never silences the MG -------------------------------------------------

func test_flame_with_only_armor_ahead_falls_through_to_the_mg() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	var nest := _foe(sim, 0, -40, "mg_nest", 3)
	var mg0: int = p["mg_ammo"]
	var fuel0: int = p["wpn_ammo"]
	for _i in 120:
		_fire_tick(sim)
	Runner.T.ok(p["mg_ammo"] < mg0, "the MG fired while the flame had nothing to cook")
	Runner.T.eq(p["wpn_ammo"], fuel0, "...and the flame magazine did not burn")
	Runner.T.ok(not nest["alive"] or nest["hp"] < 3, "the armored target took MG damage")


func test_flame_with_infantry_in_the_cone_fires_flame_not_mg() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	var foe := _foe(sim, 0, -50)
	var mg0: int = p["mg_ammo"]
	var fuel0: int = p["wpn_ammo"]
	_fire_tick(sim)
	Runner.T.ok(not foe["alive"], "the flame killed the infantry")
	Runner.T.eq(p["wpn_ammo"], fuel0 - 1, "one flame burst spent")
	Runner.T.eq(p["mg_ammo"], mg0, "the MG stayed quiet while the flame had a target")


func test_rocket_with_a_target_in_the_lane_fires_rocket_not_mg() -> void:
	var sim := _sim(Weapons.ROCKET)
	var p: Dictionary = sim.players[0]
	_foe(sim, 0, -120, "mg_nest", 3)
	var mg0: int = p["mg_ammo"]
	var rk0: int = p["wpn_ammo"]
	_fire_tick(sim)
	Runner.T.eq(p["wpn_ammo"], rk0 - 1, "one rocket spent")
	Runner.T.eq(p["mg_ammo"], mg0, "the MG stayed quiet on the rocket's trigger tick")
	Runner.T.eq(sim.rockets.size(), 1, "a rocket is in the air")


func test_rocket_with_an_empty_lane_falls_through_to_the_mg() -> void:
	var sim := _sim(Weapons.ROCKET)
	var p: Dictionary = sim.players[0]
	_foe(sim, 150, -60)   # well off the 12 px lane
	var mg0: int = p["mg_ammo"]
	var rk0: int = p["wpn_ammo"]
	_fire_tick(sim)
	Runner.T.eq(p["wpn_ammo"], rk0, "no rocket burnt on an empty lane")
	Runner.T.ok(p["mg_ammo"] < mg0, "the MG fired instead")


func test_a_special_in_hand_does_not_block_the_empty_clip_bash() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	p["mg_ammo"] = 0
	var behind := _foe(sim, 0, 10)   # at its back: outside the cone, inside bash reach
	_fire_tick(sim)
	Runner.T.ok(not behind["alive"], "dry MG + special with no target: the bash still lands")
	Runner.T.eq(sim.players[0]["wpn_ammo"], Weapons.TABLE[Weapons.FLAME]["grant"], "the flame fuel is untouched by the bash")


func test_the_special_still_wins_the_trigger_over_a_bash() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	p["mg_ammo"] = 0
	var close := _foe(sim, 0, -10)   # in the cone AND in bash reach
	var fuel0: int = p["wpn_ammo"]
	_fire_tick(sim)
	Runner.T.ok(not close["alive"], "burned")
	Runner.T.eq(p["wpn_ammo"], fuel0 - 1, "by the flame, not the free bash")


# --- 2. rockets vs a drifting hull ----------------------------------------------------------

func _gunship_duel(range_px: int, ticks: int) -> Array:
	## [rockets fired, rockets that damaged the hull, boss hp lost]
	var sim := SimWorld.new(5, 1)
	sim.enemies.clear()
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.bunkers.clear()
	sim.barrels.clear()
	var gy: int = sim.camera_top + 120 * F
	sim._stamp_gunship_gate(gy, 0, false)
	var boss: Dictionary = sim.gates[sim.gates.size() - 1]["boss"]
	boss["x"] = 200 * F
	var p: Dictionary = sim.players[0]
	p["y"] = boss_y(boss) + range_px * F
	sim._apply_supply(p, Weapons.KIND_ROCKET)
	sim.god_mode = true   # the gunship shells the player; this test measures the rocket, not survival
	var hp0: int = boss["hp"]
	var fired := 0
	for _t in ticks:
		# hold a fixed firing line and aim straight up: the hull has to drift across it
		p["x"] = 320 * F
		p["aim_x"] = 0
		p["aim_y"] = -F
		p["mg_ammo"] = 0        # only the rocket may damage the hull in this measurement
		p["alive"] = true
		if p["weapon"] != Weapons.ROCKET:
			sim._apply_supply(p, Weapons.KIND_ROCKET)
		sim.step([_inp()])
		for ev in sim.events:
			if ev["t"] == "rocket_launch":
				fired += 1
		if not boss["alive"]:
			break
	return [fired, hp0 - boss["hp"], hp0]


static func boss_y(boss: Dictionary) -> int:
	return SimWorld.boss_cy(boss)


func test_rockets_connect_with_a_drifting_gunship_at_long_range() -> void:
	var r := _gunship_duel(200, 900)
	Runner.T.ok(r[0] >= 3, "the launcher fired a salvo at 200 px (fired %d)" % r[0])
	# each connecting rocket is boss_dmg (6) hp; before the fix 0 of 10 connected at 200 px
	var hits: int = r[1] / int(Weapons.TABLE[Weapons.ROCKET]["boss_dmg"])
	Runner.T.ok(hits * 2 >= r[0], "most rockets connected (%d of %d)" % [hits, r[0]])


# --- 3. flame vs solid cover --------------------------------------------------------------------

func test_flame_is_stopped_by_stone_and_wrecks_but_not_by_slabs_or_grass() -> void:
	for kind in [0, 3]:
		var sim := _sim(Weapons.FLAME)
		var p: Dictionary = sim.players[0]
		sim.rocks.append({"x": p["x"], "y": p["y"] - 38 * F, "kind": kind})
		var behind := _foe(sim, 0, -66)
		var fuel0: int = p["wpn_ammo"]
		sim._fire_special(p, 0)
		Runner.T.ok(behind["alive"], "kind %d blocks the flame: infantry behind it lives" % kind)
		Runner.T.eq(p["wpn_ammo"], fuel0, "kind %d: no fuel burnt on a walled-off target" % kind)
		var front := _foe(sim, 0, -8)
		sim._fire_special(p, 0)
		Runner.T.ok(not front["alive"], "kind %d: infantry in front of the wall still burns" % kind)
	for kind in [1, 2]:
		var sim2 := _sim(Weapons.FLAME)
		var p2: Dictionary = sim2.players[0]
		sim2.rocks.append({"x": p2["x"], "y": p2["y"] - 30 * F, "kind": kind})
		var thru := _foe(sim2, 0, -60)
		sim2._fire_special(p2, 0)
		Runner.T.ok(not thru["alive"], "kind %d (soft cover) burns through" % kind)


func test_flame_reach_is_clipped_to_the_first_blocker() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	Runner.T.eq(sim.flame_reach(p), Weapons.TABLE[Weapons.FLAME]["reach"], "open field: full reach")
	sim.rocks.append({"x": p["x"], "y": p["y"] - 40 * F, "kind": 0})   # classic rock, 12 px half-height
	var r: int = sim.flame_reach(p)
	Runner.T.ok(r > 20 * F and r < 40 * F, "reach stops at the rock's near face (got %.1f px)" % (float(r) / F))
	# an off-axis rock does not shorten it
	var sim2 := _sim(Weapons.FLAME)
	sim2.rocks.append({"x": sim2.players[0]["x"] + 60 * F, "y": sim2.players[0]["y"] - 40 * F, "kind": 0})
	Runner.T.eq(sim2.flame_reach(sim2.players[0]), Weapons.TABLE[Weapons.FLAME]["reach"], "a rock off the aim line leaves the reach alone")


func test_drawn_flame_cone_clips_where_the_sim_does() -> void:
	var sim := _sim(Weapons.FLAME)
	var p: Dictionary = sim.players[0]
	sim.rocks.append({"x": p["x"], "y": p["y"] - 40 * F, "kind": 3})
	var reach_px: float = float(sim.flame_reach(p)) / F
	var poly := WeaponFx.flame_cone(Vector2.ZERO, Vector2(0, -1), reach_px)
	var far := 0.0
	for v in poly:
		far = maxf(far, -v.y)
	var wt: Dictionary = Weapons.TABLE[Weapons.FLAME]
	Runner.T.ok(absf(far - (reach_px + float(wt["pad"]) / F)) < 0.01, "the drawn cone ends at the clipped reach + pad (%.2f)" % far)
	Runner.T.ok(far < float(wt["reach"]) / F, "...which is shorter than the open-field cone")


# --- 4. pickup colours leave the lethal band -----------------------------------------------------

static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _in_lethal_band(c: Color) -> bool:
	## Saturated red / orange / amber: the family bullets, mines and role rims own.
	var h := c.h * 360.0
	return c.s > 0.45 and (h >= 345.0 or h <= 50.0)


func test_weapon_pickup_colours_are_off_the_lethal_band_and_far_apart() -> void:
	var caps: Array = Main._CAPSULE_COL
	var flame: Color = caps[8]
	var rocket: Color = caps[9]
	Runner.T.ok(not _in_lethal_band(flame), "flame capsule is out of the red/amber band")
	Runner.T.ok(not _in_lethal_band(rocket), "rocket capsule is out of the red/amber band")
	var dh := absf(flame.h - rocket.h) * 360.0
	dh = minf(dh, 360.0 - dh)
	Runner.T.ok(dh >= 60.0, "hue gap >= 60 degrees (got %.0f)" % dh)
	Runner.T.ok(absf(_lum(flame) - _lum(rocket)) >= 0.25, "luminance gap >= 0.25 (got %.2f)" % absf(_lum(flame) - _lum(rocket)))


func test_weapon_chips_match_the_capsule_colours() -> void:
	var caps: Array = Main._CAPSULE_COL
	for wid in [Weapons.FLAME, Weapons.ROCKET]:
		var sim := _sim(wid)
		var chips: Array = HudScript_chip_specs(sim, sim.players[0])
		var found := false
		for c in chips:
			if c.get("icon", "") in ["icon_flame", "icon_rocket"]:
				found = true
				var want: Color = caps[8] if wid == Weapons.FLAME else caps[9]
				Runner.T.ok(c["col"].is_equal_approx(want), "chip colour for weapon %d is its capsule colour" % wid)
				Runner.T.ok(not _in_lethal_band(c["col"]), "chip for weapon %d is off the lethal band" % wid)
		Runner.T.ok(found, "weapon %d has a buff chip" % wid)


func HudScript_chip_specs(sim: SimWorld, p: Dictionary) -> Array:
	var h := HudIcons.new()
	var chips: Array = h._buff_chip_specs(p)
	h.free()
	return chips


# --- 5. the Siege Tank cannot starve the player -------------------------------------------------

func _siege_arena() -> Array:
	var sim := SimWorld.new(41, 1)
	sim.enemies.clear()
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.pickups.clear()
	var gy: int = sim.camera_top + 100 * F
	sim._stamp_gunship_gate(gy, 0, false, "siege")
	sim.pickups.clear()
	sim.pickups.append({"x": 120 * F, "y": gy + 160 * F, "kind": 1, "cost": 0})
	var boss: Dictionary = sim.gates[sim.gates.size() - 1]["boss"]
	var p: Dictionary = sim.players[0]
	p["x"] = 320 * F
	p["y"] = gy + 210 * F
	return [sim, boss]


func _grenade_crates(sim: SimWorld) -> int:
	var n := 0
	for pk in sim.pickups:
		if pk["kind"] == 1 and int(pk.get("cost", 0)) == 0:
			n += 1
	return n


func test_siege_grenade_crate_rearms_when_nobody_holds_a_grenade() -> void:
	var a := _siege_arena()
	var sim: SimWorld = a[0]
	var p: Dictionary = sim.players[0]
	p["grenade_ammo"] = 0
	sim.pickups.clear()   # the player already used the crate
	Runner.T.eq(_grenade_crates(sim), 0, "setup: no crate")
	var back := -1
	for t in SiegeBoss.RESUPPLY_TICKS + 30:
		SiegeBoss.step(sim, a[1])
		if back < 0 and _grenade_crates(sim) >= 1:
			back = t + 1
	Runner.T.eq(back, SiegeBoss.RESUPPLY_TICKS, "the crate re-armed exactly RESUPPLY_TICKS after the last grenade was gone")
	Runner.T.eq(sim.pickups[0]["x"], SiegeBoss.CRATE_POS[0] * F, "...at its home spot")


func test_siege_grenade_crate_does_not_rearm_while_a_grenade_is_held() -> void:
	var a := _siege_arena()
	var sim: SimWorld = a[0]
	var p: Dictionary = sim.players[0]
	p["grenade_ammo"] = 1
	sim.pickups.clear()
	for _t in SiegeBoss.RESUPPLY_TICKS * 3:
		SiegeBoss.step(sim, a[1])
	Runner.T.eq(_grenade_crates(sim), 0, "a player holding a grenade gets no free crate")


func test_siege_crate_is_not_duplicated_and_is_taken_from_a_rocket_holder() -> void:
	var a := _siege_arena()
	var sim: SimWorld = a[0]
	var p: Dictionary = sim.players[0]
	p["grenade_ammo"] = 0
	for _t in SiegeBoss.RESUPPLY_TICKS * 3:
		SiegeBoss.step(sim, a[1])
	Runner.T.eq(_grenade_crates(sim), 1, "one crate stays one crate (no stacking)")
	# a rocket launcher with ammo counts as a way to hurt the hull
	var b := _siege_arena()
	var sim2: SimWorld = b[0]
	var p2: Dictionary = sim2.players[0]
	p2["grenade_ammo"] = 0
	sim2._apply_supply(p2, Weapons.KIND_ROCKET)
	sim2.pickups.clear()
	for _t in SiegeBoss.RESUPPLY_TICKS * 3:
		SiegeBoss.step(sim2, b[1])
	Runner.T.eq(_grenade_crates(sim2), 0, "a loaded launcher is not starved")


func test_siege_resupply_countdown_is_in_the_checksum() -> void:
	var a := _siege_arena()
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	var before: int = sim.checksum()
	boss["sc"] = 17
	Runner.T.ok(sim.checksum() != before, "the resupply countdown is hashed")
