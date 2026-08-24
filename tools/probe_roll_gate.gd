extends SceneTree
# Headless probe: measures traversal advantage of roll-spam vs walk.
# Two parallel sims, 1200 ticks, north vector, p1 spams roll on cooldown.
# Assert traversal_ratio = roll_dist / walk_dist ; free roll => >1.15 (FAIL)
# After fix => <=1.15 (PASS)

func _init() -> void:
	var ticks := 1200
	var roll_dist := _run(ticks, true)
	var walk_dist := _run(ticks, false)
	var ratio := 0.0
	if walk_dist != 0:
		ratio = float(roll_dist) / float(walk_dist)
	# Fixed ONE = 65536
	var roll_px := float(roll_dist) / 65536.0
	var walk_px := float(walk_dist) / 65536.0
	print("ROLL_DIST_FIXED=%d WALK_DIST_FIXED=%d" % [roll_dist, walk_dist])
	print("ROLL_PX=%.2f WALK_PX=%.2f RATIO=%.4f" % [roll_px, walk_px, ratio])
	var head_fail := ratio > 1.15
	print("CHECK_FAILS_ON_HEAD (ratio>1.15): %s" % str(head_fail))
	# For fix verification we want PASS = ratio <=1.15
	if ratio <= 1.15:
		print("PROBE_RESULT: PASS (gated, ratio <=1.15)")
	else:
		print("PROBE_RESULT: FAIL (free roll, ratio >1.15)")
	quit(0 if ratio <= 1.15 else 1)


func _run(ticks: int, do_roll: bool) -> int:
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	# Silence enemies/bunkers for pure traversal: clear after init, keep camera.
	# We keep sim minimal — just player movement matters.
	sim.enemies.clear()
	sim.bunkers.clear()
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.waters.clear()
	sim.mines.clear()
	sim.barrels.clear()
	sim.tanks.clear()
	sim.gates.clear()
	sim.bullets.clear()
	sim.enemy_bullets.clear()
	var start_y: int = sim.players[0]["y"]
	# Use north vector consistently
	for t in ticks:
		var inp := SimInput.new()
		inp.move_x = 0
		inp.move_y = -256
		inp.aim_x = 0
		inp.aim_y = -256
		# Spam roll on cooldown: rising edge every ROLL_CD_TICKS
		# Use current SimWorld constant so probe adapts after fix
		if do_roll:
			var cd: int = SimWorld.ROLL_CD_TICKS
			if t % cd == 0:
				inp.roll = true
			else:
				inp.roll = false
		else:
			inp.roll = false
		sim.step([inp])
		# Keep world clear each tick (respawns/streaming may add)
		sim.enemies.clear()
		sim.bullets.clear()
		sim.enemy_bullets.clear()
		sim.mines.clear()
		sim.barrels.clear()
		sim.rocks.clear()
		sim.sandbags.clear()
		sim.tanks.clear()
		sim.bunkers.clear()
		sim.waters.clear()
		sim.gates.clear()
		sim.vents.clear()
		# Push streaming horizons far away so nothing reappears
		sim._next_rock_y = sim.camera_top - 10000 * Fixed.ONE
		sim._next_bunker_y = sim.camera_top - 10000 * Fixed.ONE
		sim._next_mine_y = sim.camera_top - 10000 * Fixed.ONE
		sim._next_barrel_y = sim.camera_top - 10000 * Fixed.ONE
		sim._next_vent_y = sim.camera_top - 10000 * Fixed.ONE
	var end_y: int = sim.players[0]["y"]
	var dist: int = absi(end_y - start_y)
	return dist
