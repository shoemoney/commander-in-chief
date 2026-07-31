extends SceneTree
## Hulk-salvage-at-cap probe: a player at GRENADE_AMMO_MAX salvaging a
## smoldering hulk should, by the game's own _supply_full rule ("none of them
## can bill for a no-op"), keep the cover. What actually happens?

func _init() -> void:
	var sim := SimWorld.new(1, 1, "campaign")
	sim.god_mode = true
	var p: Dictionary = sim.players[0]
	p["grenade_ammo"] = SimWorld.GRENADE_AMMO_MAX
	# Stage a dead, smoldering hulk next to the player.
	sim.tanks.append({"x": p["x"], "y": p["y"], "alive": false, "burning": false,
		"burn_ticks": 100, "occupant": -1, "fuel": 0, "fire_cd": 0})
	var before_ammo: int = p["grenade_ammo"]
	var ok: bool = sim._try_salvage_hulk(p)
	var after_ammo: int = p["grenade_ammo"]
	var hulk_bt: int = sim.tanks[0]["burn_ticks"]
	print("salvage returned: ", ok)
	print("grenades before/after: ", before_ammo, " -> ", after_ammo)
	print("hulk burn_ticks after salvage: ", hulk_bt, " (100 = cover kept, 0 = cover stripped)")
	for ev in sim.events:
		if ev["t"] == "hulk_salvage":
			print("event granted n=", ev.get("n", -1))
	quit()
