extends RefCounted
## The Bridge Gunship: the first mini-boss. Bullets chip, grenades chunk,
## its death is the only key to a bridge gate.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func _inject_boss_gate(sim: SimWorld) -> Dictionary:
	## Boss bridge placed inside the current view so it engages immediately.
	var gy: int = sim.camera_top + 100 * Fixed.ONE
	var gate := {"y": gy, "open": false, "b1": {}, "b2": {},
		"boss": {"alive": true, "hp": SimWorld.BOSS_HP, "x": 320 * Fixed.ONE,
			"dir": 1, "phase_t": 0, "gate_y": gy}}
	sim.gates.append(gate)
	return gate


func test_boss_gate_streams_every_third() -> void:
	var sim := SimWorld.new(41, 1)
	# Stream enough world for 3 gates by faking deep camera advance.
	sim.camera_top = -(3200 * Fixed.ONE)
	sim.step([_idle()])
	var boss_gates := 0
	var arena_gates := 0
	for g in sim.gates:
		if g["boss"].is_empty():
			arena_gates += 1
		else:
			boss_gates += 1
	Runner.T.ok(boss_gates >= 1, "a boss bridge streamed in (got %d)" % boss_gates)
	Runner.T.ok(arena_gates >= 2, "regular arena gates still stream (got %d)" % arena_gates)


func test_bullets_chip_grenades_chunk() -> void:
	var sim := SimWorld.new(41, 1)
	var gate := _inject_boss_gate(sim)
	var boss: Dictionary = gate["boss"]
	# The exact hit path _step_bullets consults, with a bullet on the hull.
	var hit: bool = sim._bullet_hits_boss({"x": boss["x"], "y": boss["gate_y"] - SimWorld.BOSS_Y_OFFSET})
	Runner.T.ok(hit, "bullet on the hull registers")
	Runner.T.eq(boss["hp"], SimWorld.BOSS_HP - 1, "one bullet chips 1 HP")
	# A miss well off the hull does not register.
	var miss: bool = sim._bullet_hits_boss({"x": boss["x"] + 100 * Fixed.ONE, "y": boss["gate_y"]})
	Runner.T.ok(not miss, "wide shot misses the boss")
	# A grenade burst next to it chunks it.
	sim._explode(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
	Runner.T.eq(boss["hp"], SimWorld.BOSS_HP - 1 - SimWorld.BOSS_GRENADE_DAMAGE, "grenade chunks 8 HP")


func test_boss_death_opens_gate_and_pays() -> void:
	var sim := SimWorld.new(41, 1)
	var gate := _inject_boss_gate(sim)
	var boss: Dictionary = gate["boss"]
	var chest_before := sim.war_chest
	sim._damage_boss(boss, SimWorld.BOSS_HP)
	Runner.T.ok(not boss["alive"], "boss down")
	Runner.T.eq(sim.war_chest, chest_before + SimWorld.BOSS_BOUNTY, "boss bounty minted")
	sim.step([_idle()])
	Runner.T.ok(gate["open"], "bridge opened on boss death")
	Runner.T.eq(sim.last_gate_y, gate["y"], "bridge is the new checkpoint")


func test_strafe_sprays_and_volley_strikes() -> void:
	var sim := SimWorld.new(41, 1)
	var gate := _inject_boss_gate(sim)
	var boss: Dictionary = gate["boss"]
	var start_x: int = boss["x"]
	# First half of the cycle: strafing spray.
	for i in 60:
		sim.step([_idle()])
	Runner.T.ok(boss["x"] != start_x, "boss strafes during the first half-cycle")
	Runner.T.ok(sim.enemy_bullets.size() > 0 or not sim.players[0]["alive"], "spray produced enemy fire")
	# Jump to the volley phase and cross the strike timestamps.
	boss["phase_t"] = 199
	var strikes_before := sim.strikes.size()
	sim.step([_idle()])
	Runner.T.ok(sim.strikes.size() > strikes_before, "mortar volley called a tracked strike (t=200)")


func test_enemy_bullet_kills_and_roll_dodges() -> void:
	var sim := SimWorld.new(41, 1)
	var p := sim.players[0]
	sim.enemy_bullets.append({"x": p["x"], "y": p["y"] - 4 * Fixed.ONE,
		"vx": 0, "vy": Fixed.ONE, "ttl": 60})
	sim.step([_idle()])
	Runner.T.ok(not p["alive"], "enemy bullet is a one-hit kill")
	# Same setup, but rolling through it.
	var sim2 := SimWorld.new(41, 1)
	var p2 := sim2.players[0]
	sim2.enemy_bullets.append({"x": p2["x"], "y": p2["y"] - 4 * Fixed.ONE,
		"vx": 0, "vy": Fixed.ONE, "ttl": 60})
	var roll := SimInput.new()
	roll.roll = true
	roll.move_x = 256
	sim2.step([roll])
	Runner.T.ok(p2["alive"], "roll i-frames dodge enemy fire")