extends RefCounted
## Endless variety: the tiered roster (one debut per wave, never an easier wave than
## the old all-at-once roster), the gunship that cannot die before it lands, and
## minibosses that open differently by tier (src/sim/endless_roster.gd).

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


## Kinds fielded by ONE wave's trickle: stage wave `w` and step until the trickle is
## dry, recording every kind alive on any tick (spawns can be shot or walk off, so the
## set is read each tick). Returns {kinds: {kind: peak-simultaneous-new-count},
## spawned: bodies fielded}.
func _wave_roster(seed_v: int, w: int) -> Dictionary:
	var sim := SimWorld.new(seed_v, 1, "endless")
	sim.step([_idle()])   # wave 1 starts
	sim.wave = w - 1
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.intermission_ticks = 0
	sim._start_wave()
	var budget: int = sim.wave_pending
	var seen: Array = []   # enemy dict references already counted
	var order: Array = []
	var guard := 0
	while sim.wave_pending > 0 and guard < 6000:
		guard += 1
		sim.step([_idle()])
		for p in sim.players:
			p["alive"] = true
			p["invuln"] = 600
		for e in sim.enemies:
			if e["kind"] == "pilot":
				continue
			var known := false
			for s in seen:
				if is_same(s, e):
					known = true
					break
			if not known:
				seen.append(e)
				order.append(e["kind"])
		# keep the arena from filling up and gating the spawner
		if sim.enemies.size() > 40:
			sim.enemies.clear()
	var kinds := {}
	for k in order:
		kinds[k] = int(kinds.get(k, 0)) + 1
	return {"kinds": kinds, "bodies": order.size(), "budget": budget, "wave": sim.wave}


func test_each_archetype_debuts_alone_on_its_own_wave() -> void:
	var waves := {}
	for k in EndlessRoster.DEBUT:
		var w: int = EndlessRoster.DEBUT[k]
		Runner.T.ok(not waves.has(w), "%s debuts on a wave of its own (%d)" % [k, w])
		waves[w] = k
	# A new thing at least every 3 waves from 3 through 15 (minibosses count at 5/10/15).
	for w in range(3, 16):
		var fresh := false
		for d in range(w - 2, w + 1):
			if waves.has(d) or (d % 5 == 0 and d >= 5):
				fresh = true
		Runner.T.ok(fresh, "a new beat lands within 3 waves of wave %d" % w)
	var specials := ["grenadier", "sniper", "shield", "sapper", "ghillie", "drone",
		"mg_nest", "technical", "broadcast"]
	for seed_v in [11, 23, 77]:
		for w in range(3, 15):
			var r: Dictionary = _wave_roster(seed_v, w)
			Runner.T.eq(r["wave"], w, "staged wave %d is live (seed %d)" % [w, seed_v])
			for k in specials:
				var n: int = int(r["kinds"].get(k, 0))
				if EndlessRoster.unlocked(k, w):
					continue
				if EndlessRoster.DEBUT[k] == w:
					Runner.T.eq(n, 1, "wave %d fields exactly ONE %s (its debut), seed %d" % [w, k, seed_v])
				else:
					Runner.T.eq(n, 0, "wave %d fields no %s before its debut (seed %d)" % [w, k, seed_v])


func test_waves_one_and_two_are_riflemen_and_rushers_only() -> void:
	for w in [1, 2]:
		var r: Dictionary = _wave_roster(5, w)
		for k in r["kinds"]:
			Runner.T.ok(k == "rusher" or k == "elite", "wave %d is plain bodies, saw %s" % [w, k])


func test_no_wave_is_easier_than_the_old_roster() -> void:
	for w in range(1, 41):
		Runner.T.ok(EndlessRoster.threat_new(w) >= EndlessRoster.threat_old(w),
			"wave %d: tiered threat %d >= old %d" % [w, EndlessRoster.threat_new(w), EndlessRoster.threat_old(w)])
	# ...and the tiering is real, not a no-op: early waves pay for the removed archetypes in bodies.
	Runner.T.ok(EndlessRoster.bonus_count(3) > 0, "wave 3 compensates with extra bodies")
	Runner.T.eq(EndlessRoster.bonus_count(15), 0, "the roster is whole by 15: no compensation needed")
	Runner.T.eq(EndlessRoster.bonus_count(2), 0, "waves 1-2 are untouched")
	# The sim honours the budget the helper promises.
	for w in [3, 6, 9, 12]:
		var r: Dictionary = _wave_roster(9, w)
		Runner.T.eq(r["budget"], EndlessRoster.wave_budget(w), "wave %d trickle budget = base + bonus" % w)


func _boss_sim(wave: int) -> SimWorld:
	var sim := SimWorld.new(31, 1, "endless")
	sim.step([_idle()])
	sim.wave = wave - 1
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.intermission_ticks = 0
	sim._start_wave()
	return sim


func test_miniboss_is_untouchable_until_it_lands_and_the_shots_visibly_bounce() -> void:
	var sim := _boss_sim(5)
	var boss: Dictionary = sim.endless_boss
	Runner.T.ok(boss["phase_t"] < 0, "the wave-5 gunship spawns mid-approach")
	var hp0: int = boss["hp"]
	var off: Array = SimWorld.boss_flyin_offset(boss["phase_t"])
	var bx: int = boss["x"] + int(off[0])
	var by: int = boss["gate_y"] - SimWorld.BOSS_Y_OFFSET + int(off[1])
	sim.events.clear()
	var b := {"x": bx, "y": by}
	Runner.T.ok(sim._bullet_hits_boss(b), "a round on the approaching hull is still consumed")
	Runner.T.eq(boss["hp"], hp0, "...but does no damage")
	var blocks := 0
	var hits := 0
	for ev in sim.events:
		if ev["t"] == "armor_block":
			blocks += 1
		if ev["t"] == "boss_hit":
			hits += 1
	Runner.T.eq(blocks, 1, "a bounce cue (armor_block) marks the refusal")
	Runner.T.eq(hits, 0, "no boss_hit (that cue means DAMAGE)")
	sim._explode(bx, by)
	Runner.T.eq(boss["hp"], hp0, "grenades bounce off the approaching hull too")
	sim._rocket_blast(bx, by)
	Runner.T.eq(boss["hp"], hp0, "so does rocket splash")
	# Land it: damage works again.
	boss["phase_t"] = 0
	sim.events.clear()
	Runner.T.ok(sim._bullet_hits_boss({"x": boss["x"], "y": boss["gate_y"] - SimWorld.BOSS_Y_OFFSET}), "landed: round connects")
	Runner.T.eq(boss["hp"], hp0 - 1, "landed: the hull takes damage")


func test_the_approach_cannot_be_skipped_by_killing_it() -> void:
	var sim := _boss_sim(5)
	var boss: Dictionary = sim.endless_boss
	boss["hp"] = 1
	sim._damage_boss(boss, 99)   # backstop: even a direct damage call is refused
	Runner.T.ok(boss["alive"], "a mid-approach gunship survives any damage call")
	Runner.T.eq(boss["hp"], 1, "hp untouched")


func test_boss_variants_name_and_open_differently() -> void:
	var names := {}
	for tier in [1, 2, 3, 4]:
		names[EndlessRoster.boss_name(tier)] = true
	Runner.T.eq(names.size(), 4, "waves 5/10/15/20 wear four different plate names")
	Runner.T.eq(EndlessRoster.boss_name(5), EndlessRoster.boss_name(1), "the names cycle")
	Runner.T.eq(EndlessRoster.boss_act(1, 40, 40), 1, "wave 5 opens in act 1")
	Runner.T.eq(EndlessRoster.boss_act(2, 40, 40), 2, "wave 10 opens in act 2")
	Runner.T.eq(EndlessRoster.boss_act(2, 10, 40), 3, "...and still reaches act 3 on HP")
	Runner.T.eq(EndlessRoster.boss_act(0, 40, 40), 1, "campaign (tier 0) is untouched")
	# Measured in the sim: the wave-10 gunship calls the cover-denial salvo at FULL hp.
	for tier_wave in [[5, 0], [10, 2]]:
		var sim := _boss_sim(tier_wave[0])
		var boss: Dictionary = sim.endless_boss
		boss["phase_t"] = 49   # next step is t=50, the first salvo tick
		sim.players[0]["x"] = 200 * Fixed.ONE
		sim.players[0]["y"] = (sim.camera_top + 250 * Fixed.ONE)
		sim.strikes.clear()
		sim._step_one_boss(boss)
		Runner.T.eq(sim.strikes.size(), tier_wave[1] / 2,
			"wave %d gunship at full HP: salvo strikes on t=50" % tier_wave[0])


func test_warden_brings_escorts_on_arrival() -> void:
	for tw in [[5, 0], [10, 0], [15, 2], [20, 2]]:
		var sim := _boss_sim(tw[0])
		var boss: Dictionary = sim.endless_boss
		sim.wave_pending = 0
		sim.enemies.clear()
		boss["phase_t"] = -1
		sim._step_one_boss(boss)
		Runner.T.eq(boss["phase_t"], 0, "wave %d gunship has landed" % tw[0])
		var n := 0
		for e in sim.enemies:
			if e["alive"]:
				n += 1
		Runner.T.eq(n, tw[1], "wave %d: %d escorts touch down with it" % [tw[0], tw[1]])
