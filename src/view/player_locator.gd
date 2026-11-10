class_name PlayerLocator
extends RefCounted
## VIEW-ONLY "where am I" ring under each live soldier: a dark under-ring with a thin
## identity-colour rim sitting INSIDE it (a bright hairline outlined in dark reads on
## sand, grass, water and smoke alike), plus one expanding pulse on spawn, revive /
## respawn and the end of a roll. Pure data: main.gd draws the layers this returns, and
## tests composite those same layers, so what is measured is what is drawn.

const PULSE_TICKS := 24
const RING_R := 12
const UNDER_R := 13   # outer radius of the dark band: rim (11..12] sits inside it, dark on BOTH sides
const PULSE_R_MAX := 26
const UNDER_W := 3
const UNDER_ALPHA := 0.72
const RIM_W := 1
const RIM_ALPHA := 0.95

## Per player: age in ticks of the running pulse, -1 = none.
var pulse_age: Array[int] = []
var _was_alive: Array[bool] = []
var _was_rolling: Array[bool] = []


## Feed once per view tick with sim.players. Returns the slots that START a pulse.
func observe(players: Array) -> Array[int]:
	var started: Array[int] = []
	while pulse_age.size() < players.size():
		pulse_age.append(-1)
		_was_alive.append(false)   # first sight of an alive soldier == spawn
		_was_rolling.append(false)
	for i in players.size():
		var p: Dictionary = players[i]
		var alive: bool = p["alive"]
		var rolling: bool = p["roll_ticks"] > 0
		if alive and (not _was_alive[i] or (_was_rolling[i] and not rolling)):
			pulse_age[i] = 0
			started.append(i)
		elif pulse_age[i] >= 0:
			pulse_age[i] += 1
			if pulse_age[i] > PULSE_TICKS:
				pulse_age[i] = -1
		_was_alive[i] = alive
		_was_rolling[i] = rolling
	return started


func reset() -> void:
	pulse_age.clear()
	_was_alive.clear()
	_was_rolling.clear()


## Draw layers, back to front: {r: int, w: int, col: Color}. Empty for a downed soldier.
static func layers(alive: bool, ident: Color, age: int) -> Array:
	var out: Array = []
	if not alive:
		return out
	out.append({"r": UNDER_R, "w": UNDER_W, "col": Color(0.01, 0.015, 0.02, UNDER_ALPHA)})
	out.append({"r": RING_R, "w": RIM_W, "col": Color(ident.r, ident.g, ident.b, RIM_ALPHA)})
	if age >= 0 and age <= PULSE_TICKS:
		var t := float(age) / float(PULSE_TICKS)
		var r := roundi(lerpf(float(RING_R), float(PULSE_R_MAX), 1.0 - (1.0 - t) * (1.0 - t)))
		var a := 0.85 * (1.0 - t)
		out.append({"r": r + 1, "w": UNDER_W, "col": Color(0.01, 0.015, 0.02, a * 0.6)})
		out.append({"r": r, "w": RIM_W, "col": Color(ident.r, ident.g, ident.b, a)})
	return out
