extends RefCounted
## Zone gates: hard walls that become checkpoints when their arena falls.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_world_streams_gate_arena() -> void:
	var sim := SimWorld.new(21, 1)
	sim.step([_idle()])
	Runner.T.ok(sim.gates.size() >= 1, "first gate streamed in ahead of the scroll")
	var g := sim.gates[0]
	Runner.T.eq(g["y"], -SimWorld.GATE_SPACING, "gate at the 1000-unit line")
	Runner.T.ok(g["b1"]["alive"] and g["b2"]["alive"], "gate arena bunkers alive")
	Runner.T.ok(sim.tanks.size() >= 1, "a tank is parked between gates")


func test_closed_gate_blocks_player_and_camera() -> void:
	var sim := SimWorld.new(21, 1)
	var p := sim.players[0]
	var up := SimInput.new()
	up.move_y = -256
	for i in 600:
		sim.step([up])
		if not p["alive"]:
			break
	var g := sim.gates[0]
	if p["alive"]:
		Runner.T.ok(p["y"] >= g["y"] + SimWorld.GATE_BLOCK_PAD, "player held south of the closed gate")
	Runner.T.ok(sim.camera_top >= g["y"] - SimWorld.GATE_CAMERA_PAD, "camera held at the closed gate")


func test_gate_opens_and_sets_checkpoint() -> void:
	var sim := SimWorld.new(21, 1)
	sim.step([_idle()])
	var g := sim.gates[0]
	Runner.T.eq(sim.last_gate_y, 0, "no checkpoint before any gate opens")
	g["b1"]["alive"] = false
	g["b2"]["alive"] = false
	sim.step([_idle()])
	Runner.T.ok(g["open"], "gate opened once both arena bunkers fell")
	Runner.T.eq(sim.last_gate_y, g["y"], "checkpoint recorded at the gate")


func test_broke_respawn_uses_checkpoint() -> void:
	var sim := SimWorld.new(21, 1)
	var p := sim.players[0]
	sim.step([_idle()])
	var g := sim.gates[0]
	g["b1"]["alive"] = false
	g["b2"]["alive"] = false
	sim.step([_idle()])
	# March the camera past the gate so the checkpoint is meaningfully north.
	var up := SimInput.new()
	up.move_y = -256
	for i in 500:
		sim.step([up])
	# Die broke: no coin, revive denied, timer respawn at the gate line.
	sim.war_chest = 0
	sim._kill_player(p)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive])
	Runner.T.ok(p["broke_timer"] > 0, "broke timer armed")
	for i in SimWorld.BROKE_RESPAWN_TICKS:
		sim.step([_idle()])
		if p["alive"]:
			break
	Runner.T.ok(p["alive"], "broke fallback respawned player")
	# The respawn targets the checkpoint, clamped into the view at the respawn
	# tick; the ratchet may then follow the respawned player within the same
	# step, so assert the invariants rather than re-deriving the exact clamp:
	# never north of the checkpoint line, and always inside the current view.
	Runner.T.ok(p["y"] >= sim.last_gate_y + 30 * Fixed.ONE, "respawn never north of the checkpoint")
	Runner.T.ok(p["y"] >= sim.camera_top + 16 * Fixed.ONE
		and p["y"] <= sim.camera_top + 344 * Fixed.ONE, "respawn inside the current view")
