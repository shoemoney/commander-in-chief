extends "res://src/main.gd"

enum Intent { ADVANCE, COMBAT, DEMOLITION, BOSS, RECOVER }

const OBSERVATION_POLICY := "Current viewport entities and geometry, surfaced hostiles, visible projectile motion, strike and vent telegraphs, current drawn Colossus phase rings, own HUD resources and cooldowns. No future simulation, offscreen target selection, hidden hostiles, or gameplay state writes. Input API verification only; physical devices remain unverified."
const DIRECTIONS := [Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
	Vector2(-0.707107, -0.707107), Vector2(0.707107, -0.707107),
	Vector2(-0.707107, 0.707107), Vector2(0.707107, 0.707107)]

var controller_history: Dictionary = {}
var controller_intents: Dictionary = {}
var controller_player_history: Dictionary = {}
var controller_navigation_events: Array[Dictionary] = []
var _controller_memory: Dictionary = {}
var _target_observations: Dictionary = {}
var _cover_observation_tick := -1
var _cover_observation: Array[Rect2] = []
var _route_observations: Dictionary = {}
var _cache_pursuits: Dictionary = {}
var _ignored_caches: Dictionary = {}


func _gather_inputs() -> Array[SimInput]:
	var checksum_before := sim.checksum()
	var inputs: Array[SimInput] = []
	for pi in sim.players.size():
		inputs.append(_controller_input(pi))
	if sim.checksum() != checksum_before:
		push_error("Full-run input controller changed simulation state while choosing inputs")
	return inputs


func _point(entity: Dictionary) -> Vector2:
	return Vector2(float(entity["x"]) / Fixed.ONE, float(entity["y"]) / Fixed.ONE)


func _visible(point: Vector2) -> bool:
	var top := float(sim.camera_top) / Fixed.ONE
	return point.x >= 0.0 and point.x <= 640.0 and point.y >= top and point.y <= top + 360.0


func _controller_input(pi: int) -> SimInput:
	var p: Dictionary = sim.players[pi]
	var input := SimInput.new()
	input.fire = true
	if not bool(p["alive"]):
		input.revive = true
		_count_intent(pi, Intent.RECOVER)
		return input
	var pos := _point(p)
	var target := _hostile_target(pos)
	var objective := _objective_target(pos)
	var aim_point := pos + Vector2.UP * 300.0
	var goal := pos + Vector2.UP * 160.0
	var intent := Intent.ADVANCE
	var throw := false
	if not objective.is_empty():
		var obj_pos: Vector2 = objective["point"]
		if objective["kind"] == "bunker":
			intent = Intent.DEMOLITION
			goal = obj_pos + Vector2(0.0, 98.0)
			var distance := pos.distance_to(obj_pos)
			if distance >= 72.0 and distance <= 125.0 and int(p["grenade_ammo"]) > 0 and int(p["grenade_cd"]) == 0:
				aim_point = obj_pos
				throw = sim.tick_count % 2 == 0
			elif not target.is_empty():
				aim_point = target["point"]
			else:
				aim_point = obj_pos
		else:
			intent = Intent.BOSS
			aim_point = _lead_target("%s_player_%d" % [String(objective.get("observation_key", "fortress")), pi], obj_pos, pos)
			var side := 1.0 if pos.x >= obj_pos.x else -1.0
			goal = obj_pos + Vector2(side * 130.0, 145.0)
			if objective["kind"] == "colossus" and int(objective.get("core_open", 0)) <= 0 and not target.is_empty():
				aim_point = target["point"]
			elif pos.distance_to(obj_pos) <= 120.0 and int(p["grenade_ammo"]) > 0 and int(p["grenade_cd"]) == 0:
				throw = sim.tick_count % 2 == 0
	elif not target.is_empty():
		intent = Intent.COMBAT
		aim_point = target["point"]
		var target_pos: Vector2 = target["point"]
		if pos.distance_to(target_pos) < 110.0:
			goal = pos + (pos - target_pos).normalized() * 100.0
		else:
			goal = Vector2(pos.x, pos.y - 50.0)
		if String(target.get("kind", "")) == "shield" and pos.distance_to(target_pos) <= 120.0 and int(p["grenade_ammo"]) > 0 and int(p["grenade_cd"]) == 0:
			throw = sim.tick_count % 2 == 0
	var regroup := _partner_catchup(pi, pos)
	if not regroup.is_empty():
		goal = regroup["point"]
		intent = Intent.ADVANCE
	elif intent != Intent.BOSS:
		var cache := _free_cache_target(pi, p, pos)
		if not cache.is_empty():
			goal = cache["point"]
	var move := _steer(pi, pos, goal)
	var aim := (aim_point - pos).normalized()
	input.move_x = _quantize_axis(move.x)
	input.move_y = _quantize_axis(move.y)
	input.aim_x = _quantize_axis(aim.x)
	input.aim_y = _quantize_axis(aim.y)
	input.grenade = throw
	input.roll = int(p["roll_cd"]) == 0 and _danger(pos, Vector2.ZERO) > 80.0 and sim.tick_count % 2 == 0
	if int(p["in_tank"]) >= 0:
		var tank: Dictionary = sim.tanks[int(p["in_tank"])]
		input.interact = bool(tank["burning"]) and sim.tick_count % 2 == 0
		input.roll = false
	if sim.tick_count % 2 == 0:
		if int(p["mg_ammo"]) <= 35 and sim.war_chest >= sim.supply_price(p, 0):
			input.buy = 1
		elif int(p["grenade_ammo"]) < 3 and sim.war_chest >= sim.supply_price(p, 1):
			input.buy = 2
		elif not bool(p["vest"]) and sim.war_chest >= sim.supply_price(p, 2) + sim.supply_price(p, 0):
			input.buy = 3
	_count_intent(pi, intent)
	return input


func _lead_target(key: String, point: Vector2, origin: Vector2) -> Vector2:
	var previous: Dictionary = _target_observations.get(key, {})
	var velocity := Vector2.ZERO
	if not previous.is_empty():
		var ticks := maxi(sim.tick_count - int(previous["tick"]), 1)
		velocity = (point - Vector2(previous["point"])) / float(ticks)
	_target_observations[key] = {"point": point, "tick": sim.tick_count}
	return point + velocity * minf(point.distance_to(origin) / 6.0, 40.0)


func _count_intent(pi: int, intent: int) -> void:
	var name: String = Intent.keys()[intent]
	controller_intents[pi] = name
	controller_history[name] = int(controller_history.get(name, 0)) + 1
	var player_key := str(pi)
	if not controller_player_history.has(player_key):
		controller_player_history[player_key] = {}
	var player_history: Dictionary = controller_player_history[player_key]
	player_history[name] = int(player_history.get(name, 0)) + 1


func _hostile_target(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for e in sim.enemies:
		if not bool(e["alive"]) or bool(e.get("submerged", false)) or String(e.get("kind", "")) == "pilot":
			continue
		var point := _point(e)
		if not _visible(point):
			continue
		var distance := pos.distance_to(point)
		var value := distance
		if String(e.get("kind", "")) in ["grenadier", "sniper", "mg_nest", "broadcast"]:
			value -= 40.0
		if not _shot_clear(pos, point):
			value += 250.0
		if value < best_score:
			best_score = value
			best = {"point": point, "kind": e.get("kind", "")}
	if not sim.observer.is_empty() and bool(sim.observer.get("alive", true)):
		var observer_pos := Vector2(float(sim.observer["x"]) / Fixed.ONE,
			float(sim.camera_top + SimWorld.OBSERVER_Y_OFFSET) / Fixed.ONE)
		if _visible(observer_pos) and pos.distance_to(observer_pos) - 60.0 < best_score:
			best = {"point": observer_pos, "kind": "observer"}
	return best


func _objective_target(pos: Vector2) -> Dictionary:
	if not sim.colossus.is_empty() and bool(sim.colossus["alive"]) and _visible(_point(sim.colossus)):
		return {"point": _point(sim.colossus), "kind": "colossus", "core_open": sim.colossus["core_open"], "observation_key": "fortress"}
	for gate in sim.gates:
		if bool(gate["open"]) or gate["boss"].is_empty() or not bool(gate["boss"]["alive"]):
			continue
		var boss: Dictionary = gate["boss"]
		var point := Vector2(float(boss["x"]) / Fixed.ONE, float(boss["gate_y"] - SimWorld.BOSS_Y_OFFSET) / Fixed.ONE)
		if _visible(point):
			return {"point": point, "kind": "gunship", "observation_key": "gunship_%d" % int(boss["gate_y"])}
	var best: Dictionary = {}
	var best_distance := INF
	for bunker in sim.bunkers:
		if not bool(bunker["alive"]):
			continue
		var point := _point(bunker) + Vector2(24.0, 16.0)
		if not _visible(point) or point.y > pos.y + 100.0:
			continue
		var distance := pos.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = {"point": point, "kind": "bunker"}
	return best


func _partner_catchup(pi: int, pos: Vector2) -> Dictionary:
	for other in sim.players.size():
		if other == pi:
			continue
		var partner: Dictionary = sim.players[other]
		var point := _point(partner)
		if bool(partner["alive"]) and _visible(point) and pos.y - point.y > 120.0:
			return {"point": Vector2(pos.x, point.y + 60.0)}
	return {}


func _free_cache_target(pi: int, p: Dictionary, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 130.0
	for pickup in sim.pickups:
		if int(pickup.get("cost", 0)) != 0:
			continue
		var kind := int(pickup["kind"])
		var needed := kind == 0 and int(p["mg_ammo"]) < 65 or kind == 1 and int(p["grenade_ammo"]) < 6 or kind == 2 and not bool(p["vest"])
		if not needed:
			continue
		var key := "%d_%d_%d_%d" % [pi, kind, int(pickup["x"]), int(pickup["y"])]
		if int(_ignored_caches.get(key, -1)) > sim.tick_count:
			continue
		var point := _point(pickup)
		var distance := pos.distance_to(point)
		if _visible(point) and distance < best_distance:
			best_distance = distance
			best = {"point": point, "key": key}
	if not best.is_empty():
		var key: String = best["key"]
		_cache_pursuits[key] = int(_cache_pursuits.get(key, 0)) + 1
		if int(_cache_pursuits[key]) >= 180:
			_ignored_caches[key] = sim.tick_count + 600
			_cache_pursuits.erase(key)
			controller_navigation_events.append({"tick": sim.tick_count, "player": pi,
				"reason": "pickup_pursuit_budget_expired", "point": [best["point"].x, best["point"].y]})
			return {}
	return best


func _steer(pi: int, pos: Vector2, goal: Vector2) -> Vector2:
	var top := float(sim.camera_top) / Fixed.ONE
	goal.x = clampf(goal.x, 40.0, 600.0)
	goal.y = clampf(goal.y, top + 28.0, top + 326.0)
	goal = _route_goal(pi, pos, goal)
	var memory: Dictionary = _controller_memory.get(pi, {"position": pos, "stuck": 0})
	if pos.distance_to(memory["position"]) < 0.2:
		memory["stuck"] = int(memory["stuck"]) + 1
	else:
		memory["stuck"] = 0
	memory["position"] = pos
	_controller_memory[pi] = memory
	var best_move := Vector2.ZERO
	var best_score := INF
	for direction in DIRECTIONS:
		var movement: Vector2 = direction
		var next := pos + movement * 2.4
		var future := pos + movement * 19.2
		if _blocked(next, pos):
			continue
		var score := future.distance_to(goal) + _danger(pos, movement)
		if _blocked(future, pos):
			score += 80.0
		if int(memory["stuck"]) > 20 and movement.y < -0.5:
			score += 60.0
		if int(memory["stuck"]) > 20 and absf(movement.x) > 0.5:
			score -= 30.0
		if score < best_score:
			best_score = score
			best_move = movement
	return best_move


func _route_goal(pi: int, pos: Vector2, goal: Vector2) -> Vector2:
	if _walking_clear(pos, goal):
		_route_observations.erase(pi)
		return goal
	var cached: Dictionary = _route_observations.get(pi, {})
	if not cached.is_empty() and sim.tick_count - int(cached["tick"]) < 24 and Vector2(cached["goal"]).distance_to(goal) < 60.0:
		var waypoint: Vector2 = cached["waypoint"]
		if pos.distance_to(waypoint) > 12.0 and _walking_clear(pos, waypoint):
			return waypoint
	# A bounded route over the currently visible screen. Every vertex and edge
	# reads the same observed collision geometry used by immediate steering.
	const COLS := 30
	const ROWS := 16
	const SPACING := 20.0
	var origin := Vector2(24.0, float(sim.camera_top) / Fixed.ONE + 24.0)
	var points: Array[Vector2] = []
	var blocked: Array[bool] = []
	var parents: Array[int] = []
	var distances: Array[int] = []
	var start := 0
	var start_distance := INF
	for row in ROWS:
		for col in COLS:
			var point := origin + Vector2(col, row) * SPACING
			points.append(point)
			blocked.append(_blocked(point, pos))
			parents.append(-1)
			distances.append(-1)
			var distance := pos.distance_to(point)
			if not blocked[-1] and distance < start_distance and _walking_clear(pos, point):
				start_distance = distance
				start = points.size() - 1
	if start_distance == INF:
		return goal
	var queue: Array[int] = [start]
	distances[start] = 0
	var cursor := 0
	var best := start
	var best_score := points[start].distance_to(goal)
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		var score := points[current].distance_to(goal) + float(distances[current]) * 0.2
		if score < best_score:
			best_score = score
			best = current
		var row := current / COLS
		var col := current % COLS
		for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var next_col: int = col + delta.x
			var next_row: int = row + delta.y
			if next_col < 0 or next_col >= COLS or next_row < 0 or next_row >= ROWS:
				continue
			var next := next_row * COLS + next_col
			if blocked[next] or distances[next] >= 0 or not _walking_clear(points[current], points[next]):
				continue
			parents[next] = current
			distances[next] = distances[current] + 1
			queue.append(next)
	var path: Array[int] = []
	while best != start and best >= 0:
		path.push_front(best)
		best = parents[best]
	var waypoint := points[start]
	for vertex in path:
		if pos.distance_to(points[vertex]) > 100.0 or not _walking_clear(pos, points[vertex]):
			break
		waypoint = points[vertex]
	_route_observations[pi] = {"tick": sim.tick_count, "goal": goal, "waypoint": waypoint}
	return waypoint


func _walking_clear(from: Vector2, to: Vector2) -> bool:
	var samples := maxi(int(ceil(from.distance_to(to) / 8.0)), 1)
	var previous := from
	for sample in range(1, samples + 1):
		var point := from.lerp(to, float(sample) / float(samples))
		if _blocked(point, previous):
			return false
		previous = point
	return true


func _danger(pos: Vector2, movement: Vector2) -> float:
	var danger := 0.0
	var velocity := movement * 2.4
	for bullet in sim.enemy_bullets:
		var point := _point(bullet)
		if not _visible(point) or pos.distance_to(point) > 120.0:
			continue
		var relative := point - pos
		var bullet_velocity := Vector2(float(bullet["vx"]) / Fixed.ONE, float(bullet["vy"]) / Fixed.ONE)
		var relative_velocity := bullet_velocity - velocity
		var closest_tick := clampf(-relative.dot(relative_velocity) / maxf(relative_velocity.length_squared(), 0.001), 0.0, 16.0)
		var closest := (relative + relative_velocity * closest_tick).length()
		if closest < 24.0 and _shot_clear(point, pos + velocity * closest_tick):
			danger += (24.0 - closest) * 25.0
	for strike in sim.strikes:
		var point := _point(strike)
		if _visible(point):
			var distance := (pos + velocity * minf(float(strike["ticks"]), 16.0)).distance_to(point)
			if distance < 50.0:
				danger += (50.0 - distance) * 30.0
	for mine in sim.mines:
		if not bool(mine["armed"]):
			continue
		var point := _point(mine)
		if _visible(point):
			var distance := (pos + velocity * 8.0).distance_to(point)
			if distance < 28.0:
				danger += (28.0 - distance) * 35.0
	# Match the renderer's current warn/jet classification, not a future phase.
	for vent in sim.vents:
		var point := _point(vent)
		if not _visible(point):
			continue
		var phase: int = posmod(sim.tick_count + 7 * (int(vent["x"]) / Fixed.ONE), SimWorld.VENT_CYCLE_TICKS)
		var warn_at := SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS - SimWorld.VENT_WARN_TICKS
		if phase >= warn_at:
			var radius := float(SimWorld.VENT_HURT_RADIUS) / Fixed.ONE + 12.0
			var distance := (pos + velocity * 8.0).distance_to(point)
			if distance < radius:
				danger += (radius - distance) * 40.0
	for e in sim.enemies:
		if not bool(e["alive"]) or bool(e.get("submerged", false)) or String(e.get("kind", "")) == "pilot":
			continue
		var point := _point(e)
		if _visible(point):
			var distance := (pos + velocity * 8.0).distance_to(point)
			if distance < 32.0:
				danger += (32.0 - distance) * 15.0
	if not sim.colossus.is_empty() and bool(sim.colossus["alive"]) and _visible(_point(sim.colossus)):
		var distance := (pos + velocity * 8.0).distance_to(_point(sim.colossus))
		var radius := float(SimWorld.COLOSSUS_RING_INNER + (sim.colossus_phase() - 1) * SimWorld.COLOSSUS_RING_STEP) + 12.0
		if distance < radius:
			danger += (radius - distance) * 15.0
	return danger


func _blocked(point: Vector2, previous: Vector2) -> bool:
	var top := float(sim.camera_top) / Fixed.ONE
	var nearest := Vector2(clampf(point.x, 24.0, 616.0), clampf(point.y, top + 18.0, top + 336.0))
	var previous_nearest := Vector2(clampf(previous.x, 24.0, 616.0), clampf(previous.y, top + 18.0, top + 336.0))
	if point.distance_to(nearest) > 0.0 and point.distance_to(nearest) >= previous.distance_to(previous_nearest):
		return true
	for rect in _visible_cover():
		if rect.has_point(point) and not rect.has_point(previous):
			return true
	var fx := int(point.x * Fixed.ONE)
	var fy := int(point.y * Fixed.ONE)
	var previous_x := int(previous.x * Fixed.ONE)
	var previous_y := int(previous.y * Fixed.ONE)
	if sim._lane_blocked(fx, fy) and not sim._lane_blocked(previous_x, previous_y):
		return true
	if sim._barricade_solid(fx, fy) and not sim._barricade_solid(previous_x, previous_y):
		return true
	for gate in sim.gates:
		var gy := float(gate["y"]) / Fixed.ONE
		if not bool(gate["open"]) and gy >= top and gy <= top + 360.0 and point.y < gy + 20.0 and point.y <= previous.y:
			return true
		var fork_x := int(gate.get("fork_x", 0))
		if fork_x != 0 and sim._in_fork_divider(fx, fy, int(gate["y"]), fork_x) and not sim._in_fork_divider(int(previous.x * Fixed.ONE), int(previous.y * Fixed.ONE), int(gate["y"]), fork_x):
			return true
	return false


func _visible_cover() -> Array[Rect2]:
	if _cover_observation_tick == sim.tick_count:
		return _cover_observation
	var rects: Array[Rect2] = []
	for rock in sim.rocks:
		if SimWorld._rk_solid(rock) and _visible(_point(rock)):
			var half := Vector2(float(SimWorld._rk_hw(rock)) / Fixed.ONE, float(SimWorld._rk_hh(rock)) / Fixed.ONE)
			rects.append(Rect2(_point(rock) - half, half * 2.0))
	for bag in sim.sandbags:
		if _visible(_point(bag)):
			var half := Vector2(float(SimWorld._sb_hw(bag)) / Fixed.ONE, float(SimWorld._sb_hh(bag)) / Fixed.ONE)
			rects.append(Rect2(_point(bag) - half, half * 2.0))
	for tank in sim.tanks:
		if _visible(_point(tank)) and (bool(tank["alive"]) and int(tank["occupant"]) < 0 or not bool(tank["alive"]) and int(tank["burn_ticks"]) > 0):
			rects.append(Rect2(_point(tank) - Vector2(16.0, 23.0), Vector2(32.0, 46.0)))
	_cover_observation_tick = sim.tick_count
	_cover_observation = rects
	return _cover_observation


func _shot_clear(from: Vector2, to: Vector2) -> bool:
	for rect in _visible_cover():
		for sample in range(1, 9):
			if rect.has_point(from.lerp(to, float(sample) / 9.0)):
				return false
	return true
