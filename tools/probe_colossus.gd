extends SceneTree
## Colossus finale pacing probe (dev tool, not part of the suite).
## Jumps an arcade world to the final chapter, god-mode on, and drives the
## scripted demo_input bot through the finale. Reports: ticks to engage,
## ticks from engage to kill, downs, grenades thrown, grenade hits vs MG hits
## on the colossus, core windows seen, supply drops taken, deaths by cause
## (crush vs shot vs strike, best effort), and whether the fight stalls.
##
##   tools/run_tests.sh -s res://tools/probe_colossus.gd
##   SEEDS=0xC0FFEE,1 MAXT=60000 tools/run_tests.sh -s res://tools/probe_colossus.gd

func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2,3").split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 60000

	for sd in seeds:
		var sim := SimWorld.new(sd, 1, "arcade")
		sim.god_mode = true
		sim.jump_to_chapter(SimWorld.FINAL_GATE_INDEX)
		var p: Dictionary = sim.players[0]
		var t := 0
		var engage_t := -1
		var kill_t := -1
		var downs0: int = p["deaths"]
		var downs := 0
		var nades0: int = p["grenade_ammo"]
		var nades_thrown := 0
		var core_opens := 0
		var last_core_cd := -1
		var prev_gn: int = p["grenade_ammo"]
		var strikes_on_player := 0
		var crush_downs := 0
		var spray_downs := 0
		var last_hp := -1
		var stall_ticks := 0
		var max_stall := 0
		var drops_seen := 0
		var pk_before: int = sim.pickups.size()
		var drop_collects := 0
		while t < maxt:
			var inp = MainScript.demo_input(t, sim)
			sim.step([inp])
			t += 1
			# grenade-throw accounting (ammo decrement with a throw event)
			if p["grenade_ammo"] < prev_gn:
				nades_thrown += 1
			prev_gn = p["grenade_ammo"]
			for ev in sim.events:
				if ev["t"] == "colossus_engage" and engage_t < 0:
					engage_t = t
					last_hp = sim.colossus["hp"]
				elif ev["t"] == "core_open":
					core_opens += 1
				elif ev["t"] == "player_down":
					downs += 1
				elif ev["t"] == "supply_drop":
					drops_seen += 1
				elif ev["t"] == "pickup" and engage_t >= 0:
					drop_collects += 1
				elif ev["t"] == "victory":
					kill_t = t
			# siege grenade packs spawn silently: count new kind-1 pickups that
			# appear after engage with no supply_drop event
			if engage_t >= 0 and sim.pickups.size() > pk_before:
				for pi in range(pk_before, sim.pickups.size()):
					if sim.pickups[pi].get("kind", -1) == 1:
						drops_seen += 1
			pk_before = sim.pickups.size()
			if engage_t >= 0 and kill_t < 0:
				if sim.colossus["hp"] == last_hp:
					stall_ticks += 1
					max_stall = maxi(max_stall, stall_ticks)
				else:
					stall_ticks = 0
					last_hp = sim.colossus["hp"]
			if kill_t >= 0:
				break
		print("seed=%d engage_t=%d fight_ticks=%d downs=%d nades=%d core_opens=%d max_hp_stall=%d siege_drops=%d collects=%d victory=%s"
			% [sd, engage_t, (kill_t - engage_t) if kill_t >= 0 else -1, downs,
				nades_thrown, core_opens, max_stall, drops_seen, drop_collects, str(kill_t >= 0)])
	quit()
