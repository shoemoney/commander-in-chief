extends SceneTree
## WHICH GATES DOES THE 60s DETERMINISM TORTURE ACTUALLY CONSTRUCT? (dev tool.)
##
## Several sim comments justified a change as "torture-inert — never streams past
## gate 1", which is the difference between "GOLDEN cannot move" and "GOLDEN must be
## re-recorded". Those claims went stale as the run got faster, and a stale one sends
## you hunting a determinism break that is really just expected churn. Run this
## instead of trusting the comment: as of 2026-07-25 it reports gate 1 @tick 0,
## gate 2 @tick 1309, gate 3 @tick 3108, camera_top ending at -2563 px.
##
## Cross-check the first tick a gate appears against SAMPLE_EVERY (600) to predict
## exactly which GOLDEN samples an edit to that gate's content can move.
##
##   godot --headless --path . -s res://tools/probe_torture_gates.gd

func _init() -> void:
	var Det: Script = load("res://tests/test_determinism.gd")
	var sim := SimWorld.new(0xC0FFEE, 2)
	var seen := {}
	for tick in 3600:
		var inputs: Array = [Det.scripted_input(tick, 0), Det.scripted_input(tick, 1)]
		sim.step(inputs)
		for g in sim.gates:
			var no: int = absi(g["y"] / SimWorld.GATE_SPACING)
			if not seen.has(no):
				seen[no] = tick
	var keys: Array = seen.keys()
	keys.sort()
	print("gates constructed during the 3600-tick torture (gate_no: first tick seen):")
	for k in keys:
		print("  gate %d  @tick %d" % [k, seen[k]])
	print("camera_top at end: %d px" % (sim.camera_top / SimWorld.F_ONE))
	print("northmost gate streamed: %d" % (keys[-1] if keys.size() > 0 else -1))
	print("ARENAS-templated gates that streamed: %s"
		% [keys.filter(func(k): return SimWorld.ARENAS.has(k))])
	quit()
