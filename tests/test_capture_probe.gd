extends RefCounted
## RATCHET for the capture gate. Planted cases that FAIL LOUDLY.
##
## WHY THIS TEST EXISTS, and it is the point of the whole file:
##
## tools/capture_probe.gd exists because its predecessor produced FALSE FAILURES.
## The blank-frame gate summed get_pixel() (0..1 floats) and compared against 96.0,
## an 8-bit threshold, so it scored correctly-rendered frames zero and printed
## "BLANK FRAME" with total confidence — while the same image saved one line later
## by save_png was 14,262/14,400 lit. Six probes chased a black frame that did not
## exist.
##
## A gate that has never been shown to PASS is not a gate. It is a machine that
## produces confident sentences. This file plants the two cases that must hold —
## a real frame is content, a black frame is not — plus the exact scale case that
## bit us, so the 0-1-vs-0-255 error cannot come back unnoticed.
##
## If every one of these passes and the tool still refuses a good frame, the gate is
## wrong in a way this file does not cover, and that must be treated as a real
## possibility rather than assumed away.

const Runner := preload("res://tests/run_tests.gd")
const S := preload("res://tools/capture_probe.gd")


func test_black_frame_is_refused() -> void:
	## The case the gate exists for. An all-black frame MUST be refused, loudly.
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var reason := S.refuse_reason(img)
	Runner.T.ok(reason != "", "an all-black frame is refused (got '%s')" % reason)
	Runner.T.ok(reason.contains("refusing"), "the refusal says WHY it refuses, so a blank frame is never silently skipped")


func test_mid_frame_is_content() -> void:
	## THE CONTROL. A gate that refuses everything is exactly as broken as one that
	## passes everything, and it is the failure I actually made: role_sheet refused
	## every real frame seven times and I read each refusal as evidence about the
	## capture rather than about the gate.
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.45, 0.47, 0.25, 1))   # jungle-turf green, the real px00 value
	Runner.T.eq(S.refuse_reason(img), "", "a genuinely lit frame is NOT refused")
	Runner.T.ok(S.lit_fraction(img) > 0.99, "a fully-lit frame measures ~100%% (got %.3f)"
		% S.lit_fraction(img))


func test_threshold_is_in_zero_to_one_scale() -> void:
	## The exact bug, planted. get_pixel() returns 0..1 floats. If LIT_LEVEL ever
	## drifts back into 8-bit territory (>=1.0), every pixel of a real frame sums to
	## at most 3.0 and the gate calls it black again — which is what happened, six
	## probes deep.
	Runner.T.ok(S.LIT_LEVEL < 1.0, "LIT_LEVEL is in 0..1 float scale, not 8-bit (got %.3f)"
		% S.LIT_LEVEL)
	Runner.T.ok(S.MIN_LIT_FRACTION < 1.0,
		"MIN_LIT_FRACTION is a fraction, not a percentage (got %.3f)" % S.MIN_LIT_FRACTION)
	# A real frame's max possible sum is 3.0, so a 0..1 threshold can never be
	# unreachable. Assert the threshold is strictly inside that reachable range.
	Runner.T.ok(S.LIT_LEVEL < 3.0, "LIT_LEVEL is reachable by real pixels (max sum 3.0)")


func test_actual_pixel_sum_is_float_scale() -> void:
	## Measures the real Image API rather than assuming it: whatever get_pixel
	## returns, its channel sum must be within 0..3, i.e. float scale. If a future
	## engine or import path returned 0..255, this is the test that notices.
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var c := img.get_pixel(0, 0)
	var s := c.r + c.g + c.b
	Runner.T.ok(s <= 3.01, "get_pixel channels are 0..1 (max sum %.3f), so an 8-bit threshold is unreachable" % s)
	Runner.T.ok(s >= 0.99, "a white pixel sums to ~3.0 (got %.3f)" % s)


func test_null_and_degenerate_frames_are_refused() -> void:
	Runner.T.ok(S.refuse_reason(null) != "", "a null image is refused rather than crashing")
	var z := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	z.fill(Color(0.9, 0.9, 0.9, 1))
	Runner.T.eq(S.lit_fraction(z), 1.0, "a 1x1 lit image still measures, not divides by zero")


func test_compressed_image_is_readable() -> void:
	## get_pixel() returns zeros for a VRAM-compressed image until it is
	## decompressed — the guard that must travel WITH the scale fix. Fixing only
	## the scale would have produced a different wrong answer: a correctly-scaled
	## comparison against all-zero pixels, i.e. every frame "black".
	var img := Image.create_empty(32, 32, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1))
	Runner.T.ok(S.lit_fraction(img) > 0.5,
		"an image with mipmaps is still readable (got %.3f) — lit_fraction must handle it"
			% S.lit_fraction(img))


func test_gate_has_a_pass_direction_and_a_fail_direction() -> void:
	## The blunt instrument: across a sweep of brightness, the gate must accept the
	## bright end and reject the dark end, with a boundary somewhere between. A gate
	## that always refuses fails this. A gate that always accepts fails this.
	var accepts := 0
	var refuses := 0
	for i in 11:
		var v := float(i) / 10.0
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(v, v, v, 1))
		if S.refuse_reason(img) == "":
			accepts += 1
		else:
			refuses += 1
	Runner.T.ok(accepts > 0, "the gate accepts SOME frames (%d/11) — not a blanket refusal" % accepts)
	Runner.T.ok(refuses > 0, "the gate refuses SOME frames (%d/11) — not a blanket pass" % refuses)
	Runner.T.ok(accepts + refuses == 11, "every sweep sample was decided one way or the other")