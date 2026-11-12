class_name PlayerPolish
extends RefCounted
## VIEW-ONLY hero presence: directional muzzle flash + brief light pool, ejected brass,
## footstep / roll dust, a crisp reticle overlay, P1/P2 identity pips and a readable
## hurt / downed read. Nothing here touches the sim; it only OBSERVES sim.players once per
## tick (idempotent per tick, so a hitstop frame cannot double-emit) and draws through the
## CanvasItem main.gd hands it. Randomness is a hash of tick + slot, never the sim RNG,
## so captures stay byte-reproducible.
##
## Geometry helpers are static and pure so tests measure exactly what is drawn.

const FLASH_TICKS := 6
const FLASH_LEN := 34.0          # px of the cone at age 0
const MUZZLE_OFF := 12.0         # px from body centre to the muzzle
const CASING_MAX := 48
const CASING_LIFE := 70
const DUST_MAX := 40
const DUST_LIFE := 22
const STEP_EVERY := 7            # ticks between footstep puffs while moving
const HURT_TICKS := 14
const FIRE_CD := 8               # mirrors SimWorld.FIRE_COOLDOWN_TICKS (a view copy, asserted in tests)

const KEYLINE_OFFSETS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

const CASING_BRASS := Color(0.95, 0.78, 0.32)
const CASING_HI := Color(1.0, 0.95, 0.7)
const CASING_DARK := Color(0.12, 0.09, 0.04)

var flash_age: Array[int] = []        # per slot, -1 none
var flash_dir: Array[Vector2] = []
var hurt_age: Array[int] = []
var casings: Array[Dictionary] = []   # {p: Vector2 world px, v: Vector2, z: float, vz: float, rot: float, age: int, rest: bool}
var dust: Array[Dictionary] = []      # {p: Vector2, v: Vector2, age: int, r: float, a: float}

var _last_tick := -1
var _prev_ammo: Array[int] = []
var _prev_cd: Array[int] = []
var _prev_pos: Array[Vector2] = []
var _prev_roll: Array[bool] = []
var _prev_iframes: Array[int] = []
var _prev_alive: Array[bool] = []
var _step_clock: Array[int] = []


func reset() -> void:
	flash_age.clear()
	flash_dir.clear()
	hurt_age.clear()
	casings.clear()
	dust.clear()
	_prev_ammo.clear()
	_prev_cd.clear()
	_prev_pos.clear()
	_prev_roll.clear()
	_prev_iframes.clear()
	_prev_alive.clear()
	_step_clock.clear()
	_last_tick = -1


static func hash01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 1023) / 1023.0


## Feed once per frame from the draw; acts only when the tick advanced.
## `motion` is main._motion (0 = reduce motion); `water` is a per-slot bool Array.
func observe(players: Array, tick: int, motion: float, water: Array = []) -> void:
	if tick < _last_tick:
		reset()
	if tick == _last_tick:
		return
	_last_tick = tick
	while flash_age.size() < players.size():
		flash_age.append(-1)
		flash_dir.append(Vector2.RIGHT)
		hurt_age.append(-1)
		_prev_ammo.append(-1)
		_prev_cd.append(0)
		_prev_pos.append(Vector2.INF)
		_prev_roll.append(false)
		_prev_iframes.append(0)
		_prev_alive.append(true)
		_step_clock.append(0)
	for i in players.size():
		var p: Dictionary = players[i]
		var pos := Vector2(float(p["x"]), float(p["y"])) / float(Fixed.ONE)
		var alive: bool = p["alive"]
		var aim := Vector2(p["aim_x"], p["aim_y"])
		var on_foot: bool = p["in_tank"] < 0
		var wet: bool = i < water.size() and water[i]
		# age running effects
		if flash_age[i] >= 0:
			flash_age[i] += 1
			if flash_age[i] > FLASH_TICKS:
				flash_age[i] = -1
		if hurt_age[i] >= 0:
			hurt_age[i] += 1
			if hurt_age[i] > HURT_TICKS:
				hurt_age[i] = -1
		# shot: ammo fell and the cooldown was just re-armed
		var shot: bool = alive and on_foot and _prev_ammo[i] >= 0 \
			and p["mg_ammo"] < _prev_ammo[i] and p["fire_cd"] > _prev_cd[i] \
			and aim.length_squared() > 0.0001
		if shot:
			flash_age[i] = 0
			flash_dir[i] = aim.normalized()
			_eject_casing(i, pos, flash_dir[i], tick, motion)
		# hurt: fresh i-frames, or the body just dropped
		if (alive and p["hurt_iframes"] > _prev_iframes[i]) or (_prev_alive[i] and not alive):
			hurt_age[i] = 0
		# dust: footsteps, roll start / end
		var moved := 0.0
		if _prev_pos[i] != Vector2.INF:
			moved = pos.distance_to(_prev_pos[i])
		var rolling: bool = p["roll_ticks"] > 0
		if alive and on_foot and not wet and motion >= 0.5:
			if rolling and not _prev_roll[i]:
				_puff_burst(i, pos, -_move_dir(p, pos, _prev_pos[i]), 4, tick)
			elif _prev_roll[i] and not rolling:
				_puff_burst(i, pos, Vector2.ZERO, 5, tick)
			elif moved > 0.35 and not rolling:
				_step_clock[i] += 1
				if _step_clock[i] >= STEP_EVERY:
					_step_clock[i] = 0
					var back := -(pos - _prev_pos[i]).normalized()
					_add_puff(pos + Vector2(0, 5) + back * 3.0, back * 0.25, tick * 7 + i, 2.6)
			else:
				_step_clock[i] = 0
			if rolling and moved > 0.2 and tick % 3 == 0:
				_add_puff(pos + Vector2(0, 5), -(pos - _prev_pos[i]).normalized() * 0.3, tick + i * 5, 3.2)
		_prev_ammo[i] = p["mg_ammo"]
		_prev_cd[i] = p["fire_cd"]
		_prev_pos[i] = pos
		_prev_roll[i] = rolling
		_prev_iframes[i] = p["hurt_iframes"]
		_prev_alive[i] = alive
	_step_particles(motion)


static func _move_dir(p: Dictionary, pos: Vector2, prev: Vector2) -> Vector2:
	var d := Vector2(p["roll_dx"], p["roll_dy"])
	if d.length_squared() > 0.0001:
		return d.normalized()
	if prev != Vector2.INF and pos != prev:
		return (pos - prev).normalized()
	return Vector2.DOWN


func _eject_casing(slot: int, pos: Vector2, dir: Vector2, tick: int, motion: float) -> void:
	if casings.size() >= CASING_MAX:
		casings.remove_at(0)
	var perp := Vector2(-dir.y, dir.x)    # ejects out the right side of the gun
	var spd := 1.5 + hash01(tick, slot + 3) * 1.1
	var c := {"p": pos + dir * 5.0 + perp * 2.0 + Vector2(0, 2), "v": perp * spd - dir * 0.25,
		"z": 6.0, "vz": 1.6 + hash01(tick, slot + 9) * 0.8, "rot": hash01(tick, slot + 1) * TAU,
		"age": 0, "rest": false}
	if motion < 0.5:
		# reduce motion: brass simply lands beside the gun, no flight
		c["p"] += c["v"] * 5.0
		c["z"] = 0.0
		c["rest"] = true
		c["v"] = Vector2.ZERO
	casings.append(c)


func _add_puff(p: Vector2, v: Vector2, seed_v: int, r: float) -> void:
	if dust.size() >= DUST_MAX:
		dust.remove_at(0)
	dust.append({"p": p + Vector2(hash01(seed_v, 1) - 0.5, hash01(seed_v, 2) - 0.5) * 3.0,
		"v": v + Vector2(hash01(seed_v, 3) - 0.5, -0.15 - hash01(seed_v, 4) * 0.15) * 0.35,
		"age": 0, "r": r, "a": 0.85})


func _puff_burst(slot: int, pos: Vector2, back: Vector2, n: int, tick: int) -> void:
	for k in n:
		var ang := (float(k) / float(n)) * TAU + hash01(tick, k + slot) * 0.8
		var v := Vector2.from_angle(ang) * 0.5 + back * 0.35
		_add_puff(pos + Vector2(0, 5) + Vector2.from_angle(ang) * 3.0, v, tick * 13 + k + slot * 101, 3.6)


func _step_particles(motion: float) -> void:
	var i := 0
	while i < casings.size():
		var c: Dictionary = casings[i]
		c["age"] += 1
		if not c["rest"]:
			c["p"] += c["v"]
			c["v"] *= 0.92
			c["z"] += c["vz"]
			c["vz"] -= 0.34
			c["rot"] += 0.5
			if c["z"] <= 0.0:
				c["z"] = 0.0
				if c["vz"] < -0.9:           # one small bounce, then it rests
					c["vz"] = -c["vz"] * 0.35
				else:
					c["rest"] = true
		if c["age"] >= CASING_LIFE:
			casings[i] = casings[casings.size() - 1]
			casings.remove_at(casings.size() - 1)
		else:
			i += 1
	i = 0
	while i < dust.size():
		var d: Dictionary = dust[i]
		d["age"] += 1
		d["p"] += d["v"]
		d["v"] *= 0.9
		if d["age"] >= DUST_LIFE:
			dust[i] = dust[dust.size() - 1]
			dust.remove_at(dust.size() - 1)
		else:
			i += 1


# ---------------------------------------------------------------- pure geometry

## Muzzle-flash polygon layers for a shot age, in muzzle-local space with +x = aim.
## Each: {pts: PackedVector2Array, col: Color}. Empty when no flash. `strength` is the
## accessibility flash scale (0..1): below ~0.5 the flash is a calm, short, dim glow.
static func flash_layers(age: int, strength: float) -> Array:
	var out: Array = []
	if age < 0 or age > FLASH_TICKS or strength <= 0.0:
		return out
	var t := float(age) / float(FLASH_TICKS)
	var fade := 1.0 - t
	var calm := strength < 0.5
	var len := FLASH_LEN * (1.0 - 0.45 * t) * (0.7 if calm else 1.0)
	var wid := 7.0 * (1.0 - 0.3 * t)
	var a := clampf(fade * 1.15, 0.0, 1.0) * clampf(strength, 0.0, 1.0)
	# ONE punchy spike (the engine's round crack-pop sits at its base): amber body, hot white core
	out.append({"pts": PackedVector2Array([Vector2(-1, -wid * 0.55), Vector2(len * 0.42, -wid * 0.3),
		Vector2(len * 0.8, 0), Vector2(len * 0.42, wid * 0.3), Vector2(-1, wid * 0.55)]),
		"col": Color(1.0, 0.86, 0.38, 0.92 * a)})
	out.append({"pts": PackedVector2Array([Vector2(-1, -wid * 0.22), Vector2(len * 0.4, 0),
		Vector2(-1, wid * 0.22)]), "col": Color(1.0, 1.0, 0.9, a)})
	# cross-spikes only on the first two ticks (the crack of the shot), never in calm mode
	if age <= 1 and not calm:
		var sp := len * 0.38
		out.append({"pts": PackedVector2Array([Vector2(2, -sp), Vector2(4, 0), Vector2(2, sp), Vector2(0.5, 0)]),
			"col": Color(1.0, 0.97, 0.8, 0.85 * a)})
	return out


## Brief warm light pool on the ground around the muzzle: {r, col}. Empty past its life.
static func light_pool(age: int, strength: float) -> Dictionary:
	if age < 0 or age > FLASH_TICKS or strength <= 0.0:
		return {}
	var t := float(age) / float(FLASH_TICKS)
	return {"r": 36.0 - 10.0 * t, "col": Color(1.0, 0.72, 0.3, 0.42 * (1.0 - t) * clampf(strength, 0.0, 1.0))}


## Reticle overlay: crisp corner ticks + centre pip, each as {a: Vector2, b: Vector2, w: float,
## col: Color} line segments around the origin; dark keylines come first.
static func reticle_segments(col: Color, ident: Color, grow: float) -> Array:
	var out: Array = []
	var inner := 7.0 + grow
	var outer := 11.0 + grow
	var dark := Color(0.0, 0.0, 0.0, 0.85)
	var dirs := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	for pass_i in 2:
		for d: Vector2 in dirs:
			out.append({"a": d * inner, "b": d * outer, "w": 3.0 if pass_i == 0 else 1.0,
				"col": dark if pass_i == 0 else Color(col.r, col.g, col.b, 1.0)})
	# centre pip: dark 3x3 under a bright 1x1 in the identity colour
	out.append({"a": Vector2(-1, 0), "b": Vector2(1, 0), "w": 3.0, "col": dark})
	out.append({"a": Vector2(-0.5, 0), "b": Vector2(0.5, 0), "w": 1.0, "col": Color(ident.r, ident.g, ident.b, 1.0)})
	return out


## Identity pips floating above the head in co-op: P1 one diamond, P2 two. {c, r, col}.
## Always-on identity marker above the head: a keylined down-chevron (solo) with 1 / 2 pip
## bars in co-op. Returned as draw_segments() lines around the origin (dark keyline first).
static func marker_segments(ident: Color, coop: bool, slot: int) -> Array:
	var out: Array = []
	var col := Color(ident.r, ident.g, ident.b, 1.0)
	var dark := Color(0, 0, 0, 0.9)
	for pass_i in 2:
		var w := 3.0 if pass_i == 0 else 1.0
		var c := dark if pass_i == 0 else col
		out.append({"a": Vector2(-3, -2), "b": Vector2(0, 1), "w": w, "col": c})
		out.append({"a": Vector2(0, 1), "b": Vector2(3, -2), "w": w, "col": c})
		if coop:
			for k in slot + 1:
				var y := -5.0 - float(k) * 3.0
				out.append({"a": Vector2(-2, y), "b": Vector2(2, y), "w": w, "col": c})
	return out


static func ident_pips(slot: int, ident: Color) -> Array:
	var out: Array = []
	var n := slot + 1
	for k in n:
		var cx := (float(k) - float(n - 1) * 0.5) * 5.0
		out.append({"c": Vector2(cx, 0), "r": 2.0, "col": Color(ident.r, ident.g, ident.b, 0.95)})
	return out


## Hurt read: expanding red ring + body flash. Returns {r, ring: Color, body: Color}; {} when idle.
static func hurt_look(age: int, strength: float) -> Dictionary:
	if age < 0 or age > HURT_TICKS or strength <= 0.0:
		return {}
	var t := float(age) / float(HURT_TICKS)
	var s := clampf(strength, 0.0, 1.0)
	return {"r": 8.0 + 14.0 * t, "ring": Color(1.0, 0.15, 0.1, 0.9 * (1.0 - t) * s),
		"body": Color(1.0, 0.1, 0.05, 0.55 * (1.0 - t) * (1.0 if t < 0.5 else 0.5) * s)}


## Downed marker: bold ident-coloured cross over a dark plate. {segs: [{a,b,w,col}], ring_r, ring: Color}.
static func downed_marker(ident: Color, phase: float, calm: bool) -> Dictionary:
	var pulse := 1.0 if calm else 0.75 + 0.25 * sin(phase * TAU)
	var segs: Array = []
	for pass_i in 2:
		var w := 4.0 if pass_i == 0 else 2.0
		var col := Color(0, 0, 0, 0.8) if pass_i == 0 else Color(ident.r, ident.g, ident.b, pulse)
		segs.append({"a": Vector2(-4, -4), "b": Vector2(4, 4), "w": w, "col": col})
		segs.append({"a": Vector2(-4, 4), "b": Vector2(4, -4), "w": w, "col": col})
	return {"segs": segs, "ring_r": 13.0 + (0.0 if calm else 1.5 * pulse), "ring": Color(ident.r, ident.g, ident.b, 0.55 * pulse)}


# ---------------------------------------------------------------- drawing

static func _scr(world: Vector2, cam_top_px: float) -> Vector2:
	return Vector2(roundf(world.x), roundf(world.y - cam_top_px))


## Ground layer (under the soldiers): dust puffs, resting/flying brass, muzzle light pools.
func draw_ground(ci: CanvasItem, cam_top_px: float, softspot: Texture2D, players: Array,
		strength: float) -> void:
	for d in dust:
		var t := float(d["age"]) / float(DUST_LIFE)
		var r: float = d["r"] * (1.0 + t * 1.6)
		var s := _scr(d["p"], cam_top_px)
		ci.draw_texture_rect(softspot, Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(0.82, 0.74, 0.58, d["a"] * (1.0 - t) * (1.0 - t * 0.4)))
	for c in casings:
		var life_left := 1.0 - maxf(0.0, float(c["age"] - (CASING_LIFE - 20))) / 20.0
		var s := _scr(c["p"], cam_top_px) - Vector2(0, c["z"])
		var sh := _scr(c["p"], cam_top_px)
		if c["z"] > 0.5:
			ci.draw_rect(Rect2(sh + Vector2(-1, 0), Vector2(2, 1)), Color(0, 0, 0, 0.3 * life_left))
		ci.draw_set_transform(s, c["rot"], Vector2.ONE)
		ci.draw_rect(Rect2(-2.5, -1.5, 5, 3), Color(CASING_DARK.r, CASING_DARK.g, CASING_DARK.b, 0.75 * life_left))
		ci.draw_rect(Rect2(-2.0, -1.0, 4, 2), Color(CASING_BRASS.r, CASING_BRASS.g, CASING_BRASS.b, life_left))
		ci.draw_rect(Rect2(-2.0, -1.0, 4, 1), Color(CASING_HI.r, CASING_HI.g, CASING_HI.b, 0.85 * life_left))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in mini(flash_age.size(), players.size()):
		var lp := light_pool(flash_age[i], strength)
		if lp.is_empty():
			continue
		var pp: Dictionary = players[i]
		var c := Vector2(float(pp["x"]), float(pp["y"])) / float(Fixed.ONE) + flash_dir[i] * 9.0
		var s := _scr(c, cam_top_px)
		var r: float = lp["r"]
		ci.draw_texture_rect(softspot, Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), false, lp["col"])


## Muzzle flash cone for one soldier, drawn over the sprite. `pos` is the body's screen pos.
func draw_flash(ci: CanvasItem, slot: int, pos: Vector2, strength: float) -> void:
	if slot >= flash_age.size():
		return
	var layers := flash_layers(flash_age[slot], strength)
	if layers.is_empty():
		return
	var dir := flash_dir[slot]
	ci.draw_set_transform((pos + dir * MUZZLE_OFF).round(), dir.angle(), Vector2.ONE)
	for l in layers:
		ci.draw_colored_polygon(l["pts"], l["col"])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_segments(ci: CanvasItem, origin: Vector2, segs: Array) -> void:
	for s in segs:
		ci.draw_line(origin + s["a"], origin + s["b"], s["col"], s["w"])
