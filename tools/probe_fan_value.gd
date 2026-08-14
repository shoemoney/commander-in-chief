extends SceneTree

# Hits-per-ROUND-BILLED for every fan combo against every shipped hitbox radius,
# measured through the SHIPPED fire path (sim.step) and the sim's own per-tick
# bullet march + _dist_lte hit test.

const F := 65536

func _init() -> void:
	var radii := {"fodder": SimWorld.BULLET_HIT_RADIUS}
	for k in SimWorld.KIND_HIT_RADIUS:
		radii[k] = SimWorld.KIND_HIT_RADIUS[k]
	radii["colossus"] = 34 * F
	var combos := [["base", false, 0], ["triple", true, 0], ["trench", false, 480], ["both", true, 480]]
	for d in [40, 60, 80, 100, 140, 180, 220, 260]:
		var line := "dist=%3dpx  " % d
		for c in combos:
			var res := _fire(c[1], c[2])
			var billed: int = res["billed"]
			for rk in radii:
				pass
			var s := ""
			for rk in ["fodder", "elite", "mg_nest", "colossus"]:
				var r: int = radii[rk]
				var hits := 0
				for b in res["bullets"]:
					if _flies_into(b, d * F, r):
						hits += 1
				s += "%s %.2f " % [rk.substr(0, 3), float(hits) / float(billed)]
			line += "| %-6s billed=%d %s" % [c[0], billed, s]
		print(line)
	quit()


func _fire(triple: bool, spread: int) -> Dictionary:
	var sim := SimWorld.new(0, 1, "campaign")
	var p: Dictionary = sim.players[0]
	# Pin the player mid-lane so nothing else is in front of the muzzle.
	p["triple"] = triple
	p["spread_ticks"] = spread
	p["mg_ammo"] = 99
	p["fire_cd"] = 0
	var before: int = p["mg_ammo"]
	sim.bullets.clear()
	var inp := SimInput.new()
	inp.aim_x = 0
	inp.aim_y = -256
	inp.fire = true
	var px: int = p["x"]
	var py: int = p["y"]
	sim.step([inp])
	var out: Array = []
	for b in sim.bullets:
		out.append({"vx": b["vx"], "vy": b["vy"], "x": px, "y": py})
	return {"billed": before - int(sim.players[0]["mg_ammo"]), "bullets": out}


func _flies_into(b: Dictionary, dist: int, r: int) -> bool:
	# Target sits `dist` north of the muzzle; march the sim's way (one vx/vy add
	# per tick, hit test at the post-move position) for BULLET_TTL_TICKS.
	var tx: int = b["x"]
	var ty: int = b["y"] - dist
	var x: int = b["x"]
	var y: int = b["y"]
	for t in SimWorld.BULLET_TTL_TICKS:
		x += b["vx"]
		y += b["vy"]
		if absi(x - tx) <= r and Fixed.mul(x - tx, x - tx) + Fixed.mul(y - ty, y - ty) <= Fixed.mul(r, r):
			return true
	return false
