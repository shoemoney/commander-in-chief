extends SceneTree
## SECTOR_STANDUPS calibration sweep (dev tool, not part of the suite).
##
##   tools/run_tests.sh -s res://tools/probe_standup_budget.gd
##   SEEDS=0,1,2  NS=4,5,6  MAXT=40000  tools/run_tests.sh -s res://tools/probe_standup_budget.gd
##
## Answers the ONE question SECTOR_STANDUPS has to be calibrated against: at budget N, is a
## campaign run still WINNABLE and still LOSABLE? A budget nobody ever hits is the infinite
## rally it replaced; a budget everybody hits in sector 1 is not a game.
##
## ONE PASS PER SEED covers every N. The shipped budget is a `const`, so it cannot be swept
## from a probe — instead this drives a normal (NOT god-mode) campaign with main.gd's
## scripted `demo_input` bot, keeps its own SHADOW knockdown counter, and each tick clamps
## `sim.deaths_since_gate` below SECTOR_STANDUPS so the sim's own budget can never fire.
## The clamp is gameplay-inert: the only other reader is the Flawless Gate bonus, which
## tests `deaths_since_gate == 0`, and the clamp never maps a non-zero count onto zero.
## The shadow is then replayed against every candidate N offline.
##
## ⚠️ INSTRUMENT LIMIT, same one sector_probe.gd carries: `demo_input` aims OPEN-LOOP.
## Its knockdowns are not a player's knockdowns, and a run it loses is not proof a person
## would. Read the numbers as a DELTA across N, never as an absolute difficulty verdict.

func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2,3,4,5,6,7").split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var ns: Array = []
	for s in (OS.get_environment("NS") if OS.has_environment("NS") else "4,5,6,7,8,9,10").split(","):
		ns.append(int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 40000
	var cap: int = SimWorld.SECTOR_STANDUPS - 1   # the clamp ceiling: the sim can never reach its own budget

	# n -> {"win": x, "wipe": y, "last_stand": z, "wipe_ticks": [...]}
	var tally := {}
	for n in ns:
		tally[n] = {"win": 0, "wipe": 0, "last_stand": 0, "wipe_ticks": []}
	var run_ticks: Array = []
	var knockdowns: Array = []
	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "campaign")
		sim.god_mode = false
		var shadow := 0
		var prev_deaths := 0
		var t := 0
		var vic_t := -1
		# n -> [tick, last_stand] of the first moment budget n would have ended this run
		var first := {}
		while t < maxt:
			var inp = MainScript.demo_input(t, sim)
			var arr: Array[SimInput] = [inp]
			sim.step(arr)
			t += 1
			for ev in sim.events:
				if ev.get("t", "") == "gate_open":
					shadow = 0
					prev_deaths = _deaths(sim)
			var d := _deaths(sim)
			if d > prev_deaths:
				shadow += d - prev_deaths
				prev_deaths = d
			# Neutralize the SHIPPED budget so one pass can be replayed against every
			# candidate N. Inert for the Flawless Gate (its only other reader tests == 0).
			sim.deaths_since_gate = mini(shadow, cap)
			var down := true
			for p in sim.players:
				if p["alive"]:
					down = false
			for n in ns:
				if not first.has(n) and down and shadow >= n:
					first[n] = [t, sim.last_stand]
			if sim.victory:
				vic_t = t
				break
			if sim.wiped:
				break
		run_ticks.append(t)
		knockdowns.append(_deaths(sim))
		for n in ns:
			var wt: int = first[n][0] if first.has(n) else -1
			if vic_t >= 0 and (wt < 0 or vic_t <= wt):
				tally[n]["win"] += 1
			elif wt >= 0:
				tally[n]["wipe"] += 1
				tally[n]["wipe_ticks"].append(wt)
				if bool(first[n][1]):
					tally[n]["last_stand"] += 1
		print("seed %d: %d ticks, %d knockdowns, victory=%s wiped=%s  first-wipe-by-N=%s" % [
			sd, t, _deaths(sim), str(vic_t >= 0), str(sim.wiped), str(first)])
	print("")
	print("  N   win/%d  wipe  of-which-at-the-finale  median-wipe-tick   verdict" % seeds.size())
	for n in ns:
		var row: Dictionary = tally[n]
		var wts: Array = row["wipe_ticks"]
		wts.sort()
		var med: int = int(wts[wts.size() / 2]) if wts.size() > 0 else -1
		var pre_finale: int = int(row["wipe"]) - int(row["last_stand"])
		# "Losable but winnable": the smallest N where >=25% of seeds still reach victory
		# AND >=25% wipe with last_stand == false (i.e. lost BEFORE the Colossus).
		var ok: bool = float(row["win"]) / float(seeds.size()) >= 0.25 \
			and float(pre_finale) / float(seeds.size()) >= 0.25
		print("  %-3d %5d   %4d   %20d   %14d   %s" % [
			n, row["win"], row["wipe"], row["last_stand"], med, "LOSABLE+WINNABLE" if ok else "-"])
	run_ticks.sort()
	knockdowns.sort()
	print("")
	print("longest run %d ticks, median %d; knockdowns median %d, max %d" % [
		run_ticks[-1], run_ticks[run_ticks.size() / 2],
		knockdowns[knockdowns.size() / 2], knockdowns[-1]])
	quit()


func _deaths(sim: SimWorld) -> int:
	var n := 0
	for p in sim.players:
		n += int(p["deaths"])
	return n
