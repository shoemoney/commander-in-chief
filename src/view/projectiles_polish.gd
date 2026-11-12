class_name ProjectilesPolish
extends RefCounted
## View-only projectile readability. In a one-hit-kill shooter enemy fire has to be the
## most legible thing on screen: dark outline + saturated body + hot core + halo for
## hostile rounds, tapered hot-core tracers for the player's, an exhaust plume for
## rockets and a dotted arc to the landing point for grenades. Nothing here touches the
## sim; every size is a pure function of sim state the caller already read.

const PX := 1.0 / Fixed.ONE
const OUTLINE := Color(0.02, 0.01, 0.02, 0.92)
const ENEMY_BODY := Color(1.0, 0.22, 0.82)
const ENEMY_CORE := Color(1.0, 0.93, 0.55)
const SNIPER_CORE := Color(1.0, 0.98, 0.85)

## Hostile glow halo radius in px. It reaches out to the lethal radius so the lit area a
## player sees is never smaller than the area that kills; the solid body stays inside it.
static func enemy_halo_radius(fast: bool) -> float:
	return maxf(float(SimWorld.ENEMY_BULLET_HIT_RADIUS) * PX, 8.0 if fast else 7.0)


static func enemy_body_radius(fast: bool) -> float:
	return 3.4 if fast else 3.0


## Streak length behind a hostile round; faster rounds read proportionally longer.
static func enemy_tail(speed_ratio: float) -> float:
	return 7.0 + maxf(0.0, speed_ratio - 1.0) * 8.0


## Pass 1 (under the card): the halo, as wide as the lethal radius.
static func draw_enemy_halo(c: CanvasItem, pos: Vector2, speed_ratio: float, frame: int, motion: float) -> void:
	var halo := enemy_halo_radius(speed_ratio > 1.4)
	var pulse := 1.0 if motion < 0.5 else 0.88 + 0.12 * sin(float(frame) * 0.5)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * halo, Vector2.ONE * halo * 2.0),
		false, Color(1.0, 0.22, 0.82, 0.8 * pulse))


## Pass 2 (over the card): tapered wake, dark outline, saturated body, hot core.
static func draw_enemy_body(c: CanvasItem, pos: Vector2, dir: Vector2, speed_ratio: float) -> void:
	var fast := speed_ratio > 1.4
	var body := enemy_body_radius(fast)
	if dir.length() > 0.5:
		var tail := enemy_tail(speed_ratio)
		Art.line(c, pos - dir * tail * 0.45, pos, ENEMY_BODY, body * 1.6)
	Art.circle(c, pos, body + 1.4, OUTLINE)
	Art.circle(c, pos, body, ENEMY_BODY)
	Art.circle(c, pos, body * 0.55, SNIPER_CORE if fast else ENEMY_CORE)


## Four tapering segments, tail to head: [from, to, width, alpha].
static func tracer_segments(pos: Vector2, dir: Vector2, length: float) -> Array:
	var out: Array = []
	for k in 4:
		var t0 := float(k) / 4.0
		var t1 := float(k + 1) / 4.0
		out.append([pos - dir * length * (1.0 - t0), pos - dir * length * (1.0 - t1),
			1.4 + t1 * 2.2, 0.3 + 0.75 * t1])
	return out


static func draw_player_tracer(c: CanvasItem, pos: Vector2, dir: Vector2, length: float, heat: float, piercing: bool) -> void:
	var glow := Color(0.35, 0.9, 1.0) if piercing else Color(1.0, 0.7, 0.2).lerp(Color(1.0, 0.95, 0.6), heat)
	var hot := Color(0.85, 1.0, 1.0) if piercing else Color(1.0, 0.98, 0.85)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * 4.5, Vector2.ONE * 9.0), false,
		Color(glow.r, glow.g, glow.b, 0.7))
	for s in tracer_segments(pos, dir, length):
		Art.line(c, s[0], s[1], Color(0.02, 0.02, 0.04, 0.4 * s[3]), s[2] + 1.6)
	for s in tracer_segments(pos, dir, length):
		Art.line(c, s[0], s[1], Color(glow.r, glow.g, glow.b, s[3]), s[2])
	Art.line(c, pos - dir * length * 0.4, pos, hot, 1.8)
	Art.circle(c, pos, 2.0, hot)


## Underlay for a rocket: a long fading exhaust plume, drawn BEFORE the weapon_fx body.
static func draw_rocket_exhaust(c: CanvasItem, pos: Vector2, dir: Vector2, frame: int, motion: float) -> void:
	var flick := 0.0 if motion < 0.5 else float(frame % 3) * 0.8
	var n := Vector2(-dir.y, dir.x)
	c.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - dir * 6.0 - Vector2.ONE * 7.0, Vector2.ONE * 14.0), false,
		Color(1.0, 0.55, 0.15, 0.5))
	for k in 6:
		var t := float(k) / 6.0
		var p := pos - dir * (5.0 + t * 20.0) + n * sin(float(frame) * 0.3 + float(k)) * 0.5 * motion
		Art.circle(c, p, 3.2 - t * 1.8 + flick * 0.2, Color(1.0, 0.75 - t * 0.35, 0.2, 0.55 * (1.0 - t)))


## Dotted arc from the airborne frag to its landing point, bulging upward mid-flight.
static func grenade_arc(body: Vector2, land: Vector2, n := 6) -> Array:
	var pts: Array = []
	var bulge := minf(body.distance_to(land) * 0.15, 10.0)
	for k in range(1, n + 1):
		var t := float(k) / float(n + 1)
		pts.append(body.lerp(land, t) - Vector2(0.0, sin(PI * t) * bulge))
	return pts


static func draw_grenade_arc(c: CanvasItem, body: Vector2, land: Vector2) -> void:
	var pts := grenade_arc(body, land)
	for i in pts.size():
		var a := 0.75 * (1.0 - float(i) / float(pts.size()) * 0.6)
		Art.circle(c, pts[i], 1.5, Color(0.02, 0.02, 0.04, a * 0.6))
		Art.circle(c, pts[i], 0.9, Color(1.0, 0.95, 0.7, a))
