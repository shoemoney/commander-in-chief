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
			or line.contains("fw_fx") or line.contains("ford_x") or line.contains("wall_x")
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
	Runner.T.ok(SimWorld.SPEND_SCORE_MULT < SimWorld.VICTORY_SCORE_MULT,
		"spending stays DISCOUNTED against the VICTORY_SCORE_MULT an unspent chest converts at on victory — "
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


# --- 9. TERMINAL VALUE: every way a run can end must convert the War Chest, and the
# debrief must SAY what it converted to. The win path did both; both loss paths did
# neither — you could die holding 224 coin and no screen ever mentioned it. ---

func test_no_run_ending_bypasses_the_chest_converter() -> void:
	## CLASS ratchet, set derived from source. `wiped = true` / `victory = true` are the
	## sim's only terminal latches; each must sit inside the function that also converts
	## the chest (`_latch_wipe` for the losing end, `_damage_colossus` for the win), so a
	## terminal state added tomorrow that forgets the payout reddens the day it lands.
	var lines := FileAccess.get_file_as_string("res://src/sim/sim_world.gd").split("\n")
	var fn := ""
	var found := 0
	var offenders: Array[String] = []
	for i in lines.size():
		var ln: String = lines[i]
		if ln.begins_with("func ") or ln.begins_with("static func "):
			fn = ln.substr(ln.find("func ") + 5).split("(")[0]
		var code: String = ln.split("#")[0].strip_edges()
		if code == "wiped = true" or code == "victory = true":
			found += 1
			if fn != "_latch_wipe" and fn != "_damage_colossus":
				offenders.append("sim_world.gd:%d  `%s` in %s()" % [i + 1, code, fn])
	Runner.T.ok(found >= 2, "scraped the terminal-state latches out of the sim (found %d)" % found)
	Runner.T.eq(offenders.size(), 0,
		"every terminal latch converts the War Chest — offenders: %s" % str(offenders))


func test_debrief_states_the_chest_conversion() -> void:
	## The K.I.A. card must name the salvage, and take the NUMBER from the sim event —
	## a view-side multiplier literal is exactly the drift this suite exists to stop.
	var mult: int = SimWorld.WIPE_SCORE_MULT
	var rows: Array = Main._wipe_chest_row(180, 180 * mult)
	Runner.T.eq(rows.size(), 1, "a chest with coin left in it earns a debrief row")
	if rows.size() == 1:
		var txt := String(rows[0].get("text", ""))
		Runner.T.ok(txt.contains("WAR CHEST"), "…and names the WAR CHEST (got %s)" % txt)
		Runner.T.ok(txt.contains("180"), "…states the coin that was left (got %s)" % txt)
		Runner.T.ok(txt.contains(Art.group_digits(180 * mult)),
			"…and what it converted to, %d, computed from SimWorld.WIPE_SCORE_MULT (got %s)"
				% [180 * mult, txt])
	Runner.T.eq(Main._wipe_chest_row(0, 0).size(), 0, "died broke: say nothing")
	# The HOW-TO page must teach both rates from the sim consts, never a hand-typed number.
	var msrc := FileAccess.get_file_as_string("res://src/view/menu.gd")
	Runner.T.ok(msrc.contains("SimWorld.SPEND_SCORE_MULT") and msrc.contains("SimWorld.WIPE_SCORE_MULT"),
		"the HOW-TO WAR CHEST page builds both multipliers from the sim consts")
	# review tell 1: the same page never mentioned the WIN conversion at all — and closed with
	# "That's the choice.", presenting spend-vs-salvage as the complete decision while the
	# richest rate in the economy (10x + 5000 on a win) went untaught. It must teach it,
	# const-derived like the other two rates, so a retune updates the copy for free.
	Runner.T.ok(msrc.contains("SimWorld.VICTORY_SCORE_MULT") and msrc.contains("SimWorld.VICTORY_SCORE_BONUS"),
		"the HOW-TO WAR CHEST page teaches the WIN conversion from the sim consts")
	var corpus := _menu_text_corpus()
	Runner.T.ok(corpus.contains("%d×" % SimWorld.VICTORY_SCORE_MULT), "the drawn page states the win bank rate")
	Runner.T.ok(corpus.contains(Art.group_digits(SimWorld.VICTORY_SCORE_BONUS)), "the drawn page states the flat win bonus")
	Runner.T.ok(not corpus.contains("That's the choice"), "no copy presents spend-vs-salvage as the complete decision")


# --- 8. The COPY is a view assertion too: a rules page that names the run's contract ---

const Menu := preload("res://src/view/menu.gd")
const TML := preload("res://tests/test_menu_layout.gd")


## Every string the menu DRAWS, joined into one corpus: HOWTO_TABS x _endless_pages()
## (the rules pages) plus every Mode's row labels. Derived from source, so a rules page
## added tomorrow is audited the day it lands.
func _menu_text_corpus() -> String:
	var stub := TML._StubMain.new()
	var m = TML._CaptureMenu.new()
	m.main = stub
	m.size = Vector2(Menu.CANVAS_WIDTH, 360.0)
	m._open_t = 1.0
	var parts: PackedStringArray = []
	for tab in Menu.HOWTO_TABS.size():
		var pages := m._endless_pages() if tab == Menu.HOWTO_ENDLESS_TAB else 1
		for ep in pages:
			m.mode = Menu.Mode.HOWTO
			m._howto_page = tab
			m._howto_endless_page = ep
			m.ops.clear()
			var prev = Art.text_capture
			Art.text_capture = m.ops
			m._draw_howto()
			Art.text_capture = prev
			for op in m.ops:
				if op["k"] == "text":
					parts.append(String(op["id"]))
	for mode_id in Menu.Mode.values():
		m.mode = mode_id
		for it in m._menu_items():
			parts.append(String(it["label"]))
	m.free()
	stub.free()
	return " ".join(parts)


func test_the_rules_page_states_every_continue_the_campaign_actually_grants() -> void:
	## The WAR CHEST page read "No health bar, no second chance" and offered the chest
	## only "to REVIVE a fallen partner". Three continues the sim actually grants went
	## unmentioned — SELF-revive, the free broke-fallback rally, and the LAST STAND
	## finale where revives genuinely stop. Measure them out of the sim first, then
	## demand the page confess them.

	# (i) BROKE: a solo player with an empty chest rallies for free after BROKE_RESPAWN_TICKS.
	var s1 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p1: Dictionary = s1.players[0]
	s1.war_chest = 0
	p1["alive"] = false
	for _i in SimWorld.BROKE_RESPAWN_TICKS + 2:
		s1.step(_idle())
	Runner.T.ok(p1["alive"], "a broke solo campaign player DOES rally free after %d ticks"
		% SimWorld.BROKE_RESPAWN_TICKS)
	Runner.T.ok(not s1.wiped, "…and the run is not over")

	# (ii) SELF-REVIVE: a downed solo player with coin pays the chest and stands up NOW.
	var s2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p2: Dictionary = s2.players[0]
	p2["alive"] = false
	s2.war_chest = 2000
	var cost: int = s2.revive_cost(p2)
	var before: int = s2.war_chest
	var rev: Array[SimInput] = []
	var ri := SimInput.new()
	ri.revive = true
	rev.append(ri)
	s2.step(rev)
	Runner.T.ok(p2["alive"], "a funded downed player CAN revive themselves (no partner needed)")
	Runner.T.eq(before - s2.war_chest, cost, "…and the chest is debited exactly revive_cost")

	# (iii) LAST STAND: past the final gate BOTH continues are refused.
	var s3 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p3: Dictionary = s3.players[0]
	s3.last_stand = true
	p3["alive"] = false
	s3.war_chest = 2000
	s3.step(rev)
	Runner.T.ok(not p3["alive"], "LAST STAND refuses a PAID revive")
	s3.war_chest = 0
	for _i in SimWorld.BROKE_RESPAWN_TICKS + 2:
		s3.step(_idle())
	Runner.T.ok(not p3["alive"], "LAST STAND refuses the free rally too — the copy's one true 'no revives'")

	# --- The page must say all of it, and take the timer off the sim const.
	var corpus := _menu_text_corpus()
	Runner.T.ok(corpus.length() > 400, "the menu corpus captured real ink (%d chars)" % corpus.length())
	for lie in ["no second chance", "no continues", "one life"]:
		Runner.T.ok(not corpus.to_lower().contains(lie),
			"no menu string claims '%s' — the sim grants continues" % lie)
	if corpus.to_lower().contains("no revives"):
		Runner.T.ok(corpus.contains("LAST STAND"),
			"the only 'no revives' sentence is the LAST STAND one")
	Runner.T.ok(corpus.contains("REVIVE yourself"),
		"the rules page says the chest revives YOURSELF, not just a partner")
	Runner.T.ok(corpus.contains("%ds" % (SimWorld.BROKE_RESPAWN_TICKS / 60)),
		"the rules page states the free-rally delay (%ds) off SimWorld.BROKE_RESPAWN_TICKS"
			% (SimWorld.BROKE_RESPAWN_TICKS / 60))
	Runner.T.ok(corpus.contains("LAST STAND"), "the rules page names the LAST STAND finale")
	var msrc := FileAccess.get_file_as_string("res://src/view/menu.gd")
	Runner.T.ok(msrc.contains("SimWorld.BROKE_RESPAWN_TICKS"),
		"the rally delay is DERIVED from the sim const, so a retune can't strand the copy")


func test_the_debrief_reports_the_continues_the_run_actually_used() -> void:
	## The card tallied kills, streak, prey and rescues — and never once said the run
	## was carried by revives. `p["deaths"]` had exactly ONE view read (hud.gd), and
	## the coin spent standing back up was invisible on both end cards.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p: Dictionary = sim.players[0]
	p["alive"] = false
	sim.war_chest = 2000
	var cost: int = sim.revive_cost(p)
	var before: int = sim.war_chest
	var rev: Array[SimInput] = []
	var ri := SimInput.new()
	ri.revive = true
	rev.append(ri)
	sim.step(rev)
	var paid := {}
	for e in sim.events:
		if e.get("t", "") == "revive":
			paid = e
	Runner.T.ok(not paid.is_empty(), "a paid revive emits a revive event")
	Runner.T.eq(int(paid.get("cost", -1)), before - sim.war_chest,
		"the revive event carries the coin it cost (%d), so the card never restates a price"
			% [before - sim.war_chest])
	Runner.T.ok(cost > 0, "…and that price is non-zero (%d)" % cost)

	# The FREE rally must never be billed to the player on the card.
	var s2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p2: Dictionary = s2.players[0]
	s2.war_chest = 0
	p2["alive"] = false
	var free_ev := {}
	for _i in SimWorld.BROKE_RESPAWN_TICKS + 2:
		s2.step(_idle())
		for e in s2.events:
			if e.get("t", "") == "revive":
				free_ev = e
	Runner.T.ok(not free_ev.is_empty(), "the broke fallback respawn emits a revive event too")
	Runner.T.eq(int(free_ev.get("cost", -1)), 0, "…and it costs 0 — the free rally is never billed")

	# --- Both end cards must carry the ledger row.
	# Loaded at RUNTIME (not via the Main const) so a missing method reports as a red
	# assertion instead of aborting the whole suite with a parse error.
	var ms: Script = load("res://src/main.gd")
	var has_rows := false
	for meth in ms.get_script_method_list():
		if String(meth["name"]) == "_continue_ledger_rows":
			has_rows = true
	Runner.T.ok(has_rows, "Main._continue_ledger_rows() is the one source for the continue tally")
	if has_rows:
		Runner.T.eq(ms._continue_ledger_rows(0, 0).size(), 0, "a clean run says nothing")
		var rows: Array = ms._continue_ledger_rows(3, 75)
		Runner.T.eq(rows.size(), 1, "a run that used continues earns exactly one row")
		if rows.size() == 1:
			var txt := String(rows[0].get("text", ""))
			Runner.T.ok(txt.contains("3"), "…stating the knockdown count (got %s)" % txt)
			Runner.T.ok(txt.contains("75"), "…and the coin spent getting back up (got %s)" % txt)
	var vsrc := _view_src()
	Runner.T.eq(vsrc.count("_continue_ledger_rows("), 3,
		"the ledger is built once and called from BOTH end cards (victory + K.I.A.), not just the loss")


# --- What death DELETES vs what the screen SAYS it deleted (cycle 7) --------
#
# The loss payload used to be three literals typed by hand into _kill_player's
# `player_down` event ("triple"/"pierce"/"spread"), and `revive` carried none at
# all. Meanwhile _respawn strips SEVEN per-player fields and _kill_player burns
# two global ones. Measured on HEAD: 3 of 9 named. Every accrual added to the
# strip list since was silently uncovered — the classic write-it-twice drift
# this suite exists to pin, except here the second copy was a hand-written list.
#
# So: derive the strip set from the SOURCE, then prove the sim names every one
# of them on an event and the view has a word for each.

## Fields _respawn zeroes that are NOT losses — timers and cooldowns that were
## about to expire anyway, so announcing them would be noise:
##   broke_timer  - the revive-affordability clock, meaningless while dead
##   roll_ticks   - the in-progress dodge-roll frame counter
##   boost_ticks  - the sprint window
## Same discipline as run_tests.gd's ERROR_ALLOW: an entry needs a justification.
const EPHEMERAL := ["broke_timer", "roll_ticks", "boost_ticks"]


## The set of accrued player state a death deletes, read out of _respawn's own body.
func _death_strip_keys() -> Array[String]:
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var start := src.find("\nfunc _respawn(")
	Runner.T.ok(start >= 0, "could not find _respawn( in sim_world.gd — the strip-set scrape is dead")
	var body := src.substr(start + 1)
	var nxt := body.find("\nfunc ")
	if nxt > 0:
		body = body.substr(0, nxt)
	var re := RegEx.create_from_string('p\\["([a-z_]+)"\\]\\s*=\\s*(0|false|assist_mode)\\b')
	var keys: Array[String] = []
	for m in re.search_all(body):
		var k := m.get_string(1)
		if k not in EPHEMERAL and k not in keys:
			keys.append(k)
	Runner.T.ok(keys.size() >= 5,
		"the _respawn strip-set scrape matched only %d fields — the parser is broken, not the sim" % keys.size())
	return keys


func test_every_field_death_strips_is_named_on_a_loss_payload() -> void:
	var strips := _death_strip_keys()
	var sim := SimWorld.new(7, 1)
	sim.tokens = 2
	sim.flawless_streak = 3
	var p: Dictionary = sim.players[0]
	for k in strips:
		# Fail LOUDLY on a key the player dict doesn't carry. Reading p[k] on a missing key
		# throws, and a throw mid-method silently aborts the remaining assertions and still
		# reports PASS (the documented "green but wrong" trap) — measured: planting an unknown
		# strip in _respawn took this test from 656 assertions to 635 and printed PASS.
		if not p.has(k):
			Runner.T.ok(false, "_respawn strips p[\"%s\"], which is not a field any player carries — the scrape or the sim is wrong" % k)
			continue
		p[k] = true if typeof(p[k]) == TYPE_BOOL else 300

	sim.events.clear()
	sim._kill_player(p)
	var down := {}
	for ev in sim.events:
		if ev["t"] == "player_down":
			down = ev
	Runner.T.ok(not down.is_empty(), "_kill_player emitted no player_down event")

	sim.events.clear()
	sim._respawn(p, p["y"], 0)
	var rev := {}
	for ev in sim.events:
		if ev["t"] == "revive":
			rev = ev
	Runner.T.ok(not rev.is_empty(), "_respawn emitted no revive event")
	var lost: Dictionary = rev.get("lost", {})

	# Every per-player accrual that actually went truthy -> falsy must be NAMED somewhere.
	for k in strips:
		if not p.has(k):
			continue   # already reported above
		var still_set: bool = (p[k] if typeof(p[k]) == TYPE_BOOL else p[k] != 0)
		if still_set:
			continue   # not stripped in this configuration (e.g. assist_mode re-issues the vest)
		Runner.T.ok(lost.has(k) or down.has(k),
			"death deletes p[\"%s\"] but neither player_down nor revive names it — the player watches it vanish with no cue" % k)

	# ...and the two GLOBAL losses _kill_player takes, which nothing ever announced.
	Runner.T.eq(down.get("token", 0), 1,
		"_kill_player burns a Commendation but player_down does not report the spend")
	Runner.T.eq(down.get("streak", -1), 3,
		"_kill_player zeroes flawless_streak but player_down does not report what was broken")

	# View half: a key with no noun prints nothing, which is the same silence in a new costume.
	var vsrc := _view_src()
	# Normalise line endings before slicing: a Windows checkout without .gitattributes
	# delivers "\r\n\r\n", which contains no "\n\n", so find() returned -1, the slice
	# collapsed to "" and every lookup below failed — Windows-only, 9 assertions, while
	# macOS and Linux stayed green. .gitattributes now pins eol=lf; this is the second lock.
	var vnorm := vsrc.replace("\r\n", "\n")
	var nouns := vnorm.substr(vnorm.find("const LOSS_NOUN"))
	var blank := nouns.find("\n\n")
	nouns = nouns.substr(0, blank) if blank > 0 else nouns
	Runner.T.ok(vsrc.find("const LOSS_NOUN") >= 0,
		"src/main.gd has no LOSS_NOUN table — the sim can name a loss the view has no word for")
	for k in (strips + ["token", "streak"]):
		Runner.T.ok('"%s"' % k in nouns,
			"the sim reports \"%s\" as lost but main.gd's LOSS_NOUN has no word for it" % k)


# --- stall_ticks is a STALE number the moment the sim holds the camera ------
#
# The sim-side freeze (SimWorld._step_observer) stops the counter accruing
# inside a gate arena, but it cannot un-accrue what a genuine loiterer banked
# BEFORE walking in — a player at stall_ticks=400 who then enters a held arena
# carries that 400 across the threshold. And _hint() is once-per-save-EVER, so
# burning "PUSH NORTH" on a stale value in a mode with no north is unrecoverable.
# Hence: every view line that reads sim.stall_ticks routes through the sim's own
# camera_held(), or is on this allowlist with a reason.
#
# SCOPE — this scrape stays on main.gd, but the earlier note here claimed hud.gd's three
# readers were "honest already" because _telegraph_spec swaps PRESSURE for CLEAR THE GATE
# "the moment a closed gate is on screen". That was FALSE, and writing it down is why the
# sibling half of the defect survived a whole honesty sweep: the note read the gate loop
# and never read the `stall_ticks > PRESSURE_WARN_TICKS` early-return three lines ABOVE it,
# which made the gate branch unreachable at a held camera (stall_ticks is frozen at 0 there).
# hud.gd now checks the gate branch BEFORE any stall threshold, and the reachability of both
# gate readouts is pinned by measured sim state in
# test_gate_guidance_reaches_the_player_the_gate_is_walling_in — not by a comment.

## Empty on purpose. main.gd:_top_center_priority's gate arm used to be allowlisted here as
## "correct unguarded"; it was not — "a closed gate is on screen" and "stall_ticks > 90" are
## mutually exclusive for anyone who walked into the clamp. It now consults camera_held(),
## so the scrape counts it as guarded and the escape hatch is closed: any future unguarded
## reader goes red immediately.
const STALL_READER_ALLOW: Array[String] = []


func test_every_stall_ticks_reader_is_guarded_by_camera_held() -> void:
	var lines := _view_src().split("\n")
	var readers := 0
	var guarded := 0
	var allowed := 0
	for i in lines.size():
		var ln: String = lines[i]
		if "sim.stall_ticks" not in ln or ln.strip_edges().begins_with("#"):
			continue
		readers += 1
		# The guard may sit on the same line or on the continued expression around it.
		var expr := ln
		var j := i
		while j + 1 < lines.size() and expr.strip_edges().ends_with("\\"):
			j += 1
			expr += lines[j]
		var tail: String = lines[j + 1] if j + 1 < lines.size() else ""
		if "camera_held()" in expr:
			guarded += 1
		elif STALL_READER_ALLOW.any(func(a: String) -> bool: return '"%s"' % a in tail):
			allowed += 1
		else:
			Runner.T.ok(false,
				"src/main.gd:%d reads sim.stall_ticks unguarded — the counter is stale inside a held camera, and this line acts on it: %s" \
					% [i + 1, ln.strip_edges()])
	Runner.T.ok(readers >= 3,
		"found only %d sim.stall_ticks readers in main.gd — the scrape is broken, not the view" % readers)
	Runner.T.eq(guarded + allowed, readers,
		"every sim.stall_ticks reader must either consult camera_held() or be allowlisted")


# --- 8. The CLASS ratchet: every tick-phased hazard has a tell ---------------

## Phase sites that deliberately do NOT telegraph, with the reason each is exempt.
## House-style allowlist (see run_tests.gd's ERROR_ALLOW / OPT_IN_SUITES): adding a
## row is a written decision, not a way to silence the gate.
## Keyed by the modulus's constant FAMILY (the token up to its first underscore); a
## bare numeric literal is its own family, and has to be justified by that number.
const PHASE_NO_TELEGRAPH := {
	"90": "posmod(tick_count, 90) in _step_spawner — a spawn CADENCE, not a state the player collides with",
	"BOSS": "BOSS_CYCLE_TICKS picks the gunship's cover rotation — already telegraphed by the boss's own strafe/mortar tells",
}


func test_every_tick_phased_hazard_telegraphs_before_it_bites() -> void:
	## The collapsing ford shipped as the only tick-phased hazard in the sim with no
	## tell: the lane block, the foundry vent and the mast all emit a `_warn` event and
	## the view handles all three. This scrapes the sim for EVERY phase site, keys each
	## by the CONSTANT FAMILY of its modulus, and demands a telegraph per family — so
	## the next phase-cycled hazard anyone adds is red the day it lands until it either
	## telegraphs or earns a written row in PHASE_NO_TELEGRAPH.
	##
	## Keyed on the family (FORD_CYCLE_TICKS -> "FORD") rather than the exact token
	## because the emit and the phase read legitimately live in different functions and
	## name different members of the same const family — and because a BARE LITERAL has
	## no family at all, which is how the ford escaped: `posmod(tick_count + band_idx *
	## 150, 600)`, four unnamed numbers, matched to nothing and warned about nothing.
	## `posmod(tick` (not `tick_count`) so wrapping the phase in a pure helper — which
	## is exactly what fixing this cycle did — cannot shrink the domain being scanned.
	var view := _view_src()
	# Comment lines are stripped first: a doc-comment QUOTING an old phase expression
	# is not a hazard, and counting it would invent a defect out of prose.
	var kept := PackedStringArray()
	for line in FileAccess.get_file_as_string("res://src/sim/sim_world.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	var src := "\n".join(kept)
	var funcs: Array[String] = []
	for chunk in src.split("\nfunc "):
		funcs.append(chunk)
	var site_re := RegEx.new()
	site_re.compile("posmod\\(tick[^,]*,\\s*([A-Za-z_0-9]+)\\s*\\)")
	var warn_re := RegEx.new()
	warn_re.compile('events\\.append\\(\\{"t":\\s*"([a-z_]+_warn)"')
	var families := {}
	for m in site_re.search_all(src):
		var tok := m.get_string(1)
		families[tok.split("_")[0]] = tok
	Runner.T.ok(families.size() >= 4,
		"the scrape found the sim's phase families (%d: %s)" % [families.size(), ", ".join(families.keys())])
	var untelegraphed: Array[String] = []
	var warn_names := {}
	for fam: String in families.keys():
		if PHASE_NO_TELEGRAPH.has(fam):
			continue
		var told := false
		for f: String in funcs:
			var w := warn_re.search(f)
			if w == null or not f.contains(fam + "_"):
				continue
			told = true
			warn_names[w.get_string(1)] = true
		if not told:
			untelegraphed.append("%s (modulus %s)" % [fam, families[fam]])
	Runner.T.eq(untelegraphed.size(), 0,
		"every tick-phased hazard warns before it bites (untelegraphed: %s)"
			% ", ".join(untelegraphed))
	# ...and a telegraph fired into the void is just as dead as no telegraph.
	Runner.T.ok(warn_names.size() >= 3, "found the sim's telegraph events (%s)" % ", ".join(warn_names.keys()))
	for wn: String in warn_names.keys():
		Runner.T.ok(view.contains('"%s"' % wn), 'src/main.gd handles the "%s" event the sim emits' % wn)


func test_the_collapsing_ford_emits_its_tell_before_the_crossing_goes() -> void:
	## The scrape above proves a warn EXISTS; this proves it lands FORD_WARN_TICKS
	## before the crossing actually stops being one, measured by running the sim.
	var sim := SimWorld.new(0xC0FFEE, 1)
	var band_idx := 3
	var band_y: int = -(band_idx * SimWorld.GATE_SPACING)
	sim.camera_top = band_y - 40 * Fixed.ONE
	sim.waters.clear()
	sim.waters.append({"y": band_y, "ford_x": 300 * Fixed.ONE})
	var warn_at := -1
	var closed_at := -1
	for t in SimWorld.FORD_CYCLE_TICKS:
		sim.tick_count = t
		sim.events.clear()
		sim._step_fords()
		for ev in sim.events:
			if ev["t"] == "ford_warn" and warn_at < 0:
				warn_at = t
			elif ev["t"] == "ford_closed" and closed_at < 0 and warn_at >= 0:
				closed_at = t
	Runner.T.ok(warn_at >= 0, "the ford emits a ford_warn somewhere in its cycle")
	Runner.T.eq(closed_at - warn_at, SimWorld.FORD_WARN_TICKS,
		"the tell lands exactly FORD_WARN_TICKS (%d) before the crossing washes out"
			% SimWorld.FORD_WARN_TICKS)
	# The tell is only useful if the crossing really is still dry when it fires, and
	# really is gone when the close event lands. Measured against _in_water, not a const.
	sim.tick_count = warn_at
	Runner.T.ok(not sim._in_water(300 * Fixed.ONE, band_y + 40 * Fixed.ONE),
		"at the warn tick the crossing is still dry — the tell is a lead, not a eulogy")
	sim.tick_count = closed_at
	Runner.T.ok(sim._in_water(300 * Fixed.ONE, band_y + 40 * Fixed.ONE),
		"at the close tick the crossing is water")


func test_the_victory_card_banked_row_reads_the_event_not_the_emptied_chest() -> void:
	## Hardening only — GREEN on HEAD, and it cannot fail there: the defect it guards
	## was fixed in 55a07d3. Its sibling above pins the bug's ABSENCE with a negative
	## grep, which would also pass if the row were simply deleted. This pins the
	## positive direction: the row exists, and it is fed by the event payload.
	var view := _view_src()
	Runner.T.ok(view.contains('_victory_banked'),
		"the victory card still HAS a war-chest row (a negative grep alone would not notice)")
	Runner.T.ok(view.contains('ev.get("banked"'),
		"_ev_victory reads the banked amount off the checksum-excluded victory event")
	Runner.T.ok(view.contains('WAR CHEST BANKED  → +%s" % [_victory_banked,'),
		"the drawn row interpolates the event payload, not the live (already-zeroed) sim.war_chest")


# --- Counter-verb honesty: a card may only name a verb the sim answers to ------
#
# The riot shield's first-sighting card said "FLANK OR GRENADE" and the ENDLESS
# roster page said "Flank it or grenade it". Half of that is real: `_explode` has
# no shield exemption. The other half never was — `_shield_blocks` recomputes the
# facing as "toward the nearest player" EVERY tick (sim_world.gd:3734), so the
# blocking arc rotates with you and there is no flank to take. Measured live over
# 1,512 strafe/orbit trials: 46 kills, ALL of them at 9.05-10.30 px closest
# approach, i.e. inside the ENEMY_TOUCH_RADIUS contact ring — the shield was
# walked into, not flanked.
#
# The class is "a teaching card names a counter-verb the sim refuses", so the set
# under test is scraped from source (both card surfaces), not typed out here, and
# each promised verb is RUN against the sim it describes.

const FLANK_STANDOFF := 40.0   # 4x ENEMY_TOUCH_RADIUS: a kill here cannot be muzzle-stuffing
const FLANK_TICKS := 300       # 7x the ~40-tick close of a 1px/tick shield from 40px
## A TAP lob flies a FIXED 96 px (GRENADE_SPEED 3 px/tick x the 32-tick fuse:
## 2*GRENADE_ZVEL/GRENADE_GRAV), so the standoff a throw connects from depends on
## how fast the sim walks the target in (0 px/tick rooted, 1.0 shield, 1.6 fodder).
## The probe therefore sweeps the engagement band instead of pinning one radius —
## the card promises the VERB works, not that it works at one magic distance.
const GRENADE_DISTS := [80.0, 100.0, 120.0, 140.0, 160.0]
const GRENADE_TICKS := 120     # 3.7x the 32-tick fuse

## sprite key on an ENDLESS roster row -> the sim `kind` that row teaches. Asserted
## exhaustive against the live roster below, so a row added tomorrow fails loudly
## instead of being silently unmapped (and its verbs unchecked).
const ROSTER_KIND := {
	"m_soldier2": "grenadier", "enemy_sniper": "sniper", "ghillie": "ghillie",
	"sapper": "sapper", "m_bombsuit": "shield", "m_drone": "drone",
	"m_technical": "technical",
}


func _clean_arena() -> SimWorld:
	## An endless world with every bullet-stopper and every rival threat removed,
	## so the only thing that can save the archetype under test is its own rules.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	for _i in 30:
		sim.step(_idle())
	for arr in [sim.enemies, sim.bullets, sim.enemy_bullets, sim.rocks, sim.sandbags,
			sim.bunkers, sim.mines, sim.barrels, sim.tanks, sim.grenades]:
		arr.clear()
	return sim


func _spawn_kind(sim: SimWorld, kind: String, x: int, y: int) -> Dictionary:
	## Through the sim's OWN spawners, so the probe can't invent a soft variant.
	match kind:
		"mg_nest": sim._spawn_mg_nest(x, y)
		"broadcast": sim._spawn_broadcast(x, y)
		"fodder": sim._spawn_enemy(x, y, false)
		_: sim._spawn_special(x, y, kind)
	return sim.enemies[sim.enemies.size() - 1]


func _verb_trial(kind: String, bearing: float, dist: float, strafe: int, use_grenade: bool) -> bool:
	## One live trial. Real SimInput, real trigger, real bullets. Returns whether
	## the archetype DIED. The player is held un-killable via hurt_iframes (never
	## moved or respawned) so the trial measures the VERB, not who dies first.
	var sim := _clean_arena()
	var ex := 320 * Fixed.ONE
	var ey: int = sim.camera_top + 140 * Fixed.ONE
	var e := _spawn_kind(sim, kind, ex, ey)
	var p: Dictionary = sim.players[0]
	p["x"] = ex + int(cos(bearing) * dist * Fixed.ONE)
	p["y"] = ey + int(sin(bearing) * dist * Fixed.ONE)
	p["alive"] = true
	p["in_tank"] = -1   # on foot (this field is a TANK INDEX, not a flag)
	var ticks := GRENADE_TICKS if use_grenade else FLANK_TICKS
	for _t in range(ticks):
		if not e["alive"]:
			return true
		# Reinforcements from the endless spawner would eat rounds meant for the
		# archetype under test; the arena stays a duel.
		for i in range(sim.enemies.size() - 1, -1, -1):
			if not is_same(sim.enemies[i], e):
				sim.enemies.remove_at(i)
		p["hurt_iframes"] = 60
		p["mg_ammo"] = 9999
		p["grenade_ammo"] = 12
		var dx := float(e["x"] - p["x"])
		var dy := float(e["y"] - p["y"])
		var d := sqrt(dx * dx + dy * dy)
		if d < 0.001:
			break
		var inp := SimInput.new()
		inp.aim_x = int(round(dx / d * 256.0))
		inp.aim_y = int(round(dy / d * 256.0))
		# TAP, never hold: holding the button airbursts the charge at the arc's
		# apex (sim_world.gd:2637) at ~half range. A tap is the full 32-tick lob.
		if use_grenade:
			inp.grenade = _t == 0
		else:
			inp.fire = true
			# full-stick strafe perpendicular to the line of sight
			inp.move_x = int(round(-dy / d * 256.0)) * strafe
			inp.move_y = int(round(dx / d * 256.0)) * strafe
		var batch: Array[SimInput] = [inp]
		sim.step(batch)
	return not e["alive"]


func _verb_kills(kind: String, use_grenade: bool) -> Array:
	## [honoured, trials] over 8 bearings. Shooting: both strafe directions must
	## kill. Explosives: the bearing counts once ANY standoff in the band kills.
	var honoured := 0
	var trials := 0
	for step_deg in range(0, 360, 45):
		var ang := deg_to_rad(float(step_deg))
		if use_grenade:
			trials += 1
			for dist in GRENADE_DISTS:
				if _verb_trial(kind, ang, dist, 1, true):
					honoured += 1
					break
		else:
			for sd in [-1, 1]:
				trials += 1
				if _verb_trial(kind, ang, FLANK_STANDOFF, sd, false):
					honoured += 1
	return [honoured, trials]


func _promised_verbs() -> Dictionary:
	## kind -> {"flank": [where...], "boom": [where...]} scraped from BOTH card
	## surfaces in source: the first-sighting teaching cards and the ENDLESS
	## roster page. Copy added tomorrow is audited the day it lands.
	var cards := {}   # kind -> Array[String] of the strings shown for that kind
	for kind in Main._KIND_TEACH:
		cards[kind] = [String(Main._KIND_TEACH[kind])]
	var m = TML._CaptureMenu.new()
	var roster: Array = m._endless_threats()
	var mapped := 0
	for row in roster:
		var spr := String(row[0])
		if ROSTER_KIND.has(spr):
			mapped += 1
			var k: String = ROSTER_KIND[spr]
			if not cards.has(k):
				cards[k] = []
			cards[k].append(String(row[2]))
	m.free()
	Runner.T.eq(mapped, roster.size(),
		"every ENDLESS roster row maps to a sim kind (%d/%d) — an unmapped row is an unchecked promise"
			% [mapped, roster.size()])
	var out := {}
	for k in cards:
		var flank: Array = []
		var boom: Array = []
		for s in cards[k]:
			var up := String(s).to_upper()
			if up.contains("FLANK"):
				flank.append(s)
			# Counter-verb PHRASES, not bare nouns: "lobs a telegraphed blast" is
			# what the grenadier does TO you, not an instruction to the player.
			if up.contains("GRENADE IT") or up.contains("OR GRENADE") \
					or up.contains("BLOW IT OPEN") or up.contains("BLAST IT") \
					or up.contains("WITH A BLAST"):
				boom.append(s)
		if not flank.is_empty() or not boom.is_empty():
			out[k] = {"flank": flank, "boom": boom}
	return out


func test_every_counter_verb_a_card_promises_is_one_the_sim_honours() -> void:
	# Positive controls FIRST: if the harness stopped firing, the verb sets below
	# would pass vacuously. Plain fodder must fall to both.
	var cf := _verb_kills("fodder", false)
	Runner.T.eq(cf[0], cf[1],
		"CONTROL: plain fodder dies to the %.0fpx strafe probe on every bearing (%d/%d)"
			% [FLANK_STANDOFF, cf[0], cf[1]])
	var cg := _verb_kills("fodder", true)
	Runner.T.eq(cg[0], cg[1],
		"CONTROL: plain fodder dies to a lobbed grenade on every bearing (%d/%d)"
			% [cg[0], cg[1]])

	var promised := _promised_verbs()
	Runner.T.ok(not promised.is_empty(),
		"the card scrape found counter-verb promises at all (%d kinds)" % promised.size())
	for kind in promised:
		var pr: Dictionary = promised[kind]
		if not pr["flank"].is_empty():
			var r := _verb_kills(kind, false)
			Runner.T.eq(r[0], r[1],
				"'%s' promises a FLANK — strafing it at %.0fpx kills it (%d/%d bearings): %s"
					% [kind, FLANK_STANDOFF, r[0], r[1], String(pr["flank"][0])])
		if not pr["boom"].is_empty():
			var r2 := _verb_kills(kind, true)
			Runner.T.eq(r2[0], r2[1],
				"'%s' promises an explosive — a lobbed grenade kills it (%d/%d bearings): %s"
					% [kind, r2[0], r2[1], String(pr["boom"][0])])


# --- The RANK card: a scale that spends its whole range ------------------------
#
# `_run_rank()` graded every mode off ONE hand-tuned table topping out at S >= 300
# mvp, and measured runs land at 758-1190 (campaign) — ~75% of the real range sits
# above the top letter, so finishing was an automatic S and the letter carried no
# information. The TITLE line one row below had the same defect (ONE-MAN ARMY at
# streak >= 20 vs measured bests of 20-92), and the knockdown ledger the card
# PRINTS two rows further down (`_continue_ledger_rows`) was not a term in either.
#
# This pins the INVARIANTS, not the constants: retuning the bands after a scoring
# change must not require editing this test — re-running tools/probe_rank.gd and
# repasting MEASURED_RUNS must.

## Real driven runs, pasted verbatim from `tools/probe_rank.gd` (5 seeds x 4 modes,
## god-mode ceiling pass + real-cost pass, 40,000-tick cap = 3.0x the longest
## measured campaign completion of 13,364 ticks). `downs` is the `player_down`
## count — a BOT'S knockdown distribution, which is far heavier than a competent
## player's; that makes it the pessimistic end of the cost term, not the typical one.
const MEASURED_RUNS := [
	{"mode": "campaign", "kills": 269, "streak": 46, "gates": 6, "wave": 0, "victory": true, "downs": 46},   # seed 1 god
	{"mode": "campaign", "kills": 328, "streak": 20, "gates": 5, "wave": 0, "victory": false, "downs": 52},   # seed 1
	{"mode": "campaign", "kills": 276, "streak": 41, "gates": 6, "wave": 0, "victory": true, "downs": 38},   # seed 2 god
	{"mode": "campaign", "kills": 234, "streak": 38, "gates": 5, "wave": 0, "victory": false, "downs": 31},   # seed 2
	{"mode": "campaign", "kills": 264, "streak": 67, "gates": 6, "wave": 0, "victory": true, "downs": 29},   # seed 3 god
	{"mode": "campaign", "kills": 245, "streak": 59, "gates": 5, "wave": 0, "victory": false, "downs": 26},   # seed 3
	{"mode": "campaign", "kills": 242, "streak": 45, "gates": 6, "wave": 0, "victory": true, "downs": 33},   # seed 4 god
	{"mode": "campaign", "kills": 315, "streak": 92, "gates": 5, "wave": 0, "victory": false, "downs": 27},   # seed 4
	{"mode": "campaign", "kills": 317, "streak": 58, "gates": 6, "wave": 0, "victory": true, "downs": 39},   # seed 5 god
	{"mode": "campaign", "kills": 348, "streak": 35, "gates": 5, "wave": 0, "victory": false, "downs": 47},   # seed 5
	{"mode": "endless", "kills": 420, "streak": 26, "gates": 0, "wave": 19, "victory": false, "downs": 48},   # seed 1 god
	{"mode": "endless", "kills": 29, "streak": 6, "gates": 0, "wave": 5, "victory": false, "downs": 5},   # seed 1
	{"mode": "endless", "kills": 183, "streak": 24, "gates": 0, "wave": 12, "victory": false, "downs": 24},   # seed 2 god
	{"mode": "endless", "kills": 40, "streak": 12, "gates": 0, "wave": 5, "victory": false, "downs": 6},   # seed 2
	{"mode": "endless", "kills": 276, "streak": 27, "gates": 0, "wave": 15, "victory": false, "downs": 45},   # seed 3 god
	{"mode": "endless", "kills": 28, "streak": 6, "gates": 0, "wave": 5, "victory": false, "downs": 5},   # seed 3
	{"mode": "endless", "kills": 41, "streak": 10, "gates": 0, "wave": 5, "victory": false, "downs": 12},   # seed 4 god
	{"mode": "endless", "kills": 37, "streak": 7, "gates": 0, "wave": 5, "victory": false, "downs": 5},   # seed 4
	{"mode": "endless", "kills": 132, "streak": 17, "gates": 0, "wave": 10, "victory": false, "downs": 14},   # seed 5 god
	{"mode": "endless", "kills": 32, "streak": 8, "gates": 0, "wave": 5, "victory": false, "downs": 5},   # seed 5
	{"mode": "boss_rush", "kills": 5, "streak": 1, "gates": 4, "wave": 0, "victory": true, "downs": 14},   # seed 1 god
	{"mode": "boss_rush", "kills": 3, "streak": 0, "gates": 3, "wave": 0, "victory": false, "downs": 17},   # seed 1
	{"mode": "boss_rush", "kills": 5, "streak": 2, "gates": 4, "wave": 0, "victory": true, "downs": 16},   # seed 2 god
	{"mode": "boss_rush", "kills": 3, "streak": 0, "gates": 3, "wave": 0, "victory": false, "downs": 15},   # seed 2
	{"mode": "boss_rush", "kills": 5, "streak": 2, "gates": 4, "wave": 0, "victory": true, "downs": 12},   # seed 3 god
	{"mode": "boss_rush", "kills": 3, "streak": 0, "gates": 3, "wave": 0, "victory": false, "downs": 17},   # seed 3
	{"mode": "boss_rush", "kills": 5, "streak": 2, "gates": 4, "wave": 0, "victory": true, "downs": 11},   # seed 4 god
	{"mode": "boss_rush", "kills": 3, "streak": 0, "gates": 3, "wave": 0, "victory": false, "downs": 17},   # seed 4
	{"mode": "boss_rush", "kills": 5, "streak": 2, "gates": 4, "wave": 0, "victory": true, "downs": 11},   # seed 5 god
	{"mode": "boss_rush", "kills": 3, "streak": 0, "gates": 3, "wave": 0, "victory": false, "downs": 17},   # seed 5
	{"mode": "arcade", "kills": 280, "streak": 46, "gates": 6, "wave": 0, "victory": true, "downs": 44},   # seed 1 god
	{"mode": "arcade", "kills": 315, "streak": 62, "gates": 5, "wave": 0, "victory": false, "downs": 40},   # seed 1
	{"mode": "arcade", "kills": 273, "streak": 41, "gates": 6, "wave": 0, "victory": true, "downs": 38},   # seed 2 god
	{"mode": "arcade", "kills": 235, "streak": 38, "gates": 5, "wave": 0, "victory": false, "downs": 31},   # seed 2
	{"mode": "arcade", "kills": 372, "streak": 75, "gates": 6, "wave": 0, "victory": true, "downs": 41},   # seed 3 god
	{"mode": "arcade", "kills": 253, "streak": 49, "gates": 5, "wave": 0, "victory": false, "downs": 26},   # seed 3
	{"mode": "arcade", "kills": 265, "streak": 39, "gates": 6, "wave": 0, "victory": true, "downs": 30},   # seed 4 god
	{"mode": "arcade", "kills": 310, "streak": 29, "gates": 5, "wave": 0, "victory": false, "downs": 37},   # seed 4
	{"mode": "arcade", "kills": 305, "streak": 42, "gates": 6, "wave": 0, "victory": true, "downs": 36},   # seed 5 god
	{"mode": "arcade", "kills": 298, "streak": 24, "gates": 5, "wave": 0, "victory": false, "downs": 41},   # seed 5
]

## The structural floor every mode can produce: spawn, die, nothing opened. Not from
## the probe (the bot never fails that hard) — it is the zero end of the scale, and a
## grade scale that cannot tell it apart from a finished run is not a scale.
const FLOOR_MODES := ["campaign", "endless", "boss_rush", "arcade"]


func _rank_of(row: Dictionary, downs: int) -> Dictionary:
	## Grade one measured profile through the SHIPPED grader, on a real SimWorld of
	## that mode with its gates/wave/victory posed. No formula is restated here.
	var m = Main.new()
	var sim := SimWorld.new(0xC0FFEE, 1, String(row["mode"]))
	sim.gates.clear()
	for _g in int(row["gates"]):
		sim.gates.append({"open": true})
	sim.wave = int(row["wave"])
	sim.victory = bool(row["victory"])
	m.sim = sim
	m._run_kills = int(row["kills"])
	m._run_best_streak = int(row["streak"])
	m._run_knockdowns = downs
	var rr: Dictionary = m._run_rank()
	m.free()
	return rr


func _rows_for(mode: String) -> Array:
	var out: Array = []
	for r in MEASURED_RUNS:
		if String(r["mode"]) == mode:
			out.append(r)
	return out


## Ordering proxy ONLY — used to pick a middle row out of a mode's sample. It is
## deliberately NOT the graded formula (restating that here is the exact bug this
## suite exists to catch); every assertion below reads the shipped grader's output.
func _proxy(row: Dictionary) -> int:
	return int(row["kills"]) * 2 + int(row["streak"]) * 5 + int(row["gates"]) * 20 \
		+ int(row["wave"]) * 12


func _median_row(rows: Array) -> Dictionary:
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return _proxy(a) < _proxy(b))
	return sorted_rows[sorted_rows.size() / 2]


func test_the_rank_scale_spends_its_whole_range_on_every_mode() -> void:
	var consts: Dictionary = load("res://src/main.gd").get_script_constant_map()
	Runner.T.ok(consts.has("RANK_BANDS"),
		"the grade/title thresholds live in a named per-mode table (main.RANK_BANDS), not inline literals")
	if not consts.has("RANK_BANDS"):
		return
	var bands: Dictionary = consts["RANK_BANDS"]

	# (6) Every mode the game can CONSTRUCT has a row — scraped from the one place
	# main.gd picks a mode string, so a fifth mode fails here the day it lands.
	var pick := ""
	for line in _view_src().split("\n"):
		if line.contains("var _mode_str :="):
			pick = line
	Runner.T.ok(pick != "", "found main.gd's mode-string picker")
	var re := RegEx.create_from_string('"([a-z_]+)"')
	var seen := {}
	for mm in re.search_all(pick):
		seen[mm.get_string(1)] = true
	# the else-branch mode sits on the wrapped continuation line
	seen["campaign"] = true
	for mode in seen:
		Runner.T.ok(bands.has(mode), "RANK_BANDS covers constructible mode '%s'" % mode)
	for mode in bands:
		var mv: Array = bands[mode]["mvp"]
		Runner.T.eq(mv.size(), 4, "%s has 4 grade thresholds [S,A,B,C]" % mode)
		for i in mv.size() - 1:
			Runner.T.ok(int(mv[i]) > int(mv[i + 1]),
				"%s thresholds strictly decrease (%d > %d)" % [mode, int(mv[i]), int(mv[i + 1])])

	for mode in FLOOR_MODES:
		var rows := _rows_for(mode)
		Runner.T.ok(rows.size() >= 5, "%s has a measured sample (%d rows)" % [mode, rows.size()])
		if rows.is_empty():
			continue
		var s_thresh := int(bands[mode]["mvp"][0])

		# (1) COST: the ledger the card already prints is a term in the grade.
		var med := _median_row(rows)
		var clean: Dictionary = _rank_of(med, 0)
		var bloody: Dictionary = _rank_of(med, 25)
		Runner.T.ok(clean["grade"] != bloody["grade"],
			"%s: the median run graded clean (%s) and after 25 knockdowns (%s) are different letters"
				% [mode, clean["grade"], bloody["grade"]])

		# (2) HEADROOM: the top letter is not buried under the achievable range.
		var top := 0
		var grades := {}
		var titles := {}
		for r in rows:
			var rr := _rank_of(r, int(r["downs"]))
			top = maxi(top, int(rr["mvp"]))
			grades[rr["grade"]] = true
			titles[rr["title"]] = true
		var floor_rank := _rank_of({"mode": mode, "kills": 0, "streak": 0, "gates": 0,
			"wave": 0, "victory": false, "downs": 0}, 0)
		grades[floor_rank["grade"]] = true
		titles[floor_rank["title"]] = true
		Runner.T.ok(top <= int(round(1.6 * float(s_thresh))),
			"%s: best measured run (%d mvp) is within 1.6x the S band (%d) — the scale reaches the play"
				% [mode, top, s_thresh])
		Runner.T.eq(floor_rank["grade"], "D",
			"%s: a spawn-and-die run grades D (got %s)" % [mode, floor_rank["grade"]])

		# (3) A FINISH IS NOT A FREE S.
		var wins: Array = []
		for r in rows:
			if bool(r["victory"]):
				wins.append(r)
		if wins.is_empty():
			# endless has no natural end; its rows are wave-N snapshots, not completions.
			Runner.T.ok(true, "%s has no measured completion — 'a finish is not a free S' does not apply" % mode)
		else:
			var mw := _median_row(wins)
			var wr := _rank_of(mw, int(mw["downs"]))
			Runner.T.ok(wr["grade"] != "S",
				"%s: the median measured COMPLETION grades %s, not an automatic S" % [mode, wr["grade"]])

		# (4)(5) THE SCALE IS USED — letters and titles both.
		Runner.T.ok(grades.size() >= 3,
			"%s: the measured profiles spread over >=3 grades (got %d: %s)"
				% [mode, grades.size(), ", ".join(PackedStringArray(grades.keys()))])
		Runner.T.ok(titles.size() >= 3,
			"%s: …and >=3 titles (got %d: %s)"
				% [mode, titles.size(), ", ".join(PackedStringArray(titles.keys()))])


# --- 9. The debrief's progress row must move with the run it describes -------

func test_endless_debrief_names_the_wave_not_a_frozen_campaign_sector() -> void:
	## Ground truth first: endless has no gates and a pinned camera, so the campaign
	## progress string is CONSTANT — "SECTOR 1/6   36m PUSHED" on every endless death.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var top0 := sim.camera_top
	for i in 300:
		sim.step(_idle())
	Runner.T.eq(sim.gates.size(), 0, "endless never spawns a gate — `opened` is pinned at 0")
	Runner.T.eq(sim.camera_top, top0, "endless never advances the camera")
	Runner.T.eq(-Fixed.to_int(sim.camera_top) / 10, 36, "…so the campaign row's metres are the constant 36")
	Runner.T.ok(sim.wave >= 1, "…while WAVE is the axis that actually moves")
	var ms: Script = load("res://src/main.gd")
	var has_row := false
	for meth in ms.get_script_method_list():
		if String(meth["name"]) == "debrief_progress_row":
			has_row = true
	Runner.T.ok(has_row, "Main.debrief_progress_row() is the debrief's one progress-row source")
	if has_row:
		var txt := String(ms.debrief_progress_row("endless", 0, 36, 7).get("text", ""))
		Runner.T.ok(not txt.contains("SECTOR"), "the endless debrief prints no campaign sector (got %s)" % txt)
		Runner.T.ok(not txt.contains("PUSHED"), "…nor metres a camera that never moved (got %s)" % txt)
		Runner.T.ok(txt.contains("7"), "…it names the wave reached (got %s)" % txt)
		# The load-bearing one: the row must MOVE with the run.
		Runner.T.ok(ms.debrief_progress_row("endless", 0, 36, 4) != ms.debrief_progress_row("endless", 0, 36, 19),
			"two endless runs ending on different waves get different rows")
		# The other three modes are unchanged.
		Runner.T.ok(String(ms.debrief_progress_row("campaign", 2, 400, 0).get("text", "")) == "SECTOR 3/6   400m PUSHED",
			"campaign keeps its sector+distance row")
		Runner.T.ok(String(ms.debrief_progress_row("arcade", 2, 400, 0).get("text", "")).begins_with("SECTOR"),
			"arcade has real gates and a real camera — same row as campaign")
		Runner.T.ok(String(ms.debrief_progress_row("boss_rush", 2, 0, 0).get("text", "")) == "GUNSHIPS DOWNED  2/3",
			"boss_rush keeps its gunship tally")
	Runner.T.eq(_view_src().count("debrief_progress_row("), 2,
		"the debrief builds its progress row THROUGH the helper (1 def + 1 call) — the helper can't drift into decoration")


# --- 10. A cue's timbre comes from the ground it is raised on ----------------

func test_the_surface_cue_is_picked_from_the_ground_it_rises_out_of() -> void:
	## The sim raises ONE "frogman_surface" event from five sites and three of them are on
	## DRY LAND (beached-diver re-telegraph, ghillie reveal, endless anti-stall reveal).
	## The view played the water splash for all five, so a sniper crawling out of grass in a
	## waterless endless arena made a river noise on every single reveal.
	# NOTE: probe through a Script-typed var, never `Main._surface_cue(...)` — a direct
	# static call on the preloaded class is resolved at PARSE time, so on a tree without
	# the helper the whole suite fails to load instead of reporting one red assertion.
	var ms: Script = load("res://src/main.gd")
	var names := PackedStringArray()
	for m in ms.get_script_method_list():
		names.append(m["name"])
	Runner.T.ok(names.has("_surface_cue"),
		"the view picks the surface timbre from TERRAIN, not from the event name")
	if not names.has("_surface_cue"):
		return   # guard: calling a missing static aborts the method SILENTLY (see CLAUDE.md)
	# MEASURED, not asserted from a constant: run a real ghillie reveal in endless, where the
	# world streamer never runs and `waters` is therefore empty.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim.enemies.clear()
	var p: Dictionary = sim.players[0]
	sim._spawn_special(p["x"] + 80 * Fixed.ONE, p["y"], "ghillie")
	var dry := {}
	for i in 20:
		sim.step(_idle())
		for ev in sim.events:
			if ev["t"] == "frogman_surface":
				dry = ev.duplicate()
		if not dry.is_empty():
			break
	Runner.T.ok(not dry.is_empty(), "the ghillie reveal raises the surface cue")
	Runner.T.ok(not sim._in_water(dry["x"], dry["y"]), "and it comes from DRY GROUND")
	var dry_voice: String = ms._surface_cue(sim._in_water(dry["x"], dry["y"]))[0]
	var wet_voice: String = ms._surface_cue(true)[0]
	Runner.T.ok(dry_voice != wet_voice,
		"a surface raised on land does not play the water voice (played '%s')" % dry_voice)
	Runner.T.eq(wet_voice, Main._EVENT_SOUND["frogman_surface"][0],
		"a real diver still breaks water on the splash the table names")
	var sfx := Sfx.new()
	sfx._synth_all()
	Runner.T.ok(sfx._sounds.has(dry_voice),
		"the dry surface voice '%s' is a synthesized voice, not dead air" % dry_voice)
	sfx.free()


# --- 11. Gate guidance must reach the player the gate is walling in ---------

func test_gate_guidance_reaches_the_player_the_gate_is_walling_in() -> void:
	## Both gate readouts existed only to explain the closed-gate clamp, and both were gated
	## behind sim.stall_ticks — which SimWorld._step_observer freezes for exactly the ticks
	## the clamp is binding. A player who walks north into the wall arrives at stall_ticks 0
	## and it never moves, so the two lines were dead in the one state they were written for.
	## Drive the real sim there with the same push-north bot test_observer.gd uses.
	var sim := SimWorld.new(3, 1, "campaign")
	sim.god_mode = true
	var inp := SimInput.new()
	inp.move_y = -256
	inp.aim_y = -256
	var held_at_gate := false
	for t in 6000:
		inp.fire = (t % 8) != 0
		sim.step([inp])
		if not sim.camera_held():
			continue
		var on_screen := false
		for g in sim.gates:
			if not g["open"] and not g.get("final", false) \
					and g["y"] >= sim.camera_top and g["y"] <= sim.camera_top + SimWorld.VIEW_H:
				on_screen = true
				break
		if not on_screen:
			continue
		held_at_gate = true
		break
	Runner.T.ok(held_at_gate,
		"never reached a held camera at a closed non-final gate in 6000 ticks — this test ran on nothing")
	var h := HudIcons.new()
	Runner.T.eq(h._telegraph_spec(sim)["kind"], "gate",
		"the camera is clamped by a closed gate and the HUD telegraph says \"%s\" (stall_ticks=%d) — CLEAR THE GATE is unreachable for anyone who pushed north into the wall" \
			% [str(h._telegraph_spec(sim)["kind"]), sim.stall_ticks])
	h.free()
	var m = load("res://src/main.gd").new()
	m.sim = sim
	Runner.T.eq(m._top_center_priority(), "boss",
		"the camera is clamped by a closed gate and the top band arbitrates to \"%s\" — the objective line (GRENADE THE BUNKERS / DESTROY THE GUNSHIP TO ADVANCE) never prints" \
			% m._top_center_priority())
	Runner.T.ok(not String(m._band_top_text("boss").get("text", "")).is_empty(),
		"the winning band message resolves to a real string")
	m.free()


# --- 12. One silhouette, one rule: cover is never also walk-through decor ----

func test_no_walkthrough_prop_wears_the_ambient_cover_silhouette() -> void:
	## _draw_rocks() picks the kind-0 (SOLID, ROCK_KIND_EXT[0] 16x12 half-extent) sprite
	## from an inline 3-name list; _draw_terrain() scatters the walk-through dead canopy
	## from _CACTUS_DEAD. A name in BOTH teaches one silhouette two rules.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var word := RegEx.create_from_string('"([a-z0-9_]+)"')
	var cov_m := RegEx.create_from_string('var rtex: String = \\[([^\\]]+)\\]\\[rh3').search(src)
	Runner.T.ok(cov_m != null, "_draw_rocks still picks its kind-0 sprite from an inline list")
	var cover := {}
	for q in word.search_all(cov_m.get_string(1)):
		cover[q.get_string(1)] = true
	Runner.T.eq(cover.size(), 3, "kind-0 cover still draws 3 silhouettes")
	var pool_m := RegEx.create_from_string('const _CACTUS_DEAD :?= \\[([^\\]]+)\\]').search(src)
	Runner.T.ok(pool_m != null, "the dead-canopy decor pool still exists")
	var pool: Array = []
	for q in word.search_all(pool_m.get_string(1)):
		pool.append(q.get_string(1))
	Runner.T.ok(pool.size() >= 2, "the dead canopy keeps at least two variants")
	for nm in pool:
		Runner.T.ok(Art.TEX.has(nm), "dead-canopy pool entry '%s' resolves to a texture" % nm)
		Runner.T.ok(not cover.has(nm),
			"'%s' is scattered as walk-through decor AND drawn as kind-0 SOLID cover" % nm)
	# The naive fix (shrink the pool, leave the indexers) is an out-of-range crash
	# in a draw path headless tests never execute. Pin every literal modulus.
	for q in RegEx.create_from_string('_CACTUS_DEAD\\[[a-z0-9_]+ % ([0-9]+)\\]').search_all(src):
		Runner.T.eq(int(q.get_string(1)), pool.size(),
			"_CACTUS_DEAD indexed %% %d but the pool holds %d" % [int(q.get_string(1)), pool.size()])


# --- The teaching layer: a cue must name the rule the sim actually ran ---

func test_the_blind_shell_cue_names_the_cover_that_actually_hid_you() -> void:
	## `_concealed()` is smoke OR grass OR trench, but the ONE once-per-profile
	## concealment teach hard-coded "SMOKE". Grass is a streamed cover tier and
	## trenches are authored from band 2, so most players burn the game's only
	## concealment lesson on a noun the sim never used for them.
	var sim := SimWorld.new(21, 1)
	var p: Dictionary = sim.players[0]
	p["smoke_ticks"] = 100
	sim.events.clear()
	sim._blind_scatter(p)
	Runner.T.eq(str(sim.events[0].get("src", "")), "smoke",
		"a smoked target's blind shell is tagged smoke")

	var sim2 := SimWorld.new(21, 1)
	var p2: Dictionary = sim2.players[0]
	p2["smoke_ticks"] = 0
	sim2.rocks.append({"x": p2["x"], "y": p2["y"], "kind": 1})
	sim2.events.clear()
	sim2._blind_scatter(p2)
	Runner.T.eq(str(sim2.events[0].get("src", "")), "grass",
		"a grass-hidden target's blind shell is tagged grass")

	# The VIEW's one-and-only concealment teach, driven through the real
	# _consume_events — not a re-implementation of the match arm.
	var stub := Main.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN   # _hint early-returns in Mode.TITLE
	stub.sim = sim2
	stub.sim.events = [{"t": "blind_shell", "x": 0, "y": 0, "src": "grass"}]
	stub._consume_events()
	Runner.T.eq(stub._hint_queue.size(), 1, "the grass blind-shell queues exactly one teach")
	var line: String = stub._hint_queue[0]
	Runner.T.ok(not line.contains("SMOKE"),
		"the concealment teach fired by GRASS must not tell the player it was smoke (got '%s')" % line)
	Runner.T.ok(line.contains("GRASS"), "it names the cover that actually hid them (got '%s')" % line)
	stub.free()


func test_the_specialist_roster_is_not_filed_under_a_mode_it_outlives() -> void:
	## Seven of the nine CAMPAIGN special archetypes are the HOW TO PLAY roster —
	## filed under a tab labelled ENDLESS, headed "ENDLESS WAR". They start
	## fielding in campaign sector 2. And the ninth (drone) has no teaching card
	## at all, so its first sighting is silent.
	var campaign_kinds := {}
	for sector in SimWorld.SECTOR_SPECIALS:
		for k in sector:
			campaign_kinds[k] = true
	Runner.T.eq(campaign_kinds.size(), 9,
		"SECTOR_SPECIALS fields 9 distinct archetypes across the campaign")

	var m = TML._CaptureMenu.new()
	var roster: Array = m._endless_threats()
	var in_campaign := 0
	for row in roster:
		var spr := String(row[0])
		if ROSTER_KIND.has(spr) and campaign_kinds.has(ROSTER_KIND[spr]):
			in_campaign += 1
	Runner.T.eq(in_campaign, roster.size(),
		"every row on that roster is CAMPAIGN content (%d/%d)" % [in_campaign, roster.size()])

	# Measured ink, not a source constant: nothing that screen draws may call the
	# roster a mode. (The MODES tab's real "ENDLESS WAR" row is out of scope.)
	m.main = TML._StubMain.new()
	m.size = Vector2(Menu.CANVAS_WIDTH, 360.0)
	m._open_t = 1.0
	for ep in m._endless_pages():
		m.mode = Menu.Mode.HOWTO
		m._howto_page = Menu.HOWTO_ENDLESS_TAB
		m._howto_endless_page = ep
		m.ops.clear()
		var prev = Art.text_capture
		Art.text_capture = m.ops
		m._draw_howto()
		Art.text_capture = prev
		for op in m.ops:
			if op["k"] == "text":
				Runner.T.ok(not String(op["id"]).to_upper().contains("ENDLESS"),
					"the specialist roster page draws '%s' — it is not an ENDLESS-only roster" % op["id"])
	var stub2 = m.main
	m.free()
	stub2.free()

	# Standing ratchet: a kind added to SECTOR_SPECIALS without a card goes red.
	for kind in campaign_kinds:
		Runner.T.ok(Main._KIND_TEACH.has(kind),
			"'%s' is fielded by the campaign but has no first-sighting teaching card" % kind)


func test_every_view_that_draws_the_broke_timer_asks_whether_the_rally_is_free() -> void:
	## In solo ENDLESS the broke timer is not an inbound rescue — at zero it
	## latches the WIPE. Three view sites captioned it as a free rally anyway.
	## One sim predicate, and every renderer must consult it.
	for path in ["res://src/view/hud.gd", "res://src/main.gd"]:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var fn := ""
		var bodies := {}
		for ln in lines:
			var s := String(ln).strip_edges()
			if s.begins_with("func ") or s.begins_with("static func "):
				fn = String(ln).substr(String(ln).find("func ") + 5).split("(")[0]
			bodies[fn] = String(bodies.get(fn, "")) + String(ln) + "\n"
		var hits := 0
		for k in bodies:
			var body: String = bodies[k]
			if body.contains('"broke_timer"'):
				hits += 1
				Runner.T.ok(body.contains("rally_is_free"),
					"%s::%s() renders broke_timer without asking rally_is_free()" % [path, k])
		Runner.T.ok(hits >= 1, "the broke_timer view scrape found nothing in %s — parser is broken" % path)

	# The rules page must name the mode where that clock is the run ending.
	var m = TML._CaptureMenu.new()
	m.main = TML._StubMain.new()
	m.size = Vector2(Menu.CANVAS_WIDTH, 360.0)
	m._open_t = 1.0
	m.mode = Menu.Mode.HOWTO
	m._howto_page = 1        # WAR CHEST
	m.ops.clear()
	var prev = Art.text_capture
	Art.text_capture = m.ops
	m._draw_howto()
	Art.text_capture = prev
	var page := ""
	for op in m.ops:
		# Skip the tab strip _draw_howto stamps on EVERY page — a tab literally
		# named "ENDLESS" would otherwise launder this assertion green.
		if op["k"] == "text" and not Menu.HOWTO_TABS.has(String(op["id"])):
			page += String(op["id"]) + " "
	var wc_stub = m.main
	m.free()
	wc_stub.free()
	Runner.T.ok(page.contains("ENDLESS"),
		"the WAR CHEST page names the mode where the rally clock is the run ending (got '%s')" % page)


func test_the_controls_page_never_denies_the_flak_vest() -> void:
	## menu.gd's CONTROLS row said "armor never stops them" of bullets. Measure the
	## vest against a real enemy bullet FIRST, then demand the page stop denying it.

	# (i) MEASURE: a vested player takes an enemy bullet dead-on and LIVES.
	var s1 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p1: Dictionary = s1.players[0]
	p1["vest"] = true
	p1["hurt_iframes"] = 0
	s1.enemy_bullets.append({"x": p1["x"], "y": p1["y"], "vx": 0, "vy": 0, "ttl": 10})
	s1.step(_idle())
	Runner.T.ok(p1["alive"], "a VESTED player survives a dead-on enemy bullet")
	Runner.T.ok(not p1["vest"], "…and the vest is what paid for it")

	# (ii) CONTROL: the same shot with no vest kills. The vest is the whole difference.
	var s2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p2: Dictionary = s2.players[0]
	p2["vest"] = false
	p2["hurt_iframes"] = 0
	s2.enemy_bullets.append({"x": p2["x"], "y": p2["y"], "vx": 0, "vy": 0, "ttl": 10})
	s2.step(_idle())
	Runner.T.ok(not p2["alive"], "…and an UNVESTED player takes the identical shot and drops")

	# (iii) THE PAGE MUST NOT DENY IT.
	var corpus := _menu_text_corpus()
	Runner.T.ok(corpus.length() > 400, "the menu corpus captured real ink (%d chars)" % corpus.length())
	for lie in ["armor never stops", "nothing stops bullets", "nothing absorbs"]:
		Runner.T.ok(not corpus.to_lower().contains(lie),
			"no menu string claims '%s' — the FLAK VEST does" % lie)
	Runner.T.ok(corpus.contains("FLAK VEST"),
		"the rules pages name the FLAK VEST as the thing that eats a hit")


func test_arcade_ground_scorches_toward_the_foundry() -> void:
	## The ground palette marched on OPENED GATES in campaign and on `wave` in
	## everything else — but `wave` only ever increments in _start_wave(), which
	## only endless reaches. Arcade therefore sat at march 0.0 for the whole run:
	## jungle-green floor under the Foundry finale it was streaming.
	var m = Main.new()
	m.sim = SimWorld.new(0, 1, "arcade")
	for _g in 5:
		m.sim.gates.append({"open": true})
	var march: float = m._compute_sector_march()
	m.free()
	Runner.T.ok(march > 0.9,
		"ARCADE ground scorches toward the Foundry — 5 gates open must read as the finale, not wave 0, got %.2f" % march)


func test_the_ground_decal_band_loop_survives_a_band_boundary() -> void:
	## camera_top is the NORTH edge of the view, so absi() DESCENDS down the
	## screen. Both ground-decal loops ran range(absi(top)/seg, absi(bot)/seg + 1)
	## — high to low — so the range went EMPTY whenever the 420px window straddled
	## a band line, and trenches/rubble silently vanished for ~42% of every band.
	Runner.T.ok(_view_src().contains("func _visible_bands("),
		"the ground decals share one band-range helper")
	if not _view_src().contains("func _visible_bands("):
		return
	var m = Main.new()
	m.sim = SimWorld.new(0xC0FFEE, 1)
	m.sim.camera_top = -3050 * Fixed.ONE        # window covers absi 2630..3050 -> bands 2 AND 3
	var got: Array = []
	for b in m._visible_bands():
		got.append(b)
	Runner.T.ok(got.has(2) and got.has(3),
		"a view straddling the band 2/3 line draws BOTH bands' decals, got %s" % [got])
	m.sim.camera_top = -2500 * Fixed.ONE
	got = []
	for b in m._visible_bands():
		got.append(b)
	Runner.T.ok(got == [2], "a view inside one band draws exactly that band, got %s" % [got])
	m.free()


func test_the_step_reverting_geometry_is_drawn_where_it_collides() -> void:
	## Two predicates reverted your step with NOTHING on screen: the temporary lane
	## seal (a 200x120 slab that walls off a flank for 12s of every 20s cycle) and
	## the one-way ledge (a 320px span that eats every retreat step, in every band
	## from 2 up). The seal had a 3-tick particle telegraph for the camera's band
	## only; the ledge had no signal of any kind. Both are now drawn at the sim's
	## OWN span helpers, so art == collision by construction.
	var view := _view_src()
	Runner.T.ok(view.contains("_draw_ledges()") and view.contains("_draw_lane_seals()"),
		"_draw_terrain draws the one-way ledge and the lane seal")
	Runner.T.ok(view.contains("SimWorld.ledge_span(") and view.contains("SimWorld.lane_seal_span("),
		"...off the sim's own span helpers, not a restated _mix in the draw call")
	var sim := SimWorld.new(0xC0FFEE, 1)   # campaign
	for band in [2, 3, 4, 5]:
		var lg: Array = SimWorld.ledge_span(band)
		var north: int = lg[0] - 4 * Fixed.ONE
		var south: int = lg[0] + 4 * Fixed.ONE
		Runner.T.ok(sim._crosses_ledge_south(lg[1] + Fixed.ONE, south, north),
			"band %d: the drawn LEFT end of the ledge blocks a retreat" % band)
		Runner.T.ok(sim._crosses_ledge_south(lg[2] - Fixed.ONE, south, north),
			"band %d: the drawn RIGHT end blocks a retreat" % band)
		Runner.T.ok(not sim._crosses_ledge_south(lg[1] - 2 * Fixed.ONE, south, north),
			"band %d: 2px outside the drawn LEFT end is free — art == collision" % band)
		Runner.T.ok(not sim._crosses_ledge_south(lg[2] + 2 * Fixed.ONE, south, north),
			"band %d: 2px outside the drawn RIGHT end is free" % band)
		Runner.T.eq(lg[2] - lg[1], 320 * Fixed.ONE, "band %d: the drawn ledge is 320px wide" % band)
		var sp: Array = SimWorld.lane_seal_span(band)
		var y_in: int = -(band * SimWorld.GATE_SPACING + (sp[0] + sp[1]) / 2)
		var y_out: int = -(band * SimWorld.GATE_SPACING + sp[1] + 2 * Fixed.ONE)
		var x_in: int = (SimWorld.WORLD_LEFT + Fixed.ONE) if sp[2] == 0 else (SimWorld.WORLD_RIGHT - Fixed.ONE)
		var x_out: int = (SimWorld.WORLD_LEFT + 202 * Fixed.ONE) if sp[2] == 0 else (SimWorld.WORLD_RIGHT - 202 * Fixed.ONE)
		sim.tick_count = SimWorld.LANE_BLOCK_CYCLE - band * 300          # phase 0 -> SEALED
		Runner.T.ok(SimWorld.lane_sealed(sim.tick_count, band), "band %d: sealed phase" % band)
		Runner.T.ok(sim._lane_blocked(x_in, y_in), "band %d: the drawn slab is the solid slab" % band)
		Runner.T.ok(not sim._lane_blocked(x_out, y_in), "band %d: 2px past the drawn inner edge is free" % band)
		Runner.T.ok(not sim._lane_blocked(x_in, y_out), "band %d: 2px past the drawn north edge is free" % band)
		sim.tick_count += SimWorld.LANE_BLOCK_SEALED                     # -> OPEN
		Runner.T.ok(not SimWorld.lane_sealed(sim.tick_count, band), "band %d: open phase" % band)
		Runner.T.ok(not sim._lane_blocked(x_in, y_in),
			"band %d: the slab is passable while OPEN — the view must not draw it solid" % band)


func test_grenade_landing_marker_is_where_the_grenade_detonates() -> void:
	## The marker + blast ring solved a CLOSED-FORM parabola and moved the
	## grenade along vx/vy only. The sim integrates discretely (gravity AFTER
	## the z step -> it lands one tick later, ~3px) and shoves airborne frags
	## MARSH_DRIFT/tick sideways over seg-2 open water. Over a full 33-tick
	## lob that is 33px of un-previewed drift against a 28px kill radius: the
	## ring you aimed with need not overlap the circle that kills.
	Runner.T.ok(not _view_src().contains("sqrt(zv * zv + 2.0 * grav"),
		"the landing marker no longer closed-forms a parabola the sim never integrates")
	var sim := SimWorld.new(31, 1)
	sim.waters.append({"y": -2540 * Fixed.ONE, "ford_x": 600 * Fixed.ONE})
	var x0: int = 300 * Fixed.ONE
	var g := {"x": x0, "y": -2500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 0, "zv": SimWorld.GRENADE_ZVEL, "owner": 0, "shell": false, "hold": false}
	sim.grenades.append(g)
	var pred: Array = sim.predict_grenade_landing(g)
	for t in 128:
		sim._step_grenades()
		if sim.grenades.is_empty():
			break
	# _explode fires on the tick the grenade is swept; we hold the dict, so
	# g["x"]/g["y"] ARE the coordinates it detonated at.
	Runner.T.eq(int(pred[0]), int(g["x"]), "the previewed landing X is the X it detonates at")
	Runner.T.eq(int(pred[1]), int(g["y"]), "the previewed landing Y is the Y it detonates at")
	Runner.T.ok(absi(int(g["x"]) - x0) >= SimWorld.GRENADE_RADIUS,
		"this throw really does drift %.0fpx — a full %.0fpx blast radius the old marker never showed"
		% [absi(int(g["x"]) - x0) * PX, SimWorld.GRENADE_RADIUS * PX])


func test_grenade_landing_marker_models_the_held_airburst() -> void:
	## The predictor flew the full 32-tick lob (~99px) even while the fuse hand
	## was still armed — but _step_grenades pops a HELD frag at the arc's apex
	## (the zv sign-flip, tick 17, ~51px out). The ring you aimed with sat 48px
	## past the circle that kills: a lie BIGGER than the 28px GRENADE_RADIUS
	## kill ring. sim.grenades has exactly three shapes (held frag / tap frag /
	## tank shell) and one consumer seam, so pin all three through it.
	var y0: int = -2500 * Fixed.ONE
	# 1. HELD FRAG: airbursts at the apex, ~51px out — NOT the 99px full lob.
	var sim := SimWorld.new(31, 1)
	sim.players[0]["grenade_prev"] = true   # the fuse hand stays armed (no release disarm)
	var held := {"x": 300 * Fixed.ONE, "y": y0, "vx": 0, "vy": -SimWorld.GRENADE_SPEED,
		"z": 0, "zv": SimWorld.GRENADE_ZVEL, "owner": 0, "shell": false, "hold": true}
	sim.grenades.append(held)
	var hpred: Array = sim.predict_grenade_landing(held)
	for t in 128:
		sim._step_grenades()
		if sim.grenades.is_empty():
			break
	var held_dist: int = absi(int(held["y"]) - y0)
	Runner.T.ok(held_dist < 70 * Fixed.ONE,
		"this throw really did airburst inside the arc (detonated %.0fpx out, not the 99px lob)"
		% (held_dist * PX))
	Runner.T.eq(int(hpred[0]), int(held["x"]),
		"HELD frag: the previewed X is the airburst X (marker was %.0fpx past the detonation)"
		% (absi(int(hpred[0]) - int(held["x"])) * PX))
	Runner.T.eq(int(hpred[1]), int(held["y"]),
		"HELD frag: the previewed Y is the airburst Y (marker was %.0fpx past the 28px kill ring)"
		% (absi(int(hpred[1]) - int(held["y"])) * PX))
	# 2. TAP FRAG (hold: false): flies the full lob — the fix must not shorten it.
	var sim2 := SimWorld.new(31, 1)
	var tap := {"x": 300 * Fixed.ONE, "y": y0, "vx": 0, "vy": -SimWorld.GRENADE_SPEED,
		"z": 0, "zv": SimWorld.GRENADE_ZVEL, "owner": 0, "shell": false, "hold": false}
	sim2.grenades.append(tap)
	var tpred: Array = sim2.predict_grenade_landing(tap)
	for t in 128:
		sim2._step_grenades()
		if sim2.grenades.is_empty():
			break
	Runner.T.eq(int(tpred[0]), int(tap["x"]), "TAP frag: the previewed X is the landing X")
	Runner.T.eq(int(tpred[1]), int(tap["y"]), "TAP frag: the previewed Y is the landing Y (full lob)")
	var tap_dist: int = absi(int(tap["y"]) - y0)
	Runner.T.ok(tap_dist > held_dist + 40 * Fixed.ONE,
		"the tap lob (%.0fpx) really outranges the held airburst (%.0fpx) by the ~48px the marker used to hide"
		% [tap_dist * PX, held_dist * PX])
	# 3. TANK SHELL (shell: true): the cannon has no fuse hand — full lob even
	# with hold forced on. Pins the `not g["shell"]` guard, not just the break.
	var sim3 := SimWorld.new(31, 1)
	sim3.players[0]["grenade_prev"] = true
	var shell := {"x": 300 * Fixed.ONE, "y": y0, "vx": 0, "vy": -SimWorld.GRENADE_SPEED,
		"z": 0, "zv": SimWorld.GRENADE_ZVEL, "owner": 0, "shell": true, "hold": true}
	sim3.grenades.append(shell)
	var spred: Array = sim3.predict_grenade_landing(shell)
	for t in 128:
		sim3._step_grenades()
		if sim3.grenades.is_empty():
			break
	Runner.T.eq(int(spred[0]), int(shell["x"]), "SHELL: the previewed X is the impact X")
	Runner.T.eq(int(spred[1]), int(shell["y"]),
		"SHELL: no airburst even with hold set — the previewed Y is the full-lob impact Y")
	Runner.T.eq(absi(int(shell["y"]) - y0), tap_dist,
		"SHELL flies the same full lob as the tap frag (the fuse hand is a frag-only verb)")


func test_airburst_verb_is_taught() -> void:
	## The fuse-hand verb existed only in a sim comment — nothing on screen or
	## in the manual ever said TAP lobs far / HOLD pops it at the arc, so the
	## first airburst read as a malfunction. It now teaches at the exact moment
	## of surprise (the idempotent, persisted _hint seam) and the HOWTO grenade
	## row names both verbs.
	Runner.T.ok(_view_src().contains('_hint("airburst"'),
		"the first airburst fires the one-shot TAP-vs-HOLD hint through _hint")
	var menu := FileAccess.get_file_as_string("res://src/view/menu.gd")
	var gpos := menu.find("GRENADES crack armor")
	Runner.T.ok(gpos >= 0, "the HOWTO grenade verb line is still findable")
	var gline := menu.substr(gpos, menu.find("\n", gpos) - gpos)
	Runner.T.ok(gline.contains("TAP") and gline.contains("HOLD"),
		"the HOWTO grenade line names both verbs (TAP lobs far — HOLD pops it at the arc)")


func test_result_cards_are_debrief_documents_not_bare_boxes() -> void:
	## Victory and K.I.A. both stamped bare stats on the same near-black
	## ui_panel — one grey box for both debriefs. They are now DOCUMENTS: the
	## panel body draws a header band (doc["band"]) and a form-number microline
	## (doc["form"]) fed by each call site's own identity, so the card you get
	## for winning can never read as the card you get for dying.
	## Source-shape pin (the suite's established idiom for view furniture):
	## main.gd draw paths have no _emit_* capture seam and screenshots need a
	## GL context, so the strongest headless check pins the shipped draw body.
	var src := _view_src()
	for s in ["AFTER-ACTION REPORT", "CASUALTY REPORT", "FORM AAR-7", "FORM KIA-1"]:
		Runner.T.ok(src.contains(s), "the result cards carry the %s document identity" % s)
	var body_start := src.find("func _draw_result_panel(")
	Runner.T.ok(body_start >= 0, "_draw_result_panel still exists")
	var body := src.substr(body_start, src.find("\nfunc ", body_start + 10) - body_start)
	Runner.T.ok(body.contains("Art.text_center(self, doc[\"band\"]"),
		"the panel body actually draws the band stencil")
	Runner.T.ok(body.contains("Art.text_center(self, doc[\"form\"]"),
		"the panel body actually draws the form-number microline")


# --- 7. Copy honesty: "PERMANENT" must never name something death strips ------

func _stripped_loss_nouns() -> Array[String]:
	## Both halves derived from source, so a noun or a stripped key added tomorrow
	## is covered the day it lands: the noun table scraped out of main.gd's
	## LOSS_NOUN, the strip list read off SimWorld.DEATH_LOSS_KEYS itself.
	var src := _view_src()
	var start := src.find("const LOSS_NOUN")
	Runner.T.ok(start >= 0, "LOSS_NOUN const not found in main.gd — the scrape anchor moved")
	var body := src.substr(start)
	body = body.substr(0, body.find("\n}\n") + 3)
	var re := RegEx.create_from_string('"([a-z_]+)":\\s*"([^"]+)"')
	var nouns: Array[String] = []
	for m in re.search_all(body):
		if m.get_string(1) in SimWorld.DEATH_LOSS_KEYS:
			nouns.append(m.get_string(2))
	return nouns


func _contains_word(haystack: String, needle: String) -> bool:
	var re := RegEx.create_from_string("(?<![A-Z0-9])" + needle + "(?![A-Z0-9])")
	return re.search(haystack) != null


func test_no_player_facing_string_calls_a_death_stripped_mod_permanent() -> void:
	## The Triple Shot hint shipped "PERMANENT 3-ROUND FAN" — but `triple` is in
	## DEATH_LOSS_KEYS and _respawn strips it (the 1986 rule, pinned by
	## test_gameplay.gd's test_triple_pickup_grants_and_death_strips). One word
	## promised the player the one thing the sim never does. The sim strip is
	## deliberate; the copy was the lie. This scans every player-facing string
	## (view sources + locale msgids, which are keyed on the English literal) for
	## "PERMANENT" standing next to the name of anything death takes.
	var nouns := _stripped_loss_nouns()
	Runner.T.ok(nouns.size() >= 5,
		"only %d stripped nouns parsed — the LOSS_NOUN/DEATH_LOSS_KEYS scrape is broken, not the copy" % nouns.size())
	var offenders: Array[String] = []
	var lit_re := RegEx.create_from_string('"([^"\\n]*)"')
	for path in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd"]:
		for m in lit_re.search_all(FileAccess.get_file_as_string(path)):
			var s: String = m.get_string(1)
			if not s.contains("PERMANENT"):
				continue
			for noun in nouns:
				if _contains_word(s, noun):
					offenders.append("%s: \"%s\" calls %s PERMANENT, but death strips it" % [path, s, noun])
	var dir := DirAccess.open("res://locale")
	Runner.T.ok(dir != null, "res://locale unreadable — the msgid scan is not running")
	for f in dir.get_files():
		if not f.ends_with(".po"):
			continue
		var path := "res://locale/" + f
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with('msgid "') or not line.contains("PERMANENT"):
				continue
			var s := line.substr(7, line.length() - 8)
			for noun in nouns:
				if _contains_word(s, noun):
					offenders.append("%s: msgid \"%s\" calls %s PERMANENT, but death strips it" % [path, s, noun])
	Runner.T.ok(offenders.is_empty(),
		"player-facing copy calls a death-stripped mod PERMANENT:\n" + "\n".join(offenders))


func test_wave_13_banner_names_the_armor() -> void:
	## The endless difficulty curve's ONLY unbounded term — _wave_armor, live
	## from wave 13, +1 bullet per body every 6 waves — shipped with ZERO view
	## tell: the wave banner named the mutator but never the armor, so the
	## moment your gun stopped killing was indistinguishable from every other
	## wave. The sim term is deliberate (the _wave_armor docstring explains it
	## redirects the War Chest into grenades) — the SILENCE was the defect. The
	## banner must name each thickening once, with the counter-rule in the same
	## breath. Driven through the REAL _consume_events, not a re-implementation.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var stub := Main.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN   # _hint/banners early-return under the title
	stub.sim = sim
	var armor_banners := func() -> Array:
		var out := []
		for b in stub._banners:
			if String(b["text"]).contains("ARMOR"):
				out.append(b["text"])
		return out
	# Wave 12 (and every earlier wave): armor is 0 — no armor banner may fire.
	sim.wave = 12
	sim.events = [{"t": "wave_start", "mod": 0}]
	stub._consume_events()
	Runner.T.eq(armor_banners.call().size(), 0,
		"wave 12 has no veteran armor — an armor banner here is a false positive (got %s)" % str(armor_banners.call()))
	# Wave 13: the term goes live (armor 1) — the banner must NAME it.
	sim.wave = 13
	sim.events = [{"t": "wave_start", "mod": 0}]
	stub._consume_events()
	var got13: Array = armor_banners.call()
	Runner.T.eq(got13.size(), 1,
		"wave 13 turns veteran armor ON and the view said nothing about it (banners: %s)" % str(stub._banners))
	if got13.size() == 1:
		Runner.T.ok(String(got13[0]).contains("GRENADE"),
			"the armor banner must carry the counter-rule in the same breath (got '%s')" % got13[0])
	# Wave 14: same armor level — the banner must NOT re-fire every wave.
	stub._banners.clear()
	sim.wave = 14
	sim.events = [{"t": "wave_start", "mod": 0}]
	stub._consume_events()
	Runner.T.eq(armor_banners.call().size(), 0,
		"armor did not thicken at wave 14 — re-announcing an unchanged level is banner spam")
	# Wave 19: armor thickens to 2 — the thickening is re-announced, once.
	stub._banners.clear()
	sim.wave = 19
	sim.events = [{"t": "wave_start", "mod": 0}]
	stub._consume_events()
	var got19: Array = armor_banners.call()
	Runner.T.eq(got19.size(), 1,
		"the wave-19 thickening (armor 2) landed silently (banners: %s)" % str(stub._banners))
	if got19.size() == 1:
		Runner.T.ok(String(got19[0]).contains("2"),
			"the re-announce must name the NEW level (got '%s')" % got19[0])
	stub.free()


func test_veteran_armor_block_is_not_the_wall_plink() -> void:
	## The armor_block view handler knew two targets: walls/bunkers (flat ping +
	## once-ever "BUNKERS TAKE NO BULLETS" hint) and two special cases (mg_nest,
	## shield). Wave-13+ veteran infantry — the third target — fell into the
	## WALL path: a fresh profile shooting a wave-13 soldier got a bunker
	## lecture and a ping that says "give up", when the truth is "bullets still
	## chip it, just slower". The split is the sim's own seam: hp is only ever
	## SET on the enemy dict when _wave_armor applied it (sim_world.gd
	## _spawn_enemy/_spawn_special: "Only SET when it applies"), absent on every
	## unarmored spawn — and the GATE is _wave_armor() > 0, because hp alone
	## leaks: technical (TECHNICAL_HP) and broadcast (BROADCAST_HP) carry hp at
	## EVERY wave of both modes, so a wave-5 truck plink must keep the wall
	## grammar, not draw the veteran chip. Driven through the REAL
	## _consume_events.
	var ms: Script = load("res://src/main.gd")
	var cmap: Dictionary = ms.get_script_constant_map()
	Runner.T.ok(cmap.has("VET_CHIP_COL"),
		"the veteran chip wears its own named ink (same amber family as the armor banner)")
	if not cmap.has("VET_CHIP_COL"):
		return
	var vet_col: Color = cmap["VET_CHIP_COL"]
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim.wave = 13
	var stub := Main.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN
	stub.sim = sim
	var ex: int = 100 * Fixed.ONE
	var ey: int = sim.camera_top + 200 * Fixed.ONE
	# A wave-13 rusher: hp SET by the sim's own spawn path (2 = 1 base + 1 armor).
	sim.enemies.append({"x": ex, "y": ey, "alive": true, "kind": "rusher", "hp": 2})
	sim.events = [{"t": "armor_block", "x": ex, "y": ey}]
	stub._consume_events()
	var chip := false
	for fx in stub._fx:
		if fx.get("tex", "") == "fx_sparkle" and fx.get("col", Color()) == vet_col:
			chip = true
			break
	Runner.T.ok(chip,
		"bullets chipping veteran armor drew NOTHING distinct — same spark + wall ping as a bunker")
	var vet_hint := false
	var bunker_hint := false
	for line in stub._hint_queue:
		if String(line).contains("VETERAN ARMOR"):
			vet_hint = true
		if String(line).contains("BUNKERS TAKE NO BULLETS"):
			bunker_hint = true
	Runner.T.ok(vet_hint,
		"the first veteran chip must teach the counter-rule (bullets chip, grenades one-shot)")
	Runner.T.ok(not bunker_hint,
		"a soldier is not a bunker — the BUNKERS TAKE NO BULLETS lecture is the wall grammar leaking")
	# Companion, pinning the seam the other way: a wave-<=12 enemy (hp ABSENT —
	# the sim never sets it) blocking a bullet is NOT a veteran — no amber
	# chip, and the wall hint still fires.
	var stub2 := Main.new()
	stub2._menu.mode = GameMenu.Mode.HIDDEN
	var sim2 := SimWorld.new(0xC0FFEE, 1, "endless")
	sim2.wave = 5
	stub2.sim = sim2
	sim2.enemies.append({"x": ex, "y": ey, "alive": true, "kind": "rusher"})
	sim2.events = [{"t": "armor_block", "x": ex, "y": ey}]
	stub2._consume_events()
	var chip2 := false
	for fx in stub2._fx:
		if fx.get("tex", "") == "fx_sparkle" and fx.get("col", Color()) == vet_col:
			chip2 = true
			break
	Runner.T.ok(not chip2,
		"the veteran chip leaked onto UNARMORED infantry — hp >= 1 is the split, nothing else")
	var bunker_hint2 := false
	for line in stub2._hint_queue:
		if String(line).contains("BUNKERS TAKE NO BULLETS"):
			bunker_hint2 = true
	Runner.T.ok(bunker_hint2,
		"an unarmored-target block keeps the wall teach — the split must not swallow it")
	# Third pin, the leak the hp-only split shipped: a TECHNICAL at wave 5
	# carries hp=TECHNICAL_HP at every wave of both modes — hp >= 1 alone
	# matched it and taught "VETERAN ARMOR" eight waves before any veteran
	# exists. The _wave_armor() gate must keep it on the wall grammar.
	var stub3 := Main.new()
	stub3._menu.mode = GameMenu.Mode.HIDDEN
	var sim3 := SimWorld.new(0xC0FFEE, 1, "endless")
	sim3.wave = 5
	stub3.sim = sim3
	sim3.enemies.append({"x": ex, "y": ey, "alive": true, "kind": "technical", "hp": 2})
	sim3.events = [{"t": "armor_block", "x": ex, "y": ey}]
	stub3._consume_events()
	var chip3 := false
	for fx in stub3._fx:
		if fx.get("tex", "") == "fx_sparkle" and fx.get("col", Color()) == vet_col:
			chip3 = true
			break
	Runner.T.ok(not chip3,
		"a wave-5 technical is not a veteran — hp is set on trucks/broadcasts at EVERY wave")
	var vet_hint3 := false
	for line in stub3._hint_queue:
		if String(line).contains("VETERAN ARMOR"):
			vet_hint3 = true
	Runner.T.ok(not vet_hint3,
		"the VETERAN ARMOR teach fired before veteran armor exists (wave 5) — a lie about the mechanic")
	stub.free()
	stub2.free()
	stub3.free()


# --- A duplicate capsule's receipt names the item it actually is ---

func test_duplicate_pickup_receipt_names_the_item_it_actually_is() -> void:
	## The "honest receipt" branch in main.gd's pickup consumer fires for ANY
	## capsule the sim flags `full` — and _supply_full can flag TWO: a Triple Shot
	## you already own (kind 6 — permanent, so free duplicates ride the
	## consume-and-flag grammar at 1/30 per elite kill while triple persists) and
	## claymores at the cap (kind 8). The view printed the hardcoded literal
	## "CLAYMORES FULL" for BOTH, so a duplicate TRIPLE SHOT announced itself as
	## the wrong item. Sim-driven pin: make the sim emit the kind-6 full event,
	## then require the view's receipt text for that kind to name TRIPLE and never
	## CLAYMORE. Class pin: no capsule kind's receipt may borrow a DIFFERENT
	## capsule's name, so the day _supply_full grows a branch the wrong-name shape
	## is unrepresentable, not just unfired.
	var ms: Script = load("res://src/main.gd")
	var sim := SimWorld.new(0xC0FFEE, 1)
	var p: Dictionary = sim.players[0]
	p["triple"] = true
	sim.pickups = [{"x": p["x"], "y": p["y"], "kind": 6, "cost": 0}]
	sim._collect_pickups(p, 0)
	var full6 := false
	for ev in sim.events:
		if ev.get("t") == "pickup" and int(ev.get("kind", -1)) == 6 and ev.get("full", false):
			full6 = true
	Runner.T.ok(full6,
		"the sim really does flag a duplicate TRIPLE SHOT pickup full (kind 6)")
	Runner.T.ok(ms.has_method("pickup_full_text"),
		"the view derives the full-receipt text from the kind (pickup_full_text), not one hardcoded item name")
	if ms.has_method("pickup_full_text"):
		var t6: String = ms.call("pickup_full_text", 6)
		Runner.T.ok(t6.contains("TRIPLE"),
			"a duplicate TRIPLE SHOT's receipt names TRIPLE, got '%s'" % t6)
		Runner.T.ok(not t6.contains("CLAYMORE"),
			"a duplicate TRIPLE SHOT's receipt never says CLAYMORES FULL, got '%s'" % t6)
		var labels: Array = ms.get_script_constant_map()["_CAPSULE_LABEL"]
		for k in range(4, 4 + labels.size()):
			var tk: String = ms.call("pickup_full_text", k)
			for li2 in labels.size():
				if li2 != k - 4 and tk.contains(str(labels[li2])):
					Runner.T.ok(false,
						"kind %d's receipt '%s' borrows %s's name" % [k, tk, str(labels[li2])])
	# Wiring ratchet (the claim_label_slot precedent): a def-only helper is the
	# same green-but-wrong trap — it must be CALLED by the pickup consumer.
	var src := _view_src()
	Runner.T.ok(src.count("pickup_full_text(") >= 2,
		"pickup_full_text is wired into the pickup consumer, not just defined (%d sites)"
			% src.count("pickup_full_text("))
