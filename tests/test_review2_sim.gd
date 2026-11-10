extends RefCounted
## Second-review sim fixes: (1) the Siege Tank's grenade-crate re-arm sees only crates a player
## can still reach, (2) the charge lane is cut at the first wreck so the lane drawn is the lane
## swept, (3) no standing spot along the gate wall dodges the whole fight, (4) themed endless
## waves keep their theme while a member is still locked, (5) the escort and crater flags are
## hashed.

const Runner := preload("res://tests/run_tests.gd")
const F := 65536


func _stage(hp_act := 2) -> Array:
	var sim := SimWorld.new(41, 1)
	var gy: int = sim.camera_top + 100 * F
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.pickups.clear()
	var boss := SiegeBoss.make(gy, sim._scaled_boss_hp(SiegeBoss.HP))
	var mx: int = boss["max_hp"]
	boss["hp"] = [mx, mx * 2 / 3, mx / 3][hp_act - 1]
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
	sim.players[0]["x"] = 320 * F
	sim.players[0]["y"] = gy + 210 * F
	sim.god_mode = true
	return [sim, boss]


func _drive(sim: SimWorld, boss: Dictionary, st: int, guard := 3000) -> int:
	var n := 0
	while boss["st"] != st and n < guard:
		SiegeBoss.step(sim, boss)
		n += 1
	return n if boss["st"] == st else -1


# --- 1. the re-arm ignores crates nobody can reach --------------------------------------------

func test_a_free_crate_behind_the_camera_does_not_hold_the_rearm_off() -> void:
	var a := _stage(1)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	sim.players[0]["grenade_ammo"] = 0
	var stray_y: int = boss["gate_y"] + 600 * F
	Runner.T.ok(stray_y > sim.camera_top + SimWorld.VIEW_H, "setup: the stray crate is off the bottom of the screen")
	sim.pickups.append({"x": 300 * F, "y": stray_y, "kind": 1, "cost": 0})
	var home := -1
	for t in SiegeBoss.RESUPPLY_TICKS + 30:
		SiegeBoss.step(sim, boss)
		if home < 0:
			for pk in sim.pickups:
				if pk["x"] == SiegeBoss.CRATE_POS[0] * F:
					home = t + 1
	Runner.T.eq(home, SiegeBoss.RESUPPLY_TICKS, "the arena crate re-arms on schedule despite an unreachable stray")


func test_a_free_crate_inside_the_arena_still_counts() -> void:
	var a := _stage(1)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	sim.players[0]["grenade_ammo"] = 0
	sim.pickups.append({"x": 300 * F, "y": boss["gate_y"] + 160 * F, "kind": 1, "cost": 0})
	for _t in SiegeBoss.RESUPPLY_TICKS * 2:
		SiegeBoss.step(sim, boss)
	Runner.T.eq(sim.pickups.size(), 1, "a reachable crate is the supply: nothing is stacked on it")


func test_stray_crates_piled_up_behind_the_camera_do_not_starve_the_player() -> void:
	# The shape of the measured bug: Arcade never culls pickups, so crates pile up behind the camera.
	var a := _stage(1)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	var gy: int = boss["gate_y"]
	for i in 3:
		sim.pickups.append({"x": (100 + i * 80) * F, "y": gy + (500 + i * 60) * F, "kind": 1, "cost": 0})
	sim.players[0]["grenade_ammo"] = 0
	for _t in SiegeBoss.RESUPPLY_TICKS + 5:
		SiegeBoss.step(sim, boss)
	var home := 0
	for pk in sim.pickups:
		if pk["x"] == SiegeBoss.CRATE_POS[0] * F:
			home += 1
	Runner.T.eq(home, 1, "the starved player gets the arena crate back in a run with stray crates")


# --- 2. the lane is the swept lane ---------------------------------------------------------------

func _lock_lane(sim: SimWorld, boss: Dictionary) -> Dictionary:
	SiegeBoss._begin_rev(sim, boss, sim.players[0])
	return SiegeBoss.lane(boss)


func test_a_wreck_in_the_lane_truncates_the_lane_before_the_charge_starts() -> void:
	for act in [2, 3]:
		var a := _stage(act)
		var sim: SimWorld = a[0]
		var boss: Dictionary = a[1]
		var open_lane := _lock_lane(sim, boss)
		var open_len := Fixed.length(open_lane["ex"] - open_lane["sx"], open_lane["ey"] - open_lane["sy"])
		boss["st"] = SiegeBoss.St.SHELL
		boss["st_t"] = 0
		var mid_x: int = (open_lane["sx"] + open_lane["ex"]) / 2
		var mid_y: int = (open_lane["sy"] + open_lane["ey"]) / 2
		sim.rocks.append({"x": mid_x, "y": mid_y, "kind": 2})
		var lane := _lock_lane(sim, boss)
		var cut_len := Fixed.length(lane["ex"] - lane["sx"], lane["ey"] - lane["sy"])
		Runner.T.ok(cut_len < open_len / 2 + 2 * F, "act %d: the promised lane stops short of the wreck (%.0f of %.0f px)" % [act, cut_len / float(F), open_len / float(F)])
		var ex: int = lane["ex"]
		var ey: int = lane["ey"]
		var ev_before := sim.events.size()
		_drive(sim, boss, SiegeBoss.St.STUN)
		Runner.T.eq([boss["x"], boss["y"]], [ex, ey], "act %d: the hull comes to rest exactly where the drawn ring said" % act)
		var slammed := false
		for i in range(ev_before, sim.events.size()):
			if sim.events[i].get("t", "") == "siege_slam":
				slammed = true
		Runner.T.ok(slammed, "act %d: the cut lane still ends in a slam" % act)


func test_a_wreck_beside_the_lane_leaves_it_alone() -> void:
	var a := _stage(2)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	var open_lane := _lock_lane(sim, boss)
	var oex: int = open_lane["ex"]
	var oey: int = open_lane["ey"]
	boss["st"] = SiegeBoss.St.SHELL
	sim.rocks.append({"x": open_lane["sx"] + 200 * F, "y": open_lane["sy"], "kind": 2})
	var lane := _lock_lane(sim, boss)
	Runner.T.eq([lane["ex"], lane["ey"]], [oex, oey], "an off-lane wreck does not move the lane end")


func test_the_arenas_stamped_wrecks_never_leave_the_drawn_lane_a_lie() -> void:
	# The real arena always has the slabs at (96,130) / (544,130) and stones at (230,290) / (410,290).
	for sd in [1, 2, 3, 4]:
		for px in [40, 120, 230, 320, 410, 520, 600]:
			var sim := SimWorld.new(sd, 1)
			var gy: int = sim.camera_top + 100 * F
			sim.rocks.clear()
			sim.sandbags.clear()
			var boss := SiegeBoss.make(gy, sim._scaled_boss_hp(SiegeBoss.HP))
			boss["hp"] = boss["max_hp"] / 2
			sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": boss})
			sim._stamp_siege_cover(gy)
			sim.god_mode = true
			sim.players[0]["x"] = px * F
			sim.players[0]["y"] = gy + 250 * F
			boss["x"] = clampi((px + 60) * F, SiegeBoss.X_MIN, SiegeBoss.X_MAX)
			SiegeBoss._begin_rev(sim, boss, sim.players[0])
			var lane := SiegeBoss.lane(boss)
			var ex: int = lane["ex"]
			var ey: int = lane["ey"]
			_drive(sim, boss, SiegeBoss.St.STUN)
			Runner.T.eq([boss["x"], boss["y"]], [ex, ey], "seed %d player x=%d: the hull rests on the lane end" % [sd, px])


# --- 3. nowhere to stand along the wall ------------------------------------------------------------

## Fight a stationary player for `ticks` of boss time at `act`: which of the three attacks reached him?
func _fight(act: int, px: int, py_dy: int, ticks: int) -> Dictionary:
	var a := _stage(act)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	var p: Dictionary = sim.players[0]
	p["x"] = px * F
	p["y"] = boss["gate_y"] + py_dy * F
	var out := {"charge": false, "fan": false, "shell": false}
	for _t in ticks:
		SiegeBoss.step(sim, boss)
		if boss["st"] == SiegeBoss.St.CHARGE and SiegeBoss._near(p["x"], p["y"], boss["x"], boss["y"], SiegeBoss.RAM_R):
			out["charge"] = true
		if boss["st"] == SiegeBoss.St.SWEEP and boss["st_t"] % SiegeBoss.SWEEP_FIRE_EVERY == 0:
			var d := SiegeBoss.fan_dir(boss["fx"], boss["fy"], SiegeBoss.beam_index(boss))
			var m := SiegeBoss._muzzle(boss)
			var rx: int = p["x"] - m[0]
			var ry: int = p["y"] - m[1]
			var along := Fixed.mul(rx, d[0]) + Fixed.mul(ry, d[1])
			var off := absi(Fixed.mul(rx, d[1]) - Fixed.mul(ry, d[0]))
			if along > 0 and along <= SiegeBoss.SWEEP_RANGE and off <= 9 * F:
				out["fan"] = true
	for s in sim.strikes:
		if SiegeBoss._near(s["x"], s["y"], p["x"], p["y"], SimWorld.GRENADE_RADIUS):
			out["shell"] = true
	return out


func test_no_standing_spot_on_the_wall_strip_dodges_the_whole_fight() -> void:
	# A whole fight = act 2 (charge) then act 3 (charge + MG fan). The hull's x clamp (90..550) leaves
	# the extreme corners to the act-3 fan, so the sweep is judged over both acts together.
	var safe := []
	for px in range(60, 600, 60):
		var reached := false
		for act in [2, 3]:
			var r := _fight(act, px, 14, 1800)
			if r["charge"] or r["fan"]:
				reached = true
		if not reached:
			safe.append("x%d" % px)
	Runner.T.eq(safe, [], "every spot hugging the gate wall is reached by the charge or the MG fan within a fight")


func test_the_hull_reaches_the_wall_strip_in_a_charge() -> void:
	var a := _stage(2)
	var sim: SimWorld = a[0]
	var boss: Dictionary = a[1]
	sim.players[0]["x"] = boss["x"]
	sim.players[0]["y"] = boss["gate_y"] + 14 * F
	SiegeBoss._begin_rev(sim, boss, sim.players[0])
	var p: Dictionary = sim.players[0]
	Runner.T.ok(SiegeBoss._near(p["x"], p["y"], boss["ex"], boss["ey"], SiegeBoss.RAM_R),
		"a charge at a wall-hugger ends within the lethal radius of him")


func test_no_position_in_the_arena_is_safe_from_shells_charge_and_fan_together() -> void:
	var safe := []
	var charge_free := 0
	for px in range(60, 600, 120):
		for dy in [14, 60, 130, 200, 280]:
			var hit := false
			for act in [2, 3]:
				var r := _fight(act, px, dy, 1500)
				if r["charge"] or r["fan"] or r["shell"]:
					hit = true
				if not r["charge"]:
					charge_free += 1
			if not hit:
				safe.append("x%d dy%d" % [px, dy])
	Runner.T.eq(safe, [], "every arena position is touched by at least one attack over a fight")
	Runner.T.ok(charge_free > 0, "the charge's limited range farther south is intended and stays")


# --- 4. themed waves keep the theme ----------------------------------------------------------------

func test_themed_waves_are_never_easier_than_the_old_roster() -> void:
	for theme in [7, 8]:
		for w in range(3, 10):
			var n := EndlessRoster.threat_new(w, theme)
			var o := EndlessRoster.threat_old(w, theme)
			Runner.T.ok(n >= o, "theme %d wave %d: tiered threat %d >= old %d" % [theme, w, n, o])
	Runner.T.eq(EndlessRoster.threat_new(5, 0), EndlessRoster.threat_new(5), "no theme = the shipped numbers")


func test_a_locked_theme_member_falls_back_to_an_unlocked_member_not_an_elite() -> void:
	# wave 6: ghillie (debut 9) and drone (debut 11) are locked, sniper (debut 4) is not
	Runner.T.eq(EndlessRoster.themed_kind(4, 6, 7), "sniper", "marksmen: a locked ghillie roll becomes a sniper")
	Runner.T.eq(EndlessRoster.themed_kind(5, 6, 7), "sniper", "marksmen: a locked drone roll becomes a sniper")
	Runner.T.eq(EndlessRoster.themed_kind(3, 6, 8), "grenadier", "bombardment: a locked sapper roll becomes a grenadier")
	Runner.T.eq(EndlessRoster.themed_kind(1, 3, 7), "elite", "...and only a fully locked theme gives a plain elite")
	Runner.T.eq(EndlessRoster.themed_kind(1, 10, 7), "sniper", "an unlocked member is untouched")
	Runner.T.eq(EndlessRoster.themed_kind(9, 6, 0), EndlessRoster.kind_for(9, 6), "no theme = the shipped resolution")


func _themed_elites(mod: int, w: int) -> Dictionary:
	var sim := SimWorld.new(23, 1, "endless")
	sim.step([SimInput.new()])
	sim.wave = w - 1
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.intermission_ticks = 0
	sim._start_wave()
	sim.wave_mod = mod
	sim.wave_pending = EndlessRoster.wave_budget(w, EndlessRoster.theme_of(mod))
	var kinds := {}
	var seen: Array = []
	var guard := 0
	while sim.wave_pending > 0 and guard < 6000:
		guard += 1
		sim.wave_mod = mod
		sim.step([SimInput.new()])
		for p in sim.players:
			p["alive"] = true
			p["invuln"] = 600
		for e in sim.enemies:
			var known := false
			for s in seen:
				if is_same(s, e):
					known = true
					break
			if not known:
				seen.append(e)
				kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
		if sim.enemies.size() > 40:
			sim.enemies.clear()
	return kinds


func test_an_early_themed_wave_still_reads_as_its_theme() -> void:
	for mod in [7, 8]:
		var k := _themed_elites(mod, 6)
		Runner.T.eq(int(k.get("elite", 0)), 0, "theme %d wave 6: no plain elites dilute the theme (%s)" % [mod, k])
		if mod == 7:
			Runner.T.ok(int(k.get("sniper", 0)) >= 3, "marksmen wave 6 fields several snipers")
			Runner.T.eq(int(k.get("grenadier", 0)), 0, "...and nothing off-theme")
		else:
			Runner.T.ok(int(k.get("grenadier", 0)) >= 3, "bombardment wave 6 fields several grenadiers")
			Runner.T.eq(int(k.get("sniper", 0)), 0, "...and nothing off-theme")


func test_a_debut_on_a_themed_wave_is_never_skipped() -> void:
	# wave 3 debuts the grenadier (off the MARKSMEN theme): the first-sight card still lands
	var k := _themed_elites(7, 3)
	Runner.T.eq(int(k.get("grenadier", 0)), 1, "the wave-3 grenadier debut survives a MARKSMEN wave")
	var k2 := _themed_elites(8, 4)
	Runner.T.eq(int(k2.get("sniper", 0)), 1, "the wave-4 sniper debut survives a BOMBARDMENT wave")


func test_the_trickle_budget_follows_the_rolled_theme() -> void:
	for w in [3, 4, 6, 8]:
		var sim := SimWorld.new(9, 1, "endless")
		sim.step([SimInput.new()])
		sim.wave = w - 1
		sim.wave_pending = 0
		sim.enemies.clear()
		sim.intermission_ticks = 0
		sim._start_wave()
		Runner.T.eq(sim.wave_pending, EndlessRoster.wave_budget(w, EndlessRoster.theme_of(sim.wave_mod, sim.second_mod())),
			"wave %d budget = base + the compensation for its own theme (mod %d)" % [w, sim.wave_mod])


# --- 5. the two flags are hashed ------------------------------------------------------------------

func test_escort_and_crater_flags_are_in_the_checksum() -> void:
	var sim := SimWorld.new(3, 1)
	sim._spawn_enemy(300 * F, sim.camera_top + 50 * F, false)
	sim._add_strike(200 * F, sim.camera_top + 80 * F)
	var base := sim.checksum()
	sim.enemies[sim.enemies.size() - 1]["escort"] = true
	Runner.T.ok(sim.checksum() != base, "tagging an enemy as an escort changes the checksum")
	sim.enemies[sim.enemies.size() - 1]["escort"] = false
	Runner.T.eq(sim.checksum(), base, "a false escort flag leaves the stream byte-identical")
	sim.strikes[sim.strikes.size() - 1]["crater"] = true
	Runner.T.ok(sim.checksum() != base, "a crater shell changes the checksum")
	sim.strikes[sim.strikes.size() - 1]["crater"] = false
	Runner.T.eq(sim.checksum(), base, "a non-crater shell leaves the stream byte-identical")
