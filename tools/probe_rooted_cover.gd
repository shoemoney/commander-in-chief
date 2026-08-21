extends SceneTree
## Rooted-spawn cover census (dev tool, not part of the suite).
##
##   tools/run_tests.sh -s res://tools/probe_rooted_cover.gd
##   SEEDS=1,2,3 MAXT=9000 tools/run_tests.sh -s res://tools/probe_rooted_cover.gd
##
## Drives god-mode campaign AND endless runs with main.gd's `demo_input` bot and
## counts, per rooted archetype (ROOTED_KINDS never write x or y after birth),
## how many were BORN INSIDE geometry that _step_projectiles treats as armor.
## Such a unit is un-shootable from the arc its cover faces, and a revealed
## ghillie keeps `all_cloaked` false, so the force-reveal anti-stall cannot
## clear it and the wave stays open.
##
## The blocking predicate below is DELIBERATELY DUPLICATED from sim_world's
## projectile scan rather than calling `_spawn_cover_at`: this probe must run
## unchanged against a build that has no such helper, so the "before" number is
## measured by the same instrument as the "after" one.
##
## ⚠️ This is a SAMPLING instrument — it sees only the spawns this bot's run
## reaches. The spawn-seam ratchets in tests/test_spawn_cover.gd call the
## spawners directly and have no sampling window at all; they, not this census,
## are the gate.

const SLACK := 0   # census asks "inside the ARMOR box", not "inside box + slack"


func _in_cover(sim: SimWorld, x: int, y: int) -> String:
	for bk in sim.bunkers:
		if bk["alive"] and x >= bk["x"] - SLACK and x <= bk["x"] + SimWorld.BUNKER_W + SLACK \
				and y >= bk["y"] - SLACK and y <= bk["y"] + SimWorld.BUNKER_H + SLACK:
			return "bunker"
	for sb in sim.sandbags:
		if absi(x - sb["x"]) <= SimWorld._sb_hw(sb) + SLACK \
				and absi(y - sb["y"]) <= SimWorld._sb_hh(sb) + SLACK:
			return "sandbag"
	for hk in sim.tanks:
		if ((hk["alive"] and hk["occupant"] < 0) or (not hk["alive"] and hk["burn_ticks"] > 0)) \
				and absi(x - hk["x"]) <= SimWorld.HULK_HALF_W + SLACK \
				and absi(y - hk["y"]) <= SimWorld.HULK_HALF_H + SLACK:
			return "hulk"
	for rk in sim.rocks:
		if not SimWorld._rk_solid(rk):
			continue
		if absi(x - rk["x"]) <= SimWorld._rk_hw(rk) + SLACK \
				and absi(y - rk["y"]) <= SimWorld._rk_hh(rk) + SLACK:
			return "rock"
	return ""


func _seen(list: Array, e: Dictionary) -> bool:
	for s in list:
		if is_same(s, e):
			return true
	return false


func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	var raw := OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "0xC0FFEE,1,2,3,4,5,6,7"
	for s in raw.split(","):
		seeds.append(s.hex_to_int() if s.begins_with("0x") else int(s))
	var maxt: int = int(OS.get_environment("MAXT")) if OS.has_environment("MAXT") else 9000

	for mode in ["endless", "campaign"]:
		var total := 0
		var bad := 0
		var by_kind := {}
		var by_family := {}
		for sd in seeds:
			var sim := SimWorld.new(sd, 1, mode)
			sim.god_mode = true
			var seen: Array = []
			for t in maxt:
				var arr: Array[SimInput] = [MainScript.demo_input(t, sim)]
				sim.step(arr)
				for e in sim.enemies:
					if not SimWorld.ROOTED_KINDS.has(e["kind"]):
						continue
					if _seen(seen, e):
						continue
					seen.append(e)
					total += 1
					var k: String = e["kind"]
					var slot: Array = by_kind.get(k, [0, 0])
					slot[1] += 1
					var fam := _in_cover(sim, e["x"], e["y"])
					if fam != "":
						bad += 1
						slot[0] += 1
						by_family[fam] = by_family.get(fam, 0) + 1
					by_kind[k] = slot
		var pct := 0.0 if total == 0 else 100.0 * float(bad) / float(total)
		print("%-8s  rooted spawns %4d   born in cover %3d (%.1f%%)" % [mode, total, bad, pct])
		for k in by_kind:
			print("            %-10s %d/%d" % [k, by_kind[k][0], by_kind[k][1]])
		if not by_family.is_empty():
			print("            families: %s" % str(by_family))
	print("seeds=%s ticks=%d" % [str(seeds), maxt])
	quit(0)
