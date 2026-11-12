class_name BossesPolish
extends RefCounted
## Set-piece presentation for vehicles and bosses (view only, never read by the sim):
## damage states (smoke, then fire, as HP drops), tread marks + exhaust behind driven
## tanks, rotor blur and a drifting ground shadow for helicopters, the styled boss HP
## bar, and the foundry arena's legibility scrim. `ci` is any CanvasItem (the Main node).
## Everything is deterministic off the physics frame counter (no RNG, no fx spawns from
## _draw), honours reduce-motion (`motion < 0.5` => static) and allocates nothing per
## frame beyond the draw calls themselves.

const PX := 1.0 / 65536.0
const SMOKE_START := 0.25   # wound fraction (1 - hp) where the first smoke appears
const FIRE_START := 0.60    # ... where fire breaks out
const TRAIL_MAX := 18       # tread-mark samples kept per vehicle
const TRAIL_STEP := 5.0     # world px between samples
const FILL_HOT := Color(0.98, 0.42, 0.12)
const FILL_BASE := Color(0.85, 0.25, 0.18)
const GOLD := Color(0.95, 0.78, 0.35)

static var _trails := {}   # key -> Array[Vector3] (world x, world y, hull angle)


static func reset() -> void:
	_trails.clear()


# ---------------------------------------------------------------- damage states

static func damage_stage(wound: float) -> int:
	## 0 pristine, 1 smoking, 2 burning.
	if wound >= FIRE_START:
		return 2
	if wound >= SMOKE_START:
		return 1
	return 0


static func smoke_count(wound: float) -> int:
	if wound < SMOKE_START:
		return 0
	return clampi(2 + int((wound - SMOKE_START) * 8.0), 2, 6)


static func fire_count(wound: float) -> int:
	if wound < FIRE_START:
		return 0
	return clampi(1 + int((wound - FIRE_START) * 12.0), 1, 4)


static func draw_damage(ci: CanvasItem, center: Vector2, wound: float, r: float, motion: float, seed_i := 0) -> void:
	## Smoke columns from stage 1, licking flames from stage 2. `r` is the hull radius.
	var stage := damage_stage(wound)
	if stage == 0:
		return
	var t := float(Engine.get_physics_frames())
	var anim := 0.0 if motion < 0.5 else 1.0
	for i in smoke_count(wound):
		var ph := fposmod(t * 0.016 * anim + float(i) * 0.19 + float(seed_i) * 0.07, 1.0)
		if anim == 0.0:
			ph = fposmod(float(i) * 0.19 + 0.1, 1.0)
		var sx := center.x + sin(float(i) * 2.3 + float(seed_i)) * r * 0.5 + ph * 6.0
		var sy := center.y - r * 0.15 - ph * (r * 1.1 + 12.0)
		var sr := 3.0 + ph * (4.0 + r * 0.16)
		var dark := 0.07 + 0.04 * float(i % 2)
		var al := minf(1.0, (1.0 - ph) * 1.1)
		ci.draw_circle(Vector2(sx, sy), sr, Color(dark, dark * 0.95, dark * 0.9, al))
		ci.draw_circle(Vector2(sx - sr * 0.25, sy - sr * 0.25), sr * 0.6, Color(dark + 0.1, dark + 0.09, dark + 0.08, al * 0.6))
	var k := clampf(r / 18.0, 1.0, 2.4)   # flame scale: a 110px colossus needs bigger fires than a tank
	for i in fire_count(wound):
		var ang := float(i) * 2.1 + float(seed_i)
		var base := center + Vector2(cos(ang), sin(ang) * 0.6) * r * 0.6
		var fl := 0.5 + 0.5 * sin(t * 0.7 * anim + float(i) * 1.9)
		var fh := (7.0 + fl * 4.0 * anim + 3.0 * wound) * k
		var fw := 4.5 * k
		ci.draw_circle(base, fw * 1.7, Color(1.0, 0.35, 0.05, 0.28))
		ci.draw_colored_polygon(_flame(base, fw, fh), Color(0.95, 0.30, 0.06, 0.95))
		ci.draw_colored_polygon(_flame(base + Vector2(0, 0.5), fw * 0.66, fh * 0.72), Color(1.0, 0.65, 0.15))
		ci.draw_colored_polygon(_flame(base + Vector2(0, 1.0), fw * 0.34, fh * 0.42), Color(1.0, 0.95, 0.65))


static func _flame(base: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([base + Vector2(-w, 0), base + Vector2(-w * 0.8, -h * 0.35),
		base + Vector2(-w * 0.25, -h * 0.6), base + Vector2(0, -h), base + Vector2(w * 0.3, -h * 0.55),
		base + Vector2(w * 0.85, -h * 0.3), base + Vector2(w, 0), base + Vector2(0, w * 0.5)])


# ---------------------------------------------------------- tanks: marks + exhaust

static func tank_wound(tank: Dictionary) -> float:
	## A tank has no HP: its "wound" is engine strain from the fuel clock, and a lit hull is all fire.
	if tank.get("burning", false):
		return 1.0
	if int(tank.get("occupant", -1)) < 0:
		return 0.0
	var f := clampf(float(tank["fuel"]) / float(SimWorld.TANK_FUEL_TICKS), 0.0, 1.0)
	return clampf((0.5 - f) * 1.4, 0.0, 0.85)


static func push_track(key, wx: int, wy: int, angle: float) -> void:
	## Record a tread-mark sample once the vehicle has moved TRAIL_STEP world px.
	var arr: Array = _trails.get(key, [])
	var p := Vector2(float(wx) * PX, float(wy) * PX)
	if not arr.is_empty():
		var last: Vector3 = arr[arr.size() - 1]
		var gap := Vector2(last.x, last.y).distance_to(p)
		if gap < TRAIL_STEP:
			return
		if gap > 60.0:
			arr.clear()   # a different vehicle reusing the key, or a teleport: no streak across the map
	arr.append(Vector3(p.x, p.y, angle))
	if arr.size() > TRAIL_MAX:
		arr.pop_front()
	_trails[key] = arr


static func track_count(key) -> int:
	return (_trails.get(key, []) as Array).size()


static func draw_tracks(ci: CanvasItem, m, key, scale := 1.0) -> void:
	## Twin dark tread lines on the ground, oldest faintest. `m._to_screen` re-projects
	## the stored world points so the marks scroll with the ground.
	var arr: Array = _trails.get(key, [])
	if arr.size() < 2:
		return
	var n := arr.size()
	var last: Vector3 = arr[n - 1]
	var ls: Vector2 = m._to_screen(int(last.x / PX), int(last.y / PX))
	if ls.y < -80.0 or ls.y > 440.0:
		return
	for i in n - 1:
		var a: Vector3 = arr[i]
		var b: Vector3 = arr[i + 1]
		var sa: Vector2 = m._to_screen(int(a.x / PX), int(a.y / PX))
		var sb: Vector2 = m._to_screen(int(b.x / PX), int(b.y / PX))
		if sa.distance_to(sb) > 30.0:
			continue
		var d := (sb - sa).normalized()
		var nrm := Vector2(-d.y, d.x) * 5.0 * scale
		var al := 0.10 + 0.32 * float(i) / float(n)
		var col := Color(0.07, 0.06, 0.04, al)
		ci.draw_line(sa + nrm, sb + nrm, col, 1.6)
		ci.draw_line(sa - nrm, sb - nrm, col, 1.6)
		# cleat ticks
		ci.draw_line(sa + nrm - d * 0.0, sa - nrm, Color(col.r, col.g, col.b, al * 0.5), 1.0)


static func draw_exhaust(ci: CanvasItem, pos: Vector2, hull: float, motion: float, big := 1.0) -> void:
	## Grey puffs drifting off the rear deck of a running engine. Hull art points up at 0,
	## so the rear is +Y rotated by the hull angle.
	if motion < 0.5:
		return
	var rear := Vector2(0, 1).rotated(hull)
	var t := float(Engine.get_physics_frames())
	var soft: Texture2D = Art.tex("fx_softspot")
	for i in 3:
		var ph := fposmod(t * 0.045 + float(i) / 3.0, 1.0)
		var p := pos + rear * (12.0 + ph * 16.0 * big) + Vector2(0, -ph * 5.0)
		var r := (2.5 + ph * 5.0) * big
		ci.draw_texture_rect(soft, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false,
			Color(0.5, 0.48, 0.44, (1.0 - ph) * 0.38))


# ------------------------------------------------------------------- helicopters

static func draw_rotor(ci: CanvasItem, pos: Vector2, radius: float, motion: float) -> void:
	## A translucent blur disc with a bright leading swept fan: reads as spinning blades,
	## not two lines. Reduce-motion freezes the fan but keeps the disc.
	var t := float(Engine.get_physics_frames())
	var soft: Texture2D = Art.tex("fx_softspot")
	ci.draw_texture_rect(soft, Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0), false,
		Color(0.78, 0.82, 0.86, 0.16))
	var base := 0.0 if motion < 0.5 else t * 0.9
	for blade in 2:
		for k in 5:
			var a := base + float(blade) * PI + float(k) * -0.13
			var al := 0.46 - float(k) * 0.09
			var v := Vector2.from_angle(a) * radius
			ci.draw_line(pos, pos + v, Color(0.9, 0.92, 0.95, al), 3.0 - float(k) * 0.4)
	ci.draw_circle(pos, 5.0, Color(0.3, 0.3, 0.35))
	ci.draw_circle(pos, 2.0, Color(0.7, 0.72, 0.78))


static func shadow_offset(sway_phase: float, motion: float) -> Vector2:
	## Where the airborne ground shadow sits relative to the hull: down-screen for altitude,
	## swinging a few px as the heli drifts so the shadow visibly travels over the ground.
	return Vector2(10.0 + sin(sway_phase) * 5.0 * motion, 40.0 + cos(sway_phase * 1.3) * 2.0 * motion)


static func draw_heli_shadow(ci: CanvasItem, pos: Vector2, radius: float, sway_phase: float, motion: float) -> void:
	var sp := pos + shadow_offset(sway_phase, motion)
	var soft: Texture2D = Art.tex("fx_softspot")
	ci.draw_texture_rect(soft, Rect2(sp.x - radius, sp.y - radius * 0.55, radius * 2.0, radius * 1.1), false,
		Color(0.0, 0.02, 0.0, 0.34))
	var t := float(Engine.get_physics_frames())
	var base := 0.0 if motion < 0.5 else t * 0.9
	for blade in 2:
		var v := Vector2.from_angle(base + float(blade) * PI) * radius * 0.9
		v.y *= 0.55
		ci.draw_line(sp - v * 0.2, sp + v, Color(0.0, 0.02, 0.0, 0.22), 2.0)


# ------------------------------------------------------------------- HP bar

static func fill_color(frac: float, base := FILL_BASE) -> Color:
	## The fill heats toward orange as the boss nears death.
	return base.lerp(FILL_HOT, clampf(1.0 - frac * 2.2, 0.0, 1.0)) if base == FILL_BASE else base


static func pip_lit(k: int, ticks: int, frac: float) -> bool:
	## Phase pip k (1-based of ticks-1 dividers) is "burned through" once HP is below its mark.
	return frac <= float(k) / float(maxi(ticks, 1))


static func draw_bar(ci: CanvasItem, rect: Rect2, frac: float, fill: Color, ghost: float, ticks: int, motion: float) -> void:
	var inset := Vector2(rect.size.x * 0.06, rect.size.y * 0.22)
	var well := Rect2(rect.position + inset, rect.size - inset * 2.0)
	frac = clampf(frac, 0.0, 1.0)
	var fw := well.size.x
	ci.draw_rect(well, Color(0.05, 0.04, 0.04, 0.95))
	if ghost > frac:
		ci.draw_rect(Rect2(well.position + Vector2(fw * frac, 0), Vector2(fw * (ghost - frac), well.size.y)),
			Color(1.0, 0.86, 0.5, 0.75))
	if frac > 0.0:
		var fc := fill_color(frac, fill)
		var fr := Rect2(well.position, Vector2(fw * frac, well.size.y))
		ci.draw_rect(fr, fc.darkened(0.25))
		ci.draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(1.0, fr.size.y * 0.55))), fc)
		ci.draw_rect(Rect2(fr.position, Vector2(fr.size.x, 1.0)), fc.lightened(0.45))
		# leading-edge glint, pulsing when nearly dead
		var lowp := 1.0 if frac > 0.25 or motion < 0.5 else 0.6 + 0.4 * sin(float(Engine.get_physics_frames()) * 0.3)
		ci.draw_rect(Rect2(fr.end.x - 1.0, fr.position.y, 1.0, fr.size.y), Color(1, 0.95, 0.8, 0.9 * lowp))
	# phase pips: diamond notches on the well edge, gold once that phase is burned through
	for k in range(1, ticks):
		var tx := well.position.x + fw * float(k) / float(ticks)
		var lit := pip_lit(k, ticks, frac)
		var pc := Color(0.04, 0.03, 0.03, 0.9)
		ci.draw_line(Vector2(tx, well.position.y), Vector2(tx, well.end.y), pc, 1.0)
		var dc := Color(0.35, 0.3, 0.22) if lit else GOLD
		var cy := rect.end.y - 1.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(tx - 3.0, cy), Vector2(tx, cy - 3.0),
			Vector2(tx + 3.0, cy), Vector2(tx, cy + 3.0)]), dc)
	# end caps: gold brackets so the bar reads as a boss plate, not a progress strip
	var cy0 := rect.position.y + 1.0
	var cy1 := rect.end.y - 1.0
	for sx in [rect.position.x + 1.0, rect.end.x - 1.0]:
		var dir := 1.0 if sx < rect.get_center().x else -1.0
		ci.draw_line(Vector2(sx, cy0), Vector2(sx, cy1), GOLD, 1.0)
		ci.draw_line(Vector2(sx, cy0), Vector2(sx + 4.0 * dir, cy0), GOLD, 1.0)
		ci.draw_line(Vector2(sx, cy1), Vector2(sx + 4.0 * dir, cy1), GOLD, 1.0)


# ------------------------------------------------------------------- arena

static func draw_arena_scrim(ci: CanvasItem, center: Vector2, motion: float) -> void:
	## The finale floor is red-brown on red-brown. A cool dark pool under the fight desaturates
	## the clutter around the boss so the telegraph rings, bullets and hull separate from it.
	var soft: Texture2D = Art.tex("fx_softspot")
	ci.draw_texture_rect(soft, Rect2(center.x - 330.0, center.y - 230.0, 660.0, 460.0), false,
		Color(0.03, 0.03, 0.05, 0.5))
	ci.draw_texture_rect(soft, Rect2(center.x - 190.0, center.y - 130.0, 380.0, 260.0), false,
		Color(0.03, 0.03, 0.06, 0.3))
