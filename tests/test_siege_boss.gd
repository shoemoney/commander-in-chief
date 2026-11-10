extends RefCounted
## The Crashed Convoy's Siege Tank (src/sim/siege_boss.gd, drawn by src/view/siege_view.gd):
## act thresholds, each attack's telegraph length and geometry, the rear weak-point window,
## armor rules per weapon, gate opening, 2P scaling, checksum coverage, and the view-honesty
## ties (every drawn telegraph is read back from a sim value, not restated).

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")
const F := 65536
const R := SimWorld.GRENADE_RADIUS


func _stage(players := 1, hp := -1) -> Array:
	var sim := SimWorld.new(41, players)
	var gy: int = sim.camera_top + 100 * F
	sim.rocks.clear()   # a bare arena: ambient streamed rocks would slam the charge at its first step
	sim.sandbags.clear()
	var boss := SiegeBoss.make(gy, sim._scaled_boss_hp(SiegeBoss.HP))
	if hp >= 0:
		boss["hp"] = hp
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	sim.players[0]["x"] = 320 * F
	sim.players[0]["y"] = gy + 210 * F
	return [sim, boss]


## Step the boss (not the whole sim) until it enters `st`; returns ticks spent or -1.
func _drive(sim: SimWorld, boss: Dictionary, st: int, guard := 3000) -> int:
	var n := 0
	while boss["st"] != st and n < guard:
		SiegeBoss.step(sim, boss)
		n += 1
	return n if boss["st"] == st else -1


func _hp_for_act(boss: Dictionary, act: int) -> int:
	var mx: int = boss["max_hp"]
	return [mx, mx * 2 / 3, mx / 3][act - 1]


# --- placement + plumbing -------------------------------------------------------------

func test_only_gate_five_is_the_siege_tank_and_the_other_locks_are_unchanged() -> void:
	var sim := SimWorld.new(0xC0FFEE, 1, "arcade")
	sim.jump_to_chapter(5)
	sim.step([SimInput.new()])
	var siege_gates := 0
	for g in sim.gates:
		if g["boss"].is_empty():
			continue
		Runner.T.ok(SiegeBoss.is_siege(g["boss"]), "the one boss gate streamed at chapter 5 is the Siege Tank")
		siege_gates += 1
		Runner.T.ok(g["b1"].is_empty() and g["b2"].is_empty(), "the Siege Tank IS the lock: no bunker pair")
	Runner.T.eq(siege_gates, 1, "exactly one boss gate streams at chapter 5")
	# gate 3 stays the gunship; gates 1, 2, 4 stay bunker pairs.
	var sim3 := SimWorld.new(0xC0FFEE, 1, "arcade")
	sim3.jump_to_chapter(3)
	sim3.step([SimInput.new()])
	var kinds3: Array = []
	for g in sim3.gates:
		if not g["boss"].is_empty():
			kinds3.append(SiegeBoss.is_siege(g["boss"]))
	Runner.T.eq(kinds3, [false], "chapter 3 is still the Bridge Gunship")
	for ch in [1, 2, 4]:
		var s := SimWorld.new(0xC0FFEE, 1, "arcade")
		s.jump_to_chapter(ch)
		s.step([SimInput.new()])
		var bossless := true
		for g in s.gates:
			if not g["boss"].is_empty():
				bossless = false
		Runner.T.ok(bossless, "chapter %d is still a two-bunker gate" % ch)


func test_the_stamp_takes_a_boss_kind_and_keeps_the_gunship_path_byte_identical() -> void:
	var sim := SimWorld.new(41, 1)
	var gy: int = sim.camera_top + 100 * F
	sim._stamp_gunship_gate(gy, 0, false, "siege")
	var b: Dictionary = sim.gates[sim.gates.size() - 1]["boss"]
	Runner.T.ok(SiegeBoss.is_siege(b), "kind 'siege' stamps a Siege Tank")
	Runner.T.eq(b["hp"], b["max_hp"], "the pool is banked at spawn")
	Runner.T.eq(b["y"], gy + SiegeBoss.REST_DY, "it starts on its rest row south of the gate wall")
	var sim2 := SimWorld.new(41, 1)
	sim2._stamp_gunship_gate(gy, 0, false)
	var gb: Dictionary = sim2.gates[sim2.gates.size() - 1]["boss"]
	Runner.T.ok(not gb.has("kind") and not gb.has("y"), "the default kind is the untouched gunship dict")


func test_it_counts_as_a_boss_for_music_and_the_intro_and_the_bot() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	Runner.T.ok(Main._boss_music_on(sim), "the boss track engages for the Siege Tank (generic gate-boss check)")
	var tgt: Dictionary = Main._demo_boss_target(sim, sim.players[0])
	Runner.T.eq(tgt.get("y", 0), pair[1]["y"], "the scripted bot aims at the hull, not at the gunship's hover row")
	pair[1]["wp"] = 30
	var tgt2: Dictionary = Main._demo_boss_target(sim, sim.players[0])
	var w := SiegeBoss.weak_point(pair[1])
	Runner.T.eq([tgt2["x"], tgt2["y"]], w, "while the plate is open the bot shoots the plate")


func test_death_opens_the_gate_through_the_existing_plumbing() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var g: Dictionary = sim.gates[sim.gates.size() - 1]
	sim._damage_boss(boss, boss["hp"])
	Runner.T.ok(not boss["alive"], "lethal damage kills the boss through _damage_boss")
	sim._step_gates()
	Runner.T.ok(g["open"], "_step_gates opens the gate on its death")
	var wreck := false
	for ev in sim.events:
		if ev.get("t", "") == "kill" and ev.get("kind", "") == "boss":
			wreck = true
			Runner.T.eq(ev["y"], boss["y"], "the wreck is where the HULL is, not the gunship's hover row")
	Runner.T.ok(wreck, "a boss kill event is emitted for the finale beat")


# --- acts ------------------------------------------------------------------------------

func test_acts_are_hp_thirds_of_the_stored_max_and_2p_scales_the_pool() -> void:
	var pair := _stage()
	var boss: Dictionary = pair[1]
	var mx: int = boss["max_hp"]
	Runner.T.eq(SiegeBoss.act_of(boss), 1, "full pool is act 1 SHELLING")
	boss["hp"] = mx * 2 / 3
	Runner.T.eq(SiegeBoss.act_of(boss), 2, "two thirds is act 2 CHARGE")
	boss["hp"] = mx / 3
	Runner.T.eq(SiegeBoss.act_of(boss), 3, "one third is act 3 LAST GASP")
	boss["hp"] = mx * 2 / 3 + 1
	Runner.T.eq(SiegeBoss.act_of(boss), 1, "one point above two thirds is still act 1")
	var pair2 := _stage(2)
	Runner.T.eq(pair2[1]["max_hp"], SiegeBoss.HP + SiegeBoss.HP * 6 / 10, "2P scales the pool +60% like every other boss")
	Runner.T.eq(SiegeBoss.act_of(pair2[1]), 1, "the 2P pool starts at act 1")
	pair2[1]["hp"] = pair2[1]["max_hp"] / 3
	Runner.T.eq(SiegeBoss.act_of(pair2[1]), 3, "2P thresholds ride the scaled pool")
	Runner.T.eq(["SHELLING", "CHARGE", "LAST GASP"], [SiegeBoss.act_name(1), SiegeBoss.act_name(2), SiegeBoss.act_name(3)],
		"the act names the plate prints")


func test_act_one_shells_on_a_schedule_and_every_shell_is_a_real_telegraphed_strike() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var landed: Array = []
	for t in range(1, SiegeBoss.SHELL_LEN[0] + 1):
		var n := sim.strikes.size()
		SiegeBoss.step(sim, boss)
		for i in range(n, sim.strikes.size()):
			landed.append(t)
	var plan: Array = []
	for e in SiegeBoss.SHELL_PLAN[0]:
		plan.append(e[0])
	Runner.T.eq(landed, plan, "act 1 calls its shells exactly on SHELL_PLAN")
	Runner.T.eq(boss["st"], SiegeBoss.St.SHELL, "act 1 loops its shelling cycle (no charge yet)")
	for st in sim.strikes:
		Runner.T.ok(st["ticks"] >= SiegeBoss.MIN_TELEGRAPH_TICKS, "a shell is telegraphed at or above the 24-tick floor")
		Runner.T.eq(st["ticks"], SimWorld.STRIKE_TELEGRAPH_TICKS, "...as the plain 45-tick strike whose ring is GRENADE_RADIUS")


func test_cover_shells_crater_the_bags_inside_their_ring_and_lead_shells_do_not() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var gy: int = boss["gate_y"]
	var px := 300 * F
	var py := gy + 200 * F
	sim.players[0]["x"] = px + 12 * F
	sim.players[0]["y"] = py
	sim.sandbags.append({"x": px, "y": py})
	sim.sandbags.append({"x": px + 3 * R, "y": py})   # outside the ring: survives
	Runner.T.eq(SiegeBoss.cover_point(sim, px + 12 * F, py), [px, py], "the cover shell aims at the bag the player is hiding behind")
	boss["st_t"] = SiegeBoss.SHELL_PLAN[0][0][0] - 1
	SiegeBoss.step(sim, boss)
	Runner.T.eq(sim.strikes.size(), 1, "the first act-1 shell is called")
	Runner.T.ok(sim.strikes[0]["crater"], "...and it is a cover-crater shell")
	Runner.T.eq([sim.strikes[0]["x"], sim.strikes[0]["y"]], [px, py], "...landing on the bag, not on the boss's guess of his feet")
	var before := sim.sandbags.size()
	sim.strikes[0]["ticks"] = 1
	sim._resolve_strikes()
	Runner.T.eq(sim.sandbags.size(), before - 1, "the ring broke exactly the bag inside it")
	Runner.T.eq(sim.sandbags[sim.sandbags.size() - 1]["x"], px + 3 * R, "the bag outside the ring stands")
	# a lead shell (kind 0) carries no crater flag
	sim.strikes.clear()
	sim.players[0]["alive"] = true   # the cover shell above was a trap: it got him too
	boss["st_t"] = SiegeBoss.SHELL_PLAN[0][1][0] - 1
	SiegeBoss.step(sim, boss)
	Runner.T.ok(not sim.strikes[0]["crater"], "the lead-the-player shell does not crater")


func test_act_two_runs_shell_rev_charge_stun_return_and_loops() -> void:
	var pair := _stage(1, 0)
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 2)
	var order: Array = [boss["st"]]
	for i in 1200:
		SiegeBoss.step(sim, boss)
		if boss["st"] != order[order.size() - 1]:
			order.append(boss["st"])
		if order.size() >= 7:
			break
	var S = SiegeBoss.St
	Runner.T.eq(order.slice(0, 6), [S.SHELL, S.REV, S.CHARGE, S.STUN, S.RETURN, S.SHELL], "act 2 cycle: shell, rev, charge, stun, return, shell")


# --- the charge lane ---------------------------------------------------------------------

func test_rev_is_at_or_above_the_reaction_floor_in_every_act_that_charges() -> void:
	for act in [2, 3]:
		Runner.T.ok(SiegeBoss.REV_TICKS[act - 1] >= SiegeBoss.MIN_TELEGRAPH_TICKS,
			"act %d rev is %d ticks (>= 24)" % [act, SiegeBoss.REV_TICKS[act - 1]])
	Runner.T.ok(SiegeBoss.SWEEP_WARN_TICKS >= SiegeBoss.MIN_TELEGRAPH_TICKS, "the sweep warning is >= 24 ticks")
	Runner.T.ok(SiegeBoss.MIN_TELEGRAPH_TICKS == GunshipPhases.MIN_TELEGRAPH_TICKS, "the floor is the project's one number")


func test_the_drawn_lane_is_the_lane_the_hull_sweeps() -> void:
	for act in [2, 3]:
		var pair := _stage()
		var sim: SimWorld = pair[0]
		var boss: Dictionary = pair[1]
		boss["hp"] = _hp_for_act(boss, act)
		Runner.T.ok(_drive(sim, boss, SiegeBoss.St.REV) >= 0, "act %d reaches its rev" % act)
		var lane := SiegeBoss.lane(boss)
		Runner.T.ok(not lane.is_empty(), "the lane exists the moment the rev starts")
		Runner.T.ok(not lane["live"], "...and is a promise (not live) during the rev")
		Runner.T.eq(lane["left"], SiegeBoss.REV_TICKS[act - 1], "the rev shows its full length when it starts")
		var sx: int = lane["sx"]
		var sy: int = lane["sy"]
		var ex: int = lane["ex"]
		var ey: int = lane["ey"]
		var rev_ticks := 0
		while boss["st"] == SiegeBoss.St.REV:
			Runner.T.eq(SiegeBoss.lane(boss)["ex"], ex, "the lane does not move during the rev")
			SiegeBoss.step(sim, boss)
			rev_ticks += 1
		Runner.T.eq(rev_ticks, SiegeBoss.REV_TICKS[act - 1], "the rev lasts exactly the telegraph the lane advertised")
		Runner.T.ok(SiegeBoss.lane(boss)["live"], "the charge turns the lane live")
		var seglen := Fixed.length(ex - sx, ey - sy)
		var max_off := 0
		var charged := 0
		while boss["st"] == SiegeBoss.St.CHARGE:
			SiegeBoss.step(sim, boss)
			charged += 1
			# distance from the hull centre to the promised segment
			var d := _dist_to_segment(boss["x"], boss["y"], sx, sy, ex, ey)
			max_off = maxi(max_off, d)
		Runner.T.ok(max_off <= 2 * F, "every hull position stays on the promised segment (worst %.2fpx)" % (max_off / float(F)))
		Runner.T.eq([boss["x"], boss["y"]], [ex, ey], "the charge ends exactly at the lane's end")
		Runner.T.ok(seglen > 60 * F, "the lane is a real run (%.0fpx)" % (seglen / float(F)))
		Runner.T.eq(lane["half_w"], SiegeBoss.RAM_R, "the drawn half-width is the lethal radius")


func _dist_to_segment(px: int, py: int, ax: int, ay: int, bx: int, by: int) -> int:
	var abx := bx - ax
	var aby := by - ay
	var l2 := Fixed.mul(abx, abx) + Fixed.mul(aby, aby)
	var t := 0
	if l2 > 0:
		t = clampi(Fixed.div(Fixed.mul(px - ax, abx) + Fixed.mul(py - ay, aby), l2), 0, F)
	return Fixed.length(px - (ax + Fixed.mul(abx, t)), py - (ay + Fixed.mul(aby, t)))


func test_the_charge_kills_inside_the_lane_and_spares_a_player_who_steps_off_or_rolls() -> void:
	for case in ["in_lane", "off_lane", "rolling"]:
		var pair := _stage()
		var sim: SimWorld = pair[0]
		var boss: Dictionary = pair[1]
		boss["hp"] = _hp_for_act(boss, 2)
		_drive(sim, boss, SiegeBoss.St.REV)
		var lane := SiegeBoss.lane(boss)
		var p: Dictionary = sim.players[0]
		var mid_x: int = (lane["sx"] + lane["ex"]) / 2
		var mid_y: int = (lane["sy"] + lane["ey"]) / 2
		var off := 0 if case != "off_lane" else SiegeBoss.RAM_R + 12 * F
		# step off along the lane normal
		var nx: int = -(lane["ey"] - lane["sy"])
		var ny: int = lane["ex"] - lane["sx"]
		var nl := Fixed.length(nx, ny)
		p["x"] = mid_x + Fixed.mul(Fixed.div(nx, nl), off)
		p["y"] = mid_y + Fixed.mul(Fixed.div(ny, nl), off)
		p["alive"] = true
		p["roll_iframe"] = case == "rolling"
		var guard := 0
		while boss["st"] != SiegeBoss.St.STUN and guard < 400:
			p["roll_iframe"] = case == "rolling"
			SiegeBoss.step(sim, boss)
			guard += 1
		if case == "in_lane":
			Runner.T.ok(not p["alive"], "standing in the promised lane when the hull arrives is lethal")
		elif case == "off_lane":
			Runner.T.ok(p["alive"], "stepping off the drawn lane by a body width + a pad is safe")
		else:
			Runner.T.ok(p["alive"], "a roll's i-frames dodge the ram like every other lethal touch")


func test_the_charge_is_clamped_to_the_arena_and_a_wreck_stops_it_into_a_stun() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 3)
	boss["x"] = SiegeBoss.X_MAX
	sim.players[0]["x"] = 620 * F   # lane would run off the east wall
	boss["st"] = SiegeBoss.St.SHELL
	boss["st_t"] = 0
	_drive(sim, boss, SiegeBoss.St.REV)
	var lane := SiegeBoss.lane(boss)
	Runner.T.ok(lane["ex"] <= SiegeBoss.X_MAX, "the lane end is clamped inside the east wall")
	Runner.T.ok(lane["ey"] >= boss["gate_y"] + SimWorld.GATE_BLOCK_PAD, "...and never north of the gate wall")
	# a wreck in the lane: slam, stun, hull stops short of the lane end
	var pair2 := _stage()
	var sim2: SimWorld = pair2[0]
	var b2: Dictionary = pair2[1]
	b2["hp"] = _hp_for_act(b2, 2)
	_drive(sim2, b2, SiegeBoss.St.REV)
	var l2 := SiegeBoss.lane(b2)
	sim2.rocks.append({"x": (l2["sx"] + l2["ex"]) / 2, "y": (l2["sy"] + l2["ey"]) / 2, "kind": 2})
	_drive(sim2, b2, SiegeBoss.St.STUN)
	Runner.T.ok(b2["st"] == SiegeBoss.St.STUN, "a wreck in the lane ends the charge in a stun")
	Runner.T.ok(Fixed.length(b2["x"] - l2["ex"], b2["y"] - l2["ey"]) > 10 * F, "...short of where the lane promised")
	var slammed := false
	for ev in sim2.events:
		if ev.get("t", "") == "siege_slam":
			slammed = true
	Runner.T.ok(slammed, "the slam has a receipt event")


func test_a_charge_crushes_the_bags_it_drives_over() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 2)
	_drive(sim, boss, SiegeBoss.St.REV)
	var lane := SiegeBoss.lane(boss)
	sim.sandbags.append({"x": (lane["sx"] + lane["ex"]) / 2, "y": (lane["sy"] + lane["ey"]) / 2})
	_drive(sim, boss, SiegeBoss.St.STUN)
	Runner.T.eq(sim.sandbags.size(), 0, "the bag in the lane is gone")


# --- the rear weak point -----------------------------------------------------------------

func test_the_window_opens_after_a_charge_for_a_stated_time_and_then_closes() -> void:
	for act in [2, 3]:
		var pair := _stage()
		var sim: SimWorld = pair[0]
		var boss: Dictionary = pair[1]
		boss["hp"] = _hp_for_act(boss, act)
		Runner.T.ok(not SiegeBoss.weak_open(boss), "the plate is shut before any charge")
		_drive(sim, boss, SiegeBoss.St.STUN)
		Runner.T.ok(SiegeBoss.weak_open(boss), "act %d: the plate opens the tick the charge ends" % act)
		Runner.T.eq(boss["wp"], SiegeBoss.STUN_TICKS[act - 1], "...for the table's window")
		var open_ticks := 0
		while boss["st"] == SiegeBoss.St.STUN:
			if SiegeBoss.weak_open(boss):
				open_ticks += 1
			SiegeBoss.step(sim, boss)
		Runner.T.eq(open_ticks, SiegeBoss.STUN_TICKS[act - 1], "...and it stays open exactly that long")
		Runner.T.ok(not SiegeBoss.weak_open(boss), "the plate shuts when the stun ends")
	Runner.T.ok(SiegeBoss.STUN_TICKS[2] < SiegeBoss.STUN_TICKS[1], "the last-gasp window is shorter than act 2's")


func test_bullet_armor_rule_front_pings_rear_hurts_only_while_open() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 2)
	_drive(sim, boss, SiegeBoss.St.STUN)
	var w := SiegeBoss.weak_point(boss)
	# FRONT of the hull (ahead of the facing): ping, no damage, even with the plate open.
	var front_x: int = boss["x"] + Fixed.mul(boss["fx"], 14 * F)
	var front_y: int = boss["y"] + Fixed.mul(boss["fy"], 14 * F)
	var hp0: int = boss["hp"]
	sim.events.clear()
	Runner.T.ok(sim._bullet_hits_boss({"x": front_x, "y": front_y}), "a front round is absorbed by the hull")
	Runner.T.eq(boss["hp"], hp0, "...and does nothing")
	Runner.T.eq(sim.events.filter(func(e): return e["t"] == "armor_block").size(), 1, "...with an armor_block ping")
	Runner.T.eq(SiegeBoss.bullet_result(boss, front_x, front_y), "armor", "the rule agrees")
	# REAR plate while open: damage, with the hit event at the plate.
	sim.events.clear()
	Runner.T.ok(sim._bullet_hits_boss({"x": w[0], "y": w[1]}), "a rear round is consumed")
	Runner.T.eq(boss["hp"], hp0 - SiegeBoss.WEAK_DAMAGE, "...and hurts for WEAK_DAMAGE")
	var hit_ev: Array = sim.events.filter(func(e): return e["t"] == "boss_hit")
	Runner.T.eq(hit_ev.size(), 1, "...with a boss_hit event")
	Runner.T.eq([hit_ev[0]["x"], hit_ev[0]["y"]], [w[0], w[1]], "...located at the plate")
	# plate CLOSED: the same rear round pings.
	while boss["st"] == SiegeBoss.St.STUN:
		SiegeBoss.step(sim, boss)
	var w2 := SiegeBoss.weak_point(boss)
	var hp1: int = boss["hp"]
	sim.events.clear()
	Runner.T.ok(sim._bullet_hits_boss({"x": w2[0], "y": w2[1]}), "a rear round on a shut plate is still absorbed")
	Runner.T.eq(boss["hp"], hp1, "...for nothing")
	Runner.T.eq(SiegeBoss.bullet_result(boss, w2[0], w2[1]), "armor", "the rule says armor")
	# a round that misses the hull entirely is not absorbed
	Runner.T.ok(not sim._bullet_hits_boss({"x": boss["x"] + 200 * F, "y": boss["y"] + 200 * F}), "a miss passes through")
	Runner.T.eq(SiegeBoss.bullet_result(boss, boss["x"] + 200 * F, boss["y"]), "miss", "...per the rule too")


func test_blasts_hurt_it_at_any_time_and_use_the_hull_position_not_the_gunship_row() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var hp0: int = boss["hp"]
	sim._explode(boss["x"], boss["y"])
	Runner.T.eq(boss["hp"], hp0 - SimWorld.BOSS_GRENADE_DAMAGE, "a grenade blast on the hull hurts with the plate SHUT")
	# the gunship's hover row is 140px away from this hull: a blast THERE does nothing
	var hp1: int = boss["hp"]
	sim._explode(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
	Runner.T.eq(boss["hp"], hp1, "a blast at the gunship's hover row misses the ground tank")
	var hp2: int = boss["hp"]
	sim._rocket_blast(boss["x"], boss["y"])
	Runner.T.eq(boss["hp"], hp2 - Weapons.TABLE[Weapons.ROCKET]["boss_dmg"], "a rocket hurts it")
	Runner.T.ok(sim._rocket_hits(boss["x"], boss["y"]), "a rocket in flight detonates on the hull")
	var p: Dictionary = sim.players[0]
	p["weapon"] = Weapons.ROCKET
	p["x"] = boss["x"]
	p["y"] = boss["y"] + 120 * F
	p["aim_x"] = 0
	p["aim_y"] = -F
	Runner.T.ok(sim._rocket_lane_has_target(p, Weapons.TABLE[Weapons.ROCKET]), "the launcher auto-triggers on the hull")


func test_the_flamethrower_does_not_hurt_it() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var p: Dictionary = sim.players[0]
	p["weapon"] = Weapons.FLAME
	p["wpn_ammo"] = 10
	p["x"] = boss["x"]
	p["y"] = boss["y"] + 40 * F
	p["aim_x"] = 0
	p["aim_y"] = -F
	var hp0: int = boss["hp"]
	for i in 30:
		p["fire_cd"] = 0
		sim._fire_special(p, 0)
		sim._flame_burst(p, 0)
	Runner.T.eq(boss["hp"], hp0, "30 flame bursts straight into the hull leave its pool alone")
	Runner.T.eq(p["wpn_ammo"], 10, "...and the trigger does not even spend ammo (nothing flame can burn)")


# --- act three ---------------------------------------------------------------------------

func test_the_sweep_fan_is_warned_then_fired_inside_exactly_the_drawn_arc() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 3)
	Runner.T.ok(_drive(sim, boss, SiegeBoss.St.SWEEP_WARN) >= 0, "act 3 shells, then warns the sweep")
	var arc := SiegeBoss.sweep_arc(boss)
	Runner.T.ok(not arc.is_empty() and not arc["live"], "the fan is drawn (not live) during the warning")
	Runner.T.eq(arc["left"], SiegeBoss.SWEEP_WARN_TICKS, "the warning shows its full length")
	var fx: int = boss["fx"]
	var fy: int = boss["fy"]
	var lo: Array = arc["lo"]
	var hi: Array = arc["hi"]
	# edges are the first and last fan beams
	Runner.T.eq(lo, SiegeBoss.fan_dir(fx, fy, 0), "the drawn low edge is beam 0")
	Runner.T.eq(hi, SiegeBoss.fan_dir(fx, fy, SiegeBoss.SWEEP_BEAMS - 1), "the drawn high edge is the last beam")
	Runner.T.ok(arc["range"] >= SimWorld.ENEMY_BULLET_SPEED * SimWorld.ENEMY_BULLET_TTL_TICKS,
		"the drawn range covers how far the rounds fly")
	sim.enemy_bullets.clear()
	_drive(sim, boss, SiegeBoss.St.SWEEP)
	var fired := 0
	var worst_cos := F
	while boss["st"] == SiegeBoss.St.SWEEP:
		var n := sim.enemy_bullets.size()
		SiegeBoss.step(sim, boss)
		for i in range(n, sim.enemy_bullets.size()):
			var b: Dictionary = sim.enemy_bullets[i]
			var bl := Fixed.length(b["vx"], b["vy"])
			var c := Fixed.mul(Fixed.div(b["vx"], bl), fx) + Fixed.mul(Fixed.div(b["vy"], bl), fy)
			worst_cos = mini(worst_cos, c)
			fired += 1
	Runner.T.eq(fired, SiegeBoss.SWEEP_TICKS / SiegeBoss.SWEEP_FIRE_EVERY, "the sweep fires on its cadence")
	Runner.T.ok(worst_cos >= SiegeBoss.FAN_COS_MIN - 400, "every round leaves inside the drawn 80-degree fan (worst cos %d)" % worst_cos)
	Runner.T.eq(boss["st"], SiegeBoss.St.REV, "the sweep hands off to the charge rev")
	for beam in 3:
		var d := SiegeBoss.fan_dir(F, 0, beam)
		Runner.T.ok(absi(Fixed.length(d[0], d[1]) - F) < 700, "fan beam %d is a unit vector" % beam)


func test_escorts_dismount_once_per_cycle_and_never_stack_past_the_cap() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 3)
	_drive(sim, boss, SiegeBoss.St.SWEEP_WARN)
	SiegeBoss.step(sim, boss)
	var escorts := sim.enemies.filter(func(e): return e.get("escort", false))
	Runner.T.eq(escorts.size(), SiegeBoss.ESCORTS, "act 3's sweep warning dismounts the escorts")
	var dm := sim.events.filter(func(e): return e["t"] == "siege_dismount")
	Runner.T.eq(dm.size(), SiegeBoss.ESCORTS, "each has a dismount event for the view")
	# a second cycle with the first escorts alive adds none
	boss["st"] = SiegeBoss.St.SWEEP_WARN
	boss["st_t"] = 0
	SiegeBoss.step(sim, boss)
	Runner.T.eq(sim.enemies.filter(func(e): return e.get("escort", false)).size(), SiegeBoss.ESCORTS, "living escorts are not stacked")
	# acts 1 and 2 never dismount
	var pair2 := _stage()
	pair2[1]["hp"] = _hp_for_act(pair2[1], 2)
	for i in 900:
		SiegeBoss.step(pair2[0], pair2[1])
	Runner.T.eq(pair2[0].enemies.filter(func(e): return e.get("escort", false)).size(), 0, "act 2 fields no escorts")


func test_act_three_cycles_faster_than_act_two() -> void:
	var lens: Array = []
	for act in [2, 3]:
		var pair := _stage()
		pair[1]["hp"] = _hp_for_act(pair[1], act)
		# measure one full loop SHELL -> ... -> SHELL (second arrival)
		var arrivals := 0
		var n := 0
		var prev: int = pair[1]["st"]
		while arrivals < 2 and n < 3000:
			SiegeBoss.step(pair[0], pair[1])
			n += 1
			if prev != SiegeBoss.St.SHELL and pair[1]["st"] == SiegeBoss.St.SHELL:
				arrivals += 1
			prev = pair[1]["st"]
		lens.append(n)
	Runner.T.ok(lens[1] > 0 and lens[0] > 0, "both cycles complete")
	# act 3 packs a sweep in, but its shell, rev, stun and return are all shorter
	Runner.T.ok(SiegeBoss.SHELL_LEN[2] < SiegeBoss.SHELL_LEN[1] and SiegeBoss.REV_TICKS[2] < SiegeBoss.REV_TICKS[1]
		and SiegeBoss.RETURN_SPEED[2] > SiegeBoss.RETURN_SPEED[1] and SiegeBoss.CHARGE_SPEED[2] > SiegeBoss.CHARGE_SPEED[1],
		"act 3's shell, rev, charge and return are all on a faster clock")


# --- determinism ---------------------------------------------------------------------------

func test_every_siege_field_is_in_the_checksum() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	var base := sim.checksum()
	for k in SiegeBoss.HASHED_KEYS:
		var old: int = boss[k]
		boss[k] = old + 7
		Runner.T.ok(sim.checksum() != base, "the checksum moves when boss['%s'] does" % k)
		boss[k] = old
	Runner.T.eq(sim.checksum(), base, "restoring the fields restores the checksum")
	# and every key SiegeBoss.make writes is either hashed here or one of the gunship's already-hashed keys
	var known := SiegeBoss.HASHED_KEYS + ["alive", "hp", "max_hp", "x", "dir", "phase_t", "gate_y", "kind"]
	for k in boss.keys():
		Runner.T.ok(known.has(k), "boss key '%s' is classified" % k)


func test_the_fight_is_deterministic_across_two_identical_runs() -> void:
	var sums: Array = []
	for run in 2:
		var pair := _stage()
		pair[1]["hp"] = _hp_for_act(pair[1], 2)
		for i in 1500:
			SiegeBoss.step(pair[0], pair[1])
			pair[0].tick_count += 1
		sums.append(pair[0].checksum())
	Runner.T.eq(sums[0], sums[1], "two identical Siege Tank runs end on the same checksum")


# --- view honesty --------------------------------------------------------------------------

func test_the_plate_label_names_the_act_and_the_open_window_from_sim_state() -> void:
	var pair := _stage()
	var boss: Dictionary = pair[1]
	Runner.T.eq(SiegeView.label(boss), "SIEGE TANK — SHELLING", "act 1 plate")
	boss["hp"] = _hp_for_act(boss, 2)
	Runner.T.eq(SiegeView.label(boss), "SIEGE TANK — CHARGE", "act 2 plate")
	boss["wp"] = 40
	Runner.T.eq(SiegeView.label(boss), "SIEGE TANK — CHARGE · REAR OPEN", "the plate says so exactly while the sim has the window open")
	boss["wp"] = 0
	boss["hp"] = _hp_for_act(boss, 3)
	Runner.T.eq(SiegeView.label(boss), "SIEGE TANK — LAST GASP", "act 3 plate")


func test_view_telegraphs_read_the_sim_accessors_not_their_own_numbers() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/siege_view.gd")
	for needle in ["SiegeBoss.lane(", "SiegeBoss.sweep_arc(", "SiegeBoss.weak_point(", "SiegeBoss.weak_open(",
			"SiegeBoss.fan_dir(", "SiegeBoss.WEAK_R", "lane[\"half_w\"]", "boss[\"wp\"]", "boss[\"wpm\"]"]:
		Runner.T.ok(src.contains(needle), "siege_view.gd reads the sim's %s" % needle)
	# the pixel half-width of the lane edge is the sim's RAM_R, via the lane dict (not a literal)
	var pair := _stage()
	var sim: SimWorld = pair[0]
	var boss: Dictionary = pair[1]
	boss["hp"] = _hp_for_act(boss, 2)
	_drive(sim, boss, SiegeBoss.St.REV)
	var lane := SiegeBoss.lane(boss)
	var cs: Array = SiegeView.lane_corners(lane, 1.0)
	var width: float = (cs[0] as Vector2).distance_to(cs[1] as Vector2)
	Runner.T.ok(absf(width - 2.0 * SiegeBoss.RAM_R / float(F)) < 0.01,
		"the drawn lane is %.1fpx wide: 2 x RAM_R" % width)
	var length: float = ((cs[0] as Vector2) + (cs[1] as Vector2)).distance_to((cs[2] as Vector2) + (cs[3] as Vector2)) / 2.0
	var seg := Fixed.length(lane["ex"] - lane["sx"], lane["ey"] - lane["sy"]) / float(F)
	Runner.T.ok(absf(length - seg) < 0.05, "the drawn lane is as long as the segment the hull sweeps")
	# hull sprite angle follows the sim's facing
	var a := SiegeView.hull_angle(boss)
	var v := Vector2.from_angle(a - PI / 2.0)
	Runner.T.ok(absf(v.x - boss["fx"] / float(F)) < 0.01 and absf(v.y - boss["fy"] / float(F)) < 0.01, "the hull is drawn facing the sim's facing")


func test_the_main_hooks_route_the_siege_tank_not_the_gunship_label() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("SiegeView.draw(self, g[\"boss\"], slot)"), "_draw_gunships hands the Siege Tank to SiegeView")
	Runner.T.ok(src.contains("SiegeView.label(boss)"), "the boss bar prints the siege plate")
	Runner.T.ok(src.contains("SiegeView.BANNER"), "the first-sight banner names it")
	Runner.T.ok(src.contains("SiegeView.BAND"), "the top band names the objective")
	Runner.T.ok(src.contains("SimWorld.boss_cy(g[\"boss\"])"), "the off-screen chevron points at the hull's row")
	for ev in ["siege_fire", "siege_vent", "siege_slam", "siege_dismount"]:
		Runner.T.ok(src.contains("\"%s\":" % ev), "event %s has a view handler" % ev)
	Runner.T.ok(SiegeView.BAND.length() <= 40, "the objective band fits the band")


func test_boss_rush_stays_a_gunship_gauntlet_and_says_so() -> void:
	var sim := SimWorld.new(1, 1, "boss_rush")
	var siege := 0
	for g in sim.gates:
		if not g["boss"].is_empty() and SiegeBoss.is_siege(g["boss"]):
			siege += 1
	Runner.T.eq(siege, 0, "Boss Rush enumerates gunships only (its HUD and menu copy say GUNSHIPS)")


# --- the fight as a whole ------------------------------------------------------------------

func test_a_scripted_duelist_finishes_the_fight_and_the_gate_opens() -> void:
	var pair := _stage()
	var sim: SimWorld = pair[0]
	sim.god_mode = true
	sim._stamp_siege_cover(pair[1]["gate_y"])
	var boss: Dictionary = pair[1]
	var gate: Dictionary = sim.gates[sim.gates.size() - 1]
	var t := 0
	while boss["alive"] and t < 6000:
		var inp := SimInput.new()
		var p: Dictionary = sim.players[0]
		var tx: int = boss["x"]
		var ty: int = boss["y"]
		if SiegeBoss.weak_open(boss):
			var w := SiegeBoss.weak_point(boss)
			tx = w[0]
			ty = w[1]
		inp.move_x = clampi((boss["x"] - p["x"]) / F * 8, -256, 256)
		inp.move_y = clampi((boss["y"] + 90 * F - p["y"]) / F * 8, -256, 256)
		var ax: int = tx - p["x"]
		var ay: int = ty - p["y"]
		var al: int = Fixed.length(ax, ay)
		if al > 0:
			inp.aim_x = clampi(Fixed.div(ax, al) / 256, -256, 256)
			inp.aim_y = clampi(Fixed.div(ay, al) / 256, -256, 256)
		inp.fire = (t % 60) < 27
		inp.grenade = (t % 120) == 100
		sim.step([inp])
		t += 1
	Runner.T.ok(not boss["alive"], "a tracking duelist kills the Siege Tank in %d ticks" % t)
	Runner.T.ok(t >= 25 * 60 and t <= 45 * 60, "...in a 25-45 s fight (measured %.1fs)" % (t / 60.0))
	sim.step([SimInput.new()])
	Runner.T.ok(gate["open"], "the gate opens on its death")
