extends SceneTree
# Headless probe: how much of a campaign run's KILL economy is zeroed by the
# closed-gate throttle in _kill_enemy (sim_world.gd:3505)?
#
# Steps the sim directly (no frames). God-mode auto-restore so a run cannot end.
# Counts, per gate-interval: kills paid vs kills zeroed, coin/score forfeited,
# and how many kill-streaks were broken by the throttle rather than by time.

func _init() -> void:
	for m in ["campaign", "arcade", "boss_rush"]:
		var mr := _run_mode(m, 0xC0FFEE, 8000)
		print("MODE %-10s held=%.1f%% of ticks   kills paid=%d zeroed=%d (%.1f%% of kills pay 0)   coin banked=%d coin forfeited=%d" % [
			m, 100.0 * mr["held"] / maxi(1, mr["ticks"]), mr["paid"], mr["zeroed"],
			100.0 * mr["zeroed"] / maxi(1, mr["paid"] + mr["zeroed"]), mr["coin_got"], mr["coin_lost"]])
	print("")
	var seeds := [0xC0FFEE, 0xBEEF01, 0x51EED2, 0xA11CE3]
	var tot_paid := 0
	var tot_zero := 0
	var tot_coin_lost := 0
	var tot_score_lost := 0
	var tot_ticks := 0
	var tot_held := 0
	var tot_streak_break := 0
	var best_streak_overall := 0
	for s in seeds:
		var r := _run(s, 12000)
		print("seed 0x%X  ticks=%d held=%d(%.1f%%)  kills_paid=%d kills_zeroed=%d (%.1f%% zeroed)  coin_lost=%d score_lost=%d  best_streak=%d streak_breaks=%d  supply drops: held=%d open=%d" % [
			s, r["ticks"], r["held"], 100.0 * r["held"] / maxi(1, r["ticks"]),
			r["paid"], r["zeroed"], 100.0 * r["zeroed"] / maxi(1, r["paid"] + r["zeroed"]),
			r["coin_lost"], r["score_lost"], r["best_streak"], r["streak_break"],
			r["drop_held"], r["drop_free"]])
		for line in r["per_gate"]:
			print("    %s" % line)
		tot_paid += r["paid"]; tot_zero += r["zeroed"]
		tot_coin_lost += r["coin_lost"]; tot_score_lost += r["score_lost"]
		tot_ticks += r["ticks"]; tot_held += r["held"]
		tot_streak_break += r["streak_break"]
		best_streak_overall = maxi(best_streak_overall, r["best_streak"])
	print("")
	print("TOTAL kills_paid=%d kills_zeroed=%d -> %.1f%% of all kills pay NOTHING" % [
		tot_paid, tot_zero, 100.0 * tot_zero / maxi(1, tot_paid + tot_zero)])
	print("TOTAL coin forfeited=%d  score forfeited=%d  (%.1f%% of ticks are gate_held)" % [
		tot_coin_lost, tot_score_lost, 100.0 * tot_held / maxi(1, tot_ticks)])
	print("TOTAL streaks broken while gate_held=%d ; best streak reached=%d" % [
		tot_streak_break, best_streak_overall])
	quit(0)


func _run_mode(m: String, seed_v: int, max_ticks: int) -> Dictionary:
	return _run(seed_v, max_ticks, m)


func _run(seed_v: int, max_ticks: int, m: String = "campaign") -> Dictionary:
	var sim := SimWorld.new(seed_v, 1, m)
	sim.god_mode = true
	var paid := 0
	var zeroed := 0
	var coin_lost := 0
	var score_lost := 0
	var held := 0
	var streak_break := 0
	var coin_got := 0
	var drop_held := 0
	var drop_free := 0
	var best := 0
	var per_gate: Array[String] = []
	var gates_open_seen := 0
	var seg_paid := 0
	var seg_zero := 0
	var t := 0
	while t < max_ticks and not sim.victory:
		var was_held: bool = sim.gate_held()
		var prev_streak: int = sim.kill_streak
		var prev_timer: int = sim.kill_streak_timer
		var pk_before: int = sim.pickups.size()
		sim.step([_drive(sim)])
		var dropped: int = maxi(0, sim.pickups.size() - pk_before)
		if was_held:
			drop_held += dropped
		else:
			drop_free += dropped
		if was_held:
			held += 1
		for ev in sim.events:
			if ev["t"] == "kill":
				# reconstruct the gross bounty the kill WOULD have paid
				var gross := _gross(ev.get("kind", "rusher"))
				if int(ev.get("coin", 0)) > 0:
					paid += 1
					seg_paid += 1
					coin_got += int(ev["coin"])
				else:
					# pilot pays 0 by design — exclude it
					if ev.get("kind", "") == "pilot":
						continue
					zeroed += 1
					seg_zero += 1
					if was_held:
						coin_lost += gross
						score_lost += gross * 10
			if ev["t"] == "gate_open":
				gates_open_seen += 1
				per_gate.append("gate %d: paid=%d zeroed=%d" % [gates_open_seen, seg_paid, seg_zero])
				seg_paid = 0
				seg_zero = 0
		# streak broken while the camera is pinned at a closed gate?
		if was_held and prev_timer == 1 and sim.kill_streak_timer == 0 and prev_streak >= 3:
			streak_break += 1
		best = maxi(best, sim.kill_streak)
		t += 1
	per_gate.append("tail: paid=%d zeroed=%d" % [seg_paid, seg_zero])
	return {"ticks": t, "held": held, "paid": paid, "zeroed": zeroed,
		"coin_lost": coin_lost, "score_lost": score_lost,
		"streak_break": streak_break, "best_streak": best, "per_gate": per_gate,
		"coin_got": coin_got, "drop_held": drop_held, "drop_free": drop_free}


func _gross(kind: String) -> int:
	match kind:
		"mg_nest": return SimWorld.COIN_MG_NEST
		"courier": return SimWorld.COIN_ELITE * 4
		"elite", "sniper", "grenadier", "technical", "drone", "shield", "ghillie": return SimWorld.COIN_ELITE
	return SimWorld.COIN_RUSHER


func _drive(sim: SimWorld) -> SimInput:
	## Minimal combat bot: push north, aim/fire at the nearest live enemy.
	var inp := SimInput.new()
	var p: Dictionary = sim.players[0]
	inp.move_y = -256
	var bx := 0
	var by := -256
	var best := 1 << 62
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var dx: int = e["x"] - p["x"]
		var dy: int = e["y"] - p["y"]
		var d: int = absi(dx) + absi(dy)
		if d < best:
			best = d
			bx = dx
			by = dy
	for bk in sim.bunkers:
		if not bk["alive"]:
			continue
		var dx: int = bk["x"] - p["x"]
		var dy: int = bk["y"] - p["y"]
		var d: int = absi(dx) + absi(dy) - (40 << 16)
		if d < best:
			best = d
			bx = dx
			by = dy
	var m: int = maxi(absi(bx), absi(by))
	if m > 0:
		inp.aim_x = (bx * 256) / m
		inp.aim_y = (by * 256) / m
	inp.fire = true
	# Bunkers are armour: only explosives hurt them. Close to ~85px and lob.
	var nb := {}
	var nbd := 1 << 62
	for bk in sim.bunkers:
		if not bk["alive"]:
			continue
		var cx: int = bk["x"] + SimWorld.BUNKER_W / 2
		var cy: int = bk["y"] + SimWorld.BUNKER_H / 2
		var d: int = absi(cx - p["x"]) + absi(cy - p["y"])
		if d < nbd:
			nbd = d
			nb = {"x": cx, "y": cy}
	if not nb.is_empty():
		var gx: int = nb["x"] - p["x"]
		var gy: int = nb["y"] - p["y"]
		var gm: int = maxi(absi(gx), absi(gy))
		if gm > 0:
			inp.aim_x = (gx * 256) / gm
			inp.aim_y = (gy * 256) / gm
		var gd: int = absi(gx) + absi(gy)
		if gd > 78 << 16:
			inp.move_x = clampi((gx * 256) / maxi(1, gm), -256, 256)
			inp.move_y = clampi((gy * 256) / maxi(1, gm), -256, 256)
		else:
			inp.move_x = 0
			inp.move_y = 0
			inp.grenade = (sim.tick_count % 4) == 0
	return inp
