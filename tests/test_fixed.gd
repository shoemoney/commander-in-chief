extends RefCounted
## Fixed-point math invariants.
##
## These pin the ROUNDING CONTRACT documented at the top of src/sim/fixed.gd.
## Several assertions below look like they are asserting a *bug* (mul and div
## round differently; mirrored motion is not symmetric). They are. The point is
## that the asymmetry is load-bearing — every GOLDEN in test_determinism.gd was
## recorded with it — so a future "cleanup" that harmonises the rounding must
## fail HERE, loudly, instead of silently re-rolling the whole game world.

const Runner := preload("res://tests/run_tests.gd")


func test_int_roundtrip() -> void:
	for v in [-1000, -1, 0, 1, 7, 640, 99999]:
		Runner.T.eq(Fixed.to_int(Fixed.from_int(v)), v, "from_int/to_int roundtrip %d" % v)


func test_mul_div() -> void:
	var three := Fixed.from_int(3)
	var four := Fixed.from_int(4)
	Runner.T.eq(Fixed.mul(three, four), Fixed.from_int(12), "3*4=12")
	Runner.T.eq(Fixed.div(Fixed.from_int(12), four), three, "12/4=3")
	Runner.T.eq(Fixed.mul(Fixed.ONE / 2, Fixed.from_int(10)), Fixed.from_int(5), "0.5*10=5")


func test_mul_div_negative_operands() -> void:
	## Exact cases: no rounding involved, so signs must behave like plain arithmetic.
	var three := Fixed.from_int(3)
	var four := Fixed.from_int(4)
	Runner.T.eq(Fixed.mul(-three, four), Fixed.from_int(-12), "-3*4=-12")
	Runner.T.eq(Fixed.mul(three, -four), Fixed.from_int(-12), "3*-4=-12")
	Runner.T.eq(Fixed.mul(-three, -four), Fixed.from_int(12), "-3*-4=12")
	Runner.T.eq(Fixed.div(Fixed.from_int(-12), four), -three, "-12/4=-3")
	Runner.T.eq(Fixed.div(Fixed.from_int(12), -four), -three, "12/-4=-3")
	Runner.T.eq(Fixed.div(Fixed.from_int(-12), -four), three, "-12/-4=3")
	Runner.T.eq(Fixed.mul(-Fixed.ONE / 2, Fixed.from_int(10)), Fixed.from_int(-5), "-0.5*10=-5")
	Runner.T.eq(Fixed.mul(0, -Fixed.from_int(9)), 0, "0 * -9 = 0 (no negative zero)")
	Runner.T.eq(Fixed.div(0, -Fixed.from_int(9)), 0, "0 / -9 = 0 (no negative zero)")


func test_rounding_split_is_pinned() -> void:
	## THE contract: mul FLOORS, div TRUNCATES TOWARD ZERO. Do not harmonise them.
	## Positive operands agree; negative operands are where they part company.
	Runner.T.eq(Fixed.mul(1, Fixed.ONE / 2), 0, "mul floors +0.5 raw -> 0")
	Runner.T.eq(Fixed.mul(-1, Fixed.ONE / 2), -1, "mul FLOORS -0.5 raw -> -1 (not -0)")
	Runner.T.eq(Fixed.div(1, Fixed.from_int(2)), 0, "div truncates +0.5 raw -> 0")
	Runner.T.eq(Fixed.div(-1, Fixed.from_int(2)), 0, "div TRUNCATES -0.5 raw -> 0 (not -1)")

	## div is sign-symmetric: +x/y and -x/y are exact negatives of each other.
	for pair in [[7, 3], [1, 3], [99, 7], [5, 65536]]:
		var a: int = Fixed.from_int(pair[0])
		var b: int = Fixed.from_int(pair[1])
		Runner.T.eq(Fixed.div(a, b) + Fixed.div(-a, b), 0,
			"div is mirror-symmetric for %d/%d" % [pair[0], pair[1]])

	## mul is NOT: a negative inexact product lands one raw unit further from zero.
	var third := Fixed.div(Fixed.ONE, Fixed.from_int(3))
	Runner.T.eq(Fixed.mul(third, Fixed.ONE / 3), 7281, "mul(1/3, 1/3) floors to 7281")
	Runner.T.eq(Fixed.mul(-third, Fixed.ONE / 3), -7282, "mul(-1/3, 1/3) floors to -7282, NOT -7281")

	## to_int floors; bare `/ ONE` truncates. Both ship in the sim, deliberately
	## (see the site-by-site audit in fixed.gd) — pin that they still differ.
	Runner.T.eq(Fixed.to_int(-1), -1, "to_int(-1 raw) floors to -1")
	Runner.T.eq(-1 / Fixed.ONE, 0, "bare -1/ONE truncates to 0")
	Runner.T.eq(Fixed.to_int(-Fixed.ONE - 1), -2, "to_int(-1.0000x) floors to -2")
	Runner.T.eq((-Fixed.ONE - 1) / Fixed.ONE, -1, "bare (-1.0000x)/ONE truncates to -1")


func test_mirror_asymmetry_is_pinned() -> void:
	## The consequence of the rounding split, measured on the ACTUAL player-move
	## pipeline from sim_world._step_players: mul(div(axis, len), spd).
	## A mirrored input does NOT produce a mirrored displacement — left/up travel
	## up to 1 raw unit/tick further than right/down. Deterministic, sub-pixel, and
	## baked into every golden. If this test fails, someone changed the rounding.
	var spd := SimWorld.PLAYER_SPEED

	for axes in [[256, 256], [181, 256], [256, 181]]:
		var mx: int = axes[0] * 256
		var my: int = axes[1] * 256
		var mlen := Fixed.length(mx, my)
		var dx := Fixed.mul(Fixed.div(mx, mlen), spd)
		var dy := Fixed.mul(Fixed.div(my, mlen), spd)
		var nlen := Fixed.length(-mx, -my)
		var ndx := Fixed.mul(Fixed.div(-mx, nlen), spd)
		var ndy := Fixed.mul(Fixed.div(-my, nlen), spd)
		Runner.T.eq(mlen, nlen, "mirrored input has identical length %s" % [axes])
		Runner.T.ok(ndx == -dx or ndx == -dx - 1,
			"mirrored dx is equal or 1 raw further from zero %s (%d vs %d)" % [axes, dx, ndx])
		Runner.T.ok(ndy == -dy or ndy == -dy - 1,
			"mirrored dy is equal or 1 raw further from zero %s (%d vs %d)" % [axes, dy, ndy])

	## Cardinal axes are exact (the normalize divides evenly), so they DO mirror.
	var clen := Fixed.length(256 * 256, 0)
	Runner.T.eq(Fixed.mul(Fixed.div(-256 * 256, clen), spd),
		-Fixed.mul(Fixed.div(256 * 256, clen), spd), "pure-cardinal motion is mirror-exact")


func test_div_by_zero_returns_zero() -> void:
	## GDScript's int `/` already yields 0 on a zero divisor (after a non-fatal
	## engine error); Fixed.div short-circuits it so the sim cannot spew SCRIPT
	## ERROR — which CI treats as a failure — if a length ever comes out 0.
	Runner.T.eq(Fixed.div(Fixed.ONE, 0), 0, "div(1, 0) = 0")
	Runner.T.eq(Fixed.div(-Fixed.from_int(999), 0), 0, "div(-999, 0) = 0")
	Runner.T.eq(Fixed.div(0, 0), 0, "div(0, 0) = 0")


func test_sqrt() -> void:
	Runner.T.eq(Fixed.fsqrt(Fixed.from_int(16)), Fixed.from_int(4), "sqrt(16)=4")
	Runner.T.eq(Fixed.fsqrt(Fixed.from_int(144)), Fixed.from_int(12), "sqrt(144)=12")
	Runner.T.eq(Fixed.fsqrt(0), 0, "sqrt(0)=0")
	# sqrt(2) in 16.16 ≈ 92681 (1.41421); integer sqrt truncation may be 1 ulp shy.
	var r2 := Fixed.fsqrt(Fixed.from_int(2))
	Runner.T.ok(absi(r2 - 92681) <= 256, "sqrt(2) within tolerance, got %d" % r2)


func test_isqrt_edges() -> void:
	## Newton iteration on raw (non-fixed) ints. Floors, and clamps <= 0 to 0
	## rather than looping or dividing by zero.
	Runner.T.eq(Fixed.isqrt(0), 0, "isqrt(0)=0")
	Runner.T.eq(Fixed.isqrt(-1), 0, "isqrt(-1)=0 (guarded, no div-by-zero)")
	Runner.T.eq(Fixed.isqrt(-999999), 0, "isqrt(large negative)=0")
	Runner.T.eq(Fixed.fsqrt(-Fixed.from_int(9)), 0, "fsqrt(negative)=0")
	for n in [1, 2, 3, 4, 5, 8, 9, 15, 16, 24, 25, 26, 99, 100, 101]:
		var r := Fixed.isqrt(n)
		Runner.T.ok(r * r <= n and (r + 1) * (r + 1) > n, "isqrt(%d)=%d floors exactly" % [n, r])
	## Perfect squares must land ON the root, never 1 shy (a classic Newton off-by-one).
	for root in [1, 7, 256, 4095, 65535]:
		Runner.T.eq(Fixed.isqrt(root * root), root, "isqrt(%d^2)=%d" % [root, root])


func test_vector_length() -> void:
	Runner.T.eq(Fixed.length(Fixed.from_int(3), Fixed.from_int(4)), Fixed.from_int(5), "3-4-5 triangle")
	Runner.T.eq(Fixed.length(0, Fixed.from_int(-7)), Fixed.from_int(7), "|(0,-7)| = 7")
	Runner.T.eq(Fixed.length(0, 0), 0, "|(0,0)| = 0")
	## All four sign quadrants give the same magnitude.
	for q in [[3, 4], [-3, 4], [3, -4], [-3, -4]]:
		Runner.T.eq(Fixed.length(Fixed.from_int(q[0]), Fixed.from_int(q[1])), Fixed.from_int(5),
			"|(%d,%d)| = 5" % [q[0], q[1]])


func test_length_overflow_bound() -> void:
	## The docstring used to claim safety "up to ~2^23 (128 world units)"; the real
	## wall is Fixed.SQUARE_MAX = isqrt(2^63-1) = 3037000499 raw = 46340 px, because
	## mul(x, x) squares the RAW int. Past it the square wraps negative and fsqrt's
	## `v <= 0` guard hands back a silent, plausible 0 — deterministic corruption
	## with nothing to detect it. length() now asserts the bound in dev/tests, so
	## this pins the SAFE side (crossing it is a hard assert, not a return value).
	Runner.T.eq(Fixed.SQUARE_MAX, 3037000499, "SQUARE_MAX is isqrt(2^63-1)")
	Runner.T.eq(Fixed.SQUARE_MAX / Fixed.ONE, 46340, "SQUARE_MAX is 46340 px, not 128")
	Runner.T.ok(Fixed.SQUARE_MAX * Fixed.SQUARE_MAX > 0, "SQUARE_MAX^2 still fits int64")

	## Exact at the boundary: |(SQUARE_MAX, 0)| must come back positive and within
	## one 16.16 quantum of the input (mul(x,x) drops the low 16 bits before fsqrt).
	var lim := Fixed.SQUARE_MAX
	var l0 := Fixed.length(lim, 0)
	Runner.T.ok(l0 > 0 and absi(l0 - lim) <= Fixed.ONE,
		"|(SQUARE_MAX, 0)| = %d, within 1 unit of %d" % [l0, lim])
	Runner.T.ok(Fixed.length(-lim, 0) == l0, "|(-SQUARE_MAX, 0)| matches")
	## Both components maxed: the SUM of the two squares must not wrap either.
	Runner.T.ok(Fixed.length(lim, lim) > l0, "|(SQUARE_MAX, SQUARE_MAX)| does not wrap")

	## Regression guard for the actual trap: an endless run's camera_top passes
	## -46340 px, so an absolute coordinate handed to length() would blow the bound
	## minutes into a run. Every call site must pass a DELTA.
	var endless_5min_y := -46340 * Fixed.ONE
	Runner.T.ok(absi(endless_5min_y) > Fixed.SQUARE_MAX - Fixed.ONE,
		"an endless run reaches the overflow bound in absolute y — deltas only")
