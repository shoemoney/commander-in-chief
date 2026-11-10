class_name CameraLead
extends RefCounted
## VIEW-ONLY aim look-ahead: a critically-damped offset that pulls the frame a few
## pixels toward where the squad is aiming. Nothing here touches the sim or the
## checksum. main.gd folds `offset` into the same final transform as `_kick` and the
## trauma rattle, so the mouse mapping (get_local_mouse_position), reticle, threat
## pips and shake-immune HUD edge elements all see it through the canvas transform
## they already invert.
##
## The lead is the FRAME moving toward the aim, i.e. the world shifts the OPPOSITE way:
## `offset` is the signed world-shift to add to main.position.

## Largest lead per axis in px. X is 0 on purpose: the full-width water quads and a few
## 640px-wide world strips start exactly at x=0, so a sustained horizontal shift would
## park a persistent un-drawn stripe at the river bank (the trauma rattle only shows it
## for a few frames). The scroll axis has >=120 px of ground overscan, so Y is free.
## Raise X only after those strips are given horizontal overscan.
const MAX_PX := Vector2(0.0, 10.0)

## Natural frequency (rad/s) of the critically-damped spring: ~95% settled in 0.5 s.
const OMEGA := 9.0
const DT := 1.0 / 60.0

var offset := Vector2.ZERO
var velocity := Vector2.ZERO


## Mean aim of every ALIVE player (unit vectors averaged, so opposing aims in co-op
## cancel and the frame stays put). Returns a vector of length 0..1.
static func mean_aim(players: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in players:
		if not p["alive"]:
			continue
		var a := Vector2(p["aim_x"], p["aim_y"])
		if a.length_squared() > 0.0:
			sum += a.normalized()
		n += 1
	if n == 0:
		return Vector2.ZERO
	return sum / float(n)


## One fixed 60 Hz tick of the spring. `strength` is the shake-level scale (0 under
## reduce-motion); at 0 the offset is cleared to EXACTLY zero, not eased out.
func step(aim: Vector2, strength: float) -> void:
	if strength <= 0.0:
		offset = Vector2.ZERO
		velocity = Vector2.ZERO
		return
	var target := -aim.limit_length(1.0) * MAX_PX * minf(strength, 1.0)
	var accel := (target - offset) * (OMEGA * OMEGA) - velocity * (2.0 * OMEGA)
	velocity += accel * DT
	offset += velocity * DT


func reset() -> void:
	offset = Vector2.ZERO
	velocity = Vector2.ZERO
