extends RefCounted
## The spend-wheel shop economy: wave-scaled prices, ammo caps, broke denial.

const Runner := preload("res://tests/run_tests.gd")


func test_supply_cost_scales_with_wave() -> void:
	# Endless creeps on wave; campaign creeps on gates opened (campaign is always
	# wave 0, so the wave creep never fired there and prices were frozen all run).
	var sim := SimWorld.new(7, 1, "endless")
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST, "wave 0 is base price, no surcharge")
	sim.wave = 6
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST + 20, "wave 6 adds (6/3)*10 surcharge")
	sim.wave = 600
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST + 150,
		"the endless creep is capped so late waves aren't price starvation")

	var camp := SimWorld.new(7, 1)
	camp.wave = 6
	Runner.T.eq(camp._supply_cost(0), SimWorld.SHOP_AMMO_COST,
		"campaign ignores wave — it is always wave 0")
	if not camp.gates.is_empty():
		camp.gates[0]["open"] = true
		Runner.T.eq(camp._supply_cost(0), SimWorld.SHOP_AMMO_COST + 10,
			"campaign creeps on each gate opened instead")


func test_apply_supply_clamps_mg_ammo_at_max() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	sim._apply_supply(p, 0)
	Runner.T.eq(p["mg_ammo"], SimWorld.MG_AMMO_MAX, "MG ammo stays clamped at max, no overflow")


func test_apply_supply_clamps_grenade_ammo_at_max() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX
	sim._apply_supply(p, 1)
	Runner.T.eq(p["grenade_ammo"], SimWorld.GRENADE_AMMO_MAX, "grenade ammo stays clamped at max, no overflow")


func test_try_buy_denies_when_broke() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	var cost: int = sim._supply_cost(0)
	sim.war_chest = cost - 1
	p["mg_ammo"] = 10
	sim._try_buy(p, 0)
	Runner.T.eq(sim.war_chest, cost - 1, "broke buy left the chest untouched")
	Runner.T.eq(p["mg_ammo"], 10, "no supply delivered when broke")
	Runner.T.eq(sim.events[-1]["t"], "deny", "deny event fired instead of buy")
