extends SceneTree
# Does the Mortar Observer that spawns while the camera is HELD ever exist?
# _step_observer spawns it in the `observer.is_empty()` arm, then the NEXT tick's
# else-arm despawns it unconditionally when `held` — so it can live 1 tick and
# fire nothing, while main.gd has already played the alarm, the VO and the
# full-screen banner "MORTAR OBSERVER — SHOOT IT DOWN".

func _init() -> void:
	var tot_spawn := 0
	var tot_ghost := 0
	var tot_strikes := 0
	var tot_born_held := 0
	var lives: Array[int] = []
	for s in [0xC0FFEE, 0xBEEF01, 0x51EED2, 0xA11CE3, 0x1234AB, 0x99FEED]:
		var sim := SimWorld.new(s, 1, "campaign")
		sim.god_mode = true
		var spawns := 0
		var ghosts := 0
		var strikes := 0
		var life := -1
		var born_h := 0
		var born_held := false
		for t in 12000:
			var held_before: bool = sim.camera_held()
			var obs_before: bool = not sim.observer.is_empty()
			sim.step([_drive(sim)])
			for ev in sim.events:
				if ev["t"] == "observer_spawn":
					spawns += 1
					life = 0
					born_held = held_before
					if born_held:
						born_h += 1
				if ev["t"] == "strike" and ev.get("obs", false):
					strikes += 1
			if life >= 0:
				if sim.observer.is_empty():
					lives.append(life)
					if life <= 2:
						ghosts += 1
					life = -1
				else:
					life += 1
		tot_spawn += spawns
		tot_ghost += ghosts
		tot_strikes += strikes
		tot_born_held += born_h
		print("seed 0x%X  observer_spawn banners=%d  died within 2 ticks=%d  observer mortars actually telegraphed=%d  born while camera HELD=%d" % [
			s, spawns, ghosts, strikes, born_h])
	var avg := 0.0
	for l in lives:
		avg += float(l)
	if lives.size() > 0:
		avg /= float(lives.size())
	print("")
	print("TOTAL  banners=%d  ghost(<=2 ticks)=%d (%.0f%%)  mean observer lifetime=%.1f ticks  mortars=%d" % [
		tot_spawn, tot_ghost, 100.0 * tot_ghost / maxi(1, tot_spawn), avg, tot_strikes])
	print("banners fired while the camera was HELD (unwinnable order) = %d of %d" % [tot_born_held, tot_spawn])
	print("OBSERVER_STRIKE_CD_TICKS=%d — an observer must live this long to fire once." % SimWorld.OBSERVER_STRIKE_CD_TICKS)
	quit(0)


func _drive(sim: SimWorld) -> SimInput:
	var inp := SimInput.new()
	var p: Dictionary = sim.players[0]
	inp.move_y = -256
	var bx := 0
	var by := -256
	var best := 1 << 62
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var d: int = absi(e["x"] - p["x"]) + absi(e["y"] - p["y"])
		if d < best:
			best = d; bx = e["x"] - p["x"]; by = e["y"] - p["y"]
	var m: int = maxi(absi(bx), absi(by))
	if m > 0:
		inp.aim_x = (bx * 256) / m
		inp.aim_y = (by * 256) / m
	inp.fire = true
	var nb := {}
	var nbd := 1 << 62
	for bk in sim.bunkers:
		if not bk["alive"]:
			continue
		var cx: int = bk["x"] + SimWorld.BUNKER_W / 2
		var cy: int = bk["y"] + SimWorld.BUNKER_H / 2
		var d2: int = absi(cx - p["x"]) + absi(cy - p["y"])
		if d2 < nbd:
			nbd = d2; nb = {"x": cx, "y": cy}
	if not nb.is_empty():
		var gx: int = nb["x"] - p["x"]
		var gy: int = nb["y"] - p["y"]
		var gm: int = maxi(absi(gx), absi(gy))
		if gm > 0:
			inp.aim_x = (gx * 256) / gm
			inp.aim_y = (gy * 256) / gm
		if absi(gx) + absi(gy) > 78 << 16:
			inp.move_x = clampi((gx * 256) / maxi(1, gm), -256, 256)
			inp.move_y = clampi((gy * 256) / maxi(1, gm), -256, 256)
		else:
			inp.move_x = 0
			inp.move_y = 0
			inp.grenade = (sim.tick_count % 4) == 0
	return inp
