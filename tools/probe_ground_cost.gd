extends SceneTree
## Ground-track cost probe: microseconds per SCROLLING frame of GroundStructure.plan (the
## per-frame work behind main._paint_ground_structure), plus its split into the lane rows and
## the dressing pass. Run: godot --headless --path . -s res://tools/probe_ground_cost.gd
## Dev tool only. Headless debug build numbers are a ratio, not a shipped-frame budget.

const FRAMES := 600


func _init() -> void:
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var anc := GroundStructure.anchors(sim.gates, sim.waters, SimWorld.WATER_H / float(Fixed.ONE), 1.0 / float(Fixed.ONE))
	var gys: Array = []
	for g in sim.gates:
		gys.append(float(g["y"]) / float(Fixed.ONE))
	var ford := func(b: int) -> int: return SimWorld.ford_half_w(b)
	var h := SimWorld.WATER_H / float(Fixed.ONE)
	# scroll through sector 3 at 1.5 px/frame (a real run advances about 0.5-2 px per frame)
	var cam := -3000.0
	GroundStructure.plan(anc, gys, sim.waters, cam, h, ford)   # warm
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		cam -= 1.5
		GroundStructure.plan(anc, gys, sim.waters, cam, h, ford)
	var us := float(Time.get_ticks_usec() - t0) / float(FRAMES)
	print("PROBE ground plan: %.0f us per scrolling frame (%d frames, 1.5 px/frame)" % [us, FRAMES])
	var p := GroundStructure.plan(anc, gys, sim.waters, cam, h, ford)
	print("PROBE lane rows=%d  rows computed in last plan=%d" % [p["lane"].size(), GroundStructure.rows_computed])
	var canvas := Node2D.new()
	GroundStructure._paint_lane(canvas, p["lane"])
	print("PROBE lane canvas commands issued by paint = %d (vertices %d)" % [GroundStructure.lane_commands, GroundStructure.lane_vertex_count])
	canvas.free()
	quit()
