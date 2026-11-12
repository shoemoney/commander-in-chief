extends RefCounted
## Master grade de-murk: real blacks, midtone separation, richer colour, subtle scanlines.

const Runner := preload("res://tests/run_tests.gd")


func test_blacks_are_real_and_midtones_separate() -> void:
	var k := GradePolish.apply(Color(0.04, 0.04, 0.04))
	Runner.T.ok(k.r < 0.005, "near-black maps to true black (%.4f)" % k.r)
	var lo := GradePolish.apply(Color(0.40, 0.40, 0.40)).r
	var hi := GradePolish.apply(Color(0.60, 0.60, 0.60)).r
	Runner.T.ok(hi - lo > 0.20, "midtone separation widened beyond 0.20 input gap (%.3f)" % (hi - lo))


func test_colour_is_richer_not_garish() -> void:
	var c := Color(0.36, 0.40, 0.20)
	var o := GradePolish.apply(c)
	Runner.T.ok(o.s > c.s * 1.1, "saturation up (%.2f -> %.2f)" % [c.s, o.s])
	Runner.T.ok(o.s < 1.0, "not clipped to garish")


func test_scanlines_subtle_at_rest() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("const SCANLINE_BASE := ")
	var base := float(src.substr(i + 23, 6))
	Runner.T.ok(base <= 0.02 and base > 0.0, "resting scanline strength is subtle (%.3f)" % base)


func test_wired_through_main_and_shader() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("GradePolish.push(_grade_mat"), "main feeds the de-murk uniforms")
	var sh := FileAccess.get_file_as_string("res://src/view/grade.gdshader")
	for u in ["black_point", "contrast", "sat_boost"]:
		Runner.T.ok(sh.contains("uniform float " + u), "shader declares " + u)
	var m := ShaderMaterial.new()
	GradePolish.push(m)
	Runner.T.eq(m.get_shader_parameter("black_point"), GradePolish.BLACK_POINT, "push sets black_point")
