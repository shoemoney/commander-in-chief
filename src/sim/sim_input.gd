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


func hash_ints() -> Array[int]:
	return [move_x, move_y, aim_x, aim_y, int(fire), int(grenade), int(revive)]
