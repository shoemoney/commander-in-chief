class_name WeaponFx
extends RefCounted
## View side of the special weapons (src/sim/weapons.gd). Stateless: the flame stream is
## derived from the player's hashed fire_cd (non-zero for the 4 ticks after each burst), the
## rocket from sim.rockets, so nothing here can drift from what the sim did. Every extent it
## draws comes from Weapons.TABLE, the same numbers the sim hit-tests with -- the cone polygon
## below is the sim's cone, vertex for vertex (tests/test_weapons_view.gd sweeps the two).

const PX := 1.0 / Fixed.ONE


static func cone_polygon(origin: Vector2, aim: Vector2, reach: float, tan_half: float, pad: float) -> PackedVector2Array:
	## The exact region Weapons.in_cone accepts, in screen px: a pad-wide strip behind the muzzle
	## widening to +-(tan * length + pad) at reach + pad.
	var a := aim.normalized()
	var n := Vector2(-a.y, a.x)
	var far := reach + pad
	var half_far := far * tan_half + pad
	return PackedVector2Array([
		origin - a * pad - n * pad,
		origin - n * pad,
		origin + a * far - n * half_far,
		origin + a * far + n * half_far,
		origin + n * pad,
		origin - a * pad + n * pad,
	])


static func flame_cone(origin: Vector2, aim: Vector2, reach_px := -1.0) -> PackedVector2Array:
	## reach_px < 0 = the open-field reach; the live draw passes SimWorld.flame_reach(p) so the
	## cone stops where the sim's does (indestructible cover clips it).
	var wt: Dictionary = Weapons.TABLE[Weapons.FLAME]
	return cone_polygon(origin, aim, float(wt["reach"]) * PX if reach_px < 0.0 else reach_px, float(wt["tan"]) / float(Fixed.ONE), float(wt["pad"]) * PX)


static func blast_radius_px() -> float:
	return float(Weapons.TABLE[Weapons.ROCKET]["blast"]) * PX


static func on_event(ev: Dictionary, fx: Array) -> void:
	## Rocket blast: the ring marks the REAL splash radius (the generic shockwave grows past it).
	if ev["t"] == "explosion" and ev.get("src", "") == "rocket":
		fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.1,
			"sz": blast_radius_px(), "grow_px": 0.0, "col": Color(1.0, 0.8, 0.45, 0.8)})


static func _hash01(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663)
	h = (h >> 5) & 0xFFFF
	return float(h) / 65535.0


static func draw_world(c: CanvasItem, sim: SimWorld, to_screen: Callable, motion: float) -> void:
	var frame := Engine.get_physics_frames()
	for pi in sim.players.size():
		var p: Dictionary = sim.players[pi]
		if p["alive"] and p.get("weapon", 0) == Weapons.FLAME and p["fire_cd"] > 0:
			_draw_flame(c, to_screen.call(p["x"], p["y"]), Vector2(p["aim_x"], p["aim_y"]) * PX, frame, pi, motion,
				float(sim.flame_reach(p)) * PX)
	for r in sim.rockets:
		var pos: Vector2 = to_screen.call(r["x"], r["y"])
		if pos.y < -20.0 or pos.y > 380.0 or pos.x < -20.0 or pos.x > 660.0:
			continue
		_draw_rocket(c, pos, Vector2(r["vx"], r["vy"]).normalized(), frame)


static func _draw_flame(c: CanvasItem, origin: Vector2, aim: Vector2, frame: int, pi: int, motion: float, reach: float) -> void:
	var wt: Dictionary = Weapons.TABLE[Weapons.FLAME]
	var tan_half := float(wt["tan"]) / float(Fixed.ONE)
	var poly := flame_cone(origin, aim, reach)
	var hot := Color(1.0, 0.55, 0.15, 0.16)
	c.draw_colored_polygon(poly, hot)
	var a := aim.normalized()
	var n := Vector2(-a.y, a.x)
	var tex := Art.tex("fx_flame")
	var steps := 9
	var jit_frame := frame >> 1 if motion >= 0.5 else 0
	for k in steps:
		var t := (float(k) + 0.5) / float(steps)
		var along := 6.0 + t * (reach - 6.0)
		var width := along * tan_half
		var off := (_hash01(k * 31 + pi, jit_frame) * 2.0 - 1.0) * width * 0.7
		var sz := 10.0 + t * 20.0
		var col := Color(1.0, 0.9 - t * 0.5, 0.55 - t * 0.45, 0.85 - t * 0.45)
		var pos := origin + a * along + n * off
		c.draw_set_transform(pos, a.angle() + PI / 2.0, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), false, col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_rocket(c: CanvasItem, pos: Vector2, dir: Vector2, frame: int) -> void:
	var n := Vector2(-dir.y, dir.x)
	# Smoke trail: fading puffs strung back along the flight line.
	for k in 7:
		var back := pos - dir * (4.0 + float(k) * 4.5)
		var al := 0.5 * (1.0 - float(k) / 7.0)
		Art.circle(c, back + n * (float(((frame >> 1) + k) % 3) - 1.0) * 0.6, 2.2 + float(k) * 0.45, Color(0.72, 0.7, 0.66, al))
	# Motor flame, then the body: a short fat shell with a red nose.
	var jet := 3.0 + float(frame % 3)
	Art.line(c, pos - dir * 4.0, pos - dir * (4.0 + jet), Color(1.0, 0.75, 0.25, 0.95), 2.4)
	Art.line(c, pos - dir * 4.0, pos - dir * (4.0 + jet * 0.5), Color(1.0, 0.97, 0.8), 1.2)
	Art.line(c, pos - dir * 3.5, pos + dir * 3.0, Color(0.82, 0.84, 0.8), 3.0)
	Art.line(c, pos + dir * 2.0, pos + dir * 4.5, Color(0.9, 0.25, 0.2), 3.0)
	Art.line(c, pos - dir * 3.5 - n * 1.8, pos - dir * 3.5 + n * 1.8, Color(0.45, 0.47, 0.44), 1.2)
