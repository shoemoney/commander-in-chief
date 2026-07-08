class_name Fixed
extends RefCounted
## 16.16 fixed-point math for the deterministic sim.
##
## Every quantity inside src/sim is a 64-bit int in 16.16 format.
## GDScript ints are VM-defined 64-bit two's complement on every platform
## (x86_64, Apple Silicon arm64, Windows, Linux, macOS), so results are
## bit-identical across architectures — floats never enter the sim.

const SHIFT := 16
const ONE := 1 << SHIFT
const HALF := ONE >> 1

static func from_int(v: int) -> int:
	return v << SHIFT


static func to_int(v: int) -> int:
	## Truncates toward negative infinity (arithmetic shift), consistently on all platforms.
	return v >> SHIFT


static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT


static func div(a: int, b: int) -> int:
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
	## Magnitude of a fixed-point vector. Safe for |x|,|y| up to ~2^23 (128 world units << SHIFT).
	return fsqrt(mul(x, x) + mul(y, y))


static func clampi_fixed(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v
