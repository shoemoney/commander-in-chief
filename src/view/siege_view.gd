class_name SiegeView
extends RefCounted
## The Siege Tank's presentation (the sim half is src/sim/siege_boss.gd). Lives in its own
## script so the 16k-line main.gd carries only hook lines. Every telegraph here is read back
## from the sim's own accessors -- lane(), sweep_arc(), weak_point(), weak_open() -- never
## from a constant of the view's: the lane drawn IS the segment the sim sweeps, the fan drawn
## IS the beams the sim fires, the plate drawn open IS the one place a bullet counts.
## `m` is the Main node (it owns _spr / _to_screen / the boss chrome queue).

const BANNER := "SIEGE TANK"
const BAND := "DESTROY THE SIEGE TANK TO ADVANCE"
const PX := 1.0 / 65536.0
const HULL_SCALE := 1.0
const COL_WARN := Color(1.0, 0.75, 0.25)
const COL_LIVE := Color(1.0, 0.25, 0.18)
const COL_WEAK := Color(0.55, 1.0, 0.6)


static func label(boss: Dictionary) -> String:
	## The plate under the top-centre boss bar: name, act, and the one live cue that matters.
	var s := "%s — %s" % [BANNER, SiegeBoss.act_name(SiegeBoss.act_of(boss))]
	if SiegeBoss.weak_open(boss):
		s += " · REAR OPEN"
	return s


static func hull_angle(boss: Dictionary) -> float:
	## Sprite angle for the sim's facing (the tank art points up at 0).
	return atan2(float(boss["fy"]), float(boss["fx"])) + PI / 2.0


static func lane_corners(lane: Dictionary, scale_px: float) -> Array:
	## The four screen-space-free corners [a0, a1, b0, b1] of the lane rectangle in WORLD px,
	## from the sim's lane() dict. Pure so a test can compare it with the swept hull.
	var sx: float = float(lane["sx"]) * PX
	var sy: float = float(lane["sy"]) * PX
	var ex: float = float(lane["ex"]) * PX
	var ey: float = float(lane["ey"]) * PX
	var d := Vector2(ex - sx, ey - sy)
	var n := Vector2(-d.y, d.x).normalized() * float(lane["half_w"]) * PX * scale_px
	return [Vector2(sx, sy) + n, Vector2(sx, sy) - n, Vector2(ex, ey) + n, Vector2(ex, ey) - n]


static func draw(m, boss: Dictionary, slot: int) -> void:
	var sim: SimWorld = m.sim
	var c: Vector2 = m._to_screen(boss["x"], boss["y"])
	_draw_lane(m, boss)
	_draw_fan(m, boss)
	var ang := hull_angle(boss)
	BossesPolish.draw_tracks(m, m, "siege", 1.6)
	var face := Vector2(float(boss["fx"]), float(boss["fy"])) * PX
	m._ground_shadow(c + Vector2(0, 6), 30.0, 0.38)
	var mod := Color(1.12, 0.92, 0.82)
	if boss["st"] == SiegeBoss.St.REV or boss["st"] == SiegeBoss.St.SWEEP_WARN:
		# Anticipation: the hull heats before it commits (same cue family as the gunship's mortar flash).
		if m._motion < 0.5 or (Engine.get_physics_frames() / 5) % 2 == 0:
			mod = Color(1.5, 0.7, 0.55)
	mod = mod.lerp(Color(2.2, 2.2, 2.2), m._boss_flash)
	m._spr("tank_body", c, ang, m.VEHICLE_CONTACT["tank_body"]["call_scale"] * 1.5 * HULL_SCALE, mod)
	m._spr("tank_barrel", c + face * 12.0, ang, 0.62 * 1.5 * HULL_SCALE, mod)
	if m._boss_flash > 0.01:
		Art.circle(m, c, 30.0 + m._boss_flash * 10.0, Color(1, 1, 1, m._boss_flash * 0.25))
	_draw_weak_point(m, boss)
	var bkey := "boss%d" % boss["gate_y"]
	m._boss_hpmax[bkey] = maxf(m._boss_hpmax.get(bkey, 1.0), float(boss["hp"]))
	var bfrac := minf(1.0, float(boss["hp"]) / m._boss_hpmax[bkey])
	BossesPolish.push_track("siege", boss["x"], boss["y"], ang)
	BossesPolish.draw_exhaust(m, c, ang, m._motion, 1.6)
	BossesPolish.draw_damage(m, c, 1.0 - bfrac, 30.0, m._motion, 3)
	m._boss_wounds(c, 1.0 - bfrac, 30.0)
	# pt = -1: no mortar countdown on this boss's bar (the bar names the act via label()).
	m._boss_chrome.append({"kind": "gunship", "boss": boss, "label": BANNER, "slot": slot, "pt": -1})


static func _draw_lane(m, boss: Dictionary) -> void:
	var lane := SiegeBoss.lane(boss)
	if lane.is_empty():
		return
	var s0: Vector2 = m._to_screen(lane["sx"], lane["sy"])
	var e0: Vector2 = m._to_screen(lane["ex"], lane["ey"])
	var along := (e0 - s0)
	var perp := Vector2(-along.y, along.x).normalized() * float(lane["half_w"]) * PX
	var a0 := s0 + perp
	var a1 := s0 - perp
	var b0 := e0 + perp
	var b1 := e0 - perp
	var live: bool = lane["live"]
	var left: int = lane["left"]
	# Pulse quickens as the rev runs out; reduce-motion holds it steady.
	var pulse := 0.6 if m._motion < 0.5 else 0.5 + 0.5 * sin(float(Engine.get_physics_frames()) * (0.25 if left > 12 else 0.6))
	var col: Color = Art.safe(COL_LIVE if live else COL_WARN)
	col.a = 0.95 if live else (0.7 + 0.3 * pulse)
	Art.line(m, a0, b0, col, 1.0)
	Art.line(m, a1, b1, col, 1.0)
	Art.line(m, a0, a1, col, 1.0)
	Art.line(m, b0, b1, col, 1.0)
	Art.arc(m, e0, float(lane["half_w"]) * PX, 0.0, TAU, 20, col, 1.0)   # where the hull comes to rest
	# Chevrons down the middle: which way it will run.
	var dir := (e0 - s0)
	var n := dir.length()
	if n > 8.0:
		dir /= n
		var cperp := Vector2(-dir.y, dir.x)
		var k := 24.0
		while k < n:
			var p := s0 + dir * k
			Art.line(m, p - dir * 4.0 + cperp * 5.0, p, col, 1.0)
			Art.line(m, p - dir * 4.0 - cperp * 5.0, p, col, 1.0)
			k += 28.0


static func _draw_fan(m, boss: Dictionary) -> void:
	var arc := SiegeBoss.sweep_arc(boss)
	if arc.is_empty():
		return
	var apex: Vector2 = m._to_screen(arc["x"], arc["y"])
	var rng_px: float = float(arc["range"]) * PX
	var live: bool = arc["live"]
	var pulse := 0.6 if m._motion < 0.5 else 0.5 + 0.5 * sin(float(Engine.get_physics_frames()) * 0.4)
	var col: Color = Art.safe(COL_LIVE if live else COL_WARN)
	col.a = 0.85 if live else (0.35 + 0.4 * pulse)
	var lo := Vector2(float(arc["lo"][0]), float(arc["lo"][1])) * PX
	var hi := Vector2(float(arc["hi"][0]), float(arc["hi"][1])) * PX
	Art.line(m, apex, apex + lo * rng_px, col, 1.0)
	Art.line(m, apex, apex + hi * rng_px, col, 1.0)
	# Range arcs between the edges: how far the rounds actually fly is the outer one.
	var a_lo := lo.angle()
	var a_hi := hi.angle()
	for r in [90.0, 180.0, 300.0]:
		Art.arc(m, apex, r, a_lo, a_hi, 14, col, 1.0)
	if live and arc["beam"] >= 0:
		var bd := SiegeBoss.fan_dir(boss["fx"], boss["fy"], arc["beam"])
		var hot := Vector2(float(bd[0]), float(bd[1])) * PX
		Art.line(m, apex, apex + hot * rng_px, Color(1, 1, 1, 0.9), 1.0)


static func _draw_weak_point(m, boss: Dictionary) -> void:
	if not SiegeBoss.weak_open(boss):
		return
	var w := SiegeBoss.weak_point(boss)
	var wp: Vector2 = m._to_screen(w[0], w[1])
	var r: float = float(SiegeBoss.WEAK_R) * PX
	var pulse := 0.7 if m._motion < 0.5 else 0.6 + 0.4 * sin(float(Engine.get_physics_frames()) * 0.3)
	var col: Color = Art.safe(COL_WEAK)
	Art.circle(m, wp, r, Color(col.r, col.g, col.b, 0.25 * pulse))
	Art.arc(m, wp, r, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.95), 1.0)
	# The window clock: the arc around the plate drains with the sim's own wp counter.
	var frac := float(boss["wp"]) / float(maxi(1, boss["wpm"]))
	Art.arc(m, wp, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24, Color(col.r, col.g, col.b, 0.8), 1.0)
