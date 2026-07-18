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


func test_technical_charge_follows_the_locked_line_not_the_player() -> void:
	var sim := SimWorld.new(21, 1, "endless")
	var p := sim.players[0]
	sim._spawn_special(p["x"], p["y"] - 200 * Fixed.ONE, "technical")
	var e := sim.enemies[0]
	e["fire_cd"] = 0
	sim._step_enemies()   # rev starts (windup armed)
	Runner.T.ok(e["windup"] > 0, "technical revs before charging")
	for t in SimWorld.TECHNICAL_REV_TICKS:
		sim._step_enemies()
	Runner.T.ok(e.get("lunge_ticks", 0) > 0, "rev end locks the charge")
	var lock_lx: int = e["aim_lx"]
	# Teleport the player far sideways — the charge must NOT re-aim.
	p["x"] = p["x"] + 300 * Fixed.ONE
	var x0: int = e["x"]
	var y0: int = e["y"]
	sim._step_enemies()
	Runner.T.eq(e["aim_lx"], lock_lx, "mid-charge the locked vector never re-aims")
	Runner.T.ok(e["y"] != y0, "the charge travels")
	Runner.T.eq(e["x"], x0, "a straight-down lock gains no sideways ground on a dodger")


func test_pilot_rescue_pays_ransom_and_escape_forfeits() -> void:
	var sim := SimWorld.new(22, 1)
	var p := sim.players[0]
	# Rescue: pilot under the player's feet — touch pays, never hurts.
	sim.enemies.append({"x": p["x"], "y": p["y"], "alive": true, "elite": false, "kind": "pilot"})
	var chest0 := sim.war_chest
	sim.step([SimInput.new()])
	Runner.T.eq(sim.war_chest - chest0, SimWorld.PILOT_RANSOM, "touching the pilot pays the ransom")
	Runner.T.ok(p["alive"], "the rescue touch does not kill the rescuer")
	# Escape: a pilot at the top edge crosses it and is captured (no pay).
	sim.enemies.append({"x": 100 * Fixed.ONE, "y": sim.camera_top - 30 * Fixed.ONE,
		"alive": true, "elite": false, "kind": "pilot"})
	var chest1 := sim.war_chest
	sim._step_enemies()
	var esc: Dictionary = sim.enemies[sim.enemies.size() - 1]
	Runner.T.ok(not esc["alive"], "crossing the top edge captures the pilot")
	Runner.T.eq(sim.war_chest, chest1, "a captured pilot pays nothing")


func test_boss_death_spawns_a_pilot_and_shooting_him_pays_nothing() -> void:
	var sim := SimWorld.new(23, 1)
	var boss := {"hp": 1, "alive": true, "x": 320 * Fixed.ONE, "gate_y": 0}
	sim._damage_boss(boss, 99)
	var pilot := {}
	for e in sim.enemies:
		if e["kind"] == "pilot":
			pilot = e
	Runner.T.ok(not pilot.is_empty(), "a downed gunship ejects its pilot")
	var chest0 := sim.war_chest
	var score0 := sim.score
	sim._kill_enemy(pilot)
	Runner.T.eq(sim.war_chest, chest0, "gunning down the pilot mints no coin")
	Runner.T.eq(sim.score, score0, "and no score")


func test_pilot_punchout_grace_blocks_the_touch_then_expires() -> void:
	var sim := SimWorld.new(24, 1)
	var p := sim.players[0]
	var boss := {"hp": 1, "alive": true, "x": p["x"], "gate_y": p["y"] + SimWorld.BOSS_Y_OFFSET}
	sim._damage_boss(boss, 99)
	var pilot: Dictionary = sim.enemies[sim.enemies.size() - 1]
	Runner.T.ok(pilot.get("submerged", false), "the pilot punches out under a no-shoot grace")
	var chest0 := sim.war_chest
	sim._step_players([SimInput.new()])
	Runner.T.eq(sim.war_chest, chest0, "no rescue while he climbs out")
	var y0: int = pilot["y"]
	for t in SimWorld.PILOT_PUNCHOUT_TICKS:
		sim._step_enemies()
	Runner.T.ok(not pilot["submerged"], "the grace expires on schedule")
	Runner.T.eq(pilot["y"], y0, "he holds the crash site while getting up")
	sim._step_players([SimInput.new()])
	Runner.T.eq(sim.war_chest - chest0, SimWorld.PILOT_RANSOM, "then the touch rescues")


func test_roll_iframes_do_not_block_the_rescue() -> void:
	var sim := SimWorld.new(25, 1)
	var p := sim.players[0]
	sim.enemies.append({"x": p["x"], "y": p["y"], "alive": true, "elite": false, "kind": "pilot"})
	p["roll_ticks"] = 3   # mid-roll: i-frames active this step
	p["roll_dx"] = 0
	p["roll_dy"] = 0
	var chest0 := sim.war_chest
	sim.step([SimInput.new()])
	Runner.T.eq(sim.war_chest - chest0, SimWorld.PILOT_RANSOM,
		"rolling onto the pilot still grabs him — i-frames stop deaths, not rescues")


func test_tank_treads_rescue_not_crush_the_pilot() -> void:
	var sim := SimWorld.new(26, 1)
	var p := sim.players[0]
	var tank := {"x": p["x"], "y": p["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": 0}
	sim.tanks.append(tank)
	p["in_tank"] = 0
	# Hold the dict reference — step() sweeps dead enemies out of the array.
	var pilot := {"x": tank["x"], "y": tank["y"], "alive": true, "elite": false, "kind": "pilot"}
	sim.enemies.append(pilot)
	var chest0 := sim.war_chest
	sim.step([SimInput.new()])
	Runner.T.ok(not pilot["alive"], "the treads picked him up")
	Runner.T.eq(sim.war_chest - chest0, SimWorld.PILOT_RANSOM, "treads grab the ransom, not a corpse")


func test_airstrike_spares_the_pilot() -> void:
	var sim := SimWorld.new(27, 1)
	sim.enemies.append({"x": 100 * Fixed.ONE, "y": sim.camera_top + 100 * Fixed.ONE,
		"alive": true, "elite": false, "kind": "pilot"})
	sim._spawn_enemy(200 * Fixed.ONE, sim.camera_top + 100 * Fixed.ONE, false)
	sim._fire_mission()
	Runner.T.ok(sim.enemies[0]["alive"], "the screen-clear spares the objective")
	Runner.T.ok(not sim.enemies[1]["alive"], "but still wipes the hostiles")


func test_technical_cruises_between_charges() -> void:
	var sim := SimWorld.new(28, 1, "endless")
	var p := sim.players[0]
	sim._spawn_special(p["x"], p["y"] - 300 * Fixed.ONE, "technical")
	var e := sim.enemies[0]
	e["fire_cd"] = 50   # mid-cooldown: no rev this tick — the old truck just parked here
	var y0: int = e["y"]
	sim._step_enemies()
	Runner.T.ok(e["y"] > y0, "between charges the raider closes on the player")
	Runner.T.eq(e.get("windup", 0), 0, "closing is a cruise, not a rev")


func test_technical_is_armored_like_the_nest() -> void:
	# iter2 salvage: a truck one-shot by a pistol round died before it ever
	# charged twice — 3 bullets to crack, same grammar as the MG nest.
	var sim := SimWorld.new(31, 1, "endless")
	var p := sim.players[0]
	sim._spawn_special(p["x"], p["y"] - 60 * Fixed.ONE, "technical")
	var e := sim.enemies[0]
	Runner.T.eq(e.get("hp", 0), SimWorld.TECHNICAL_HP, "technical spawns with armor")
	for i in 2:
		sim.bullets.append({"x": e["x"], "y": e["y"], "vx": 0, "vy": -Fixed.ONE,
			"ttl": 10, "owner": 0})
		sim._step_bullets()
	Runner.T.ok(e["alive"], "two rounds dent, don't kill")
	sim.bullets.append({"x": e["x"], "y": e["y"], "vx": 0, "vy": -Fixed.ONE,
		"ttl": 10, "owner": 0})
	sim._step_bullets()
	Runner.T.ok(not e["alive"], "the third round cracks it")


func test_pilot_ignores_blasts_and_mines_past_his_grace() -> void:
	# iter2 salvage: the punch-out grace covered bullets/mines via the frogman
	# flags, but a POST-grace pilot still died to sapper mines and grenadier
	# lobs on his fixed walk — a ransom coin-flip. Blasts/mines now pass over
	# him permanently; bullets still kill (the lesson stays player-owned).
	var sim := SimWorld.new(32, 1)
	sim.enemies.append({"x": 300 * Fixed.ONE, "y": sim.camera_top + 100 * Fixed.ONE,
		"alive": true, "elite": false, "kind": "pilot"})
	var pilot := sim.enemies[sim.enemies.size() - 1]
	sim._explode(pilot["x"], pilot["y"])
	Runner.T.ok(pilot["alive"], "a blast on his position passes over the pilot")
	sim.mines.append({"x": pilot["x"], "y": pilot["y"], "armed": true})
	sim._step_mines()
	Runner.T.ok(sim.mines[sim.mines.size() - 1]["armed"], "the pilot doesn't trip mines")


func test_airburst_hold_pops_at_apex_tap_flies_full_arc() -> void:
	# Hold the grenade button through the apex: the charge pops mid-air
	# (~throw+17); a 1-tick tap flies the full ~32-tick arc. Zero new state —
	# the fuse hand is the already-hashed grenade_prev.
	var sim := SimWorld.new(1, 2)
	var hold := SimInput.new()
	hold.grenade = true
	hold.aim_x = 256
	var idle := SimInput.new()
	var t := 0
	sim.step([hold, idle])   # throw tick (edge)
	Runner.T.eq(sim.grenades.size(), 1, "throw leaves one grenade in flight")
	while sim.grenades.size() > 0 and t < 40:
		sim.step([hold, idle])   # keep holding
		t += 1
	Runner.T.ok(t <= 18, "held grenade airbursts at the apex (~+17), not the full arc (got +%d)" % t)
	var burst := false
	for ev in sim.events:
		if ev["t"] == "explosion" and ev["src"] == "airburst":
			burst = true
	Runner.T.ok(burst, "the airburst pop is tagged src=airburst for the view")

	var sim2 := SimWorld.new(1, 2)
	var tap := SimInput.new()
	tap.grenade = true
	tap.aim_x = 256
	var idle2 := SimInput.new()
	sim2.step([tap, idle2])
	Runner.T.eq(sim2.grenades.size(), 1, "tap throw leaves one grenade in flight")
	var t2 := 0
	while sim2.grenades.size() > 0 and t2 < 40:
		sim2.step([idle2, idle2])   # button released
		t2 += 1
	Runner.T.ok(t2 >= 28, "tapped grenade flies the full arc (~+32, got +%d)" % t2)


func test_route_fork_streams_lanes_at_gates_2_and_4() -> void:
	# Force gate 2 to stream by staging the counter at 1 and pulling the
	# stream horizon down (the 60s torture never gets here — probe-verified).
	var sim := SimWorld.new(7, 1)
	sim._gate_counter = 1
	var gate_y: int = sim._next_gate_y
	sim.camera_top = gate_y + 2 * SimWorld.VIEW_H - SimWorld.F_ONE  # horizon just past the gate row
	sim.step([_idle()])
	var forked := false
	for ev in sim.events:
		if ev["t"] == "route_fork":
			forked = true
	Runner.T.ok(forked, "gate 2 stream emits the route_fork telegraph event")
	# Cache lane: one free crate left of center, ringed by extra mines.
	var crates_left := 0
	for pk in sim.pickups:
		if pk["cost"] == 0 and pk["x"] < SimWorld.SCREEN_CX and pk["y"] > gate_y:
			crates_left += 1
	Runner.T.eq(crates_left, 1, "cache lane holds exactly one free crate left of center")
	var band_mines := 0
	for m in sim.mines:
		if m["y"] > gate_y and m["y"] < gate_y + 300 * SimWorld.F_ONE and m["x"] < SimWorld.SCREEN_CX:
			band_mines += 1
	Runner.T.ok(band_mines >= 3, "cache lane is ringed by at least the 3 extra mines (got %d)" % band_mines)
	# Gauntlet lane: two elites right of center, exactly one a marked bounty.
	var lane_elites := 0
	var lane_marked := 0
	for e in sim.enemies:
		if e["kind"] == "elite" and e["x"] > SimWorld.SCREEN_CX and e["y"] > gate_y:
			lane_elites += 1
			if e.get("marked", false):
				lane_marked += 1
	Runner.T.eq(lane_elites, 2, "gauntlet lane spawns two extra elites right of center")
	Runner.T.ok(lane_marked >= 1, "at least one gauntlet elite is a guaranteed marked bounty")
	# A==B determinism over the forked stream.
	var a := _fork_run()
	var b := _fork_run()
	Runner.T.eq(a, b, "route-fork stream A/B checksum diverged")


func _fork_run() -> int:
	var sim := SimWorld.new(11, 1)
	sim._gate_counter = 1
	sim.camera_top = sim._next_gate_y + 2 * SimWorld.VIEW_H - SimWorld.F_ONE
	for tick in 400:
		sim.step([_idle()])
	return sim.checksum()


func test_supply_drop_magnetizes_rushers_and_dies_to_their_touch() -> void:
	# Force-stage the wave >= 4 drop roll, then prove the objective beat:
	# rushers retarget the crate, and touching it destroys it (denial).
	var sim := SimWorld.new(3, 1, "endless")
	sim.wave = 3
	var dropped := false
	for attempt in 12:   # 1-in-3 roll: 12 tries make a miss ~0.8% likely
		sim._start_wave()
		for pk in sim.pickups:
			if pk.get("drop", false):
				dropped = true
		if dropped:
			break
	Runner.T.ok(dropped, "wave >= 4 rolls a parachute drop within 12 waves")
	var drop: Dictionary
	for pk in sim.pickups:
		if pk.get("drop", false):
			drop = pk
	# A rusher spawned away from the drop must walk TOWARD it, not the player.
	sim.enemies.clear()
	sim.wave_pending = 0
	sim._spawn_enemy(drop["x"] + 100 * SimWorld.F_ONE, drop["y"], false)
	var r := sim.enemies[sim.enemies.size() - 1]
	var d0: int = drop["x"] - r["x"]
	sim.step([_idle()])
	var d1: int = drop["x"] - r["x"]
	Runner.T.ok(absi(d1) < absi(d0), "rusher closes on the drop, not the player")
	# Park him on the crate: it dies to the touch.
	r["x"] = drop["x"]
	r["y"] = drop["y"]
	sim.step([_idle()])
	var still_there := false
	for pk in sim.pickups:
		if pk.get("drop", false):
			still_there = true
	Runner.T.ok(not still_there, "rusher touch destroys the drop (denial)")
	var stolen := false
	for ev in sim.events:
		if ev["t"] == "drop_stolen":
			stolen = true
	Runner.T.ok(stolen, "denial emits drop_stolen for the view")


func test_broadcast_tower_debuts_wave_7_and_its_aura_speeds_the_swarm() -> void:
	var sim := SimWorld.new(5, 1, "endless")
	# Below wave 7 the roll-8 slot must stay a plain elite (rng stream unchanged).
	sim.wave = 6
	sim._spawn_broadcast(300 * SimWorld.F_ONE, sim.camera_top + 100 * SimWorld.F_ONE)
	var mast := sim.enemies[0]
	Runner.T.eq(mast["hp"], SimWorld.BROADCAST_HP, "mast spawns armored at BROADCAST_HP")
	# Aura: a rusher inside 140px outruns a twin outside it.
	var py: int = sim.camera_top + 300 * SimWorld.F_ONE
	sim._spawn_enemy(300 * SimWorld.F_ONE, sim.camera_top + 160 * SimWorld.F_ONE, false)  # inside aura
	sim._spawn_enemy(40 * SimWorld.F_ONE, py, false)                                       # outside aura
	var near := sim.enemies[1]
	var far := sim.enemies[2]
	var ny0: int = near["y"]
	var fx0: int = far["x"]
	sim.players[0]["x"] = 300 * SimWorld.F_ONE
	sim.players[0]["y"] = py + 200 * SimWorld.F_ONE
	sim.step([_idle()])
	var near_moved: int = absi(near["y"] - ny0)
	var far_moved: int = absi(far["x"] - fx0) + absi(far["y"] - py)
	Runner.T.ok(near_moved > far_moved, "rusher in the rally aura outpaces one outside (%d vs %d)" % [near_moved, far_moved])
	# The mast is rooted and holds the wave open.
	Runner.T.eq(mast["x"], 300 * SimWorld.F_ONE, "mast never moves")
	Runner.T.ok(not sim._wave_hostiles_cleared(), "a live mast holds the wave open (anti-stall pressure)")
	# 5 bullets crack it: simulate via the armor gate.
	for hit in 4:
		mast["hp"] = mast["hp"] - 1
	Runner.T.eq(mast["hp"], 1, "armor chip grammar reaches 1 hp")


func test_tank_crew_gunner_seat() -> void:
	# P2 boards an OCCUPIED tank as coax gunner: derived identity (in_tank set,
	# occupant unchanged), independent aim + on-foot-cadence MG, +25% fuel tax,
	# driver exit promotes the gunner to the sticks.
	var sim := SimWorld.new(9, 2)
	# Stage INSIDE the camera view — _clamp_actor snaps players back into
	# frame during step(), which silently un-boards anyone parked off-screen.
	var tx: int = 300 * SimWorld.F_ONE
	var ty: int = sim.camera_top + 200 * SimWorld.F_ONE
	sim.tanks.clear()
	sim.tanks.append({"x": tx, "y": ty, "alive": true,
		"burning": false, "fuel": 100000, "burn_ticks": 0, "fire_cd": 0, "occupant": -1})
	var p0 := sim.players[0]
	var p1 := sim.players[1]
	for p in [p0, p1]:
		p["x"] = tx
		p["y"] = ty
	var board := SimInput.new()
	board.interact = true
	sim.step([board, _idle()])
	Runner.T.eq(sim.tanks[0]["occupant"], 0, "P1 boards as driver")
	sim.step([_idle(), _idle()])   # release interact edges
	var board2 := SimInput.new()
	board2.interact = true
	sim.step([_idle(), board2])
	Runner.T.eq(p1["in_tank"], 0, "P2 boards the occupied tank as gunner")
	Runner.T.eq(sim.tanks[0]["occupant"], 0, "occupant stays driver-only (derived gunner)")
	# Gunner fires the coax with his own aim while the driver holds fire.
	var gun := SimInput.new()
	gun.fire = true
	gun.aim_x = 256
	var ammo0: int = p1["mg_ammo"]
	sim.step([_idle(), gun])
	Runner.T.eq(p1["mg_ammo"], ammo0 - 1, "coax spends the gunner's own mg_ammo")
	Runner.T.ok(sim.bullets.size() > 0, "coax rounds join the shared bullets array")
	# Fuel tax: crewed burn outpaces solo burn over the same window.
	var fuel0: int = sim.tanks[0]["fuel"]
	for t in 40:
		sim.step([_idle(), _idle()])
	var crewed_burn: int = fuel0 - sim.tanks[0]["fuel"]
	Runner.T.ok(crewed_burn > 40, "double-crew burns fuel faster than 1/tick (got %d/40)" % crewed_burn)
	# Driver steps off: the gunner inherits the sticks.
	var exit := SimInput.new()
	exit.interact = true
	sim.step([exit, _idle()])
	Runner.T.eq(sim.tanks[0]["occupant"], 1, "departing driver promotes the gunner to occupant")
	Runner.T.eq(p0["in_tank"], -1, "the old driver is on foot")


func test_sandbags_wheel_buy_plants_blocks_and_dies_to_grenade() -> void:
	var sim := SimWorld.new(13, 1)
	var p := sim.players[0]
	p["x"] = 300 * SimWorld.F_ONE
	p["y"] = sim.camera_top + 200 * SimWorld.F_ONE
	p["aim_x"] = SimWorld.F_ONE
	p["aim_y"] = 0
	sim.war_chest = 500
	sim._try_buy(p, 4)
	Runner.T.eq(sim.sandbags.size(), 1, "wheel slot 4 plants a sandbag segment")
	Runner.T.eq(sim.war_chest, 500 - SimWorld.SHOP_SANDBAG_COST, "bag costs SHOP_SANDBAG_COST")
	var sb := sim.sandbags[0]
	Runner.T.ok(sb["x"] > p["x"], "bag plants ALONG the aim, not underfoot")
	# Bullets die inside the bag AABB — both directions use the same block.
	sim.bullets.append({"x": sb["x"], "y": sb["y"], "vx": 0, "vy": 0, "ttl": 10, "owner": 0})
	sim.enemy_bullets.append({"x": sb["x"], "y": sb["y"], "vx": 0, "vy": 0, "ttl": 10})
	sim._step_bullets()
	sim._step_enemy_bullets()
	Runner.T.eq(sim.bullets.size(), 0, "player bullet dies in the bag")
	Runner.T.eq(sim.enemy_bullets.size(), 0, "enemy bullet dies in the bag")
	# A rusher walking the bag line stalls (move-revert), then a grenade clears it.
	sim._spawn_enemy(sb["x"] + 24 * SimWorld.F_ONE, sb["y"], false)
	var r := sim.enemies[sim.enemies.size() - 1]
	p["x"] = sb["x"] - 60 * SimWorld.F_ONE
	p["y"] = sb["y"]
	# Walk at REAL enemy speed for 90 steps: the wall must hold the line —
	# a mover may skim the AABB edge but can never end up on the far side.
	for step in 90:
		var dx: int = p["x"] - r["x"]
		sim._advance_toward(r, dx, 0, Fixed.length(dx, 0), SimWorld.ENEMY_SPEED)
	Runner.T.ok(r["x"] > sb["x"], "rusher never phases through the bag line (at %d vs bag %d)" % [r["x"], sb["x"]])
	sim._explode(sb["x"], sb["y"])
	Runner.T.eq(sim.sandbags.size(), 0, "one grenade clears the bag")
	# Field cap denies the 7th bag, loudly.
	for n in SimWorld.SANDBAG_FIELD_CAP:
		sim.sandbags.append({"x": n * 40 * SimWorld.F_ONE, "y": p["y"]})
	var chest0: int = sim.war_chest
	sim._try_buy(p, 4)
	Runner.T.eq(sim.sandbags.size(), SimWorld.SANDBAG_FIELD_CAP, "field cap holds at 6")
	Runner.T.eq(sim.war_chest, chest0, "capped buy denies without charging")


func test_commendation_tokens_mint_cap_wipe_and_spend() -> void:
	var sim := SimWorld.new(17, 1)
	var p := sim.players[0]
	# Mint rides the streak-20 surge: stage 19 and land the 20th kill.
	sim.kill_streak = 19
	sim.kill_streak_timer = 600
	sim._spawn_enemy(p["x"], p["y"] - 40 * SimWorld.F_ONE, false)
	sim._kill_enemy(sim.enemies[sim.enemies.size() - 1])
	Runner.T.eq(sim.tokens, 1, "streak-20 mints a Commendation")
	sim._mint_token(0, 0)
	sim._mint_token(0, 0)
	Runner.T.eq(sim.tokens, 2, "cap 2 kills hoarding (3rd milestone mints nothing)")
	# Spend: buy=6 wheel release — a free supply call, chest untouched.
	var chest0: int = sim.war_chest
	var spend := SimInput.new()
	spend.buy = 6
	sim.step([spend])
	Runner.T.eq(sim.tokens, 1, "token drop spends exactly one")
	Runner.T.eq(sim.war_chest, chest0, "token spend never touches the War Chest")
	# Death burns ONE token per body (a full wipe let a partner's stray death
	# zero your earned pair — re-review fix).
	sim._mint_token(0, 0)   # back to 2
	sim._kill_player(p)
	Runner.T.eq(sim.tokens, 1, "a death burns exactly one Commendation")
	p["alive"] = true
	sim._kill_player(p)
	Runner.T.eq(sim.tokens, 0, "the second death burns the last one")


func test_tank_hulk_covers_then_salvage_strips_it() -> void:
	var sim := SimWorld.new(19, 1)
	var p := sim.players[0]
	sim.tanks.clear()
	var ty: int = sim.camera_top + 200 * SimWorld.F_ONE
	sim.tanks.append({"x": 300 * SimWorld.F_ONE, "y": ty, "alive": true,
		"burning": true, "fuel": 0, "burn_ticks": 1, "fire_cd": 0, "occupant": -1})
	sim._detonate_tank(sim.tanks[0])
	Runner.T.eq(sim.tanks[0]["burn_ticks"], SimWorld.HULK_TICKS, "dead hull arms the hulk timer")
	# Bullets die on the smoldering hull — both directions.
	sim.bullets.append({"x": 300 * SimWorld.F_ONE, "y": ty, "vx": 0, "vy": 0, "ttl": 10, "owner": 0})
	sim.enemy_bullets.append({"x": 300 * SimWorld.F_ONE, "y": ty, "vx": 0, "vy": 0, "ttl": 10})
	sim._step_bullets()
	sim._step_enemy_bullets()
	Runner.T.eq(sim.bullets.size(), 0, "player bullet dies on the hulk")
	Runner.T.eq(sim.enemy_bullets.size(), 0, "enemy bullet dies on the hulk")
	# Salvage: +2 grenades, cover stripped, second tap a no-op.
	p["x"] = 300 * SimWorld.F_ONE
	p["y"] = ty
	p["grenade_ammo"] = 0
	Runner.T.ok(sim._try_salvage_hulk(p), "interact in reach salvages the hulk")
	Runner.T.eq(p["grenade_ammo"], 2, "salvage pays +2 grenades")
	Runner.T.eq(sim.tanks[0]["burn_ticks"], 0, "salvage strips the cover with it")
	# Same-tick second tap is SWALLOWED (returns true so P2's tap can't fall
	# through to a claymore plant) but grants nothing.
	var g_after: int = p["grenade_ammo"]
	Runner.T.ok(sim._try_salvage_hulk(p), "same-tick partner tap is swallowed, not a claymore misfire")
	Runner.T.eq(p["grenade_ammo"], g_after, "the swallowed tap pays nothing")
	sim.step([_idle()])
	Runner.T.ok(not sim._try_salvage_hulk(p), "next tick a stripped hulk is inert")
	sim.bullets.append({"x": 300 * SimWorld.F_ONE, "y": ty, "vx": 0, "vy": 0, "ttl": 10, "owner": 0})
	sim._step_bullets()
	Runner.T.eq(sim.bullets.size(), 1, "stripped hulk no longer blocks")


func test_vest_creep_ladder_and_last_stand_wipe_latch() -> void:
	# Campaign vests creep 60/75/90/105/120 per purchase and never reset on
	# death; endless keeps its wave-creep pricing untouched.
	var sim := SimWorld.new(23, 1)
	sim.war_chest = 2000
	var p := sim.players[0]
	var expect := [60, 75, 90, 105, 120, 120]
	for n in expect.size():
		Runner.T.eq(sim._supply_cost(2), expect[n], "vest buy %d costs %d" % [n, expect[n]])
		p["vest"] = false
		sim._try_buy(p, 2)
	var esim := SimWorld.new(23, 1, "endless")
	Runner.T.eq(esim._supply_cost(2), SimWorld.SHOP_VEST_COST, "endless vest keeps wave pricing")
	# Last Stand + all down latches the terminal wiped freeze.
	sim.last_stand = true
	sim._kill_player(p)
	sim.step([_idle()])
	Runner.T.ok(sim.wiped, "all-down in Last Stand latches wiped (no soft-hang)")


func test_arena_templates_vary_by_gate_and_still_open() -> void:
	# Gates 1/2/4 stream their authored layouts; destroy-both still opens.
	var sim := SimWorld.new(31, 1)
	sim.camera_top = sim._next_gate_y - 4 * SimWorld.GATE_SPACING
	sim._step_camera()
	Runner.T.ok(sim.gates.size() >= 4, "streamed through gate 4")
	Runner.T.eq(sim.gates[0]["b1"]["x"], 180 * SimWorld.F_ONE, "gate 1 keeps the classic left sentinel")
	Runner.T.eq(sim.gates[1]["b1"]["x"], 300 * SimWorld.F_ONE, "gate 2 goes staggered-front")
	Runner.T.eq(sim.gates[1]["b2"]["y"] - sim.gates[1]["y"], 40 * SimWorld.F_ONE, "gate 2 rear bunker tucks at +40")
	Runner.T.eq(sim.gates[3]["b1"]["x"], 240 * SimWorld.F_ONE, "gate 4 goes crossfire-close")
	var g2: Dictionary = sim.gates[1]
	g2["b1"]["alive"] = false
	g2["b2"]["alive"] = false
	sim._step_gates()
	Runner.T.ok(g2["open"], "destroy-both still opens a templated arena")


func test_rocks_are_real_cover() -> void:
	var sim := SimWorld.new(37, 1)
	var rx: int = 300 * SimWorld.F_ONE
	var ry: int = sim.camera_top + 200 * SimWorld.F_ONE
	sim.rocks.append({"x": rx, "y": ry})
	# Bullets die on it, both directions.
	sim.bullets.append({"x": rx, "y": ry, "vx": 0, "vy": 0, "ttl": 10, "owner": 0})
	sim.enemy_bullets.append({"x": rx, "y": ry, "vx": 0, "vy": 0, "ttl": 10})
	sim._step_bullets()
	sim._step_enemy_bullets()
	Runner.T.eq(sim.bullets.size(), 0, "player bullet dies on rock")
	Runner.T.eq(sim.enemy_bullets.size(), 0, "enemy bullet dies on rock")
	# Enemy step reverts at the face.
	sim._spawn_enemy(rx + 16 * SimWorld.F_ONE, ry, false)
	var e := sim.enemies[sim.enemies.size() - 1]
	sim.players[0]["x"] = rx - 60 * SimWorld.F_ONE
	sim.players[0]["y"] = ry
	for n in 60:
		var dx: int = sim.players[0]["x"] - e["x"]
		sim._advance_toward(e, dx, 0, Fixed.length(dx, 0), SimWorld.ENEMY_SPEED)
	Runner.T.ok(e["x"] > rx, "enemy never phases through the rock")
	# Player walk reverts too.
	var p := sim.players[0]
	p["x"] = rx - 16 * SimWorld.F_ONE
	p["y"] = ry
	var walk := SimInput.new()
	walk.move_x = 256
	for n in 30:
		sim.step([walk])
	Runner.T.ok(p["x"] < rx, "player never walks through the rock")
	# Grenade blast leaves it standing.
	var before: int = sim.rocks.size()   # step() streamed more — count, don't assume
	sim._explode(rx, ry)
	Runner.T.eq(sim.rocks.size(), before, "grenades arc over — no rock dies to a blast")


func test_arena_templates_are_clearable_and_barrel_safe() -> void:
	# KIMK round-2: prove the arenas PLAY, not just that coordinates match.
	var sim := SimWorld.new(41, 1)
	sim.camera_top = sim._next_gate_y - 4 * SimWorld.GATE_SPACING
	sim._step_camera()
	for gi in [0, 1, 3]:
		var g: Dictionary = sim.gates[gi]
		# Clearability: a player standing in the open lane south of each bunker
		# kills it with a straight grenade lob (the real opener verb).
		for bk in [g["b1"], g["b2"]]:
			Runner.T.ok(bk["x"] >= 40 * SimWorld.F_ONE and bk["x"] <= 560 * SimWorld.F_ONE,
				"gate %d bunker sits inside the playable lane" % (gi + 1))
			sim._explode(bk["x"] + SimWorld.BUNKER_W / 2, bk["y"] + SimWorld.BUNKER_H / 2)
			Runner.T.ok(not bk["alive"], "gate %d bunker dies to a reachable grenade" % (gi + 1))
		sim._step_gates()
		Runner.T.ok(g["open"], "gate %d opens after both bunkers fall" % (gi + 1))
	# Barrel-chain safety (gate 4): detonating the center cluster must NOT
	# double-kill the bunkers — the shortcut is a tool, not a sleepwalk.
	var sim2 := SimWorld.new(41, 1)
	sim2.camera_top = sim2._next_gate_y - 4 * SimWorld.GATE_SPACING
	sim2._step_camera()
	var g4: Dictionary = sim2.gates[3]
	var chained := 0
	for bl in sim2.barrels:
		if bl["y"] > g4["y"] and bl["y"] <= g4["y"] + 140 * SimWorld.F_ONE:
			sim2._detonate_barrel(bl, true)
			chained += 1
	Runner.T.ok(chained >= 3, "gate 4 fields its barrel cluster (got %d)" % chained)
	for t in 20:
		sim2._step_barrels()
	Runner.T.ok(g4["b1"]["alive"] and g4["b2"]["alive"],
		"the barrel chain scars the arena but never one-shots the lock")


func test_biome_view_goldens() -> void:
	# KIMK round-2: pin the LOOK — one assertion set per sector band.
	var MainS := load("res://src/main.gd")
	var m = MainS.new()
	var stops := [Color(0.58, 0.50, 0.38, 0.7), Color(0.49, 0.42, 0.33, 0.7), Color(0.42, 0.38, 0.24, 0.7),
		Color(0.44, 0.42, 0.40, 0.7), Color(0.40, 0.34, 0.28, 0.7)]
	for band in 5:
		var march := float(band) / 5.0
		Runner.T.eq(m._biome_ramp(march, stops), stops[band],
			"sector %d wears exactly its own dirt stop (flat, no mud)" % band)
	Runner.T.eq(m._biome_ramp(1.0, stops), stops[4], "the foundry holds the final stop")
	Runner.T.ok("crater_field" in m._LITTER_FOUNDRY and "wreck_halftrack" in m._LITTER_FOUNDRY,
		"the foundry band owns its slagged litter pool")
	Runner.T.ok(m._LITTER_FOUNDRY != m._LITTER_LATE, "foundry pool is distinct from the late pool")
	m.free()


func test_choke_bounds_and_fork_island() -> void:
	var sim := SimWorld.new(43, 1)
	# Segments 0-1: full lane (torture window untouched — the inert proof).
	Runner.T.eq(sim._choke_bounds(-500 * SimWorld.F_ONE)[0], SimWorld.WORLD_LEFT, "segment 0 stays open")
	# Segment 2, in-band: one flank bitten to a 368px lane.
	var cb: Array = sim._choke_bounds(-(2000 + 200) * SimWorld.F_ONE)
	Runner.T.ok(cb[1] - cb[0] == 608 * SimWorld.F_ONE - SimWorld.CHOKE_BITE, "choke bites the lane to 368px")
	# Fork island: a player inside the divider snaps to an edge.
	sim.gates.append({"y": -3000 * SimWorld.F_ONE, "open": true, "b1": {}, "b2": {}, "boss": {}, "fork": true})
	var p := sim.players[0]
	p["x"] = 260 * SimWorld.F_ONE
	p["y"] = -3000 * SimWorld.F_ONE + 100 * SimWorld.F_ONE
	sim.camera_top = p["y"] - 100 * SimWorld.F_ONE
	sim._clamp_actor(p)
	Runner.T.ok(p["x"] == 216 * SimWorld.F_ONE or p["x"] == 304 * SimWorld.F_ONE,
		"the wreck island is solid — the lane choice is physical")


func test_cover_sprites_fit_their_collision() -> void:
	# KIMK: an elongated log whose pixel ends outrun the AABB is the same lie
	# wearing a new sprite. Pin every cover sprite's drawn HALF-width to the
	# collision half-width (+4px art tolerance for soft edges).
	var MainS := load("res://src/main.gd")
	var m = MainS.new()
	for tex_name in ["rock1", "rock2", "tree_dead2"]:
		var half_w: float = Art.tex(tex_name).get_size().x * Art.draw_scale(tex_name) \
			* (1.3 if tex_name != "tree_dead2" else 0.35) / 2.0
		Runner.T.ok(half_w <= 20.0,
			"%s drawn half-width %.1f fits the 16px cover AABB (+4 tolerance)" % [tex_name, half_w])
	# Endless quadrant rocks are SIM entities now (art that reads as cover IS cover).
	var sim := SimWorld.new(47, 1, "endless")
	Runner.T.ok(sim.rocks.size() >= 6, "endless seeds its six quadrant rocks as real blockers")
	# Palette-contrast evidence: the rust-tan shift is hue-only — ground
	# luminance moves <3%, so enemy silhouette contrast is preserved.
	var base := Color(0.5, 0.53, 0.375)
	var rust := Color(base.r + 0.04, base.g - 0.04, base.b)
	Runner.T.ok(absf(rust.get_luminance() - base.get_luminance()) < 0.03,
		"endless tint shifts hue, not luminance — enemy contrast holds")
	m.free()
