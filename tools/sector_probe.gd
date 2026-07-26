extends SceneTree
## Sector difficulty telemetry probe (dev tool, not part of the suite).
##
##   godot --headless --path . -s res://tools/sector_probe.gd
##   SEEDS=0xC0FFEE,1,2  MAXT=40000  godot --headless ... -s res://tools/sector_probe.gd
##
## Drives a god-mode campaign with main.gd's scripted `demo_input` bot and reports,
## per sector (band |y|/GATE_SPACING + 1): knockdowns, ticks spent, and how many of
## those ticks made NO northward progress. God mode never ends the run, so a wall
## shows up as ticks+stalls instead of a truncated log.

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
	var finished := 0
	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "campaign")
		sim.god_mode = true
		var p: Dictionary = sim.players[0]
		var deaths := {}
		var ticks := {}
		var stalls := {}
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
			print("   s%-2d  kills_of_you=%-4d ticks=%-6d stalled=%-6d (%d%%)" % [
				k, deaths.get(k, 0), ticks[k], stalls.get(k, 0),
				100 * stalls.get(k, 0) / maxi(1, ticks[k])])
			agg_k[k] = agg_k.get(k, 0) + deaths.get(k, 0)
			agg_t[k] = agg_t.get(k, 0) + ticks[k]
			agg_s[k] = agg_s.get(k, 0) + stalls.get(k, 0)
			if not per_seed_k.has(k):
				per_seed_k[k] = []
				per_seed_t[k] = []
			per_seed_k[k].append(deaths.get(k, 0))
			per_seed_t[k].append(ticks[k])
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
	print("--- per-sector MEDIAN across seeds ---")
	for k in ak:
		print("s%-2d  knockdowns=%-4d ticks=%d" % [k, _median(per_seed_k[k]), _median(per_seed_t[k])])
	quit(0)


func _median(a: Array) -> int:
	if a.is_empty():
		return 0
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]
