extends RefCounted
## Pins the capture-liveness detector itself.
##
## tools/screenshots.gd once shipped seven stacked bugs that each printed "SAVED"
## for a 1768-byte flat-colour PNG. The fix is _frame_is_live(); this suite is what
## keeps the fix honest — feed it a synthetic dead frame and a synthetic live one
## and assert it can still tell them apart. A detector nothing tests is a detector
## that silently starts returning true.

const Runner := preload("res://tests/run_tests.gd")
const Shots := preload("res://tools/screenshots.gd")

const W := 64
const H := 64


func _blank(fill: Color) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return img


# --- dead frames: every shape the black-PNG bug actually took ---

func test_solid_black_frame_is_dead() -> void:
	Runner.T.ok(not Shots._frame_is_live(_blank(Color.BLACK)),
		"solid black frame must fail the liveness gate (this is the exact bug)")


func test_solid_colour_frame_is_dead() -> void:
	# The 1768-byte PNGs weren't always black — a flat field fill is just as blind.
	Runner.T.ok(not Shots._frame_is_live(_blank(Color(0.21, 0.33, 0.17))),
		"solid mid-green frame must fail the liveness gate")


func test_single_lit_pixel_frame_is_dead() -> void:
	# Two distinct colours is not a picture; fails the colour-count arm.
	var img := _blank(Color.BLACK)
	img.set_pixel(0, 0, Color.WHITE)
	Runner.T.ok(not Shots._frame_is_live(img),
		"near-black frame with one lit pixel must fail on distinct-colour count")


func test_many_colours_but_no_contrast_is_dead() -> void:
	# Guards the OTHER arm independently: plenty of distinct colours, luma spread
	# of ~1. A dithered/compression-noise blank must not sneak past on count alone.
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			# 7 and 5 are coprime with SAMPLE_STRIDE — a %4 pattern would land on one
			# residue forever and the fixture would collapse to a single colour.
			img.set_pixel(x, y, Color8(20 + (x % 7), 20 + (y % 5), 20))
	var st := Shots.frame_stats(img)
	Runner.T.ok(int(st["colors"]) >= Shots.MIN_COLORS,
		"fixture must clear the colour-count arm to isolate the stddev arm (got %d)" % st["colors"])
	Runner.T.ok(not Shots._frame_is_live(img),
		"flat-luma frame must fail on stddev even with enough distinct colours")


func test_null_and_empty_images_are_dead() -> void:
	Runner.T.ok(not Shots._frame_is_live(null),
		"null image (no GL context) must never read as live")
	Runner.T.ok(not Shots._frame_is_live(Image.new()),
		"empty image must never read as live")


# --- live frames ---

func test_noisy_frame_is_live() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0FFEE   # view-layer tool test, not the sim — engine RNG is fine here
	for y in H:
		for x in W:
			img.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	Runner.T.ok(Shots._frame_is_live(img), "a frame full of varied pixels must read as live")


func test_gameplay_like_frame_is_live() -> void:
	# Closer to a real capture than pure noise: a dark field with a bright sprite
	# and a gradient — the kind of frame the harness is supposed to accept.
	var img := _blank(Color8(24, 40, 22))
	for y in H:
		for x in W:
			img.set_pixel(x, y, Color8(18 + y * 2, 34 + (x % 8) * 3, 20 + x))
	for y in range(24, 40):
		for x in range(24, 40):
			img.set_pixel(x, y, Color8(240, 220, 90))
	Runner.T.ok(Shots._frame_is_live(img),
		"a lit sprite over a gradient field must read as live")
	var st := Shots.frame_stats(img)
	Runner.T.ok(float(st["stddev"]) >= Shots.MIN_STDDEV,
		"gameplay-like fixture should have real luma spread (got %.2f)" % st["stddev"])


func test_thresholds_have_not_been_loosened() -> void:
	# The failure mode this whole file exists to prevent is someone "fixing" a red
	# capture by dropping the floor to 0. Pin the numbers.
	Runner.T.eq(Shots.MIN_COLORS, 12, "distinct-colour floor")
	Runner.T.eq(Shots.MIN_STDDEV, 6.0, "luma stddev floor")
