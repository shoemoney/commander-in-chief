class_name SimRng
extends RefCounted
## Seeded xoshiro128** — the sim's only randomness source.
##
## Pure 32-bit integer state, masked explicitly, so the stream is
## bit-identical on every platform and architecture. Engine RNG
## (randi/randf/RandomNumberGenerator) is banned inside src/sim.

const MASK32 := 0xFFFFFFFF

var _s0: int
var _s1: int
var _s2: int
var _s3: int


func _init(seed_value: int) -> void:
	# Murmur3-style 32-bit mixing to spread the seed into four non-zero words.
	# All intermediates stay far below 2^63 — no literal or overflow hazards.
	var words: Array[int] = []
	for i in 4:
		var z := ((seed_value & MASK32) + _mul32(i + 1, 0x9E3779B9)) & MASK32
		z = z ^ (z >> 16)
		z = _mul32(z, 0x85EBCA6B)
		z = z ^ (z >> 13)
		z = _mul32(z, 0xC2B2AE35)
		z = z ^ (z >> 16)
		words.append(z)
	_s0 = words[0] if words[0] != 0 else 1
	_s1 = words[1] if words[1] != 0 else 2
	_s2 = words[2] if words[2] != 0 else 3
	_s3 = words[3] if words[3] != 0 else 4


static func _mul32(a: int, b: int) -> int:
	## (a * b) mod 2^32 without any intermediate exceeding 2^49.
	var al := a & MASK32
	var lo := al * (b & 0xFFFF)
	var hi := al * ((b >> 16) & 0xFFFF)
	return (lo + ((hi & 0xFFFF) << 16)) & MASK32


static func _rotl32(v: int, k: int) -> int:
	return ((v << k) | (v >> (32 - k))) & MASK32


func next_u32() -> int:
	var result := (_rotl32((_s1 * 5) & MASK32, 7) * 9) & MASK32
	var t := (_s1 << 9) & MASK32
	_s2 = _s2 ^ _s0
	_s3 = _s3 ^ _s1
	_s1 = _s1 ^ _s2
	_s0 = _s0 ^ _s3
	_s2 = _s2 ^ t
	_s3 = _rotl32(_s3, 11)
	return result


func range_i(lo: int, hi_inclusive: int) -> int:
	## Uniform int in [lo, hi_inclusive]. Modulo bias is acceptable for gameplay.
	var span := hi_inclusive - lo + 1
	return lo + (next_u32() % span)
