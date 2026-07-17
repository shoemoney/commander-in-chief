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
