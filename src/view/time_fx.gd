class_name TimeFx
extends RefCounted
## View-only time layer: slow-motion beats, a hit-stop budget and per-enemy flinch.
##
## The sim is never touched. A beat only decides WHETHER main.gd calls sim.step() on a given
## physics frame (the same skip-the-step mechanism hit-stop already uses, so input latching and
## the recorder behave identically), scales the fx clock, and dips AudioServer's pitch.
## Pure per-frame math rather than a Tween: a Tween rides wall-clock time and the SceneTree,
## which makes the number of skipped steps non-deterministic and untestable headless.

## Test/tool switch: step-counting harnesses set this false and keep 1:1 stepping.
static var enabled := true

const BEATS := {
	# kind: [frames, speed floor]
	"boss": [36, 0.40],
	"victory": [50, 0.30],
	"wipe": [40, 0.35],
	"blast": [30, 0.50],
}
const EASE_IN_FRAC := 0.25
const HOLD_FRAC := 0.30
const PITCH_DIP := 0.30            # AudioServer pitch = 1 - PITCH_DIP * (1 - speed)

const HS_WINDOW := 6               # ticks
const HS_CAP_ORDINARY := 1         # frozen frames per window, ordinary kills
const HS_CAP_HEAVY := 2            # ... tier-2+ kills
const FLINCH_TICKS := 6
const FLINCH_PX := 2.0
const FLINCH_SQUASH := 0.08

var _total := 0
var _t := 0
var _floor := 1.0
var _acc := 1.0
var _audio_base := 1.0
var _audio_held := false

var _win_start := -1000
var _win_used := 0
var _win_folded := 0

var _flinch := {}   # slot -> {"dir": Vector2, "t": int}


## Current speed multiplier in (0, 1]; 1.0 when no beat is live.
func speed() -> float:
	if _total <= 0:
		return 1.0
	var p := float(_t) / float(_total)
	if p < EASE_IN_FRAC:
		var q := p / EASE_IN_FRAC
		return lerpf(1.0, _floor, 1.0 - pow(1.0 - q, 3.0))
	if p < EASE_IN_FRAC + HOLD_FRAC:
		return _floor
	var r := (p - EASE_IN_FRAC - HOLD_FRAC) / (1.0 - EASE_IN_FRAC - HOLD_FRAC)
	return lerpf(_floor, 1.0, r * r * (3.0 - 2.0 * r))


func active() -> bool:
	return _total > 0


## Multiplier for the view's fx clock.
func fx_scale() -> float:
	return speed()


## Begin (or lengthen) a beat. False when refused: reduce-motion, disabled, unknown kind, or a
## shorter beat than the one already running.
func start(kind: String, motion: float) -> bool:
	if not enabled or motion < 0.5 or not BEATS.has(kind):
		return false
	var frames: int = BEATS[kind][0]
	if _total > 0 and frames <= _total - _t:
		return false
	if _total == 0:
		_acc = 1.0
		if not _audio_held:
			_audio_base = AudioServer.playback_speed_scale
			_audio_held = true
	_total = frames
	_t = 0
	_floor = BEATS[kind][1]
	_apply_audio()
	return true


## Advance one physics frame. Returns true when this frame must NOT call sim.step().
## `frozen` (hit-stop) holds the clock so the beat begins after the freeze.
func advance(frozen: bool) -> bool:
	if _total <= 0 or frozen:
		return false
	_t += 1
	if _t >= _total:
		cancel()
		return false
	_acc += speed()
	_apply_audio()
	if _acc >= 1.0:
		_acc -= 1.0
		return false
	return true


## End any beat and restore pitch exactly. Safe to call any time (restart, replay, pause).
func cancel() -> void:
	_total = 0
	_t = 0
	_floor = 1.0
	_acc = 1.0
	if _audio_held:
		AudioServer.playback_speed_scale = _audio_base
		_audio_held = false


func _apply_audio() -> void:
	if _audio_held:
		AudioServer.playback_speed_scale = 1.0 - PITCH_DIP * (1.0 - speed())


## Hit-stop budget. `want` is the frames the caller wanted, `heavy` marks a tier-2+ kill.
## Returns the frames to freeze for; anything suppressed is folded into punch_bonus().
func grant_hitstop(tick: int, want: int, heavy: bool) -> int:
	if tick - _win_start >= HS_WINDOW or tick < _win_start:
		_win_start = tick
		_win_used = 0
		_win_folded = 0
	var cap := HS_CAP_HEAVY if heavy else HS_CAP_ORDINARY
	var give := maxi(0, mini(want, cap) - _win_used)
	_win_used += give
	if give < want:
		_win_folded += 1
	return give


## Extra camera punch earned by kills whose freeze was folded away in this window.
func punch_bonus() -> float:
	return 0.004 * float(mini(_win_folded, 6))


func reset_hitstop() -> void:
	_win_start = -1000
	_win_used = 0
	_win_folded = 0


## --- flinch -------------------------------------------------------------------------

func flinch_hit(slot: int, dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	_flinch[slot] = {"dir": dir.normalized(), "t": FLINCH_TICKS}


func flinch_clear(slot: int) -> void:
	_flinch.erase(slot)


## Once per sim tick.
func flinch_tick() -> void:
	for k in _flinch.keys():
		_flinch[k]["t"] -= 1
		if _flinch[k]["t"] <= 0:
			_flinch.erase(k)


func _flinch_frac(slot: int) -> float:
	if not _flinch.has(slot):
		return 0.0
	return float(_flinch[slot]["t"]) / float(FLINCH_TICKS)


func flinch_offset(slot: int, motion: float) -> Vector2:
	if motion < 0.5 or not _flinch.has(slot):
		return Vector2.ZERO
	return (_flinch[slot]["dir"] as Vector2) * FLINCH_PX * _flinch_frac(slot)


## Squash read as a WIDEN of the axis perpendicular to the hit (scale-UP only: the text-under-
## canvas-scale ratchet bans shrinking, and a 1.0..1.08 widen never deletes a glyph scanline).
## Vector2.ONE when idle.
func flinch_scale(slot: int, motion: float) -> Vector2:
	if motion < 0.5 or not _flinch.has(slot):
		return Vector2.ONE
	var d: Vector2 = _flinch[slot]["dir"]
	var s := FLINCH_SQUASH * _flinch_frac(slot)
	return Vector2(1.0 + s, 1.0) if absf(d.y) >= absf(d.x) else Vector2(1.0, 1.0 + s)


func flinch_active(slot: int) -> bool:
	return _flinch.has(slot)


func flinch_clear_all() -> void:
	_flinch.clear()
