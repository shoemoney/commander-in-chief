extends SceneTree
## Endless-variety probe (dev tool, not part of the suite).
##   tools/run_tests.sh -s res://tools/probe_endless_variety.gd
## Prints (1) per-wave tiered-roster threat vs the old roster and the compensation bodies
## (when EndlessRoster exists), (2) the kinds a staged wave actually fields, and (3) how far
## the scripted bot gets in Endless on SEEDS (default 1,2,3) within TICKS (default 14000),
## with each wave's start tick. Section 3 runs unchanged on the pre-tiering tree, which is
## how the before/after numbers in the commit body were taken.


func _kinds_of_wave(seed_v: int, w: int) -> Dictionary:
	var sim := SimWorld.new(seed_v, 1, "endless")
	sim.step([SimInput.new()])
	sim.wave = w - 1
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.intermission_ticks = 0
	sim._start_wave()
	var seen: Array = []
	var kinds := {}
	var guard := 0
	while sim.wave_pending > 0 and guard < 6000:
		guard += 1
		sim.step([SimInput.new()])
		for p in sim.players:
			p["alive"] = true
			p["hurt_iframes"] = 600
		for e in sim.enemies:
			if e["kind"] == "pilot":
				continue
			var known := false
			for s in seen:
				if is_same(s, e):
					known = true
					break
			if not known:
				seen.append(e)
				kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
		if sim.enemies.size() > 40:
			sim.enemies.clear()
	return kinds


func _init() -> void:
	if ResourceLoader.exists("res://src/sim/endless_roster.gd"):
		var R: Script = load("res://src/sim/endless_roster.gd")
		print("WAVE  budget(old->new)  threat x10 (old->new)  debut")
		for w in range(1, 21):
			print("w%-3d %3d -> %3d        %5d -> %5d        %s" % [w, R.base_total(w), R.wave_budget(w),
				R.threat_old(w), R.threat_new(w), R.debut_kind(w)])
		for w in [3, 4, 6, 8, 9, 11, 12, 14]:
			print("KINDS seed=11 w%d: %s" % [w, str(_kinds_of_wave(11, w))])
	var MainScript: Script = load("res://src/main.gd")
	var seeds: Array = []
	for s in (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "1,2,3").split(","):
		seeds.append(int(s))
	var maxt: int = int(OS.get_environment("TICKS")) if OS.has_environment("TICKS") else 14000
	for sd in seeds:
		var w := SimWorld.new(sd, 1, "endless")
		var starts := {}
		var t := 0
		while t < maxt and not w.wiped:
			var arr: Array[SimInput] = [MainScript.demo_input(t, w)]
			w.step(arr)
			t += 1
			if not starts.has(w.wave):
				starts[w.wave] = t
		print("BOT seed=%d ticks=%d wave=%d wiped=%s score=%d starts=%s" % [sd, t, w.wave, w.wiped, w.score, str(starts)])
	quit()
