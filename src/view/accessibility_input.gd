class_name AccessibilityInput
extends RefCounted

const ACTIONS: Array[String] = ["grenade", "roll", "interact", "revive", "buy"]
const DEFAULTS := {
	"single_stick_p1": false,
	"single_stick_p2": false,
	"classic_aim_p1": false,
	"classic_aim_p2": false,
	"aim_assist": 0,
	"toggle_grenade": false,
	"toggle_roll": false,
	"toggle_interact": false,
	"toggle_revive": false,
	"toggle_buy": false,
}
const AUTO_RANGE := 320.0
const ASSIST_RANGE: Array[float] = [0.0, 240.0, 320.0]
const ASSIST_CONE_DEGREES: Array[float] = [0.0, 12.0, 24.0]
const ASSIST_CORRECTION: Array[float] = [0.0, 0.35, 0.65]
const DETENT_COUNT := 12

class ActionLatch:
	extends RefCounted
	var pressed := false
	var active := false
	var suppressed := false

class SeatState:
	extends RefCounted
	var actions: Dictionary[String, ActionLatch] = {}
	var detent := -1
	var detent_changed := false

var _settings: Dictionary = DEFAULTS.duplicate()
var _seats: Array[SeatState] = [SeatState.new(), SeatState.new()]


func configure(settings: Dictionary) -> void:
	var next: Dictionary = DEFAULTS.duplicate()
	for key in DEFAULTS:
		if key == "aim_assist":
			next[key] = clampi(int(settings.get(key, DEFAULTS[key])), 0, 2)
		else:
			next[key] = bool(settings.get(key, DEFAULTS[key]))
	if next != _settings:
		_settings = next
		reset()


func resolve_aim(seat: int, movement: Vector2, requested: Vector2, world: SimWorld) -> Vector2:
	if seat < 0 or seat >= _seats.size():
		return requested
	var single_stick: bool = _settings["single_stick_p%d" % (seat + 1)]
	var classic: bool = _settings["classic_aim_p%d" % (seat + 1)]
	var tier: int = _settings["aim_assist"]
	var result := requested
	if world != null and seat < world.players.size() and world.players[seat]["alive"]:
		if single_stick and requested == Vector2.ZERO:
			var target: Vector2 = _target_direction(world, seat, Vector2.ZERO, AUTO_RANGE, PI)
			if target != Vector2.ZERO:
				result = target
			elif movement != Vector2.ZERO:
				result = movement.normalized()
			else:
				var player: Dictionary = world.players[seat]
				result = Vector2(player["aim_x"], player["aim_y"]).normalized()
				if result == Vector2.ZERO:
					result = Vector2.UP
		elif tier > 0 and requested != Vector2.ZERO:
			var target: Vector2 = _target_direction(world, seat, requested,
				ASSIST_RANGE[tier], deg_to_rad(ASSIST_CONE_DEGREES[tier]))
			if target != Vector2.ZERO:
				var angle := lerp_angle(requested.angle(), target.angle(), ASSIST_CORRECTION[tier])
				result = Vector2.from_angle(angle) * requested.length()
	if classic and result != Vector2.ZERO:
		var detent: int = posmod(int(round(result.angle() * DETENT_COUNT / TAU)), DETENT_COUNT)
		var state: SeatState = _seats[seat]
		if state.detent >= 0 and state.detent != detent:
			state.detent_changed = true
		state.detent = detent
		result = Vector2.from_angle(float(detent) * TAU / DETENT_COUNT) * result.length()
	return result


func transform_action(seat: int, action: String, pressed: bool) -> bool:
	var latch: ActionLatch = _action_latch(seat, action)
	if latch == null:
		return pressed
	if latch.suppressed:
		latch.pressed = pressed
		if not pressed:
			latch.suppressed = false
		return false
	var toggle: bool = _settings["toggle_" + action]
	if toggle and pressed and not latch.pressed:
		latch.active = not latch.active
	latch.pressed = pressed
	return latch.active if toggle else pressed


func cancel_action(seat: int, action: String) -> void:
	var latch: ActionLatch = _action_latch(seat, action)
	if latch != null:
		latch.active = false


func prime_action(seat: int, action: String, pressed: bool) -> void:
	var latch: ActionLatch = _action_latch(seat, action)
	if latch != null:
		latch.active = false
		latch.pressed = pressed
		latch.suppressed = pressed


func reset() -> void:
	for state in _seats:
		state.actions.clear()
		state.detent = -1
		state.detent_changed = false


func consume_detent_change(seat: int) -> bool:
	if seat < 0 or seat >= _seats.size():
		return false
	var state: SeatState = _seats[seat]
	var changed: bool = state.detent_changed
	state.detent_changed = false
	return changed


func _action_latch(seat: int, action: String) -> ActionLatch:
	if seat < 0 or seat >= _seats.size() or not ACTIONS.has(action):
		return null
	var state: SeatState = _seats[seat]
	if not state.actions.has(action):
		state.actions[action] = ActionLatch.new()
	return state.actions[action]


func _target_direction(world: SimWorld, seat: int, requested: Vector2, reach: float, cone: float) -> Vector2:
	var origin := _position(world.players[seat])
	var best := Vector2.ZERO
	var best_distance := INF
	var best_position := Vector2.ZERO
	for position in _target_positions(world, seat):
		var offset: Vector2 = position - origin
		var distance: float = offset.length_squared()
		if distance <= 0.0 or distance > reach * reach:
			continue
		if position.x < 0.0 or position.x > 640.0 \
				or position.y < float(world.camera_top) / Fixed.ONE \
				or position.y > float(world.camera_top + SimWorld.VIEW_H) / Fixed.ONE:
			continue
		if requested != Vector2.ZERO and absf(requested.angle_to(offset)) > cone:
			continue
		if not _lane_clear(world, origin, position):
			continue
		if distance < best_distance or (is_equal_approx(distance, best_distance) \
				and (position.x < best_position.x \
					or (position.x == best_position.x and position.y < best_position.y))):
			best_distance = distance
			best_position = position
			best = offset.normalized()
	return best


func _target_positions(world: SimWorld, seat: int) -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var player: Dictionary = world.players[seat]
	for enemy in world.enemies:
		if not enemy["alive"] or enemy.get("submerged", false) or enemy.get("kind", "") == "pilot":
			continue
		if enemy.get("kind", "") == "shield" and player.get("rend_ticks", 0) <= 0:
			var bullet := {"vx": int(enemy["x"]) - int(player["x"]),
				"vy": int(enemy["y"]) - int(player["y"])}
			if world._shield_blocks(enemy, bullet):
				continue
		targets.append(_position(enemy))
	for gate in world.gates:
		var boss: Dictionary = gate.get("boss", {})
		if not gate["open"] and not boss.is_empty() and boss["alive"]:
			targets.append(Vector2(float(boss["x"]) / Fixed.ONE,
				float(int(boss["gate_y"]) - SimWorld.BOSS_Y_OFFSET) / Fixed.ONE))
	if not world.endless_boss.is_empty() and world.endless_boss["alive"]:
		var boss: Dictionary = world.endless_boss
		var offset: Array = SimWorld.boss_flyin_offset(boss["phase_t"])
		targets.append(Vector2(float(int(boss["x"]) + int(offset[0])) / Fixed.ONE,
			float(int(boss["gate_y"]) - SimWorld.BOSS_Y_OFFSET + int(offset[1])) / Fixed.ONE))
	if not world.colossus.is_empty() and world.colossus["alive"] \
			and world.colossus.get("core_open", 0) > 0:
		targets.append(_position(world.colossus))
	if not world.observer.is_empty():
		targets.append(Vector2(float(world.observer["x"]) / Fixed.ONE,
			float(world.camera_top + SimWorld.OBSERVER_Y_OFFSET) / Fixed.ONE))
	return targets


func _lane_clear(world: SimWorld, origin: Vector2, target: Vector2) -> bool:
	for bunker in world.bunkers:
		if bunker["alive"] and _crosses_box(origin, target, _position(bunker),
				Vector2(float(SimWorld.BUNKER_W) / Fixed.ONE, float(SimWorld.BUNKER_H) / Fixed.ONE)):
			return false
	for rock in world.rocks:
		if SimWorld._rk_solid(rock) and _crosses_centered_box(origin, target, _position(rock),
				Vector2(float(SimWorld._rk_hw(rock)) / Fixed.ONE, float(SimWorld._rk_hh(rock)) / Fixed.ONE)):
			return false
	for bag in world.sandbags:
		if _crosses_centered_box(origin, target, _position(bag),
				Vector2(float(SimWorld._sb_hw(bag)) / Fixed.ONE, float(SimWorld._sb_hh(bag)) / Fixed.ONE)):
			return false
	for tank in world.tanks:
		if ((tank["alive"] and tank["occupant"] < 0) \
				or (not tank["alive"] and tank["burn_ticks"] > 0)) \
				and _crosses_centered_box(origin, target, _position(tank),
					Vector2(float(SimWorld.HULK_HALF_W) / Fixed.ONE, float(SimWorld.HULK_HALF_H) / Fixed.ONE)):
			return false
	return true


func _crosses_centered_box(origin: Vector2, target: Vector2, center: Vector2, half_size: Vector2) -> bool:
	return _crosses_box(origin, target, center - half_size, half_size * 2.0)


func _crosses_box(origin: Vector2, target: Vector2, corner: Vector2, size: Vector2) -> bool:
	var direction := target - origin
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if direction[axis] == 0.0:
			if origin[axis] < corner[axis] or origin[axis] > corner[axis] + size[axis]:
				return false
		else:
			var first: float = (corner[axis] - origin[axis]) / direction[axis]
			var last: float = (corner[axis] + size[axis] - origin[axis]) / direction[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter > leave:
				return false
	return true


func _position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity["x"]) / Fixed.ONE, float(entity["y"]) / Fixed.ONE)
