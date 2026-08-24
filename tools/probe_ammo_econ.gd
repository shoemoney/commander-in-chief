extends SceneTree
## AMMO ECONOMY under ALWAYS-FIRE.
## The MG has no trigger (src/main.gd:6701 sets p1.fire = true unconditionally),
## so mg_ammo drains on a wall clock the player cannot stop. Measure:
##   - ticks spent DRY (mg_ammo == 0) per run
##   - rounds actually spent while NO enemy was on screen ("wasted" rounds)
##   - the same, with the Triple Shot mod (a 120c shop purchase, permanent
##     until death) forced on -- it charges +1 ammo per shot with no way to
##     holster.
##
##   godot --headless --path . -s res://tools/probe_ammo_econ.gd

const TICKS := 5400   # 90 s

func _drive(sim, p: Dictionary) -> Array:
	# Crude but honest driver: walk north, aim at the nearest live enemy.
	var inp := SimInput.new()
	inp.move_y = -256
	inp.fire = true
	var best := {}
	var bd := 1 << 60
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var d: int = absi(e["x"] - p["x"]) + absi(e["y"] - p["y"])
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		inp.aim_y = -256
	else:
		var dx: int = (best["x"] - p["x"]) / SimWorld.F_ONE
		var dy: int = (best["y"] - p["y"]) / SimWorld.F_ONE
		var l: int = maxi(1, absi(dx) + absi(dy))
		inp.aim_x = clampi(dx * 256 / l, -256, 256)
		inp.aim_y = clampi(dy * 256 / l, -256, 256)
	return [inp, best.is_empty()]


func _run(mode: String, force_triple: bool, force_spread: bool) -> void:
	var sim := SimWorld.new(0xC0FFEE, 1, mode)
	var p: Dictionary = sim.players[0]
	var dry := 0
	var shots := 0
	var rounds := 0
	var wasted := 0          # rounds spent on a tick with zero live enemies
	var no_target_ticks := 0
	var picked := 0
	var last_ammo: int = p["mg_ammo"]
	for t in TICKS:
		if force_triple:
			p["triple"] = true
		if force_spread:
			p["spread_ticks"] = 999999
		var r := _drive(sim, p)
		var inp: SimInput = r[0]
		var empty: bool = r[1]
		var before: int = p["mg_ammo"]
		sim.step([inp] as Array[SimInput])
		p = sim.players[0]
		var after: int = p["mg_ammo"]
		if after > before:
			picked += after - before
		else:
			rounds += before - after
			if empty:
				wasted += before - after
		for ev in sim.events:
			if ev["t"] == "shot":
				shots += 1
		if p["mg_ammo"] == 0:
			dry += 1
		if empty:
			no_target_ticks += 1
	var tag := "base"
	if force_triple and force_spread:
		tag = "triple+spread"
	elif force_triple:
		tag = "triple"
	print("%-14s %-8s shots=%4d rounds=%4d picked=%4d dry_ticks=%4d (%4.1f%%) no_target_ticks=%4d wasted_rounds=%4d (%4.1f%% of spend) ammo_end=%d"
		% [mode, tag, shots, rounds, picked, dry, 100.0 * dry / TICKS,
		   no_target_ticks, wasted, (100.0 * wasted / maxi(1, rounds)), p["mg_ammo"]])


func _init() -> void:
	print("MG_AMMO_MAX=%d  FIRE_COOLDOWN_TICKS=%d  -> %.1f s of continuous fire from a full mag"
		% [SimWorld.MG_AMMO_MAX, SimWorld.FIRE_COOLDOWN_TICKS,
		   float(SimWorld.MG_AMMO_MAX * SimWorld.FIRE_COOLDOWN_TICKS) / 60.0])
	print("run length = %d ticks (%.0f s)" % [TICKS, TICKS / 60.0])
	for m in ["campaign", "endless"]:
		_run(m, false, false)
		_run(m, true, false)
		_run(m, true, true)
	quit()
