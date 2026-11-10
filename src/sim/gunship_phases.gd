class_name GunshipPhases
extends RefCounted
## The Bridge Gunship's three HP-keyed acts (colossus_phase() precedent): the
## fight is cut at HP thirds of the boss's OWN stored max, so 2P / Boss Rush /
## Endless scaling shifts the thresholds with the pool instead of cramming two
## acts into the last 40 HP. Pure integer helpers so the sim and the view read
## ONE source (lint_sim clean: no floats, no RNG, no scene tree).
##
##   1  STRAFING RUN       the original cycle, byte-for-byte: aimed spray, then mortars.
##   2  COVER DENIAL       + a two-strike salvo inside the strafe act that lands on the
##                           spot the player is hiding at (the nearest cover bag, else
##                           his feet) - sit still and you are shelled out of it.
##   3  DESPERATION        + 1.25x hull drift, 2/3 spray interval, and a CARPET: five
##                           strikes laid one by one across the whole arena on the row
##                           the player is standing on as each one lands. Leave the row.
##
## Every new lethal attack is a plain _add_strike (45-tick STRIKE_TELEGRAPH_TICKS,
## ring == GRENADE_RADIUS), so the telegraph the view draws is the strike the sim
## resolves. Nothing here adds sim state: phase is a pure function of hp / max_hp.

const SALVO_TICKS := [50, 80]            # inside the strafe act (t < BOSS_STRAFE_TICKS)
const COVER_SNAP_RANGE := 100 * 65536    # a bag this close to the player is "his cover"
const CARPET_START := 228                # inside the mortar act, after the 3rd base shell
const CARPET_STEP := 8                   # ticks between successive carpet strikes
const CARPET_COUNT := 5
const CARPET_X0 := 80                    # px: first and last column, evenly spread
const CARPET_X1 := 560
const ENRAGE_SPEED_NUM := 5              # phase-3 hull drift = BOSS_SPEED * 5 / 4
const ENRAGE_SPEED_DEN := 4
const ENRAGE_SPRAY_NUM := 2              # phase-3 spray interval = base * 2 / 3
const ENRAGE_SPRAY_DEN := 3
const MIN_TELEGRAPH_TICKS := 24          # the project's reaction floor


static func phase_of(hp: int, max_hp: int) -> int:
	## 1..3 by HP thirds. Same cut points as _damage_boss's arena-crack edges.
	if hp > (max_hp * 2) / 3:
		return 1
	if hp > max_hp / 3:
		return 2
	return 3


static func carpet_ticks() -> Array:
	var out: Array = []
	for i in CARPET_COUNT:
		out.append(CARPET_START + i * CARPET_STEP)
	return out


static func carpet_x(i: int, dir: int) -> int:
	## Fixed-point column of the i-th carpet strike. The sweep runs the way the
	## hull is drifting (dir = +1 left->right), so the order is learnable.
	var span: int = (CARPET_X1 - CARPET_X0) * 65536
	var k: int = i if dir >= 0 else CARPET_COUNT - 1 - i
	return CARPET_X0 * 65536 + span * k / (CARPET_COUNT - 1)


static func speed(phase: int, base: int) -> int:
	if phase >= 3:
		return base * ENRAGE_SPEED_NUM / ENRAGE_SPEED_DEN
	return base


static func spray_interval(phase: int, base: int) -> int:
	if phase >= 3:
		return maxi(4, base * ENRAGE_SPRAY_NUM / ENRAGE_SPRAY_DEN)
	return base


static func denial_point(px: int, py: int, bags: Array, gate_y: int) -> Array:
	## [x, y] (fixed) the salvo lands on: the cover bag nearest the player when
	## one is within COVER_SNAP_RANGE (bags = [[x_px, y_off_px], ...], campaign
	## arena only), else the player's own position (Endless has no bags).
	var best: Array = [px, py]
	var best_d: int = COVER_SNAP_RANGE
	for bag in bags:
		var bx: int = int(bag[0]) * 65536
		var by: int = gate_y + int(bag[1]) * 65536
		var d: int = Fixed.length(bx - px, by - py)
		if d < best_d:
			best_d = d
			best = [bx, by]
	return best
