extends SceneTree
## Siege Tank probes. Two views, selected by env:
##   (default) DUEL   - an aim-tracking player (hold fire DUTY% of every 60 ticks, a grenade
##                      every GREN ticks, lobbed from ~80 px) against the staged boss.
##                      Reports ticks-to-kill, act entry ticks and the share of ticks the rear
##                      window was open. Env: PLAYERS, DUTY, GREN, SEEDS.
##   STARVED=1        - REAL AMMO ECONOMY (god mode OFF): a 1P player starts at the staged gate with 0
##                      grenades and 0 coins, goes for the arena's grenade crate, lobs from ~85 px
##                      and fetches again. Reports kill tick, deaths, grenades thrown and crate
##                      re-arms. NOREARM=1 deletes every crate after the first pickup, which is the
##                      pre-fix arena (the crate was a one-shot). Env: SEEDS, CAP.
##   WALL=1           - stationary-player sweep over the arena (x 60..540, rows from the gate wall
##                      down): for each post, which of charge / MG fan / shell reached him over a
##                      2-act fight. Prints the posts NOT reached by the charge or the fan.
##   CAMPAIGN=1       - the scripted bot (main.gd demo_input) through a whole god-mode campaign:
##                      ticks to victory (or the cap) and the tick each gate opened. This part
##                      uses only SimWorld + demo_input, so it also runs on a tree without the
##                      Siege Tank (the "before" numbers). Env: SEEDS, CAP.
func _init() -> void:
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "1,2,3").split(","):
		seeds.append(int(s))
	if OS.has_environment("STARVED"):
		var cap2: int = int(OS.get_environment("CAP")) if OS.has_environment("CAP") else 12000
		for sd in seeds:
			_starved(sd, cap2, OS.has_environment("NOREARM"))
	elif OS.has_environment("WALL"):
		_wall_sweep()
	elif OS.has_environment("CAMPAIGN"):
		var cap: int = int(OS.get_environment("CAP")) if OS.has_environment("CAP") else 24000
		for sd in seeds:
			_campaign(sd, cap)
	else:
		var players: int = int(OS.get_environment("PLAYERS")) if OS.has_environment("PLAYERS") else 1
		var duty: int = int(OS.get_environment("DUTY")) if OS.has_environment("DUTY") else 45
		var gren: int = int(OS.get_environment("GREN")) if OS.has_environment("GREN") else 90
		for sd in seeds:
			_duel(sd, players, duty, gren)
	quit()


func _duel(sd: int, players: int, duty: int, gren: int) -> void:
	var sim := SimWorld.new(sd, players)
	sim.god_mode = true
	var gy: int = sim.camera_top + 100 * Fixed.ONE
	var hp: int = sim._scaled_boss_hp(SiegeBoss.HP)
	sim.rocks.clear()
	sim.sandbags.clear()
	var boss := SiegeBoss.make(gy, hp)
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	sim._stamp_siege_cover(gy)
	var t := 0
	var entered := {}
	var open_ticks := 0
	var thrown := 0
	var prev_g: int = sim.players[0]["grenade_ammo"]
	while boss["alive"] and t < 12000:
		var act: int = SiegeBoss.act_of(boss)
		if not entered.has(act):
			entered[act] = t
		if SiegeBoss.weak_open(boss):
			open_ticks += 1
		var inputs: Array = []
		for p in sim.players:
			var inp := SimInput.new()
			# Stand ~90 px south of the hull, track it sideways, aim at the rear plate when open.
			var tx: int = boss["x"]
			var ty: int = boss["y"]
			if SiegeBoss.weak_open(boss):
				var w := SiegeBoss.weak_point(boss)
				tx = w[0]
				ty = w[1]
			inp.move_x = clampi((boss["x"] - p["x"]) / Fixed.ONE * 8, -256, 256)
			inp.move_y = clampi((boss["y"] + 90 * Fixed.ONE - p["y"]) / Fixed.ONE * 8, -256, 256)
			var ax: int = tx - p["x"]
			var ay: int = ty - p["y"]
			var al: int = Fixed.length(ax, ay)
			if al > 0:
				inp.aim_x = clampi(Fixed.div(ax, al) / 256, -256, 256)
				inp.aim_y = clampi(Fixed.div(ay, al) / 256, -256, 256)
			inp.fire = (t % 60) < duty * 60 / 100
			inp.grenade = (t % gren) == gren - 20
			inp.roll = SiegeBoss.lane(boss).get("live", false) and (t % 30) == 0
			inputs.append(inp)
		sim.step(inputs)
		if sim.players[0]["grenade_ammo"] < prev_g:
			thrown += prev_g - sim.players[0]["grenade_ammo"]
		prev_g = sim.players[0]["grenade_ammo"]
		t += 1
	print("siege duel seed=%d players=%d hp=%d kill_tick=%d (%.1fs) act_entry=%s window_open=%d%% grenades_thrown=%d (every %d) duty=%d"
		% [sd, players, hp, t, t / 60.0, str(entered), open_ticks * 100 / maxi(1, t), thrown, gren, duty])


func _campaign(sd: int, cap: int) -> void:
	var MainScript: Script = load("res://src/main.gd")
	var sim := SimWorld.new(sd, 1, "campaign")
	sim.god_mode = true
	var t := 0
	var opened: Array = []
	var victory := false
	var seen_open := 0
	while t < cap and not victory:
		sim.step([MainScript.demo_input(t, sim)])
		t += 1
		for ev in sim.events:
			if ev.get("t", "") == "gate_open":
				opened.append(t)
			elif ev.get("t", "") == "victory":
				victory = true
	var bosses := 0
	for g in sim.gates:
		if not g["boss"].is_empty() and g["open"]:
			bosses += 1
	print("bot campaign seed=%d ticks=%d victory=%s gates_opened=%s boss_gates_opened=%d" % [sd, t, str(victory), str(opened), bosses])


func _starved(sd: int, cap: int, norearm: bool) -> void:
	var sim := SimWorld.new(sd, 1)
	var gy: int = sim.camera_top + 100 * Fixed.ONE
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.pickups.clear()
	var boss := SiegeBoss.make(gy, sim._scaled_boss_hp(SiegeBoss.HP))
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	sim._stamp_siege_cover(gy)
	var p: Dictionary = sim.players[0]
	p["grenade_ammo"] = 0
	p["x"] = 320 * Fixed.ONE
	p["y"] = gy + 210 * Fixed.ONE
	sim.war_chest = 0
	var t := 0
	var deaths := 0
	var deaths_act1 := 0
	var was_alive := true
	var thrown := 0
	var prev_g := 0
	var crates := 0
	var taken_once := false
	var prev_crates := 0
	var act1_end := -1
	while boss["alive"] and t < cap:
		sim.enemies.clear()   # isolate the boss AMMO economy from the field spawner (the boss escorts spawn after this)
		var inp := SimInput.new()
		var crate: Array = []
		for pk in sim.pickups:
			if pk["kind"] == 1 and int(pk.get("cost", 0)) == 0:
				crate = [pk["x"], pk["y"]]
		var tx: int = boss["x"]
		var ty: int = boss["y"] + 85 * Fixed.ONE
		if p["grenade_ammo"] == 0 and not crate.is_empty():
			tx = crate[0]
			ty = crate[1]
		var mx: int = (tx - p["x"]) / Fixed.ONE * 8
		var my: int = (ty - p["y"]) / Fixed.ONE * 8
		# Dodge by ROLLING (i-frames) when a shell is about to land on top of us.
		var dodge := false
		for st in sim.strikes:
			if st["ticks"] <= 14 and absi((p["x"] - st["x"]) / Fixed.ONE) < 45 and absi((p["y"] - st["y"]) / Fixed.ONE) < 45:
				dodge = true
		inp.move_x = clampi(mx, -256, 256)
		inp.move_y = clampi(my, -256, 256)
		var ax: int = boss["x"] - p["x"]
		var ay: int = boss["y"] - p["y"]
		var al: int = Fixed.length(ax, ay)
		if al > 0:
			inp.aim_x = clampi(Fixed.div(ax, al) / 256, -256, 256)
			inp.aim_y = clampi(Fixed.div(ay, al) / 256, -256, 256)
		inp.fire = true
		inp.grenade = p["grenade_ammo"] > 0 and al < 120 * Fixed.ONE and (t % 40) == 0   # a one-tick press: the grenade is held while the button is down
		inp.roll = dodge or (SiegeBoss.lane(boss).get("live", false) and (t % 30) == 0)
		sim.step([inp])
		if OS.has_environment("TRACE") and t % 30 == 0 and t < 1500:
			print(t, " p=", p["x"] / Fixed.ONE, ",", p["y"] / Fixed.ONE, " alive=", p["alive"], " g=", p["grenade_ammo"], " boss=", boss["x"] / Fixed.ONE, ",", boss["y"] / Fixed.ONE, " st=", boss["st"], " strikes=", sim.strikes.size(), " en=", sim.enemies.size(), " crate=", crate)
		if p["alive"] != was_alive:
			if not p["alive"]:
				deaths += 1
				if act1_end < 0:
					deaths_act1 += 1
			was_alive = p["alive"]
		if p["grenade_ammo"] < prev_g:
			thrown += prev_g - p["grenade_ammo"]
		prev_g = p["grenade_ammo"]
		var n := 0
		for pk in sim.pickups:
			if pk["kind"] == 1 and int(pk.get("cost", 0)) == 0:
				n += 1
		if n > prev_crates and taken_once:
			crates += 1
		if n < prev_crates:
			taken_once = true
		if norearm and taken_once:
			for pi in range(sim.pickups.size() - 1, -1, -1):
				if sim.pickups[pi]["kind"] == 1 and int(sim.pickups[pi].get("cost", 0)) == 0:
					sim.pickups.remove_at(pi)
			n = 0
		prev_crates = n
		if act1_end < 0 and SiegeBoss.act_of(boss) > 1:
			act1_end = t
		t += 1
	print("siege STARVED seed=%d norearm=%s boss_dead=%s ticks=%d (%.1fs) act1_end=%d deaths=%d (in act 1: %d) grenades_thrown=%d crate_rearms=%s boss_hp=%d/%d"
		% [sd, str(norearm), str(not boss["alive"]), t, t / 60.0, act1_end, deaths, deaths_act1, thrown, "n/a" if norearm else str(crates), boss["hp"], boss["max_hp"]])


func _wall_sweep() -> void:
	var F := Fixed.ONE
	for dy in [14, 30, 60, 130, 200, 280]:
		var row := ""
		for px in range(60, 600, 60):
			var charge := false
			var fan := false
			var shell := false
			for act in [2, 3]:
				var sim := SimWorld.new(41, 1)
				var gy: int = sim.camera_top + 100 * F
				sim.rocks.clear()
				sim.sandbags.clear()
				sim.god_mode = true
				var boss := SiegeBoss.make(gy, sim._scaled_boss_hp(SiegeBoss.HP))
				var mx: int = boss["max_hp"]
				boss["hp"] = [mx, mx * 2 / 3, mx / 3][act - 1]
				sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
				var p: Dictionary = sim.players[0]
				p["x"] = px * F
				p["y"] = gy + dy * F
				for _t in 1800:
					SiegeBoss.step(sim, boss)
					if boss["st"] == SiegeBoss.St.CHARGE and SiegeBoss._near(p["x"], p["y"], boss["x"], boss["y"], SiegeBoss.RAM_R):
						charge = true
					if boss["st"] == SiegeBoss.St.SWEEP and boss["st_t"] % SiegeBoss.SWEEP_FIRE_EVERY == 0:
						var d := SiegeBoss.fan_dir(boss["fx"], boss["fy"], SiegeBoss.beam_index(boss))
						var m := SiegeBoss._muzzle(boss)
						var rx: int = p["x"] - m[0]
						var ry: int = p["y"] - m[1]
						var along := Fixed.mul(rx, d[0]) + Fixed.mul(ry, d[1])
						if along > 0 and along <= SiegeBoss.SWEEP_RANGE and absi(Fixed.mul(rx, d[1]) - Fixed.mul(ry, d[0])) <= 9 * F:
							fan = true
				for st in sim.strikes:
					if SiegeBoss._near(st["x"], st["y"], p["x"], p["y"], SimWorld.GRENADE_RADIUS):
						shell = true
			row += " %s%s%s" % ["C" if charge else ".", "F" if fan else ".", "S" if shell else "."]
		print("dy=%3d %s" % [dy, row])
