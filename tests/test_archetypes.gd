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


func test_shield_facing_cannot_snap_and_a_safe_flank_opens() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim.enemies.clear()
	p["x"] = 320 * Fixed.ONE
	p["y"] = 50 * Fixed.ONE
	sim._spawn_special(320 * Fixed.ONE, 0, "shield")
	var e: Dictionary = sim.enemies[0]
	Runner.T.ok(e["face_y"] > 0, "spawned shield initially faces the player below")
	# Teleport the target to the opposite side to stress the turn cap. One update must not
	# reverse the plate; this is the old every-tick snap failure in its strongest form.
	p["y"] = -50 * Fixed.ONE
	sim._turn_shield_toward(e, 0, -50 * Fixed.ONE, 50 * Fixed.ONE)
	Runner.T.ok(e["face_y"] > 0, "one tick cannot snap the shield through 180 degrees")
	# Move to a safe lateral standoff. The facing starts down and only begins turning right;
	# a shot from the player's new side therefore reaches the exposed arc.
	p["x"] = 360 * Fixed.ONE
	p["y"] = 0
	sim._turn_shield_toward(e, 40 * Fixed.ONE, 0, 40 * Fixed.ONE)
	Runner.T.ok(e["face_x"] < Fixed.ONE / 2, "capped turn leaves a flank outside the front cone")
	sim.bullets.append({"x": e["x"], "y": e["y"], "vx": -SimWorld.BULLET_SPEED,
		"vy": 0, "ttl": 60})
	sim._step_bullets()
	Runner.T.ok(not e["alive"], "a lateral shot earned at 40px standoff kills the shieldman")


func test_shield_exact_opposite_turn_has_stable_tie_break_and_converges() -> void:
	var sim := SimWorld.new(1, 1)
	var e := {"face_x": 0, "face_y": Fixed.ONE}
	# Exact antipodes have no cross-product sign. The old component approach reduced +Y,
	# normalized it straight back to +Y, and repeated forever. The first tick must retain
	# forward continuity while also choosing a deterministic side out of that tie.
	sim._turn_shield_toward(e, 0, -50 * Fixed.ONE, 50 * Fixed.ONE)
	Runner.T.ok(e["face_y"] > 0, "an exact-opposite request still cannot reverse in one tick")
	Runner.T.ok(e["face_x"] < 0, "the 180-degree tie deterministically starts through -X")
	for _tick in 110:
		sim._turn_shield_toward(e, 0, -50 * Fixed.ONE, 50 * Fixed.ONE)
	Runner.T.eq(e["face_x"], 0, "the capped turn settles exactly on the antipodal X heading")
	Runner.T.eq(e["face_y"], -Fixed.ONE, "the capped turn reaches the target behind it")


func test_shield_ordinary_enemy_steps_leave_a_flank_for_safe_standoff_circle() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var cx := 320 * Fixed.ONE
	var cy := -160 * Fixed.ONE
	p["x"] = cx
	p["y"] = cy + 40 * Fixed.ONE
	sim._spawn_special(cx, cy, "shield")
	var e: Dictionary = sim.enemies[0]
	var orbit_x := 0
	var orbit_y := Fixed.ONE
	# Twice the plate's angular step at a 40px radius is about 2.5px/tick: ordinary
	# player running speed, safely four touch-radii away. Keep the shield centered after
	# each ordinary enemy-AI step so this isolates the promised circling contest from its
	# unrelated forward translation and holds the measured standoff constant.
	for _tick in 40:
		var next_x := orbit_x + Fixed.mul(-orbit_y, SimWorld.SHIELD_TURN_STEP * 2)
		var next_y := orbit_y + Fixed.mul(orbit_x, SimWorld.SHIELD_TURN_STEP * 2)
		var next_len := Fixed.length(next_x, next_y)
		orbit_x = Fixed.div(next_x, next_len)
		orbit_y = Fixed.div(next_y, next_len)
		p["x"] = cx + Fixed.mul(orbit_x, 40 * Fixed.ONE)
		p["y"] = cy + Fixed.mul(orbit_y, 40 * Fixed.ONE)
		sim._step_enemies()
		e["x"] = cx
		e["y"] = cy
	var shot_vx := -Fixed.mul(orbit_x, SimWorld.BULLET_SPEED)
	var shot_vy := -Fixed.mul(orbit_y, SimWorld.BULLET_SPEED)
	Runner.T.ok(not sim._shield_blocks(e, {"vx": shot_vx, "vy": shot_vy}),
		"a normal-speed 40px circle outruns the plate far enough to expose its flank")
	sim.bullets.append({"x": e["x"], "y": e["y"], "vx": shot_vx, "vy": shot_vy,
		"ttl": 60})
	sim._step_bullets()
	Runner.T.ok(not e["alive"], "the earned circling flank is lethal during ordinary bullet resolution")


func test_shield_two_player_nearest_target_swap_turns_continuously_then_reblocks() -> void:
	var sim := SimWorld.new(1, 2)
	var p0 := sim.players[0]
	var p1 := sim.players[1]
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var ex := 320 * Fixed.ONE
	var ey := -200 * Fixed.ONE
	p0["x"] = ex
	p0["y"] = -120 * Fixed.ONE   # initially nearest, directly below
	p1["x"] = ex
	p1["y"] = -450 * Fixed.ONE   # initially farther, directly above
	sim._spawn_special(ex, ey, "shield")
	var e: Dictionary = sim.enemies[0]
	Runner.T.eq(e["face_y"], Fixed.ONE, "spawn faces the initially nearest teammate")
	# Hand nearest status to the teammate on the exact opposite side. The live enemy step
	# must use that new target without teleporting its already-visible plate.
	p0["x"] = 620 * Fixed.ONE
	p0["y"] = 100 * Fixed.ONE
	sim._step_enemies()
	Runner.T.ok(e["face_y"] > 0 and e["face_x"] < 0,
		"nearest-target swap starts a continuous deterministic turn, not a 180 snap")
	Runner.T.ok(sim._shield_blocks(e, {"vx": 0, "vy": -SimWorld.BULLET_SPEED}),
		"the old teammate's head-on lane remains blocked during the first swap tick")
	Runner.T.ok(not sim._shield_blocks(e, {"vx": 0, "vy": SimWorld.BULLET_SPEED}),
		"the new teammate behind the plate has a temporary firing window")
	for _tick in 110:
		sim._step_enemies()
	Runner.T.eq(e["face_x"], 0, "continued ordinary steps settle on the new nearest target's axis")
	Runner.T.eq(e["face_y"], -Fixed.ONE, "continued ordinary steps face the new nearest target")
	Runner.T.ok(sim._shield_blocks(e, {"vx": 0, "vy": SimWorld.BULLET_SPEED}),
		"the plate re-blocks the new teammate after completing its capped turn")
	Runner.T.ok(not sim._shield_blocks(e, {"vx": 0, "vy": -SimWorld.BULLET_SPEED}),
		"the old teammate is now on the exposed rear arc")


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
	Runner.T.eq(sim.strikes.size(), 3, "windup hitting zero lobs the three-blast cluster")
	Runner.T.eq(sim.strikes[1]["x"], pos_x, "centre strike lands on the player's x at lob time")
	Runner.T.eq(sim.strikes[1]["y"], pos_y, "centre strike lands on the player's y at lob time")
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
	Runner.T.eq(sim2.strikes.size(), 3, "windup hitting zero lobs the cluster (case 2)")
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


func test_sapper_cannot_cross_a_sandbag_line() -> void:
	## Regression: _step_sapper open-coded its movement instead of routing through
	## _advance_toward, so it phased straight through sandbags — a 40-coin player
	## purchase — plus rocks, hulks and sealed lane blocks. Cover you paid for has
	## to stop the thing that lays mines under it.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = 0
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var wall_y := 50 * Fixed.ONE
	# Three segments (half-width 18px) laid shoulder to shoulder: a solid -54..54 wall.
	for n in [-36, 0, 36]:
		sim.sandbags.append({"x": n * Fixed.ONE, "y": wall_y, "player": 1})
	var start_y := 120 * Fixed.ONE
	sim._spawn_special(0, start_y, "sapper")
	var sap := sim.enemies[sim.enemies.size() - 1]
	for _i in 200:   # far more ticks than the ~44 a clear walk to the player would need
		var dx: int = p["x"] - sap["x"]
		var dy: int = p["y"] - sap["y"]
		sim._step_sapper(sap, dx, dy, Fixed.length(dx, dy))
	Runner.T.ok(sap["y"] > wall_y, "sapper never ends up on the player's side of the bag line")
	Runner.T.ok(sap["y"] < start_y, "it did close on the wall (not passing by standing still)")
	Runner.T.ok(sim.mines.size() > 0, "and it still lays mines on its cadence while stalled")


func test_sapper_does_not_detonate_its_own_mine_the_tick_it_lays_it() -> void:
	## _step_sapper laid the mine AT the sapper's own feet (distance 0) and
	## _step_mines' enemy scan — which deliberately ignores `grace`, so a
	## claymore dropped in a pursuer's path works on the tick it lands — then
	## tripped it against the layer on that same tick. Every sapper that lived
	## long enough to lay killed itself, so the advertised "hazard trail across
	## the arena" never existed: what the player actually got was a free kill
	## and free coin from the blast. Measured, not theorised — the mine and the
	## sapper are both gone one _step_mines() after the drop.
	var sim := SimWorld.new(3, 1)
	var p := sim.players[0]
	# Both bodies must sit INSIDE the live band: _step_mines culls anything past
	# camera_top+420 before it ever scans, so a mine dropped south of that would
	# vanish for the wrong reason and the check would prove nothing.
	p["x"] = 300 * Fixed.ONE
	p["y"] = sim.camera_top + 40 * Fixed.ONE
	sim.enemies.clear()
	sim.mines.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	sim._spawn_special(300 * Fixed.ONE, sim.camera_top + 200 * Fixed.ONE, "sapper")
	var sap := sim.enemies[sim.enemies.size() - 1]
	sap["fire_cd"] = 0
	var dx: int = p["x"] - sap["x"]
	var dy: int = p["y"] - sap["y"]
	sim._step_sapper(sap, dx, dy, Fixed.length(dx, dy))
	Runner.T.eq(sim.mines.size(), 1, "the sapper laid exactly one mine")
	# The drop must clear its own 9px trigger — the same rule the player's
	# claymore already follows via CLAYMORE_PLANT_OFFSET.
	var m: Dictionary = sim.mines[0]
	Runner.T.ok(Fixed.length(m["x"] - sap["x"], m["y"] - sap["y"]) > SimWorld.MINE_TRIGGER_RADIUS,
		"the mine lands outside the sapper's own trigger radius")
	sim._step_mines()
	Runner.T.eq(sim.mines.size(), 1, "the mine survives the tick it was laid on")
	Runner.T.ok(sim.mines[0]["armed"], "and it is still armed, waiting for someone else")
	Runner.T.ok(sap["alive"], "the sapper did not blow itself up")


# --- Per-sector rosters -------------------------------------------------------
# The campaign used to run ONE flat ["grenadier","sniper","shield"]+mg_nest roll
# from sector 2 all the way to the finale, while ZONE_INFO promised six distinct
# zones. SECTOR_SPECIALS is that promise made real; these pin it.

const SPAWNABLE_SPECIALS := ["grenadier", "sniper", "shield", "sapper", "ghillie",
	"drone", "technical", "mg_nest", "broadcast"]


func test_sector_specials_is_one_distinct_roster_per_authored_zone() -> void:
	Runner.T.eq(SimWorld.SECTOR_SPECIALS.size(), SimWorld.ZONE_INFO.size(),
		"one special roster per named zone")
	Runner.T.ok(SimWorld.SECTOR_SPECIALS[0].is_empty(),
		"sector 1 (STAGING GROUND) fields no specials — 'no surprises, learn the rules here'")
	var seen_rosters := {}
	for i in range(SimWorld.SECTOR_SPECIALS.size()):
		var roster: Array = SimWorld.SECTOR_SPECIALS[i]
		if i > 0:
			Runner.T.ok(not roster.is_empty(), "sector %d fields specials" % (i + 1))
		for k in roster:
			Runner.T.ok(SPAWNABLE_SPECIALS.has(k),
				"sector %d kind '%s' is one the spawner can actually build" % [i + 1, k])
		var key: String = ",".join(roster)
		Runner.T.ok(not seen_rosters.has(key),
			"sector %d's roster is not a duplicate of sector %s's" % [i + 1, seen_rosters.get(key, "?")])
		seen_rosters[key] = i + 1
	# Every archetype the table can name must actually be USED, or the advertised
	# vocabulary is quietly narrower than the roster list looks.
	var used := {}
	for roster in SimWorld.SECTOR_SPECIALS:
		for k in roster:
			used[k] = true
	for k in SPAWNABLE_SPECIALS:
		Runner.T.ok(used.has(k), "archetype '%s' appears in at least one sector roster" % k)


func _spawner_kinds(sector: int) -> Dictionary:
	## Every kind the campaign field spawner produces while fighting `sector`
	## (0-based). _gate_counter is what an Arcade chapter jump primes and what a
	## continuous run reaches; gates stay shut so `opened` alone would say sector 1.
	var sim := SimWorld.new(0xBEEF + sector, 1)
	sim._gate_counter = sector + 1
	var seen := {}
	for i in 600:
		sim.tick_count = 0        # % interval == 0: every call spawns
		sim._spawn_grace = 0
		sim.enemies.clear()
		sim._step_spawner()
		for e in sim.enemies:
			seen[e["kind"]] = true
	return seen


func test_field_spawner_only_fields_the_current_sectors_roster() -> void:
	for sector in range(SimWorld.SECTOR_SPECIALS.size()):
		var roster: Array = SimWorld.SECTOR_SPECIALS[sector]
		var seen := _spawner_kinds(sector)
		Runner.T.ok(seen.has("rusher"), "sector %d still fields ordinary rushers" % (sector + 1))
		for k in seen:
			if k == "rusher" or k == "elite":
				continue
			Runner.T.ok(roster.has(k),
				"sector %d spawned '%s', which is not on its roster" % [sector + 1, k])
		for k in roster:
			Runner.T.ok(seen.has(k),
				"sector %d never fielded its own '%s' in 600 spawns" % [sector + 1, k])


func test_campaign_never_roots_a_shooter_above_the_reachable_band() -> void:
	## Campaign twin of test_endless.gd's
	## test_rooted_wave_spawns_land_where_the_player_can_reach_them.
	## Sectors 3/5/6 field mg_nest/ghillie/broadcast, and _step_camera PINS the camera
	## for the whole closed-gate arena fight — so a rooted unit born at camera_top-24
	## sits above the drawn viewport and above _clamp_actor's camera_top+16 ceiling
	## until the gate opens: invisible, unwalkable-to, and still firing aimed bursts.
	## Assert at the SPAWN MOMENT only — the campaign camera ratchets, so a
	## legitimately-placed unit later drifts south before the sweep takes it.
	## ROOTED_KINDS is the ratchet: a new never-moves archetype that isn't listed
	## there inherits the walker spawn y and this test stays green (which is how
	## the ghillie shipped broken in endless).
	var lo_off := 16 * SimWorld.F_ONE
	for sector in [2, 4, 5]:   # 0-based: BRIDGE GUNSHIP / CRASHED CONVOY / FOUNDRY CORE
		var sim := SimWorld.new(0xBEEF + sector, 1)
		sim._gate_counter = sector + 1
		var rooted := 0
		for i in 600:
			sim.tick_count = 0
			sim._spawn_grace = 0
			sim.enemies.clear()
			sim._step_spawner()
			for e in sim.enemies:
				if SimWorld.ROOTED_KINDS.has(e["kind"]):
					rooted += 1
					Runner.T.ok(e["y"] >= sim.camera_top + lo_off \
						and e["y"] <= sim.camera_top + SimWorld.CAMERA_BAND_BOTTOM,
						"sector %d rooted '%s' spawns inside the player's reachable band"
							% [sector + 1, e["kind"]])
		Runner.T.ok(rooted > 0,
			"sector %d actually fielded a rooted archetype in 600 spawns" % (sector + 1))
	# A closed gate is a wall for the spawner too, exactly as it is for _clamp_actor.
	var gsim := SimWorld.new(7, 1)
	gsim.gates.append({"y": gsim.camera_top + 60 * SimWorld.F_ONE, "open": false,
		"b1": {}, "b2": {}, "boss": {}})
	Runner.T.ok(gsim._rooted_spawn_y() >= gsim.camera_top + 60 * SimWorld.F_ONE + SimWorld.GATE_BLOCK_PAD,
		"a rooted spawn never lands north of a closed gate's wall")


func test_rend_unlocks_exactly_where_shieldmen_can_exist() -> void:
	# Rend is the shield counter; offering it in a sector that fields no shields
	# is a dead draw (and withholding it where they DO spawn is worse).
	for sector in range(SimWorld.SECTOR_SPECIALS.size()):
		var sim := SimWorld.new(3, 1)
		sim._gate_counter = sector + 1
		Runner.T.eq(sim._shields_possible(), SimWorld.SECTOR_SPECIALS[sector].has("shield"),
			"sector %d Rend gate matches its roster" % (sector + 1))
	# A shieldman carried over from an earlier sector still counts.
	var carry := SimWorld.new(3, 1)
	carry._gate_counter = 2   # MARSH BASIN — no shields on the roster
	carry.enemies.clear()
	Runner.T.ok(not carry._shields_possible(), "no shields on the marsh roster")
	carry.enemies.append({"x": 0, "y": 0, "alive": true, "elite": true, "kind": "shield"})
	Runner.T.ok(carry._shields_possible(), "a shieldman still walking re-opens the Rend drop")


func test_campaign_sweeps_rally_masts_the_ratchet_left_behind() -> void:
	# CRASHED CONVOY fields broadcast masts, and the campaign camera ratchets: a
	# mast exempt from the off-screen sweep would live in enemies[] (and in the
	# per-tick _broadcasts aura scan) for the rest of the run.
	# The exemption is GONE IN EVERY MODE, not just campaign. A sibling pass moved
	# endless masts to camera_top+40 (they used to spawn above the player's own
	# clamp ceiling, unreachable), and under endless's fixed camera an in-band
	# rooted mast can never exceed camera_top+420 — so the unconditional sweep
	# cannot remove a live one, and one rule beats a mode-conditional special case.
	# This test therefore drives an ARTIFICIAL out-of-band endless mast, which real
	# play cannot produce, purely to pin that the rule has no exception.
	var camp := SimWorld.new(5, 1)
	camp.enemies.clear()
	camp._spawn_broadcast(0, camp.camera_top + 900 * Fixed.ONE)   # well below the live band
	camp._step_enemies()
	Runner.T.eq(camp.enemies.size(), 0, "a passed-by mast is swept in campaign")
	var endless := SimWorld.new(5, 1, "endless")
	endless.enemies.clear()
	endless._spawn_broadcast(0, endless.camera_top + 900 * Fixed.ONE)
	endless._step_enemies()
	Runner.T.eq(endless.enemies.size(), 0, "the sweep has no mode exception — an out-of-band mast goes too")


# --- Duplicate-pair splits ----------------------------------------------------

func test_grenadier_lobs_a_cluster_across_the_firing_line_not_one_circle() -> void:
	# Grenadier and drone both terminate in _add_strike. The cluster is what makes
	# them read as two different threats: the drone's single circle is a
	# step-off-the-spot dodge, the grenadier's wall must be broken LENGTHWISE.
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = -100 * Fixed.ONE
	sim.enemies.clear()
	# Grenadier due EAST of the player: the firing line is horizontal, so the
	# cluster must walk vertically.
	var e := {"x": 60 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true, "elite": true,
		"kind": "grenadier", "fire_cd": SimWorld.GRENADIER_FIRE_CD_TICKS, "windup": 1}
	sim.enemies.append(e)
	sim.step([_idle()])
	Runner.T.eq(sim.strikes.size(), 3, "one lob, three craters")
	for s in sim.strikes:
		Runner.T.eq(s["x"], p["x"], "every crater sits ON the firing line's x — the spread is perpendicular")
	var ys := [sim.strikes[0]["y"], sim.strikes[1]["y"], sim.strikes[2]["y"]]
	ys.sort()
	Runner.T.eq(ys[1], p["y"], "the middle crater is on the player")
	Runner.T.eq(p["y"] - ys[0], SimWorld.GRENADIER_CLUSTER_SPREAD, "near crater is one spread out")
	Runner.T.eq(ys[2] - p["y"], SimWorld.GRENADIER_CLUSTER_SPREAD, "far crater is one spread the other way")
	# The wall is wider than one fat circle — you cannot no-op it by standing still.
	Runner.T.ok(SimWorld.GRENADIER_CLUSTER_SPREAD > SimWorld.GRENADE_RADIUS,
		"craters are spread wider than one blast radius (a wall, not one fat circle)")

	# The drone, from the identical setup, still calls exactly ONE circle.
	var sim2 := SimWorld.new(1, 1)
	var p2 := sim2.players[0]
	p2["x"] = 0
	p2["y"] = -100 * Fixed.ONE
	sim2.enemies.clear()
	sim2.enemies.append({"x": 60 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true,
		"elite": true, "kind": "drone", "fire_cd": SimWorld.DRONE_FIRE_CD_TICKS, "windup": 1})
	sim2.step([_idle()])
	Runner.T.eq(sim2.strikes.size(), 1, "the drone's paint is still a single precise circle")


func test_ghillie_fires_once_then_vanishes_where_the_sniper_stays_up() -> void:
	var sim := SimWorld.new(1, 1)
	var p := sim.players[0]
	p["x"] = 0
	p["y"] = -100 * Fixed.ONE
	sim.enemies.clear()
	# Mid-paint, one tick from firing, well inside the notice radius.
	var g := {"x": 0, "y": -220 * Fixed.ONE, "alive": true, "elite": true, "kind": "ghillie",
		"fire_cd": 0, "windup": 1, "submerged": false, "surface_ticks": 0,
		"aim_lx": 0, "aim_ly": 120 * Fixed.ONE}
	sim.enemies.append(g)
	sim.step([_idle()])
	Runner.T.eq(sim.enemy_bullets.size(), 1, "the paint resolves into exactly one shot")
	Runner.T.ok(g["submerged"], "and he is back under the grass the same tick he fires")
	Runner.T.eq(g["fire_cd"], SimWorld.GHILLIE_RECLOAK_TICKS, "the cloak lockout is armed")
	# Cloaked = untouchable: the kill window closed with the muzzle flash.
	sim.bullets.append({"x": g["x"], "y": g["y"], "vx": 0, "vy": -SimWorld.BULLET_SPEED, "ttl": 60})
	sim._step_bullets()
	Runner.T.ok(g["alive"], "a re-cloaked ghillie eats no damage — you missed the window")
	# He stays gone for the whole lockout even though the player never left range.
	for i in SimWorld.GHILLIE_RECLOAK_TICKS - 1:
		sim.step([_idle()])
	Runner.T.ok(g["submerged"], "still cloaked one tick short of the lockout")
	sim.step([_idle()])
	Runner.T.ok(not g["submerged"], "surfaces again the tick the lockout expires — a NEW window")

	# The sniper's whole counter-loop is the opposite: he fires and STAYS up, so
	# he can be traded with at any time.
	var sim2 := SimWorld.new(1, 1)
	var p2 := sim2.players[0]
	p2["x"] = 0
	p2["y"] = -100 * Fixed.ONE
	sim2.enemies.clear()
	var s2 := {"x": 0, "y": -220 * Fixed.ONE, "alive": true, "elite": true, "kind": "sniper",
		"fire_cd": SimWorld.SNIPER_FIRE_CD_TICKS, "windup": 1,
		"aim_lx": 0, "aim_ly": 120 * Fixed.ONE}
	sim2.enemies.append(s2)
	sim2.step([_idle()])
	Runner.T.eq(sim2.enemy_bullets.size(), 1, "the sniper fires his one shot too")
	Runner.T.ok(not s2.get("submerged", false), "but the sniper does not vanish")
	sim2.bullets.append({"x": s2["x"], "y": s2["y"], "vx": 0, "vy": -SimWorld.BULLET_SPEED, "ttl": 60})
	sim2._step_bullets()
	Runner.T.ok(not s2["alive"], "so he can be shot back the very next tick")


func test_all_ghillie_wave_force_reveals_even_with_a_pilot_walking() -> void:
	## The anti-stall promise is "the wave must ALWAYS be finishable". The scan
	## seeded all_cloaked from every enemy, so a walking rescue pilot — not a
	## hostile, per _wave_hostiles_cleared — vetoed the reveal for the ~85 ticks
	## he takes to clear the top edge, and the ghillies stayed bullet-immune.
	var sim := SimWorld.new(31, 1, "endless")
	sim.wave = 3
	sim.wave_pending = 0
	sim.intermission_ticks = 0
	sim.enemies.clear()
	var g := {"x": 0, "y": -220 * Fixed.ONE, "alive": true, "elite": true, "kind": "ghillie",
		"fire_cd": 0, "windup": 0, "submerged": true, "surface_ticks": 0,
		"aim_lx": 0, "aim_ly": 0}
	var pilot := {"x": 40 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true,
		"elite": false, "kind": "pilot"}
	sim.enemies.append(g)
	sim.enemies.append(pilot)
	sim._step_waves()
	Runner.T.ok(not g["submerged"], "the last cloaked ghillie surfaces despite the live pilot")
	Runner.T.eq(g["surface_ticks"], SimWorld.GHILLIE_REVEAL_TICKS, "with the full reveal window")
	Runner.T.ok(not pilot.get("submerged", false), "and the pilot is not dragged into the reveal")
	Runner.T.ok(not pilot.has("surface_ticks"), "nor given a ghillie-only surface timer")
	# Control: a real hostile alongside still legitimately vetoes the reveal.
	var sim2 := SimWorld.new(31, 1, "endless")
	sim2.wave = 3
	sim2.wave_pending = 0
	sim2.intermission_ticks = 0
	sim2.enemies.clear()
	var g2 := {"x": 0, "y": -220 * Fixed.ONE, "alive": true, "elite": true, "kind": "ghillie",
		"fire_cd": 0, "windup": 0, "submerged": true, "surface_ticks": 0,
		"aim_lx": 0, "aim_ly": 0}
	sim2.enemies.append(g2)
	sim2.enemies.append({"x": 0, "y": -80 * Fixed.ONE, "alive": true, "elite": false,
		"kind": "rusher"})
	sim2._step_waves()
	Runner.T.ok(g2["submerged"], "a live rusher means the wave is already finishable — no reveal")
