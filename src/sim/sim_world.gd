class_name SimWorld
extends RefCounted
## The deterministic gameplay core. Fixed 60 Hz tick, 16.16 fixed-point math,
## seeded RNG, no floats, no engine RNG, no wall-clock time, no scene tree.
##
## Everything the game IS lives here: players (with dodge roll), bullets,
## grenades and tank shells (fake-Z parabolas), rusher/elite infantry,
## infinite-spawn bunkers sealed only by grenades, enterable tanks with fuel
## and bail windows, the Mortar Observer pacing whip, zone gates that become
## checkpoints, pickups, the ratchet scroll camera, one-hit death, and the
## War Chest shared economy. The scene tree is only a view over this state.
##
## P1 scope: P0 systems + dodge roll, tank vehicle (crush/shells/fuel/bail/
## kamikaze), Mortar Observer with tracked strikes, gates → checkpoints.

# --- Tuning constants (all fixed-point unless suffixed _TICKS/_RAW) ---
const F_ONE := Fixed.ONE
const WORLD_LEFT := 16 * F_ONE
const WORLD_RIGHT := 624 * F_ONE
const VIEW_H := 360 * F_ONE
const SCREEN_CX := 320 * F_ONE
const SCREEN_W_FP := 640 * F_ONE
const PLAYER_SPEED := (F_ONE * 12) / 5        # 2.4 px/tick = 144 px/s (+35% over 1986 feel)
const BULLET_SPEED := 6 * F_ONE
const BULLET_TTL_TICKS := 120
const FIRE_COOLDOWN_TICKS := 8
# Empty-clip bash: a point-blank melee counter when the MG runs dry. Reach is a
# touch wider than a rusher's kill radius so you can pre-empt one; the long
# cooldown keeps it a last resort, not a replacement weapon.
const BASH_RADIUS := 16 * F_ONE
const BASH_COOLDOWN_TICKS := 40
# Piercing Rounds power-up (1986 capsule grammar): a timed buff, rarely dropped
# by elites, that lets MG bullets punch clean through a kill to the next target.
const PIERCE_TICKS := 600
# Spread Shot power-up ("Trench Gun"): a timed buff that fires a 3-bullet fan per
# shot (one round of ammo, three pellets). ±12° fan via fixed-point rotation.
const SPREAD_TICKS := 480
const SPREAD_COS := 64102   # cos(12°) * F_ONE
const SPREAD_SIN := 13626   # sin(12°) * F_ONE
const GRENADE_SPEED := 3 * F_ONE
const GRENADE_ZVEL := 2 * F_ONE
const GRENADE_GRAV := F_ONE / 8
const GRENADE_RADIUS := 28 * F_ONE
const GRENADE_COOLDOWN_TICKS := 30
const ENEMY_SPEED := (F_ONE * 8) / 5          # 1.6 px/tick
# Supply courier: the roster's only enemy that FLEES. Runs for the top edge at
# just under player speed (so it's a real chase, catchable by cutting it off or
# shooting it down); killed before it escapes it drops a fat bounty.
const COURIER_SPEED := (PLAYER_SPEED * 9) / 10
const ELITE_SPEED := 2 * F_ONE
# Elites are ranged skirmishers: close to standoff range, telegraph a wind-up,
# then loose one aimed shot. Starting values (tune via playtest).
const ELITE_STANDOFF := 120 * F_ONE
const ELITE_FIRE_CD_TICKS := 150
const ELITE_WINDUP_TICKS := 24
# Grenadier (endless-only): mid-range zoner that lobs a telegraphed area strike.
const GRENADIER_STANDOFF := 150 * F_ONE
const GRENADIER_FIRE_CD_TICKS := 130
const GRENADIER_WINDUP_TICKS := 40
# Sniper (endless-only): long-range, paints a laser line then fires one fast shot.
const SNIPER_STANDOFF := 240 * F_ONE
const SNIPER_FIRE_CD_TICKS := 170
const SNIPER_WINDUP_TICKS := 55
const SNIPER_BULLET_SPEED := 6 * F_ONE
# Shield (endless-only): slow heavy; front-arc blocks bullets, flank/grenade kills.
const SHIELD_SPEED := F_ONE
# Sapper (endless-only): advances like a rusher but seeds armed mines behind it,
# authoring a hazard trail between you and the top edge. Reuses fire_cd as the
# mine-drop timer — no new hashed field.
const SAPPER_MINE_CD_TICKS := 40
const SAPPER_MAX_MINES := 40
# Ghillie (endless-only): a cloaked sniper dug into LAND. Sits 'submerged' (no
# threat arrow, bullet-immune) until you enter notice range, briefly reveals,
# then runs the STATIONARY sniper paint→fire cycle. Reuses submerged/
# surface_ticks/windup/aim_lx/aim_ly/fire_cd — no new hashed field.
const GHILLIE_NOTICE_RADIUS := 210 * F_ONE
const GHILLIE_REVEAL_TICKS := 26
const ENEMY_TOUCH_RADIUS := 10 * F_ONE
# Landmines: deterministic field hazards. Any grounded unit (player on foot, or
# an enemy) that steps within the trigger radius detonates them via _explode() —
# herd rushers onto them, or respect them yourself. Rolling clears them safely.
const MINE_TRIGGER_RADIUS := 9 * F_ONE
const MINE_SPACING := 340 * F_ONE
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
# Kill-streak: consecutive kills inside this window escalate a SCORE-ONLY bonus
# at the 5/10/20 tiers the view already telegraphs (matches the view's window).
const KILL_STREAK_WINDOW_TICKS := 90
# Post-checkpoint spawn lull: the field spawner holds fire this long after a gate
# opens so the "GATE SECURED" beat isn't stepped on by a fresh rusher.
const GATE_SPAWN_GRACE_TICKS := 90
const CAMERA_LEAD := 160 * F_ONE
const BUNKER_W := 48 * F_ONE
const BUNKER_H := 32 * F_ONE
# Dodge roll: 0.3 s i-frames, 1.2 s cooldown, 2× speed in the move direction.
# A press up to ROLL_BUFFER_TICKS early is queued and fires when the roll is ready.
const ROLL_TICKS := 18
const ROLL_CD_TICKS := 72
const ROLL_BUFFER_TICKS := 8
# Tank: 0.8× player speed, cannon draws from grenade ammo, ~20 s of fuel,
# guaranteed 3.0 s bail window once burning.
const TANK_SPEED := (PLAYER_SPEED * 4) / 5
const TANK_BOARD_RADIUS := 24 * F_ONE
const TANK_CRUSH_RADIUS := 18 * F_ONE
const TANK_FIRE_COOLDOWN_TICKS := 45
const TANK_FUEL_TICKS := 1200
const TANK_BAIL_TICKS := 180
const TANK_KAMIKAZE_PAD := 20 * F_ONE
const SHELL_SPEED := 5 * F_ONE
const SHELL_ZVEL := F_ONE
const BAIL_BOOST_TICKS := 90
const BAIL_IFRAME_TICKS := 20   # a forced dismount can't insta-die on landing
# Mortar Observer: spawns after an 8 s stall; strike every 1.5 s with a
# 0.75 s telegraph; despawns once the players push 150 px past his arrival.
const OBSERVER_STALL_TICKS := 480
const OBSERVER_STRIKE_CD_TICKS := 90
const STRIKE_TELEGRAPH_TICKS := 45
const OBSERVER_DESPAWN_ADVANCE := 150 * F_ONE
const OBSERVER_Y_OFFSET := 14 * F_ONE
# Gates: a full-width barrier every 1000 world units, flanked by two bunkers;
# both bunkers down = gate opens and becomes the checkpoint. (Greybox gates
# block movement and camera, not bullets — the arena bunkers sit south of the
# wall and are fought from below.)
const GATE_SPACING := 1000 * F_ONE
const GATE_BLOCK_PAD := 14 * F_ONE
const GATE_CAMERA_PAD := 60 * F_ONE
# Flak Vest: absorbs exactly one hit, then a mercy window.
const VEST_IFRAME_TICKS := 90
# Endless War: escalating waves with a between-wave War Chest shop.
const WAVE_BASE_ENEMIES := 4
const WAVE_ENEMIES_PER_WAVE := 2
const WAVE_SPAWN_INTERVAL_TICKS := 20
const WAVE_INTERMISSION_TICKS := 300
const SHOP_AMMO_COST := 30
const SHOP_GRENADE_COST := 30
const SHOP_VEST_COST := 60
const SHOP_AIRSTRIKE_COST := 100
# Spend-wheel prices by supply kind (0 ammo, 1 grenade, 2 vest, 3 airstrike).
const SUPPLY_COSTS: Array[int] = [SHOP_AMMO_COST, SHOP_GRENADE_COST, SHOP_VEST_COST, SHOP_AIRSTRIKE_COST]
# Foundry Colossus: the finale. A fortress-crawler that inverts the scroll —
# it advances DOWN the map at the players. Armor: grenades only. Three
# phases by HP thirds. Engaging it triggers the Last Stand rule: no more
# War Chest revives; on victory the remaining chest converts to score.
const FINAL_GATE_INDEX := 5
const COLOSSUS_HP := 60
const COLOSSUS_GRENADE_DAMAGE := 4
const COLOSSUS_SPEED := F_ONE / 2
const COLOSSUS_HIT_RADIUS := 34 * F_ONE
const COLOSSUS_CRUSH_RADIUS := 26 * F_ONE
const COLOSSUS_SPRAY_CD_TICKS := 30
const COLOSSUS_VOLLEY_CD_TICKS := 120
const COLOSSUS_SPAWN_CD_TICKS := 90
# Core window: every cycle the plating retracts for a beat during which
# BULLETS also chip the Colossus — a timing/aggression path for a dry pool.
const COLOSSUS_CORE_CYCLE_TICKS := 240
const COLOSSUS_CORE_OPEN_TICKS := 90
const COLOSSUS_BULLET_DAMAGE := 1
const SUPPLY_DROP_INTERVAL_TICKS := 300
# Water: rivers between gate arenas. Wading halves speed, disables the roll,
# and walls out tanks; submerged frogmen answer only to grenades (1986 rule).
const WATER_H := 80 * F_ONE
const FORD_HALF_W := 32 * F_ONE
const FROGMAN_NOTICE_RADIUS := 60 * F_ONE
const FROGMAN_CALM_RADIUS := 100 * F_ONE
const FROGMAN_LUNGE_SPEED := 3 * F_ONE
const FROGMAN_LUNGE_TICKS := 45
# Surfacing telegraph: the frogman is visible, rooted and harmless (but
# shootable) for this window before the lunge — one-hit-death fairness.
const FROGMAN_SURFACE_TICKS := 30
# Bridge Gunship: every 3rd gate is a bridge boss fight. Bullets chip it,
# grenades chunk it; strafe sprays and mortar volleys alternate.
const BOSS_GATE_EVERY := 3
const BOSS_HP := 40
const BOSS_GRENADE_DAMAGE := 8
const BOSS_HIT_RADIUS := 20 * F_ONE
const BOSS_SPEED := 2 * F_ONE
const BOSS_Y_OFFSET := 40 * F_ONE
const BOSS_CYCLE_TICKS := 360
const BOSS_SPRAY_INTERVAL_TICKS := 12
const BOSS_BOUNTY := COIN_BUNKER * 4
# Mortar volley: the three strike ticks within the second half of the phase cycle.
const BOSS_MORTAR_TICKS := [200, 240, 280]
const ENEMY_BULLET_SPEED := 3 * F_ONE
const ENEMY_BULLET_TTL_TICKS := 180
const ENEMY_BULLET_HIT_RADIUS := 8 * F_ONE

var tick_count: int = 0
var rng: SimRng
var players: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var grenades: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var bunkers: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var tanks: Array[Dictionary] = []
var gates: Array[Dictionary] = []
var strikes: Array[Dictionary] = []
var waters: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []
var mines: Array[Dictionary] = []
var observer: Dictionary = {}
var war_chest: int = 0
var score: int = 0
var camera_top: int = 0
var last_gate_y: int = 0          # 0 = no checkpoint yet (sentinel)
var stall_ticks: int = 0
var mode: String = "campaign"     # "campaign" | "endless"
var wave: int = 0
var wave_pending: int = 0
var wave_spawn_cd: int = 0
var wave_mod: int = 0              # endless-only wave mutator (0 none, 1 blitz, 2 elite-guard, 3 spotter)
var intermission_ticks: int = 0
var pending_airstrike: int = 0     # ticks until a called airstrike resolves (0 = none)
var colossus: Dictionary = {}
var endless_boss: Dictionary = {}   # endless-only miniboss (reuses the gunship schema)
var assist_mode: bool = false       # accessibility: every life starts with a flak vest (2-hit)
var hard: bool = false              # New Game+ HARD: a tighter campaign spawn curve
var last_stand: bool = false
var victory: bool = false
var wiped: bool = false            # endless: whole party down with no rescue → run over
var _supply_cd: int = 0
var _world_ended: bool = false    # final gate streamed; no more world
## Transient per-tick view events: {"t": <kind>, "x", "y", ...kind-specific fields}.
## Rebuilt every step() from state transitions; EXCLUDED from the checksum.
## ~40 kinds exist now — see main._consume_events() + _EVENT_SOUND for the full set.
var events: Array[Dictionary] = []
var _spawn_counter: int = 0
var _next_bunker_y: int = 0
var _next_gate_y: int = 0
var _next_tank_y: int = 0
var _next_water_y: int = 0
var _next_mine_y: int = 0
var _gate_counter: int = 0
var _spawn_grace: int = 0          # field-spawner lull after a checkpoint opens
var kill_streak: int = 0           # consecutive kills (drives the score-bonus tiers)
var kill_streak_timer: int = 0     # ticks left before the streak lapses
var deaths_since_gate: int = 0     # for the Flawless Gate bonus (reset on gate open)
var flawless_streak: int = 0       # consecutive deathless gates (compounds the bonus)
var deaths_this_wave: int = 0      # endless: for the Clean Wave bonus
var _prev_camera_top: int = 0


func _init(seed_value: int, player_count: int, game_mode: String = "campaign") -> void:
	mode = game_mode
	rng = SimRng.new(seed_value)
	camera_top = -VIEW_H
	_prev_camera_top = camera_top
	_next_bunker_y = -(500 * F_ONE)
	_next_gate_y = -GATE_SPACING
	_next_tank_y = -(750 * F_ONE)
	_next_water_y = -(1500 * F_ONE)
	_next_mine_y = -(700 * F_ONE)
	for i in player_count:
		players.append({
			"idx": i,
			"x": (280 + i * 80) * F_ONE,
			"y": -(60 * F_ONE),
			"aim_x": 0, "aim_y": -F_ONE,
			"alive": true,
			"deaths": 0,
			"mg_ammo": MG_AMMO_MAX,
			"grenade_ammo": GRENADE_AMMO_MAX,
			"fire_cd": 0, "grenade_cd": 0,
			"broke_timer": 0,
			"roll_ticks": 0, "roll_cd": 0, "roll_buf": 0,
			"roll_iframe": false,
			"roll_dx": 0, "roll_dy": -F_ONE,
			"boost_ticks": 0,
			"in_tank": -1,
			"interact_prev": false,
			"buy_prev": 0,
			"vest": false,
			"hurt_iframes": 0,
			"pierce_ticks": 0,
			"spread_ticks": 0,
		})


func is_solo() -> bool:
	return players.size() == 1


func revive_cost(p: Dictionary) -> int:
	# Soft-cap the multiplier at 3 deaths: a linear ramp against flat kill
	# income becomes an unrecoverable death spiral otherwise.
	var cost: int = REVIVE_BASE_COST * mini(p["deaths"], 3)
	if mode == "endless":
		cost += (wave / 5) * 20   # deep-endless revives cost more (kill income scales too)
	if is_solo():
		cost = cost / 2
	return maxi(cost, REVIVE_BASE_COST / (2 if is_solo() else 1))


func step(inputs: Array) -> void:
	## Advance one tick. `inputs` is one SimInput per player.
	tick_count += 1
	events.clear()
	if wiped:
		return   # the run is over; the sim is frozen behind the debrief
	_prev_camera_top = camera_top
	_step_players(inputs)
	_step_tanks()
	_step_bullets()
	_step_enemy_bullets()
	_step_grenades()
	_step_enemies()
	# Kill-streak lapses if no kill lands within the window.
	if kill_streak_timer > 0:
		kill_streak_timer -= 1
		if kill_streak_timer == 0:
			kill_streak = 0
	# A called airstrike resolves after its telegraph window (enemies keep acting
	# through it — the buyer commits before seeing the result).
	if pending_airstrike > 0:
		pending_airstrike -= 1
		if pending_airstrike == 0:
			_fire_mission()
	_step_bunkers()
	if mode == "endless":
		_step_waves()
		if not endless_boss.is_empty() and endless_boss["alive"]:
			_step_one_boss(endless_boss)
		# The Spotter wave-mutator drops an Observer; step it so its barrage is
		# real (endless has no camera advance, so the despawn path never fires
		# — the observer lives until shot, which is the intended pressure).
		if not observer.is_empty():
			_step_observer()
		_resolve_strikes()   # grenadier lobs detonate even with no observer
	else:
		_step_spawner()
		_step_mines()
		_step_boss()
		_step_colossus()
		_step_gates()
		_step_camera()
		_step_observer()
		_resolve_strikes()   # was the tail of _step_observer; same order


# --- Players ---

func _enemy_strikeable(e: Dictionary) -> bool:
	return e["alive"] and not e.get("submerged", false) and e.get("surface_ticks", 0) == 0


func _step_players(inputs: Array) -> void:
	for i in players.size():
		var p := players[i]
		var inp: SimInput = inputs[i] if i < inputs.size() else SimInput.new()
		p["fire_cd"] = maxi(0, p["fire_cd"] - 1)
		p["grenade_cd"] = maxi(0, p["grenade_cd"] - 1)
		p["roll_cd"] = maxi(0, p["roll_cd"] - 1)
		p["roll_buf"] = maxi(0, p["roll_buf"] - 1)
		p["boost_ticks"] = maxi(0, p["boost_ticks"] - 1)
		p["hurt_iframes"] = maxi(0, p["hurt_iframes"] - 1)
		p["pierce_ticks"] = maxi(0, p["pierce_ticks"] - 1)
		p["spread_ticks"] = maxi(0, p["spread_ticks"] - 1)
		p["roll_iframe"] = false
		var interact_edge: bool = inp.interact and not p["interact_prev"]
		p["interact_prev"] = inp.interact
		var buy_edge: bool = inp.buy > 0 and p["buy_prev"] == 0
		p["buy_prev"] = inp.buy

		if not p["alive"]:
			_step_dead_player(i, p, inp)
			continue

		# Spend-wheel purchases work on foot and from the tank (radio op).
		if buy_edge:
			_try_buy(p, inp.buy - 1)

		if p["in_tank"] >= 0:
			_drive_tank(i, p, inp, interact_edge)
			continue

		# Movement: quantized stick [-256,256] -> fixed direction, normalized.
		var mx: int = inp.move_x * 256   # 256*256 = 65536 = 1.0 fixed at full deflection
		var my: int = inp.move_y * 256
		var mlen := Fixed.length(mx, my)
		var moving: bool = mlen > F_ONE / 8

		var wading := _in_water(p["x"], p["y"])

		# Dodge roll: locks direction at trigger, 2× speed, i-frames.
		# You cannot roll while wading (1986 water grammar). Presses buffer for
		# ROLL_BUFFER_TICKS so a slightly-early press still rolls on cd end.
		if inp.roll:
			p["roll_buf"] = ROLL_BUFFER_TICKS
		if p["roll_buf"] > 0 and p["roll_cd"] == 0 and p["roll_ticks"] == 0 and moving and not wading:
			p["roll_buf"] = 0
			p["roll_ticks"] = ROLL_TICKS
			p["roll_cd"] = ROLL_CD_TICKS
			p["roll_dx"] = Fixed.div(mx, mlen)
			p["roll_dy"] = Fixed.div(my, mlen)
			events.append({"t": "roll", "x": p["x"], "y": p["y"], "i": i})
		if p["roll_ticks"] > 0:
			p["roll_ticks"] = p["roll_ticks"] - 1
			p["roll_iframe"] = true
			p["x"] = p["x"] + Fixed.mul(p["roll_dx"], PLAYER_SPEED * 2)
			p["y"] = p["y"] + Fixed.mul(p["roll_dy"], PLAYER_SPEED * 2)
		elif moving:
			var spd := PLAYER_SPEED
			if p["boost_ticks"] > 0:
				spd = (PLAYER_SPEED * 3) / 2
			if wading:
				spd = spd / 2
			p["x"] = p["x"] + Fixed.mul(Fixed.div(mx, mlen), spd)
			p["y"] = p["y"] + Fixed.mul(Fixed.div(my, mlen), spd)
		_clamp_actor(p)

		# Aim: decoupled from movement (the loop-lever identity).
		var ax: int = inp.aim_x * 256
		var ay: int = inp.aim_y * 256
		var alen := Fixed.length(ax, ay)
		if alen > F_ONE / 4:
			p["aim_x"] = Fixed.div(ax, alen)
			p["aim_y"] = Fixed.div(ay, alen)

		if inp.fire and p["fire_cd"] == 0 and p["mg_ammo"] <= 0:
			# Empty-clip bash: one enemy in reach dies (no coin), on a long
			# cooldown — running dry is a beat of danger, not pure helplessness.
			var bashed := false
			if p["in_tank"] < 0:
				for e in enemies:
					if _enemy_strikeable(e) \
							and _dist_lte(p["x"], p["y"], e["x"], e["y"], BASH_RADIUS):
						_kill_enemy(e, true)
						p["fire_cd"] = BASH_COOLDOWN_TICKS
						events.append({"t": "bash", "x": p["x"], "y": p["y"], "i": i})
						bashed = true
						break
			if not bashed:
				events.append({"t": "dry_fire", "x": p["x"], "y": p["y"], "i": i})
		if inp.fire and p["fire_cd"] == 0 and p["mg_ammo"] > 0:
			p["fire_cd"] = FIRE_COOLDOWN_TICKS
			p["mg_ammo"] = p["mg_ammo"] - 1
			events.append({"t": "shot", "x": p["x"], "y": p["y"], "i": i})
			var fax: int = p["aim_x"]
			var fay: int = p["aim_y"]
			_spawn_mg_bullet(p, i, fax, fay)
			if p["spread_ticks"] > 0:
				# Trench Gun: two extra pellets fanned +/-12 deg (fixed-point rotate).
				_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD_COS) - Fixed.mul(fay, SPREAD_SIN),
					Fixed.mul(fax, SPREAD_SIN) + Fixed.mul(fay, SPREAD_COS))
				_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD_COS) + Fixed.mul(fay, SPREAD_SIN),
					Fixed.mul(fay, SPREAD_COS) - Fixed.mul(fax, SPREAD_SIN))

		if inp.grenade and p["grenade_cd"] == 0 and p["grenade_ammo"] > 0:
			p["grenade_cd"] = GRENADE_COOLDOWN_TICKS
			p["grenade_ammo"] = p["grenade_ammo"] - 1
			events.append({"t": "throw", "x": p["x"], "y": p["y"], "i": i})
			grenades.append({
				"x": p["x"], "y": p["y"],
				"vx": Fixed.mul(p["aim_x"], GRENADE_SPEED),
				"vy": Fixed.mul(p["aim_y"], GRENADE_SPEED),
				"z": 0, "zv": GRENADE_ZVEL, "owner": i, "shell": false,
			})

		if inp.revive:
			_try_revive(i, p)

		if interact_edge:
			_try_board_tank(i, p)

		# Contact with any enemy = one-hit death (roll i-frames protect;
		# submerged frogmen must surface before they can strike).
		if not p["roll_iframe"] and p["in_tank"] < 0:
			for e in enemies:
				if _enemy_strikeable(e) and e["kind"] != "courier" \
						and _dist_lte(p["x"], p["y"], e["x"], e["y"], ENEMY_TOUCH_RADIUS):
					_hurt_player(p)
					break

		# Pickups. Shop crates carry a price paid from the shared War Chest;
		# an unaffordable crate stays on the ground.
		if p["alive"]:
			_collect_pickups(p, i)


func _clamp_actor(p: Dictionary) -> void:
	p["x"] = clampi(p["x"], WORLD_LEFT, WORLD_RIGHT)
	p["y"] = clampi(p["y"], camera_top + 16 * F_ONE, camera_top + 344 * F_ONE)
	# Closed gates are a hard wall to the north.
	for g in gates:
		if not g["open"] and p["y"] < g["y"] + GATE_BLOCK_PAD:
			p["y"] = g["y"] + GATE_BLOCK_PAD


func _collect_pickups(p: Dictionary, i: int) -> void:
	## Extracted, same-order pass over the tail of _step_players: a player
	## in range of an affordable (or free) pickup collects it immediately.
	for k in range(pickups.size() - 1, -1, -1):
		var pk := pickups[k]
		if not _dist_lte(p["x"], p["y"], pk["x"], pk["y"], PICKUP_RADIUS):
			continue
		var cost: int = pk.get("cost", 0)
		if cost > 0 and war_chest < cost:
			continue
		war_chest -= cost
		_apply_supply(p, pk["kind"])
		events.append({"t": "pickup", "x": pk["x"], "y": pk["y"],
			"kind": pk["kind"], "cost": cost})
		pickups.remove_at(k)


func _step_dead_player(_index: int, p: Dictionary, inp: SimInput) -> void:
	# Last Stand: past the final gate, dead is dead — no timer, no coin reader.
	if last_stand:
		return
	# Broke fallback: if nobody can afford a revive, a timer respawns you at
	# the last opened gate (or the bottom of the screen before any gate).
	if p["broke_timer"] > 0:
		p["broke_timer"] = p["broke_timer"] - 1
		if p["broke_timer"] == 0:
			# Endless has NO free respawn once the whole party is down — that is
			# the wipe, and the only way an endless run ends (and records). A
			# partner still up rescues you; campaign still respawns at checkpoint.
			if mode == "endless" and _all_players_down():
				wiped = true
				events.append({"t": "wiped", "x": p["x"], "y": p["y"]})
			else:
				_respawn(p, _checkpoint_y())
			return
	# Dead player pressing revive = feeding the War Chest coin reader (solo,
	# or when the partner is also down).
	if inp.revive:
		_try_revive(-1, p)


func _all_players_down() -> bool:
	for p in players:
		if p["alive"]:
			return false
	return true


func _checkpoint_y() -> int:
	if last_gate_y != 0:
		return last_gate_y + 30 * F_ONE
	return camera_top + 330 * F_ONE


func _try_revive(reviver_index: int, reviver: Dictionary) -> void:
	## An alive player revives all dead partners at their side; a dead player
	## (reviver_index == -1) revives themself. Spends the shared War Chest.
	## LAST STAND: once the Colossus is engaged, the coin reader is dead —
	## no revives past the final gate (the arcade's no-continue finale).
	if last_stand:
		return
	for j in players.size():
		var target := players[j]
		if target["alive"]:
			continue
		if reviver_index == -1 and target != reviver:
			continue
		var cost := revive_cost(target)
		if war_chest >= cost:
			war_chest -= cost
			var at_y: int = reviver["y"] if reviver["alive"] else _checkpoint_y()
			_respawn(target, at_y)
		else:
			if target["broke_timer"] == 0:
				target["broke_timer"] = BROKE_RESPAWN_TICKS


func _respawn(p: Dictionary, at_y: int) -> void:
	p["alive"] = true
	p["mg_ammo"] = MG_AMMO_MAX         # death restores ammo (1986 rule)
	p["grenade_ammo"] = GRENADE_AMMO_MAX
	p["broke_timer"] = 0
	p["roll_ticks"] = 0
	p["boost_ticks"] = 0
	p["in_tank"] = -1
	p["vest"] = assist_mode            # death strips upgrades (1986 rule; assist re-issues a vest)
	p["pierce_ticks"] = 0              # ...including the Piercing Rounds buff
	p["spread_ticks"] = 0             # ...and the Trench Gun spread buff
	p["hurt_iframes"] = VEST_IFRAME_TICKS   # post-spawn mercy window
	p["y"] = clampi(at_y, camera_top + 16 * F_ONE, camera_top + 344 * F_ONE)
	p["x"] = clampi(p["x"], WORLD_LEFT, WORLD_RIGHT)
	events.append({"t": "revive", "x": p["x"], "y": p["y"]})


func _hurt_player(p: Dictionary) -> void:
	## Every lethal touch funnels here: the Flak Vest absorbs exactly one hit
	## (with a mercy window), otherwise it's the 1986 rule — one hit, done.
	if p["hurt_iframes"] > 0:
		return
	if p["vest"]:
		p["vest"] = false
		p["hurt_iframes"] = VEST_IFRAME_TICKS
		events.append({"t": "vest_break", "x": p["x"], "y": p["y"], "p": p["idx"]})
		return
	_kill_player(p)


func _kill_player(p: Dictionary) -> void:
	p["alive"] = false
	p["deaths"] = p["deaths"] + 1
	p["broke_timer"] = 0
	p["in_tank"] = -1
	deaths_since_gate += 1   # a death here forfeits the next Flawless Gate bonus
	flawless_streak = 0      # ...and breaks the compounding clean-gate streak
	if mode == "endless":
		deaths_this_wave += 1   # ...and forfeits this wave's Clean Wave bonus
	events.append({"t": "player_down", "x": p["x"], "y": p["y"], "p": p["idx"]})


func _fire_mission() -> void:
	## The screen-clear: wipes every surfaced enemy. Spares the submerged
	## (1986 rule) and armor (bosses, bunkers). Mints NO coin — a 100-coin
	## buy that reaped a full screen's bounty was a net-positive money printer.
	events.append({"t": "explosion", "x": SCREEN_CX, "y": camera_top + 180 * F_ONE})
	for e in enemies:
		if e["alive"] and not e.get("submerged", false):
			_kill_enemy(e, true)


func _apply_supply(p: Dictionary, kind: int) -> void:
	## One supply grammar shared by ground pickups, shop crates and buys.
	match kind:
		0:
			p["mg_ammo"] = mini(MG_AMMO_MAX, p["mg_ammo"] + 30)
		1:
			p["grenade_ammo"] = mini(GRENADE_AMMO_MAX, p["grenade_ammo"] + 4)
		2:
			p["vest"] = true
		4:
			p["pierce_ticks"] = PIERCE_TICKS   # Piercing Rounds capsule (drop-only)
		5:
			p["spread_ticks"] = SPREAD_TICKS   # Trench Gun spread capsule (drop-only)
		3:
			# Airstrike is CALLED IN, not instant — it now telegraphs like every
			# other lethal AoE (grenadier lob, sniper paint, observer mortar),
			# giving a commit-then-wait beat instead of a silent screen-wipe.
			pending_airstrike = STRIKE_TELEGRAPH_TICKS
			events.append({"t": "airstrike_called", "x": SCREEN_CX, "y": camera_top + 180 * F_ONE})


func _supply_cost(kind: int) -> int:
	## Endless prices creep up every 3 waves so a fat late-game chest still faces
	## a real spend decision (income scales with the wave, so the shop must too).
	## Campaign is wave 0 → base price, unchanged.
	if kind < 0 or kind >= SUPPLY_COSTS.size():
		return 0
	return SUPPLY_COSTS[kind] + (wave / 3) * 10


func _try_buy(p: Dictionary, kind: int) -> void:
	## Spend-wheel purchase: supplies radioed in, paid from the shared
	## War Chest — the same pool that funds revives. That's the decision.
	if kind < 0 or kind >= SUPPLY_COSTS.size():
		return
	var cost: int = _supply_cost(kind)
	if war_chest < cost:
		events.append({"t": "deny", "x": p["x"], "y": p["y"]})
		return
	war_chest -= cost
	_apply_supply(p, kind)
	events.append({"t": "buy", "x": p["x"], "y": p["y"], "kind": kind})


# --- Tank ---

func _try_board_tank(player_index: int, p: Dictionary) -> void:
	for t in tanks.size():
		var tank := tanks[t]
		if tank["alive"] and tank["occupant"] < 0 and not tank["burning"] \
				and _dist_lte(p["x"], p["y"], tank["x"], tank["y"], TANK_BOARD_RADIUS):
			tank["occupant"] = player_index
			p["in_tank"] = t
			events.append({"t": "tank_board", "x": tank["x"], "y": tank["y"]})
			return


func _drive_tank(player_index: int, p: Dictionary, inp: SimInput, interact_edge: bool) -> void:
	var tank := tanks[p["in_tank"]]
	if not tank["alive"]:
		p["in_tank"] = -1
		return

	if interact_edge:
		_dismount(p, tank)
		return

	var mx: int = inp.move_x * 256
	var my: int = inp.move_y * 256
	var mlen := Fixed.length(mx, my)
	if mlen > F_ONE / 8:
		# Water is a hard wall to armor: revert the move if it would wade.
		var prev_x: int = tank["x"]
		var prev_y: int = tank["y"]
		tank["x"] = tank["x"] + Fixed.mul(Fixed.div(mx, mlen), TANK_SPEED)
		tank["y"] = tank["y"] + Fixed.mul(Fixed.div(my, mlen), TANK_SPEED)
		if _in_water(tank["x"], tank["y"]):
			tank["x"] = prev_x
			tank["y"] = prev_y
	_clamp_actor(tank)
	p["x"] = tank["x"]
	p["y"] = tank["y"]

	var ax: int = inp.aim_x * 256
	var ay: int = inp.aim_y * 256
	var alen := Fixed.length(ax, ay)
	if alen > F_ONE / 4:
		p["aim_x"] = Fixed.div(ax, alen)
		p["aim_y"] = Fixed.div(ay, alen)

	# Cannon: draws from the grenade pool (1986 rule) and lands like one.
	if inp.fire and tank["fire_cd"] == 0 and p["grenade_ammo"] > 0:
		tank["fire_cd"] = TANK_FIRE_COOLDOWN_TICKS
		p["grenade_ammo"] = p["grenade_ammo"] - 1
		events.append({"t": "tank_shot", "x": tank["x"], "y": tank["y"], "i": player_index})
		grenades.append({
			"x": tank["x"], "y": tank["y"],
			"vx": Fixed.mul(p["aim_x"], SHELL_SPEED),
			"vy": Fixed.mul(p["aim_y"], SHELL_SPEED),
			"z": 0, "zv": SHELL_ZVEL, "owner": player_index, "shell": true,
		})

	# Treads: crush infantry, mint coin.
	for e in enemies:
		if e["alive"] and _dist_lte(tank["x"], tank["y"], e["x"], e["y"], TANK_CRUSH_RADIUS):
			_kill_enemy(e)


func _dismount(p: Dictionary, tank: Dictionary) -> void:
	tank["occupant"] = -1
	p["in_tank"] = -1
	p["y"] = tank["y"] + 24 * F_ONE
	if tank["burning"]:
		p["boost_ticks"] = BAIL_BOOST_TICKS   # bailing gets the speed boost
		# ...and a brief mercy window — a forced bail can't hand you a corpse the
		# instant you land on an enemy (matches the respawn/frogman-surface grace).
		p["hurt_iframes"] = maxi(p["hurt_iframes"], BAIL_IFRAME_TICKS)
	_clamp_actor(p)


func _step_tanks() -> void:
	for tank in tanks:
		if not tank["alive"]:
			continue
		tank["fire_cd"] = maxi(0, tank["fire_cd"] - 1)

		if tank["occupant"] >= 0 and not tank["burning"]:
			tank["fuel"] = tank["fuel"] - 1
			if tank["fuel"] <= 0:
				_ignite_tank(tank)

		if tank["burning"]:
			# Kamikaze verb: a burning tank driven into a bunker detonates it.
			# The driver is thrown clear (the cinematic leap) with the boost.
			for bk in bunkers:
				if bk["alive"] and _point_in_aabb_expanded(tank["x"], tank["y"], bk, TANK_KAMIKAZE_PAD):
					bk["alive"] = false
					war_chest += COIN_BUNKER * 2
					score += COIN_BUNKER * 20
					events.append({"t": "bunker_break", "x": bk["x"] + BUNKER_W / 2,
						"y": bk["y"] + BUNKER_H / 2, "coin": COIN_BUNKER * 2})
					if tank["occupant"] >= 0:
						var driver := players[tank["occupant"]]
						_dismount(driver, tank)
					_detonate_tank(tank)
					break
			if not tank["alive"]:
				continue
			tank["burn_ticks"] = tank["burn_ticks"] - 1
			if tank["burn_ticks"] <= 0:
				# Bail window expired: anyone still inside goes with it.
				if tank["occupant"] >= 0:
					_kill_player(players[tank["occupant"]])
					tank["occupant"] = -1
				_detonate_tank(tank)


func _ignite_tank(tank: Dictionary) -> void:
	if not tank["burning"]:
		tank["burning"] = true
		tank["burn_ticks"] = TANK_BAIL_TICKS
		events.append({"t": "tank_ignite", "x": tank["x"], "y": tank["y"]})


func _detonate_tank(tank: Dictionary) -> void:
	tank["alive"] = false
	tank["occupant"] = -1
	_explode(tank["x"], tank["y"])


# --- Projectiles ---

func _offscreen(x: int, y: int) -> bool:
	## Shared screen-bounds cull for bullets: past the vertical strike zone or
	## off either horizontal edge. Callers still add their own TTL check.
	return y < camera_top - 40 * F_ONE or y > camera_top + 400 * F_ONE \
		or x < 0 or x > SCREEN_W_FP


func _step_bullets() -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		b["x"] = b["x"] + b["vx"]
		b["y"] = b["y"] + b["vy"]
		b["ttl"] = b["ttl"] - 1
		var dead: bool = b["ttl"] <= 0 or _offscreen(b["x"], b["y"])
		if not dead:
			# Bullets are stopped by armor: bunkers block, only grenades hurt them.
			for bk in bunkers:
				if bk["alive"] and _point_in_aabb(b["x"], b["y"], bk):
					events.append({"t": "armor_block", "x": b["x"], "y": b["y"]})
					dead = true
					break
		if not dead:
			for e in enemies:
				# Bullets pass clean over submerged frogmen — grenades only.
				if e["alive"] and not e.get("submerged", false) \
						and _dist_lte(b["x"], b["y"], e["x"], e["y"], BULLET_HIT_RADIUS):
					# Shield: a bullet arriving into the front arc (roughly
					# opposite the shieldman's facing-toward-you) is deflected;
					# flank it or use a grenade. Front cone ~120°.
					if e["kind"] == "shield" and _shield_blocks(e, b):
						events.append({"t": "armor_block", "x": b["x"], "y": b["y"]})
						dead = true
						break
					_kill_enemy(e)
					# Piercing Rounds: the shooter's active buff lets the bullet punch
					# through the kill and keep going to the next target this tick.
					var powner: int = b.get("owner", -1)
					if powner >= 0 and powner < players.size() and players[powner]["pierce_ticks"] > 0:
						continue
					dead = true
					break
		if not dead:
			dead = _bullet_hits_boss(b)
		# Colossus core window: while the plating is retracted, bullets chip it
		# too (otherwise grenades-only). A timing/aggression path for the finale.
		if not dead and not colossus.is_empty() and colossus["alive"] \
				and colossus.get("core_open", 0) > 0 \
				and _dist_lte(b["x"], b["y"], colossus["x"], colossus["y"], COLOSSUS_HIT_RADIUS):
			events.append({"t": "boss_hit", "x": b["x"], "y": b["y"]})
			_damage_colossus(COLOSSUS_BULLET_DAMAGE)
			dead = true
		if not dead and not observer.is_empty():
			if _dist_lte(b["x"], b["y"], observer["x"], camera_top + OBSERVER_Y_OFFSET, BULLET_HIT_RADIUS):
				_kill_observer()
				dead = true
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
	events.append({"t": "explosion", "x": x, "y": y})
	var frags := 0
	for e in enemies:
		if e["alive"] and _dist_lte(x, y, e["x"], e["y"], GRENADE_RADIUS):
			_kill_enemy(e)
			frags += 1
	if frags >= 3:
		# Frag bonus: a single blast that catches a pack rewards reading the field.
		score += frags * 50
		events.append({"t": "frag_bonus", "x": x, "y": y, "n": frags})
	for bk in bunkers:
		if bk["alive"] and _point_in_aabb_expanded(x, y, bk, GRENADE_RADIUS):
			bk["alive"] = false
			war_chest += COIN_BUNKER
			score += COIN_BUNKER * 10
			events.append({"t": "bunker_break", "x": bk["x"] + BUNKER_W / 2,
				"y": bk["y"] + BUNKER_H / 2, "coin": COIN_BUNKER})
	# Explosions torch tanks in radius (the observer mortar already did; a
	# player's own grenade now does too) — deny a parked tank to a partner, or
	# torch the tank a partner is driving (they get the bail-boost / kamikaze
	# path). Boarding a burning tank is still guarded, so you can't self-ignite
	# and re-board your own — the ride is a co-op / already-aboard beat.
	for tank in tanks:
		if tank["alive"] and _dist_lte(x, y, tank["x"], tank["y"], GRENADE_RADIUS):
			_ignite_tank(tank)
	if not observer.is_empty() and _dist_lte(x, y, observer["x"], camera_top + OBSERVER_Y_OFFSET, GRENADE_RADIUS):
		_kill_observer()
	for g in gates:
		if not g["boss"].is_empty() and g["boss"]["alive"] and not g["open"] \
				and _dist_lte(x, y, g["boss"]["x"], g["boss"]["gate_y"] - BOSS_Y_OFFSET, GRENADE_RADIUS + BOSS_HIT_RADIUS):
			_damage_boss(g["boss"], BOSS_GRENADE_DAMAGE)
	if not endless_boss.is_empty() and endless_boss["alive"] \
			and _dist_lte(x, y, endless_boss["x"], endless_boss["gate_y"] - BOSS_Y_OFFSET, GRENADE_RADIUS + BOSS_HIT_RADIUS):
		_damage_boss(endless_boss, BOSS_GRENADE_DAMAGE)
	# The Colossus is pure armor: grenades are the only thing it respects.
	if not colossus.is_empty() and colossus["alive"] \
			and _dist_lte(x, y, colossus["x"], colossus["y"], GRENADE_RADIUS + COLOSSUS_HIT_RADIUS):
		_damage_colossus(COLOSSUS_GRENADE_DAMAGE)


func _kill_enemy(e: Dictionary, no_coin := false) -> void:
	e["alive"] = false
	var coin: int = COIN_ELITE if e["elite"] else COIN_RUSHER
	if e["kind"] == "courier":
		coin = COIN_ELITE * 4   # fat bounty for catching the runner
	if e.get("marked", false):
		coin *= 3   # bounty target pays triple (chest + score)
		events.append({"t": "bounty_kill", "x": e["x"], "y": e["y"], "coin": coin})
	if wave_mod == 4:
		coin *= 2   # PAYDAY wave: every bounty doubles
	# kind rides the (checksum-excluded) kill event so the view can spawn a
	# per-type death throe + corpse — golden-safe.
	events.append({"t": "kill", "x": e["x"], "y": e["y"], "coin": 0 if no_coin else coin,
		"kind": e["kind"]})
	if not no_coin:
		war_chest += coin
		# Avenge bounty: a kill next to a downed ally pays a little extra and
		# calls it out — standing your ground over a partner's body is rewarded.
		for pl in players:
			if not pl["alive"] and _dist_lte(e["x"], e["y"], pl["x"], pl["y"], 60 * F_ONE):
				war_chest += 5
				events.append({"t": "avenge", "x": e["x"], "y": e["y"]})
				break
	# Last Stand doubles the score credit — the finale strips revives, so reward
	# pushing into the crush radius instead of kiting (War Chest bounty stays flat).
	score += coin * 10 * (2 if last_stand else 1)
	# Kill-streak: consecutive kills inside the window escalate a SCORE-ONLY
	# bonus at the tiers the view telegraphs (5/10/20). War Chest stays flat —
	# the streak rewards aggression on the leaderboard, not the economy.
	kill_streak = kill_streak + 1 if kill_streak_timer > 0 else 1
	kill_streak_timer = KILL_STREAK_WINDOW_TICKS
	var streak_bonus_pct := 0
	if kill_streak >= 20:
		streak_bonus_pct = 100
	elif kill_streak >= 10:
		streak_bonus_pct = 50
	elif kill_streak >= 5:
		streak_bonus_pct = 25
	if streak_bonus_pct > 0:
		score += (coin * 10 * streak_bonus_pct) / 100
	if kill_streak == 20:
		# The 20-streak stops being just a number: every alive fighter gets a
		# ~3s adrenaline surge (reuses the tank-bail speed boost), so the reward
		# is felt in the hands, not just read on the HUD.
		for pl in players:
			if pl["alive"]:
				pl["boost_ticks"] = maxi(pl["boost_ticks"], BAIL_BOOST_TICKS * 2)
		# One-shot view cue; events[] is checksum-excluded -> golden-safe.
		events.append({"t": "surge", "x": e["x"], "y": e["y"]})
	if e["elite"] and not no_coin:
		pickups.append({
			"x": e["x"], "y": e["y"],
			# ~1-in-6 elites drop a rare power-up capsule (Piercing or Spread);
			# otherwise the usual Ammo/Grenade.
			"kind": (4 + rng.range_i(0, 1)) if rng.range_i(0, 5) == 0 else rng.range_i(0, 1),
		})


# --- Enemies / bunkers / spawner ---

func _advance_toward(e: Dictionary, dx: int, dy: int, dlen: int, base_spd: int) -> void:
	## Shared "move toward target at base_spd, halved while wading" step used by
	## rushers, shieldmen, elites, grenadiers and snipers. Same fixed-point ops,
	## same order, as the code this replaces — golden-safe.
	var spd := base_spd
	if _in_water(e["x"], e["y"]):
		spd = spd / 2
	e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), spd)
	e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), spd)


func _spawn_enemy_bullet(x: int, y: int, dx: int, dy: int, dlen: int, speed: int = ENEMY_BULLET_SPEED) -> void:
	## Shared enemy-bullet-spawn dict used by elites, snipers, the colossus and
	## the bridge boss. Same fixed-point ops, same order, as the code this
	## replaces — golden-safe.
	enemy_bullets.append({
		"x": x, "y": y,
		"vx": Fixed.mul(Fixed.div(dx, dlen), speed),
		"vy": Fixed.mul(Fixed.div(dy, dlen), speed),
		"ttl": ENEMY_BULLET_TTL_TICKS,
	})


func _step_enemies() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not e["alive"] or e["y"] > camera_top + 420 * F_ONE:
			enemies.remove_at(i)
			continue
		if e["kind"] == "frogman":
			_step_frogman(e)
			continue
		var target := _nearest_alive_player(e["x"], e["y"])
		if target.is_empty():
			continue
		var dx: int = target["x"] - e["x"]
		var dy: int = target["y"] - e["y"]
		var dlen := Fixed.length(dx, dy)
		if e["kind"] == "courier":
			# Flee AWAY from the nearest player, biased up toward the top edge;
			# crossing above the view means it escaped (and forfeits its bounty).
			var fx: int = -dx
			var fy: int = -dy - 40 * F_ONE
			var flen := Fixed.length(fx, fy)
			if flen > F_ONE:
				e["x"] = e["x"] + Fixed.mul(Fixed.div(fx, flen), COURIER_SPEED)
				e["y"] = e["y"] + Fixed.mul(Fixed.div(fy, flen), COURIER_SPEED)
			if e["y"] < camera_top - 30 * F_ONE:
				e["alive"] = false
				events.append({"t": "courier_escape", "x": e["x"], "y": e["y"]})
			continue
		if e["kind"] == "grenadier":
			_step_grenadier(e, target, dx, dy, dlen)
			continue
		if e["kind"] == "sniper":
			_step_sniper(e, target, dx, dy, dlen)
			continue
		if e["kind"] == "shield":
			# Advances slowly behind a frontal shield (bullet block handled in
			# _step_bullets); touch still kills. No ranged attack.
			if dlen > F_ONE:
				_advance_toward(e, dx, dy, dlen, SHIELD_SPEED)
			continue
		if e["kind"] == "sapper":
			_step_sapper(e, dx, dy, dlen)
			continue
		if e["kind"] == "ghillie":
			_step_ghillie(e, target, dx, dy, dlen)
			continue
		if e["elite"]:
			_step_elite(e, target, dx, dy, dlen)
			continue
		if dlen > F_ONE:
			_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)


func _step_elite(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Skirmisher: advance to standoff range, wind up (visible, interruptible
	## by killing him), fire one aimed shot. Touch still kills.
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0 and dlen > F_ONE:
			events.append({"t": "enemy_shot", "x": e["x"], "y": e["y"]})
			_spawn_enemy_bullet(e["x"], e["y"], dx, dy, dlen)
		return   # rooted while winding up
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > ELITE_STANDOFF:
		_advance_toward(e, dx, dy, dlen, ELITE_SPEED)
	elif e["fire_cd"] == 0:
		e["fire_cd"] = ELITE_FIRE_CD_TICKS
		e["windup"] = ELITE_WINDUP_TICKS
		events.append({"t": "elite_windup", "x": e["x"], "y": e["y"]})


func _step_grenadier(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Mid-range zoner: holds GRENADIER_STANDOFF, winds up, then lobs a
	## telegraphed area strike onto your CURRENT ground — move or eat it.
	## Reuses fire_cd/windup (both already hashed) so campaign stays golden.
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0:
			_add_strike(target["x"], target["y"])   # telegraphed blast where you stand
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > GRENADIER_STANDOFF:
		_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)
	elif e["fire_cd"] == 0:
		e["fire_cd"] = GRENADIER_FIRE_CD_TICKS
		e["windup"] = GRENADIER_WINDUP_TICKS
		events.append({"t": "grenadier_windup", "x": e["x"], "y": e["y"]})


func _step_sniper(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Long-range: paints a laser line on you for a long windup (view draws it
	## off the windup state), then fires ONE fast bullet down the locked line.
	## Sidestep or break LOS. Reuses fire_cd/windup — campaign golden-safe.
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0:
			# Fire down the vector LOCKED at paint start — the laser line the view
			# drew is a promise: sidestepping it must actually dodge the bullet.
			var lx: int = e.get("aim_lx", dx)
			var ly: int = e.get("aim_ly", dy)
			var llen := Fixed.length(lx, ly)
			if llen > F_ONE:
				events.append({"t": "sniper_fire", "x": e["x"], "y": e["y"]})
				_spawn_enemy_bullet(e["x"], e["y"], lx, ly, llen, SNIPER_BULLET_SPEED)
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	# Keeps to the back — only closes if the target runs far away.
	if dlen > SNIPER_STANDOFF:
		_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)
	elif e["fire_cd"] == 0:
		e["fire_cd"] = SNIPER_FIRE_CD_TICKS
		e["windup"] = SNIPER_WINDUP_TICKS
		e["aim_lx"] = dx   # lock the shot vector at paint start (see fire branch)
		e["aim_ly"] = dy
		events.append({"t": "sniper_paint", "x": e["x"], "y": e["y"]})


func _step_frogman(e: Dictionary) -> void:
	## Lurks submerged (grenades only), telegraphs by surfacing (rooted and
	## harmless for FROGMAN_SURFACE_TICKS, but shootable), then lunges;
	## re-submerges when the water calms.
	var target := _nearest_alive_player(e["x"], e["y"])
	if target.is_empty():
		return
	var dx: int = target["x"] - e["x"]
	var dy: int = target["y"] - e["y"]
	if e["submerged"]:
		if Fixed.mul(dx, dx) + Fixed.mul(dy, dy) <= Fixed.mul(FROGMAN_NOTICE_RADIUS, FROGMAN_NOTICE_RADIUS):
			e["submerged"] = false
			e["surface_ticks"] = FROGMAN_SURFACE_TICKS
			events.append({"t": "frogman_surface", "x": e["x"], "y": e["y"]})
		return
	if e["surface_ticks"] > 0:
		e["surface_ticks"] = e["surface_ticks"] - 1
		if e["surface_ticks"] == 0:
			e["lunge_ticks"] = FROGMAN_LUNGE_TICKS
		return
	var dlen := Fixed.length(dx, dy)
	if e["lunge_ticks"] > 0:
		e["lunge_ticks"] = e["lunge_ticks"] - 1
		if dlen > F_ONE:
			e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), FROGMAN_LUNGE_SPEED)
			e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), FROGMAN_LUNGE_SPEED)
	elif dlen > FROGMAN_CALM_RADIUS and _in_water(e["x"], e["y"]):
		e["submerged"] = true
	else:
		e["lunge_ticks"] = FROGMAN_LUNGE_TICKS   # rewind for another lunge


func _step_sapper(e: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Advances like a rusher (touch still kills) but drops an armed mine on a
	## cooldown, authoring a hazard trail across the arena. Reuses fire_cd as the
	## drop timer, and the existing landmine array/detonation — no new state.
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if e["fire_cd"] == 0 and mines.size() < SAPPER_MAX_MINES:
		e["fire_cd"] = SAPPER_MINE_CD_TICKS
		mines.append({"x": e["x"], "y": e["y"], "armed": true})
		events.append({"t": "mine_lay", "x": e["x"], "y": e["y"]})
	if dlen > F_ONE:
		var spd := ENEMY_SPEED
		if wave_mod == 6:
			spd = (spd * 7) / 5   # FRENZY wave: the swarm rushes 40% faster
		if _in_water(e["x"], e["y"]):
			spd = spd / 2
		e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), spd)
		e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), spd)


func _step_ghillie(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## A cloaked sniper dug into the ground: bullet-immune + harmless + no threat
	## arrow while submerged, reveals when you enter notice range, then paints and
	## fires ONE locked shot from cover (stationary — never chases). Killing it
	## during the reveal/paint window defuses the shot. Reuses sniper paint state.
	if e["submerged"]:
		if dlen <= GHILLIE_NOTICE_RADIUS:
			e["submerged"] = false
			e["surface_ticks"] = GHILLIE_REVEAL_TICKS
			events.append({"t": "frogman_surface", "x": e["x"], "y": e["y"]})
		return
	if e["surface_ticks"] > 0:
		e["surface_ticks"] = e["surface_ticks"] - 1
		return
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0:
			var lx: int = e.get("aim_lx", dx)
			var ly: int = e.get("aim_ly", dy)
			var llen := Fixed.length(lx, ly)
			if llen > F_ONE:
				events.append({"t": "sniper_fire", "x": e["x"], "y": e["y"]})
				enemy_bullets.append({
					"x": e["x"], "y": e["y"],
					"vx": Fixed.mul(Fixed.div(lx, llen), SNIPER_BULLET_SPEED),
					"vy": Fixed.mul(Fixed.div(ly, llen), SNIPER_BULLET_SPEED),
					"ttl": ENEMY_BULLET_TTL_TICKS,
				})
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > GHILLIE_NOTICE_RADIUS:
		e["submerged"] = true   # you slipped out of range — re-cloak and wait
		return
	if e["fire_cd"] == 0:
		e["fire_cd"] = SNIPER_FIRE_CD_TICKS
		e["windup"] = SNIPER_WINDUP_TICKS
		e["aim_lx"] = dx   # lock the shot vector at paint start (view draws the line)
		e["aim_ly"] = dy
		events.append({"t": "sniper_paint", "x": e["x"], "y": e["y"]})


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


func _step_mines() -> void:
	for i in range(mines.size() - 1, -1, -1):
		var m := mines[i]
		if not m["armed"] or m["y"] > camera_top + 420 * F_ONE:
			mines.remove_at(i)
			continue
		var triggered := false
		# A player on foot (not rolling) stepping on it takes the hit + detonates.
		for p in players:
			if p["alive"] and p["in_tank"] < 0 and not p["roll_iframe"] \
					and _dist_lte(p["x"], p["y"], m["x"], m["y"], MINE_TRIGGER_RADIUS):
				_hurt_player(p)
				triggered = true
		# Or an enemy walks onto it — herd rushers into the minefield.
		if not triggered:
			for e in enemies:
				if e["alive"] and not e.get("submerged", false) \
						and _dist_lte(e["x"], e["y"], m["x"], m["y"], MINE_TRIGGER_RADIUS):
					triggered = true
					break
		if triggered:
			m["armed"] = false
			_explode(m["x"], m["y"])


func _step_spawner() -> void:
	# Field spawner: pressure from above the screen edge; every 8th is a red
	# elite. Each opened gate tightens the interval — the campaign's
	# difficulty ratchet (45 → 24 ticks by gate 5).
	var opened := 0
	for g in gates:
		if g["open"]:
			opened += 1
	if _spawn_grace > 0:
		_spawn_grace -= 1
	var interval := maxi(24, SPAWN_INTERVAL_TICKS - opened * 4)
	if hard:
		interval = maxi(16, (interval * 2) / 3)   # NG+ pours them in faster
	if tick_count % interval != 0 or enemies.size() >= MAX_ENEMIES or _spawn_grace > 0:
		return
	_spawn_counter += 1
	var x := rng.range_i(24, 616) * F_ONE
	# Sector 4+ (3 gates opened): the endless ranged roster starts bleeding into
	# the campaign field, so late sectors get a genuinely new threat vocabulary
	# (laser-paint sniper, riot shield) — not just faster rushers.
	if opened >= 3 and rng.range_i(0, 4) == 0:
		var specials := ["grenadier", "sniper", "shield"]
		_spawn_special(x, camera_top - 24 * F_ONE, specials[rng.range_i(0, 2)])
	else:
		# Elite ratio tightens with each opened gate (every 8th → every 3rd by
		# gate 5) so late campaign escalates composition, not just cadence.
		var elite_every := maxi(3, 8 - opened)
		if hard:
			elite_every = maxi(2, elite_every - 2)   # NG+ fields far more red elites
		_spawn_enemy(x, camera_top - 24 * F_ONE, _spawn_counter % elite_every == 0)


func _spawn_enemy(x: int, y: int, elite: bool) -> void:
	var e := {"x": x, "y": y, "alive": true, "elite": elite,
		"kind": "elite" if elite else "rusher"}
	if elite:
		e["fire_cd"] = ELITE_FIRE_CD_TICKS / 2   # first shot comes sooner
		e["windup"] = 0
		# ~1 in 7 elites is a marked BOUNTY target — triple pay, worth chasing
		# across the field (the view crowns it so the payoff reads before you commit).
		if rng.range_i(0, 6) == 0:
			e["marked"] = true
	enemies.append(e)


func _spawn_frogman(x: int, y: int) -> void:
	enemies.append({"x": x, "y": y, "alive": true, "elite": false,
		"kind": "frogman", "submerged": true, "lunge_ticks": 0, "surface_ticks": 0})


func _shield_blocks(e: Dictionary, b: Dictionary) -> bool:
	## True if bullet b hits the shieldman's front arc. Facing = toward the
	## nearest player; a head-on bullet travels roughly opposite that, so a
	## strongly-negative dot(bullet_dir, facing) means 'into the shield'.
	var target := _nearest_alive_player(e["x"], e["y"])
	if target.is_empty():
		return false
	var fx: int = target["x"] - e["x"]
	var fy: int = target["y"] - e["y"]
	var flen := Fixed.length(fx, fy)
	var blen := Fixed.length(b["vx"], b["vy"])
	if flen <= 0 or blen <= 0:
		return false
	# dot of unit vectors, in fixed-point; block when < -0.5 (front 120° cone).
	var dot := Fixed.mul(Fixed.div(fx, flen), Fixed.div(b["vx"], blen)) \
		+ Fixed.mul(Fixed.div(fy, flen), Fixed.div(b["vy"], blen))
	return dot < -(F_ONE / 2)


func _spawn_mg_bullet(p: Dictionary, i: int, ax: int, ay: int) -> void:
	bullets.append({"x": p["x"], "y": p["y"],
		"vx": Fixed.mul(ax, BULLET_SPEED), "vy": Fixed.mul(ay, BULLET_SPEED),
		"ttl": BULLET_TTL_TICKS, "owner": i})


func _spawn_courier() -> void:
	# A fleeing supply runner, dropped into the lower-middle so it has to cross
	# the arena on its way to the top edge — a window to catch it.
	enemies.append({"x": rng.range_i(80, 560) * F_ONE, "y": camera_top + 240 * F_ONE,
		"alive": true, "elite": false, "kind": "courier"})


func _spawn_special(x: int, y: int, kind: String) -> void:
	## Endless-only ranged/hazard archetypes (grenadier/sniper/shield/sapper/
	## ghillie). Coin-worthy like an elite; reuse fire_cd/windup/submerged so no
	## new hashed enemy field is introduced.
	var e := {"x": x, "y": y, "alive": true, "elite": true,
		"kind": kind, "fire_cd": SNIPER_FIRE_CD_TICKS / 2, "windup": 0}
	if kind == "ghillie":
		e["submerged"] = true   # dug in, cloaked until you close the distance
		e["surface_ticks"] = 0
	enemies.append(e)


# --- Gates ---

func _step_gates() -> void:
	for g in gates:
		if g["open"] or g.get("final", false):
			continue   # the final gate is opened by the Colossus's death alone
		var cleared: bool
		if not g["boss"].is_empty():
			cleared = not g["boss"]["alive"]
		else:
			cleared = not g["b1"]["alive"] and not g["b2"]["alive"]
		if cleared:
			g["open"] = true
			last_gate_y = g["y"]
			_spawn_grace = GATE_SPAWN_GRACE_TICKS   # let the checkpoint beat breathe
			# Flawless Gate: clear a checkpoint with zero deaths since the last one
			# and the discipline pays — a legible reward for playing tight.
			if deaths_since_gate == 0:
				# Compounding: consecutive clean checkpoints pay more (capped 3×),
				# rewarding sustained discipline across the campaign, not one clean gate.
				flawless_streak += 1
				var fmult: int = mini(flawless_streak, 3)
				war_chest += 50 * fmult
				score += 2000 * fmult
				events.append({"t": "gate_flawless", "x": SCREEN_CX, "y": g["y"], "mult": fmult})
			deaths_since_gate = 0
			# Guaranteed cache past every checkpoint — the gate-open beat had a big
			# audiovisual payoff but no mechanical reward; a free grenade/vest crate
			# closes that loop.
			pickups.append({"x": (200 + rng.range_i(0, 240)) * F_ONE, "y": g["y"] - 40 * F_ONE,
				"kind": 1 + rng.range_i(0, 1), "cost": 0})
			events.append({"t": "gate_open", "x": SCREEN_CX, "y": g["y"]})


func _in_water(x: int, y: int) -> bool:
	for w in waters:
		if y >= w["y"] and y <= w["y"] + WATER_H:
			if x < w["ford_x"] - FORD_HALF_W or x > w["ford_x"] + FORD_HALF_W:
				return true
	return false


# --- Camera & world streaming ---

func _step_camera() -> void:
	# Ratchet: follows the highest (most advanced) alive player, never scrolls back.
	var focus := 0
	var found := false
	for p in players:
		if p["alive"] and (not found or p["y"] < focus):
			focus = p["y"]
			found = true
	if found:
		var desired := focus - CAMERA_LEAD
		# Closed gates hold the camera so the arena stays on one screen.
		for g in gates:
			if not g["open"] and desired < g["y"] - GATE_CAMERA_PAD:
				desired = g["y"] - GATE_CAMERA_PAD
		if desired < camera_top:
			camera_top = desired

	# Stream the world ahead of the scroll: bunkers between gates, a gate
	# arena every GATE_SPACING, a parked tank between each pair of gates.
	var horizon := camera_top - 2 * VIEW_H
	while _next_bunker_y > horizon:
		# Positions that coincide with a gate row are handled by the gate arena.
		var idx: int = absi(_next_bunker_y / (500 * F_ONE))
		if idx % 2 == 1:
			var flank := (idx / 2) % 2
			bunkers.append(_make_bunker((120 if flank == 0 else 460) * F_ONE, _next_bunker_y))
		_next_bunker_y -= 500 * F_ONE
	# Stream landmines between the arenas — deterministic x, off the gate rows.
	while _next_mine_y > horizon:
		if absi(_next_mine_y / MINE_SPACING) % 2 == 0:
			mines.append({"x": rng.range_i(70, 570) * F_ONE, "y": _next_mine_y, "armed": true})
		_next_mine_y -= MINE_SPACING
	while _next_gate_y > horizon and not _world_ended:
		_gate_counter += 1
		if _gate_counter == FINAL_GATE_INDEX:
			# The end of the road: the Foundry. Nothing streams past it.
			gates.append({"y": _next_gate_y, "open": false, "b1": {}, "b2": {},
				"boss": {}, "final": true})
			_world_ended = true
			break
		if _gate_counter % BOSS_GATE_EVERY == 0:
			# Bridge boss gate: no arena bunkers — the Gunship IS the lock.
			gates.append({"y": _next_gate_y, "open": false, "b1": {}, "b2": {},
				"boss": {"alive": true, "hp": BOSS_HP, "x": SCREEN_CX,
					"dir": 1, "phase_t": 0, "gate_y": _next_gate_y}})
		else:
			var b1 := _make_bunker(180 * F_ONE, _next_gate_y + 50 * F_ONE)
			var b2 := _make_bunker(412 * F_ONE, _next_gate_y + 50 * F_ONE)
			bunkers.append(b1)
			bunkers.append(b2)
			gates.append({"y": _next_gate_y, "open": false, "b1": b1, "b2": b2, "boss": {}})
		_next_gate_y -= GATE_SPACING
	while _next_tank_y > horizon:
		tanks.append({
			"x": SCREEN_CX, "y": _next_tank_y,
			"alive": true, "burning": false,
			"fuel": TANK_FUEL_TICKS, "burn_ticks": 0,
			"fire_cd": 0, "occupant": -1,
		})
		_next_tank_y -= GATE_SPACING
	while _next_water_y > horizon:
		var water := {"y": _next_water_y, "ford_x": rng.range_i(80, 560) * F_ONE}
		waters.append(water)
		# Frogmen lurk in every river.
		for f in 3:
			_spawn_frogman(rng.range_i(40, 600) * F_ONE, _next_water_y + rng.range_i(10, 70) * F_ONE)
		_next_water_y -= GATE_SPACING


func _make_bunker(x: int, y: int) -> Dictionary:
	return {"x": x, "y": y, "alive": true, "spawn_cd": BUNKER_SPAWN_INTERVAL_TICKS}


# --- Endless War (roguelite survival mode) ---

func _step_waves() -> void:
	if intermission_ticks > 0:
		intermission_ticks -= 1
		if intermission_ticks == 0:
			# Unbought shop stock is packed up when the next wave lands.
			for k in range(pickups.size() - 1, -1, -1):
				if pickups[k].get("cost", 0) > 0:
					pickups.remove_at(k)
			_start_wave()
		return
	if wave == 0:
		_start_wave()
		return
	# Trickle the wave in from the top edge. Deeper waves spawn FASTER (down
	# to 8 ticks) and pack more elites (every 4th → every 2nd by wave 10) so
	# threat scales, not just raw count. (Endless-only; campaign torture never
	# reaches here, so campaign goldens are unaffected.)
	if wave_pending > 0:
		wave_spawn_cd -= 1
		if wave_spawn_cd <= 0 and enemies.size() < MAX_ENEMIES:
			var interval := maxi(8, WAVE_SPAWN_INTERVAL_TICKS - wave)
			if wave_mod == 1:   # Blitz: spawns pour in twice as fast
				interval = maxi(4, interval / 2)
			wave_spawn_cd = interval
			wave_pending -= 1
			var x := rng.range_i(24, 616) * F_ONE
			var elite_every: int = maxi(2, 4 - wave / 5)
			var is_elite: bool = wave_mod == 2 or (wave_pending % elite_every) == 0
			# From wave 3, some ranged spawns become grenadiers/snipers so the
			# threat vector varies (Blitz/wave1-2 stay pure rushers/elites).
			if wave >= 3 and is_elite and wave_mod != 1:
				var roll := rng.range_i(0, 6)
				if roll == 0:
					_spawn_special(x, camera_top - 24 * F_ONE, "grenadier")
				elif roll == 1:
					_spawn_special(x, camera_top - 24 * F_ONE, "sniper")
				elif roll == 2:
					_spawn_special(x, camera_top - 24 * F_ONE, "shield")
				elif roll == 3:
					_spawn_special(x, camera_top - 24 * F_ONE, "sapper")
				elif roll == 4:
					_spawn_special(x, camera_top - 24 * F_ONE, "ghillie")
				else:
					_spawn_enemy(x, camera_top - 24 * F_ONE, true)
			else:
				_spawn_enemy(x, camera_top - 24 * F_ONE, is_elite)
	elif enemies.is_empty() and (endless_boss.is_empty() or not endless_boss["alive"]):
		# Wave cleared: open the shop for the intermission (a live miniboss holds it).
		intermission_ticks = WAVE_INTERMISSION_TICKS
		events.append({"t": "wave_clear", "x": 320 * F_ONE, "y": camera_top + 180 * F_ONE})
		# Clean Wave: endless's answer to the campaign's Flawless Gate — no deaths
		# this wave pays a bonus, so cautious and reckless play stop earning alike.
		if deaths_this_wave == 0 and wave > 1:
			war_chest += 40
			score += 1500
			events.append({"t": "wave_flawless", "x": 320 * F_ONE, "y": camera_top + 150 * F_ONE})
		var shop_y: int = camera_top + 120 * F_ONE
		# Shuffle the crate→slot mapping each wave so the shop stays a live read
		# (far-left ≠ always ammo), Fisher-Yates on the seeded SimRng.
		var kinds := [0, 1, 2, 3]
		for si in range(3, 0, -1):
			var sj := rng.range_i(0, si)
			var tmp: int = kinds[si]
			kinds[si] = kinds[sj]
			kinds[sj] = tmp
		var xs := [170, 290, 410, 530]
		for ci in 4:
			pickups.append({"x": xs[ci] * F_ONE, "y": shop_y, "kind": kinds[ci],
				"cost": _supply_cost(kinds[ci])})


func _start_wave() -> void:
	wave += 1
	wave_pending = WAVE_BASE_ENEMIES + WAVE_ENEMIES_PER_WAVE * (wave - 1)
	wave_spawn_cd = 1
	deaths_this_wave = 0
	if wave >= 3 and rng.range_i(0, 2) == 0:
		_spawn_courier()   # ~1-in-3 waves field a fleeing bounty runner
	# Wave mutators give each wave an identity (and make the shop a counter-
	# pick). None on the first two waves; then roll one. Endless-only.
	# 4 = PAYDAY (double coin, no extra threat) — a go-big economy beat.
	# 5 = NIGHT OPS (vision tightens; view only). 6 = FRENZY (swarm +40% speed).
	wave_mod = 0 if wave <= 2 else rng.range_i(0, 6)
	if wave_mod == 3:
		# Spotter wave: a Mortar Observer joins the fray.
		observer = {
			"x": rng.range_i(60, 580) * F_ONE,
			"strike_cd": OBSERVER_STRIKE_CD_TICKS,
			"spawn_cam": camera_top,
		}
		events.append({"t": "observer_spawn", "x": observer["x"], "y": camera_top + OBSERVER_Y_OFFSET})
	if wave % 5 == 0:
		# Milestone miniboss: a Bridge Gunship parked over the arena, HP scaling
		# with depth. Reuses the campaign boss schema + state machine wholesale.
		endless_boss = {"alive": true, "hp": BOSS_HP + (wave / 5 - 1) * (BOSS_HP / 2),
			"x": SCREEN_CX, "dir": 1, "phase_t": 0, "gate_y": camera_top + 90 * F_ONE}
		events.append({"t": "endless_boss", "x": SCREEN_CX, "y": camera_top + 50 * F_ONE})
	events.append({"t": "wave_start", "x": SCREEN_CX, "y": camera_top + 40 * F_ONE, "mod": wave_mod})


# --- Foundry Colossus (the finale) ---

func colossus_phase() -> int:
	## 1..3 by HP thirds; 0 when absent.
	if colossus.is_empty() or not colossus["alive"]:
		return 0
	var hp: int = colossus["hp"]
	if hp > (COLOSSUS_HP * 2) / 3:
		return 1
	if hp > COLOSSUS_HP / 3:
		return 2
	return 3


func _step_colossus() -> void:
	# Engage when the final gate scrolls into view.
	if colossus.is_empty():
		for g in gates:
			if g.get("final", false) and g["y"] >= camera_top and g["y"] <= camera_top + VIEW_H and not victory:
				colossus = {
					"alive": true, "hp": COLOSSUS_HP,
					"x": SCREEN_CX, "y": g["y"] - 120 * F_ONE,
					"spray_cd": COLOSSUS_SPRAY_CD_TICKS,
					"volley_cd": COLOSSUS_VOLLEY_CD_TICKS,
					"spawn_cd": COLOSSUS_SPAWN_CD_TICKS,
					"core_cd": COLOSSUS_CORE_CYCLE_TICKS, "core_open": 0,
				}
				last_stand = true
				events.append({"t": "colossus_engage", "x": colossus["x"], "y": colossus["y"]})
				break
		return
	if not colossus["alive"]:
		return
	var target := _nearest_alive_player(colossus["x"], colossus["y"])
	if target.is_empty():
		return
	var phase := colossus_phase()

	# The scroll inverts: the fortress advances DOWN the map at the players.
	var descent: int = COLOSSUS_SPEED * (2 if phase == 3 else 1)
	if colossus["y"] < target["y"] - 60 * F_ONE:
		colossus["y"] = colossus["y"] + descent
	var dx: int = target["x"] - colossus["x"]
	colossus["x"] = colossus["x"] + clampi(dx, -COLOSSUS_SPEED, COLOSSUS_SPEED)

	# Core window cycle: plating retracts (core_open ticks) then re-seals.
	if colossus["core_open"] > 0:
		colossus["core_open"] = colossus["core_open"] - 1
		if colossus["core_open"] == 0:
			colossus["core_cd"] = COLOSSUS_CORE_CYCLE_TICKS
	else:
		colossus["core_cd"] = colossus["core_cd"] - 1
		if colossus["core_cd"] <= 0:
			colossus["core_open"] = COLOSSUS_CORE_OPEN_TICKS
			events.append({"t": "core_open", "x": colossus["x"], "y": colossus["y"]})

	# Phase 1+: turret spray. Phase 2+: mortar volleys. Phase 3: sapper drops.
	colossus["spray_cd"] = colossus["spray_cd"] - 1
	if colossus["spray_cd"] <= 0:
		colossus["spray_cd"] = COLOSSUS_SPRAY_CD_TICKS
		events.append({"t": "enemy_shot", "x": colossus["x"], "y": colossus["y"]})
		for spread in [-64, 0, 64]:
			var bx: int = target["x"] - colossus["x"] + spread * F_ONE / 4
			var by: int = target["y"] - colossus["y"]
			var blen := Fixed.length(bx, by)
			if blen > F_ONE:
				_spawn_enemy_bullet(colossus["x"], colossus["y"], bx, by, blen)
	if phase >= 2:
		colossus["volley_cd"] = colossus["volley_cd"] - 1
		if colossus["volley_cd"] <= 0:
			colossus["volley_cd"] = COLOSSUS_VOLLEY_CD_TICKS
			_add_strike(target["x"], target["y"])
	if phase == 3:
		colossus["spawn_cd"] = colossus["spawn_cd"] - 1
		if colossus["spawn_cd"] <= 0 and enemies.size() < MAX_ENEMIES:
			colossus["spawn_cd"] = COLOSSUS_SPAWN_CD_TICKS
			_spawn_enemy(colossus["x"], colossus["y"] + 30 * F_ONE, false)

	# Treads: contact with the crawler is death (vest rules apply).
	for p in players:
		if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
				and _dist_lte(colossus["x"], colossus["y"], p["x"], p["y"], COLOSSUS_CRUSH_RADIUS):
			_hurt_player(p)

	# Supply drops keep the grenade economy alive during the siege.
	_supply_cd -= 1
	if _supply_cd <= 0:
		_supply_cd = SUPPLY_DROP_INTERVAL_TICKS
		pickups.append({"x": rng.range_i(60, 580) * F_ONE, "y": camera_top + rng.range_i(200, 320) * F_ONE, "kind": 1})


func _damage_colossus(amount: int) -> void:
	if colossus.is_empty() or not colossus["alive"]:
		return
	colossus["hp"] = colossus["hp"] - amount
	if colossus["hp"] <= 0:
		colossus["alive"] = false
		victory = true
		events.append({"t": "explosion", "x": colossus["x"], "y": colossus["y"]})
		events.append({"t": "victory", "x": colossus["x"], "y": colossus["y"]})
		# Last Stand payout: the unspent War Chest converts to score.
		score += war_chest * 10 + 5000
		war_chest = 0
		for g in gates:
			if g.get("final", false):
				g["open"] = true
				last_gate_y = g["y"]


# --- Bridge Gunship boss ---

func _step_boss() -> void:
	for g in gates:
		if g["open"] or g["boss"].is_empty() or not g["boss"]["alive"]:
			continue
		# Engage only while the bridge is in view.
		if g["y"] < camera_top or g["y"] > camera_top + VIEW_H:
			continue
		_step_one_boss(g["boss"])


func _step_one_boss(boss: Dictionary) -> void:
	boss["phase_t"] = (boss["phase_t"] + 1) % BOSS_CYCLE_TICKS
	var t: int = boss["phase_t"]
	if t < BOSS_CYCLE_TICKS / 2:
		# Strafe run: sweep the bridge, spraying aimed-with-spread fire.
		boss["x"] = boss["x"] + BOSS_SPEED * boss["dir"]
		if boss["x"] < 60 * F_ONE or boss["x"] > 580 * F_ONE:
			boss["dir"] = -boss["dir"]
			boss["x"] = clampi(boss["x"], 60 * F_ONE, 580 * F_ONE)
		if t % BOSS_SPRAY_INTERVAL_TICKS == 0:
			var by: int = boss["gate_y"] - BOSS_Y_OFFSET
			var target := _nearest_alive_player(boss["x"], by)
			if not target.is_empty():
				var dx: int = target["x"] - boss["x"] + rng.range_i(-40, 40) * F_ONE
				var dy: int = target["y"] - by
				var dlen := Fixed.length(dx, dy)
				if dlen > F_ONE:
					events.append({"t": "enemy_shot", "x": boss["x"], "y": by})
					_spawn_enemy_bullet(boss["x"], by, dx, dy, dlen)
	else:
		# Mortar volley: three tracked strikes, reusing the Observer machinery.
		if t in BOSS_MORTAR_TICKS:
			var by2: int = boss["gate_y"] - BOSS_Y_OFFSET
			var target2 := _nearest_alive_player(boss["x"], by2)
			if not target2.is_empty():
				_add_strike(target2["x"], target2["y"])


func _bullet_hits_boss(b: Dictionary) -> bool:
	for g in gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		var boss: Dictionary = g["boss"]
		if _dist_lte(b["x"], b["y"], boss["x"], boss["gate_y"] - BOSS_Y_OFFSET, BOSS_HIT_RADIUS):
			events.append({"t": "boss_hit", "x": b["x"], "y": b["y"]})
			_damage_boss(boss, 1)
			return true
	if not endless_boss.is_empty() and endless_boss["alive"] \
			and _dist_lte(b["x"], b["y"], endless_boss["x"], endless_boss["gate_y"] - BOSS_Y_OFFSET, BOSS_HIT_RADIUS):
		events.append({"t": "boss_hit", "x": b["x"], "y": b["y"]})
		_damage_boss(endless_boss, 1)
		return true
	return false


func _damage_boss(boss: Dictionary, amount: int) -> void:
	boss["hp"] = boss["hp"] - amount
	if boss["hp"] <= 0 and boss["alive"]:
		boss["alive"] = false
		war_chest += BOSS_BOUNTY
		score += BOSS_BOUNTY * 10
		var by: int = boss["gate_y"] - BOSS_Y_OFFSET
		events.append({"t": "explosion", "x": boss["x"], "y": by})
		events.append({"t": "kill", "x": boss["x"], "y": by, "coin": BOSS_BOUNTY, "kind": "boss"})


func _step_enemy_bullets() -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b := enemy_bullets[i]
		b["x"] = b["x"] + b["vx"]
		b["y"] = b["y"] + b["vy"]
		b["ttl"] = b["ttl"] - 1
		var dead: bool = b["ttl"] <= 0 or _offscreen(b["x"], b["y"])
		if not dead:
			# Cover is real both ways now: a bunker between you and a shooter eats
			# the round, same as it eats yours (player bullets already block here).
			for bk in bunkers:
				if bk["alive"] and _point_in_aabb(b["x"], b["y"], bk):
					events.append({"t": "armor_block", "x": b["x"], "y": b["y"]})
					dead = true
					break
		if not dead:
			for p in players:
				if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
						and _dist_lte(b["x"], b["y"], p["x"], p["y"], ENEMY_BULLET_HIT_RADIUS):
					_hurt_player(p)
					dead = true
					break
		if dead:
			enemy_bullets.remove_at(i)


func _add_strike(x: int, y: int) -> void:
	## Every tracked mortar strike funnels here so the view/audio get one
	## consistent "incoming" warning event alongside the telegraph state.
	strikes.append({"x": x, "y": y, "ticks": STRIKE_TELEGRAPH_TICKS})
	events.append({"t": "strike_warn", "x": x, "y": y})


# --- Mortar Observer ---

func _step_observer() -> void:
	# Stall detection runs after the camera step: no advance this tick = stall.
	var any_alive := false
	for p in players:
		if p["alive"]:
			any_alive = true
			break
	if camera_top < _prev_camera_top:
		stall_ticks = 0
	elif any_alive:
		stall_ticks += 1

	if observer.is_empty():
		if stall_ticks >= OBSERVER_STALL_TICKS:
			observer = {
				"x": rng.range_i(60, 580) * F_ONE,
				"strike_cd": OBSERVER_STRIKE_CD_TICKS,
				"spawn_cam": camera_top,
			}
			events.append({"t": "observer_spawn", "x": observer["x"],
				"y": camera_top + OBSERVER_Y_OFFSET})
	else:
		# Pushing well past the observer despawns him (pressure released).
		if camera_top < observer["spawn_cam"] - OBSERVER_DESPAWN_ADVANCE:
			observer = {}
			strikes.clear()
			stall_ticks = 0
		else:
			observer["strike_cd"] = observer["strike_cd"] - 1
			if observer["strike_cd"] <= 0:
				observer["strike_cd"] = OBSERVER_STRIKE_CD_TICKS
				var target := _nearest_alive_player(observer["x"], camera_top + OBSERVER_Y_OFFSET)
				if not target.is_empty():
					_add_strike(target["x"], target["y"])
	# NOTE: strike resolution is NOT here — step() calls _resolve_strikes()
	# once per tick for both modes. (Calling it here too double-decremented
	# every strike, halving its telegraph window; fixed iter 28.)


func _resolve_strikes() -> void:
	# Resolve telegraphed strikes: lethal to players (roll i-frames dodge it),
	# ignites tanks, harmless to enemy infantry. Extracted from _step_observer
	# so it also runs in endless (where the observer step is conditional) —
	# otherwise grenadier lobs never detonate and pile up.
	for i in range(strikes.size() - 1, -1, -1):
		var s := strikes[i]
		s["ticks"] = s["ticks"] - 1
		if s["ticks"] > 0:
			continue
		events.append({"t": "explosion", "x": s["x"], "y": s["y"]})
		for p in players:
			if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
					and _dist_lte(s["x"], s["y"], p["x"], p["y"], GRENADE_RADIUS):
				_hurt_player(p)
		for tank in tanks:
			if tank["alive"] and _dist_lte(s["x"], s["y"], tank["x"], tank["y"], GRENADE_RADIUS):
				_ignite_tank(tank)
		strikes.remove_at(i)


func _kill_observer() -> void:
	events.append({"t": "kill", "x": observer["x"], "y": camera_top + OBSERVER_Y_OFFSET,
		"coin": COIN_ELITE * 2, "kind": "observer"})
	war_chest += COIN_ELITE * 2
	score += COIN_ELITE * 20
	observer = {}
	strikes.clear()
	stall_ticks = 0


# --- Geometry helpers ---

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
	## (Transient view `events` are intentionally excluded.)
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
	h = feed.call(last_gate_y, h)
	h = feed.call(stall_ticks, h)
	h = feed.call(_spawn_grace, h)
	h = feed.call(kill_streak, h)
	h = feed.call(kill_streak_timer, h)
	h = feed.call(deaths_since_gate, h)
	h = feed.call(flawless_streak, h)
	h = feed.call(deaths_this_wave, h)
	h = feed.call(1 if mode == "endless" else 0, h)
	h = feed.call(wave, h)
	h = feed.call(wave_pending, h)
	if mode == "endless":
		h = feed.call(wave_mod, h)   # endless-only: campaign checksums unchanged
	h = feed.call(intermission_ticks, h)
	h = feed.call(pending_airstrike, h)
	h = feed.call(int(last_stand), h)
	h = feed.call(int(wiped), h)
	h = feed.call(int(victory), h)
	if assist_mode:
		h = feed.call(2166136261, h)   # only perturbs the hash when assist is ON (torture: OFF)
	if hard:
		h = feed.call(40503, h)        # only perturbs the hash when HARD is ON (torture: OFF)
	if not colossus.is_empty():
		for v in [colossus["hp"], colossus["x"], colossus["y"], int(colossus["alive"]),
				colossus.get("core_open", 0), colossus.get("core_cd", 0)]:
			h = feed.call(v, h)
	for s in [rng._s0, rng._s1, rng._s2, rng._s3]:
		h = feed.call(s, h)
	for p in players:
		for v in [p["x"], p["y"], int(p["alive"]), p["deaths"], p["mg_ammo"], p["grenade_ammo"],
				p["fire_cd"], p["broke_timer"], p["roll_ticks"], p["roll_cd"], p["roll_buf"],
				p["boost_ticks"], p["in_tank"], int(p["vest"]), p["hurt_iframes"], p["pierce_ticks"], p["spread_ticks"]]:
			h = feed.call(v, h)
	for arrs: Array in [bullets, grenades, enemies, bunkers, pickups, strikes, enemy_bullets, waters]:
		h = feed.call(arrs.size(), h)
		for d: Dictionary in arrs:
			h = feed.call(d.get("x", 0), h)
			h = feed.call(d.get("y", 0), h)
	for e in enemies:
		h = feed.call(int(e.get("submerged", false)), h)
		h = feed.call(e.get("lunge_ticks", 0), h)
		h = feed.call(e.get("surface_ticks", 0), h)
		h = feed.call(e.get("fire_cd", 0), h)
		h = feed.call(e.get("windup", 0), h)
		h = feed.call(e.get("aim_lx", 0), h)
		h = feed.call(e.get("aim_ly", 0), h)
		h = feed.call(int(e.get("marked", false)), h)
	for pk in pickups:
		h = feed.call(pk["kind"], h)
		h = feed.call(pk.get("cost", 0), h)
	for w in waters:
		h = feed.call(w["ford_x"], h)
	h = feed.call(mines.size(), h)
	for m in mines:
		h = feed.call(m["x"], h)
		h = feed.call(m["y"], h)
		h = feed.call(int(m["armed"]), h)
	h = feed.call(tanks.size(), h)
	for t in tanks:
		for v in [t["x"], t["y"], int(t["alive"]), int(t["burning"]), t["fuel"], t["burn_ticks"], t["occupant"]]:
			h = feed.call(v, h)
	h = feed.call(gates.size(), h)
	for g in gates:
		h = feed.call(g["y"], h)
		h = feed.call(int(g["open"]), h)
		if not g["boss"].is_empty():
			for v in [g["boss"]["hp"], g["boss"]["x"], int(g["boss"]["alive"]), g["boss"]["phase_t"], g["boss"]["dir"]]:
				h = feed.call(v, h)
	if not observer.is_empty():
		h = feed.call(observer["x"], h)
		h = feed.call(observer["strike_cd"], h)
	if not endless_boss.is_empty():
		for v in [endless_boss["hp"], endless_boss["x"], int(endless_boss["alive"]),
				endless_boss["phase_t"], endless_boss["dir"]]:
			h = feed.call(v, h)
	return h
