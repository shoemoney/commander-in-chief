extends RefCounted
## Endless-roster archetype behaviors: shield front-arc, sniper paint-lock,
## grenadier telegraphed lob, frogman re-submerge. Not covered by
## test_gameplay/test_water/test_endless.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_shield_blocks_front_arc_but_dies_from_behind() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 0
	sim.enemies.clear()
	# Shieldman sits above the player, facing down toward him (front = toward player).
	var e := {"x": 0, "y": -50 * Fixed.ONE, "alive": true, "elite": true, "kind": "shield"}
	sim.enemies.append(e)
	# A player shot travels UP into the enemy's front (the side facing the player).
	sim.bullets.append({"x": e["x"], "y": e["y"], "vx": 0, "vy": -SimWorld.BULLET_SPEED, "ttl": 60})
	sim._step_bullets()
	Runner.T.ok(sim.bullets.is_empty(), "front-arc bullet is consumed by the shield")
	Runner.T.ok(e["alive"], "shieldman survives a frontal hit")
	# A bullet arriving from behind (same direction the shield faces) is not blocked.
	sim.bullets.append({"x": e["x"], "y": e["y"], "vx": 0, "vy": SimWorld.BULLET_SPEED, "ttl": 60})
	sim._step_bullets()
	Runner.T.ok(not e["alive"], "a bullet into the shieldman's back kills him")


func test_sniper_shot_follows_locked_paint_vector_not_new_player_pos() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 200 * Fixed.ONE
	sim.enemies.clear()
	# Paint already locked straight down at the player's old spot (aim_lx/ly),
	# with windup at its last tick.
	var e := {"x": 0, "y": 0, "alive": true, "elite": true, "kind": "sniper",
		"fire_cd": SimWorld.SNIPER_FIRE_CD_TICKS, "windup": 1,
		"aim_lx": 0, "aim_ly": 200 * Fixed.ONE}
	sim.enemies.append(e)
	p["x"] = 300 * Fixed.ONE   # sidestep AFTER the paint locked
	sim.step([_idle()])
	Runner.T.eq(sim.enemy_bullets.size(), 1, "windup hitting zero fires exactly one bullet")
	var b := sim.enemy_bullets[0]
	Runner.T.eq(b["vx"], 0, "locked vector was straight down: the sidestep added no sideways velocity")
	Runner.T.ok(b["vy"] > 0, "bullet still travels down the locked line, not toward the new player x")


func test_grenadier_lob_lands_on_stood_ground_but_missed_if_player_leaves() -> void:
	var pos_x := 40 * Fixed.ONE
	var pos_y := -100 * Fixed.ONE   # inside the on-screen clamp band at tick 0
	# Case 1: player stands still through the whole telegraph -> takes the hit.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = pos_x
	p["y"] = pos_y
	sim.enemies.clear()
	# Enemy stands off (not stacked on the player, or the ordinary touch-kill
	# check would end the player before the lob ever resolves).
	var e := {"x": pos_x + 60 * Fixed.ONE, "y": pos_y, "alive": true, "elite": true,
		"kind": "grenadier", "fire_cd": SimWorld.GRENADIER_FIRE_CD_TICKS, "windup": 1}
	sim.enemies.append(e)
	sim.step([_idle()])
	Runner.T.eq(sim.strikes.size(), 1, "windup hitting zero lobs a tracked strike")
	Runner.T.eq(sim.strikes[0]["x"], pos_x, "strike lands on the player's x at lob time")
	Runner.T.eq(sim.strikes[0]["y"], pos_y, "strike lands on the player's y at lob time")
	for i in SimWorld.STRIKE_TELEGRAPH_TICKS:
		sim.step([_idle()])
	Runner.T.ok(not p["alive"], "player who stayed in the blast is hurt when it resolves")

	# Case 2: player retreats past GRENADE_RADIUS before it lands -> survives.
	var sim2 := SimWorld.new(1, 1)
	var p2 := sim2.players[0]
	p2["x"] = pos_x
	p2["y"] = pos_y
	sim2.enemies.clear()
	var e2 := {"x": pos_x + 60 * Fixed.ONE, "y": pos_y, "alive": true, "elite": true,
		"kind": "grenadier", "fire_cd": SimWorld.GRENADIER_FIRE_CD_TICKS, "windup": 1}
	sim2.enemies.append(e2)
	sim2.step([_idle()])
	Runner.T.eq(sim2.strikes.size(), 1, "windup hitting zero lobs a tracked strike (case 2)")
	p2["x"] = pos_x + SimWorld.GRENADE_RADIUS + 20 * Fixed.ONE
	p2["y"] = pos_y + SimWorld.GRENADE_RADIUS + 20 * Fixed.ONE
	for i in SimWorld.STRIKE_TELEGRAPH_TICKS:
		sim2.step([_idle()])
	Runner.T.ok(p2["alive"], "player who left the blast radius survives it")


func test_frogman_resubmerges_once_lunge_ends_in_calm_water() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 0
	sim.enemies.clear()
	sim.waters.append({"y": -50 * Fixed.ONE, "ford_x": 9999 * Fixed.ONE})
	sim._spawn_frogman(200 * Fixed.ONE, 0)   # well outside FROGMAN_CALM_RADIUS, in water
	var frog := sim.enemies[sim.enemies.size() - 1]
	Runner.T.ok(sim._in_water(frog["x"], frog["y"]), "frogman sits in a water band")
	# Jump straight to the tail of a lunge (reachable via the normal
	# submerge->surface->lunge sequence; skipped here for a deterministic probe).
	frog["submerged"] = false
	frog["surface_ticks"] = 0
	frog["lunge_ticks"] = 1
	sim._step_frogman(frog)   # exhausts the last lunge tick
	Runner.T.eq(frog["lunge_ticks"], 0, "lunge counted down to zero")
	Runner.T.ok(not frog["submerged"], "still surfaced the instant the lunge ends")
	sim._step_frogman(frog)   # water is calm and the player is still far -> re-submerge
	Runner.T.ok(frog["submerged"], "frogman re-submerges once the water calms")


func test_frogman_stranded_on_land_retelegraphs_instead_of_lunging_forever() -> void:
	## Regression: a lunge is FROGMAN_LUNGE_DIST but a water band is ~80px, so a lunging
	## frogman lands on DRY GROUND. The re-submerge branch required `_in_water`, which is
	## then false forever, and the else rewound lunge_ticks every tick — an unescapable
	## 3.0px/t homing one-hit kill versus a 2.4px/t player, no telegraph, no cooldown,
	## and no cull (it stays glued to the target). It must re-telegraph instead.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 0
	sim.enemies.clear()
	sim.waters.append({"y": -400 * Fixed.ONE, "ford_x": 9999 * Fixed.ONE})
	sim._spawn_frogman(0, 0)
	var frog := sim.enemies[sim.enemies.size() - 1]
	frog["x"] = 0
	frog["y"] = 0   # on land, right on top of the player: close AND dry
	Runner.T.ok(not sim._in_water(frog["x"], frog["y"]), "frogman is stranded on dry land")
	frog["submerged"] = false
	frog["surface_ticks"] = 0
	frog["lunge_ticks"] = 1
	sim._step_frogman(frog)   # exhausts the lunge
	Runner.T.eq(frog["lunge_ticks"], 0, "lunge counted down to zero")
	sim._step_frogman(frog)   # the old code rewound lunge_ticks here, forever
	Runner.T.eq(frog["lunge_ticks"], 0, "does NOT instantly re-arm the lunge on land")
	Runner.T.ok(frog["surface_ticks"] > 0, "re-telegraphs (surfaced + rooted) before lunging again")


func test_sniper_fires_exactly_when_windup_hits_zero() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 0
	sim.enemies.clear()
	var e := {"x": 0, "y": -100 * Fixed.ONE, "alive": true, "elite": true, "kind": "sniper",
		"fire_cd": SimWorld.SNIPER_FIRE_CD_TICKS, "windup": 3,
		"aim_lx": 0, "aim_ly": 100 * Fixed.ONE}
	sim.enemies.append(e)
	for i in 2:
		sim.step([_idle()])
		Runner.T.eq(sim.enemy_bullets.size(), 0, "no shot while windup is still counting down (tick %d)" % i)
	Runner.T.eq(e["windup"], 1, "windup at 1 before the final tick")
	sim.step([_idle()])
	Runner.T.eq(e["windup"], 0, "windup reaches exactly zero")
	Runner.T.eq(sim.enemy_bullets.size(), 1, "the shot fires on the exact tick windup hits zero")
	sim.step([_idle()])
	Runner.T.eq(sim.enemy_bullets.size(), 1, "no follow-up shot fires once windup rests at zero (fire_cd still cooling)")
