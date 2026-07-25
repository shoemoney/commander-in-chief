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
const WALL_CRACK_HITS := 6                   # c4 2v: bullets to breach a kind-2 ruined-wall slab (1 explosion breaches instantly)
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
# Grenadier: mid-range zoner that lobs a telegraphed area strike. The lob is a
# CLUSTER of three walked ACROSS the firing line — that is the whole difference
# between him and the drone, who calls one precise circle from the same
# _add_strike. Drone = step off the spot; grenadier = a wall you have to break
# lengthwise (run at him or away from him, never sideways).
const GRENADIER_STANDOFF := 150 * F_ONE
const GRENADIER_FIRE_CD_TICKS := 130
const GRENADIER_WINDUP_TICKS := 40
const GRENADIER_CLUSTER_SPREAD := 44 * F_ONE   # perpendicular offset of the outer two lobs
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
# Ghillie: a cloaked marksman dug into LAND. Sits 'submerged' (no threat arrow,
# bullet-immune) until you enter notice range, briefly reveals, paints, fires ONE
# shot — and then VANISHES again. That fire-and-vanish is the whole difference
# between him and the sniper: the sniper stands there and can be traded with at
# any time, the ghillie only exists inside a reveal→paint window, so the counter
# is to rush the grass and kill him before he sinks back in. fire_cd doubles as
# the post-shot cloak lockout. Reuses submerged/surface_ticks/windup/aim_lx/
# aim_ly/fire_cd — no new hashed field.
const GHILLIE_NOTICE_RADIUS := 210 * F_ONE
const GHILLIE_REVEAL_TICKS := 26
const GHILLIE_RECLOAK_TICKS := 90   # reveal(26)+paint(55) after it ≈ the sniper's 170t cadence
const ENEMY_TOUCH_RADIUS := 10 * F_ONE
# Landmines: deterministic field hazards. Any grounded unit (player on foot, or
# an enemy) that steps within the trigger radius detonates them via _explode() —
# herd rushers onto them, or respect them yourself. Rolling clears them safely.
const MINE_TRIGGER_RADIUS := 9 * F_ONE
const MINE_SPACING := 340 * F_ONE
const BARREL_SPACING := 420 * F_ONE
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
# c2 2v (both reviewers' #1 pick): the ratchet camera anchored the player at
# 44% down-screen (160/360), so top-of-screen hazard drops gave no reaction
# time. 260 anchors the player at 72% down (lookahead +62%), turning blind
# top-edge deaths into readable ones. Retreat room to the +344 clamp is 84px;
# 288 (literal bottom-20%) would leave only 56px, so 260 is the tuned floor.
const CAMERA_LEAD := 260 * F_ONE
const BUNKER_W := 48 * F_ONE
const BUNKER_H := 32 * F_ONE
# Dodge roll: 0.3 s i-frames, 1.2 s cooldown, 2× speed in the move direction.
# A press up to ROLL_BUFFER_TICKS early is queued and fires when the roll is ready.
const ROLL_TICKS := 18
const ROLL_CD_TICKS := 72
const ROLL_BUFFER_TICKS := 8
const GRENADE_BUFFER_TICKS := 8   # parity with the roll buffer — see _step_players
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
# c3 3v: the 72%-down camera makes the rear hemisphere fully safe, rewarding a
# mindless hold-up advance. A low-density REAR TRICKLE (1 rusher chasing north
# per 700px of advance, seg 2+ only) and a stall-keyed CHOKE-CAMP breach put
# threat behind you. Both campaign-only + gated deep enough that the ~1260px
# torture never triggers them → goldens byte-identical.
const REAR_TRICKLE_SPACING := 700 * F_ONE
const REAR_TRICKLE_START := -(2400 * F_ONE)   # first trickle once the camera passes seg-2+400 (torture stops at ~-1520)
const REAR_CAMP_TICKS := 300                  # 5s camping a choke before the rear answers (earlier/softer than the 480t Observer)
const REAR_WARN_TICKS := 90                    # c4 2v: 1.5s lead warn before a rear-trickle spawn (>= the 24t reaction floor)
const OBSERVER_STRIKE_CD_TICKS := 90
const STRIKE_TELEGRAPH_TICKS := 45
# Blind-fire scatter (px, RAW): how far a mortar/volley aimed at a CONCEALED
# target can miss. Deliberately > the 28px GRENADE_RADIUS kill ring, so a shell
# fired into smoke is a coin flip on the ring rather than a guaranteed hit —
# concealment DEGRADES area fire instead of switching it off. See _blind_scatter.
const BLIND_SCATTER_RAW := 44
const OBSERVER_DESPAWN_ADVANCE := 150 * F_ONE
const OBSERVER_Y_OFFSET := 14 * F_ONE
# Gates: a full-width barrier every 1000 world units, flanked by two bunkers;
# both bunkers down = gate opens and becomes the checkpoint. (Greybox gates
# block movement and camera, not bullets — the arena bunkers sit south of the
# wall and are fought from below.)
const GATE_SPACING := 1000 * F_ONE
const GATE_BLOCK_PAD := 14 * F_ONE
# Arena templates (9/9 panel: every bunker-pair gate was the identical room).
# Intended difficulty ramp: gate 1 (baseline, teaches the rules) < gate 2
# (staggered depth: angled fight, mines punish the straight line) < gate 4
# (crossfire pinch: tighter seam + live ordnance mid-arena). The barrel
# cluster is a tool AND a hazard — its chain must never trivially kill the
# bunkers (test-pinned below at >GRENADE_RADIUS from both).
# Pure _gate_counter lookup — ZERO rng draws (any draw here would shift the
# shared stream-rng for every mine/barrel after it). Gate 1 = the exact
# classic literals (torture-safe, byte-identical); positions are plain ints,
# *F_ONE at the use site. props: [kind, x, y_off] with kind "mine"/"barrel".
const ARENAS := {
	1: {"b1": [180, 50], "b2": [412, 50], "props": []},
	2: {"b1": [300, 150], "b2": [160, 40], "props": [   # staggered depth: a front
		["mine", 240, 100], ["mine", 350, 60]]},        # sentinel screens the rear
	4: {"b1": [240, 50], "b2": [368, 50], "props": [    # crossfire-close: barrels
		["barrel", 290, 120], ["barrel", 306, 120], ["barrel", 322, 120],   # center seam, held
		["mine", 120, 70], ["mine", 500, 70]]},   # >blast+AABB reach of both locks (test-pinned)
	# c2-authored-campaign: gate 5 was "final" pre-P3.6 (FINAL_GATE_INDEX==5) and
	# never ran this branch at all. Now a regular arena wearing the CRASHED
	# CONVOY (RUINS) landmark — a staggered depth pair (mirrors gate 2's read,
	# but the mine sits BEHIND b2 instead of in front, so the two staggered
	# gates don't play identically) with a held center barrel pair.
	5: {"b1": [340, 130], "b2": [180, 40], "props": [
		["mine", 190, 90], ["barrel", 320, 110], ["barrel", 336, 110]]},
}
# Zone identity (authored-campaign-and-modes): the narrative/UI name for the
# stretch CULMINATING in each gate — index i is gate (i+1), so this indexes
# 1:1 with _gate_counter (and with ARENAS' per-sector landmark above). Pure
# flavor data (name shown by the Chapter Select screen + the zone-arrival
# banner, blurb shown on the Chapter Select row) — reading it never touches
# gameplay state, so it carries zero checksum/determinism risk.
const ZONE_INFO: Array[Dictionary] = [
	{"name": "STAGING GROUND", "blurb": "The LZ perimeter. Two bunkers, no surprises — learn the rules here."},
	{"name": "MARSH BASIN", "blurb": "Flooded pipeline flats. Grenades drift on the water; frogmen surface from the fords."},
	{"name": "BRIDGE GUNSHIP", "blurb": "A lone gunship holds the span — no bunkers here, the boss IS the lock."},
	{"name": "FOUNDRY WORKS", "blurb": "The ironworks quarter. Heat vents cook the approach on a cycle — time the crossing."},
	{"name": "CRASHED CONVOY", "blurb": "A derailed supply train wedged across the road, dug in and defended."},
	{"name": "THE FOUNDRY CORE", "blurb": "The Colossus's throne. No revives past this line — finish it."},
]
# Per-sector special roster — index i is the stretch culminating in gate i+1, so
# it lines up 1:1 with ZONE_INFO above. The field spawner draws its specials from
# THIS list, so each authored zone fields its own threat vocabulary instead of the
# old flat grenadier/sniper/shield/mg_nest roll running unchanged from sector 2 to
# the finale. Sector 1 stays empty on purpose (ZONE_INFO: "no surprises — learn
# the rules here"). Every entry must be a kind the spawner can build (see
# _spawn_special / _spawn_mg_nest / _spawn_broadcast) — test-pinned.
const SECTOR_SPECIALS: Array[Array] = [
	[],                                    # 1 STAGING GROUND — rushers and elites only
	["grenadier", "sapper"],               # 2 MARSH BASIN — area denial across the flats
	["sniper", "mg_nest"],                 # 3 BRIDGE GUNSHIP — long open span, rooted guns
	["shield", "technical"],               # 4 FOUNDRY WORKS — armor down the vent lanes
	["ghillie", "broadcast", "sapper"],    # 5 CRASHED CONVOY — dug in among the wreckage
	["drone", "grenadier", "mg_nest", "shield"],   # 6 THE FOUNDRY CORE — the throne bombards
]
const GATE_CAMERA_PAD := 60 * F_ONE
# Flak Vest: absorbs exactly one hit, then a mercy window.
const VEST_IFRAME_TICKS := 90
# Endless War: escalating waves with a between-wave War Chest shop.
const WAVE_BASE_ENEMIES := 4
# Dynamic arena geometry (c2 4v): every ARENA_SHIFT_CADENCE-th wave SCARS one
# rock out (floor ARENA_ROCK_FLOOR) and DROPS a fresh 3-bag L from this
# authored slot table. Anchors are play-placed: every slot keeps >= 44px
# (HULL_CLEARANCE) from arena walls and >= 44px center-distance from every
# static quadrant-rock coord (statically asserted in test_endless).
const ARENA_SHIFT_CADENCE := 3
const ARENA_ROCK_FLOOR := 2
const ARENA_L_SLOTS := [
	[250, -60], [390, -288], [200, -180], [440, -180], [320, -48], [320, -312],
]
const ARENA_LAYOUTS := [
	[[0, 0], [0, -24], [24, 0]],                    # 0 corner L (the exact classic stub)
	[[-33, 0], [-11, 0], [11, 0], [33, 0]],         # 1 barricade belt (horizontal line)
	[[0, 0], [0, -26], [0, -52], [0, -78]],         # 2 wreck line (vertical column)
]
const WAVE_ENEMIES_PER_WAVE := 2
const WAVE_SPAWN_INTERVAL_TICKS := 20
const WAVE_INTERMISSION_TICKS := 300
const SHOP_AMMO_COST := 30
const SHOP_GRENADE_COST := 30
const SHOP_VEST_COST := 60
const SHOP_AIRSTRIKE_COST := 100
# Spend-wheel prices by supply kind (0 ammo, 1 grenade, 2 vest, 3 airstrike).
const SHOP_SANDBAG_COST := 40        # starting value (grenade 30 < bag < vest 60); test: a scripted endless bot should buy 1-3/run
const HULK_TICKS := 1050             # starting value, mid of the panel's 900-1200 band; test: block flips off at exactly 0
const HULK_HALF_W := 16 * F_ONE      # dead-hull cover AABB (center-point tanks, unlike corner-origin bunkers)
const HULK_HALF_H := 12 * F_ONE
const SANDBAG_FIELD_CAP := 6         # starting value: 6 x 36px = 216px can never wall the ~592px lane
const SANDBAG_HALF_W := 18 * F_ONE   # segment is 36x10 px — rushers must flank in under ~2s
const SANDBAG_HALF_H := 5 * F_ONE
# Collidable rocks (9/9 panel: cover-shaped decor with no collision LIED in a
# one-hit game). Streamed rng-FREE (Knuth-hash of the spacing index) so the
# shared stream-rng sequence is untouched; campaign-only.
# Corridor chokes (7v: the lane is a constant 608px tube): from segment 2 on,
# each between-gate stretch bites one flank down to a 368px lane. Pure
# function of y — no state, no rng, nothing hashed; segments 0-1 stay open
# (the calm opening act + the torture window = inert by construction).
# Authored hazard chunks (4v: flat global spacings made every minefield the
# same). Chunk pitch keeps the old constants; the BODY is an authored table,
# picked by a pure integer mix of (slot, run seed) — ZERO rng draws, so
# per-seed variety survives and the shared stream sequence has NO draws left
# to shift. [dx, dy] px offsets from the chunk anchor.
const MINE_CHUNKS := [
	[], [],
	[[0, 0]],
	[[-120, 40], [-60, 20], [0, 0], [60, 20], [120, 40]],
	[[-135, 0], [-90, 20], [-45, 40], [45, 40], [90, 20], [135, 0]],
	[[-90, 0], [-30, 0], [30, 0], [90, 0], [-60, 60], [0, 60], [60, 60], [120, 60]],
	[[0, 0], [0, 40], [40, 40], [80, 40], [80, 0], [80, -40]],
	[[-50, 0], [10, 30], [70, -10]],
]
const BARREL_CHUNKS := [
	[],
	[[0, 0], [18, 0]],
	[[0, 0], [18, 0], [90, 0], [108, 0], [180, 0], [198, 0]],
	[[-60, 0], [-20, 0], [20, 0], [60, 0]],
	[[0, 0], [18, 0], [9, 30]],                       # tripod stack
	[[-80, 0], [80, 0]],                              # split pair — thread the middle
	[[0, 0], [40, 24], [80, 48], [120, 72]],          # diagonal drip
]
# Biome-exclusive verbs (c2 5v: sectors were palette swaps that all play
# identically). Two campaign-only mechanics, both past the golden window:
# seg-2 marsh water drifts airborne grenades; seg-4+ foundry rows grow heat
# vents on an authored-chunk cadence (MINE_CHUNKS pattern, _mix-picked, zero
# rng draws). Vent chunk pitch is >= 100px so every lane between 24px hurt
# discs clears HULL_CLEARANCE (100 - 2*24 = 52 >= 44, pinned by test).
const MARSH_SEG := 2
const MARSH_DRIFT := F_ONE           # 1px/tick sideways while airborne over marsh water
const FORD_CURRENT := F_ONE / 2      # c3 2v: 0.5px/tick sideways shove on a deep-river (band>=2) crossing
const MUD_SURFACE_RADIUS := 90 * F_ONE  # c3 2v: stepping into deep-river mud pops lurking frogmen within 90px
const VENT_START_SEG := 4
const VENT_SPACING := 300 * F_ONE   # 300 (not 460): after the apron/water/gate keep-outs eat their rows, seg 4 must still KEEP >= 2 vent rows (-4200/-4800; test-pinned) — at 460 the campaign foundry surfaced zero
const VENT_CYCLE_TICKS := 180        # full cycle; jet holds the final 60
const VENT_JET_TICKS := 60
const VENT_WARN_TICKS := 30          # >= the 24t reaction floor (KIMK r4 precedent)
const VENT_HURT_RADIUS := 24 * F_ONE
const VENT_COVER_BURN_TICKS := 120   # c3 5v: ~2s of a vent jet burns off grass / cracks a wall slab
const BREAKWATER_SLACK := 6 * F_ONE  # c3 5v: the grenade must be within a cover half-extent + this touch margin of the rock face for it to shadow the drift
# c3 3v: the endless central mast (a 360-degree cover pivot at SCREEN_CX,-180)
# periodically BURNS its own orbit — a phase-timed radial pulse (the vent
# telegraph pattern) that hurts any player hugging it, denying the infinite
# kite. Pure function of tick_count: no new state, no rng, endless-only + wave
# 5/10/15 = past the wave-2 endless wipe, so ENDLESS_GOLDEN is byte-identical.
const MAST_X := SCREEN_CX
const MAST_Y := -180 * F_ONE
const MAST_HAZARD_RADIUS := 120 * F_ONE   # > the ~64px sandbag diamond, so hugging cover doesn't save you
const MAST_CYCLE_TICKS := 180
const MAST_JET_TICKS := 60
const MAST_WARN_TICKS := 90                # 1.5s tell — a fat 120px one-shot zone earns a longer warn than the vent's 30t
# c3 2v: connective cover reads as scatter between setpieces. Authored concave
# 3-piece POCKETS (mouth opening SOUTH, toward the player) turn the ambient
# stream into committed fight-geometry. Pieces are classic (16px half) or grass
# (non-solid), so every intra-pocket lane clears HULL_CLEARANCE by geometry
# (flanks >= 80px apart → 48px lane > 44). [dx, dy] px from the row anchor.
const COVER_POCKETS := [
	[[-40, 0], [40, 0], [0, -40]],     # C-pocket: two flanks + a back stone
	[[-46, 0], [38, -24], [0, 40]],    # staggered wedge
	[[0, -44], [-46, 10], [46, 10]],   # back wall + two wings
	[[-44, -10], [44, -10], [0, 30]],  # V-mouth facing south
]
# c4 3v: 4-part ROOM grammar (richer than the 3-piece pocket) for 1-in-3 seg>=2
# stream rows — a MOUTH (2 kind-0 solids facing SOUTH, 48px gap) -> an INTERIOR
# island (kind-0 rock or kind-3 hero) -> a REAR gate (kind-1 grass conceal strip
# or kind-0 corner posts, 48px gap). Every intra-room lane clears HULL_CLEARANCE.
# [dx, dy, kind] px from the row anchor; +dy is SOUTH (the mouth the player enters).
const COVER_ROOMS := [
	[[-40, 55, 0], [40, 55, 0], [0, 5, 3], [0, -48, 1]],                 # mouth -> hero island -> grass rear
	[[-40, 55, 0], [40, 55, 0], [0, 0, 0], [-64, -48, 2], [64, -48, 2]],  # mouth -> rock island -> kind-2 SIDE-DOOR rear (48px gap)
	[[-44, 55, 0], [44, 55, 0], [0, 0, 1], [-40, -46, 0], [40, -46, 0]], # mouth -> grass core -> rear posts
	[[-40, 58, 0], [40, 58, 0], [0, 8, 3], [0, -46, 1]],                 # wide mouth -> hero island -> grass rear
]
const VENT_CHUNKS := [
	# No empty chunks (unlike MINE_CHUNKS): seg 4 keeps only ~2 rows after the
	# keep-outs, so an empty roll on both would erase the mechanic for that
	# seed. Mines have ~15 rows to absorb empties; the foundry doesn't.
	[[0, 0]],
	[[-100, 0], [100, 0]],
	[[-100, -60], [0, 0], [100, 60]],   # diagonal sweep
	[[-150, 0], [0, 40], [150, 0]],     # wide tripod
]
# KIMK round-4 provenance: HULL_CLEARANCE is ANCHORED, not free — it derives
# from the hull it names plus a pinned positive margin, and a central test
# asserts the equation. COMPARATOR CONTRACT (stated once, here): consumers
# test passage >= HULL_CLEARANCE; the margin absorbs the boundary, so exactly
# 44 clears with 12px to spare — no off-by-one drift at the seam.
const HULL_W := 2 * HULK_HALF_W      # the hull footprint the constant serves (32px)
const HULL_MARGIN := 12 * F_ONE      # pinned > 0: clearance is never zero-thread
const HULL_CLEARANCE := HULL_W + HULL_MARGIN
const FLANK_SQUAD := 3               # 2v flank doors: squad size per side (starting value)
const FLANK_DOOR_Y := 140 * F_ONE    # door row south of the gate
const FLANK_WARN_TICKS := 45         # c2 2v: 0.75s dust-fall tell BEFORE any breach (> the 24t reaction floor)
const FLANK_STAGGER_TICKS := 30      # c2 2v: 0.5s between the two walls (no simultaneous double-pinch)
const MUD_BANK_H := 40 * F_ONE   # 2v: muddy approaches flank every river (roll legal, tanks unaffected)
const CHOKE_START_SEG := 2
const LANE_BLOCK_CYCLE := 1200               # c4 2v: full temporary-lane-seal cycle (20s)
const LANE_BLOCK_SEALED := 720               # sealed portion of the cycle (12s)
const LANE_BLOCK_WARN := 45                  # 0.75s dust tell before a seal
const BUNKER_EXCLUSION := 48 * F_ONE   # c2 4v: hazard keep-out ring around streamed bunkers (= BUNKER_W)
const FORK_GATES := [2, 4]             # the route-fork gates: their approach band is a cover-free decision apron
# c2 3v BREATHING CURVE: one whole-band calm beat — the pre-Foundry exhale.
# The band right before the Foundry stands down its ambush litter: no mines,
# no barrels, no choke, no blockade. The seg-4+ foundry VENTS stay — the
# breath has heat, not ambush; a self-telegraphing biome verb IS the
# "you've arrived somewhere" story. seg >= 2 by value, so golden-inert.
# c2-authored-campaign: tracks FINAL_GATE_INDEX - 1 (4 -> 5 when the finale
# moved from gate 5 to gate 6) so the exhale always sits immediately before
# whichever gate is the actual finale.
const CALM_BAND_SEG := 5
const RUINS_SEG := 3               # c3 5v: the ruins sector — dog-leg maze chokes, wall-heavy cover, half-speed rubble
const CHOKE_OFF_LO := 150 * F_ONE
const ROCK_SPACING := 260 * F_ONE
# Cover TIERS (c2 3v: one-size rocks made every LOS puzzle "is there a rock
# between us"). Each streamed cover carries a "kind"; extents + solidity read
# from this table (art == collision holds — the view scales each sprite to
# match). Kind is DERIVED from the row hash at spawn and stored, but NOT fed to
# the checksum (the feed stays x,y). Grass changes bullet lifetimes and the
# other tiers change extents, so variety is gated to COVER_VARIETY_SEG (the
# blockade "gates 2+ = past torture" precedent) — segs 0-1 stay all-classic,
# so both goldens are inert by construction.
#   0 classic rock  16x12  blocks all           (the shipped tier)
#   1 tall grass    28x20  blocks NOTHING        (conceals — smoke's gates)
#   2 ruined wall   40x10  blocks all            (wide mass, narrow lanes)
#   3 hero wreck    32x24  blocks all, drawn 2x  (a focal silhouette)
const ROCK_KIND_EXT := [[16, 12, 1], [28, 20, 0], [40, 10, 1], [32, 24, 1]]
const COVER_VARIETY_SEG := 2
# Foundry escape corridor (c2 3v): the crush-radius-26 colossus corners a
# player against wall-hugging debris. Guarantee a debris-free margin at BOTH
# walls of the final approach (seg >= COLOSSUS_ARENA_SEG). 96 >= the asked 80
# and > 2*HULL_CLEARANCE (88), so a hull always slips the margin (comparator
# contract). Pure x-clamp on streamed hazards; seg 4+ is far past the torture
# reach, so both goldens are inert.
const ARENA_MARGIN := 96 * F_ONE
const COLOSSUS_ARENA_SEG := 4
const SUPPLY_COSTS: Array[int] = [SHOP_AMMO_COST, SHOP_GRENADE_COST, SHOP_VEST_COST, SHOP_AIRSTRIKE_COST, SHOP_SANDBAG_COST]
# Foundry Colossus: the finale. A fortress-crawler that inverts the scroll —
# it advances DOWN the map at the players. Armor: grenades only. Three
# phases by HP thirds. Engaging it triggers the Last Stand rule: no more
# War Chest revives; on victory the remaining chest converts to score.
# c2-authored-campaign: 5 -> 6 gates. Gate 5 (previously final) is now a
# regular bunker arena wearing the RUINS crashed-convoy landmark that used to
# be dead code (lm_sector case 3 could never fire -- gate 3 is always the
# boss gate). The Foundry Colossus finale just moves one gate deeper; nothing
# else reads this const positionally, so the shift is torture-inert (the
# 60s campaign torture never streams past gate ~2 -- see test_determinism.gd).
const FINAL_GATE_INDEX := 6
const COLOSSUS_HP := 60
const COLOSSUS_GRENADE_DAMAGE := 2
const COLOSSUS_SPEED := F_ONE / 2
const COLOSSUS_HIT_RADIUS := 34 * F_ONE
const COLOSSUS_CRUSH_RADIUS := 26 * F_ONE
const COLOSSUS_RING_INNER := 60              # c4 2v: inner melee-risk ring radius (>= crush 26)
const COLOSSUS_RING_OUTER := 160             # inner/outer boundary at phase 1
const COLOSSUS_RING_STEP := 40               # each phase rise pushes the safe annulus +40px outward
const COLOSSUS_SPRAY_CD_TICKS := 30
const COLOSSUS_VOLLEY_CD_TICKS := 120
const COLOSSUS_SPAWN_CD_TICKS := 90
const COLOSSUS_SWEEP_CD_TICKS := 150   # c3 3v: 2.5s between lane-sweep mortars when the player PARKS in a Foundry side lane (the retreat stays fair; camping it costs you)
const FLUSH_RADIUS := 100 * F_ONE      # c3 2v: an enemy this close to a grass-camper lobs a flush grenade
const FLUSH_CD_TICKS := 600            # 10s between flushes — grass conceals, but sitting in it near a threat costs you
# Core window: every cycle the plating retracts for a beat during which
# BULLETS also chip the Colossus — a timing/aggression path for a dry pool.
# The window is 90 of every 330 ticks (27% uptime), so the per-hit number has to
# carry the whole mechanic: at 3 dmg a full open window pays 90/8*3 = 33, while
# grenades — never gated by the window — pay 330/30*2 = 22 over the same cycle.
# The fight shouts "WAIT FOR THE CORE / OPEN FIRE"; these two numbers are what
# make that the profitable read instead of a lie (test_core_window_is_the_payoff).
const COLOSSUS_CORE_CYCLE_TICKS := 240
const COLOSSUS_CORE_OPEN_TICKS := 90
const COLOSSUS_BULLET_DAMAGE := 3
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
const BOSS_CYCLE_TICKS := 300
# How much of the cycle act one (the strafing run) owns; the mortar act owns the
# rest. This used to be an implicit BOSS_CYCLE_TICKS / 2 = 180, which put the
# first shell at t=200 — but a 1P campaign gunship (40 HP, 1/bullet at an 8t
# cooldown, 8/grenade at a 30t cooldown + 32t airtime) dies somewhere between
# ~150 ticks (a perfect five-frag rush) and ~320, so the whole mortar act and
# its telegraph kit was content most runs never reached. Act one now ends at
# 120: even the theoretical fastest kill crosses it, and the mortar act keeps
# its full 180-tick shape, so the fight is not one tick longer.
const BOSS_STRAFE_TICKS := 120
# The four gunship-arena cover bags as [x, y_off_from_gate] pairs — the ONE
# source of truth shared by the arena authoring AND the rotating-denial
# invalidator, so a denied spot can never drift off a real bag.
const GUNSHIP_COVER_BAGS := [[164, 120], [200, 120], [432, 200], [468, 200]]
const BOSS_SPRAY_INTERVAL_TICKS := 12
const BOSS_BOUNTY := COIN_BUNKER * 4
# Mortar volley: the strike ticks within the mortar act, by endless tier —
# deeper waves add a 4th (tier >= 2) and 5th (tier >= 3) shell at the same
# +40/+60 spacing they always had. Read through boss_mortar_ticks() so the sim
# and the HP-bar countdown can never disagree about which shells exist.
const BOSS_MORTAR_TICKS := [140, 180, 220]
const BOSS_MORTAR_TICKS_T2 := [140, 180, 220, 260]
const BOSS_MORTAR_TICKS_T3 := [140, 180, 220, 260, 280]
# Boss Rush mode (authored-campaign-and-modes): every gate is a gunship, back
# to back, capped by the same Foundry Colossus finale campaign ends on — a
# practice/replay mode for the fights, no field filler between them. Gates are
# pre-authored in _setup_boss_rush() rather than streamed by _step_camera
# (which no-ops entirely for this mode — see the mode guard there).
const BOSS_RUSH_COUNT := 3          # gunships fought before the Colossus caps the run
const BOSS_RUSH_HP_STEPS: Array[int] = [0, 14, 32]  # non-linear escalation knob
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
var rocks: Array[Dictionary] = []      # streamed natural hard cover {x,y} — blocks moves+bullets, grenades arc over
var _next_rock_y: int = 0
var _next_rear_y: int = 0   # c3 3v: next camera-advance mark that births a rear-trickle rusher
var _rear_warn_ticks: int = 0   # c4 2v: rear-spawn lead-warn countdown (camera-derived, unhashed; 0 in both torture windows)
var _rear_warn_x: int = 0       # c4 2v: the wall the pending rear rusher spawns from
var _world_seed: int = 0   # stored run seed for the authored-chunk mixes (derived, unhashed)
var barrels: Array[Dictionary] = []
var vents: Array[Dictionary] = []      # foundry heat vents {x,y} — seg 4+ only, phase derived from tick_count
var _next_vent_y: int = 0
var observer: Dictionary = {}
var war_chest: int = 0
var score: int = 0
var camera_top: int = 0
var last_gate_y: int = 0          # 0 = no checkpoint yet (sentinel)
var stall_ticks: int = 0
var mode: String = "campaign"     # "campaign" | "endless"
var wave: int = 0
var wave_start_tick: int = 0       # c3 3v: tick the current wave began (derived; not hashed) — the mast hazard's phase is wave-LOCAL so its warn always precedes the first jet
var wave_pending: int = 0
var wave_spawn_cd: int = 0
var wave_mod: int = 0              # endless-only wave mutator (0 none, 1 blitz, 2 elite-guard, 3 spotter, 4 payday, 5 night, 6 frenzy, 7 marksmen, 8 bombardment)
var pressure_side: int = -1        # c3 7v: endless spawn pressure quadrant (0 left/1 center/2 right, -1 none); rotates every 3rd wave so the camp SPOT migrates
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
var vest_buys: int = 0             # campaign vest-price creep (9v: flat 60 read as a
                                   # subscription); run-scoped, never reset on death.
var tokens: int = 0                # Commendation Orders (9/9 panel: the score->power bridge) —
                                   # minted by PLAY (streak-20, flawless gates), never coin-buyable,
                                   # cap 2, wiped on death. Spent via the wheel for a free supply call.
var deaths_this_wave: int = 0      # endless: for the Clean Wave bonus
var _prev_camera_top: int = 0


func _init(seed_value: int, player_count: int, game_mode: String = "campaign") -> void:
	mode = game_mode
	rng = SimRng.new(seed_value)
	camera_top = -VIEW_H
	_prev_camera_top = camera_top
	if game_mode == "endless":
		# Endless-arena identity (9/9 panel: the arena had ZERO spatial
		# character vs campaign). Sixteen authored sandbag emplacements — four
		# 3-bag L-stubs anchoring the quadrants + a 4-bag diamond ringing the
		# central landmark. Constant coords, no rng; destructible like player
		# bags (rebuild via the 40-coin shop bag IS the intended loop).
		for eb in [[140, -250], [500, -250], [140, -110], [500, -110]]:
			sandbags.append({"x": eb[0] * F_ONE, "y": eb[1] * F_ONE})
			sandbags.append({"x": eb[0] * F_ONE, "y": (eb[1] - 24) * F_ONE})
			sandbags.append({"x": (eb[0] + (24 if eb[0] < 320 else -24)) * F_ONE, "y": eb[1] * F_ONE})
		for db in [[320, -212], [320, -148], [288, -180], [352, -180]]:
			sandbags.append({"x": db[0] * F_ONE, "y": db[1] * F_ONE})
		# Quadrant rocks are REAL cover (KIMK: art that reads as cover must
		# BE cover) — they ride the full rock grammar: bullets, boots, treads.
		for qr in [[80, -300], [560, -300], [80, -60], [560, -60], [210, -320], [430, -50]]:
			rocks.append({"x": qr[0] * F_ONE, "y": qr[1] * F_ONE})
	elif game_mode == "campaign":
		_author_lz()
	_next_bunker_y = -(500 * F_ONE)
	_next_gate_y = -GATE_SPACING
	_next_tank_y = -(750 * F_ONE)
	_next_water_y = -(1500 * F_ONE)
	_next_mine_y = -(700 * F_ONE)
	_next_rear_y = REAR_TRICKLE_START
	_next_barrel_y = -(900 * F_ONE)
	_next_rock_y = -(700 * F_ONE)
	_world_seed = seed_value
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
			"roll_ticks": 0, "roll_cd": 0, "roll_buf": 0, "roll_prev": false,
			"grenade_buf": 0, "fire_prev": false,
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
			"flush_cd": 0,   # c3 2v: tall-grass flush-grenade cooldown (0 = clear; runs only while camping grass near enemies)
		})
	if game_mode == "boss_rush":
		# Called AFTER players[] above (not from the game_mode branch further up)
		# so _scaled_boss_hp sees the real roster -- a 2P Boss Rush escalates HP
		# the same way every other boss fight in the game does.
		_setup_boss_rush()


func _setup_boss_rush() -> void:
	## Boss Rush (authored-campaign-and-modes): BOSS_RUSH_COUNT gunships back-
	## to-back, each escalating per BOSS_RUSH_HP_STEPS (a non-linear per-boss
	## knob table -- design can retune any single fight without reshaping the
	## whole ramp), capped by the same Foundry Colossus finale campaign ends on
	## (colossus engage/victory/last-stand are all mode-agnostic already -- see
	## _step_colossus). Gates are pre-authored here rather than streamed by
	## _step_camera (which no-ops entirely for this mode): it's a practice/
	## replay mode for the boss cadence, with no field filler between fights,
	## not a shrunk campaign.
	var gy := -GATE_SPACING
	for i in BOSS_RUSH_COUNT:
		_stamp_gunship_gate(gy, BOSS_RUSH_HP_STEPS[i], false)
		gy -= GATE_SPACING
	_stamp_final_gate(gy)
	_world_ended = true
	_next_gate_y = gy - GATE_SPACING   # belt-and-braces: _step_camera's mode guard already no-ops streaming
	_gate_counter = BOSS_RUSH_COUNT + 1


func jump_to_chapter(target_gate: int) -> void:
	## Arcade (authored-campaign-and-modes): start already at the mouth of
	## `target_gate`'s zone (1..FINAL_GATE_INDEX), skipping the chapters before
	## it, by priming every streaming cursor forward the same distance the
	## camera would have covered getting there. Safe because every streamed
	## pick keyed off these cursors (gate arena template, per-sector landmark,
	## mine/barrel/vent/rock chunk) is a pure function of ABSOLUTE world
	## position -- a Knuth-hash of a slot/gate index (_mix), never a
	## sequential rng draw -- so shifting every cursor by an identical amount
	## reproduces the same *kind* of catch-up streaming a fresh campaign start
	## does, just deeper in. (Only the gate 2/4 fork content and pickup-kind
	## rolls consume the shared rng stream sequentially; those come out as
	## valid but seed-shifted flavor rather than a bit-exact match to a
	## hypothetical continuous run -- fine for a practice jump, and it changes
	## nothing about determinism: same seed + same chapter always replays
	## identically.) No-op for chapter 1 (nothing to skip) and a no-op call
	## for any non-arcade mode never happens -- main.gd only calls this after
	## constructing an "arcade" SimWorld.
	target_gate = clampi(target_gate, 1, FINAL_GATE_INDEX)
	var skip: int = (target_gate - 1) * GATE_SPACING
	if skip <= 0:
		return
	camera_top -= skip
	_prev_camera_top = camera_top
	for p in players:
		p["y"] -= skip
	_next_bunker_y -= skip
	_next_gate_y -= skip
	_next_tank_y -= skip
	_next_water_y -= skip
	_next_mine_y -= skip
	_next_barrel_y -= skip
	_next_rock_y -= skip
	_next_vent_y -= skip
	_next_rear_y -= skip
	_gate_counter = target_gate - 1


static func zone_info(gate_idx: int) -> Dictionary:
	## The named zone CULMINATING in gate `gate_idx` (1..FINAL_GATE_INDEX) --
	## ZONE_INFO index gate_idx-1. Clamped so a caller past the finale (e.g.
	## "opened+1" right after the last gate) still gets a valid entry instead
	## of an out-of-bounds crash.
	return ZONE_INFO[clampi(gate_idx, 1, ZONE_INFO.size()) - 1]


func is_solo() -> bool:
	return players.size() == 1


func revive_cost(p: Dictionary) -> int:
	var cost: int
	if mode == "endless":
		# Endless has no ending, so the ONLY brake on a run is what a body costs.
		# The old rule (deaths capped at 3, +20/5 waves) topped out near 150 while
		# wave income climbed ~35/wave — the chest outran it ~9:1 and the wipe
		# became unreachable. Here deaths COMPOUND uncapped and the price is
		# wave-MULTIPLIED, so a fat late chest is one bad patch from zero: keep
		# clean and the surcharge never touches you, chain deaths and the run ends.
		cost = REVIVE_BASE_COST * maxi(p["deaths"], 1) * (1 + wave / 5)
	else:
		# Campaign keeps the soft cap at 3 deaths: with checkpoints and a finish
		# line, a linear ramp against flat kill income is just a death spiral.
		cost = REVIVE_BASE_COST * mini(p["deaths"], 3)
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
	# Last Stand terminal state (9v, campaign + solo endless): all fighters
	# down with no revives left latches the same `wiped` freeze endless wipes
	# already use — the debrief/restart plumbing all keys off it downstream.
	if last_stand and not victory and not wiped and _all_players_down():
		wiped = true
		events.append({"t": "wiped", "x": players[0]["x"], "y": players[0]["y"]})
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
		_step_mast_hazard()   # c3 3v: the central mast periodically denies its own orbit
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
	elif mode == "boss_rush":
		_step_boss()
		_step_colossus()
		_step_gates()
		_step_camera()   # ratchet + gate-hold only — the streaming appendix no-ops (mode != campaign)
		_step_observer()
		_resolve_strikes()
	else:
		_step_spawner()
		_step_mines()
		_step_barrels()
		_step_boss()
		_step_colossus()
		_step_gates()
		_step_camera()
		_step_observer()
		_step_grass_flush()   # c3 2v: tall-grass camping draws a flush grenade
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
		# Freeze the roll buffer for the duration of a roll. ROLL_BUFFER_TICKS is 8
		# but ROLL_TICKS is 18, so a press made DURING a roll — the single most
		# common way anyone queues the next dodge — always expired before the roll
		# ended and could never be honoured. The buffer only worked from a standstill.
		if p["roll_ticks"] <= 0:
			p["roll_buf"] = maxi(0, p["roll_buf"] - 1)
		p["grenade_buf"] = maxi(0, p["grenade_buf"] - 1)
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
			if inp.buy == 6:
				_try_token_drop(p)
			else:
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
		# Rising edge only. This used to be a level read, so HOLDING roll re-armed
		# the buffer every tick and auto-rolled the instant the cd expired — a free
		# perpetual i-frame chain (18 i-frames per 72 ticks) off one held button,
		# which also made the buffer meaningless (it only ever mattered for held
		# input). Tapping still buffers exactly as before.
		var roll_edge: bool = inp.roll and not p["roll_prev"]
		p["roll_prev"] = inp.roll
		if roll_edge:
			if wading:
				# Rolling is forbidden in water, and this was the last silent refusal:
				# the press either died quietly or sat in the buffer and auto-fired a
				# roll the instant you stepped onto dry land, which reads as the game
				# rolling on its own. Refuse it out loud and drop it. `events` is
				# checksum-excluded, so the deny cue itself is free.
				p["roll_buf"] = 0
				events.append({"t": "deny", "why": "water", "x": p["x"], "y": p["y"], "i": i})
			else:
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
		var rpx: int = p["x"]
		var rpy: int = p["y"]
		if p["roll_ticks"] > 0:
			p["roll_ticks"] = p["roll_ticks"] - 1
			p["roll_iframe"] = true
			p["x"] = p["x"] + Fixed.mul(p["roll_dx"], PLAYER_SPEED * 2)
			p["y"] = p["y"] + Fixed.mul(p["roll_dy"], PLAYER_SPEED * 2)
		elif moving:
			var spd := PLAYER_SPEED
			if p["boost_ticks"] > 0:
				spd = (PLAYER_SPEED * 3) / 2
			# Modifier composition rule (KIMK r2, pinned): slow zones do NOT
			# stack — wading OR wire OR mud is one halving, and boost applies
			# before it (a boosted wader runs 3/4 speed, not 3/8).
			if wading or _in_fork_wire(p["x"], p["y"]) or _in_mud(p["x"], p["y"]) \
					or _in_rubble(p["x"], p["y"]):
				spd = spd / 2
			elif _in_trench(p["x"], p["y"]):
				# c3 2v: a sunken trench drags the boots to 85% — the single strongest
				# slow wins (this elif only fires when no /2 zone does), never compounds.
				spd = (spd * 17) / 20
			p["x"] = p["x"] + Fixed.mul(Fixed.div(mx, mlen), spd)
			p["y"] = p["y"] + Fixed.mul(Fixed.div(my, mlen), spd)
		# c3 2v FORD CURRENT: a deep-river crossing shoves you sideways each tick
		# (drifts the firing origin, not the aim). Applies standing or moving; the
		# reverts below clamp it out of cover, so no softlock. Band 1 -> 0 -> golden.
		var fcur := _ford_current(p["y"])
		if fcur != 0:
			p["x"] = p["x"] + fcur
		# Fork wreck-island: full AABB move-revert (KIMK round-2: the old
		# nearest-edge snap POPPED on north entry; a revert lets you slide
		# along the face by strafing — geography, resolved like geography).
		for g2 in gates:
			var fx2: int = g2.get("fork_x", 0)
			if fx2 == 0:
				continue
			# c2 2v: the divider now spans +40..+620 (~1.7 screens) so the lane
			# choice is a real COMMITMENT — you can't switch mid-fork, only ride
			# your pick north to the gate (progress is always possible; only
			# lateral crossing is blocked, so no softlock under the ratchet).
			if p["y"] >= g2["y"] + 40 * F_ONE and p["y"] <= g2["y"] + 620 * F_ONE \
					and absi(p["x"] - fx2 * F_ONE) < 44 * F_ONE:
				if not (rpy >= g2["y"] + 40 * F_ONE and rpy <= g2["y"] + 620 * F_ONE \
						and absi(rpx - fx2 * F_ONE) < 44 * F_ONE):
					p["x"] = rpx
					p["y"] = rpy
				break
		# Parked/dead armor is solid to boots (2v hulk-cover; escape rule):
		for hk2 in tanks:
			if (hk2["alive"] and hk2["occupant"] < 0) or (not hk2["alive"] and hk2["burn_ticks"] > 0):
				if absi(p["x"] - hk2["x"]) <= HULK_HALF_W and absi(p["y"] - hk2["y"]) <= HULK_HALF_H:
					if absi(rpx - hk2["x"]) > HULK_HALF_W or absi(rpy - hk2["y"]) > HULK_HALF_H:
						p["x"] = rpx
						p["y"] = rpy
					break
		# Rocks are a hard wall to boots too (escape rule: a step that STARTED
		# inside — post-respawn edge case — may walk out).
		if not rocks.is_empty():
			for rk in rocks:
				if not _rk_solid(rk):
					continue   # grass conceals, never blocks the boot
				var rhw := _rk_hw(rk)
				var rhh := _rk_hh(rk)
				if absi(p["x"] - rk["x"]) <= rhw and absi(p["y"] - rk["y"]) <= rhh:
					if absi(rpx - rk["x"]) > rhw or absi(rpy - rk["y"]) > rhh:
						p["x"] = rpx
						p["y"] = rpy
					break
		# c4 2v: a SEALED lane-block is solid to boots — revert a step that ENTERS
		# it (escape-rule: a step started inside can still walk out). The open
		# opposite flank is the guaranteed bypass, so you reroute, never softlock.
		if _lane_blocked(p["x"], p["y"]) and not _lane_blocked(rpx, rpy):
			p["x"] = rpx
			p["y"] = rpy
		# c4 2v: the one-way ledge blocks a RETREAT step (southbound over the line).
		if _crosses_ledge_south(p["x"], p["y"], rpy):
			p["y"] = rpy
		# c4 2v: a keyed-encounter barricade is solid until you push past its midpoint.
		if _barricade_solid(p["x"], p["y"]) and not _barricade_solid(rpx, rpy):
			p["x"] = rpx
			p["y"] = rpy
		_clamp_actor(p)
		# c3 2v: stepping into deep-river MUD (band>=2) proactively SURFACES any
		# lurking frogman within MUD_SURFACE_RADIUS — reusing the frogman surface
		# path so the 30t harmless-telegraph fairness window holds by construction
		# (no instant lunge). The active answer to passive wading: step in to pop
		# the ambush and shoot it. Band 1 has no submerged frogmen in-window -> inert.
		if _in_mud(p["x"], p["y"]) and absi(p["y"] / GATE_SPACING) >= 2:
			for fr in enemies:
				if fr.get("kind", "") == "frogman" and fr.get("submerged", false) \
						and absi(fr["x"] - p["x"]) + absi(fr["y"] - p["y"]) <= MUD_SURFACE_RADIUS:
					fr["submerged"] = false
					fr["surface_ticks"] = FROGMAN_SURFACE_TICKS
					events.append({"t": "frogman_surface", "x": fr["x"], "y": fr["y"]})

		# Aim: decoupled from movement (the loop-lever identity).
		var ax: int = inp.aim_x * 256
		var ay: int = inp.aim_y * 256
		var alen := Fixed.length(ax, ay)
		if alen > F_ONE / 4:
			p["aim_x"] = Fixed.div(ax, alen)
			p["aim_y"] = Fixed.div(ay, alen)

		# Bash is edge-triggered too, for the same reason roll and grenade now are:
		# as a level read, simply HOLDING fire in a swarm auto-bashed a guaranteed
		# kill every 40 ticks with no further input. It was the last held-button
		# autopilot left in the kit.
		var fire_edge: bool = inp.fire and not p["fire_prev"]
		p["fire_prev"] = inp.fire
		if fire_edge and p["fire_cd"] == 0 and p["mg_ammo"] <= 0:
			# Empty-clip bash: one enemy in reach dies (no coin), on a long
			# cooldown — running dry is a beat of danger, not pure helplessness.
			var bashed := false
			if p["in_tank"] < 0:
				for e in enemies:
					if _enemy_strikeable(e) \
							and _dist_lte(p["x"], p["y"], e["x"], e["y"], BASH_RADIUS):
						# no_score too: bash guarantees a kill on a 40-tick cd while
						# KILL_STREAK_WINDOW_TICKS is 90, so an out-of-ammo player
						# parked in a swarm sustained the 20-kill streak (and its
						# 100% score bonus + token mint) forever at zero resource
						# cost — running dry was a leaderboard UPGRADE. Same rule
						# the airstrike already follows: unearned kills mint nothing.
						_kill_enemy(e, true, true)
						p["fire_cd"] = BASH_COOLDOWN_TICKS
						events.append({"t": "bash", "x": p["x"], "y": p["y"], "i": i})
						bashed = true
						break
			if not bashed:
				events.append({"t": "dry_fire", "x": p["x"], "y": p["y"], "i": i})
		elif inp.fire and p["fire_cd"] == 0 and p["mg_ammo"] <= 0:
			# Held fire on an empty clip still deserves the empty-mag click — the
			# edge gate above governs the BASH, not the feedback.
			events.append({"t": "dry_fire", "x": p["x"], "y": p["y"], "i": i})
		if inp.fire and p["fire_cd"] == 0 and p["mg_ammo"] > 0:
			p["fire_cd"] = FIRE_COOLDOWN_TICKS
			p["mg_ammo"] = p["mg_ammo"] - 1
			events.append({"t": "shot", "x": p["x"], "y": p["y"], "i": i})
			var fax: int = p["aim_x"]
			var fay: int = p["aim_y"]
			_spawn_mg_bullet(p, i, fax, fay)
			# Charge for the fan. A Triple/Trench burst spawned 3 (or 5 with both)
			# pellets for a SINGLE ammo decrement, so the permanent Triple mod was a
			# free 3-5x DPS multiplier and ammo stopped being a resource at all —
			# the softest sink in the game. One extra round per pellet PAIR keeps the
			# upgrade clearly worth taking while making it cost something.
			# Starting values (+1 for a 3-fan, +2 for a 5-fan); test: time-to-empty
			# from 99 should fall to roughly half the base gun's, not stay identical.
			# If Triple then feels punitive rather than powerful, drop the 5-fan to +1.
			if p["spread_ticks"] > 0 or p["triple"]:
				var fan_cost := 2 if (p["spread_ticks"] > 0 and p["triple"]) else 1
				p["mg_ammo"] = maxi(0, p["mg_ammo"] - fan_cost)
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

		# Grenade presses buffer like roll does. Grenade is the panic button AND the
		# only armor-cracker, yet it was the one verb with no buffer at all: a press
		# anywhere inside the 30-tick cooldown was discarded outright with no re-fire.
		# GRENADE_BUFFER_TICKS = 8 is parity with the shipped ROLL_BUFFER_TICKS (the
		# in-repo precedent). Test: tap grenade at cd-2/-4/-8 and assert 3/3 land.
		# If presses still feel eaten, step to 12.
		if grenade_edge:
			p["grenade_buf"] = GRENADE_BUFFER_TICKS
		if p["grenade_buf"] > 0 and p["grenade_cd"] == 0 and p["grenade_ammo"] > 0:
			p["grenade_buf"] = 0
			p["grenade_cd"] = GRENADE_COOLDOWN_TICKS
			p["grenade_ammo"] = p["grenade_ammo"] - 1
			events.append({"t": "throw", "x": p["x"], "y": p["y"], "i": i})
			grenades.append({
				"x": p["x"], "y": p["y"],
				"vx": Fixed.mul(p["aim_x"], GRENADE_SPEED),
				"vy": Fixed.mul(p["aim_y"], GRENADE_SPEED),
				"z": 0, "zv": GRENADE_ZVEL, "owner": i, "shell": false, "hold": true,
			})

		if inp.revive:
			_try_revive(i, p)

		if interact_edge and not _try_board_tank(i, p) and not _try_salvage_hulk(p) \
				and p["claymores"] > 0 and not _boardable_tank_near(p):
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
						or e["kind"] == "broadcast" \
						or not _dist_lte(p["x"], p["y"], e["x"], e["y"], ENEMY_TOUCH_RADIUS):
					continue
				_hurt_player(p)
				break

		# Pickups. Shop crates carry a price paid from the shared War Chest;
		# an unaffordable crate stays on the ground.
		if p["alive"]:
			_collect_pickups(p, i)


static func _mix(a: int, b: int) -> int:
	## Integer hash mix for authored-chunk picks — stream-loop randomness with
	## ZERO rng draws (the shared sequence stays untouched by construction).
	var v: int = (a * 2654435761) ^ (b * 40503)
	v = (v ^ (v >> 13)) * 1274126177
	return (v ^ (v >> 16)) & 0x7FFFFFFF


static func _rk_hw(rk: Dictionary) -> int:
	return ROCK_KIND_EXT[rk.get("kind", 0)][0] * F_ONE


static func _rk_hh(rk: Dictionary) -> int:
	return ROCK_KIND_EXT[rk.get("kind", 0)][1] * F_ONE


static func _rk_solid(rk: Dictionary) -> bool:
	## Kind 1 (grass) blocks nothing physically — it only conceals.
	return ROCK_KIND_EXT[rk.get("kind", 0)][2] == 1


static func _off_center_px(px: int) -> int:
	## c3 3v: pull an objective DROP out of the SCREEN_CX ±64px dead-band
	## ([256,384]) to the nearer lateral edge, so drops break the center rail
	## instead of reinforcing it. Same single draw folded IN PLACE — no new rng,
	## no sequence shift; only the drawn value moves. A dead-center 320 ties to
	## the right edge (384) by the `< 320` split.
	if px > 256 and px < 384:
		return 256 if px < 320 else 384
	return px


static func _rk_burnable(rk: Dictionary) -> bool:
	## c3 5v: soft cover a vent jet can destroy — grass (kind 1, burns off) and
	## wall slabs (kind 2, crack apart). Stone (0) and hero wrecks (3) are immune
	## ("stone doesn't burn"). One place for the kind filter + immunity read.
	var k: int = rk.get("kind", 0)
	return k == 1 or k == 2


func _in_grass(t: Dictionary) -> bool:
	## Tall-grass concealment (c2 3v): standing in a grass patch hides you from
	## enemy fire-acquisition exactly as smoke does. Bullets and boots pass
	## through (grass hides, it does not save) — the non-solid conceal tier.
	for rk in rocks:
		if rk.get("kind", 0) == 1 \
				and absi(t["x"] - rk["x"]) <= ROCK_KIND_EXT[1][0] * F_ONE \
				and absi(t["y"] - rk["y"]) <= ROCK_KIND_EXT[1][1] * F_ONE:
			return true
	return false


func _concealed(t: Dictionary) -> bool:
	## The unified fire-acquisition gate: smoke OR tall grass. Segs 0-1 stream
	## no grass, so in the torture window this is exactly the old smoke gate.
	return t["smoke_ticks"] > 0 or _in_grass(t) or _in_trench(t["x"], t["y"])


func _blind_scatter(t: Dictionary) -> Array:
	## THE CONCEALMENT RULE, in one place: smoke/grass/trench beats AIM, not AREA.
	##
	## `_concealed` still hard-gates every AIMED shooter (elite, sniper, technical
	## charge, gunship spray, colossus spray) — a bullet needs a target it can see.
	## AREA fire (grenadier lobs, drone paints, observer barrage, gunship mortars,
	## every colossus strike) no longer checks it at all; instead it takes this
	## offset, which is zero in the open and a BLIND_SCATTER_RAW-box miss when the
	## target is hidden. The shell still comes, it just lands where you probably
	## were — which is exactly what the 45t telegraph ring is FOR.
	##
	## Why this and not the alternatives: a cost/cooldown on smoke only delays the
	## off-switch (a supply drop re-arms it mid-siege), and a "boss sweeps the
	## smoke" reaction needs new hashed boss state for a rule the player still has
	## to be told. This one is a single sentence the HUD can teach, it keeps smoke
	## genuinely strong (every direct-fire threat in the game goes silent), and it
	## leaves both set-pieces with a live, dodgeable offense while you hide.
	if not _concealed(t):
		return [0, 0]
	# View-only teaching cue (events are checksum-excluded, so this is free).
	events.append({"t": "blind_shell", "x": t["x"], "y": t["y"]})
	return [rng.range_i(-BLIND_SCATTER_RAW, BLIND_SCATTER_RAW) * F_ONE,
		rng.range_i(-BLIND_SCATTER_RAW, BLIND_SCATTER_RAW) * F_ONE]


func _lane_blocked(x: int, y: int) -> bool:
	## c4 2v TEMPORARY LANE SEAL: a ~200x120 span on a hash-picked flank seals for
	## LANE_BLOCK_SEALED ticks each LANE_BLOCK_CYCLE (a >= HULL_CLEARANCE bypass
	## always sits on the opposite ~400px), reverting anyone who tries to cross it
	## — so the static corridor gains a reroute beat. Pure tick_count-derived phase
	## (no entity, no hashed field); campaign seg>=2 only, so torture (seg 0-1) and
	## endless (band 0-1) never see it -> both goldens byte-identical.
	if mode != "campaign":
		return false
	var band: int = absi(y) / GATE_SPACING
	if band < CHOKE_START_SEG:
		return false
	var lh := _mix(band, 733)
	var span_off: int = 250 + lh % 400
	var off: int = absi(y) % GATE_SPACING
	if off < span_off * F_ONE or off > (span_off + 120) * F_ONE:
		return false
	var phase: int = posmod(tick_count + band * 300, LANE_BLOCK_CYCLE)
	if phase >= LANE_BLOCK_SEALED:
		return false   # OPEN phase — free passage
	if lh & 1 == 0:
		return x <= WORLD_LEFT + 200 * F_ONE
	return x >= WORLD_RIGHT - 200 * F_ONE


func _barricade_solid(x: int, y: int) -> bool:
	## c4 2v ENCOUNTER MIDPOINT TRANSFORM (non-boss): a keyed-encounter barricade
	## (a ~200px flank span at band off 400..460) is SOLID until the advance pushes
	## past the encounter midpoint (camera_top past off 250), then OPENS — the
	## geometry transforms mid-encounter. The opposite flank is the guaranteed
	## bypass (no softlock). Pure function of camera_top + position, ZERO state;
	## campaign seg>=2 only -> torture/endless never see it -> goldens inert.
	if mode != "campaign":
		return false
	var band: int = absi(y) / GATE_SPACING
	if band < CHOKE_START_SEG:
		return false
	var off: int = absi(y) % GATE_SPACING
	if off < 400 * F_ONE or off > 460 * F_ONE:
		return false
	var bh := _mix(band, 929)
	if bh & 1 == 0:
		if x > WORLD_LEFT + 240 * F_ONE:
			return false   # bypass flank (right) is open
	else:
		if x < WORLD_RIGHT - 240 * F_ONE:
			return false   # bypass flank (left) is open
	return absi(camera_top) < band * GATE_SPACING + 250 * F_ONE   # solid until past the midpoint


func _crosses_ledge_south(nx: int, ny: int, oy: int) -> bool:
	## c4 2v ONE-WAY LEDGE: a collapsed embankment you can drop DOWN (northward,
	## the advance) but never climb back UP — a step that moves SOUTH (y increases,
	## retreat) across the band ledge line within a ~160px x-span is reverted, so
	## the route is an irreversible commitment. Northbound is free. Pure position
	## predicate, zero state; campaign seg>=2 only -> torture/endless never see it
	## -> both goldens byte-identical.
	if mode != "campaign" or ny <= oy:
		return false
	var band: int = absi(oy) / GATE_SPACING
	if band < CHOKE_START_SEG:
		return false
	var ly: int = -(band * GATE_SPACING + (300 + _mix(band, 617) % 380) * F_ONE)
	var lx: int = (100 + _mix(band, 811) % 440) * F_ONE
	if absi(nx - lx) > 160 * F_ONE:
		return false
	return oy <= ly and ny > ly   # crossed the ledge going south (retreat)


func _choke_bounds(y: int) -> Array:
	## Lane bounds at world y — KIMK round-2: bands PARAMETERIZE by a pure
	## hash of the segment index (length 200-280, bite 200-280, and from
	## segment 4 an occasional DOUBLE band with a mid gap), so modulation
	## never reads as a metronome. Still zero state, zero rng, nothing hashed.
	var seg: int = absi(y) / GATE_SPACING
	if seg == CALM_BAND_SEG:
		# c2 3v: the calm band never chokes — the corridor opens for the exhale.
		return [WORLD_LEFT, WORLD_RIGHT]
	if seg == RUINS_SEG:
		# c3 5v: the ruins are a MAZE — a DOG-LEG, two alternating-flank bites
		# in one band so the lane snakes (left, then right) instead of a single
		# straight squeeze. Each leg leaves >= HULL_CLEARANCE (bite <= 280 → lane
		# >= 328px), pinned like every choke. seg 3 = past the torture reach.
		var sh3: int = (seg * 2654435761) & 0x7FFFFFFF
		var off3: int = absi(y) % GATE_SPACING
		var bite3: int = (200 + (sh3 >> 8) % 80) * F_ONE
		var lo3: int = CHOKE_OFF_LO
		var leg: int = 140 * F_ONE
		if off3 >= lo3 and off3 < lo3 + leg:
			return [WORLD_LEFT + bite3, WORLD_RIGHT]        # first leg: bite the LEFT flank
		if off3 >= lo3 + leg and off3 <= lo3 + 2 * leg:
			return [WORLD_LEFT, WORLD_RIGHT - bite3]        # dog-leg: bite the RIGHT flank
		return [WORLD_LEFT, WORLD_RIGHT]
	if seg >= CHOKE_START_SEG:
		var sh: int = (seg * 2654435761) & 0x7FFFFFFF
		var off: int = absi(y) % GATE_SPACING
		var b_len: int = (200 + sh % 80) * F_ONE
		var bite: int = (200 + (sh >> 8) % 80) * F_ONE
		var lo: int = CHOKE_OFF_LO
		var in_band := off >= lo and off <= lo + b_len
		if not in_band and seg >= 4 and sh % 3 == 0:
			# Double band: a second squeeze after an 80px gap, opposite flank.
			var lo2: int = lo + b_len + 80 * F_ONE
			if off >= lo2 and off <= lo2 + b_len / 2:
				if seg % 2 == 0:
					return [WORLD_LEFT, WORLD_RIGHT - bite]
				return [WORLD_LEFT + bite, WORLD_RIGHT]
		if in_band:
			if seg % 2 == 0:
				return [WORLD_LEFT + bite, WORLD_RIGHT]
			return [WORLD_LEFT, WORLD_RIGHT - bite]
	return [WORLD_LEFT, WORLD_RIGHT]


func _in_choke_apron(y: int) -> bool:
	## The BREATHER (KIMK round-2): a guaranteed hazard-free full-width apron
	## right after every choke — width modulates in both directions because
	## the squeeze is followed by authored open ground, not more minefield.
	## c2 4v PANIC POCKET: the 80px BEFORE the band (off 70-150) is hazard-free
	## too — both sides of every squeeze, inherited by every hazard stream that
	## already consumes this predicate (mines, barrels, vents).
	var seg: int = absi(y) / GATE_SPACING
	if seg < CHOKE_START_SEG:
		return false
	var off: int = absi(y) % GATE_SPACING
	return (off > 520 * F_ONE and off <= 640 * F_ONE) \
		or (off > 70 * F_ONE and off <= 150 * F_ONE)


func _is_calm_band(y: int) -> bool:
	## c2 3v: the whole-band breath — pure skip-guard (zero state, zero rng,
	## never re-phases a neighbor's _mix pick; the _in_choke_apron pattern).
	return absi(y) / GATE_SPACING == CALM_BAND_SEG


func _in_fork_apron(y: int) -> bool:
	## c2 4v DECISION APRON: the gate+300..460 approach band before fork gates
	## 2/4 is COVER-free (not just hazard-free) — the route choice gets read
	## from open ground, not mid-firefight. Blockade/camp skip their whole
	## stamp; the ambient rock stream consults this per row.
	var a: int = absi(y)
	var k: int = a / GATE_SPACING + 1     # the gate this approach band feeds
	if k not in FORK_GATES:
		return false
	var off: int = a % GATE_SPACING
	return off >= 540 * F_ONE and off <= 700 * F_ONE


func _arena_margin_x(x: int, y: int) -> int:
	## Foundry escape corridor (c2 3v): in the colossus approach (seg >=
	## COLOSSUS_ARENA_SEG) keep streamed hazards ARENA_MARGIN off both walls so
	## the crush-crawler can never corner a player against wall-hugging debris.
	## Golden-inert (seg 4+ is far past the torture reach); identity elsewhere.
	if absi(y) / GATE_SPACING >= COLOSSUS_ARENA_SEG:
		return clampi(x, ARENA_MARGIN, SCREEN_W_FP - ARENA_MARGIN)
	return x


func _near_stream_bunker(x: int, y: int) -> bool:
	## Fairness pocket (c2 4v): streamed hazards keep BUNKER_EXCLUSION clear of
	## streamed bunkers, so a breach is never also a minefield. Bunker placement
	## is a pure function of its cadence (idx odd, x 120/460 by flank parity,
	## y = -idx*500) — pure math per offset, no array scan.
	var row: int = absi(y) / (500 * F_ONE)
	for idx in [row - 1, row, row + 1]:
		if idx < 1 or idx % 2 == 0:
			continue
		var bx: int = (120 if (idx / 2) % 2 == 0 else 460) * F_ONE
		var by: int = -idx * 500 * F_ONE
		if x >= bx - BUNKER_EXCLUSION and x <= bx + BUNKER_W + BUNKER_EXCLUSION \
				and y >= by - BUNKER_EXCLUSION and y <= by + BUNKER_H + BUNKER_EXCLUSION:
			return true
	return false


func _clamp_actor(p: Dictionary) -> void:
	var cb := _choke_bounds(p["y"])
	p["x"] = clampi(p["x"], cb[0], cb[1])
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
		# A supply the player is already capped on grants nothing (mini() eats it,
		# or the vest is already on). A PRICED one must not be auto-bought on
		# proximity: that was a silent chest debit PLUS a cost*10 score credit for
		# nothing (an endless laundering loop). Leave it standing — the view
		# already greys it and prints MAXED.
		var full := _supply_full(p, pk["kind"])
		if cost > 0 and full:
			continue
		war_chest -= cost
		if pk["kind"] == 2:
			vest_buys += 1   # priced crates ride the same campaign creep (no loophole)
		# Same score credit as the spend-wheel buy: a priced ground crate must not
		# silently lose score vs an identical wheel purchase (the _try_buy invariant).
		if cost > 0:
			score += cost * 10
		# `full` rides the event so the view can stop paying the celebratory
		# callout for a free no-op too. Events are checksum-excluded: golden-safe.
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
			# Deny is NEVER silent (9v): _kill_player pre-arms broke_timer on a
			# broke death, which muted this exact event in the most common case.
			events.append({"t": "revive_deny", "x": target["x"], "y": target["y"], "cost": cost})


func _respawn(p: Dictionary, at_y: int) -> void:
	p["alive"] = true
	# PARTIAL resupply, not a full one. A free 99 rounds + 12 grenades cost ~190
	# coins at shop rates (3x SHOP_AMMO_COST + 3x SHOP_GRENADE_COST), and the
	# broke fallback respawns you for nothing — so once you carried no upgrades,
	# dying strictly dominated buying and the whole supply economy was decorative.
	# Half a clip and 4 grenades still ends the helplessness the 1986 rule was
	# protecting, while leaving a restock DECISION on the table.
	# Starting values (49/4); test: dying must be worse EV than one 30-coin ammo
	# buy. If players now feel stranded on respawn, raise grenades to 6.
	p["mg_ammo"] = MG_AMMO_MAX / 2
	p["grenade_ammo"] = 4
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
	tokens = maxi(0, tokens - 1)   # ...and burns ONE Commendation — a full wipe let
	                               # a partner's stray death zero YOUR earned pair
	                               # with no agency (re-review); -1 keeps the
	                               # spend-them-or-lose-them pressure per body.
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
			# "player": 1 is what SANDBAG_FIELD_CAP counts. Counting *untagged* bags
			# instead meant every authored bag on the field billed against the player's
			# 6-bag allowance: endless plants 16 in _init, so the 40-coin shop bag
			# answered deny/"cap" from tick 0 — in the only mode that has a shop, and
			# the exact loop _init's own comment calls intended. ("world" could not be
			# reused for this: in endless it marks the TEMPORARY shop barricades that
			# crumble at intermission end, so tagging permanent cover with it deletes
			# the arena's cover every wave — tests/test_endless.gd:492 pins that.)
			sandbags.append({"x": sbx, "y": sby, "player": 1})
			events.append({"t": "sandbag_plant", "x": sbx, "y": sby})
		3:
			# Airstrike is CALLED IN, not instant — it now telegraphs like every
			# other lethal AoE (grenadier lob, sniper paint, observer mortar),
			# giving a commit-then-wait beat instead of a silent screen-wipe.
			pending_airstrike = STRIKE_TELEGRAPH_TICKS
			events.append({"t": "airstrike_called", "x": SCREEN_CX, "y": camera_top + 180 * F_ONE})


func _econ_depth() -> int:
	## The ONE depth axis every scaling price and payout reads: campaign counts
	## gates opened, endless counts 3-wave steps. Prices and income must ride the
	## same number or the economy inverts (see _supply_cost).
	if mode == "campaign":
		var gates_open := 0
		for g in gates:
			if g["open"]:
				gates_open += 1
		return gates_open
	return wave / 3


func _econ_scale(base: int) -> int:
	## +25% of base per depth step. PROPORTIONAL, not flat, and NOT capped —
	## both of those broke the shop:
	##   - Flat +10/step is regressive: it tripled the 30c ammo across a campaign
	##     while the 100c airstrike moved 1.7x, so "what do I buy" collapsed to
	##     "buy the expensive thing, it barely moved".
	##   - The endless +150 ceiling capped the SINK while every SOURCE kept
	##     climbing (a wave's kill income grows with WAVE_ENEMIES_PER_WAVE, the
	##     Clean Wave bonus and the miniboss bounty ride the wave too). A full
	##     restock was ~1 wave's income at wave 10 and under a THIRD of it by
	##     wave 100 — buy-everything went from a trade to a formality, the exact
	##     failure the 6x score haircut in _try_buy exists to prevent.
	## 25%/step is the rate the Clean Wave bonus was already authored at
	## (40 + depth*10 IS 40 scaled by 25%/step), so the two now provably track.
	return base + base * _econ_depth() / 4


func _supply_cost(kind: int) -> int:
	## Prices creep with depth so a fat late chest still faces a real spend
	## decision — income scales with depth, so the shop must scale with it too,
	## at the same rate and with the same (absent) ceiling. Endless creeps every
	## 3 waves; campaign creeps per gate opened (it is ALWAYS wave 0, so the wave
	## term never fired there and every price was frozen for the whole 7-gate run).
	## Test: end-of-sector chest should stay under ~3 affordable buys.
	if kind < 0 or kind >= SUPPLY_COSTS.size():
		return 0
	var base: int = SUPPLY_COSTS[kind]
	if kind == 2 and mode == "campaign":
		# Per-purchase creep, campaign only (endless prices on the wave alone):
		# 60/75/90/105/120, capped after 4 buys. This USED to return early, so
		# the one item that grants an extra life was also the only item that
		# never gate-crept — the cheapest thing on the endgame wheel. It now
		# feeds the depth scale like everything else.
		base = mini(SHOP_VEST_COST + vest_buys * 15, 120)
	return _econ_scale(base)


func _supply_full(p: Dictionary, kind: int) -> bool:
	## True when this supply would deliver NOTHING to p (already at the cap /
	## already wearing it). Shared by every path that hands out a supply so none
	## of them can bill for a no-op: the wheel buy, priced ground crates, and the
	## view's "don't play the celebratory callout" flag.
	match kind:
		0:
			return p["mg_ammo"] >= MG_AMMO_MAX
		1:
			return p["grenade_ammo"] >= GRENADE_AMMO_MAX
		2:
			return p["vest"]
		6:
			return p["triple"]
		8:
			return p["claymores"] >= CLAYMORE_CAP
	return false


func _mint_token(x: int, y: int) -> void:
	## Commendation mint: only the two already-telegraphed peaks pay (streak-20
	## surge, flawless gate) — no new tiers to teach. Cap 2 = starting value
	## (test: a run crossing 3 milestones holds 2). Airstrike wipes can't feed
	## kill_streak (no_score) and the MG Nest is streak-excluded, so there is
	## no low-risk token farm.
	if tokens < 2:
		tokens += 1
		events.append({"t": "token_mint", "x": x, "y": y, "n": tokens})


func _try_token_drop(p: Dictionary) -> void:
	## Spend one Commendation for a free supply call (basic table 0-3, seeded
	## roll). NO coin path in or out: not buyable with the chest, no score
	## credit back (tokens bridge score->power; crediting score would loop).
	if tokens <= 0:
		events.append({"t": "deny", "x": p["x"], "y": p["y"], "why": "token"})
		return
	tokens -= 1
	# Roll only among USEFUL kinds — burning a Commendation on a vest you're
	# already wearing was a silent no-op against the deny-loudly grammar
	# (re-review). Airstrike is always live, so the pool is never empty.
	var cands: Array[int] = []
	if p["mg_ammo"] < MG_AMMO_MAX:
		cands.append(0)
	if p["grenade_ammo"] < GRENADE_AMMO_MAX:
		cands.append(1)
	if not p["vest"]:
		cands.append(2)
	cands.append(3)
	var kind: int = cands[rng.range_i(0, cands.size() - 1)]
	_apply_supply(p, kind)
	events.append({"t": "token_drop", "x": p["x"], "y": p["y"], "kind": kind})


func _try_buy(p: Dictionary, kind: int) -> void:
	## Spend-wheel purchase: supplies radioed in, paid from the shared
	## War Chest — the same pool that funds revives. That's the decision.
	if kind < 0 or kind >= SUPPLY_COSTS.size():
		return
	var cost: int = _supply_cost(kind)
	var player_bags := 0
	for pb in sandbags:
		if pb.get("player", 0) == 1:
			player_bags += 1
	if kind == 4 and (player_bags >= SANDBAG_FIELD_CAP or p["in_tank"] >= 0):
		# Sandbag-specific denials: field cap reached, or buying from a tank
		# (no hands on the deck to dig in). Deny is loud AND says why —
		# "NEED COINS" at a full field with 400 in the chest was a HUD lie.
		events.append({"t": "deny", "x": p["x"], "y": p["y"],
			"why": "cap" if player_bags >= SANDBAG_FIELD_CAP else "tank"})
		return
	if _supply_full(p, kind):
		# Buying a vest you're already wearing, or ammo at the cap, used to
		# charge the chest AND credit score for nothing delivered — the same
		# silent no-op _collect_pickups denies. Deny loudly instead.
		events.append({"t": "deny", "x": p["x"], "y": p["y"], "why": "full"})
		return
	if war_chest < cost:
		events.append({"t": "deny", "x": p["x"], "y": p["y"], "why": "coins"})
		return
	war_chest -= cost
	if kind == 2:
		vest_buys += 1
	# Spending credits a DISCOUNTED rate against the 10x the victory payout gives
	# unspent chest. At exact parity the "gear now vs. revives later" decision this
	# shop is built around was fake — buying was score-neutral, so buy-everything-
	# immediately strictly dominated and hoarding cost nothing. A 40% haircut makes
	# a buy a real trade without punishing the run-saving purchase.
	# Starting value 6x; test: a hoard run should out-score an all-buy run on the
	# same seed by 10-25%. If the gap exceeds 40% (nobody ever buys), raise to 8.
	score += cost * 6
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


func _try_salvage_hulk(p: Dictionary) -> bool:
	## Interact on a smoldering hulk strips it: +2 grenades (the cannon draws
	## from the grenade pool — same logistics), and the strip ENDS the cover
	## (burn_ticks = 0). That is the decision: keep the wall or take the ammo.
	## +2 = starting value; test: salvage at cap clamps, second tap is a no-op.
	for tank in tanks:
		if not tank["alive"] and tank["burn_ticks"] > 0 \
				and _dist_lte(p["x"], p["y"], tank["x"], tank["y"], TANK_BOARD_RADIUS):
			# Event reports what was actually GRANTED (a capped player got +1/+0
			# while the toast promised +2 — a HUD lie, re-review).
			var before: int = p["grenade_ammo"]
			p["grenade_ammo"] = mini(GRENADE_AMMO_MAX, p["grenade_ammo"] + 2)
			tank["burn_ticks"] = 0
			tank["salvage_tick"] = tick_count
			events.append({"t": "hulk_salvage", "x": tank["x"], "y": tank["y"],
				"n": p["grenade_ammo"] - before})
			return true
		if not tank["alive"] and tank.get("salvage_tick", -1) == tick_count \
				and _dist_lte(p["x"], p["y"], tank["x"], tank["y"], TANK_BOARD_RADIUS):
			# 2P same-tick guard: P1 stripped this hulk THIS tick — swallow P2's
			# tap instead of letting it fall through and arm a claymore underfoot.
			return true
	return false


func _boardable_tank_near(p: Dictionary) -> bool:
	## Near-miss board taps must not arm a claymore at your feet: a boardable
	## tank just outside TANK_BOARD_RADIUS means INTERACT read as "board".
	for t in tanks.size():
		var tank := tanks[t]
		if tank["alive"] and not tank["burning"] \
				and (tank["occupant"] < 0 or _tank_gunner(t) < 0) \
				and _dist_lte(p["x"], p["y"], tank["x"], tank["y"], 2 * TANK_BOARD_RADIUS):
			return true
		# Near-miss salvage taps must not arm a claymore either (same rule as
		# the near-miss board guard above).
		if not tank["alive"] and tank["burn_ticks"] > 0 \
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
		for rk in rocks:
			if not _rk_solid(rk):
				continue   # a tank crushes through grass
			if absi(tank["x"] - rk["x"]) <= _rk_hw(rk) + 6 * F_ONE \
					and absi(tank["y"] - rk["y"]) <= _rk_hh(rk) + 6 * F_ONE:
				tank["x"] = prev_x
				tank["y"] = prev_y
				break
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
			if tank["burn_ticks"] > 0:
				tank["burn_ticks"] = tank["burn_ticks"] - 1   # hulk cover cooling off
			continue
		tank["fire_cd"] = maxi(0, tank["fire_cd"] - 1)

		if tank["occupant"] >= 0 and not tank["burning"]:
			tank["fuel"] = tank["fuel"] - 1
			# Crew fuel tax: a seated gunner burns +25% (every 4th tick) —
			# double-crewing is a deliberate commitment, not a free gun deck.
			# Starting value; staged probe: crewed fuel life ~20s -> ~16s.
			# tick_count cadence, NOT fuel%4 — the tax decrement shifted fuel's
			# residue so the "every 4th" fired every 3rd (+33%, re-review).
			if tick_count % 4 == 0 and _tank_gunner(ti) >= 0:
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
	tank["burning"] = false   # dead is dead — a hulk carrying burning=true forever was a trap for later readers
	# Tank Hulk (5-vote panel): the dead hull IS the cover — burn_ticks is
	# hashed but dead-unused after death, so it becomes the hulk lifetime.
	# Zero new fields, zero new entities; behavior change -> golden re-record.
	tank["burn_ticks"] = HULK_TICKS
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
			# Dead tanks are cover while they smolder (burn_ticks > 0): the
			# bunker two-way rule from an asset the field already produces.
			for hk in tanks:
				if ((hk["alive"] and hk["occupant"] < 0) or (not hk["alive"] and hk["burn_ticks"] > 0)) \
						and absi(bx - hk["x"]) <= HULK_HALF_W and absi(by - hk["y"]) <= HULK_HALF_H:
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead and not rocks.is_empty():
			for ri in rocks.size():
				var rk: Dictionary = rocks[ri]
				if not _rk_solid(rk):
					continue   # bullets pass through grass — it hides, doesn't save
				if absi(bx - rk["x"]) <= _rk_hw(rk) and absi(by - rk["y"]) <= _rk_hh(rk):
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					# c4 2v: kind-2 ruined-wall slabs CHIP under fire — WALL_CRACK_HITS
					# rounds breach one and open a lane through it (kills turtling). crack
					# is an EXCLUDED accrual (drives removal, not a hashed flag); kind-2
					# only streams past both torture windows -> goldens byte-identical.
					if rk.get("kind", 0) == 2:
						rk["crack"] = rk.get("crack", 0) + 1
						if rk["crack"] >= WALL_CRACK_HITS:
							events.append({"t": "cover_crack", "x": rk["x"], "y": rk["y"]})
							rocks.remove_at(ri)
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
					# Armor: a body with hp > 1 eats the round instead of dying (a
					# grenade still one-shots it via _explode). Only a lethal round
					# routes through _kill_enemy. Was a kind whitelist (mg_nest/
					# technical/broadcast, hp 3/TECHNICAL_HP/BROADCAST_HP); reading
					# hp itself is behaviour-identical for those and lets deep-endless
					# VETERAN ARMOR (_wave_armor) harden the bulk roster too.
					if e.get("hp", 1) > 1:
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
		# "hold" = button held SINCE the throw (re-review: sampling grenade_prev
		# only at the apex tick made a mid-cooldown re-press pop the previous
		# grenade at half range). Any release — or boarding a tank, where the
		# button means nothing — disarms the fuse hand for good.
		if g.get("hold", false) and (not players[g["owner"]]["grenade_prev"] \
				or players[g["owner"]]["in_tank"] >= 0 or not players[g["owner"]]["alive"]):
			g["hold"] = false
		if not g["shell"] and g["zv"] < 0 and g["zv"] + GRENADE_GRAV >= 0 \
				and g.get("hold", false):
			_explode(g["x"], g["y"], false, "airburst")
			grenades.remove_at(i)
			continue
		# Marsh current (c2 5v): the seg-2 EXCLUSIVE biome verb — airborne
		# grenades drift sideways over open marsh water, direction hashed per
		# run band (learnable within one river). Shells exempt: heavy ordnance
		# flies true. Pure read past the golden window — no state, no rng draw.
		if not g["shell"]:
			var g_band: int = absi(g["y"]) / GATE_SPACING
			if g_band == MARSH_SEG and _in_water(g["x"], g["y"]):
				var drift: int = MARSH_DRIFT if _mix(g_band, _world_seed) & 1 else -MARSH_DRIFT
				# c3 5v BREAKWATER: a solid rock immediately downstream stops the
				# drift — its LEEWARD cell is a safe shadow where the current can't
				# bank the grenade into you. Cover choice now informs the hazard.
				var blocked := false
				for wk in rocks:
					if _rk_solid(wk) and absi(g["y"] - wk["y"]) <= _rk_hh(wk) \
							and (g["x"] - wk["x"]) * drift < 0 \
							and absi(g["x"] - wk["x"]) <= _rk_hw(wk) + BREAKWATER_SLACK:
						blocked = true
						break
				if not blocked:
					g["x"] = g["x"] + drift
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
	# c4 2v: an explosion instantly BREACHES a kind-2 ruined-wall slab in radius —
	# a grenade/barrel opens a lane through a wall in one shot (no chip count).
	for ki in range(rocks.size() - 1, -1, -1):
		if rocks[ki].get("kind", 0) == 2 and _dist_lte(x, y, rocks[ki]["x"], rocks[ki]["y"], GRENADE_RADIUS):
			events.append({"t": "cover_crack", "x": rocks[ki]["x"], "y": rocks[ki]["y"]})
			rocks.remove_at(ki)
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
	# c4 2v PLAYER-TRIGGERED GEOMETRY: a STRUT barrel DROPS a slag-pour/log wall
	# (a 3-slab kind-2 line) onto the adjacent lane when it blows, which enemies
	# then reroute around via the shipped rock move-revert — the player reshapes
	# the battlefield, not only clears cover. strut stores the drop x (0 = a plain
	# barrel); struts are authored seg>=2 so goldens stay byte-identical.
	if bl.get("strut", false):
		var sdx: int = bl["x"]   # drop the wall at the strut's own x (no stored value)
		var sdy: int = bl["y"] - 30 * F_ONE
		for sds in 3:
			rocks.append({"x": sdx + (sds - 1) * 80 * F_ONE, "y": sdy, "kind": 2})
		events.append({"t": "cover_crack", "x": sdx, "y": sdy})
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
		# chest, no score, no avenge, and no STREAK: without no_score the pilot
		# still ticked kill_streak and refreshed the window, so executing the
		# rescue target was a free combo-keepalive. The corpse is the only receipt.
		coin = 0
		no_coin = true
		no_score = true
	if e.get("marked", false):
		coin *= 3   # bounty target pays triple (chest + score)
		events.append({"t": "bounty_kill", "x": e["x"], "y": e["y"], "coin": coin})
	if has_mod(4):
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
			_mint_token(e["x"], e["y"])
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
	## rushers, shieldmen, elites, grenadiers, snipers, sappers, lunging frogmen
	## and technicals (both phases). Same fixed-point ops,
	## same order, as the code this replaces — golden-safe.
	## FRENZY (wave_mod 6) belongs HERE, not just in _step_sapper: "the swarm
	## rushes 40% faster" means the WHOLE swarm. wave_mod is endless-only and the
	## torture wipes long before wave 6, so this stays golden-inert.
	var spd := base_spd
	if has_mod(6):
		spd = (spd * 7) / 5
	# Broadcast Tower rally aura: any live mast within 140 px drives ground
	# troops +25% — deliberately under FRENZY's +40% so aura+FRENZY stacking
	# reads as escalation, not a doubling. Stateless read of hashed x/y;
	# campaign never spawns a mast -> golden-inert.
	if not _broadcasts.is_empty():
		for be in _broadcasts:
			# alive re-check: the cache holds refs — a mast killed mid-loop by a
			# blast must not buff the movers stepped after it this tick.
			if be["alive"] and _dist_lte(e["x"], e["y"], be["x"], be["y"], BROADCAST_AURA_RADIUS):
				spd = (spd * 5) / 4
				break
	if _in_water(e["x"], e["y"]) or _in_fork_wire(e["x"], e["y"]) or _in_mud(e["x"], e["y"]) \
			or _in_rubble(e["x"], e["y"]):
		spd = spd / 2
	var pvx: int = e["x"]
	var pvy: int = e["y"]
	e["x"] = pvx + Fixed.mul(Fixed.div(dx, dlen), spd)
	e["y"] = pvy + Fixed.mul(Fixed.div(dy, dlen), spd)
	# Sandbag walls stop ground movers both ways (the water-clamp pattern:
	# move, then revert into-AABB steps) — the swarm flanks cover, never
	# phases through it. Empty-array fast path keeps the hot loop clean.
	# Occupancy-toggle semantics (KIMK r2, pinned): solidity flips the TICK
	# the occupant changes — bullets already in flight test against the new
	# state next step (chaos accepted as feature: boarding under fire pulls
	# the cover out from behind you). The swarm cannot crew tanks (board is
	# a player-input verb only), so enemy-side cover never flickers.
	for hk3 in tanks:
		if (hk3["alive"] and hk3["occupant"] < 0) or (not hk3["alive"] and hk3["burn_ticks"] > 0):
			if absi(e["x"] - hk3["x"]) <= HULK_HALF_W and absi(e["y"] - hk3["y"]) <= HULK_HALF_H:
				if absi(pvx - hk3["x"]) > HULK_HALF_W or absi(pvy - hk3["y"]) > HULK_HALF_H:
					e["x"] = pvx
					e["y"] = pvy
				break
	if not rocks.is_empty():
		for rk in rocks:
			if not _rk_solid(rk):
				continue   # enemies walk through grass too
			var rhw := _rk_hw(rk)
			var rhh := _rk_hh(rk)
			if absi(e["x"] - rk["x"]) <= rhw and absi(e["y"] - rk["y"]) <= rhh:
				if absi(pvx - rk["x"]) > rhw or absi(pvy - rk["y"]) > rhh:
					e["x"] = pvx
					e["y"] = pvy
				break
	# c4 2v: enemies reroute around a SEALED lane-block too (same escape rule).
	if _lane_blocked(e["x"], e["y"]) and not _lane_blocked(pvx, pvy):
		e["x"] = pvx
		e["y"] = pvy
	if not sandbags.is_empty():
		for sb in sandbags:
			if absi(e["x"] - sb["x"]) <= SANDBAG_HALF_W and absi(e["y"] - sb["y"]) <= SANDBAG_HALF_H:
				# Escape rule: revert only steps ENTERING the bag — a mover the
				# bag was planted ON walks out instead of freezing bulletproof
				# forever (re-review: the frozen immortal blocker).
				if absi(pvx - sb["x"]) > SANDBAG_HALF_W or absi(pvy - sb["y"]) > SANDBAG_HALF_H:
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
		# Rally masts have NO sweep exemption. They used to be the one entity that could
		# never be swept; a sibling pass then made them spawn at camera_top+40 (inside the
		# reachable band) instead of above the player's own ceiling. Under endless's FIXED
		# camera an in-band rooted mast can never exceed camera_top+420, so sweeping
		# unconditionally cannot remove a live one — and campaign's ratcheting camera needs
		# the sweep or every mast walked past lives forever in enemies[] and in the per-tick
		# _broadcasts aura scan. One rule beats a mode-conditional special case.
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
				# Magnet only while the crate is in the live band — a drop the
				# ratchet left behind must not pull rushers out of the fight.
				if pk.get("drop", 0) > 0 and pk["y"] >= camera_top \
						and pk["y"] <= camera_top + 400 * F_ONE:
					drop = pk
					break
			if not drop.is_empty():
				var ddx: int = drop["x"] - e["x"]
				var ddy: int = drop["y"] - e["y"]
				var ddlen := Fixed.length(ddx, ddy)
				if ddlen <= PICKUP_RADIUS:
					pickups.erase(drop)
					events.append({"t": "drop_stolen", "x": drop["x"], "y": drop["y"]})
					continue
				elif ddlen > F_ONE:
					var mpx: int = e["x"]
					var mpy: int = e["y"]
					_advance_toward(e, ddx, ddy, ddlen, ENEMY_SPEED)
					if e["x"] != mpx or e["y"] != mpy:
						continue
					# Blocked (sandbag wall around the crate) — fall through to
					# the player chase instead of pinning here forever.
		if dlen > F_ONE:
			_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)


func _step_elite(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Skirmisher: advance to standoff range, wind up (visible, interruptible
	## by killing him), fire one aimed shot. Touch still kills.
	# Route-fork lane leash: gauntlet elites HOLD their lane (no advance, no
	# fire) until a player crosses the band's south edge — then the leash
	# clears for good. hold_y is spawn-immutable, unhashed-classified.
	if e.get("hold_y", 0) != 0:
		if target["y"] > e["hold_y"]:
			return
		e.erase("hold_y")
	# c3 2v flanker crossing: once the leash clears, the sack flanker CROSSES
	# the lane toward the nest-side pocket (steering to flank_x while tracking
	# the player's row) before it resumes the standoff — an authored crossfire,
	# not ambient drift. Cleared the moment it passes the centerline onto the
	# nest side. flank_x is unhashed / gate-3 torture-inert (goldens untouched).
	if e.has("flank_x"):
		if (e["x"] - SCREEN_CX) * (e["flank_x"] - SCREEN_CX) > 0:
			e.erase("flank_x")
		else:
			var wx: int = e["flank_x"] - e["x"]
			var wy: int = target["y"] - e["y"]
			var wlen := Fixed.length(wx, wy)
			if wlen > F_ONE:
				_advance_toward(e, wx, wy, wlen, ELITE_SPEED)
			return
	if e["windup"] > 0:
		e["windup"] = e["windup"] - 1
		if e["windup"] == 0 and dlen > F_ONE:
			events.append({"t": "enemy_shot", "x": e["x"], "y": e["y"]})
			_spawn_enemy_bullet(e["x"], e["y"], dx, dy, dlen)
		return   # rooted while winding up
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > ELITE_STANDOFF:
		_advance_toward(e, dx, dy, dlen, ELITE_SPEED)
	elif e["fire_cd"] == 0 and not _concealed(target):   # can't aim into smoke
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
			# THREE lobs walked ACROSS the firing line, not one circle underfoot.
			# The drone calls the identical _add_strike as a single precise
			# circle — the cluster is what makes these two read as different
			# threats: you dodge the drone by stepping off the spot, you dodge
			# the grenadier by running the line lengthwise (at him or away).
			var px := 0
			var py := 0
			if dlen > F_ONE:
				px = -Fixed.mul(Fixed.div(dy, dlen), GRENADIER_CLUSTER_SPREAD)
				py = Fixed.mul(Fixed.div(dx, dlen), GRENADIER_CLUSTER_SPREAD)
			# One scatter for the whole cluster: concealment DISPLACES the firing
			# line, it does not scramble it (the walked line is this threat's
			# identity — see above). Zero offset in the open.
			var sc := _blind_scatter(target)
			var cx: int = target["x"] + sc[0]
			var cy: int = target["y"] + sc[1]
			_add_strike(cx - px, cy - py)
			_add_strike(cx, cy)
			_add_strike(cx + px, cy + py)
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > GRENADIER_STANDOFF:
		_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)
	elif e["fire_cd"] == 0:   # AREA fire: smoke scatters the lobs, it does not stop them
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
	elif e["fire_cd"] == 0 and not _concealed(target):   # can't paint into smoke
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
			var sc := _blind_scatter(target)
			_add_strike(target["x"] + sc[0], target["y"] + sc[1])
		return   # holds position while painting
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > DRONE_STANDOFF:
		e["x"] = e["x"] + Fixed.mul(Fixed.div(dx, dlen), DRONE_SPEED)
		e["y"] = e["y"] + Fixed.mul(Fixed.div(dy, dlen), DRONE_SPEED)
	elif e["fire_cd"] == 0:   # AREA fire: smoke scatters the paint, it does not stop it
		e["fire_cd"] = DRONE_FIRE_CD_TICKS
		e["windup"] = DRONE_WINDUP_TICKS
		events.append({"t": "drone_windup", "x": e["x"], "y": e["y"]})


func _step_technical(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	# The raider SMASHES sandbags it drives over (re-review: the fastest ground
	# vehicle phased through player cover a walking rusher respected).
	if not sandbags.is_empty():
		for si in range(sandbags.size() - 1, -1, -1):
			var tsb := sandbags[si]
			if absi(e["x"] - tsb["x"]) <= SANDBAG_HALF_W + 8 * F_ONE \
					and absi(e["y"] - tsb["y"]) <= SANDBAG_HALF_H + 8 * F_ONE:
				events.append({"t": "sandbag_break", "x": tsb["x"], "y": tsb["y"]})
				sandbags.remove_at(si)
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
			# Shared mover step (it smashes sandbags above, but rocks, hulks and
			# sealed lane blocks used to be phased straight through mid-charge).
			_advance_toward(e, lx, ly, llen, TECHNICAL_SPEED)
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
		_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)   # cover is cover for wheels too
		if _in_water(e["x"], e["y"]):   # wheels don't swim (tank rule)
			e["x"] = cpx
			e["y"] = cpy
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if e["fire_cd"] == 0 and not _concealed(target):   # can't line up a charge into smoke
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
			# Shared mover step: the lunge is fast, not incorporeal — it stops at
			# sandbags/rocks/hulks/sealed blocks like every other ground mover, and
			# wades out of its own river at half pace.
			_advance_toward(e, dx, dy, dlen, FROGMAN_LUNGE_SPEED)
	elif dlen > FROGMAN_CALM_RADIUS and _in_water(e["x"], e["y"]):
		e["submerged"] = true
	else:
		# Re-telegraph before lunging again, instead of rewinding the lunge on the spot.
		# The old `lunge_ticks = FROGMAN_LUNGE_TICKS` here was unescapable: a lunge is
		# 135px but the water band is ~80px, so the frogman lands on DRY GROUND, and the
		# `_in_water` half of the elif above can then never be true again. It rewound
		# every tick — a permanent 3.0px/t homing one-hit kill chasing a 2.4px/t player,
		# with no telegraph, no cooldown, and no cull (it stays glued to the target).
		# Routing back through the surface telegraph keeps it rooted and harmless for
		# FROGMAN_SURFACE_TICKS first, which is the window the player needs to break away.
		e["surface_ticks"] = FROGMAN_SURFACE_TICKS
		events.append({"t": "frogman_surface", "x": e["x"], "y": e["y"]})


func _step_sapper(e: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## Advances like a rusher (touch still kills) but drops an armed mine on a
	## cooldown, authoring a hazard trail across the arena. Reuses fire_cd as the
	## drop timer, and the existing landmine array/detonation — no new state.
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if e["fire_cd"] == 0 and mines.size() < SAPPER_MAX_MINES:
		e["fire_cd"] = SAPPER_MINE_CD_TICKS
		mines.append({"x": e["x"], "y": e["y"], "armed": true})
		events.append({"t": "mine_lay", "x": e["x"], "y": e["y"]})
	# Moves through the shared mover step, so the sapper respects the cover the
	# player PAID for: hand-rolled movement here phased straight through sandbags,
	# rocks, tank hulks and sealed lane blocks (and skipped mud/rubble/wire).
	if dlen > F_ONE:
		_advance_toward(e, dx, dy, dlen, ENEMY_SPEED)


func _step_ghillie(e: Dictionary, target: Dictionary, dx: int, dy: int, dlen: int) -> void:
	## A cloaked sniper dug into the ground: bullet-immune + harmless + no threat
	## arrow while submerged, reveals when you enter notice range, then paints and
	## fires ONE locked shot from cover (stationary — never chases), then SINKS
	## BACK IN. Killing it during the reveal/paint window defuses the shot — and
	## that window is the only time it can be killed at all, which is what makes
	## it a different problem from the sniper standing in the open. Reuses sniper
	## paint state; fire_cd is the post-shot cloak lockout while submerged.
	if e["submerged"]:
		e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
		if e["fire_cd"] == 0 and dlen <= GHILLIE_NOTICE_RADIUS:
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
			# FIRE AND VANISH: the shot leaves and he is instantly back under the
			# grass, bullet-immune. Where the sniper stays standing and can be
			# traded with whenever you like, the ghillie only exists inside a
			# reveal→paint window — rush the grass in that window or you never get
			# to touch him. fire_cd is the lockout before he can surface again.
			e["submerged"] = true
			e["fire_cd"] = GHILLIE_RECLOAK_TICKS
		return
	e["fire_cd"] = maxi(0, e["fire_cd"] - 1)
	if dlen > GHILLIE_NOTICE_RADIUS:
		e["submerged"] = true   # you slipped out of range — re-cloak and wait
		return
	if e["fire_cd"] == 0 and not _concealed(target):   # can't paint into smoke
		e["windup"] = SNIPER_WINDUP_TICKS   # fire_cd is the CLOAK timer here, not a reload
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
	# Bunkers spawn infantry until sealed (the 1986 infinite-spawn grammar) —
	# but only while they're still in the live band. `bunkers` was never removed
	# from and this loop had no on-screen gate, so every passed-but-unsealed
	# bunker kept spitting rushers behind the camera forever: they ate the shared
	# MAX_ENEMIES budget, got culled by _step_enemies the next tick, and starved
	# the real front-line spawner on deep runs. Same off-screen test the enemy /
	# sandbag / rock sweeps use, so it prunes and gates in one pass.
	# Safe for gate arenas: gates hold their own b1/b2 dict refs (removal from
	# this array doesn't touch them), and a closed gate pins the camera within
	# GATE_CAMERA_PAD + 150px of its pair — well inside the band.
	for i in range(bunkers.size() - 1, -1, -1):
		var bk := bunkers[i]
		if bk["y"] > camera_top + 420 * F_ONE:
			bunkers.remove_at(i)
			continue
		if not bk["alive"]:
			continue
		bk["spawn_cd"] = bk["spawn_cd"] - 1
		if bk["spawn_cd"] <= 0 and enemies.size() < MAX_ENEMIES:
			bk["spawn_cd"] = BUNKER_SPAWN_INTERVAL_TICKS
			_spawn_enemy(bk["x"] + BUNKER_W / 2, bk["y"] + BUNKER_H + 8 * F_ONE, false)


func _step_mines() -> void:
	# Sandbag sweep (mirrors the enemy off-screen cull): bags the ratchet left
	# behind are unreachable in campaign but still counted against the global
	# cap — a silent permanent buy-lockout (re-review). Torture-inert (empty).
	for si in range(sandbags.size() - 1, -1, -1):
		if sandbags[si]["y"] > camera_top + 420 * F_ONE:
			sandbags.remove_at(si)
	for ri in range(rocks.size() - 1, -1, -1):
		if rocks[ri]["y"] > camera_top + 420 * F_ONE:
			rocks.remove_at(ri)
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
	# Foundry vents: phase is DERIVED from the global tick (no per-vent timer,
	# no new state) — the 7*x term staggers neighbors so a chunk never jets in
	# unison. Warn event fires VENT_WARN_TICKS before the jet; the jet holds
	# VENT_JET_TICKS and funnels hits through _hurt_player, whose 90t iframe
	# window > the 60t jet — "once per jet cycle" holds by construction.
	# Events are checksum-excluded; the array itself is a conditional feed.
	for vi in range(vents.size() - 1, -1, -1):
		var v := vents[vi]
		if v["y"] > camera_top + 420 * F_ONE:
			vents.remove_at(vi)
			continue
		var v_phase: int = posmod(tick_count + 7 * (v["x"] / F_ONE), VENT_CYCLE_TICKS)
		if v_phase == VENT_CYCLE_TICKS - VENT_JET_TICKS - VENT_WARN_TICKS:
			events.append({"t": "vent_warn", "x": v["x"], "y": v["y"]})
		elif v_phase >= VENT_CYCLE_TICKS - VENT_JET_TICKS:
			if v_phase == VENT_CYCLE_TICKS - VENT_JET_TICKS:
				events.append({"t": "vent_jet", "x": v["x"], "y": v["y"]})
			for p in players:
				if p["alive"] and p["in_tank"] < 0 and not p["roll_iframe"] \
						and _dist_lte(p["x"], p["y"], v["x"], v["y"], VENT_HURT_RADIUS):
					_hurt_player(p)
			# c3 5v: the jet also BURNS soft cover — grass (kind 1) burns off,
			# wall slabs (kind 2) crack; stone (0) and hero wrecks (3) are immune
			# ("stone doesn't burn" = the cluster's immune-to-one/vulnerable-to-
			# another for free). Removal auto-kills concealment/blocking — no flag
			# plumbing, _in_grass/_rk_solid just stop matching. burn_ticks is NOT
			# fed to checksum; seg-4+ vents = torture-inert.
			for ri in range(rocks.size() - 1, -1, -1):
				var brk := rocks[ri]
				if not _rk_burnable(brk):
					continue
				if absi(brk["x"] - v["x"]) <= VENT_HURT_RADIUS + _rk_hw(brk) \
						and absi(brk["y"] - v["y"]) <= VENT_HURT_RADIUS + _rk_hh(brk):
					brk["burn_ticks"] = brk.get("burn_ticks", 0) + 1
					if brk["burn_ticks"] >= VENT_COVER_BURN_TICKS:
						events.append({"t": "cover_burn" if brk.get("kind", 0) == 1 else "cover_crack",
							"x": brk["x"], "y": brk["y"]})
						rocks.remove_at(ri)


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
	# Sector 2+: the ranged roster bleeds into the campaign field, drawn from THIS
	# sector's own vocabulary (SECTOR_SPECIALS) so the six authored zones are six
	# different fights, not one flat list reskinned. Sector 1's roster is empty.
	var roster: Array = SECTOR_SPECIALS[_sector_index(opened)]
	if not roster.is_empty() and rng.range_i(0, 3 if hard else 4) == 0:  # NG+: 1-in-4 specials
		var kind: String = roster[rng.range_i(0, roster.size() - 1)]
		if kind == "mg_nest":
			_spawn_mg_nest(x, camera_top - 24 * F_ONE)
		elif kind == "broadcast":
			_spawn_broadcast(x, camera_top - 24 * F_ONE)
		else:
			_spawn_special(x, camera_top - 24 * F_ONE, kind)
	else:
		# Elite ratio tightens with each opened gate (every 7th → every 3rd by
		# gate 4) so late campaign escalates composition, not just cadence.
		var elite_every := maxi(3, 7 - opened)
		if hard:
			elite_every = maxi(2, elite_every - 2)   # NG+ fields far more red elites
		_spawn_enemy(x, camera_top - 24 * F_ONE, _spawn_counter % elite_every == 0)


func _spawn_enemy(x: int, y: int, elite: bool) -> void:
	# Spawn-path nudge (fork-mine precedent): never birth a unit inside a rock.
	for rk in rocks:
		if not _rk_solid(rk):
			continue   # birthing in grass is fine — it doesn't block
		if absi(x - rk["x"]) <= _rk_hw(rk) + 4 * F_ONE and absi(y - rk["y"]) <= _rk_hh(rk) + 4 * F_ONE:
			x += 24 * F_ONE
			break
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
		# Bare `/ F_ONE` truncates toward 0, and y here is negative — deliberate, see
		# the "`x / ONE` vs `to_int(x)`" contract in fixed.gd. Checksum-excluded, so
		# the floor/truncate choice cannot move a golden either way.
		e["skin"] = (x / F_ONE + y / F_ONE) & 3
	# Deep-endless veteran armor (wave 13+): the bulk roster takes an extra
	# bullet. Only SET when it applies, so the (already hashed) hp feed stays
	# absent — and both goldens byte-identical — everywhere else.
	var arm := _wave_armor()
	if arm > 0:
		e["hp"] = e.get("hp", 1) + arm
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


func _sector_index(opened: int) -> int:
	## 0-based ZONE_INFO/SECTOR_SPECIALS index of the stretch being fought.
	## `opened` tracks it in a continuous run; `_gate_counter - 1` tracks it too
	## and survives an Arcade chapter jump (jump_to_chapter primes the streaming
	## cursors without opening any gate), so take the larger of the two — in a
	## continuous campaign they are always equal, a closed gate being a hard lock.
	return clampi(maxi(opened, _gate_counter - 1), 0, SECTOR_SPECIALS.size() - 1)


func _shields_possible() -> bool:
	## True when the shield archetype can actually turn up — gates the Rend drop
	## so it's never inert. Campaign: this sector's roster fields shieldmen, or one
	## is still walking (spawned in an earlier sector and carried over). Endless:
	## wave 3+, matching _step_wave_spawner's roster.
	if mode == "endless":
		return wave >= 3
	var opened := 0
	for g in gates:
		if g["open"]:
			opened += 1
	if SECTOR_SPECIALS[_sector_index(opened)].has("shield"):
		return true
	for e in enemies:
		if e["alive"] and e["kind"] == "shield":
			return true
	return false


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
	# the arena on its way to the top edge — a window to catch it. +300 (was
	# +240): with the c2 camera lead at 260, +240 would pop it IN FRONT of the
	# anchored player; +300 keeps it a chase from behind.
	enemies.append({"x": rng.range_i(80, 560) * F_ONE, "y": camera_top + 300 * F_ONE,
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
		e["fire_cd"] = 0        # already in position: fire_cd is his cloak lockout, and it's spent
	if kind == "drone":
		# The marquee aerial threat kills like a trophy, not a grunt: marked
		# rides the existing bounty grammar (3× pay + gold fountain + crown).
		e["marked"] = true
	if kind == "technical":
		e["hp"] = TECHNICAL_HP   # armored like the nest — hp is already hashed
	# Deep-endless veteran armor (wave 13+): the bulk roster takes an extra
	# bullet. Only SET when it applies, so the (already hashed) hp feed stays
	# absent — and both goldens byte-identical — everywhere else.
	var arm := _wave_armor()
	if arm > 0:
		e["hp"] = e.get("hp", 1) + arm
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
		# Flank doors (2v): the moment the FIRST bunker of a pair falls, the
		# arena answers — a 3-rusher squad breaches from each wall (right-side
		# leader is an elite). Fixed positions, zero rng; once per gate.
		# Staggered breach countdown (c2 2v): warn -> near wall -> far wall.
		# Runs BEFORE the trigger below so it skips on the trigger tick itself —
		# a clean FLANK_WARN_TICKS gap from warn to the first squad. Parity
		# (KIMK r2) is UNCHANGED, only the timing moved: odd gates keep the 140
		# row + right elite (gate 1 = torture, layout intact); even gates drop
		# the door to 180 and the elite leads from the LEFT.
		if g.get("flanked", false) and g.get("breach_cd", 0) > 0:
			g["breach_cd"] -= 1
			var fdy: int = FLANK_DOOR_Y if absi(g["y"] / GATE_SPACING) % 2 == 1 else FLANK_DOOR_Y + 40 * F_ONE
			var f_left_elite: bool = absi(g["y"] / GATE_SPACING) % 2 == 0
			if g["breach_cd"] == FLANK_STAGGER_TICKS:
				_breach_wall(g, g["breach_first_left"], fdy, f_left_elite)
			elif g["breach_cd"] == 0:
				_breach_wall(g, not g["breach_first_left"], fdy, f_left_elite)
		if not g["open"] and g["boss"].is_empty() and not g.get("final", false) \
				and not g.get("b1", {}).is_empty() \
				and not g.get("flanked", false) and g["b1"]["alive"] != g["b2"]["alive"]:
			g["flanked"] = true
			# c2 2v: the breach now TELEGRAPHS then STAGGERS instead of a
			# same-tick double-wall crossfire coin flip. The wall nearest the
			# FALLEN bunker answers FIRST (causal read), FLANK_WARN_TICKS after a
			# dust-fall warn; the far wall follows FLANK_STAGGER_TICKS later.
			# b1/b2 aren't fixed L/R (ARENAS vary), so read the dead bunker's x.
			var dead_bunker: Dictionary = g["b1"] if not g["b1"]["alive"] else g["b2"]
			g["breach_first_left"] = dead_bunker["x"] < SCREEN_CX
			g["breach_cd"] = FLANK_WARN_TICKS + FLANK_STAGGER_TICKS
			var wdy: int = FLANK_DOOR_Y if absi(g["y"] / GATE_SPACING) % 2 == 1 else FLANK_DOOR_Y + 40 * F_ONE
			events.append({"t": "flank_warn", "x": WORLD_LEFT, "y": g["y"] + wdy})
			events.append({"t": "flank_warn", "x": WORLD_RIGHT, "y": g["y"] + wdy})
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
				_mint_token(SCREEN_CX, camera_top + 60 * F_ONE)
				var fmult: int = mini(flawless_streak, 3)
				war_chest += 50 * fmult
				score += 2000 * fmult
				events.append({"t": "gate_flawless", "x": SCREEN_CX, "y": g["y"], "mult": fmult})
			deaths_since_gate = 0
			# Guaranteed cache past every checkpoint — the gate-open beat had a big
			# audiovisual payoff but no mechanical reward; a free grenade/vest crate
			# closes that loop.
			# Victory strip (2v): the checkpoint reward is a composed PLACE —
			# crate dead-center, flanked by two fresh bags (the x rng draw is
			# deleted; the kind draw stays, so the sequence past here shifts
			# once — covered by this batch's re-record).
			pickups.append({"x": SCREEN_CX, "y": g["y"] - 60 * F_ONE,
				"kind": 1 + rng.range_i(0, 1), "cost": 0})
			# Pocket shape varies by gate parity (KIMK r2: ritual, not
			# wallpaper): odd gates = flat flank pair; even gates = a forward
			# chevron. All north of the wall — clear of every south-band system.
			if absi(g["y"] / GATE_SPACING) % 2 == 1:
				sandbags.append({"x": SCREEN_CX - 70 * F_ONE, "y": g["y"] - 60 * F_ONE, "world": 1})
				sandbags.append({"x": SCREEN_CX + 70 * F_ONE, "y": g["y"] - 60 * F_ONE, "world": 1})
			else:
				sandbags.append({"x": SCREEN_CX - 50 * F_ONE, "y": g["y"] - 80 * F_ONE, "world": 1})
				sandbags.append({"x": SCREEN_CX + 50 * F_ONE, "y": g["y"] - 80 * F_ONE, "world": 1})
				sandbags.append({"x": SCREEN_CX, "y": g["y"] - 44 * F_ONE, "world": 1})
			events.append({"t": "gate_open", "x": SCREEN_CX, "y": g["y"]})


func _breach_wall(g: Dictionary, left_side: bool, fdy: int, f_left_elite: bool) -> void:
	## One wall of a staggered flank breach (c2 2v): a 3-rusher squad from the
	## given wall, its "flank_breach" klaxon now landing at the staggered moment
	## for free. Elite parity matches the shipped layout (right on odd gates,
	## left on even). Blocked spawns ride the existing rock-nudge.
	var wx: int = WORLD_LEFT if left_side else WORLD_RIGHT
	var is_elite_wall: bool = (f_left_elite and left_side) or (not f_left_elite and not left_side)
	for fi in FLANK_SQUAD:
		_spawn_enemy(wx, g["y"] + fdy + fi * 22 * F_ONE, is_elite_wall and fi == 0)
	events.append({"t": "flank_breach", "x": wx, "y": g["y"] + fdy})


func _in_fork_wire(x: int, y: int) -> bool:
	## CACHE-lane wire strips: two fixed bands per fork that HALVE ground
	## speed (players and enemies alike) — fortified means slower, truly.
	for g in gates:
		var fx3: int = g.get("fork_x", 0)
		if fx3 == 0:
			continue
		# c2 2v: two more strips at +330/+450 extend the CACHE-lane slow cost
		# down the full ~1.7-screen commitment (was only +90/+210).
		if y >= g["y"] + 90 * F_ONE and y <= g["y"] + 110 * F_ONE \
				or (y >= g["y"] + 210 * F_ONE and y <= g["y"] + 230 * F_ONE) \
				or (y >= g["y"] + 330 * F_ONE and y <= g["y"] + 350 * F_ONE) \
				or (y >= g["y"] + 450 * F_ONE and y <= g["y"] + 470 * F_ONE):
			if (fx3 == 260 and x < fx3 * F_ONE - 44 * F_ONE) \
					or (fx3 == 380 and x > fx3 * F_ONE + 44 * F_ONE):
				return true
	return false


func _step_grass_flush() -> void:
	## c3 2v: tall grass conceals (via _in_grass -> _concealed), which made it
	## strictly dominant over solid cover. The DOWNSIDE: while a player camps
	## grass with an enemy within FLUSH_RADIUS, a cooldown runs; on expiry an
	## enemy lobs a TELEGRAPHED flush grenade onto the player's ground —
	## reusing _add_strike, but DELIBERATELY without the _concealed guard (that
	## omission IS the feature). Keyed on _in_grass, not _concealed, so smoke
	## keeps full ranged-immunity. Grass streams seg>=2 only -> torture-inert.
	for p in players:
		if not p["alive"] or p["in_tank"] >= 0 or not _in_grass(p):
			p["flush_cd"] = 0
			continue
		var threat := false
		for e in enemies:
			if e["alive"] and e["kind"] != "pilot" \
					and _dist_lte(e["x"], e["y"], p["x"], p["y"], FLUSH_RADIUS):
				threat = true
				break
		if not threat:
			p["flush_cd"] = 0
			continue
		if p["flush_cd"] <= 0:
			p["flush_cd"] = FLUSH_CD_TICKS
		p["flush_cd"] = p["flush_cd"] - 1
		if p["flush_cd"] <= 0:
			_add_strike(p["x"], p["y"])   # NO _concealed guard — grass gets flushed
			p["flush_cd"] = FLUSH_CD_TICKS


func _step_mast_hazard() -> void:
	## c3 3v: on waves 5/10/15… the endless mast denies its own orbit with a
	## phase-timed radial pulse (the foundry-vent telegraph, cloned): 90t warn,
	## then a 60t jet that hurts any on-foot player within MAST_HAZARD_RADIUS.
	## Pure read of tick_count/wave — zero new state, zero rng, endless-inert
	## before wave 3 so the wave-2 torture never sees it.
	if wave < 5 or wave % 5 != 0:
		return
	# Wave-LOCAL phase (judge r1): counting from the wave's start guarantees the
	# 90t warn always precedes the first jet — a global-tick phase could drop a
	# jet on wave entry with no tell. wave_start_tick is derived, never hashed.
	var phase: int = posmod(tick_count - wave_start_tick, MAST_CYCLE_TICKS)
	if phase == MAST_CYCLE_TICKS - MAST_JET_TICKS - MAST_WARN_TICKS:
		events.append({"t": "mast_warn", "x": MAST_X, "y": MAST_Y})
	elif phase >= MAST_CYCLE_TICKS - MAST_JET_TICKS:
		if phase == MAST_CYCLE_TICKS - MAST_JET_TICKS:
			events.append({"t": "mast_pulse", "x": MAST_X, "y": MAST_Y})
		for p in players:
			if p["alive"] and p["in_tank"] < 0 and not p["roll_iframe"] \
					and _dist_lte(p["x"], p["y"], MAST_X, MAST_Y, MAST_HAZARD_RADIUS):
				_hurt_player(p)


func _in_rubble(x: int, y: int) -> bool:
	## c3 5v: the ruins (seg 3) signature VERB — collapsed-pillar rubble that
	## HALF-SPEEDS boots (the _in_mud primitive, seg-3 exclusive). Two hash-
	## placed 80px-wide × 40px-tall patches per band; pure function, zero rng,
	## zero state. seg 3 is past the torture reach, so golden-inert.
	if absi(y) / GATE_SPACING != RUINS_SEG:
		return false
	var off: int = absi(y) % GATE_SPACING
	for k in 2:
		var rh: int = _mix(RUINS_SEG * 100 + k, _world_seed)
		var ry: int = (250 + k * 380 + rh % 120) * F_ONE
		var rx: int = (100 + (rh >> 8) % 420) * F_ONE
		if off >= ry - 20 * F_ONE and off <= ry + 20 * F_ONE and absi(x - rx) <= 40 * F_ONE:
			return true
	return false


func _in_trench(x: int, y: int) -> bool:
	## c3 2v: pseudo-elevation, trimmed to a flat SUNKEN TRENCH — a conceal zone
	## that also DRAGS the boots (85% speed: gentler than the /2 slow zones, and
	## NON-STACKING with them). One hash-placed lateral ditch per band from
	## COVER_VARIETY_SEG on; pure, rng-free, zero state. seg >= 2 is past the
	## campaign torture reach, and endless y stays in band 0-1, so both goldens
	## stay byte-identical (kept out of the checksum feed, like grass "kind").
	var band: int = absi(y) / GATE_SPACING
	if band < COVER_VARIETY_SEG:
		return false
	var off: int = absi(y) % GATE_SPACING
	var th: int = _mix(band * 70 + 7, _world_seed)
	var ty: int = (200 + th % 500) * F_ONE
	var tx: int = (120 + (th >> 8) % 380) * F_ONE
	return off >= ty - 24 * F_ONE and off <= ty + 24 * F_ONE and absi(x - tx) <= 60 * F_ONE


func _in_mud(_x: int, y: int) -> bool:
	## Mud banks flank every river (2v): full-width MUD_BANK_H strips above
	## and below each band — ford approaches included (honest risk beat).
	## Half speed for boots; rolls stay legal; armor doesn't care.
	for w in waters:
		if (y >= w["y"] - MUD_BANK_H and y < w["y"]) \
				or (y > w["y"] + WATER_H and y <= w["y"] + WATER_H + MUD_BANK_H):
			return true
	return false


func _ford_current(y: int) -> int:
	## c3 2v: deeper river bands (idx>=2) push a wader/forder sideways
	## FORD_CURRENT/tick in a per-band hashed, LEARNABLE direction (same _mix
	## grammar as MARSH_DRIFT) — the crossing becomes an active beat, drifting
	## the firing ORIGIN (never the aim vector). Band 1 (the torture band)
	## returns 0, so both goldens stay byte-identical.
	for w in waters:
		if y >= w["y"] and y <= w["y"] + WATER_H:
			var band_idx: int = absi(w["y"] / GATE_SPACING)
			if band_idx < 2:
				return 0
			return FORD_CURRENT if _mix(band_idx, _world_seed) & 1 else -FORD_CURRENT
	return 0


func _in_water(x: int, y: int) -> bool:
	## Water/ford variation (8v): deeper bands earn a SECOND ford (every 3rd
	## band) and a dry mid-river ISLAND with wet lips (every 4th) — all pure
	## derivations from the band's existing y/ford_x, zero new rng or fields.
	## Band 1 (the torture band) hits neither branch: byte-identical behavior.
	for w in waters:
		if y >= w["y"] and y <= w["y"] + WATER_H:
			var band_idx: int = absi(w["y"] / GATE_SPACING)
			# Depth-tightening (KIMK r2: rivers must EVOLVE, not just vary):
			# ford width compresses as the run deepens — full at band 1, -4px
			# per band, floored at half. Band 1 keeps FORD_HALF_W exactly.
			var fw: int = maxi(FORD_HALF_W / 2, FORD_HALF_W - (band_idx - 1) * 4 * F_ONE)
			if x >= w["ford_x"] - fw and x <= w["ford_x"] + fw:
				# c4 2v COLLAPSING BRIDGE (band>=2): the main ford is dry-foot only in
				# the OPEN phase; during the CLOSED phase it washes out (you wade / edge-
				# revert). Phase-cycled from tick_count (no contact timer, no new field);
				# band 1 (the torture ford) is unaffected -> goldens byte-identical.
				if band_idx >= 2 and posmod(tick_count + band_idx * 150, 600) >= 180:
					return true   # CLOSED — the bridge is washed out (wade)
				return false     # dry ford (OPEN)
			# Hash stream: the SAME decorrelation-tested _mix as L10's chunks
			# (KIMK round-3: no unaudited randomness sources).
			var wh2 := _mix(band_idx, w["ford_x"] / F_ONE)
			if band_idx % 3 == 2:
				# Second ford: hash-derived 180-300px offset (was const 240 —
				# a learnable rotation, KIMK r2), same depth-tightened width.
				var ford2_x: int = 80 * F_ONE + ((w["ford_x"] - 80 * F_ONE) + (180 + wh2 % 121) * F_ONE) % (480 * F_ONE)
				if x >= ford2_x - fw and x <= ford2_x + fw:
					return false
			if band_idx >= 4 and band_idx % 4 == 0:
				# Island placed relative to BOTH fords on overlap bands (idx%12
				# == 8): midway between them, never across either (designed +
				# pinned, KIMK r2). Otherwise offset from the main ford.
				var isl_x2: int
				if band_idx % 12 == 8:
					var f2: int = 80 * F_ONE + ((w["ford_x"] - 80 * F_ONE) + (180 + wh2 % 121) * F_ONE) % (480 * F_ONE)
					isl_x2 = 80 * F_ONE + (((w["ford_x"] + f2) / 2 - 80 * F_ONE) + 240 * F_ONE) % (480 * F_ONE)
				else:
					isl_x2 = 80 * F_ONE + ((w["ford_x"] - 80 * F_ONE) + 120 * F_ONE) % (480 * F_ONE)
				if absi(x - isl_x2) <= 60 * F_ONE and y >= w["y"] + 20 * F_ONE and y <= w["y"] + 60 * F_ONE:
					return false
			return true
	return false


# --- Camera & world streaming ---

func _step_camera() -> void:
	# c4 2v: lane-block TELEGRAPH — emit warn/seal/clear cues for the band in view
	# so a seal reads before it commits. Checksum-excluded events; pure phase read.
	if mode == "campaign":
		var lb_band: int = absi(camera_top) / GATE_SPACING
		if lb_band >= CHOKE_START_SEG:
			var lbh := _mix(lb_band, 733)
			var lbphase: int = posmod(tick_count + lb_band * 300, LANE_BLOCK_CYCLE)
			var lbx: int = (WORLD_LEFT + 100 * F_ONE) if lbh & 1 == 0 else (WORLD_RIGHT - 100 * F_ONE)
			var lby: int = -(lb_band * GATE_SPACING + (250 + lbh % 400 + 60) * F_ONE)
			if lbphase == LANE_BLOCK_CYCLE - LANE_BLOCK_WARN:
				events.append({"t": "lane_warn", "x": lbx, "y": lby})
			elif lbphase == 0:
				events.append({"t": "lane_seal", "x": lbx, "y": lby})
			elif lbphase == LANE_BLOCK_SEALED:
				events.append({"t": "lane_clear", "x": lbx, "y": lby})
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

	if mode != "campaign" and mode != "arcade":
		return   # boss_rush pre-authors its whole gate gauntlet in _init; nothing to stream
		# (endless never reaches here at all -- see step()). Arcade reuses the
		# FULL campaign streaming machinery below (it's the same authored world,
		# just entered mid-way via jump_to_chapter()), so it must NOT no-op here.

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
		var m_slot: int = absi(_next_mine_y / MINE_SPACING)
		var m_gate_off: int = absi(_next_mine_y) % GATE_SPACING
		if m_slot % 2 == 0 and not _in_choke_apron(_next_mine_y) and m_gate_off >= 80 * F_ONE \
				and not _is_calm_band(_next_mine_y):
			var mh2 := _mix(m_slot, _world_seed)
			var m_pick: int = mh2 % MINE_CHUNKS.size()
			# No-immediate-repeat window (KIMK r2): a slot never repeats its
			# neighbor's chunk — recompute the neighbor's pick the same way.
			var m_prev: int = _mix(m_slot - 2, _world_seed) % MINE_CHUNKS.size()
			if m_pick == m_prev:
				# Re-pick offsets FROM the neighbor by 1..n-1: != by construction,
				# single-shot, no retry loop to bound (KIMK round-3).
				m_pick = (m_prev + 1 + (mh2 >> 16) % (MINE_CHUNKS.size() - 1)) % MINE_CHUNKS.size()
			var m_chunk: Array = MINE_CHUNKS[m_pick]
			var m_ax: int = (150 + (mh2 >> 8) % 340) * F_ONE
			for od in m_chunk:
				# Bunker exclusion (c2 4v): per-offset, so a chunk CAN straddle
				# the ring — only the offending mines vanish, not the pattern.
				var m_py: int = _next_mine_y + od[1] * F_ONE
				var m_px: int = _arena_margin_x(m_ax + od[0] * F_ONE, m_py)
				# c2-authored-campaign: the calm-band guard above only tests the
				# ROW ANCHOR -- a chunk member with a large dy offset can still
				# land inside the calm band from an anchor that sits just
				# outside it (BARREL_SPACING/MINE_SPACING don't divide
				# GATE_SPACING evenly, so this can happen for any seed). Re-test
				# the ACTUAL placement, same as the bunker-exclusion re-test.
				if not _near_stream_bunker(m_px, m_py) and not _is_calm_band(m_py):
					mines.append({"x": m_px, "y": m_py, "armed": true})
		_next_mine_y -= MINE_SPACING
	# Stream explosive fuel-barrel CLUSTERS off the gate rows — live ordnance a
	# grenade chains through (and that catches you if you stand too close).
	while _next_barrel_y > camera_top - 2 * VIEW_H:
		var b_slot: int = absi(_next_barrel_y / BARREL_SPACING)
		var b_gate_off: int = absi(_next_barrel_y) % GATE_SPACING
		# Barrels inherit the mines' gate-row strip guard (c2 4v: the torture
		# barrel row sits at offset 320, so the goldens never see this branch).
		if b_slot % 2 == 1 and not _in_choke_apron(_next_barrel_y) and b_gate_off >= 80 * F_ONE \
				and not _is_calm_band(_next_barrel_y):
			var bh2 := _mix(b_slot + 7919, _world_seed)
			var b_chunk: Array = BARREL_CHUNKS[bh2 % BARREL_CHUNKS.size()]
			var b_ax: int = (120 + (bh2 >> 8) % 400) * F_ONE
			for od in b_chunk:
				# Same per-offset bunker exclusion as the mine stream, plus the
				# same per-offset calm-band re-test (see the mine stream above
				# for why the row-anchor-only guard isn't enough).
				var b_py: int = _next_barrel_y + od[1] * F_ONE
				var b_px: int = _arena_margin_x(b_ax + od[0] * F_ONE, b_py)
				if not _near_stream_bunker(b_px, b_py) and not _is_calm_band(b_py):
					barrels.append({"x": b_px, "y": b_py, "armed": true, "fuse_ticks": 0})
		_next_barrel_y -= BARREL_SPACING
	# Foundry heat vents (c2 5v): seg-4+ EXCLUSIVE — authored chunks on their
	# own slot cadence, _mix-picked with a prime salt (decorrelated from mine/
	# barrel picks). Rows dodge gate rows, choke aprons (hazard-free by the
	# cycle-1 contract), and the water-band cadence incl. mud lips (bands sit
	# at offset 500, WATER_H 80, MUD_BANK_H 40 → keep-out 460-620) — widened
	# ±60 on both guards because chunk dy offsets reach ±60 from the row.
	while _next_vent_y > horizon:
		var v_seg: int = absi(_next_vent_y) / GATE_SPACING
		var v_off: int = absi(_next_vent_y) % GATE_SPACING
		if v_seg >= VENT_START_SEG and not _in_choke_apron(_next_vent_y) \
				and v_off >= 140 * F_ONE and (v_off < 400 * F_ONE or v_off > 680 * F_ONE):
			var v_slot: int = absi(_next_vent_y / VENT_SPACING)
			var vh := _mix(v_slot + 104729, _world_seed)
			var v_chunk: Array = VENT_CHUNKS[vh % VENT_CHUNKS.size()]
			var v_ax: int = (230 + (vh >> 8) % 180) * F_ONE
			for od in v_chunk:
				vents.append({"x": v_ax + od[0] * F_ONE, "y": _next_vent_y + od[1] * F_ONE})
		_next_vent_y -= VENT_SPACING
	while _next_rock_y > horizon:
		var r_idx: int = absi(_next_rock_y / ROCK_SPACING)
		# Dry-land + open-corridor predicate (pure math, no array reads): skip
		# the water band cadence (+margin) and the gate arena/fork zone.
		var r_off: int = posmod(-_next_rock_y / F_ONE, 1000)
		if r_idx % 3 != 0 and r_off < 700 and (r_off < 400 or r_off > 520) \
				and not _in_fork_apron(_next_rock_y):
			var rx: int = (80 + ((r_idx * 2654435761) & 0x7FFFFFFF) % 460) * F_ONE
			# Cover TIER by hash (c2 3v), weighted 3 classic : 2 grass : 1 wall.
			# Forced classic in segs 0-1 (COVER_VARIETY_SEG) so both torture
			# windows are byte-identical — the tier's extents/solidity only
			# ever differ past the golden reach.
			if absi(_next_rock_y) / GATE_SPACING >= COVER_VARIETY_SEG:
				# c3 2v: past the golden reach, the ambient stream places an
				# authored concave POCKET (not a scatter pair) so connective
				# cover reads as committed fight-geometry, not wallpaper. Pieces
				# are classic or grass (the ruins get their wall-mass from the
				# maze stub below); every pocket lane clears HULL_CLEARANCE by
				# the baked-in >=80px flank spacing. _mix pick, rng-free.
				var pmix := _mix(r_idx, _world_seed)
				var cb := _choke_bounds(_next_rock_y)
				var wide: bool = cb[0] == WORLD_LEFT and cb[1] == WORLD_RIGHT
				# c4-05: WIDE rows hug a WALL (edge cover, open center for the long shot);
				# NARROW rows cluster mid-lane (CQB). Rooms + pockets share this anchor.
				if wide:
					rx = (110 if r_idx % 2 == 0 else 530) * F_ONE
				else:
					rx = (cb[0] + cb[1]) / 2
				if pmix % 3 == 0:
					# c4 3v ROOM: a 4-part mouth->interior->rear-gate grammar (per-piece
					# kind, fixed HULL_CLEARANCE lanes) — the richer half of the pocket set.
					var room: Array = COVER_ROOMS[(pmix >> 4) % COVER_ROOMS.size()]
					for rp in room:
						var rpx: int = rx + rp[0] * F_ONE
						var rpy: int = _next_rock_y + rp[1] * F_ONE
						rocks.append({"x": _arena_margin_x(rpx, rpy), "y": rpy, "kind": rp[2]})
				else:
					# c4-05 density pocket: WIDE spreads (spc 5/5), NARROW tightens (3/5).
					var pocket: Array = COVER_POCKETS[pmix % COVER_POCKETS.size()]
					var spc: int = 5 if wide else 3
					for po in pocket:
						var ppx: int = rx + (po[0] * spc / 5) * F_ONE
						var ppy: int = _next_rock_y + (po[1] * spc / 5) * F_ONE
						rocks.append({"x": _arena_margin_x(ppx, ppy), "y": ppy, "kind": 0})
			else:
				# Segs 0-1 (the torture window) keep the shipped classic 2-rock
				# pair verbatim — golden-inert.
				rocks.append({"x": _arena_margin_x(rx, _next_rock_y), "y": _next_rock_y, "kind": 0})
				rocks.append({"x": _arena_margin_x(rx + 22 * F_ONE, _next_rock_y + 10 * F_ONE),
					"y": _next_rock_y + 10 * F_ONE, "kind": 0})
		# c3 5v: the seg-3 ruins get an authored MAZE-WALL run so the labyrinth
		# reads even though band 3 is squeezed between gate-3's boss arena and
		# gate-4's fork island. Confined to the band's CLEAN southern third
		# (off 60-350 = y -3060..-3350: south of the fork island at -3380..-3960,
		# north of the gate-3 boss row): a 3-slab kind-2 wall on one flank, x kept
		# inside [78,534] (clears the breach x>60 pin). seg 3 = past the torture.
		if absi(_next_rock_y) / GATE_SPACING == RUINS_SEG:
			# c4 3v RUINS DUAL-LANE (r2): the whole split is ONE continuous fixed-coord
			# stretch, fired once per band-3 via ROCK_SPACING containment (off=200): a
			# covered RIGHT wall column (kind-2) + a central PERMEABLE divider (world-
			# bags at SCREEN_CX) + an exposed LEFT lane, all co-placed over off 40..312
			# (~272px; the shipped fork-4 island caps the span north). Left WORLD_LEFT..
			# 302 and right 338..WORLD_RIGHT both clear HULL_CLEARANCE (the wall at 470
			# leaves 92px/114px sub-lanes). Band 3 = torture-inert -> goldens hold.
			var ruins_div_y: int = -(RUINS_SEG * GATE_SPACING + 200 * F_ONE)
			if _next_rock_y <= ruins_div_y and _next_rock_y + ROCK_SPACING > ruins_div_y:
				var rd_top: int = -(RUINS_SEG * GATE_SPACING + 40 * F_ONE)
				for dv in 5:
					var ry5: int = rd_top - (dv * 68) * F_ONE
					sandbags.append({"x": SCREEN_CX, "y": ry5, "world": 1})   # permeable central divider
					rocks.append({"x": 470 * F_ONE, "y": ry5, "kind": 2})     # covered right-lane wall
				# c4 2v PLAYER-TRIGGERED GEOMETRY: a CRACKED WALL (kind-2 slab + an armed
				# barrel — shoot the barrel and the c4-10 _explode wall-breach opens the
				# LEFT/exposed lane) and a STRUT (a barrel that DROPS a slag-pour wall
				# onto the exposed lane when shot, which enemies reroute around). Ruins
				# band 3 = torture-inert -> goldens byte-identical.
				var pg_y: int = rd_top - 34 * F_ONE
				rocks.append({"x": 130 * F_ONE, "y": pg_y, "kind": 2})
				if not _near_stream_bunker(130 * F_ONE, pg_y + 18 * F_ONE):
					barrels.append({"x": 130 * F_ONE, "y": pg_y + 18 * F_ONE, "armed": true, "fuse_ticks": 0})
				if not _near_stream_bunker(210 * F_ONE, pg_y + 140 * F_ONE):
					barrels.append({"x": 210 * F_ONE, "y": pg_y + 140 * F_ONE,
						"armed": true, "fuse_ticks": 0, "strut": true})
		_next_rock_y -= ROCK_SPACING
	while _next_gate_y > horizon and not _world_ended:
		_gate_counter += 1
		if _gate_counter == FINAL_GATE_INDEX:
			# The end of the road: the Foundry. Nothing streams past it.
			_stamp_final_gate(_next_gate_y)
			_world_ended = true
			break
		if _gate_counter % BOSS_GATE_EVERY == 0:
			# Bridge boss gate: no arena bunkers — the Gunship IS the lock.
			_stamp_gunship_gate(_next_gate_y, 0, true)
			# Boss stretches compose too (c2 3v — see _stamp_stretch_setpieces).
			_stamp_stretch_setpieces()
		else:
			# Arena template lookup (unlisted indexes fall back to classic —
			# future-proof if FINAL_GATE_INDEX ever grows).
			var arena: Dictionary = ARENAS.get(_gate_counter, ARENAS[1])
			var b1 := _make_bunker(arena["b1"][0] * F_ONE, _next_gate_y + arena["b1"][1] * F_ONE)
			var b2 := _make_bunker(arena["b2"][0] * F_ONE, _next_gate_y + arena["b2"][1] * F_ONE)
			bunkers.append(b1)
			bunkers.append(b2)
			_stamp_stretch_setpieces()
			# Hardpoint HERO wreck ~140px south of every bunker-pair gate,
			# flank-alternating: the mortar-observer fallback cover the panel
			# asked for. Kind-3 focal silhouette (32x24, drawn 2x — the "one
			# 1.5-2x hero landmark per hardpoint", c2 3v) ONLY past the torture
			# window; gate 1 keeps the shipped classic-extent rock so goldens
			# hold (the bigger extent inside the window would re-record).
			var hero_kind: int = 3 if absi(_next_gate_y) / GATE_SPACING >= COVER_VARIETY_SEG else 0
			rocks.append({"x": (150 if _gate_counter % 2 == 1 else 490) * F_ONE,
				"y": _next_gate_y + 140 * F_ONE, "kind": hero_kind})
			# c4 2v PER-SECTOR LANDMARK (was a 1-in-2 random ruined wall): a UNIQUE
			# authored solid mass keyed by SECTOR so a large landmark tells you which
			# sector you are in (a routing anchor, not a random wall) — sector 2 marsh
			# = a PIPELINE run (kind-2), sector 4 foundry = a CRANE hero pair (kind-3),
			# sector 5 = a crashed RUINS convoy (kind-2 line). Seg>=2 only (the ~-1957
			# stream horizon leaves gate 2+ unstreamed in torture -> goldens byte-
			# identical); every lane clears HULL_CLEARANCE by the 80px kind-2 pitch;
			# solidity is free via the rock move-revert. Opposite flank to the hero wreck.
			# c2-authored-campaign: the RUINS case moves off dead case-3 (gate 3 is
			# ALWAYS the boss gate -- BOSS_GATE_EVERY -- so lm_sector could never be 3;
			# this landmark had never once fired) onto case-5, which the FINAL_GATE_INDEX
			# 5->6 shift just turned into a real, reachable bunker arena.
			if absi(_next_gate_y) / GATE_SPACING >= COVER_VARIETY_SEG:
				var lm_sector: int = absi(_next_gate_y) / GATE_SPACING
				var wall_side: int = 460 if _gate_counter % 2 == 1 else 60   # opposite the hero
				var lm_y: int = _next_gate_y + 220 * F_ONE
				var inward: int = 40 if wall_side < 320 else -40
				match lm_sector:
					2:
						# MARSH pipeline: a 3-slab kind-2 HORIZONTAL run (80px pitch, one
						# hash-dropped lane slot >= HULL_CLEARANCE).
						var pg: int = _mix(_gate_counter, 907) % 3
						for ws in 3:
							if ws != pg:
								rocks.append({"x": _arena_margin_x((wall_side + (ws - 1) * 80) * F_ONE, lm_y), "y": lm_y, "kind": 2})
					4:
						# FOUNDRY crane: a kind-3 hero focal PAIR (a tall recognizable mass).
						rocks.append({"x": _arena_margin_x(wall_side * F_ONE, lm_y), "y": lm_y, "kind": 3})
						rocks.append({"x": _arena_margin_x((wall_side + inward) * F_ONE, lm_y), "y": lm_y - 44 * F_ONE, "kind": 3})
					5:
						# RUINS crashed-convoy: a 4-slab kind-2 LINE that dovetails the maze,
						# 76px pitch with a hash-dropped car (the gap threads a hull lane).
						# c2-authored-campaign: gate 5 sits inside the COLOSSUS_ARENA_SEG
						# escape corridor (band >= 4) for the first time now that it's a
						# real arena, not the old truncation point -- the 228px-wide line
						# (4 slabs @ 76px pitch) can reach past the ARENA_MARGIN corridor
						# at either wall_side, so it's the one landmark that needs the
						# same clamp the ambient mine/barrel streams already carry. Its row
						# also sits at +160 (not the shared +220) -- test-swept against the
						# ambient ROCK stream's own hero-kind pieces at every gate-5 seed the
						# opposite-flank suite checks (3/43/97): +220 lands within 200y of an
						# unrelated ambient kind-3 piece for seed 3.
						var lm_y5: int = _next_gate_y + 160 * F_ONE
						var tg: int = _mix(_gate_counter, 907) % 4
						for ws in 4:
							if ws != tg:
								rocks.append({"x": _arena_margin_x((wall_side + (ws - 1) * 76) * F_ONE, lm_y5), "y": lm_y5, "kind": 2})
					_:
						# Belt-and-braces default (unreachable today: every arena-gate
						# lm_sector is 1 [excluded by the guard above], 2, 4 or 5, all
						# named above) -- an offset stack so a future arena gate never
						# silently drops the landmark grammar.
						rocks.append({"x": _arena_margin_x(wall_side * F_ONE, lm_y), "y": lm_y, "kind": 2})
						rocks.append({"x": _arena_margin_x((wall_side + inward) * F_ONE, lm_y), "y": lm_y - 24 * F_ONE, "kind": 2})
						rocks.append({"x": _arena_margin_x((wall_side + inward + inward) * F_ONE, lm_y), "y": lm_y - 48 * F_ONE, "kind": 2})
			for pr in arena["props"]:
				if pr[0] == "mine":
					mines.append({"x": pr[1] * F_ONE, "y": _next_gate_y + pr[2] * F_ONE, "armed": true})
				else:
					barrels.append({"x": pr[1] * F_ONE, "y": _next_gate_y + pr[2] * F_ONE,
						"armed": true, "fuse_ticks": 0})
			# fork_x: 0 = no fork. Gate 2 islands at 260 (CACHE narrow-left,
			# fortified); gate 4 MIRRORS to 380 (the killbox becomes the
			# corridor — the second fork teaches a new read, KIMK round-2).
			gates.append({"y": _next_gate_y, "open": false, "b1": b1, "b2": b2, "boss": {},
				"fork_x": (260 if _gate_counter == 2 else 380) if (_gate_counter == 2 or _gate_counter == 4) else 0})
			# Route Fork (panel 8-vote): the approach to bunker-pair gates 2 & 4
			# splits into two telegraphed lanes — walking a side IS the choice
			# (pure position: no new input, no stored state, gates[] is unhashed).
			# LEFT = Cache lane: a free crate ringed by extra mines. RIGHT =
			# Gauntlet lane: two extra elites, one a guaranteed marked bounty.
			# Torture-inert: the 60 s campaign run never streams past gate 1
			# (probe-verified — camera_top ends ~43 units short of gate 2).
			if _gate_counter == 2 or _gate_counter == 4:
				# c3 4v: the gauntlet stops being always-a-killbox. mod-4 of the
				# per-seed _mix gives three READS you must learn to tell apart:
				# ==0 TRAP (extra ambush), ==2 BLUFF (looks fortified but the
				# defenders are gone — free high-tier loot for reading the empty
				# threat), else HONEST killbox. The sandbag LOOK never changes;
				# only the defenders do — reading past the dressing is the skill.
				var is_bluff: bool = _mix(_gate_counter, _world_seed) % 4 == 2
				var fcx: int = (90 + rng.range_i(0, 120)) * F_ONE
				var fcy: int = _next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE
				pickups.append({"x": fcx, "y": fcy, "kind": 1 + rng.range_i(0, 1), "cost": 0})
				for m in 3:
					var fmx: int = (70 + rng.range_i(0, 180)) * F_ONE
					var fmy: int = _next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE
					# A mine sitting ON the free crate priced the "free" cache at
					# 1 HP (re-review, ~9%/fork) — nudge it clear deterministically.
					if absi(fmx - fcx) < 28 * F_ONE and absi(fmy - fcy) < 28 * F_ONE:
						fmx += 48 * F_ONE
					mines.append({"x": fmx, "y": fmy, "armed": true})
				# c3 4v: on a BLUFF seed the gauntlet's defenders never spawn — the
				# lane LOOKS the same (sandbags below still stream) but is empty.
				# The rng draws stay unconditional so the (torture-inert) fork
				# stream is byte-identical seed-to-seed; only the spawns are gated.
				for s in 2:
					var fex: int = (360 + rng.range_i(0, 160)) * F_ONE
					var fey: int = _next_gate_y + (60 + rng.range_i(0, 240)) * F_ONE
					if is_bluff:
						continue
					_spawn_enemy(fex, fey, true)
					# Lane leash (re-review: un-leashed elites walked the corridor
					# and engaged the CACHE lane before the signposts were even on
					# screen — the choice has to survive until it's made). They
					# stand down until a player crosses the band's south edge.
					var fge: Dictionary = enemies[enemies.size() - 1]
					if fge["kind"] == "elite":
						fge["hold_y"] = _next_gate_y + 380 * F_ONE
				if not is_bluff and not enemies.is_empty():
					var fmk: Dictionary = enemies[enemies.size() - 1]
					if fmk["kind"] == "elite":
						fmk["marked"] = true
				# Mechanical lane truth (KIMK round-2: dressing must not be
				# paint one level down): BOUNTY's sandbag arcs are REAL bags
				# (full cover grammar, destructible), CACHE's wire is a real
				# slow zone via _in_fork_wire.
				var bounty_x0: int = 380 if _gate_counter == 2 else 60
				for fbg in 4:
					sandbags.append({"x": (bounty_x0 + 40 + fbg * 45) * F_ONE,
						"y": _next_gate_y + (110 + (fbg % 2) * 120) * F_ONE})
				events.append({"t": "route_fork", "x": (260 if _gate_counter == 2 else 380) * F_ONE,
					"y": _next_gate_y})
				# c2 2v: DEEPEN the fork into a ~1.7-screen commitment + a 1-in-4
				# BAIT variant. All _mix-derived (the shared rng sequence stays
				# clean), gate 2/4 only (torture never streams here), no new gate
				# field. bounty_x0 is the GAUNTLET (fortified-looking) side.
				var fmix := _mix(_gate_counter, _world_seed)
				# Deeper content beats: CACHE +2 mines, GAUNTLET +1 leashed elite.
				var cache_x0: int = 70 if _gate_counter == 2 else 400
				# Beats live SOUTH of the c2-03 decision apron (+300..460 stays
				# clean so the choice reads) and route through the same bunker
				# exclusion as the main streams.
				for dm in 2:
					var cmx: int = (cache_x0 + (fmix >> (dm * 4)) % 150) * F_ONE
					var cmy: int = _next_gate_y + (500 + dm * 80) * F_ONE
					if not _near_stream_bunker(cmx, cmy):
						mines.append({"x": cmx, "y": cmy, "armed": true})
				# The deep gauntlet elite also stands down on a bluff seed.
				if not is_bluff:
					_spawn_enemy((bounty_x0 + 40 + (fmix >> 8) % 120) * F_ONE,
						_next_gate_y + 560 * F_ONE, true)
					var deep_e: Dictionary = enemies[enemies.size() - 1]
					if deep_e["kind"] == "elite":
						deep_e["hold_y"] = _next_gate_y + 680 * F_ONE
				# c3 4v REWARD: a guaranteed high-tier OFFENSE capsule (Pierce/
				# Spread/Triple — strictly above the cache lane's grenade/vest) sits
				# at the DEEP end of the gauntlet, past the leash lines, so clearing
				# the killbox pays and the bluff pays for reading it. kind 4/5/6.
				# c4 5v FORK REWARD VARIETY: 1-in-3 forks swap the offense capsule for a
				# defensive VEST VAULT — the deep reward is a guaranteed Flak Vest (kind
				# 2) ringed by 2 extra guarding mines (the panel's "guaranteed-Vest
				# hazard room" compressed). Reward TYPE now varies across forks instead
				# of always being an offense buff, so the off-lane gauntlet payoff earns
				# a fresh read. _mix-derived, gate 2/4 only -> both goldens byte-identical.
				# Gate-4 only: fork gate 2 (-2000) is stamped ahead of the campaign
				# torture camera, so its reward stays fixed; gate 4 (-4000) is inert.
				if _gate_counter >= 4 and (fmix >> 12) % 3 == 0:
					pickups.append({"x": (bounty_x0 + 60) * F_ONE, "y": _next_gate_y + 620 * F_ONE,
						"kind": 2, "cost": 0})   # guaranteed Flak Vest
					# A 3-mine ring + two framing sandbag walls read the pocket as a VAULT
					# (a walled hazard room), not a loose drop.
					for vmo in [-40, 0, 40]:
						var vmx: int = (bounty_x0 + 60) * F_ONE + vmo * F_ONE
						var vmy: int = _next_gate_y + 660 * F_ONE
						if not _near_stream_bunker(vmx, vmy):
							mines.append({"x": vmx, "y": vmy, "armed": true})
					for vbo in [-56, 56]:
						sandbags.append({"x": (bounty_x0 + 60) * F_ONE + vbo * F_ONE,
							"y": _next_gate_y + 600 * F_ONE})
				else:
					pickups.append({"x": (bounty_x0 + 60) * F_ONE, "y": _next_gate_y + 620 * F_ONE,
						"kind": 4 + fmix % 3, "cost": 0})   # offense capsule (Pierce/Spread/Triple)
				# BAIT (1-in-4): the fortified-LOOKING gauntlet lane is a kill-box
				# — extra sandbags read as the reward lane, but 2 ambush elites +
				# a mine cluster punish the autopilot pick; the cache lane is
				# comparatively safe. NO hard dead-end cap: the ratchet camera
				# can't backtrack far enough to escape a true wall without a
				# softlock, so the cost is the FIGHT, not an unwinnable trap. No
				# honest signpost — reading the bait IS the skill.
				if fmix % 4 == 0:
					for bg2 in 2:
						sandbags.append({"x": (bounty_x0 + 40 + bg2 * 45) * F_ONE,
							"y": _next_gate_y + (490 + bg2 * 40) * F_ONE})
					for amb in 2:
						_spawn_enemy((bounty_x0 + 30 + amb * 60) * F_ONE,
							_next_gate_y + 560 * F_ONE, true)
						var ae: Dictionary = enemies[enemies.size() - 1]
						if ae["kind"] == "elite":
							ae["hold_y"] = _next_gate_y + 560 * F_ONE
					for bm in 3:
						var bmx: int = (bounty_x0 + 20 + bm * 40) * F_ONE
						var bmy: int = _next_gate_y + (500 + bm * 30) * F_ONE
						if not _near_stream_bunker(bmx, bmy):
							mines.append({"x": bmx, "y": bmy, "armed": true})
					events.append({"t": "route_bait", "x": (bounty_x0 + 80) * F_ONE, "y": _next_gate_y})
		_next_gate_y -= GATE_SPACING
	while _next_tank_y > horizon:
		tanks.append({
			"x": SCREEN_CX, "y": _next_tank_y,
			"alive": true, "burning": false,
			"fuel": TANK_FUEL_TICKS, "burn_ticks": 0,
			"fire_cd": 0, "occupant": -1,
		})
		# c2-authored-campaign: this pocket had no calm-band guard at all (the
		# OTHER anti-armor barrel pair a few lines down does) -- harmless while
		# CALM_BAND_SEG==4 never lined up with an odd tank row for the swept
		# seeds, but CALM_BAND_SEG==5 does (tank rows land on every *1000 from
		# a -750 base, so an odd row can coincide with any band). Same guard
		# as the sibling pair below, for the same reason.
		if absi(_next_tank_y / GATE_SPACING) % 2 == 1 and not _is_calm_band(_next_tank_y):
			# Cover pocket (2v): a barrel pair tucked beside every other parked
			# tank — hard cover with a live-ordnance tradeoff.
			barrels.append({"x": SCREEN_CX - 46 * F_ONE, "y": _next_tank_y + 8 * F_ONE,
				"armed": true, "fuse_ticks": 0})
			barrels.append({"x": SCREEN_CX - 28 * F_ONE, "y": _next_tank_y + 8 * F_ONE,
				"armed": true, "fuse_ticks": 0})
		# c4 3v ANTI-ARMOR GEOMETRY: seg>=2 tank bands get two flanking solid slabs
		# so the fight stops being an open-field circle-strafe — the slabs break the
		# tank/technical long-axis shot and give the player hard cover, threading a
		# hull-clear lane between them. Solid-to-all (no per-entity collision class
		# needed) + a hedgehog barrel pair. seg>=2 tanks (-2750+) are torture-inert
		# so both goldens hold. (The plow-path/rut AI was cut as YAGNI.)
		if absi(_next_tank_y) / GATE_SPACING >= COVER_VARIETY_SEG and not _is_calm_band(_next_tank_y):
			for asx in [SCREEN_CX - 90 * F_ONE, SCREEN_CX + 90 * F_ONE]:
				var asy: int = _next_tank_y + 40 * F_ONE
				# kind-0 solid stone (not a kind-2 wall) so the anti-armor cover never
				# contests the maze/hero opposite-flank invariant; still blocks the
				# tank/technical long shot and gives the player hard cover.
				rocks.append({"x": _arena_margin_x(asx, asy), "y": asy, "kind": 0})
			for hbx in [SCREEN_CX + 46 * F_ONE, SCREEN_CX + 64 * F_ONE]:
				if not _near_stream_bunker(_arena_margin_x(hbx, _next_tank_y + 8 * F_ONE), _next_tank_y + 8 * F_ONE):
					barrels.append({"x": _arena_margin_x(hbx, _next_tank_y + 8 * F_ONE),
						"y": _next_tank_y + 8 * F_ONE, "armed": true, "fuse_ticks": 0})
		_next_tank_y -= GATE_SPACING
	while _next_water_y > horizon:
		var water := {"y": _next_water_y, "ford_x": rng.range_i(80, 560) * F_ONE}
		waters.append(water)
		# Frogmen lurk in every river.
		for f in 3:
			_spawn_frogman(rng.range_i(40, 600) * F_ONE, _next_water_y + rng.range_i(10, 70) * F_ONE)
		# c3 2v MUD LURKER: deeper rivers (band >= 2) post a submerged frogman at
		# the ford MOUTH, near the north bank — so a player stepping into the
		# approach mud reliably has a lurker to pop (the mud-surface verb is felt
		# in play, not just in tests). No rng draw (derived from ford_x), and
		# band >= 2 is past both torture windows -> goldens byte-identical.
		if absi(_next_water_y / GATE_SPACING) >= 2:
			_spawn_frogman(water["ford_x"], _next_water_y + 12 * F_ONE)
		# Late-depth escalation (KIMK r2): band 6+ posts a DEFENDER at the ford
		# mouth — the guaranteed crossing stops being guaranteed-safe. Derived
		# position, no extra rng draw; past-torture by construction.
		if absi(_next_water_y / GATE_SPACING) >= 6:
			# Fairness: _spawn_frogman seeds SUBMERGED — the defender must run
			# the full surfacing telegraph before it can strike (test-pinned);
			# it can never spawn-camp a mid-crossing player with an instant hit.
			_spawn_frogman(water["ford_x"], _next_water_y + 40 * F_ONE)
		# Mud-bank rock (c2 4v FAIRNESS POCKET): one hard-cover pair mid the
		# 40px north mud strip on bands >= 2 — a bullet-blocker for the slowed
		# approach, so mud + band-6+ crossfire isn't a naked walk. _mix-derived
		# x (stream loops stay rng-FREE); band 1 = the golden window, skipped.
		var w_band: int = absi(_next_water_y / GATE_SPACING)
		if w_band >= 2:
			var mrx: int = (80 + _mix(w_band, water["ford_x"] / F_ONE) % 460) * F_ONE
			var mry1: int = _next_water_y - 20 * F_ONE
			var mry2: int = _next_water_y - 10 * F_ONE
			rocks.append({"x": _arena_margin_x(mrx, mry1), "y": mry1})
			rocks.append({"x": _arena_margin_x(mrx + 22 * F_ONE, mry2), "y": mry2})
			# c4 2v NEAR-SHORE TEETH: a hold-and-clear podium ~60px north of the water
			# — 4 low wreck rocks + 2 world-bag scraps placed OFF the ford_x lane so a
			# clean >= HULL_CLEARANCE COMMIT APRON sits aligned to the ford before you
			# step into the current. _mix-jittered, band>=2 -> torture-inert. This is
			# the missing podium; the dual-ford + island + defender already yield the
			# A/B/C route-class reads.
			var teeth_y: int = _next_water_y - 60 * F_ONE
			# Skip the fork decision apron (must stay cover-free) and the calm band.
			if not _in_fork_apron(teeth_y) and not _is_calm_band(teeth_y):
				var tfx: int = water["ford_x"]
				var th: int = _mix(w_band * 40 + 9, water["ford_x"] / F_ONE)
				for ti in 4:
					var tside: int = -1 if ti % 2 == 0 else 1
					var toff: int = 60 + (ti / 2) * 30 + (th >> (ti * 2)) % 16   # 60..105px, off the apron
					var ttx: int = _arena_margin_x(tfx + tside * toff * F_ONE, teeth_y)
					# Never let a clamped tooth encroach the commit apron at ford_x.
					if absi(ttx - tfx) >= HULL_CLEARANCE:
						rocks.append({"x": ttx, "y": teeth_y})
				for tsi in [-78, 78]:
					var tsy: int = teeth_y - 10 * F_ONE
					sandbags.append({"x": _arena_margin_x(tfx + tsi * F_ONE, tsy), "y": tsy, "world": 1})
		_next_water_y -= GATE_SPACING
	# c3 3v REAR TRICKLE (once per camera step, NOT per streamed band): every
	# 700px of camera advance past seg-2+400, birth ONE rusher off the REAR edge
	# (camera_top+380, walks up = symmetric with the top spawns) at an
	# alternating wall — genuine behind-you pressure while advancing, so a
	# mindless hold-up push is no longer free. rng-FREE (wall picked by _mix).
	# Gated so the camera never triggers it inside the ~1260px torture (which
	# stops at ~-1520 > REAR_TRICKLE_START) → both goldens byte-identical.
	# c4 2v: a rear spawn is deferred behind a 1.5s WARN so a behind-you rusher
	# is READABLE in a one-hit game (the view pulses a bottom-edge wedge + scree).
	# The warn timer is CAMERA-DERIVED and unhashed; it stays 0 for the whole
	# torture window (REAR_TRICKLE_START=-2400 > the ~-1520 reach) so goldens hold.
	if mode == "campaign" and _rear_warn_ticks > 0:
		_rear_warn_ticks -= 1
		if _rear_warn_ticks == 0:
			var sy: int = camera_top + 380 * F_ONE
			_spawn_enemy(_rear_warn_x, sy, false)
			events.append({"t": "rear_breach", "x": _rear_warn_x, "y": sy})
	while mode == "campaign" and camera_top < _next_rear_y and _rear_warn_ticks == 0:
		var rslot: int = absi(_next_rear_y / REAR_TRICKLE_SPACING)
		var rear_x: int = WORLD_LEFT if _mix(rslot, _world_seed) & 1 else WORLD_RIGHT
		_rear_warn_x = rear_x
		_rear_warn_ticks = REAR_WARN_TICKS
		events.append({"t": "rear_warn", "x": rear_x, "y": camera_top + 380 * F_ONE})
		_next_rear_y -= REAR_TRICKLE_SPACING


func _stamp_gunship_gate(gy: int, hp_bonus: int, include_approach: bool) -> void:
	## Bridge Gunship gate: no arena bunkers -- the Gunship IS the lock. Shared
	## by the campaign gate-3 stream and Boss Rush (authored-campaign-and-
	## modes), which restamps this exact arena back-to-back with an escalating
	## hp_bonus per boss (via BOSS_RUSH_HP_STEPS) -- DRY, and it means Boss Rush
	## fights in the SAME authored room the campaign gunship does, not a
	## stripped-down stand-in. include_approach skips the MG-nest approach ramp
	## for Boss Rush (a deliberate "no field filler between fights" design
	## choice -- see _setup_boss_rush) while the campaign stream keeps it.
	gates.append({"y": gy, "open": false, "b1": {}, "b2": {},
		"boss": {"alive": true, "hp": _scaled_boss_hp(BOSS_HP + hp_bonus),
			"max_hp": _scaled_boss_hp(BOSS_HP + hp_bonus), "x": SCREEN_CX,
			"dir": 1, "phase_t": 0, "gate_y": gy}})
	# Boss-arena cover (5v): four bags in two mirrored lines turn the
	# strafe half into a COVER fight (mortars ignore cover, so the
	# volley half stays a movement fight). Reuses the whole sandbag
	# grammar; torture never streams gate 3 -> inert.
	# c3 2v BREAKS THE MIRROR: the right pair shifts +40px so the inner
	# gap no longer centers on 296 — the straight-up center lane is gone
	# and the gunship arena gets its own asymmetric identity.
	for bag in GUNSHIP_COVER_BAGS:
		sandbags.append({"x": bag[0] * F_ONE, "y": gy + bag[1] * F_ONE})
	# c3 2v PARTIAL BRIDGE-SPAN WRECK: a 2-slab kind-2 wall straddling
	# center (256/336) denies the center run — commit to a flank. Flank
	# lanes [16,216]/[376,624] >> HULL_CLEARANCE.
	for bwx in [256, 336]:
		rocks.append({"x": bwx * F_ONE, "y": gy + 160 * F_ONE, "kind": 2})
	# c3 2v SHORE-BATTERY STUBS: hard cover at both outer walls (kind-0).
	rocks.append({"x": 60 * F_ONE, "y": gy + 90 * F_ONE, "kind": 0})
	rocks.append({"x": 532 * F_ONE, "y": gy + 90 * F_ONE, "kind": 0})
	# c3 2v ONE-SIDED destructible AMMO CACHE (LEFT only): 2 barrels as a
	# crate + a free ammo pickup behind — an asymmetric reward pulling you
	# off the line to the left (grenade the barrels to reach it).
	barrels.append({"x": 110 * F_ONE, "y": gy + 120 * F_ONE, "armed": true, "fuse_ticks": 0})
	barrels.append({"x": 128 * F_ONE, "y": gy + 120 * F_ONE, "armed": true, "fuse_ticks": 0})
	pickups.append({"x": 120 * F_ONE, "y": gy + 150 * F_ONE, "kind": 0, "cost": 0})
	if not include_approach:
		return
	# c3 2v APPROACH RAMP (gate 3 / Bridge Gunship only — the final gate
	# already ships the calm band + parapets + vents). Density ESCALATES
	# toward the gate so the boss room does not appear with no warning: 1
	# lone MG nest far out (+780, ~-2220 seg 2, south of the ~-1957 torture
	# horizon), then 2 flanking nests closer (+360), each dug in behind a
	# world-bag. A low checkpoint threshold bag row at +340 is the visible
	# marker backing the shipped BRIDGE GUNSHIP banner. Gate-relative, no rng.
	_spawn_mg_nest(SCREEN_CX, gy + 780 * F_ONE)
	sandbags.append({"x": SCREEN_CX, "y": gy + 800 * F_ONE, "world": 1})
	for nsx in [SCREEN_CX - 90 * F_ONE, SCREEN_CX + 90 * F_ONE]:
		_spawn_mg_nest(nsx, gy + 360 * F_ONE)
		sandbags.append({"x": nsx, "y": gy + 380 * F_ONE, "world": 1})
	# Threshold checkpoint row (~1 screen south): a low bag line with a
	# center gap >= HULL_CLEARANCE so the crossing reads as a doorway.
	for thx in [SCREEN_CX - 130 * F_ONE, SCREEN_CX + 130 * F_ONE]:
		sandbags.append({"x": thx, "y": gy + 340 * F_ONE, "world": 1})
	# c3-12 r2 CALM STAGING BEAT (judge TO_TEN): an authored hazard-free
	# pocket immediately south of the threshold — two staging bags far to
	# the sides mark a regroup point with a wide-open center and NO nests/
	# barrels between +420 and +500, so the calm reads as its own beat
	# before the doorway rather than an implied gap.
	for stx in [SCREEN_CX - 190 * F_ONE, SCREEN_CX + 190 * F_ONE]:
		sandbags.append({"x": stx, "y": gy + 460 * F_ONE, "world": 1})


func _stamp_final_gate(gy: int) -> void:
	## The end of the road: the Foundry. Nothing streams past it in campaign;
	## Boss Rush (authored-campaign-and-modes) stamps this same finale to cap
	## its own gauntlet, so both modes end on an identical Colossus arena.
	gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": {}, "final": true})
	# Trench parapets (2v elevation, trimmed of the z-axis): two dug-in
	# world-bag columns guard the Foundry approach — pure arithmetic,
	# exempt from the player buy cap via the "world" flag.
	# parapet = the column x, a non-hashed tag so the colossus phase-rise
	# hook can COLLAPSE the nearest column (c3 2v) without touching any
	# player-authored or other world bag. sandbags feed only x,y -> inert.
	for tcx in [220, 420]:
		for ti2 in 5:
			sandbags.append({"x": tcx * F_ONE, "y": gy + (280 + ti2 * 14) * F_ONE, "world": 1, "parapet": tcx})
	# Foundry phase terrain (5v): three live barrel clusters seed the
	# finale floor — each colossus phase-shift COOKS the nearest one
	# (the arena itself escalates). Fixed coords, no rng; the torture
	# never reaches the final gate -> inert.
	# Left cluster 100 (not 90) clears the c2 ARENA_MARGIN; the paired
	# barrel offsets INWARD (-16) so both authored barrels stay 96..544.
	for fbx in [100, 296, 500]:
		var fby1: int = gy + 140 * F_ONE
		var fby2: int = gy + 148 * F_ONE
		barrels.append({"x": _arena_margin_x(fbx * F_ONE, fby1), "y": fby1,
			"armed": true, "fuse_ticks": 0})
		barrels.append({"x": _arena_margin_x((fbx - 16) * F_ONE, fby2), "y": fby2,
			"armed": true, "fuse_ticks": 0})


func _stamp_stretch_setpieces() -> void:
	## Mid-stretch compositions for the gate being streamed: blockade (2-in-3
	## hash) XOR fire sack (1-in-3 of the remainder) + camp stamp. FORK_GATES
	## skip everything (c2 4v decision apron — the _in_fork_apron contract);
	## the calm band stands down (c2 3v). Called from BOTH the bunker-arena
	## and boss-gate branches: c2 review caught that arena-only placement made
	## fork gates 2/4 the ONLY eligible gates, silently deleting every
	## campaign blockade and camp the day the apron shipped.
	if _gate_counter < 2 or _gate_counter in FORK_GATES \
			or _is_calm_band(_next_gate_y + 460 * F_ONE):
		return
	if _mix(_gate_counter, 31) % 3 != 0:
		# Composition gate holds at exactly 2-in-3 (judge r1): of the stretches
		# that compose, 1-in-3 field the FIRE SACK and the rest the blockade —
		# a replacement slice, not an additive roll, so stretch density never
		# creeps.
		if _mix(_gate_counter, 47) % 3 == 0:
			# FIRE SACK (c2 3v): a COMPOSED encounter — an MG nest dug in
			# behind two world-bags, cover FAVORING the nest against the
			# southern approach. Break LOS, flank the open side (the full
			# remaining corridor, >= HULL_CLEARANCE by construction — test-
			# pinned), or grenade the bags; camping is already punished by
			# the nest's tracking rake. Flank alternates OPPOSITE the
			# hardpoint rock's parity (rock: 150 odd / 490 even). Rows sit at
			# +300/+340 — both clear _in_choke_apron (offsets 700/660 vs the
			# 520-640 + 70-150 apron bands, test-pinned).
			var sack_x: int = (470 if _gate_counter % 2 == 1 else 170) * F_ONE
			_spawn_mg_nest(sack_x, _next_gate_y + 300 * F_ONE)
			sandbags.append({"x": sack_x - 12 * F_ONE, "y": _next_gate_y + 340 * F_ONE, "world": 1})
			sandbags.append({"x": sack_x + 12 * F_ONE, "y": _next_gate_y + 340 * F_ONE, "world": 1})
			# c3 2v DELAYED FLANKER: a mandatory mobile elite on the OPPOSITE wall
			# holds at far cover until the player advances past the nest row
			# (leash trips ~20px north of the nest), then flanks — converting the
			# frontal peek-and-delete gallery into a pincer. No new field (rides
			# the shipped hold_y leash); mirror x = the sack's opposite side.
			# It spawns on the wall OPPOSITE the nest, then (once the leash trips)
			# CROSSES the lane toward the nest-side pocket — an authored crossfire
			# path, not ambient drift. flank_x is the nest-side x it steers to; the
			# leash is set ~10px north of the nest so it trips as the player commits
			# to the peek. flank_x is spawn-immutable, unhashed (gate-3 torture-inert).
			var flank_spawn_x: int = (170 if _gate_counter % 2 == 1 else 470) * F_ONE
			enemies.append({"x": flank_spawn_x, "y": _next_gate_y + 300 * F_ONE, "alive": true,
				"elite": true, "kind": "elite", "hp": 2, "fire_cd": ELITE_FIRE_CD_TICKS / 2,
				"windup": 0, "lunge_ticks": 0, "aim_lx": 0, "aim_ly": 0,
				"hold_y": _next_gate_y + 290 * F_ONE, "flank_x": sack_x})
			return
		# Authored blockade setpiece (5v): a 2-4 bag line mid-stretch the
		# player must grenade, flank, or crush — rides the ENTIRE sandbag
		# grammar for free. Hash-gated + VARIED (KIMK r2), derived gap,
		# occasionally pre-shelled (1-in-3, never back-to-back, KIMK r3).
		var bmix := _mix(_gate_counter, _world_seed)
		var blk_x: int = (140 + bmix % 320) * F_ONE
		var blk_n: int = 2 + (bmix >> 6) % 3
		var shelled: bool = (bmix >> 12) % 3 == 0 \
			and (_mix(_gate_counter - 1, _world_seed) >> 12) % 3 != 0
		var blk_gap: int = (bmix >> 9) % blk_n if shelled else -1
		for bseg2 in blk_n:
			if bseg2 == blk_gap:
				continue   # pre-shelled: the war got here first
			sandbags.append({"x": blk_x + (bseg2 - (blk_n >> 1)) * 24 * F_ONE,
				"y": _next_gate_y + 460 * F_ONE, "world": 1})
		# Stamp sim identity (KIMK r2): halftrack wrecks are REAL cover and
		# camps CARRY a pickup — places are used, not just seen.
		var sp_slot: int = absi(_next_gate_y / (400 * F_ONE))
		var sph2 := _mix(sp_slot * 7, 13)
		if sph2 % 2 == 0:
			var spx2: int = (100 + sph2 % 440) * F_ONE
			var sp_y: int = _next_gate_y + 300 * F_ONE
			var sp_kind: int = (sph2 / 3) % 4
			if sp_kind == 3:
				# Halftrack anchors are INERT-STATIC cover (rock grammar).
				rocks.append({"x": spx2, "y": sp_y})
			elif sp_kind == 1:
				# "Priced" pinned: 10 + 5/segment past 2, capped 30.
				pickups.append({"x": spx2, "y": sp_y, "kind": 0,
					"cost": mini(30, 10 + (absi(_next_gate_y / GATE_SPACING) - 2) * 5)})


func _author_lz() -> void:
	## The landing zone IS the tutorial (no training room, no cards). Three
	## authored props on the player's walking line, in the order the verbs are
	## needed: cover -> the grenade box -> the thing rifles can't touch.
	## Fixed coords, no rng draw -- the streamed world past -500 is unchanged.
	# 1. Seawall: two kind-0 (solid) rock runs with a single center lane
	#    (192px >> HULL_CLEARANCE). Teaches "cover is real, pick a lane" by
	#    standing in the way of the first rushers.
	# Hand-staggered depth + mixed tiers — a placed seawall, not a stamped
	# row. x within +-4 of the original six, y within +-26px of -180 (clear
	# of the -300 grenade crate and the -420 bunker), kind fixed at 0.
	for sr in [[96, 0, 0], [158, -22, 0], [226, 14, 0],
			[414, 18, 0], [478, -16, 0], [546, 6, 0]]:
		rocks.append({"x": sr[0] * F_ONE, "y": -((180 + sr[1]) * F_ONE), "kind": sr[2]})
	# 2. An armored bunker at the lane mouth, spitting infantry every 2s. Rifle
	#    rounds spark off it (armor_block -> the view's existing ricochet), one
	#    grenade seals it for 50 coins. Gate 1 then repeats the lesson as a hard
	#    wall. Corner-origin like every streamed bunker.
	bunkers.append(_make_bunker(SCREEN_CX - BUNKER_W / 2, -(420 * F_ONE)))
	# 3. The conspicuous grenade box, dead center in the lane, free -- 60px PAST
	#    the bunker's north face. Players spawn at GRENADE_AMMO_MAX, so a crate
	#    placed BEFORE the bunker granted mini(MAX, ammo+4) = nothing and taught
	#    nothing. On the far side it refills the grenade the bunker just cost,
	#    which is the actual lesson: grenades are a resource that gets resupplied.
	#    Clear of the streamed bunker row at y=-500 (that one sits at x=120).
	pickups.append({"x": SCREEN_CX, "y": -(480 * F_ONE), "kind": 1, "cost": 0})


func _make_bunker(x: int, y: int) -> Dictionary:
	return {"x": x, "y": y, "alive": true, "spawn_cd": BUNKER_SPAWN_INTERVAL_TICKS}


# --- Endless War (roguelite survival mode) ---

func second_mod() -> int:
	## The wave-15+ STACKED mutator. Every difficulty knob in endless bottoms out
	## early (spawn cadence at wave 12, elite density at 10, roster complete at 7),
	## after which the only delta was +2 bodies against the MAX_ENEMIES wall. From
	## wave 15 a SECOND mutator rides along, so the combination space keeps opening
	## (BLITZ+MARKSMEN reads nothing like FRENZY+BOMBARDMENT).
	## Pure function of wave + world seed: no new hashed field, no rng draw, so the
	## mutator/miniboss/drop streams and both goldens are untouched by construction.
	## Miniboss waves stay single-mutator (the shipped ramp-smoothing rule).
	if mode != "endless" or wave < 15 or wave % 5 == 0:
		return 0
	var m: int = 1 + _mix(wave * 7 + 3, _world_seed) % 8
	if m == wave_mod:
		m = 1 + m % 8   # never double the primary — that would read as no mutator
	return m


func has_mod(m: int) -> bool:
	## True when mutator `m` is live from EITHER slot. Every mutator effect reads
	## through here so wave-15+ stacking needs no per-effect plumbing.
	return wave_mod == m or second_mod() == m


func _wave_armor() -> int:
	## Deep-endless VETERAN ARMOR — the curve's only unbounded term. The spawn
	## cadence floors at 8 ticks, which is exactly FIRE_COOLDOWN_TICKS, so from
	## wave 12 a perfect player broke even with the treadmill forever. One extra
	## bullet per body every 6 waves past 12 pushes time-to-kill past the cadence
	## permanently. Grenades/mines/airstrikes still one-shot, so armor redirects
	## the overflowing War Chest into spending instead of walling the player out.
	if mode != "endless" or wave < 13:
		return 0
	return 1 + (wave - 13) / 6


func _step_waves() -> void:
	# Supply-drop TTL: the contested beat expires instead of pinning rushers
	# forever. Torture-inert (no drop exists before wave 4).
	for di in range(pickups.size() - 1, -1, -1):
		var dpk := pickups[di]
		if dpk.get("drop", 0) > 0:
			dpk["drop"] = dpk["drop"] - 1
			if dpk["drop"] == 0:
				events.append({"t": "drop_gone", "x": dpk["x"], "y": dpk["y"]})
				pickups.remove_at(di)
	if intermission_ticks > 0:
		intermission_ticks -= 1
		if intermission_ticks == 0:
			# Unbought shop stock is packed up when the next wave lands.
			for k in range(pickups.size() - 1, -1, -1):
				if pickups[k].get("cost", 0) > 0:
					pickups.remove_at(k)
			# c4 2v: the shop barricades CRUMBLE as the intermission ends (world:1
			# is the barricade tag; endless sets it nowhere else).
			for sk in range(sandbags.size() - 1, -1, -1):
				if sandbags[sk].get("world", 0) == 1:
					events.append({"t": "sandbag_break", "x": sandbags[sk]["x"], "y": sandbags[sk]["y"]})
					sandbags.remove_at(sk)
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
			if has_mod(1):   # Blitz: spawns pour in twice as fast
				interval = maxi(4, interval / 2)
			wave_spawn_cd = interval
			wave_pending -= 1
			# c3 7v: fold the spawn x toward the rotating pressure side — the
			# full [24,616] range compresses into a ±120 band around the side's
			# center {160,320,480}, so ~200px of clean flank always sits opposite
			# and the safe corner migrates every 3 waves. One draw, folded in
			# place (no new/removed rng), so the wave-1/2 torture is untouched.
			var xpx := rng.range_i(24, 616)
			if pressure_side >= 0:
				xpx = clampi([160, 320, 480][pressure_side] + (xpx - 320) * 120 / 296, 24, 616)
			var x := xpx * F_ONE
			# ROOTED spawns (mg_nest / broadcast) can't use the walk-in-from-the-top
			# y: endless never runs _step_camera, so camera_top is pinned at -VIEW_H
			# forever and camera_top-24 sits ABOVE the player's own _clamp_actor
			# ceiling (camera_top+16). A rooted unit there is permanently
			# unreachable — blind-fire only — yet it counts in _wave_hostiles_cleared
			# and holds the wave open indefinitely. Root them inside the reachable
			# band instead (16..344 below camera_top).
			var rooted_y: int = camera_top + 40 * F_ONE
			var elite_every: int = maxi(2, 4 - wave / 5)
			var is_elite: bool = has_mod(2) or (wave_pending % elite_every) == 0
			# From wave 3, some ranged spawns become grenadiers/snipers so the
			# threat vector varies (Blitz/wave1-2 stay pure rushers/elites).
			# Deliberately reads the PRIMARY slot only: a wave-15+ stacked Blitz
			# must not veto its partner's theme, or the stack would read as a
			# downgrade. Blitz-as-primary keeps its shipped "pure bodies" identity.
			if wave >= 3 and is_elite and wave_mod != 1:
				var roll := rng.range_i(0, 9)
				# c3 2v per-wave COMPOSITION THEMES: remap the SAME draw (no extra rng)
				# onto a themed subset so a marksmen/bombardment wave reads as a unit.
				if has_mod(7):   # MARKSMEN: balanced sniper(1)/ghillie(4)/drone(5)
					roll = [1, 4, 5, 1, 4, 5, 1, 4, 5, 4][roll]   # ranged paint, even weights
				elif has_mod(8):   # BOMBARDMENT: balanced grenadier(0)/sapper(3)
					roll = [0, 3, 0, 3, 0, 3, 0, 3, 0, 3][roll]   # area denial, 50/50
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
					_spawn_mg_nest(x, rooted_y)
				elif roll == 7:
					_spawn_special(x, camera_top - 24 * F_ONE, "technical")
				elif roll == 8 and wave >= 7:
					# Late-debut archetype: deep waves stop being static. Roll 8 fell
					# to plain-elite before, and still does under wave 7 — the rng
					# stream is untouched, only the wave-7+ interpretation changes.
					_spawn_broadcast(x, rooted_y)
				else:
					_spawn_enemy(x, camera_top - 24 * F_ONE, true)
			elif has_mod(7) and wave_pending % 3 == 0:
				# c3-17 r2: ~1/3 of the NON-elite bulk also reads thematic on a themed
				# wave (deterministic from wave_pending, NO rng draw) so the WHOLE wave
				# reads as the theme, not only its elites. Endless wave>=3 -> golden-inert.
				_spawn_special(x, camera_top - 24 * F_ONE, "sniper")
			elif has_mod(8) and wave_pending % 3 == 0:
				_spawn_special(x, camera_top - 24 * F_ONE, "grenadier")
			else:
				_spawn_enemy(x, camera_top - 24 * F_ONE, is_elite)
	elif _wave_hostiles_cleared() and (endless_boss.is_empty() or not endless_boss["alive"]):
		# Wave cleared: open the shop for the intermission (a live miniboss holds it).
		intermission_ticks = WAVE_INTERMISSION_TICKS
		events.append({"t": "wave_clear", "x": 320 * F_ONE, "y": camera_top + 180 * F_ONE})
		# Clean Wave: endless's answer to the campaign's Flawless Gate — no deaths
		# this wave pays a bonus, so cautious and reckless play stop earning alike.
		if deaths_this_wave == 0 and wave > 1:
			# Bonus rides the same creep curve as _supply_cost — literally the
			# same helper now, so price inflation can never erode it into a
			# rounding error (nor outrun it). Value-identical to the old
			# `40 + (wave/3)*10`; that expression IS 25%-of-base per depth step.
			war_chest += _econ_scale(40)
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
		# c4 2v SHOP BARRICADES: from wave 2 on, wall the shop wheel with 4
		# destructible L-shaped world-bag clusters at the shop cluster's corners
		# so the tactical reset is a regroup pocket, not a wide-open dead-end.
		# Tagged world:1 (nothing else sets world in endless) -> trivial cleanup;
		# they crumble at intermission end. Gated wave>=2 (wave 2 never CLEARS in
		# torture -> ENDLESS_GOLDEN inert).
		if wave >= 2:
			for bcx in [150, 530]:
				var barm: int = 24 if bcx < 320 else -24
				for bcy in [shop_y - 30 * F_ONE, shop_y + 40 * F_ONE]:
					for bo in [[0, 0], [0, -24], [barm, 0]]:
						sandbags.append({"x": bcx * F_ONE + bo[0] * F_ONE,
							"y": bcy + bo[1] * F_ONE, "world": 1})
	else:
		# Anti-stall: a passed-by ghillie re-cloaks (bullet-immune) yet stays
		# alive, holding the wave open until the player backtracks into its
		# notice radius — a soft-lock they trip without understanding why. When
		# ONLY cloaked ghillies remain, force the reveal: the wave must always
		# be finishable from where the player stands.
		# A walking rescue pilot is NOT a hostile (same rule as
		# _wave_hostiles_cleared), so it must not veto the reveal — otherwise the
		# guarantee above lapses for the ~85 ticks the pilot takes to walk off.
		var all_cloaked := not enemies.is_empty()
		for e in enemies:
			if e["kind"] == "pilot":
				continue
			if not (e["kind"] == "ghillie" and e.get("submerged", false)):
				all_cloaked = false
				break
		if all_cloaked:
			for e in enemies:
				if e["kind"] != "ghillie":
					continue   # don't surface the pilot we just skipped
				e["submerged"] = false
				e["surface_ticks"] = GHILLIE_REVEAL_TICKS
				events.append({"t": "frogman_surface", "x": e["x"], "y": e["y"]})


func _live_drop() -> bool:
	for pk in pickups:
		if pk.get("drop", 0) > 0:
			return true
	return false


func _wave_hostiles_cleared() -> bool:
	## The wave is beaten when no HOSTILE remains — a walking downed pilot is
	## an optional side objective, never a reason to hold the shop hostage.
	for e in enemies:
		if e["kind"] != "pilot":
			return false
	return true


func _cover_blocked(bx: int, by: int, recycle: bool) -> bool:
	## The 20px dedupe both endless arena drops (the every-3rd-wave L and the
	## wave-5 supply pod) share. `recycle` is the congestion escape hatch: the
	## stale cover in the way is DESTROYED — loudly, through the crater/break
	## events the view already renders — instead of blocking the drop. A
	## player-BOUGHT sandbag is never recycled (you don't bulldoze what someone
	## paid for) and rocks stop being eaten at ARENA_ROCK_FLOOR, so both keep
	## blocking; with 6 slots x 3-8 cells there is always somewhere else.
	var blocked := false
	for si in range(sandbags.size() - 1, -1, -1):
		var sb: Dictionary = sandbags[si]
		if absi(sb["x"] - bx) < 20 * F_ONE and absi(sb["y"] - by) < 20 * F_ONE:
			if recycle and sb.get("player", 0) == 0:
				events.append({"t": "sandbag_break", "x": sb["x"], "y": sb["y"]})
				sandbags.remove_at(si)
			else:
				blocked = true
	for ri in range(rocks.size() - 1, -1, -1):
		var rk: Dictionary = rocks[ri]
		if absi(rk["x"] - bx) < 20 * F_ONE and absi(rk["y"] - by) < 20 * F_ONE:
			if recycle and rocks.size() > ARENA_ROCK_FLOOR:
				events.append({"t": "rock_crater", "x": rk["x"], "y": rk["y"]})
				rocks.remove_at(ri)
			else:
				blocked = true
	return blocked


func _start_wave() -> void:
	wave += 1
	wave_start_tick = tick_count
	wave_pending = WAVE_BASE_ENEMIES + WAVE_ENEMIES_PER_WAVE * (wave - 1)
	wave_spawn_cd = 1
	deaths_this_wave = 0
	# Dynamic arena geometry (c2 4v): the learned kiting loop goes stale on a
	# cadence — every 3rd wave one rock craters out FOREVER (scarring emerges
	# free: removed rocks never respawn) and an authored 3-bag L drops in.
	# _mix-derived BEFORE the rng rolls below, drawing nothing: the courier/
	# mutator/miniboss/drop streams stay byte-identical. Wave 3 never starts
	# inside the endless torture (it wipes during wave 2) -> ENDLESS_GOLDEN
	# holds; rocks/sandbags are already conditional checksum feeds.
	if mode == "endless" and wave >= 3 and wave % ARENA_SHIFT_CADENCE == 0:
		var amix := _mix(wave, _world_seed)
		# c3 7v: rotate the spawn PRESSURE SIDE so the player's camp SPOT dies
		# (the shipped scar/drop rotates COVER, but the spatial kite loop never
		# moved). Reuse amix — zero new rng draws — and never repeat back-to-back.
		var side: int = (amix >> 16) % 3
		if side == pressure_side:
			side = (side + 1) % 3
		pressure_side = side
		events.append({"t": "arena_pressure", "x": [160, 320, 480][side] * F_ONE, "y": camera_top})
		if rocks.size() > ARENA_ROCK_FLOOR:
			var scar_i: int = amix % rocks.size()
			events.append({"t": "rock_crater", "x": rocks[scar_i]["x"], "y": rocks[scar_i]["y"]})
			rocks.remove_at(scar_i)
		# Slot fallthrough (judge r1): if every bag of the picked L dedupes
		# away, walk the table — a DROP beat is never a no-op under congestion.
		# The walk alone was NOT enough (endless audit): by ~wave 30 the fixed
		# 6-slot table is full and the whole walk planted NOTHING, so the
		# advertised "the arena keeps changing" beat died in silence while the
		# rock-crater half kept firing. It now walks the table TWICE — the
		# second lap RECYCLES, destroying the stale non-player cover in the
		# footprint (loudly, via the same crater/break events the view already
		# renders) so a shift wave always plants something.
		var slot_base: int = (amix >> 8) % ARENA_L_SLOTS.size()
		# c4 3v: the every-3rd-wave drop now stamps a whole LAYOUT (barricade belt /
		# corner L / wreck line, _mix-picked) anchored to the SAME slot — footprint
		# stays put but the ARRANGEMENT swaps, so old muscle memory dies with the
		# co-cratered rock. Endless wave>=3 -> past the wave-2 wipe -> golden-inert.
		var layout: Array = ARENA_LAYOUTS[(amix >> 12) % ARENA_LAYOUTS.size()]
		for attempt in ARENA_L_SLOTS.size() * 2:
			var recycle := attempt >= ARENA_L_SLOTS.size()
			var slot: Array = ARENA_L_SLOTS[(slot_base + attempt) % ARENA_L_SLOTS.size()]
			var l_ax: int = slot[0] * F_ONE
			var l_ay: int = slot[1] * F_ONE
			var planted := 0
			var mir: int = -1 if slot[0] >= 320 else 1   # arrange toward arena center
			for bo in layout:
				var l_bx: int = l_ax + (bo[0] * mir) * F_ONE
				var l_by: int = l_ay + bo[1] * F_ONE
				if not _cover_blocked(l_bx, l_by, recycle):
					sandbags.append({"x": l_bx, "y": l_by})
					planted += 1
			if planted > 0:
				events.append({"t": "arena_shift", "x": l_ax, "y": l_ay,
					"forced": 1 if recycle else 0})
				break
	# c4 2v RENEWABLE COVER: a supply pod impacts every 5th wave and carves a 3x3
	# RIM of fresh solid rock (8 outer cells; center left open = an instant micro-
	# fort), so the c2-04 scar rule can no longer strip the arena bare by ~wave 15.
	# _mix-picked slot (zero new rng), same dedupe walk as the L-drop. Endless
	# wave>=5 -> past the wave-2 ENDLESS_GOLDEN wipe -> byte-identical. (The
	# DRIFTING moving-solid cover was cut: it is the L14 solid-vs-occupant
	# impossibility + a new hashed velocity field for a 2-vote item.)
	# The pod had NO fallthrough at all (endless audit): one congested slot and a
	# PROMISED resupply silently evaporated — measured missing from wave 20 on.
	# Same two-lap walk as the L-drop above (polite lap, then recycle), and if
	# even the recycle lap finds nowhere, it says so out loud instead of no-oping.
	if mode == "endless" and wave >= 5 and wave % 5 == 0:
		var pmix := _mix(wave * 3 + 1, _world_seed)
		var pbase: int = (pmix >> 4) % ARENA_L_SLOTS.size()
		var planted_pod := 0
		var pcx: int = ARENA_L_SLOTS[pbase][0] * F_ONE
		var pcy: int = ARENA_L_SLOTS[pbase][1] * F_ONE
		for pattempt in ARENA_L_SLOTS.size() * 2:
			var precycle := pattempt >= ARENA_L_SLOTS.size()
			var pslot: Array = ARENA_L_SLOTS[(pbase + pattempt) % ARENA_L_SLOTS.size()]
			pcx = pslot[0] * F_ONE
			pcy = pslot[1] * F_ONE
			for oy in [-48, 0, 48]:
				for ox in [-48, 0, 48]:
					if ox == 0 and oy == 0:
						continue   # center open = a LEGAL hull pocket (64px, standable)
					if ox == 0 and oy == 48:
						continue   # south DOORWAY so the player can actually enter the fort
					var pbx: int = pcx + ox * F_ONE
					var pby: int = pcy + oy * F_ONE
					if not _cover_blocked(pbx, pby, precycle):
						rocks.append({"x": pbx, "y": pby, "kind": 0})
						planted_pod += 1
			if planted_pod > 0:
				events.append({"t": "supply_pod", "x": pcx, "y": pcy,
					"forced": 1 if precycle else 0})
				break
		if planted_pod == 0:
			# Loud failure beats a quiet one: the view banners this so a lost
			# resupply is never something the player just has to notice missing.
			events.append({"t": "supply_pod_blocked", "x": pcx, "y": pcy})
	if wave >= 3 and rng.range_i(0, 2) == 0:
		_spawn_courier()   # ~1-in-3 waves field a fleeing bounty runner
	# Wave mutators give each wave an identity (and make the shop a counter-
	# pick). None on the first two waves; then roll one. Endless-only.
	# 4 = PAYDAY (double coin, no extra threat) — a go-big economy beat.
	# 5 = NIGHT OPS (vision tightens; view only). 6 = FRENZY (swarm +40% speed).
	# 7 = MARKSMEN (elite picks bias to sniper/ghillie/drone — ranged paint).
	# 8 = BOMBARDMENT (elite picks bias to grenadier/sapper — area denial).
	# No back-to-back repeats: wave_mod still holds last wave's mutator here,
	# so a duplicate roll falls back to plain — twice-in-a-row reads as a bug.
	var prev_mod := wave_mod
	wave_mod = 0 if wave <= 2 else rng.range_i(0, 8)
	if wave_mod != 0 and wave_mod == prev_mod:
		wave_mod = 0
	# Ramp smoothing (8v: wave 5 stacked gunship + mutator + shop lockout into
	# a cliff): miniboss waves refuse the harsh mutators — PAYDAY/NIGHT OPS
	# stay legal for flavor. Roll-then-clamp preserves the rng stream.
	if wave % 5 == 0 and wave_mod in [1, 2, 3, 6, 7, 8]:
		wave_mod = 0
	if has_mod(3):
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
		# phase_t starts NEGATIVE: a 7s fly-in (8v ramp smoothing — the gunship
		# no longer lands on top of the wave_start card). Already-hashed field,
		# zero new state; the arrival emits the endless_boss event instead.
		endless_boss = {"alive": true, "hp": _scaled_boss_hp(BOSS_HP + (wave / 5 - 1) * (BOSS_HP / 2)),
			"max_hp": _scaled_boss_hp(BOSS_HP + (wave / 5 - 1) * (BOSS_HP / 2)),
			"x": SCREEN_CX, "dir": 1, "phase_t": -420, "gate_y": camera_top + 90 * F_ONE}
	if wave >= 4 and not _live_drop() and rng.range_i(0, 2) == 0:
		# Mid-wave optional objective (5-vote panel, trimmed to the drop beat):
		# a parachuted free crate lands down-screen and rushers magnet to it —
		# defend the drop or cede it. The wave >= 4 gate sits BEFORE the rng
		# roll, so waves 1-3 draw nothing new and the endless torture (wipes at
		# wave 2) never perturbs the stream -> ENDLESS_GOLDEN byte-identical.
		# 1-in-3 roll mirrors the courier's (starting value; force-stage 30
		# waves -> expect ~10 drops). "drop" is an immutable-at-spawn marker,
		# unhashed (classified in test_checksum_coverage).
		var drx := _off_center_px(rng.range_i(60, 580)) * F_ONE   # c3 3v: off the center rail
		var dry: int = camera_top + 240 * F_ONE
		# "drop" holds the remaining TTL (600t = 10 s starting value; test: the
		# beat resolves inside a wave) — an eternal crate was a rusher-despawn
		# beacon via the ratchet camera, a sandbag-walled kill funnel, and a
		# strictly-dominant "never collect it" aggro pin (re-review, all three).
		pickups.append({"x": drx, "y": dry, "kind": 1 + rng.range_i(0, 1), "cost": 0, "drop": 600})
		events.append({"t": "supply_drop", "x": drx, "y": dry})
	events.append({"t": "wave_start", "x": SCREEN_CX, "y": camera_top + 40 * F_ONE,
		"mod": wave_mod, "mod2": second_mod()})


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
	## 1..3 by HP thirds of the ACTUAL scaled max, 0 when absent. The boss spawns with
	## _scaled_boss_hp(COLOSSUS_HP) (96 in 2P, 90 hard), so thresholding the unscaled
	## COLOSSUS_HP=60 pinned it in phase 1 for most of a scaled fight and crammed phases
	## 2-3 into the last 40 HP — mis-firing every phase-keyed behavior (mortars, sappers,
	## descent speed, ring migration). Gate on the stored max instead.
	if colossus.is_empty() or not colossus["alive"]:
		return 0
	var hp: int = colossus["hp"]
	var mx: int = colossus.get("max_hp", _scaled_boss_hp(COLOSSUS_HP))
	if hp > (mx * 2) / 3:
		return 1
	if hp > mx / 3:
		return 2
	return 3


func _colossus_ring_radii() -> Array:
	## c4 2v: the safe ANNULUS (the mid ring) migrates OUTWARD each phase rise —
	## both radii grow by COLOSSUS_RING_STEP per phase, so a fixed camp spot that
	## was safe becomes inner-ring danger and the player must kite further out.
	var ph: int = colossus_phase()
	if ph < 1:
		ph = 1
	return [COLOSSUS_RING_INNER + (ph - 1) * COLOSSUS_RING_STEP,
		COLOSSUS_RING_OUTER + (ph - 1) * COLOSSUS_RING_STEP]


func _colossus_ring(dist: int) -> int:
	## 0 inner (melee-crush risk) / 1 mid (the safe collapsible-wreck belt) / 2
	## outer (kite rim, side-lane sweep). dist is raw fixed-point from the boss.
	var r := _colossus_ring_radii()
	if dist <= r[0] * F_ONE:
		return 0
	if dist <= r[1] * F_ONE:
		return 1
	return 2


func _colossus_strike(p: Dictionary) -> void:
	## Every colossus mortar LEADS its target — the same poor-man's velocity the
	## gunship volley uses (_step_boss): sample the player, project the delta since
	## the last sample one full telegraph forward. A 45t warn + 28px kill ring aimed
	## at the tile you're STANDING on can never catch a 2.4px/tick walker (108px of
	## travel vs a 28px ring), so the phase-2 volley, the lane-sweep punisher and the
	## inner-ring punisher were all free auto-dodges for anyone who kept walking —
	## the whole escalation ladder was banners over an inert threat. Standing still
	## gives a zero delta, so a camper is hit exactly where they always were.
	## The sample lives on the player (per-player: 2P leads both) and is SHARED by
	## all three sources — a fresher sample only sharpens the lead.
	var aim_x: int = p["x"]
	var aim_y: int = p["y"]
	if p.has("lead_t"):
		var elapsed: int = maxi(1, tick_count - int(p["lead_t"]))
		aim_x += (p["x"] - int(p["lead_x"])) * STRIKE_TELEGRAPH_TICKS / elapsed
		aim_y += (p["y"] - int(p["lead_y"])) * STRIKE_TELEGRAPH_TICKS / elapsed
	p["lead_x"] = p["x"]
	p["lead_y"] = p["y"]
	p["lead_t"] = tick_count
	# Every colossus mortar source (volley, lane sweep, ring punisher) funnels
	# here, so the blind-fire scatter belongs here too: hiding degrades the
	# fortress's shelling, it never silences it.
	var sc := _blind_scatter(p)
	_add_strike(clampi(aim_x + sc[0], WORLD_LEFT, WORLD_RIGHT), aim_y + sc[1])


func _step_colossus() -> void:
	# Phase terrain: when the phase rises, fuse the nearest live foundry
	# cluster — the floor answers the boss. pv = last seen phase (derived,
	# unhashed-classified; colossus fights are torture-unreachable).
	if not colossus.is_empty() and colossus["alive"]:
		var cph := colossus_phase()
		if cph > colossus.get("pv", 1):
			var best := -1
			var best_d := 0
			for bi in barrels.size():
				if barrels[bi]["armed"]:
					var d := absi(barrels[bi]["x"] - colossus["x"]) + absi(barrels[bi]["y"] - colossus["y"])
					if best < 0 or d < best_d:
						best = bi
						best_d = d
			if best >= 0:
				barrels[best]["fuse_ticks"] = 8
			# c3 2v: the FLOOR also recedes — collapse the trench-parapet column
			# nearest the boss (one per rise; 2 rises + 2 columns => both fall over
			# the fight, so the arena the player learned in phase 1 is gone by the
			# finish). Removal (not a hashed flag) drives it; colossus is torture-
			# unreachable so goldens are untouched. Reuse barrel_blast for the juice.
			var pcol: int = 0
			var pfound := false
			var pbest_d := 0
			for sb in sandbags:
				if sb.has("parapet"):
					var pd := absi(sb["x"] - colossus["x"])
					if not pfound or pd < pbest_d:
						pcol = sb["parapet"]
						pbest_d = pd
						pfound = true
			if pfound:
				var px: int = 0
				var py: int = 0
				var pi := sandbags.size() - 1
				while pi >= 0:
					if sandbags[pi].get("parapet", -1) == pcol:
						px = sandbags[pi]["x"]
						py = sandbags[pi]["y"]
						sandbags.remove_at(pi)
					pi -= 1
				# Dedicated collapse juice (not the barrel boom): a structural column
				# drops — the view answers with dust + debris + a heavier shake.
				events.append({"t": "parapet_collapse", "x": px, "y": py})
			# c4 2v: each phase rise also SWEEPS the mid-arena — 3 telegraphed strikes
			# across the center herd the player toward the two ARENA_MARGIN wall lanes
			# (the ready-made safe alcoves). Reuses _add_strike (45t warn). Colossus is
			# torture-unreachable -> free.
			for swi in 3:
				_add_strike(SCREEN_CX + (swi - 1) * 140 * F_ONE, colossus["y"] + 60 * F_ONE)
		colossus["pv"] = cph
	# Engage when the final gate scrolls into view.
	if colossus.is_empty():
		for g in gates:
			if g.get("final", false) and g["y"] >= camera_top and g["y"] <= camera_top + VIEW_H and not victory:
				colossus = {
					"alive": true, "hp": _scaled_boss_hp(COLOSSUS_HP), "max_hp": _scaled_boss_hp(COLOSSUS_HP),
					"x": SCREEN_CX, "y": g["y"] - 120 * F_ONE,
					"spray_cd": COLOSSUS_SPRAY_CD_TICKS,
					"volley_cd": COLOSSUS_VOLLEY_CD_TICKS,
					"spawn_cd": COLOSSUS_SPAWN_CD_TICKS,
					"core_cd": COLOSSUS_CORE_CYCLE_TICKS, "core_open": 0,
					"sweep_cd": COLOSSUS_SWEEP_CD_TICKS,   # c3 3v: side-lane camp punisher
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
	# The standoff CLOSES with the phases (60 / 30 / 0 px): at phase 1 it parks
	# out of reach and the treads are a threat you opt into, by phase 3 it drives
	# onto your y-line and the crush is only avoided by moving. Lateral tracking
	# rides `descent` for the same reason — still under half PLAYER_SPEED (2.4),
	# so kiting works, but it has to be kiting and not standing.
	var descent: int = COLOSSUS_SPEED * (2 if phase == 3 else 1)
	if colossus["y"] < target["y"] - (3 - phase) * 30 * F_ONE:
		colossus["y"] = colossus["y"] + descent
	var dx: int = target["x"] - colossus["x"]
	colossus["x"] = colossus["x"] + clampi(dx, -descent, descent)

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
	if colossus["spray_cd"] <= 0 and not _concealed(target):   # can't aim into smoke (descent continues)
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
		if colossus["volley_cd"] <= 0:   # AREA fire: _colossus_strike scatters into smoke, it never stops
			colossus["volley_cd"] = COLOSSUS_VOLLEY_CD_TICKS
			_colossus_strike(target)
	if phase == 3:
		colossus["spawn_cd"] = colossus["spawn_cd"] - 1
		if colossus["spawn_cd"] <= 0 and enemies.size() < MAX_ENEMIES:
			colossus["spawn_cd"] = COLOSSUS_SPAWN_CD_TICKS
			_spawn_enemy(colossus["x"], colossus["y"] + 30 * F_ONE, false)

	# c3 3v: the 96px escape corridor (c2-10) is a fair RETREAT, but PARKING in a
	# side lane to cheese the boss was risk-free. A telegraphed lane-sweep mortar
	# (reuses _add_strike: 45t warn > the 24t floor) drops on a player camping
	# either margin lane — dodge IN is still fine, holding is not. sweep_cd
	# rate-limits it (runs every phase, not just phase 3) so it never carpets.
	colossus["sweep_cd"] = colossus.get("sweep_cd", COLOSSUS_SWEEP_CD_TICKS) - 1
	if colossus["sweep_cd"] <= 0 \
			and (target["x"] < ARENA_MARGIN or target["x"] > SCREEN_W_FP - ARENA_MARGIN):
		colossus["sweep_cd"] = COLOSSUS_SWEEP_CD_TICKS
		_colossus_strike(target)

	# c4 2v ROTATING RINGS: the inner DANGER ring GROWS each phase rise (the safe
	# annulus migrates OUTWARD). A player camping inside the inner ring eats a
	# telegraphed strike, forcing them to kite further out as the boss escalates.
	# Tick-phased (no new field); colossus is torture-unreachable so it is free.
	if posmod(tick_count, 90) == 0:
		for rp in players:
			if rp["alive"]:
				var rd := Fixed.length(colossus["x"] - rp["x"], colossus["y"] - rp["y"])
				if _colossus_ring(rd) == 0:   # camping the (growing) inner ring is punished
					_colossus_strike(rp)

	# Treads: contact with the crawler is death (vest rules apply).
	for p in players:
		if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
				and _dist_lte(colossus["x"], colossus["y"], p["x"], p["y"], COLOSSUS_CRUSH_RADIUS):
			_hurt_player(p)

	# Supply drops keep the grenade economy alive during the siege.
	_supply_cd -= 1
	if _supply_cd <= 0:
		_supply_cd = SUPPLY_DROP_INTERVAL_TICKS
		pickups.append({"x": _off_center_px(rng.range_i(60, 580)) * F_ONE, "y": camera_top + rng.range_i(200, 320) * F_ONE, "kind": 1})   # c3 3v: siege drop pulls to a flank


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
			_mint_token(SCREEN_CX, camera_top + 60 * F_ONE)
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


static func boss_mortar_ticks(tier: int) -> Array:
	## The shells this gunship actually fires at `tier` (= wave / 5; 0 in
	## campaign). Const arrays, so no per-tick allocation — _step_one_boss reads
	## it every mortar-act tick and the HP-bar countdown reads it every frame.
	if tier >= 3:
		return BOSS_MORTAR_TICKS_T3
	if tier == 2:
		return BOSS_MORTAR_TICKS_T2
	return BOSS_MORTAR_TICKS


func _step_one_boss(boss: Dictionary) -> void:
	if boss["phase_t"] < 0:
		# Endless fly-in: unhittable and silent until arrival (campaign bosses
		# start at 0 and never enter this branch).
		boss["phase_t"] = boss["phase_t"] + 1
		if boss["phase_t"] == 0:
			events.append({"t": "endless_boss", "x": boss["x"], "y": boss["gate_y"] - BOSS_Y_OFFSET})
		return
	boss["phase_t"] = (boss["phase_t"] + 1) % BOSS_CYCLE_TICKS
	var t: int = boss["phase_t"]
	if t == 0:
		# Act-one opener: the gunship ACQUIRES the nearest player and every
		# spray in the act re-aims at him, so the honest telegraph is a lock on
		# that player (checksum-excluded, like every event). It used to ship the
		# boss's own x as a "sweep lane" the view painted as a 300px column —
		# a lane this boss has never once swept.
		var lock := _nearest_alive_player(boss["x"], boss["gate_y"] - BOSS_Y_OFFSET)
		var lock_ev := {"t": "strafe_lock", "x": boss["x"], "y": boss["gate_y"] - BOSS_Y_OFFSET}
		if not lock.is_empty():
			lock_ev["tx"] = lock["x"]
			lock_ev["ty"] = lock["y"]
		events.append(lock_ev)
	# c4 2v ROTATING POSITIONAL ZONES (gunship): each boss CYCLE, one of the four
	# arena cover spots is INVALIDATED by a telegraphed radial strike (which spot
	# rotates per cycle), so no single firing spot stays safe. Campaign gunship
	# (gate 3) only — endless minibosses have no such bags (no-op) — so gate 3 is
	# torture-inert and ENDLESS_GOLDEN is untouched.
	if mode == "campaign" and t == BOSS_STRAFE_TICKS:
		var spot_i: int = posmod(tick_count / BOSS_CYCLE_TICKS, GUNSHIP_COVER_BAGS.size())
		var bag: Array = GUNSHIP_COVER_BAGS[spot_i]
		_add_strike(bag[0] * F_ONE, boss["gate_y"] + bag[1] * F_ONE)
	# Endless tier escalation (9v: waves 5/10/15/20 differed only by HP).
	# wave is 0 in campaign, so tier 0/1 reproduce today's numbers exactly.
	var tier: int = wave / 5
	# The boss drifts through BOTH halves now (8v: parking during the mortar
	# volley made the whole phase a stand-still pinata).
	boss["x"] = boss["x"] + BOSS_SPEED * boss["dir"]
	if boss["x"] < 60 * F_ONE or boss["x"] > 580 * F_ONE:
		boss["dir"] = -boss["dir"]
		boss["x"] = clampi(boss["x"], 60 * F_ONE, 580 * F_ONE)
	if t < BOSS_STRAFE_TICKS:
		# Strafe run: spray tightens with depth (jitter 40px -> 16px by w20,
		# cadence 12t -> 6t; starting values, staged-tier test asserts both).
		var spray_iv: int = maxi(6, BOSS_SPRAY_INTERVAL_TICKS - 2 * maxi(0, tier - 1))
		if t % spray_iv == 0:
			var jit: int = maxi(16, 40 - 8 * maxi(0, tier - 1))
			var by: int = boss["gate_y"] - BOSS_Y_OFFSET
			var target := _nearest_alive_player(boss["x"], by)
			if not target.is_empty() and not _concealed(target):
				var dx: int = target["x"] - boss["x"] + rng.range_i(-jit, jit) * F_ONE
				var dy: int = target["y"] - by
				var dlen := Fixed.length(dx, dy)
				if dlen > F_ONE:
					events.append({"t": "enemy_shot", "x": boss["x"], "y": by})
					_spawn_enemy_bullet(boss["x"], by, dx, dy, dlen)
		# Arm the mortar-lead sampler as the strafe half closes.
		if t == BOSS_STRAFE_TICKS - 1:
			var s0 := _nearest_alive_player(boss["x"], boss["gate_y"] - BOSS_Y_OFFSET)
			if not s0.is_empty():
				boss["stx"] = s0["x"]
				boss["sty"] = s0["y"]
				boss["st_at"] = t
	else:
		# Mortar volley: strikes LEAD the walker now (8v: constant-speed
		# walking auto-dodged every strike — 28px ring + 45t telegraph can
		# never catch a walker without aiming ahead). Poor-man's velocity:
		# delta since the last sample, projected one telegraph forward.
		# Deeper waves add a 4th (w10+) and 5th (w15+) strike.
		if t in boss_mortar_ticks(tier):
			var by2: int = boss["gate_y"] - BOSS_Y_OFFSET
			var target2 := _nearest_alive_player(boss["x"], by2)
			if not target2.is_empty():   # AREA fire: smoke scatters the volley, it does not stop it
				var aim_x: int = target2["x"]
				var aim_y: int = target2["y"]
				if boss.has("stx"):
					var elapsed: int = maxi(1, t - int(boss["st_at"]))
					aim_x += (target2["x"] - int(boss["stx"])) * STRIKE_TELEGRAPH_TICKS / elapsed
					aim_y += (target2["y"] - int(boss["sty"])) * STRIKE_TELEGRAPH_TICKS / elapsed
				var sc := _blind_scatter(target2)
				_add_strike(clampi(aim_x + sc[0], WORLD_LEFT, WORLD_RIGHT), aim_y + sc[1])
				boss["stx"] = target2["x"]
				boss["sty"] = target2["y"]
				boss["st_at"] = t


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
	if not endless_boss.is_empty() and endless_boss["alive"] and endless_boss["phase_t"] >= 0 \
			and _dist_lte(b["x"], b["y"], endless_boss["x"], endless_boss["gate_y"] - BOSS_Y_OFFSET, BOSS_HIT_RADIUS):
		events.append({"t": "boss_hit", "x": b["x"], "y": b["y"]})
		_damage_boss(endless_boss, 1)
		return true
	return false


func _crack_bridge_span(boss: Dictionary) -> void:
	## Remove the nearest live kind-2 bridge-span slab at the boss's span row and
	## drop a wreck-cover piece one row south — the crack opens a fresh center gap
	## but leaves new cover (net geometry SHIFTS, not just opens). No-op if the
	## arena has no span slab (endless miniboss) -> goldens untouched.
	var span_y: int = boss["gate_y"] + 160 * F_ONE
	var best := -1
	var best_d := 0
	for ri in rocks.size():
		if rocks[ri].get("kind", 0) == 2 and absi(rocks[ri]["y"] - span_y) <= 24 * F_ONE:
			var d := absi(rocks[ri]["x"] - boss["x"])
			if best < 0 or d < best_d:
				best = ri
				best_d = d
	if best < 0:
		return
	var rx: int = rocks[best]["x"]
	events.append({"t": "arena_crack", "x": rx, "y": span_y})
	rocks.remove_at(best)
	# Wreckage drops a row south (kind-0 hard cover) at the cracked slab's x — a
	# different x than the surviving slab, so nothing overlaps and every flank
	# lane stays > HULL_CLEARANCE.
	rocks.append({"x": rx, "y": span_y + 40 * F_ONE, "kind": 0, "burn_ticks": 0})


func _damage_boss(boss: Dictionary, amount: int) -> void:
	var old_hp: int = boss["hp"]
	boss["hp"] = boss["hp"] - amount
	# c4 5v GUNSHIP ARENA CRACK: unlike the colossus, the gunship never mutated
	# its arena mid-fight. On each HP-third CROSSING a cannon volley cracks a
	# bridge-span slab — the learned floor is gone by the finish. Stateless (HP
	# edge, no new boss field), reuses hashed rocks[]; only the campaign gunship
	# has span slabs to crack (endless minibosses no-op), and gate 3 is torture-
	# unreachable, so both goldens stay byte-identical.
	# Thresholds come off the SPAWN-time pool (colossus precedent), not a fresh
	# _scaled_boss_hp(BOSS_HP): that ignored the Boss Rush hp_bonus and the endless
	# depth scaling, and re-read the LIVE player count — so a partner dying mid-fight
	# shifted both crack thresholds under the fight (a 2P gunship at 64/96 HP could
	# skip its first crack entirely). Test callers stage bare boss dicts, hence .get.
	var maxhp: int = boss.get("max_hp", _scaled_boss_hp(BOSS_HP))
	for thr in [maxhp * 2 / 3, maxhp / 3]:
		if old_hp > thr and boss["hp"] <= thr:
			_crack_bridge_span(boss)
	if boss["hp"] <= 0 and boss["alive"]:
		boss["alive"] = false
		# Endless minibosses pay with their depth: HP scales +50%/milestone
		# (x1.6/player) while the flat 200c shrank into a time-tax. Campaign
		# gunships stay flat (wave = 0). Test: coins/sec on the w5 vs w25
		# miniboss within ~25%.
		var bounty: int = BOSS_BOUNTY
		if mode == "endless" and wave >= 5:
			bounty += (wave / 5 - 1) * (BOSS_BOUNTY / 2)
		if has_mod(4):
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
		if not dead:
			for p in players:
				if p["alive"] and not p["roll_iframe"] and p["in_tank"] < 0 \
						and _dist_lte(bx, by, p["x"], p["y"], ENEMY_BULLET_HIT_RADIUS):
					_hurt_player(p)
					dead = true
					break
		# Cover blocks AFTER the player-hit check (re-review: a player standing
		# INSIDE his own sandbag/hulk AABB was immune to every enemy bullet —
		# cover now protects only what stands BEHIND it).
		if not dead and not sandbags.is_empty():
			for sb in sandbags:
				if absi(bx - sb["x"]) <= SANDBAG_HALF_W and absi(by - sb["y"]) <= SANDBAG_HALF_H:
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead:
			# Dead tanks are cover while they smolder (burn_ticks > 0): the
			# bunker two-way rule from an asset the field already produces.
			for hk in tanks:
				if ((hk["alive"] and hk["occupant"] < 0) or (not hk["alive"] and hk["burn_ticks"] > 0)) \
						and absi(bx - hk["x"]) <= HULK_HALF_W and absi(by - hk["y"]) <= HULK_HALF_H:
					events.append({"t": "armor_block", "x": bx, "y": by})
					dead = true
					break
		if not dead and not rocks.is_empty():
			for rk in rocks:
				if not _rk_solid(rk):
					continue   # grass stops no bullet
				if absi(bx - rk["x"]) <= _rk_hw(rk) and absi(by - rk["y"]) <= _rk_hh(rk):
					events.append({"t": "armor_block", "x": bx, "y": by})
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

	# c3 3v CHOKE-CAMP breach: camping a seg-2+ choke for REAR_CAMP_TICKS (the
	# earlier, softer, rear-only nudge before the 480t front Observer) spawns a
	# rusher from the rear wall behind the lead player. Single-shot by equality
	# (advancing resets stall_ticks -> re-arms); stall_ticks is already hashed,
	# so no new field. seg>=2 keeps the torture (which never stalls 300t) inert.
	if mode == "campaign" and stall_ticks == REAR_CAMP_TICKS:
		var lead_y := 0
		var found_lead := false
		for p in players:
			if p["alive"] and (not found_lead or p["y"] < lead_y):
				lead_y = p["y"]
				found_lead = true
		if found_lead and absi(lead_y) >= 2 * GATE_SPACING:
			var cb := _choke_bounds(lead_y)
			if cb[0] != WORLD_LEFT or cb[1] != WORLD_RIGHT:   # the lead player is in a choke
				# camera_top is always negative, so this bare `/ F_ONE` truncates toward 0
				# where Fixed.to_int would floor — 1 apart. It is a HASH SEED, not a
				# coordinate: both are "correct", truncate is what the goldens recorded.
				# See the "`x / ONE` vs `to_int(x)`" contract in fixed.gd before changing it.
				var camp_x: int = WORLD_LEFT if _mix(absi(camera_top / F_ONE), _world_seed) & 1 else WORLD_RIGHT
				var camp_y: int = camera_top + 380 * F_ONE
				_spawn_enemy(camp_x, camp_y, false)
				events.append({"t": "rear_breach", "x": camp_x, "y": camp_y})

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
				if not target.is_empty():   # AREA fire: smoke scatters the barrage, it does not stop it
					var sc := _blind_scatter(target)
					_add_strike(target["x"] + sc[0], target["y"] + sc[1], true)
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
	# Half, not zero. Killing the spotter used to fully re-arm the 480-tick timer,
	# so the game's only anti-camp valve paid the camper (2x elite coin + 500 score)
	# AND bought back the whole stall window — parking at a closed gate to farm the
	# bunker's rusher drip and pop a spotter every 8s was strictly profitable.
	# Now a player who still hasn't moved sees the next one twice as fast, while a
	# player who kills it and advances never notices the difference.
	stall_ticks = OBSERVER_STALL_TICKS / 2


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
	h = feed.call(tokens, h)
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
	if vest_buys > 0:
		h = feed.call(vest_buys, h)   # conditional: 0 buys = untouched stream (torture never buys)
	for p in players:
		if p["flush_cd"] > 0:
			h = feed.call(p["flush_cd"], h)   # c3 2v: conditional — flush_cd is 0 unless camping grass near a threat (never in either torture window)
	if not rocks.is_empty():
		h = feed.call(rocks.size(), h)
		for rk in rocks:
			h = feed.call(rk["x"], h)
			h = feed.call(rk["y"], h)
	if not sandbags.is_empty():
		# Conditional feed (assist/hard/colossus precedent): an empty array
		# leaves the hash stream untouched, so goldens hold while unbought —
		# the mines[] unconditional-feed lesson, learned.
		h = feed.call(sandbags.size(), h)
		for sb in sandbags:
			h = feed.call(sb["x"], h)
			h = feed.call(sb["y"], h)
	if not vents.is_empty():
		# Conditional feed (sandbags precedent): vents exist only past seg 4 —
		# neither torture window ever streams one, so goldens hold.
		h = feed.call(vents.size(), h)
		for vt in vents:
			h = feed.call(vt["x"], h)
			h = feed.call(vt["y"], h)
	if not colossus.is_empty():
		for v in [colossus["hp"], colossus["x"], colossus["y"], int(colossus["alive"]),
				colossus.get("core_open", 0), colossus.get("core_cd", 0)]:
			h = feed.call(v, h)
	for s in [rng._s0, rng._s1, rng._s2, rng._s3]:
		h = feed.call(s, h)
	for p in players:
		for v in [p["x"], p["y"], int(p["alive"]), p["deaths"], p["mg_ammo"], p["grenade_ammo"],
				p["fire_cd"], p["broke_timer"], p["roll_ticks"], p["roll_cd"], p["roll_buf"],
				int(p["roll_prev"]), p["grenade_buf"], int(p["fire_prev"]),
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
		if g.get("breach_cd", 0) > 0:
			# c2 2v: conditional feed — a live staggered breach countdown enters
			# the hash; 0 (the default, and every non-flanked gate) leaves the
			# stream untouched (sandbags precedent).
			h = feed.call(g["breach_cd"], h)
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
