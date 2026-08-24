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


func _call_src(src: String, at: int) -> String:
	## The exact text of the call that starts at `at`, paren-balanced. A source-grep
	## over a WIDE WINDOW around a neighbouring call is how a half-applied effect
	## passes its own ratchet (c4-19: the nest's gun ramped, its sandbag base did
	## not, and a 1400-char window around `_spr("mg_stand"` never noticed).
	var i := src.find("(", at)
	if i < 0:
		return ""
	var depth := 0
	var j := i
	while j < src.length():
		var c := src[j]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return src.substr(at, j - at + 1)
		j += 1
	return src.substr(at, 240)


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
	elif kind == "rifleman":
		sim.enemies.append({"x": x, "y": y, "alive": true, "elite": false,
			"kind": "rusher", "fire_cd": 0, "windup": 0, "skin": 1})
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
	Runner.T.eq(kinds, ["elite", "ghillie", "mg_nest", "rifleman", "sniper", "technical"],
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
	Runner.T.eq(view.count("telegraph_dir(sim, e)"), 6,
		"all six enemy telegraph draw sites (rifleman/sniper/technical/mg_nest/ghillie/elite) read Main.telegraph_dir()")
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


func test_death_feedback_is_concise_causal_and_last_stand_explicit() -> void:
	var ms: Script = load("res://src/main.gd")
	Runner.T.ok(ms.has_method("_loss_summary"), "revive loss has one summary formatter")
	if ms.has_method("_loss_summary"):
		var summary: String = ms._loss_summary({"vest": true, "triple": true,
			"pierce_ticks": 300, "claymores": 3})
		Runner.T.ok(summary.begins_with("LOADOUT LOST — 4 ITEMS"),
			"one compact receipt reports the full stripped-field count (got %s)" % summary)
		Runner.T.ok(summary.contains("3 CLAYMORES"),
			"countable mine stock remains explicit in the compact receipt (got %s)" % summary)
		Runner.T.ok(not summary.contains("\n"), "inventory loss stays on one battlefield line")
		Runner.T.eq(ms._loss_summary({}), "", "no stripped loadout emits no loss noise")
	Runner.T.ok(ms.has_method("_down_loss_summary"), "global down losses share one summary line")
	if ms.has_method("_down_loss_summary"):
		var down_summary: String = ms._down_loss_summary(1, 3)
		Runner.T.ok(down_summary.contains("COMMENDATION") and down_summary.contains("FLAWLESS STREAK"),
			"the combined down receipt still names both global losses")
		Runner.T.ok(not down_summary.contains("\n"), "global down losses stay on one battlefield line")
	Runner.T.ok(ms.has_method("_defeat_title"), "defeat title has a Last Stand-aware source")
	if ms.has_method("_defeat_title"):
		Runner.T.eq(ms._defeat_title(false), "K.I.A.", "ordinary defeats keep the established title")
		Runner.T.ok(String(ms._defeat_title(true)).contains("LAST STAND")
			and String(ms._defeat_title(true)).contains("DEFEAT"),
			"the finale debrief explicitly identifies a Last Stand defeat")
	var src := _view_src()
	Runner.T.ok(src.contains('_loss_sting(ev, "DOWNED — %s" % death_cause)'),
		"the fatal beat names its inferred cause at the body, before the debrief")
	Runner.T.ok(src.contains("_draw_result_panel(_defeat_title(sim.last_stand)"),
		"the Last Stand-aware title is wired into the actual casualty card")
	# Exactly one loadout receipt call in _ev_revive: complete event payload, one visual line.
	var rev_start := src.find("func _ev_revive(")
	var rev_end := src.find("\nfunc ", rev_start + 6)
	Runner.T.ok(rev_start >= 0 and rev_end > rev_start, "revive feedback block is delimited")
	if rev_start >= 0 and rev_end > rev_start:
		var rev_body := src.substr(rev_start, rev_end - rev_start)
		Runner.T.eq(rev_body.count("_loss_sting("), 1,
			"any-size loadout loss emits exactly one battlefield receipt")


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


# c4-19: A ROOTED UNIT FADES IN INSTEAD OF POPPING.
# mg_nest / broadcast / ghillie never move, so before this they simply EXISTED on
# the next frame at full opacity, mid-screen, with no arrival beat — the sim emitted
# nothing the view could hang one on. The sim now emits `rooted_spawn`; this pins the
# VIEW half, which the event-coverage gate cannot reach (that gate only sees event
# types the determinism torture emits, and the torture produces ZERO rooted births
# in either mode — measured).
#
# Fairness: the ramp must never eat into the player's warning. Measured on this tree,
# a nest's birth -> aim-lock is 30 ticks and birth -> first round is 60, with the last
# 30 drawing the amber telegraph lane. The bound below is read off the SIM constant,
# not off a literal, so a shortened reload drags the ramp down with it.
func test_a_rooted_unit_fades_in_instead_of_popping() -> void:
	Runner.T.ok(Main.ROOTED_ARRIVE_FRAMES <= SimWorld.MG_NEST_AIM_TICKS,
		"the arrival ramp (%d frames) finishes inside the nest's pre-telegraph reload (%d ticks)"
			% [Main.ROOTED_ARRIVE_FRAMES, SimWorld.MG_NEST_AIM_TICKS])
	Runner.T.ok(Main.rooted_arrival_alpha(0.0) < 0.35,
		"a rooted unit's first drawn frame is faint, not solid (alpha %.2f)" % Main.rooted_arrival_alpha(0.0))
	Runner.T.eq(Main.rooted_arrival_alpha(float(Main.ROOTED_ARRIVE_FRAMES)), 1.0,
		"the ramp reaches full opacity exactly at the window")
	Runner.T.eq(Main.rooted_arrival_alpha(999.0), 1.0,
		"a unit with no recorded arrival (missed event, loaded mid-run) draws normally")

	for k in SimWorld.ROOTED_KINDS:
		var sim := SimWorld.new(11, 1, "endless")
		sim.step([SimInput.new()])
		var stub := Main.new()
		stub._menu.mode = GameMenu.Mode.HIDDEN
		stub.sim = sim
		var fx_before: int = stub._fx.size()
		sim.events = [{"t": "rooted_spawn", "x": 300 * SimWorld.F_ONE,
			"y": sim.camera_top + 150 * SimWorld.F_ONE, "kind": k}]
		stub._consume_events()
		Runner.T.ok(stub._fx.size() > fx_before,
			"'%s' arrival spawns view FX (%d -> %d)" % [k, fx_before, stub._fx.size()])
		var key := "%d,%d" % [300 * SimWorld.F_ONE, sim.camera_top + 150 * SimWorld.F_ONE]
		if k == "broadcast":
			# The mast is deliberately NOT ramped: it already announces itself on its
			# first stepped tick (fire_cd == 0 at birth -> `broadcast_pulse`), and its
			# draw branch reads no ramp. A key registered for it would be state nothing
			# consumes — which is worse than none, because THIS test would then report
			# "broadcast registers its dig-in ramp" while the mast never faded a pixel.
			Runner.T.ok(not stub._rooted_arrive.has(key),
				"'broadcast' registers NO ramp key — its arrival beat is the tick-1 broadcast_pulse, and its draw branch reads no ramp")
		else:
			Runner.T.ok(stub._rooted_arrive.has(key),
				"'%s' arrival registers its dig-in ramp under the unit's stable x,y key" % k)
		stub.free()

	# ...and the draw branches must actually CONSULT the ramp. A registered age that
	# nothing reads is the `claim_label_slot` failure: green signature, unchanged screen.
	var src := _view_src()
	for branch in ["mg_stand", "ghillie"]:
		var at := src.find('_spr("%s"' % branch)
		Runner.T.ok(at >= 0, "the %s draw branch is still findable" % branch)
		if at < 0:
			continue
		var lo := maxi(0, at - 1400)
		Runner.T.ok(src.substr(lo, at - lo + 400).contains("rooted_arrival_alpha"),
			"the %s draw branch fades its sprite in through rooted_arrival_alpha" % branch)

	# ...and EVERY element of the emplacement, at the CALL SITE. The nest is two
	# sprites: measured off the source PNGs through tools/measure_hitbox.gd's formula
	# (imported px x art SCALE x call-site spr_scale, opaque-alpha bbox), the sandbag
	# ring draws 33.2 x 16.6 px / 325 px^2 and mg_stand 24.0 x 35.4 px / 477 px^2 — so
	# the bags are 41% of the emplacement's opaque pixels and its WIDEST element. A
	# ramp on the gun alone still materialises the nest, and the window grep above
	# passes anyway, because the sandbag call is INSIDE the same 1400 chars.
	# Anchored INSIDE the mg_nest branch: three other `sandbag_beige` calls draw wreck
	# debris earlier in the file, and a bare find() pins one of those instead.
	var nest_at := src.find('elif e["kind"] == "mg_nest":')
	Runner.T.ok(nest_at >= 0, "the mg_nest draw branch is still findable")
	var sb := src.find('_spr("sandbag_beige"', nest_at) if nest_at >= 0 else -1
	Runner.T.ok(sb >= 0, "the mg_nest sandbag draw call is still findable")
	if sb >= 0:
		var sb_call := _call_src(src, sb)
		Runner.T.ok(sb_call.contains("n_arr"),
			"the sandbag base rides the SAME dig-in ramp as the gun, at its own call site: %s" % sb_call)
		var ramp_at := src.find("var n_arr := rooted_arrival_alpha(", nest_at)
		Runner.T.ok(ramp_at >= 0 and ramp_at < sb,
			"the nest's ramp is computed from rooted_arrival_alpha BEFORE the sandbag call (ramp at %d, call at %d)" % [ramp_at, sb])


func test_smoke_hint_names_the_nest_that_still_aims() -> void:
	## First-grab kind-9 teach: "SMOKE — BLINDS THEIR AIM. SHELLS STILL FALL BLIND."
	## Measured 2026-08-14: _step_mg_nest fired aims=3 shots=9 in 400 ticks at a
	## smoked player AND at a clear one — identical. The nest has no _concealed
	## gate (sim_world.gd:_step_mg_nest, "suppressing through smoke is its whole
	## identity"). Shells are the exception the hint already names; the nest is
	## the exception it doesn't. A player who trusts the teach dies to the rake.
	var src := _view_src()
	var arm := src.find('9: _hint("smoke"')
	Runner.T.ok(arm >= 0, "the first-grab smoke teach is still the kind-9 _hint arm")
	var line := src.substr(arm, src.find("\n", arm) - arm)
	Runner.T.ok(line.contains("NEST") or line.contains("MG"),
		"the smoke hint must name the nest that still aims through it (got '%s')" % line)
	Runner.T.ok(not (line.contains("BLINDS THEIR AIM") and not (line.contains("NEST") or line.contains("MG"))),
		"it cannot claim universal aim-blind without the nest exception")


func test_colossus_screen_bar_opts_out_under_the_result_card() -> void:
	## Live last-stand (15-live-t18000) painted FOUNDRY COLOSSUS — ADVANCE through
	## the CASUALTY REPORT. Captions/verbs already opt out via _result_card_up;
	## the screen-space bar in _draw_colossus never did.
	var src := _view_src()
	var mark := src.find('var clabel := "FOUNDRY COLOSSUS')
	Runner.T.ok(mark >= 0, "the colossus HUD label is still authored here")
	var chunk := src.substr(maxi(0, mark - 1200), 1600)
	Runner.T.ok(chunk.contains("if _debrief or sim.victory"),
		"the colossus screen-space bar must hide while a result card owns the frame")


func test_hall_tags_the_score_inflating_hard_toggle() -> void:
	## *ASSIST and *DAILY already stamp the board. NG+ HARD was the one toggle
	## that moved score (~1.58x) with no marker.
	var menu_src := FileAccess.get_file_as_string("res://src/view/menu.gd")
	Runner.T.ok(menu_src.contains("tag += \"  *HARD\""),
		"the Hall stamps *HARD on NG+ runs the same way it stamps *ASSIST")
	var rec := _view_src()
	var arm := rec.find("func _record_run(")
	Runner.T.ok(arm >= 0, "_record_run still exists")
	var body := rec.substr(arm, rec.find("\nfunc ", arm + 10) - arm)
	Runner.T.ok(body.contains("\"hard\": sim.hard"),
		"_record_run banks the hard flag the Hall reads")


func test_supply_call_label_names_the_table() -> void:
	## Commendation spend rolled ammo/nades/vest/strike with a label that said
	## only SUPPLY CALL.
	var src := _view_src()
	Runner.T.ok(src.contains("CALL: AMMO/NADES/VEST/STRIKE"),
		"the wheel names what a Commendation can roll")
	Runner.T.ok(not src.contains("\"label\": \"AMMO +30\""),
		"ammo socket no longer promises the catalogue +30 on a partial fill")


func test_airstrike_hint_gates_on_the_live_price() -> void:
	var src := _view_src()
	Runner.T.ok(src.contains("sim.war_chest >= sim._supply_cost(3)"),
		"the airstrike teach uses the depth-creeped price, not the 100c base")
	Runner.T.ok(not src.contains("war_chest >= SimWorld.SHOP_AIRSTRIKE_COST"),
		"the base constant is not the live gate")


func test_ready_up_tally_exists_for_split_votes() -> void:
	var src := _view_src()
	Runner.T.ok(src.contains("func _draw_ready_tally"),
		"2P ready-up has a visible tally")
	Runner.T.ok(src.contains("BOTH HOLD TO DEPLOY"),
		"a split vote says both must hold")


func test_hulk_flame_dies_with_sim_cover() -> void:
	var src := _view_src()
	Runner.T.ok(src.contains("func _hulk_sim_cover"),
		"view wreck fire asks the sim cover clock")
	Runner.T.ok(src.contains("if not _hulk_sim_cover(h):"),
		"the view-time hulk flame pool is gated on that clock")


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

	# ...and it must not sell the rally as a FLAT clock. In endless the free wait
	# compounds on the same deaths curve the price does (SimWorld.broke_wait_ticks),
	# so "A 5s rally puts you back in the fight" became a lie from the second death
	# on. Both numbers come off the sim consts — the floor and the ceiling — so a
	# retune of either can never strand the sentence.
	var sim_consts: Dictionary = (SimWorld as Script).get_script_constant_map()
	Runner.T.ok(sim_consts.has("BROKE_WAIT_MAX_MULT"),
		"SimWorld exposes BROKE_WAIT_MAX_MULT — the ceiling the HOW-TO has to be able to quote")
	var rally_lo: int = int(sim_consts["BROKE_RESPAWN_TICKS"]) / 60
	var rally_hi: int = rally_lo * int(sim_consts.get("BROKE_WAIT_MAX_MULT", 1))
	Runner.T.ok(page.contains("%ds" % rally_lo),
		"the WAR CHEST page still quotes the %ds floor the rally starts on (got '%s')" % [rally_lo, page])
	Runner.T.ok(rally_hi != rally_lo and page.contains("%ds" % rally_hi),
		"...and the %ds ceiling it slows to in ENDLESS, so the clock is not sold as flat (got '%s')"
			% [rally_hi, page])
	# Derived, not typed — at BOTH copy sites. menu.gd ships the sentence twice
	# (_howto_large_entries' list row and _howto_page_warchest's body block); a
	# hand-typed "5s to 20s" in either one is exactly the drift this suite exists for.
	var menu_src := FileAccess.get_file_as_string("res://src/view/menu.gd")
	var rally_sites := 0
	var at := menu_src.find("rally puts you back")
	while at >= 0:
		rally_sites += 1
		# The format args sit within a few lines of the sentence at both sites; a
		# 400-char window is wide enough to reach them and far too narrow to catch
		# an unrelated const mention elsewhere on the page.
		var stmt := menu_src.substr(at, 400)
		Runner.T.ok(stmt.contains("BROKE_RESPAWN_TICKS") and stmt.contains("BROKE_WAIT_MAX_MULT"),
			"menu.gd rally-copy site #%d builds BOTH seconds from the sim consts, not from typed digits"
				% rally_sites)
		at = menu_src.find("rally puts you back", at + 1)
	Runner.T.eq(rally_sites, 2, "both shipped rally-copy sites were found by the scrape")


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


func test_every_deny_reason_the_sim_emits_has_view_wording() -> void:
	## A refusal that states the wrong cause is the loudest kind of view lie. The
	## view had TWO `"deny":` arms in one `match kind:` — the second was dead, so
	## the water-roll refusal fell through to the live arm's default and told the
	## player "NEED COINS" about a rule that has nothing to do with money. Pin the
	## shape (one arm) and the coverage (every `why` the sim can emit is worded).
	var view := _view_src()
	Runner.T.eq(view.count("\n\t\t\t\"deny\":\n"), 1,
		"exactly one \"deny\" arm in the event match — a second one is unreachable and its wording never runs")
	var sim_src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var re := RegEx.create_from_string("\"t\": \"deny\"[^}]*?\"why\": \"([a-z_]+)\"")
	var reasons := re.search_all(sim_src)
	Runner.T.ok(reasons.size() >= 6,
		"found the sim's deny reasons to check against (%d)" % reasons.size())
	for m in reasons:
		var why: String = m.get_string(1)
		Runner.T.ok(view.contains("\"%s\"" % why),
			"the view has wording for deny reason '%s' instead of falling through to NEED COINS" % why)


func test_supply_float_prints_the_delivered_quantity() -> void:
	## Same shape as the pickup_full_text ratchet above, for the buy/token_drop
	## float. BUY_FLOAT hardcoded "+30 AMMO" / "+4 GRENADES" — the CATALOGUE
	## quantity — while the sim clamps at the cap, so a +1 top-up at 11/12
	## grenades announced "+4 GRENADES". The literals must be gone, the formatter
	## must exist, and it must be CALLED (a def-only helper is the claim_label_slot
	## trap: green check, unchanged screen).
	var src := _view_src()
	Runner.T.ok(not src.contains("+30 AMMO"),
		"the catalogue ammo literal is gone from the view — the clamped count is printed instead")
	Runner.T.ok(not src.contains("+4 GRENADES"),
		"the catalogue grenade literal is gone from the view")
	var ms: Script = load("res://src/main.gd")
	Runner.T.ok(ms.has_method("buy_float_text"),
		"the supply float text is derived by buy_float_text(kind, n), not indexed straight out of BUY_FLOAT")
	if ms.has_method("buy_float_text"):
		Runner.T.eq(ms.call("buy_float_text", 0, 30), "+30 AMMO", "a full ammo delivery still reads +30")
		# The COUNT was already honest here; the NOUN was not. A clamped top-up of one
		# printed "+1 GRENADES" (see test_no_shipped_string_says_one_of_a_plural).
		Runner.T.eq(ms.call("buy_float_text", 1, 1), "+1 GRENADE", "a clamped top-up reads what it delivered, singular")
		Runner.T.eq(ms.call("buy_float_text", 1, 4), "+4 GRENADES", "a full delivery still reads the plural")
		Runner.T.eq(ms.call("buy_float_text", 3, 1), "AIRSTRIKE INBOUND",
			"a quantity-less kind ignores n rather than printing a number at it")
	Runner.T.ok(src.count("buy_float_text(") >= 3,
		"buy_float_text is wired into both float consumers, not just defined (%d sites)"
			% src.count("buy_float_text("))


func test_mast_telegraph_sleeps_with_the_shop() -> void:
	## The sim's mast hazard sleeps while the intermission shop is open (the
	## shop is sold threat-free). The VIEW must mirror that gate: a warn ring
	## or jet edge drawn during the breather telegraphs a hazard that cannot
	## hurt — the same lie in the opposite direction. Wiring scrape in this
	## suite's house style: the _draw_mast_hazard body must read the same
	## intermission state the sim's _step_mast_hazard now gates on.
	var src := _view_src()
	var start := src.find("func _draw_mast_hazard")
	Runner.T.ok(start >= 0, "found _draw_mast_hazard")
	if start < 0:
		return
	var end := src.find("\nfunc ", start + 1)
	Runner.T.ok(end > start, "the mast draw body is delimited by the next func")
	if end > start:
		Runner.T.ok(src.substr(start, end - start).contains("intermission_ticks"),
			"the mast telegraph sleeps while the shop is open — same gate as _step_mast_hazard")


# --- r4-menu #2: REDUCE MOTION's copy must not promise more than the floors deliver -----

func test_reduce_motion_copy_does_not_overclaim_past_its_own_floors() -> void:
	## main.gd deliberately keeps a floor under two motion effects even with REDUCE MOTION
	## on (main.gd:1264's blast-warp maxf(_motion, 0.25) and :12934's flash-alpha
	## maxf(_motion, 0.4) — both commented as intentional, "the strongest motion effect in
	## the game" / a dimmed-not-zeroed wash). The SETTING_HELP copy used to say "NO ...
	## FLASH" outright, which was simply false. This pins both halves so a floor edit
	## without a copy edit (or vice versa) goes red instead of quietly drifting apart again.
	var msrc := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(msrc.contains("maxf(_motion, 0.25)"),
		"the blast-warp motion floor still exists at its documented value")
	Runner.T.ok(msrc.contains("maxf(_motion, 0.4)"),
		"the flash-alpha motion floor still exists at its documented value")
	var help: String = GameMenu.setting_help("motion")
	Runner.T.ok(not help.contains("NO SHAKE, FLASH"),
		"REDUCE MOTION copy no longer claims FLASH is fully eliminated alongside SHAKE (%s)" % help)
	Runner.T.ok(help.contains("DAMPED") or help.contains("DAMPS"),
		"REDUCE MOTION copy says the flash/warp are damped, not removed (%s)" % help)


# --- R4: the fan's ammo tax is sold as pure upside ---------------------------

func test_fan_ammo_tax_is_disclosed_in_the_hint_copy() -> void:
	## sim_world.gd charges 1 ammo for the base shot, then an extra fan_cost
	## on top (1 for a LONE 3-round fan — Trench Gun or Triple alone — 2 for
	## the STACKED 5-round fan) — so 2 ammo/pull and 3 ammo/pull respectively,
	## not the "free extra pellets" the old hint copy implied. Prove the
	## sim's real drain first, then hold the pickup copy to it.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p := sim.players[0]
	p["spread_ticks"] = 200
	var ammo0: int = p["mg_ammo"]
	var inp := SimInput.new()
	inp.aim_y = -256
	inp.fire = true
	sim.step([inp])
	Runner.T.eq(ammo0 - p["mg_ammo"], 2, "a lone 3-round fan (Trench Gun or Triple) costs 2 ammo/pull")

	var sim2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	var p2 := sim2.players[0]
	p2["spread_ticks"] = 200
	p2["triple"] = true
	var ammo1: int = p2["mg_ammo"]
	var inp2 := SimInput.new()
	inp2.aim_y = -256
	inp2.fire = true
	sim2.step([inp2])
	Runner.T.eq(ammo1 - p2["mg_ammo"], 3, "the stacked 5-round fan costs 3 ammo/pull")

	var src := _view_src()
	Runner.T.ok(src.contains("2 AMMO A PULL"),
		"the Trench Gun / Triple Shot hint copy must state the real per-pull ammo cost")
	Runner.T.ok(src.contains("5 FOR 3"),
		"the stacked-fan hint copy must state the real 3-ammo cost for the 5-way fan")


# --- R4: getting shot boils a second off the tank, and the only feedback said "safe" ---

func test_manned_tank_hit_gets_its_own_cue_not_the_wall_plink() -> void:
	## Enemy fire hitting a MANNED tank hull is cover too, and the ride PAYS
	## for it: TANK_HIT_FUEL_COST comes off hk["fuel"] (sim_world.gd
	## _step_enemy_bullets), but the event fired was the SAME bare
	## {"t":"armor_block"} every other deflection uses — captioned "[ROUNDS
	## BOUNCING OFF ARMOR]" at the exact moment the ride is being spent. Same
	## Main.new()/_consume_events() idiom as the veteran-armor sibling test.
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var stub := Main.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN
	stub.sim = sim
	var tx: int = 100 * Fixed.ONE
	var ty: int = sim.camera_top + 200 * Fixed.ONE
	sim.tanks.append({"x": tx, "y": ty, "alive": true, "occupant": 0, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "fire_cd": 0})
	sim.events = [{"t": "armor_block", "x": tx, "y": ty}]
	stub._consume_events()
	var cue := false
	for fx in stub._fx:
		if fx.get("kind", "") == "floattext" and String(fx.get("text", "")).contains("-1S"):
			cue = true
			break
	Runner.T.ok(cue, "a manned-hull block must float the -1s fuel cost, not just spark silently")
	# Negative: an UNMANNED hulk-as-cover block is the ordinary wall grammar —
	# no crew is paying anything, so no fuel-loss cue should fire.
	var stub2 := Main.new()
	stub2._menu.mode = GameMenu.Mode.HIDDEN
	var sim2 := SimWorld.new(0xC0FFEE, 1, "campaign")
	stub2.sim = sim2
	sim2.tanks.append({"x": tx, "y": ty, "alive": true, "occupant": -1, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "fire_cd": 0})
	sim2.events = [{"t": "armor_block", "x": tx, "y": ty}]
	stub2._consume_events()
	var cue2 := false
	for fx in stub2._fx:
		if fx.get("kind", "") == "floattext" and String(fx.get("text", "")).contains("-1S"):
			cue2 = true
			break
	Runner.T.ok(not cue2, "an unmanned hulk taking cover fire pays no fuel — it must not get the fuel cue")
	stub.free()
	stub2.free()


# --- R4: arena_crack has no visual card -----------------------------------

func test_arena_crack_gets_a_visual_card() -> void:
	## _crack_bridge_span (sim_world.gd) fires on each gunship HP-third
	## crossing: a bridge slab the player may be hiding behind disappears and
	## a new one pops in nearby. The view's response used to be sound-only
	## (_EVENT_SOUND's "arena_crack" row) — no fx, no decal, no shake, unlike
	## every sibling geometry-mutation event (rock_crater, lane_seal,
	## supply_pod, cover_crack all get a full card).
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	var stub := Main.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN
	stub.sim = sim
	var cx: int = 150 * Fixed.ONE
	var cy: int = sim.camera_top + 300 * Fixed.ONE
	var scorch0: int = stub._scorch.size()
	sim.events = [{"t": "arena_crack", "x": cx, "y": cy}]
	stub._consume_events()
	var tex_card := false
	for fx in stub._fx:
		if fx.get("kind", "") == "tex" and fx.get("tex", "") == "fx_groundbreak":
			tex_card = true
			break
	Runner.T.ok(tex_card, "arena_crack must draw the fx_groundbreak card, not fire silently")
	Runner.T.ok(stub._scorch.size() > scorch0, "arena_crack must leave a permanent scorch like its siblings")
	stub.free()


# --- R5: teach cards must not sell verbs the sim no longer honours -----------

func test_ghillie_card_does_not_sell_a_grenade_flush() -> void:
	## Cloaked ghillies skip blast (sim_world._explode). "FLUSH IT OUT" was a lie.
	var card: String = String(Main._KIND_TEACH["ghillie"]).to_upper()
	Runner.T.ok(not card.contains("FLUSH"),
		"ghillie first-sighting must not say FLUSH after cloak blast-immunity: %s" % card)
	Runner.T.ok(card.contains("LASER") or card.contains("CLOSE"),
		"ghillie card still names the real window: %s" % card)


func test_last_stand_banner_is_plated() -> void:
	## Foundry floor is orange-red; unplated LAST STAND ink washed out.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("LAST STAND — NO REVIVES")
	Runner.T.ok(at > 0, "the last-stand banner string still exists")
	var window := src.substr(maxi(0, at - 280), 360)
	Runner.T.ok(window.contains("_banner_plate"),
		"LAST STAND goes through _banner_plate, not raw Art.text_center:\n%s" % window)


func test_river_clock_is_view_owned_not_gpu_time() -> void:
	var sh := FileAccess.get_file_as_string("res://src/view/water.gdshader")
	Runner.T.ok(sh.contains("uniform float clock"), "water.gdshader exposes a view clock")
	Runner.T.ok(not sh.contains("(TIME + phase)"),
		"no remaining TIME+phase river animation")
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("set_shader_parameter(\"clock\""),
		"_sync_water pushes the view clock")
	Runner.T.ok(src.contains("_water_clock"),
		"main owns _water_clock and advances it only off hit-stop")


func test_priced_crate_plate_follows_the_cost_not_the_mode() -> void:
	## Campaign/arcade stamp priced crates too. Gating the hazard plate on
	## endless left those sitting as unlabelled boxes.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("pk.get(\"cost\", 0) > 0")
	Runner.T.ok(at > 0, "the crate-cost gate still exists")
	var window := src.substr(at, 180)
	Runner.T.ok(not window.contains("sim.mode == \"endless\""),
		"the supply plate follows cost, not mode:\n%s" % window)
	Runner.T.ok(src.contains("Art.warn(Color(1.0, 0.45, 0.35))"),
		"unaffordable crate prices go through Art.warn, not a raw red")


func test_friendly_airstrike_does_not_tell_you_to_run() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("AIRSTRIKE INBOUND — KEEP FIRING"),
		"the inbound banner tells you to keep firing, not to flee")
	Runner.T.ok(src.contains("KEEP FIRING  %.1fs"),
		"the countdown rail says KEEP FIRING")
	var sfx := FileAccess.get_file_as_string("res://src/view/sfx.gd")
	Runner.T.ok(not sfx.contains("clear the area"),
		"spotter VO no longer teaches the player to flee their own strike")


func test_concussion_shader_uses_the_view_clock() -> void:
	var sh := FileAccess.get_file_as_string("res://src/view/screen_fx.gdshader")
	Runner.T.ok(sh.contains("uniform float clock"), "concussion overlay has a view clock")
	Runner.T.ok(not sh.contains("sin(TIME") and not sh.contains("cos(TIME"),
		"concussion overlay does not animate off GPU TIME")


func test_concussion_warp_spares_the_downed_soldier() -> void:
	# The radial blur taps are distance-scaled by construction (`to_center * i`),
	# so they are 0 px at the exact screen centre and grow outward. The other warp
	# channels were NOT. `normalize()` throws distance away, so the chroma split had
	# a fixed UV magnitude of 0.0045 * amt at EVERY pixel (at the shipped SOLO
	# knockdown peak — down_self_scale(partner_standing=false) returns 1.0, main.gd,
	# NOT the 0.7 of a flak-vest break — and the 640x360 logical frame, that is
	# 5.76 px of R/B separation, nonzero even at the exact centre); the wobble was a
	# fixed whole-image shove (2.82 px x / 1.58 px y at amt 1.0, |wob| <= 2); the
	# green channel was taken from the blur unconditionally; and the fold pulled all
	# of it into the final colour at a flat 50% everywhere. Net effect: the fallen
	# soldier came out doubled and smeared at the exact moment the player is
	# squinting at him to see whether he got back up.
	#
	# The ramp must be anchored on HIM, not on the middle of the frame — this is the
	# FOCUS-ANCHORED ramp, NOT the earlier screen-centred revision (Backlog #44),
	# which measured 0.04 edge retention at x=60. There is no horizontal camera in
	# this game — main._to_screen() has no x term at all — so his world x IS his
	# screen x over the 16..624 play field and he is routinely 200+ px off centre.
	# Measured on this tree: a 5-seed player_down census logged 135 events spanning
	# screen-UV x 0.025..0.975, with 43% (58/135) within 0.1 of centre — a
	# screen-centred ramp is a coin flip. test_concussion_focus_is_pushed_from_the_player()
	# pins the main.gd half; this one pins the shader half.
	#
	# Source-text ratchet by necessity: the shader only exists on the GPU, and the
	# pixel-level proof lives in tools/probe_concussion_hud.gd (GL-only — it fails
	# closed under --headless with "PROBE UNUSABLE", and `grep -rln` finds it
	# referenced by nothing in .github/workflows/, tools/run_tests.sh or
	# tests/run_tests.gd, so it CANNOT be gated in CI; that is a banked gap, and it
	# is why the numeric arms in the sibling test below exist). MEASURED there at
	# concussion 1.0 — exposure-matched strong edges in the box around the LIVE
	# soldier, swept across the play field. Shipped column quoted as a
	# median of 3 runs (Apple M4 Max / OpenGL 4.1 Metal); unlike the controls it
	# does NOT reproduce cell-for-cell, it spreads ~0.98..1.12:
	#           no ramp   ramp @ vec2(0.5)   ramp @ focus
	#   x=40     0.00          0.01             1.01
	#   x=320    0.09          0.98             1.07
	#   x=600    0.00          0.04             1.03
	# Across all 9 shipped-column samples the worst single sample 0.98 — that, not
	# the median, is what the probe's 0.85 floor has to clear.
	# Both left-hand columns are CONTROLS that were actually run and actually
	# failed. This gate is what makes a silent revert impossible; the probe is what
	# proves the pixels.
	var sh := FileAccess.get_file_as_string("res://src/view/screen_fx.gdshader")
	Runner.T.ok(sh.contains("uniform vec2 focus"),
		"the concussion pass takes a focus point rather than assuming screen centre")
	Runner.T.ok(sh.contains("float dist = length(focus - uv);"),
		"the ramp's distance is measured from the focus point")
	Runner.T.ok(not sh.contains("float dist = length(to_center);"),
		"no screen-centred distance survives as the ramp's input")
	Runner.T.ok(sh.contains("float ramp = smoothstep("),
		"the concussion pass derives a peripheral ramp")
	var ramp_line := ""
	for line in sh.split("\n"):
		if line.contains("float ramp = smoothstep("):
			ramp_line = line
	Runner.T.ok(ramp_line.contains("dist"),
		"the peripheral ramp is a function of the distance from the focus (got \"%s\")"
			% ramp_line.strip_edges())
	# TWO consumers, opposite intents: _blast_warp rides this same shader and WANTS
	# its punch centred on the detonation, so the ramp is gated rather than silently
	# rebalancing the heat-shock. `spare` is that gate; at 0 the maths is bit-for-bit
	# the pre-ramp path. Without this the fix quietly changes a second effect.
	Runner.T.ok(sh.contains("uniform float spare"),
		"the peripheral ramp is gated, so the blast heat-shock keeps its centred punch")
	Runner.T.ok(sh.contains("float periph = mix(1.0, ramp, spare);"),
		"spare crossfades between the flat whole-frame warp and the focus ramp")

	Runner.T.ok(sh.contains("0.0045 * amt * periph"),
		"the chromatic split is ramped, not applied at full strength on the soldier")
	Runner.T.ok(not sh.contains("(0.0045 * amt)"),
		"no distance-independent chroma magnitude survives")
	Runner.T.ok(sh.contains("0.0022 * amt * periph"),
		"the underwater wobble is ramped, not a whole-image displacement")
	Runner.T.ok(not sh.contains("vec2(wob) * 0.0022 * amt;"),
		"no distance-independent wobble amplitude survives")
	Runner.T.ok(sh.contains("mix(col, blur, 0.5 * periph)"),
		"the soft-blur fold weight is ramped")
	Runner.T.ok(not sh.contains("mix(col, blur, 0.5)"),
		"no flat 50% blur fold survives to carry the smear onto the soldier")
	# The fold has two halves: the mix() above, and the green channel, which is
	# read straight OUT of `blur`. Ramping only the mix leaves the taps' vertical
	# reach landing on the soldier at full strength in G — a soldier "spared" in
	# R and B only, which looks fixed in a diff and is still smeared on screen.
	Runner.T.ok(sh.contains("mix(texture(screen_tex, wob_uv).g, blur.g, periph)"),
		"the green channel is ramped toward the unblurred sample, not taken from the blur outright")
	Runner.T.ok(not sh.contains("\t\t\tblur.g,"),
		"no unconditional blur.g survives as the green channel")
	# The VIGNETTE deliberately does NOT follow the focus. A darkening that chased
	# the soldier around the frame reads as a wandering black blob; the warp is
	# aimed at the player, the grade frames the screen. Measured: luma is
	# byte-comparable before and after this change in every region sampled (left
	# edge 53.46 -> 53.39, top strip 62.69 -> 62.69 of 255).
	Runner.T.ok(sh.contains("float vig = 1.0 - smoothstep(0.3, 0.75, length(to_center));"),
		"the vignette stays screen-centred instead of chasing the focus point")
	Runner.T.ok(not sh.contains("float vig = 1.0 - periph;"),
		"the vignette is not coupled to the moving ramp")

	# Guard the parts that were already correct, so a later 'simplification' of the
	# ramp cannot take the safety paths with it.
	Runner.T.ok(sh.contains("if (concussion < 0.001)"),
		"the bit-exact pass-through below 0.001 is intact")
	Runner.T.ok(sh.contains("mix(clean, col, amt)"),
		"the master blend on concussion amount is intact")
	Runner.T.ok(sh.contains("to_center * (float(i) * 0.018 * amt)"),
		"the radial blur taps still march toward the true screen centre — that is the disorientation, and it was never the defect")


func test_concussion_focus_is_pushed_from_the_player() -> void:
	# The shader half of the fix is inert unless main.gd actually pushes a focus.
	# Left unwired, `focus` sits at its vec2(0.5) default and the ramp degrades to
	# exactly the screen-centred version the probe measured at keep 0.01 / 0.04 at
	# the edge poses — green diff, unchanged screen. So pin the wiring too.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains('_screen_fx_mat.set_shader_parameter("focus", _concussion_focus_uv())'),
		"the per-frame uniform push feeds the shader a focus point")
	Runner.T.ok(src.contains('_screen_fx_mat.set_shader_parameter("spare",'),
		"the per-frame uniform push also sets the ramp gate")
	# The focus must come from the SHIPPED world->screen seam. A second copy of the
	# camera maths here is how the focus drifts off the soldier the first time
	# _to_screen changes.
	Runner.T.ok(src.contains("func _concussion_focus_uv() -> Vector2:"),
		"the focus resolver exists")
	var body := src.get_slice("func _concussion_focus_uv() -> Vector2:", 1).get_slice("\nfunc ", 0)
	Runner.T.ok(body.contains("_to_screen(p[\"x\"], p[\"y\"])"),
		"the focus routes through main._to_screen, not a private copy of the camera maths")
	Runner.T.ok(body.contains("concussion_focus_uv("),
		"the resolver delegates the arithmetic to the pure static helper the numeric arm can call")
	Runner.T.ok(body.contains("sim.players[_concussion_p]"),
		"the focus is the player named by _concussion_p, not a hardcoded index")
	# Both beats that raise _concussion must also say WHOSE it is, or 2P aims the
	# ramp at the wrong soldier. down_self_scale already distinguishes them.
	Runner.T.ok(src.contains("_concussion_p = int(ev.get(\"p\", 0))"),
		"the concussion triggers record which player the beat belongs to")
	var trigger_count := src.count("_concussion_p = int(ev.get(\"p\", 0))")
	Runner.T.eq(trigger_count, 2,
		"both concussion sources (player_down and vest_break) name their player")
	# The BLAST channel is the other consumer of this shader and must not have been
	# silently rebalanced: it needs spare -> 0 when it is the louder one.
	Runner.T.ok(src.contains("var warp := _blast_warp * motion_gate"),
		"the blast heat-shock is scaled separately so the ramp gate can tell the two channels apart")
	Runner.T.ok(src.contains("clampf((conc - warp) / amt, 0.0, 1.0)"),
		"spare falls to 0 as the blast heat-shock takes over, restoring its un-ramped whole-frame punch")

	# --- NUMERIC ARMS. Everything above is a grep; a grep cannot tell a focus that
	# tracks the soldier from one that returns vec2(0.5) with the right spelling.
	# Both helpers below are pure statics precisely so this headless suite can call
	# them (the pixel claim needs GL and is banked in the sibling test's header).
	var ms: Script = load("res://src/main.gd")
	Runner.T.ok(ms.has_method("concussion_focus_uv"),
		"the focus arithmetic is a pure static, callable without a scene tree")
	Runner.T.ok(ms.has_method("concussion_spare"),
		"the ramp gate is a pure static, callable without a scene tree")
	if not ms.has_method("concussion_focus_uv") or not ms.has_method("concussion_spare"):
		return
	# EXHAUSTIVE 1px sweep of the play field. The measured player_down census that
	# motivates this spanned screen-UV x 0.025..0.975 over 135 events on 5 seeds;
	# WORLD_LEFT..WORLD_RIGHT is 16..624 px, so this window strictly CONTAINS the
	# measured one — the ratchet is wider than the defect, not narrower. The helper
	# takes the SCREEN point on purpose (see its docstring: _to_screen stays the one
	# copy of the camera maths), and _to_screen has no x term, so a player's world x
	# IS the sx swept here.
	var u_min := 2.0
	var u_max := -1.0
	var uv_err := 0
	for sx in range(int(SimWorld.WORLD_LEFT / Fixed.ONE), int(SimWorld.WORLD_RIGHT / Fixed.ONE) + 1):
		var uv: Vector2 = ms.concussion_focus_uv(Vector2(float(sx), 180.0))
		if absf(uv.x - clampf(float(sx) / 640.0, 0.0, 1.0)) > 0.0001:
			uv_err += 1
		if absf(uv.y - 0.5) > 0.0001:
			uv_err += 1
		u_min = minf(u_min, uv.x)
		u_max = maxf(u_max, uv.x)
	Runner.T.eq(uv_err, 0,
		"the focus UV is the player's own screen x over the whole play field (%d mismatches)" % uv_err)
	Runner.T.ok(maxf(absf(u_min - 0.5), absf(u_max - 0.5)) >= 0.45,
		("the focus actually TRACKS the soldier across the field — it is not vec2(0.5)"
			+ " wearing a new name (u spans %.3f..%.3f, max offset from centre %.3f)")
			% [u_min, u_max, maxf(absf(u_min - 0.5), absf(u_max - 0.5))])
	# spare: 1.0 = pure concussion (full focus ramp), 0.0 = blast owns the frame.
	Runner.T.ok(absf(float(ms.concussion_spare(1.0, 0.0)) - 1.0) < 0.0001,
		"with no blast, the ramp is fully open (spare 1.0)")
	Runner.T.ok(absf(float(ms.concussion_spare(1.0, 1.0))) < 0.0001,
		"a blast at the concussion level restores the flat whole-frame punch (spare 0.0)")
	Runner.T.ok(absf(float(ms.concussion_spare(0.4, 0.9))) < 0.0001,
		"a blast LOUDER than the concussion also yields spare 0.0, never a negative")
	var prev := 2.0
	var mono_err := 0
	for i in 21:
		var w := float(i) / 20.0
		var s := float(ms.concussion_spare(1.0, w))
		if s > prev + 0.0001:
			mono_err += 1
		prev = s
	Runner.T.eq(mono_err, 0,
		"spare is monotone non-increasing as the blast grows louder (%d inversions)" % mono_err)


func test_dry_shrub_and_tumbleweed_are_not_outlined() -> void:
	Runner.T.ok(not Art.outlined("dry_shrub"), "dry_shrub is a tuft, not a 3-pass rim")
	Runner.T.ok(not Art.outlined("tumbleweed"), "tumbleweed is a tuft, not a 3-pass rim")


func test_r8_first_mint_teaches_how_to_spend_a_commendation() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains('_hint("commendation", "COMMENDATION — SPEND IT FROM THE SUPPLY WHEEL")'),
		"first mint queues a spend teach on the supply wheel")


func test_r8_deep_ford_current_gets_a_named_banner() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("_current_told"), "once-per-run CURRENT latch exists")
	Runner.T.ok(src.contains("CURRENT — THE RIVER SHOVES YOU"),
		"first contact with a deep-ford shove is named")
	Runner.T.ok(src.contains("sim._ford_current(p[\"y\"])"),
		"the teach keys off the same helper the sim uses to shove")


func test_r8_mast_warn_names_the_overheat() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains('_hint("mast_overheat", "MAST OVERHEAT — VACATE THE ORBIT", true)'),
		"first mast warn names the threat and the vacate")


func test_r8_reduce_motion_gates_wedge_mine_lane_observer() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("rpulse := 1.0 if _motion < 0.5 else (0.35 + 0.35 * sin(_rear_wedge_t * 12.0))"),
		"rear-warn wedge is steady under reduce-motion")
	Runner.T.ok(src.contains("mb := 0.0 if _motion < 0.5 else Art.pulse(0.1)"),
		"mine telegraph pins radius/alpha under reduce-motion")
	Runner.T.ok(src.contains("pulse := 0.22 if _motion < 0.5 else (0.10 + 0.20 * absf(sin(float(Engine.get_physics_frames()) * 0.35)))"),
		"lane-seal warn is a steady fill under reduce-motion, not a 3.3 Hz strobe")
	Runner.T.ok(src.contains("sweep := 0.0 if _motion < 0.5 else float(Engine.get_physics_frames()) * 0.09"),
		"observer radar sweep holds still under reduce-motion")
	Runner.T.ok(src.contains("if _motion >= 0.5:\n\t\top.y += sin(float(Engine.get_physics_frames()) * 0.07) * 0.8"),
		"observer bob is gated, not an always-on sine")


# --- Endless miniboss fly-in: the drawn hull vs the damageable hitbox ----------
#
# `_draw_one_gunship` paints the approaching miniboss along an authored diagonal
# ramp (top-right -> arrival) while `_bullet_hits_boss` / `_explode` tested the
# ARRIVAL point and refused damage outright for the whole 420-tick approach. Two
# separate lies on one entity: the sprite is not where the hitbox is, and the
# hitbox is not live. Every ratchet below samples a 720-tick window against a
# 420-tick defect, so the sample can never sit entirely inside the healthy part.

# The approach ramp, DERIVED from the sim's published constants rather than
# restated. Hard-coding 150.0 / -55.0 here made this file a second copy of the
# curve: re-tune BOSS_FLYIN_DX and the ratchet would have kept measuring the old
# one. (Sign: boss_flyin_offset returns -DY, the hull comes in from ABOVE.)
const FLYIN_VIEW_DX := float(SimWorld.BOSS_FLYIN_DX) * PX
const FLYIN_VIEW_DY := -float(SimWorld.BOSS_FLYIN_DY) * PX


func _flyin_boss_sim(pt: int) -> SimWorld:
	## A fresh endless world whose wave-5 miniboss is pinned at `phase_t == pt`.
	var sim := SimWorld.new(7, 1, "endless")
	sim.wave = 4
	sim._start_wave()
	Runner.T.ok(not sim.endless_boss.is_empty(), "wave 5 fields an endless miniboss")
	sim.endless_boss["phase_t"] = pt
	sim.events.clear()
	return sim


func _flyin_drawn_px(sim: SimWorld) -> Vector2:
	## Screen-space centre the VIEW paints the hull at, in px.
	var pt: int = sim.endless_boss["phase_t"]
	var eta: float = 1.0 + float(pt) / float(SimWorld.BOSS_FLYIN_TICKS) if pt < 0 else 1.0
	var gx: float = sim.endless_boss["x"] * PX
	var gy: float = (sim.endless_boss["gate_y"] - SimWorld.BOSS_Y_OFFSET) * PX
	return Vector2(gx + (1.0 - eta) * FLYIN_VIEW_DX, gy + (1.0 - eta) * FLYIN_VIEW_DY)


func _flyin_samples() -> Array[int]:
	## Every 10th tick across the whole approach AND a full engaged cycle:
	## 720 ticks of window against a 420-tick defect.
	var out: Array[int] = []
	var t := -SimWorld.BOSS_FLYIN_TICKS
	while t < SimWorld.BOSS_CYCLE_TICKS:
		out.append(t)
		t += 10
	return out


func test_endless_boss_is_hittable_wherever_it_is_drawn() -> void:
	## HEAD: 42/42 fly-in samples returned hit=false with an empty event list and
	## hp unchanged, while the view drew a helicopter the player was emptying a
	## magazine into. Every OTHER damage refusal in the sim (bunkers, sandbags,
	## tank hulks, rocks, shield front-arc, enemy armour, closed colossus core)
	## already emits `armor_block`; this was the last silent one in the file.
	var bullet_ok := 0
	var blast_ok := 0
	var samples := _flyin_samples()
	for pt in samples:
		# --- bullet ---
		var sim := _flyin_boss_sim(pt)
		var hp0: int = sim.endless_boss["hp"]
		var at := _flyin_drawn_px(sim)
		var b := {"x": int(at.x * Fixed.ONE), "y": int(at.y * Fixed.ONE)}
		var hit: bool = sim._bullet_hits_boss(b)
		var got_ev := false
		for e in sim.events:
			if e["t"] == "boss_hit":
				got_ev = true
		if hit and got_ev and sim.endless_boss["hp"] == hp0 - 1:
			bullet_ok += 1
		# --- explosive family (grenade / airburst / barrel / mine) ---
		var sim2 := _flyin_boss_sim(pt)
		var hp2: int = sim2.endless_boss["hp"]
		var at2 := _flyin_drawn_px(sim2)
		sim2._explode(int(at2.x * Fixed.ONE), int(at2.y * Fixed.ONE))
		var got2 := false
		for e in sim2.events:
			if e["t"] == "boss_hit":
				got2 = true
		if got2 and sim2.endless_boss["hp"] < hp2:
			blast_ok += 1
	Runner.T.eq(bullet_ok, samples.size(),
		"a round on the drawn hull damages the miniboss at every sampled tick (%d/%d)"
			% [bullet_ok, samples.size()])
	Runner.T.eq(blast_ok, samples.size(),
		"a blast on the drawn hull damages the miniboss at every sampled tick (%d/%d)"
			% [blast_ok, samples.size()])


func test_flyin_sprite_sits_on_its_own_hitbox() -> void:
	## The disc must MOVE with the sprite, not merely grow to swallow both. HEAD
	## drew the hull up to 159.8 px from the arrival point it tested — 8.0x
	## BOSS_HIT_RADIUS — so a fix that inflated the radius instead of relocating
	## the disc would still be a lie. Assert both edges: a round ON the drawn hull
	## registers (test_endless_boss_is_hittable_wherever_it_is_drawn), and a round
	## 1.5 radii PAST it, back along the approach ramp, does not.
	var divorce := 0.0
	var sep := 0.0
	var far_misses := 0
	var samples := _flyin_samples()
	for pt in samples:
		var sim := _flyin_boss_sim(pt)
		var arrival := Vector2(sim.endless_boss["x"] * PX,
			(sim.endless_boss["gate_y"] - SimWorld.BOSS_Y_OFFSET) * PX)
		var drawn := _flyin_drawn_px(sim)
		divorce = maxf(divorce, drawn.distance_to(arrival))
		# The sim's live hit-disc centre, straight off the shared helper.
		var hoff: Array = SimWorld.boss_flyin_offset(pt)
		var disc := Vector2(float(sim.endless_boss["x"] + int(hoff[0])) * PX,
			float(sim.endless_boss["gate_y"] - SimWorld.BOSS_Y_OFFSET + int(hoff[1])) * PX)
		sep = maxf(sep, drawn.distance_to(disc))
		# 1.5 radii further UP the ramp than the hull — empty sky at every tick.
		var ramp := Vector2(FLYIN_VIEW_DX, FLYIN_VIEW_DY).normalized()
		var off_hull := drawn + ramp * (SimWorld.BOSS_HIT_RADIUS * PX * 1.5)
		var hp0: int = sim.endless_boss["hp"]
		var hit: bool = sim._bullet_hits_boss({"x": int(off_hull.x * Fixed.ONE),
			"y": int(off_hull.y * Fixed.ONE)})
		if not hit and sim.endless_boss["hp"] == hp0:
			far_misses += 1
	Runner.T.eq(far_misses, samples.size(),
		"empty sky 1.5 radii off the drawn hull stays a miss (%d/%d) — the disc MOVED, it did not grow"
			% [far_misses, samples.size()])
	Runner.T.ok(divorce > SimWorld.BOSS_HIT_RADIUS * PX,
		"sanity: the approach really does travel far from the arrival point (%.1f px vs a %.1f px radius)"
			% [divorce, SimWorld.BOSS_HIT_RADIUS * PX])
	# --- Source half ---------------------------------------------------------
	# Everything above measures a DERIVATION of the ramp, not main.gd's own draw
	# call, so on its own it cannot see the view drifting off the helper it reads:
	# `int(foff[0]) * 2` re-creates the full 159.8 px divorce, carries none of the
	# banned literals, and sails past a name-only grep. So pin the whole placement
	# EXPRESSION, character for character — the offset is consumed as-is or this
	# goes red.
	var view := _view_src()
	var branch := view.substr(view.find("func _draw_one_gunship"))
	branch = branch.substr(0, branch.find("\tvar bpos := _to_screen"))
	Runner.T.ok(branch.contains("boss_flyin_offset"),
		"the fly-in draw branch positions the hull from SimWorld.boss_flyin_offset")
	Runner.T.ok(branch.contains("var apos := _to_screen(boss[\"x\"] + int(foff[0]),\n"
			+ "\t\t\tboss[\"gate_y\"] - SimWorld.BOSS_Y_OFFSET + int(foff[1]))"),
		"the hull is drawn at EXACTLY the sim's offset hull point — no arithmetic on foff beyond int()")
	var span := branch.substr(branch.find("var foff:"))
	span = span.substr(0, span.find("_spr(body_tex, apos"))
	for bad in ["foff[0] *", "foff[0] +", "foff[0] -", "foff[0] /",
			"foff[1] *", "foff[1] +", "foff[1] -", "foff[1] /"]:
		Runner.T.ok(not span.contains(bad),
			"no arithmetic ('%s') is applied to the sim's fly-in offset before drawing" % bad)
	for lit in ["150.0", "55.0", "420.0", "420"]:
		Runner.T.ok(not branch.contains(lit),
			"the fly-in draw branch carries no restated '%s' ramp literal" % lit)
	# Numeric half of R2: the point the view is pinned to and the point the sim
	# tests are the SAME point at every sampled tick (0.0 px, vs 159.8 px on HEAD).
	Runner.T.ok(sep <= SimWorld.BOSS_HIT_RADIUS * PX,
		"worst drawn-hull vs hit-disc separation is %.1f px, inside the %.1f px hit radius"
			% [sep, SimWorld.BOSS_HIT_RADIUS * PX])


func test_flyin_bar_does_not_name_an_act_the_sim_refuses() -> void:
	## The fly-in now draws the top-center boss bar for the whole 420-tick approach
	## (it used to leave the slot it claimed empty). That bar names the boss's ACT,
	## and `_step_one_boss` returns before any firing while `phase_t < 0` — "the
	## gunship holds its fire during the approach". So borrowing act one's name
	## ("STRAFING RUN") for the approach puts a lie in the highest-stakes read on
	## screen for 7.00 s. Sampled across the same 720-tick window as its siblings.
	var strafe: String = Main.GUNSHIP_PHASE_NAMES[0]
	var bad := 0
	var good := 0
	var approach := 0
	var engaged := 0
	for pt in _flyin_samples():
		var lbl: String = Main.gunship_phase_label("GUNSHIP", pt)
		if pt < 0:
			approach += 1
			if not lbl.contains(strafe):
				bad += 0
			else:
				bad += 1
		elif pt < SimWorld.BOSS_STRAFE_TICKS:
			engaged += 1
			if lbl.contains(strafe):
				good += 1
	Runner.T.eq(bad, 0,
		"the approach bar never names the strafing run the sim refuses to perform (%d/%d samples did)"
			% [bad, approach])
	Runner.T.eq(good, engaged,
		"once engaged, the bar DOES name act one (%d/%d samples)" % [good, engaged])
	# One vocabulary, two surfaces: the spawn banner says GUNSHIP INBOUND, so the
	# bar under it must not say something else about the same 7 s.
	var inbound: String = Main.gunship_phase_label("GUNSHIP", -SimWorld.BOSS_FLYIN_TICKS)
	Runner.T.ok(inbound.contains("INBOUND"),
		"the approach bar reads INBOUND, matching the spawn banner (got '%s')" % inbound)
	Runner.T.ok(_view_src().contains("show_banner(\"GUNSHIP INBOUND\""),
		"the spawn banner this shares its vocabulary with is still worded GUNSHIP INBOUND")


func test_gunship_warning_precedes_its_approach() -> void:
	## HEAD: the `endless_boss` warning fired on the tick the gunship ARRIVED —
	## 420 ticks (7.0 s) after it entered the screen, i.e. the "incoming" card
	## landed once the thing was already overhead.
	var sim := SimWorld.new(7, 1, "endless")
	sim.wave = 4
	sim.events.clear()
	sim._start_wave()
	var found := false
	for e in sim.events:
		if e["t"] == "endless_boss":
			found = true
	Runner.T.ok(found, "the endless_boss warning is emitted on the SPAWN tick")
	Runner.T.ok(sim.endless_boss["phase_t"] <= -SimWorld.BOSS_FLYIN_TICKS + 1,
		"...with the whole approach still ahead (phase_t %d)" % int(sim.endless_boss["phase_t"]))
	# ...and never a second time at arrival.
	var late := 0
	for i in SimWorld.BOSS_FLYIN_TICKS + 5:
		sim.events.clear()
		sim._step_one_boss(sim.endless_boss)
		for e in sim.events:
			if e["t"] == "endless_boss":
				late += 1
	Runner.T.eq(late, 0, "the warning is not re-emitted at arrival")


func test_no_damage_path_gates_on_flyin_phase() -> void:
	## Pins the CLASS in source so it cannot be satisfied cosmetically: neither
	## damage seam may branch on the fly-in phase again. HEAD: 2 occurrences.
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	for fn in ["_bullet_hits_boss", "_explode"]:
		var body := src.substr(src.find("func %s(" % fn))
		body = body.substr(0, body.find("\n\nfunc "))
		var bad := 0
		for line in body.split("\n"):
			var code: String = line.strip_edges()
			if code.begins_with("#"):
				continue
			if not code.contains("phase_t"):
				continue
			for op in [">=", "<=", "==", "!=", ">", "<"]:
				if code.contains("phase_t\"] %s" % op) or code.contains("phase_t %s" % op):
					bad += 1
					break
		Runner.T.eq(bad, 0, "%s carries no fly-in phase gate (%d found)" % [fn, bad])


func test_flyin_rewards_tracking_not_the_arrival_point() -> void:
	## The balance the fix creates, pinned — and it is NOT "the approach survives".
	## MEASURED on this tree, driving `main.demo_input` on a real
	## `SimWorld.new(seed, 1, "endless")` from tick 0 to the wave-5 miniboss,
	## 7 seeds (`hp_max` 40 in all of them):
	##   seed  7  fielded t=2098  hp@arrival  8/40   (32 landed during the approach)
	##   seed 11  fielded t=2387  DESTROYED mid-approach at phase_t = -95
	##   seed 23  never fields a miniboss inside 8 minutes
	##   seed 42  fielded t=2209  hp@arrival 31/40
	##   seed 55  fielded t=1835  hp@arrival 38/40
	##   seed  3  fielded t=2217  hp@arrival 15/40
	##   seed 99  fielded t=1986  DESTROYED mid-approach at phase_t = -16
	## So: 6 seeds field it, 2 of those 6 kill it before it lands, and the median
	## hp@arrival across the 4 that do land is 23/40. The approach is genuinely
	## deletable — that is the intended skill payoff, and it is why the death block
	## in `_damage_boss` now has to place its wreck FX by `boss_flyin_offset`
	## (see test_flyin_death_fx_land_on_the_wreck_not_the_pad). What must stay
	## true is that the damage costs TRACKING.
	## (Instrument limit: those are the SHIPPED BOT's numbers, open-loop aim — read
	## them as "a competent lane, not a human's best", per sector_probe.gd:12-20.)
	##
	## A shooter who keeps holding the arrival point — which is exactly what the
	## pre-fix hitbox rewarded, and what a "just widen the radius" fix would keep
	## rewarding — must land nothing while the hull is more than one radius away
	## from it.
	var tracked := 0
	var arrival_missed := 0
	var arrival_eligible := 0
	var samples := _flyin_samples()
	for pt in samples:
		var sim := _flyin_boss_sim(pt)
		var arrival := Vector2(sim.endless_boss["x"] * PX,
			(sim.endless_boss["gate_y"] - SimWorld.BOSS_Y_OFFSET) * PX)
		var drawn := _flyin_drawn_px(sim)
		if sim._bullet_hits_boss({"x": int(drawn.x * Fixed.ONE), "y": int(drawn.y * Fixed.ONE)}):
			tracked += 1
		if drawn.distance_to(arrival) > SimWorld.BOSS_HIT_RADIUS * PX:
			arrival_eligible += 1
			var sim2 := _flyin_boss_sim(pt)
			if not sim2._bullet_hits_boss({"x": int(arrival.x * Fixed.ONE),
					"y": int(arrival.y * Fixed.ONE)}):
				arrival_missed += 1
	Runner.T.eq(tracked, samples.size(),
		"a tracking shooter connects at every sampled tick (%d/%d)" % [tracked, samples.size()])
	Runner.T.ok(arrival_eligible >= 30,
		"sanity: the hull spends most of the approach off the arrival point (%d of %d samples)"
			% [arrival_eligible, samples.size()])
	Runner.T.eq(arrival_missed, arrival_eligible,
		"holding the arrival point lands nothing while the hull is elsewhere (%d/%d) — the fly-in costs tracking"
			% [arrival_missed, arrival_eligible])


func test_flyin_death_fx_land_on_the_wreck_not_the_pad() -> void:
	## The SIBLING SEAM the hitbox fix opened. Making the approach damageable made
	## `_damage_boss`'s death block reachable at negative `phase_t` for the first
	## time — and that block was written when the boss could only ever die at its
	## arrival point, so it emitted `explosion` / `kill` (the coin toast) /
	## `pilot_down` at `boss["x"], gate_y - BOSS_Y_OFFSET` with no fly-in offset.
	##
	## MEASURED on this tree before the fix, killing the boss at each sampled tick:
	##   phase_t=-420  hull=(470.0,-365.0)  explosion@(320.0,-310.0)  d=159.8 px
	##   phase_t=-300  d=114.1 px    phase_t=-160  d=61.0 px    phase_t=0  d=0.0 px
	## i.e. the wreck ball, the coin toast and the ejecting pilot all fired up to
	## 8.0 boss-radii from the helicopter the player had just shot down.
	var samples := _flyin_samples()
	var fx_off := 0
	var worst := 0.0
	var pilot_off := 0
	for pt in samples:
		var sim := _flyin_boss_sim(pt)
		var boss: Dictionary = sim.endless_boss
		var off: Array = SimWorld.boss_flyin_offset(pt)
		var hull := Vector2(float(boss["x"] + int(off[0])) * PX,
			float(boss["gate_y"] - SimWorld.BOSS_Y_OFFSET + int(off[1])) * PX)
		boss["hp"] = 1
		sim._damage_boss(boss, 1)
		Runner.T.ok(not boss["alive"], "the sampled hit kills the miniboss (phase_t %d)" % pt)
		var seen := 0
		for ev in sim.events:
			if ev["t"] == "explosion" or ev["t"] == "kill":
				seen += 1
				var d: float = Vector2(float(ev["x"]) * PX, float(ev["y"]) * PX).distance_to(hull)
				worst = maxf(worst, d)
				if d > SimWorld.BOSS_HIT_RADIUS * PX:
					fx_off += 1
			elif ev["t"] == "pilot_down":
				seen += 1
				# The pilot's Y is deliberately floor-clamped off the top edge
				# (PILOT_FLOOR_ENDLESS) — pin the clamp, not a raw distance.
				var floor_y: int = sim.camera_top + SimWorld.PILOT_FLOOR_ENDLESS * SimWorld.F_ONE
				var want_y: int = maxi(boss["gate_y"] - SimWorld.BOSS_Y_OFFSET + int(off[1]), floor_y)
				if ev["x"] != boss["x"] + int(off[0]) or ev["y"] != want_y:
					pilot_off += 1
		Runner.T.eq(seen, 3, "the death emits explosion + kill + pilot_down (phase_t %d)" % pt)
	Runner.T.eq(fx_off, 0,
		"the wreck ball and the coin toast fire ON the hull at every sampled tick (%d/%d off, worst %.1f px)"
			% [fx_off, samples.size(), worst])
	Runner.T.eq(pilot_off, 0,
		"the pilot punches out at the crash site, floor-clamped (%d/%d misplaced)"
			% [pilot_off, samples.size()])


func test_flyin_hull_reacts_to_being_shot() -> void:
	## `_boss_flash` is set on EVERY `boss_hit` (main.gd, "the big body reacts, not
	## just a spark") — but the arrived path's `hull_mod.lerp(Color(2.2, 2.2, 2.2),
	## _boss_flash)` sits PAST the fly-in branch's `return`, so before this fix the
	## one window this cycle exists to open was also the one window where the body
	## never reacted to a round landing on it. Source-pinned, same idiom as
	## test_flyin_sprite_sits_on_its_own_hitbox's grep half.
	var view := _view_src()
	var body := view.substr(view.find("func _draw_one_gunship("))
	var flyin := body.substr(0, body.find("\n\tvar bpos := _to_screen("))
	Runner.T.ok(flyin.length() > 200 and flyin.contains("boss_flyin_offset"),
		"scraped the fly-in branch of _draw_one_gunship (%d chars)" % flyin.length())
	Runner.T.ok(flyin.contains("_boss_flash"),
		"the fly-in hull colour reacts to _boss_flash — a round landing during the approach flashes the body")
	Runner.T.ok(flyin.contains("2.2, 2.2, 2.2"),
		"it flashes toward the SAME white-hot the engaged hull uses, not a second authored value")


# ---------------------------------------------------------------------------
# "CAREER — 1 RUNS · 4 KILLS · 0% WON".
#
# Not one string: FIVE count-noun literals across menu.gd and main.gd printed a
# hardcoded plural against a live count, and FOUR of them are reachable at n = 1 —
# a first run, a one-kill run, the grenade top-up the SIM CLAMPS ("a top-up at
# 11/12 grenades delivers 1", buy_float_text's own docstring), and the same clamp
# on the hulk-salvage receipt. Two halves, so this pins the class and not the four
# instances:
#
#   SCRAPE — every `%d <PLURAL>` literal in the three view files must be listed
#            below against the PURE producer that emits it. A `%d TANKS` added
#            tomorrow is unlisted and reds the day it lands.
#   BEHAVIOUR — call each listed producer at n = 1 and assert it says the singular;
#            call it at 0 and 2 and assert the plural comes back, so nobody
#            "fixes" a failure by singularising unconditionally.
const PLURAL_SITES := {
	"+%d GRENADES": {"noun": "GRENADE", "who": "main.buy_float_text"},
	"+%d GRENADES — COVER STRIPPED": {"noun": "GRENADE", "who": "main.hulk_salvage_text"},
	"%d KILLS  ·  LONGEST STREAK  x%d": {"noun": "KILL", "who": "main._victory_story_rows"},
	"%d GUNSHIPS DOWNED — RUSH CLEARED": {"noun": "GUNSHIP", "who": "main.boss_rush_cleared_text"},
	"CAREER — %d RUNS · %d KILLS · %d%% WON": {"noun": "RUN", "who": "Menu.career_line"},
	"BOARD KEEPS YOUR TOP %d RUNS": {"noun": "RUN", "who": "Menu (HALL_KEEP is a const 40 — unreachable at 1)"},
}


func _plural_producer(who: String, n: int) -> String:
	match who:
		"main.buy_float_text": return Main.buy_float_text(1, n)          # kind 1 == grenades
		"main.hulk_salvage_text": return Main.hulk_salvage_text(n)
		"main._victory_story_rows": return String(Main._victory_story_rows(n, n, {})[0]["text"])
		"main.boss_rush_cleared_text": return Main.boss_rush_cleared_text(n)
		"Menu.career_line": return Menu.career_line(n, n, 0)
	return ""


func test_no_shipped_string_says_one_of_a_plural() -> void:
	var re := RegEx.new()
	re.compile('"[^"]*%d[ \\t]+[A-Z][A-Z]+S\\b[^"]*"')
	var found := 0
	for path in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var lit: String = m.get_string().substr(1, m.get_string().length() - 2)
			found += 1
			Runner.T.ok(PLURAL_SITES.has(lit),
				"%s: count-noun literal %s is listed against its pure producer" % [path.get_file(), lit])
	# Two literals SURVIVE the fix and are meant to: BUY_FLOAT's readable catalogue wording
	# (resolved through BUY_FLOAT_NOUN at draw time) and the Hall's const-40 board line. The
	# guard against a refactor that quietly empties this ratchet is the TABLE, not the scrape.
	Runner.T.ok(found >= 2, "scraped the count-noun literals out of the view layer (%d found)" % found)
	Runner.T.ok(PLURAL_SITES.size() >= 6, "the count-noun site table still names every known producer (%d)" % PLURAL_SITES.size())
	var wrong := 0
	var detail := ""
	for lit in PLURAL_SITES.keys():
		var who: String = PLURAL_SITES[lit]["who"]
		var noun: String = PLURAL_SITES[lit]["noun"]
		if not who.begins_with("main.") and not who.begins_with("Menu."):
			continue   # count is a const that can never be 1 — recorded, not exercised
		var one := _plural_producer(who, 1)
		Runner.T.ok(one != "", "%s answers at n = 1 (%s)" % [who, one])
		if one.contains("1 %sS" % noun):
			wrong += 1
			detail += "  %s -> %s\n" % [who, one]
		Runner.T.ok(one.contains("1 %s" % noun),
			"%s names the noun it counts at n = 1 (%s)" % [who, one])
		for many in [0, 2, 7]:
			var s := _plural_producer(who, many)
			if not s.contains(str(many)):
				# A producer may swap to a COUNT-FREE line at that quantity (hulk salvage
				# says "FULL UP — COVER STRIPPED" when it delivers none). Nothing to
				# pluralise, so nothing to assert — but the n = 1 arm above still runs.
				continue
			Runner.T.ok(s.contains("%d %sS" % [many, noun]),
				"%s still pluralises at n = %d (%s)" % [who, many, s])
	Runner.T.eq(wrong, 0, "no shipped line says \"1 <PLURAL>\" (%d producers do:\n%s)" % [wrong, detail])


# ---------------------------------------------------------------------------
# NO WORLD LABEL LANDS ON THE BOTTOM HUD RAIL.
#
# Reported as one floattext toast ("CLICK") printing under the caption strip. It is
# not one toast: main.gd::_draw seeds `_label_slots` with THREE families — the
# per-player exclusion boxes, the top-left HUD corner plate and last frame's message
# band — and claim_label_slot then accepts any row satisfying `y + h <= 360`. There
# is no bottom-rail rect in `taken` and there is no max_y. Meanwhile $HUD is a
# CanvasLayer at layer 2 and every world label draws at z=0, so the overprint
# direction is HUD-OVER-LABEL: the label is smothered under the 0.75-alpha caption
# scrim and the bark text prints across its own plate. Nineteen producers feed that
# arbiter; REVIVE <cost> over a partner downed near the viewport floor and AIM AWAY
# are both worse than the reported toast, because both are actionable and captions
# are ON by default for the full length of every bark clip.
#
# The sweep is exhaustive over the arbiter's whole input domain in the bottom 70px —
# there is no sampling window to under-shoot — and it runs THREE counter-factuals so
# the ratchet proves it can still see the defect it pins:
#     A. no rail reserved at all           (HEAD's behaviour)
#     B. rail reserved, no max_y bound     (reservation alone is not enough: an
#                                           exhausted PERSISTENT ladder deliberately
#                                           settles for LEAST OVERLAP, i.e. hands
#                                           rail pixels back by design)
#     C. rail reserved + max_y bound       (shipped — must be 0)
# A and B are asserted NON-ZERO. A ratchet whose counter-factual is also clean is
# pinning nothing, and would read green forever.
func test_no_world_label_ever_lands_on_the_bottom_hud_rail() -> void:
	var producers := _world_label_producers()
	Runner.T.ok(producers.size() >= 16,
		"scraped the world-label / floattext / supply-receipt producers out of main.gd (%d)" % producers.size())
	# --- the rail, seeded through the PRODUCTION path (hud.gd::bottom_rail_rects), not
	# --- a hand-typed rect list: the draw's own resolved caption box and verb chip.
	var stub := _RailMain.new()
	stub._sfx = Sfx.new()
	stub._sfx._arm_caption("SPOTTER: \"Gunship inbound, break left and keep moving!\"", null, true, false)
	var hud := HudIcons.new()
	hud.main = stub
	var frames := {}
	frames["default"] = hud.bottom_rail_rects()
	var csim := SimWorld.new(0xC0FFEE, 1, "campaign")
	csim.colossus = {"alive": true, "hp": 100}
	stub.sim = csim
	frames["colossus"] = hud.bottom_rail_rects()
	for tag in frames.keys():
		var rr: Array[Rect2] = frames[tag]
		Runner.T.eq(rr.size(), 2, "%s frame reserves BOTH rail members (caption scrim + verb chip)" % tag)
	Runner.T.ok(HudIcons.bottom_band_lift(csim) > 0.0,
		"the colossus frame really does lift the bottom cluster (%.0fpx)" % HudIcons.bottom_band_lift(csim))
	# --- the sweep ---
	var was_scale: float = Art.text_scale
	var counts := {"A_no_reservation": 0, "B_no_max_y": 0, "C_shipped": 0}
	var claims := 0
	var worst := ""
	for scale in [1.0, 2.0]:
		Art.text_scale = scale
		var sz := Art.fs(8)
		# The arbiter sees a rect, not a string: reduce the scraped producers to the
		# distinct WIDTHS they measure at this size, which is the whole of what varies.
		var widths := {}
		for t in producers:
			widths[Art.tw(t, sz)] = true
		for tag in frames.keys():
			var rail: Array[Rect2] = frames[tag]
			# Everything else the frame has already claimed. TWO regimes, because the
			# max_y bound is only load-bearing in the second, and a sweep that ran the
			# first alone would report the bound as dead code:
			#   clean      — a couple of reservations. The 13-row ladder virtually always
			#                finds a free row, so the RESERVATION alone is sufficient here
			#                (measured: 0 collisions survive it).
			#   congested  — 20 more labels already placed, each one GRANTED BY THE ARBITER
			#                and appended to `taken` exactly the way _draw does
			#                (`_label_slots.append(got)`). Now the ladder exhausts, the
			#                PERSISTENT path falls through to least-overlap, and without the
			#                bound it settles onto the rail by design.
			for regime in ["clean", "congested"]:
				var base: Array[Rect2] = [Main.player_label_exclusion(Vector2(320.0, 300.0)),
					Rect2(0.0, 0.0, 120.0, 60.0)]
				if regime == "congested":
					# A SATURATED frame, built the way _draw builds one: every rect here was
					# granted by the arbiter and then appended to `taken`. Three anchor
					# columns across the full width x 20 rows, because a wall confined to
					# screen-centre leaves the x40 and x600 ladders free and the
					# least-overlap fallback never fires (measured: 0).
					for cx in [60.0, 230.0, 400.0]:
						for i in 20:
							var cr := Main._label_plate_rect(cx, 40.0 + float(i) * 13.0, 180.0, sz)
							base.append(Main.claim_label_slot(cr, base))
				var with_rail: Array[Rect2] = base.duplicate()
				for r in rail:
					with_rail.append(r)
				var ceil_y: float = Main.label_rail_ceiling(rail)
				var where := "%s/%s scale %.1f" % [tag, regime, scale]
				# The congested regime costs ~20x per claim (its `taken` is 60+ rects and the
				# least-overlap fallback is O(rows x rects)), so it runs on a coarser x/width
				# grid: its job is to FIRE the fallback, while the clean regime is the one
				# that has to be exhaustive over the arbiter's whole bottom-70px domain.
				var xs := (range(40, 601, 20) if regime == "clean" else range(40, 601, 80))
				var ws := (widths.keys() if regime == "clean" else _width_spread(widths.keys(), 12))
				for wv in ws:
					var w: float = wv
					for xi in xs:
						for yi in range(290, 361):
							var pw := Main._label_plate_rect(float(xi), float(yi), w, sz)
							var fw := Main.floattext_claim_rect(Vector2(xi, yi), w, sz)
							claims += 2
							# The two counter-factuals exist to prove this sweep can still SEE the
							# defect. B only ever fires in the congested regime (the least-overlap
							# fallback needs an exhausted ladder). They run on every third x —
							# 116,564 / 343 collisions is ample proof of detectability, and the
							# exhaustive arm is C, the shipped behaviour, on every x.
							if xi % 60 == 40:
								claims += 4
								if _hits_rail(Main.claim_label_slot(pw, base), rail):
									counts["A_no_reservation"] += 1
								if _hits_rail(Main.claim_label_slot(fw, base, 0.0, true), rail):
									counts["A_no_reservation"] += 1
								if _hits_rail(Main.claim_label_slot(pw, with_rail), rail):
									counts["B_no_max_y"] += 1
								if _hits_rail(Main.claim_label_slot(fw, with_rail, 0.0, true), rail):
									counts["B_no_max_y"] += 1
							var pgot := Main.claim_label_slot(pw, with_rail, 0.0, false, ceil_y)
							if _hits_rail(pgot, rail):
								counts["C_shipped"] += 1
								if worst == "":
									worst = "persistent w%.0f @%d,%d %s -> %s" % [w, xi, yi, where, str(pgot)]
							var fgot := Main.claim_label_slot(fw, with_rail, 0.0, true, ceil_y)
							if _hits_rail(fgot, rail):
								counts["C_shipped"] += 1
								if worst == "":
									worst = "toast w%.0f @%d,%d %s -> %s" % [w, xi, yi, where, str(fgot)]
	Art.text_scale = was_scale
	Runner.T.ok(claims >= 90000, "swept the arbiter's whole input domain in the bottom 70px (%d claims)" % claims)
	Runner.T.ok(counts["A_no_reservation"] > 0,
		"COUNTER-FACTUAL A: with no rail reserved the sweep still sees the defect (%d collisions) — a clean A means this ratchet pins nothing"
			% counts["A_no_reservation"])
	Runner.T.ok(counts["B_no_max_y"] > 0,
		"COUNTER-FACTUAL B: reserving the rail alone is NOT enough (%d collisions survive the least-overlap fallback)"
			% counts["B_no_max_y"])
	Runner.T.eq(counts["C_shipped"], 0,
		"no world label or toast lands on the caption scrim / verb chip (%d collisions%s)"
			% [counts["C_shipped"], "" if worst == "" else " — first: " + worst])
	# The arbiter that is COMPUTED AND NEVER SEEDED is this codebase's own documented
	# failure mode (claim_label_slot shipped once as a signature, a docstring and
	# `return rect`, called only from its own test). Geometry alone would pass forever.
	var src := _view_src()
	var draw_body := src.substr(src.find("func _draw() -> void:"))
	draw_body = draw_body.substr(0, draw_body.find("\nfunc "))
	Runner.T.ok(draw_body.length() > 4000, "scraped _draw()'s body (%d chars)" % draw_body.length())
	var rail_at := draw_body.find("bottom_rail_rects(")
	Runner.T.ok(rail_at >= 0, "_draw() asks the HUD for the bottom rail")
	# CALLING it is not SEEDING it. A first cut of this assertion checked only that the call
	# was present, and a mutation that replaced the append loop's body with `pass` — the
	# arbiter's rects computed and thrown away, which is this codebase's own documented
	# failure mode — sailed straight through it green. Read the loop that follows.
	var seed_block := draw_body.substr(rail_at, 260) if rail_at >= 0 else ""
	Runner.T.ok(seed_block.contains("_label_slots.append("),
		"_draw() APPENDS the rail rects into _label_slots, not merely computes them")
	Runner.T.ok(seed_block.contains("_label_rail_ceiling = label_rail_ceiling("),
		"_draw() caches the rail ceiling off the SAME rects it seeded")
	var sites := 0
	var unbounded := 0
	var at := src.find("claim_label_slot(")
	while at >= 0:
		var call := _call_src(src, at)
		if not src.substr(maxi(0, at - 12), 12).contains("func "):
			sites += 1
			if not call.contains("_label_rail_ceiling"):
				unbounded += 1
		at = src.find("claim_label_slot(", at + 1)
	Runner.T.ok(sites >= 3, "found the production claim sites (%d)" % sites)
	Runner.T.eq(unbounded, 0, "every production claim passes the rail ceiling as max_y (%d unbounded)" % unbounded)
	hud.free()
	stub._sfx.free()
	stub.free()


## An evenly-spaced sample of `all`, always including its narrowest and widest member —
## the width spectrum is what the arbiter actually sees, and the ends are where the x-clamp
## and the rail intersection behave differently.
func _width_spread(all: Array, n: int) -> Array:
	var sorted := all.duplicate()
	sorted.sort()
	if sorted.size() <= n:
		return sorted
	var out: Array = []
	for i in n:
		out.append(sorted[int(round(float(i) * float(sorted.size() - 1) / float(n - 1)))])
	return out


func _hits_rail(got: Rect2, rail: Array[Rect2]) -> bool:
	if not got.has_area():
		return false   # the blessed droppable-suppression sentinel
	for r in rail:
		if got.grow(-0.5).intersects(r.grow(-0.5)):
			return true
	return false


## Every string main.gd hands to the in-world label arbiter, scraped from source so a
## producer added tomorrow enters the sweep the day it lands: the string-literal arguments
## of _world_label / _world_label_centered, the floattext `"text":` literals, and the
## supply-receipt catalogue. Format conversions are substituted with a WIDE token so the
## swept width spectrum bounds the real one rather than under-measuring it.
func _world_label_producers() -> Array:
	var src := _view_src()
	var seen := {}
	var re := RegEx.new()
	re.compile('_world_label(_centered)?\\(\\s*"([^"]*)"')
	for m in re.search_all(src):
		seen[m.get_string(2)] = true
	var re2 := RegEx.new()
	re2.compile('"text": "([^"]*)"')
	for m in re2.search_all(src):
		seen[m.get_string(1)] = true
	for b in Main.BUY_FLOAT:
		seen[b] = true
	var out: Array = []
	for k in seen.keys():
		out.append(String(k).replace("%d", "8888").replace("%s", "WWWWWWWW").replace("%.1f", "88.8"))
	return out


## The narrowest `main` hud.gd's bottom-rail reservation can read: the caption gates gate on
## _menu / _debrief / _captions / _sfx / _motion, the verb chip on the same plus main._menu.
class _RailMain extends Node2D:
	var sim: SimWorld = null
	var _debrief := false
	var _menu = null
	var _motion := 1.0
	var _captions := true
	var _sfx = null
	var _grenade_dry: Array = [0, 0]
	var _token_loss_t := 0.0
	var best_score := 0
	var best_wave := 0
	var _record_fired := false
	func bind_for_glyph(_a: String) -> int: return 0
	func pad_bind_for_glyph(_a: String, _device := 0) -> int: return -1


# ---------------------------------------------------------------------------
# NO STRING IS DRAWN UNDER A SHRINKING CANVAS
# ---------------------------------------------------------------------------
# The seam ratchet behind test_main.gd's whole-pixel check. That test pins the
# ONE producer's geometry; this one pins the CLASS, derived from source, so
# tomorrow's producer is covered the day it lands.
#
# Art.text floors its position to whole pixels in LOCAL space (art.gd). A canvas
# transform then maps those whole pixels to DEVICE pixels. At a scale below 1.0
# the mapping is fractional, and PixelOperator8 is a bitmap face: a half-pixel
# baseline splits the glyph's bottom scanline across two device rows at ~50% each.
# E loses its bottom bar and reads as F; B loses its bowl and reads as F or R.
# Shipped, and captured: the victory card's "BEST 143095   NEW BEST!" rendered as
# "FFST 143Ø95  NEW BEST!" in tools/screenshots.gd's 06-victoly.png.
#
# Scale-UP is a different animal and is NOT banned: rasterised through a GL probe,
# 1.28 turned 10 ink rows into 12 and 1.5 turned them into 15 — strokes thicken
# unevenly, but no bar is ever removed and no letter changes identity. Only
# scale-DOWN deletes a scanline. The two pop-in sites below are clamped at or
# above 1.0 by construction, so they are allowlisted BY EXPRESSION — same
# near-empty, written-justification discipline as run_tests.gd's ERROR_ALLOW.
# Fix the cause; only add an entry with a measurement behind it.
const TEXT_XFORM_SCALE_ALLOW := {
	"Vector2.ONE * punch":
		"main.gd _draw_banners splash pop-in. `punch = 1.0 + (BANNER_PUNCH_MAX - 1.0) * clampf(...)`"
		+ " and the block is gated on `if punch > 1.0`, so it is 1.0..1.28 — scale-UP only"
		+ " (measured: 10 ink rows -> 12 at 1.28, letter identity intact).",
	"Vector2.ONE * fpunch":
		"main.gd _draw_fx floattext toast. `fpunch = 1.0 + maxf(0.0, (FLOAT_PUNCH_MAX - 1.0) - t * 4.0)`,"
		+ " so it is 1.0..1.5 — scale-UP only (same measurement: 15 ink rows at 1.5).",
}
const _TEXT_DRAW_CALLS := ["Art.text(", "Art.text_center(", "draw_string(", "draw_string_outline("]


func _xform_args(src: String, open_paren: int) -> Array[String]:
	## Top-level comma split of one call's argument list. Handles the multi-line
	## calls both producers use — a line-based scrape misses those entirely.
	var out: Array[String] = []
	var depth := 0
	var cur := ""
	var i := open_paren
	while i < src.length():
		var ch := src[i]
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			if depth == 0:
				out.append(cur.strip_edges())
				break
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	for j in out.size():
		out[j] = out[j].replace("\n", " ").replace("\t", "")
		while out[j].contains("  "):
			out[j] = out[j].replace("  ", " ")
	return out


func _t2d_scale(expr: String) -> String:
	## Transform2D(rotation, SCALE, skew, origin) — the scale is argument 2. Only the
	## FIRST is read: no shipped site composes two scaled matrices in one expression,
	## and `.scaled(` is flagged separately so that route can't sneak past either.
	if expr.contains(".scaled("):
		return "<matrix .scaled()>"
	var at := expr.find("Transform2D(")
	if at < 0:
		return "Vector2.ONE"
	var args := _xform_args(expr, at + "Transform2D(".length())
	return args[1] if args.size() >= 2 else "Vector2.ONE"


func test_no_string_is_drawn_under_a_scaled_canvas_transform() -> void:
	var checked := 0
	var expected := 0
	var scaled_text_blocks := 0
	for path in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd",
			"res://src/view/art.gd"]:
		var raw := FileAccess.get_file_as_string(path)
		for tok in _TEXT_DRAW_CALLS:
			expected += raw.count(tok)
		# Blank out whole-line comments — the prose in this repo is full of
		# draw_set_transform talk — but blank them to the SAME LENGTH. The assignment
		# scan below indexes by character offset, and collapsing a comment to "" slides
		# every later offset left, which silently reorders the event walk and lets a
		# real violation resolve against the wrong matrix. (Inline `#` is left alone: it
		# can live inside a string literal, and eating the rest of the line would eat code.)
		var lines := raw.split("\n")
		var body := ""
		for ln in lines:
			var s0 := String(ln)
			body += (" ".repeat(s0.length()) if s0.strip_edges().begins_with("#") else s0) + "\n"

		# Ordered event walk. A block is "whatever is in force when a string is drawn",
		# which is the granularity the defect lives at — _draw_fx sets three different
		# scales and only ONE of its blocks contains text.
		var events: Array = []
		var mark := func(tok: String, kind: String) -> void:
			var at := body.find(tok)
			while at >= 0:
				events.append([at, kind, at + tok.length()])
				at = body.find(tok, at + 1)
		mark.call("draw_set_transform_matrix(", "xform_matrix")
		mark.call("draw_set_transform(", "xform")
		for tok in _TEXT_DRAW_CALLS:
			mark.call(tok, "text")
		# Matrix variables: every assignment whose RHS builds or scales a Transform2D.
		var off := 0
		for ln in lines:
			var s := String(ln)
			var stripped := s.strip_edges()
			if not stripped.begins_with("#") and (stripped.contains("Transform2D(") or stripped.contains(".scaled(")):
				var eq := s.find(":=")
				if eq < 0:
					eq = s.find("=")
				if eq > 0 and not s.substr(0, eq).contains("draw_set_transform"):
					var name := s.substr(0, eq).strip_edges().trim_prefix("var ").split(":")[0].strip_edges()
					if name.is_valid_identifier():
						# The RHS can wrap; take the rest of the file and let the paren
						# walk inside _t2d_scale find the end of the Transform2D call.
						events.append([off + eq, "assign", name, _t2d_scale(body.substr(off + eq, 400))])
			off += s.length() + 1
		events.sort_custom(func(a, b): return int(a[0]) < int(b[0]))

		var cur := "Vector2.ONE"
		var mat := {}
		for ev in events:
			match String(ev[1]):
				"assign":
					mat[String(ev[2])] = String(ev[3])
				"xform":
					var args := _xform_args(body, int(ev[2]))
					cur = args[2] if args.size() >= 3 else "Vector2.ONE"
				"xform_matrix":
					var args2 := _xform_args(body, int(ev[2]))
					var expr := args2[0] if args2.size() >= 1 else ""
					if expr.contains("Transform2D(") or expr.contains(".scaled("):
						cur = _t2d_scale(expr)
					else:
						cur = String(mat.get(expr.strip_edges(), "Vector2.ONE"))
				"text":
					checked += 1
					if cur == "Vector2.ONE":
						continue
					scaled_text_blocks += 1
					Runner.T.ok(TEXT_XFORM_SCALE_ALLOW.has(cur),
						("%s draws a string under canvas scale `%s` — a scale below 1.0 maps"
							+ " floored LOCAL pixels onto fractional DEVICE rows and deletes the"
							+ " glyph's bottom scanline (BEST -> FFST). Animate on whole-pixel"
							+ " offsets and alpha, or justify the expression in TEXT_XFORM_SCALE_ALLOW.")
							% [path, cur])
	# Not a guessed floor: the walk must reach EVERY text call a plain token count finds,
	# so a parser that silently drops half the file can't launder this suite green.
	Runner.T.eq(checked, expected,
		"the transform/text walk reached every string draw in the view (%d of %d)"
			% [checked, expected])
	Runner.T.ok(scaled_text_blocks >= 2,
		"...and still finds the two allowlisted pop-in sites (%d scaled text blocks), so a green"
			% scaled_text_blocks
			+ " here means the scrape ran, not that it matched nothing")


# --- WORLD-GROUND TINTS: the "unmasked shadow quad" class ---------------------
#
# SIX producers in the world-ground layer painted a FLAT, UNTEXTURED, HARD-EDGED
# draw_rect as a ground tint, on top of already-drawn terrain, litter and cacti
# (_draw_terrain tails into _draw_band_signatures/_draw_ruins_rubble/_draw_trenches/
# _draw_lane_seals/_draw_ledges AFTER the cactus/scrub/litter pass). The review that
# started this saw exactly ONE of the six — the choke wall, which lands at x 0 or
# x 400 on a 640-wide frame and so reads as "a dark rectangle slicing vertically down
# the middle". Measured on this tree at 22efd37: 30 world-ground functions derived
# from _draw's own body, 47 filled draw_rect calls, of which 6 are ground-tint PLANES
# (min dimension >= 24px); the rest are lips, chunks and debris at min dim <= 9px,
# which are authored signage and correctly stay crisp.
#
# The choke slab was ALSO in the wrong place. `band_top` resolves to the choke run's
# SOUTH edge and the rect then extends 240px further SOUTH, while the run itself
# extends NORTH — the `- 240.0 * PX * 0.0` term is a dead expression (multiplied by
# 0.0) that was clearly meant to shift it north and was neutered. Enumerated against
# the real sim over segments CHOKE_START_SEG..12 at 10-unit offsets:
#   choking rows enumerated              = 285
#   rows the shipped 240x240 slab COVERS =  10   (3.5% — one boundary row per segment)
#   rows it MISSES                       = 275
#     ...of which it is drawn SOUTH of   = 275
# So it marks 3.5% of the wall and paints 240px of near-opaque dark over open,
# walkable ground on the rest. That is why it reads as a lighting artifact rather
# than as geography: it IS unattached to any geometry.
#
# THE FIX IS A PLATEAU, NOT A BLOB, and this deliberately overturns the earlier
# soft-card attempt. assets/art/fx/fx_soft_spot.png is a RADIAL falloff card —
# measured here: alpha 255 at the exact centre, 63 at quarter-x, 0 at every edge,
# mean alpha 0.1293, only 7.05% of pixels above half. Stretched across a 216x120 rect
# it deposits 0.1798 of the ink the caller asked for, which fails the ink arm below
# (floor 0.4675) and is bit-identical to that arm's control B. The cap the same
# attempt applied (GROUND_SLAB_MAX_ALPHA 0.55) was the wrong theory of the defect too:
# the reviewer complained about the EDGE, not the DENSITY, and capping density cost
# the lane seal 88% of its contrast (Backlog:1473) and the trench floor 61%
# (Backlog:1476) while a 1px stroke got capped for no reason (Backlog:1912). So:
# full-alpha core, an inward feather ramp, and an UNCAPPED boundary stroke. Feather
# INWARD, never outward — nothing may be painted outside the collided rect, because
# in this repo terrain art == collision.
#
# Three arms, and the SET of functions arm 1 walks is derived from _draw's own body,
# so a 31st world-ground function joins the ratchet the day it lands.

func _world_ground_funcs(src: String) -> Array:
	## Every function in the world-ground layer: the ordered _draw_* calls _draw()
	## makes between _draw_terrain() and _draw_players(), plus the ones _draw_terrain
	## itself tails into. Derived, never typed — the point of the ratchet.
	var out: Array = []
	var ds := src.find("func _draw() -> void:")
	if ds < 0:
		return out
	var de := src.find("\nfunc ", ds + 1)
	var dbody := src.substr(ds, (de if de > ds else src.length()) - ds)
	var started := false
	for m in RegEx.create_from_string("(?m)^\\s*(?:_draw_[a-z0-9_]+)\\(").search_all(dbody):
		var nm := m.get_string().strip_edges().trim_suffix("(")
		if nm == "_draw_terrain":
			started = true
		if not started:
			continue
		if nm == "_draw_players":
			break
		if not out.has(nm):
			out.append(nm)
	var ts := src.find("func _draw_terrain() -> void:")
	if ts >= 0:
		var te := src.find("\nfunc ", ts + 1)
		var tbody := src.substr(ts, (te if te > ts else src.length()) - ts)
		for m in RegEx.create_from_string("_draw_[a-z0-9_]+\\(").search_all(tbody):
			var nm := m.get_string().trim_suffix("(")
			if not out.has(nm):
				out.append(nm)
	return out


func _filled_rects_in(src: String, fn: String) -> int:
	## Comment-stripped count of FILLED draw_rect lines in one function. A line
	## carrying `, false,` is a STROKE (draw_rect's `filled` arg) and does not count:
	## a boundary LINE is authored signage, a filled PLANE is a debug volume.
	var s := src.find("func %s(" % fn)
	if s < 0:
		return -1
	var e := src.find("\nfunc ", s + 1)
	var body := src.substr(s, (e if e > s else src.length()) - s)
	var n := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#") or not code.contains("draw_rect("):
			continue
		if code.contains(", false,"):
			continue
		n += 1
	return n


func _slab_ink(ops: Array, sample: Rect2) -> Color:
	## RASTERIZE a planned ground slab for real and return the ink it deposits over
	## `sample`: `.a` is the mean coverage, `.rgb` the mean PREMULTIPLIED colour — i.e.
	## exactly the two terms a GL capture's `dR = 255 * (premult_r - a * ground_r)`
	## needs, with no assumption about what colour the ground under it happens to be.
	##
	## Soft ops are sampled through the ACTUAL fx_softspot image, so a RADIAL card can
	## never be scored as if it were a body. That is the whole point: the retired
	## version of this seam masked every zone with fx_softspot stretched across the
	## rect, and since that card is a radial falloff (measured on this tree: mean alpha
	## 33/255 = 12.9% of nominal, only 7.05% of its pixels above half) it deposited
	## 0.1798 of a licensed 0.55. The lane seal's three-state cycle collapsed and every
	## geometric arm stayed green through it, because "is it soft" and "can you still
	## see it" are different questions.
	var soft_img: Image = Art.tex("fx_softspot").get_image()
	var sw := soft_img.get_width()
	var sh := soft_img.get_height()
	var acc_a := 0.0
	var acc_r := 0.0
	var acc_g := 0.0
	var acc_b := 0.0
	var n := 0
	for py in range(int(sample.position.y), int(sample.position.y + sample.size.y)):
		for pxx in range(int(sample.position.x), int(sample.position.x + sample.size.x)):
			var p := Vector2(float(pxx) + 0.5, float(py) + 0.5)
			var a := 0.0
			var cr := 0.0
			var cg := 0.0
			var cb := 0.0
			for op in ops:
				var box: Rect2 = op["box"]
				var col: Color = op["col"]
				var src_a := 0.0
				match String(op["k"]):
					"soft":
						if box.has_point(p):
							var u := int(clampf((p.x - box.position.x) / maxf(box.size.x, 0.001), 0.0, 0.999) * float(sw))
							var v := int(clampf((p.y - box.position.y) / maxf(box.size.y, 0.001), 0.0, 0.999) * float(sh))
							src_a = col.a * soft_img.get_pixel(u, v).a
					"stroke", "feather":
						var half := maxf(float(op["w"]), 1.0) * 0.5
						if box.grow(half).has_point(p) and not box.grow(-half).has_point(p):
							src_a = col.a
					_:
						if box.has_point(p):
							src_a = col.a
				if src_a <= 0.0:
					continue
				cr = col.r * src_a + cr * (1.0 - src_a)
				cg = col.g * src_a + cg * (1.0 - src_a)
				cb = col.b * src_a + cb * (1.0 - src_a)
				a = src_a + a * (1.0 - src_a)
			acc_a += a
			acc_r += cr
			acc_g += cg
			acc_b += cb
			n += 1
	var f := 1.0 / maxf(float(n), 1.0)
	return Color(acc_r * f, acc_g * f, acc_b * f, acc_a * f)


func _lane_seal_plans(ms: Script) -> Dictionary:
	## The THREE shipped lane-seal states, planned through the shipped seam at the
	## widest real seal geometry (216x120 — SimWorld.LANE_SEAL_DEPTH against the left
	## flank). Colours and alphas copied from _draw_lane_seals' own call sites. All
	## three states are planned DIRECTLY, so this arm is state-exhaustive: there is no
	## tick sampling and therefore no window to compare against the defect's length.
	var r := Rect2(0.0, 0.0, 216.0, 120.0)
	return {
		"rect": r,
		"sealed": ms.ground_slab_ops(r, Color(0.17, 0.15, 0.13, 0.92), Color(0.42, 0.40, 0.34, 0.9)),
		"warn": ms.ground_slab_ops(r, Color(0.85, 0.55, 0.15, 0.22), Color(0.95, 0.62, 0.20, 0.85)),
		"scar": ms.ground_slab_ops(r, Color(0.20, 0.18, 0.16, 0.16), Color(0.35, 0.32, 0.27, 0.35)),
	}


func test_ground_zone_tints_keep_their_read_after_soft_masking() -> void:
	# The soft-mask seam (test_world_ground_tints_are_soft_masked_not_raw_quads) is
	# free to take the LID off a ground tint. It is not free to take the ZONE off the
	# screen, and the geometric arms over there structurally cannot tell the two apart.
	#
	# Measured, GL capture at 640x360, mean R over a 140x80 sample inside the seal rect
	# vs an equal sample of adjacent open ground on the same rows:
	#
	#            HEAD    radial-card seam    this seam
	#   SEALED   -50           -6              -50
	#   WARN     +30          +12              +30
	#   SCAR      -3           +2               -3
	#
	# SEALED and SCAR 8 R-points apart is not a learnable three-state cycle; it is the
	# "reverted your step with nothing on screen" bug _draw_lane_seals was written to
	# fix, shipped again under a nicer docstring. This arm is deliberately stated in
	# COVERAGE, not in dR: coverage is a property of the plan alone, so it needs no
	# assumption about the colour of the sand underneath and cannot rot when the
	# terrain palette moves.
	var ms: Script = load("res://src/main.gd")
	Runner.T.ok(ms.has_method("ground_slab_ops"), "the soft-mask planner is a named, testable helper")
	if not ms.has_method("ground_slab_ops"):
		return
	var consts: Dictionary = ms.get_script_constant_map()
	Runner.T.ok(not consts.has("GROUND_SLAB_MAX_ALPHA"),
		("no blanket alpha CAP survives: the defect was the razor EDGE, not the density,"
			+ " and capping density cost the lane seal 88% of its contrast (dR -50 -> -6)"
			+ " and the trench floor 61% (dR -36 -> -14) for nothing"))
	var bleed: float = float(consts["GROUND_SLAB_BLEED"])
	var plans := _lane_seal_plans(ms)
	var r: Rect2 = plans["rect"]
	# The reviewer's window: 140x80 centred, which sits wholly inside the collided rect.
	var core := Rect2(r.get_center() - Vector2(70.0, 40.0), Vector2(140.0, 80.0))
	var sealed_ink := _slab_ink(plans["sealed"], core)
	var warn_ink := _slab_ink(plans["warn"], core)
	var scar_ink := _slab_ink(plans["scar"], core)
	# 1. The seam must not EAT the caller's ink. The plateau's whole point is that the
	#    body arrives at exactly the alpha asked for and only the outer bleed ramps.
	for st in [["sealed", sealed_ink, 0.92], ["warn", warn_ink, 0.22], ["scar", scar_ink, 0.16]]:
		var want: float = float(st[2])
		var got: float = (st[1] as Color).a
		Runner.T.ok(got >= want * 0.85,
			("%s: the plan DEPOSITS the ink it was asked for over the zone body"
				+ " — %.4f of an asked %.2f (floor %.4f)") % [st[0], got, want, want * 0.85])
	# 2. ...and the three states stay separated, which is the property the cycle's
	#    learnability actually rests on. HEAD's spread was 0.92 / 0.22 / 0.16.
	Runner.T.ok(sealed_ink.a - scar_ink.a >= 0.30,
		("SEALED vs SCAR: blocked and walkable are separated by coverage"
			+ " (%.4f vs %.4f, gap %.4f)") % [sealed_ink.a, scar_ink.a, sealed_ink.a - scar_ink.a])
	Runner.T.ok(sealed_ink.a - warn_ink.a >= 0.20,
		"SEALED vs WARN: the 45-tick tell is not the seal (%.4f vs %.4f)" % [sealed_ink.a, warn_ink.a])
	Runner.T.ok(warn_ink.r - warn_ink.b >= 0.06,
		("WARN reads AMBER, not grey — the pulse's hue survives the mask"
			+ " (premultiplied r %.4f vs b %.4f)") % [warn_ink.r, warn_ink.b])
	# SEALED must READ darker than SCAR on the ground it actually lands on. Stated as
	# the rasterizer's own dR = 255 * (premult_r - a * ground_r), against a nominal
	# sand reference — NOT as a bare premultiplied-r comparison. Over a black
	# accumulator premult r rises with COVERAGE, so `sealed.r < scar.r` is true only
	# while sealed's alpha is being crushed (it held under the retired cap, and
	# inverts the moment the plateau delivers the density the caller asked for). It
	# was measuring the cap, not the darkness.
	var sand_r := 0.75
	var d_sealed := 255.0 * (sealed_ink.r - sealed_ink.a * sand_r)
	var d_scar := 255.0 * (scar_ink.r - scar_ink.a * sand_r)
	Runner.T.ok(d_sealed < d_scar - 40.0,
		("SEALED darkens the sand under it far harder than SCAR does"
			+ " (dR %.1f vs %.1f against ground r %.2f)") % [d_sealed, d_scar, sand_r])
	# 3. GRADIENT ARM — the reported defect itself. Sample 1px bands ENTIRELY INSIDE
	#    r's north edge, never straddling it: a band that straddles a perfect step edge
	#    averages to exactly half the interior (0.460 of 0.920 — measured), which sails
	#    through any "edge < inside * 0.85" threshold. That measures straddle-averaging,
	#    not gradient, and it is why the earlier attempt's feather arm could not detect
	#    the defect it was written for (and why its own control A asserted 0.460 >= 0.782
	#    and failed).
	#
	#    Measured, sealed 0.92 over 216x120, bleed 8:
	#      j       0      1      2      3      4      5      6      7      8+
	#      plateau 0.102  0.204  0.307  0.409  0.511  0.612  0.713  0.812  0.910
	#      HEAD    0.920  0.920  0.920  0.920  0.920  0.920  0.920  0.920  0.920
	var bands: Array = []
	for j in range(0, int(bleed) + 3):
		var band := Rect2(r.position + Vector2(4.0, float(j)), Vector2(r.size.x - 8.0, 1.0))
		bands.append(_slab_ink(plans["sealed"], band).a)
	Runner.T.ok(float(bands[0]) <= 0.92 * 0.25,
		("the tint enters SOFT at the collided boundary instead of at full alpha"
			+ " (first inside row %.4f, ceiling %.4f)") % [float(bands[0]), 0.92 * 0.25])
	var rise_err := 0
	for j in range(1, int(bleed)):
		if float(bands[j]) <= float(bands[j - 1]) + 0.0001:
			rise_err += 1
	Runner.T.eq(rise_err, 0,
		("...and it RAMPS strictly inward across the whole bleed rather than stepping"
			+ " (%d non-rising rows of %d)") % [rise_err, int(bleed) - 1])
	Runner.T.ok(float(bands[int(bleed)]) >= 0.92 * 0.95,
		"...reaching the full asked density by the time it clears the %.0fpx bleed (%.4f)"
			% [bleed, float(bands[int(bleed)])])
	# Non-vacuity controls, both scored through the SAME rasterizer. The raw quad
	# passes the ink arm and fails the gradient arm; the radial card does the exact
	# opposite. A ratchet with only one of the two would have shipped one of the two bugs.
	var legacy: Array = [{"k": "body", "box": r, "col": Color(0.17, 0.15, 0.13, 0.92), "w": 0.0}]
	var legacy_ink := _slab_ink(legacy, core)
	var legacy_first := _slab_ink(legacy,
		Rect2(r.position + Vector2(4.0, 0.0), Vector2(r.size.x - 8.0, 1.0))).a
	Runner.T.ok(legacy_ink.a > 0.9 and legacy_first > 0.92 * 0.25,
		("control A: HEAD's raw 0.92 quad passes the INK arm (%.4f) and fails the GRADIENT"
			+ " arm — its first inside row is already at full alpha (%.4f > %.4f)")
			% [legacy_ink.a, legacy_first, 0.92 * 0.25])
	var radial: Array = [{"k": "soft", "box": r.grow(bleed),
		"col": Color(0.17, 0.15, 0.13, 0.55), "w": 0.0}]
	var radial_ink := _slab_ink(radial, core)
	Runner.T.ok(radial_ink.a < 0.55 * 0.85,
		("control B: an fx_softspot card stretched across the zone deposits only %.4f"
			+ " of a licensed %.4f — a radial falloff is a shadow, not a zone body, and"
			+ " it fails the ink arm above") % [radial_ink.a, 0.55])


func test_world_ground_tints_are_soft_masked_not_raw_quads() -> void:
	var ms: Script = load("res://src/main.gd")
	var src := _view_src()
	# --- ARM 1: no raw ground-tint fill anywhere in the world-ground layer.
	var fns := _world_ground_funcs(src)
	Runner.T.ok(fns.size() >= 30,
		"the world-ground function set is derived from _draw's own body (%d functions)" % fns.size())
	var total := 0
	for f in fns:
		total += maxi(_filled_rects_in(src, f), 0)
	# 47 before the fix; 6 raw ground-tint PLANES retired (1 choke slab, 3 lane-seal
	# slabs, 1 rubble tint, 1 trench floor). Not a floor — an EQUALITY, so a new raw
	# quad in any of the 30 functions fails here even if someone deletes an old one.
	Runner.T.eq(total, 41,
		"filled draw_rect count across the whole world-ground layer (%d)" % total)
	# Per-function, so those exact fills cannot creep back one at a time. _draw_ledges
	# is UNTOUCHED at 3 and asserted at 3 — proof this arm is not just "everything went
	# to zero": its three rects are a 7px lip shadow, a 3px lit lip and a 2px underline,
	# which are small crisp OBJECTS and correctly stay raw.
	for pair in [["_draw_terrain", 0], ["_draw_lane_seals", 4], ["_draw_ruins_rubble", 1],
			["_draw_trenches", 3], ["_draw_ledges", 3]]:
		Runner.T.eq(_filled_rects_in(src, pair[0]), pair[1],
			"%s filled draw_rect count" % pair[0])
	Runner.T.ok(src.count("_ground_slab(") >= 7,
		"the soft-mask seam is WIRED (def + executor + 6 call sites), not just a signature (%d)"
			% src.count("_ground_slab("))
	# --- ARM 2: the seam's own geometry, measured without a draw context.
	Runner.T.ok(ms.has_method("ground_slab_ops"), "the soft-mask planner is a named, testable helper")
	if not ms.has_method("ground_slab_ops"):
		return
	var consts: Dictionary = ms.get_script_constant_map()
	var bleed_c: float = float(consts["GROUND_SLAB_BLEED"])
	var min_dim: float = float(consts["GROUND_SLAB_MIN_DIM"])
	var bad := 0
	var strokes := 0
	var planes := 0
	var crisp := 0
	for w in [8.0, 40.0, 80.0, 120.0, 216.0, 296.0]:
		for h in [4.0, 20.0, 48.0, 120.0, 240.0]:
			for a in [0.10, 0.16, 0.30, 0.5, 0.55, 0.85, 0.92, 1.0]:
				var r := Rect2(30.0, 40.0, w, h)
				var m := minf(w, h)
				for edge in [Color(0, 0, 0, 0), Color(0.42, 0.40, 0.34, 0.9)]:
					var ops: Array = ms.ground_slab_ops(r, Color(0.17, 0.15, 0.13, a), edge)
					var n_soft := 0
					var n_fill := 0
					var n_plane := 0
					var prev_a := -1.0
					for op in ops:
						var k := String(op["k"])
						if k == "soft":
							n_soft += 1      # the retired radial card must never come back
						elif k == "fill":
							n_fill += 1
							# a raw plane is licensed ONLY for a LINE/CHUNK, never a plane
							if m >= min_dim:
								bad += 1
							if not (op["box"] as Rect2).is_equal_approx(r):
								bad += 1
						elif k == "plane":
							n_plane += 1
							# the full-alpha core must arrive UNCAPPED and strictly INSIDE r
							if absf(float(op["col"].a) - a) > 0.0001:
								bad += 1
							if not r.encloses(op["box"]) or (op["box"] as Rect2).is_equal_approx(r):
								bad += 1
						elif k == "feather":
							# rings rise strictly inward and never leave the collided rect
							if not r.encloses((op["box"] as Rect2).grow(0.5)):
								bad += 1
							if float(op["col"].a) <= prev_a + 0.000001:
								bad += 1
							prev_a = float(op["col"].a)
							if float(op["col"].a) > a + 0.0001:
								bad += 1
						elif k == "stroke":
							strokes += 1
							# UNCAPPED: the boundary line is authored signage
							if absf(float(op["col"].a) - edge.a) > 0.0001:
								bad += 1
							if not (op["box"] as Rect2).is_equal_approx(r) \
									or absf(float(op["w"]) - 1.0) > 0.0001:
								bad += 1
					if n_soft != 0:
						bad += 1
					if m < min_dim:
						crisp += 1
						if n_fill != 1 or n_plane != 0:
							bad += 1     # a LINE/CHUNK stays crisp and is the sole body op
					else:
						planes += 1
						if n_plane != 1 or n_fill != 0:
							bad += 1     # a PLANE gets exactly one core, no raw fill
					if edge.a > 0.0 and strokes == 0:
						bad += 1
	Runner.T.eq(bad, 0,
		"every planned ground slab is a plateau: uncapped core, inward feather, crisp signage (%d violations)" % bad)
	Runner.T.ok(strokes > 0 and planes > 0 and crisp > 0,
		"...and the sweep exercised all three paths (%d strokes, %d planes, %d crisp lines)"
			% [strokes, planes, crisp])
	# Non-vacuity control: run the RETIRED models — HEAD's raw fill at 0.92 whose
	# boundary IS the collision edge, and the radial card — through the same predicate
	# and assert both are rejected.
	var legacy_bad := 0
	var big := Rect2(30.0, 40.0, 216.0, 120.0)
	for op in [{"k": "fill", "box": big, "col": Color(0.17, 0.15, 0.13, 0.92), "w": 0.0},
			{"k": "soft", "box": big.grow(bleed_c), "col": Color(0.17, 0.15, 0.13, 0.55), "w": 0.0}]:
		var k := String(op["k"])
		if k == "fill" and minf(big.size.x, big.size.y) >= min_dim:
			legacy_bad += 1
		if k == "soft":
			legacy_bad += 1
	Runner.T.eq(legacy_bad, 2,
		("control: HEAD's raw 0.92 lane-seal quad AND the retired radial card are both"
			+ " rejected by the arm above — so a green there means the predicate ran,"
			+ " not that it matched nothing"))
	# --- ARM 3: the choke wall's extent is DERIVED, and it is culled off-frame.
	Runner.T.ok(ms.has_method("choke_slab_rect"), "the choke slab's extent is a named, testable helper")
	# Loaded as a Script, not called as `SimWorld.x`: a direct static call to a method
	# that does not exist yet is a PARSE error, which would take the whole suite down
	# instead of failing this one assertion.
	var sws: Script = load("res://src/sim/sim_world.gd")
	Runner.T.ok(sws.has_method("choke_band_span"), "...and its band span comes from the sim")
	if not ms.has_method("choke_slab_rect") or not sws.has_method("choke_band_span"):
		return
	var sim := SimWorld.new(0xC0FFEE, 1)
	var px: float = float(consts["PX"])
	var rows := 0
	var derived_err := 0
	var covered := 0
	var head_covered := 0
	var head_south := 0
	var head_dy := 0.0
	var offscreen_culled := 0
	var bites := {}
	var lens := {}
	for seg in range(SimWorld.CHOKE_START_SEG, 13):
		for off_u in range(0, 1000, 10):
			var wy: int = -(seg * SimWorld.GATE_SPACING + off_u * Fixed.ONE)
			var cb: Array = sim._choke_bounds(wy)
			if cb[0] == SimWorld.WORLD_LEFT and cb[1] == SimWorld.WORLD_RIGHT:
				continue
			rows += 1
			var span: Array = sws.choke_band_span(wy)
			if span.is_empty():
				derived_err += 1
				continue
			# The span must CONTAIN this row and be same-flank throughout.
			var off: int = absi(wy) % SimWorld.GATE_SPACING
			if off < span[0] or off > span[1]:
				derived_err += 1
			var left_bite: bool = cb[0] != SimWorld.WORLD_LEFT
			for probe in [span[0], (int(span[0]) + int(span[1])) / 2, span[1]]:
				var pb: Array = sim._choke_bounds(-(seg * SimWorld.GATE_SPACING + int(probe)))
				if (pb[0] != SimWorld.WORLD_LEFT) != left_bite:
					derived_err += 1
				if pb[0] == SimWorld.WORLD_LEFT and pb[1] == SimWorld.WORLD_RIGHT:
					derived_err += 1
			# Camera placed so THIS row sits at screen y 180 — the same sample point
			# _draw_terrain's scan=2 hits, so the pose is one the shipped loop reaches.
			var cam_on: int = wy - 180 * Fixed.ONE
			var r: Rect2 = ms.choke_slab_rect(cb, span, seg, cam_on)
			var want_h: float = float(int(span[1]) - int(span[0])) * px
			if absf(r.size.y - want_h) > 1.5:
				derived_err += 1
			if left_bite and absf(r.position.x) > 0.001:
				derived_err += 1
			if not left_bite and absf(r.position.x + r.size.x - 640.0) > 1.0:
				derived_err += 1
			var bite_px: float = float(cb[0] - SimWorld.WORLD_LEFT) * px if left_bite \
				else float(SimWorld.WORLD_RIGHT - cb[1]) * px
			bites[int(bite_px)] = true
			lens[int(want_h)] = true
			# Does the DERIVED slab actually mark the wall at THIS row? Probe the
			# midpoint of the walled-off strip on the row's own screen line.
			var mid_x: float = (float(SimWorld.WORLD_LEFT + cb[0]) * 0.5) * px if left_bite \
				else (float(int(cb[1]) + SimWorld.WORLD_RIGHT) * 0.5) * px
			var probe_pt := Vector2(mid_x, 180.0)
			if r.grow(1.0).has_point(probe_pt):
				covered += 1
			# HEAD's model for the same row: a fixed 240x240 anchored on the band's
			# SOUTH edge (`_to_screen(0, wy3 + (seg_off - CHOKE_OFF_LO))`, which resolves
			# to off == lo) and drawn 240px further SOUTH, at x 0 or 400, with no y cull.
			var seg_off: int = absi(wy) % SimWorld.GATE_SPACING
			var band_top := roundf(float(wy + (seg_off - SimWorld.CHOKE_OFF_LO) - cam_on) * px)
			var head := Rect2(0.0 if left_bite else 400.0, band_top, 240.0, 240.0)
			if head.has_point(probe_pt):
				head_covered += 1
			elif head.position.y > 180.0:
				head_south += 1
			head_dy = maxf(head_dy, absf(240.0 - want_h))
			# ...and the cull: park the camera a whole band south of the slab.
			var cam_off: int = -(seg * SimWorld.GATE_SPACING + int(span[1])) + 900 * Fixed.ONE
			var r_off: Rect2 = ms.choke_slab_rect(cb, span, seg, cam_off)
			if r_off == Rect2():
				offscreen_culled += 1
			else:
				derived_err += 1
	# WINDOW: exhaustive over segments CHOKE_START_SEG..12 at 10-unit offsets, which is
	# the full hashed variety the predicate produces (285 rows on this tree). Not a
	# sample — there is no longer instance of the defect to under-reach.
	Runner.T.ok(rows >= 250, "arm 3 enumerates the choking rows, it does not sample (%d rows)" % rows)
	Runner.T.ok(bites.size() >= 5 and lens.size() >= 5,
		"...and the enumeration covers the hashed variety it exists to catch (%d bites, %d band lengths)"
			% [bites.size(), lens.size()])
	Runner.T.eq(derived_err, 0, "the choke slab is derived from the sim's own bounds (%d mismatches)" % derived_err)
	Runner.T.eq(covered, rows,
		"the derived slab MARKS the wall on every choking row (%d of %d)" % [covered, rows])
	Runner.T.eq(offscreen_culled, rows, "every fully-off-frame band yields an empty rect (%d of %d)"
		% [offscreen_culled, rows])
	# Control: the retired hard-coded 240x240 marks 10 of 285 rows (3.5% — only each
	# segment's boundary row) and is drawn SOUTH of the other 275, i.e. onto the open
	# side of the squeeze. If this control ever goes green, arm 3 has stopped being
	# able to see the defect.
	Runner.T.ok(head_covered * 20 < rows,
		("control: the retired fixed 240x240 slab marks only %d of %d choking rows (%.1f%%)"
			+ " — it was anchored on the band's SOUTH edge and drawn 240px further south")
			% [head_covered, rows, 100.0 * float(head_covered) / maxf(float(rows), 1.0)])
	Runner.T.ok(head_south > 0 and head_dy > 0.0,
		("control: ...and on %d of them it lands entirely SOUTH of the row, missing the real"
			+ " run by up to %.0fpx tall — so a green above means arm 3 can still see the defect")
			% [head_south, head_dy])
