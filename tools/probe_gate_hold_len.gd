extends SceneTree
# How long is the kill economy switched OFF per gate? Ticks from the first
# gate_held() tick of a gate to that gate's gate_open, plus what died in it.

func _init() -> void:
	for s in [0xC0FFEE, 0xBEEF01, 0x51EED2, 0xA11CE3, 0x1234AB, 0x99FEED]:
		var sim := SimWorld.new(s, 1, "campaign")
		sim.god_mode = true
		var run := 0
		var kills := 0
		var lost := 0
		var out: Array[String] = []
		for t in 14000:
			var h: bool = sim.gate_held()
			sim.step([_drive(sim)])
			if h:
				run += 1
				for ev in sim.events:
					if ev["t"] == "kill" and int(ev.get("coin", 0)) == 0 and ev.get("kind", "") != "pilot":
						kills += 1
						lost += (SimWorld.COIN_ELITE if ev.get("kind", "") != "rusher" else SimWorld.COIN_RUSHER)
			for ev in sim.events:
				if ev["t"] == "gate_open":
					out.append("hold %d ticks (%.1fs), %d kills paid 0 coin / 0 score, ~%d coin voided" % [
						run, run / 60.0, kills, lost])
					run = 0; kills = 0; lost = 0
		print("seed 0x%X" % s)
		for l in out:
			print("   " + l)
	quit(0)


func _drive(sim: SimWorld) -> SimInput:
	var inp := SimInput.new()
	var p: Dictionary = sim.players[0]
	inp.move_y = -256
	var bx := 0; var by := -256; var best := 1 << 62
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
	var nb := {}; var nbd := 1 << 62
	for bk in sim.bunkers:
		if not bk["alive"]:
			continue
		var cx: int = bk["x"] + SimWorld.BUNKER_W / 2
		var cy: int = bk["y"] + SimWorld.BUNKER_H / 2
		var d2: int = absi(cx - p["x"]) + absi(cy - p["y"])
		if d2 < nbd:
			nbd = d2; nb = {"x": cx, "y": cy}
	if not nb.is_empty():
		var gx: int = nb["x"] - p["x"]; var gy: int = nb["y"] - p["y"]
		var gm: int = maxi(absi(gx), absi(gy))
		if gm > 0:
			inp.aim_x = (gx * 256) / gm
			inp.aim_y = (gy * 256) / gm
		if absi(gx) + absi(gy) > 78 << 16:
			inp.move_x = clampi((gx * 256) / maxi(1, gm), -256, 256)
			inp.move_y = clampi((gy * 256) / maxi(1, gm), -256, 256)
		else:
			inp.move_x = 0; inp.move_y = 0
			inp.grenade = (sim.tick_count % 4) == 0
	return inp
