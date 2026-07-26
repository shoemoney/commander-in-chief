extends SceneTree

func _init() -> void:
	var seeds := [0xC0FFEE, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
	var bad_crate := 0
	var buried := 0
	var total_g4 := 0
	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "campaign")
		sim.god_mode = true
		var inp := SimInput.new()
		# Force-stream the whole map by dragging the ratchet camera north.
		for t in 400:
			sim.camera_top = mini(sim.camera_top, -(t * 25) * SimWorld.F_ONE)
			sim.step([inp] as Array[SimInput])
		for gi in sim.gates.size():
			var g: Dictionary = sim.gates[gi]
			var fx: int = g.get("fork_x", 0)
			if fx == 0:
				continue
			var gn: int = absi(g["y"]) / SimWorld.GATE_SPACING
			var lo: int = fx - 44
			var hi: int = fx + 44
			var L := {"pickup": [], "e": 0, "mine": 0, "bag": 0}
			var R := {"pickup": [], "e": 0, "mine": 0, "bag": 0}
			var inband := []
			for pk in sim.pickups:
				if pk["y"] < g["y"] + 40 * SimWorld.F_ONE or pk["y"] > g["y"] + 700 * SimWorld.F_ONE:
					continue
				var x: int = pk["x"] / SimWorld.F_ONE
				(L if x < fx else R)["pickup"].append("k%d@x%d" % [pk["kind"], x])
			for e in sim.enemies:
				if e["y"] < g["y"] + 40 * SimWorld.F_ONE or e["y"] > g["y"] + 700 * SimWorld.F_ONE:
					continue
				(L if e["x"] / SimWorld.F_ONE < fx else R)["e"] += 1
			for m in sim.mines:
				if m["y"] < g["y"] + 40 * SimWorld.F_ONE or m["y"] > g["y"] + 700 * SimWorld.F_ONE:
					continue
				var x: int = m["x"] / SimWorld.F_ONE
				(L if x < fx else R)["mine"] += 1
				if x > lo and x < hi and sim._in_fork_divider(m["x"], m["y"], g["y"], fx):
					inband.append(x)
			for b in sim.sandbags:
				if b["y"] < g["y"] + 40 * SimWorld.F_ONE or b["y"] > g["y"] + 700 * SimWorld.F_ONE:
					continue
				(L if b["x"] / SimWorld.F_ONE < fx else R)["bag"] += 1
			# Derive the column headers from the sim's OWN predicate rather than restating
			# them -- an earlier version of this tool hardcoded "LEFT(sign:CACHE)", which
			# was the exact lie the fix removed from main.gd (at gate 4 the wire is on the
			# RIGHT, so a hardcoded LEFT label restates the bug this census exists to catch).
			var cache_left: bool = SimWorld.fork_cache_is_left(fx)
			var wire := "LEFT" if cache_left else "RIGHT"
			var cache_side := L if cache_left else R
			var bounty_side := R if cache_left else L
			print("g%d 0x%-7X fx=%3d CACHEwire=%-5s | CACHE(%s) mine=%-2d enemy=%-2d bag=%-2d pk=%-24s || BOUNTY(%s) mine=%-2d enemy=%-2d bag=%-2d pk=%-24s inside_island=%s" % [
				gn, sd, fx, wire, wire, cache_side["mine"], cache_side["e"], cache_side["bag"], str(cache_side["pickup"]),
				("RIGHT" if cache_left else "LEFT"), bounty_side["mine"], bounty_side["e"], bounty_side["bag"], str(bounty_side["pickup"]), str(inband)])
			if gn == 4:
				total_g4 += 1
				if cache_side["pickup"].is_empty():
					bad_crate += 1
				if not inband.is_empty():
					buried += 1
	print("\ngate-4 forks measured: %d" % total_g4)
	print("  CACHE lane (right of divider = the wire side) held ZERO pickups: %d/%d" % [bad_crate, total_g4])
	print("  forks with >=1 mine sealed inside the impassable wreck island: %d/%d" % [buried, total_g4])
	quit(0)
