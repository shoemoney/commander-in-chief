class_name AccessibilityPolicy
extends RefCounted

const EDGE_ACTIONS: Array[StringName] = [&"grenade", &"roll", &"interact"]

var _phase := 0
var _sampled: Array[SimInput] = []
var _pending: Array[SimInput] = []
var _delivered: Array[SimInput] = []
var _purchases: Array[Array] = []


static func shake_scale(level: int, reduce_motion: bool) -> float:
	return float(clampi(level, 0, 10)) / 10.0 * (0.0 if reduce_motion else 1.0)


static func flash_scale(level: int, reduce_motion: bool) -> float:
	return float(clampi(level, 0, 10)) / 10.0 * (0.4 if reduce_motion else 1.0)


func should_step(slow: bool) -> bool:
	if not slow:
		_phase = 0
		return true
	_phase = (_phase + 1) % 4
	return _phase != 0


func reset_clock() -> void:
	_phase = 0
	_sampled.clear()
	_pending.clear()
	_delivered.clear()
	_purchases.clear()


func buffer_inputs(inputs: Array[SimInput]) -> void:
	if inputs.size() != _sampled.size():
		_sampled.clear()
		_pending.clear()
		_delivered.clear()
		_purchases.clear()
		for _i in inputs.size():
			_sampled.append(SimInput.new())
			_pending.append(SimInput.new())
			_delivered.append(SimInput.new())
			_purchases.append([])
	for i in inputs.size():
		var latest := SimInput.decode(inputs[i].encode())
		var previous := _sampled[i]
		var pending := _pending[i]
		for action in EDGE_ACTIONS:
			if bool(latest.get(action)) and not bool(previous.get(action)):
				pending.set(action, true)
		pending.revive = pending.revive or latest.revive
		if latest.buy > 0 and latest.buy < SimWorld.BUY_WHEEL_OPEN \
				and (previous.buy == 0 or previous.buy == SimWorld.BUY_WHEEL_OPEN):
			_purchases[i].append(latest.buy)
		if latest.buy == SimWorld.BUY_WHEEL_OPEN:
			pending.roll = false
		_sampled[i] = latest


func take_inputs() -> Array[SimInput]:
	var result: Array[SimInput] = []
	for i in _sampled.size():
		var latest := _sampled[i]
		var pending := _pending[i]
		var delivered := _delivered[i]
		var next := SimInput.decode(latest.encode())
		for action in EDGE_ACTIONS:
			if bool(pending.get(action)) and bool(delivered.get(action)):
				# A release and new press need a neutral sim tick between their edges.
				next.set(action, false)
			else:
				next.set(action, bool(latest.get(action)) or bool(pending.get(action)))
				pending.set(action, false)
		if latest.buy == SimWorld.BUY_WHEEL_OPEN:
			next.roll = false
			pending.roll = false
		next.revive = latest.revive or pending.revive
		pending.revive = false
		next.buy = SimWorld.BUY_WHEEL_OPEN if latest.buy == SimWorld.BUY_WHEEL_OPEN else 0
		if not _purchases[i].is_empty():
			if delivered.buy == 0 or delivered.buy == SimWorld.BUY_WHEEL_OPEN:
				next.buy = int(_purchases[i].pop_front())
		_delivered[i] = SimInput.decode(next.encode())
		result.append(next)
	return result
