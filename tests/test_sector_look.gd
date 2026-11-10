extends RefCounted
## Ratchet for the per-sector colour look (src/view/sector_look.gd + grade.gdshader) and
## the pixel-locked CRT row.
##
## The headless suite has no framebuffer, so "rendered pixels" here are COMPOSITED colours:
## SectorLook.apply() is the CPU twin of the shader's look block (the test also parses the
## shader so the twin cannot drift from the uniforms main feeds), run over real game colours
## (the exclusive lethal bolt, the hero rim, a warm hostile, the print ink) against ground
## colours. The GL-rendered measurement of the same claim lives in the work-package report.

const Runner := preload("res://tests/run_tests.gd")

const GROUNDS := {
	"olive": Color(0.36, 0.40, 0.20),
	"sand": Color(0.58, 0.44, 0.28),
	"ash": Color(0.30, 0.27, 0.23),
	"mud": Color(0.33, 0.26, 0.17),
}
const ACTORS := {
	"lethal_bolt": Color(1.0, 0.22, 0.82),
	"hero_rim": Color(0.72, 0.93, 1.0),
	"hostile_warm": Color(0.85, 0.55, 0.35),
	"print_ink": Color(0.05, 0.06, 0.04),
}
# Colour distance actor-vs-ground may not fall below this share of the neutral value.
const MIN_CONTRAST_KEEP := 0.80
# Hue drift of the lethal bolt: lift/gain/sat is allowed to tint it, not to turn it into
# another colour. Role rims are >= 25 deg apart, so the bolt keeps well under that.
const MAX_BOLT_DRIFT_DEG := 20.0


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _hue_drift(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h) * 360.0
	return minf(d, 360.0 - d)


func test_six_looks_and_neutral_is_identity() -> void:
	Runner.T.eq(SectorLook.LOOKS.size(), 6, "six sectors, six looks")
	for c in [Color(0.2, 0.5, 0.9), Color(1.0, 0.22, 0.82), Color(0, 0, 0)]:
		var o := SectorLook.apply(c, SectorLook.neutral())
		Runner.T.ok(_dist(o, c) < 0.0005, "neutral look is an exact no-op for %s" % str(c))


func test_looks_are_distinct_on_the_ground() -> void:
	## Before: sectors 3+ shared one brown. After: every pair of looks moves the same
	## ground sample apart by a measurable amount.
	var g: Color = GROUNDS["sand"]
	for i in 6:
		for j in range(i + 1, 6):
			var d := _dist(SectorLook.apply(g, SectorLook.look(i)), SectorLook.apply(g, SectorLook.look(j)))
			Runner.T.ok(d > 0.025, "look %d and %d separate the ground (%.3f)" % [i + 1, j + 1, d])


func test_look_never_degrades_lethal_bolt_or_actor_contrast() -> void:
	for i in 6:
		var lk := SectorLook.look(i)
		var bolt: Color = ACTORS["lethal_bolt"]
		var drift := _hue_drift(bolt, SectorLook.apply(bolt, lk))
		Runner.T.ok(drift <= MAX_BOLT_DRIFT_DEG, "look %d keeps the lethal bolt hue (drift %.1f deg)" % [i + 1, drift])
		for gname in GROUNDS:
			var ground: Color = GROUNDS[gname]
			var g2 := SectorLook.apply(ground, lk)
			for aname in ACTORS:
				var a: Color = ACTORS[aname]
				var before := _dist(a, ground)
				var after := _dist(SectorLook.apply(a, lk), g2)
				Runner.T.ok(after >= before * MIN_CONTRAST_KEEP,
					"look %d: %s vs %s ground keeps contrast (%.3f -> %.3f)" % [i + 1, aname, gname, before, after])


func test_look_selection() -> void:
	Runner.T.eq(SectorLook.index_for(true, 0.0, 0), 0, "campaign sector 1")
	Runner.T.eq(SectorLook.index_for(true, 0.6, 0), 3, "campaign sector 4")
	Runner.T.eq(SectorLook.index_for(true, 1.0, 0), 5, "finale / colossus is the furnace night")
	Runner.T.eq(SectorLook.index_for(false, 0.0, 0), 0, "endless opens on dawn")
	Runner.T.eq(SectorLook.index_for(false, 0.0, 11), 5, "endless wave 11 reaches furnace")
	var seen := {}
	for w in range(12, 60):
		seen[SectorLook.index_for(false, 1.0, w)] = true
	Runner.T.eq(seen.keys().size(), 3, "deep endless rotates the three late looks")


func test_grade_shader_exposes_the_uniforms_main_feeds() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/grade.gdshader")
	for u in ["look_lift", "look_gamma", "look_gain", "look_sat"]:
		Runner.T.ok(src.contains("uniform") and src.contains(u), "grade.gdshader declares %s" % u)
	var sl := FileAccess.get_file_as_string("res://src/view/sector_look.gd")
	for u in ["look_lift", "look_gamma", "look_gain", "look_sat"]:
		Runner.T.ok(sl.contains("\"%s\"" % u), "SectorLook.push feeds %s" % u)
	Runner.T.ok(FileAccess.get_file_as_string("res://src/main.gd").contains("SectorLook.push(_grade_mat"),
		"main pushes the look into the grade material")


func test_crt_scanline_is_locked_to_the_canvas_row() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/crt.gdshader")
	Runner.T.ok(not src.contains("FRAGCOORD"), "crt.gdshader no longer reads window pixels")
	Runner.T.ok(src.contains("UV.y * canvas_size.y"), "scanline row derives from UV x canvas height")
	# At the centre of each of the 360 canvas rows the line alternates strictly, whatever
	# the window scale, because the row index comes from UV, not from the window.
	var flips := 0
	var prev := false
	for r in 360:
		var d := SectorLook.scan_row_dark((float(r) + 0.5) / 360.0, 360.0)
		Runner.T.eq(d, r % 2 == 1, "canvas row %d parity" % r)
		if r > 0 and d != prev:
			flips += 1
		prev = d
	Runner.T.eq(flips, 359, "every canvas row flips the line")
