extends SceneTree
# sim_world.gd:3629 claims "campaign never spawns a mast -> golden-inert" for the
# Broadcast Tower rally aura. SECTOR_SPECIALS[4] (CRASHED CONVOY) lists "broadcast".
func _init() -> void:
	for ch in [5, 6]:
		var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
		sim.god_mode = true
		sim.jump_to_chapter(ch - 1)
		var masts := 0
		for t in 6000:
			var inp := SimInput.new()
			inp.move_y = -256
			inp.aim_y = -256
			sim.step([inp])
			for ev in sim.events:
				if ev["t"] == "rooted_spawn" and String(ev.get("kind", "")) == "broadcast":
					masts += 1
		print("campaign chapter %d, 6000 ticks: broadcast masts spawned = %d" % [ch, masts])
	quit(0)
