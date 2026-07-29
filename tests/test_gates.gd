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
		# STAY broke for the whole window — that is this test's premise, and it is no
		# longer free. Now that the field keeps advancing on a downed player, enemies
		# walk onto the streamed mines and bank coin with nobody shooting: measured
		# chest 0 -> 40 by tick 187, which is >= the 25 solo revive cost, so
		# _step_dead_player's (correct, deliberate) re-affordability check DISARMED the
		# fallback and the player waited for a self-revive press that this test never
		# sends. Pinning the chest keeps the assertion about the fallback.
		sim.war_chest = 0
		sim.step([_idle()])
		if p["alive"]:
			break
	Runner.T.ok(p["alive"], "broke fallback respawned player")
	# The respawn targets the checkpoint, clamped into the view at the respawn
	# tick; the ratchet may then follow the respawned player within the same
	# step, so assert the invariants rather than re-deriving the exact clamp:
	# never north of the checkpoint line, and always inside the current view.
	# If the player out-marched the checkpoint off the bottom of the screen, the
	# never-retreating ratchet caps the respawn at the south view edge (you can't
	# spawn off-screen south), so the reachable floor is min(checkpoint, view bottom).
	Runner.T.ok(p["y"] >= mini(sim.last_gate_y + 30 * Fixed.ONE, sim.camera_top + 344 * Fixed.ONE),
		"respawn never north of the checkpoint (clamped into the current view)")
	Runner.T.ok(p["y"] >= sim.camera_top + 16 * Fixed.ONE
		and p["y"] <= sim.camera_top + 344 * Fixed.ONE, "respawn inside the current view")


func test_flawless_gate_pays_bonus_only_when_deathless() -> void:
	# Opening a checkpoint with zero deaths since the last one pays +50/+2000.
	var sim := SimWorld.new(11, 1, "campaign")
	sim.gates.clear()
	sim.gates.append({"y": 100 * Fixed.ONE, "open": false,
		"b1": {"alive": false}, "b2": {"alive": false}, "boss": {}})
	sim.deaths_since_gate = 0
	var chest0 := sim.war_chest
	var score0 := sim.score
	sim._step_gates()
	Runner.T.ok(sim.gates[0]["open"], "gate with two dead bunkers opens")
	Runner.T.eq(sim.war_chest - chest0, 50, "flawless gate paid the chest bonus")
	Runner.T.eq(sim.score - score0, 2000, "flawless gate paid the score bonus")
	# A death since the last gate forfeits it.
	var sim2 := SimWorld.new(11, 1, "campaign")
	sim2.gates.clear()
	sim2.gates.append({"y": 100 * Fixed.ONE, "open": false,
		"b1": {"alive": false}, "b2": {"alive": false}, "boss": {}})
	sim2.deaths_since_gate = 1
	var score0b := sim2.score
	sim2._step_gates()
	Runner.T.eq(sim2.score - score0b, 0, "a death since the last gate forfeits the bonus")


func test_flawless_streak_compounds_and_resets_on_death() -> void:
	var sim := SimWorld.new(13, 1, "campaign")
	sim.gates = [{"y": 100 * Fixed.ONE, "open": false,
		"b1": {"alive": false}, "b2": {"alive": false}, "boss": {}}]
	sim.deaths_since_gate = 0
	var s0 := sim.score
	sim._step_gates()
	Runner.T.eq(sim.score - s0, 2000, "first flawless gate pays 1×")
	Runner.T.eq(sim.flawless_streak, 1, "flawless streak = 1")
	sim.gates = [{"y": 200 * Fixed.ONE, "open": false,
		"b1": {"alive": false}, "b2": {"alive": false}, "boss": {}}]
	sim.deaths_since_gate = 0
	var s1 := sim.score
	sim._step_gates()
	Runner.T.eq(sim.score - s1, 4000, "second consecutive flawless gate pays 2×")
	sim._kill_player(sim.players[0])
	Runner.T.eq(sim.flawless_streak, 0, "a death resets the flawless streak")


func test_every_campaign_sector_is_the_same_length() -> void:
	# The DIFFICULTY-RAMP ratchet. A 2026-07-25 telemetry study opened with the
	# hypothesis that one sector was ~3x its neighbours in length and that this was
	# why it owned ~48% of all knockdowns. It is not: GATE_SPACING is a single
	# constant and every sector is exactly one of them, so the "one sector is
	# longer" accident cannot exist by construction — the real cause was the
	# scripted probe bot, which could not aim at the gate-3 gunship.
	#
	# That makes this cheap to keep true, and expensive to rediscover if it stops
	# being true: per-sector spacing is exactly the kind of knob someone adds to
	# "make the finale feel bigger", and it would silently reshape the whole ramp.
	# If you deliberately want uneven sectors, this test is the conversation.
	var sim := SimWorld.new(21, 1)
	# Scroll far enough to stream the whole authored gate run.
	for i in SimWorld.FINAL_GATE_INDEX + 1:
		sim.camera_top = -(i * SimWorld.GATE_SPACING) - 2 * SimWorld.VIEW_H
		sim._step_camera()
	var ys: Array[int] = []
	for g in sim.gates:
		ys.append(g["y"])
	ys.sort()
	ys.reverse()   # -1000, -2000, ... (nearest gate first)
	Runner.T.ok(ys.size() >= 3, "at least three gates streamed to compare")
	Runner.T.eq(ys[0], -SimWorld.GATE_SPACING, "the first gate sits one spacing north of the start")
	for i in range(1, ys.size()):
		Runner.T.eq(ys[i - 1] - ys[i], SimWorld.GATE_SPACING,
			"sector %d is exactly one GATE_SPACING long, like every other" % i)


func test_gate_open_never_snaps_the_camera() -> void:
	## A gate opening removes its camera hold in ONE tick. The ratchet used to
	## take the whole accumulated backlog (up to 186px hugging the wall) in that
	## tick — an uninterpolated jump, and in 2P a teleport of the trailing player.
	var sim := SimWorld.new(21, 1)
	sim.step([_idle()])
	var g := sim.gates[0]
	var p := sim.players[0]
	# Teleport to the gate instead of fighting 17 s of campaign to reach it, then
	# park the player hard against it — the worst case, where `desired` sits a
	# full CAMERA_LEAD - GATE_BLOCK_PAD (186px) north of the hold.
	sim.camera_top = g["y"] - SimWorld.GATE_CAMERA_PAD + 200 * SimWorld.F_ONE
	for _i in 200:
		sim.enemies.clear()
		sim.enemy_bullets.clear()   # this is a camera test, not a survival test
		p["y"] = g["y"] + SimWorld.GATE_BLOCK_PAD
		sim.step([_idle()])
	Runner.T.eq(sim.camera_top, g["y"] - SimWorld.GATE_CAMERA_PAD,
		"camera parked exactly at the closed gate's hold")
	g["b1"]["alive"] = false
	g["b2"]["alive"] = false
	var worst := 0
	for _i in 120:
		var before: int = sim.camera_top
		sim.enemies.clear()
		sim.enemy_bullets.clear()
		p["y"] = g["y"] + SimWorld.GATE_BLOCK_PAD
		sim.step([_idle()])
		worst = maxi(worst, before - sim.camera_top)   # north = decreasing y
	Runner.T.ok(g["open"], "the gate opened, dropping its camera hold in one tick")
	Runner.T.ok(worst <= SimWorld.MAX_CAM_STEP,
		"camera never moved more than MAX_CAM_STEP in one tick (worst %d, limit %d)"
			% [worst, SimWorld.MAX_CAM_STEP])
	Runner.T.eq(sim.camera_top, p["y"] - SimWorld.CAMERA_LEAD,
		"...and the rate limit still caught all the way up, it did not stall behind the player")
