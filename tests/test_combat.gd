extends RefCounted
## Player combat/survival states: roll i-frames, the empty-clip bash and its
## cooldown, ally/self revive, and the broke-fallback timer's interaction with
## a manual revive. (The Flak Vest one-hit absorb + its VEST_IFRAME_TICKS
## mercy window are already covered directly by test_endless.gd and
## test_gameplay.gd — this suite covers the surrounding states those don't.)

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


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
	sim._step_players([roll])
	Runner.T.ok(p["roll_ticks"] > 0, "roll triggered")
	Runner.T.ok(p["alive"], "mid-roll i-frames: the triggering tick's contact did not kill")
	var idle := SimInput.new()
	while p["roll_ticks"] > 1:
		e["x"] = p["x"]
		e["y"] = p["y"]
		sim._step_players([idle])
	Runner.T.ok(p["alive"], "player survived every roll tick except the last")
	# Final active-roll tick: roll_ticks decrements to 0 THIS tick, but the
	# player still executed roll movement this tick, so i-frames still protect.
	e["x"] = p["x"]
	e["y"] = p["y"]
	sim._step_players([idle])
	Runner.T.eq(p["roll_ticks"], 0, "roll has ended")
	Runner.T.ok(p["alive"], "the final active-roll tick is still protected")
	# One more idle tick: roll has fully ended (no roll-move happened this
	# tick), so contact damage resumes.
	e["x"] = p["x"]
	e["y"] = p["y"]
	sim._step_players([idle])
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
	sim._step_players([inp])
	Runner.T.ok(not e1["alive"], "first bash kills the adjacent enemy")
	Runner.T.eq(p["fire_cd"], SimWorld.BASH_COOLDOWN_TICKS, "bash arms its long cooldown")
	Runner.T.ok(p["alive"], "player survives the bash tick")
	sim._spawn_enemy(p["x"] + 5 * Fixed.ONE, p["y"], false)   # well within touch range too
	var e2 := sim.enemies[sim.enemies.size() - 1]
	sim._step_players([inp])
	Runner.T.ok(e2["alive"], "bash cooldown blocks a second melee kill")
	Runner.T.ok(not p["alive"], "no bash + no ammo + contact = death during the cooldown window")


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


func test_ally_revive_snaps_y_to_reviver_keeps_x_and_restores_ammo() -> void:
	# _try_revive spends the shared War Chest, restores the 1986-rule ammo
	# reset, and repositions the downed ally onto the reviver's Y line —
	# but leaves their X exactly where they fell.
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
	Runner.T.eq(p1["x"], x1_before, "revived player's X stays where they fell — only Y snaps")
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
	sim._step_players([revive])
	Runner.T.ok(p["alive"], "self-revive succeeded")
	Runner.T.eq(p["hurt_iframes"], SimWorld.VEST_IFRAME_TICKS, "respawn grants the full post-spawn mercy window")
	sim.enemies.clear()
	sim._spawn_enemy(p["x"], p["y"], false)   # standing exactly on the fresh spawn
	var idle := SimInput.new()
	sim._step_players([idle])
	Runner.T.ok(p["alive"], "mercy window absorbs the immediate re-contact with no vest needed")
	for i in SimWorld.VEST_IFRAME_TICKS:
		sim._step_players([idle])
		if not p["alive"]:
			break
	Runner.T.ok(not p["alive"], "contact damage resumes once the mercy window lapses")
