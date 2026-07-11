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
