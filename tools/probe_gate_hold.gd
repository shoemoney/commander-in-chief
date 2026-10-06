extends SceneTree
## Headless gate-hold farm probe (1.3 sim fix).
## Drives a campaign sim to gate-1 hold, then idles 3000 ticks with zero inputs.
## HEAD: stall_ticks==0 (held guard gates stall increment), observer empty for
## 50s, +10 coin +2 kills from bunker drip while camera_held (24 bodies/600t).
## Fixed: stall accrues even while held (half-rate), and bunker/spawner drip
## throttles, so 3000 idle ticks see mortar telegraph and 0 coin.
##
## Run: tools/run_tests.sh -s res://tools/probe_gate_hold.gd

func _init() -> void:
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	sim.god_mode = true
	# Drive north to gate-1 hold (camera_top == g.y - GATE_CAMERA_PAD).
	var inp := SimInput.new()
	inp.move_y = -256
	var held_at := -1
	for t in 3000:
		sim.step([inp])
		if sim.camera_held():
			held_at = t
			break
	if held_at < 0:
		push_error("probe_gate_hold: never reached gate-1 hold in 3000 north ticks — camera_top %d, gates %d" % [sim.camera_top, sim.gates.size()])
		print("PROBE INCONCLUSIVE — could not reach hold")
		quit(1)
		return
	print("probe_gate_hold: reached hold at tick %d, camera_top %d" % [held_at, sim.camera_top])
	# Snapshot economy at hold entry
	var chest0: int = sim.war_chest
	var kills0: int = sim.score  # proxy; war_chest delta is the real gate
	var observer_seen := false
	var max_stall: int = sim.stall_ticks
	var kills: int = 0
	# Idle 3000 ticks with zero inputs (no fire, no move)
	var idle := SimInput.new()
	for t in 3000:
		var war_before: int = sim.war_chest
		var score_before: int = sim.score
		sim.step([idle])
		max_stall = maxi(max_stall, sim.stall_ticks)
		if not sim.observer.is_empty():
			observer_seen = true
		# count any coin gain as farm
		if sim.war_chest > chest0:
			pass
	# After 3000 idle ticks, check whip + economy
	var chest_delta: int = sim.war_chest - chest0
	var fail := false
	if max_stall <= 90 and not observer_seen:
		push_error("probe_gate_hold: stall whip absent — max stall_ticks %d (need >90) and observer never spawned over 3000 idle ticks while held" % max_stall)
		fail = true
	else:
		print("probe_gate_hold: whip OK — max_stall %d observer_seen %s" % [max_stall, observer_seen])
	if chest_delta != 0:
		push_error("probe_gate_hold: farm economy leaked — war_chest delta %d over 3000 idle held ticks (expected 0), kills proxy %d" % [chest_delta, sim.score - kills0])
		fail = true
	else:
		print("probe_gate_hold: economy OK — war_chest delta 0")
	# Second leg: 5000-tick north-push held ratio (info, but also gate)
	var sim2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	sim2.god_mode = true
	var held_ticks := 0
	for t in 5000:
		sim2.step([inp])
		if sim2.camera_held():
			held_ticks += 1
	var ratio: float = float(held_ticks) / 5000.0
	print("probe_gate_hold: north-push held %d/5000 (%.1f%%)" % [held_ticks, ratio * 100.0])
	if held_ticks >= 4700:
		# HEAD is 4692/5000 (93.8%). If still that high and stall never fired,
		# the gate is still a safe farm. This is secondary to the idle check,
		# so only flag if whip also absent.
		if max_stall <= 90 and not observer_seen:
			push_error("probe_gate_hold: 5000-tick north-push held %.1f%% — gate is still a safe farm with zero whip" % (ratio * 100.0))
			fail = true
	if fail:
		print("PROBE FAILED")
		quit(1)
		return
	print("PROBE OK — held stall whip fires and idle farm yields 0 coin over 3000t")
	quit(0)
