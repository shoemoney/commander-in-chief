extends RefCounted
## The owner-requested control scheme, pinned:
##   1. ALWAYS FIRE — the MG has no button. It must fire wherever the game allows firing and
##      stay silent everywhere the game already forbade it.
##   2. GRENADE AND REVIVE SHIP ON DISTINCT INPUTS. Custom layouts may still bind them
##      together, in which case main.revive_context provides deterministic arbitration.
##      SHIFT stays a secondary, PURE throw.

const Runner := preload("res://tests/run_tests.gd")
const MainScript = preload("res://src/main.gd")
const Menu := preload("res://src/view/menu.gd")


func _fire() -> SimInput:
	var inp := SimInput.new()
	inp.fire = true
	inp.aim_y = -256
	return inp


func _shots(sim: SimWorld) -> int:
	var n := 0
	for ev in sim.events:
		if ev.get("t") == "shot":
			n += 1
	return n


# --- 1. ALWAYS FIRE -----------------------------------------------------------------

func test_there_is_no_fire_binding_and_space_is_the_dedicated_revive() -> void:
	Runner.T.ok(not MainScript.BIND_DEFAULTS.has("fire"),
		"no keyboard FIRE binding exists — aiming is the whole weapon verb")
	Runner.T.ok(not MainScript.PAD_DEFAULTS.has("fire"), "no pad FIRE button either")
	for a in MainScript.BIND_DEFAULTS:
		if a != "revive":
			Runner.T.ok(int(MainScript.BIND_DEFAULTS[a]) != KEY_SPACE,
				"SPACE belongs only to REVIVE — '%s' must not take it" % a)
	Runner.T.eq(int(MainScript.BIND_DEFAULTS["revive"]), KEY_SPACE,
		"REVIVE owns the freed always-fire key")


func test_held_fire_keeps_shooting_on_the_cooldown_cadence() -> void:
	# Always-fire's whole point: a permanently-true `fire` must land a round every
	# FIRE_COOLDOWN_TICKS for as long as there is ammo, with no edge anywhere.
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	var fired := 0
	for i in 80:
		sim.events.clear()   # _step_players does not clear; step() does
		sim._step_players([_fire()])
		fired += _shots(sim)
	Runner.T.eq(fired, 80 / SimWorld.FIRE_COOLDOWN_TICKS,
		"held fire lands exactly one round per FIRE_COOLDOWN_TICKS")

	Runner.T.eq(int(p["mg_ammo"]), SimWorld.MG_AMMO_MAX - fired, "and bills one round each")


func test_full_clip_dries_in_the_advertised_thirteen_seconds() -> void:
	# The economy headline, pinned as arithmetic the sim actually performs: a full clip at
	# max cadence is ~13 s of continuous fire. If either constant moves, this says so.
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	var t := 0
	while int(p["mg_ammo"]) > 0 and t < 3600:
		sim._step_players([_fire()])
		t += 1
	# The first round leaves on tick 1 (fire_cd starts at 0), so the last of N rounds lands
	# on tick (N-1)*cd + 1 — 785 ticks / 13.1 s for the shipped 99 rounds at an 8-tick cadence.
	Runner.T.eq(t, (SimWorld.MG_AMMO_MAX - 1) * SimWorld.FIRE_COOLDOWN_TICKS + 1,
		"a full %d-round clip empties in %.1f s of continuous fire"
			% [SimWorld.MG_AMMO_MAX,
				float((SimWorld.MG_AMMO_MAX - 1) * SimWorld.FIRE_COOLDOWN_TICKS + 1) / 60.0])


func test_a_downed_player_never_fires_however_hard_fire_is_held() -> void:
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	p["alive"] = false
	for i in 60:
		sim._step_players([_fire()])
		Runner.T.eq(_shots(sim), 0, "a body on the floor fires nothing")
	Runner.T.eq(int(p["mg_ammo"]), SimWorld.MG_AMMO_MAX, "and spends no ammo doing it")


func test_a_wiped_run_fires_nothing() -> void:
	# A wipe freezes the whole sim: step() returns before _step_players, so always-fire
	# cannot spend a round into a finished run.
	# (VICTORY deliberately not asserted here: SimWorld.step() only early-returns on `wiped`.
	# A won run keeps simulating behind the debrief card until the player redeploys, so the
	# gun keeps going — exactly as it did for anyone holding the old fire key. Pre-existing,
	# and post-victory ammo has no value: the score is already banked by then.)
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	sim.wiped = true
	var before: int = p["mg_ammo"]
	for i in 30:
		sim.step([_fire()])
	Runner.T.eq(int(p["mg_ammo"]), before, "a wiped run freezes the gun with it")


func test_empty_clip_bash_survives_the_loss_of_the_fire_edge() -> void:
	# Bash used to be edge-gated. With no fire button the edge arrives once per RUN, so an
	# edge gate would have quietly deleted the empty-clip counter. Level-triggered now, and
	# still rationed by BASH_COOLDOWN_TICKS rather than by the button.
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	var held := _fire()
	sim._step_players([held])   # burn the one and only rising edge
	sim._spawn_enemy(p["x"] + 12 * Fixed.ONE, p["y"], false)
	var e1 := sim.enemies[sim.enemies.size() - 1]
	sim._step_players([held])
	Runner.T.ok(not e1["alive"], "a dry player still bashes with fire already held down")
	Runner.T.eq(int(p["fire_cd"]), SimWorld.BASH_COOLDOWN_TICKS, "and pays the long cooldown")


func test_bash_is_still_rationed_by_its_cooldown_not_by_the_button() -> void:
	var sim := SimWorld.new(7, 1, "campaign")
	var p := sim.players[0]
	p["mg_ammo"] = 0
	sim.enemies.clear()
	var held := _fire()
	var kills := 0
	for i in SimWorld.BASH_COOLDOWN_TICKS:
		sim._spawn_enemy(p["x"] + 12 * Fixed.ONE, p["y"], false)
		var e := sim.enemies[sim.enemies.size() - 1]
		sim._step_players([held])
		if not e["alive"]:
			kills += 1
		p["hurt_iframes"] = 60   # the point is the bash cadence, not contact death
	Runner.T.eq(kills, 1, "one bash per BASH_COOLDOWN_TICKS even with fire permanently held")


# --- 2. DISTINCT DEFAULTS + CUSTOM SHARED-KEY FALLBACK ------------------------------

func test_grenade_and_revive_ship_on_distinct_keyboard_inputs() -> void:
	Runner.T.eq(int(MainScript.BIND_DEFAULTS["grenade"]), KEY_E, "GRENADE ships on E")
	Runner.T.eq(int(MainScript.BIND_DEFAULTS["revive"]), KEY_SPACE, "REVIVE ships on SPACE")
	Runner.T.ok(MainScript.BIND_DEFAULTS["grenade"] != MainScript.BIND_DEFAULTS["revive"],
		"the ship defaults never change a grenade press into a rescue")
	Runner.T.eq(int(MainScript.BIND_DEFAULTS["grenade_alt"]), KEY_SHIFT,
		"SHIFT survives as the secondary throw")


func test_shift_always_throws_even_when_e_is_busy_reviving() -> void:
	# [grenade, revive] for: E down, SHIFT down, revive-context ON, keys shared.
	var both := MainScript.shared_e(true, true, true, true, true)
	Runner.T.ok(both[0], "SHIFT throws while a rescue is on the table")
	Runner.T.ok(both[1], "...and the same held E still performs the rescue")
	var alt_only := MainScript.shared_e(false, true, false, true, false)
	Runner.T.ok(alt_only[0] and not alt_only[1], "SHIFT alone is a pure throw, never a revive")


func test_shared_e_truth_table() -> void:
	# E alone, keys shared. revives=false -> throw; revives=true -> revive. Never both.
	var throw := MainScript.shared_e(true, false, true, true, false)
	Runner.T.ok(throw[0] and not throw[1], "no rescue on the table: E throws")
	var rescue := MainScript.shared_e(true, false, true, true, true)
	Runner.T.ok(rescue[1] and not rescue[0], "rescue on the table: the same E revives instead")
	# Rebound apart (or a pad, where they are two real buttons): no muting at all.
	var split_up := MainScript.shared_e(true, false, false, false, true)
	Runner.T.ok(split_up[0] and not split_up[1],
		"once the keys differ, the grenade key throws even mid-rescue")
	var split_rev := MainScript.shared_e(false, false, true, false, false)
	Runner.T.ok(split_rev[1] and not split_rev[0],
		"...and the revive key revives even with nobody down (the sim just no-ops it)")
	var idle := MainScript.shared_e(false, false, false, true, true)
	Runner.T.ok(not idle[0] and not idle[1], "nothing held, nothing fires")


func test_solo_context_is_down_revives_up_throws() -> void:
	var sim := SimWorld.new(7, 1, "campaign")
	Runner.T.ok(not MainScript.revive_context(sim, 0), "solo and standing: E is a grenade")
	sim.players[0]["alive"] = false
	Runner.T.ok(MainScript.revive_context(sim, 0), "solo and down: E is GET UP")


func test_two_player_rule_downed_partner_plus_affordable_chest() -> void:
	# THE 2P RULE: you are up, your partner is down. E revives only if the chest can pay.
	var sim := SimWorld.new(7, 2, "campaign")
	Runner.T.ok(not MainScript.revive_context(sim, 0), "both up: E throws")
	sim.players[1]["alive"] = false
	sim.war_chest = 0
	Runner.T.ok(not MainScript.revive_context(sim, 0),
		"partner down but the chest is broke: E keeps throwing — a rescue you cannot "
		+ "perform must not disarm the only armor-cracker in the fight")
	sim.war_chest = sim.revive_cost(sim.players[1])
	Runner.T.ok(MainScript.revive_context(sim, 0), "partner down and affordable: E is the rescue")


func test_a_downed_player_revives_regardless_of_price() -> void:
	# Rule 2: your own body ignores affordability. You cannot throw from the floor anyway,
	# and gating it would swallow the revive_deny cue that explains the silence.
	var sim := SimWorld.new(7, 2, "campaign")
	sim.players[0]["alive"] = false
	sim.war_chest = 0
	Runner.T.ok(MainScript.revive_context(sim, 0), "broke and down: E is still GET UP, so the deny cue fires")


func test_last_stand_hands_e_back_to_the_grenade() -> void:
	var sim := SimWorld.new(7, 2, "campaign")
	sim.players[1]["alive"] = false
	sim.war_chest = 9999
	sim.last_stand = true
	Runner.T.ok(not MainScript.revive_context(sim, 0),
		"past the final gate the coin reader is dead, so E is a grenade again")


func test_e_aboard_a_tank_is_the_cannon_unless_a_rescue_is_on_the_table() -> void:
	# THE E-ABOARD-A-TANK RULE (mirrored in SimWorld._drive_tank's comment). E means the
	# same thing aboard as on foot: the grenade verb. Aboard, the grenade verb is the
	# CANNON — which spends the same pool — so nothing new needs arbitrating and the rule
	# above stands unchanged. A rider can never be the downed one (_kill_player clears
	# in_tank), but a PARTNER can, and then the rescue still wins the key.
	var sim := SimWorld.new(7, 2, "campaign")
	sim.players[0]["in_tank"] = 0
	Runner.T.ok(not MainScript.revive_context(sim, 0),
		"riding, nobody down: E is the cannon")
	sim.players[1]["alive"] = false
	sim.war_chest = sim.revive_cost(sim.players[1])
	Runner.T.ok(MainScript.revive_context(sim, 0),
		"riding with a downed, affordable partner: E is the rescue and the cannon holds fire")
	# ...and SHIFT (grenade_alt) is the escape hatch: a pure throw OUTSIDE the arbitration,
	# so a driver can always shell something even while a partner bleeds out.
	var shift := MainScript.shared_e(false, true, false, true, true)
	Runner.T.ok(shift[0], "SHIFT still fires the cannon through a live rescue prompt")


func test_the_rescue_a_tank_seat_routes_actually_fires_in_the_sim() -> void:
	# The sibling above proves ROUTING only and never steps the sim — which is how a
	# swallowed press shipped green. This is the one-tick execution proof.
	var sim := SimWorld.new(7, 2, "campaign")
	sim.step([SimInput.new(), SimInput.new()])
	var p1: Dictionary = sim.players[0]
	var p2: Dictionary = sim.players[1]
	sim.tanks.append({"x": p1["x"], "y": p1["y"], "alive": true, "burning": false,
		"fuel": SimWorld.TANK_FUEL_TICKS, "burn_ticks": 0, "crew_ring_ticks": -1,
		"fire_cd": 0, "occupant": -1})
	var board := SimInput.new()
	board.interact = true
	sim.step([board, SimInput.new()])
	Runner.T.ok(p1["in_tank"] >= 0, "setup: P1 is crewing the hull")
	sim.war_chest = 500
	sim._kill_player(p2)
	var cost: int = sim.revive_cost(p2)
	var chest0: int = sim.war_chest
	Runner.T.ok(MainScript.revive_context(sim, 0), "setup: the key IS routed to the rescue")
	var press := SimInput.new()
	press.revive = true
	sim.step([press, SimInput.new()])
	Runner.T.ok(p2["alive"], "an affordable revive from the driver's seat stands the partner up in ONE tick")
	Runner.T.eq(chest0 - sim.war_chest, cost, "...and the chest paid exactly revive_cost")
	# ...and a BROKE crew press is loud, not silent.
	sim._kill_player(p2)
	sim.war_chest = 0
	sim.step([press, SimInput.new()])
	var denied := false
	for ev in sim.events:
		if ev.get("t", "") == "revive_deny":
			denied = true
	Runner.T.ok(denied, "a broke revive from the tank emits revive_deny instead of a dead key")


func test_endless_intermission_gives_e_to_the_ready_up_hold() -> void:
	# SimWorld._ready_up reads `revive` as HOLD TO DEPLOY EARLY, and the hint already names E.
	var sim := SimWorld.new(7, 1, "endless")
	Runner.T.ok(not MainScript.revive_context(sim, 0), "mid-wave: E throws")
	sim.intermission_ticks = 120
	Runner.T.ok(MainScript.revive_context(sim, 0), "shop window open: E is the ready-up hold")


# --- 3. THE SURFACES THAT TEACH IT ---------------------------------------------------

func test_no_ui_surface_still_advertises_a_fire_key() -> void:
	Runner.T.ok(not ("fire" in Menu.REBIND_ACTIONS),
		"the REBIND screen no longer offers a FIRE row to rebind")
	Runner.T.ok("grenade_alt" in Menu.REBIND_ACTIONS, "GRENADE (ALT) is rebindable in its place")


func test_pause_footer_names_the_permanent_verb_on_e() -> void:
	# The pause footer is the PERMANENT reference; revive is contextual, grenade is not.
	var acts: Array = []
	for seg in Menu.footer_verb_segs():
		acts.append(seg["act"])
	Runner.T.ok("grenade" in acts, "the mid-run footer names GRENADE (the always-available E)")
	Runner.T.ok(not ("revive" in acts),
		"...not REVIVE, which only exists over a body and is taught there")
