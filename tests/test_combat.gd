extends RefCounted
## Player combat/survival states: roll i-frames, the empty-clip bash and its
## cooldown, ally/self revive, and the broke-fallback timer's interaction with
## a manual revive. (The Flak Vest one-hit absorb + its VEST_IFRAME_TICKS
## mercy window are already covered directly by test_endless.gd and
## test_gameplay.gd — this suite covers the surrounding states those don't.)

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _pstep(sim: SimWorld, inputs: Array) -> void:
	## Contact death no longer lives at the tail of _step_players — hitbox
	## fairness moved it to its own late pass (_step_contact_deaths), which
	## step() runs AFTER the player's bullets/grenades resolve so a rusher your
	## own round killed this tick can no longer kill you. Tests that drive
	## _step_players directly must drive the contact pass too, or they measure a
	## player who can never die by touch — exactly the silently-green shape the
	## stub-parity gate exists to catch.
	sim._step_players(inputs)
	sim._step_contact_deaths()


func test_roll_iframes_block_contact_damage_then_expire() -> void:
	# A rolling player is immune to contact damage for every tick that actually
	# executes roll movement — including the final active-roll tick, where
	# roll_ticks decrements to 0 but the player still moved at roll speed this
	# tick. The `roll_iframe` flag is set for the duration of that movement (set
	# true right after the decrement, cleared at the top of next tick), so the
	# contact-kill guards read "was this tick a roll-move tick", not the
	# post-decrement roll_ticks value. Protection lapses only once roll has
	# fully ended — i.e. the tick *after* the last roll-move tick.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	sim.enemies.clear()
	sim._spawn_enemy(p["x"], p["y"], false)   # enemy exactly on the player
	var e := sim.enemies[sim.enemies.size() - 1]
	var roll := SimInput.new()
	roll.move_x = 256
	roll.roll = true
	_pstep(sim, [roll])
	Runner.T.ok(p["roll_ticks"] > 0, "roll triggered")
	Runner.T.ok(p["alive"], "mid-roll i-frames: the triggering tick's contact did not kill")
	var idle := SimInput.new()
	while p["roll_ticks"] > 1:
		e["x"] = p["x"]
		e["y"] = p["y"]
		_pstep(sim, [idle])
	Runner.T.ok(p["alive"], "player survived every roll tick except the last")
	# Final active-roll tick: roll_ticks decrements to 0 THIS tick, but the
	# player still executed roll movement this tick, so i-frames still protect.
	e["x"] = p["x"]
	e["y"] = p["y"]
	_pstep(sim, [idle])
	Runner.T.eq(p["roll_ticks"], 0, "roll has ended")
	Runner.T.ok(p["alive"], "the final active-roll tick is still protected")
	# One more idle tick: roll has fully ended (no roll-move happened this
	# tick), so contact damage resumes.
	e["x"] = p["x"]
	e["y"] = p["y"]
	_pstep(sim, [idle])
	Runner.T.ok(not p["alive"], "contact damage resumes once the roll fully ends")


func test_bash_cooldown_leaves_player_vulnerable_to_second_attacker() -> void:
	# Empty-clip bash kills one adjacent enemy but arms BASH_COOLDOWN_TICKS;
	# a second attacker closing in during that window is not bashable and
	# still lands a normal contact kill.
	var sim := SimWorld.new(5, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	sim._spawn_enemy(p["x"] + 12 * Fixed.ONE, p["y"], false)   # within BASH_RADIUS (16)
	var e1 := sim.enemies[sim.enemies.size() - 1]
	var inp := SimInput.new()
	inp.fire = true
	_pstep(sim, [inp])
	Runner.T.ok(not e1["alive"], "first bash kills the adjacent enemy")
	Runner.T.eq(p["fire_cd"], SimWorld.BASH_COOLDOWN_TICKS, "bash arms its long cooldown")
	Runner.T.ok(p["alive"], "player survives the bash tick")
	sim._spawn_enemy(p["x"] + 5 * Fixed.ONE, p["y"], false)   # well within touch range too
	var e2 := sim.enemies[sim.enemies.size() - 1]
	_pstep(sim, [inp])
	Runner.T.ok(e2["alive"], "bash cooldown blocks a second melee kill")
	Runner.T.ok(not p["alive"], "no bash + no ammo + contact = death during the cooldown window")


func test_empty_clip_bash_never_executes_the_rescue_pilot() -> void:
	# The bash's auto-kill ring took the first _enemy_strikeable thing inside
	# BASH_RADIUS with no friend/objective check — and the downed pilot is
	# strikeable. Every other kill path in the sim already exempts him
	# (_explode, the airstrike wipe, the tank treads, which rescue instead);
	# only the bash did not. Worse, the bash runs EARLIER in _step_players than
	# the on-foot rescue grab, and BASH_RADIUS (16) is wider than
	# PILOT_RESCUE_RADIUS (14) — so an on-foot approach made dry executed the
	# 100-coin objective at every distance, and the rescue scan then found a
	# corpse. Measured on the war chest, not on a source constant.
	var sim := SimWorld.new(5, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	sim.enemies.append({"x": p["x"] + 10 * Fixed.ONE, "y": p["y"], "alive": true,
		"elite": false, "kind": "pilot", "submerged": false, "surface_ticks": 0})
	var chest_before: int = sim.war_chest
	var inp := SimInput.new()
	inp.fire = true
	sim._step_players([inp])
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.PILOT_RANSOM,
		"a dry-mag walk onto the pilot pays the ransom instead of executing him")
	Runner.T.eq(p["fire_cd"], 0, "no bash happened, so the bash cooldown never armed")
	var rescued := false
	for ev in sim.events:
		if ev.get("t") == "pilot_rescued":
			rescued = true
	Runner.T.ok(rescued, "the tick emits pilot_rescued, not a bash kill")
	# And the bash still works past him: a real hostile sharing the ring dies.
	var sim2 := SimWorld.new(5, 1, "campaign")
	var p2 := sim2.players[0]
	p2["mg_ammo"] = 0
	sim2.enemies.clear()
	# Pilot listed FIRST so the scan must skip him to reach the rusher.
	sim2.enemies.append({"x": p2["x"] + 15 * Fixed.ONE, "y": p2["y"], "alive": true,
		"elite": false, "kind": "pilot", "submerged": false, "surface_ticks": 0})
	sim2._spawn_enemy(p2["x"] + 12 * Fixed.ONE, p2["y"], false)
	var rusher := sim2.enemies[sim2.enemies.size() - 1]
	sim2._step_players([inp])
	Runner.T.ok(not rusher["alive"], "the bash still reaches the hostile behind the pilot")
	Runner.T.ok(sim2.enemies[0]["alive"],
		"and the pilot in the 14..16px annulus (bashable, not yet grabbable) is left standing")


func test_bash_routes_through_the_same_armour_rules_as_a_bullet() -> void:
	# The bash consulted NEITHER armour rule the bullet path owns: not the
	# shieldman's front arc (_shield_blocks) and not `hp > 1`. One free rifle
	# butt therefore deleted a 3-hp MG nest and a head-on shieldman — the only
	# free, unlimited, zero-resource one-shot in the game. Grenades/mines/
	# airstrikes still one-shot BY DESIGN (they cost a resource).
	var inp := SimInput.new()
	inp.fire = true

	# ARMOUR: a 3-hp MG nest.
	var a := SimWorld.new(5, 1, "campaign")
	a.players[0]["mg_ammo"] = 0
	a.enemies.clear()
	a._spawn_mg_nest(a.players[0]["x"] + 12 * Fixed.ONE, a.players[0]["y"])
	var nest: Dictionary = a.enemies[0]
	a._step_players([inp])
	Runner.T.ok(nest["alive"], "one rifle butt does not delete a 3-hp MG nest")
	Runner.T.eq(int(nest["hp"]), 2, "the bash chips exactly one point of armor")
	Runner.T.eq(int(a.players[0]["fire_cd"]), SimWorld.BASH_COOLDOWN_TICKS,
		"a blocked swing still costs the cooldown — same grammar as a bullet dying on armor")

	# SHIELD ARC: a shieldman facing the basher.
	var b := SimWorld.new(5, 1, "campaign")
	b.players[0]["mg_ammo"] = 0
	b.enemies.clear()
	b._spawn_special(b.players[0]["x"] + 12 * Fixed.ONE, b.players[0]["y"], "shield")
	var sh: Dictionary = b.enemies[0]
	b._step_players([inp])
	Runner.T.ok(sh["alive"], "a front-arc shieldman eats the rifle butt, same as a bullet")


func test_empty_clip_out_of_bash_range_only_dry_fires() -> void:
	# An empty-clip fire with no enemy in melee reach is a whiff, not a bash:
	# it emits dry_fire and never arms the bash cooldown.
	var sim := SimWorld.new(5, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	sim._spawn_enemy(p["x"] + 40 * Fixed.ONE, p["y"], false)   # outside BASH_RADIUS (16)
	var e := sim.enemies[sim.enemies.size() - 1]
	var inp := SimInput.new()
	inp.fire = true
	sim._step_players([inp])
	Runner.T.ok(e["alive"], "enemy out of bash range survives the empty-clip swing")
	var dry := false
	for ev in sim.events:
		if ev.get("t") == "dry_fire":
			dry = true
	Runner.T.ok(dry, "an out-of-range empty-clip fire emits dry_fire, not a bash")
	Runner.T.eq(p["fire_cd"], 0, "a whiffed dry-fire does not arm the bash cooldown")


func test_ally_revive_lands_the_partner_at_the_reviver_and_restores_ammo() -> void:
	# WAS test_ally_revive_snaps_y_to_reviver_keeps_x..., and the old name stated the
	# defect as if it were the design: "repositions onto the reviver's Y line — but leaves
	# their X exactly where they fell". "At their side" is BOTH axes. Snapping y alone stood
	# the partner up on the rescuer's ROW at the x where they DIED — up to the full 608px
	# arena away (WORLD_LEFT 16 .. WORLD_RIGHT 624), which in practice is the flank squad or
	# the bunker that just killed them. The chest paid 50-150 to drop a stripped, vestless
	# body back into its own killer.
	# Found twice, independently: a round-1 audit lens filed it as a defect, and a skeptic
	# reviewing an external report used the SAME fact to REJECT a proposed HUD string
	# ("RALLY P2 TO YOU") as a lie the sim could not honour. Fixing the sim is what makes
	# that string honest — so this assertion flipping is the point, not a casualty.
	var sim := SimWorld.new(3, 2, "campaign")
	var p1 := sim.players[0]
	var p2 := sim.players[1]
	var x1_before: int = p1["x"]
	sim.war_chest = 500
	p1["grenade_ammo"] = 0
	sim._kill_player(p1)
	var cost := sim.revive_cost(p1)
	var chest0 := sim.war_chest
	var revive := SimInput.new()
	revive.revive = true
	sim._step_players([_idle(), revive])
	Runner.T.ok(p1["alive"], "ally revive brings the partner back")
	Runner.T.eq(chest0 - sim.war_chest, cost, "revive spent exactly revive_cost from the shared chest")
	Runner.T.eq(p1["y"], p2["y"], "revived player snaps to the reviver's Y line")
	Runner.T.eq(p1["x"], p2["x"], "...and to their X — a rescue puts you at their SIDE, not just their row")
	Runner.T.ok(p1["x"] != x1_before or p2["x"] == x1_before,
		"the corpse's x is genuinely abandoned (guards against a vacuous pass when both happen to match)")
	Runner.T.eq(p1["grenade_ammo"], 4, "death/revive restores a PARTIAL 4 grenades")
	Runner.T.ok(p1["hurt_iframes"] > 0, "revive grants a post-spawn mercy window")


func test_broke_countdown_can_be_beaten_by_a_late_revive() -> void:
	# The broke-fallback timer is a background clock, not an exclusive lock:
	# a manual revive is still evaluated every tick while it counts down, so
	# topping up the chest mid-countdown revives immediately instead of
	# waiting out the full BROKE_RESPAWN_TICKS.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	sim.war_chest = 0
	sim._kill_player(p)
	# All-loops batch: dying broke arms the timer on its own (no press required —
	# the endless wipe, the only run-ender, must never hang on an idle pad).
	# _step_dead_player owns the arming now, and re-checks it every tick, so a
	# partner emptying the shared chest under a downed body arms it too.
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive])
	Runner.T.ok(p["broke_timer"] > 0, "dying broke auto-arms the fallback timer")
	Runner.T.ok(not p["alive"], "broke: first revive attempt denied")
	Runner.T.ok(p["broke_timer"] > 0 and p["broke_timer"] < SimWorld.BROKE_RESPAWN_TICKS,
		"the countdown is running (a denied press does not reset it)")
	sim.war_chest = sim.revive_cost(p)
	sim.step([revive])
	Runner.T.ok(p["alive"], "a funded revive press succeeds on the very next tick")
	Runner.T.eq(p["broke_timer"], 0, "the successful revive cancels the countdown")


func test_post_respawn_mercy_window_blocks_immediate_recontact() -> void:
	# _respawn grants VEST_IFRAME_TICKS of mercy on every revive (not just a
	# vest break): standing back into an enemy the instant you spawn does not
	# kill you again, until the window lapses.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	sim.war_chest = 500
	sim._kill_player(p)
	var revive := SimInput.new()
	revive.revive = true
	_pstep(sim, [revive])
	Runner.T.ok(p["alive"], "self-revive succeeded")
	Runner.T.eq(p["hurt_iframes"], SimWorld.VEST_IFRAME_TICKS, "respawn grants the full post-spawn mercy window")
	sim.enemies.clear()
	sim._spawn_enemy(p["x"], p["y"], false)   # standing exactly on the fresh spawn
	var idle := SimInput.new()
	_pstep(sim, [idle])
	Runner.T.ok(p["alive"], "mercy window absorbs the immediate re-contact with no vest needed")
	for i in SimWorld.VEST_IFRAME_TICKS:
		_pstep(sim, [idle])
		if not p["alive"]:
			break
	Runner.T.ok(not p["alive"], "contact damage resumes once the mercy window lapses")


func test_rock_pre_reject_bound_actually_bounds_every_rock_kind() -> void:
	# _step_bullets axis-pre-rejects rocks on ROCK_HALF_W_MAX before paying the
	# two per-pair static-func lookups (_rk_solid + _rk_hw). That is checksum-
	# neutral ONLY while the constant really is an upper bound on _rk_hw for every
	# kind — add a wider tier to ROCK_KIND_EXT without bumping it and the scan
	# starts silently eating armor_blocks and kind-2 crack accrual, with no test
	# and no engine error to say so. Derived from the table, never restated.
	var widest := 0
	for ext in SimWorld.ROCK_KIND_EXT:
		widest = maxi(widest, int(ext[0]))
	Runner.T.eq(SimWorld.ROCK_HALF_W_MAX, widest * SimWorld.F_ONE,
		"ROCK_HALF_W_MAX bounds the widest ROCK_KIND_EXT half-width")
	Runner.T.ok(SimWorld.SANDBAG_HALF_W >= SimWorld.SANDBAG_HALF_H,
		"the sandbag scans pre-reject on HALF_W, so it must dominate both orientations")
	# And the widest tier still blocks at its own edge — the bound is not off by one.
	var sim := SimWorld.new(3, 1, "campaign")
	sim.rocks.clear()
	sim.bullets.clear()
	var rx: int = sim.players[0]["x"] + 200 * SimWorld.F_ONE
	var ry: int = sim.players[0]["y"] - 40 * SimWorld.F_ONE
	sim.rocks.append({"x": rx, "y": ry, "kind": 2})
	# Stage a REAL bullet: _step_bullets reads b["ttl"] unconditionally (it decrements
	# before the off-band check), so a hand-rolled dict missing that key aborts the whole
	# stepper on a bad-key access and every later assertion in this method silently stops
	# running — which is exactly how this test first "failed" against a correct fix.
	# Schema mirrors the real fire path at sim_world.gd:4405. `pierce`/`rend` are not
	# bullet fields at all.
	sim.bullets.append({"x": rx + widest * SimWorld.F_ONE, "y": ry,
		"vx": 0, "vy": 0, "ttl": SimWorld.BULLET_TTL_TICKS, "owner": 0})
	sim._step_bullets()
	var blocked := false
	for ev in sim.events:
		if ev.get("t", "") == "armor_block":
			blocked = true
	Runner.T.ok(blocked, "a round exactly on the widest rock's edge is still blocked")
