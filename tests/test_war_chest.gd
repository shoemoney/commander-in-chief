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
