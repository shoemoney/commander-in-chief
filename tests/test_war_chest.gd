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
