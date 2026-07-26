extends SceneTree
## Cooldown-runaway probe (dev tool, not part of the suite).
##
##   godot --headless --path . -s res://tools/probe_cd_clamp.gd
##   SEEDS=0xC0FFEE,1,2  MAXT=40000  godot --headless ... -s res://tools/probe_cd_clamp.gd
##
## Both `bk["spawn_cd"]` and `colossus["spawn_cd"]` decrement every tick but only
## reset when `enemies.size() < MAX_ENEMIES`, so a full field drives them negative
## with no floor — the same shape as the spray_cd bug already fixed at
## sim_world.gd:5341. The question this answers is whether the roster ACTUALLY
## saturates in play, because an unreachable branch is not a defect.
##
## Reports, per seed: the most-negative value each cooldown reached, the peak
## roster size, and how many ticks were spent at the cap. The bunker figure is
## the one that matters — main.gd:6130 renders `1 - spawn_cd/120` as a hatch
## charge glow, so a negative there is a telegraph drawn at full brightness for
## a spawn that is blocked.

func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2").split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 30000

	for mode in ["campaign", "endless"]:
		for sd in seeds:
			var sim := SimWorld.new(sd, 1, mode)
			sim.god_mode = true
			var min_bunker: int = 0
			var min_colossus: int = 0
			var peak_roster: int = 0
			var capped_ticks: int = 0
			var charge_lies: int = 0    # ticks where a live bunker drew a >100% charge glow
			var t := 0
			while t < maxt:
				sim.step([MainScript.demo_input(t, sim)] as Array[SimInput])
				var n: int = sim.enemies.size()
				peak_roster = maxi(peak_roster, n)
				if n >= SimWorld.MAX_ENEMIES:
					capped_ticks += 1
				for bk in sim.bunkers:
					if not bk["alive"]:
						continue
					min_bunker = mini(min_bunker, bk["spawn_cd"])
					if bk["spawn_cd"] < 0:
						charge_lies += 1
				if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
					min_colossus = mini(min_colossus, int(sim.colossus["spawn_cd"]))
				if sim.victory:
					break
				t += 1
			print("%-9s seed=%-9d ticks=%-6d peak_roster=%-3d capped_ticks=%-6d min_bunker_cd=%-7d min_colossus_cd=%-7d bunker_glow_lie_ticks=%d"
				% [mode, sd, t, peak_roster, capped_ticks, min_bunker, min_colossus, charge_lies])
	quit()
