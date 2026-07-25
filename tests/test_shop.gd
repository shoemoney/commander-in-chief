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


func test_priced_crate_at_cap_is_not_auto_bought() -> void:
	# Auto-buy on proximity had NO need check: walking over a priced crate you
	# cannot use charged the chest, credited cost*10 score (an endless laundering
	# loop) and fired the celebratory pickup event for a guaranteed no-op.
	for kind in [0, 1, 2]:
		var sim := SimWorld.new(7, 1)
		var p := sim.players[0]
		p["mg_ammo"] = SimWorld.MG_AMMO_MAX
		p["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX
		p["vest"] = true
		sim.pickups.clear()
		sim.pickups.append({"x": p["x"], "y": p["y"], "kind": kind, "cost": 20})
		sim.war_chest = 500
		sim.score = 0
		sim.events.clear()
		sim._collect_pickups(p, 0)
		Runner.T.eq(sim.war_chest, 500, "kind %d at cap: the chest is not charged" % kind)
		Runner.T.eq(sim.score, 0, "kind %d at cap: no cost*10 score laundering" % kind)
		Runner.T.eq(sim.pickups.size(), 1, "kind %d at cap: the crate is left standing" % kind)
		var fired := false
		for ev in sim.events:
			if ev["t"] == "pickup":
				fired = true
		Runner.T.ok(not fired, "kind %d at cap: no celebratory pickup event" % kind)


func test_priced_crate_still_bought_when_it_grants_something() -> void:
	# The guard must only refuse a crate that grants NOTHING — the normal buy and
	# the free-crate path are untouched.
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["grenade_ammo"] = 2
	sim.pickups.clear()
	sim.pickups.append({"x": p["x"], "y": p["y"], "kind": 1, "cost": 20})
	sim.war_chest = 500
	sim.score = 0
	sim.events.clear()
	sim._collect_pickups(p, 0)
	Runner.T.eq(sim.war_chest, 480, "a useful priced crate still charges its cost")
	Runner.T.eq(sim.score, 200, "a useful priced crate still credits cost*10")
	Runner.T.eq(p["grenade_ammo"], 6, "the supply was actually delivered")
	Runner.T.eq(sim.pickups.size(), 0, "the crate was consumed")

	# Free crates are never refused (they cost nothing) — they just carry
	# full=true so the view can skip the celebration.
	p["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX
	sim.pickups.append({"x": p["x"], "y": p["y"], "kind": 1, "cost": 0})
	sim.events.clear()
	sim._collect_pickups(p, 0)
	Runner.T.eq(sim.pickups.size(), 0, "a free crate at cap is still collected")
	Runner.T.ok(sim.events[-1]["full"], "the free no-op is flagged full for the view")


func test_supply_full_covers_every_capped_kind() -> void:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	p["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX
	p["vest"] = true
	p["claymores"] = SimWorld.CLAYMORE_CAP
	for kind in [0, 1, 2, 8]:
		Runner.T.ok(sim._supply_full(p, kind), "kind %d reads full at its cap" % kind)
	p["mg_ammo"] = 0
	p["grenade_ammo"] = 0
	p["vest"] = false
	p["claymores"] = 0
	for kind in [0, 1, 2, 8]:
		Runner.T.ok(not sim._supply_full(p, kind), "kind %d reads usable when empty" % kind)
	# Timed capsules / one-shots always re-apply usefully, so never "full".
	for kind in [4, 5, 7, 9, 10, 11]:
		Runner.T.ok(not sim._supply_full(p, kind), "kind %d is never full" % kind)
