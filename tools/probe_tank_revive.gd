extends SceneTree
## Verify: a tank DRIVER pressing E with a downed, affordable partner gets nothing.
## revive_context routes E to revive, but _step_players continues into _drive_tank
## before _try_revive — so the press is swallowed with no event at all.
func _init() -> void:
	var MainScript: Script = load("res://src/main.gd")
	var sim := SimWorld.new(0xC0FFEE, 2, "campaign")
	# Settle one tick so _init authoring is done.
	sim.step([SimInput.new(), SimInput.new()])
	var p1: Dictionary = sim.players[0]
	var p2: Dictionary = sim.players[1]
	# Park a live tank on P1 and board it.
	sim.tanks.append({"x": p1["x"], "y": p1["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "fire_cd": 0, "occupant": -1})
	var ti: int = sim.tanks.size() - 1
	var ib := SimInput.new()
	ib.interact = true
	sim.step([ib, SimInput.new()])
	print("boarded: in_tank=%d occupant=%d" % [p1["in_tank"], sim.tanks[ti]["occupant"]])
	# Fund the chest, down P2.
	sim.war_chest = 500
	sim._kill_player(p2)
	print("p2 alive=%s  chest=%d  revive_cost=%d  affordable=%s"
		% [str(p2["alive"]), sim.war_chest, sim.revive_cost(p2),
			str(sim.war_chest >= sim.revive_cost(p2))])
	print("revive_context(P1)=%s  (what main.gd would route E to)"
		% str(MainScript.revive_context(sim, 0)))
	# Press E exactly as _gather_inputs would after arbitration: revive=true, grenade=false.
	var revived := false
	var cannon := false
	var events_seen := []
	for t in 120:
		var inp := SimInput.new()
		inp.revive = t < 60   # hold E for a full second, then release
		sim.step([inp, SimInput.new()])
		for ev in sim.events:
			if ev.get("t", "") in ["revive", "revive_deny", "tank_shot"]:
				events_seen.append(ev["t"])
			if ev.get("t", "") == "revive":
				revived = true
			if ev.get("t", "") == "tank_shot":
				cannon = true
		if p2["alive"]:
			revived = true
			break
	print("after 120 ticks of E held: p2 alive=%s  revived=%s  cannon_fired=%s"
		% [str(p2["alive"]), str(revived), str(cannon)])
	print("revive-related events seen: %s" % str(events_seen))
	# Control: same press ON FOOT revives instantly.
	var sim2 := SimWorld.new(0xC0FFEE, 2, "campaign")
	sim2.step([SimInput.new(), SimInput.new()])
	sim2.war_chest = 500
	sim2._kill_player(sim2.players[1])
	var inp2 := SimInput.new()
	inp2.revive = true
	sim2.step([inp2, SimInput.new()])
	print("CONTROL on foot: p2 alive after 1 tick of E = %s" % str(sim2.players[1]["alive"]))
	quit()
