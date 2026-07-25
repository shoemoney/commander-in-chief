class_name Fixed
extends RefCounted
## 16.16 fixed-point math for the deterministic sim.
##
## Every quantity inside src/sim is a 64-bit int in 16.16 format.
## GDScript ints are VM-defined 64-bit two's complement on every platform
## (x86_64, Apple Silicon arm64, Windows, Linux, macOS), so results are
## bit-identical across architectures — floats never enter the sim.
##
## ═══ THE ROUNDING CONTRACT — read before you "clean up" anything here ═══
##
## The two rounding modes in this file DISAGREE on negative operands, and that
## disagreement is baked into every committed golden checksum:
##
##   mul(a, b) = (a * b) >> SHIFT   FLOORS   (arithmetic shift, toward -inf)
##   div(a, b) = (a << SHIFT) / b   TRUNCATES (GDScript int `/`, toward zero)
##   to_int(v) = v >> SHIFT         FLOORS
##
## Both are perfectly deterministic — same bits on every platform — so the sim
## is safe. What they are NOT is mirror-symmetric. `mul` rounds a negative
## product AWAY from zero (-0.5 -> -1) while a positive product rounds toward
## zero (0.5 -> 0), so any pipeline ending in `mul` gives left/up motion up to
## 1 raw unit (1/65536 px) more travel per tick than the mirrored right/down
## motion. Measured on the real player-move pipeline in sim_world's
## `mul(div(axis, len), spd)`: a NE diagonal steps +313 raw/tick and the exact
## mirror SW diagonal steps -314. That is ~60 raw/s ≈ 0.001 px/s — invisible in
## play, but it means a mirrored replay is NOT bit-identical to its original.
##
## DO NOT harmonise the two (e.g. make div floor, or make mul round-to-nearest).
## It would re-roll every world in the game for a cosmetic sub-pixel gain and
## invalidate every GOLDEN in tests/test_determinism.gd.
## `tests/test_fixed.gd::test_rounding_split_is_pinned` and
## `::test_mirror_asymmetry_is_pinned` fail loudly if anyone tries.
##
## ═══ `x / ONE` vs `to_int(x)` — pick deliberately ═══
##
## Bare `/ F_ONE` (truncate) and `Fixed.to_int` (floor) differ by 1 for every
## negative non-multiple of ONE, and the campaign runs into NEGATIVE y. Neither
## is "the" right one; what matters is that each site is deliberate. Audit of
## every bare `/ F_ONE` in src/sim/sim_world.gd (2026-07-25):
##
##   OPERAND ALWAYS >= 0 — floor == truncate, both conventions identical:
##     _step_vents        `v["x"] / F_ONE`          vent x, world 80..560 px
##     _is_water_blocked  `w["ford_x"] / F_ONE`     ford x, rng.range_i(80,560)
##     _stream_terrain    `water["ford_x"] / F_ONE` (x2: mud rock + near-shore teeth)
##     _stream_terrain    `(-_next_rock_y) / F_ONE` rock cursor starts at
##                        -700*F_ONE and only decreases, so the negation is > 0
##
##   OPERAND IS NEGATIVE — truncate != floor, and truncate is what shipped:
##     _spawn_enemy   `(x / F_ONE + y / F_ONE) & 3`  cosmetic sprite `skin`;
##                    y is negative. EXCLUDED from checksum() (see KNOWN["enemy"])
##                    -> golden-inert either way; a wrong pick is invisible.
##     _step_spawner  `_mix(absi(camera_top / F_ONE), _world_seed)` rear-camp
##                    side pick. camera_top starts at -VIEW_H and only decreases,
##                    so this truncates a negative every time. The value is a
##                    HASH SEED, not a coordinate — floor and truncate are both
##                    "correct"; they just seed different worlds. Locked to
##                    truncate because that is what the goldens recorded.
##
## Verdict: no site is wrong, so nothing here changes behaviour. If you convert
## one of the two negative-operand sites to `to_int`, you are re-rolling world
## layout — re-record the goldens and say why.

const SHIFT := 16
const ONE := 1 << SHIFT

## Largest raw magnitude `length`/`mul(v, v)` can square without wrapping int64:
## isqrt(2^63 - 1). In pixels that is 46340 — see `length` below.
const SQUARE_MAX := 3037000499

static func from_int(v: int) -> int:
	return v << SHIFT


static func to_int(v: int) -> int:
	## FLOORS (arithmetic shift, toward -inf), consistently on all platforms.
	## NOT the same as `v / ONE` for negatives — see the rounding contract above.
	return v >> SHIFT


static func mul(a: int, b: int) -> int:
	## FLOORS. Wraps silently once |a * b| >= 2^63; keep operands under SQUARE_MAX.
	return (a * b) >> SHIFT


static func div(a: int, b: int) -> int:
	## TRUNCATES TOWARD ZERO. Also wraps once |a| >= 2^47 (the `<< SHIFT` runs first).
	if b == 0:
		return 0   # GDScript's int `/` already yields 0 here — this only mutes the
		           # engine's non-fatal "Division by zero" spam, so behaviour and
		           # every golden are byte-identical. Pinned by test_fixed.
	return (a << SHIFT) / b


static func isqrt(v: int) -> int:
	## Integer square root of a raw non-negative int (not fixed-scaled).
	if v <= 0:
		return 0
	var x := v
	var y := (x + 1) >> 1
	while y < x:
		x = y
		y = (x + v / x) >> 1
	return x


static func fsqrt(v: int) -> int:
	## Square root of a 16.16 value, returning 16.16.
	## sqrt(v * 2^16) * 2^8 == sqrt(v) * 2^16.
	if v <= 0:
		return 0
	return isqrt(v) << (SHIFT >> 1)


static func length(x: int, y: int) -> int:
	## Magnitude of a fixed-point vector.
	##
	## OVERFLOW BOUND — the old docstring claimed "~2^23 (128 world units)", which is
	## wrong by eight bits. The real limit is `mul(x, x)`: it squares the RAW int, so
	## it wraps int64 once |x| > SQUARE_MAX = 3037000499 raw = 46340 px. Past that the
	## square goes negative and fsqrt's `v <= 0` guard returns a silent, plausible 0 —
	## a corrupt-but-deterministic run with nothing to detect it (both lockstep peers
	## agree on the garbage). Verified: length(46340px, 0) is exact, length(46341px, 0)
	## returns 0.
	##
	## PASS DELTAS, NEVER ABSOLUTE COORDINATES. All current call sites do. The trap is
	## that world y is unbounded downward — an endless run's `camera_top` passes
	## -46340 px around the 5-minute mark, so the first person who hands an absolute
	## coordinate to this function ships a run that quietly corrupts itself minutes in.
	## The assert catches that in dev/tests (it is compiled out of release builds, so
	## it costs the shipped sim nothing and can never change a checksum).
	assert(absi(x) <= SQUARE_MAX and absi(y) <= SQUARE_MAX,
		"Fixed.length overflow: (%d, %d) exceeds SQUARE_MAX — pass a delta, not an absolute coordinate" % [x, y])
	return fsqrt(mul(x, x) + mul(y, y))
