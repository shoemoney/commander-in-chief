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
	for mode in ["campaign", "boss_rush", "endless"]:
		var sim := SimWorld.new(3, 1, mode)
		sim.god_mode = true   # DEBUG-ONLY: keeps any_alive true so the counter's guard stays open
		if mode == "endless":
			# Endless only steps the observer when the Spotter mutator has dropped one.
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
		Runner.T.eq(bad, 0,
			"%s: stall_ticks incremented on %d of %d ticks where camera_held() was true — the sim is scoring its own wall as the player loitering" \
				% [mode, bad, held_ticks])
		# Vacuity guard: a leg that never observed a hold longer than the fuse proved nothing.
		Runner.T.ok(longest >= SimWorld.OBSERVER_STALL_TICKS,
			"%s: longest contiguous held run was only %d ticks (< the %d-tick observer fuse) — this leg ran on nothing" \
				% [mode, longest, SimWorld.OBSERVER_STALL_TICKS])


func test_no_observer_spawns_or_persists_while_the_camera_is_held() -> void:
	# (a) nothing new may arrive while the player is walled in...
	for mode in ["campaign", "boss_rush"]:
		var sim := SimWorld.new(3, 1, mode)
		sim.god_mode = true
		var inp := _push_north()
		var spawns := 0
		for t in 4000:
			inp.fire = (t % 8) != 0
			var held: bool = sim.camera_held()
			sim.step([inp])
			if not held:
				continue
			for ev in sim.events:
				if ev["t"] == "observer_spawn":
					spawns += 1
		Runner.T.eq(spawns, 0,
			"%s: %d observer(s) spawned on a tick where the sim itself was holding the camera" % [mode, spawns])

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
