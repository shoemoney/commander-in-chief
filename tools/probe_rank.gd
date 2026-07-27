extends SceneTree
## RANK CANVAS — what letters real runs actually earn.
##
## Drives main.gd::demo_input (the headless combat bot) through every mode and
## calls the SHIPPED main.gd::_run_rank() on the result, so the numbers below can
## never drift from the grade the player is shown. Two passes per seed:
##
##   god  — cost-free ceiling: the run cannot end, so mvp climbs to the mode's roof.
##   real — no god mode: the run ends when it ends, knockdowns are counted from
##          the `player_down` events, i.e. the distribution a player actually lives.
##
## Output is CSV; tests/test_view_honesty.gd::MEASURED_RUNS is pasted from it.
## Re-run after any scoring/pacing change and re-anchor main.gd::RANK_BANDS.
##
##   godot --headless --path . -s res://tools/probe_rank.gd

const MAX_TICKS := 40000        # 3.0x the longest measured campaign completion (13,364 ticks)
const SEEDS := [1, 2, 3, 4, 5]
const MODES := ["campaign", "endless", "boss_rush", "arcade"]


func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	print("mode,seed,god,ticks,victory,kills,streak,gates,wave,knockdowns,grade,title")
	for mode in MODES:
		for sd in SEEDS:
			for god in [true, false]:
				var sim := SimWorld.new(sd, 1, mode)
				sim.god_mode = god
				var kills := 0
				var streak := 0
				var downs := 0
				var t := 0
				while t < MAX_TICKS:
					sim.step([MainScript.demo_input(t, sim)] as Array[SimInput])
					for ev in sim.events:
						match ev.get("t", ""):
							"kill": kills += 1
							"player_down": downs += 1
					streak = maxi(streak, sim.kill_streak)
					t += 1
					# god mode clears the wipe latch on its own heartbeat — breaking on a
					# transient `wiped` there would truncate the ceiling run at its first
					# knockdown streak, which is exactly what the ceiling is not about.
					if sim.victory or (sim.wiped and not god):
						break
				var opened := 0
				for g in sim.gates:
					if g["open"]:
						opened += 1
				# The shipped grader, driven exactly as the debrief card drives it.
				var m = MainScript.new()
				m.sim = sim
				m._run_kills = kills
				m._run_best_streak = streak
				m._run_knockdowns = downs
				var rr: Dictionary = m._run_rank()
				m.free()
				print("%s,%d,%s,%d,%s,%d,%d,%d,%d,%d,%s,%s" % [mode, sd, str(god), t,
					str(sim.victory), kills, streak, opened, sim.wave, downs,
					rr["grade"], rr["title"]])
	quit()
