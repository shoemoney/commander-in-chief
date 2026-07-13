extends RefCounted
## Checksum-coverage tripwire. CLAUDE.md warns that adding a gameplay field and
## forgetting to hash it in checksum() = silent cross-arch desync, with zero
## enforcement. This test knows every field each sim entity currently carries
## (each classified HASHED or EXCLUDED); any NEW, unclassified key fails the
## test until a human decides whether it must join checksum(). It converts an
## invisible determinism footgun into a caught error.
##
## When you add a field: add its key here (HASHED if it affects gameplay and
## should be verified cross-arch, EXCLUDED if it's input-derived/view-only or
## deterministically redundant). If HASHED, also add it to SimWorld.checksum().

const Runner := preload("res://tests/run_tests.gd")

# Per-entity known keys. Union of what checksum() hashes + deliberately-omitted
# deterministic/derived fields. The test fails on ANY key not listed here.
const KNOWN := {
	"player": ["idx", "x", "y", "aim_x", "aim_y", "alive", "deaths", "mg_ammo", "grenade_ammo",
		"fire_cd", "grenade_cd", "broke_timer", "roll_ticks", "roll_cd", "roll_buf",
		"roll_iframe", "roll_dx", "roll_dy", "boost_ticks", "in_tank", "interact_prev", "buy_prev",
		"vest", "hurt_iframes", "pierce_ticks"],
	"bullet": ["x", "y", "vx", "vy", "ttl", "owner"],
	"grenade": ["x", "y", "vx", "vy", "z", "zv", "owner", "shell"],
	"enemy": ["x", "y", "alive", "elite", "kind", "submerged", "lunge_ticks",
		"surface_ticks", "fire_cd", "windup", "aim_lx", "aim_ly", "marked"],
	"bunker": ["x", "y", "alive", "spawn_cd"],
	"pickup": ["x", "y", "kind", "cost"],
	"tank": ["x", "y", "alive", "burning", "fuel", "burn_ticks", "fire_cd", "occupant"],
	"gate": ["y", "open", "b1", "b2", "boss", "final"],
	"boss": ["alive", "hp", "x", "dir", "phase_t", "gate_y"],
	"strike": ["x", "y", "ticks"],
	"water": ["y", "ford_x"],
	"enemy_bullet": ["x", "y", "vx", "vy", "ttl"],
	"mine": ["x", "y", "armed"],
	"observer": ["x", "strike_cd", "spawn_cam"],
	"colossus": ["alive", "hp", "x", "y", "spray_cd", "volley_cd", "spawn_cd",
		"core_cd", "core_open"],
}


func _check(label: String, d: Dictionary) -> void:
	var known: Array = KNOWN[label]
	for k in d.keys():
		Runner.T.ok(known.has(k),
			"UNCLASSIFIED %s field '%s' — classify it in test_checksum_coverage KNOWN and, if it affects gameplay, add it to SimWorld.checksum()" % [label, k])


func test_all_entity_fields_are_classified() -> void:
	# Populate every entity type across both modes, then verify no stray keys.
	var seen := {}
	for setup in ["campaign", "endless", "colossus"]:
		var sim := _stage(setup)
		for i in 400:
			sim.step(_inputs(sim))
			# Record kinds every tick — short-lived spawns (a sapper that lays its
			# mines then dies, a ghillie that reveals and is shot) would otherwise
			# vanish before the final-state field sweep below. Their fields are all
			# already-classified (shared with sniper/frogman), so no field gap.
			for e in sim.enemies:
				seen[e["kind"]] = true
		for p in sim.players:
			_check("player", p)
		for b in sim.bullets:
			_check("bullet", b)
		for g in sim.grenades:
			_check("grenade", g)
		for e in sim.enemies:
			_check("enemy", e)
			seen[e["kind"]] = true
		for bk in sim.bunkers:
			_check("bunker", bk)
		for pk in sim.pickups:
			_check("pickup", pk)
		for t in sim.tanks:
			_check("tank", t)
		for eb in sim.enemy_bullets:
			_check("enemy_bullet", eb)
		for m in sim.mines:
			_check("mine", m)
		for s in sim.strikes:
			_check("strike", s)
		for w in sim.waters:
			_check("water", w)
		for g in sim.gates:
			_check("gate", g)
			if not g["boss"].is_empty():
				_check("boss", g["boss"])
		if not sim.observer.is_empty():
			_check("observer", sim.observer)
		if not sim.colossus.is_empty():
			_check("colossus", sim.colossus)
		if not sim.endless_boss.is_empty():
			_check("boss", sim.endless_boss)
	for k in ["rusher", "elite", "frogman", "grenadier", "sniper", "shield", "sapper", "ghillie"]:
		Runner.T.ok(seen.has(k), "coverage staged enemy kind '%s'" % k)


func _stage(kind: String) -> SimWorld:
	if kind == "endless":
		return SimWorld.new(0xBEEF, 2, "endless")
	var sim := SimWorld.new(0xBEEF, 2)
	if kind == "colossus":
		sim.gates.append({"y": sim.camera_top + 40 * Fixed.ONE, "open": false,
			"b1": {}, "b2": {}, "boss": {}, "final": true})
	# Seed a water band + frogman so those entity types appear.
	sim.waters.append({"y": sim.camera_top - 100 * Fixed.ONE, "ford_x": 400 * Fixed.ONE})
	sim._spawn_frogman(300 * Fixed.ONE, sim.camera_top - 90 * Fixed.ONE)
	# Directly stage the endless ranged archetypes — the 400-tick budget never
	# organically reaches wave 3, so the tripwire wouldn't otherwise cover them.
	sim._spawn_special(200 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "grenadier")
	sim._spawn_special(440 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "sniper")
	sim._spawn_special(320 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "shield")
	sim._spawn_special(260 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "sapper")
	sim._spawn_special(380 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "ghillie")
	return sim


func _inputs(sim: SimWorld) -> Array:
	var arr: Array = []
	var inp := SimInput.new()
	inp.move_y = -256
	inp.fire = true
	inp.grenade = true
	for i in sim.players.size():
		arr.append(inp)
	return arr
