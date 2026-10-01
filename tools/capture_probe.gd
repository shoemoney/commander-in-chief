class_name CaptureProbe
extends RefCounted
## ONE lit-predicate for every GL capture tool in this repo.
##
## WHY THIS EXISTS — and it is the second time this class of bug has cost this
## repo real time.
##
## The blank-frame gate (added to stop tools printing SAVED over black PNGs) summed
## get_pixel() components and compared against 96.0. get_pixel() on a GL viewport
## returns 0..1 floats, so every pixel of a correctly rendered frame summed to at
## most 3.0. The gate scored lit frames zero and printed "BLANK FRAME" with total
## confidence, while the SAME image object saved by save_png one line later was
## 14,262/14,400 lit. Six probes were spent chasing a black frame that did not
## exist.
##
## Then role_sheet.gd carried the identical bug in three more copies of the same
## expression, which is why it ALWAYS exited 2 — read six separate times as "the
## capture is broken" when it was reporting a false failure in a different place.
##
## Four copies of one threshold, hardcoded, is how a scale error survives a test
## suite that is otherwise 1,249 methods of green. This file is the single
## definition, and tests/test_capture_probe.gd plants the cases that must hold —
## including the two that actually bit us.


## Is this image "a frame with content"?
##
## `min_lit` is the fraction of the sampling grid that must be brighter than
## `level`. Kept as a FRACTION so the caller cannot reintroduce an 8-bit scale by
## accident, and kept in ONE place so a fix cannot be applied to one call site and
## missed in the other three.
static func lit_fraction(img: Image, step: int = 8, level: float = LIT_LEVEL) -> float:
	if img == null:
		return 0.0
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	var lit := 0
	var total := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			total += 1
			var c := img.get_pixel(x, y)
			# 0..1 SUM, compared against a 0..1 level. This is the whole fix.
			if c.r + c.g + c.b > level:
				lit += 1
	if total == 0:
		return 0.0
	return float(lit) / float(total)


## The brightness level a pixel must exceed to count as content. 0.37 in 0..1 is
## ~0.123 per channel: dark enough that shadowed jungle turf and dark UI chrome do
## not count as content, bright enough that lit ground, sprites and HUD text do.
const LIT_LEVEL := 0.37

## Minimum lit fraction for a frame to be considered real content. A real captured
## frame measures 0.99; a black or not-yet-rendered frame measures 0.00. The gap is
## enormous, so this threshold is not delicate — it is only here to reject the
## degenerate cases, not to make fine judgements about an image.
const MIN_LIT_FRACTION := 0.02


## Would this tool be about to save an unusable frame? Returns a REASON string when
## it must refuse, or "" when the frame is good. Callers print the reason and skip
## the save; they do not decide for themselves, because "deciding for itself" is
## how four copies of one threshold happened.
static func refuse_reason(img: Image) -> String:
	if img == null:
		return "no image from the viewport"
	if img.get_width() <= 0 or img.get_height() <= 0:
		return "zero-sized frame %dx%d" % [img.get_width(), img.get_height()]
	var f := lit_fraction(img)
	if f < MIN_LIT_FRACTION:
		return "frame is %.1f%% lit, below the %.1f%% floor — refusing to save a black PNG" % [
			f * 100.0, MIN_LIT_FRACTION * 100.0]
	return ""
