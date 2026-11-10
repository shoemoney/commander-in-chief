class_name SectorLook
extends RefCounted
## Per-sector colour look: the six sectors as six times of day. VIEW ONLY: nothing here
## reaches SimWorld or its checksum.
##
## The master grade (grade.gdshader) used to be one film for the whole run, and from sector
## 3 on the ground was nearly the same brown. A look is four numbers per sector (lift,
## gamma, gain, saturation) fed to grade.gdshader and eased by main when the sector turns.
## Lift/gain/saturation only, never a hue rotation, so the role hues and the exclusive
## lethal-bolt magenta keep their identity (tests/test_sector_look.gd measures this on
## composited colours: bolt hue drift, bolt-vs-ground and unit-vs-ground contrast).
##
## apply() is the CPU twin of the look block in grade.gdshader and MUST stay equal to it;
## the test also parses the shader to catch a uniform that stops being fed.

const NEUTRAL := {"lift": Vector3(0, 0, 0), "gamma": Vector3(1, 1, 1), "gain": Vector3(1, 1, 1), "sat": 1.0}

## Sector 1..6: dawn green, teal overcast morning, bleached noon, amber late afternoon,
## dusk (violet shadows / orange highlights), furnace-lit night.
const LOOKS := [
	{"name": "Staging Ground: cool dawn green", "lift": Vector3(0.000, 0.020, 0.010), "gamma": Vector3(1.00, 1.04, 1.00), "gain": Vector3(0.96, 1.04, 0.97), "sat": 1.04},
	{"name": "Marsh Basin: teal overcast morning", "lift": Vector3(0.000, 0.020, 0.030), "gamma": Vector3(1.00, 1.00, 1.03), "gain": Vector3(0.90, 1.01, 1.05), "sat": 0.88},
	{"name": "Bridge Gunship: bleached high noon", "lift": Vector3(0.030, 0.030, 0.025), "gamma": Vector3(0.96, 0.96, 0.96), "gain": Vector3(1.05, 1.04, 1.01), "sat": 0.86},
	{"name": "Foundry Works: amber late afternoon", "lift": Vector3(0.025, 0.010, 0.000), "gamma": Vector3(1.00, 1.00, 1.00), "gain": Vector3(1.10, 0.98, 0.82), "sat": 1.08},
	{"name": "Crashed Convoy: dusk", "lift": Vector3(0.050, 0.000, 0.075), "gamma": Vector3(1.02, 1.02, 1.00), "gain": Vector3(1.06, 0.95, 0.90), "sat": 1.00},
	{"name": "Foundry Core: furnace night", "lift": Vector3(0.000, 0.010, 0.070), "gamma": Vector3(1.03, 1.03, 1.00), "gain": Vector3(1.00, 0.95, 0.90), "sat": 0.95},
]


static func neutral() -> Dictionary:
	return NEUTRAL.duplicate()


static func look(index: int) -> Dictionary:
	return LOOKS[clampi(index, 0, LOOKS.size() - 1)]


## Which of the six looks is on screen. Campaign: the sector index (march is sector/5).
## Endless: a wave tier (two waves each) walking dawn -> furnace, then rotating the three
## late looks so a long run keeps changing light instead of sitting on one.
static func index_for(campaign: bool, march: float, wave: int) -> int:
	if campaign:
		return clampi(roundi(march * 5.0), 0, 5)
	var tier := maxi(wave, 0) / 2
	return tier if tier < 6 else 3 + (tier - 6) % 3


static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"lift": (a["lift"] as Vector3).lerp(b["lift"], t),
		"gamma": (a["gamma"] as Vector3).lerp(b["gamma"], t),
		"gain": (a["gain"] as Vector3).lerp(b["gain"], t),
		"sat": lerpf(a["sat"], b["sat"], t),
	}


## CPU twin of grade.gdshader's look block.
static func apply(c: Color, lk: Dictionary) -> Color:
	var gm: Vector3 = lk["gamma"]
	var gn: Vector3 = lk["gain"]
	var lf: Vector3 = lk["lift"]
	var g := Vector3(
		pow(maxf(c.r, 0.0), 1.0 / gm.x), pow(maxf(c.g, 0.0), 1.0 / gm.y), pow(maxf(c.b, 0.0), 1.0 / gm.z))
	g = Vector3(g.x * gn.x + lf.x * (1.0 - g.x), g.y * gn.y + lf.y * (1.0 - g.y), g.z * gn.z + lf.z * (1.0 - g.z))
	var l := g.x * 0.299 + g.y * 0.587 + g.z * 0.114
	var s: float = lk["sat"]
	g = Vector3(l, l, l).lerp(g, s)
	return Color(clampf(g.x, 0.0, 1.0), clampf(g.y, 0.0, 1.0), clampf(g.z, 0.0, 1.0), c.a)


## True for the canvas rows the CRT darkens (odd rows). Derived from UV x canvas height,
## which is what crt.gdshader does, not from window pixels.
static func scan_row_dark(uv_y: float, canvas_h: float) -> bool:
	return int(floor(uv_y * canvas_h)) % 2 == 1


## Push a look into the grade material.
static func push(mat: ShaderMaterial, lk: Dictionary) -> void:
	mat.set_shader_parameter("look_lift", lk["lift"])
	mat.set_shader_parameter("look_gamma", lk["gamma"])
	mat.set_shader_parameter("look_gain", lk["gain"])
	mat.set_shader_parameter("look_sat", lk["sat"])
