class_name ExplosionsPolish
extends RefCounted
## Layered explosions and impact VFX. VIEW ONLY: nothing here touches src/sim; the sim's
## `explosion` fx entries and its `kill` / `bullet_dirt` events are the only inputs.
##
## A blast is a white-hot flash, an expanding fireball whose colour cools
## white -> yellow -> orange -> dark red, a ground shockwave ring, thrown dark chunks, hot
## sparks, and charcoal smoke that rolls up and lingers ~2.5 s. Bullet strikes get a spark
## star plus a dust puff; an enemy death gets a dust ball.
##
## Everything is a pure function of (entry, current sim tick): no per-frame allocation beyond
## the draw calls, no RNG (hash-seeded from the world position so a replay looks the same),
## and ages count SIM ticks so hit-stop and slow-motion freeze/stretch the blast with the world.
## Reduce-motion (`motion < 0.5`) is static: the fireball and smoke fade in place, with no
## expansion, sparks, flung chunks, shockwave or impact puffs.

const MAX_BLASTS := 14
const MAX_PUFFS := 36
const FIRE_FRAMES := 24.0
const FLASH_FRAMES := 5.0
const SHOCK_FRAMES := 18.0
const CHUNK_FRAMES := 44.0
const SMOKE_FRAMES := 150
const SMOKE_FRAMES_STATIC := 60
const SMOKE_PUFFS := 7
const SPARKS := 10
const CHUNKS := 6
const HIT_FRAMES := 14
const DEATH_FRAMES := 26
const FIRE_R := 26.0

static var _cards: Dictionary = {}

var blasts: Array[Dictionary] = []
var puffs: Array[Dictionary] = []
var _ingested_tick := -999999


static func hash01(seed_v: int, k: int) -> float:
	var h: int = (seed_v * 73856093) ^ (k * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Fireball temperature ramp: 0 = white-hot, 1 = spent dark red.
static func fire_color(u: float) -> Color:
	u = clampf(u, 0.0, 1.0)
	var stops: Array[Color] = [Color(1.0, 1.0, 0.92), Color(1.0, 0.86, 0.3),
		Color(1.0, 0.5, 0.1), Color(0.46, 0.08, 0.04)]
	var f := u * 3.0
	var i := mini(int(f), 2)
	return stops[i].lerp(stops[i + 1], f - float(i))


## The two lumpy volumetric cards from tools/gen_fx_cards.py (fx_fireball, fx_billow).
static func card(name: String) -> Texture2D:
	if not _cards.has(name):
		_cards[name] = load("res://assets/art/fx/%s.png" % name)
	return _cards[name]


static func ease_out(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)


static func smoke_life(motion: float) -> int:
	return SMOKE_FRAMES if motion >= 0.5 else SMOKE_FRAMES_STATIC


func add_blast(x: int, y: int, tick: int, blast_scale := 1.0) -> void:
	if blasts.size() >= MAX_BLASTS:
		blasts.remove_at(0)
	blasts.append({"x": x, "y": y, "born": tick, "seed": absi(x / 7 + y / 13) + blasts.size(), "scale": blast_scale})


func add_puff(kind: String, x: int, y: int, tick: int) -> void:
	if puffs.size() >= MAX_PUFFS:
		puffs.remove_at(0)
	puffs.append({"kind": kind, "x": x, "y": y, "born": tick, "seed": absi(x / 5 + y / 11) + puffs.size()})


## Called once per draw from main._classify_fx(). Registers each new `explosion` fx entry (flagged
## so it is only taken once) and, once per sim tick, the strike / death events.
func ingest(fx: Array, events: Array, tick: int, wet_fn: Callable) -> void:
	for e in fx:
		if e["kind"] == "explosion" and not e.has("pf"):
			e["pf"] = true
			add_blast(e["x"], e["y"], tick)
	if tick == _ingested_tick:
		return
	_ingested_tick = tick
	var hits := 0
	var deaths := 0
	for ev in events:
		var t: String = ev["t"]
		if t == "bullet_dirt" and hits < 3:
			if not (wet_fn.is_valid() and wet_fn.call(ev["x"], ev["y"])):
				hits += 1
				add_puff("hit", ev["x"], ev["y"], tick)
		elif t == "kill" and deaths < 5 and ev.get("kind", "") != "pilot":
			if not (wet_fn.is_valid() and wet_fn.call(ev["x"], ev["y"])):
				deaths += 1
				add_puff("death", ev["x"], ev["y"], tick)
	prune(tick, 1.0)


func prune(tick: int, motion: float) -> void:
	var life := smoke_life(motion) + 12
	var i := blasts.size() - 1
	while i >= 0:
		var age: int = tick - int(blasts[i]["born"])
		if age < 0 or age > life:
			blasts.remove_at(i)
		i -= 1
	i = puffs.size() - 1
	while i >= 0:
		var age2: int = tick - int(puffs[i]["born"])
		if age2 < 0 or age2 > DEATH_FRAMES:
			puffs.remove_at(i)
		i -= 1


static func _on_screen(p: Vector2) -> bool:
	return p.y > -90.0 and p.y < 450.0 and p.x > -90.0 and p.x < 730.0


## Drawn UNDER the actors: shockwave, fireball body, flung chunks, rolling smoke, impact dust.
func draw_under(ci: CanvasItem, to_screen: Callable, tick: int, motion: float) -> void:
	var live := motion >= 0.5
	var soft := Art.tex("fx_softspot")
	var smoke_tex := card("fx_billow")
	var fire_tex := card("fx_fireball")
	var life := smoke_life(motion)
	for b in blasts:
		var age := float(tick - int(b["born"]))
		if age < 0.0 or age > float(life):
			continue
		var o: Vector2 = to_screen.call(b["x"], b["y"])
		if not _on_screen(o):
			continue
		var sd: int = b["seed"]
		var sc: float = b["scale"] * (0.9 + 0.25 * hash01(sd, 0))
		if live and age < SHOCK_FRAMES:
			var sp := age / SHOCK_FRAMES
			var sr := (5.0 + ease_out(sp) * 42.0) * sc
			ci.draw_texture_rect(Art.tex("fx_ring"), Rect2(o - Vector2.ONE * sr, Vector2.ONE * sr * 2.0),
				false, Color(0.95, 0.85, 0.7, 0.4 * (1.0 - sp)))
		# Smoke first (it is the cool, dark layer the fire burns in front of).
		for i in SMOKE_PUFFS:
			var delay := 3.0 + float(i) * 2.0
			var a := age - delay
			if a < 0.0:
				continue
			var p := a / float(life)
			var dir := Vector2.from_angle(hash01(sd, 10 + i) * TAU)
			var spread := (6.0 + 16.0 * hash01(sd, 20 + i)) * sc
			var drift := Vector2.ZERO
			var grow := 0.8
			if live:
				drift = Vector2(0.05 * (hash01(sd, 30) - 0.3), -0.1) * a
				grow = 0.5 + 0.7 * ease_out(a / 40.0)
				spread *= ease_out(a / 30.0)
			var pos := o + dir * spread + drift
			var rad := (10.0 + 9.0 * hash01(sd, 40 + i)) * sc * grow
			var col := Color(0.14, 0.12, 0.11).lerp(Color(0.5, 0.47, 0.44), smoothstep(0.0, 0.5, p))
			col = col.lerp(Color(0.5, 0.2, 0.08), clampf(1.0 - a / 12.0, 0.0, 1.0) * 0.6)
			col.a = 0.5 * smoothstep(0.0, 0.08, p) * (1.0 - smoothstep(0.55, 1.0, p))
			ci.draw_set_transform(pos, hash01(sd, 50 + i) * TAU + (a * 0.012 if live else 0.0), Vector2.ONE)
			ci.draw_texture_rect(smoke_tex, Rect2(-rad, -rad, rad * 2.0, rad * 2.0), false, col)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Fireball: five overlapping lobes, each cooling along the colour ramp.
		if age < FIRE_FRAMES:
			var u := age / FIRE_FRAMES
			var growth := ease_out(age / 10.0) if live else 0.7
			for k in 5:
				var ang := hash01(sd, 60 + k) * TAU
				var dist := FIRE_R * sc * 0.38 * hash01(sd, 70 + k) * growth
				var lr := FIRE_R * sc * (0.62 + 0.4 * hash01(sd, 80 + k)) * (0.35 + 0.65 * growth)
				var lc := fire_color(u * 1.15 + (dist / (FIRE_R * sc)) * 0.4)
				lc.a = 0.95 * pow(1.0 - u, 0.6)
				var lp := o + Vector2.from_angle(ang) * dist
				ci.draw_set_transform(lp, ang * 3.0, Vector2.ONE)
				ci.draw_texture_rect(fire_tex, Rect2(-lr, -lr, lr * 2.0, lr * 2.0), false, lc)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var cc := fire_color(u * 0.7)
			cc.a = 0.9 * (1.0 - u)
			var cr := FIRE_R * sc * 0.45 * (0.5 + 0.5 * growth)
			ci.draw_texture_rect(soft, Rect2(o - Vector2.ONE * cr, Vector2.ONE * cr * 2.0), false, cc)
		# Thrown chunks: ballistic arc, then they sit where they landed and fade.
		if live and age < CHUNK_FRAMES:
			for k in CHUNKS:
				var cd := Vector2.from_angle(hash01(sd, 90 + k) * TAU)
				var spd := (1.6 + 2.2 * hash01(sd, 100 + k)) * sc
				var vz := 1.4 + 1.8 * hash01(sd, 110 + k)
				var travel := spd * (1.0 - pow(0.9, minf(age, 24.0))) * 10.0
				var lift := maxf(0.0, vz * age - 0.06 * age * age)
				var cp := o + cd * travel + Vector2(0.0, -lift)
				var csz := 1.3 + 1.6 * hash01(sd, 120 + k)
				var ca := 1.0 - smoothstep(0.65, 1.0, age / CHUNK_FRAMES)
				ci.draw_set_transform(cp, hash01(sd, 130 + k) * TAU + age * 0.35, Vector2.ONE)
				ci.draw_rect(Rect2(-csz, -csz * 0.55, csz * 2.0, csz * 1.1),
					Color(0.24, 0.18, 0.13, ca))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not live:
		return
	for pf in puffs:
		var pa := float(tick - int(pf["born"]))
		if pa < 0.0:
			continue
		var pp: Vector2 = to_screen.call(pf["x"], pf["y"])
		if not _on_screen(pp):
			continue
		var psd: int = pf["seed"]
		if pf["kind"] == "hit":
			if pa > HIT_FRAMES:
				continue
			var hp := pa / float(HIT_FRAMES)
			var hr := 2.5 + ease_out(hp) * 5.0
			ci.draw_texture_rect(soft, Rect2(pp - Vector2.ONE * hr, Vector2.ONE * hr * 2.0), false,
				Color(0.72, 0.62, 0.45, 0.42 * (1.0 - hp)))
		elif pf["kind"] == "death":
			var dp := pa / float(DEATH_FRAMES)
			for k in 4:
				var dd := Vector2.from_angle(hash01(psd, k) * TAU) * ease_out(dp) * (5.0 + 6.0 * hash01(psd, 9 + k))
				var dr := 4.0 + ease_out(dp) * 7.0 * (0.7 + 0.5 * hash01(psd, 19 + k))
				var dc := Color(0.62, 0.55, 0.45).lerp(Color(0.4, 0.37, 0.33), dp)
				dc.a = 0.55 * smoothstep(0.0, 0.1, dp) * (1.0 - dp)
				ci.draw_texture_rect(soft, Rect2(pp + dd - Vector2.ONE * dr, Vector2.ONE * dr * 2.0), false, dc)


## Drawn on the additive glow layer: white-hot flash, the fireball's hot heart, sparks and
## the strike star. `flash` is the player's flash-intensity setting (0..1) and scales only the
## white photographic pop, never the fire itself.
func draw_glow(g: CanvasItem, to_screen: Callable, tick: int, motion: float, flash: float) -> void:
	var live := motion >= 0.5
	var soft := Art.tex("fx_softspot")
	for b in blasts:
		var age := float(tick - int(b["born"]))
		if age < 0.0 or age > FIRE_FRAMES:
			continue
		var o: Vector2 = to_screen.call(b["x"], b["y"])
		if not _on_screen(o):
			continue
		var sd: int = b["seed"]
		var sc: float = b["scale"] * (0.9 + 0.25 * hash01(sd, 0))
		var u := age / FIRE_FRAMES
		var br := FIRE_R * sc * 1.5 * (0.6 + 0.4 * ease_out(age / 8.0))
		var bc := Color(1.0, 0.55, 0.18, 0.3 * (1.0 - u) * (0.5 + 0.5 * flash))
		g.draw_texture_rect(soft, Rect2(o - Vector2.ONE * br, Vector2.ONE * br * 2.0), false, bc)
		if age < FLASH_FRAMES and flash > 0.0:
			var fp := age / FLASH_FRAMES
			var fr := (20.0 + fp * 20.0) * sc
			g.draw_texture_rect(soft, Rect2(o - Vector2.ONE * fr, Vector2.ONE * fr * 2.0), false,
				Color(1.0, 0.98, 0.88, 0.85 * (1.0 - fp) * flash))
		if live:
			for k in SPARKS:
				var life := 9.0 + 16.0 * hash01(sd, 140 + k)
				if age > life:
					continue
				var dir := Vector2.from_angle(hash01(sd, 150 + k) * TAU)
				var spd := (2.2 + 3.0 * hash01(sd, 160 + k)) * sc
				var p1 := _spark_pos(o, dir, spd, age)
				var p0 := _spark_pos(o, dir, spd, maxf(age - 2.0, 0.0))
				var sp := age / life
				var scol := fire_color(sp * 0.8)
				scol.a = 1.0 - sp
				g.draw_line(p0, p1, scol, 1.0)
				g.draw_rect(Rect2(p1 - Vector2(0.5, 0.5), Vector2.ONE), Color(1.0, 0.95, 0.75, scol.a))
	if not live:
		return
	for pf in puffs:
		if pf["kind"] != "hit":
			continue
		var pa := float(tick - int(pf["born"]))
		if pa < 0.0 or pa > 6.0:
			continue
		var pp: Vector2 = to_screen.call(pf["x"], pf["y"])
		if not _on_screen(pp):
			continue
		var hp := pa / 6.0
		var psd: int = pf["seed"]
		var base := hash01(psd, 0) * TAU
		for k in 4:
			var d := Vector2.from_angle(base + float(k) * TAU / 4.0 + (hash01(psd, 1 + k) - 0.5) * 0.7)
			var s0 := pp + d * (1.0 + hp * 3.0)
			var s1 := pp + d * (3.0 + hp * 6.0)
			g.draw_line(s0, s1, Color(1.0, 0.85 - hp * 0.3, 0.4, 1.0 - hp), 1.0)
		g.draw_texture_rect(soft, Rect2(pp - Vector2.ONE * 5.0, Vector2.ONE * 10.0), false,
			Color(1.0, 0.8, 0.45, 0.55 * (1.0 - hp) * maxf(flash, 0.3)))


static func _spark_pos(o: Vector2, dir: Vector2, spd: float, age: float) -> Vector2:
	var travel := spd * (1.0 - pow(0.9, minf(age, 20.0))) * 10.0
	return o + dir * travel + Vector2(0.0, 0.05 * age * age)
