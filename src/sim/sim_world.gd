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
const SPREAD2_COS := 59876  # cos(24°) * F_ONE — outer pair for the Triple+Spread 5-fan
const SPREAD2_SIN := 26657  # sin(24°) * F_ONE
# Rend Rounds power-up: a timed buff that lets MG bullets punch THROUGH a
# shieldman's front-arc block — the shield archetype's missing item counter.
const REND_TICKS := 480
# Player Claymore: a carried charge (capped) planted with INTERACT on foot away
# from any tank. Reuses the landmine array wholesale — it hurts both sides.
const CLAYMORE_CAP := 3
const CLAYMORE_PLANT_OFFSET := 20 * F_ONE   # behind the aim, outside its own trigger radius
# Smoke capsule: personal concealment — while active NO enemy AI can target you
# (one guard in _nearest_alive_player covers every ranged/mortar/chase caller).
const SMOKE_TICKS := 300
# Flashbang capsule: stuns the whole field roster (enemies array only — bosses,
# the observer and the colossus shrug it off) for 1.5 s.
const FLASH_STUN_TICKS := 90
# Recon Drone (endless-only): a flying spotter that holds a standoff hover and
# paints tracked mortar strikes on your CURRENT ground. Flying: never water-
# slowed, but bullets still swat it. Reuses fire_cd/windup — no new hashed field.
const DRONE_STANDOFF := 130 * F_ONE
const DRONE_SPEED := 2 * F_ONE
# Cadence tightened from 140/45: paint(45t) + strike telegraph(45t) double-tell
# every 2.3s was ignorable clutter. Keep a SHORT paint (feeds the off-screen
# threat pip + fairness) but let the strike ring be the main dodge window.
# Starting values; test: a hovering drone must restrict player footing — if
# players still ignore it, lower fire_cd toward 80.
const DRONE_FIRE_CD_TICKS := 100
const DRONE_WINDUP_TICKS := 24
# Technical raider (endless-only): the fastest thing on the field. Revs in
# place, LOCKS a charge line at your position, then barrels down it — it
# cannot steer mid-charge, so repositioning off the line is the dodge. One
# round kills it (fragile). Starting values; test: a strafing player at
# 100px+ must dodge every charge — if charges land on movers, widen REV_TICKS.
const TECHNICAL_SPEED := 3 * F_ONE            # player is 2.4 px/t — it outruns you on a straight
const TECHNICAL_REV_TICKS := 18               # rev tell, cut from 30: a lock landing 80t before
	# impact let a 2.4px/t strafer clear the point with a 4-tick nudge. Starting
	# value; test: a late-reacting strafer eats ~2/10 charges — widen toward 24
	# if first contact feels unreactable (the sighting card teaches the rule).
const TECHNICAL_CHARGE_TICKS := 50            # one charge = ~150px of travel
const TECHNICAL_LOCK_CD_TICKS := 70           # pause between charges (the dodge rhythm)
const TECHNICAL_HP := 3                       # a truck is not a paper target (nest precedent)
# Downed Pilot ransom: a dead gunship's pilot punches out at the crash site and
# staggers for the enemy line at the TOP edge. TOUCH him to rescue (+ransom);
# let him cross the edge and he's captured. Shooting him pays NOTHING.
# 1.4px/t (0.58x player): at 0.8 the rescue was a ~100% grab — he ejects at the
# crash site you already stand on (the courier, this file's "real chase"
# benchmark, runs 0.9x player). Starting value; test: mid-arena catch rate
# should land 50-70% — at ~100% raise again, below 50% drop toward 1.1.
const PILOT_SPEED := (F_ONE * 7) / 5
const PILOT_RANSOM := COIN_ELITE * 4          # courier-bounty parity (the same "worth the chase")
# Punch-out grace: the pilot spawns unshootable (and unrescuable) for one
# reaction window, because he appears ON the boss the player is still firing
# at — trigger inertia gunned him down before the RESCUE banner even existed.
# Starting value 36t (0.6s); test: a bot holding fire through 10 boss kills
# must leave the pilot rescuable ≥9/10 — raise by 12t increments if not.
const PILOT_PUNCHOUT_TICKS := 36
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
const BARREL_SPACING := 420 * F_ONE
const BARREL_CLUSTER_GAP := 18 * F_ONE
const BARREL_FUSE_TICKS := 8         # chained barrels cook this long before detonating (rollable ripple)
const MG_NEST_AIM_TICKS := 30       # telegraph before the first round of a burst
const MG_NEST_BURST_GAP_TICKS := 8  # spacing between the 3 rounds
const MG_NEST_BURST_ROUNDS := 3
const MG_NEST_BURST_CD_TICKS := 90  # reload between bursts
const BULLET_HIT_RADIUS := 9 * F_ONE
const BROADCAST_HP := 5                       # starting value: outlasts a 3-round burst, a grenade still one-shots (nest grammar)
const BROADCAST_AURA_RADIUS := 140 * F_ONE    # starting value ~half a screen — rusher inside must visibly outpace one outside
const BROADCAST_PULSE_TICKS := 90             # view metronome only (rides hashed fire_cd)
const PICKUP_RADIUS := 12 * F_ONE
const MG_AMMO_MAX := 99
const GRENADE_AMMO_MAX := 12
const SPAWN_INTERVAL_TICKS := 45
const BUNKER_SPAWN_INTERVAL_TICKS := 120
const MAX_ENEMIES := 64
const REVIVE_BASE_COST := 50
const BROKE_RESPAWN_TICKS := 300
const COIN_RUSHER := 10
const COIN_MG_NEST := 15   # stationary/telegraphed: pays less than a mobile elite
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
const SHOP_SANDBAG_COST := 40        # starting value (grenade 30 < bag < vest 60); test: a scripted endless bot should buy 1-3/run
const SANDBAG_FIELD_CAP := 6         # starting value: 6 x 36px = 216px can never wall the ~592px lane
const SANDBAG_HALF_W := 18 * F_ONE   # segment is 36x10 px — rushers must flank in under ~2s
const SANDBAG_HALF_H := 5 * F_ONE
const SUPPLY_COSTS: Array[int] = [SHOP_AMMO_COST, SHOP_GRENADE_COST, SHOP_VEST_COST, SHOP_AIRSTRIKE_COST, SHOP_SANDBAG_COST]
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
var sandbags: Array[Dictionary] = []   # player-authored cover (wheel-only; dead bags are erased on the spot)
var barrels: Array[Dictionary] = []
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
var flash_ticks: int = 0           # flashbang stun: field enemies skip their step while > 0
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
var _next_barrel_y: int = 0
var _gate_counter: int = 0
var _broadcasts: Array = []        # per-tick cache of live rally masts (derived, rebuilt in _step_enemies, never hashed)
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
	_next_barrel_y = -(900 * F_ONE)
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
			"grenade_prev": false,
			"vest": false,
			"hurt_iframes": 0,
			"pierce_ticks": 0,
			"spread_ticks": 0,
			"rend_ticks": 0,
			"smoke_ticks": 0,
			"claymores": 0,
			"triple": false,
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
	# Flashbang stun runs down AFTER the enemy step, so a fresh bang buys the
	# full window (the collecting tick already skipped their step).
	if flash_ticks > 0:
		flash_ticks -= 1
		if flash_ticks == 20:
			# Wake-up warning ~0.33s out so the stun window closing never
			# blindsides (starting value; if the resume still surprises in
			# playtest, raise by 10t). Event only — checksum-excluded.
			events.append({"t": "flash_recover", "x": SCREEN_CX, "y": camera_top + 180 * F_ONE})
	# A called airstrike resolves after its telegraph window (enemies keep acting
	# through it — the buyer commits before seeing the result).
	if pending_airstrike > 0:
		pending_airstrike -= 1
		if pending_airstrike == 0:
			_fire_mission()
	_step_bunkers()
	if mode == "endless":
		_step_waves()
		# Sappers are ENDLESS-ONLY, but _step_mines() (the only code that detonates or
		# culls a laid mine) ran only in the campaign branch — so every mine a Sapper
		# armed here just sat forever, inert. Step them here too.
		_step_mines()
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
		_step_barrels()
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
		p["rend_ticks"] = maxi(0, p["rend_ticks"] - 1)
		p["smoke_ticks"] = maxi(0, p["smoke_ticks"] - 1)
		p["roll_iframe"] = false
		var interact_edge: bool = inp.interact and not p["interact_prev"]
		p["interact_prev"] = inp.interact
		var buy_edge: bool = inp.buy > 0 and p["buy_prev"] == 0
		p["buy_prev"] = inp.buy
		var grenade_edge: bool = inp.grenade and not p["grenade_prev"]
		p["grenade_prev"] = inp.grenade

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
		if p["roll_buf"] > 0 and p["roll_cd"] == 0 and p["roll_ticks"] == 0 and not wading:
			p["roll_buf"] = 0
			p["roll_ticks"] = ROLL_TICKS
			p["roll_cd"] = ROLL_CD_TICKS
			# Stationary panic-roll: with the move stick neutral, dodge along the
			# aim vector (always a unit vector) so a standing aim-spray can still
			# bail from a closing rusher.
			if moving:
				p["roll_dx"] = Fixed.div(mx, mlen)
				p["roll_dy"] = Fixed.div(my, mlen)
			else:
				p["roll_dx"] = p["aim_x"]
				p["roll_dy"] = p["aim_y"]
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
			if p["spread_ticks"] > 0 or p["triple"]:
				# Trench Gun (timed) / Triple Shot (permanent mod) both spray this one
				# fan: two extra pellets +/-12 deg off the aim (fixed-point rotate).
				_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD_COS) - Fixed.mul(fay, SPREAD_SIN),
					Fixed.mul(fax, SPREAD_SIN) + Fixed.mul(fay, SPREAD_COS))
				_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD_COS) + Fixed.mul(fay, SPREAD_SIN),
					Fixed.mul(fay, SPREAD_COS) - Fixed.mul(fax, SPREAD_SIN))
				if p["spread_ticks"] > 0 and p["triple"]:
					# Both active: a real burst-DPS spike — add an outer +/-24 deg pair
					# so stacking Spread onto Triple is a 5-pellet fan, not a no-op.
					_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD2_COS) - Fixed.mul(fay, SPREAD2_SIN),
						Fixed.mul(fax, SPREAD2_SIN) + Fixed.mul(fay, SPREAD2_COS))
					_spawn_mg_bullet(p, i, Fixed.mul(fax, SPREAD2_COS) + Fixed.mul(fay, SPREAD2_SIN),
						Fixed.mul(fay, SPREAD2_COS) - Fixed.mul(fax, SPREAD2_SIN))

		if grenade_edge and p["grenade_cd"] == 0 and p["grenade_ammo"] > 0:
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

		if interact_edge and not _try_board_tank(i, p) and p["claymores"] > 0 \
				and not _boardable_tank_near(p):
			# Claymore: no tank in reach, so INTERACT plants a carried charge one
			# step ALONG the aim — into the enemy lane you're already shooting,
			# clear of your own kiting path (planting behind the aim dropped it
			# straight into the retreat line: ~5 ticks from a self-kill at full
			# backpedal). Still outside its own 9px trigger. It joins mines[]
			# wholesale — armed instantly, and it hurts both sides (1986 grammar).
			p["claymores"] = p["claymores"] - 1
			var cmx: int = p["x"] + Fixed.mul(p["aim_x"], CLAYMORE_PLANT_OFFSET)
			var cmy: int = p["y"] + Fixed.mul(p["aim_y"], CLAYMORE_PLANT_OFFSET)
			# `friendly` is view-only identity (yours vs the sapper's) — same
			# trigger, same blast, NOT hashed (see test_checksum_coverage).
			mines.append({"x": cmx, "y": cmy, "armed": true, "friendly": true})
			events.append({"t": "claymore_plant", "x": cmx, "y": cmy, "i": i})

		# The rescue touch ignores roll i-frames — i-frames stop contact DEATH,
		# not a friendly grab (rolling through fire onto the pilot is the
		# natural approach; gating it made the intuitive input do nothing).
		# The punch-out grace (submerged) must elapse first. Tank treads
		# rescue in _step_tank.
		for e in enemies:
			# Same axis pre-reject + truncation proof as the bullet scan (:1007):
			# |dx| > r means _dist_lte was already false — checksum-neutral.
			if absi(p["x"] - e["x"]) > ENEMY_TOUCH_RADIUS:
				continue
			if e["alive"] and e["kind"] == "pilot" and not e.get("submerged", false) \
					and _dist_lte(p["x"], p["y"], e["x"], e["y"], ENEMY_TOUCH_RADIUS):
				_rescue_pilot(e)

		# Contact with any enemy = one-hit death (roll i-frames protect;
		# submerged frogmen must surface before they can strike).
		if not p["roll_iframe"] and p["in_tank"] < 0:
			for e in enemies:
				if absi(p["x"] - e["x"]) > ENEMY_TOUCH_RADIUS:
					continue
				if not _enemy_strikeable(e) or e["kind"] == "courier" or e["kind"] == "pilot" \
						or not _dist_lte(p["x"], p["y"], e["x"], e["y"], ENEMY_TOUCH_RADIUS):
					continue
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
		# Same score credit as the spend-wheel buy: a priced ground crate must not
		# silently lose score vs an identical wheel purchase (the _try_buy invariant).
		if cost > 0:
			score += cost * 10
		# Claymore capsule grabbed at the 3-charge cap grants nothing (mini()
		# eats it) — flag the event so the view can stop paying the celebratory
		# callout for a no-op. Events are checksum-excluded: golden-safe.
		var full: bool = pk["kind"] == 8 and p["claymores"] >= CLAYMORE_CAP
		_apply_supply(p, pk["kind"])
		events.append({"t": "pickup", "x": pk["x"], "y": pk["y"],
			"kind": pk["kind"], "cost": cost, "full": full})
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
	if reviver_index == -1:
		# Dead self-revive is the solo/all-down fallback ONLY: with a partner
		# still standing, the rescue is theirs to perform — the co-op decision
		# (walk to the body, spend together) must not be mashable from the floor.
		for pl in players:
			if pl["alive"]:
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
				# One 'can't afford it' cue on the first denial (not per-mash) — a
				# denied revive was as silent as a denied buy is loud. Event only,
				# checksum-excluded, so golden-safe.
				events.append({"t": "revive_deny", "x": target["x"], "y": target["y"]})


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
	p["rend_ticks"] = 0               # ...and Rend Rounds
	p["smoke_ticks"] = 0              # ...and the smoke concealment
	p["claymores"] = 0                # ...and any carried claymore charges
	p["triple"] = false               # ...and the Triple Shot permanent mod
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
	# Death strips Triple/Pierce/Spread (see _respawn); flag it on the (checksum-
	# excluded) event so the view can sting a "LOADOUT LOST" beat. Golden-safe.
	events.append({"t": "player_down", "x": p["x"], "y": p["y"], "p": p["idx"],
		"triple": p["triple"], "pierce": p["pierce_ticks"] > 0, "spread": p["spread_ticks"] > 0})
	# Arm the broke fallback on death itself, not only on a revive press: the
	# wipe (endless's only run-ender) must not require a button press.
	if war_chest < revive_cost(p):
		p["broke_timer"] = BROKE_RESPAWN_TICKS


func _fire_mission() -> void:
	## The screen-clear: wipes every surfaced enemy. Spares the submerged
	## (1986 rule), armor (bosses, bunkers), and the downed pilot — the
	## objective is not a hostile, and an unaimed 100-coin buy silently
	## deleting the 100-coin ransom read as the game cheating. Mints NO coin —
	## a 100-coin buy that reaped a full screen's bounty was a money printer.
	events.append({"t": "explosion", "x": SCREEN_CX, "y": camera_top + 180 * F_ONE})
	for e in enemies:
		if e["alive"] and not e.get("submerged", false) and e["kind"] != "pilot":
			_kill_enemy(e, true, true)


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
		6:
			p["triple"] = true                 # Triple Shot: a permanent 3-round fan mod
		7:
			p["rend_ticks"] = REND_TICKS       # Rend Rounds capsule (drop-only)
		8:
			p["claymores"] = mini(CLAYMORE_CAP, p["claymores"] + 1)   # a carried charge
		9:
			p["smoke_ticks"] = SMOKE_TICKS     # smoke concealment capsule (drop-only)
		10:
			# Flashbang: one field-wide stun, resolved the instant it's grabbed.
			flash_ticks = FLASH_STUN_TICKS
			# Fairness re-arm: a windup frozen mid-telegraph would otherwise
			# resume with the player's dodge window already burned — restore every
			# in-flight windup to ITS OWN archetype's full tell (a flat 24t floor
			# compressed a sniper's 55t laser paint to less than half its promise).
			for fe in enemies:
				if fe["alive"] and fe.get("windup", 0) > 0:
					fe["windup"] = maxi(fe["windup"], _windup_for(fe["kind"]))
			events.append({"t": "flashbang", "x": p["x"], "y": p["y"]})
		11:
			# Deployable sandbags (5-vote panel): the wheel buy plants a cover
			# segment IMMEDIATELY one step along the aim (claymore grammar) —
			# no carried inventory, no new player field, which is exactly what
			# keeps the player hash list untouched while unbought. Blocks
			# bullets AND rusher pathing both ways; one grenade or tank tread
			# clears it; mortar rings ignore it (strikes never check cover).
			var sbx: int = p["x"] + Fixed.mul(p["aim_x"], CLAYMORE_PLANT_OFFSET)
			var sby: int = p["y"] + Fixed.mul(p["aim_y"], CLAYMORE_PLANT_OFFSET)
			sandbags.append({"x": sbx, "y": sby})
			events.append({"t": "sandbag_plant", "x": sbx, "y": sby})
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
	if kind == 4 and (sandbags.size() >= SANDBAG_FIELD_CAP or p["in_tank"] >= 0):
		# Sandbag-specific denials: field cap reached, or buying from a tank
		# (no hands on the deck to dig in). Deny is loud, same as broke.
		events.append({"t": "deny", "x": p["x"], "y": p["y"]})
		return
	if war_chest < cost:
		events.append({"t": "deny", "x": p["x"], "y": p["y"]})
		return
	war_chest -= cost
	# Spending is not a score cut: credit the same 10x the Last Stand victory
	# payout gives unspent chest, so a run-saving buy trades power-now for
	# banked-score rather than costing points outright.
	score += cost * 10
	# Wheel slot 4 is the sandbag: supply-kind 11 (pickup kinds 4-10 are the
	# rare capsules — a priced crate can never carry 11, so no collision).
	_apply_supply(p, 11 if kind == 4 else kind)
	events.append({"t": "buy", "x": p["x"], "y": p["y"], "kind": kind})


# --- Tank ---

func _try_board_tank(player_index: int, p: Dictionary) -> bool:
	## True if a tank was boarded — INTERACT falls through to the claymore plant
	## only when there was nothing to board.
	for t in tanks.size():
		var tank := tanks[t]
		if not tank["alive"] or tank["burning"] \
				or not _dist_lte(p["x"], p["y"], tank["x"], tank["y"], TANK_BOARD_RADIUS):
			continue
		if tank["occupant"] < 0:
			tank["occupant"] = player_index
			p["in_tank"] = t
			events.append({"t": "tank_board", "x": tank["x"], "y": tank["y"]})
			return true
		if tank["occupant"] != player_index and _tank_gunner(t) < 0:
			# Tank Crew (8-vote panel): the second player rides an OCCUPIED tank
			# as coax gunner. Identity is DERIVED — in_tank set, occupant is
			# someone else — so the tank dict gains ZERO fields (occupant stays
			# driver-only) and the goldens never move (torture never boards:
			# probe-verified). Distinct event: tank_board already carries ~3
			# meanings and the SFX panel wants fewer, not more.
			p["in_tank"] = t
			events.append({"t": "tank_crew", "x": tank["x"], "y": tank["y"], "i": player_index})
			return true
	return false


func _tank_gunner(t: int) -> int:
	## Index of the player riding tank t as gunner (in_tank == t but not the
	## occupant), or -1. Always derived, never stored.
	for gi in players.size():
		if players[gi]["in_tank"] == t and tanks[t]["occupant"] != gi:
			return gi
	return -1


func _boardable_tank_near(p: Dictionary) -> bool:
	## Near-miss board taps must not arm a claymore at your feet: a boardable
	## tank just outside TANK_BOARD_RADIUS means INTERACT read as "board".
	for t in tanks.size():
		var tank := tanks[t]
		if tank["alive"] and not tank["burning"] \
				and (tank["occupant"] < 0 or _tank_gunner(t) < 0) \
				and _dist_lte(p["x"], p["y"], tank["x"], tank["y"], 2 * TANK_BOARD_RADIUS):
			return true
	return false


func _drive_tank(player_index: int, p: Dictionary, inp: SimInput, interact_edge: bool) -> void:
	var tank := tanks[p["in_tank"]]
	if not tank["alive"]:
		p["in_tank"] = -1
		return

	if tank["occupant"] != player_index:
		_ride_as_gunner(player_index, p, tank, inp, interact_edge)
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
			if e["kind"] == "pilot":
				# Treads GRAB, not shred: the tank is the best chase tool for a
				# 0.8px/t walker, and crushing the objective it's built to reach
				# was a silent ransom forfeit. Grace still applies.
				if not e.get("submerged", false):
					_rescue_pilot(e)
				continue
			_kill_enemy(e)
	# Treads flatten sandbags — armor does not respect your landscaping.
	for si in range(sandbags.size() - 1, -1, -1):
		var tsb := sandbags[si]
		if absi(tank["x"] - tsb["x"]) <= SANDBAG_HALF_W + TANK_CRUSH_RADIUS \
				and absi(tank["y"] - tsb["y"]) <= SANDBAG_HALF_H + TANK_CRUSH_RADIUS:
			events.append({"t": "sandbag_break", "x": tsb["x"], "y": tsb["y"]})
			sandbags.remove_at(si)
	# ...and roll over fuel barrels to set them off (chains via the fuse in _step_barrels).
	for bl in barrels:
		if bl["armed"] and _dist_lte(tank["x"], tank["y"], bl["x"], bl["y"], TANK_CRUSH_RADIUS):
			_detonate_barrel(bl, true)


func _ride_as_gunner(player_index: int, p: Dictionary, tank: Dictionary, inp: SimInput, interact_edge: bool) -> void:
	## Coax gunner seat: rides the hull, aims independently, fires the ON-FOOT
	## gun from the top deck — same 8t cadence, same mg_ammo pool, single
	## bullet (no capsule fans up there), so crewing up buys position + the
	## fuel tax, never a DPS printer. Starting values; probe test asserts
	## coax DPS <= on-foot DPS over a staged 600-tick burst.
	if interact_edge:
		p["in_tank"] = -1
		p["y"] = tank["y"] + 24 * F_ONE
		if tank["burning"]:
			# The bail window covers the gunner too — same leap, same mercy.
			p["boost_ticks"] = BAIL_BOOST_TICKS
			p["hurt_iframes"] = maxi(p["hurt_iframes"], BAIL_IFRAME_TICKS)
		_clamp_actor(p)
		return
	p["x"] = tank["x"]
	p["y"] = tank["y"]
	var ax: int = inp.aim_x * 256
	var ay: int = inp.aim_y * 256
	var alen := Fixed.length(ax, ay)
	if alen > F_ONE / 4:
		p["aim_x"] = Fixed.div(ax, alen)
		p["aim_y"] = Fixed.div(ay, alen)
	if inp.fire and p["fire_cd"] == 0:
		if p["mg_ammo"] > 0:
			p["fire_cd"] = FIRE_COOLDOWN_TICKS
			p["mg_ammo"] = p["mg_ammo"] - 1
			events.append({"t": "shot", "x": p["x"], "y": p["y"], "i": player_index})
			_spawn_mg_bullet(p, player_index, p["aim_x"], p["aim_y"])
		else:
			events.append({"t": "dry_fire", "x": p["x"], "y": p["y"], "i": player_index})


func _dismount(p: Dictionary, tank: Dictionary) -> void:
	# Crew promotion: a departing driver hands the hull to a seated gunner
	# instead of orphaning them (one assignment — no driverless zombie tank).
	var t_idx: int = p["in_tank"]
	tank["occupant"] = -1
	p["in_tank"] = -1
	if t_idx >= 0:
		var g := _tank_gunner(t_idx)
		if g >= 0:
			tank["occupant"] = g
	p["y"] = tank["y"] + 24 * F_ONE
	if tank["burning"]:
		p["boost_ticks"] = BAIL_BOOST_TICKS   # bailing gets the speed boost
		# ...and a brief mercy window — a forced bail can't hand you a corpse the
		# instant you land on an enemy (matches the respawn/frogman-surface grace).
		p["hurt_iframes"] = maxi(p["hurt_iframes"], BAIL_IFRAME_TICKS)
	_clamp_actor(p)


func _step_tanks() -> void:
	for ti in tanks.size():
		var tank := tanks[ti]
		if not tank["alive"]:
			continue
		tank["fire_cd"] = maxi(0, tank["fire_cd"] - 1)

		if tank["occupant"] >= 0 and not tank["burning"]:
			tank["fuel"] = tank["fuel"] - 1
			# Crew fuel tax: a seated gunner burns +25% (every 4th tick) —
			# double-crewing is a deliberate commitment, not a free gun deck.
			# Starting value; staged probe: crewed fuel life ~20s -> ~16s.
			if tank["fuel"] % 4 == 0 and _tank_gunner(ti) >= 0:
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
					# The bail window covers the whole crew: driver first (his
					# dismount promotes the gunner to occupant), then the gunner.
					for ci in players.size():
						if players[ci]["in_tank"] == ti:
							_dismount(players[ci], tank)
					_detonate_tank(tank)
					break
			if not tank["alive"]:
				continue
			tank["burn_ticks"] = tank["burn_ticks"] - 1
			if tank["burn_ticks"] <= 0:
				# Bail window expired: anyone still inside goes with it —
				# driver AND gunner (_kill_player clears each rider's in_tank).
				for ci in players.size():
					if players[ci]["in_tank"] == ti:
						_kill_player(players[ci])
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

func _step_bullets() -> void:
	# Offscreen bounds + per-bullet dict fields hoisted into locals (identical
	# values, so checksum-neutral): b["x"]/b["y"] never move after integration,
	# and each String-keyed Dictionary read is a hash lookup the hottest sim
	# loop was paying 5+ times per bullet per tick.
	var ylo := camera_top - 40 * F_ONE
	var yhi := camera_top + 400 * F_ONE
	# Bunker band prefilter: any bullet reaching the cover scan has by in
	# [ylo,yhi] (off-band bullets die above), so a bunker whose AABB misses that
	# band can never contain it — checksum-neutral by construction. Positions
	# never move; alive is RE-CHECKED per bullet (a barrel cook-off via
	# _detonate_barrel below can _explode a bunker mid-loop).
	var near_bks: Array[Dictionary] = []
	for bk in bunkers:
		if bk["alive"] and bk["y"] <= yhi and bk["y"] + BUNKER_H >= ylo:
			near_bks.append(bk)
	# Boss prefilter: gate boss dicts are never emptied and g["open"] mutates
	# only in _step_gates, so both gates are stable within this call; the
	# per-bullet boss["alive"] re-check stays (_damage_boss kills mid-loop).
	var boss_gates: Array[Dictionary] = []
	for g in gates:
		if not g["boss"].is_empty() and not g["open"]:
			boss_gates.append(g)
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var bx: int = b["x"] + b["vx"]
		var by: int = b["y"] + b["vy"]
		var ttl: int = b["ttl"] - 1
		b["x"] = bx
		b["y"] = by
		b["ttl"] = ttl
		var off := by < ylo or by > yhi or bx < 0 or bx > SCREEN_W_FP
		var dead: bool = ttl <= 0 or off
		if ttl <= 0 and not off:
			# Spent round lands in view: dirt-kick cue (events are checksum-excluded).
			events.append({"t": "bullet_dirt", "x": bx, "y": by})
		if not dead:
			# Bullets are stopped by armor: bunkers block, only grenades hurt them.
			for bk in near_bks:
				if bk["alive"] and _point_in_aabb(bx, by, bk):
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead and not sandbags.is_empty():
			# Player-authored cover eats rounds the same way (both directions).
			for sb in sandbags:
				if absi(bx - sb["x"]) <= SANDBAG_HALF_W and absi(by - sb["y"]) <= SANDBAG_HALF_H:
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead:
			for e in enemies:
				# Cheap axis pre-reject for the hottest O(bullets×enemies) scan.
				# Checksum-neutral by construction: |dx| ≥ r+1 raw units makes
				# dx² ≥ r² + 2r + 1 with 2r+1 > 1<<16 for any radius ≥ 0.5px, so
				# Fixed.mul(dx,dx) > Fixed.mul(r,r) even after >>16 truncation —
				# _dist_lte was already false for every pair skipped here.
				if absi(bx - e["x"]) > BULLET_HIT_RADIUS:
					continue
				# Bullets pass clean over submerged frogmen — grenades only.
				if e["alive"] and not e.get("submerged", false) \
						and _dist_lte(bx, by, e["x"], e["y"], BULLET_HIT_RADIUS):
					# Shield: a bullet arriving into the front arc (roughly
					# opposite the shieldman's facing-toward-you) is deflected;
					# flank it or use a grenade. Front cone ~120°.
					if e["kind"] == "shield" and _shield_blocks(e, b):
						# Rend Rounds: the shooter's active buff punches clean through
						# the front-arc block — otherwise the shield eats the round.
						var rw: int = b.get("owner", -1)
						if rw < 0 or rw >= players.size() or players[rw]["rend_ticks"] <= 0:
							events.append({"t": "armor_block", "x": bx, "y": by})
							dead = true
							break
						# Rend beat the block — a distinct shear event so the payoff
						# reads AT the shield (a silent skip looked like a normal kill).
						events.append({"t": "rend_pierce", "x": bx, "y": by})
					# MG Nest is armored: 3 bullets to crack (a grenade still one-shots
					# it via _explode). Only a lethal round routes through _kill_enemy.
					if e["kind"] == "mg_nest" or e["kind"] == "technical" or e["kind"] == "broadcast":
						e["hp"] = e["hp"] - 1
						if e["hp"] > 0:
							events.append({"t": "armor_block", "x": bx, "y": by})
							var mgowner: int = b.get("owner", -1)
							if mgowner >= 0 and mgowner < players.size() and players[mgowner]["pierce_ticks"] > 0:
								continue
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
			# A player round into a live fuel drum cooks it off (same blast path as a
			# tank rollover). Barrel kills mint no coin (no_coin) — no bullet farm.
			for bl in barrels:
				if bl["armed"] and _dist_lte(bx, by, bl["x"], bl["y"], BULLET_HIT_RADIUS):
					_detonate_barrel(bl, true)
					dead = true
					break
		if not dead:
			dead = _bullet_hits_boss(b, boss_gates)
		# Colossus core window: while the plating is retracted, bullets chip it
		# too (otherwise grenades-only). A timing/aggression path for the finale.
		if not dead and not colossus.is_empty() and colossus["alive"] \
				and colossus.get("core_open", 0) > 0 \
				and _dist_lte(bx, by, colossus["x"], colossus["y"], COLOSSUS_HIT_RADIUS):
			events.append({"t": "boss_hit", "x": bx, "y": by})
			_damage_colossus(COLOSSUS_BULLET_DAMAGE)
			dead = true
		if not dead and not observer.is_empty():
			if _dist_lte(bx, by, observer["x"], camera_top + OBSERVER_Y_OFFSET, BULLET_HIT_RADIUS):
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
		# Airburst: still HOLDING the grenade button at the arc's apex pops the
		# charge mid-air — tap throws the full 32-tick lob (unchanged), hold is
		# on-demand range control. Rides the hashed grenade_prev + this
		# grenade's own zv sign-flip: zero new state, no rng draw. Shells are
		# excluded (the cannon has no fuse hand).
		if not g["shell"] and g["zv"] < 0 and g["zv"] + GRENADE_GRAV >= 0 \
				and players[g["owner"]]["alive"] and players[g["owner"]]["grenade_prev"]:
			_explode(g["x"], g["y"], false, "airburst")
			grenades.remove_at(i)
			continue
		if g["z"] <= 0 and g["zv"] < 0:
			_explode(g["x"], g["y"])
			grenades.remove_at(i)


func _explode(x: int, y: int, no_coin := false, src := "") -> void:
	# src tags the trigger (e.g. "barrel") so the view can dedupe feel against
	# the co-located barrel_blast event; events are checksum-excluded.
	events.append({"t": "explosion", "x": x, "y": y, "src": src})
	var frags := 0
	for e in enemies:
		# The pilot is a non-combatant objective PAST his punch-out grace too:
		# a sapper mine or grenadier lob on his fixed walk was a ransom
		# coin-flip the player couldn't influence. Bullets still kill him —
		# "don't shoot the rescue" stays the player's lesson.
		if e["alive"] and e["kind"] != "pilot" and _dist_lte(x, y, e["x"], e["y"], GRENADE_RADIUS):
			_kill_enemy(e, no_coin)
			frags += 1
	if frags >= 3:
		# Frag bonus: a single blast that catches a pack rewards reading the field.
		score += frags * 50
		events.append({"t": "frag_bonus", "x": x, "y": y, "n": frags})
	for si in range(sandbags.size() - 1, -1, -1):
		# One grenade clears a bag — player-authored cover is real but cheap
		# to answer, for BOTH sides of it (your own grenade included).
		var sb := sandbags[si]
		if _dist_lte(x, y, sb["x"], sb["y"], GRENADE_RADIUS):
			events.append({"t": "sandbag_break", "x": sb["x"], "y": sb["y"]})
			sandbags.remove_at(si)
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
	# Explosive barrels in the blast don't chain in the SAME frame — they light a
	# short fuse (_step_barrels detonates it) so a cluster ripples over ~8 ticks:
	# visible, and rollable. Already-cooking barrels aren't re-lit.
	for bl in barrels:
		if bl["armed"] and bl["fuse_ticks"] == 0 \
				and _dist_lte(x, y, bl["x"], bl["y"], GRENADE_RADIUS):
			bl["fuse_ticks"] = BARREL_FUSE_TICKS
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


func _detonate_barrel(bl: Dictionary, no_coin := false) -> void:
	## One detonation path for every barrel trigger (tank rollover, player bullet,
	## enemy contact, chain fuse). Hurts players in radius (roll i-frames dodge it),
	## then blasts. Barrel kills mint NO coin — a self-detonating farm was free money.
	bl["armed"] = false
	events.append({"t": "barrel_blast", "x": bl["x"], "y": bl["y"]})
	for p in players:
		if p["alive"] and p["in_tank"] < 0 and p["roll_ticks"] == 0 \
				and _dist_lte(bl["x"], bl["y"], p["x"], p["y"], GRENADE_RADIUS):
			_hurt_player(p)
	_explode(bl["x"], bl["y"], no_coin, "barrel")


func _kill_enemy(e: Dictionary, no_coin := false, no_score := false) -> void:
	## no_score: unaimed screen-wipes (airstrike) mint no score and can't feed
	## the kill-streak either — a 100-coin buy vaulting the streak tiers was
	## a leaderboard printer. Barrel kills (no_coin only) still score.
	e["alive"] = false
	var coin: int = COIN_ELITE if e["elite"] else COIN_RUSHER
	if e["kind"] == "mg_nest":
		coin = COIN_MG_NEST   # own tier: stationary/telegraphed pays between rusher and elite
	if e["kind"] == "courier":
		coin = COIN_ELITE * 4   # fat bounty for catching the runner
	if e["kind"] == "pilot":
		# Gunning down the man you were meant to rescue pays NOTHING — no
		# chest, no score, no avenge. The corpse is the only receipt.
		coin = 0
		no_coin = true
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
				# Scales with the same wave/5 step as revive_cost, or deep-endless
				# revive inflation turns the avenge beat into pocket change.
				war_chest += 5 + ((wave / 5) * 5 if mode == "endless" else 0)
				events.append({"t": "avenge", "x": e["x"], "y": e["y"]})
				break
	# Last Stand doubles the score credit — the finale strips revives, so reward
	# pushing into the crush radius instead of kiting (War Chest bounty stays flat).
	if not no_score:
		score += coin * 10 * (2 if last_stand else 1)
	# Kill-streak: consecutive kills inside the window escalate a SCORE-ONLY
	# bonus at the tiers the view telegraphs (5/10/20). War Chest stays flat —
	# the streak rewards aggression on the leaderboard, not the economy.
	# The MG Nest is excluded: it's the lowest-risk target, so it can't feed the
	# streak (nor drop the elite capsule below) despite carrying elite:true.
	if e["kind"] != "mg_nest" and not no_score:
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
	if e["elite"] and e["kind"] != "mg_nest" and not no_coin:
		# ~1-in-6 elites drop a rare capsule; otherwise the usual Ammo/Grenade.
		# The rare table is WEIGHTED: the three offense mods (pierce/spread/
		# triple) at double the four situational tools (rend/claymore/smoke/
		# flash) — a uniform roll made run-driving offense rare while diluting
		# the pool with utility. Starting weights; test: over ~100 elite kills,
		# offense capsules should be ≥40% of rare drops — if <30%, raise them.
		var pkind: int
		if rng.range_i(0, 5) == 0:
			pkind = [4, 4, 5, 5, 6, 6, 7, 8, 9, 10][rng.range_i(0, 9)]
			if pkind == 7 and not _shields_possible():
				pkind = 4   # Rend before any shield can exist is a dead draw — give Pierce
		else:
			pkind = rng.range_i(0, 1)
		pickups.append({"x": e["x"], "y": e["y"], "kind": pkind})


# --- Enemies / bunkers / spawner ---

func _advance_toward(e: Dictionary, dx: int, dy: int, dlen: int, base_spd: int) -> void:
	## Shared "move toward target at base_spd, halved while wading" step used by
	## rushers, shieldmen, elites, grenadiers and snipers. Same fixed-point ops,
	## same order, as the code this replaces — golden-safe.
	## FRENZY (wave_mod 6) belongs HERE, not just in _step_sapper: "the swarm
	## rushes 40% faster" means the WHOLE swarm. wave_mod is endless-only and the
	## torture wipes long before wave 6, so this stays golden-inert.
	var spd := base_spd
	if wave_mod == 6:
		spd = (spd * 7) / 5
	# Broadcast Tower rally aura: any live mast within 140 px drives ground
	# troops +25% — deliberately under FRENZY's +40% so aura+FRENZY stacking
	# reads as escalation, not a doubling. Stateless read of hashed x/y;
	# campaign never spawns a mast -> golden-inert.
	if not _broadcasts.is_empty():
		for be in _broadcasts:
			if _dist_lte(e["x"], e["y"], be["x"], be["y"], BROADCAST_AURA_RADIUS):
				spd = (spd * 5) / 4
				break
	if _in_water(e["x"], e["y"]):
		spd = spd / 2
	var pvx: int = e["x"]
	var pvy: int = e["y"]
	e["x"] = pvx + Fixed.mul(Fixed.div(dx, dlen), spd)
	e["y"] = pvy + Fixed.mul(Fixed.div(dy, dlen), spd)
	# Sandbag walls stop ground movers both ways (the water-clamp pattern:
	# move, then revert into-AABB steps) — the swarm flanks cover, never
	# phases through it. Empty-array fast path keeps the hot loop clean.
	if not sandbags.is_empty():
		for sb in sandbags:
			if absi(e["x"] - sb["x"]) <= SANDBAG_HALF_W and absi(e["y"] - sb["y"]) <= SANDBAG_HALF_H:
				e["x"] = pvx
				e["y"] = pvy
				break


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


func _rescue_pilot(e: Dictionary) -> void:
	## The one touch on this field that pays instead of kills — shared by the
	## on-foot grab (incl. mid-roll) and the tank treads.
	e["alive"] = false
	war_chest += PILOT_RANSOM
	score += PILOT_RANSOM * 10
	events.append({"t": "pilot_rescued", "x": e["x"], "y": e["y"], "coin": PILOT_RANSOM})


func _step_enemies() -> void:
	# One O(n) sweep so _advance_toward's aura check never rescans the roster
	# per mover (that hot path just got 37% cheaper — keep it that way).
	_broadcasts.clear()
	for be in enemies:
		if be["kind"] == "broadcast" and be["alive"]:
			_broadcasts.append(be)
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		if not e["alive"] or e["y"] > camera_top + 420 * F_ONE:
			enemies.remove_at(i)
			continue
		if flash_ticks > 0:
			continue   # flashbang: the whole field roster is stunned in place
		if e["kind"] == "pilot":
			# Punch-out grace first: he wears the frogman's no-shoot grammar
			# (submerged + surface_ticks — both already hashed, zero new
			# fields) while he staggers to his feet, so trigger inertia held
			# through the boss kill can't gun him down before the banner lands.
			if e.get("surface_ticks", 0) > 0:
				e["surface_ticks"] = e["surface_ticks"] - 1
				if e["surface_ticks"] == 0:
					e["submerged"] = false
				continue
			# Downed pilot: no AI, no target — he just staggers for the enemy
			# line at the top. Crossing it = captured, ransom forfeit. (Rescue
			# by touch lives in _step_players; killing him pays nothing.)
			e["y"] = e["y"] - PILOT_SPEED
			if e["y"] < camera_top - 30 * F_ONE:
				e["alive"] = false
				events.append({"t": "pilot_lost", "x": e["x"], "y": e["y"]})
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
		if e["kind"] == "drone":
			_step_drone(e, target, dx, dy, dlen)
			continue
		if e["kind"] == "broadcast":
			# Rooted rally mast: the AURA is the threat, and holding the wave
			# open (it counts in _wave_hostiles_cleared) is the anti-stall
			# pressure. fire_cd doubles as the view-pulse metronome.
			e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
			if e["fire_cd"] == 0:
				e["fire_cd"] = BROADCAST_PULSE_TICKS
				events.append({"t": "broadcast_pulse", "x": e["x"], "y": e["y"]})
			continue
		if e["kind"] == "technical":
			_step_technical(e, target, dx, dy, dlen)
			continue
		if e["kind"] == "mg_nest":
			_step_mg_nest(e, target, dx, dy, dlen)
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
		# A live supply drop MAGNETIZES rushers (mid-wave objective beat): they
		# break off the player chase to steal the crate — defend it or cede it.
		# Touch destroys the crate (denial): no coin, no blast, just gone.
		if e["kind"] == "rusher":
			var drop := {}
			for pk in pickups:
				if pk.get("drop", false):
					drop = pk
					break
			if not drop.is_empty():
				var ddx: int = drop["x"] - e["x"]
				var ddy: int = drop["y"] - e["y"]
				var ddlen := Fixed.length(ddx, ddy)
				if ddlen <= PICKUP_RADIUS:
					pickups.erase(drop)
					events.append({"t": "drop_stolen", "x": drop["x"], "y": drop["y"]})
				elif ddlen > F_ONE:
					_advance_toward(e, ddx, ddy, ddlen, ENEMY_SPEED)
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
	elif e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't aim into smoke
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
	elif e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't paint into smoke
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
	elif e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't paint into smoke
		e["fire_cd"] = SNIPER_FIRE_CD_TICKS
		e["windup"] = SNIPER_WINDUP_TICKS
		e["aim_lx"] = dx   # lock the shot vector at paint start (see fire branch)
		e["aim_ly"] = dy
		events.append({"t": "sniper_paint", "x": e["x"], "y": e["y"]})


func _step_drone(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Recon Drone (endless-only): a flying spotter that holds a standoff hover,
	## winds up a paint, then calls a tracked mortar strike on the target's
	## CURRENT ground via _add_strike (the strike telegraph is the dodge window).
	## Flying: never water-slowed. Bullets still swat it; touch still kills.
	## Reuses fire_cd/windup — no new hashed enemy field.
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0:
			_add_strike(target["x"], target["y"])
		return   # holds position while painting
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > DRONE_STANDOFF:
		e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), DRONE_SPEED)
		e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), DRONE_SPEED)
	elif e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't paint into smoke
		e["fire_cd"] = DRONE_FIRE_CD_TICKS
		e["windup"] = DRONE_WINDUP_TICKS
		events.append({"t": "drone_windup", "x": e["x"], "y": e["y"]})


func _step_technical(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Technical raider (endless-only): rev telegraph → LOCK a charge line at
	## the target's position → barrel down it at TECHNICAL_SPEED. It cannot
	## steer mid-charge (repositioning off the line is the dodge), water is a
	## hard wall to wheels (tank rule — the charge dies at the bank), and an
	## overshot charge just keeps going (a raider that misses barrels past).
	## Reuses windup/aim_lx/aim_ly/lunge_ticks/fire_cd — no new hashed field.
	if e.get("lunge_ticks", 0) > 0:
		e["lunge_ticks"] = e["lunge_ticks"] - 1
		var lx: int = e.get("aim_lx", 0)
		var ly: int = e.get("aim_ly", 0)
		var llen := Fixed.length(lx, ly)
		if llen > F_ONE:
			var prev_x: int = e["x"]
			var prev_y: int = e["y"]
			e["x"] = e["x"] + Fixed.mul(Fixed.div(lx, llen), TECHNICAL_SPEED)
			e["y"] = e["y"] + Fixed.mul(Fixed.div(ly, llen), TECHNICAL_SPEED)
			if _in_water(e["x"], e["y"]):
				e["x"] = prev_x
				e["y"] = prev_y
				e["lunge_ticks"] = 0   # wheels don't swim
				# The bank-stop needs a receipt — a silent zero-frame halt read
				# as a sim glitch, and the water counter never taught. (Events
				# are checksum-excluded: golden-safe.)
				events.append({"t": "technical_stall", "x": e["x"], "y": e["y"]})
		return
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0:
			e["aim_lx"] = dx   # the drawn rev line is a promise: charge follows IT, not you
			e["aim_ly"] = dy
			e["lunge_ticks"] = TECHNICAL_CHARGE_TICKS
		return
	# Between charges the raider CLOSES at infantry pace — a parked gun-truck
	# sold as "the fastest thing on the field" was stationary ~100 of every
	# 150 ticks, and one that spawned or overshot >150px from the player (a
	# charge travels ~150px) lobbed charges that died short forever. The rev
	# itself stays rooted (honest telegraph); the charge is still the only
	# kill move. Starting value ENEMY_SPEED; test: a technical spawned 250px
	# from a strafing player must force ≥1 dodged charge within 4s — if it
	# still never engages, drop TECHNICAL_LOCK_CD_TICKS toward 50.
	if dlen > F_ONE:
		var cpx: int = e["x"]
		var cpy: int = e["y"]
		e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), ENEMY_SPEED)
		e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), ENEMY_SPEED)
		if _in_water(e["x"], e["y"]):   # wheels don't swim (tank rule)
			e["x"] = cpx
			e["y"] = cpy
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't line up a charge into smoke
		e["fire_cd"] = TECHNICAL_LOCK_CD_TICKS
		e["windup"] = TECHNICAL_REV_TICKS
		events.append({"t": "technical_rev", "x": e["x"], "y": e["y"]})


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
	if e["fire_cd"] == 0 and target["smoke_ticks"] == 0:   # can't paint into smoke
		e["fire_cd"] = SNIPER_FIRE_CD_TICKS
		e["windup"] = SNIPER_WINDUP_TICKS
		e["aim_lx"] = dx   # lock the shot vector at paint start (view draws the line)
		e["aim_ly"] = dy
		events.append({"t": "sniper_paint", "x": e["x"], "y": e["y"]})


func _nearest_alive_player(x: int, y: int) -> Dictionary:
	var best := {}
	var best_d := 0
	for p in players:
		# NOTE: smoke concealment is NOT applied here — this lookup also drives
		# MOVEMENT (rusher chase, courier flee, colossus descent, frogman
		# proximity), and blinding it froze the whole field into a free-kill
		# printer. Smoke instead gates the ranged FIRE-COMMIT sites (windup/
		# paint/strike starts) via smoke_ticks checks at each shooter.
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
			# Mine position hoisted out of the inner scan (dict hash per read).
			var mx: int = m["x"]
			var my: int = m["y"]
			for e in enemies:
				# Axis pre-reject — same truncation-safe proof as _step_bullets.
				if absi(e["x"] - mx) > MINE_TRIGGER_RADIUS:
					continue
				# (Pilot exemption: his fixed walk crossing a random field was a
				# ransom coin-flip, not counterplay.)
				if e["alive"] and not e.get("submerged", false) and e["kind"] != "pilot" \
						and _dist_lte(e["x"], e["y"], mx, my, MINE_TRIGGER_RADIUS):
					triggered = true
					break
		if triggered:
			m["armed"] = false
			_explode(m["x"], m["y"])


func _step_barrels() -> void:
	for i in range(barrels.size() - 1, -1, -1):
		var bl := barrels[i]
		if bl["armed"] and bl["fuse_ticks"] > 0:
			# Chain fuse counting down — detonates when it hits 0 (coin-neutral).
			bl["fuse_ticks"] = bl["fuse_ticks"] - 1
			if bl["fuse_ticks"] == 0:
				_detonate_barrel(bl, true)
		elif bl["armed"]:
			# Enemy contact detonates it (like a mine) — a two-way hazard that
			# auto-clears the rows enemies wade through. No coin (enemy-suicide farm).
			# Barrel position hoisted out of the inner scan (dict hash per read).
			var blx: int = bl["x"]
			var bly: int = bl["y"]
			for e in enemies:
				# Axis pre-reject — same truncation-safe proof as _step_bullets.
				if absi(e["x"] - blx) > MINE_TRIGGER_RADIUS:
					continue
				if e["alive"] and not e.get("submerged", false) \
						and _dist_lte(e["x"], e["y"], blx, bly, MINE_TRIGGER_RADIUS):
					_detonate_barrel(bl, true)
					break
		if not bl["armed"] or bl["y"] > camera_top + 420 * F_ONE:
			barrels.remove_at(i)


func _step_spawner() -> void:
	# Field spawner: pressure from above the screen edge; every 7th is a red
	# elite. Each opened gate tightens the interval — the campaign's
	# difficulty ratchet (45 → 24 ticks by gate 4; the final gate only opens
	# on Colossus death, so gate 4 is the last one the ramp can see).
	var opened := 0
	for g in gates:
		if g["open"]:
			opened += 1
	if _spawn_grace > 0:
		_spawn_grace -= 1
	var interval := maxi(24, SPAWN_INTERVAL_TICKS - opened * 6)
	if hard:
		interval = maxi(16, (interval * 2) / 3)   # NG+ pours them in faster
	if tick_count % interval != 0 or enemies.size() >= MAX_ENEMIES or _spawn_grace > 0:
		return
	_spawn_counter += 1
	var x := rng.range_i(24, 616) * F_ONE
	# Sector 2+ (1 gate opened): the endless ranged roster starts bleeding into
	# the campaign field, so later sectors get a genuinely new threat vocabulary
	# (laser-paint sniper, riot shield) — not just faster rushers.
	if opened >= 1 and rng.range_i(0, 3 if hard else 4) == 0:  # NG+: 1-in-4 specials
		var spick := rng.range_i(0, 3)   # +mg_nest turret
		if spick == 3:
			_spawn_mg_nest(x, camera_top - 24 * F_ONE)
		else:
			_spawn_special(x, camera_top - 24 * F_ONE, ["grenadier", "sniper", "shield"][spick])
	else:
		# Elite ratio tightens with each opened gate (every 7th → every 3rd by
		# gate 4) so late campaign escalates composition, not just cadence.
		var elite_every := maxi(3, 7 - opened)
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
	else:
		# Cosmetic sprite variant so a rusher wave reads as varied troops, not one
		# silhouette cloned N times. Derived from spawn position (NO rng draw) and
		# excluded from checksum() -> golden-safe (see KNOWN["enemy"] in coverage).
		e["skin"] = (x / F_ONE + y / F_ONE) & 3
	enemies.append(e)


func _spawn_frogman(x: int, y: int) -> void:
	enemies.append({"x": x, "y": y, "alive": true, "elite": false,
		"kind": "frogman", "submerged": true, "lunge_ticks": 0, "surface_ticks": 0})


func _windup_for(kind: String) -> int:
	## The archetype's full telegraph length (the flashbang re-arm restores a
	## frozen shot to its own tell, keeping every telegraph a truthful promise).
	match kind:
		"sniper", "ghillie":
			return SNIPER_WINDUP_TICKS
		"grenadier":
			return GRENADIER_WINDUP_TICKS
		"drone":
			return DRONE_WINDUP_TICKS
		"technical":
			return TECHNICAL_REV_TICKS
	return ELITE_WINDUP_TICKS


func _shields_possible() -> bool:
	## True once the shield archetype can actually spawn (campaign: 1 gate
	## opened, matching _step_spawner's special roster; endless: wave 3+) —
	## gates the Rend drop so it's never inert.
	if mode == "endless":
		return wave >= 3
	var opened := 0
	for g in gates:
		if g["open"]:
			opened += 1
	return opened >= 1


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
	if kind == "drone":
		# The marquee aerial threat kills like a trophy, not a grunt: marked
		# rides the existing bounty grammar (3× pay + gold fountain + crown).
		e["marked"] = true
	if kind == "technical":
		e["hp"] = TECHNICAL_HP   # armored like the nest — hp is already hashed
	enemies.append(e)


func _spawn_mg_nest(x: int, y: int) -> void:
	## Rooted fixed turret: rakes its lane with aimed 3-round bursts, never moves.
	## Reuses fire_cd/windup/lunge_ticks/aim_lx/aim_ly — all already hashed.
	enemies.append({"x": x, "y": y, "alive": true, "elite": true,
		"kind": "mg_nest", "hp": 3, "fire_cd": MG_NEST_AIM_TICKS, "windup": 0,
		"lunge_ticks": 0, "aim_lx": 0, "aim_ly": 0})


func _spawn_broadcast(x: int, y: int) -> void:
	## Rooted rally mast (endless wave-7+ debut — panel 4-vote): fires nothing,
	## moves nothing; every ground mover in its aura runs +25%. Killing the mast
	## breaks the rally. Reuses hashed hp/fire_cd/windup — zero new fields.
	enemies.append({"x": x, "y": y, "alive": true, "elite": true,
		"kind": "broadcast", "hp": BROADCAST_HP, "fire_cd": 0, "windup": 0})



func _step_mg_nest(e: Dictionary, _target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Break LOS, flank, or grenade it. windup = inter-round spacing, lunge_ticks =
	## rounds left, aim_lx/ly = the LOCKED burst vector, fire_cd = reload.
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0 and e["lunge_ticks"] > 0:
			# Re-acquire toward the CURRENT nearest player at each round: a tracking
			# rake that punishes standing still (one sidestep no longer clears the
			# burst). Deterministic — reads hashed player positions.
			var tgt := _nearest_alive_player(e["x"], e["y"])
			if not tgt.is_empty():
				e["aim_lx"] = tgt["x"] - e["x"]
				e["aim_ly"] = tgt["y"] - e["y"]
			var lx: int = e["aim_lx"]
			var ly: int = e["aim_ly"]
			var llen := Fixed.length(lx, ly)
			if llen > F_ONE:
				events.append({"t": "enemy_shot", "x": e["x"], "y": e["y"]})
				enemy_bullets.append({"x": e["x"], "y": e["y"],
					"vx": Fixed.mul(Fixed.div(lx, llen), ENEMY_BULLET_SPEED),
					"vy": Fixed.mul(Fixed.div(ly, llen), ENEMY_BULLET_SPEED),
					"ttl": ENEMY_BULLET_TTL_TICKS})
			e["lunge_ticks"] = e["lunge_ticks"] - 1
			if e["lunge_ticks"] > 0:
				e["windup"] = MG_NEST_BURST_GAP_TICKS
			else:
				e["fire_cd"] = MG_NEST_BURST_CD_TICKS
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if e["fire_cd"] == 0 and dlen > F_ONE:
		# Lock the aim on the target NOW and open a 3-round burst down that line.
		e["aim_lx"] = dx
		e["aim_ly"] = dy
		e["lunge_ticks"] = MG_NEST_BURST_ROUNDS
		e["windup"] = MG_NEST_AIM_TICKS
		events.append({"t": "mg_nest_aim", "x": e["x"], "y": e["y"]})


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
	# Stream explosive fuel-barrel CLUSTERS off the gate rows — live ordnance a
	# grenade chains through (and that catches you if you stand too close).
	while _next_barrel_y > camera_top - 2 * VIEW_H:
		if absi(_next_barrel_y / BARREL_SPACING) % 2 == 1:
			var bx := rng.range_i(60, 520) * F_ONE
			for c in rng.range_i(2, 3):
				barrels.append({"x": bx + c * BARREL_CLUSTER_GAP,
					"y": _next_barrel_y + rng.range_i(-8, 8) * F_ONE, "armed": true, "fuse_ticks": 0})
		_next_barrel_y -= BARREL_SPACING
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
				"boss": {"alive": true, "hp": _scaled_boss_hp(BOSS_HP), "x": SCREEN_CX,
					"dir": 1, "phase_t": 0, "gate_y": _next_gate_y}})
		else:
			var b1 := _make_bunker(180 * F_ONE, _next_gate_y + 50 * F_ONE)
			var b2 := _make_bunker(412 * F_ONE, _next_gate_y + 50 * F_ONE)
			bunkers.append(b1)
			bunkers.append(b2)
			gates.append({"y": _next_gate_y, "open": false, "b1": b1, "b2": b2, "boss": {}})
			# Route Fork (panel 8-vote): the approach to bunker-pair gates 2 & 4
			# splits into two telegraphed lanes — walking a side IS the choice
			# (pure position: no new input, no stored state, gates[] is unhashed).
			# LEFT = Cache lane: a free crate ringed by extra mines. RIGHT =
			# Gauntlet lane: two extra elites, one a guaranteed marked bounty.
			# Torture-inert: the 60 s campaign run never streams past gate 1
			# (probe-verified — camera_top ends ~43 units short of gate 2).
			if _gate_counter == 2 or _gate_counter == 4:
				pickups.append({"x": (90 + rng.range_i(0, 120)) * F_ONE,
					"y": _next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE,
					"kind": 1 + rng.range_i(0, 1), "cost": 0})
				for m in 3:
					mines.append({"x": (70 + rng.range_i(0, 180)) * F_ONE,
						"y": _next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE, "armed": true})
				for s in 2:
					_spawn_enemy((360 + rng.range_i(0, 160)) * F_ONE,
						_next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE, true)
				enemies[enemies.size() - 1]["marked"] = true
				events.append({"t": "route_fork", "x": SCREEN_CX, "y": _next_gate_y})
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
				var roll := rng.range_i(0, 9)
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
				elif roll == 5:
					# Tracked-AoE is the hardest special to answer — waves 3-4 teach
					# the dodge-by-aim shooters first, then the drone layers on at 5
					# (the same beat the first miniboss lands).
					_spawn_special(x, camera_top - 24 * F_ONE, "drone" if wave >= 5 else "sniper")
				elif roll == 6:
					_spawn_mg_nest(x, camera_top - 24 * F_ONE)
				elif roll == 7:
					_spawn_special(x, camera_top - 24 * F_ONE, "technical")
				elif roll == 8 and wave >= 7:
					# Late-debut archetype: deep waves stop being static. Roll 8 fell
					# to plain-elite before, and still does under wave 7 — the rng
					# stream is untouched, only the wave-7+ interpretation changes.
					_spawn_broadcast(x, camera_top - 24 * F_ONE)
				else:
					_spawn_enemy(x, camera_top - 24 * F_ONE, true)
			else:
				_spawn_enemy(x, camera_top - 24 * F_ONE, is_elite)
	elif _wave_hostiles_cleared() and (endless_boss.is_empty() or not endless_boss["alive"]):
		# Wave cleared: open the shop for the intermission (a live miniboss holds it).
		intermission_ticks = WAVE_INTERMISSION_TICKS
		events.append({"t": "wave_clear", "x": 320 * F_ONE, "y": camera_top + 180 * F_ONE})
		# Clean Wave: endless's answer to the campaign's Flawless Gate — no deaths
		# this wave pays a bonus, so cautious and reckless play stop earning alike.
		if deaths_this_wave == 0 and wave > 1:
			# Bonus rides the same creep curve as _supply_cost, or price inflation
			# quietly erodes it into a rounding error by deep waves.
			war_chest += 40 + (wave / 3) * 10
			score += 1500
			events.append({"t": "wave_flawless", "x": 320 * F_ONE, "y": camera_top + 150 * F_ONE})
		var shop_y: int = camera_top + 120 * F_ONE
		# Shuffle the crate→slot mapping each wave so the shop stays a live read
		# (far-left ≠ always ammo), Fisher-Yates on the seeded SimRng.
		# Airstrike (kind 3) is deliberately absent: it stays a WHEEL-ONLY
		# telegraphed buy so a priced crate can't auto-buy it into an empty shop
		# on proximity. Ammo/grenade/vest remain the crate pool.
		var kinds := [0, 1, 2]
		for si in range(2, 0, -1):
			var sj := rng.range_i(0, si)
			var tmp: int = kinds[si]
			kinds[si] = kinds[sj]
			kinds[sj] = tmp
		var xs := [190, 350, 510]
		for ci in 3:
			pickups.append({"x": xs[ci] * F_ONE, "y": shop_y, "kind": kinds[ci],
				"cost": _supply_cost(kinds[ci])})
	else:
		# Anti-stall: a passed-by ghillie re-cloaks (bullet-immune) yet stays
		# alive, holding the wave open until the player backtracks into its
		# notice radius — a soft-lock they trip without understanding why. When
		# ONLY cloaked ghillies remain, force the reveal: the wave must always
		# be finishable from where the player stands.
		var all_cloaked := not enemies.is_empty()
		for e in enemies:
			if not (e["kind"] == "ghillie" and e.get("submerged", false)):
				all_cloaked = false
				break
		if all_cloaked:
			for e in enemies:
				e["submerged"] = false
				e["surface_ticks"] = GHILLIE_REVEAL_TICKS
				events.append({"t": "frogman_surface", "x": e["x"], "y": e["y"]})


func _wave_hostiles_cleared() -> bool:
	## The wave is beaten when no HOSTILE remains — a walking downed pilot is
	## an optional side objective, never a reason to hold the shop hostage.
	for e in enemies:
		if e["kind"] != "pilot":
			return false
	return true


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
	# No back-to-back repeats: wave_mod still holds last wave's mutator here,
	# so a duplicate roll falls back to plain — twice-in-a-row reads as a bug.
	var prev_mod := wave_mod
	wave_mod = 0 if wave <= 2 else rng.range_i(0, 6)
	if wave_mod != 0 and wave_mod == prev_mod:
		wave_mod = 0
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
		endless_boss = {"alive": true, "hp": _scaled_boss_hp(BOSS_HP + (wave / 5 - 1) * (BOSS_HP / 2)),
			"x": SCREEN_CX, "dir": 1, "phase_t": 0, "gate_y": camera_top + 90 * F_ONE}
		events.append({"t": "endless_boss", "x": SCREEN_CX, "y": camera_top + 50 * F_ONE})
	if wave >= 4 and rng.range_i(0, 2) == 0:
		# Mid-wave optional objective (5-vote panel, trimmed to the drop beat):
		# a parachuted free crate lands down-screen and rushers magnet to it —
		# defend the drop or cede it. The wave >= 4 gate sits BEFORE the rng
		# roll, so waves 1-3 draw nothing new and the endless torture (wipes at
		# wave 2) never perturbs the stream -> ENDLESS_GOLDEN byte-identical.
		# 1-in-3 roll mirrors the courier's (starting value; force-stage 30
		# waves -> expect ~10 drops). "drop" is an immutable-at-spawn marker,
		# unhashed (classified in test_checksum_coverage).
		var drx := rng.range_i(60, 580) * F_ONE
		var dry: int = camera_top + 240 * F_ONE
		pickups.append({"x": drx, "y": dry, "kind": 1 + rng.range_i(0, 1), "cost": 0, "drop": true})
		events.append({"t": "supply_drop", "x": drx, "y": dry})
	events.append({"t": "wave_start", "x": SCREEN_CX, "y": camera_top + 40 * F_ONE, "mod": wave_mod})


# --- Foundry Colossus (the finale) ---

func _scaled_boss_hp(base: int) -> int:
	## Boss/colossus starting HP scales with the living player count at spawn:
	## +60% per extra player (integer math). Grenade DPS is per-player, so a
	## flat pool let 2P melt a boss ~2x faster; this keeps the fight length even.
	if hard:
		base = base * 3 / 2   # NG+ armor: bosses stop being first-run pushovers
	var pc := 0
	for pl in players:
		if pl["alive"]:
			pc += 1
	if pc < 1:
		pc = 1
	return base + base * 6 * (pc - 1) / 10


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
					"alive": true, "hp": _scaled_boss_hp(COLOSSUS_HP),
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
	if colossus["spray_cd"] <= 0 and target["smoke_ticks"] == 0:   # can't aim into smoke (descent continues)
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
		if colossus["volley_cd"] <= 0 and target["smoke_ticks"] == 0:
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
		# The finale joins the Flawless economy: a deathless Colossus clear pays
		# the same checkpoint bonus (capped 3×) instead of ending a streak unpaid.
		if deaths_since_gate == 0:
			flawless_streak += 1
			var fmult: int = mini(flawless_streak, 3)
			score += 2000 * fmult
			events.append({"t": "gate_flawless", "x": colossus["x"], "y": colossus["y"], "mult": fmult})
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
			if not target.is_empty() and target["smoke_ticks"] == 0:
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
			if not target2.is_empty() and target2["smoke_ticks"] == 0:
				_add_strike(target2["x"], target2["y"])


func _bullet_hits_boss(b: Dictionary, boss_gates: Variant = null) -> bool:
	# boss_gates: _step_bullets passes its per-call prefilter (gates with a
	# non-empty boss, still closed) so ~150 live rounds don't re-interrogate
	# all ~5 gates each tick; direct test callers omit it and scan everything.
	# The full guard stays — it's what makes both paths identical.
	var cands: Array = boss_gates if boss_gates != null else gates
	for g in cands:
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
		# Endless minibosses pay with their depth: HP scales +50%/milestone
		# (x1.6/player) while the flat 200c shrank into a time-tax. Campaign
		# gunships stay flat (wave = 0). Test: coins/sec on the w5 vs w25
		# miniboss within ~25%.
		var bounty: int = BOSS_BOUNTY
		if mode == "endless" and wave >= 5:
			bounty += (wave / 5 - 1) * (BOSS_BOUNTY / 2)
		if wave_mod == 4:
			bounty *= 2   # PAYDAY wave: every bounty doubles (same rule as _kill_enemy)
		war_chest += bounty
		score += bounty * 10
		var by: int = boss["gate_y"] - BOSS_Y_OFFSET
		events.append({"t": "explosion", "x": boss["x"], "y": by})
		events.append({"t": "kill", "x": boss["x"], "y": by, "coin": bounty, "kind": "boss"})
		# The gunship's pilot punches out at the crash site and staggers for the
		# enemy line — reach him before the top edge for the ransom.
		# Unconditional + floor-clamped: the MAX_ENEMIES gate silently voided the
		# advertised ransom at capped waves (one transient non-combatant just
		# delays the next gated spawn), and a top-edge gunship kill ejected a
		# pilot with a ~1s unavoidable fail (120px floor -> 50-70% catch target).
		var pilot_y: int = maxi(by, camera_top + 120 * F_ONE)
		enemies.append({"x": boss["x"], "y": pilot_y, "alive": true, "elite": false, "kind": "pilot",
			"submerged": true, "surface_ticks": PILOT_PUNCHOUT_TICKS})
		events.append({"t": "pilot_down", "x": boss["x"], "y": pilot_y})


func _step_enemy_bullets() -> void:
	# Same locals hoist as _step_bullets: identical values, checksum-neutral.
	var ylo := camera_top - 40 * F_ONE
	var yhi := camera_top + 400 * F_ONE
	# Same bunker band prefilter as _step_bullets (nothing here can kill a
	# bunker mid-loop, but the per-bullet alive re-check is kept for symmetry).
	var near_bks: Array[Dictionary] = []
	for bk in bunkers:
		if bk["alive"] and bk["y"] <= yhi and bk["y"] + BUNKER_H >= ylo:
			near_bks.append(bk)
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b := enemy_bullets[i]
		var bx: int = b["x"] + b["vx"]
		var by: int = b["y"] + b["vy"]
		var ttl: int = b["ttl"] - 1
		b["x"] = bx
		b["y"] = by
		b["ttl"] = ttl
		var off := by < ylo or by > yhi or bx < 0 or bx > SCREEN_W_FP
		var dead: bool = ttl <= 0 or off
		if ttl <= 0 and not off:
			# Spent round lands in view: dirt-kick cue (events are checksum-excluded).
			events.append({"t": "bullet_dirt", "x": bx, "y": by})
		if not dead:
			# Cover is real both ways now: a bunker between you and a shooter eats
			# the round, same as it eats yours (player bullets already block here).
			for bk in near_bks:
				if bk["alive"] and _point_in_aabb(bx, by, bk):
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead and not sandbags.is_empty():
			for sb in sandbags:
				if absi(bx - sb["x"]) <= SANDBAG_HALF_W and absi(by - sb["y"]) <= SANDBAG_HALF_H:
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead:
			for p in players:
				if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
						and _dist_lte(bx, by, p["x"], p["y"], ENEMY_BULLET_HIT_RADIUS):
					_hurt_player(p)
					dead = true
					break
		if dead:
			enemy_bullets.remove_at(i)


func _add_strike(x: int, y: int, obs := false) -> void:
	## Every tracked mortar strike funnels here so the view/audio get one
	## consistent "incoming" warning event alongside the telegraph state.
	## `obs` tags the Observer's own barrage: killing/outrunning him defuses
	## ONLY his strikes — grenadier lobs, drone paints and boss volleys sharing
	## this array keep falling (they have their own living owners).
	strikes.append({"x": x, "y": y, "ticks": STRIKE_TELEGRAPH_TICKS, "obs": obs})
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
			_clear_observer_strikes()
			stall_ticks = 0
		else:
			observer["strike_cd"] = observer["strike_cd"] - 1
			if observer["strike_cd"] <= 0:
				observer["strike_cd"] = OBSERVER_STRIKE_CD_TICKS
				var target := _nearest_alive_player(observer["x"], camera_top + OBSERVER_Y_OFFSET)
				if not target.is_empty() and target["smoke_ticks"] == 0:   # can't paint into smoke
					_add_strike(target["x"], target["y"], true)
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
	_clear_observer_strikes()
	stall_ticks = 0


func _clear_observer_strikes() -> void:
	# Downing the spotter defuses HIS barrage only — a shared strikes.clear()
	# used to also cancel every in-flight grenadier/drone/boss strike, a free
	# field-wide defuse that had nothing to do with the observer.
	for i in range(strikes.size() - 1, -1, -1):
		if strikes[i].get("obs", false):
			strikes.remove_at(i)


# --- Geometry helpers ---

func _dist_lte(x1: int, y1: int, x2: int, y2: int, r: int) -> bool:
	# Axis early-out: |dx| > r implies dx^2 > r^2 — byte-identical result,
	# skips the fixed-point multiplies on the (common) far-apart case.
	if absi(x1 - x2) > r or absi(y1 - y2) > r:
		return false
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
	h = feed.call(flash_ticks, h)
	h = feed.call(int(last_stand), h)
	h = feed.call(int(wiped), h)
	h = feed.call(int(victory), h)
	if assist_mode:
		h = feed.call(2166136261, h)   # only perturbs the hash when assist is ON (torture: OFF)
	if hard:
		h = feed.call(40503, h)        # only perturbs the hash when HARD is ON (torture: OFF)
	if not sandbags.is_empty():
		# Conditional feed (assist/hard/colossus precedent): an empty array
		# leaves the hash stream untouched, so goldens hold while unbought —
		# the mines[] unconditional-feed lesson, learned.
		h = feed.call(sandbags.size(), h)
		for sb in sandbags:
			h = feed.call(sb["x"], h)
			h = feed.call(sb["y"], h)
	if not colossus.is_empty():
		for v in [colossus["hp"], colossus["x"], colossus["y"], int(colossus["alive"]),
				colossus.get("core_open", 0), colossus.get("core_cd", 0)]:
			h = feed.call(v, h)
	for s in [rng._s0, rng._s1, rng._s2, rng._s3]:
		h = feed.call(s, h)
	for p in players:
		for v in [p["x"], p["y"], int(p["alive"]), p["deaths"], p["mg_ammo"], p["grenade_ammo"],
				p["fire_cd"], p["broke_timer"], p["roll_ticks"], p["roll_cd"], p["roll_buf"],
				p["boost_ticks"], p["in_tank"], int(p["vest"]), p["hurt_iframes"], p["pierce_ticks"], p["spread_ticks"],
				int(p["triple"]), p["rend_ticks"], p["smoke_ticks"], p["claymores"]]:
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
		h = feed.call(e.get("hp", 0), h)   # MG Nest armor (other kinds have none)
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
	h = feed.call(barrels.size(), h)
	for bl in barrels:
		h = feed.call(bl["x"], h)
		h = feed.call(bl["y"], h)
		h = feed.call(int(bl["armed"]), h)
		h = feed.call(bl.get("fuse_ticks", 0), h)   # chain-fuse countdown
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
