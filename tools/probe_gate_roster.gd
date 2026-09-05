extends SceneTree
# During a closed-gate hold the field saturates at MAX_ENEMIES. Where do those
# bodies actually SIT? Anything north of camera_top or south of camera_top+VIEW_H
# is off the drawn viewport: it burns a roster slot the front line cannot use,
# and (north of the ceiling) sits where _clamp_actor forbids the player to walk.

func _init() -> void:
	var on_h := 0; var off_n_h := 0; var off_s_h := 0; var th := 0
	var on_f := 0; var off_n_f := 0; var off_s_f := 0; var tf := 0
	var cap_hits_h := 0; var cap_hits_f := 0
	for s in [0xC0FFEE, 0xBEEF01, 0x51EED2, 0xA11CE3]:
		var sim := SimWorld.new(s, 1, "campaign")
		sim.god_mode = true
		for t in 12000:
			var held: bool = sim.gate_held()
			sim.step([_drive(sim)])
			var on := 0; var n := 0; var so := 0
			for e in sim.enemies:
				if not e["alive"]:
					continue
				if e["y"] < sim.camera_top:
					n += 1
				elif e["y"] > sim.camera_top + SimWorld.VIEW_H:
					so += 1
				else:
					on += 1
			if held:
				th += 1; on_h += on; off_n_h += n; off_s_h += so
				if sim.enemies.size() >= SimWorld.MAX_ENEMIES:
					cap_hits_h += 1
			else:
				tf += 1; on_f += on; off_n_f += n; off_s_f += so
				if sim.enemies.size() >= SimWorld.MAX_ENEMIES:
					cap_hits_f += 1
	print("MAX_ENEMIES=%d  VIEW_H=%dpx" % [SimWorld.MAX_ENEMIES, SimWorld.VIEW_H / 65536])
	print("HELD at a closed gate (%d ticks): mean on-screen=%.1f  off-screen NORTH=%.1f  SOUTH=%.1f   roster at cap %.1f%% of ticks" % [
		th, float(on_h)/maxi(1,th), float(off_n_h)/maxi(1,th), float(off_s_h)/maxi(1,th), 100.0*cap_hits_h/maxi(1,th)])
	print("OPEN field           (%d ticks): mean on-screen=%.1f  off-screen NORTH=%.1f  SOUTH=%.1f   roster at cap %.1f%% of ticks" % [
		tf, float(on_f)/maxi(1,tf), float(off_n_f)/maxi(1,tf), float(off_s_f)/maxi(1,tf), 100.0*cap_hits_f/maxi(1,tf)])
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
