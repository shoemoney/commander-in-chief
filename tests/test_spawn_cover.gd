extends RefCounted
## Spawn-seam de-confliction: no spawner may birth a unit inside geometry that
## _step_projectiles treats as armor.
##
## The defect class: rooted archetypes (ROOTED_KINDS) never write x or y after
## birth, so a unit born inside a bullet-blocking AABB is un-shootable from the
## side the cover faces — it holds an endless wave open forever. The old guard
## lived at ONE caller (_spawn_enemy), checked ONE of the four blocking
## families (rocks), and nudged by a single +24px that could not clear a kind-2
## ruined wall at all. Nine rooted call sites bypassed it entirely.

const Runner := preload("res://tests/run_tests.gd")

const BX := 320 * SimWorld.F_ONE
const BY := -200 * SimWorld.F_ONE


func _fresh() -> SimWorld:
	var sim := SimWorld.new(11, 1, "endless")
	sim.rocks.clear()
	sim.sandbags.clear()
	sim.tanks.clear()
	sim.bunkers.clear()
	sim.enemies.clear()
	return sim


func _spawn_rooted(sim: SimWorld, kind: String, x: int, y: int) -> void:
	## Route through the REAL spawners, exactly as the field/wave code does.
	if kind == "mg_nest":
		sim._spawn_mg_nest(x, y)
	elif kind == "broadcast":
		sim._spawn_broadcast(x, y)
	else:
		sim._spawn_special(x, y, kind)


func _blockers() -> Array:
	## One entry per bullet-blocking family _step_projectiles scans, each placed
	## so its AABB is centred on (BX, BY + dy). Rock kinds are ITERATED off
	## ROCK_KIND_EXT, so a new kind is covered the day it lands. Non-solid kinds
	## (grass) are listed and skipped: bullets pass through them, so birthing
	## there is legal and pinning it would be wrong.
	var out: Array = []
	for k in SimWorld.ROCK_KIND_EXT.size():
		var ext: Array = SimWorld.ROCK_KIND_EXT[k]
		out.append({
			"name": "rock kind %d" % k,
			"family": "rock",
			"solid": ext[2] == 1,
			"hw": int(ext[0]) * SimWorld.F_ONE,
			"hh": int(ext[1]) * SimWorld.F_ONE,
			"kind": k,
		})
	out.append({"name": "sandbag (horizontal)", "family": "sandbag", "solid": true,
		"hw": SimWorld.SANDBAG_HALF_W, "hh": SimWorld.SANDBAG_HALF_H, "vertical": 0})
	out.append({"name": "sandbag (vertical)", "family": "sandbag", "solid": true,
		"hw": SimWorld.SANDBAG_HALF_H, "hh": SimWorld.SANDBAG_HALF_W, "vertical": 1})
	out.append({"name": "tank hulk (cover)", "family": "hulk", "solid": true,
		"hw": SimWorld.HULK_HALF_W, "hh": SimWorld.HULK_HALF_H})
	out.append({"name": "live bunker", "family": "bunker", "solid": true,
		"hw": SimWorld.BUNKER_W / 2, "hh": SimWorld.BUNKER_H / 2})
	return out


func _place(sim: SimWorld, cfg: Dictionary, cy: int) -> void:
	match cfg["family"]:
		"rock":
			sim.rocks.append({"x": BX, "y": cy, "kind": cfg["kind"]})
		"sandbag":
			sim.sandbags.append({"x": BX, "y": cy, "vertical": cfg["vertical"]})
		"hulk":
			sim.tanks.append({"x": BX, "y": cy, "alive": false, "burning": true,
				"fuel": 0, "burn_ticks": 200, "crew_ring_ticks": -1,
				"fire_cd": 0, "occupant": -1})
		"bunker":
			sim.bunkers.append({"x": BX - SimWorld.BUNKER_W / 2,
				"y": cy - SimWorld.BUNKER_H / 2, "alive": true, "spawn_cd": 9999})


func test_no_spawner_births_a_unit_inside_bullet_cover() -> void:
	## THE CLASS, derived from source: every rooted archetype x every blocking
	## family x 41 spawn offsets x 3 blocker rows. ~2,900 real spawner calls.
	var cfgs := _blockers()
	var violations := 0
	var first := ""
	var calls := 0
	for kind in SimWorld.ROOTED_KINDS:
		for cfg in cfgs:
			for dy in [-8, 0, 8]:
				var cy: int = BY + dy * SimWorld.F_ONE
				for step in 41:
					var off: int = (step - 20) * SimWorld.F_ONE
					var sim := _fresh()
					_place(sim, cfg, cy)
					_spawn_rooted(sim, kind, BX + off, BY)
					calls += 1
					if not cfg["solid"]:
						continue   # bullets pass through: birthing here is legal
					var e: Dictionary = sim.enemies[-1]
					var inside: bool = absi(e["x"] - BX) <= int(cfg["hw"]) \
						and absi(e["y"] - cy) <= int(cfg["hh"])
					if inside:
						violations += 1
						if first == "":
							first = "%s in %s (spawn offset %dpx, row %+dpx) -> x=%d" % [
								kind, cfg["name"], (step - 20), dy, e["x"] / SimWorld.F_ONE]
	Runner.T.ok(calls >= 2900, "cross-product exercised the real spawners (%d calls)" % calls)
	Runner.T.eq(violations, 0,
		"no rooted spawn lands inside bullet cover (first: %s)" % first)


func test_rooted_unit_born_on_cover_is_killable_from_the_south() -> void:
	## THE SHOT-BLOCKING PREDICATE, not containment. A kind-0 rock (half 16x12)
	## out-reaches the ghillie's 10px BULLET_HIT_RADIUS: a round aimed due north
	## is eaten by the rock two sample steps BEFORE it is close enough to count,
	## so the unit is immortal from the whole southern arc. mg_nest (16px) and
	## broadcast (17px) are the control arms — their reach exceeds the rock's
	## south face, so they die even on the unfixed build and prove the harness
	## can go green.
	##
	## Window: 90 ticks per row. Longest legitimate kill measured on this rig is
	## 33 ticks (clear-nest control) — 2.7x headroom.
	for kind in SimWorld.ROOTED_KINDS:
		var killed_from: Array[int] = []
		for row in [48, 52, 56, 60, 64, 68]:
			var sim := SimWorld.new(11, 1, "endless")
			sim.god_mode = true
			sim.rocks.clear()
			sim.sandbags.clear()
			sim.tanks.clear()
			sim.bunkers.clear()
			sim.enemies.clear()
			sim.rocks.append({"x": BX, "y": BY, "kind": 0})
			_spawn_rooted(sim, kind, BX, BY)
			var e: Dictionary = sim.enemies[-1]
			var px: int = e["x"]
			var py: int = e["y"] + row * SimWorld.F_ONE
			var inp := SimInput.new()
			inp.aim_y = -256
			inp.fire = true
			for t in 90:
				# Hold the arena still: only OUR unit, player pinned due south.
				for i in range(sim.enemies.size() - 1, -1, -1):
					if not is_same(sim.enemies[i], e):
						sim.enemies.remove_at(i)
				e["submerged"] = false   # revealed: this is the shot test, not the cloak test
				var p: Dictionary = sim.players[0]
				p["x"] = px
				p["y"] = py
				p["down_ticks"] = 0
				sim.step([inp])
				if not e["alive"]:
					killed_from.append(row)
					break
		Runner.T.ok(not killed_from.is_empty(),
			"%s born on a kind-0 rock is killable from the south (rows that worked: %s)"
				% [kind, str(killed_from)])


func test_spawn_clear_x_is_deterministic_and_terminates() -> void:
	## Pins the helper's lint_sim contract: pure, integer-only, terminating.
	var sim := _fresh()
	Runner.T.ok(sim.has_method("_spawn_clear_x"),
		"SimWorld exposes the spawn-seam de-confliction helper")
	if not sim.has_method("_spawn_clear_x"):
		return
	sim.rocks.append({"x": BX, "y": BY, "kind": 0})
	var a: int = sim._spawn_clear_x(BX, BY)
	var b: int = sim._spawn_clear_x(BX, BY)
	Runner.T.eq(a, b, "same input twice -> same output")
	Runner.T.ok(absi(a - BX) > 16 * SimWorld.F_ONE, "it actually left the rock")
	Runner.T.eq(sim._spawn_clear_x(BX + 200 * SimWorld.F_ONE, BY),
		BX + 200 * SimWorld.F_ONE, "a clear x is returned untouched")
	# Wall the whole row: every 4px probe is blocked, so the loop must give up
	# and hand back its input rather than spin.
	sim.rocks.clear()
	for wx in range(0, 700, 16):
		sim.rocks.append({"x": wx * SimWorld.F_ONE, "y": BY, "kind": 2})
	Runner.T.eq(sim._spawn_clear_x(BX, BY), BX,
		"a fully walled row terminates and returns the input")
