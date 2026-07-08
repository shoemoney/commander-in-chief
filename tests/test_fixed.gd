extends RefCounted
## Fixed-point math invariants.

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


func test_sqrt() -> void:
	Runner.T.eq(Fixed.fsqrt(Fixed.from_int(16)), Fixed.from_int(4), "sqrt(16)=4")
	Runner.T.eq(Fixed.fsqrt(Fixed.from_int(144)), Fixed.from_int(12), "sqrt(144)=12")
	Runner.T.eq(Fixed.fsqrt(0), 0, "sqrt(0)=0")
	# sqrt(2) in 16.16 ≈ 92681 (1.41421); integer sqrt truncation may be 1 ulp shy.
	var r2 := Fixed.fsqrt(Fixed.from_int(2))
	Runner.T.ok(absi(r2 - 92681) <= 256, "sqrt(2) within tolerance, got %d" % r2)


func test_vector_length() -> void:
	Runner.T.eq(Fixed.length(Fixed.from_int(3), Fixed.from_int(4)), Fixed.from_int(5), "3-4-5 triangle")
	Runner.T.eq(Fixed.length(0, Fixed.from_int(-7)), Fixed.from_int(7), "|(0,-7)| = 7")
