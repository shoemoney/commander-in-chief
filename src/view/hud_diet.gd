class_name HudDiet
extends RefCounted
## HUD DIET: take text off the playfield during combat. View-only, never touches the sim.
##
## Two jobs, both driven by the sim tick the HUD already has:
##  1. Change-triggered reveal. A static top-bar chip (RECORD / REINFORCEMENTS / SUPPLIES) stays at
##     full alpha while it is new or changing, then eases to DIM_ALPHA after IDLE_TICKS unchanged.
##     A change snaps it back to full. Never dims at an enlarged TEXT SIZE (legibility setting).
##  2. A single objective slot. The "what do I do at this gate" sentence is stated loudly for the
##     first OBJECTIVE_TICKS of each gate, then retires; the top-bar gate telegraph carries on.

const IDLE_TICKS := 240        # 4 s unchanged before a chip starts to dim
const FADE_TICKS := 30         # ease length from full to DIM_ALPHA
const DIM_ALPHA := 0.28
const OBJECTIVE_TICKS := 240   # 4 s of the objective sentence per gate
# A chip not asked for within this many ticks counts as having been absent, so its reappearance
# is a change (the REINFORCEMENTS chip leaves and returns across sectors).
const ABSENT_GAP_TICKS := 3

var _epoch := 0
var _chips := {}       # id -> {"v": Variant, "changed": int, "seen": int}
var _objectives := {}  # key -> first tick the objective was stated


## Reset when the sim instance changes (restart), since ticks restart from 0.
func sync(epoch: int) -> void:
	if epoch != _epoch:
		_epoch = epoch
		_chips.clear()
		_objectives.clear()


## Alpha multiplier for a chip showing `value` at `tick`. Records the observation.
## `force_full` is for "became actionable" moments (wheel open, etc).
func chip_alpha(id: String, value: Variant, tick: int, force_full := false) -> float:
	var c: Dictionary = _chips.get(id, {})
	if c.is_empty() or tick < int(c["seen"]) or tick - int(c["seen"]) > ABSENT_GAP_TICKS \
			or c["v"] != value:
		c = {"v": value, "changed": tick, "seen": tick}
	c["seen"] = tick
	if force_full:
		c["changed"] = tick
	_chips[id] = c
	if Art.text_scale > 1.001:
		return 1.0
	return alpha_for_age(tick - int(c["changed"]))


static func alpha_for_age(age: int) -> float:
	if age <= IDLE_TICKS:
		return 1.0
	var f := clampf(float(age - IDLE_TICKS) / float(FADE_TICKS), 0.0, 1.0)
	return lerpf(1.0, DIM_ALPHA, f)


## True while the objective sentence for `key` (a gate) is still inside its lifetime.
func objective_live(key: int, tick: int) -> bool:
	if not _objectives.has(key) or tick < int(_objectives[key]):
		_objectives[key] = tick
	return tick - int(_objectives[key]) < OBJECTIVE_TICKS


## True once the sentence for `key` has been stated and retired (telegraph shortens to MID).
func objective_seen(key: int, tick: int) -> bool:
	return _objectives.has(key) and tick >= int(_objectives[key]) \
		and tick - int(_objectives[key]) >= OBJECTIVE_TICKS
