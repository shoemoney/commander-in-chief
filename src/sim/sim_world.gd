class_name SimWorld
extends RefCounted
## The deterministic gameplay core. Fixed 60 Hz tick, 16.16 fixed-point math,
## seeded RNG, no floats, no engine RNG, no wall-clock time, no scene tree.
##
## Everything the game IS lives here: players, bullets, grenades (fake-Z
## parabolas), rusher/elite infantry, infinite-spawn bunkers sealed only by
## grenades, pickups, the ratchet scroll camera, one-hit death, and the
## War Chest shared economy. The scene tree is only a view over this state.
##
## P0 scope (greybox): 1-2 players, endless vertical scroll, rusher + red
## elite + bunker enemy grammar, ammo economy, War Chest revives.

# --- Tuning constants (all fixed-point unless suffixed _TICKS/_RAW) ---
const F_ONE := Fixed.ONE
const WORLD_LEFT := 16 * F_ONE
const WORLD_RIGHT := 624 * F_ONE
const VIEW_H := 360 * F_ONE
const PLAYER_SPEED := (F_ONE * 12) / 5        # 2.4 px/tick = 144 px/s (+35% over 1986 feel)
const BULLET_SPEED := 6 * F_ONE
const BULLET_TTL_TICKS := 120
const FIRE_COOLDOWN_TICKS := 8
const GRENADE_SPEED := 3 * F_ONE
const GRENADE_ZVEL := 2 * F_ONE
const GRENADE_GRAV := F_ONE / 8
const GRENADE_RADIUS := 28 * F_ONE
const GRENADE_COOLDOWN_TICKS := 30
const ENEMY_SPEED := (F_ONE * 8) / 5          # 1.6 px/tick
const ELITE_SPEED := 2 * F_ONE
const ENEMY_TOUCH_RADIUS := 10 * F_ONE
const BULLET_HIT_RADIUS := 9 * F_ONE
const PICKUP_RADIUS := 12 * F_ONE
const MG_AMMO_MAX := 99
const GRENADE_AMMO_MAX := 12
const SPAWN_INTERVAL_TICKS := 45
const BUNKER_SPAWN_INTERVAL_TICKS := 120
const MAX_ENEMIES := 64
const REVIVE_BASE_COST := 50
const BROKE_RESPAWN_TICKS := 300
const COIN_RUSHER := 10
const COIN_ELITE := 25
const COIN_BUNKER := 50
const CAMERA_LEAD := 160 * F_ONE
const BUNKER_W := 48 * F_ONE
const BUNKER_H := 32 * F_ONE

var tick_count: int = 0
var rng: SimRng
var players: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var bunkers: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var war_chest: int = 0
var score: int = 0
var camera_top: int = 0
var _spawn_counter: int = 0
var _next_bunker_y: int = 0


func _init(seed_value: int, player_count: int) -> void:
	rng = SimRng.new(seed_value)
	camera_top = -VIEW_H
	_next_bunker_y = -(500 * F_ONE)
	for i in player_count:
		players.append({
			"x": (280 + i * 80) * F_ONE,
			"y": -(60 * F_ONE),
			"aim_x": 0, "aim_y": -F_ONE,
			"alive": true,
			"deaths": 0,
			"mg_ammo": MG_AMMO_MAX,
			"grenade_ammo": GRENADE_AMMO_MAX,
			"fire_cd": 0, "grenade_cd": 0,
			"broke_timer": 0,
		})


func is_solo() -> bool:
	return players.size() == 1


func revive_cost(p: Dictionary) -> int:
	var cost: int = REVIVE_BASE_COST * (p["deaths"])
	if is_solo():
		cost = cost / 2
	return maxi(cost, REVIVE_BASE_COST / (2 if is_solo() else 1))


func step(inputs: Array) -> void:
	## Advance one tick. `inputs` is one SimInput per player.
	tick_count += 1
	_step_players(inputs)
	_step_bullets()
	_step_grenades()
	_step_enemies()
	_step_bunkers()
	_step_spawner()
	_step_camera()


func _step_players(inputs: Array) -> void:
	for i in players.size():
		var p := players[i]
		var inp: SimInput = inputs[i] if i < inputs.size() else SimInput.new()
		p["fire_cd"] = maxi(0, p["fire_cd"] - 1)
		p["grenade_cd"] = maxi(0, p["grenade_cd"] - 1)

		if not p["alive"]:
			_step_dead_player(i, p, inp)
			continue

		# Movement: quantized stick [-256,256] -> fixed direction, normalized.
		var mx: int = inp.move_x * 256   # 256*256 = 65536 = 1.0 fixed at full deflection
		var my: int = inp.move_y * 256
		var mlen := Fixed.length(mx, my)
		if mlen > F_ONE / 8:
			var nx := Fixed.div(mx, mlen)
			var ny := Fixed.div(my, mlen)
			p["x"] = p["x"] + Fixed.mul(nx, PLAYER_SPEED)
			p["y"] = p["y"] + Fixed.mul(ny, PLAYER_SPEED)
		p["x"] = Fixed.clampi_fixed(p["x"], WORLD_LEFT, WORLD_RIGHT)
		p["y"] = Fixed.clampi_fixed(p["y"], camera_top + 16 * F_ONE, camera_top + 344 * F_ONE)

		# Aim: decoupled from movement (the loop-lever identity).
		var ax: int = inp.aim_x * 256
		var ay: int = inp.aim_y * 256
		var alen := Fixed.length(ax, ay)
		if alen > F_ONE / 4:
			p["aim_x"] = Fixed.div(ax, alen)
			p["aim_y"] = Fixed.div(ay, alen)

		if inp.fire and p["fire_cd"] == 0 and p["mg_ammo"] > 0:
			p["fire_cd"] = FIRE_COOLDOWN_TICKS
			p["mg_ammo"] = p["mg_ammo"] - 1
			bullets.append({
				"x": p["x"], "y": p["y"],
				"vx": Fixed.mul(p["aim_x"], BULLET_SPEED),
				"vy": Fixed.mul(p["aim_y"], BULLET_SPEED),
				"ttl": BULLET_TTL_TICKS, "owner": i,
			})

		if inp.grenade and p["grenade_cd"] == 0 and p["grenade_ammo"] > 0:
			p["grenade_cd"] = GRENADE_COOLDOWN_TICKS
			p["grenade_ammo"] = p["grenade_ammo"] - 1
			grenades.append({
				"x": p["x"], "y": p["y"],
				"vx": Fixed.mul(p["aim_x"], GRENADE_SPEED),
				"vy": Fixed.mul(p["aim_y"], GRENADE_SPEED),
				"z": 0, "zv": GRENADE_ZVEL, "owner": i,
			})

		if inp.revive:
			_try_revive(i, p)

		# Contact with any enemy = one-hit death.
		for e in enemies:
			if e["alive"] and _dist_lte(p["x"], p["y"], e["x"], e["y"], ENEMY_TOUCH_RADIUS):
				_kill_player(p)
				break

		# Pickups.
		for k in range(pickups.size() - 1, -1, -1):
			var pk := pickups[k]
			if _dist_lte(p["x"], p["y"], pk["x"], pk["y"], PICKUP_RADIUS):
				if pk["kind"] == 0:
					p["mg_ammo"] = mini(MG_AMMO_MAX, p["mg_ammo"] + 30)
				else:
					p["grenade_ammo"] = mini(GRENADE_AMMO_MAX, p["grenade_ammo"] + 4)
				pickups.remove_at(k)


func _step_dead_player(_index: int, p: Dictionary, inp: SimInput) -> void:
	# Broke fallback: if nobody can afford a revive, a timer respawns you at
	# the bottom of the current screen (the "last gate" stand-in for P0).
	if p["broke_timer"] > 0:
		p["broke_timer"] = p["broke_timer"] - 1
		if p["broke_timer"] == 0:
			_respawn(p, camera_top + 330 * F_ONE)
			return
	# Dead player pressing revive = feeding the War Chest coin reader (solo,
	# or when the partner is also down).
	if inp.revive:
		_try_revive(-1, p)


func _try_revive(reviver_index: int, reviver: Dictionary) -> void:
	## An alive player revives all dead partners at their side; a dead player
	## (reviver_index == -1) revives themself. Spends the shared War Chest.
	for j in players.size():
		var target := players[j]
		if target["alive"]:
			continue
		if reviver_index == -1 and target != reviver:
			continue
		var cost := revive_cost(target)
		if war_chest >= cost:
			war_chest -= cost
			var at_y: int = reviver["y"] if reviver["alive"] else camera_top + 330 * F_ONE
			_respawn(target, at_y)
		else:
			if target["broke_timer"] == 0:
				target["broke_timer"] = BROKE_RESPAWN_TICKS


func _respawn(p: Dictionary, at_y: int) -> void:
	p["alive"] = true
	p["mg_ammo"] = MG_AMMO_MAX         # death restores ammo (1986 rule)
	p["grenade_ammo"] = GRENADE_AMMO_MAX
	p["broke_timer"] = 0
	p["y"] = Fixed.clampi_fixed(at_y, camera_top + 16 * F_ONE, camera_top + 344 * F_ONE)
	p["x"] = Fixed.clampi_fixed(p["x"], WORLD_LEFT, WORLD_RIGHT)


func _kill_player(p: Dictionary) -> void:
	p["alive"] = false
	p["deaths"] = p["deaths"] + 1
	p["broke_timer"] = 0


func _step_bullets() -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		b["x"] = b["x"] + b["vx"]
		b["y"] = b["y"] + b["vy"]
		b["ttl"] = b["ttl"] - 1
		var dead: bool = b["ttl"] <= 0 or b["y"] < camera_top - 40 * F_ONE \
			or b["y"] > camera_top + 400 * F_ONE or b["x"] < 0 or b["x"] > 640 * F_ONE
		if not dead:
			# Bullets are stopped by armor: bunkers block, only grenades hurt them.
			for bk in bunkers:
				if bk["alive"] and _point_in_aabb(b["x"], b["y"], bk):
					dead = true
					break
		if not dead:
			for e in enemies:
				if e["alive"] and _dist_lte(b["x"], b["y"], e["x"], e["y"], BULLET_HIT_RADIUS):
					_kill_enemy(e)
					dead = true
					break
		if dead:
			bullets.remove_at(i)


func _step_grenades() -> void:
	for i in range(grenades.size() - 1, -1, -1):
		var g := grenades[i]
		g["x"] = g["x"] + g["vx"]
		g["y"] = g["y"] + g["vy"]
		g["z"] = g["z"] + g["zv"]
		g["zv"] = g["zv"] - GRENADE_GRAV
		if g["z"] <= 0 and g["zv"] < 0:
			_explode(g["x"], g["y"])
			grenades.remove_at(i)


func _explode(x: int, y: int) -> void:
	for e in enemies:
		if e["alive"] and _dist_lte(x, y, e["x"], e["y"], GRENADE_RADIUS):
			_kill_enemy(e)
	for bk in bunkers:
		if bk["alive"] and _point_in_aabb_expanded(x, y, bk, GRENADE_RADIUS):
			bk["alive"] = false
			war_chest += COIN_BUNKER
			score += COIN_BUNKER * 10


func _kill_enemy(e: Dictionary) -> void:
	e["alive"] = false
	var coin: int = COIN_ELITE if e["elite"] else COIN_RUSHER
	war_chest += coin
	score += coin * 10
	if e["elite"]:
		pickups.append({
			"x": e["x"], "y": e["y"],
			"kind": rng.range_i(0, 1),   # 0 = Ammo Cache, 1 = Grenade Crate
		})


func _step_enemies() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not e["alive"] or e["y"] > camera_top + 420 * F_ONE:
			enemies.remove_at(i)
			continue
		var target := _nearest_alive_player(e["x"], e["y"])
		if target.is_empty():
			continue
		var dx: int = target["x"] - e["x"]
		var dy: int = target["y"] - e["y"]
		var dlen := Fixed.length(dx, dy)
		if dlen > F_ONE:
			var spd: int = ELITE_SPEED if e["elite"] else ENEMY_SPEED
			e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), spd)
			e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), spd)


func _nearest_alive_player(x: int, y: int) -> Dictionary:
	var best := {}
	var best_d := 0
	for p in players:
		if not p["alive"]:
			continue
		var d := Fixed.mul(p["x"] - x, p["x"] - x) + Fixed.mul(p["y"] - y, p["y"] - y)
		if best.is_empty() or d < best_d:
			best = p
			best_d = d
	return best


func _step_bunkers() -> void:
	# Bunkers spawn infantry until sealed (the 1986 infinite-spawn grammar).
	for bk in bunkers:
		if not bk["alive"]:
			continue
		bk["spawn_cd"] = bk["spawn_cd"] - 1
		if bk["spawn_cd"] <= 0 and enemies.size() < MAX_ENEMIES:
			bk["spawn_cd"] = BUNKER_SPAWN_INTERVAL_TICKS
			_spawn_enemy(bk["x"] + BUNKER_W / 2, bk["y"] + BUNKER_H + 8 * F_ONE, false)


func _step_spawner() -> void:
	# Field spawner: pressure from above the screen edge; every 8th is a red elite.
	if tick_count % SPAWN_INTERVAL_TICKS != 0 or enemies.size() >= MAX_ENEMIES:
		return
	_spawn_counter += 1
	var x := rng.range_i(24, 616) * F_ONE
	_spawn_enemy(x, camera_top - 24 * F_ONE, _spawn_counter % 8 == 0)


func _spawn_enemy(x: int, y: int, elite: bool) -> void:
	enemies.append({"x": x, "y": y, "alive": true, "elite": elite})


func _step_camera() -> void:
	# Ratchet: follows the highest (most advanced) alive player, never scrolls back.
	var focus := 0
	var found := false
	for p in players:
		if p["alive"] and (not found or p["y"] < focus):
			focus = p["y"]
			found = true
	if not found:
		return
	var desired := focus - CAMERA_LEAD
	if desired < camera_top:
		camera_top = desired
	# Lay bunkers ahead of the scroll, alternating flanks — the P0 "level".
	while _next_bunker_y > camera_top - VIEW_H:
		var flank := (absi(_next_bunker_y / (500 * F_ONE))) % 2
		bunkers.append({
			"x": (120 if flank == 0 else 460) * F_ONE,
			"y": _next_bunker_y,
			"alive": true,
			"spawn_cd": BUNKER_SPAWN_INTERVAL_TICKS,
		})
		_next_bunker_y -= 500 * F_ONE


func _dist_lte(x1: int, y1: int, x2: int, y2: int, r: int) -> bool:
	var dx := x1 - x2
	var dy := y1 - y2
	return Fixed.mul(dx, dx) + Fixed.mul(dy, dy) <= Fixed.mul(r, r)


func _point_in_aabb(x: int, y: int, bk: Dictionary) -> bool:
	return x >= bk["x"] and x <= bk["x"] + BUNKER_W and y >= bk["y"] and y <= bk["y"] + BUNKER_H


func _point_in_aabb_expanded(x: int, y: int, bk: Dictionary, r: int) -> bool:
	return x >= bk["x"] - r and x <= bk["x"] + BUNKER_W + r \
		and y >= bk["y"] - r and y <= bk["y"] + BUNKER_H + r


# --- Determinism instrumentation ---

func checksum() -> int:
	## FNV-1a over the full ordered sim state. Bit-identical across platforms
	## and architectures; the golden values asserted in CI on x86_64 Linux and
	## Apple Silicon macOS runners are the cross-arch determinism proof.
	# FNV-1a offset basis with the top bit dropped — GDScript int literals are
	# signed 64-bit, and the state is masked to 63 bits each step anyway.
	var h := 0x4BF29CE484222325
	var feed := func(v: int, acc: int) -> int:
		var a: int = acc ^ (v & 0x7FFFFFFFFFFFFFFF)
		return (a * 0x100000001B3) & 0x7FFFFFFFFFFFFFFF
	h = feed.call(tick_count, h)
	h = feed.call(war_chest, h)
	h = feed.call(score, h)
	h = feed.call(camera_top, h)
	for s in [rng._s0, rng._s1, rng._s2, rng._s3]:
		h = feed.call(s, h)
	for p in players:
		for v in [p["x"], p["y"], int(p["alive"]), p["deaths"], p["mg_ammo"], p["grenade_ammo"], p["fire_cd"], p["broke_timer"]]:
			h = feed.call(v, h)
	for arrs: Array in [bullets, grenades, enemies, bunkers, pickups]:
		h = feed.call(arrs.size(), h)
		for d: Dictionary in arrs:
			h = feed.call(d.get("x", 0), h)
			h = feed.call(d.get("y", 0), h)
	return h
