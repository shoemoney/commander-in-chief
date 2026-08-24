extends RefCounted
## The Mortar Observer — the pacing whip. Stall and he appears; stall longer
## and shells track you; kill him or push forward and the pressure lifts.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _stall_until_observer(sim: SimWorld) -> void:
	var guard := SimWorld.OBSERVER_STALL_TICKS + 10
	while sim.observer.is_empty() and guard > 0:
		sim.step([_idle()])
		guard -= 1


func test_observer_spawns_on_stall() -> void:
	var sim := SimWorld.new(11, 1)
	# Clear field pressure so the idle player isn't killed before the stall
	# threshold (enemy contact death would reset nothing — but a corpse can't
	# stall). Kill switch: park the player in a fresh tank; contact-immune.
	var tank := {"x": sim.players[0]["x"], "y": sim.players[0]["y"], "alive": true,
		"burning": false, "fuel": 1 << 40, "fire_cd": 0, "burn_ticks": 0, "occupant": -1}
	sim.tanks.append(tank)
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.ok(sim.players[0]["in_tank"] >= 0, "player parked in tank for the stall")
	_stall_until_observer(sim)
	Runner.T.ok(not sim.observer.is_empty(), "observer spawned after sustained stall")
	Runner.T.ok(sim.stall_ticks >= SimWorld.OBSERVER_STALL_TICKS, "stall counter reached threshold")


func test_strike_tracks_and_kills_staller() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.enemies.clear()
	# Force the observer directly; stand still and take the hit.
	sim.observer = {"x": p["x"], "strike_cd": 1, "spawn_cam": sim.camera_top}
	sim.step([_idle()])
	Runner.T.eq(sim.strikes.size(), 1, "strike called on the staller")
	for i in SimWorld.STRIKE_TELEGRAPH_TICKS + 1:
		sim.step([_idle()])
		if not p["alive"]:
			break
	Runner.T.ok(not p["alive"], "standing in the telegraph is death")


func test_roll_iframes_survive_strike() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.observer = {"x": p["x"], "strike_cd": 999999, "spawn_cam": sim.camera_top}
	# Strike landing this tick, player mid-roll.
	sim.strikes.append({"x": p["x"], "y": p["y"], "ticks": 1})
	var roll := SimInput.new()
	roll.roll = true
	roll.move_x = 256
	sim.step([roll])
	Runner.T.ok(p["roll_ticks"] > 0, "roll triggered")
	Runner.T.ok(p["alive"], "i-frames beat the mortar strike")


func test_kill_observer_cancels_only_his_strikes() -> void:
	# Design-loop iter1: strikes[] is shared by the observer, grenadiers, drones
	# and boss volleys — killing the spotter must defuse ONLY the obs-tagged
	# barrage, not hand out a free field-wide defuse of everyone else's shots.
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	sim.observer = {"x": p["x"], "strike_cd": 999999, "spawn_cam": sim.camera_top}
	sim._add_strike(p["x"] + 100 * Fixed.ONE, p["y"], true)    # the observer's own
	sim._add_strike(p["x"] - 100 * Fixed.ONE, p["y"])          # a grenadier's lob
	sim.stall_ticks = 400
	var chest_before := sim.war_chest
	sim._kill_observer()
	Runner.T.ok(sim.observer.is_empty(), "observer down")
	Runner.T.eq(sim.strikes.size(), 1, "observer strikes cancelled, the grenadier's lob still falls")
	Runner.T.ok(not sim.strikes[0].get("obs", false), "the surviving strike is the non-observer one")
	# Downing the spotter now HALVES the stall clock instead of zeroing it — the
	# anti-camp valve must not fully re-arm the window it exists to punish.
	Runner.T.eq(sim.stall_ticks, SimWorld.OBSERVER_STALL_TICKS / 2,
		"stall pressure halved, not fully reset")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_ELITE * 2, "observer bounty minted")


func test_strike_ignites_tank_not_infantry() -> void:
	var sim := SimWorld.new(11, 1)
	var p := sim.players[0]
	var tank := {"x": p["x"] + 200 * Fixed.ONE, "y": p["y"], "alive": true,
		"burning": false, "fuel": 100, "fire_cd": 0, "burn_ticks": 0, "occupant": -1}
	sim.tanks.append(tank)
	sim._spawn_enemy(tank["x"], tank["y"], false)
	sim.strikes.append({"x": tank["x"], "y": tank["y"], "ticks": 1})
	sim.step([_idle()])
	Runner.T.ok(tank["burning"], "mortar strike ignites armor")
	var enemy_alive := false
	for e in sim.enemies:
		if e["alive"]:
			enemy_alive = true
	Runner.T.ok(enemy_alive, "mortar fire is harmless to enemy infantry")


# --- The camera-hold contradiction (cycle 7) -------------------------------
#
# stall_ticks scores "the camera did not advance this tick" as loitering. But
# THREE live situations pin the camera with the player pushing as hard as they
# can: a closed gate's clamp (campaign/arcade), the same clamp on boss_rush's
# pre-authored gauntlet, and endless (which never scrolls at all, by design).
# In all three the game punishes the player for a wall the game itself put up,
# and the punishment is a mortar barrage plus an on-screen "PUSH NORTH" order
# that cannot be obeyed.
#
# Measured by MUTATING the fix out (drop `and not held` from the stall_ticks
# increment) and re-running exactly this test — so these are the numbers it
# prints, not a probe's:
#   campaign   3691 held ticks, 3227 of them incremented stall_ticks
#   boss_rush  3691 held ticks, 3167 of them incremented stall_ticks
#   endless    4000 held ticks, 3624 of them incremented (live Spotter)
# and dropping `held or` from the observer despawn leaves the pre-seeded
# observer up in campaign AND boss_rush; dropping neither, 6 fresh observers
# spawn while held in each.
#
# WINDOW SIZING. This leg observes a 3691-tick contiguous hold. Cross-checked
# against real play (.aaa/probe_c7d.gd, the repo's combat bot over 8 seeds x
# 6000 campaign ticks): longest contiguous hold 3678 ticks, median per-seed
# 2549. So 4000 ticks covers the longest hold anything has measured, and is
# 7.7x the 480-tick OBSERVER_STALL_TICKS fuse the pin must outlast for the
# defect to bite at all. The vacuity guard below re-checks that per run.


func _push_north() -> SimInput:
	var inp := SimInput.new()
	inp.move_y = -256
	inp.aim_y = -256
	return inp


func test_stall_never_accrues_while_the_sim_holds_the_camera() -> void:
	# 1.3: a closed gate held 93.8% of ticks with zero whip — the old `and not held`
	# guard gated stall increment while camera_held, so the drip farmed for free.
	# Stall now accrues at half-rate while held (tick parity => 0.5/tick), so
	# OBSERVER_STALL_TICKS (480) fires at ~960 held ticks instead of never. Endless
	# stays exempt (always held by design, its Spotter lives until shot).
	# Isolated from the earlier "hold is not loitering" leg (1845/3691 held ticks
	# during the 60s torture reached the observer fusion, peaks at 924 stalls with 1 observer) now
	# 3691 held ticks accumulate ~1600 stall counts, 3 observers spawn while held at half rate — measured values.
	for mode in ["campaign", "boss_rush", "endless"]:
		var sim := SimWorld.new(3, 1, mode)
		sim.god_mode = true
		if mode == "endless":
			sim.observer = {"x": 300 * Fixed.ONE, "strike_cd": 120, "spawn_cam": sim.camera_top}
		var inp := _push_north()
		var held_ticks := 0
		var bad := 0
		var run := 0
		var longest := 0
		for t in 4000:
			inp.fire = (t % 8) != 0
			var held: bool = sim.camera_held()
			var before: int = sim.stall_ticks
			sim.step([inp])
			if not held:
				run = 0
				continue
			held_ticks += 1
			run += 1
			longest = maxi(longest, run)
			if sim.stall_ticks > before:
				bad += 1
		if mode == "endless":
			Runner.T.eq(bad, 0,
				"%s: stall_ticks incremented on %d of %d ticks where camera_held() was true — endless must stay frozen" \
					% [mode, bad, held_ticks])
		else:
			# Half-rate while held: expect ~50% of held ticks increment stall
			var expect_min: int = int(float(held_ticks) * 0.35)
			var expect_max: int = int(float(held_ticks) * 0.65)
			Runner.T.ok(bad >= expect_min and bad <= expect_max,
				"%s: stall_ticks incremented on %d of %d held ticks — expected ~50%% half-rate (range %d..%d) while held, 0 is the old farm" \
					% [mode, bad, held_ticks, expect_min, expect_max])
		Runner.T.ok(longest >= SimWorld.OBSERVER_STALL_TICKS,
			"%s: longest contiguous held run was only %d ticks (< the %d-tick observer fuse) — this leg ran on nothing" \
				% [mode, longest, SimWorld.OBSERVER_STALL_TICKS])


func test_no_observer_spawns_or_persists_while_the_camera_is_held() -> void:
	# (a) While held, the drip is throttled and the whip accrues at half-rate —
	# observers CAN spawn (the gate farm fix), but only at the throttled cadence
	# (~1 per 960 held ticks). Before 1.3 this was 0 while held and the gate was a
	# farm; endless stays at 0 by exemption.
	for mode in ["campaign", "boss_rush"]:
		var sim := SimWorld.new(3, 1, mode)
		sim.god_mode = true
		var inp := _push_north()
		var spawns := 0
		var held_ticks := 0
		for t in 4000:
			inp.fire = (t % 8) != 0
			var held: bool = sim.camera_held()
			sim.step([inp])
			if not held:
				continue
			held_ticks += 1
			for ev in sim.events:
				if ev["t"] == "observer_spawn":
					spawns += 1
		# Half-rate stall: at most ceil(held/960) observers in this window
		var max_expected: int = int(ceil(float(held_ticks) / float(SimWorld.OBSERVER_STALL_TICKS * 2))) + 1
		Runner.T.ok(spawns <= max_expected,
			"%s: %d observer(s) spawned while held (%d held ticks) — expected at most %d at half-rate, unlimited spawn is the farm" % [mode, spawns, held_ticks, max_expected])
		Runner.T.ok(spawns >= 1,
			"%s: %d observer(s) while held — expected at least 1 at half-rate (held %d ticks, 0 was the pre-1.3 farm)" % [mode, spawns, held_ticks])

	# ...(b) and one that was ALREADY up when you hit the wall must stand down.
	# OBSERVER_DESPAWN_ADVANCE is 150px of northward advance the clamp forbids, so
	# without this it is an unshakeable barrage: you cannot outrun it and you cannot
	# walk away. (Endless is exempt by design — its Spotter lives until it is shot.)
	for mode in ["campaign", "boss_rush"]:
		var sim := SimWorld.new(3, 1, mode)
		sim.god_mode = true
		var inp := _push_north()
		var seeded := false
		for t in 4000:
			inp.fire = (t % 8) != 0
			if sim.camera_held():
				if not seeded:
					sim.observer = {"x": 300 * Fixed.ONE, "strike_cd": 120, "spawn_cam": sim.camera_top}
					seeded = true
					sim.step([inp])
					continue
				Runner.T.ok(sim.observer.is_empty(),
					"%s: an observer that was already up when the camera got held is still firing — it can never be outrun (needs %dpx of advance the clamp forbids)" \
						% [mode, SimWorld.OBSERVER_DESPAWN_ADVANCE / Fixed.ONE])
				break
			sim.step([inp])
		Runner.T.ok(seeded, "%s: never reached a held-camera tick — the pre-existing-observer leg ran on nothing" % mode)
