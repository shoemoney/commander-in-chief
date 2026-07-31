extends SceneTree
## Boss Rush end-to-end probe: can the scripted bot finish it, and what does
## pacing look like per boss? Also records downs, stalls, observer activity.
func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2").split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 90000
	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "boss_rush")
		sim.god_mode = true
		var p: Dictionary = sim.players[0]
		var t := 0
		var downs := 0
		var prev_deaths: int = p["deaths"]
		var gates_opened := 0
		var boss_kill_ticks: Array = []
		var last_open_t := 0
		var observer_spawns := 0
		var strikes := 0
		var engage_t := -1
		var victory_t := -1
		var stall := 0
		var max_stall := 0
		var best_y: int = p["y"]
		var boss_hp0 := -1
		var boss_fight_start := -1
		var fight_lens: Array = []
		while t < maxt:
			var inp = MainScript.demo_input(t, sim)
			sim.step([inp])
			t += 1
			for ev in sim.events:
				match ev.get("t", ""):
					"gate_open":
						gates_opened += 1
						if boss_fight_start >= 0:
							fight_lens.append(t - boss_fight_start)
							boss_fight_start = -1
						last_open_t = t
					"observer_spawn":
						observer_spawns += 1
					"colossus_engage":
						engage_t = t
					"victory":
						victory_t = t
			if not sim.strikes.is_empty():
				strikes += 1
			# boss fight timer: a live unopened gate boss or colossus with hp
			for g in sim.gates:
				if not g["open"] and not g["boss"].is_empty() and g["boss"].get("alive", false):
					if boss_fight_start < 0 and sim.camera_top >= g["y"] - 400 * SimWorld.F_ONE:
						boss_fight_start = t
			if p["y"] < best_y:
				best_y = p["y"]
				stall = 0
			else:
				stall += 1
				max_stall = maxi(max_stall, stall)
			var d: int = p["deaths"]
			if d > prev_deaths:
				downs += d - prev_deaths
				prev_deaths = d
			if victory_t >= 0:
				break
		print("seed=%d ticks=%d gates=%d fight_lens=%s downs=%d max_stall=%d observer=%d strike_ticks=%d colossus_engage=%d victory=%s"
			% [sd, t, gates_opened, str(fight_lens), downs, max_stall, observer_spawns, strikes, engage_t, str(victory_t >= 0)])
	quit()
