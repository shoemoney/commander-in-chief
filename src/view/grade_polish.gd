class_name GradePolish
extends RefCounted
## Master grade de-murk. VIEW ONLY. Real blacks (black point), midtone separation (S-curve)
## and richer colour (saturation boost), applied inside grade.gdshader before the sector
## look. apply() is the CPU twin of that block and must stay numerically equal to it.

const BLACK_POINT := 0.05
const CONTRAST := 0.55
const SAT_BOOST := 1.22
## Shadow warmth added by the shader (scaled by 1 - luma). Was 0.030/0.014/-0.010, which lifted blacks.
const SHADOW_WARM := Vector3(0.006, 0.003, -0.002)


static func push(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("black_point", BLACK_POINT)
	mat.set_shader_parameter("contrast", CONTRAST)
	mat.set_shader_parameter("sat_boost", SAT_BOOST)


static func apply(c: Color) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	v = Vector3(maxf(v.x - BLACK_POINT, 0.0), maxf(v.y - BLACK_POINT, 0.0), maxf(v.z - BLACK_POINT, 0.0)) / (1.0 - BLACK_POINT)
	var sc := Vector3(v.x * v.x * (3.0 - 2.0 * v.x), v.y * v.y * (3.0 - 2.0 * v.y), v.z * v.z * (3.0 - 2.0 * v.z))
	v = v.lerp(sc, CONTRAST)
	var l := v.x * 0.299 + v.y * 0.587 + v.z * 0.114
	v = Vector3(l, l, l).lerp(v, SAT_BOOST)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0), c.a)
