extends SceneTree
## Siege Tank probes. Two views, selected by env:
##   (default) DUEL   - an aim-tracking player (hold fire DUTY% of every 60 ticks, a grenade
##                      every GREN ticks, lobbed from ~80 px) against the staged boss.
##                      Reports ticks-to-kill, act entry ticks and the share of ticks the rear
##                      window was open. Env: PLAYERS, DUTY, GREN, SEEDS.
##   CAMPAIGN=1       - the scripted bot (main.gd demo_input) through a whole god-mode campaign:
##                      ticks to victory (or the cap) and the tick each gate opened. This part
##                      uses only SimWorld + demo_input, so it also runs on a tree without the
##                      Siege Tank (the "before" numbers). Env: SEEDS, CAP.
func _init() -> void:
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "1,2,3").split(","):
		seeds.append(int(s))
	if OS.has_environment("CAMPAIGN"):
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
