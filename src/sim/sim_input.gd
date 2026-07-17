class_name SimInput
extends RefCounted
## One player's input for one sim tick.
##
## Analog values are quantized to integers in [-256, 256] at the view/input
## boundary — the sim never sees a float. Quantized inputs are also what the
## replay format and (later) lockstep netcode serialize.

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
	var inp := SimInput.new()
	inp.move_x = data[0]
	inp.move_y = data[1]
	inp.aim_x = data[2]
	inp.aim_y = data[3]
	var flags: int = data[4]
	inp.fire = (flags & 1) != 0
	inp.grenade = (flags & 2) != 0
	inp.revive = (flags & 4) != 0
	inp.roll = (flags & 8) != 0
	inp.interact = (flags & 16) != 0
	inp.buy = (flags >> 5) & 7
	return inp
