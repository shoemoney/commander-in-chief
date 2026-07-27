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
const Art := preload("res://src/view/art.gd")
const Main := preload("res://src/main.gd")
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


# --- 11. IMPORT-SCALE DRIFT: a SCALE row must know the canvas it was tuned on ---

## Every `Art.SCALE` row is a multiplier authored against ONE canvas size, and
## `main._spr` sizes off the IMPORTED texture — not the source PNG. So adding or
## changing `process/size_limit` in a `.import` resizes that sprite on screen with
## no error, no warning and no failing test. Nothing in the sim moves with it, so
## every extent tied to the art (a blocking AABB, a hitbox, a pickup radius) stays
## exactly where it was and quietly stops matching what the player can see.
##
## It has shipped three times:
##   * the bunker — SCALE tuned on a 440px source, capped to 128px: the strongpoint
##     drew 3.44x too small around an unchanged 48x32 AABB, so rounds died in
##     invisible armour a sprite-width off the drawn wall (343% of its silhouette).
##   * the capsule glyphs — tuned uncapped at 512/1024px, capped to 128px: the
##     1-in-6 elite reward drew at THREE PIXELS under a 12px pickup radius.
##   * the spotter's pennant — tuned on 256px, capped to 128px: halved to a speck.
## In all three the numbers still read fine in review, because the diff that broke
## them was in a different file from the number it invalidated.
##
## SPRITE_CANVAS is the missing half of each SCALE row: the imported canvas that
## row was tuned against. Kept here beside the assertion rather than derived —
## deriving it from the same import the test is checking would assert nothing. An
## import sweep, a re-bake at a new resolution, or a brand-new SCALE row all move
## a number out from under this table and turn the suite red. When that happens
## the fix is to re-tune SCALE by the same factor the canvas moved (that is all
## three fixes above were) and THEN update the row — never the row alone.
const SPRITE_CANVAS := {
	"ammobox": 160, "barbedwire": 220, "barrel": 160, "barricade": 200, "barrier": 220, "bridge_mid": 220,
	"bridge_ramp": 220, "bunker": 128, "bunker2": 128, "cactus_dead1": 120, "cactus_dead2": 120,
	"cactus_dead3": 120, "cactus_large": 120, "cactus_small": 96, "cap_claymore": 128, "cap_flash": 128,
	"cap_pierce": 128, "cap_rend": 128, "cap_smoke": 128, "cap_spread": 128, "cap_triple": 128,
	"colossus_barrel": 72, "colossus_body": 128, "corpse_soldier1": 140, "corpse_soldier2": 140,
	"courier": 64, "crate_airstrike": 56, "crate_ammo": 56, "crate_grenade": 56, "crate_stack": 220,
	"crater": 160, "crater_field": 240, "crater_water": 240, "dropped_shield": 140, "dry_shrub": 220,
	"elite": 256, "enemy_assault": 128, "enemy_lmg": 128, "enemy_shotgun": 128, "enemy_smg": 128,
	"enemy_sniper": 128, "explosion0": 128, "explosion1": 128, "explosion2": 128, "explosion3": 128,
	"fallen_merc": 180, "flag_iran": 600, "flag_marker": 200, "flak_gun": 220, "frogman": 128,
	"frogman_speargun": 128, "fx_bubble1": 64, "fx_bubble2": 64, "fx_flame": 200, "fx_fumes": 128,
	"fx_impactdark": 200, "fx_muzzle_fan": 128, "fx_smoke": 200, "ghillie": 128, "gunship_barrel": 48,
	"gunship_body": 112, "hud_flag": 128, "item_binoculars": 40, "item_bullet": 32, "item_bullet_shotgun": 32,
	"m_bombsuit": 128, "m_drone": 48, "m_heli_attack2": 112, "m_heli_transport": 112, "m_jet": 128,
	"m_pilot": 56, "m_radar_tank": 104, "m_rocket_truck": 104, "m_soldier2": 128, "m_technical": 96,
	"mg_stand": 160, "mg_tripod": 160, "mz_pop": 128, "observer": 128, "pickup_vest": 56, "player1": 256,
	"player2": 256, "radio_tower": 220, "riot_shield": 64, "rock1": 220, "rock2": 260, "rusher": 256,
	"sandbag_beige": 80, "sapper": 128, "scrub": 72, "skyline_chimney": 160, "skyline_mast": 200,
	"tank_barrel": 72, "tank_body": 104, "tank_hulk": 104, "tank_shell": 32, "tank_trap": 200,
	"tent": 260, "trench": 260, "tumbleweed": 200, "wall_sandbag": 240, "wall_sandbag_b": 240,
	"wall_sandbag_c": 240, "wall_sandbag_end": 120, "watchtower": 260, "wep_claymore": 40, "wep_flashbang": 40,
	"wep_grenade": 40, "wep_mg": 56, "wep_rifle": 56, "wep_shotgun": 56, "wep_smoke": 40, "wreck": 220,
	"wreck_apc": 104, "wreck_halftrack": 240, "wreck_light_tank": 96, "wreck_technical": 96,
}


func test_every_scale_row_still_has_the_canvas_it_was_tuned_against() -> void:
	for key in Art.SCALE:
		Runner.T.ok(Art.TEX.has(key), "SCALE row '%s' has a texture to scale" % key)
		if not Art.TEX.has(key):
			continue
		Runner.T.ok(SPRITE_CANVAS.has(key),
			"new SCALE row '%s' must record the imported canvas its multiplier was tuned " % key
			+ "against — see the note above; _spr sizes off the IMPORT, not the source PNG")
		if not SPRITE_CANVAS.has(key):
			continue
		var t: Texture2D = Art.tex(key)
		var got := maxi(int(t.get_size().x), int(t.get_size().y))
		var want: int = SPRITE_CANVAS[key]
		Runner.T.ok(got == want,
			("'%s' imports at %dpx but its SCALE (%.3f) was tuned on a %dpx canvas — it now "
				% [key, got, Art.draw_scale(key), want])
			+ ("draws %.2fx its authored size while every sim extent tied to it stayed put. "
				% (float(got) / float(maxi(want, 1))))
			+ "Re-tune SCALE by that factor, THEN update SPRITE_CANVAS.")


func test_the_canvas_table_does_not_outlive_the_scale_rows() -> void:
	## The other direction: a retired sprite must not leave a stale row behind to
	## be silently "verified" forever. A ratchet nobody prunes stops being read.
	for key in SPRITE_CANVAS:
		Runner.T.ok(Art.SCALE.has(key),
			"SPRITE_CANVAS still lists '%s', which no longer has an Art.SCALE row" % key)
# --- 11. The GRADED number is the SIMULATED number ---

func test_graded_kill_streak_is_the_sims_kill_streak() -> void:
	## The view kept its own combo counter and the RANK grade read IT. Two ways it
	## drifted from `sim.kill_streak`, both measured below:
	##   * it counted every "kill" event, including the mg_nest kills the sim
	##     deliberately excludes from the streak;
	##   * its window advanced on PHYSICS FRAMES, which keep running through
	##     hitstop and pause, while the sim's window advances on TICKS.
	## So `_run_rank()` — which weights the streak at 5x to pick the letter the
	## player is graded with, plus the ONE-MAN ARMY / IRON NERVES titles — graded
	## the run on a number the simulation never agreed happened. The view counter
	## survives as `_blip_streak` (blip pitch only, renamed so it can never again
	## be mistaken for the authoritative one); the graded value reads the sim.
	var sim := SimWorld.new(7, 1)
	var kill_events := 0
	for k in 4:
		var e := {"x": 0, "y": 0, "alive": true, "elite": false, "kind": "rusher"}
		sim.enemies.append(e)
		sim._kill_enemy(e)
	# ...then a nest, which fires a kill EVENT but must not advance the streak.
	var nest := {"x": 0, "y": 0, "alive": true, "elite": true, "kind": "mg_nest"}
	sim.enemies.append(nest)
	sim._kill_enemy(nest)
	for ev in sim.events:
		if ev["t"] == "kill":
			kill_events += 1
	Runner.T.eq(kill_events, 5, "5 kill events fired (the view's per-event counter reads 5)")
	Runner.T.eq(sim.kill_streak, 4, "the SIM's streak is 4 — the nest is excluded")
	Runner.T.ok(kill_events != sim.kill_streak,
		"the two numbers provably differ, so which one the grade reads is load-bearing")
	# The grade path must read the sim's number, and only the sim's number.
	var view := _view_src()
	Runner.T.ok(view.contains("_run_best_streak = maxi(_run_best_streak, sim.kill_streak)"),
		"_track_bests feeds the graded streak straight from sim.kill_streak")
	Runner.T.ok(not view.contains("maxi(_run_best_streak, _blip_streak)"),
		"the graded streak is never fed from the view's audio-facing ramp")
	Runner.T.ok(not view.contains("var _kill_streak"),
		"the ambiguous `_kill_streak` name is gone — the audio ramp is `_blip_streak`")
	var rank_body := view.substr(view.find("func _run_rank("))
	rank_body = rank_body.substr(0, rank_body.find("\nfunc "))
	Runner.T.ok(rank_body.contains("_run_best_streak") and not rank_body.contains("_blip_streak"),
		"_run_rank() grades on _run_best_streak and never touches the audio ramp")
	# ...and the milestone pop, which advertises the sim's +25/50/100% bonus, reads
	# the same sim streak — on the ramp it claimed a bonus the sim had not awarded.
	Runner.T.ok(view.contains("var sstreak: int = sim.kill_streak"),
		"the streak-milestone FX reads the sim's streak, not the ramp")


# --- 12. Two spend paths, one rate: the comment said "same", the code said otherwise ---

func test_crate_and_wheel_credit_the_same_score() -> void:
	## `_collect_pickups` credited `cost * 10` under a comment reading "Same score
	## credit as the spend-wheel buy ... (the _try_buy invariant)", while `_try_buy`
	## credited `cost * 6`. The comment was the lie, and the drift mattered twice
	## over: walking to a crate paid 67% more score than radioing the IDENTICAL item
	## in, and at 10x the crate was the one spend path at exact parity with the 10x
	## the victory payout gives an UNSPENT chest — i.e. the score-neutral
	## buy-everything-immediately that the 40% haircut in _try_buy exists to kill.
	## Both now read SPEND_SCORE_MULT. Measured by spending, not read off constants.
	var cost := SimWorld.SHOP_AMMO_COST
	var a := SimWorld.new(0xC0FFEE, 1)
	var pa: Dictionary = a.players[0]
	a.war_chest = 5000
	pa["mg_ammo"] = 0
	a.pickups = [{"x": pa["x"], "y": pa["y"], "kind": 0, "cost": cost}]
	var a_score: int = a.score
	var a_chest: int = a.war_chest
	a._collect_pickups(pa, 0)
	var b := SimWorld.new(0xC0FFEE, 1)
	var pb: Dictionary = b.players[0]
	b.war_chest = 5000
	pb["mg_ammo"] = 0
	var b_score: int = b.score
	var b_chest: int = b.war_chest
	b._try_buy(pb, 0)
	Runner.T.eq(a_chest - a.war_chest, cost, "the ground crate charged the chest")
	Runner.T.eq(b_chest - b.war_chest, cost, "the wheel charged the same chest")
	Runner.T.eq(a.score - a_score, b.score - b_score,
		"the same item costs the same and scores the same however it was bought")
	Runner.T.eq(a.score - a_score, cost * SimWorld.SPEND_SCORE_MULT,
		"and both pay the single-sourced SPEND_SCORE_MULT rate")
	Runner.T.ok(SimWorld.SPEND_SCORE_MULT < 10,
		"spending stays DISCOUNTED against the 10x an unspent chest converts at on victory — "
		+ "at parity, buying everything on sight costs nothing and hoarding is never a choice")


# --- 13. The fork-lane signpost must name the lane the sim actually wired ---

func _stream_fork_at(seed: int, gate_n: int) -> SimWorld:
	var sim := SimWorld.new(seed, 1)
	sim._gate_counter = gate_n - 1
	sim.camera_top = sim._next_gate_y + 2 * SimWorld.VIEW_H - SimWorld.F_ONE
	sim.step(_idle())
	return sim


func test_fork_signposts_name_the_lane_the_sim_actually_wired() -> void:
	## main.gd's route-fork HUD painted "< CACHE" at a hardcoded LEFT x (84) and
	## "BOUNTY >" at a hardcoded RIGHT x (556 - width) for EVERY fork gate — but the
	## sim mirrors gate 4's island (fork_x 380, the CACHE lane on the RIGHT), so the
	## label was pointing at the wrong road at gate 4: the sign says CACHE on the
	## fortified-mines side while the real wire-slowed CACHE lane sits on the other
	## side of the screen. Probe the sim's OWN wire zone (_in_fork_wire) to find which
	## side it actually slows, and assert the drawn "< CACHE" x lands on THAT side —
	## not a hardcoded assumption of which side is which.
	for gate_n in SimWorld.FORK_GATES:
		var sim := _stream_fork_at(7, gate_n)
		var gate_y := 0
		var fx := 0
		for g in sim.gates:
			if g.get("fork_x", 0) != 0:
				gate_y = g["y"]
				fx = g["fork_x"]
				break
		Runner.T.ok(fx != 0, "gate %d: a fork gate streamed" % gate_n)
		var probe_y: int = gate_y + 100 * Fixed.ONE   # inside the first _in_fork_wire band (+90..+110)
		var wire_left: bool = sim._in_fork_wire(fx * Fixed.ONE - 100 * Fixed.ONE, probe_y)
		var wire_right: bool = sim._in_fork_wire(fx * Fixed.ONE + 100 * Fixed.ONE, probe_y)
		Runner.T.ok(wire_left != wire_right, "gate %d: the wire zone slows exactly one side (left=%s right=%s)" % [gate_n, wire_left, wire_right])
		# fork_cache_is_left is THE predicate the sim itself uses to decide the CACHE
		# side (both the wire zone and every content beat read it after the fix) — pin
		# it agrees with the independently-probed wire side, so a future change to
		# either can't drift the two apart.
		Runner.T.eq(SimWorld.fork_cache_is_left(fx), wire_left,
			"gate %d: fork_cache_is_left(%d) agrees with the independently-probed wire side" % [gate_n, fx])
		# The load-bearing assertion: run _draw_gates' OWN sign-placement helper
		# (fork_sign_xs) against the sim's OWN predicate output, and check the
		# resulting drawn x actually lands on the probed wire side. Paired with
		# the tightened grep pin below (which requires the exact
		# `fork_cache_is_left(int(isl_x))` call, not just the substring), a
		# hardcoded sign (e.g. cache_left fed a literal 260 at the draw call
		# site) now goes red — that was the gap the un-pinned substring left.
		var xs := Main.fork_sign_xs(SimWorld.fork_cache_is_left(fx), 60.0, 70.0)
		Runner.T.eq(xs.x < 320.0, wire_left,
			"gate %d: the drawn '< CACHE' label x (%.1f) lands on the probed wire-slowed side (wire_left=%s)" % [gate_n, xs.x, wire_left])
	# Grep pin (this suite's house pattern — see _view_src() at the top of the file):
	# main.gd must derive the fork lane side from the sim's shared predicate, not
	# restate its own 320.0 copy or draw the CACHE label at an unconditional x.
	# Pinned to the exact call (the measured fork_x, not a hardcoded stand-in) —
	# a bare "fork_cache_is_left(" substring check would still pass if the real
	# argument were swapped for a literal like 260.
	var view := _view_src()
	Runner.T.ok(view.contains("SimWorld.fork_cache_is_left(int(isl_x))"),
		"main.gd derives the fork lane side from the sim's own predicate, fed the real measured fork_x")
	Runner.T.ok(not view.contains("isl_x < 320.0"),
		"the bare 320.0 fork-side literal is gone from main.gd (collapsed into fork_cache_is_left)")


# --- 6. Telegraph VECTOR: the lane the view paints must be the lane the shot flies ---

## Source-derived roster of every aim-locked shooter: each `e["aim_lx"] = ` in the
## sim, resolved to its enclosing `func _step_<kind>`. Adding a sixth shooter that
## locks an aim vector makes the equality assertion below go red the day it lands,
## rather than shipping a sixth telegraph nobody checked.
func _aim_locking_kinds() -> Array:
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var lines := src.split("\n")
	var fn := ""
	var kinds := {}
	for ln in lines:
		if ln.begins_with("func _step_"):
			fn = ln.substr(11, ln.find("(") - 11)
		elif ln.strip_edges().begins_with("e[\"aim_lx\"]") and ln.contains("=") and fn != "":
			kinds[fn] = true
	var out := kinds.keys()
	out.sort()
	return out


func _spawn_shooter(sim: SimWorld, kind: String, x: int, y: int) -> Dictionary:
	if kind == "mg_nest":
		sim._spawn_mg_nest(x, y)
	elif kind == "elite":
		sim.enemies.append({"x": x, "y": y, "alive": true, "elite": true,
			"kind": "elite", "fire_cd": 0, "windup": 0})
	else:
		sim._spawn_special(x, y, kind)
	return sim.enemies[-1]


func _bullets_at(sim: SimWorld, x: int, y: int) -> Array:
	## Every live enemy bullet sitting exactly on (x, y) — i.e. still on the muzzle
	## it was born on this tick. Used to attribute a shot to ONE shooter in a live
	## endless field. See the note in the telegraph test.
	var out: Array = []
	for b in sim.enemy_bullets:
		if b["x"] == x and b["y"] == y:
			out.append(b)
	return out


func test_every_painted_telegraph_lane_fires_down_itself() -> void:
	## THE CLASS RULE: "a drawn line is a committed shot". Four of the five
	## aim-locked shooters obeyed it; the mg_nest opted out. It painted the lane
	## it locked at burst start, then RE-ACQUIRED the nearest player at the top of
	## every round (sim_world.gd `_step_mg_nest`) and fired somewhere else.
	##
	## MEASURED before the fix (tools/probe_mg_lane.gd, 1P endless, nest at x=320,
	## the player strafing): the painted lane sat 20.4 / 14.8 / 10.4 deg off the
	## bullet at 140 / 213 / 318 px range, and missed the player it was actually
	## shooting at by 58.5 / 59.3 / 59.7 px — 5.9x BULLET_HIT_RADIUS (10 px). Six
	## body-widths off the amber lane and you are still the thing being shot.
	##
	## The sim's tracking rake is a GOOD mechanic and is untouched; the view stops
	## lying about it. Both sides now read one helper, Main.telegraph_dir().
	##
	## SAMPLING WINDOW vs the defect it pins: the mg_nest defect spans the whole
	## 30-tick AIM window plus a 3-round burst at 8-tick gaps = 46 ticks, repeating
	## every 30+16+90 = 136 ticks. This drives 600 ticks per (kind x range) cell,
	## i.e. ~4.4 bursts per cell, and strafes the player left<->right every 40
	## ticks so the bot never parks on a wall and stops generating drift (the
	## probe's rounds 2-5 read 0.0 deg for exactly that reason).
	const MAX_ANGLE_DEG := 3.0
	var hit_r: float = float(SimWorld.BULLET_HIT_RADIUS) * PX
	var kinds := _aim_locking_kinds()
	Runner.T.eq(kinds, ["elite", "ghillie", "mg_nest", "sniper", "technical"],
		"the aim-locked shooter roster derived from src/sim/sim_world.gd is the set this test drives")
	for kind in kinds:
		var commits := 0
		var worst_ang := 0.0
		var worst_perp := 0.0
		var worst_at := ""
		for range_px in [140, 180, 240]:
			var sim := SimWorld.new(0xC0FFEE, 1, "endless")
			var p: Dictionary = sim.players[0]
			var e := _spawn_shooter(sim, kind, 320 * Fixed.ONE, p["y"] - range_px * Fixed.ONE)
			var inp := SimInput.new()
			for t in 600:
				# Strafe back and forth: a bot pinned on a wall stops drifting and
				# would let a stale lane score 0.0 deg for free.
				inp.move_x = 256 if (t / 40) % 2 == 0 else -256
				var drawn := Main.telegraph_dir(sim, e)   # what the view paints THIS tick
				var rel := Vector2(float(p["x"] - e["x"]), float(p["y"] - e["y"])) * PX
				var ex0: int = e["x"]
				var ey0: int = e["y"]
				var muzzled_before := _bullets_at(sim, ex0, ey0)
				sim.step([inp])
				if not e.get("alive", false):
					break
				# A "commit" is the tick the promise is cashed. ATTRIBUTION MATTERS:
				# this is endless, the wave spawner keeps adding OTHER shooters, and
				# the first draft of this check read sim.enemy_bullets[-1] — charging
				# `e` with a neighbour's bullet and reporting 11.8-40.6 deg of fake
				# drift on the four honest shooters. A bullet born this tick still
				# sits on its own shooter's exact fixed-point muzzle (projectiles
				# step BEFORE enemies in SimWorld.step), so attribute by position.
				var fired := Vector2.ZERO
				var muzzled_after := _bullets_at(sim, e["x"], e["y"])
				if muzzled_after.size() > muzzled_before.size():
					var b: Dictionary = muzzled_after[-1]
					fired = Vector2(float(b["vx"]), float(b["vy"]))
				elif int(e.get("lunge_ticks", 0)) > 0:
					# The technical fires no bullet — its projectile is the truck. Its
					# painted corridor is checked against where the body ACTUALLY went.
					fired = Vector2(float(e["x"] - ex0), float(e["y"] - ey0))
				if fired.length() <= 0.0 or drawn.length() <= 1.0:
					continue
				commits += 1
				var ld := drawn.normalized()
				var ang := rad_to_deg(absf(ld.angle_to(fired.normalized())))
				# The angle, restated in the units a player feels: how far apart the
				# painted lane and the real shot are OUT WHERE YOU ARE STANDING.
				#   NOT the drawn lane's distance from the player — for a LOCKED
				#   shooter that distance is the mechanic (you sidestepped the sniper
				#   line, which is the whole point), and asserting on it wrongly
				#   reported 38-62 px of "defect" on the four honest shooters.
				var sep: float = rel.length() * sin(deg_to_rad(ang))
				if ang > worst_ang:
					worst_ang = ang
					worst_at = "%s @%dpx t=%d" % [kind, range_px, t]
				worst_perp = maxf(worst_perp, sep)
		Runner.T.ok(commits > 0,
			"%s: the drive actually produced a committed shot (%d) — the check is not vacuous" % [kind, commits])
		Runner.T.ok(worst_ang <= MAX_ANGLE_DEG,
			"%s: painted telegraph is within %.1f deg of the shot it promises (worst %.1f deg over %d commits, %s)"
				% [kind, MAX_ANGLE_DEG, worst_ang, commits, worst_at])
		Runner.T.ok(worst_perp <= hit_r,
			"%s: at the target's own range the painted lane and the real shot are within one bullet radius (%.0f px) of each other (worst %.1f px)"
				% [kind, hit_r, worst_perp])


func test_the_enemy_draw_path_reads_one_telegraph_source() -> void:
	## The defect above was possible because five draw sites each restated
	## `Vector2(e.aim_lx, e.aim_ly)` inline. Pin that they route through the one
	## helper the test above measures — otherwise a future site can re-open the gap
	## while test_every_painted_telegraph_lane_fires_down_itself stays green.
	var view := _view_src()
	Runner.T.eq(view.count("telegraph_dir(sim, e)"), 5,
		"all five enemy telegraph draw sites (sniper/technical/mg_nest/ghillie/elite) read Main.telegraph_dir()")
	Runner.T.eq(view.count("e.get(\"aim_lx\""), 1,
		"main.gd reads the raw aim vector in exactly ONE place — inside telegraph_dir() — so no draw site can restate it")
