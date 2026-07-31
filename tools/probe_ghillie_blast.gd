extends SceneTree
## Does _explode kill a CLOAKED (submerged) ghillie? The archetype comment claims the
## reveal/paint window is "the only time it can be killed at all", and the airstrike
## deliberately spares submerged enemies — check where the hand grenade lands.
func _init() -> void:
	var sim := SimWorld.new(7, 1, "campaign")
	sim.step([SimInput.new()])
	var p: Dictionary = sim.players[0]
	# Plant a cloaked ghillie 20px from the player (inside BLAST_KILL_RADIUS 30).
	sim._spawn_special(p["x"] + 20 * SimWorld.F_ONE, p["y"], "ghillie")
	var g: Dictionary = sim.enemies[sim.enemies.size() - 1]
	print("ghillie submerged=%s hp=%s" % [str(g.get("submerged", false)), str(g.get("hp", 1))])
	sim._explode(p["x"], p["y"], false, "probe")
	print("after grenade blast: alive=%s  (airstrike would have spared it: _fire_mission exempts submerged)"
		% str(g["alive"]))
	# Control: the same blast vs a REVEALED ghillie.
	var sim2 := SimWorld.new(7, 1, "campaign")
	sim2.step([SimInput.new()])
	sim2._spawn_special(sim2.players[0]["x"] + 20 * SimWorld.F_ONE, sim2.players[0]["y"], "ghillie")
	var g2: Dictionary = sim2.enemies[sim2.enemies.size() - 1]
	g2["submerged"] = false
	sim2._explode(sim2.players[0]["x"], sim2.players[0]["y"], false, "probe")
	print("control revealed ghillie: alive=%s" % str(g2["alive"]))
	quit()
