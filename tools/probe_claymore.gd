extends SceneTree
## Does planting a claymore actually kill the planter, and in how many ticks?
## The backlog says "kills planter in 4 ticks"; the plant site says the current
## along-the-aim placement was chosen BECAUSE behind-the-aim self-killed in ~5 at
## full backpedal. Both cannot be fine. Measure it instead of picking a side.
##
##   godot --headless --path . -s res://tools/probe_claymore.gd

func _init() -> void:
	print("aim/move combo -> ticks until the planter is hurt by their own claymore")
	print("(plant is at player + aim*%d px; MINE_TRIGGER_RADIUS = %d px)"
		% [SimWorld.CLAYMORE_PLANT_OFFSET / SimWorld.F_ONE,
		   SimWorld.MINE_TRIGGER_RADIUS / SimWorld.F_ONE])
	# aim north (the common case: you shoot up-screen), then try each move direction.
	var combos := [
		["advance INTO your own aim", 0, -256],
		["retreat away from aim", 0, 256],
		["strafe right", 256, 0],
		["stand still", 0, 0],
	]
	for c in combos:
		var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
		var p: Dictionary = sim.players[0]
		p["claymores"] = 3
		var hp0: int = p.get("hp", 0)
		var vest0: bool = p.get("vest", false)
		var deaths0: int = p["deaths"]
		# tick 1: plant (INTERACT edge), aiming north
		var plant := SimInput.new()
		plant.aim_x = 0
		plant.aim_y = -256
		plant.interact = true
		sim.step([plant] as Array[SimInput])
		var planted: int = sim.mines.size()
		# then hold the movement under test with the same aim
		var hurt_at := -1
		for t in 120:
			var inp := SimInput.new()
			inp.aim_x = 0
			inp.aim_y = -256
			inp.move_x = c[1]
			inp.move_y = c[2]
			sim.step([inp] as Array[SimInput])
			var q: Dictionary = sim.players[0]
			if q["deaths"] > deaths0 or q.get("hp", hp0) < hp0 or (vest0 and not q.get("vest", false)):
				hurt_at = t + 1
				break
		print("  %-26s mines=%d  hurt_at=%s"
			% [c[0], planted, ("tick %d" % hurt_at) if hurt_at > 0 else "never (120 ticks)"])

	# The grace must not neuter the weapon. Two counter-checks.
	print("counter-checks (the fix must NOT make it harmless):")
	# (a) an enemy standing on it trips it during the planter's grace window
	var s2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p2: Dictionary = s2.players[0]
	p2["claymores"] = 3
	var pl := SimInput.new()
	pl.aim_x = 0
	pl.aim_y = -256
	pl.interact = true
	s2.step([pl] as Array[SimInput])
	var mine: Dictionary = s2.mines[s2.mines.size() - 1]
	s2._spawn_enemy(mine["x"], mine["y"], false)
	var n0: int = s2.enemies.size()
	var idle := SimInput.new()
	var enemy_died := -1
	for t in 30:
		s2.step([idle] as Array[SimInput])
		if s2.enemies.size() < n0:
			enemy_died = t + 1
			break
	print("  enemy on the charge during grace -> %s"
		% (("killed at tick %d" % enemy_died) if enemy_died > 0 else "SURVIVED 30 ticks (BAD)"))
	# (b) once grace expires the charge is live to the planter again
	var s3 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p3: Dictionary = s3.players[0]
	p3["claymores"] = 3
	s3.step([pl] as Array[SimInput])
	var d0: int = s3.players[0]["deaths"]
	var hp0b: int = s3.players[0].get("hp", 0)
	var vest0b: bool = s3.players[0].get("vest", false)
	for t in SimWorld.CLAYMORE_ARM_TICKS + 4:
		s3.step([idle] as Array[SimInput])       # stand still: grace runs out
	var late := -1
	for t in 60:
		var adv := SimInput.new()
		adv.aim_x = 0
		adv.aim_y = -256
		adv.move_y = -256
		s3.step([adv] as Array[SimInput])
		var q3: Dictionary = s3.players[0]
		if q3["deaths"] > d0 or q3.get("hp", hp0b) < hp0b or (vest0b and not q3.get("vest", false)):
			late = t + 1
			break
	print("  planter walks in AFTER grace expires -> %s"
		% (("hurt at tick %d (grammar intact)" % late) if late > 0 else "never (grammar LOST)"))
	quit(0)
