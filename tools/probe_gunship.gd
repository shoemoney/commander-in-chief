extends SceneTree
## Gunship fight-length probe. Two views of the same fight:
##   DUELIST - an aim-tracking player holding fire for DUTY percent of every
##             60-tick window (a human is never on target 100% of the time),
##             lobbing a grenade every 90 ticks. Reports ticks-to-kill, phase
##             entry ticks, strikes called per phase and bullets that left the boss.
##   BOT     - main.gd::demo_input in Boss Rush (the scripted bot's own fight
##             lengths and whether it still wins). Knockdowns measure the bot.
## Env: PLAYERS (1|2), DUTY (percent, default 45), WAVE (0 = campaign), SEEDS, BOT=1.
func _init() -> void:
	var players: int = int(OS.get_environment("PLAYERS")) if OS.has_environment("PLAYERS") else 1
	var duty: int = int(OS.get_environment("DUTY")) if OS.has_environment("DUTY") else 45
	var wave: int = int(OS.get_environment("WAVE")) if OS.has_environment("WAVE") else 0
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "1,2,3,4").split(","):
		seeds.append(int(s))
	for sd in seeds:
		_duel(sd, players, duty, wave)
	if OS.has_environment("BOT"):
		_bot()
	quit()


func _duel(sd: int, players: int, duty: int, wave: int) -> void:
	var sim := SimWorld.new(sd, players)
	sim.god_mode = true
	sim.wave = wave
	var gy: int = sim.camera_top + 100 * Fixed.ONE
	var hp: int = sim._scaled_boss_hp(SimWorld.BOSS_HP + (wave / 5 - 1 if wave >= 5 else 0) * (SimWorld.BOSS_HP / 2))
	var boss := {"alive": true, "hp": hp, "max_hp": hp, "x": 320 * Fixed.ONE,
		"dir": 1, "phase_t": 0, "gate_y": gy}
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	var t := 0
	var entered := {}
	var strikes_by_phase := [0, 0, 0, 0]
	var seen_strikes := {}
	while boss["alive"] and t < 12000:
		var ph := 1
		if boss["hp"] <= boss["max_hp"] / 3:
			ph = 3
		elif boss["hp"] <= boss["max_hp"] * 2 / 3:
			ph = 2
		if not entered.has(ph):
			entered[ph] = t
		var inputs: Array = []
		for p in sim.players:
			var inp := SimInput.new()
			var dx: int = boss["x"] - p["x"]
			inp.move_x = clampi(dx / Fixed.ONE * 8, -256, 256)
			var ay: int = gy - 40 * Fixed.ONE - p["y"]
			# Lead the drifting hull by the bullet's flight time, as a human does.
			var flight: int = absi(ay) / SimWorld.BULLET_SPEED
			dx += boss["dir"] * GunshipPhases.speed(ph, SimWorld.BOSS_SPEED) * flight
			var al: int = Fixed.length(dx, ay)
			if al > 0:
				inp.aim_x = clampi(Fixed.div(dx, al) / 256, -256, 256)
				inp.aim_y = clampi(Fixed.div(ay, al) / 256, -256, 256)
			inp.fire = (t % 60) < duty * 60 / 100
			inp.grenade = (t % 90) == 70
			inputs.append(inp)
		var n_before := sim.strikes.size()
		sim.step(inputs)
		for s in sim.strikes:
			if s["ticks"] == SimWorld.STRIKE_TELEGRAPH_TICKS - 1:
				strikes_by_phase[ph] += 1
		t += 1
	print("duel seed=%d players=%d duty=%d wave=%d hp=%d kill_tick=%d (%.1fs) phase_entry=%s strikes_by_phase=%s"
		% [sd, players, duty, wave, hp, t, t / 60.0, str(entered), str(strikes_by_phase.slice(1))])


func _bot() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var sim := SimWorld.new(0xC0FFEE, 1, "boss_rush")
	sim.god_mode = true
	var t := 0
	var start := -1
	var lens: Array = []
	var victory := false
	while t < 90000 and not victory:
		sim.step([MainScript.demo_input(t, sim)])
		t += 1
		for ev in sim.events:
			if ev.get("t", "") == "gate_open":
				if start >= 0:
					lens.append(t - start)
					start = -1
			elif ev.get("t", "") == "victory":
				victory = true
		for g in sim.gates:
			if not g["open"] and not g["boss"].is_empty() and g["boss"].get("alive", false):
				if start < 0 and sim.camera_top >= g["y"] - 400 * SimWorld.F_ONE:
					start = t
	print("bot boss_rush ticks=%d gunship_fight_lens=%s victory=%s" % [t, str(lens), str(victory)])
