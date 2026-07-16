extends RefCounted
## Core mechanics: the 1986 grammar the sim must honor.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _inputs(p1: SimInput, p2: SimInput = null) -> Array:
	return [p1] if p2 == null else [p1, p2]


func test_fire_consumes_ammo_and_spawns_bullet() -> void:
	var sim := SimWorld.new(1, 1)
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	sim.step(_inputs(inp))
	Runner.T.eq(sim.bullets.size(), 1, "one bullet after first fire tick")
	Runner.T.eq(sim.players[0]["mg_ammo"], SimWorld.MG_AMMO_MAX - 1, "fire consumed one round")
	sim.step(_inputs(inp))
	Runner.T.eq(sim.bullets.size(), 2 - 1, "cooldown blocks second bullet on next tick")
	Runner.T.ok(sim.bullets[0]["vy"] < 0, "bullet travels up (aim up)")


func test_ammo_floor_no_fire_at_zero() -> void:
	var sim := SimWorld.new(1, 1)
	sim.players[0]["mg_ammo"] = 0
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	sim.step(_inputs(inp))
	Runner.T.eq(sim.bullets.size(), 0, "no bullets at zero MG ammo")


func test_bullet_kills_rusher() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim._spawn_enemy(p["x"], p["y"] - 60 * Fixed.ONE, false)
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	var chest_before := sim.war_chest
	for i in 30:
		sim.step(_inputs(inp if i == 0 else _idle()))
	Runner.T.ok(sim.enemies.is_empty() or not sim.enemies[0]["alive"], "rusher dead within 30 ticks")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.COIN_RUSHER, "kill minted rusher coin to War Chest")


func test_bunker_blocks_bullets_grenade_destroys() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	var bunker := {
		"x": p["x"] - 24 * Fixed.ONE, "y": p["y"] - 80 * Fixed.ONE,
		"alive": true, "spawn_cd": 999999,
	}
	sim.bunkers.append(bunker)
	# Bullets: blocked, bunker survives.
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	for i in 40:
		sim.step(_inputs(fire))
	Runner.T.ok(bunker["alive"], "bunker survives sustained MG fire (armor grammar)")
	Runner.T.ok(sim.bullets.is_empty(), "bullets absorbed by bunker, none alive past it")
	# Grenade: arcs and destroys.
	var toss := SimInput.new()
	toss.aim_y = -256
	toss.grenade = true
	var grenades_before: int = sim.players[0]["grenade_ammo"]
	for i in 60:
		sim.step(_inputs(toss if i == 0 else _idle()))
	Runner.T.eq(sim.players[0]["grenade_ammo"], grenades_before - 1, "grenade consumed")
	Runner.T.ok(not bunker["alive"], "grenade destroyed the bunker (grenades-vs-armor)")


func test_one_hit_death_and_ammo_restore() -> void:
	var sim := SimWorld.new(1, 2)
	var p := sim.players[0]
	p["mg_ammo"] = 5
	sim._spawn_enemy(p["x"], p["y"], false)  # contact
	sim.step(_inputs(_idle(), _idle()))
	Runner.T.ok(not p["alive"], "contact with enemy = one-hit death")
	Runner.T.eq(p["deaths"], 1, "death counted")
	# Partner revives; ammo restored per 1986 rule.
	sim.war_chest = 500
	var revive := SimInput.new()
	revive.revive = true
	sim.step(_inputs(_idle(), revive))
	Runner.T.ok(p["alive"], "partner revive brings player back")
	Runner.T.eq(p["mg_ammo"], SimWorld.MG_AMMO_MAX, "death restores MG ammo")


func test_roll_press_buffered_through_cooldown() -> void:
	# An early roll press (within ROLL_BUFFER_TICKS of cooldown end) must queue
	# and fire the moment the roll is ready — not be silently dropped.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	var move := SimInput.new()
	move.move_x = 256
	var roll := SimInput.new()
	roll.move_x = 256
	roll.roll = true
	sim.step(_inputs(roll))
	Runner.T.ok(p["roll_ticks"] > 0, "first roll triggered")
	while p["roll_cd"] > 5:
		sim.step(_inputs(move))
	sim.step(_inputs(roll))   # pressed 4 ticks early: buffered, not rolling yet
	Runner.T.eq(p["roll_ticks"], 0, "early press does not roll while on cooldown")
	var fired := false
	for i in SimWorld.ROLL_BUFFER_TICKS:
		sim.step(_inputs(move))   # roll released; only the buffer can fire it
		if p["roll_ticks"] > 0:
			fired = true
			break
	Runner.T.ok(fired, "buffered press fires the roll when the cooldown ends")


func test_ratchet_camera_never_scrolls_back() -> void:
	var sim := SimWorld.new(1, 1)
	var up := SimInput.new()
	up.move_y = -256
	for i in 240:
		sim.step(_inputs(up))
	var top_after_advance := sim.camera_top
	Runner.T.ok(top_after_advance < -SimWorld.VIEW_H, "camera advanced upward with player")
	var down := SimInput.new()
	down.move_y = 256
	for i in 240:
		sim.step(_inputs(down))
	Runner.T.eq(sim.camera_top, top_after_advance, "ratchet: camera never scrolls back down")


func test_elite_skirmisher_telegraphed_shot() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim._spawn_enemy(p["x"], p["y"] - 100 * Fixed.ONE, true)   # inside standoff
	var elite := sim.enemies[sim.enemies.size() - 1]
	elite["fire_cd"] = 1
	sim.step([_idle()])
	Runner.T.ok(elite["windup"] > 0, "elite winds up inside standoff range")
	sim.step([_idle()])
	var ey: int = elite["y"]
	for i in SimWorld.ELITE_WINDUP_TICKS:
		sim.step([_idle()])
	Runner.T.eq(elite["y"], ey, "elite rooted while winding up")
	Runner.T.ok(sim.enemy_bullets.size() >= 1, "wind-up resolved into an aimed shot")


func test_spawner_escalates_with_opened_gates() -> void:
	# Same seed, same ticks: a run with cleared gates must field more spawns.
	var calm := SimWorld.new(5, 1)
	var hot := SimWorld.new(5, 1)
	for i in 3:
		hot.gates.append({"y": -(2000 + i * 1000) * Fixed.ONE, "open": true,
			"b1": {}, "b2": {}, "boss": {}})
	for i in 450:
		calm.step([_idle()])
		hot.step([_idle()])
	Runner.T.ok(hot.enemies.size() > calm.enemies.size(),
		"opened gates tighten the spawn interval (got %d vs %d)" % [hot.enemies.size(), calm.enemies.size()])


func test_elite_drops_pickup() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim._spawn_enemy(p["x"], p["y"] - 40 * Fixed.ONE, true)  # red elite
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	for i in 20:
		sim.step(_inputs(inp if i == 0 else _idle()))
	Runner.T.eq(sim.pickups.size(), 1, "red elite dropped a crate")


func test_kill_streak_bonuses_score_not_chest() -> void:
	# The streak is a leaderboard reward, never an economy pump: the chest mints
	# the flat bounty on every kill; score gets an escalating bonus at 5/10/20.
	var sim := SimWorld.new(7, 1)
	var base := SimWorld.COIN_RUSHER * 10
	for k in range(1, 7):
		var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
		sim.enemies.append(e)
		var chest_before := sim.war_chest
		var score_before := sim.score
		sim._kill_enemy(e)
		Runner.T.eq(sim.war_chest - chest_before, SimWorld.COIN_RUSHER,
			"kill %d mints flat rusher coin — streak never touches the chest" % k)
		if k >= 5:
			Runner.T.ok(sim.score - score_before > base, "streak tier adds a score bonus (kill %d)" % k)
		else:
			Runner.T.eq(sim.score - score_before, base, "pre-streak kill %d scores base only" % k)
	# The streak lapses after the window elapses with no further kills.
	for t in SimWorld.KILL_STREAK_WINDOW_TICKS + 1:
		sim.step(_inputs(_idle()))
	Runner.T.eq(sim.kill_streak, 0, "streak lapses after the window with no kills")


func test_landmine_detonates_and_kills_enemy() -> void:
	# An enemy walking onto an armed mine is killed by the blast; the mine disarms.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	sim.mines.clear()
	var mx: int = p["x"] + 200 * Fixed.ONE
	sim.mines.append({"x": mx, "y": p["y"], "armed": true})
	sim._spawn_enemy(mx, p["y"], false)   # enemy standing on the mine
	var enemy := sim.enemies[sim.enemies.size() - 1]
	sim._step_mines()
	Runner.T.ok(not enemy["alive"], "enemy on a mine is killed by the blast")
	Runner.T.ok(sim.mines.is_empty() or not sim.mines[0]["armed"], "mine disarms after detonating")


func test_landmine_kills_player_but_vest_absorbs() -> void:
	# Standing on a mine is lethal — unless a Flak Vest eats the one hit.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	sim.enemies.clear()
	sim.mines = [{"x": p["x"], "y": p["y"], "armed": true}]
	sim._step_mines()
	Runner.T.ok(not p["alive"], "player standing on a mine is killed")
	# With a vest, the same hit is absorbed (mine still detonates).
	var sim2 := SimWorld.new(3, 1, "campaign")
	var p2 := sim2.players[0]
	sim2.enemies.clear()
	p2["vest"] = true
	sim2.mines = [{"x": p2["x"], "y": p2["y"], "armed": true}]
	sim2._step_mines()
	Runner.T.ok(p2["alive"] and not p2["vest"], "vest absorbs the mine hit (player lives, vest gone)")


func test_empty_clip_bash_kills_adjacent_enemy_no_coin() -> void:
	# Out of MG ammo + an enemy in reach + fire = a melee bash: enemy dies, no
	# coin, no bullet. It's the panic counter, not a free weapon.
	var sim := SimWorld.new(5, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	sim._spawn_enemy(p["x"] + 12 * Fixed.ONE, p["y"], false)   # within BASH_RADIUS (16)
	var e := sim.enemies[sim.enemies.size() - 1]
	var chest_before := sim.war_chest
	var inp := SimInput.new()
	inp.fire = true
	sim.step(_inputs(inp))
	Runner.T.ok(not e["alive"], "empty-clip bash kills the adjacent enemy")
	Runner.T.eq(sim.war_chest, chest_before, "bash mints no coin")
	Runner.T.eq(sim.bullets.size(), 0, "bash spends no ammo and spawns no bullet")
	Runner.T.ok(p["alive"], "the bash pre-empts the touch-kill — player survives")


func test_marked_elite_pays_triple_bounty() -> void:
	# A marked bounty elite mints 3× the normal elite coin into the War Chest.
	var sim := SimWorld.new(1, 1, "campaign")
	var chest0 := sim.war_chest
	var e := {"x": 0, "y": 0, "alive": true, "elite": true, "kind": "elite", "marked": true}
	sim.enemies.append(e)
	sim._kill_enemy(e)
	Runner.T.eq(sim.war_chest - chest0, SimWorld.COIN_ELITE * 3, "marked elite pays triple coin")


func test_grenade_frag_bonus_on_multikill() -> void:
	# One blast catching 3+ enemies awards a frag score bonus.
	var sim := SimWorld.new(1, 1, "campaign")
	for k in 4:
		sim.enemies.append({"x": 100 * Fixed.ONE + k, "y": 100 * Fixed.ONE, "alive": true,
			"elite": false, "kind": "rusher"})
	var score0 := sim.score
	sim._explode(100 * Fixed.ONE, 100 * Fixed.ONE)
	var base := SimWorld.COIN_RUSHER * 10 * 4   # four rusher kills, base score
	Runner.T.ok(sim.score - score0 > base, "a 4-kill blast pays a frag bonus over the base kills")


func test_piercing_rounds_punch_through_two_enemies() -> void:
	# With the Piercing Rounds buff active, a single MG bullet kills a line of
	# enemies instead of stopping at the first.
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	p["pierce_ticks"] = 200
	sim.enemies.clear()
	var e1 := {"x": p["x"], "y": p["y"] - 30 * Fixed.ONE, "alive": true, "elite": false, "kind": "rusher"}
	var e2 := {"x": p["x"], "y": p["y"] - 55 * Fixed.ONE, "alive": true, "elite": false, "kind": "rusher"}
	sim.enemies.append(e1)
	sim.enemies.append(e2)
	var fire := SimInput.new()
	fire.aim_y = -256
	fire.fire = true
	sim.step(_inputs(fire))
	var aim := SimInput.new()
	aim.aim_y = -256
	for t in 18:
		sim.step(_inputs(aim))
	Runner.T.ok(not e1["alive"] and not e2["alive"], "one piercing bullet punched through both enemies")


func test_spread_shot_fires_three_bullets() -> void:
	# With the Spread Shot buff, one fire tick spawns a 3-bullet fan (1 ammo).
	var sim := SimWorld.new(3, 1, "campaign")
	var p := sim.players[0]
	p["spread_ticks"] = 200
	var ammo0: int = p["mg_ammo"]
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	sim.step(_inputs(inp))
	Runner.T.eq(sim.bullets.size(), 3, "spread shot spawns a 3-bullet fan")
	Runner.T.eq(p["mg_ammo"], ammo0 - 1, "spread shot still costs one round of ammo")


func test_assist_mode_gives_a_two_hit_vest_each_life() -> void:
	# Assist Mode: every life starts with a flak vest, so the first hit is absorbed.
	var sim := SimWorld.new(3, 1, "campaign")
	sim.assist_mode = true
	var p := sim.players[0]
	p["vest"] = true   # what main._reset issues under assist
	p["hurt_iframes"] = 0
	sim._hurt_player(p)
	Runner.T.ok(p["alive"] and not p["vest"], "assist: first hit breaks the vest, player survives")
	sim._respawn(p, sim.camera_top)
	Runner.T.ok(p["vest"], "assist re-issues a vest on respawn")


func _hard_spawn_count(hard: bool) -> int:
	var sim := SimWorld.new(77, 1, "campaign")
	sim.hard = hard
	for g in 3:
		sim.gates.append({"y": -1000000 * g, "open": true, "b1": {}, "b2": {}, "boss": {}})
	for t in 1200:
		sim._step_spawner()
		sim.tick_count += 1
	return sim.enemies.size()


func test_ng_plus_hard_tightens_the_spawn_curve() -> void:
	Runner.T.ok(_hard_spawn_count(true) > _hard_spawn_count(false),
		"NG+ HARD fields more enemies than the normal campaign curve")


func test_barrels_chain_and_frag_the_pack() -> void:
	# One grenade lights a barrel; the chain now ripples down the line over a
	# short fuse (_step_barrels), not all in one frame — but still frags the pack.
	var sim := SimWorld.new(1, 1)
	var y: int = sim.camera_top + 120 * Fixed.ONE
	sim.barrels.clear()
	sim.enemies.clear()
	var b0 := {"x": 200 * Fixed.ONE, "y": y, "armed": true, "fuse_ticks": 0}
	var b1 := {"x": 218 * Fixed.ONE, "y": y, "armed": true, "fuse_ticks": 0}   # 18px apart < GRENADE_RADIUS
	var b2 := {"x": 236 * Fixed.ONE, "y": y, "armed": true, "fuse_ticks": 0}
	sim.barrels.append(b0)
	sim.barrels.append(b1)
	sim.barrels.append(b2)
	sim.enemies.append({"x": 236 * Fixed.ONE, "y": y, "alive": true, "elite": false, "kind": "rusher"})
	var foe: Dictionary = sim.enemies[0]
	sim._explode(200 * Fixed.ONE, y)   # light the first barrel's fuse
	for i in 40:                       # let the fuse ripple down the cluster
		sim._step_barrels()
	for bl in [b0, b1, b2]:
		Runner.T.ok(not bl["armed"], "the whole barrel line chained (via fuse)")
	Runner.T.ok(not foe["alive"], "the chain reaction fragged the enemy at the far end")


func test_barrel_blast_hurts_a_close_player() -> void:
	# Stand too close to a barrel you detonate and it takes you with it — the
	# fuse makes it rollable, but standing in it once it cooks off still hits.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["vest"] = true
	sim.barrels.clear()
	sim.barrels.append({"x": p["x"] + 10 * Fixed.ONE, "y": p["y"], "armed": true, "fuse_ticks": 0})
	sim._explode(p["x"] + 10 * Fixed.ONE, p["y"])   # light the fuse
	for i in 12:
		sim._step_barrels()
	Runner.T.ok(not p["vest"], "the barrel blast broke the too-close player's vest")


func test_mg_nest_is_rooted_and_bursts() -> void:
	var sim := SimWorld.new(1, 1)
	var ct: int = sim.camera_top
	sim.enemies.clear()
	sim._spawn_mg_nest(320 * Fixed.ONE, ct + 80 * Fixed.ONE)
	var nest: Dictionary = sim.enemies[0]
	var x0: int = nest["x"]
	var y0: int = nest["y"]
	sim.players[0]["x"] = 200 * Fixed.ONE   # in its field of fire, but the nest never chases
	sim.players[0]["y"] = ct + 220 * Fixed.ONE
	var bullets_seen := 0
	for i in 200:
		sim.step(_inputs(_idle()))
		bullets_seen = maxi(bullets_seen, sim.enemy_bullets.size())
	Runner.T.eq(nest["x"], x0, "the MG nest never moves in x")
	Runner.T.eq(nest["y"], y0, "the MG nest never moves in y")
	Runner.T.ok(bullets_seen > 0, "the MG nest rakes the lane with aimed fire")


func test_mg_nest_dies_to_a_grenade() -> void:
	var sim := SimWorld.new(1, 1)
	sim.enemies.clear()
	sim._spawn_mg_nest(300 * Fixed.ONE, sim.camera_top + 90 * Fixed.ONE)
	var nest: Dictionary = sim.enemies[0]
	sim._explode(nest["x"], nest["y"])
	Runner.T.ok(not nest["alive"], "a grenade silences the MG nest")


func test_triple_shot_sprays_three_bullets() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["triple"] = true
	var inp := SimInput.new()
	inp.aim_y = -256   # aim straight up
	inp.fire = true
	sim.step(_inputs(inp))
	Runner.T.eq(sim.bullets.size(), 3, "triple shot fires three bullets on one trigger pull")
	Runner.T.eq(p["mg_ammo"], SimWorld.MG_AMMO_MAX - 1, "the 3-round fan still costs a single round")
	var vmin := 1 << 40
	var vmax := -(1 << 40)
	for b in sim.bullets:
		vmin = mini(vmin, b["vx"])
		vmax = maxi(vmax, b["vx"])
	Runner.T.ok(vmin < 0 and vmax > 0, "the fan spreads left and right of the aim")


func test_triple_pickup_grants_and_death_strips() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim._apply_supply(p, 6)   # kind 6 = Triple Shot (4=pierce, 5=spread already taken)
	Runner.T.ok(p["triple"], "the triple-shot supply kind grants the mod")
	sim._respawn(p, p["y"])   # revive path = the 1986 upgrade strip
	Runner.T.ok(not p["triple"], "death/respawn strips the Triple Shot mod")
