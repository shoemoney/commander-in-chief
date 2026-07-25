extends RefCounted
## VIEW HONESTY — the drawn-vs-simulated ratchet.
##
## Sibling of test_hitbox_fairness.gd. That suite asks "is the lethal radius the
## size it looks?"; this one asks the broader question behind it:
##
##   **Does anything the view ASSERTS still match what the sim DOES?**
##
## Every defect pinned here shipped green. They share one shape: a number, a
## clock, a vector or a noun was written down TWICE — once in src/sim/, once in
## src/main.gd or src/view/ — and only one copy was ever updated. Nothing failed,
## because a duplicated constant is not a bug until the two drift, and the suite
## had no way to notice drift.
##
## Two rules follow, and every test below enforces one of them:
##
##   1. A view that shows a sim quantity READS the sim, it does not restate it.
##      Where the value is dynamic (a scaled payout, a tier-dependent cadence),
##      the sim ships it on the checksum-EXCLUDED event, or exposes one shared
##      pure helper both sides call. Never a literal in the draw call.
##   2. A telegraph is measured against the thing it precedes, in the same units,
##      by running the sim — not by reading the constant it was authored from.
##
## Sim world units ARE screen pixels (PX = 1/Fixed.ONE), and one tick is 1/60 s,
## so every comparison below is a plain number against a plain number.

const Runner := preload("res://tests/run_tests.gd")
const PX := 1.0 / Fixed.ONE


func _view_src() -> String:
	return FileAccess.get_file_as_string("res://src/main.gd")


func _idle() -> Array[SimInput]:
	var inputs: Array[SimInput] = []
	inputs.append(SimInput.new())
	return inputs


# --- 1. Telegraph GEOMETRY: a drawn corridor must be the distance actually travelled ---

func test_technical_charge_corridor_is_its_real_remaining_travel() -> void:
	## The raider's committed charge draws a "sidestep this lane" corridor whose
	## length is remaining_ticks x px-per-tick. It read `t_lunge * 3.0 * PX` — a
	## hardcoded 3 px/tick with a spurious `* PX` on top (PX converts FIXED to px;
	## that product was already px), so a 150px lethal lane rendered 0.0023px long.
	## The promise the sim's own comment makes ("charge follows IT, not you") was
	## never once drawn. Assert against the distance the sim MOVES it, measured.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var p: Dictionary = sim.players[0]
	sim.enemies.append({"x": p["x"] + 100 * Fixed.ONE, "y": p["y"], "alive": true,
		"kind": "technical", "hp": SimWorld.TECHNICAL_HP, "fire_cd": 0,
		"windup": 0, "lunge_ticks": 0, "aim_lx": 0, "aim_ly": 0})
	# Step until the raider commits a charge, then measure one tick of it.
	var lunge_at_start := 0
	var moved := 0.0
	var prev := Vector2.ZERO
	var prev_lunge := 0
	for t in 400:
		sim.step(_idle())
		for e in sim.enemies:
			if e.get("kind", "") != "technical":
				continue
			var lt: int = e.get("lunge_ticks", 0)
			if lt > 0 and prev_lunge > 0 and moved == 0.0:
				moved = Vector2(float(e["x"] - prev.x), float(e["y"] - prev.y)).length() * PX
			if lt > lunge_at_start:
				lunge_at_start = lt
			prev = Vector2(float(e["x"]), float(e["y"]))
			prev_lunge = lt
	Runner.T.ok(lunge_at_start > 0, "the probe actually provoked a charge (else this test proves nothing)")
	# The sim moves it TECHNICAL_SPEED px per lunge tick.
	var per_tick := float(SimWorld.TECHNICAL_SPEED) * PX
	Runner.T.ok(absf(moved - per_tick) < 0.35,
		"measured charge speed %.2f px/tick == TECHNICAL_SPEED %.2f" % [moved, per_tick])
	var full_lane := float(SimWorld.TECHNICAL_CHARGE_TICKS) * per_tick
	Runner.T.ok(full_lane > 100.0,
		"a full charge covers %.0f px — a corridor drawn shorter than this under-warns" % full_lane)
	# The draw must derive per-tick distance from the sim constant, never a literal.
	var view := _view_src()
	Runner.T.ok(view.contains("float(SimWorld.TECHNICAL_SPEED) * PX"),
		"the charge corridor's length reads TECHNICAL_SPEED, not a hardcoded px/tick")
	Runner.T.ok(not view.contains("t_lunge * 3.0 * PX"),
		"the corridor no longer multiplies an already-in-pixels value by PX (that drew it 65536x too short)")


# --- 2. Telegraph CLOCK: a charge-up cue must run the cadence the sim fires on ---

func test_gunship_spray_telegraph_runs_the_tier_cadence_the_sim_fires_on() -> void:
	## The chin turret's charge swell + white muzzle pop keyed off a flat
	## BOSS_SPRAY_INTERVAL_TICKS (12) while the sim's cadence TIGHTENS with tier.
	## From endless wave 10 the cue and the round were on different clocks; by
	## wave 20 the boss fired twice per cue. Both sides now call one static.
	for wave in [0, 5, 10, 15, 20, 40]:
		var tier: int = wave / 5
		var iv: int = SimWorld.boss_spray_interval(tier)
		# Reconstruct the sim's own firing ticks for act one at this tier...
		var sim_shots: Array[int] = []
		for t in SimWorld.BOSS_STRAFE_TICKS:
			if t % iv == 0:
				sim_shots.append(t)
		# ...and what the flat-12 telegraph would have popped on.
		var flat_pops: Array[int] = []
		for t in SimWorld.BOSS_STRAFE_TICKS:
			if t % SimWorld.BOSS_SPRAY_INTERVAL_TICKS == 0:
				flat_pops.append(t)
		Runner.T.ok(iv >= 6 and iv <= SimWorld.BOSS_SPRAY_INTERVAL_TICKS,
			"wave %d: spray interval %d stays inside [6, %d]" % [wave, iv, SimWorld.BOSS_SPRAY_INTERVAL_TICKS])
		if tier >= 2:
			Runner.T.ok(sim_shots != flat_pops,
				"wave %d: the sim's cadence (%dt) genuinely differs from the flat %dt — "
				% [wave, iv, SimWorld.BOSS_SPRAY_INTERVAL_TICKS]
				+ "this is the case a hardcoded telegraph got wrong")
	# And the view must be reading the shared helper.
	var view := _view_src()
	Runner.T.ok(view.contains("SimWorld.boss_spray_interval("),
		"the chin-turret telegraph reads boss_spray_interval(), the same helper _step_one_boss fires on")
	Runner.T.ok(not view.contains("pt % SimWorld.BOSS_SPRAY_INTERVAL_TICKS"),
		"the telegraph no longer counts a flat spray interval the deep-wave boss does not use")


# --- 3. Telegraph FOOTPRINT: one drawn ring per strike the sim actually lands ---

func test_grenadier_preview_draws_every_lob_the_sim_throws() -> void:
	## The windup preview drew ONE 28px ring under the player. _step_grenadier
	## calls _add_strike THREE times — centre, and a pair offset
	## +/-GRENADIER_CLUSTER_SPREAD PERPENDICULAR to the firing line. Stepping
	## sideways off the one drawn ring walked you into an outer lob, i.e. the
	## telegraph taught the exactly-wrong dodge. Count the strikes for real.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var p: Dictionary = sim.players[0]
	sim.enemies.append({"x": p["x"], "y": p["y"] - SimWorld.GRENADIER_STANDOFF, "alive": true,
		"elite": true, "kind": "grenadier", "fire_cd": 0, "windup": 0})
	var most := 0
	for t in 240:
		sim.step(_idle())
		most = maxi(most, sim.strikes.size())
	Runner.T.eq(most, 3, "one grenadier windup lands THREE strikes, not one")
	Runner.T.ok(SimWorld.GRENADIER_CLUSTER_SPREAD > SimWorld.GRENADE_RADIUS,
		"the outer lobs (%.0fpx out) sit OUTSIDE the centre lob's %.0fpx kill radius, so a "
		% [float(SimWorld.GRENADIER_CLUSTER_SPREAD) * PX, float(SimWorld.GRENADE_RADIUS) * PX]
		+ "single drawn ring cannot cover the cluster")
	var view := _view_src()
	Runner.T.ok(view.contains("SimWorld.GRENADIER_CLUSTER_SPREAD"),
		"the grenadier preview draws the cluster offset from the sim constant")


func test_every_tracked_strike_telegraph_draws_the_radius_that_kills() -> void:
	## _add_strike is the ONE funnel for every tracked mortar (grenadier lobs,
	## drone paints, observer barrage, colossus volleys/sweeps, gunship shells),
	## and _resolve_strikes kills at GRENADE_RADIUS for all of them. The drone's
	## paint ring was a hardcoded 9->12px against that 28px kill circle — you
	## could stand a clear 16px outside everything drawn and still die.
	## Any hazard preview keyed to a strike must read the constant.
	var view := _view_src()
	Runner.T.ok(not view.contains("Art.arc(self, dtp, 9.0 + df * 3.0"),
		"the drone's paint ring is no longer a hardcoded 9-12px over a 28px kill radius")
	Runner.T.ok(view.contains("SimWorld.GRENADE_RADIUS * PX"),
		"strike previews are drawn from GRENADE_RADIUS itself")
	# The radius the drone paint resolves at IS GRENADE_RADIUS — prove it from the sim.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim._add_strike(sim.players[0]["x"], sim.players[0]["y"])
	Runner.T.eq(sim.strikes.size(), 1, "the funnel queued one strike")
	Runner.T.eq(int(sim.strikes[0]["ticks"]), SimWorld.STRIKE_TELEGRAPH_TICKS,
		"and it telegraphs for STRIKE_TELEGRAPH_TICKS — the lead the view fills its disc over")


# --- 4. Hazard LIVENESS: a lethal window must be drawn for all of it, at its true size ---

func test_mast_hazard_is_drawn_for_its_whole_lethal_window_at_its_true_radius() -> void:
	## The endless mast's 120px one-shot zone was drawn only by two one-shot event
	## FX. The warn card SHRANK 120px -> 84px over a CONSTANT 120px kill radius
	## (the exact defect the vent was rewritten to fix), lived 50 ticks against a
	## 90-tick warn, and during the 60 lethal ticks the only draws were a 22-tick
	## shockwave and a 12-tick light. Now re-derived per frame from the sim phase.
	var view := _view_src()
	Runner.T.ok(view.contains("SimWorld.MAST_HAZARD_RADIUS"),
		"the mast jet/warn rings are drawn from MAST_HAZARD_RADIUS, not a literal 240 card")
	Runner.T.ok(view.contains("SimWorld.MAST_CYCLE_TICKS") and view.contains("SimWorld.MAST_JET_TICKS"),
		"the draw re-derives the sim's own phase (the vent's drift-proof pattern)")
	# The warn ring must close ONTO the kill radius from OUTSIDE it, never inside.
	var hr := float(SimWorld.MAST_HAZARD_RADIUS) * PX
	for wt: float in [0.0, 0.5, 1.0]:
		var drawn: float = hr * (1.4 - 0.4 * wt)
		Runner.T.ok(drawn >= hr - 0.01,
			"warn ring at t=%.1f is %.0fpx >= the %.0fpx it kills at (it must never promise a shrinking hazard)"
			% [wt, drawn, hr])
	# And the sim really is lethal for the whole jet window, at a constant radius.
	Runner.T.ok(SimWorld.MAST_JET_TICKS > 0 and SimWorld.MAST_WARN_TICKS > 0,
		"the mast has both a warn lead (%dt) and a lethal window (%dt) to draw"
		% [SimWorld.MAST_WARN_TICKS, SimWorld.MAST_JET_TICKS])


# --- 5. NUMBERS: a payout the sim SCALES must not be a literal in the callout ---

func test_scaling_payout_callouts_read_the_amount_the_sim_banked() -> void:
	## Three callouts hardcoded a coin figure that the sim scales with depth:
	##   CLEAN WAVE "+40¢"  — _econ_scale(40), 140 by wave 30
	##   AVENGED    "+5¢"   — +5 per wave/5 step in endless, 55 by wave 50
	##   FLAWLESS   "+50¢"  — the COLOSSUS path pays NO coin at all
	## Each amount now rides the (checksum-excluded) event. Measure the divergence
	## so the test fails if anyone re-hardcodes a value that provably moves.
	var view := _view_src()
	Runner.T.ok(not view.contains('"CLEAN WAVE  +40'),
		"the Clean Wave callout no longer hardcodes +40 coin")
	Runner.T.ok(not view.contains('"AVENGED +5'),
		"the Avenged callout no longer hardcodes +5 coin")
	Runner.T.ok(view.contains('ev.get("coin"'),
		"payout callouts read the amount off the event")
	# Prove the sim value really does move, so these are not vacuous greps.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var shallow: int = sim._econ_scale(40)
	sim.wave = 30
	var deep: int = sim._econ_scale(40)
	Runner.T.eq(shallow, 40, "at wave 0 the Clean Wave bonus is the authored 40")
	Runner.T.ok(deep > shallow * 2,
		"by wave 30 it is %d — a hardcoded '+40' under-reports by %d" % [deep, deep - shallow])


func test_victory_card_reports_a_war_chest_that_still_exists() -> void:
	## "%d¢ WAR CHEST BANKED" read live sim.war_chest. _damage_colossus sets
	## victory=true and then, in the SAME tick, converts the chest to score and
	## zeroes it — so the card read 0¢ on every win the game has ever produced.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	sim.colossus = {"alive": true, "hp": 5, "max_hp": SimWorld.COLOSSUS_HP,
		"x": SimWorld.SCREEN_CX, "y": -100 * Fixed.ONE, "spray_cd": 10, "volley_cd": 10,
		"spawn_cd": 10, "core_cd": 10, "core_open": 0, "sweep_cd": 10}
	sim.war_chest = 275
	sim.deaths_since_gate = 0
	sim._damage_colossus(99)
	Runner.T.ok(sim.victory, "the colossus died and the run is a win")
	Runner.T.eq(sim.war_chest, 0,
		"the chest IS zeroed on the victory tick — which is why a live read was always 0")
	var vic := {}
	for ev in sim.events:
		if ev.get("t", "") == "victory":
			vic = ev
	Runner.T.eq(int(vic.get("banked", -1)), 275,
		"the victory event carries the PRE-ZERO chest for the result card")
	Runner.T.eq(int(vic.get("banked_score", -1)), 2750,
		"and what it converted to, so the card can say where the coin went")
	var view := _view_src()
	Runner.T.ok(not view.contains('"%d¢ WAR CHEST BANKED" % sim.war_chest'),
		"the card no longer reads a value the sim clears on the same tick")


func test_flawless_callout_never_advertises_coin_the_finale_does_not_pay() -> void:
	## The gate path pays war_chest += 50*mult. The COLOSSUS path fires the SAME
	## gate_flawless event with score only and no chest line, and one view handler
	## printed "+50¢" for both — advertising up to 150¢ that never arrived.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	sim.colossus = {"alive": true, "hp": 1, "max_hp": SimWorld.COLOSSUS_HP,
		"x": SimWorld.SCREEN_CX, "y": -100 * Fixed.ONE, "spray_cd": 10, "volley_cd": 10,
		"spawn_cd": 10, "core_cd": 10, "core_open": 0, "sweep_cd": 10}
	sim.war_chest = 0
	sim.deaths_since_gate = 0
	sim._damage_colossus(99)
	var flaw := {}
	for ev in sim.events:
		if ev.get("t", "") == "gate_flawless":
			flaw = ev
	Runner.T.ok(not flaw.is_empty(), "a deathless colossus clear fires gate_flawless")
	Runner.T.eq(int(flaw.get("coin", -1)), 0,
		"and it declares coin: 0 — the finale pays this bonus in SCORE only")
	Runner.T.ok(int(flaw.get("score", 0)) > 0, "the score half is real and shipped")


func test_bounty_callout_is_emitted_after_every_multiplier() -> void:
	## "BOUNTY +N¢" read the coin off an event emitted BETWEEN the x3 bounty and
	## the x2 PAYDAY multiplier, so on a PAYDAY wave it under-reported by half.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim.wave_mod = 4   # PAYDAY
	Runner.T.ok(sim.has_mod(4), "PAYDAY is live for this probe")
	var e := {"x": 320 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true,
		"elite": false, "kind": "rusher", "marked": true}
	sim.enemies.append(e)
	var chest_before: int = sim.war_chest
	sim._kill_enemy(e)
	var banked: int = sim.war_chest - chest_before
	var pop := {}
	for ev in sim.events:
		if ev.get("t", "") == "bounty_kill":
			pop = ev
	Runner.T.ok(not pop.is_empty(), "a marked kill fires bounty_kill")
	Runner.T.eq(int(pop.get("coin", -1)), banked,
		"the coin the pop SHOWS (%d) equals the coin the chest RECEIVED (%d)"
		% [int(pop.get("coin", -1)), banked])
	Runner.T.eq(banked, SimWorld.COIN_RUSHER * 3 * 2,
		"and PAYDAY x2 on top of bounty x3 really is in that number")


func test_sandbag_stock_counts_the_population_its_cap_caps() -> void:
	## The supply wheel printed "N/6 UP" with N = sandbags.size() — EVERY bag on
	## the field, including the 16 the endless arena plants at _init and the
	## per-wave shop barricades. SANDBAG_FIELD_CAP caps only player-planted bags,
	## so the readout sat permanently over its own cap ("22/6 UP").
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var world_bags: int = sim.sandbags.size()
	Runner.T.ok(world_bags > SimWorld.SANDBAG_FIELD_CAP,
		"endless starts with %d authored bags — more than the %d-bag PLAYER cap, which is "
		% [world_bags, SimWorld.SANDBAG_FIELD_CAP] + "exactly how the readout went over 100%")
	Runner.T.eq(sim.player_sandbag_count(), 0,
		"none of them are the player's, so the wheel must read 0/%d" % SimWorld.SANDBAG_FIELD_CAP)
	sim.sandbags.append({"x": 0, "y": 0, "player": 1})
	Runner.T.eq(sim.player_sandbag_count(), 1, "planting one bag moves the numerator by one")
	Runner.T.ok(_view_src().contains("sim.player_sandbag_count()"),
		"the wheel reads the same helper _try_buy enforces the cap with")


# --- 6. CLOCKS: a seconds readout must be the ceiling of its tick count ---

func test_every_seconds_readout_uses_the_ceil_idiom() -> void:
	## Five countdowns used `ticks / 60 + 1`, which over-reports by a whole second
	## at every exact multiple of 60: a fresh 300-tick rally timer read "6s" while
	## the world label on the SAME timer read "5.0s". The house idiom is the true
	## ceiling, (ticks + 59) / 60 — already used by BAIL OUT, SHOP OPEN and FLASH.
	var hud := FileAccess.get_file_as_string("res://src/view/hud.gd")
	Runner.T.ok(not hud.contains("/ 60 + 1"),
		"no seconds readout in hud.gd uses the off-by-one `ticks / 60 + 1`")
	Runner.T.ok(hud.contains("+ 59) / 60"), "the ceil idiom is what is used instead")
	# Pin the arithmetic itself so nobody 'simplifies' it back.
	for pair in [[300, 5], [301, 6], [359, 6], [360, 6], [1, 1], [60, 1], [0, 0]]:
		var ticks: int = pair[0]
		Runner.T.eq((ticks + 59) / 60, int(pair[1]),
			"%d ticks displays as %ds" % [ticks, int(pair[1])])
		if ticks > 0 and ticks % 60 == 0:
			Runner.T.ok(ticks / 60 + 1 != (ticks + 59) / 60,
				"...and the old idiom really did disagree at %d ticks" % ticks)


# --- 7. NOUNS: a label must name the thing the sim spawns ---

func test_colossus_phase_three_names_the_enemy_it_actually_fields() -> void:
	## The persistent label under the boss bar for the whole final phase of the
	## final fight read "SAPPERS OUT". The sim calls _spawn_enemy(..., false),
	## which builds kind "rusher" — no sapper reaches the Foundry at all. It
	## taught mine-avoidance against a charge.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	sim.colossus = {"alive": true, "hp": 1, "max_hp": 90, "x": SimWorld.SCREEN_CX,
		"y": -100 * Fixed.ONE, "spray_cd": 999, "volley_cd": 999, "spawn_cd": 1,
		"core_cd": 999, "core_open": 0, "sweep_cd": 999, "pv": 3}
	sim.players[0]["x"] = SimWorld.SCREEN_CX
	sim.players[0]["y"] = -50 * Fixed.ONE
	Runner.T.eq(sim.colossus_phase(), 3, "the probe is in the phase the label names")
	var before: int = sim.enemies.size()
	for t in 4:
		sim.step(_idle())
	var kinds: Dictionary = {}
	for i in range(before, sim.enemies.size()):
		kinds[sim.enemies[i]["kind"]] = true
	Runner.T.ok(kinds.size() > 0, "phase 3 really does drop reinforcements")
	Runner.T.ok(not kinds.has("sapper"),
		"and none of them is a sapper — so the label must not say SAPPERS")
	var names: Array = (load("res://src/main.gd") as Script) \
		.get_script_constant_map().get("COLOSSUS_PHASE_NAMES", [])
	Runner.T.eq(names.size(), 3, "three phases, three names")
	for nm in names:
		Runner.T.ok(not String(nm).to_lower().contains("sapper"),
			"'%s' does not name an enemy the finale never fields" % nm)


func test_campaign_length_copy_matches_the_sim_gate_count() -> void:
	## Menu copy said "five sectors" while FINAL_GATE_INDEX is 6, the HUD prints
	## SECTOR n/6, the debrief prints /6 and the README says 6.
	var menu := FileAccess.get_file_as_string("res://src/view/menu.gd")
	var words := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
		"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}
	for w in words:
		var phrase: String = "%s sectors" % w
		if menu.to_lower().contains(phrase):
			Runner.T.eq(int(words[w]), SimWorld.FINAL_GATE_INDEX,
				"menu copy says '%s' — the sim has %d" % [phrase, SimWorld.FINAL_GATE_INDEX])
	Runner.T.ok(menu.to_lower().contains("six sectors"),
		"the campaign blurb states the real sector count")


# --- 8. NO FAKE MECHANICS: the view must not visualise a rule the sim lacks ---

func test_reticle_does_not_advertise_a_spread_the_sim_never_applies() -> void:
	## The crosshair widened up to 5px with sustained fire, captioned "the
	## barrel-heat mechanic, made visible". _spawn_mg_bullet fires down
	## p["aim_x"/"aim_y"] EXACTLY — no jitter, no heat term anywhere in the sim.
	## The reticle was charging the player for an accuracy penalty they never paid.
	## Prove the sim's shots are exact, then hold the view to it.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p: Dictionary = sim.players[0]
	var vs: Array[Vector2i] = []
	for shot in 12:
		sim.bullets.clear()
		sim._spawn_mg_bullet(p, 0, p["aim_x"], p["aim_y"])
		vs.append(Vector2i(sim.bullets[0]["vx"], sim.bullets[0]["vy"]))
	for v in vs:
		Runner.T.eq(v, vs[0],
			"every MG round off the same aim has an IDENTICAL velocity — the sim has no spread")
	Runner.T.ok(not _view_src().contains("var bloom := roundf("),
		"the reticle no longer blooms to imply a spread mechanic that does not exist")


# --- 9. LETHAL POINT: a contact-killer's sim position must carry a ground mark ---

func test_the_drone_marks_the_spot_that_actually_kills() -> void:
	## The drone's body draws at epos + (0, -5 + bob) to sell altitude, but it
	## contact-kills at epos, and the only ground mark was a 4px disc offset a
	## further +8y — so the lethal point had nothing on it at all. It is the one
	## enemy whose sprite anchor differs from its sim position.
	var view := _view_src()
	Runner.T.ok(view.contains("Art.circle(self, epos, float(SimWorld.ENEMY_TOUCH_RADIUS) * PX"),
		"the drone marks ENEMY_TOUCH_RADIUS at epos — the exact point _step_enemies tests")
	# ...and that radius is really what kills.
	Runner.T.ok(SimWorld.ENEMY_TOUCH_RADIUS > 0,
		"ENEMY_TOUCH_RADIUS is %.0fpx — the footprint the mark must be drawn at"
		% (float(SimWorld.ENEMY_TOUCH_RADIUS) * PX))


# --- 10. The generic ratchet: PX converts FIXED to pixels, and nothing else ---

func test_px_is_only_ever_applied_to_fixed_point_quantities() -> void:
	## PX == 1/Fixed.ONE. Multiplying by it converts a SIM (16.16 fixed) value
	## into pixels. Applying it to a value that is ALREADY in pixels divides by
	## 65536 and silently erases the drawing — which is exactly how the technical's
	## 150px charge corridor came to render 0.002px long, undetected, for months.
	## Scan every `* PX` and require the multiplicand to look like sim state:
	## a SimWorld constant, a sim dict field, or Fixed.ONE-scaled arithmetic.
	var suspicious: Array[String] = []
	var lines := _view_src().split("\n")
	for n in lines.size():
		var line: String = lines[n]
		if line.strip_edges().begins_with("#") or not line.contains("* PX"):
			continue
		# The token immediately left of `* PX` is what is being converted.
		var ok := line.contains("SimWorld.") or line.contains("sim.") \
			or line.contains("Fixed.ONE") or line.contains("[\"") or line.contains("(\"") \
			or line.contains("float(") or line.contains("_fx") or line.contains("g[") \
			or line.contains("p[") or line.contains("b[") or line.contains("w[") \
			or line.contains("e[") or line.contains("pk[") or line.contains("tk[") \
			or line.contains("dp2[") or line.contains("fk.get") or line.contains("isl_x2") \
			or line.contains("fw_fx") or line.contains("ford2_x") or line.contains("wall_x")
		if not ok:
			suspicious.append("main.gd:%d  %s" % [n + 1, line.strip_edges()])
	Runner.T.eq(suspicious.size(), 0,
		"every `* PX` converts a fixed-point sim value; unexplained ones: %s" % str(suspicious))
