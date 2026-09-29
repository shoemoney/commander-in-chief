extends "res://tools/screenshots.gd"
## QA-only milestone setups, not store screenshots. The simulation produces the
## kill and payout; the real event consumer creates and ages the visual receipt.

func _build_shots() -> void:
	shots = [
		{"name": "tier5", "build": _world, "dress": func(m): _milestone(m, 5, 0)},
		{"name": "tier10", "build": _world, "dress": func(m): _milestone(m, 10, 0)},
		{"name": "tier20", "build": _world, "dress": func(m): _milestone(m, 20, 0)},
		{"name": "settled", "build": _world, "dress": func(m): _milestone(m, 5, 16)},
		{"name": "expired", "build": _world, "dress": func(m): _milestone(m, 5, 65)},
	]


func _world() -> SimWorld:
	return SimWorld.new(7, 1, "endless")


func _milestone(m: Node2D, tier: int, age: int) -> void:
	m._motion = 0.0
	m._hint_t = 0.0
	m._streak_popped = 0
	m.sim.kill_streak = tier - 1
	m.sim.kill_streak_timer = SimWorld.KILL_STREAK_WINDOW_TICKS
	var p: Dictionary = m.sim.players[0]
	var enemy := {"x": p["x"] + 55 * Fixed.ONE, "y": p["y"] - 32 * Fixed.ONE,
		"alive": true, "elite": true, "kind": "elite"}
	m.sim.enemies.append(enemy)
	m.sim._kill_enemy(enemy)
	m._consume_events()
	for tick in age:
		m._hitstop_frames = 0
		m._update_feel()
	var receipt_count := 0
	for fx in m._fx:
		if fx.get("role", "") == "streak":
			receipt_count += 1
			print("STREAK RECEIPT ", fx["text"], " age=", fx["t"])
	if receipt_count != (0 if age >= 65 else 1):
		push_error("streak QA: expected one active receipt, then none after expiry")
		quit(1)
		return
	print("STREAK QA tier=%d age=%d receipts=%d" % [tier, age, receipt_count])
