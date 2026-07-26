extends SceneTree
## Sector difficulty telemetry probe (dev tool, not part of the suite).
##
##   godot --headless --path . -s res://tools/sector_probe.gd
##   SEEDS=0xC0FFEE,1,2  MAXT=40000  godot --headless ... -s res://tools/sector_probe.gd
##
## Drives a god-mode campaign with main.gd's scripted `demo_input` bot and reports,
## per sector (band |y|/GATE_SPACING + 1): knockdowns, ticks spent, how many of those
## ticks made NO northward progress, and KILLS BY THE PLAYER. God mode never ends the
## run, so a wall shows up as ticks+stalls instead of a truncated log.
##
## ⚠️ KNOCKDOWNS ALONE DO NOT MEASURE DIFFICULTY — they measure this bot. `demo_input`
## aims OPEN-LOOP, so anything small and drifting beats it regardless of how fair the
## fight is: one 40 HP gunship once absorbed 6,200 ticks and 35 of 41 knockdowns while
## the code budgets it at 150-320. A whole session was spent "fixing" a sector that was
## never hard. So this also reports KILLS, which separates the two cases:
##   many knockdowns + normal kills  -> real pressure, the sector is genuinely costly
##   many knockdowns + FEW kills     -> the bot cannot land shots here; measuring the
##                                      instrument, not the game. Do NOT tune on it.
## `offense` below is kills per 1000 ticks, which is the number to compare across
## sectors — it is roughly flat when the bot is fighting normally and collapses where it
## is only being hit.
##
## JSON_OUT=/abs/path.json writes the medians machine-readably, so a caller can DIFF two
## runs. Deltas are the trustworthy signal: an absolute "too hard" verdict from a
## scripted bot is unanchored, but "sector 3 went 19 -> 31 knockdowns since the last
## measurement" is real regardless of how good the bot is.

func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2,3").split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 40000

	var agg_k := {}
	var agg_t := {}
	var agg_s := {}
	var per_seed_k := {}    # sector -> Array of per-seed knockdowns (for the median)
	var per_seed_t := {}
	var per_seed_x := {}    # sector -> Array of per-seed KILLS BY the player
	var agg_x := {}
	var scores: Array = []
	var finished := 0
	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "campaign")
		sim.god_mode = true
		var p: Dictionary = sim.players[0]
		var deaths := {}
		var ticks := {}
		var stalls := {}
		var kills := {}
		var best_y: int = p["y"]
		var prev_deaths: int = p["deaths"]
		var t := 0
		var vic_t := -1
		while t < maxt:
			var inp = MainScript.demo_input(t, sim)
			var arr: Array[SimInput] = [inp]
			sim.step(arr)
			p = sim.players[0]
			var sec: int = absi(p["y"]) / SimWorld.GATE_SPACING + 1
			ticks[sec] = ticks.get(sec, 0) + 1
			if p["y"] < best_y:
				best_y = p["y"]
			else:
				stalls[sec] = stalls.get(sec, 0) + 1
			for ev in sim.events:
				if ev.get("t", "") == "kill":
					kills[sec] = kills.get(sec, 0) + 1
			var d: int = p["deaths"]
			if d > prev_deaths:
				deaths[sec] = deaths.get(sec, 0) + (d - prev_deaths)
				prev_deaths = d
			if OS.has_environment("DUMPT") and t == int(OS.get_environment("DUMPT")):
				print("DUMP @t=%d player=(%d,%d) alive=%s cam=%d" % [
					t, p["x"] / SimWorld.F_ONE, p["y"] / SimWorld.F_ONE, str(p["alive"]),
					sim.camera_top / SimWorld.F_ONE])
				for nm in ["rocks", "sandbags", "barrels", "bunkers", "waters", "gates", "tanks", "mines"]:
					for e in sim.get(nm):
						if absi(e.get("x", 1 << 40) - p["x"]) < 220 * SimWorld.F_ONE \
								and absi(e.get("y", 1 << 40) - p["y"]) < 220 * SimWorld.F_ONE:
							print("   %-9s (%4d,%6d) %s" % [nm, e["x"] / SimWorld.F_ONE,
								e["y"] / SimWorld.F_ONE, str(e)])
				print("   choke=%s" % str(sim._choke_bounds(p["y"])))
				for g in sim.gates:
					print("   gate y=%-7d open=%s fork_x=%s" % [g["y"] / SimWorld.F_ONE,
						str(g["open"]), str(g.get("fork_x", 0))])
			if OS.has_environment("DETAIL") and t % int(OS.get_environment("DETAIL")) == 0:
				var bstat := "-"
				for g in sim.gates:
					if not g["open"] and not g["boss"].is_empty():
						bstat = "boss@%d hp=%d alive=%s" % [g["y"] / SimWorld.F_ONE,
							g["boss"]["hp"], str(g["boss"]["alive"])]
				var closed := 0
				for g in sim.gates:
					if not g["open"] and g["y"] >= sim.camera_top and g["y"] <= sim.camera_top + 360 * SimWorld.F_ONE:
						closed += 1
				var bk := ""
				for b in sim.bunkers:
					if b["alive"] and absi(b["y"] - p["y"]) < 400 * SimWorld.F_ONE:
						bk += " bunker(%d,%d)" % [b["x"] / SimWorld.F_ONE, b["y"] / SimWorld.F_ONE]
				print("   t=%-6d x=%-5d y=%-7d off=%-5d alive=%d best=%-7d cam=%-7d closed=%d deaths=%d %s%s" % [
					t, p["x"] / SimWorld.F_ONE, p["y"] / SimWorld.F_ONE,
					(absi(p["y"]) % SimWorld.GATE_SPACING) / SimWorld.F_ONE, int(p["alive"]),
					best_y / SimWorld.F_ONE, sim.camera_top / SimWorld.F_ONE, closed, d, bstat, bk])
			t += 1
			if sim.victory:
				vic_t = t
				break
		var line := "seed 0x%X  victory=%s @t=%d  score=%d  deaths=%d" % [
			sd, str(sim.victory), vic_t, sim.score, p["deaths"]]
		print(line)
		var keys: Array = ticks.keys()
		keys.sort()
		for k in keys:
			print("   s%-2d  kills_of_you=%-4d your_kills=%-4d ticks=%-6d stalled=%-6d (%d%%)" % [
				k, deaths.get(k, 0), kills.get(k, 0), ticks[k], stalls.get(k, 0),
				100 * stalls.get(k, 0) / maxi(1, ticks[k])])
			agg_k[k] = agg_k.get(k, 0) + deaths.get(k, 0)
			agg_t[k] = agg_t.get(k, 0) + ticks[k]
			agg_s[k] = agg_s.get(k, 0) + stalls.get(k, 0)
			if not per_seed_k.has(k):
				per_seed_k[k] = []
				per_seed_t[k] = []
				per_seed_x[k] = []
			per_seed_k[k].append(deaths.get(k, 0))
			per_seed_t[k].append(ticks[k])
			per_seed_x[k].append(kills.get(k, 0))
			agg_x[k] = agg_x.get(k, 0) + kills.get(k, 0)
		scores.append(sim.score)
		if sim.victory:
			finished += 1
	print("\n=== AGGREGATE over %d seeds ===" % seeds.size())
	var ak: Array = agg_t.keys()
	ak.sort()
	var tot := 0
	for k in ak:
		tot += agg_k[k]
	for k in ak:
		print("s%-2d  knockdowns=%-5d (%2d%%)  ticks=%-7d stalled=%-7d (%d%%)" % [
			k, agg_k.get(k, 0), 100 * agg_k.get(k, 0) / maxi(1, tot),
			agg_t[k], agg_s.get(k, 0), 100 * agg_s.get(k, 0) / maxi(1, agg_t[k])])
	print("total knockdowns=%d   campaigns finished: %d/%d" % [tot, finished, seeds.size()])
	# MEDIAN is the honest headline for this instrument. `demo_input` is an open-loop
	# scripted bot, so one seed that traps it against geometry can own most of the
	# mean — the sum row above is a trap detector, not a difficulty curve.
	print("--- per-sector MEDIAN across seeds (offense = your kills per 1000 ticks) ---")
	var rows: Array = []
	for k in ak:
		var mk: int = _median(per_seed_k[k])
		var mt: int = _median(per_seed_t[k])
		var mx: int = _median(per_seed_x[k])
		var off: int = 1000 * mx / maxi(1, mt)
		print("s%-2d  knockdowns=%-4d ticks=%-6d your_kills=%-4d offense=%d/1000t" % [k, mk, mt, mx, off])
		rows.append({"sector": k, "knockdowns": mk, "ticks": mt, "kills": mx, "offense": off})
	# The discriminator, stated rather than left to the reader: a sector that costs a lot
	# AND fights normally is hard; one that costs a lot while offense collapses is beating
	# the bot's aim, not the player. Flag it here so nobody tunes on the wrong one.
	var off_all: Array = []
	for r in rows:
		off_all.append(r["offense"])
	var off_med: int = _median(off_all)
	for r in rows:
		var costly: bool = r["knockdowns"] > 0 and r["knockdowns"] >= 2 * _median(per_seed_k[ak[0]])
		if r["offense"] * 2 < off_med and r["ticks"] > 0:
			print("  ⚠️ s%d: offense %d vs median %d — SUSPECT THE INSTRUMENT, not the difficulty"
				% [r["sector"], r["offense"], off_med])
		elif costly:
			print("  → s%d: costly WITH normal offense — real pressure" % r["sector"])
	if OS.has_environment("JSON_OUT"):
		var out := {"seeds": seeds.size(), "finished": finished, "total_knockdowns": tot,
			"score_median": _median(scores), "offense_median": off_med, "sectors": rows}
		var f := FileAccess.open(OS.get_environment("JSON_OUT"), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(out, "\t"))
			f.close()
			print("\nwrote %s" % OS.get_environment("JSON_OUT"))
		else:
			print("\nFAILED to write %s" % OS.get_environment("JSON_OUT"))
	quit(0)


func _median(a: Array) -> int:
	if a.is_empty():
		return 0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]
