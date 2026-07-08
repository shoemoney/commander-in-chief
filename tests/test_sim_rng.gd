extends RefCounted
## Seeded RNG stream properties.

const Runner := preload("res://tests/run_tests.gd")


func test_same_seed_same_stream() -> void:
	var a := SimRng.new(12345)
	var b := SimRng.new(12345)
	for i in 100:
		Runner.T.eq(a.next_u32(), b.next_u32(), "stream divergence at draw %d" % i)


func test_different_seeds_differ() -> void:
	var a := SimRng.new(1)
	var b := SimRng.new(2)
	var same := 0
	for i in 50:
		if a.next_u32() == b.next_u32():
			same += 1
	Runner.T.ok(same < 5, "seeds 1 and 2 produce near-identical streams (%d/50 collisions)" % same)


func test_u32_bounds_and_range() -> void:
	var r := SimRng.new(777)
	for i in 200:
		var v := r.next_u32()
		Runner.T.ok(v >= 0 and v <= 0xFFFFFFFF, "u32 out of bounds: %d" % v)
	for i in 200:
		var v := r.range_i(24, 616)
		Runner.T.ok(v >= 24 and v <= 616, "range_i out of bounds: %d" % v)
