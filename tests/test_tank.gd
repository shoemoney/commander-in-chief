extends RefCounted
## The tank: board, crush, shells-from-grenade-ammo, fuel burn, bail window,
## kamikaze verb. (1986 rules: enterable armor with a fuel clock.)

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _park_tank(sim: SimWorld, x: int, y: int) -> Dictionary:
	var tank := {
		"x": x, "y": y, "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0,
		"fire_cd": 0, "occupant": -1,
	}
	sim.tanks.append(tank)
	return tank


func _board(sim: SimWorld, tank: Dictionary) -> void:
	sim.players[0]["x"] = tank["x"]
	sim.players[0]["y"] = tank["y"]
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])


func _board_two(sim: SimWorld, tank: Dictionary) -> void:
	for p in sim.players:
		p["x"] = tank["x"]
		p["y"] = tank["y"]
	var driver_press := SimInput.new()
	driver_press.interact = true
	var gunner_press := SimInput.new()
	gunner_press.interact = true
	sim.step([driver_press, gunner_press])
	# Release both edges so a later interact is an intentional bailout press.
	sim.step([_idle(), _idle()])


func test_board_and_exit() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"] - 10 * Fixed.ONE)
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.ok(p["in_tank"] >= 0 and sim.tanks[p["in_tank"]] == tank, "player boarded the parked tank")
	Runner.T.eq(tank["occupant"], 0, "tank records occupant")
	# Release, then press again to exit (edge-triggered).
	sim.step([_idle()])
	sim.step([inp])
	Runner.T.eq(p["in_tank"], -1, "player exited the tank")
	Runner.T.eq(tank["occupant"], -1, "tank vacated")
	Runner.T.ok(p["boost_ticks"] == 0, "no bail boost from a healthy tank")


func test_crush_and_bullet_immunity() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	# Enemy at contact range: crushed instead of killing the player.
	sim._spawn_enemy(tank["x"], tank["y"], false)
	var chest_before := sim.war_chest
	sim.step([_idle()])
	Runner.T.ok(p["alive"], "tanked player survives enemy contact")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_RUSHER, "crush minted coin")


func test_cannon_draws_grenade_ammo() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var shells_before: int = p["grenade_ammo"]
	var fire := SimInput.new()
	fire.grenade = true   # the cannon rides the GRENADE verb — it spends grenade ammo
	fire.aim_y = -256
	sim.step([fire])
	Runner.T.eq(p["grenade_ammo"], shells_before - 1, "cannon consumed grenade ammo")
	Runner.T.ok(sim.grenades.size() == 1 and sim.grenades[0]["shell"], "shell projectile spawned")


func test_cannon_ignores_always_fire_and_is_edge_triggered() -> void:
	## THE grenade-incinerator regression. ALWAYS-FIRE pins inp.fire permanently true, so
	## a cannon on the fire verb emptied all 12 grenades in ~8 s of a 20 s ride and the
	## player dismounted with zero — with no way to decline. The cannon is on GRENADE now,
	## and edge-triggered, so neither holding fire nor holding E can drain the pool.
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var full: int = p["grenade_ammo"]
	var held := SimInput.new()
	held.fire = true         # always-fire, the shipped input shape
	held.grenade = true      # ...and E welded down on top of it
	held.aim_y = -256
	for _t in SimWorld.TANK_FUEL_TICKS:
		if p["in_tank"] < 0:
			break
		sim.step([held])
	Runner.T.eq(p["grenade_ammo"], full - 1,
		"a whole ride of held fire + held E spends exactly ONE shell (the single edge)")
	Runner.T.ok(p["grenade_ammo"] > 0, "the rider dismounts with grenades left")


func test_cannon_never_fires_without_the_grenade_verb() -> void:
	## Ride out the whole fuel clock with always-fire on and E never pressed: not one
	## shell, not one grenade gone. The trigger belongs to the player again.
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var full: int = p["grenade_ammo"]
	var fire := SimInput.new()
	fire.fire = true
	fire.aim_y = -256
	var shells := 0
	for _t in SimWorld.TANK_FUEL_TICKS:
		if p["in_tank"] < 0:
			break
		sim.step([fire])
		for ev in sim.events:
			if ev.get("t", "") == "tank_shot":
				shells += 1
	Runner.T.eq(shells, 0, "always-fire alone never fires the cannon")
	Runner.T.eq(p["grenade_ammo"], full, "a full ride costs zero grenades if you never tap E")


func test_fuel_out_ignites_and_bail_window() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	tank["fuel"] = 2
	sim.step([_idle()])
	sim.step([_idle()])
	Runner.T.ok(tank["burning"], "fuel out ignites the tank")
	Runner.T.eq(tank["burn_ticks"], SimWorld.TANK_BAIL_TICKS - 1, "bail window armed")
	# Bail: edge-press interact → out with the boost, tank still burning.
	var inp := SimInput.new()
	inp.interact = true
	sim.step([inp])
	Runner.T.eq(p["in_tank"], -1, "bailed out")
	Runner.T.ok(p["boost_ticks"] > 0, "bail grants the speed boost")
	# Window expires → detonation, player already clear survives.
	for i in SimWorld.TANK_BAIL_TICKS:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "burning tank detonated after the window")
	Runner.T.ok(p["alive"], "bailed player survived the detonation")


func test_stay_inside_and_die() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	tank["fuel"] = 1
	for i in SimWorld.TANK_BAIL_TICKS + 3:
		sim.step([_idle()])
	Runner.T.ok(not tank["alive"], "tank gone")
	Runner.T.ok(not p["alive"], "rider who ignored the klaxon died")


func test_kamikaze_destroys_bunker_and_ejects_driver() -> void:
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var bunker := {"x": tank["x"] - 10 * Fixed.ONE, "y": tank["y"] - 100 * Fixed.ONE,
		"alive": true, "spawn_cd": 999999}
	sim.bunkers.append(bunker)
	sim._ignite_tank(tank)
	# Drive north into the bunker while burning.
	var up := SimInput.new()
	up.move_y = -256
	var chest_before := sim.war_chest
	for i in 120:
		sim.step([up])
		if not tank["alive"]:
			break
	Runner.T.ok(not bunker["alive"], "kamikaze detonated the bunker")
	Runner.T.ok(not tank["alive"], "tank consumed by the verb")
	Runner.T.ok(p["alive"], "driver thrown clear, alive")
	Runner.T.ok(p["boost_ticks"] > 0 or p["in_tank"] == -1, "driver ejected with escape boost")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_BUNKER * 2, "kamikaze pays double bunker coin")


# ---------------------------------------------------------------------------
# The rider, not the tank. 8 lethal predicates in sim_world.gd each spelled
# `p["in_tank"] < 0` inline, so ARMOR was absolute: measured on the pre-fix
# tree, a boarded player took 179 ticks (the full TANK_BAIL_TICKS window) of a
# mortar strike + a rusher + an enemy bullet ALL landing on the hull EVERY tick
# and finished alive=true, vest intact, zero damage events. On foot the same
# shelling killed at tick 44. The bail window was a guaranteed 3-second
# invulnerable walk-out instead of a race.
# ---------------------------------------------------------------------------

func _shell_the_hull(sim: SimWorld, tank: Dictionary) -> void:
	sim.strikes.append({"x": tank["x"], "y": tank["y"], "ticks": 1, "obs": false})


func test_burning_tank_crew_is_exposed_to_every_hazard() -> void:
	# Window = 179 ticks = the whole TANK_BAIL_TICKS bail window, i.e. >= the
	# longest instance of the defect that can exist (at 180 the expiry kills the
	# rider anyway, which would be a false green — so death must land STRICTLY
	# inside the window and is reported as the tick it happened).
	var window := SimWorld.TANK_BAIL_TICKS - 1

	# --- artillery on a BURNING hull ---
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	sim._ignite_tank(tank)
	var died_at := -1
	for i in window:
		_shell_the_hull(sim, tank)
		sim.step([_idle()])
		if not p["alive"]:
			died_at = i
			break
	Runner.T.ok(died_at >= 0 and died_at < window,
		"burning-hull rider dies to artillery inside the bail window (tick %d of %d)" % [died_at, window])

	# --- enemy bullet on a BURNING hull ---
	var bsim := SimWorld.new(3, 1)
	bsim.enemies.clear()
	var bp := bsim.players[0]
	var btank := _park_tank(bsim, bp["x"], bp["y"])
	_board(bsim, btank)
	bsim._ignite_tank(btank)
	var bdied := -1
	for i in window:
		bsim.enemy_bullets.append({"x": btank["x"], "y": btank["y"], "vx": 0, "vy": 0,
			"ttl": SimWorld.ENEMY_BULLET_TTL_TICKS})
		bsim.step([_idle()])
		if not bp["alive"]:
			bdied = i
			break
	Runner.T.ok(bdied >= 0 and bdied < window,
		"burning-hull rider dies to an enemy bullet inside the bail window (tick %d)" % bdied)

	# --- landmine under a BURNING hull ---
	var msim := SimWorld.new(3, 1)
	msim.enemies.clear()
	var mp := msim.players[0]
	var mtank := _park_tank(msim, mp["x"], mp["y"])
	_board(msim, mtank)
	msim._ignite_tank(mtank)
	msim.mines.append({"x": mtank["x"], "y": mtank["y"], "armed": true, "grace": 0})
	var mdied := -1
	for i in window:
		msim.step([_idle()])
		if not mp["alive"]:
			mdied = i
			break
	Runner.T.ok(mdied >= 0 and mdied < window,
		"burning-hull rider dies to the mine under it inside the bail window (tick %d)" % mdied)

	# --- CONTROL 1: a HEALTHY hull is still armor, and the brew-up is the bill.
	# Pins BOTH edges of the rule with no dead clauses: every round up to the
	# ignition tick is eaten by the armor (crew untouched, vest intact), and the
	# scheduled ignition ring spends exactly ONE hit after the escape grace. Given a vest so the difference
	# between "rung once" and "killed" is observable rather than collapsing into
	# `alive == false`.
	var hsim := SimWorld.new(3, 1)
	hsim.enemies.clear()
	var hp := hsim.players[0]
	var htank := _park_tank(hsim, hp["x"], hp["y"])
	_board(hsim, htank)
	hp["vest"] = true
	for i in 10:
		hsim.enemy_bullets.append({"x": htank["x"], "y": htank["y"], "vx": 0, "vy": 0,
			"ttl": SimWorld.ENEMY_BULLET_TTL_TICKS})
		hsim.step([_idle()])
		Runner.T.ok(hp["alive"] and hp["vest"] and not htank["burning"],
			"armor ate round %d — crew untouched, vest unspent, hull intact" % i)
	# ...and the same crew, in the same hull, once ordnance brews it: exactly one
	# hit. Both edges pinned, no dead clause.
	hsim.strikes.append({"x": htank["x"], "y": htank["y"], "ticks": 1, "obs": false})
	hsim.step([_idle()])
	Runner.T.ok(htank["burning"], "the hull ignites under a shell")
	Runner.T.ok(hp["alive"] and hp["vest"],
		"the brew-up starts the reaction window without an unavoidable hit")
	for i in SimWorld.TANK_IGNITION_GRACE_TICKS:
		hsim.step([_idle()])
	Runner.T.ok(hp["alive"] and not hp["vest"],
		"THE BILL: staying aboard through the grace rings the crew once — vest spent, rider alive")

	# --- CONTROL 2: what the bail window is WORTH, pinned on both sides of
	# assist_mode. The first version of this control staged the ignition with
	# `_ignite_tank(etank)` — from_damage defaults to FALSE, so it only ever
	# exercised a FUEL-OUT brew-up, the one path deliberately documented as not
	# ringing the crew. It was a dead control for ordnance and is re-staged here
	# with a real shell.
	#
	# 2a — SHIPPED DEFAULT (assist off, no vest): the shell lights the hull and
	# schedules its crew hit after the advertised reaction window. A prompt bail
	# wins; ignoring the klaxon still applies the ordinary one-hit rule.
	var nsim := SimWorld.new(3, 1)
	nsim.enemies.clear()
	var np := nsim.players[0]
	Runner.T.ok(not nsim.assist_mode and not np["vest"], "shipped default: assist off, no vest")
	var ntank := _park_tank(nsim, np["x"], np["y"])
	_board(nsim, ntank)
	nsim.strikes.append({"x": ntank["x"], "y": ntank["y"], "ticks": 1, "obs": false})
	nsim.step([_idle()])
	Runner.T.ok(ntank["burning"], "the shell brews the hull")
	Runner.T.ok(np["alive"], "ASSIST OFF: ignition leaves a real reaction window")
	Runner.T.eq(ntank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
		"damage ignition arms the measured crew-ring grace")
	for i in SimWorld.TANK_IGNITION_GRACE_TICKS:
		nsim.step([_idle()])
	Runner.T.ok(not np["alive"], "ignoring BAIL OUT through the grace still kills a vestless rider")

	var qsim := SimWorld.new(3, 1)
	qsim.enemies.clear()
	var qp := qsim.players[0]
	var qtank := _park_tank(qsim, qp["x"], qp["y"])
	_board(qsim, qtank)
	qsim.step([_idle()])
	qsim.strikes.append({"x": qtank["x"], "y": qtank["y"], "ticks": 1, "obs": false})
	qsim.step([_idle()])
	var quick_bail := SimInput.new()
	quick_bail.interact = true
	qsim.step([quick_bail])
	for i in SimWorld.TANK_IGNITION_GRACE_TICKS:
		qsim.step([_idle()])
	Runner.T.ok(qp["alive"] and qp["in_tank"] == -1,
		"a prompt normal-difficulty bail survives the scheduled ignition hit")

	# 2b — ASSIST ON: the same grace applies. A prompt bail preserves the vest;
	# assistance is insurance for ignoring the warning, not a mandatory tax.
	var esim := SimWorld.new(3, 1)
	esim.assist_mode = true      # every life is issued a vest (_kill_player:1769)
	esim.enemies.clear()
	var ep := esim.players[0]
	ep["vest"] = true            # ...seeded here for life #1, which predates any respawn
	var etank := _park_tank(esim, ep["x"], ep["y"])
	_board(esim, etank)
	esim.step([_idle()])   # release the boarding press — interact is edge-triggered
	esim.strikes.append({"x": etank["x"], "y": etank["y"], "ticks": 1, "obs": false})
	esim.step([_idle()])
	Runner.T.ok(etank["burning"] and ep["alive"] and ep["vest"],
		"ASSIST ON: ignition still grants a fair reaction window")
	var bail := SimInput.new()
	bail.interact = true
	esim.step([bail])
	Runner.T.eq(ep["in_tank"], -1, "driver bails off a hull lit by a REAL shell")
	for i in window:
		esim.step([_idle()])
	Runner.T.ok(ep["alive"] and ep["vest"],
		"...and walks the full %d-tick window out without paying an unavoidable vest" % window)

	# 2c — the OTHER ordnance ignition, same funnel: a barrel under the treads
	# (_detonate_barrel -> _explode -> _ignite_tank(..., true)). It arms the same grace.
	var lsim := SimWorld.new(3, 1)
	lsim.enemies.clear()
	var lp := lsim.players[0]
	var ltank := _park_tank(lsim, lp["x"], lp["y"])
	_board(lsim, ltank)
	var barrel := {"x": ltank["x"], "y": ltank["y"], "armed": true, "fuse_ticks": 0}
	lsim.barrels.append(barrel)
	lsim._detonate_barrel(barrel)
	Runner.T.ok(ltank["burning"] and lp["alive"],
		"a barrel under the treads brews the hull without deleting the bailout")
	Runner.T.eq(ltank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
		"barrel and artillery share the same grace")


func test_damage_ignition_last_safe_bail_tick_is_exact() -> void:
	# step() handles rider input before _step_tanks decrements the crew ring.
	# Therefore ring==1 is the final actionable frame: an interact edge escapes;
	# waiting through that same frame resolves the hit before any later press.
	var safe_sim := SimWorld.new(3, 1)
	safe_sim.enemies.clear()
	var safe_p := safe_sim.players[0]
	var safe_tank := _park_tank(safe_sim, safe_p["x"], safe_p["y"])
	_board(safe_sim, safe_tank)
	safe_sim.step([_idle()])
	safe_sim._ignite_tank(safe_tank, true)
	for _i in SimWorld.TANK_IGNITION_GRACE_TICKS - 1:
		safe_sim.step([_idle()])
	Runner.T.eq(safe_tank["crew_ring_ticks"], 1,
		"the final safe bailout frame begins with exactly one crew-ring tick")
	var last_safe_press := SimInput.new()
	last_safe_press.interact = true
	safe_sim.step([last_safe_press])
	Runner.T.ok(safe_p["alive"] and safe_p["in_tank"] == -1,
		"an interact edge on the exact last safe tick clears the rider before the ring")
	Runner.T.eq(safe_tank["crew_ring_ticks"], -1,
		"the ring resolves once and disarms after finding the last-tick bail clear")

	var late_sim := SimWorld.new(3, 1)
	late_sim.enemies.clear()
	var late_p := late_sim.players[0]
	var late_tank := _park_tank(late_sim, late_p["x"], late_p["y"])
	_board(late_sim, late_tank)
	late_sim.step([_idle()])
	late_sim._ignite_tank(late_tank, true)
	for _i in SimWorld.TANK_IGNITION_GRACE_TICKS - 1:
		late_sim.step([_idle()])
	Runner.T.eq(late_tank["crew_ring_ticks"], 1,
		"late control reaches the same one-tick boundary")
	late_sim.step([_idle()])
	Runner.T.ok(not late_p["alive"],
		"waiting through the final actionable tick resolves the promised crew hit")
	var too_late_press := SimInput.new()
	too_late_press.interact = true
	late_sim.step([too_late_press])
	Runner.T.ok(not late_p["alive"] and late_p["in_tank"] == -1,
		"an interact press one tick after the boundary cannot retroactively bail")


func test_damage_ignition_covers_both_tank_seats_and_independent_bails() -> void:
	# Both players may occupy one hull: occupant is the driver, while the gunner
	# is derived from their shared in_tank assignment. Ignition must preserve that
	# identity until each rider chooses to leave.
	var prompt_sim := SimWorld.new(3, 2)
	prompt_sim.enemies.clear()
	var prompt_tank := _park_tank(prompt_sim, prompt_sim.players[0]["x"], prompt_sim.players[0]["y"])
	_board_two(prompt_sim, prompt_tank)
	Runner.T.eq(prompt_tank["occupant"], 0, "first rider owns the driver seat")
	Runner.T.eq(prompt_sim._tank_gunner(0), 1, "second rider owns the derived gunner seat")
	prompt_sim._ignite_tank(prompt_tank, true)
	Runner.T.eq(prompt_tank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
		"one ignition warning covers the shared two-seat hull")
	Runner.T.ok(prompt_sim.players[0]["in_tank"] == 0 and prompt_sim.players[1]["in_tank"] == 0,
		"ignition itself neither ejects nor silently reassigns either crew member")
	var driver_bail := SimInput.new()
	driver_bail.interact = true
	var gunner_bail := SimInput.new()
	gunner_bail.interact = true
	prompt_sim.step([driver_bail, gunner_bail])
	Runner.T.ok(prompt_sim.players[0]["in_tank"] == -1 and prompt_sim.players[1]["in_tank"] == -1,
		"same-tick prompt exits clear both driver and gunner")
	Runner.T.eq(prompt_tank["occupant"], -1,
		"driver promotion followed by the gunner's own bail leaves no phantom occupant")

	# Independent decision at the deadline: gunner bails, driver ignores it. The
	# ring scans authoritative assignments and hits only the rider still aboard.
	var split_sim := SimWorld.new(3, 2)
	split_sim.enemies.clear()
	var split_tank := _park_tank(split_sim, split_sim.players[0]["x"], split_sim.players[0]["y"])
	_board_two(split_sim, split_tank)
	split_sim._ignite_tank(split_tank, true)
	for _i in SimWorld.TANK_IGNITION_GRACE_TICKS - 1:
		split_sim.step([_idle(), _idle()])
	var gunner_last_safe := SimInput.new()
	gunner_last_safe.interact = true
	split_sim.step([_idle(), gunner_last_safe])
	Runner.T.ok(not split_sim.players[0]["alive"],
		"driver who remains aboard at zero receives the scheduled hit")
	Runner.T.ok(split_sim.players[1]["alive"] and split_sim.players[1]["in_tank"] == -1,
		"gunner who bails on the last safe tick survives independently")
	Runner.T.eq(split_tank["occupant"], -1,
		"a killed driver cannot leave a departed gunner promoted into the hull")


func test_repeated_damage_ignition_does_not_reset_or_duplicate_the_ring() -> void:
	# Multiple damage sources converge on _ignite_tank(..., true). Exercise that
	# authoritative seam twice on the same tick after part of the grace is spent:
	# an already-burning hull must not extend the deadline or queue another hit.
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	sim.step([_idle()])
	p["vest"] = true
	sim._ignite_tank(tank, true)
	for _i in 11:
		sim.step([_idle()])
	var spent_deadline: int = tank["crew_ring_ticks"]
	Runner.T.ok(spent_deadline > 0 and spent_deadline < SimWorld.TANK_IGNITION_GRACE_TICKS,
		"fixture spends part of the original ignition deadline")
	sim._ignite_tank(tank, true)
	sim._ignite_tank(tank, true)
	Runner.T.eq(tank["crew_ring_ticks"], spent_deadline,
		"two same-tick damage ignitions neither reset nor extend the active deadline")
	for _i in spent_deadline:
		sim.step([_idle()])
	Runner.T.ok(p["alive"] and not p["vest"],
		"the unchanged deadline resolves exactly one ordinary hit")
	Runner.T.eq(tank["crew_ring_ticks"], -1, "the single ring disarms after resolution")
	# Remove the vest mercy interval while leaving enough hull lifetime to expose
	# an accidentally queued follow-up hit immediately.
	p["hurt_iframes"] = 0
	for _i in 2:
		sim.step([_idle()])
	Runner.T.ok(p["alive"] and tank["crew_ring_ticks"] == -1,
		"simultaneous re-ignition queued no delayed duplicate crew hit")


func test_simultaneous_strikes_share_preimpact_armor_for_one_and_two_crew() -> void:
	# Strike iteration is sequential, but impacts expiring in one simulation tick
	# are one ordnance batch. The first may ignite the hull; the second must still
	# see the healthy armor that both impacts arrived against.
	var solo := SimWorld.new(3, 1)
	solo.enemies.clear()
	var solo_tank := _park_tank(solo, solo.players[0]["x"], solo.players[0]["y"])
	_board(solo, solo_tank)
	_shell_the_hull(solo, solo_tank)
	_shell_the_hull(solo, solo_tank)
	solo.step([_idle()])
	Runner.T.ok(solo_tank["burning"] and solo.players[0]["alive"],
		"1P: two same-tick strikes ignite once without erasing the reaction window")
	Runner.T.eq(solo_tank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
		"1P: the full promised deadline survives the impact batch")
	_shell_the_hull(solo, solo_tank)
	solo.step([_idle()])
	Runner.T.ok(not solo.players[0]["alive"],
		"1P: an ordinary strike on the following tick reaches the burning-hull rider")

	var crewed := SimWorld.new(3, 2)
	crewed.enemies.clear()
	var crewed_tank := _park_tank(crewed, crewed.players[0]["x"], crewed.players[0]["y"])
	_board_two(crewed, crewed_tank)
	_shell_the_hull(crewed, crewed_tank)
	_shell_the_hull(crewed, crewed_tank)
	crewed.step([_idle(), _idle()])
	Runner.T.ok(crewed.players[0]["alive"] and crewed.players[1]["alive"],
		"2P: driver and gunner both retain the simultaneous-impact grace")
	Runner.T.eq(crewed_tank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
		"2P: one shared hull carries one unchanged full deadline")
	_shell_the_hull(crewed, crewed_tank)
	crewed.step([_idle(), _idle()])
	Runner.T.ok(not crewed.players[0]["alive"] and not crewed.players[1]["alive"],
		"2P: both assigned riders are ordinarily exposed after the impact batch")


func test_simultaneous_barrels_share_preimpact_armor_for_one_and_two_crew() -> void:
	# Fuse-resolved barrels are another sequential loop with the same concurrency
	# promise. Pin both party sizes so driver/gunner ordering cannot reopen it.
	for crew_size in [1, 2]:
		var sim := SimWorld.new(3, crew_size)
		sim.enemies.clear()
		sim.barrels.clear()
		var tank := _park_tank(sim, sim.players[0]["x"], sim.players[0]["y"])
		if crew_size == 1:
			_board(sim, tank)
		else:
			_board_two(sim, tank)
		for _barrel_i in 2:
			sim.barrels.append({"x": tank["x"], "y": tank["y"],
				"armed": true, "fuse_ticks": 1})
		var inputs: Array = [_idle()] if crew_size == 1 else [_idle(), _idle()]
		sim.step(inputs)
		Runner.T.ok(tank["burning"], "%dP: overlapping fuse barrels ignite the hull" % crew_size)
		for pi in crew_size:
			Runner.T.ok(sim.players[pi]["alive"],
				"%dP rider %d survives both impacts in the ignition batch" % [crew_size, pi + 1])
		Runner.T.eq(tank["crew_ring_ticks"], SimWorld.TANK_IGNITION_GRACE_TICKS,
			"%dP: barrel batch preserves the full deadline" % crew_size)
		_shell_the_hull(sim, tank)
		sim.step(inputs)
		for pi in crew_size:
			Runner.T.ok(not sim.players[pi]["alive"],
				"%dP rider %d is exposed to next-tick ordnance" % [crew_size, pi + 1])


func _boundary_kamikaze_bunker(tank: Dictionary) -> Dictionary:
	# Expanded bunker contact begins exactly one northward tank step away.
	return {"x": tank["x"] - SimWorld.BUNKER_W / 2,
		"y": tank["y"] - SimWorld.TANK_SPEED - SimWorld.BUNKER_H - SimWorld.TANK_KAMIKAZE_PAD,
		"alive": true, "spawn_cd": 999999}


func test_grace_one_committed_kamikaze_ejects_driver_and_gunner_before_ring() -> void:
	for crew_size in [1, 2]:
		var sim := SimWorld.new(3, crew_size)
		sim.enemies.clear()
		var tank := _park_tank(sim, sim.players[0]["x"], sim.players[0]["y"])
		if crew_size == 1:
			_board(sim, tank)
		else:
			_board_two(sim, tank)
		sim._ignite_tank(tank, true)
		tank["crew_ring_ticks"] = 1
		var bunker := _boundary_kamikaze_bunker(tank)
		sim.bunkers.append(bunker)
		Runner.T.ok(not sim._point_in_aabb_expanded(tank["x"], tank["y"], bunker,
			SimWorld.TANK_KAMIKAZE_PAD),
			"%dP fixture starts outside bunker contact" % crew_size)
		var drive := SimInput.new()
		drive.move_y = -256
		var inputs: Array = [drive] if crew_size == 1 else [drive, _idle()]
		sim.step(inputs)
		Runner.T.ok(not bunker["alive"] and not tank["alive"],
			"%dP: the committed boundary contact completes the kamikaze" % crew_size)
		Runner.T.eq(tank["crew_ring_ticks"], -1,
			"%dP: tank destruction disarms the superseded crew ring" % crew_size)
		for pi in crew_size:
			Runner.T.ok(sim.players[pi]["alive"] and sim.players[pi]["in_tank"] == -1,
				"%dP rider %d is cinematically ejected before the ring" % [crew_size, pi + 1])
			Runner.T.ok(sim.players[pi]["boost_ticks"] > 0,
				"%dP rider %d receives the documented escape boost" % [crew_size, pi + 1])


func test_no_damage_predicate_gates_on_merely_being_in_a_tank() -> void:
	## CLASS ratchet, derived from the source: a 9th hazard added tomorrow that
	## copies the `p["in_tank"] < 0` idiom next to its _hurt_player call goes red
	## the day it lands. Matching only `<` / `>=` left a hole — mutation-verified
	## 2026-07-26: rewriting the strike guard as `p["in_tank"] == -1` scraped
	## CLEAN, and only the sibling _exposed() count noticed. Comparisons against a
	## NEGATIVE literal are matched too; the bail-expiry loop's legitimate
	## `players[ci]["in_tank"] == ti` cannot look like one (no leading minus).
	const BAD_GUARDS := ["in_tank\"] <", "in_tank\"] >=", "in_tank\"] == -", "in_tank\"] != -"]
	## _exposed() coverage is asserted PER FUNCTION rather than as one global
	## floor: a floor decays the moment a 10th call site is added, because one
	## site can then regress while the total still reads 9.
	const GUARDED_BY_EXPOSED := {
		"_step_contact_deaths": 1,   # rusher contact
		"_hurt_player": 1,           # the authoritative copy
		"_detonate_barrel": 1,
		"_step_mines": 2,            # landmine + vent jet
		"_step_mast_hazard": 1,
		"_step_colossus": 1,         # treads
		"_step_enemy_bullets": 1,
		"_resolve_strikes": 1,       # artillery
	}
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	Runner.T.ok(src.length() > 0, "read sim_world.gd for the predicate scrape")
	var lines := src.split("\n")
	var violations: Array[String] = []
	var per_func := {}
	var fn := ""
	for n in lines.size():
		var line: String = lines[n]
		if line.begins_with("func "):
			fn = line.substr(5).split("(")[0]
			continue
		if line.contains("_exposed("):
			per_func[fn] = int(per_func.get(fn, 0)) + 1
		if not (line.contains("_hurt_player(") or line.contains("_kill_player(")):
			continue
		# The guard for a lethal predicate lives within the enclosing if/for
		# header; 14 lines back covers the longest of the 8 (contact, 9 lines).
		var lo: int = maxi(0, n - 14)
		for k in range(lo, n + 1):
			var w: String = lines[k]
			for bad in BAD_GUARDS:
				if w.contains(bad):
					violations.append("line %d guards %s with `%s`" % [k + 1, line.strip_edges(), w.strip_edges()])
	Runner.T.eq(violations.size(), 0,
		"no damage predicate gates on merely being in a tank: %s" % [violations])
	for f in GUARDED_BY_EXPOSED:
		Runner.T.ok(int(per_func.get(f, 0)) >= int(GUARDED_BY_EXPOSED[f]),
			"%s() still routes its damage through _exposed() x%d (found %d)"
				% [f, GUARDED_BY_EXPOSED[f], per_func.get(f, 0)])


func test_attract_bot_bails_a_burning_tank() -> void:
	## demo_input drives the TITLE attract screen and every movie capture. It
	## never pressed interact while mounted, so post-fix the attract screen would
	## cremate its own bot on the menu.
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	Runner.T.ok(p["in_tank"] >= 0, "bot fixture: player is aboard")
	var ms: Script = load("res://src/main.gd")
	var healthy: SimInput = ms.demo_input(0, sim)
	Runner.T.ok(not healthy.interact, "bot stays aboard a HEALTHY tank")
	sim._ignite_tank(tank)
	var bailing := false
	for t in 20:
		if ms.demo_input(t, sim).interact:
			bailing = true
			break
	Runner.T.ok(bailing, "bot presses interact once the hull it rides is burning")

	# ...but a wreck with a bunker in reach is SPENT, not abandoned. Bailing
	# blind cost seed 1 its finish (9,642 -> never in 30,000): the bot's only
	# gate-cracking tool used to be the tank it was now jumping out of.
	var rsim := SimWorld.new(3, 1)
	var rp := rsim.players[0]
	var rtank := _park_tank(rsim, rp["x"], rp["y"])
	_board(rsim, rtank)
	rsim.bunkers.append({"x": rtank["x"] + 60 * Fixed.ONE, "y": rtank["y"] - 20 * Fixed.ONE,
		"alive": true})
	rsim._ignite_tank(rtank)
	var ram: SimInput = ms.demo_input(0, rsim)
	Runner.T.ok(not ram.interact, "bot does NOT abandon a wreck with a bunker in reach")
	Runner.T.ok(ram.move_x > 0, "bot drives the burning hull AT the bunker (kamikaze verb)")


func test_manned_hull_eats_enemy_rounds_and_the_ride_pays_for_them() -> void:
	## THE TANK COSTS SOMETHING TO HOLD. Enemy rounds used to pass straight
	## THROUGH an occupied hull — the crew was immune and the ride cost nothing,
	## which is why a rider measured 0 knockdowns in 8,038 mounted ticks once the
	## bot learned to bail. The armor still eats the round (that is what armor is
	## for); the round now eats a second of the ride, so a tank parked in a
	## firefight burns down to its bail window instead of sitting there forever.
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	var fuel0: int = tank["fuel"]
	sim.enemy_bullets.append({"x": tank["x"], "y": tank["y"], "vx": 0, "vy": 0,
		"ttl": SimWorld.ENEMY_BULLET_TTL_TICKS})
	sim.step([_idle()])
	Runner.T.ok(p["alive"] and p["hurt_iframes"] == 0,
		"the crew is untouched — armor still absorbs the round")
	Runner.T.eq(sim.enemy_bullets.size(), 0, "the manned hull CONSUMED the round (it is cover now)")
	Runner.T.eq(fuel0 - tank["fuel"], SimWorld.TANK_HIT_FUEL_COST + 1,
		"...and the round cost the ride TANK_HIT_FUEL_COST fuel (+1 idle burn)")

	# A BURNING hull is deliberately not cover: the round reaches the exposed crew.
	var bsim := SimWorld.new(3, 1)
	bsim.enemies.clear()
	var bp := bsim.players[0]
	var btank := _park_tank(bsim, bp["x"], bp["y"])
	_board(bsim, btank)
	bsim._ignite_tank(btank)
	bsim.enemy_bullets.append({"x": btank["x"], "y": btank["y"], "vx": 0, "vy": 0,
		"ttl": SimWorld.ENEMY_BULLET_TTL_TICKS})
	bsim.step([_idle()])
	Runner.T.ok(not bp["alive"], "a BURNING hull is not cover — the round reaches the crew")


func test_ordnance_that_brews_the_hull_schedules_a_crew_ring_but_running_dry_does_not() -> void:
	## The two ignition causes are deliberately NOT symmetric, and both halves
	## are pinned here so neither can drift:
	##   ordnance -> one hit on crew who stay aboard through the warning grace
	##     (vest rules). A prompt bail avoids it.
	##   fuel-out -> nothing. Running dry is your own clock, the fuel bar
	##     telegraphs it, and the free bail is what keeps the tank a tool rather
	##     than a death sentence.
	var sim := SimWorld.new(3, 1)
	sim.enemies.clear()
	var p := sim.players[0]
	var tank := _park_tank(sim, p["x"], p["y"])
	_board(sim, tank)
	p["vest"] = true
	sim.strikes.append({"x": tank["x"], "y": tank["y"], "ticks": 1, "obs": false})
	for i in 4:
		sim.step([_idle()])
		if tank["burning"]:
			break
	Runner.T.ok(tank["burning"], "the shell brewed the hull")
	Runner.T.ok(p["alive"] and p["vest"], "ordnance ignition first grants the measured escape grace")
	for i in SimWorld.TANK_IGNITION_GRACE_TICKS:
		sim.step([_idle()])
	Runner.T.ok(p["alive"] and not p["vest"], "remaining aboard through the grace rings the crew once")

	var fsim := SimWorld.new(3, 1)
	fsim.enemies.clear()
	var fp := fsim.players[0]
	var ftank := _park_tank(fsim, fp["x"], fp["y"])
	_board(fsim, ftank)
	fp["vest"] = true
	ftank["fuel"] = 1
	fsim.step([_idle()])
	Runner.T.ok(ftank["burning"], "running dry still brews the hull")
	Runner.T.ok(fp["alive"] and fp["vest"],
		"...but running dry does NOT ring the crew — the bail window stays a real escape")
