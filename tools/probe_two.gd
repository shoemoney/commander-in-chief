extends SceneTree
## A) FAN VALUE, travel-time removed. Earlier pass conflated bullet flight with
##    accuracy. Fire exactly ONE pull at a HIGH-HP body and count how many
##    pellets actually LAND (hp lost) per pull, at a spread of ranges. That is
##    the only number that says whether the fan's +1/+2 ammo surcharge buys
##    anything.
##
## B) TELEGRAPH LENGTH vs the project's own 24-tick reaction floor. The floor is
##    pinned in five constants (TECHNICAL_REV 24, REAR_WARN 90, VENT_WARN 30,
##    FLANK_WARN 45, FROGMAN_SURFACE) and asserted in three tests. Print every
##    archetype's tell against it and measure the rifleman's real dodge budget.
##
##   godot --headless --path . -s res://tools/probe_two.gd

func _sterile(mode := "campaign", wave := 0) -> SimWorld:
	var sim := SimWorld.new(0xC0FFEE, 1, mode)
	sim.wave = wave
	sim.enemies.clear(); sim.bunkers.clear(); sim.mines.clear()
	sim.barrels.clear(); sim.rocks.clear(); sim.sandbags.clear()
	sim.pickups.clear()
	return sim


func _pellets_landed(range_px: int, triple: bool, spread: bool) -> Array:
	var sim := _sterile()
	var p: Dictionary = sim.players[0]
	p["mg_ammo"] = 99
	var hp := 60
	var e := {"x": p["x"], "y": p["y"] - range_px * SimWorld.F_ONE, "alive": true,
		"elite": false, "kind": "rusher", "hp": hp, "fire_cd": 1 << 28, "windup": 0,
		"aim_lx": 0, "aim_ly": 0, "submerged": false, "surface_ticks": 0,
		"face_x": 0, "face_y": SimWorld.F_ONE, "spd_mul": 0, "hits": 0}
	sim.enemies.append(e)
	var tx: int = e["x"]
	var ty: int = e["y"]
	var billed := 0
	var fired := false
	for t in 400:
		sim._spawn_grace = 1 << 20
		e["x"] = tx
		e["y"] = ty
		p["triple"] = triple
		p["spread_ticks"] = (1 << 28) if spread else 0
		var inp := SimInput.new()
		# Fire exactly ONE pull, then hold fire so the flight can finish clean.
		inp.fire = not fired
		inp.aim_y = -256
		var before: int = p["mg_ammo"]
		sim.step([inp] as Array[SimInput])
		p = sim.players[0]
		billed += maxi(0, before - int(p["mg_ammo"]))
		for ev in sim.events:
			if ev["t"] == "shot":
				fired = true
		if fired and sim.bullets.is_empty():
			break
	return [billed, hp - int(e["hp"])]


func _rifleman_budget(range_px: int) -> Array:
	var sim := _sterile()
	var p: Dictionary = sim.players[0]
	p["mg_ammo"] = 0
	var e := {"x": p["x"], "y": p["y"] - range_px * SimWorld.F_ONE, "alive": true,
		"elite": false, "kind": "rusher", "hp": 1, "fire_cd": 0, "windup": 0,
		"aim_lx": 0, "aim_ly": 0, "submerged": false, "surface_ticks": 0,
		"face_x": 0, "face_y": SimWorld.F_ONE, "spd_mul": 0, "hits": 0}
	sim.enemies.append(e)
	var tx: int = e["x"]
	var ty: int = e["y"]
	var warn := -1
	var hit := -1
	var deaths0: int = p["deaths"]
	for t in 400:
		sim._spawn_grace = 1 << 20
		e["x"] = tx
		e["y"] = ty
		e["alive"] = true
		if not sim.enemies.has(e):
			sim.enemies.append(e)
		var inp := SimInput.new()   # stand perfectly still: measure the WINDOW, not a dodge
		inp.aim_y = -256
		sim.step([inp] as Array[SimInput])
		p = sim.players[0]
		for ev in sim.events:
			if ev["t"] == "rifleman_windup" and warn < 0:
				warn = t
		if warn >= 0 and int(p["deaths"]) > deaths0 and hit < 0:
			hit = t
			break
	return [warn, hit, (hit - warn) if (warn >= 0 and hit >= 0) else -1]


func _init() -> void:
	print("=== A) PELLETS THAT ACTUALLY LAND, per ONE pull, vs the ammo billed ===")
	print("   (60 hp dummy so nothing is wasted on overkill; each landed pellet = 1 hp)")
	print("%-8s %-22s %-22s %-22s" % ["range", "base (billed/landed)", "triple", "triple+spread"])
	for r in [16, 24, 32, 40, 47, 56, 70, 100, 150, 240]:
		var a := _pellets_landed(r, false, false)
		var b := _pellets_landed(r, true, false)
		var c := _pellets_landed(r, true, true)
		print("%-8d %-22s %-22s %-22s" % [r,
			"%d billed / %d landed" % [a[0], a[1]],
			"%d billed / %d landed" % [b[0], b[1]],
			"%d billed / %d landed" % [c[0], c[1]]])

	print("")
	print("=== B) TELEGRAPH LENGTHS vs the project's own 24-tick reaction floor ===")
	var tells := {
		"rifleman (base infantry)": SimWorld.RIFLEMAN_WINDUP_TICKS,
		"elite": SimWorld.ELITE_WINDUP_TICKS,
		"grenadier": SimWorld.GRENADIER_WINDUP_TICKS,
		"sniper / ghillie": SimWorld.SNIPER_WINDUP_TICKS,
		"drone": SimWorld.DRONE_WINDUP_TICKS,
		"technical rev": SimWorld.TECHNICAL_REV_TICKS,
		"frogman surface": SimWorld.FROGMAN_SURFACE_TICKS,
		"vent warn": SimWorld.VENT_WARN_TICKS,
		"flank warn": SimWorld.FLANK_WARN_TICKS,
		"rear warn": SimWorld.REAR_WARN_TICKS,
		"mg nest aim": SimWorld.MG_NEST_AIM_TICKS,
		"strike ring": SimWorld.STRIKE_TELEGRAPH_TICKS,
	}
	for k in tells:
		print("  %-26s %3dt  %s" % [k, tells[k], "" if tells[k] >= 24 else "<-- BELOW the 24t floor"])

	print("")
	print("Rifleman: ticks from the 'rifleman_windup' event to the round landing on a")
	print("STATIONARY player (tell + flight = the whole reaction budget).")
	print("  ENEMY_BULLET_SPEED=%d px/t, RIFLEMAN_STANDOFF=%d px"
		% [SimWorld.ENEMY_BULLET_SPEED / SimWorld.F_ONE,
		   SimWorld.RIFLEMAN_STANDOFF / SimWorld.F_ONE])
	for r in [20, 40, 60, 80, 100]:
		var b := _rifleman_budget(r)
		print("  range %-5d warn@t=%-5s hit@t=%-5s budget=%s ticks (%.2f s)"
			% [r, str(b[0]), str(b[1]), str(b[2]), float(maxi(b[2], 0)) / 60.0])
	quit()
