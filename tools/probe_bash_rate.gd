extends SceneTree
## SUSTAINED kill rate: the free empty-clip BASH vs the paid MG, against
## deep-endless veteran armor. Wave machinery is parked (intermission_ticks held
## high => _step_waves early-returns, nothing spawns), and a fresh armored body is
## re-planted the instant the last one dies, so both weapons are measured at their
## real cadence over the same window.
##
##   godot --headless --path . -s res://tools/probe_bash_rate.gd

const WINDOW := 1200   # 20 s

func _plant(sim, p: Dictionary, hp: int, reach_px: int) -> Dictionary:
	var e := {"x": p["x"], "y": p["y"] - reach_px * SimWorld.F_ONE, "alive": true,
		"elite": false, "kind": "rusher", "hp": hp, "fire_cd": 1 << 28,
		"windup": 0, "aim_lx": 0, "aim_ly": 0, "submerged": false,
		"surface_ticks": 0, "face_x": 0, "face_y": SimWorld.F_ONE,
		"spd_mul": 0, "hits": 0}
	sim.enemies.append(e)
	return e


func _rate(wave: int, use_gun: bool) -> Array:
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim.wave = wave
	var hp: int = 1 + sim._wave_armor()
	var p: Dictionary = sim.players[0]
	sim.enemies.clear(); sim.bunkers.clear(); sim.mines.clear()
	sim.barrels.clear(); sim.rocks.clear(); sim.sandbags.clear()
	sim.pickups.clear()
	var reach: int = 60 if use_gun else 12
	var cur := _plant(sim, p, hp, reach)
	var kills := 0
	var rounds := 0
	var chest0: int = sim.war_chest
	for t in WINDOW:
		sim.intermission_ticks = 1 << 20   # park the wave machine: no spawns, no wave logic
		if not cur["alive"]:
			kills += 1
			cur = _plant(sim, p, hp, reach)
		cur["x"] = p["x"]
		cur["y"] = p["y"] - reach * SimWorld.F_ONE
		if use_gun:
			p["mg_ammo"] = SimWorld.MG_AMMO_MAX     # infinite ammo: measure the WEAPON, not the wallet
		else:
			p["mg_ammo"] = 0                        # hold the empty-clip state the bash needs
		var before: int = p["mg_ammo"]
		var inp := SimInput.new()
		inp.fire = true
		inp.aim_y = -256
		sim.step([inp] as Array[SimInput])
		p = sim.players[0]
		if use_gun:
			rounds += maxi(0, before - int(p["mg_ammo"]))
		if not p["alive"]:
			break
	if not cur["alive"]:
		kills += 1
	return [kills, rounds, hp, sim.war_chest - chest0]


func _init() -> void:
	print("Sustained over %d ticks (%.0f s). BASH_COOLDOWN=%d, FIRE_COOLDOWN=%d."
		% [WINDOW, WINDOW / 60.0, SimWorld.BASH_COOLDOWN_TICKS, SimWorld.FIRE_COOLDOWN_TICKS])
	print("%-6s %-4s | %-9s %-8s %-7s | %-9s %-7s | %s"
		% ["wave", "hp", "GUN kills", "rounds", "coin", "BASH kills", "coin", "winner"])
	for w in [1, 13, 19, 25, 31, 37, 43, 50, 75, 100]:
		var g := _rate(w, true)
		var b := _rate(w, false)
		var winner := "GUN" if g[0] > b[0] else ("BASH" if b[0] > g[0] else "tie")
		print("%-6d %-4d | %-9d %-8d %-7d | %-9d %-7d | %s"
			% [w, g[2], g[0], g[1], g[3], b[0], b[3], winner])
	print("")
	print("Armor bypass check: does ONE bash kill a body carrying full veteran armor?")
	for w in [13, 50, 100]:
		var sim := SimWorld.new(0xC0FFEE, 1, "endless")
		sim.wave = w
		var p: Dictionary = sim.players[0]
		sim.enemies.clear(); sim.bunkers.clear(); sim.mines.clear()
		sim.barrels.clear(); sim.rocks.clear(); sim.sandbags.clear()
		var hp: int = 1 + sim._wave_armor()
		var e := _plant(sim, p, hp, 12)
		p["mg_ammo"] = 0
		sim.intermission_ticks = 1 << 20
		var inp := SimInput.new()
		inp.fire = true
		inp.aim_y = -256
		sim.step([inp] as Array[SimInput])
		print("  wave %-4d hp %-3d -> after ONE bash tick: alive=%s hp=%s"
			% [w, hp, str(e["alive"]), str(e.get("hp", "?"))])
	quit()
