extends SceneTree
# Two measurements at a CLOSED GATE (the campaign's marquee setpiece):
#  A) spawn pressure held vs open-field  (does the crescendo de-escalate?)
#  B) the 100-coin airstrike's score payout inside a gate hold vs outside
#     (_fire_mission promises WIPE_SCORE_PCT; _kill_enemy's gate throttle voids it)

func _init() -> void:
	_pressure()
	print("")
	_airstrike()
	quit(0)


func _pressure() -> void:
	var held_spawns := 0
	var held_ticks := 0
	var free_spawns := 0
	var free_ticks := 0
	var held_live := 0
	var free_live := 0
	var held_shots := 0
	var free_shots := 0
	for s in [0xC0FFEE, 0xBEEF01, 0x51EED2, 0xA11CE3]:
		var sim := SimWorld.new(s, 1, "campaign")
		sim.god_mode = true
		var seen := {}
		for t in 12000:
			var h: bool = sim.gate_held()
			var before: int = sim.enemies.size()
			var kills_this_tick := 0
			sim.step([_drive(sim)])
			for ev in sim.events:
				if ev["t"] == "kill":
					kills_this_tick += 1
			# spawns = size delta + removals this tick (kills + culls); use kills as floor
			var spawned: int = maxi(0, sim.enemies.size() - before + kills_this_tick)
			var live := 0
			for e in sim.enemies:
				if e["alive"]:
					live += 1
			if h:
				held_ticks += 1
				held_spawns += spawned
				held_live += live
				held_shots += sim.enemy_bullets.size()
			else:
				free_ticks += 1
				free_spawns += spawned
				free_live += live
				free_shots += sim.enemy_bullets.size()
	print("SPAWN PRESSURE (4 campaign seeds x 12000 ticks, god_mode)")
	print("  camera pinned at a CLOSED GATE : %d spawns / %d ticks = %.2f per 1000t" % [
		held_spawns, held_ticks, 1000.0 * held_spawns / maxi(1, held_ticks)])
	print("  open field                     : %d spawns / %d ticks = %.2f per 1000t" % [
		free_spawns, free_ticks, 1000.0 * free_spawns / maxi(1, free_ticks)])
	print("  mean LIVE hostiles  held=%.2f  open=%.2f" % [
		float(held_live) / maxi(1, held_ticks), float(free_live) / maxi(1, free_ticks)])
	print("  mean enemy BULLETS  held=%.2f  open=%.2f" % [
		float(held_shots) / maxi(1, held_ticks), float(free_shots) / maxi(1, free_ticks)])


func _airstrike() -> void:
	## Identical field, identical 100-coin buy — once with the camera pinned at a
	## closed gate, once one pixel south of the clamp.
	for pinned in [false, true]:
		var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
		sim.god_mode = true
		# advance until a closed gate has pinned the camera
		var t := 0
		while t < 4000 and not sim.gate_held():
			sim.step([_drive(sim)])
			t += 1
		if not pinned:
			sim.camera_top -= 1   # break the exact-equality clamp: no longer "held"
		# stock the field with a full screen of hostiles
		var made := 0
		while sim.enemies.size() < 24 and made < 200:
			sim._spawn_enemy(SimWorld.SCREEN_CX + ((made % 5) - 2) * 40 * 65536,
				sim.camera_top + (60 + (made % 4) * 30) * 65536, made % 3 == 0)
			made += 1
		var alive_before := 0
		for e in sim.enemies:
			if e["alive"]:
				alive_before += 1
		var score_before: int = sim.score
		var chest_before: int = sim.war_chest
		sim.war_chest = 1000
		sim.pending_airstrike = 0
		sim._try_buy(sim.players[0], 3)
		var paid: int = 1000 - sim.war_chest
		for _i in SimWorld.STRIKE_TELEGRAPH_TICKS + 2:
			if not pinned:
				sim.camera_top -= 1   # keep it un-pinned across the telegraph
			sim.step([_drive(sim)])
		var alive_after := 0
		for e in sim.enemies:
			if e["alive"]:
				alive_after += 1
		print("AIRSTRIKE  gate_held=%s : paid %d coin, wiped %d enemies, score gained = %d" % [
			str(pinned), paid, alive_before - alive_after, sim.score - score_before])


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
