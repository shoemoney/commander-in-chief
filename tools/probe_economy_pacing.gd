extends SceneTree
## Economy/pacing probe (dev tool, not part of the suite).
##   tools/run_tests.sh -s res://tools/probe_economy_pacing.gd
## Prints: ticks-to-empty from 99 rounds per fan combination, the endless revive curve at
## waves 5/10/15/20 (2P, deaths 1/3/8/22), the streak bonus ladder, and the scripted bot's
## campaign score on 3 seeds (SEEDS=1,2,3 TICKS=6000 to override).


func _fire() -> SimInput:
	var i := SimInput.new()
	i.fire = true
	return i


func _tte(spread: bool, triple: bool) -> int:
	var sim := SimWorld.new(5, 1)
	var p: Dictionary = sim.players[0]
	p["spread_ticks"] = 100000 if spread else 0
	p["triple"] = triple
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	var t := 0
	while p["mg_ammo"] > 0 and t < 5000:
		p["hurt_iframes"] = 9999
		sim.step([_fire()])
		t += 1
	return t


func _init() -> void:
	print("TTE base=%d trench=%d triple=%d both=%d" % [_tte(false, false), _tte(true, false), _tte(false, true), _tte(true, true)])
	var sim := SimWorld.new(9, 2, "endless")
	var p: Dictionary = sim.players[0]
	for w in [5, 10, 15, 20]:
		sim.wave = w
		var row := "REVIVE w%d:" % w
		for d in [1, 3, 8, 22]:
			p["deaths"] = d
			row += " d%d=%d" % [d, sim.revive_cost(p)]
		print(row)
	var s2 := SimWorld.new(7, 1)
	var base := SimWorld.COIN_RUSHER * 10
	var row2 := "STREAK last-kill score (base %d):" % base
	var prev := 0
	for n in [4, 1, 5, 10, 20, 20, 40, 40]:
		var last := 0
		for k in n:
			var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
			s2.enemies.append(e)
			var s0: int = s2.score
			s2._kill_enemy(e)
			last = s2.score - s0
		prev += n
		row2 += " @%d=%d" % [prev, last]
	print(row2)
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "1,2,3").split(","):
		seeds.append(int(s))
	var maxt: int = int(OS.get_environment("TICKS")) if OS.has_environment("TICKS") else 40000
	for sd in seeds:
		var w := SimWorld.new(sd, 1, "campaign")
		var best := 0
		var t := 0
		while t < maxt and not w.victory and not w.wiped:
			var arr: Array[SimInput] = [MainScript.demo_input(t, w)]
			w.step(arr)
			t += 1
			best = maxi(best, w.kill_streak)
		print("BOT seed=%d ticks=%d victory=%s wiped=%s score=%d best_streak=%d" % [sd, t, w.victory, w.wiped, w.score, best])
	quit()
