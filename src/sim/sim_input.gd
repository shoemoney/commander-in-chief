class_name SimInput
extends RefCounted
## One player's input for one sim tick.
##
## Analog values are quantized to integers in [-256, 256] at the view/input
## boundary — the sim never sees a float. Quantized inputs are also what the
## replay format and (later) lockstep netcode serialize.

## The quantized-axis range `_quantize_axis` produces and `decode` enforces.
const AXIS_MAX := 256

var move_x: int = 0
var move_y: int = 0
var aim_x: int = 0
var aim_y: int = 0
var fire: bool = false
var grenade: bool = false
var revive: bool = false
var roll: bool = false
var interact: bool = false
var buy: int = 0   # War Chest spend-wheel: 0 = none, 1..5 = wheel kind + 1, 6 = token drop


func hash_ints() -> Array[int]:
	return [move_x, move_y, aim_x, aim_y, int(fire), int(grenade), int(revive), int(roll),
		int(interact), buy]


func encode() -> Array[int]:
	## Compact wire format: 4 quantized axes + a button bitmask (buy rides in
	## bits 5-7). Int-only — this is what lockstep sends and what replays store.
	var flags := int(fire) | (int(grenade) << 1) | (int(revive) << 2) \
		| (int(roll) << 3) | (int(interact) << 4) | ((buy & 7) << 5)
	return [move_x, move_y, aim_x, aim_y, flags]


static func decode(data: Array) -> SimInput:
	## TRUST BOUNDARY. This decodes bytes from a remote peer (lockstep) or a file
	## someone mailed in with a bug report (replay) — never trust either. replay.gd
	## already validates frame SHAPE here and says why; range was still unchecked:
	## `_quantize_axis` guarantees [-256,256] locally, but a crafted payload can send
	## anything, and sim_world's `inp.move_x * 256` feeds Fixed.length, which overflows
	## int64 past ~2^24. That stays perfectly DETERMINISTIC (both peers consume the same
	## bytes), so it is a silent cheat vector with no desync to detect it.
	var inp := SimInput.new()
	if data.size() < 5:
		return inp   # short payload: neutral input beats indexing past the end mid-step
	inp.move_x = clampi(int(data[0]), -AXIS_MAX, AXIS_MAX)
	inp.move_y = clampi(int(data[1]), -AXIS_MAX, AXIS_MAX)
	inp.aim_x = clampi(int(data[2]), -AXIS_MAX, AXIS_MAX)
	inp.aim_y = clampi(int(data[3]), -AXIS_MAX, AXIS_MAX)
	var flags: int = int(data[4])
	inp.fire = (flags & 1) != 0
	inp.grenade = (flags & 2) != 0
	inp.revive = (flags & 4) != 0
	inp.roll = (flags & 8) != 0
	inp.interact = (flags & 16) != 0
	inp.buy = (flags >> 5) & 7
	return inp
