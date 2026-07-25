extends RefCounted
## The spend-wheel shop economy: wave-scaled prices, ammo caps, broke denial.

const Runner := preload("res://tests/run_tests.gd")


func test_supply_cost_scales_with_wave() -> void:
	# Endless creeps on wave; campaign creeps on gates opened (campaign is always
	# wave 0, so the wave creep never fired there and prices were frozen all run).
	# The creep is PROPORTIONAL (+25% of base per depth step) and uncapped.
	var sim := SimWorld.new(7, 1, "endless")
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST, "wave 0 is base price, no surcharge")
	sim.wave = 6
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST * 3 / 2, "wave 6 is 2 depth steps: +50%")
	sim.wave = 600
	Runner.T.eq(sim._supply_cost(0), SimWorld.SHOP_AMMO_COST * 51,
		"the endless creep is UNCAPPED — a capped sink against uncapped income inverts the shop")

	var camp := SimWorld.new(7, 1)
	camp.wave = 6
	Runner.T.eq(camp._supply_cost(0), SimWorld.SHOP_AMMO_COST,
		"campaign ignores wave — it is always wave 0")
	if not camp.gates.is_empty():
		camp.gates[0]["open"] = true
		Runner.T.eq(camp._supply_cost(0), SimWorld.SHOP_AMMO_COST * 5 / 4,
			"campaign creeps on each gate opened instead")


func test_prices_track_income_instead_of_capping_under_it() -> void:
	# THE economy invariant: a full restock must stay a comparable share of what
	# a wave pays out, forever. It used to be ~1 wave's income at wave 10 and
	# under a third of it by wave 100 (prices capped at +150, kill/Clean-Wave/
	# bounty income did not), which made buy-everything strictly optimal.
	var sim := SimWorld.new(7, 1, "endless")
	var ratios: Array[float] = []
	for w in [10, 45, 100]:
		sim.wave = w
		var restock := 0
		for k in SimWorld.SUPPLY_COSTS.size():
			restock += sim._supply_cost(k)
		# A wave's kill income: wave_pending enemies at the cheapest (rusher) rate
		# — a deliberate UNDER-estimate, plus the Clean Wave bonus.
		var enemies: int = SimWorld.WAVE_BASE_ENEMIES + SimWorld.WAVE_ENEMIES_PER_WAVE * (w - 1)
		var income: int = enemies * SimWorld.COIN_RUSHER + sim._econ_scale(40)
		ratios.append(float(restock) / float(income))
		Runner.T.ok(restock >= income / 2,
			"wave %d: a full restock (%d) is still a real spend against a wave's income (%d)"
				% [w, restock, income])
	Runner.T.ok(ratios[2] > ratios[0] / 2.0,
		"the restock/income ratio holds within 2x from wave 10 to wave 100 (was ~6x cheaper)")


func test_clean_wave_bonus_rides_the_price_curve() -> void:
	# The bonus and the prices read the SAME depth scale, so neither can outrun
	# the other. Pinned against the authored value it replaced.
	var sim := SimWorld.new(7, 1, "endless")
	for w in [1, 6, 30, 100]:
		sim.wave = w
		Runner.T.eq(sim._econ_scale(40), 40 + (w / 3) * 10,
			"wave %d Clean Wave bonus is value-identical to the authored curve" % w)


func test_campaign_vest_gate_creeps_like_everything_else() -> void:
	# The vest grants an extra life and used to return early from _supply_cost,
	# so it was the ONLY item that never gate-crept — the cheapest thing on the
	# endgame wheel.
	var camp := SimWorld.new(7, 1)
	Runner.T.eq(camp._supply_cost(2), SimWorld.SHOP_VEST_COST, "gate 0 vest is the base price")
	# Gates stream in as the camera advances, so author the end-of-run state.
	camp.gates.append({"y": 0, "open": true, "b1": {}, "b2": {}, "boss": {}})
	var opened := 0
	for g in camp.gates:
		g["open"] = true
		opened += 1
	Runner.T.eq(camp._supply_cost(2), SimWorld.SHOP_VEST_COST + SimWorld.SHOP_VEST_COST * opened / 4,
		"the vest rides the gate creep")
	Runner.T.ok(camp._supply_cost(2) > camp._supply_cost(0),
		"the extra-life item is never the cheapest thing on the wheel")


func test_try_buy_denies_a_no_op_purchase() -> void:
	# Charging (and crediting score) for a supply that delivers nothing was the
	# same silent no-op _collect_pickups already denies.
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	sim.war_chest = 5000
	var score0: int = sim.score
	p["vest"] = true
	sim._try_buy(p, 2)
	Runner.T.eq(sim.war_chest, 5000, "buying a vest while vested costs nothing")
	Runner.T.eq(sim.score, score0, "...and credits no score")
	Runner.T.eq(sim.vest_buys, 0, "...and does not advance the vest price ladder")
	Runner.T.eq(sim.events[-1]["t"], "deny", "the no-op buy denies loudly")
	Runner.T.eq(sim.events[-1]["why"], "full", "...and says why (not a NEED COINS lie)")

	p["mg_ammo"] = SimWorld.MG_AMMO_MAX
	sim._try_buy(p, 0)
	Runner.T.eq(sim.war_chest, 5000, "buying ammo at the cap costs nothing")
	Runner.T.eq(sim.events[-1]["why"], "full", "...and denies for the same reason")

	# The live buy still works — the guard is not a blanket denial.
	p["vest"] = false
	sim._try_buy(p, 2)
	Runner.T.ok(p["vest"], "a vest the player can actually use is still delivered")
	Runner.T.ok(sim.war_chest < 5000, "...and is paid for")


func test_priced_crate_is_not_billed_when_full() -> void:
	var sim := SimWorld.new(7, 1, "endless")
	var p := sim.players[0]
	sim.war_chest = 5000
	p["vest"] = true
	sim.pickups.clear()
	sim.pickups.append({"x": p["x"], "y": p["y"], "kind": 2, "cost": 60})
	sim._collect_pickups(p, 0)
	Runner.T.eq(sim.war_chest, 5000, "a priced vest crate is not billed to an already-vested player")
	Runner.T.eq(sim.pickups.size(), 1, "...and stays on the ground for when it is worth something")


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
