extends RefCounted
## The War Chest shared economy — the twist. Death is a transaction.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_revive_spends_shared_pool_and_escalates() -> void:
	var sim := SimWorld.new(7, 2)
	var p1 := sim.players[0]
	sim.war_chest = 200
	# First death.
	sim._kill_player(p1)
	Runner.T.eq(sim.revive_cost(p1), 50, "first revive costs base (2P)")
	var revive := SimInput.new()
	revive.revive = true
	sim.step([_idle(), revive])
	Runner.T.ok(p1["alive"], "revived by partner")
	Runner.T.eq(sim.war_chest, 150, "revive spent 50 from the shared pool")
	# Second death: price escalates.
	sim._kill_player(p1)
	Runner.T.eq(sim.revive_cost(p1), 100, "second revive costs double")
	sim.step([_idle(), revive])
	Runner.T.eq(sim.war_chest, 50, "second revive spent 100")


func test_solo_prices_halved() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	sim._kill_player(p)
	Runner.T.eq(sim.revive_cost(p), 25, "solo revive is half price")
	sim.war_chest = 30
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive])
	Runner.T.ok(p["alive"], "dead solo player self-revives (feeds the coin reader)")
	Runner.T.eq(sim.war_chest, 5, "solo revive spent 25")


func test_broke_fallback_respawns_at_gate() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	sim.war_chest = 0
	sim._kill_player(p)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive])
	Runner.T.ok(not p["alive"], "broke: revive denied")
	Runner.T.ok(p["broke_timer"] > 0, "broke timer armed")
	for i in SimWorld.BROKE_RESPAWN_TICKS:
		sim.step([_idle()])
	Runner.T.ok(p["alive"], "broke fallback respawned player after penalty wait")


func test_buy_spends_chest_and_delivers() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["mg_ammo"] = 10
	sim.war_chest = 100
	var buy := SimInput.new()
	buy.buy = 1   # kind 0 = ammo
	sim.step([buy])
	Runner.T.eq(sim.war_chest, 100 - SimWorld.SHOP_AMMO_COST, "buy spent the chest")
	Runner.T.eq(p["mg_ammo"], 40, "ammo delivered (+30)")


func test_buy_denied_when_broke() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	sim.war_chest = SimWorld.SHOP_VEST_COST - 1
	var buy := SimInput.new()
	buy.buy = 3   # kind 2 = vest
	sim.step([buy])
	Runner.T.eq(sim.war_chest, SimWorld.SHOP_VEST_COST - 1, "broke buy left the chest alone")
	Runner.T.ok(not p["vest"], "no vest delivered")


func test_buy_is_edge_triggered() -> void:
	# Holding the buy input across ticks must purchase exactly once.
	var sim := SimWorld.new(7, 1)
	sim.war_chest = 500
	# Players spawn at GRENADE_AMMO_MAX, and a buy that delivers nothing is now
	# denied outright — burn one first so this stays a test of edge-triggering.
	sim.players[0]["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX - 1
	var buy := SimInput.new()
	buy.buy = 2   # kind 1 = grenades
	for i in 10:
		sim.step([buy])
	Runner.T.eq(sim.war_chest, 500 - SimWorld.SHOP_GRENADE_COST, "held buy purchased once")


func test_partial_buy_announces_what_it_delivered() -> void:
	# The caps clamp, so a grenade buy at 11/12 delivers ONE — and the float text
	# announced the catalogue "+4 GRENADES" over it. The sim now rides the
	# delivered count on the buy event (checksum-excluded) and the view formats
	# from that. One assertion chain binding the sim's number to the printed one.
	var sim := SimWorld.new(7, 1)
	sim.war_chest = 500
	sim.players[0]["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX - 1
	var buy := SimInput.new()
	buy.buy = 2   # kind 1 = grenades
	sim.step([buy])
	var got := -1
	for ev in sim.events:
		if ev.get("t") == "buy":
			got = int(ev.get("n", -1))
	Runner.T.eq(got, 1, "the buy event carries the quantity actually delivered, not the catalogue 4")
	Runner.T.eq(sim.players[0]["grenade_ammo"], SimWorld.GRENADE_AMMO_MAX, "the top-up still landed")
	var ms: Script = load("res://src/main.gd")
	# Singular: the COUNT was already honest here, the NOUN was not — a clamped top-up of one
	# printed "+1 GRENADES" (see test_view_honesty.gd::test_no_shipped_string_says_one_of_a_plural).
	Runner.T.eq(ms.call("buy_float_text", 1, got), "+1 GRENADE",
		"the view prints the delivered count")
	Runner.T.eq(ms.call("buy_float_text", 2, 1), "FLAK VEST ON",
		"a kind with no quantity keeps its flat wording")


func test_buy_survives_input_wire_roundtrip() -> void:
	var inp := SimInput.new()
	inp.buy = 4
	inp.fire = true
	inp.interact = true
	var back := SimInput.decode(inp.encode())
	Runner.T.eq(back.buy, 4, "buy survives encode/decode")
	Runner.T.ok(back.fire and back.interact, "existing buttons unharmed by buy bits")


func test_kills_mint_coin() -> void:
	var sim := SimWorld.new(7, 1)
	sim._spawn_enemy(100 * Fixed.ONE, -100 * Fixed.ONE, false)
	sim._spawn_enemy(200 * Fixed.ONE, -100 * Fixed.ONE, true)
	sim._kill_enemy(sim.enemies[0])
	sim._kill_enemy(sim.enemies[1])
	Runner.T.eq(sim.war_chest, SimWorld.COIN_RUSHER + SimWorld.COIN_ELITE, "rusher + elite minted correct coin")
	Runner.T.ok(sim.score > 0, "kills also score")


# --- 2P co-op: the downed player is never a spectator ------------------------

func test_downed_player_can_pay_their_own_way_back_with_a_partner_up() -> void:
	# The strand: P2 goes down with a rich chest, so no broke fallback arms —
	# and self-revive used to be blocked outright while ANY partner stood. P2
	# had zero actions and zero timer, waiting on a partner who might be three
	# screens north. Paying from the floor is always available now.
	var sim := SimWorld.new(7, 2)
	var p2 := sim.players[1]
	sim.war_chest = 500
	sim._kill_player(p2)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([_idle(), revive])   # P1 idle: nobody is coming
	Runner.T.ok(p2["alive"], "the downed player revives themselves while the partner is up")
	Runner.T.eq(sim.war_chest, 450, "self-revive paid the same 50 the partner would have")


func test_self_revive_lands_at_the_checkpoint_partner_revive_at_the_partner() -> void:
	# The co-op decision survives the strand fix: same price, different place.
	var sim := SimWorld.new(7, 2)
	sim.war_chest = 500
	var p1 := sim.players[0]
	var p2 := sim.players[1]
	p1["y"] = sim.camera_top + 40 * Fixed.ONE     # partner pushed way north
	sim._kill_player(p2)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive, _idle()])                   # P1 performs the rescue
	Runner.T.eq(p2["y"], p1["y"], "a partner rescue puts you back at their side")
	sim._kill_player(p2)
	sim.step([_idle(), revive])                   # P2 pays from the floor
	Runner.T.ok(p2["y"] > p1["y"], "paying from the floor drops you back at the checkpoint")


func test_partner_rescue_lands_on_both_axes_not_just_the_row() -> void:
	# "At their side" was only ever half true: _try_revive passed Y and _respawn
	# merely re-clamped X in place, so the rescued partner surfaced on the
	# reviver's ROW but at the x where they died — up to the full 608px arena
	# away, which is where whatever killed them still is. The old test pinned Y
	# only, which is exactly why this stayed green.
	var sim := SimWorld.new(7, 2)
	sim.war_chest = 500
	var p1 := sim.players[0]
	var p2 := sim.players[1]
	p1["x"] = SimWorld.WORLD_LEFT + 40 * Fixed.ONE     # rescuer hard against the west wall
	p2["x"] = SimWorld.WORLD_RIGHT - 40 * Fixed.ONE    # body dies hard against the east wall
	var apart: int = absi(p2["x"] - p1["x"])
	Runner.T.ok(apart > 400 * Fixed.ONE, "setup: the corpse really is most of an arena away")
	sim._kill_player(p2)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive, _idle()])                        # P1 performs the rescue
	Runner.T.ok(p2["alive"], "setup: the rescue was actually affordable")
	Runner.T.eq(p2["y"], p1["y"], "a partner rescue puts you back on their row")
	Runner.T.eq(p2["x"], p1["x"], "...and in their COLUMN — 'at their side' is both axes")


func test_solo_self_revive_buys_the_ground_you_died_on() -> void:
	# Solo, the paid self-revive used to land at _checkpoint_y() — the exact spot
	# the FREE broke timer delivers you to. The coin bought 5 seconds and nothing
	# else, and you could not even elect the free path: _step_dead_player arms
	# that timer only while war_chest < revive_cost, so having money DISABLED it.
	# Paying must now buy the yardage back.
	var sim := SimWorld.new(7, 1)
	sim.war_chest = 500
	var p := sim.players[0]
	p["y"] = sim.camera_top + 60 * Fixed.ONE      # died pushed well north of the checkpoint
	var fell_at_y: int = p["y"]
	var fell_at_x: int = p["x"]
	sim._kill_player(p)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive])
	Runner.T.ok(p["alive"], "the solo body pays its own way back up")
	Runner.T.eq(p["y"], fell_at_y, "a PAID solo revive stands you up where you fell")
	Runner.T.eq(p["x"], fell_at_x, "...on the same column too — the corpse never slides")
	Runner.T.ok(p["y"] < sim._checkpoint_y(),
		"...which is strictly north of the checkpoint the FREE broke timer gives you")


func test_two_players_both_down_still_pay_the_checkpoint_penalty() -> void:
	# The solo carve-out above must NOT leak into 2P: the checkpoint penalty is
	# what keeps "wait for the rescue" the better play, and with a partner alive
	# or merely revivable there is still a rescue to wait for.
	var sim := SimWorld.new(7, 2)
	sim.war_chest = 500
	var p2 := sim.players[1]
	p2["y"] = sim.camera_top + 60 * Fixed.ONE
	sim._kill_player(sim.players[0])
	sim._kill_player(p2)
	var revive := SimInput.new()
	revive.revive = true
	sim.step([_idle(), revive])                   # P2 pays from the floor, P1 also down
	Runner.T.ok(p2["alive"], "the downed 2P player can still buy their own stand-up")
	Runner.T.ok(p2["y"] > sim.camera_top + 60 * Fixed.ONE,
		"2P self-revive still eats the checkpoint penalty — solo's carve-out did not leak")


func test_partner_draining_the_chest_arms_the_downed_players_fallback() -> void:
	# Hard strand: a RICH death arms no timer. The partner then spends the shared
	# chest, and the body is left with no timer, no affordable revive and nobody
	# who can pay — dead for the rest of the run. The fallback re-checks every tick.
	var sim := SimWorld.new(7, 2)
	var p2 := sim.players[1]
	sim.war_chest = 500
	sim._kill_player(p2)
	sim.step([_idle(), _idle()])
	Runner.T.eq(p2["broke_timer"], 0, "a rich death arms no fallback (the partner should rescue)")
	sim.war_chest = 0             # partner buys a vest / airstrike
	sim.step([_idle(), _idle()])
	Runner.T.ok(p2["broke_timer"] > 0, "the chest draining under a downed player arms the fallback")
	for _i in SimWorld.BROKE_RESPAWN_TICKS:
		sim.step([_idle(), _idle()])
	Runner.T.ok(p2["alive"], "the stranded player is back in the fight")


func test_broke_fallback_disarms_when_the_chest_recovers() -> void:
	# The other direction, or dying BROKE is strictly cheaper than dying rich:
	# free respawn on a timer vs. a 50-coin bill.
	var sim := SimWorld.new(7, 2)
	var p2 := sim.players[1]
	sim.war_chest = 0
	sim._kill_player(p2)
	sim.step([_idle(), _idle()])
	Runner.T.ok(p2["broke_timer"] > 0, "broke death arms the fallback")
	sim.war_chest = 200           # partner banks a kill
	sim.step([_idle(), _idle()])
	Runner.T.eq(p2["broke_timer"], 0, "the fallback disarms once the chest can pay")
	Runner.T.ok(not p2["alive"], "...and the free ride is off the table: somebody pays")


func test_revive_is_symmetric_between_p1_and_p2() -> void:
	# Nothing about the rescue may depend on WHICH seat you sit in.
	var sim := SimWorld.new(7, 2)
	var p1 := sim.players[0]
	var p2 := sim.players[1]
	sim.war_chest = 500
	sim._kill_player(p1)
	Runner.T.eq(sim.revive_cost(p1), sim.revive_cost(p2), "both seats price a body identically")
	var revive := SimInput.new()
	revive.revive = true
	sim.step([_idle(), revive])
	Runner.T.ok(p1["alive"], "P2 can rescue P1")
	Runner.T.eq(sim.war_chest, 450, "P2's rescue costs what P1's does")
	sim._kill_player(p2)
	sim.step([revive, _idle()])
	Runner.T.ok(p2["alive"], "P1 can rescue P2")
	Runner.T.eq(sim.war_chest, 400, "...for the same price")


func test_last_stand_all_down_latches_the_wipe_in_2p() -> void:
	# No revives past the final gate — so the only thing that must not happen is
	# two bodies on the floor with the sim still running and no way out.
	var sim := SimWorld.new(7, 2)
	sim.last_stand = true
	sim.war_chest = 5000
	sim._kill_player(sim.players[0])
	var revive := SimInput.new()
	revive.revive = true
	sim.step([revive, revive])
	Runner.T.ok(not sim.wiped, "one down, one up: the run continues")
	Runner.T.ok(not sim.players[0]["alive"], "no coin reader in Last Stand")
	sim._kill_player(sim.players[1])
	sim.step([revive, revive])
	Runner.T.ok(sim.wiped, "both down in Last Stand latches the wipe — never a frozen run")


# --- Terminal value of the chest. A WIN converted it (10x + 5000); BOTH loss paths
# silently binned it. The coin in your hand was worth exactly zero the instant the run
# ended and no screen ever said so. `_latch_wipe()` is now the one converter for the
# losing end, mirroring `_damage_colossus()`'s shape. ---

func test_every_run_ending_converts_the_chest() -> void:
	# Endless solo wipe. wave 12 + 3 deaths prices a body at 225, above a 200 chest,
	# which is what arms broke_timer and (with nobody up) ends the run.
	var e := SimWorld.new(7, 1, "endless")
	var ep: Dictionary = e.players[0]
	e.wave = 12
	e.war_chest = 200
	e._kill_player(ep)
	ep["deaths"] = 3
	Runner.T.eq(e.revive_cost(ep), 225, "setup: the body costs more than the chest holds")
	# BROKE_RESPAWN_TICKS is 300 — the longest instance of this window. Drive 400.
	var before := 0
	for i in 400:
		before = e.score
		e.step([_idle()])
		if e.wiped:
			break
	Runner.T.ok(e.wiped, "endless wipe latched inside the 400-tick window")
	Runner.T.eq(e.war_chest, 0, "the wipe empties the chest instead of stranding it")
	Runner.T.eq(e.score - before, 200 * SimWorld.WIPE_SCORE_MULT,
		"…converting it at the salvage rate on the same tick")
	var wev := {}
	for ev in e.events:
		if ev.get("t", "") == "wiped":
			wev = ev
	Runner.T.eq(int(wev.get("banked", -1)), 200, "the wiped event ships the PRE-zero chest for the debrief")
	Runner.T.eq(int(wev.get("banked_score", -1)), 200 * SimWorld.WIPE_SCORE_MULT,
		"…and what it converted to, so the view never restates the multiplier")

	# The campaign / solo Last Stand latch is a copy-paste sibling of the endless one;
	# it must route through the SAME converter.
	var c := SimWorld.new(7, 2)
	c.last_stand = true
	c.war_chest = 180
	var cbefore := c.score
	c._kill_player(c.players[0])
	c._kill_player(c.players[1])
	c.step([_idle(), _idle()])
	Runner.T.ok(c.wiped, "last-stand wipe latched")
	Runner.T.eq(c.war_chest, 0, "the last-stand wipe converts the chest too")
	Runner.T.eq(c.score - cbefore, 180 * SimWorld.WIPE_SCORE_MULT, "…at the same salvage rate")
	# (The victory path's 10x + 5000 is already pinned by
	# test_colossus.gd::test_death_pays_out_and_wins — not duplicated here.)


func test_god_mode_never_banks_the_chest_it_is_measuring() -> void:
	# god mode's _god_restore() clears the `wiped` latch on its next heartbeat, so a
	# Last Stand knockdown is NOT a run ending. Paying the salvage out anyway drained
	# the chest and added score on every knockdown — the debug instrument editing the
	# economy the tools/ balance probes exist to measure.
	var c := SimWorld.new(7, 2)
	c.god_mode = true
	c.last_stand = true
	c.war_chest = 180
	var before := c.score
	c._kill_player(c.players[0])
	c._kill_player(c.players[1])
	c.step([_idle(), _idle()])
	Runner.T.ok(c.wiped, "the latch still fires — god mode must not suppress the terminal state")
	Runner.T.eq(c.war_chest, 180, "god mode must NOT drain the chest: _god_restore un-latches, so this run is not over")
	Runner.T.eq(c.score, before, "…nor pay the 3x salvage a real run collects exactly once")
	var saw := false
	for ev in c.events:
		if ev.get("t", "") == "wiped":
			saw = true
	Runner.T.ok(not saw, "…and fires no OVERRUN card 60 ticks before the sim resumes")


func test_spending_stays_dominant() -> void:
	# Tuning invariant: salvaging a lost chest must never pay as well as spending it,
	# or hoarding becomes optimal and the shop stops mattering.
	Runner.T.ok(SimWorld.WIPE_SCORE_MULT > 0, "a lost run converts the chest at all")
	Runner.T.ok(SimWorld.WIPE_SCORE_MULT < SimWorld.SPEND_SCORE_MULT,
		"salvage (%dx) stays strictly under spend (%dx)"
			% [SimWorld.WIPE_SCORE_MULT, SimWorld.SPEND_SCORE_MULT])
	Runner.T.ok(SimWorld.SPEND_SCORE_MULT < SimWorld.VICTORY_SCORE_MULT,
		"spend stays under the victory bank rate — winning is still the best exit")
