extends Node2D
## Sprite view over the deterministic sim. All floats live here, never in src/sim.
## Art: Kenney CC0 (see src/view/art.gd). The sim remains pure state; this file
## only reads it.
##
## Controls (P3):
##   P1 — WASD move, mouse or arrow keys aim, Space/LMB fire, Shift/RMB
##        grenade, C roll, F interact (board/exit tank), E revive,
##        Q (hold) spend-wheel
##   Gamepad — LS move, RS aim, RT/R1 fire, L1 grenade, B roll, X interact,
##        Y revive, BACK (hold) spend-wheel
##   F2 toggles local 2P · F3 toggles Endless War · R restarts.

const PX := 1.0 / Fixed.ONE
const SCREEN_W := 640.0
const SCREEN_H := 360.0
const SCREEN_CENTER := Vector2(320, 180)
# c1-15: the top-center boss/mini HP-bar dock line lives in HudIcons (HudIcons.BOSS_BAR_TOP) as the
# ONE shared HUD-layout boundary — main imports it directly (below, in the bar renderers) so the
# corner panel's shop-strip safe height and the bar y can never desync. No local copy here.
# Battlefield-litter prop pool, scattered deterministically in _draw_terrain().
# Litter biases with the run: early sectors are an intact outpost (tents/crates/
# rocks), late sectors a wrecked front (hulks/wire/towers/fallen). Picked by _sector_march.
const _LITTER_EARLY := ["barrel", "crate_stack", "tent", "ammobox", "barrier",
	"tank_trap", "flak_gun", "hedge", "fern2", "flag_marker", "mg_tripod"]
const _LITTER_MID_A := [   # tree_dead* removed: log-shaped things are only ever REAL cover now
	"barrel", "tank_trap", "hedge", "flag_marker"]   # stump-field band: the jungle thins
const _LITTER_MID_B := ["crater", "crater_field", "barbedwire", "wreck", "corpse_soldier1",
	"barricade", "ammobox"]                 # marsh/ruins band: the war shows
# Authored setpiece stamps (5v: the corridor between gates is uniform noise —
# these are nameable PLACES): picked ~1-in-2 per 400px band by hash; plain
# scatter is suppressed inside a stamp's radius so stamps read as places,
# not denser noise. [tex, dx, dy, scale] per part.
# Ridge visibility bounds (KIMK round-3: a one-sided alpha pin fails the
# other way — invisible terrain is its own misread). Floor AND ceiling,
# consumed by the draw and asserted in test.
const RIDGE_A_LO := 0.22
const RIDGE_A_HI := 0.35
const _SETPIECES := [
	[["wreck_apc", -30, 0, 1.0], ["wreck_technical", 25, 18, 0.9], ["crater", 5, -20, 1.0]],   # dead convoy
	[["tent", -28, -10, 1.0], ["tent", 24, 6, 0.9], ["ammobox", -2, 20, 1.0], ["barrier", 30, -22, 0.9]],   # abandoned camp
	[["crater", 0, -26, 1.0], ["crater", -26, 8, 0.9], ["crater", 26, 8, 0.9], ["crater_field", 0, 30, 1.0]],   # shelled diamond
	[["wreck_halftrack", 0, 0, 1.0], ["barbedwire", -30, 22, 0.9], ["barrel", 28, -16, 1.0]],   # downed halftrack
]
const _LITTER_FOUNDRY := ["crater_field", "crater_water", "wreck_halftrack", "wreck_apc",
	"crater", "barbedwire", "corpse_soldier2", "wreck_light_tank"]   # foundry band: slagged, cratered, dead
const _LITTER_LATE := ["wreck", "watchtower", "barbedwire", "wreck_apc", "wreck_technical", "wreck_light_tank",
	"corpse_soldier1", "corpse_soldier2", "crater",
	"trench", "barricade", "radio_tower", "wreck_halftrack", "crater_field", "crater_water",
	"dropped_shield", "fallen_merc"]
# Base-rusher sprite variants indexed by the sim's cosmetic per-enemy "skin"
# (spawn-derived, checksum-excluded) so a rush reads as varied troops.
# sol-08: the base-rusher rotation is now the RED-team pack sprites (all cel — single authorship, no
# cel/legacy art strobe, per the SIMSAFE mixed-list warning). Authored friend/foe color + per-skin weapon variety.
const _RUSHER_SKINS := ["enemy_smg", "enemy_assault", "enemy_shotgun", "enemy_lmg"]
# Dead hulks that slump beside a parked tank (convoy-graveyard set-dressing).
const _TANK_HULKS := ["wreck_apc", "wreck_technical", "wreck_light_tank"]

var sim: SimWorld
var _recorder: Replay             # captures this run's inputs → user://last_run.replay (view-only)
var _watching := false            # Watch Last Run playback mode
var _watch_replay: Replay = null
var _watch_frame := 0
var _replay_saved := false        # save the replay once per run, at the debrief
var _replay_task := -1            # WorkerThreadPool id of the async replay write
var _two_players := false
var _endless := false
var _daily := false              # seed-of-the-day challenge run
var _seed_override := -1         # CHALLENGE SEED: one-shot forced seed (-1 = none)
# Feel stack (view-only; the sim never sees any of this).
var _trauma := 0.0
var _hitstop_frames := 0
var _flash_alpha := 0.0
var _fx: Array[Dictionary] = []   # explosion/smoke animations from sim events
var _trench_prev: Array[bool] = []   # c3: per-player last-tick in-trench, for the drop-in cue (view-only)
var _rear_wedge_t := 0.0              # c4: rear-warn bottom-edge wedge timer (seconds)
var _rear_wedge_x := 320.0            # c4: screen-x of the pending rear spawn
var _pending_blasts: Array[Dictionary] = []   # scheduled boss-death secondary detonations
var _scorch: Array[Dictionary] = []   # lingering ground scorch decals (drawn under units)
var _corpses: Array[Dictionary] = []  # fallen enemies, fading (drawn under units)
var _hulks: Array[Dictionary] = []    # dead-tank wrecks, persistent (view-only pool)
var _forks: Array = []   # route-fork bands (from the stream-time route_fork event)
var _vo_last: Dictionary = {}     # per-line wall throttle (frames) — radio never spams
var _vo_plea_at := -1             # frame to fire the pilot's queued plea
var _last_stand_prev := false     # edge-detect for the Last Stand VO
var _colossus_ping_frame := 0     # armor-plink throttle
var _tank_alive_prev := {}            # per-tank-index prev alive flag (edge-detects the death)
var _cursor_styled := false           # custom OS cursor active (menus/debrief only)
var _cursor_crosshair: ImageTexture   # boot-baked gameplay crosshair (from ui_reticle)
var _cursor_menu: ImageTexture        # boot-baked scaled menu pointer (from ui_cursor)
var _cursor_s := 1                     # window integer scale the cursors were baked at
var _sfx := Sfx.new()
var _recoil: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # per-player gun kick
var _hit_flinch: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # per-player body kick when hit
var _kick := Vector2.ZERO         # directional screen nudge from firing
var _kill_streak := 0             # decaying combo counter for kill-blip pitch
var _last_kill_frame := -100
var _rumble := 0.0                # pending gamepad vibration this frame
var _rumble_on := true            # accessibility: gamepad vibration on/off
var _swap_sticks: Array[bool] = [false, false]   # c1-18: PER-PLAYER left-handed pad option — swap the MOVE (left) and AIM (right) analog sticks. [0]=P1, [1]=P2, independent like the per-player pad button layouts, so a left-handed P2 swaps without touching P1. The sticks aren't per-button rebindable, so this is the accessible way to reassign them for left-handed / adaptive-controller players. Applied view-side in _gather_inputs.
var _fullscreen := false          # F11 / Alt+Enter window mode, persisted in [settings]
var _win_scale := 2               # c1-19: the player's PREFERRED windowed integer scale (Nx of the 640x360 canvas), persisted in [settings]. This is the PREFERENCE, sane-capped to [1, WIN_SCALE_MAX] but NEVER clamped down to a monitor — so moving to a smaller display and back restores it. The window is sized to _effective_scale() (this preference clamped to what the CURRENT display fits); only an explicit user pick or RESET changes this value.
const WIN_SCALE_MAX := 8          # c1-19: sanity ceiling on the STORED preference (8x = 5120x2880, past any real monitor) so a garbage save can't persist an absurd scale; the live per-monitor fit clamps below this for actual sizing.
var _deco_reserve := Vector2i(0, 40)   # c1-19: window chrome (title bar + borders) kept OFF-canvas when computing the largest scale that fits. The AUTHORITATIVE value is the live windowed decoration delta (window_get_size_with_decorations - window_get_size), written ONLY from _settle_window (deferred, a frame after a mode change) so the transient zero the OS reports right after leaving fullscreen can't clobber it; a settled borderless window's stable zero is valid. The initial 40 is a conservative fallback until the first windowed measurement (e.g. booting straight into fullscreen) — it only shrinks the temporary EFFECTIVE fit, never the stored preference, and is re-evaluated once measured.
var _last_screen := -1                 # c1-19: monitor index the window is on, polled so a drag to another display (which fires no resize signal) still re-fits/recenters the window to what the new screen holds.
var _last_usable := Rect2i()           # c1-19: last work-area seen, polled alongside _last_screen so a SAME-monitor resolution or taskbar change (no screen-index change) also re-fits the window.
var _settle_last_deco := Vector2i(-1, -1)  # c1-19: the live decoration delta _settle_window saw on the PREVIOUS deferred frame — the settle finishes only once it reads the SAME value twice running (stable), so a slow window manager's one-frame transient can't end the settle on a bad chrome reserve.
var _settle_tries := 0                  # c1-19: retry counter for _settle_window — the decorated size can take more than one deferred frame to settle under a slow window manager (X11 / Wayland especially), so re-run a bounded few frames until the client size matches the target instead of assuming one frame is enough.
var _settle_zero_streak := 0            # c1-19: how many CONSECUTIVE deferred settle frames have read a ZERO decoration delta. A zero reserve is only ACCEPTED once this reaches SETTLE_ZERO_FRAMES — so the multi-frame zero the OS reports while the title bar re-attaches after leaving fullscreen can't clobber a known-good reserve before real chrome reappears; the last nonzero reserve is retained until the transition is definitively complete.
const SETTLE_ZERO_FRAMES := 6           # c1-19: a decoration delta must read ZERO this many consecutive settle frames before it's trusted as a genuine borderless / client-side-decorated window. Above any realistic post-fullscreen title-bar re-attach latency (1-3 frames), so a transient zero streak can never reach it and drop a valid chrome reserve.
var _prog_resize := false               # c1-19: EXPLICIT programmatic-transition guard. True while WE are changing the window mode/size (fullscreen toggle, scale apply, monitor re-fit) and until that settle completes. While set, _on_window_resized ignores the size-change notifications the OS emits during the transition — so a compositor-generated intermediate client size that happens to fit within/equal the usable area can NOT be mistaken for a user drag and overwrite the saved scale. Cleared only when the settle chain finishes (transition definitively done). A genuine user drag arrives with this false and is honored.
var _resize_save_t := 0.0               # c1-19: debounce timer for persisting a free-resize scale change. A drag can cross several integer-scale boundaries in quick succession; rather than rewrite the settings file on every crossing, _on_window_resized updates the live scale immediately (so the label tracks) but only ARMS this countdown — the actual _save_settings fires once it elapses after the last size change (coalescing a whole drag into one write). Flushed early on window-close so a drag-then-quit can't lose the choice.
const RESIZE_SAVE_DELAY := 0.35         # c1-19: seconds of size quiescence before a free-resize scale change is persisted — long enough to coalesce a continuous drag into a single write, short enough to land before a normal close.
var _settle_active := false            # c1-19: is a settle chain running? Driven from _process (ONE sample per RENDERED frame — guaranteed distinct frames), NOT recursive call_deferred (whose re-queued calls can flush several times in a SINGLE idle, collapsing the multi-frame stability gate). While true, _process advances one _settle_window sample each frame until the mode/client/decorated sizes stabilize; a generation bump cancels the current chain.
var _settle_gen := 0                    # c1-19: monotonic generation tag for the settle chain. Each new windowed mode/scale change bumps it and stamps its deferred _settle_window calls; a callback whose stamp != the current gen is STALE (a newer choice superseded it) and drops out — so rapid mode/scale toggling can't have an old settle chain share counters with, or recenter/resize after, the newest choice.
const SETTLE_MAX_TRIES := 16            # c1-19: hard ceiling on settle retries — high enough that the SETTLE_ZERO_FRAMES streak (and a slow compositor's late title-bar attach) has room to complete, low enough that a genuinely stuck window manager can't loop the deferred settle forever (~0.27s at 60Hz worst case, only on a mode change).
var no_autopause := false         # set by dev harnesses whose window never holds focus
var _heat: Array[float] = [0.0, 0.0]   # per-player MG barrel heat (sustained-fire feel)
var _player_face: Array[float] = [PI / 2, PI / 2]   # smoothed body facing: keyboard 8-way aim snapped in 45° pops (enemies already lerp via _enemy_face)
var _boss_flash := 0.0           # white-hot flash on the boss/colossus body when shot
var _down_anim: Array[float] = [0.0, 0.0]   # per-player death-knockdown tween (0→1)
var _motion := 1.0               # accessibility: 0 = reduce shake/flash/vignette
var colorblind := false          # deuteran-safe: remap 'affordable/safe' green → cyan
var _assist := false             # accessibility: permanent 2-hit vest (flagged on the leaderboard)
var _binds: Dictionary = {}      # c1-18: keyboard rebinds (action -> physical keycode, 0 == UNBOUND); filled from BIND_DEFAULTS + [binds] in _load_bests
var _pad_binds: Array[Dictionary] = [{}, {}]  # c1-18: PER-PLAYER gamepad button rebinds (action -> JOY_BUTTON_*, -1 == UNBOUND). [0]=P1 (device 0, [padbinds]), [1]=P2 (device 1, [padbinds2]) — two INDEPENDENT layouts so a left-handed P2 can remap without disturbing P1
var _menu_binds: Dictionary = {} # c1-18: rebindable MENU-navigation keys (action -> physical keycode); filled from MENU_BIND_DEFAULTS + [menubinds]. Read ADDITIVELY over the immutable W/S/arrows/Enter/Esc fallback the menu always honors
var _hard := false               # New Game+ HARD: tighter campaign spawn curve
var _last_gate_tick := 0         # view-side gate-split timer (speedrun read)
var _best_gate_split := 0        # fastest gate split this run
var _punch := 0.0                # camera zoom-punch on heavy impacts
var _fade := 0.0                 # black fade-in on boot-into-combat
var _duck := 0.0                 # music-duck under heavy hits
var _concussion := 0.0           # low-pass 'ears ringing' after a near-death
var _blast_warp := 0.0           # brief heat-shock screen warp on marquee detonations
var _cinematic := 0.0            # letterbox envelope for boss intro / victory beats
var _boss_bar_slots := 0         # top-center bars drawn this frame (banner ducks below them)
var _result_t := 0.0             # debrief/victory card entrance ease (0→1)
var _enemy_face := {}            # per-slot smoothed facing (view-only; kills the 180° snap)
var _enemy_hp_prev := {}         # a2-11: per-slot prev hp — edge-detects a non-lethal hit
var _enemy_flash := {}           # a2-11: per-slot decaying white hit-flash
var _enemy_pos_prev := {}        # per-slot prev sim pos — gates the run-bob to actual movement
var _enemy_slot_kind := {}       # per-slot kind stamp — the sim compacts with remove_at, so a
                                 # slot can be inherited by a different enemy; a kind mismatch
                                 # drops the stale face/prev-pos instead of lerping out of them
var _spawn_yelled := {}          # per-slot kind stamp of last spawn shout ("" = not yet)
var _spawn_yell_cd := 0          # ticks before another first-sight shout can fire
var _esort_order: Array[int] = []   # reused y-sort buffers (zero per-frame alloc)
var _esort_ys: Array[int] = []
var _screen_fx_mat: ShaderMaterial   # full-screen concussion warp (view-only)
var _screen_fx_rect: ColorRect       # hidden unless concussed → normal play untouched
var _scan_mat: ShaderMaterial        # CRT scanline quad material; strength pulses on hitstop
var _grade_mat: ShaderMaterial       # a4-01 master color grade (always on; breather in shop)
var _grade_breather := 0.0           # a4-01/a4-15: eased shop-intermission calm grade (0..1)
var _water_shader: Shader            # animated river water (view-only, see water.gdshader)
var _water_rects: Array[ColorRect] = []   # pooled per-band water quads (z=-1, under units)
var _water_pushed: Array = []             # per pool rect: [band world-y, wsoot, splash_t] last sent to the shader
var _bg_root: Node2D                 # opaque grass/dirt base (z=-2, under the water quads)
var _bg_cam := -1                    # last (camera_top, march) painted onto _bg_root —
var _bg_march := -1.0                # its ~90-rect rebuild is a pure function of these
var _litter_cam_snap := 1 << 60      # camera_top when the march last stepped — litter rows south
var _litter_march_prev := 0.0        # of it keep the pre-step pool (no on-screen prop identity swap)
var _glow_root: Node2D               # additive blend pass: light-emitting FX brighten, never tint
var _music_hold := 0             # held-breath drum dropout before a big beat
var _whiz_frame := -100          # near-miss whiz throttle
var _dodge_frame := -100         # perfect-dodge callout throttle
var _tension := 0.0              # last-stand dread level (desat/heartbeat)
var _heart_frame := -100         # heartbeat pacing
var _hitmarker: Array[float] = [0.0, 0.0]   # reticle confirm pop on a landed hit (per-player)
var _dust_prev: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]        # per-player prev world pos (movement dust)
var _tank_dust_prev: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]   # per-driver prev tank world pos (movement dust)
var _tank_hull := {}             # per-tank-index eased hull heading (view-only; 0.0 = baked "up")
var _tank_prev := {}             # per-tank-index prev world pos, feeds the hull heading
var _tank_turret := {}           # per-tank-index eased turret heading (kills the 8-way 45° snap)
var _water_prev: Array[bool] = [false, false]   # per-player prev in-water state (edge-triggers entry droplets)
var _mud_prev: Array[bool] = [false, false]     # per-player prev in-mud state (edge-triggers the mud splash)
var _mud_told := false                          # once-per-run MUD teach banner latch
var _enemy_water_prev: Array[bool] = []         # per-enemy-slot prev in-water state (index-keyed; ponytail: a
                                                 # death mid-array can misalign one slot for a frame — cosmetic only)
var _hit_dir := Vector2.ZERO     # screen-edge damage wedge direction
var _hit_dir_t := 0.0
var _hit_dir_player := 0         # which player's body the wedge emanates from
var _downed_by := ""             # label of the last lethal source, shown in the K.I.A. debrief
var _record_fired := false       # NEW RECORD banner once per run
var _deep_fired := false         # DEEPEST WAVE banner once per run
var _boss_ghost := {}            # view-side prev-HP fraction per boss, for the draining chip
var _boss_hpmax := {}            # view-side max HP seen per boss key: the endless gunship spawns above BOSS_HP (sim_world.gd:1581), which pegged its bar at 100% for half the fight
var _endless_boss_key := ""      # last endless miniboss's dict key, so its hpmax/ghost entries get pruned on death (gate_y is unique per spawn — they'd accrete forever)
var _seen := {}                  # persisted first-time-hint flags
var _current_seed := 0           # this run's RNG seed (shown on pause)
var _hint_text := ""             # current just-in-time onboarding cue
var _hint_t := 0.0
var _hint_queue: Array[String] = []      # pending first-time hints, drained one at a time
var _run_kills := 0              # this-run tally for the debrief card
var _run_kind_kills := {}        # enemy kind → this-run kills, feeds the debrief top-prey row
var _run_rescues := 0            # pilot ransoms this run — the signature mechanic earns a tally line
var _run_best_streak := 0
var _down_frames := 0            # sustained all-players-down → debrief
var _debrief := false
var _damage_vignette := 0.0       # red screen-edge pulse on hits/deaths
var _water_splash := {"x": 0, "y": 0, "t": 0.0}   # wet-blast ring pushed to the water shader
var _banners: Array[Dictionary] = []          # FIFO of center-screen splashes {text, t, col}
var _shop_lock_told := false     # SHOP LOCKED banner latch — once per boss, not per frame
var _no_target_cd := 0.0         # NO TARGET receipt cooldown (endless dead-interact cue)
var _no_target_prev: Array[bool] = [false, false]   # per-player interact edge, view-side
var _dry_frame := -100            # rate-limits the dry-FIRE (MG) click
var _deflect_frame := -100        # rate-limits the riot-shield deflect ping
var _nest_ping_frame := -100      # rate-limits the MG-nest crack ping (own clock — sharing
                                  # _deflect_frame let each mute the other within 10 frames)
var _pilot_alarm_frame := -999    # one-shot for the pilot's ESCAPING warning tone
var _pilot_deny_frame := -100     # rate-limits the punch-out-grace deny chirp
var _dry_grenade_frame := -100    # separate clock for the dry-THROW (grenade) click
var _grenade_dry: Array[int] = [0, 0]   # HUD grenade-pip red flash on empty throw (per-player)
var _fire_swallow := false       # eat SPACE/LMB held over from a menu click / debrief redeploy —
                                 # clicking RESUME must not spend MG ammo on the first resumed ticks
var _smoke_prev: Array[int] = [0, 0]    # last tick's smoke_ticks (per-player) — expiry-edge cue
var _tech_lunge_prev := {}              # per-slot technical lunge_ticks — charge-end skid cue
var _seen_bosses := {}            # gate_y → true once the gunship intro played
var _seen_kinds := {}             # enemy kind → true once its first-encounter banner fired
# First-sighting teaching cards for the lethal archetypes that debut deep (sector 4+)
# in a one-hit game — named + told how to answer, once per run. View-only.
const _KIND_TEACH := {
	"sniper": "LASER SNIPER — BREAK THE LINE",
	"ghillie": "GHILLIE SNIPER — FLUSH IT OUT",
	"grenadier": "GRENADIER — MOVE OFF YOUR GROUND",
	"shield": "RIOT SHIELD — FLANK OR GRENADE",
	"frogman": "FROGMAN — KILL IT ON THE SURFACE",
	"sapper": "SAPPER — MIND THE MINE TRAIL",
	"mg_nest": "MG NEST — BREAK ITS LINE OR FLANK",
	# The counterplay is counterintuitive (it outruns a straight sprint at
	# 3px/t vs the player's 2.4) — the card must teach the sidestep.
	"technical": "TECHNICAL — SIDESTEP ITS CHARGE LINE, ONE SHOT DROPS IT",
	"courier": "SUPPLY COURIER — GUN IT DOWN BEFORE IT ESCAPES (4x BOUNTY)",
	"broadcast": "BROADCAST TOWER — KILL THE MAST, BREAK THE RALLY",
}
# Persistent bests — the roguelite carrot.
const SAVE_PATH := "user://ikari_best.cfg"
const SAVE_TMP := "user://ikari_best.cfg.tmp"
const SAVE_BAK := "user://ikari_best.cfg.bak"
var best_score := 0
var best_wave := 0
var best_dist := 0
var _life_runs := 0              # career totals (title screen), separate from the top-8 hall
var _life_kills := 0
var _life_wins := 0
var hall: Array[Dictionary] = []   # top-N run history for the Hall of Fame
var hall_latest: Dictionary = {}   # the run just banked this session — the Hall highlights it (session-only ref)
var _hall_seq := 0                  # monotonic run id ("hid") so the Hall identifies the EXACT banked run — value-equal twins (same score/sector) are common and must not be confused
var _best_dirty := false
var _seen_dirty := false          # first-time hints ratchet in memory, flushed with bests
var _prev_colossus_phase := 0     # phase-change escalation banners
# War Chest spend-wheel (hold Q / pad BACK, flick a direction, release to buy).
var _wheel: Array[Dictionary] = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]
var _wheel_aim := [Vector2.ZERO, Vector2.ZERO]   # aim latched while the wheel is open (sector flicks must not whip the sim aim)
const WHEEL_ITEMS := [
	{"kind": 0, "icon": "icon_ammo", "cost": SimWorld.SHOP_AMMO_COST, "label": "AMMO +30"},
	{"kind": 1, "icon": "icon_grenade", "cost": SimWorld.SHOP_GRENADE_COST, "label": "GRENADES +4"},
	{"kind": 2, "icon": "icon_vest", "cost": SimWorld.SHOP_VEST_COST, "label": "FLAK VEST"},
	{"kind": 3, "icon": "icon_airstrike", "cost": SimWorld.SHOP_AIRSTRIKE_COST, "label": "AIRSTRIKE"},
	{"kind": 4, "icon": "wall_sandbag", "cost": SimWorld.SHOP_SANDBAG_COST, "label": "SANDBAGS"},
	{"kind": 5, "icon": "icon_medal", "cost": 0, "label": "SUPPLY CALL"},   # Commendation spend — costs a token, never coins
]
const BUY_FLOAT := ["+30 AMMO", "+4 GRENADES", "FLAK VEST ON", "AIRSTRIKE INBOUND", "SANDBAGS UP"]
# 8-way wheel: compass = the classic four, SW diagonal = sandbags, other
# diagonals empty (-1) so a sloppy flick can never buy something unnamed.
const _SECTOR_TO_ITEM: Array[int] = [2, -1, 3, 4, 0, -1, 1, 5]   # E,SE,S,SW,W,NW,N,NE(token)

## Sim event → [sound, volume dB, pitch]. Pickups are special-cased on cost.
const _EVENT_SOUND := {
	"shot": ["shot", -9.0, 1.0],
	"tank_shot": ["tank_shot", -3.0, 1.0],
	"throw": ["throw", -8.0, 1.0],
	"roll": ["roll", -8.0, 1.0],
	# "explosion" plays in _ev_explosion with proximity-scaled volume, not here.
	# "kill" plays in the match branch with streak-scaled pitch, not here.
	"player_down": ["player_down", 0.0, 1.0],
	"vest_break": ["vest_break", -2.0, 1.0],
	"gate_open": ["gate_open", -4.0, 1.0],
	"supply_drop": ["supply_chime", -6.0, 1.0],   # a1-14: a warm friendly cargo CHIME (whistle is the hostile strike cue)
	"drop_stolen": ["alarm", -9.0, 0.6],     # low growl: the crate is gone
	"drop_gone": ["alarm", -12.0, 0.45],     # lower fizzle: the window closed on its own
	"broadcast_pulse": ["alarm", -14.0, 0.5],  # sub-rumble rally tick — felt more than heard, under every threat cue
	"strafe_lane": ["alarm", -13.0, 1.6],     # high tick: the sweep lane lights up
	"flank_warn": ["alarm_low", -11.0, 0.85],    # c2/a1-13: structural sub-klaxon pre-tell
	"flank_breach": ["alarm_low", -6.0, 1.1],    # a1-13: structural sub-klaxon: the walls answer
	"revive": ["revive", -5.0, 1.0],
	"tank_board": ["tank_board", -5.0, 1.0],
	"tank_crew": ["tank_board", -5.0, 1.5],   # same clunk a fifth up: mounting, but not YOUR controls
	"tank_ignite": ["alarm", -4.0, 1.1],
	"observer_spawn": ["alarm", -3.0, 1.0],
	"strike_warn": ["whistle", -6.0, 1.0],
	"enemy_shot": ["enemy_shot", -12.0, 1.0],
	"elite_windup": ["alarm", -13.0, 0.7],   # incoming attack: a threat cue, not the friendly pickup jingle
	"grenadier_windup": ["throw", -8.0, 0.7],
	"drone_windup": ["alarm_air", -12.0, 1.0],   # a1-13: dedicated aerial paint-whine timbre
	"flashbang": ["flash", -8.0, 1.0],   # noise snap + 3.2 kHz ring — the ring's fade IS the stun window
	"flash_recover": ["alarm", -16.0, 2.4],  # stun window closing — the wake-up tick
	"rock_crater": ["explosion", -8.0, 0.6],  # low crumble: the arena just lost a rock
	"arena_shift": ["alarm", -10.0, 0.9],     # geometry klaxon: fresh cover dropped in
	"supply_pod": ["explosion", -5.0, 0.7],   # c4: a supply pod slams in a fresh cover fort
	"lane_warn": ["alarm", -11.0, 1.1],       # c4: a lane is about to seal — 0.75s dust tell
	"lane_seal": ["rubble", -5.0, 0.95], # c4/a1-13: real rubble (was silent)
	"lane_clear": ["click_dry", -8.0, 0.9],   # c4: the lane reopens
	"arena_pressure": ["alarm", -9.0, 1.3],   # c3: rising pressure-shift klaxon — the hot quadrant just moved
	"vent_warn": ["alarm", -13.0, 1.8],   # thin heat-tick: the grate is about to blow
	"vent_jet": ["rev", -11.0, 1.7],      # flame whoosh on the rev voice, pitched clear of engines
	"cover_burn": ["vest_break", -9.0, 1.3],   # c3: grass burns off in the jet — dry crackle
	"cover_crack": ["rubble", -7.0, 1.2], # c3/a1-13
	# a1-13 alarm taxonomy: STRUCTURAL breaches -> alarm_low; AERIAL paints (drone/
	# sniper/mg-nest) -> alarm_air; all OTHER generic threat cues (elite/grenadier
	# windups, observer_spawn, tank_ignite, strafe_lane, arena_pressure, vent/mast/
	# lane warns, colossus_engage, broadcast_pulse) intentionally stay on base "alarm".
	"rear_warn": ["alarm_low", -12.0, 0.9],   # c4/a1-13: structural sub-klaxon LEAD warn
	"rear_breach": ["alarm_low", -8.0, 1.0],   # c3/a1-13: structural sub-klaxon
	"mast_warn": ["alarm", -8.0, 0.9],     # c3: the mast is about to overheat — vacate the orbit
	"mast_pulse": ["explosion", -3.0, 0.7], # c3: the mast core vents — a wide radial one-shot zone
	"parapet_collapse": ["rubble", -3.0, 0.85], # c3/a1-13
	"arena_crack": ["rubble", -3.0, 1.0], # c4/a1-13
	"claymore_plant": ["click_dry", -4.0, 0.8],   # deliberate arming click, no longer the mount clunk
	"sandbag_plant": ["click_dry", -5.0, 0.6],    # low dig-in thud on the dedicated plant voice
	"sandbag_break": ["vest_break", -10.0, 0.7],  # low burst-of-burlap: cover gone
	"token_mint": ["buy_fanfare", -4.0, 1.0],   # a2-16: a proper milestone FANFARE, not the buy jingle pitched up
	"token_drop": ["buy", -4.0, 1.2],       # spending it sounds like the buy it is
	"hulk_salvage": ["tank_board", -6.0, 0.8],  # heavy strip-the-wreck clunk   # deliberate arming CLUNK (sapper's ambient clink is -15)
	"rend_pierce": ["vest_break", -8.0, 2.0],      # metal shear (KIMK: pitch 2.0 clears the true-break band)
	"mg_nest_aim": ["alarm_air", -12.0, 0.85],   # a1-13: aerial paint-whine, pitched below sniper_paint
	"technical_rev": ["rev", -8.0, 1.0],   # rising engine growl: a charge is coming (own synth — the tank_board clunk at 0.75 couldn't read as a rev)
	"technical_stall": ["splash", -8.0, 0.7],      # charge dies at the bank — wheels don't swim, audibly
	"pilot_down": ["avenge", -8.0, 0.8],           # crash-site ransom ping — friendly rising two-note (the alarm voice at 1.1 was byte-identical to tank_ignite's 'bail out now')
	"pilot_lost": ["alarm", -14.0, 0.6],           # low fail tone — he's gone
	"mine_lay": ["click_dry", -15.0, 1.2],   # sapper plants a mine: faint dry click
	"sniper_paint": ["alarm_air", -12.0, 0.92],   # a1-13: aerial paint-whine
	"sniper_fire": ["shot", -4.0, 0.6],
	"bunker_break": ["rubble", -3.0, 0.8],   # a1-13: a bunker collapsing IS rubble, not a fireball
	"bash": ["vest_break", -3.0, 0.8],
	"frogman_surface": ["splash", -4.0, 1.0],
	"wave_start": ["wave_start", -5.0, 1.0],
	"wave_clear": ["wave_clear", -5.0, 1.0],
	"colossus_engage": ["alarm", 0.0, 0.75],
	"victory": ["victory", 0.0, 1.0],
	"buy": ["buy", -4.0, 1.0],
	"deny": ["deny", -6.0, 1.0],
	"courier_escape": ["deny", -5.0, 0.7],   # the bounty runner got away with your coin — a low 'you lost it' sting
	"revive_deny": ["deny", -7.0, 0.9],      # pressed revive but can't afford it
}

var _hud_icons := HudIcons.new()
var _menu := GameMenu.new()


func _ready() -> void:
	# draw_texture_rect(tile=true) silently edge-clamps unless the canvas item
	# enables repeat — the 640px river banks were one stretched sand column.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 1x design-size floor. display/window/size/window_min_width|height are NOT
	# real Godot settings (silent no-op) — Window.min_size is the actual API, so
	# the integer-scaled 640x360 canvas can't be shrunk into a cropped degenerate.
	get_window().min_size = Vector2i(640, 360)
	# c1-19: the window IS freely resizable (standard desktop behavior on Windows/macOS/X11/Wayland,
	# where forcing a fixed window is hostile — users expect to grab an edge). The 640x360 canvas is
	# drawn with viewport + integer stretch (see project.godot / test_display_integer_stretch_configured),
	# so ANY window size renders at the largest whole-pixel scale that fits and letterboxes the rest —
	# a free drag can never produce blurry fractional pixels. _on_window_resized then SNAPS the shown
	# WINDOW SCALE label to that fitted integer, so the OPTIONS control and the real window stay in
	# sync. min_size keeps the floor at a clean 1x. The OPTIONS WINDOW SCALE row remains the way to
	# jump to an exact centered multiple; dragging is just the other, equally valid, path.
	add_child(_sfx)
	_hud_icons.main = self
	$HUD.add_child(_hud_icons)
	_menu.main = self
	$HUD.add_child(_menu)   # after HudIcons: menu draws on top
	_setup_screen_fx()
	_setup_water()
	# Additive glow layer: a plain child Node2D renders after main's own _draw but
	# under the $HUD CanvasLayer — muzzle/light/ember FX finally emit instead of tint.
	_glow_root = Node2D.new()
	_glow_root.z_index = 20            # explicit pin over all z=0 world draws (belt-and-braces
	_glow_root.z_as_relative = false   # vs relying on tree order alone; HUD CanvasLayer still wins)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_root.material = glow_mat
	_glow_root.draw.connect(_draw_glow)
	add_child(_glow_root)
	# ORDER MATTERS: _load_bests() restores mute via set_bus_mute, which only works
	# because add_child(_sfx) above already ran Sfx._ready() synchronously (main is
	# in-tree) and created the SFX/Music buses. Move _sfx to an autoload or deferred
	# add and this silently no-ops (get_bus_index returns -1).
	_load_bests()
	# Deferred: fullscreen (restored in _load_bests) resizes the window after
	# this frame, and the cursor bake reads the window size for its scale.
	call_deferred("_bake_cursor")
	get_viewport().size_changed.connect(_on_window_resized)   # re-bake cursor on scale-crossing resize
	_reset()
	if OS.has_feature("movie"):
		_menu.mode = GameMenu.Mode.HIDDEN   # trailer capture: straight into combat
		# Seed 18 won the 40-seed audition: vest break, two escalating
		# revives, ends alive — the War Chest pitch in 16 seconds.
		sim = SimWorld.new(18, 1)
		sim.players[0]["vest"] = true       # opening-ambush insurance (trailer only)
		# NOTE: for HD captures drop an override.cfg with stretch mode
		# "canvas_items" — the movie recorder sizes itself before _ready runs.


func _setup_screen_fx() -> void:
	# Full-screen concussion warp on its own high CanvasLayer so it rides ABOVE
	# the world + HUD and is immune to the Node2D shake/zoom applied to `self`.
	# The rect stays hidden (a true no-op — no backbuffer copy) until concussed.
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 100
	add_child(fx_layer)
	# a4-01: the always-on MASTER COLOR GRADE — added FIRST so it's the bottom of the fx
	# layer: its hint_screen_texture read captures the finished world + HUD (lower layers)
	# and grades them, then the scanlines + concussion draw on TOP of the graded frame. One
	# unifying film across all biomes (the game had no tonemap/LUT at all). SCREEN_UV-based,
	# so — unlike the FRAGCOORD scanlines — it is safe under the canvas_items HD-capture path.
	var grade_rect := ColorRect.new()
	grade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = load("res://src/view/grade.gdshader")
	grade_rect.material = _grade_mat
	fx_layer.add_child(grade_rect)
	# Always-on subtle scanlines: the frame is explicitly framed as an arcade
	# cabinet — sell it. Cheap fixed-math shader, no screen reads, both backends.
	# Skipped whenever the effective stretch is canvas_items (the HD override.cfg
	# path — movies AND stills): FRAGCOORD lands in physical pixels there → 1px moiré.
	if str(ProjectSettings.get_setting("display/window/stretch/mode", "viewport")) != "canvas_items":
		var scan := ColorRect.new()
		scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scan_mat = ShaderMaterial.new()
		_scan_mat.shader = load("res://src/view/crt.gdshader")
		scan.material = _scan_mat
		fx_layer.add_child(scan)
	_screen_fx_rect = ColorRect.new()
	# (No explicit .size — PRESET_FULL_RECT already sizes it, and setting both
	# printed a "size overridden after _ready()" warning on every boot.)
	_screen_fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eats input
	_screen_fx_rect.visible = false
	_screen_fx_mat = ShaderMaterial.new()
	_screen_fx_mat.shader = load("res://src/view/screen_fx.gdshader")
	_screen_fx_rect.material = _screen_fx_mat
	fx_layer.add_child(_screen_fx_rect)
	# Warm the pipeline at boot: one visible identity-branch frame (concussion 0
	# is a bit-exact pass-through) so the FIRST marquee blast doesn't pay the
	# shader-compile hitch mid-impact. _process hides it again next frame.
	_screen_fx_mat.set_shader_parameter("concussion", 0.0)
	_screen_fx_rect.visible = true


func _setup_water() -> void:
	# River water is a shader, not immediate-mode draws. Two world-space child
	# layers of `self` (so they ride the same shake/zoom as the units):
	#   • _bg_root (z=-2): the opaque grass/dirt base, relocated out of _draw() so
	#     it renders UNDER the water quads (grass would otherwise cover them).
	#   • a small pool of water ColorRects (z=-1): one shader quad per on-screen
	#     band, under the immediate-mode units (z=0) but over the grass. Absolute z
	#     (z_as_relative=false) pins the ordering. Bands are GATE_SPACING (1000px)
	#     apart on a 360px screen, so ≤1 shows at a time — 4 is ample headroom.
	# The pool is pre-built here (never grown inside _draw, which forbids add_child).
	_water_shader = load("res://src/view/water.gdshader")
	_bg_root = Node2D.new()
	_bg_root.z_index = -2
	_bg_root.z_as_relative = false
	# a1-19 PIPE#2: the 1:1 pixel ground (Kenney grass/dirt/sand) draws NEAREST so it
	# stays crisp — the project default_texture_filter is LINEAR_MIPMAP (right for the
	# legacy art bakes) but bilinear-smears the pixel tiles at integer scale.
	_bg_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_root.draw.connect(_paint_bg.bind(_bg_root))
	add_child(_bg_root)
	for _i in 4:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.visible = false
		r.z_index = -1
		r.z_as_relative = false
		var m := ShaderMaterial.new()
		m.shader = _water_shader
		m.set_shader_parameter("rect_size", Vector2(640.0, SimWorld.WATER_H * PX))
		r.material = m
		add_child(r)
		_water_rects.append(r)
		_water_pushed.append([-1, -1.0, 0.0])
	# Warm the water shader too (same first-draw compile hitch as screen_fx):
	# show one rect as a 1px off-screen-bottom sliver for the boot frame —
	# _sync_water repositions or hides it on the first real draw.
	_water_rects[0].position = Vector2(0.0, 359.0)
	_water_rects[0].visible = true


# a1-03: the water body follows the SAME 5-stop biome ramp as grass/dirt. It was
# a single soot-lerp toward generic brown (capped 0.7), so marsh water still read
# blue and foundry water read muddy-blue — the one terrain layer off the journey.
# Quantized per sector like the ground (the gate IS the shift): jungle teal ->
# scorched algae -> marsh murk-green -> ruins slate -> foundry molten-rust.
const _WATER_SHALLOW_STOPS := [Color(0.24, 0.43, 0.40), Color(0.31, 0.40, 0.30),   # a2-06: jungle stop de-cerulaned toward olive/tea
	Color(0.25, 0.40, 0.24), Color(0.30, 0.34, 0.36), Color(0.46, 0.28, 0.18)]
const _WATER_DEEP_STOPS := [Color(0.10, 0.20, 0.26), Color(0.13, 0.20, 0.16),   # a2-06: jungle deep less blue
	Color(0.09, 0.20, 0.11), Color(0.12, 0.15, 0.19), Color(0.25, 0.10, 0.06)]


func _sync_water() -> void:
	# Place a shader quad over every on-screen water band, faithful to _draw_water's
	# geometry (full width, WATER_H tall, at the band's screen-y). View-only: reads
	# sim state, never writes it. Called from _draw() so it also runs under the
	# screenshot harness (which disables _process). Unused pool entries are hidden.
	if sim == null:
		return
	# The river was the last terrain layer still postcard-blue at the Foundry's
	# doorstep — murk it toward rust/ash with the run like everything else.
	var wsec := clampi(int(_sector_march() * 5.0 + 0.0001), 0, 4)
	var w_shallow: Color = _WATER_SHALLOW_STOPS[wsec]
	var w_deep: Color = _WATER_DEEP_STOPS[wsec]
	var vis := 0
	for w in sim.waters:
		if vis >= _water_rects.size():
			break
		var wy: float = (w["y"] - sim.camera_top) * PX
		if wy > 360.0 or wy + SimWorld.WATER_H * PX < 0.0:
			continue   # band fully off-screen
		var rect := _water_rects[vis]
		var pushed: Array = _water_pushed[vis]
		vis += 1
		rect.visible = true
		rect.position = Vector2(0.0, wy)
		rect.size = Vector2(640.0, SimWorld.WATER_H * PX)
		# All five uniforms are constant per band + soot level, and each
		# set_shader_parameter dirties the material. Re-push only when this pool
		# rect is re-assigned to a different band or the sector soot moves.
		if pushed[0] != w["y"] or pushed[1] != wsec:
			pushed[0] = w["y"]
			pushed[1] = wsec
			var mat: ShaderMaterial = rect.material
			mat.set_shader_parameter("ford_center", (w["ford_x"] * PX) / 640.0)
			mat.set_shader_parameter("ford_halfw", (SimWorld.FORD_HALF_W * PX) / 640.0)
			# De-sync ripples per band: derive a stable phase from the band's world y.
			mat.set_shader_parameter("phase", fmod(float(w["y"]) * 0.00013, 37.0))
			mat.set_shader_parameter("shallow_col", w_shallow)
			mat.set_shader_parameter("deep_col", w_deep)
		# Wet-blast splash ring: only the band containing the blast animates it.
		# Guarded like the uniforms above — pushes only while a ring is live.
		var in_band: bool = _water_splash["t"] > 0.0 and _water_splash["y"] >= w["y"] \
			and _water_splash["y"] < w["y"] + SimWorld.WATER_H
		var st: float = _water_splash["t"] if in_band else 0.0
		if absf(pushed[2] - st) > 0.004:
			pushed[2] = st
			var smat: ShaderMaterial = rect.material
			smat.set_shader_parameter("splash_t", st)
			if in_band:
				smat.set_shader_parameter("splash_uv", Vector2((_water_splash["x"] * PX) / 640.0,
					float(_water_splash["y"] - w["y"]) / float(SimWorld.WATER_H)))
	for i in range(vis, _water_rects.size()):
		_water_rects[i].visible = false


func _paint_bg(canvas: Node2D) -> void:
	# The opaque grass/dirt base, relocated verbatim from _draw_terrain so it can
	# render on _bg_root (below the water). Drawn onto `canvas` (== _bg_root); the
	# rest of the terrain decor (clouds, ferns, trees, litter) stays in _draw().
	if sim == null:
		return
	var cam_y := sim.camera_top * PX
	var oy := -fposmod(cam_y, 64.0)
	var base_iy := int(floor(cam_y / 64.0))
	var march := _sector_march()
	# Two passes (all grass, then all dirt): interleaving the dirt patches split
	# the 80-rect grass run into ~27 texture-switch batches (~20 extra draw calls
	# per frame). One hash pass: dirt rects are collected during the grass loop
	# and drawn after. Dirt widths are clamped to their tile so the deferred
	# draws stay pixel-identical to the old order, where the next column's
	# grass painted over any bleed.
	# De-checkerboard (7-vote, 6 HATE votes): (a) shade band 0.144 -> 0.06 so
	# tiles stop reading as a chessboard while turf variation survives, (b)
	# olive grade (green pulled down, blue crushed) per KIMK, (c) 4 hash-picked
	# flip orientations of the one grass card kill the repeating-stamp read,
	# (d) dirt becomes 2-3 hash-ROTATED overlapping cards per cell instead of
	# one axis-aligned rect. All starting values — judged by screenshot.
	var dirt_cards: Array = []   # [center, rot, size, dirt_col] tuples
	# 5-stop biome ramp (5v: one biome with a linear scorch felt like a dimmer
	# switch, not a JOURNEY): jungle -> scorched -> marsh -> ruins -> foundry
	# ash. c2 3v: sample PER TILE ROW, not per frame — the new sector's flat
	# palette sweeps in from the top edge with the scroll (mirroring the litter
	# freeze), so ground behind the player never teleports palette; the seam
	# rides the breach line where the gate rubble + dust already live. The
	# quantized stops stay flat (KIMK pin) — no lerp, just a moving seam.
	var stops := _ground_stops(sim.mode)
	var grass_stops: Array = stops[0]
	var dirt_stops: Array = stops[1]
	for ty in 8:
		# Per-row march: rows south of the last march-step snap keep the old
		# stop (same comparison the litter freeze uses at row_wy >= snap).
		var row_wy_fp := int(float(base_iy + ty) * 64.0 * Fixed.ONE)
		var row_march := _litter_march_prev if row_wy_fp >= _litter_cam_snap else march
		var dirt_col := _biome_ramp(row_march, dirt_stops)
		var gt := _biome_ramp(row_march, grass_stops)
		for tx in 10:
			# floor(): oy is fractional (fposmod of cam_y) — subpixel tile origins
			# shimmer the seams while scrolling. Per-tile snap only; units stay smooth.
			var pos := Vector2(tx * 64.0, floor(oy + ty * 64.0))
			var h := Art.cell_hash(tx, base_iy + ty)
			var shade := 0.49 + float(h % 7) * 0.012   # a1-06: tiny tile micro-var; ~0.020 band checkerboards (macro value lives on the 0.16 mottle below)
			if (base_iy + ty) % 3 == 0:
				shade -= 0.012   # breaks the horizontal scan rhythm (4v: "stripes")
			var variant := (h / 7) % 4
			var gcol := Color(shade * gt.r, (shade + 0.03) * gt.g, shade * gt.b)
			if variant == 0:
				canvas.draw_texture_rect(Art.tex("grass"), Rect2(pos, Vector2(64, 64)), false, gcol)
			else:
				# Flip via transform — draw_texture_rect silently drops
				# negative-size rects (learned the gray-void way).
				canvas.draw_set_transform(pos + Vector2(32, 32), 0.0,
					Vector2(-1.0 if variant & 1 else 1.0, -1.0 if variant & 2 else 1.0))
				canvas.draw_texture_rect(Art.tex("grass"), Rect2(Vector2(-32, -32), Vector2(64, 64)), false, gcol)
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if h % maxi(3, 7 - int(march * 4.0)) == 0:   # a1-06: bare-earth density climbs toward the foundry
				for dc in 2 + (h % 2):
					var dh := Art.cell_hash(tx * 3 + dc + 1, base_iy + ty)
					dirt_cards.append([pos + Vector2(16.0 + float(dh % 33), 14.0 + float((dh / 5) % 33)),
						float(dh % 628) / 100.0,
						Vector2(30.0 + float(dh % 5) * 5.0, 26.0 + float(dh % 4) * 5.0), dirt_col])
	for card in dirt_cards:
		var dirt_col: Color = card[3]   # this card's per-row stop (c2 3v)
		canvas.draw_set_transform(card[0], card[1], Vector2.ONE)
		# a3-05: TWO feather rings grade the bare-earth patch into the turf so the hard
		# rotated `dirt` rect stops reading as a pasted rectangular/diamond decal — the
		# single 0.28-effective halo left the card's own edge showing (4v: figure-ground).
		# Wide faint outer ring, then a stronger inner halo, both under the hard fill.
		var halo_out: Vector2 = card[2] * DIRT_FEATHER["out_scale"]
		canvas.draw_texture_rect(Art.tex("fx_softspot"), Rect2(-halo_out / 2.0, halo_out), false,
			Color(dirt_col.r, dirt_col.g, dirt_col.b, dirt_col.a * DIRT_FEATHER["out_a"]))
		var halo: Vector2 = card[2] * DIRT_FEATHER["in_scale"]
		canvas.draw_texture_rect(Art.tex("fx_softspot"), Rect2(-halo / 2.0, halo), false,
			Color(dirt_col.r, dirt_col.g, dirt_col.b, dirt_col.a * DIRT_FEATHER["in_a"]))
		canvas.draw_texture_rect(Art.tex("dirt"), Rect2(-card[2] / 2.0, card[2]), false, dirt_col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# MACRO MOTTLE (4v: the barren-lawn killer): 2-3 broad, soft value shifts
	# per screen on a coarse 256px grid — trampled-earth patches, and the
	# occasional wheel-track pair along a hash heading. ~4-6 extra draws.
	var m_base := int(floor(cam_y / 256.0))
	var moy := -fposmod(cam_y, 256.0)
	for my in 3:
		for mx in 3:
			var mh := Art.cell_hash(mx * 13, m_base + my)
			if mh % 3 != 0:
				continue
			var mpos := Vector2(float(mx) * 256.0 + float(mh % 128), floor(moy + float(my) * 256.0 + float((mh / 7) % 128)))
			var mrot := float(mh % 628) / 100.0
			var msz := 192.0 + float(mh % 97)
			if mh % 6 == 0:
				# Wheel tracks (c2 2v wayfinding): the route reads as a TRAFFICKED
				# LINE, not random scuffs — 2-of-3 tracks snap near-vertical (the
				# corridor's travel axis) and hug the center lane; 1-in-3 stays
				# wild so it doesn't read as painted-on. Odds bumped 1/8->1/6.
				if mh / 17 % 3 != 0:
					mrot = PI / 2.0 + (float(mh % 60) / 100.0 - 0.3)   # within ±0.3rad of vertical
					mpos.x = 320.0 + (float((mh / 5) % 240) - 120.0)   # biased to the 200-440 lane
				canvas.draw_set_transform(mpos, mrot, Vector2(0.25, 2.5))
				for tk2 in 2:
					canvas.draw_texture_rect(Art.tex("fx_softspot"),
						Rect2(Vector2(-msz / 8.0 + float(tk2) * 12.0 - 6.0, -msz / 2.0), Vector2(msz / 4.0, msz)),
						false, Color(0.02, 0.05, 0.0, 0.10))
			else:
				# GPT round-2: not just dark — 1-in-3 mottle cells go BRIGHT
				# (sun-worn grass) and every cell carries a faint temperature
				# lean (warm khaki vs cool blue-green) so the variation stops
				# reading as one algorithmic dark stamp.
				var m_bright := (mh / 11) % 3 == 0
				var m_warm := (mh / 5) % 10 < (3 + int(march * 6.0))   # a1-06: warm lean climbs jungle(3/10)->foundry(9/10)
				var mcol := Color(0.55, 0.5, 0.28, 0.16) if m_bright else \
					(Color(0.10, 0.07, 0.0, 0.16) if m_warm else Color(0.0, 0.05, 0.06, 0.16))   # a1-06 r2: stronger SOFT mottle (was 0.10) for value variation without the tile grid
				canvas.draw_set_transform(mpos, mrot, Vector2(1.0, 0.6 + float(mh % 5) * 0.16))
				canvas.draw_texture_rect(Art.tex("fx_softspot"),
					Rect2(-Vector2.ONE * msz / 2.0, Vector2.ONE * msz), false, mcol)
				if (mh / 13) % 4 == 0:
					# Overlapping second gradient, offset + larger, for depth.
					canvas.draw_texture_rect(Art.tex("fx_softspot"),
						Rect2(Vector2(-msz * 0.75 + float(mh % 60), -msz * 0.6), Vector2.ONE * msz * 1.3),
						false, Color(mcol.r, mcol.g, mcol.b, mcol.a * 0.5))
	# a4-04: a COHERENT worn spine down the play lane — the mid-ground anchor + forward
	# wayfinding the stochastic mottle/scuffs above never gave (they read as random, not a
	# route). Overlapping soft packed-earth cards follow _spine_center_x (a PURE fn of
	# absolute world-y, so the trail scrolls seamlessly and never teleports laterally),
	# fusing into one connected trail; a faint tread pair rides its center. The old
	# center-biased wheel scuffs now land ON this spine and reinforce it. Drawn last so it
	# reads as the most-trampled ground; under the water layer so a ford still crosses it.
	var spine_top: float = floor(moy) - 96.0
	for si in 16:
		var sy: float = spine_top + float(si) * 56.0
		var cx: float = _spine_center_x(cam_y + sy)
		canvas.draw_set_transform(Vector2(cx, sy), 0.0, Vector2.ONE)
		canvas.draw_texture_rect(Art.tex("fx_softspot"),
			Rect2(Vector2(-48.0, -68.0), Vector2(96.0, 136.0)), false, SPINE_COL)
		if si % 2 == 0:
			for tk in 2:
				canvas.draw_texture_rect(Art.tex("fx_softspot"),
					Rect2(Vector2(-11.0 + float(tk) * 22.0 - 3.0, -58.0), Vector2(6.0, 116.0)),
					false, SPINE_TREAD)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(_delta: float) -> void:
	_watch_display()   # c1-19: catch a window dragged to another monitor (fires no resize signal)
	# c1-19: advance a running window-settle ONE sample per rendered frame — the frame loop (not
	# recursive call_deferred) guarantees each decoration sample lands on a DISTINCT frame, so the
	# multi-frame zero-stability gate can't be satisfied by several samples in a single idle flush.
	if _settle_active:
		_settle_window(_settle_gen)
	# c1-19: flush a debounced free-resize scale save once the window has been quiet long enough —
	# coalesces a continuous drag (many crossed scale boundaries) into ONE settings write.
	if _resize_save_t > 0.0:
		_resize_save_t -= _delta
		if _resize_save_t <= 0.0:
			_resize_save_t = 0.0
			_save_settings()
	# Sync the concussion overlay every rendered frame (covers gameplay, attract,
	# and pause — where _concussion is force-zeroed). Hidden at zero = pure no-op.
	if _screen_fx_rect == null:
		return
	# Blast heat-warp rides the same shader at low strength — a marquee detonation
	# briefly shocks the whole frame (blur+chroma pulse), then it snaps clear.
	# REDUCE MOTION: the strongest motion effect in the game (wobble + radial blur
	# + chroma) was the one screen-feel channel that missed the _motion pass. The
	# 0.25 floor mirrors the flash-alpha floor — a faint 'hurt' read, no warp.
	var amt := maxf(_concussion, _blast_warp) * maxf(_motion, 0.25)
	var on := amt > 0.001
	_screen_fx_rect.visible = on
	if on:
		_screen_fx_mat.set_shader_parameter("concussion", amt)
	# CRT scanlines surge darker on a big hit and ease back as the freeze decays —
	# reuses the already-drawn scan quad (zero added fillrate). Baseline 0.08 = the
	# shader default, so at rest the look is unchanged. Null when the scan quad is
	# skipped (canvas_items stretch / movie capture); _motion-gated for reduce-motion.
	if _scan_mat != null:
		var hs := clampf(float(_hitstop_frames) / 10.0, 0.0, 1.0) * _motion
		_scan_mat.set_shader_parameter("strength", 0.08 + hs * 0.12)
	# a4-01/a4-15: the master grade eases into a calm "breather" during the endless shop
	# intermission (safe to buy → a tonal breath), then eases back for the next wave. A slow
	# gentle tonal shift, not a strobe — reduce-motion-safe, so it isn't _motion-gated.
	if _grade_mat != null:
		var want := 0.0 if sim == null else _grade_breather_target(sim.mode, sim.intermission_ticks)
		_grade_breather = lerpf(_grade_breather, want, 0.06)
		_grade_mat.set_shader_parameter("breather", _grade_breather)


func start_game(endless: bool) -> void:
	_endless = endless
	_daily = false
	_reset()
	_menu.mode = GameMenu.Mode.HIDDEN
	_fade = 1.0   # cut from the title into combat, not a hard snap
	# Co-op with no pad for P2 reads as a broken game (P2 gets zero input and no
	# on-screen reason). Say so — it's a setup step, not a bug.
	if _two_players and Input.get_connected_joypads().size() < 2:
		_show_banner("P2: CONNECT A CONTROLLER", Color(1.0, 0.6, 0.35))


func start_daily() -> void:
	# Seed-of-the-day: everyone who plays today fights the identical layout — the
	# deterministic core turned into a shared, comparable challenge.
	_endless = false
	_daily = true
	_reset()
	_menu.mode = GameMenu.Mode.HIDDEN
	_fade = 1.0


func _daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return ((d["year"] * 10000 + d["month"] * 100 + d["day"]) * 2654435761) & 0x7FFFFFFF


func start_seeded(seed_v: int) -> void:
	# Challenge a friend: play a pasted seed's exact layout. Determinism makes the
	# whole run reproducible from the integer alone. Not a daily, so it won't claim
	# a daily-tagged Hall of Fame slot.
	_endless = false
	_daily = false
	_seed_override = seed_v
	_reset()
	_menu.mode = GameMenu.Mode.HIDDEN
	_fade = 1.0


func _clipboard_text() -> String:
	# The one clipboard read — split out so the menu can cache the raw string and
	# only re-parse when it actually changes (preview kept off the draw path).
	return DisplayServer.clipboard_get()


func _clipboard_seed() -> int:
	return _parse_seed_text(_clipboard_text())


const SHARE_PREFIX := "SHOEMONEY SOLDIER"   # c1-14: share-card title — the single source _copy_share_text prints and the parser recognizes
static var _seed_re: RegEx   # c1-14: cached trailing "seed N" field matcher (whole-word, digits to end)


static func _parse_seed_text(txt: String) -> int:
	# c1-14: parse a challenge seed from ONLY the two documented formats — a bare
	# non-negative integer, or the "... seed N" field of a RECOGNIZED share card (one
	# that starts with SHARE_PREFIX, or a bare "seed N" string). Arbitrary prose that
	# merely contains digits or the word "seed" ("not a seed 123", "oilseed 42",
	# "seed 42junk"), negatives and int64 overflow are all rejected (-1) so the menu
	# previews exactly what will load and never grabs a stray number.
	var s := txt.strip_edges()
	if s.is_empty():
		return -1
	# Format 1: the whole clipboard is one bare integer.
	var whole := _seed_from_digits(s)
	if whole >= 0:
		return whole
	# Format 2: only a recognized share card or a bare "seed N" string may carry a
	# seed field — never stray prose. The field itself is matched whole-word with the
	# digits running to end-of-string, so "seed 42junk" / "oilseed 42" don't slip in.
	var low := s.to_lower()
	var bare_field := low.begins_with("seed") and s.length() > 4 and (s[4] == " " or s[4] == "\t")
	if not (s.begins_with(SHARE_PREFIX) or bare_field):
		return -1
	if _seed_re == null:
		_seed_re = RegEx.new()
		_seed_re.compile("(?i)(?:^|\\s)seed\\s+([0-9]+)\\s*$")
	var m := _seed_re.search(s)
	if m == null:
		return -1
	return _seed_from_digits(m.get_string(1))


const _MAX_I64_STR := "9223372036854775807"   # int64 max, for overflow rejection by digit compare


static func _seed_from_digits(s: String) -> int:
	# A pure digit string -> non-negative seed, or -1 if it isn't all digits or would
	# overflow int64. Leading zeros are fine ("007" -> 7); "0" is a valid seed. Overflow
	# is rejected BEFORE to_int() (a digit-length/lexicographic compare) — to_int() errors
	# hard on out-of-range input, so we never hand it a string it can't represent.
	if s.is_empty():
		return -1
	for c in s:
		if c < "0" or c > "9":
			return -1
	var canon := s.lstrip("0")
	if canon.is_empty():
		return 0   # "0" / "000" -> a valid zero seed
	if canon.length() > _MAX_I64_STR.length():
		return -1
	if canon.length() == _MAX_I64_STR.length() and canon > _MAX_I64_STR:
		return -1
	return canon.to_int()


func start_seed_from_clipboard() -> void:
	# CHALLENGE SEED: load the clipboard's seed. The menu previews + gates this now,
	# so an empty clipboard never reaches here; the banner stays as a belt-and-braces.
	var sd := _clipboard_seed()
	if sd < 0:
		_show_banner("CLIPBOARD HAS NO SEED")
		return
	start_seeded(sd)


func start_watch() -> void:
	# Watch Last Run: re-step the saved replay through the real draw pipeline — the
	# replay's recorded inputs drive the sim in _physics_process instead of the pad.
	# Reuses _reset() (via _seed_override) to build the matching sim; nothing recorded,
	# no bests banked. The whole record→replay path was built but never player-facing.
	# The last run's replay may still be mid-write on the worker pool — a fast
	# debrief → R → WATCH could read a truncated file. Normally finished long
	# ago, so the wait is ~0ms.
	if _replay_task != -1:
		WorkerThreadPool.wait_for_task_completion(_replay_task)
		_replay_task = -1
	var r := Replay.load_from("user://last_run.replay")
	if r == null or r.frames.is_empty():
		_show_banner("NO REPLAY SAVED YET")
		return
	_endless = r.mode == "endless"
	_two_players = r.player_count >= 2
	_seed_override = r.seed_value
	_reset()
	_menu.mode = GameMenu.Mode.HIDDEN
	_fade = 1.0
	_watch_replay = r
	_watch_frame = 0
	_watching = true
	_show_banner("REPLAY — PRESS R TO EXIT", Color(0.55, 0.9, 1.0))


func _reset() -> void:
	Art.foliage_march = 0.0   # a1-05 r2: neutral until a gameplay frame feeds the march (no stale leak)
	_flush_bests()   # a run torn down without a debrief still banks its records
	# Per-run seed variety: the arcade skeleton is fixed (gate/boss/finale
	# positions), but spawn geometry, fords and drop luck differ each run —
	# a real 'run it again' hook. The trailer keeps the audited fixed seed.
	var seed_v: int
	if _seed_override >= 0:
		seed_v = _seed_override
		_seed_override = -1   # one-shot: consumed for this run only
	elif OS.has_feature("movie"):
		seed_v = 0xC0FFEE
	else:
		seed_v = _daily_seed() if _daily else randi()
	_current_seed = seed_v   # surfaced on pause so runs can be compared/shared
	sim = SimWorld.new(seed_v, 2 if _two_players else 1, "endless" if _endless else "campaign")
	sim.assist_mode = _assist   # accessibility: 2-hit vest each life, flagged on the leaderboard
	sim.hard = _hard and not _endless   # NG+ HARD applies to campaign only
	if _assist:
		for pl in sim.players:
			pl["vest"] = true
	_recorder = Replay.new()   # record this run's inputs for a replayable last-run (passive; sim untouched)
	_recorder.seed_value = seed_v
	_recorder.mode = sim.mode
	_recorder.player_count = sim.players.size()
	_replay_saved = false
	# A restart mid-replay must not keep feeding recorded frames into the new sim.
	_watching = false
	_watch_replay = null
	_watch_frame = 0
	_trauma = 0.0
	_hitstop_frames = 0
	_flash_alpha = 0.0
	_fx.clear()
	_pending_blasts.clear()
	_scorch.clear()
	_corpses.clear()
	_hulks.clear()
	_forks.clear()
	_vo_last.clear()
	_vo_plea_at = -1
	_last_stand_prev = false
	_tank_alive_prev.clear()
	_tank_hull.clear()
	_tank_prev.clear()
	_tank_turret.clear()
	_enemy_face.clear()
	_enemy_pos_prev.clear()
	_enemy_slot_kind.clear()
	_enemy_hp_prev.clear()
	_enemy_flash.clear()
	_spawn_yelled.clear()
	_spawn_yell_cd = 0
	_tech_lunge_prev.clear()
	_litter_cam_snap = 1 << 60
	_litter_march_prev = 0.0
	_blast_warp = 0.0
	_cinematic = 0.0
	_recoil = [Vector2.ZERO, Vector2.ZERO]
	_kick = Vector2.ZERO
	_kill_streak = 0
	_last_kill_frame = -100
	_rumble = 0.0
	_wheel = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]
	_damage_vignette = 0.0
	_banners.clear()
	_mud_told = false
	_mud_prev = [false, false]
	_seen_bosses = {}
	_seen_kinds = {}
	_prev_colossus_phase = 0
	_hitmarker = [0.0, 0.0]
	_hit_dir_t = 0.0
	_record_fired = false
	_deep_fired = false
	_boss_ghost.clear()
	_boss_hpmax.clear()
	_endless_boss_key = ""
	_punch = 0.0
	_fade = 0.0
	_duck = 0.0
	_concussion = 0.0
	_music_hold = 0
	_tension = 0.0
	_heat = [0.0, 0.0]
	_down_anim = [0.0, 0.0]
	_hint_t = 0.0
	_hint_queue.clear()
	_run_kills = 0
	_run_kind_kills.clear()
	_run_rescues = 0
	_downed_by = ""
	_last_gate_tick = 0
	_best_gate_split = 0
	_run_best_streak = 0
	_down_frames = 0
	_debrief = false
	_fire_swallow = true   # a SPACE/Enter/LMB redeploy press must not open the run firing


var _joy_brand_cache := {}   # device id → "xbox"/"ps"/"switch" (name lookup once per pad)


func _joy_brand(device: int) -> String:
	# Conservative name-prefix detection; anything unrecognized teaches Xbox
	# labels (the generic fallback every pad-glyph lookup already has).
	if _joy_brand_cache.has(device):
		return _joy_brand_cache[device]
	var jn := Input.get_joy_name(device).to_lower()
	var brand := "xbox"
	for tag in ["dualsense", "dualshock", "ps5", "ps4", "ps3", "playstation", "sony"]:
		if tag in jn:
			brand = "ps"
			break
	if brand == "xbox":
		for tag in ["switch", "joy-con", "joycon", "pro controller"]:
			if tag in jn:
				brand = "switch"
				break
	_joy_brand_cache[device] = brand
	return brand


func _bake_cursor() -> void:
	# The OS arrow floated over the battlefield (mouse is the default keyboard-
	# player aim device, LMB fires). Restyle it as a crosshair baked from the
	# game's own reticle art — menus keep a working, clickable pointer.
	# OS cursors render in PHYSICAL pixels and ignore the viewport stretch, so
	# bake at the window's integer scale (24px at 1x looked half-size at 2x).
	var win := DisplayServer.window_get_size()
	var s := maxi(1, mini(win.x / 640, win.y / 360))
	var cur_img := Art.tex("ui_reticle").get_image()
	if cur_img.is_compressed():
		cur_img.decompress()   # reticle ships VRAM-compressed; resize needs raw pixels
	cur_img.resize(24 * s, 24 * s, Image.INTERPOLATE_LANCZOS)
	_cursor_crosshair = ImageTexture.create_from_image(cur_img)
	# Menu pointer scaled to match (was native-size — a speck at 2x/3x).
	var men_img := Art.tex("ui_cursor").get_image()
	if men_img.is_compressed():
		men_img.decompress()
	men_img.resize(men_img.get_width() * s, men_img.get_height() * s, Image.INTERPOLATE_LANCZOS)
	_cursor_menu = ImageTexture.create_from_image(men_img)
	_cursor_s = s
	_apply_cursor(_cursor_styled)   # re-apply the current cursor at the freshly-baked scale


func _apply_cursor(styled: bool) -> void:
	# Hotspots scale with the baked art (_cursor_s), so the aim/click point never
	# drifts off the pointer at 2x/3x/fullscreen.
	Input.set_custom_mouse_cursor(_cursor_menu if styled else _cursor_crosshair,
		Input.CURSOR_ARROW,
		(Vector2.ONE * 2.0 * _cursor_s) if styled else (Vector2.ONE * 12.0 * _cursor_s))


func _input(event: InputEvent) -> void:
	# Fullscreen: F11 / Alt+Enter — the game had NO fullscreen path at all.
	# Handled in _input so it works with menus open; persisted with settings.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	# Track the LAST-USED device so glyphs/legends teach the right buttons —
	# a merely-connected idle pad shouldn't override an active keyboard.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
			return
		# In 2P, pad 1 is P2's device — its motion must not flip P1's glyphs
		# (P2 stick + P1 mouse would otherwise thrash use_pad every frame).
		if not (_two_players and event.device == 1):
			Art.use_pad = true
			Art.pad_brand = _joy_brand(event.device)
	elif event is InputEventKey or event is InputEventMouse:
		Art.use_pad = false
	# Pad redeploy: START on the debrief/victory card mirrors keyboard R — pad
	# players otherwise had to reach for a keyboard (or tunnel through pause →
	# RESTART → confirm). Consumed here so the menu doesn't also open pause.
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_START \
			and not _menu.is_active() and (_watching or _debrief or sim.victory):
		if _watching:
			# Mirrors the KEY_R replay exit — pad players had no direct way out.
			_watching = false
			_banners.clear()
			_menu.open(GameMenu.Mode.TITLE)
		else:
			_reset()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if _menu.is_active():
		return   # menu owns input while open
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_two_players = not _two_players
			_reset()
		elif event.keycode == KEY_F3:
			_endless = not _endless
			_reset()
		elif event.keycode == KEY_R:
			if _watching:
				_watching = false
				_banners.clear()   # a mid-replay splash shouldn't linger over attract
				_menu.open(GameMenu.Mode.TITLE)
			else:
				_reset()
		elif event.keycode == KEY_C and (_debrief or sim.victory):
			_copy_share_text()
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
				or event.keycode == KEY_SPACE) and (_debrief or sim.victory):
			# Keyboard redeploy mirrors pad START. Gated on the card being fully
			# in (~0.2s) so hammering fire at the death moment can't skip it.
			if _result_t >= 1.0:
				_reset()


func _run_rank() -> Dictionary:
	# One source of truth for the run's rank grammar, shared by the K.I.A. debrief
	# row and the share-card export. Pure read of view-tracked run stats.
	# ponytail: thresholds are rough hand-tuned bands, tune to taste.
	var opened := 0
	for g in sim.gates:
		if g["open"]:
			opened += 1
	var mvp := _run_kills * 2 + _run_best_streak * 5 + opened * 20
	if sim.mode == "endless":
		mvp += sim.wave * 12
	var grade := "S" if mvp >= 300 else "A" if mvp >= 200 else "B" if mvp >= 120 else "C" if mvp >= 60 else "D"
	var gtitle := "GRUNT"
	if _run_best_streak >= 20: gtitle = "ONE-MAN ARMY"
	elif _run_best_streak >= 12: gtitle = "IRON NERVES"
	elif _run_kills >= 60: gtitle = "EXTERMINATOR"
	elif opened >= 3: gtitle = "TRAILBLAZER"
	elif _run_kills >= 25: gtitle = "SHARPSHOOTER"
	var gcol := Color(1.0, 0.85, 0.3) if grade == "S" else Color(0.55, 0.9, 1.0) if grade == "A" else Color(0.6, 0.9, 0.5) if grade == "B" else Color(0.85, 0.85, 0.8) if grade == "C" else Color(0.7, 0.7, 0.7)
	return {"grade": grade, "title": gtitle, "col": gcol}


func _copy_share_text() -> void:
	# Turn a finished run into a pasteable one-liner (Discord/bug reports). The seed
	# is deterministic, so a friend can replay the exact layout via CHALLENGE SEED.
	var rr := _run_rank()
	var where := ("WAVE %d" % sim.wave) if sim.mode == "endless" else ("%dm PUSHED" % (-Fixed.to_int(sim.camera_top) / 10))
	var txt := "%s — SCORE %d · %s · RANK %s (%s) · seed %d" % [SHARE_PREFIX, sim.score, where, rr.grade, rr.title, _current_seed]
	DisplayServer.clipboard_set(txt)
	_show_banner("COPIED TO CLIPBOARD")


func _flush_bests() -> void:
	# Bests ratchet in memory during play; this is the only place they hit disk
	# outside _record_run. Called from _reset (covers restart/new game/attract
	# rollover) and _exit_tree (covers app quit).
	var sections := {}
	if _best_dirty:
		_best_dirty = false
		sections["best"] = {"score": best_score, "wave": best_wave, "dist": best_dist}
	if _seen_dirty:
		_seen_dirty = false
		sections["seen"] = {"hints": _seen}
	if not sections.is_empty():
		_persist(sections)


func _exit_tree() -> void:
	_flush_bests()
	if _replay_task != -1:
		WorkerThreadPool.wait_for_task_completion(_replay_task)


func _notification(what: int) -> void:
	# One-death sim: alt-tabbing away keeps sim.step() ticking blind and hands the
	# player a death that reads as a bug, not a loss. Auto-open pause the instant the
	# window loses focus during live play. sim.step() is already gated behind
	# _menu.is_active(), so this is a pure view gate with zero sim contact — golden-safe.
	# c1-19: flush a debounced free-resize scale save before the window closes, so a drag-then-quit
	# (or losing focus) can't drop the choice while its debounce timer was still counting down.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _resize_save_t > 0.0:
			_resize_save_t = 0.0
			_save_settings()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# no_autopause: the screenshot harness runs unfocused by design — without
		# this every staged gameplay shot captures the pause overlay instead.
		if _menu.mode == GameMenu.Mode.HIDDEN and not sim.wiped and not sim.victory and not no_autopause:
			_menu.open(GameMenu.Mode.PAUSE)
			queue_redraw()


func _update_cursor() -> void:
	# Styled OS cursor on menu/debrief/victory surfaces only. Live gameplay keeps
	# the stock cursor: the in-game reticle sits at aim*27 off the PLAYER, not at
	# the mouse, so the OS cursor is the only absolute mouse-position indicator.
	var styled := _menu.is_active() or _debrief or sim.victory
	if styled == _cursor_styled:
		return
	_cursor_styled = styled
	_apply_cursor(styled)


func _on_window_resized() -> void:
	# c1-19: a windowed size change (user drag OR our own scale/mode change) SNAPS the shown WINDOW
	# SCALE to the largest whole-pixel scale that fits the new client — the viewport+integer stretch
	# already letterboxes, so this only syncs the label/cursor to reality. Guards:
	#  * fullscreen has no windowed scale to sync;
	#  * snap == 0 means the client OVERFLOWS the work area — the fullscreen-sized client the
	#    fullscreen->windowed transition briefly reports; ignore it (no legit windowed drag exceeds
	#    the work area), so that transient can't clobber a preserved over-ceiling preference;
	#  * snap == _win_scale_norm() means the window already sits at the effective target — that's what
	#    OUR OWN resizes (_apply_windowed_scale) produce, so skip: a monitor-clamped effective size
	#    must NOT collapse a larger stored preference. Only a genuine user drag to a DIFFERENT integer
	#    scale rewrites the stored preference (an explicit resize IS a new choice).
	if _fullscreen:
		return
	if _prog_resize:
		return   # OUR OWN mode/scale transition is in flight — ignore its intermediate resize events (explicit guard, not a size heuristic), so a fitting transient client size can't overwrite the saved scale
	var win := DisplayServer.window_get_size()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var snap := snap_scale(win, usable.size, _max_win_scale())
	if snap == 0:
		return   # oversized transient (belt-and-suspenders alongside _prog_resize) — never touch the preference
	if snap != _win_scale_norm() and snap != _win_scale:
		_win_scale = snap             # update the live scale now so the OPTIONS label tracks the drag
		_resize_save_t = RESIZE_SAVE_DELAY   # debounce the WRITE — persisted once the drag goes quiet
	if snap != _cursor_s:
		call_deferred("_bake_cursor")


# c1-19: the largest whole-pixel scale a client size can show, given the work-area size and the
# monitor ceiling — pure + static so the client/decorated/taskbar sizing math is headless-assertable.
# Returns 0 to signal "IGNORE this size": a client that OVERFLOWS the work area is the fullscreen-
# sized client reported mid fullscreen->windowed transition (no legitimate windowed resize exceeds
# the usable area), so callers skip it rather than snapping to a bogus huge scale. usable == 0
# (no display metrics) disables the overflow guard but still clamps the fitted scale.
static func snap_scale(client: Vector2i, usable: Vector2i, ceiling: int) -> int:
	if usable.x > 0 and usable.y > 0 and (client.x > usable.x or client.y > usable.y):
		return 0
	return clampi(mini(client.x / 640, client.y / 360), 1, ceiling)


# c1-19: a window dragged onto a DIFFERENT monitor fires no resize signal (its pixel size is
# unchanged), and a same-monitor resolution / taskbar change moves the work area without changing
# the screen index — so poll BOTH the screen index and the usable rect every frame. On any change,
# re-measure the chrome and re-FIT the window to what the new work area holds (a 3x window moved
# onto a 1080p screen shrinks to fit; moving back grows it again). The stored PREFERENCE is never
# touched, so this is a transient fit, not a saved downgrade — hence no _save_settings here.
func _watch_display() -> void:
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	if scr == _last_screen and usable == _last_usable:
		return
	_last_screen = scr
	_last_usable = usable
	if _fullscreen:
		return
	if usable.size.x <= 0 or usable.size.y <= 0:
		return                           # no display metrics (headless) — nothing to fit
	# c1-19: re-fit when the actual client size no longer matches the EFFECTIVE target for the new
	# work area — this catches BOTH a shrink (moved to a smaller monitor: the ceiling drops, target
	# shrinks) AND a regrow (moved back to a bigger monitor: the ceiling rises, target grows again),
	# so _win_scale_norm() and the real window can never disagree. When the size already matches,
	# never a forced recenter (that yanks a window the player deliberately positioned) — only nudge
	# it back on-screen if the new work area leaves it hanging off an edge.
	# _measure_decorations is intentionally NOT called here: the reserve is written ONLY from the
	# deferred settle pass (reached via _apply_windowed_scale), so a transient post-fullscreen zero
	# decoration read can't clobber the cached value — honoring the stated cache invariant.
	if needs_refit(DisplayServer.window_get_size(), _win_scale_norm()):
		_apply_windowed_scale()          # size drifted from the new monitor's target: re-fit (this recenters)
		call_deferred("_bake_cursor")
	else:
		_clamp_window_on_screen()        # already the right size — keep placement, only nudge on-screen if it hangs off


# c1-19: does the actual client size disagree with the effective windowed target (640Nx360N)? Pure
# + static so the shrink/regrow monitor-change decision is headless-assertable — the client size
# and the reported scale can never silently diverge across a display move.
static func needs_refit(actual: Vector2i, scale: int) -> bool:
	return actual != Vector2i(640 * scale, 360 * scale)


func _physics_process(_delta: float) -> void:
	Art.colorblind = colorblind   # apply on menu/attract frames too, not just gameplay
	_update_cursor()
	if _menu.is_active():
		# Arm the fire-swallow every menu frame: the SPACE/LMB press that closes
		# the menu (RESUME click, title confirm) must not fire on resume.
		_fire_swallow = true
		_hud_icons.visible = _menu.mode != GameMenu.Mode.TITLE
		# Attract mode: the title runs a LIVE firefight behind the overlay
		# (reusing the tuned trailer bot) so the game sells itself before a
		# button is pressed. Pause freezes as before.
		if _menu.mode == GameMenu.Mode.TITLE:
			if sim.victory or sim.wiped or _down_frames > 150:
				_reset()
			# Feed one demo input per player so 2P attract isn't lopsided.
			var demo_inputs: Array[SimInput] = []
			for pi in sim.players.size():
				demo_inputs.append(demo_input(sim.tick_count + pi * 53, sim))
			sim.step(demo_inputs)
			_consume_events()
			_check_boss_intro()
			_down_frames = 0 if not sim._all_players_down() else _down_frames + 1
			_rumble = 0.0   # never buzz a controller on the menu
			# Attract steps the sim every frame and never decrements hit-stop, but
			# _consume_events can SET it (near demo blasts) — a stuck freeze would
			# wedge every feel gate (particles/envelopes/camera) forever. Clear it.
			_hitstop_frames = 0
			_update_feel()
		else:
			# Pause: clear the underwater LPF/duck so the menu sounds clean, and
			# square the camera — pausing mid-shake froze the world offset/tilted
			# behind the overlay.
			_concussion = 0.0
			_duck = 0.0
			_sfx.set_concussion(0.0)
			# _drive_audio stops on pause, so the drums would stay frozen at combat
			# level behind the menu — ease them to the lull instead.
			_sfx.set_music_intensity(0.0, 0.0)
			position = Vector2.ZERO
			scale = Vector2.ONE
			rotation = 0.0
		queue_redraw()
		return
	_hud_icons.visible = true
	if _watching:
		if _watch_replay == null or _watch_frame >= _watch_replay.frames.size() or sim.victory or sim.wiped:
			_watching = false
			_menu.open(GameMenu.Mode.TITLE)
			queue_redraw()
			return
		var rin: Array[SimInput] = []
		for enc in _watch_replay.frames[_watch_frame]:
			rin.append(SimInput.decode(enc))
		_watch_frame += 1
		sim.step(rin)
		_consume_events()
		_check_boss_intro()
		# Replay steps the sim every frame (a recorded run can't re-freeze), so a
		# hit-stop set by _consume_events would never decrement — clear it or the
		# feel gates wedge frozen while the replayed world keeps moving.
		_hitstop_frames = 0
		_update_feel()
		queue_redraw()
		_update_hud()
		return
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
	else:
		var inputs := _gather_inputs()
		_check_dry_throw(inputs)
		_recorder.record_tick(inputs)   # same inputs the sim gets → bit-exact replay
		sim.step(inputs)
		_consume_events()
		_check_trench_edges()
		_check_smoke_edges()
		_check_boss_intro()
		_track_bests()
		_tick_spawn_yells()
	_update_feel()
	queue_redraw()
	_update_hud()


func _check_trench_edges() -> void:
	# c3 2v view-only: a one-tick DROP-IN / climb-out cue so the sunken trench
	# reads as a VERB, not just a silent slow field. Compares this tick's
	# _in_trench to last tick's per player; pure feel, zero sim/checksum impact.
	if _trench_prev.size() != sim.players.size():
		_trench_prev.resize(sim.players.size())
	for i in sim.players.size():
		var p: Dictionary = sim.players[i]
		var now: bool = p["alive"] and sim._in_trench(p["x"], p["y"])
		if now and not _trench_prev[i]:
			# Dropped in: a low scuff + a puff of kicked-up dust at the lip.
			var sp := _to_screen(p["x"], p["y"])
			_sfx.play_at("click_dry", sp, -8.0, 0.7)
			for d in 4:
				_fx.append({"x": p["x"], "y": p["y"], "t": 0.0, "kind": "tex", "tex": "fx_smoke",
					"sz": 8.0 + d * 3.0, "grow": 0.6, "fade": 1.6, "rate": 0.02, "move": true,
					"vx": randf_range(-0.5, 0.5), "vy": -0.3 - d * 0.1, "col": Color(0.3, 0.3, 0.26, 0.5)})
		elif not now and _trench_prev[i]:
			# Climbed out: a lighter scuff, no dust.
			_sfx.play_at("click_dry", _to_screen(p["x"], p["y"]), -12.0, 1.1)
		_trench_prev[i] = now


func _lane_sector_dust(wy: float) -> Color:
	# c4 2v: recolor lane-block dust by sector so the tell reads as the place.
	match int(absf(wy) / float(SimWorld.GATE_SPACING)):
		2:
			return Color(0.42, 0.5, 0.34)   # marsh: mossy silt
		3:
			return Color(0.46, 0.44, 0.42)  # ruins: grey rubble
		4:
			return Color(0.6, 0.4, 0.26)    # foundry: rust ash
		_:
			return Color(0.5, 0.42, 0.34)


func _consume_events() -> void:
	var armor_pinged := false   # one ricochet ping per tick, not per bullet
	var boss_pinged := false    # one boss-hit ping per tick, not per bullet
	var explosion_pinged := false   # one boom per tick — cluster detonations emit up to 5
	var barrel_pinged := false      # one cook-off boom per tick — a fuse chain emits several
	var dirt_puffs := 0             # spent-round dust cap per tick — MG spam guard
	for ev in sim.events:
		var kind: String = ev["t"]
		if kind == "pickup":
			_sfx.play("buy" if ev.get("cost", 0) > 0 else "pickup", -5.0)
			# Collect pop: common crates used to vanish on a quiet blip — a spark
			# kiss + brief ground light marks WHERE the supply went. Reuses the
			# existing glow-layer fx grammar; rare drops keep their bigger
			# celebration below.
			_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.07})
			_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light",
				"rate": 0.14, "r": 12.0, "col": Color(1.0, 0.95, 0.6)})
			# Rare power-up grab (pierce=4 / spread=5): a bold rising callout + a
			# celebratory kick so collecting a 1-in-6 drop lands as an event, not a
			# silent stat bump. floattext + sfx + trauma are all view-only.
			if ev.get("kind", 0) >= 4 and ev.get("full", false):
				# Claymore grabbed at the 3-charge cap granted NOTHING but still
				# paid the gold callout + trauma + jingle — the last reward-shaped
				# lie in the pickup grammar (same rule that stripped the pilot
				# kill's hitmarker). Honest grey receipt, dull tone, no trauma.
				_fx.append({"x": ev["x"], "y": ev["y"] - 6, "t": 0.0, "kind": "floattext",
					"rate": 0.013, "size": 11, "text": "CLAYMORES FULL",
					"col": Color(0.72, 0.7, 0.66)})
				_sfx.play("buy", -9.0, 0.8)
			elif ev.get("kind", 0) >= 4:
				var cap_i: int = clampi(int(ev["kind"]) - 4, 0, _CAPSULE_CALLOUT.size() - 1)
				_fx.append({"x": ev["x"], "y": ev["y"] - 6, "t": 0.0, "kind": "floattext",
					"rate": 0.013, "size": 13, "text": _CAPSULE_CALLOUT[cap_i],
					"col": _CAPSULE_COL[cap_i]})
				# First-grab teaching: the new capsules are rules, not just stats —
				# one-shot hints (persisted) say what each actually DOES.
				match int(ev["kind"]):
					4: _hint("pierce", "PIERCING ROUNDS — SHOTS PUNCH THROUGH. AIM DOWN THE COLUMN")
					5: _hint("spread", "TRENCH GUN — 3-ROUND FAN WHILE IT LASTS. ON TRIPLE IT'S A 5-WAY FAN")
					6: _hint("triple", "TRIPLE SHOT — PERMANENT 3-ROUND FAN. STACK SPREAD FOR A 5-WAY FAN")
					7: _hint("rend", "REND ROUNDS — YOUR MG NOW PUNCHES THROUGH RIOT SHIELDS")
					8: _hint("claymore", "CLAYMORE — PLANT WITH [%s] AWAY FROM TANKS (IT HURTS BOTH SIDES)"
						% (Art.pad_label("interact") if Art.use_pad else "F"))
					9: _hint("smoke", "SMOKE — BLOCKS THEIR AIM, NOT THEIR CHARGE. KEEP MOVING")
					10: _hint("flashbang", "FLASHBANG — INFANTRY STUNNED. PUSH!")
				_trauma = minf(1.0, _trauma + 0.12)
				# Per-capsule pitch: all four rares shared one 1.4 jingle — grabbing
				# REND sounded identical to grabbing FLASHBANG. kind 7..10 -> 1.2..1.56.
				_sfx.play("buy_grab", -2.0, 1.2 + float(int(ev["kind"]) - 7) * 0.12)   # a2-16: rare capsule GRAB (warm), not the transaction chime
		elif kind == "explosion":
			# Up to 5 explosion events fire in one tick (colossus death-ring, bunker
			# clusters); stacking 5 full booms pumps the HardLimiter to mush. Gate to
			# one boom per tick — same idiom as the armor/boss pings above.
			# Barrel-origin blasts already boom via their barrel_blast event.
			if not explosion_pinged and ev.get("src", "") != "barrel":
				explosion_pinged = true
				# One boom — but the ear still agrees with the camera: volume scales
				# with proximity and pans to the blast (the cluster's lead event).
				_sfx.play_at("explosion", _to_screen(ev["x"], ev["y"]),
					lerpf(-12.0, -2.0, _blast_prox(ev["x"], ev["y"])))
		elif _EVENT_SOUND.has(kind):
			var snd: Array = _EVENT_SOUND[kind]
			# Any world event that carries coordinates pans/attenuates from where
			# it happened (a flank alarm tells you WHICH flank); coordinate-less
			# screen-global beats stay centered on the flat polyphonic player.
			if ev.has("x") and ev.has("y"):
				_sfx.play_at(snd[0], _to_screen(ev["x"], ev["y"]), snd[1], snd[2])
			else:
				_sfx.play(snd[0], snd[1], snd[2])
		match kind:
			"bullet_dirt":
				# Spent rounds kick dirt (or a splash) where they land — bullets
				# used to just vanish mid-field. Silent by design (whiz covers
				# near-misses); capped so MG spam can't sandstorm the screen.
				if dirt_puffs < 2:
					dirt_puffs += 1
					_burst(ev["x"], ev["y"],
						"splash" if sim._in_water(ev["x"], ev["y"]) else "dust",
						2, 0.3, 0.8, 0.3, 0.05)
			"armor_block":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.3})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
					"sz": 8.0, "fade": 1.5, "rate": 0.15, "col": Color(0.15, 0.13, 0.12, 0.7)})
				# MG Nest crack: armor_block also fires for the nest's 3-hit armor,
				# but the wall grammar taught the WRONG lesson — bullets DO crack
				# the nest. Distinct rising ping (hear "2 left / 1 left") + sand
				# chips + an honest hint; the bunker hint only fires off-nest.
				var nest_hit := false
				for ne in sim.enemies:
					if ne["alive"] and ne.get("kind", "") == "mg_nest" \
							and absi(ne["x"] - ev["x"]) < 14 * Fixed.ONE \
							and absi(ne["y"] - ev["y"]) < 14 * Fixed.ONE:
						nest_hit = true
						# The rising HP ping IS the nest's block sound — without this
						# flag the generic 1.7 ping below also fired the same tick.
						armor_pinged = true
						var nh: int = ne.get("hp", 0)
						_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex",
							"tex": "fx_sparkle", "sz": 5.0, "fade": 1.8, "rate": 0.18,
							"col": Color(0.85, 0.78, 0.5, 0.9)})
						if Engine.get_physics_frames() - _nest_ping_frame >= 10:
							_nest_ping_frame = Engine.get_physics_frames()
							_sfx.play_at("ping_shell", _to_screen(ev["x"], ev["y"]), -12.0,
								1.0 + float(3 - nh) * 0.3)
						_hint("nest_crack", "THE NEST CRACKS UNDER FIRE — KEEP SHOOTING, OR GRENADE IT")
						break
				if not nest_hit:
					_hint("armor", "GRENADES CRACK ARMOR — BUNKERS TAKE NO BULLETS")
				if not armor_pinged:
					armor_pinged = true
					_sfx.play("ping_armor", -16.0, 1.0)
				# Riot-shield deflect: armor_block fires for bunkers AND shields, but a
				# shieldman eating your frontal rounds looked identical to plinking a
				# wall. If the block landed on a shieldman, add a bright cyan ricochet
				# flash + a throttled metallic ping so "wasted from the front — flank
				# him" reads at the impact. Reads the event + existing enemy state.
				for se in sim.enemies:
					if se["alive"] and se.get("kind", "") == "shield" \
							and absi(se["x"] - ev["x"]) < 14 * Fixed.ONE \
							and absi(se["y"] - ev["y"]) < 14 * Fixed.ONE:
						_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex",
							"tex": "fx_sparkle", "sz": 6.0, "fade": 2.0, "rate": 0.16,
							"col": Color(0.55, 0.85, 1.0, 0.9)})
						if Engine.get_physics_frames() - _deflect_frame >= 10:
							_deflect_frame = Engine.get_physics_frames()
							_sfx.play_at("ping_armor", _to_screen(ev["x"], ev["y"]), -15.0, 1.3)
						break
			"boss_hit":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.3})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
					"sz": 8.0, "fade": 1.5, "rate": 0.15, "col": Color(0.15, 0.13, 0.12, 0.7)})
				_hitmarker[_hit_owner(ev["x"], ev["y"])] = 1.0
				_boss_flash = minf(1.0, _boss_flash + 0.35)   # the big body reacts, not just a spark
				if not boss_pinged:
					boss_pinged = true
					_sfx.play("ping_shell", -10.0, 1.2)
			"dry_fire":
				if Engine.get_physics_frames() - _dry_frame >= 14:
					_dry_frame = Engine.get_physics_frames()
					_sfx.play("click_dry", -8.0, 1.0)
					_vo("vo_clip_dry", 0, 720)
					# Empty-mag tell: a weak grey puff + a red "CLICK" at the muzzle — unmistakable
					# from the yellow shot flash, so a no-fire reads as "out of ammo", not a lost input.
					var dp := sim.players[ev["i"]]
					var mzx: int = ev["x"] + int(dp["aim_x"] * 10)
					var mzy: int = ev["y"] + int(dp["aim_y"] * 10)
					_fx.append({"x": mzx, "y": mzy, "t": 0.0, "kind": "smoke", "rate": 0.14})
					_fx.append({"x": mzx, "y": mzy, "t": 0.0, "kind": "floattext",
						"rate": 0.05, "text": "CLICK", "col": Color(1.0, 0.42, 0.36)})
			"bash":
				# Brutal point-blank melee: hit-stop + a spark toward the aim.
				_hitstop_frames = maxi(_hitstop_frames, 3)
				_trauma = minf(1.0, _trauma + 0.18)
				var bp := sim.players[ev["i"]]
				_recoil[ev["i"]] -= Vector2(bp["aim_x"], bp["aim_y"]) * PX * 3.0
				_fx.append({"x": ev["x"] + int(bp["aim_x"] * 12), "y": ev["y"] + int(bp["aim_y"] * 12),
					"t": 0.0, "kind": "spark", "rate": 0.3})
				_fx.append({"x": ev["x"] + int(bp["aim_x"] * 12), "y": ev["y"] + int(bp["aim_y"] * 12),
					"t": 0.0, "kind": "tex", "tex": "fx_swipe2", "sz": 16.0, "fade": 2.0, "rate": 0.1,
					"rot": Vector2(bp["aim_x"], bp["aim_y"]).angle(), "col": Color(1, 1, 1, 0.85)})
			"buy":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.02, "text": BUY_FLOAT[ev["kind"]], "col": Color(1.0, 0.95, 0.6)})
			"deny":
				var deny_txt: String = {"cap": "FIELD FULL", "tank": "NOT FROM THE TANK",
					"token": "NO COMMENDATION"}.get(ev.get("why", "coins"), "NEED COINS")
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": deny_txt, "col": Color(1.0, 0.45, 0.35)})
			"shot":
				_ev_shot(ev)
			"throw":
				# The lob has weight too: kick the thrower's body back along the aim,
				# lighter than a gunshot — throwing was the one action with no feedback.
				if ev["i"] < _recoil.size():
					var thrower := sim.players[ev["i"]]
					_recoil[ev["i"]] -= Vector2(thrower["aim_x"], thrower["aim_y"]) * PX * 1.6
			"tank_shot":
				var gunner := sim.players[ev["i"]]
				var taim := Vector2(gunner["aim_x"], gunner["aim_y"]) * PX
				_kick -= taim * 2.5
				_trauma = minf(1.0, _trauma + 0.15)
				_fx.append({"x": ev["x"] + int(gunner["aim_x"] * 18),
					"y": ev["y"] + int(gunner["aim_y"] * 18),
					"t": 0.0, "kind": "muzzle", "rate": 0.22, "a": taim.angle(), "big": true})
				_fx.append({"x": ev["x"] + int(gunner["aim_x"] * 18),
					"y": ev["y"] + int(gunner["aim_y"] * 18), "t": 0.0, "kind": "tex", "tex": "fx_swipe",
					"sz": 22.0, "fade": 1.6, "rate": 0.15, "rot": taim.angle(), "col": Color(1.0, 0.85, 0.5, 0.8)})
			"explosion":
				_ev_explosion(ev)
			"barrel_blast":
				# A fuel drum cooks off: heavy punch + a fireball light + a scorch mark.
				# One boom per tick (a fuse chain fires several) — same idiom as the
				# clustered explosion ping, so a ripple doesn't stack into a roar.
				if not barrel_pinged:
					barrel_pinged = true
					_sfx.play_at("explosion", _to_screen(ev["x"], ev["y"]), -6.0, 0.8)
					# Shake joins the one-per-tick gate too: an 8-tick cluster ripple
					# re-adding 0.3 trauma EVERY tick pinned the shake at max for the
					# whole chain — the sound was gated but the nausea wasn't.
					_trauma = minf(1.0, _trauma + 0.3)
					_rumble = maxf(_rumble, 0.55)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.13})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.09,
					"r": 58.0, "col": Color(1.0, 0.6, 0.2)})
				# Same fireball/smoke grammar as _ev_explosion, slightly smaller — the
				# cooking drum used to pop with ring+light only, no combustion body.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_disc",
					"sz": 24.0, "grow": 0.55, "fade": 1.8, "rate": 0.12, "col": Color(1.0, 0.75, 0.4, 0.85)})
				for si in 2:
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_smoke",
						"sz": 16.0 + si * 7.0, "grow": 0.9, "fade": 2.6, "rate": 0.008, "move": true,
						"vx": randf_range(-0.4, 0.4), "vy": -0.5 - si * 0.2,
						"col": Color(0.25, 0.22, 0.2, 0.7)})
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(14.0, 20.0)})
			"parapet_collapse":
				# A Foundry trench-parapet column drops as the boss escalates —
				# structural, not incendiary: a dust plume + tumbling debris + a
				# heavier ground shake (distinct grammar from the barrel fireball).
				_trauma = minf(1.0, _trauma + 0.4)
				_rumble = maxf(_rumble, 0.6)
				for di in 3:
					_fx.append({"x": ev["x"], "y": ev["y"] - di * 8.0, "t": 0.0, "kind": "tex",
						"tex": "fx_smoke", "sz": 18.0 + di * 6.0, "grow": 1.0, "fade": 2.4,
						"rate": 0.007, "move": true, "vx": randf_range(-0.5, 0.5),
						"vy": -0.35 - di * 0.15, "col": Color(0.34, 0.31, 0.28, 0.75)})
				for _ci in 5:
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_disc",
						"sz": randf_range(4.0, 8.0), "grow": -0.2, "fade": 1.4, "rate": 0.05,
						"move": true, "vx": randf_range(-1.4, 1.4), "vy": randf_range(-1.6, 0.2),
						"col": Color(0.5, 0.46, 0.4, 0.9)})
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(16.0, 22.0)})
			"kill":
				_ev_kill(ev)
			"bounty_kill":
				# Marked target down — a gold coin fountain + a distinct sting.
				_coin_pop(ev["x"], ev["y"], "BOUNTY +%d¢" % ev["coin"], 5, Color(1.0, 0.85, 0.3), 0.02)
				_sfx.play("buy_fanfare", -3.0, 1.3)   # a2-16: marked-target-down = a distinct milestone sting, not the buy chime
			"frag_bonus":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.02, "text": "FRAG x%d" % ev["n"], "col": Color(1.0, 0.7, 0.35)})
				# One mini frag icon per kill (capped at 4) flung outward for the pop.
				for fk in mini(int(ev["n"]), 4):
					var fa := float(fk) * TAU / 3.0 + 0.4
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "fragpop",
						"rate": 0.03, "move": true, "spin": fa,
						"vx": cos(fa) * 2.2, "vy": sin(fa) * 2.2 - 0.8})
				_sfx.play("buy_grab", -6.0, 1.2)   # a2-16: frag-pop multi-kill reward (grab)
			"bunker_break":
				_ev_bunker_break(ev)
			"rock_crater":
				# c2 arena scar: the rock's exit is a real blast beat + a
				# permanent crater decal where cover used to be.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "explosion"})
				_burst(ev["x"], ev["y"], "dust", 6, 1.0, 2.2, 0.3)
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(14.0, 18.0)})
			"arena_shift":
				# c2 arena drop: alert ring on the fresh L so the new geometry
				# announces itself during the wave-start breath.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.03})
			"supply_pod":
				# c4 2v: a supply pod SLAMS in a fresh 3x3 cover fort — an impact
				# shockwave + dust ring + shake so the renewed cover reads loud.
				_trauma = minf(1.0, _trauma + 0.35)
				_rumble = maxf(_rumble, 0.5)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.05})
				_burst(ev["x"], ev["y"], "dust", 8, 1.2, 2.4, 0.35)
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(18.0, 24.0)})
			"lane_warn":
				# c4 2v: a lane is about to SEAL — a rising dust tell + alert at the span,
				# the dust recolored by the sector (marsh / ruins / foundry).
				_burst(ev["x"], ev["y"], "dust", 6, 0.8, 2.0, 0.4, 0.0, -0.3, false, _lane_sector_dust(ev["y"]))
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.02})
			"lane_seal":
				# c4 2v: the lane SLAMS shut — a sector-tinted debris burst + a jolt.
				_trauma = minf(1.0, _trauma + 0.3)
				_burst(ev["x"], ev["y"], "dust", 9, 1.2, 2.4, 0.35, 0.0, -0.2, false, _lane_sector_dust(ev["y"]))
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(14.0, 20.0)})
			"lane_clear":
				# c4 2v: the lane reopens — a light settling puff.
				_burst(ev["x"], ev["y"], "dust", 4, 0.7, 1.6, 0.3)
			"cover_burn":
				# c3 5v: grass burns off under a vent jet — a puff of ash + a scorch.
				_burst(ev["x"], ev["y"], "ember", 6, 0.8, 2.0, 0.5, 0.05, 1.0, false,
					Color(0.9, 0.55, 0.2))
				_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(12.0, 16.0)})
			"cover_crack":
				# c3 5v: a wall slab cracks apart under the heat — dark debris + dust.
				_blast_debris(ev["x"], ev["y"])
				_burst(ev["x"], ev["y"], "dust", 6, 1.0, 2.4, 0.3, 0.06, 0.0, false,
					Color(0.4, 0.36, 0.32))
			"rear_warn":
				# c4 2v: the 1.5s LEAD warn before a rear spawn — a pulsing wedge at
				# the rear edge (below the 72%-down player) so a behind-you rusher is
				# READABLE before it lands. Softer than the rear_breach alert.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_softspot",
					"sz": 90.0, "grow": -0.15, "fade": 2.5, "rate": 0.012, "col": Color(0.9, 0.5, 0.2, 0.28)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.012})
				_rear_wedge_t = 1.5
				_rear_wedge_x = _to_screen(ev["x"], ev["y"]).x
			"rear_breach":
				# c3 3v: a threat is entering from behind — a dust puff + rising
				# alert at the rear edge so the player reads the pressure vector.
				_burst(ev["x"], ev["y"], "dust", 5, 0.8, 2.0, 0.4, 0.05, -0.4, false,
					Color(0.5, 0.42, 0.34))
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.035})
			"mast_warn":
				# c3 3v: the mast is about to overheat — a tightening warning ring
				# over the 120px hazard radius so the player reads it and vacates.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_softspot",
					"sz": 240.0, "grow": -0.3, "fade": 1.5, "rate": 0.02, "col": Color(1.0, 0.5, 0.15, 0.3)})
			"mast_pulse":
				# c3 3v: the core vents — a wide radial shockwave + shake denies the orbit.
				_trauma = minf(1.0, _trauma + 0.35)
				_rumble = maxf(_rumble, 0.6)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.045})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.08,
					"r": 130.0, "col": Color(1.0, 0.55, 0.2)})
			"arena_pressure":
				# c3 7v: the spawn pressure quadrant is rotating — banner + a
				# DIRECTIONAL arrow-march of pulses sweeping from center TOWARD the
				# hot x (judge r1: a real flank read, not stacked rings at one spot).
				_fx.append({"x": ev["x"], "y": ev["y"] + 60 * Fixed.ONE, "t": 0.0,
					"kind": "floattext", "rate": 0.012, "size": 11, "text": "PRESSURE SHIFTS",
					"col": Color(1.0, 0.55, 0.3)})
				var hot_cx: int = 320 * Fixed.ONE
				for pr2 in 5:
					# March the pulses from screen-center out to the hot side so the
					# eye is led toward the new heat (staggered rate = a sweep).
					var lerp_x: int = hot_cx + (ev["x"] - hot_cx) * (pr2 + 1) / 5
					_fx.append({"x": lerp_x, "y": ev["y"] + 100 * Fixed.ONE, "t": 0.0,
						"kind": "alert", "rate": 0.06 - float(pr2) * 0.008})
			"sniper_fire":
				# Crack + red flash so the kill-shot leaving the barrel is visible —
				# the paint-line telegraph vanishes the instant it fires.
				for k in 4:
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "muzzle",
						"rate": 0.32, "a": k * TAU / 4.0})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.14,
					"r": 22.0, "col": Color(1.0, 0.3, 0.25)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_lightning",
					"sz": 26.0, "fade": 2.5, "rate": 0.05, "rot": float(ev["y"] % 628) * 0.01, "col": Color(1.0, 0.95, 0.9, 0.85)})
			"tank_ignite":
				# The bail-out clock just started (alarm already sounds) — punch the
				# camera + throw an alert ring so it lands as a real "get out" beat.
				_trauma = minf(1.0, _trauma + 0.28)
				_rumble = maxf(_rumble, 0.55)
				_kick += Vector2(0, -3)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.03})
			"player_down":
				_trauma = minf(1.0, _trauma + 0.5)
				# A one-hit death is the loudest beat in the game — hold the
				# freeze longer and punch the camera in so the loss lands.
				_hitstop_frames = maxi(_hitstop_frames, 10)
				_flash_alpha = maxf(_flash_alpha, 0.35)
				_damage_vignette = 1.0
				_punch = maxf(_punch, 0.14)
				_rumble = maxf(_rumble, 1.0)
				_duck = 1.0
				_concussion = 1.0   # the world goes underwater for a beat
				_mark_hit_dir(ev["x"], ev["y"], ev.get("p", 0))
				_hint("revive", "FEED THE WAR CHEST TO REVIVE — [%s]" % (Art.pad_label("revive") if Art.use_pad else "E"), true)
				# Dying with a loadout (Triple/Pierce/Spread) strips it — call the loss
				# out with a red descending sting so it registers as a setback, not a
				# silent reset. Flags ride the checksum-excluded event (golden-safe).
				if ev.get("triple", false) or ev.get("pierce", false) or ev.get("spread", false):
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
						"rate": 0.02, "drop": true, "text": "LOADOUT LOST", "col": Color(0.95, 0.25, 0.2)})
					_sfx.play("deny", -5.0, 0.7)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "smoke"})
				# Directional death-gore: the felling round's exit spray carries
				# past the body, opposite the threat the wedge (_hit_dir) marks.
				var exitv := (-_hit_dir) if _hit_dir.length() > 0.5 else Vector2.from_angle(randf() * TAU)
				for g in 10:
					var pa := (exitv.angle() + randf_range(-0.8, 0.8)) if g < 7 else (randf() * TAU)
					var pspd := randf_range(1.8, 3.8) if g < 7 else randf_range(0.7, 1.4)
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "gib",
						"rate": randf_range(0.05, 0.075),
						"vx": cos(pa) * pspd, "vy": sin(pa) * pspd, "spin": randf() * TAU,
						"col": Color(0.55, 0.08, 0.06)})
			"mine_lay":
				# The sapper digs a mine in: a small low dust scuff to pair with the
				# faint clink, so the trail he's seeding reads even before the ring.
				_burst(ev["x"], ev["y"], "dust", 3, 0.4, 1.0, 0.4, 0.06)
			"flashbang":
				# Field-wide stun: ONE white wash (a single flash, never a strobe —
				# stays under the photosensitivity line) + a shockwave ring so the
				# frozen roster reads as an effect, not a bug.
				_flash_alpha = maxf(_flash_alpha, 0.45)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.06})
			"claymore_plant":
				# A deliberate resource-spend verb gets its own beat (the sapper's
				# ambient mine_lay clink read as background noise): dust scuff +
				# an ARMED pop naming what just happened.
				_burst(ev["x"], ev["y"], "dust", 3, 0.4, 1.0, 0.4, 0.06)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "CLAYMORE ARMED", "col": Art.safe(Color(0.5, 0.95, 0.7))})
			"rend_pierce":
				# Rend beat the shield block: white-hot shear AT the shield so the
				# buff's payoff reads on the field, not just the HUD corner.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.25})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.12,
					"r": 16.0, "col": Color(1.0, 0.75, 0.6)})
			"technical_rev":
				# Rev-up: dust kicked behind the wheels + engine rumble in the pad —
				# a gun-truck's charge tell should carry more weight than infantry
				# (it previously had less camera acknowledgment than a grenade lob).
				_burst(ev["x"], ev["y"], "dust", 4, 0.5, 1.2, 0.5, 0.07)
				_rumble = maxf(_rumble, 0.35)
			"pilot_down":
				_vo("vo_pilot_down", 2, 600)
				_vo_plea_at = int(Engine.get_physics_frames()) + 90
				_fx.append({"x": ev["x"], "y": ev["y"] - 8, "t": 0.0, "kind": "floattext",
					"rate": 0.012, "size": 12, "text": "PILOT DOWN — REACH HIM",
					"col": Art.safe(Color(0.5, 1.0, 0.7))})
				# Small zoom-hit pulls the eye to a time-limited off-path objective
				# (a boss SIGHTING got one; the ransom window got only text).
				# _punch is motion-scaled at application — RM-safe by construction.
				_punch = maxf(_punch, 0.06)
				# The banner carries the stakes BEFORE the player commits to the
				# chase: the payout number, and the friendly-fire trap (a stray
				# round pays nothing — sim rule the green ring alone can't teach).
				_hint("pilot", "RESCUE THE DOWNED PILOT — TOUCH, DON'T SHOOT — %d¢ RANSOM" % sim.PILOT_RANSOM, true)
			"pilot_rescued":
				_run_rescues += 1
				_coin_pop(ev["x"], ev["y"], "RANSOM +%d¢" % ev["coin"], 5, Art.safe(Color(0.5, 1.0, 0.7)), 0.02)
				_sfx.play("buy_fanfare", -2.0, 1.2)   # a2-16: RANSOM milestone
			"pilot_lost":
				_fx.append({"x": ev["x"], "y": ev["y"] + 20, "t": 0.0, "kind": "floattext",
					"rate": 0.02, "text": "PILOT CAPTURED", "col": Color(0.7, 0.65, 0.6)})
			"roll":
				# Launch poof grounds the dodge.
				_burst(ev["x"], ev["y"], "dust", 4, 0.6, 1.4, 0.5, 0.08)
				var rp: Dictionary = sim.players[ev["i"]]
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_wind",
					"sz": 15.0, "grow": 0.4, "fade": 1.2, "rate": 0.05,
					"rot": Vector2(rp["aim_x"], rp["aim_y"]).angle(), "col": Color(1, 1, 1, 0.5)})
			"gate_flawless":
				_vo("vo_flawless", 0, 600)
				# A disciplined, deathless checkpoint clear — gold payoff + sting,
				# louder as the clean-gate streak compounds.
				var fm: int = ev.get("mult", 1)
				var ftxt := "FLAWLESS  +%d¢  +%d" % [50 * fm, 2000 * fm]
				if fm > 1:
					ftxt = "FLAWLESS x%d  +%d¢  +%d" % [fm, 50 * fm, 2000 * fm]
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.016, "text": ftxt, "col": Color(1.0, 0.92, 0.45)})
				_sfx.play("buy_fanfare", -3.0, 1.0 + fm * 0.06)   # a2-16: flawless-streak milestone
			"avenge":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "AVENGED +5¢", "col": Color(0.7, 0.9, 1.0)})
				_sfx.play("avenge", -5.0)
			"surge":
				_vo("vo_surge", 0, 900)
				# The 20-streak adrenaline rush lands as a body-blow of feedback —
				# shockwave, warm light, an upward kick, and a rising sting — so the
				# 1.5x speed you now HOLD announces itself, not just a HUD number.
				_trauma = minf(1.0, _trauma + 0.22)
				_punch = maxf(_punch, 0.05)
				_rumble = maxf(_rumble, 0.5)
				_kick += Vector2(0, -4)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.1})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.08,
					"r": 60.0, "col": Color(1.0, 0.6, 0.2)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_circle",
					"sz": 24.0, "grow": 1.2, "fade": 1.0, "rate": 0.04, "col": Color(1.0, 0.7, 0.3, 0.6)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "ADRENALINE", "col": Color(1.0, 0.6, 0.25)})
				_sfx.play("gate_open", -3.0, 1.3)
			"route_fork":
				# Fires at STREAM time (~2 screens ahead) — no sound/banner here;
				# store the band and let _draw_gates signpost it when it scrolls in.
				_forks.append({"y": ev["y"], "x": ev["x"]})
			"route_bait":
				# c2 2v: a bait fork's trap lane. Deliberately NO honest signpost
				# or sound (reading the bait IS the skill) — the marker is stored
				# so the deeper wreck/sandbag dressing can render the richer cover.
				_forks.append({"y": ev["y"], "x": ev["x"], "bait": true})
			"revive_deny":
				_vo("vo_chest_empty", 2, 600)
			"gate_open":
				_ev_gate_open(ev)
			"token_mint":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext", "size": 12,
					"rate": 0.012, "text": "COMMENDATION *%d" % ev.get("n", 1), "col": Color(1.0, 0.85, 0.3)})
			"token_drop":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "SUPPLY CALL — " + BUY_FLOAT[ev["kind"]], "col": Color(1.0, 0.9, 0.5)})
			"hulk_salvage":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.016, "text": ("+%d GRENADES — COVER STRIPPED" % ev.get("n", 2)) if ev.get("n", 2) > 0 else "FULL UP — COVER STRIPPED", "col": Color(1.0, 0.8, 0.45)})
			"sandbag_plant":
				# One-beat dig-in puff: planted cover kicks real dust (9/9 panel).
				_burst(ev["x"], ev["y"], "dust", 5, 0.8, 1.8, 0.35)
			"tank_crew":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "GUNNER UP", "col": Color(0.7, 0.9, 1.0)})
			"flank_warn":
				# c2 2v: 0.75s dust-fall tell on the wall BEFORE it breaches —
				# trickling grit + a faint warning glow so the player reads the
				# vector and can pre-move (reuses the dust burst + a soft ring).
				_burst(ev["x"], ev["y"], "dust", 5, 0.4, 1.0, 0.4, 0.02, -0.6, false,
					Color(0.4, 0.36, 0.3))
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_softspot",
					"sz": 18.0, "grow": 0.4, "fade": 0.75, "rate": 0.03, "col": Color(1.0, 0.55, 0.3, 0.35)})
			"flank_breach":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "FLANKS!", "col": Color(1.0, 0.5, 0.3)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_smoke",
					"sz": 20.0, "grow": 1.0, "fade": 1.4, "rate": 0.02, "col": Color(0.5, 0.42, 0.35, 0.5)})
			"strafe_lane":
				# The gunship's sweep column, painted for ~0.4s at the strafe start.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_bullettrail",
					"sz": 300.0, "grow": 0.0, "fade": 0.4, "rate": 0.04, "rot90": true,
					"col": Color(1.0, 0.35, 0.25, 0.22)})
			"broadcast_pulse":
				# Expanding rally ring: the buff source and its reach, drawn from
				# the checksum-excluded event — the aura is invisible otherwise.
				# grow_px 132: the pulse expands 8 -> 140px, sweeping the aura's
				# TRUE reach every 90 ticks (the old ring showed nothing real).
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave",
					"sz": 8.0, "grow_px": 132.0, "rate": 0.022, "col": Color(1.0, 0.4, 0.35, 0.5)})
				# One-beat origin flash (GLM round-2): the sweep starts as a
				# deliberate EVENT at the mast, not a fade-in from nowhere.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light",
					"rate": 0.25, "r": 16.0, "col": Color(1.0, 0.5, 0.4)})
			"supply_drop":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.012, "text": "SUPPLY DROP — HOLD IT", "col": Color(0.6, 0.9, 1.0)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.03,
					"r": 26.0, "col": Color(0.6, 0.9, 1.0)})
			"drop_gone":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "DROP LOST", "col": Color(0.8, 0.6, 0.4)})
			"drop_stolen":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.014, "text": "DROP STOLEN", "col": Color(1.0, 0.45, 0.35)})
			"revive":
				_ev_revive(ev)
			"enemy_shot":
				# a1-09: incoming fire gets a DIRECTIONAL red muzzle FAN aimed at the nearest
				# player (view-only — the sim sends only x,y) so you see WHO fired in a wall
				# of small silhouettes; the faint glow stays underneath.
				var esm_p := sim._nearest_alive_player(ev["x"], ev["y"])
				var esm_a := 0.0
				if not esm_p.is_empty():
					esm_a = atan2(float(esm_p["y"] - ev["y"]) * PX, float(esm_p["x"] - ev["x"]) * PX)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "muzzle", "rate": 0.14,
					"a": esm_a, "szj": 0.6, "col": Color(1.0, 0.42, 0.28)})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.2,
					"r": 10.0, "col": Color(1.0, 0.4, 0.3)})
			"vest_break":
				_ev_vest_break(ev)
			"wave_start":
				var mod_name: String = ["", "  — BLITZ", "  — ELITE GUARD", "  — SPOTTER", "  — PAYDAY", "  — NIGHT OPS", "  — FRENZY", "  — MARKSMEN", "  — BOMBARDMENT"][ev.get("mod", 0)]
				_show_banner("WAVE %d%s" % [sim.wave, mod_name])
				_music_hold = maxi(_music_hold, 36)   # the inhale before the wave
				# Horde dust-bank: a wide low roll of dust at the top edge before the
				# spawns arrive — see the horde coming, tinted by the wave's mutator.
				var wm: int = ev.get("mod", 0)
				var dbcol := Color(0.4, 0.46, 0.6, 0.42) if wm == 5 else (Color(0.7, 0.45, 0.4, 0.42) if wm == 6 else Color(0.62, 0.6, 0.55, 0.4))
				for d in 7:
					var dbx: int = (320 + d * 100 - 300) * Fixed.ONE + int(randf_range(-25.0, 25.0)) * Fixed.ONE
					_fx.append({"x": dbx, "y": sim.camera_top + 18 * Fixed.ONE, "t": 0.0, "kind": "tex",
						"tex": "fx_smoke", "sz": 42.0, "grow": 0.6, "fade": 2.4, "rate": 0.007, "col": dbcol})
			"wave_clear":
				_show_banner("WAVE CLEARED — SHOP OPEN")
			"wave_flawless":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.015, "text": "CLEAN WAVE  +40¢  +1500", "col": Art.safe(Color(0.5, 1.0, 0.7))})
				_sfx.play("buy_fanfare", -3.0, 1.1)   # a2-16: CLEAN WAVE milestone
			"courier_escape":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "GOT AWAY!", "col": Color(0.85, 0.78, 0.5)})
			"observer_spawn":
				_vo("vo_observer", 1, 600)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.025})
				_show_banner("MORTAR OBSERVER — SHOOT IT DOWN OR PUSH ON", Color(1.0, 0.92, 0.55), "hud_lightning")
			"colossus_engage":
				_trauma = 1.0
				_hitstop_frames = maxi(_hitstop_frames, 8)
				_punch = maxf(_punch, 0.08)
				_music_hold = 48   # held breath before the finale
			"endless_boss":
				_vo("vo_shop_locked", 1, 900)
				_trauma = minf(1.0, _trauma + 0.4)
				_music_hold = maxi(_music_hold, 48)
				_show_banner("GUNSHIP INBOUND", Color(1.0, 0.92, 0.55), "hud_skull")
				_sfx.play("alarm", -4.0, 0.9)
				# A fast attack-heli escort streaks the top band ahead of the boss.
				_fx.append({"x": 0, "y": 0, "t": 0.0, "kind": "chopper", "rate": 0.02,
					"tex": "m_heli_attack2", "scl": 0.5, "sy": 52.0})
			"core_open":
				_vo("vo_core", 2, 300)
				_show_banner("CORE EXPOSED — OPEN FIRE", Color(1.0, 0.92, 0.55), "hud_target")
				_sfx.play("alarm", -6.0, 1.3)
			"airstrike_called":
				_vo("vo_airstrike", 1, 300)
				# Commit beat: the strike is inbound, not instant — announce it.
				_show_banner("AIRSTRIKE INBOUND")
				_sfx.play("whistle", -3.0, 0.85)
			"wiped":
				_vo("vo_wiped", 3, 600)
				# Whole squad down with no rescue — the endless run is over.
				_trauma = minf(1.0, _trauma + 0.6)
				_flash_alpha = maxf(_flash_alpha, 0.4)
				_hitstop_frames = maxi(_hitstop_frames, 8)
				_rumble = maxf(_rumble, 1.0)
				_show_banner("OVERRUN — RUN OVER")
				_sfx.play("wiped", -2.0)
			"victory":
				_vo("vo_victoly", 3, 6000)
				_ev_victory(ev)


func _ev_shot(ev: Dictionary) -> void:
	var shooter := sim.players[ev["i"]]
	var aim := Vector2(shooter["aim_x"], shooter["aim_y"]) * PX
	_recoil[ev["i"]] -= aim * 2.2
	_kick -= aim * 0.5
	if ev["i"] < _heat.size():
		_heat[ev["i"]] = minf(1.0, _heat[ev["i"]] + 0.09)
		# Overheated barrel vents steam at the muzzle — the heat
		# mechanic gets a physical tell, not just reticle bloom.
		if _heat[ev["i"]] >= 0.95 and Engine.get_physics_frames() % 8 == 0:
			_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 13),
				"y": ev["y"] + int(shooter["aim_y"] * 13), "t": 0.35, "kind": "smoke"})
	# Size/angle jitter per shot — MG spam reads as live gunfire, not a repeated decal.
	_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 13),
		"y": ev["y"] + int(shooter["aim_y"] * 13),
		"t": 0.0, "kind": "muzzle", "rate": 0.34, "pop": true,   # sol-15/16: player muzzles get the authored crack-pop card (enemy small-arms do NOT)
		"a": aim.angle() + randf_range(-0.09, 0.09), "szj": randf_range(0.82, 1.18)})
	# (Dropped: the textured soft-spot bloom that sat directly under the additive
	# muzzle glow — same flash drawn twice; one fewer translucent quad per shot.)
	var perp := Vector2(-aim.y, aim.x) * (1.0 if randf() < 0.5 else -1.0)
	if _fx.size() > 300:
		return   # spam guard: past this, casings/decals add draws, not information
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing",
		"rate": 0.055, "spin": randf() * TAU,
		"vx": perp.x * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4),
		"vy": perp.y * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4)})
	if randf() < 0.3:
		# Casing tink (8-vote grammar split): a sparse high chime under the MG —
		# every casing would be sleigh bells; ~1 in 3 reads as brass on dirt.
		_sfx.play_at("tink", _to_screen(ev["x"], ev["y"]), -22.0, randf_range(0.9, 1.1))
	# Faint muzzle light on the ground (rate-capped so MG spam can't wash out).
	if Engine.get_physics_frames() % 2 == 0:
		_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 11), "y": ev["y"] + int(shooter["aim_y"] * 11),
			"t": 0.0, "kind": "light", "rate": 0.28, "r": 16.0,
			"col": Color(1.0, 0.9, 0.5)})


func _blast_prox(x: int, y: int) -> float:
	# Proximity of a blast to the nearest alive player: 1.0 point-blank easing to
	# 0.35 at the far corner. Drives camera impact AND boom volume so the eye and
	# ear agree. Full force when no one is alive to measure against.
	var near := sim._nearest_alive_player(x, y)
	if near.is_empty():
		return 1.0
	var dist_px := Vector2(float(x - near["x"]), float(y - near["y"])).length() * PX
	return remap(clampf(dist_px, 60.0, 340.0), 60.0, 340.0, 1.0, 0.35)


func _vo(key: String, priority := 1, throttle_frames := 240, dry := false) -> void:
	## Radio bark with per-line throttle (voices panel: barks must not wear out
	## on the hundredth replay — banner-driven lines fire once per lifecycle,
	## mashable denials get seconds-long gaps).
	var now := int(Engine.get_physics_frames())
	if now - int(_vo_last.get(key, -100000)) < throttle_frames:
		return
	_vo_last[key] = now
	_sfx.play_vo(key, priority, dry)


func _ev_explosion(ev: Dictionary) -> void:
	# Proximity-scaled impact: a blast under your feet hits the camera at full
	# force; one in the far corner registers without shaking the whole frame.
	# (Mortar strikes and flank bunker chains used to land identically to a
	# point-blank grenade.) The boom plays once per tick in _consume_events.
	# Barrel-origin explosions: the gated barrel_blast branch owns the barrel's
	# feel (trauma/rumble) and its shockwave/fireball/smoke/scorch — skip the
	# duplicates here so a drum doesn't double-fire the whole feel stack.
	var barrel: bool = ev.get("src", "") == "barrel"
	if ev.get("src", "") == "airburst":
		# The pop must read AIRBORNE (re-review: fx spawned at ground y while
		# the grenade sprite drew height-offset — it teleported down to die).
		_fx.append({"x": ev["x"], "y": ev["y"] - 9 * Fixed.ONE, "t": 0.0, "kind": "flash",
			"sz": 15.0, "rate": 0.16})
		_fx.append({"x": ev["x"], "y": ev["y"] - 9 * Fixed.ONE, "t": 0.0, "kind": "light",
			"rate": 0.1, "r": 26.0, "col": Color(1.0, 0.9, 0.6)})
		_sfx.play_at("ping_armor", _to_screen(ev["x"], ev["y"]), -10.0, 1.6)
	if not barrel:
		var prox := _blast_prox(ev["x"], ev["y"])
		_trauma = minf(1.0, _trauma + 0.35 * prox)
		if prox > 0.7:
			_hitstop_frames = maxi(_hitstop_frames, 4)
		_rumble = maxf(_rumble, 0.7 * prox)
		_punch = maxf(_punch, 0.05 * prox)
		_duck = maxf(_duck, 0.7 * prox)
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "explosion"})
	if not barrel:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.12})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.09,
		"r": 60.0, "col": Color(1.0, 0.7, 0.35)})
	# Glow-decay bridge: a dimmer, slower light spanning flash → smoke, so the
	# blast reads as combustion cooling off instead of a strobe that just stops.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.03,
		"r": 38.0, "col": Color(0.9, 0.45, 0.18, 0.5)})
	# Textured hot-disc flash (legacy art fx_disc) over the procedural burst.
	if not barrel:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_disc",
			"sz": 30.0, "grow": 0.55, "fade": 1.8, "rate": 0.12, "col": Color(1.0, 0.82, 0.5, 0.85)})
	# Dark crater stamp bridges the instant flash and the slow-building scorch.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
		"sz": 20.0, "grow": 0.2, "fade": 0.8, "rate": 0.02, "col": Color(1, 1, 1, 0.6)})
	var wet: bool = sim._in_water(ev["x"], ev["y"])
	_burst(ev["x"], ev["y"], "splash" if wet else "dust", 8, 1.5, 3.0, 0.3)
	_blast_debris(ev["x"], ev["y"], wet)
	if not wet:
		if not barrel:
			_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(11.0, 16.0)})
			# Lingering smoke drifts up after the flash — a blast site used to clear to
			# bare scorch in ~0.3s while wave/gate spawns billow. Reuses the proven
			# long-life fx_smoke card + a gentle rise (move) so it reads as air.
			for si in 2:
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_smoke",
					"sz": 20.0 + si * 8.0, "grow": 0.9, "fade": 2.6, "rate": 0.008, "move": true,
					"vx": randf_range(-0.4, 0.4), "vy": -0.5 - si * 0.2,
					"col": Color(0.25, 0.22, 0.2, 0.7)})
	else:
		# Wet blast: the aftermath is steam, not soot — pale spray columns rising
		# fast, plus an expanding foam ring pushed to the water shader (the river
		# used to stay glass-calm under a detonation).
		for si in 2:
			_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_smoke",
				"sz": 15.0 + si * 6.0, "grow": 1.1, "fade": 2.0, "rate": 0.015, "move": true,
				"vx": randf_range(-0.3, 0.3), "vy": -0.8 - si * 0.3,
				"col": Color(0.82, 0.88, 0.9, 0.55)})
		_water_splash = {"x": ev["x"], "y": ev["y"], "t": 1.0}


func _any_player_smoked() -> bool:
	for sp in sim.players:
		if sp["alive"] and sp["smoke_ticks"] > 0:
			return true
	return false


# a2-12: the non-flesh KILL kinds (machines/emplacements) — throw metal sparks.
# shield=m_bombsuit is an armored HUMAN (flesh, keeps blood); sniper/grenadier/sapper/
# courier/ghillie/pilot/rusher/elite are all infantry; the spotter vehicles aren't
# direct kill-kinds. So this set is exhaustive for machine deaths.
const _METAL_KINDS := {"drone": true, "technical": true, "broadcast": true, "mg_nest": true}

static func _gib_col(kkind: String) -> Color:
	# a2-12 VFX#4: machines/vehicles/emplacements throw warm METAL SPARKS on death;
	# infantry throws BLOOD — a destroyed vehicle no longer bleeds red.
	return Color(1.0, 0.85, 0.5) if _METAL_KINDS.has(kkind) else Color(0.5, 0.1, 0.08)


static func _kill_tier(kkind: String) -> int:
	# a3-13: death weight class — 0 light infantry, 1 elite/specialist, 2 vehicle/emplacement.
	# Scales the death-pop radius + gib volume so a heavy dies bigger than a lone trooper.
	if kkind in ["technical", "drone", "mg_nest", "broadcast", "colossus"]:
		return 2
	if kkind in ["elite", "grenadier", "sniper", "ghillie"]:
		return 1
	return 0


static func _death_pop_fx(x: int, y: int, kkind: String) -> Dictionary:
	# a3-13: the bright LOCAL death-pop every kill spawns — an additive "light" fx (NOT a
	# frame flash), radius 9 + tier*6 so a heavy pops bigger than a trooper.
	return {"x": x, "y": y, "t": 0.0, "kind": "light", "rate": 0.055,
		"r": 9.0 + float(_kill_tier(kkind)) * 6.0, "col": Color(1.0, 0.9, 0.62)}


static func _top_prey_text(kind_kills: Dictionary) -> String:
	# a4-16: the run's most-fought foe — "TOP PREY  RUSHER x37", or "" if nothing died.
	# Shared by the K.I.A. debrief AND the VICTORY card (run-story parity).
	if kind_kills.is_empty():
		return ""
	var top := ""
	for kk in kind_kills:
		if top == "":
			top = kk
			continue
		var c := int(kind_kills[kk])
		var tc := int(kind_kills[top])
		# Higher count wins; on a TIE, the alphabetically-first kind wins — a stable result
		# independent of dictionary insertion order (a4-16 r2).
		if c > tc or (c == tc and String(kk) < String(top)):
			top = kk
	return "TOP PREY  %s x%d" % [String(top).to_upper(), int(kind_kills[top])]


static func _victory_story_rows(kills: int, streak: int, kind_kills: Dictionary) -> Array:
	# a4-16: the run-STORY rows the victory card shares with the K.I.A. debrief — a
	# KILLS + LONGEST STREAK line, plus a TOP PREY line when anything died.
	var rows: Array = [{"text": "%d KILLS  ·  LONGEST STREAK  x%d" % [kills, streak],
		"color": Color(0.9, 0.92, 0.85)}]
	var prey := _top_prey_text(kind_kills)
	if prey != "":
		rows.append({"text": prey, "color": Color(0.9, 0.92, 0.85)})
	return rows


static func _victory_best_text(score: int, best: int) -> String:
	# a3-14: the shared BEST / NEW BEST! line — one predicate for BOTH the K.I.A. debrief
	# and the VICTORY card (parity). "" when there is no prior best to show.
	if best <= 0:
		return ""
	return "BEST %d" % best + ("   NEW BEST!" if score >= best else "")


static func _victory_extra_rows(score: int, best: int, pulse: float) -> Array:
	# a3-14: the K.I.A.-parity rows the VICTORY card appends — a NEW BEST! flag (shared
	# predicate) + a REDEPLOY prompt with the START glyph (redeploy input works on victory).
	var rows: Array = []
	var bt := _victory_best_text(score, best)
	if bt != "":
		rows.append({"text": bt, "color": Color(0.9, 0.92, 0.85)})
	rows.append({"text": "REDEPLOY", "color": Color(1.0, 0.9, 0.4, pulse),
		"icon": Art.glyph_key("start"), "icon_size": 14.0})
	return rows


func _ev_kill(ev: Dictionary) -> void:
	# No screen flash here: at kill-spam rates it strobes
	# (photosensitivity); smoke + gib burst + blip + coin carry it.
	# A per-type death throe + a fading corpse so a cleared field
	# reads as fought-over, not swept clean.
	var kkind: String = ev.get("kind", "rusher")
	var kwet: bool = sim._in_water(ev["x"], ev["y"])
	if kkind == "pilot":
		# The sim pays NOTHING for gunning down the rescue — so the view must
		# not pay either. The generic path below is reward-shaped (hitmarker
		# confirm, streak feed, rising kill blip); running it here teaches the
		# exact opposite of the rule. Corpse + red receipt + the same low fail
		# tone as PILOT CAPTURED, and out.
		_corpses.append({"x": ev["x"], "y": ev["y"], "t": 0.0,
			"kind": _CORPSE_TEX.get(kkind, "elite"), "spin": randf() * TAU, "wet": kwet})
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
			"rate": 0.02, "text": "RANSOM LOST", "col": Color(1.0, 0.4, 0.3)})
		_sfx.play("alarm", -14.0, 0.6)
		_vo("vo_ransom_lost", 1, 900)
		return
	if kkind == "technical":
		# A gun-truck must die like a vehicle, not pop like infantry (panel
		# compromise: threat identity through spectacle, coin stays at elite
		# parity). Shockwave + hot flash + oily smoke on top of the generic
		# treatment below — the trophy is the wreck, not the payout.
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.15})
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.1,
			"r": 34.0, "col": Color(1.0, 0.6, 0.25)})
		for ts in 3:
			_fx.append({"x": ev["x"] + (ts - 1) * 5 * Fixed.ONE, "y": ev["y"], "t": -0.05 * ts,
				"kind": "smoke"})
		_sfx.play_at("explosion", _to_screen(ev["x"], ev["y"]), -10.0, 1.3)
	# Sprawl the corpse along the shot that felled it (away from the
	# nearest shooter), not a random spin. Every specialist leaves its OWN
	# silhouette (the kill event carries kind for exactly this); wet kills
	# leave a floating body with no blood pool instead of vanishing.
	var killer := sim._nearest_alive_player(ev["x"], ev["y"])
	var cspin := randf() * TAU
	if not killer.is_empty():
		cspin = atan2(float(ev["y"] - killer["y"]), float(ev["x"] - killer["x"]))
	_corpses.append({"x": ev["x"], "y": ev["y"], "t": 0.0,
		"kind": _CORPSE_TEX.get(kkind, "elite"),
		"spin": cspin, "wet": kwet})
	# Wet kills die in a splash, not a puff — the terrain reacts.
	if kwet:
		_sfx.play_at("splash", _to_screen(ev["x"], ev["y"]), -10.0, 1.2)
		for d in 6:
			var wa := d * TAU / 6.0
			_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "splash", "rate": 0.08,
				"vx": cos(wa) * randf_range(0.8, 1.8), "vy": sin(wa) * randf_range(0.8, 1.8),
				"move": true})
	else:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "smoke"})
	# a3-13 (VFX#3/VFX#2): a bright LOCAL death-pop on EVERY kill (was only technical) so a
	# kill lands with a punch. A small ADDITIVE light at the kill point — NOT a screen flash
	# (the strobe the header comment forbids for photosensitivity is a WHOLE-frame luminance
	# spike; a localized glow doesn't strobe the frame). Radius + gib volume scale by the unit
	# tier so a heavy dies visibly bigger than a lone trooper (a2-12 already keyed gib COLOR).
	var ktier := _kill_tier(kkind)
	_fx.append(_death_pop_fx(ev["x"], ev["y"], kkind))
	# Directional gib/spark burst — the kill hits back (5/8/11 gibs by tier, faster with tier).
	for g in 5 + ktier * 3:
		var ga := randf() * TAU
		var gspd := randf_range(1.0, 2.6) + float(ktier) * 0.6
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "gib", "rate": 0.07 + float(ktier) * 0.02,
			"vx": cos(ga) * gspd, "vy": sin(ga) * gspd,
			"spin": randf() * TAU, "col": _gib_col(kkind)})
	_hitmarker[_hit_owner(ev["x"], ev["y"])] = 1.0   # kill confirms on the shooter's reticle
	_run_kills += 1
	_run_kind_kills[kkind] = int(_run_kind_kills.get(kkind, 0)) + 1
	# Kill-streak: rising blip pitch + milestone combo pop.
	var big: bool = ev.get("coin", 0) >= 25
	if Engine.get_physics_frames() - _last_kill_frame < 90:
		_kill_streak += 1
	else:
		_kill_streak = 1
	_last_kill_frame = Engine.get_physics_frames()
	_sfx.play("kill", -7.0, 1.0 + minf(0.9, _kill_streak * 0.06))
	# Infantry agony yell (Ya Zahra / Ya Hossein bank) — flesh only. Machines
	# already boom via their own branch; pilots skip the reward path entirely.
	if not _METAL_KINDS.has(kkind) and kkind != "colossus" and kkind != "broadcast":
		_sfx.play_death_yell(_to_screen(ev["x"], ev["y"]), -6.0)
	if big:
		_hitstop_frames = maxi(_hitstop_frames, 2)   # elites/bosses only
		_rumble = maxf(_rumble, 0.35)
		_punch = maxf(_punch, 0.03)
	if _kill_streak == 5 or _kill_streak == 10 or _kill_streak == 20:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
			"rate": 0.02, "text": "x%d STREAK" % _kill_streak, "col": Color(1.0, 0.75, 0.3)})
		# The sim awards a real +25/50/100% score bonus at these tiers, but only
		# the 20-streak ever FELT it. Pop the earned bonus as a bold gold headline
		# + a brief white flash so hitting 5 and 10 read as milestones, not noise.
		var streak_bonus := 25 if _kill_streak == 5 else 50 if _kill_streak == 10 else 100
		_fx.append({"x": ev["x"], "y": ev["y"] - 12, "t": -0.14, "kind": "floattext",
			"rate": 0.016, "size": 13, "text": "+%d%%!" % streak_bonus, "col": Color(1.0, 0.92, 0.4)})
		# a1-12 VFX#8: a LOCALIZED gold bloom at the kill instead of a whole-screen
		# white flash — the milestone pops without strobing the whole frame mid-fight.
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.05,
			"r": 32.0 + float(_kill_streak) * 1.4, "col": Color(1.0, 0.82, 0.35)})
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_circle",
			"sz": 16.0, "grow": 1.1, "fade": 1.2, "rate": 0.05, "col": Color(1.0, 0.85, 0.4, 0.6)})
		_sfx.play("buy_fanfare", -8.0, 0.9 + _kill_streak * 0.015)   # a2-16: kill-streak milestone
	# Big bounties get a coin moment; rusher pennies would be spam.
	if big:
		_coin_pop(ev["x"], ev["y"], "+%d¢" % ev["coin"], 3, Color(1.0, 0.9, 0.45), 0.025)
	# A downed gunship is a finale, not a kill blip — ripple it apart.
	if kkind == "boss":
		_boss_death_finale(ev["x"], ev["y"])


func _tick_spawn_yells() -> void:
	## First time an infantry unit enters the viewport this life, chance a
	## battle-cry (Marg bar Amrika / Esrail / Allahu Akbar). View-only — no sim
	## event, nothing in the checksum. Cooldown + chance keep a rusher wave from
	## becoming a wall of overlapping shouts.
	if _spawn_yell_cd > 0:
		_spawn_yell_cd -= 1
	var ecount := sim.enemies.size()
	for sk in _spawn_yelled.keys():
		if sk >= ecount:
			_spawn_yelled.erase(sk)
	for eidx in ecount:
		var e: Dictionary = sim.enemies[eidx]
		if not e["alive"]:
			_spawn_yelled.erase(eidx)
			continue
		var skind: String = e.get("kind", "rusher")
		# Machines/vehicles don't chant; wait for submerged ambushers to surface.
		if _METAL_KINDS.has(skind) or skind == "colossus" or skind == "pilot":
			continue
		if e.get("submerged", false):
			continue
		# Slot inherited by a new kind after remove_at compaction → fresh shout chance.
		if _spawn_yelled.get(eidx, "") == skind:
			continue
		var sp := _to_screen(e["x"], e["y"])
		# Off the playfield → not "appeared" yet (top-edge spawn cradles are above -24).
		if sp.y < -20.0 or sp.y > 375.0 or sp.x < -40.0 or sp.x > 680.0:
			continue
		# Mark as seen for this occupant even if we skip the audio (cooldown choke).
		_spawn_yelled[eidx] = skind
		if _spawn_yell_cd > 0:
			continue
		if randf() > 0.55:
			continue
		_sfx.play_spawn_shout(sp, -8.0)
		_spawn_yell_cd = 22   # ~0.37s at 60 Hz — one shout per dense cluster beat


func _ev_bunker_break(ev: Dictionary) -> void:
	# The "explosion" SFX already fires (_EVENT_SOUND) but nothing
	# detonated on screen — give the demolished bunker its blast.
	_trauma = minf(1.0, _trauma + 0.22)
	_rumble = maxf(_rumble, 0.5)
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "explosion"})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.14})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.1,
		"r": 46.0, "col": Color(1.0, 0.7, 0.35)})
	_burst(ev["x"], ev["y"], "dust", 6, 1.2, 2.6, 0.3)
	_blast_debris(ev["x"], ev["y"])
	_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(12.0, 17.0)})
	_coin_pop(ev["x"], ev["y"], "+%d¢" % ev.get("coin", 0), 4, Color(1.0, 0.9, 0.45), 0.025)


func _blast_debris(x: int, y: int, wet: bool = false) -> void:
	# Layers a real detonation on top of the base explosion sprite + shockwave +
	# light: hot embers, dark thrown chunks, a delayed secondary core flash, and a
	# slow rising smoke curl. Gated off under reduce-motion; a water blast is a
	# splash, so it skips the fire/debris entirely.
	if wet or _motion < 0.5:
		return
	# Hot embers fly out radially, skew upward, and cool + dim fast.
	_burst(x, y, "ember", 8, 1.5, 3.6, 0.6, 0.05, 1.2, true)
	# Dark tumbling chunks thrown with wide speed variance — the blast throws
	# material. "debris" (oriented tumbling shard), not "gib" (blood dot):
	# inanimate shrapnel should read as rock/wood, not meat. "move" rides the
	# same vx/vy decay pass as casings/gibs.
	for _d in 5:
		var da := randf() * TAU
		var dh := (x / Fixed.ONE + _d * 131) % 97
		_fx.append({"x": x, "y": y, "t": 0.0, "kind": "debris", "rate": 0.05, "move": true,
			"vx": cos(da) * randf_range(1.0, 4.5), "vy": sin(da) * randf_range(1.0, 4.5),
			"col": Color(0.2, 0.17, 0.14), "spin": float(dh) * 0.35,
			"sz": 1.5 + float(dh % 11) * 0.1})
	# Secondary inner flash: a bright core that pops ~2 frames after the main flash.
	_fx.append({"x": x, "y": y, "t": -0.24, "kind": "flash", "rate": 0.16})
	# Slow rising smoke curl lingers after the fire.
	for _s in 2:
		_fx.append({"x": x + (randi() % 9 - 4) * Fixed.ONE, "y": y, "t": 0.0,
			"kind": "smoke", "rate": 0.035})


func _boss_death_finale(x: int, y: int) -> void:
	if _motion >= 0.5:
		_blast_warp = maxf(_blast_warp, 0.30)   # heat-shock the frame on the kill
	# THE finale — the biggest spectacle in the game. A staggered chain of
	# secondary detonations marches across the wreck's footprint over ~0.8s, a
	# smoke pillar rises up its center, and the screen-feel is scaled well past a
	# normal explosion. Additive view spectacle only: score/coin payout untouched.
	# Reduce-motion gets a quieter version (fewer blasts, no big shake).
	var reduced := _motion < 0.5
	# Peak screen feel — the one moment that earns a full-strength hit.
	_trauma = 1.0
	_hitstop_frames = maxi(_hitstop_frames, 10)
	_flash_alpha = maxf(_flash_alpha, 0.5)
	# Rumble is UNGATED by reduce-motion: haptics have their own toggle
	# (_rumble_on) and should compensate for damped visuals, not vanish with
	# them — every other rumble site (player_down, wiped, proximity) fires
	# under RM already; only the boss kill was silent.
	_rumble = maxf(_rumble, 1.0)
	if not reduced:
		_punch = maxf(_punch, 0.09)
	# Rising smoke pillar: puffs stacked up the center, drifting up and thinning
	# (long life via a low rate; move+vy carries them skyward as a column).
	var puffs := 3 if reduced else 6
	for s in puffs:
		_fx.append({"x": x + (randi() % 11 - 5) * Fixed.ONE, "y": y - s * 7 * Fixed.ONE,
			"t": 0.0, "kind": "smoke", "rate": 0.016, "move": true,
			"vx": randf_range(-0.3, 0.3), "vy": -1.4 - randf() * 0.8})
	# Staggered secondary blasts across the footprint (flatter than round so it
	# reads as a wreck breaking apart, not a sphere).
	var blasts := 3 if reduced else 10
	var step := 7 if reduced else 5
	for b in blasts:
		var ba := randf() * TAU
		var rad := randf_range(6.0, 40.0)
		_pending_blasts.append({
			"x": x + int(cos(ba) * rad * Fixed.ONE),
			"y": y + int(sin(ba) * rad * 0.6 * Fixed.ONE),
			"delay": 3 + b * step})


func _ev_gate_open(ev: Dictionary) -> void:
	_trauma = minf(1.0, _trauma + 0.2)
	_kick += Vector2(0, 6)   # the wall gives way — a forward lurch
	_punch = maxf(_punch, 0.04)
	# The wall bursts apart — dust cloud + tumbling debris.
	for d in 12:
		var ga := d * TAU / 12.0 + randf() * 0.3
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "dust", "rate": 0.05,
			"vx": cos(ga) * randf_range(1.5, 4.0), "vy": sin(ga) * randf_range(1.0, 3.0)})
	for d in 6:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing", "rate": 0.03,
			"spin": randf() * TAU, "vx": randf_range(-3.0, 3.0), "vy": randf_range(-3.0, 1.0)})
	# Breach haze: a low bank of settling dust spread across the opened corridor,
	# lingering a few seconds after the burst — you push THROUGH the breach, not
	# past an instant puff. Wide, slow-fading fx_smoke cards along the gate width.
	for d in 5:
		var hx: int = ev["x"] + (d - 2) * 140 * Fixed.ONE + int(randf_range(-30.0, 30.0)) * Fixed.ONE
		_fx.append({"x": hx, "y": ev["y"] + 8 * Fixed.ONE, "t": 0.0, "kind": "tex",
			"tex": "fx_smoke", "sz": 34.0, "grow": 0.7, "fade": 2.2, "rate": 0.006,
			"col": Color(0.72, 0.7, 0.66, 0.32)})
	# Per-gate split from the deterministic tick clock (view-side, golden-safe) —
	# the speedrun read the plan promised: how fast you took this checkpoint.
	var split := sim.tick_count - _last_gate_tick
	_last_gate_tick = sim.tick_count
	var tag := ""
	if _best_gate_split > 0 and split < _best_gate_split:
		tag = "  ⚡FAST"
	if _best_gate_split == 0 or split < _best_gate_split:
		_best_gate_split = split
	_show_banner("GATE SECURED — %.1fs%s" % [split / 60.0, tag])


func _ev_revive(ev: Dictionary) -> void:
	# The run's biggest co-op payoff finally gets a picture: a green
	# heal-burst + rising motes off the revived body.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.09})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.08,
		"r": 34.0, "col": Color(0.4, 1.0, 0.5)})
	for d in 8:
		var rva := d * TAU / 8.0 + randf() * 0.3
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "gib", "rate": 0.05,
			"vx": cos(rva) * randf_range(0.6, 1.6), "vy": sin(rva) * randf_range(0.6, 1.6) - 1.0,
			"spin": 0.0, "col": Color(0.5, 1.0, 0.6)})


func _ev_vest_break(ev: Dictionary) -> void:
	_flash_alpha = maxf(_flash_alpha, 0.35)
	_damage_vignette = maxf(_damage_vignette, 0.75)
	_concussion = maxf(_concussion, 0.7)
	_mark_hit_dir(ev["x"], ev["y"], ev.get("p", 0))
	# The flak vest shatters — blue armor shards burst outward.
	for d in 8:
		var va := d * TAU / 8.0 + randf() * 0.3
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "gib", "rate": 0.06,
			"vx": cos(va) * randf_range(1.2, 2.8), "vy": sin(va) * randf_range(1.2, 2.8),
			"spin": randf() * TAU, "col": Color(0.55, 0.7, 1.0)})


func _ev_victory(ev: Dictionary) -> void:
	_trauma = 1.0
	_flash_alpha = 0.6
	_punch = maxf(_punch, 0.18)   # the run's one win-state finally out-hits a common kill
	_cinematic = 1.0              # letterbox the extraction flyover
	# The one win-state of the whole run deserves a payoff: a gold
	# shockwave + light bloom off the wreck and a fountain of gold
	# confetti casings, not just a bare white flash.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.08})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.05,
		"r": 80.0, "col": Color(1.0, 0.85, 0.4)})
	for d in 22:
		var vca := randf() * TAU
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing",
			"rate": 0.018, "spin": randf() * TAU, "col": Color(1.0, 0.82, 0.35),
			"vx": cos(vca) * randf_range(1.2, 3.6),
			"vy": sin(vca) * randf_range(1.2, 3.6) - 1.6})
	# The colossus is the campaign's last boss — give its wreck the full finale.
	_boss_death_finale(ev["x"], ev["y"])
	# Extraction inbound: a transport chopper sweeps in over the win — you're
	# getting out. Slow, high in the frame, riding the fx flyover kind.
	_fx.append({"x": 0, "y": 0, "t": 0.0, "kind": "chopper", "rate": 0.006,
		"tex": "m_heli_transport", "scl": 0.62, "sy": 60.0})


func _check_boss_intro() -> void:
	# The Gunship deserves an arrival moment; the sim has no "engage" state,
	# so first-sight detection lives here in the view.
	for g in sim.gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		if g["y"] < sim.camera_top or g["y"] > sim.camera_top + SimWorld.VIEW_H:
			continue
		if _seen_bosses.has(g["y"]):
			continue
		_seen_bosses[g["y"]] = true
		_show_banner("BRIDGE GUNSHIP", Color(1.0, 0.92, 0.55), "hud_skull")
		_sfx.play("alarm", -2.0, 0.85)
		_trauma = minf(1.0, _trauma + 0.3)
		_punch = maxf(_punch, 0.12)   # boss sighting gets a zoom hit, not just shake
		_cinematic = maxf(_cinematic, 0.6)   # brief letterbox sells the arrival moment
		_music_hold = 48
	# Colossus escalation announcements.
	var phase := sim.colossus_phase()
	if phase > _prev_colossus_phase and phase >= 2:
		_show_banner("COLOSSUS ENRAGED — MORTAR VOLLEYS" if phase == 2
			else "COLOSSUS CRITICAL — SAPPERS OUT", Color(1.0, 0.92, 0.55), "hud_skull")
		# 0.65, NOT 0.7: the alarm ladder's exact pitch IS the threat identity
		# (sfx.gd _LADDERED) and 0.7 is elite_windup's recurring incoming-attack
		# cue — same class of collision pilot_down already fixed. 0.65 is an
		# unoccupied step between the 0.6 fail family and elite's 0.7.
		_sfx.play("alarm", -3.0, 0.65)
		# Phase-break shockfront: the world flinches when the boss escalates — an
		# arena-wide ground ring bursts from the colossus + a heavy camera hit.
		if not sim.colossus.is_empty():
			_fx.append({"x": sim.colossus["x"], "y": sim.colossus["y"], "t": 0.0, "kind": "tex",
				"tex": "fx_circle", "sz": 40.0, "grow": 9.0, "fade": 1.6, "rate": 0.02,
				"col": Color(1.0, 0.55, 0.3, 0.7)})
			for d in 10:
				var sa := d * TAU / 10.0
				_fx.append({"x": sim.colossus["x"], "y": sim.colossus["y"], "t": 0.0, "kind": "dust",
					"rate": 0.03, "vx": cos(sa) * randf_range(3.0, 6.0), "vy": sin(sa) * randf_range(2.0, 4.0)})
		_trauma = minf(1.0, _trauma + 0.4)
		_kick += Vector2(0, 8)
	if phase != _prev_colossus_phase:
		_prev_colossus_phase = phase


func _save_cfg(cf: ConfigFile) -> void:
	# Atomic, crash-safe write: a mid-save crash must never corrupt the single
	# ikari_best.cfg (= total progress wipe). Write to .tmp; on success snapshot
	# the current real file to .bak, then atomically rename .tmp over the real
	# path. rename_absolute is an OS rename — atomic on the same filesystem.
	if cf.save(SAVE_TMP) != OK:
		push_warning("ikari: config save failed")
		return
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, SAVE_BAK)
	DirAccess.rename_absolute(SAVE_TMP, SAVE_PATH)


func _persist(sections: Dictionary) -> void:
	# Shared load-then-merge-then-save boilerplate: load first so sibling
	# sections ([best]/[hall]/[seen]/[settings]) already on disk never get
	# clobbered by a save that only knows about its own section. Takes
	# {section: {key: value}} so multiple dirty sections share ONE disk dance
	# (an R-restart with best+seen both dirty used to pay the 4-op load/tmp/
	# bak/rename twice back-to-back on the keypress frame).
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for section in sections:
		for k in sections[section]:
			cf.set_value(section, k, sections[section][k])
	_save_cfg(cf)


func _load_bests() -> void:
	var cf := ConfigFile.new()
	# c1-18: binds always start at their ship defaults; the load branch overlays any
	# persisted [binds]/[padbinds] on top, so a fresh install (or a save predating
	# rebinds) still has a complete, valid map before the first _gather_inputs read.
	_binds = BIND_DEFAULTS.duplicate()
	_pad_binds = [PAD_DEFAULTS.duplicate(), PAD_DEFAULTS.duplicate()]   # P1 + P2 both start at ship defaults
	_menu_binds = MENU_BIND_DEFAULTS.duplicate()
	# Fall back to the .bak snapshot if the primary is missing/corrupt, before
	# giving up to zeros (a silent wipe).
	if cf.load(SAVE_PATH) == OK or cf.load(SAVE_BAK) == OK:
		# c1-18: overlay saved binds action-by-action (never wholesale-replace the map)
		# so a verb added in a later build keeps its default when an older save lacks it,
		# and a legacy save with NO [binds]/[padbinds]/[menubinds] stays fully at defaults.
		var saved_kb := {}
		var saved_pad := {}
		var saved_pad2 := {}
		var saved_menu := {}
		for a in BIND_DEFAULTS:
			saved_kb[a] = cf.get_value("binds", a, null)
		for a in PAD_DEFAULTS:
			saved_pad[a] = cf.get_value("padbinds", a, null)
			saved_pad2[a] = cf.get_value("padbinds2", a, null)   # P2's independent layout
		for a in MENU_BIND_DEFAULTS:
			saved_menu[a] = cf.get_value("menubinds", a, null)
		# Keyboard/menu keycodes are nonnegative (lo=0); pad buttons run -1(UNBOUND)..
		# JOY_BUTTON_MAX-1 (JOY_BUTTON_MAX itself is the enum COUNT sentinel, not a real button).
		_binds = overlay_binds(BIND_DEFAULTS, saved_kb, 0)
		# c1-18: each pad reloads its OWN [padbinds]/[padbinds2] section — a save predating
		# per-player layouts has no [padbinds2], so P2 overlays all-null and lands at defaults.
		_pad_binds = [overlay_binds(PAD_DEFAULTS, saved_pad, -1, JOY_BUTTON_MAX - 1),
			overlay_binds(PAD_DEFAULTS, saved_pad2, -1, JOY_BUTTON_MAX - 1)]
		_menu_binds = overlay_binds(MENU_BIND_DEFAULTS, saved_menu, 0)
		best_score = cf.get_value("best", "score", 0)
		best_wave = cf.get_value("best", "wave", 0)
		best_dist = cf.get_value("best", "dist", 0)
		_seen = cf.get_value("seen", "hints", {})
		hall.assign(cf.get_value("hall", "runs", []))
		# Resume the id counter past the highest hid on disk so a fresh run can never
		# collide with a reloaded entry's id (old saves lack hid -> starts at 0).
		for r in hall:
			_hall_seq = maxi(_hall_seq, int(r.get("hid", -1)) + 1)
		_life_runs = cf.get_value("life", "runs", 0)
		_life_kills = cf.get_value("life", "kills", 0)
		_life_wins = cf.get_value("life", "wins", 0)
		# c1-09: read each key (SETTINGS_DEFAULTS is the fallback source; legacy saves
		# only carried the mute BOOLS, so map those to a 0 level) into one dict, then
		# push it through the SAME _apply_settings path fresh-install and RESET use —
		# no field-by-field mapping to drift, and fullscreen=false explicitly restores
		# windowed mode (the old branch only handled the true case).
		_apply_settings({
			"colorblind": cf.get_value("settings", "colorblind", SETTINGS_DEFAULTS["colorblind"]),
			"assist": cf.get_value("settings", "assist", SETTINGS_DEFAULTS["assist"]),
			"reduce_motion": cf.get_value("settings", "reduce_motion", SETTINGS_DEFAULTS["reduce_motion"]),
			"rumble": cf.get_value("settings", "rumble", SETTINGS_DEFAULTS["rumble"]),
			"swap_sticks": cf.get_value("settings", "swap_sticks", SETTINGS_DEFAULTS["swap_sticks"]),
			"swap_sticks_p2": cf.get_value("settings", "swap_sticks_p2", SETTINGS_DEFAULTS["swap_sticks_p2"]),
			"sfx_vol": cf.get_value("settings", "sfx_vol",
				0 if cf.get_value("settings", "sfx_muted", false) else SETTINGS_DEFAULTS["sfx_vol"]),
			"music_vol": cf.get_value("settings", "music_vol",
				0 if cf.get_value("settings", "music_muted", false) else SETTINGS_DEFAULTS["music_vol"]),
			"fullscreen": cf.get_value("settings", "fullscreen", SETTINGS_DEFAULTS["fullscreen"]),
			# c1-19: read the saved windowed scale back (missing this dropped it on every load,
			# so a chosen scale never survived a restart). Legacy saves lack the key -> ship 2x.
			"window_scale": cf.get_value("settings", "window_scale", SETTINGS_DEFAULTS["window_scale"]),
		})
	else:
		# c1-09: fresh install (no save yet) — apply the SAME authoritative defaults
		# rather than leaning on the field initializers, so every settings value comes
		# from one source whether the game is booting clean, loading, or resetting.
		_apply_settings(SETTINGS_DEFAULTS)


# c1-09: THE authoritative ship-default for every persisted [settings] key — one
# table so _load_settings' fallbacks and _reset_settings' revert can't drift, and
# a newly-added setting is reset the moment it's given a default here. reduce_motion
# is the persisted bool; the live field is _motion (1.0 normal / 0.0 reduced).
const SETTINGS_DEFAULTS := {
	"colorblind": false,
	"assist": false,
	"reduce_motion": false,
	"rumble": true,
	"swap_sticks": false,      # P1 stick-swap
	"swap_sticks_p2": false,   # P2 stick-swap (independent)
	"sfx_vol": 10,
	"music_vol": 10,
	"fullscreen": false,
	"window_scale": 2,
}


# c1-18: ship-default player-1 keyboard binds (action -> PHYSICAL keycode) — the ONE
# authoritative table load and RESET both read, mirroring SETTINGS_DEFAULTS. Physical
# keycodes (not logical) so a bind survives AZERTY/QWERTZ the same way the hardcoded
# reads did. The ORDER here is also the order the rebind screen lists the actions in.
# Menu nav and aim stay on their own always-available fallbacks (arrows navigate menus;
# mouse/right-stick aims), so a rebind can never strand a player with no way to steer.
const BIND_DEFAULTS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"aim_up": KEY_UP,
	"aim_down": KEY_DOWN,
	"aim_left": KEY_LEFT,
	"aim_right": KEY_RIGHT,
	"fire": KEY_SPACE,
	"grenade": KEY_SHIFT,
	"roll": KEY_C,
	"interact": KEY_F,
	"revive": KEY_E,
	"buy": KEY_Q,
}

# c1-18: ship-default gamepad button binds (action -> JOY_BUTTON_*) for the discrete
# action verbs. Movement/aim on a pad are the analog STICKS (JOY_AXIS_LEFT/RIGHT) and the
# fire TRIGGER is JOY_AXIS_TRIGGER_RIGHT — those analog inputs are fixed, standard, and
# always live (documented on the rebind screen), so the rebindable pad set is the buttons.
# -1 == UNBOUND. Both pads (P1 dev 0, P2 dev 1) share this one layout.
const PAD_DEFAULTS := {
	"fire": JOY_BUTTON_RIGHT_SHOULDER,
	"grenade": JOY_BUTTON_LEFT_SHOULDER,
	"roll": JOY_BUTTON_B,
	"interact": JOY_BUTTON_X,
	"revive": JOY_BUTTON_Y,
	"buy": JOY_BUTTON_BACK,
}

# c1-18: rebindable MENU-navigation keys. These are read ADDITIVELY by the menu ON TOP of
# the immutable W/S/arrows/Enter/Esc it always honors — so a player CAN remap menu nav, but
# can never lock themselves out of the menus (the hardcoded emergency keys keep working).
# Kept in their OWN map so a menu-key never swaps against a gameplay verb sharing that key.
const MENU_BIND_DEFAULTS := {
	"menu_up": KEY_UP,
	"menu_down": KEY_DOWN,
	"menu_left": KEY_LEFT,
	"menu_right": KEY_RIGHT,
	"menu_confirm": KEY_ENTER,
	"menu_cancel": KEY_ESCAPE,
}


# c1-18: PURE overlay — start from `defaults`, replace only the actions whose `saved`
# value is a real int (null / missing / wrong-type keeps the default). This is the whole
# legacy-save story: a save with no [binds] section (older build) passes all-null and
# comes back exactly at defaults; a save from a newer build with extra keys is ignored
# for actions this build doesn't know. Static so a headless test can pin it directly.
# c1-18: Godot Key enum ceiling for a stored PHYSICAL keycode. Special keys (arrows, Enter,
# F-keys, nav) carry the KEY_SPECIAL bit (0x400000+), so a naive small cap would WRONGLY
# reject a rebound arrow on reload. This covers every real key (well past the special block)
# yet still rejects absurd tampered ints (e.g. 999999999).
const KEYCODE_CEIL := 0x00FFFFFF


static func overlay_binds(defaults: Dictionary, saved: Dictionary, lo := -1, hi := KEYCODE_CEIL) -> Dictionary:
	var out := defaults.duplicate()
	for a in defaults:
		var v: Variant = saved.get(a, null)
		# Validate PER BINDING TYPE: keyboard/menu pass lo=0 (nonnegative keycodes, incl. the
		# 0x400000+ special block), gamepad passes lo=-1/hi=JOY_BUTTON_MAX-1 (valid buttons,
		# -1 == UNBOUND). Anything else (null, wrong type, a corrupt/out-of-range int from a
		# tampered save) keeps the ship default, so a bad value can't produce a broken binding.
		if typeof(v) == TYPE_INT and int(v) >= lo and int(v) <= hi:
			out[a] = int(v)
	return out


# c1-18: PURE swap-resolve — bind `action` to `code` in a COPY of `binds` and return
# {"binds": new_map, "swapped": other_or_empty}. A non-clear code already held by another
# verb SWAPS: that verb inherits the key `action` gave up, so no two verbs ever collide
# (a silent duplicate leaves one verb un-pressable or double-fires two). A clear (kb 0 /
# pad -1) never swaps — any number of verbs may sit UNBOUND. Static + testable.
static func apply_bind(binds: Dictionary, action: String, code: int, unbound: int) -> Dictionary:
	var out := binds.duplicate()
	var swapped := ""
	if code != unbound:
		var old := int(out.get(action, unbound))
		for other in out:
			if other != action and int(out[other]) == code:
				out[other] = old
				swapped = other
	out[action] = code
	return {"binds": out, "swapped": swapped}


# c1-18: the live physical keycode a gameplay verb is bound to (0 == UNBOUND). Falls back
# to the ship default for an unknown action (or an empty map before _load_bests), so the
# _gather_inputs reads can never index a missing key. is_physical_key_pressed(0) is always
# false, so an UNBOUND verb simply reads as never-pressed on the keyboard.
func bind(action: String) -> int:
	return int(_binds.get(action, BIND_DEFAULTS.get(action, 0)))


# c1-18: the pad button a verb is bound to on `device` (0 == P1, 1 == P2; -1 == UNBOUND) —
# the display read the rebind screen shows for the GAMEPAD tab. Mirrors bind() for keyboard.
func pad_bind(action: String, device := 0) -> int:
	return int(_pad_binds[device].get(action, PAD_DEFAULTS.get(action, -1)))


# c1-18: the physical keycode a rebindable MENU-navigation action is bound to (the menu
# reads this ADDITIVELY over its immutable hardcoded keys). 0 == UNBOUND.
func menu_bind(action: String) -> int:
	return int(_menu_binds.get(action, MENU_BIND_DEFAULTS.get(action, 0)))


# c1-18: rebind one MENU-navigation action (0 to clear) and persist. Same swap rule, but
# within the menu-key map only (never collides with a gameplay verb sharing the key).
# c1-18: the IMMUTABLE menu-nav role a physical key always serves (or "" for none) — the
# hardcoded emergency fallback keys. A menu action bound to a key whose fixed role differs
# would fire two menu commands on one press. Shared by the capture-time reject and the
# post-swap sanitize below (single source, so the two agree).
static func immutable_menu_role(pk: int) -> String:
	match pk:
		KEY_W, KEY_UP: return "menu_up"
		KEY_S, KEY_DOWN: return "menu_down"
		KEY_A, KEY_LEFT: return "menu_left"
		KEY_D, KEY_RIGHT: return "menu_right"
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: return "menu_confirm"
		KEY_ESCAPE: return "menu_cancel"
	return ""


func rebind_menu_nav(action: String, keycode: int) -> String:
	if not MENU_BIND_DEFAULTS.has(action):
		return ""
	var res := apply_bind(_menu_binds, action, keycode, 0)
	_menu_binds = res["binds"]
	# A SWAP can hand the displaced action the key `action` gave up. If that key is an
	# immutable menu key for a DIFFERENT role, the displaced action would trigger two menu
	# commands on one press — so UNBIND it instead (its immutable fallback still navigates).
	var swapped: String = res["swapped"]
	if swapped != "":
		var role := immutable_menu_role(int(_menu_binds[swapped]))
		if role != "" and role != swapped:
			_menu_binds[swapped] = 0
	_persist({"menubinds": _menu_binds})
	return swapped


# c1-18: is the pad button bound to `action` currently held on `device`? -1 (UNBOUND)
# reads as never-pressed. Each player reads its own per-device layout (P1 _pad_binds[0] / P2 [1]).
func pad_pressed(device: int, action: String) -> bool:
	# Each player reads its OWN layout, so P1 and P2 can hold different buttons for the verb.
	var b := int(_pad_binds[device].get(action, PAD_DEFAULTS.get(action, -1)))
	return b >= 0 and Input.is_joy_button_pressed(device, b)


# c1-18: rebind one KEYBOARD verb to a physical keycode (0 to clear) and persist immediately
# (same write-through the settings toggles use). Ignores unknown actions. Returns the verb
# it SWAPPED with (or "") so the UI can surface the swap. See apply_bind for the swap rule.
func rebind(action: String, keycode: int) -> String:
	if not BIND_DEFAULTS.has(action):
		return ""
	var res := apply_bind(_binds, action, keycode, 0)
	_binds = res["binds"]
	_persist({"binds": _binds})
	return res["swapped"]


# c1-18: rebind one GAMEPAD verb on `device` (0 == P1, 1 == P2) to a button (-1 to clear) and
# persist THAT player's section only ([padbinds] / [padbinds2]) — swaps stay within the one
# player's layout, so remapping P2 never disturbs P1. Same swap rule.
func rebind_pad(action: String, button: int, device := 0) -> String:
	if not PAD_DEFAULTS.has(action):
		return ""
	var res := apply_bind(_pad_binds[device], action, button, -1)
	_pad_binds[device] = res["binds"]
	_persist({("padbinds" if device == 0 else "padbinds2"): _pad_binds[device]})
	return res["swapped"]


# c1-18: RESET CONTROLS — revert every verb (keyboard AND BOTH gamepads AND menu keys) to its
# ship default and persist every section. Also the target of the F10 global recovery gesture,
# so a player who rebinds themselves into a corner is one keypress from a clean slate.
func reset_binds() -> void:
	_binds = BIND_DEFAULTS.duplicate()
	_pad_binds = [PAD_DEFAULTS.duplicate(), PAD_DEFAULTS.duplicate()]
	_menu_binds = MENU_BIND_DEFAULTS.duplicate()
	_persist({"binds": _binds, "padbinds": _pad_binds[0], "padbinds2": _pad_binds[1], "menubinds": _menu_binds})


func _save_settings() -> void:
	# Persist only the [settings] keys; load-then-set so we never clobber
	# [best]/[hall]/[seen]. Called from the pause-menu a11y/audio toggles.
	_persist({"settings": {
		"colorblind": colorblind,
		"assist": _assist,
		"reduce_motion": _motion < 0.5,
		"rumble": _rumble_on,
		"swap_sticks": _swap_sticks[0],
		"swap_sticks_p2": _swap_sticks[1],
		"sfx_vol": _bus_vol("SFX"),
		"music_vol": _bus_vol("Music"),
		"fullscreen": _fullscreen,
		"window_scale": _win_scale,
	}})


# c1-09: apply a [settings] dict onto the live fields — the SINGLE place values
# flow into the game, shared by _reset_settings and the fresh-install path in
# _load_bests, so SETTINGS_DEFAULTS is authoritative everywhere and no field
# initializer can drift from it. Does not persist (callers decide).
func _apply_settings(d: Dictionary) -> void:
	colorblind = d["colorblind"]
	_assist = d["assist"]
	_motion = 0.0 if d["reduce_motion"] else 1.0
	_rumble_on = d["rumble"]
	# .get: a save predating the option (or its per-player split) lands each pad at OFF.
	# Assigned per-index (not a fresh literal) so the typed Array[bool] property is preserved.
	_swap_sticks[0] = bool(d.get("swap_sticks", false))
	_swap_sticks[1] = bool(d.get("swap_sticks_p2", false))
	_set_bus_vol("SFX", d["sfx_vol"])
	_set_bus_vol("Music", d["music_vol"])
	_fullscreen = d["fullscreen"]
	# .get: saves predating c1-19 land at the 2x ship default. Store the PREFERENCE sane-capped
	# (NOT clamped to the current monitor) so a scale saved on a bigger display survives a load on
	# a smaller one; _apply_windowed_scale sizes the window to the live per-monitor fit.
	_win_scale = clampi(int(d.get("window_scale", 2)), 1, WIN_SCALE_MAX)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED)
	if not _fullscreen:
		_apply_windowed_scale()
	# c1-09: rebake the cursor to the new window size here too — RESET DEFAULTS switches
	# display mode through this path, and without this it left the cursor scaled for the
	# old size (the F11/Alt+Enter shortcut always rebaked; reset used to skip it).
	call_deferred("_bake_cursor")


# c1-09: the SINGLE fullscreen flip — shared by the F11/Alt+Enter shortcut and the
# OPTIONS DISPLAY row, so the on-screen toggle and the hotkey stay one behavior
# (persist + cursor rebake included). Lets DISPLAY be reviewed AND changed on the
# dedicated settings screen, not only via the hidden shortcut.
func _toggle_fullscreen() -> void:
	_prog_resize = true   # a programmatic mode change — ignore the transition's resize events until settled
	_fullscreen = not _fullscreen
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN
		if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not _fullscreen:
		# Returning to windowed restores the chosen integer scale — RE-CLAMPED to the current
		# monitor first, so a scale carried in from a larger display (save or F11 round-trip)
		# can never restore an oversized window that overflows the smaller screen. This arms a
		# windowed settle chain that clears _prog_resize once the transition completes.
		_apply_windowed_scale()
	else:
		# Entering fullscreen applies NO windowed fit, so arm a generation-tagged settle chain anyway:
		# its fullscreen branch (reached from _process next frame) resets the counters AND clears
		# _prog_resize, so the guard can never stay stuck true after a bare F11-in.
		_settle_gen += 1
		_settle_active = true
	call_deferred("_bake_cursor")   # cursor scale follows the new window size
	_save_settings()


# c1-19: largest integer window scale the current display can actually hold (min 1),
# so the OPTIONS control never offers a window that won't fit. Sized against the WORK
# area (screen_get_usable_rect excludes the taskbar / macOS menu bar) MINUS the window
# chrome (title bar + borders) — a raw-screen divide advertised e.g. 2x on a 720p display
# that the decorated 1280x720 window then overflowed. The live decoration delta is only
# trustworthy while WINDOWED (it reads 0 in fullscreen); it's cached into _deco_reserve
# there and reused when queried in fullscreen, so the ceiling computed mid-fullscreen still
# leaves room for the chrome that returns on the way out.
func _max_win_scale() -> int:
	return max_scale_for(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size, _deco_reserve)


# c1-19: the ceiling math, pure + static so it's headless-assertable with SYNTHETIC work-area +
# chrome-reserve pairs — e.g. a 1920x1080 work area caps at 2x with a 40px fallback reserve but at 3x
# once a borderless window's real zero reserve is measured. usable == 0 (no display metrics) returns
# the full 3x ladder. Capped at WIN_SCALE_MAX so even an 8K display can't offer past the declared cap.
static func max_scale_for(usable: Vector2i, reserve: Vector2i) -> int:
	if usable.x <= 0 or usable.y <= 0:
		return 3
	return clampi(mini((usable.x - reserve.x) / 640, (usable.y - reserve.y) / 360), 1, WIN_SCALE_MAX)


# c1-19: cache the real window chrome from the live delta. The cache is only ever written from
# _settle_window (a DEFERRED step that runs a frame after a windowed mode change), never inline
# in _max_win_scale — so the transient zero the OS reports in the frame right after leaving
# fullscreen (decorated size == client size until the title bar is re-attached) can't clobber a
# good value. Once settled, a genuinely borderless / client-side-decoration window reads a stable
# zero, which is valid and stored as-is.
func _measure_decorations(accept_zero := false) -> void:
	if _fullscreen:
		return
	var raw := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var live := Vector2i(maxi(0, raw.x), maxi(0, raw.y))
	# c1-19: NEVER clobber a known-good nonzero reserve with a TRANSIENT zero. Right after leaving
	# fullscreen the OS reports decorated size == client size for a frame or two (the title bar has
	# not re-attached yet); committing that 0 would drop the chrome reserve and later let
	# _max_win_scale offer / restore an OVERSIZED scale. A zero is therefore committed only when it
	# is TRUSTED: either there is no prior reserve, or `accept_zero` says a stability gate has
	# already seen this same zero across consecutive frames (a genuinely borderless / client-side-
	# decorated window). That way a real borderless window still drops the 40px fallback — a
	# transient zero can't clobber, and a stable zero isn't rejected forever. Only _settle_window,
	# which owns the multi-frame stability check, ever passes accept_zero.
	if live == Vector2i.ZERO and _deco_reserve != Vector2i.ZERO and not accept_zero:
		return
	_deco_reserve = live


# c1-19: run one frame AFTER a windowed mode change, once the OS has settled the decorated
# dimensions — re-measure the chrome, then RE-FIT + RECENTER: the boot/seed decoration estimate
# may have mis-sized the window, so resize to the effective scale recomputed from the real chrome
# and center on that FINAL decorated footprint (the inline pass ran before the title bar
# re-attached, so its size/offset could be a few px off).
# c1-19: ONE settle sample — run once per frame by _process while _settle_active, never self-requeued
# via call_deferred (which can fire multiple times in a single idle flush and collapse the per-frame
# stability gate). Each invocation takes exactly one decoration reading on a distinct rendered frame.
func _settle_window(gen := 0) -> void:
	# Drop a STALE sample: if a newer change bumped _settle_gen, this belongs to a superseded chain —
	# bail so it can't resize/recenter over the newer choice or corrupt the live chain's counters.
	# (gen 0 default = a direct/legacy call adopts the current chain.)
	if gen != 0 and gen != _settle_gen:
		return
	if _fullscreen:
		_settle_tries = 0
		_settle_last_deco = Vector2i(-1, -1)
		_settle_zero_streak = 0
		_prog_resize = false   # entered fullscreen; resize events are already guarded by _fullscreen
		_settle_active = false
		return
	# c1-19: robust to window-manager latency — the decorated size may not settle in a SINGLE
	# deferred frame (a slow X11 / Wayland compositor re-attaches the title bar a frame or two later,
	# re-measuring the chrome and thus the fit). SAMPLE the live decoration each deferred frame and
	# treat a NONZERO reading as trusted immediately (real chrome). A ZERO is only trusted once it has
	# HELD for SETTLE_ZERO_FRAMES consecutive frames: the fullscreen->windowed transition can report a
	# decorated==client (zero) size for SEVERAL frames while the title bar re-attaches, so a mere
	# "same value twice" gate could freeze that transient zero and drop a valid chrome reserve. By
	# demanding a long zero streak, the real chrome always reappears first (resetting the streak), and
	# the last known-good NONZERO reserve is retained until the transition is definitively complete.
	# A genuinely borderless window reads zero every frame and so still settles (streak reaches the
	# bar). _measure_decorations then commits, itself guarded so a transient zero can't clobber a good
	# reserve unless this streak-based accept_zero vouches for it.
	var raw := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var live := Vector2i(maxi(0, raw.x), maxi(0, raw.y))
	if live == Vector2i.ZERO:
		_settle_zero_streak += 1
	else:
		_settle_zero_streak = 0
	var deco_stable := live == _settle_last_deco
	_settle_last_deco = live
	# at_target is judged against the target implied by the CURRENT reserve (before this sample's
	# measurement) — that's the size the previous iteration aimed the window at.
	var pre_px := Vector2i(640 * _win_scale_norm(), 360 * _win_scale_norm())
	var at_target := DisplayServer.window_get_size() == pre_px
	# A ZERO reserve is trusted ONLY when it has held SETTLE_ZERO_FRAMES consecutive frames AND the
	# window is already AT its final target size — i.e. the resize/transition is definitively over.
	# Requiring at_target too means a long-but-transient zero seen WHILE the window is still resizing
	# (mid fullscreen->windowed, before the client reaches the target) can't be committed and offer an
	# oversized window; only a genuinely borderless window, settled at its size, drops the reserve.
	var accept_zero := _settle_zero_streak >= SETTLE_ZERO_FRAMES and at_target
	var prev_reserve := _deco_reserve
	_measure_decorations(accept_zero)
	var reserve_changed := _deco_reserve != prev_reserve
	# Recompute the target AFTER measuring: committing the reserve (e.g. accepting a borderless zero,
	# dropping the 40px fallback) can RAISE the effective scale, so the pre-measurement `want` is now
	# stale. Aim at the POST-measurement target and, whenever the reserve just changed, force one more
	# iteration so the new effective scale is actually applied and verified — never finish at the old
	# (smaller) scale the reserve implied before it was updated.
	var want := _win_scale_norm()
	var px := Vector2i(640 * want, 360 * want)
	var now_at_target := DisplayServer.window_get_size() == px
	# The chrome is "done" only when a nonzero reserve was committed OR a settled zero was trusted —
	# keep retrying (re-fitting to the freshly measured chrome) until that AND the client size matches
	# the POST-measurement target AND the reserve has stopped changing, bounded by SETTLE_MAX_TRIES.
	var chrome_done := live != Vector2i.ZERO or accept_zero
	if (not (deco_stable and chrome_done and now_at_target) or reserve_changed) and _settle_tries < SETTLE_MAX_TRIES:
		if not now_at_target:
			DisplayServer.window_set_size(px)   # re-fit to the scale recomputed from the freshly measured chrome
		_settle_tries += 1
		return   # NOT done — _process runs the next sample on the next distinct frame (no self-requeue)
	# Settled (stable chrome, at the post-measurement target, reserve steady) or hit the retry cap.
	_settle_tries = 0
	_settle_last_deco = Vector2i(-1, -1)
	_settle_zero_streak = 0
	_settle_active = false
	_prog_resize = false   # transition definitively complete — a genuine user drag from here IS honored
	_center_window()


# c1-19: slide the window fully back onto the current work area WITHOUT resizing or recentering —
# used when a monitor / work-area change leaves a correctly-sized window hanging off the edge, so
# the player's placement is preserved as much as possible (only the overflow is corrected).
func _clamp_window_on_screen() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var deco := DisplayServer.window_get_size_with_decorations()
	var pos := DisplayServer.window_get_position()
	var np := clamp_pos(pos, usable.position, usable.size, deco)
	if np != pos:
		DisplayServer.window_set_position(np)


# c1-19: slide a decorated window fully onto the work area, preserving placement where it already
# fits (only the overflow is corrected). Pure + static so the off-edge / taskbar-inset / multi-
# monitor-offset math is headless-assertable without a real display.
static func clamp_pos(pos: Vector2i, usable_pos: Vector2i, usable_size: Vector2i, deco: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(pos.x, usable_pos.x, maxi(usable_pos.x, usable_pos.x + usable_size.x - deco.x)),
		clampi(pos.y, usable_pos.y, maxi(usable_pos.y, usable_pos.y + usable_size.y - deco.y)))


# c1-19: top-left position that centers a DECORATED footprint (client + title bar/borders) inside a
# work area — so the whole window, chrome included, lands on-screen and clear of the taskbar/menu
# bar. Pure + static so centering is headless-assertable against synthetic taskbar/monitor rects.
static func center_pos(usable_pos: Vector2i, usable_size: Vector2i, deco: Vector2i) -> Vector2i:
	return usable_pos + (usable_size - deco) / 2


# c1-19: the ONE place the windowed size is applied — sizes the window to the EFFECTIVE scale
# (the stored preference clamped to what the CURRENT monitor fits) WITHOUT mutating the stored
# preference, so every path back to windowed (load, RESET, F11 out, a scale step, a monitor hop)
# fits the live display while a scale chosen on a bigger monitor survives to be restored later.
func _apply_windowed_scale() -> void:
	_prog_resize = true   # our own resize — suppress the size-change notifications it emits until the settle completes
	var eff := _win_scale_norm()
	DisplayServer.window_set_size(Vector2i(640 * eff, 360 * eff))
	_center_window()
	# Start a FRESH settle chain: bump the generation (cancelling any in-flight chain from a previous
	# change) and reset its counters, then arm it. _process advances it one sample per rendered frame
	# until the chrome + client size stabilize (re-measure chrome, re-fit, recenter), then clears the
	# programmatic-resize guard.
	_settle_gen += 1
	_settle_tries = 0
	_settle_last_deco = Vector2i(-1, -1)
	_settle_zero_streak = 0
	_settle_active = true


# c1-19: the EFFECTIVE windowed scale actually applied to the window — the stored PREFERENCE
# clamped to the CURRENT monitor's ceiling. The window is always sized to this; the preference
# (_win_scale) is left untouched so a smaller monitor shrinks the view without destroying the
# choice. The OPTIONS row label and the ladder step both read through here, so the on-screen
# control always sits on the real ceiling (a stale over-max preference can't wedge ►).
func _win_scale_norm() -> int:
	return clampi(_win_scale, 1, _max_win_scale())


# c1-19: apply an absolute windowed integer scale — the ONE place window size changes,
# shared by the OPTIONS WINDOW SCALE row (◄/► and Enter). Clamped to the display's fit.
# Picking a scale implies WINDOWED: fullscreen has no visible window to size, so a step
# drops out of it into the chosen clean multiple. Returns true if the value moved.
func _set_win_scale(s: int) -> bool:
	var ns := clampi(s, 1, _max_win_scale())
	if ns == _win_scale and not _fullscreen:
		return false
	_win_scale = ns
	_fullscreen = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_windowed_scale()
	call_deferred("_bake_cursor")   # cursor scale follows the new window size
	_save_settings()
	return true


# c1-19: change the STORED windowed-scale PREFERENCE without leaving fullscreen or resizing anything
# — so the DISPLAY WINDOW SCALE row stays a LIVE control while fullscreen instead of a dead, ignored
# row. The chosen value is what applies the moment you drop back to windowed (via the FULLSCREEN
# toggle or F11). Clamped to the current effective ceiling and persisted; returns true if it moved.
func _set_win_scale_pref(s: int) -> bool:
	var ns := clampi(s, 1, _max_win_scale())
	if ns == _win_scale:
		return false
	_win_scale = ns
	_save_settings()
	return true


func _center_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return   # no display metrics (headless) — leave the position as-is
	# Center the DECORATED footprint (client + title bar/borders) inside the WORK area, so the
	# whole window — chrome included — lands on-screen and clear of the taskbar/menu bar. Godot's
	# window_get_position / window_set_position are decorated-origin on our desktop targets, so
	# centering the decorated footprint is correct there; the final clamp_pos is a safety net so
	# that even where the position is treated as a client origin (leaving the title bar off the top)
	# the whole decorated box is still slid fully onto the work area rather than trusting the split.
	var deco := DisplayServer.window_get_size_with_decorations()
	var centered := center_pos(usable.position, usable.size, deco)
	DisplayServer.window_set_position(clamp_pos(centered, usable.position, usable.size, deco))


func _reset_settings() -> void:
	# c1-09: RESET DEFAULTS reverts EVERY persisted setting to its SETTINGS_DEFAULTS
	# ship value — the ONE authoritative table load and fresh-install also read, so it
	# can never miss one — and DISPLAY mode (fullscreen) is included, not exempted, so
	# "DEFAULTS RESTORED" is literally true. The OPTIONS header shows the DISPLAY state
	# (via a11y_summary), so restoring it to WINDOWED is a VISIBLE change on the same
	# screen, not a silent flip — which is why resetting it is honest rather than jarring.
	_apply_settings(SETTINGS_DEFAULTS)
	_save_settings()


func _bus_vol(name: String) -> int:
	# SFX/MUSIC level in 0..10 steps. The AudioServer IS the state: mute carries
	# the 0, volume_db carries the 1..10 level. One model: Enter and Left/Right all
	# move this single 0..10 value (0 == MUTED), never a mute toggle — stepping down
	# to 0 mutes, stepping back up resumes at 1 (a normal +1 step off the floor, not
	# a restore of the pre-mute level; the retained volume_db only survives a mute
	# that is un-set OUTSIDE the stepper, e.g. a settings reload).
	var b := AudioServer.get_bus_index(name)
	if AudioServer.is_bus_mute(b):
		return 0
	return clampi(int(round(db_to_linear(AudioServer.get_bus_volume_db(b)) * 10.0)), 1, 10)


const _SFX_SLAVED_BUSES: Array[String] = ["UI", "VO"]   # a3-16: jingle UI + radio VO both ride the one SFX knob


func _set_bus_vol(name: String, v: int) -> void:
	v = clampi(v, 0, 10)
	var b := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(b, v == 0)
	if v > 0:
		AudioServer.set_bus_volume_db(b, linear_to_db(v / 10.0))
	if name == "SFX":
		# a3-16: the jingle "UI" bus AND the radio "VO" bus both slave to the SFX
		# control — one user-facing knob for every non-music voice/cue. The radio VO
		# sent straight to Master before, so muting SFX still left the Commander blaring.
		for slaved in _SFX_SLAVED_BUSES:
			var s := AudioServer.get_bus_index(slaved)
			if s == -1:
				continue
			AudioServer.set_bus_mute(s, v == 0)
			if v > 0:
				AudioServer.set_bus_volume_db(s, linear_to_db(v / 10.0))


func _record_run() -> void:
	# Bank the finished run into the top-8 Hall of Fame (by score).
	var opened := 0
	for g in sim.gates:
		if g["open"]:
			opened += 1
	var rr := _run_rank()   # bank the earned grade/title with the run so the Hall can show it
	var entry := {"score": sim.score, "mode": sim.mode, "wave": sim.wave,
		"sector": mini(opened + 1, 5), "dist": -Fixed.to_int(sim.camera_top) / 10,
		"streak": _run_best_streak, "won": sim.victory, "daily": _daily, "assist": _assist,
		"grade": rr.grade, "title": rr.title, "rescues": _run_rescues,
		"hid": _hall_seq}
	_hall_seq += 1
	hall.append(entry)
	hall_latest = entry   # keep the ref so the Hall can highlight this run wherever it ranks
	hall.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	# Keep a deep board (many pages) — the Hall now pages instead of hard-capping
	# at one screen, so a mid-tier run you just finished still has a place to land.
	# The just-banked run is PINNED even when it ranks past the cap (see _hall_capped):
	# the board is why you opened the Hall, so it must always be reachable. The cap is
	# single-sourced from GameMenu.HALL_KEEP so the retention limit the Hall STATES on
	# screen and the limit it ENFORCES here can never drift apart.
	hall.assign(_hall_capped(hall, hall_latest, GameMenu.HALL_KEEP))
	_life_runs += 1
	_life_kills += _run_kills
	if sim.victory:
		_life_wins += 1
	# One load+save for hall/life/best together — this lands on the debrief
	# frame, and each _persist() is a full read/write/backup/rename dance.
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("hall", "runs", hall)
	cf.set_value("life", "runs", _life_runs)
	cf.set_value("life", "kills", _life_kills)
	cf.set_value("life", "wins", _life_wins)
	cf.set_value("best", "score", best_score)
	cf.set_value("best", "wave", best_wave)
	cf.set_value("best", "dist", best_dist)
	cf.set_value("seen", "hints", _seen)
	_best_dirty = false
	_seen_dirty = false
	_save_cfg(cf)


static func _hall_capped(sorted_runs: Array, latest: Dictionary, cap: int) -> Array:
	# Trim a score-sorted board to `cap`, but NEVER drop the just-banked `latest` run
	# — it is the reason the player opened the Hall. Identity is by unique "hid", not
	# value: two runs with the same score/sector are common and Array.has() (deep ==)
	# would wrongly treat a value-twin as the latest and discard the real one.
	# A pinned over-cap run is tagged "over_cap" so the view flags its rank as 41+
	# (uncertain) instead of claiming an exact slot that discarded runs may outrank.
	# Clear any stale over_cap first, then set it on the ONE pinned run below — a flag
	# is a fact about THIS trim, not a permanent brand. Without this, a run once pinned
	# past the cap would keep flashing "OUTSIDE TOP N" (its "--" dash) even after it
	# legitimately climbs back inside the retained set on a later bank.
	for r in sorted_runs:
		r.erase("over_cap")
	if sorted_runs.size() <= cap:
		return sorted_runs
	var kept := sorted_runs.slice(0, cap)
	var lid: int = latest.get("hid", -1)
	for r in kept:
		if int(r.get("hid", -2)) == lid:
			return kept   # latest earned its place inside the cap on merit
	latest["over_cap"] = true
	kept.append(latest)
	return kept


func _check_smoke_edges() -> void:
	# Concealment ending silently got players shot the instant the shroud
	# thinned — a falling-edge tick + EXPOSED pop closes the window fairly.
	# (The rising edge is the pickup itself, which already celebrates.)
	for i in sim.players.size():
		if i >= _smoke_prev.size():
			break
		var st: int = sim.players[i]["smoke_ticks"]
		if _smoke_prev[i] > 0 and st == 0 and sim.players[i]["alive"]:
			# "pickup" voice, NOT "alarm": these are SELF-status ticks, and they sat
			# 0.1-0.2 pitch from drone_windup (1.9) / flash_recover (2.4) on the same
			# alarm timbre — a "my cover is fading" cue was indistinguishable from an
			# "incoming threat" cue demanding the opposite response. alarm = threat, only.
			_sfx.play("pickup", -14.0, 0.7)
			_fx.append({"x": sim.players[i]["x"], "y": sim.players[i]["y"], "t": 0.0,
				"kind": "floattext", "rate": 0.03, "text": "EXPOSED", "col": Color(1.0, 0.6, 0.4)})
		elif _smoke_prev[i] > 60 and st <= 60 and sim.players[i]["alive"]:
			# Pre-expiry warning (6-vote panel item): one soft tick a second out,
			# paired with the shroud's blink — a 55t sniper paint can begin the
			# frame smoke clears, so "about to be exposed" must land in advance.
			_sfx.play("pickup", -18.0, 0.9)
		_smoke_prev[i] = st


func _hint(id: String, text: String, urgent := false) -> void:
	# Fire a just-in-time onboarding cue the FIRST time ever, then never again.
	# Never during attract mode — the demo bot would burn every hint to disk
	# before the player ever plays.
	if _menu.mode == GameMenu.Mode.TITLE:
		return
	if _seen.get(id, false):
		return
	_seen[id] = true
	if urgent:
		# Queue-jump (8-of-9 panel consensus on toast priority): a time-critical
		# cue — a downed buddy's revive, an escaping ransom — must not wait ~3s
		# behind each queued teach line. Jump the queue AND fast-out whatever
		# is currently showing (0.25 ≈ half a second of fade left).
		_hint_queue.push_front(text)
		_hint_t = minf(_hint_t, 0.25)
	else:
		_hint_queue.append(text)
	# No inline disk write: hints fire at the hottest moments (first affordable
	# buy mid-combat, urgent revive cues) and _persist is a synchronous 4-op
	# load/save/backup/rename — the same ~1-5ms frame spike deleted for bests.
	# Flushed in _flush_bests/_record_run; a crash merely re-shows a hint.
	_seen_dirty = true


func _track_bests() -> void:
	_run_best_streak = maxi(_run_best_streak, _kill_streak)
	# Supply-wheel discoverability: the first time the chest can afford the
	# cheapest buy, nudge the player toward the hold-to-open wheel.
	if sim.war_chest >= SimWorld.SHOP_AMMO_COST:
		_hint("supply", "HOLD [%s] FOR THE SUPPLY WHEEL" % (Art.pad_label("wheel") if Art.use_pad else "Q"))
	# Airstrike went wheel-only this patch — veterans who knew the ground-drop
	# path get one teaching line the first time the chest can afford it.
	if sim.war_chest >= SimWorld.SHOP_AIRSTRIKE_COST:
		_hint("airstrike_wheel", "AIRSTRIKES NOW LIVE IN THE SUPPLY WHEEL — HOLD [%s]"
			% (Art.pad_label("wheel") if Art.use_pad else "Q"))
	# After-Action Debrief trigger: victory, or all players down for ~2.5s
	# with no rescue coming (last stand, or broke with no chest).
	if not sim._all_players_down():
		_down_frames = 0
	else:
		_down_frames += 1
	if sim.victory or sim.wiped or (_down_frames > 150 and sim.last_stand):
		if not _debrief:
			_record_run()   # bank this run into the Hall of Fame once
			if not _replay_saved and _recorder != null:
				# Stringifying a whole run's input log is the biggest one-frame
				# stall in the view — push it to a worker so the debrief card
				# doesn't hitch. Shallow-duplicate the outer frames array: the
				# main thread may still append, but per-frame arrays are
				# immutable once recorded, so the snapshot is race-free.
				var snap := _recorder.to_dict()
				snap["frames"] = _recorder.frames.duplicate()
				# Retire the previous run's write first: the pool only frees a
				# task record inside wait_for_task_completion, and two writers
				# on the same path must never interleave. Long done → ~0ms.
				if _replay_task != -1:
					WorkerThreadPool.wait_for_task_completion(_replay_task)
				_replay_task = WorkerThreadPool.add_task(
					Replay.save_dict.bind(snap, "user://last_run.replay"))
				_replay_saved = true
		_debrief = true
	# NEW RECORD moment: the instant this run's score passes the standing best.
	if not _record_fired and best_score > 0 and sim.score > best_score:
		_record_fired = true
		_show_banner("NEW RECORD!")
		_sfx.play("wave_clear", -3.0, 1.15)
	# Ratchet the records; write at most once a second when something moved.
	if sim.score > best_score:
		best_score = sim.score
		_best_dirty = true
	if sim.mode == "endless" and sim.wave > best_wave:
		# DEEPEST WAVE milestone: the first wave this run pushes past the standing
		# best (from prior runs) is a real record — fire it once. best_wave>0 skips
		# the every-wave noise on a first-ever endless run (mirrors the score guard).
		if not _deep_fired and best_wave > 0:
			_deep_fired = true
			_show_banner("DEEPEST WAVE %d" % sim.wave)
			_sfx.play("wave_clear", -4.0, 1.25)
		best_wave = sim.wave
		_best_dirty = true
	var dist := -Fixed.to_int(sim.camera_top) / 10
	if sim.mode == "campaign" and dist > best_dist:
		best_dist = dist
		_best_dirty = true
	# No mid-run disk write: the old once-a-second _persist() here was a full
	# ConfigFile load+save+copy+rename on the main thread during the hottest
	# play (a ~1 Hz frame spike). The ratchet stays in memory; it hits disk in
	# _record_run() at the debrief and _flush_bests() on reset/exit.


func _show_banner(text: String, col := Color(1.0, 0.92, 0.55), icon := "") -> void:
	# No dupe-stacking: PERFECT DODGE! can re-fire every 24 frames and used to
	# queue itself several deep. Icon: threat callouts only — every banner
	# wearing a badge would dilute the alarm grammar.
	if not _banners.is_empty() and _banners.back()["text"] == text:
		return
	_banners.append({"text": text, "t": 1.0, "col": col, "icon": icon})


func _check_dry_throw(inputs: Array[SimInput]) -> void:
	# Empty-grenade click: pressing grenade at 0 ammo on foot does nothing in
	# the sim (grenades are the ONLY armor-cracker, so silent = maximally
	# confusing). View-side click keeps it golden-safe. Throttled like dry-fire.
	if Engine.get_physics_frames() - _dry_grenade_frame < 14:
		return
	for pi in mini(inputs.size(), sim.players.size()):
		var p := sim.players[pi]
		if inputs[pi].grenade and p["alive"] and p["in_tank"] < 0 \
				and p["grenade_ammo"] == 0 and p["grenade_cd"] == 0:
			_dry_grenade_frame = Engine.get_physics_frames()
			_sfx.play("tank_board", -12.0, 2.4)
			_grenade_dry[pi] = 12   # HUD grenade pip flashes red
			return


func _check_near_miss() -> void:
	# A crack past the ear when an enemy round barely misses a live player —
	# rewards the dodge, amplifies one-hit tension. Throttled so it can't spam.
	# Perfect Dodge: a bullet passing through a player DURING roll i-frames would
	# have killed them — the most skill-expressive save, and it was fully silent.
	# Own throttle, checked before the whiz gate so a recent whiz can't swallow it.
	# The dodge scan is dead work outside a roll window (roll_ticks > 0 for
	# only 18 of every ~78 ticks per player) — skip the O(bullets × players)
	# pass entirely unless someone is actually mid-roll.
	var any_roll := false
	for p in sim.players:
		if p["alive"] and p["roll_ticks"] > 0:
			any_roll = true
			break
	if any_roll and Engine.get_physics_frames() - _dodge_frame >= 24:
		for b in sim.enemy_bullets:
			for p in sim.players:
				if not p["alive"] or p["roll_ticks"] == 0:
					continue
				if sim._dist_lte(b["x"], b["y"], p["x"], p["y"], 11 * Fixed.ONE):
					_dodge_frame = Engine.get_physics_frames()
					_show_banner("PERFECT DODGE!", Color(0.5, 0.95, 1.0))
					_hitstop_frames = maxi(_hitstop_frames, 3)
					_sfx.play("buy_grab", -4.0, 1.6)   # a2-16: PERFECT DODGE skill reward (warm grab)
					_fx.append({"x": p["x"], "y": p["y"], "t": 0.0, "kind": "tex",
						"tex": "fx_circle", "sz": 16.0, "grow": 3.0, "fade": 1.8, "rate": 0.04,
						"col": Color(0.5, 0.95, 1.0, 0.7)})
					return
	if Engine.get_physics_frames() - _whiz_frame < 10:
		return
	var near_r := 15 * Fixed.ONE
	for b in sim.enemy_bullets:
		for p in sim.players:
			if not p["alive"] or p["roll_ticks"] > 0:
				continue
			if sim._dist_lte(b["x"], b["y"], p["x"], p["y"], near_r):
				_whiz_frame = Engine.get_physics_frames()
				_sfx.play_at("whiz", _to_screen(b["x"], b["y"]), -13.0, randf_range(0.95, 1.1))
				# Visible graze streak at the miss point so the dodge reads on-screen, not
				# just in the ears — a muted player still sees the round rip past.
				_fx.append({"x": b["x"], "y": b["y"], "t": 0.0, "kind": "tex",
					"tex": "fx_bullettrail", "sz": 11.0, "fade": 2.6, "rate": 0.28,
					"rot": Vector2(b.get("vx", 0), b.get("vy", 0)).angle(),
					"col": Color(1.0, 0.96, 0.72, 0.85)})
				return


func _hit_owner(ex: int, ey: int) -> int:
	# View-only shot attribution: the live player whose gun points nearest the
	# hit takes the reticle confirm, so P2's landed shots pop P2's reticle (not
	# P1's) without touching the checksummed sim. Bullets fly straight along aim,
	# so a hit a few ticks downrange still lines up with the shooter's aim.
	var best := 0
	var best_dot := -2.0
	for pi in sim.players.size():
		var pl: Dictionary = sim.players[pi]
		if not pl["alive"]:
			continue
		var ax := float(pl["aim_x"])
		var ay := float(pl["aim_y"])
		var dx := float(ex - pl["x"])
		var dy := float(ey - pl["y"])
		var alen := sqrt(ax * ax + ay * ay)
		var dlen := sqrt(dx * dx + dy * dy)
		if alen < 1.0 or dlen < 1.0:
			continue
		var d := (ax * dx + ay * dy) / (alen * dlen)
		if d > best_dot:
			best_dot = d
			best = pi
	return best


func _mark_hit_dir(px: int, py: int, pidx: int) -> void:
	# Point the damage wedge at the nearest lethal source at hit time — the
	# "where did that come from?" answer a one-hit game owes the player.
	var best := 1 << 62
	var dir := Vector2.ZERO
	var src := ""
	for b in sim.enemy_bullets:
		var d: int = (b["x"] - px) * (b["x"] - px) + (b["y"] - py) * (b["y"] - py)
		if d < best:
			best = d
			dir = Vector2(b["x"] - px, b["y"] - py)
			src = "GUNFIRE"
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var d2: int = (e["x"] - px) * (e["x"] - px) + (e["y"] - py) * (e["y"] - py)
		if d2 < best:
			best = d2
			dir = Vector2(e["x"] - px, e["y"] - py)
			src = String(e["kind"]).to_upper()
	# Mortar strikes and the colossus crush kill too — a wedge that only
	# scanned bullets/infantry pointed at the wrong threat for those deaths.
	for s in sim.strikes:
		var ds: int = (s["x"] - px) * (s["x"] - px) + (s["y"] - py) * (s["y"] - py)
		if ds < best:
			best = ds
			dir = Vector2(s["x"] - px, s["y"] - py)
			src = "MORTAR FIRE"
	if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
		var cx: int = sim.colossus["x"] - px
		var cy: int = sim.colossus["y"] - py
		if cx * cx + cy * cy < best:
			dir = Vector2(cx, cy)
			src = "THE COLOSSUS"
	if dir.length() > 1.0:
		_hit_dir = dir.normalized()
		_hit_dir_t = 1.0
		_hit_dir_player = pidx
		if src != "":
			_downed_by = src
		if pidx >= 0 and pidx < _hit_flinch.size():
			_hit_flinch[pidx] -= _hit_dir * 3.0   # shove the body AWAY from the source


static func _boss_music_on(sw: SimWorld) -> bool:
	# a1-15 AUD#7: a boss is ENGAGED — the colossus finale, or a gate boss alive and
	# in view. Static + sim-param so it is directly testable. Drives the boss music.
	if not sw.colossus.is_empty() and sw.colossus.get("alive", false):
		return true
	for g in sw.gates:
		if not g["boss"].is_empty() and g["boss"].get("alive", false) \
				and g["y"] >= sw.camera_top - 100 * Fixed.ONE and g["y"] <= sw.camera_top + SimWorld.VIEW_H:
			return true
	return false


func _update_feel() -> void:
	# Impact envelopes (_trauma/_punch/_kick) HOLD at peak through the hitstop
	# freeze — otherwise the biggest hits (which set the longest freeze) bleed
	# ~85% of their shake+zoom-punch off before the world unfreezes, gutting the
	# springback that should play over the resuming motion.
	if _hitstop_frames == 0:
		_trauma = maxf(0.0, _trauma - 0.03)
	_rear_wedge_t = maxf(0.0, _rear_wedge_t - 1.0 / 60.0)   # c4: rear-warn wedge decay
	# SHOP LOCKED callout (7/9 play-panel): in endless, clearing the wave while
	# the miniboss still flies leaves the shop silently hostage — say it once
	# per boss. Latch resets when the boss dies or the shop actually opens.
	if sim.mode == "endless" and not sim.endless_boss.is_empty() \
			and sim.endless_boss["alive"] and sim.intermission_ticks == 0 \
			and sim.wave_pending == 0 and sim._wave_hostiles_cleared():
		if not _shop_lock_told:
			_shop_lock_told = true
			_show_banner("SHOP LOCKED — DESTROY THE GUNSHIP", Color(1.0, 0.6, 0.3))
	else:
		_shop_lock_told = false
	# NO TARGET feedback (6/9 play-panel): endless has no tanks, so the interact
	# key with no claymore carried was dead input — a quiet receipt instead of
	# silence. View-side edge + 2s cooldown; the sim is untouched.
	_no_target_cd = maxf(0.0, _no_target_cd - 1.0 / 60.0)
	if sim.mode == "endless":
		for i in sim.players.size():
			var np := sim.players[i]
			var n_int := (Input.is_physical_key_pressed(bind("interact")) or pad_pressed(0, "interact")) \
				if i == 0 else pad_pressed(1, "interact")
			if n_int and not _no_target_prev[i] and _no_target_cd <= 0.0 \
					and np["alive"] and np["in_tank"] < 0 and np["claymores"] == 0:
				_no_target_cd = 2.0
				_fx.append({"x": np["x"], "y": np["y"] - 8 * Fixed.ONE, "t": 0.0,
					"kind": "floattext", "rate": 0.02, "size": 8,
					"text": "NO TARGET", "col": Color(0.7, 0.72, 0.66)})
				_sfx.play("deny", -16.0, 1.4)
			_no_target_prev[i] = n_int
	# Impact envelopes decay multiplicatively (fast drop, long tail) so hits snap;
	# linear release reads flat. Floors avoid a lingering near-zero tail.
	_flash_alpha = _flash_alpha * 0.7 if _flash_alpha > 0.01 else 0.0
	_damage_vignette = maxf(0.0, _damage_vignette - 0.02)
	if not _banners.is_empty():
		# Depth-scaled drain: a lone banner keeps its full ~2s, but a backlog
		# fast-forwards — GUNSHIP INBOUND used to surface 6s stale behind
		# PERFECT DODGE! vanity news (4 of 7 lenses flagged the FIFO).
		_banners[0]["t"] -= 0.008 * (1.0 + 0.75 * float(_banners.size() - 1))
		if _banners[0]["t"] <= 0.0:
			_banners.pop_front()
	for _hi in _hitmarker.size():
		_hitmarker[_hi] = _hitmarker[_hi] * 0.6 if _hitmarker[_hi] > 0.01 else 0.0
	_hit_dir_t = maxf(0.0, _hit_dir_t - 0.03)
	if _hitstop_frames == 0:
		_punch = _punch * 0.82 if _punch > 0.002 else 0.0
	_fade = maxf(0.0, _fade - 0.06)
	_duck = maxf(0.0, _duck - 0.05)
	# Concussion haze + heat-warp hold through hit-stop like the other impact
	# envelopes — the longest freezes were bleeding the residual before resume.
	if _hitstop_frames == 0:
		_concussion = _concussion * 0.9 if _concussion > 0.01 else 0.0   # match the multiplicative grammar above
		_blast_warp = _blast_warp * 0.86 if _blast_warp > 0.01 else 0.0
		_water_splash["t"] = maxf(0.0, _water_splash["t"] - 0.03)
	_cinematic = maxf(0.0, _cinematic - 0.004)
	# Debrief/victory card entrance clock: eases 0→1 while a result is showing,
	# snaps back to 0 the moment it isn't (so a restart re-plays the entrance).
	if sim.victory or _debrief:
		_result_t = minf(1.0, _result_t + 0.08)
	else:
		_result_t = 0.0
	_music_hold = maxi(0, _music_hold - 1)
	for _gi in _grenade_dry.size():
		_grenade_dry[_gi] = maxi(0, _grenade_dry[_gi] - 1)
	_hint_t = maxf(0.0, _hint_t - 0.006)
	if _hint_t <= 0.02 and not _hint_queue.is_empty():
		_hint_text = _hint_queue.pop_front()
		_hint_t = 1.0
	_spawn_ambient_motes()
	_check_near_miss()
	_check_water_entry()
	_drive_audio()
	# Global hard cap above the per-path soft guards (300 shot / 260 burst):
	# explosions, gibs and boss-death secondaries append uncapped, and every
	# live entry is walked twice per frame (_draw_fx + _draw_glow). Oldest
	# entries are the closest to expiring anyway. Stays live mid-freeze, like
	# the corpse cap below.
	# Protected kinds: the once-per-run cinematic sweeps (victory extraction /
	# boss-escort chopper, rate 0.006 ≈ 167 frames alive) ride this same array
	# and were evictable exactly when boss-finale secondaries trip the cap —
	# skip past them to the oldest expendable entry (≤2 exist, so it converges).
	while _fx.size() > 400:
		var vi := 0
		while vi < _fx.size() and _fx[vi]["kind"] == "chopper":
			vi += 1
		if vi >= _fx.size():
			break
		_fx.remove_at(vi)
	# Hit-stop freezes the particles WITH the sim: explosions hang at their
	# brightest frame and gibs hang mid-air through the freeze, then resume —
	# completing the freeze-frame the held impact envelopes above start.
	if _hitstop_frames == 0:
		var tinks := 0   # brass-landing tick budget: 2/frame keeps MG spam from ringing
		for i in range(_fx.size() - 1, -1, -1):
			var fx := _fx[i]
			fx["t"] += fx.get("rate", 0.09)
			if fx["kind"] == "casing" or fx["kind"] == "gib" or fx["kind"] == "dust" or fx.get("move", false):
				fx["x"] += int(fx["vx"] * Fixed.ONE)
				fx["y"] += int(fx["vy"] * Fixed.ONE)
				fx["vx"] *= 0.86
				fx["vy"] *= 0.86
				# Brass and body chunks fall: pure damping stopped them mid-air like
				# zero-G syrup. ponytail: fake gravity, no floor/bounce — lifetimes
				# are ~15 frames, so they settle into an arc, not sink forever.
				if fx["kind"] == "casing" or fx["kind"] == "gib":
					fx["vy"] += 0.3
			if fx["t"] >= 1.0:
				# Brass lands with a tink (the mine-plant clink, pitched up + panned):
				# gravity made casings fall, but the landing was mute — MG fire was
				# all muzzle and no ground chatter.
				if fx["kind"] == "casing" and tinks < 2:
					tinks += 1
					_sfx.play_at("tank_board", _to_screen(fx["x"], fx["y"]),
						-24.0, randf_range(2.2, 2.7))
				_fx.remove_at(i)
		# Scheduled boss-death secondaries: each pops a full _blast_debris when its
		# timer elapses, so detonations ripple across the wreck instead of at once.
		for i in range(_pending_blasts.size() - 1, -1, -1):
			var pb := _pending_blasts[i]
			pb["delay"] -= 1
			if pb["delay"] <= 0:
				_fx.append({"x": pb["x"], "y": pb["y"], "t": 0.0, "kind": "explosion"})
				_fx.append({"x": pb["x"], "y": pb["y"], "t": 0.0, "kind": "light", "rate": 0.09,
					"r": 40.0, "col": Color(1.0, 0.7, 0.35)})
				_blast_debris(pb["x"], pb["y"])
				_rumble = maxf(_rumble, 0.4)   # haptics ride _rumble_on, not reduce-motion
				if _motion >= 0.5:
					_trauma = minf(1.0, _trauma + 0.12)
				_pending_blasts.remove_at(i)
		# Decal clocks freeze with the particles: a crater fading or a corpse
		# aging under a "frozen" explosion breaks the freeze-frame read.
		# a2-13 VFX#3: campaign scorch now LINGERS — it fades SLOW toward a faint
		# permanent GHOST (t capped at 0.82, never scrubbed) instead of the old fast
		# 0.012 clean-up, so a cleared field reads as fought-over (matching the corpse/
		# hulk intent). Endless scars stay full (no aging), as before.
		for i in range(_scorch.size() - 1, -1, -1):
			if sim.mode != "endless":
				_scorch[i]["t"] = _scorch_age(_scorch[i]["t"])
	# Count-cap BOTH modes so the persistent scars stay bounded (was endless-only).
	while _scorch.size() > _scorch_cap(sim.mode):
		_scorch.remove_at(0)
	if sim.mode == "endless":
		for i in range(_corpses.size() - 1, -1, -1):
			_corpses[i]["t"] += 0.004   # linger ~4s (endless ages corpses; campaign persists — unchanged)
			if _corpses[i]["t"] >= 1.0:
				_corpses.remove_at(i)
	while _corpses.size() > 40:     # cap stays live even mid-freeze
		_corpses.remove_at(0)
	# Dead-tank hulks: the sim just flips alive=false and the tank vanished mid-
	# explosion. Edge-detect the flip here and leave a persistent view-side wreck
	# (t is only the smolder envelope — the hulk itself stays until reset/cap).
	for ti in sim.tanks.size():
		var tk: Dictionary = sim.tanks[ti]
		if _tank_alive_prev.get(ti, true) and not tk["alive"]:
			_hulks.append({"x": tk["x"], "y": tk["y"], "t": 0.0,
				"rot": float(Art.cell_hash(tk["x"], tk["y"]) % 628) / 100.0})
		_tank_alive_prev[ti] = tk["alive"]
		# Engine idle (3-vote): persistent positional growl for alive on-screen
		# tanks; pitch lifts when crewed so boarding audibly changes the engine.
		var tk_pos := _to_screen(tk["x"], tk["y"])
		var tk_on: bool = tk["alive"] and tk_pos.y > -40.0 and tk_pos.y < 400.0
		_sfx.engine_at(ti, tk_pos, tk_on)
	for h in _hulks:
		h["t"] = minf(1.0, h["t"] + 0.002)   # ~8s of flame/smolder, then a cold wreck
	# Smoke wisps drift off any hull still holding cover (burn_ticks > 0).
	for hk in sim.tanks:
		if not hk["alive"] and hk["burn_ticks"] > 0 and randf() < 0.05:
			var wp := _to_screen(hk["x"], hk["y"])
			if wp.y > -20.0 and wp.y < 380.0:
				_fx.append({"x": hk["x"] + int(randf_range(-10, 10)) * Fixed.ONE,
					"y": hk["y"] + int(randf_range(-6, 6)) * Fixed.ONE, "t": 0.0, "kind": "tex",
					"tex": "fx_smoke", "sz": 8.0 + randf() * 6.0, "grow": 0.9, "fade": 1.6,
					"rate": 0.012, "col": Color(0.35, 0.33, 0.3, 0.35)})
	while _hulks.size() > 8:
		_hulks.remove_at(0)
	for i in _recoil.size():
		_recoil[i] *= 0.72
		if i < _hit_flinch.size():
			_hit_flinch[i] *= 0.8
	for i in _heat.size():
		_heat[i] = maxf(0.0, _heat[i] - 0.02)
	_boss_flash = _boss_flash * 0.8 if _boss_flash > 0.01 else 0.0
	for i in mini(_down_anim.size(), sim.players.size()):
		if sim.players[i]["alive"]:
			# Decay, don't snap: a revived soldier rises out of the topple pose
			# over a few frames (residual blended in the alive draw branch).
			_down_anim[i] = maxf(0.0, _down_anim[i] - 0.15)
		else:
			_down_anim[i] = minf(1.0, _down_anim[i] + 0.12)
	if _hitstop_frames == 0:
		_kick *= 0.78
	# Gamepad rumble: one pooled pulse per frame across connected pads.
	if _rumble > 0.01:
		if _rumble_on:
			for pad in Input.get_connected_joypads():
				Input.start_joy_vibration(pad, _rumble * 0.4, _rumble, 0.12)
		_rumble = 0.0
	# A held freeze-frame holds the whole transform: envelopes are pinned at peak
	# above, but re-rolling a fresh random rattle from held trauma every frame
	# made the "frozen" world buzz at max amplitude through the freeze.
	if _hitstop_frames > 0:
		return
	# Random per-axis rattle (not a smooth Lissajous sway), biased vertical to match
	# the scroll axis; trauma² keeps small hits subtle while big ones land.
	var mag := _trauma * _trauma * 11.0 * _motion
	var shake := Vector2.ZERO
	if mag > 0.01:
		shake = Vector2(randf_range(-0.8, 0.8) * mag, randf_range(-1.0, 1.0) * mag)
	# Camera zoom-punch pivots around screen center, not the top-left origin.
	var pz := 1.0 + _punch * _motion
	scale = Vector2(pz, pz)
	# Rotational judder: only the biggest hits (boss deaths, phase breaks) get a hair
	# of dutch-angle roll — a juice axis untouched until now. Pivots on screen center
	# with the zoom, so the frame twists in place instead of sliding off.
	# No threshold gate: trauma² already scales roll to ~nothing on small hits, and
	# a hard gate popped visibly as trauma crossed it mid-decay.
	# 0.55 rad/frame ≈ 5Hz: a readable held twist. The old 2.9 sat near Nyquist
	# (π rad/frame), flipping sign almost every frame — buzz, not roll.
	var rot := sin(float(Engine.get_physics_frames()) * 0.55) * _trauma * _trauma * 0.035 * _motion
	rotation = rot
	position = shake + _kick * _motion + SCREEN_CENTER - (SCREEN_CENTER * pz).rotated(rot)


func _drive_audio() -> void:
	# Adaptive score: the drum bed swells with the fight and ducks in lulls;
	# the last-stand heartbeat bed rises as the finale closes in.
	var boss_on: bool = not sim.colossus.is_empty() and sim.colossus.get("alive", false)
	for g in sim.gates:
		if not g["boss"].is_empty() and g["boss"]["alive"] and not g["open"]:
			boss_on = true
	var alive_enemies := 0
	for e in sim.enemies:
		if e["alive"]:
			alive_enemies += 1
	var intensity := minf(1.0, alive_enemies / 12.0) * 0.6 + _trauma * 0.4
	if boss_on:
		intensity = maxf(intensity, 0.85)
	# Held-breath dropout before a big beat; drums duck out under last-stand
	# so the heartbeat plays alone.
	if _music_hold > 0:
		intensity = 0.0
	if _tension > 0.4:
		intensity = minf(intensity, 0.15)
	# Last Stand engage: the flag flips once; the radio marks the moment.
	if sim.last_stand and not _last_stand_prev:
		_vo("vo_last_stand", 3, 600)
	_last_stand_prev = sim.last_stand
	# The pilot's queued close-mic plea (0.4s behind the Commander's callout).
	if _vo_plea_at >= 0 and int(Engine.get_physics_frames()) >= _vo_plea_at:
		_vo_plea_at = -1
		_vo("vo_pilot_plea", 2, 600, true)
	# VO owns the mix while speaking: rides the existing duck channel.
	_sfx.set_music_intensity(intensity, maxf(_duck, 0.45 if _sfx.vo_active() else 0.0), _boss_music_on(sim))
	_sfx.duck_sfx_under_vo(_sfx.vo_active())   # a1-14 AUD#6: the combat bus dips under the radio too
	# a3-15: place-sense for the ambience beds — is a river band on screen, and are we in the
	# endless intermission shop? (near-water reuses the terrain draw window; early-out scan.)
	var near_water := false
	for w in sim.waters:
		if w["y"] <= sim.camera_top + 460 * Fixed.ONE and w["y"] + SimWorld.WATER_H >= sim.camera_top - 64 * Fixed.ONE:
			near_water = true
			break
	var in_shop: bool = sim.mode == "endless" and sim.intermission_ticks > 0
	_sfx.set_ambience_march(_sector_march(), near_water, in_shop)   # a1-15 + a3-15: biome wind + place beds
	_sfx.set_concussion(_concussion)
	# Last-stand dread: desat overlay + lub-dub heartbeat on a ~1s loop.
	var want := 1.0 if sim.last_stand and not sim.victory else 0.0
	_tension = lerpf(_tension, want, 0.03)
	if _tension > 0.3 and Engine.get_physics_frames() - _heart_frame > 55:
		_heart_frame = Engine.get_physics_frames()
		_sfx.play("heartbeat", -14.0 + _tension * 6.0, 1.0)
		_rumble = maxf(_rumble, _tension * 0.4)


static func demo_input(tick: int, dsim: SimWorld) -> SimInput:
	## Scripted "player" for Movie Maker captures (--write-movie): march
	## north weaving, burst-fire, lob grenades, roll, radio in supplies,
	## feed the coin reader if downed — and commandeer any parked tank on
	## the way. Deterministic against the fixed seed: every render is the
	## same playthrough.
	var inp := SimInput.new()
	inp.move_y = -256
	inp.move_x = [0, 256, 0, -256][(tick / 120) % 4]   # wide weave: reach the flank bunkers
	inp.aim_y = -256
	inp.aim_x = [0, 150, -150, 0][(tick / 60) % 4]     # sweeping fire
	inp.fire = (tick % 8) != 7                          # MG never sleeps
	inp.grenade = (tick % 90) == 70                     # crack armor often
	inp.roll = (tick % 150) == 90
	inp.buy = 2 if tick == 880 else 0   # "+4 GRENADES" moment
	inp.revive = (tick % 90) == 0       # downed: feed the coin reader
	var p := dsim.players[0]
	if p["in_tank"] >= 0:
		# Tank time: gentler weave, cannon on the same trigger, stay aboard.
		inp.move_x = [0, 128, -128, 0][(tick / 100) % 4]
		inp.roll = false
		inp.grenade = false
		# Shell the nearest bunker in reach — crack the gate on camera.
		for bk in dsim.bunkers:
			if bk["alive"]:
				var bdx: int = bk["x"] + SimWorld.BUNKER_W / 2 - p["x"]
				var bdy: int = bk["y"] + SimWorld.BUNKER_H / 2 - p["y"]
				if absi(bdx) < 170 * Fixed.ONE and absi(bdy) < 170 * Fixed.ONE:
					var blen := Fixed.length(bdx, bdy)
					if blen > Fixed.ONE:
						inp.aim_x = clampi(Fixed.div(bdx, blen) / 256, -256, 256)
						inp.aim_y = clampi(Fixed.div(bdy, blen) / 256, -256, 256)
					if absi(bdx) > 30 * Fixed.ONE:
						inp.move_x = 256 * signi(bdx)
					break
		return inp
	# Commandeer: steer at a parked healthy tank once it's near.
	for t in dsim.tanks:
		if t["alive"] and not t["burning"] and t["occupant"] < 0:
			var dx: int = t["x"] - p["x"]
			var dy: int = t["y"] - p["y"]
			if absi(dx) < 150 * Fixed.ONE and absi(dy) < 150 * Fixed.ONE:
				inp.move_x = 256 * signi(dx) if absi(dx) > 4 * Fixed.ONE else 0
				inp.move_y = 256 * signi(dy) if absi(dy) > 4 * Fixed.ONE else 0
				inp.roll = false
				inp.interact = absi(dx) < 20 * Fixed.ONE and absi(dy) < 20 * Fixed.ONE \
					and (tick % 3) == 0
				break
	return inp


func _gather_inputs() -> Array[SimInput]:
	if OS.has_feature("movie"):
		return [demo_input(sim.tick_count, sim)]
	var inputs: Array[SimInput] = []
	var p1 := SimInput.new()
	# c1-18: movement + aim + verbs all read their REBOUND physical keycodes (bind()), so
	# ESDF / arrow / left-handed / non-QWERTY players can fully remap. Aim keys are their
	# own binds (default arrows), so moving movement onto the arrows no longer collides with
	# a hardcoded aim; the mouse aim fallback below still fills in when no aim key is held.
	var kx := (1.0 if Input.is_physical_key_pressed(bind("move_right")) else 0.0) - (1.0 if Input.is_physical_key_pressed(bind("move_left")) else 0.0)
	var ky := (1.0 if Input.is_physical_key_pressed(bind("move_down")) else 0.0) - (1.0 if Input.is_physical_key_pressed(bind("move_up")) else 0.0)
	var ax := (1.0 if Input.is_physical_key_pressed(bind("aim_right")) else 0.0) - (1.0 if Input.is_physical_key_pressed(bind("aim_left")) else 0.0)
	var ay := (1.0 if Input.is_physical_key_pressed(bind("aim_down")) else 0.0) - (1.0 if Input.is_physical_key_pressed(bind("aim_up")) else 0.0)
	# Explicit aim only (arrow keys / pad stick, NOT the mouse fallback) — the
	# spend-wheel selects from this so tapping Q with the mouse off-center
	# can't auto-buy on release.
	var wheel_dir := Vector2(ax, ay)
	var pad_move := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if _swap_sticks[0]:   # c1-18: P1 left-handed pad option — move on the right stick, aim on the left
		var tmp := pad_move; pad_move = pad_aim; pad_aim = tmp
	if pad_aim.length() > 0.25:
		wheel_dir = pad_aim
	if pad_move.length() > 0.2:
		kx = pad_move.x
		ky = pad_move.y
	# Aim priority: pad stick > arrow keys > mouse. The mouse always has a
	# position, so it's the fallback that makes keyboard play feel twin-stick.
	if ax == 0.0 and ay == 0.0 and sim.players[0]["alive"]:
		var to_mouse := get_local_mouse_position() \
			- _to_screen(sim.players[0]["x"], sim.players[0]["y"])
		if to_mouse.length() > 4.0:
			var md := to_mouse.normalized()
			ax = md.x
			ay = md.y
	if pad_aim.length() > 0.25:
		ax = pad_aim.x
		ay = pad_aim.y
	p1.move_x = _quantize_axis(kx)
	p1.move_y = _quantize_axis(ky)
	p1.aim_x = _quantize_axis(ax)
	p1.aim_y = _quantize_axis(ay)
	# Fire-swallow: menu rows activate on LMB press and SPACE is menu-confirm /
	# debrief-redeploy — without this, clicking RESUME fired live rounds at the
	# crosshair on the first resumed ticks. Re-arms once both keys read released.
	# View-only (the input never reaches the sim), golden-safe.
	if _fire_swallow and not Input.is_physical_key_pressed(bind("fire")) \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_fire_swallow = false
	# c1-18: the fire TRIGGER (analog, always live) stays fixed; the rebindable pad
	# button reads through pad_pressed. Keyboard reads its rebound physical key.
	p1.fire = (not _fire_swallow and (Input.is_physical_key_pressed(bind("fire"))
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
		or pad_pressed(0, "fire")
	p1.grenade = Input.is_physical_key_pressed(bind("grenade")) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or pad_pressed(0, "grenade")
	p1.roll = Input.is_physical_key_pressed(bind("roll")) or pad_pressed(0, "roll")
	p1.interact = Input.is_physical_key_pressed(bind("interact")) or pad_pressed(0, "interact")
	p1.revive = Input.is_physical_key_pressed(bind("revive")) or pad_pressed(0, "revive")
	p1.buy = _update_wheel(0,
		Input.is_physical_key_pressed(bind("buy")) or pad_pressed(0, "buy"),
		wheel_dir, Vector2(kx, ky))
	# While the wheel is open, the shared roll bind is the CANCEL (a UI action,
	# not a dodge) and sector flicks steer the wheel, not the gun.
	if _wheel[0]["open"]:
		p1.roll = false
		p1.aim_x = _quantize_axis(_wheel_aim[0].x)
		p1.aim_y = _quantize_axis(_wheel_aim[0].y)
	else:
		_wheel_aim[0] = Vector2(ax, ay)
	inputs.append(p1)

	if _two_players:
		var p2 := SimInput.new()
		var p2_move := _pad_deadzone(Vector2(
			Input.get_joy_axis(1, JOY_AXIS_LEFT_X), Input.get_joy_axis(1, JOY_AXIS_LEFT_Y)), 0.2)
		var p2_aim := _pad_deadzone(Vector2(
			Input.get_joy_axis(1, JOY_AXIS_RIGHT_X), Input.get_joy_axis(1, JOY_AXIS_RIGHT_Y)), 0.25)
		if _swap_sticks[1]:   # c1-18: P2's OWN independent left-handed swap
			var t2 := p2_move; p2_move = p2_aim; p2_aim = t2
		p2.move_x = _quantize_axis(p2_move.x)
		p2.move_y = _quantize_axis(p2_move.y)
		p2.aim_x = _quantize_axis(p2_aim.x)
		p2.aim_y = _quantize_axis(p2_aim.y)
		p2.fire = Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
			or pad_pressed(1, "fire")
		p2.grenade = pad_pressed(1, "grenade")
		p2.roll = pad_pressed(1, "roll")
		p2.interact = pad_pressed(1, "interact")
		p2.revive = pad_pressed(1, "revive")
		p2.buy = _update_wheel(1, pad_pressed(1, "buy"),
			p2_aim, p2_move)
		if _wheel[1]["open"]:
			p2.roll = false
			p2.aim_x = _quantize_axis(_wheel_aim[1].x)
			p2.aim_y = _quantize_axis(_wheel_aim[1].y)
		else:
			_wheel_aim[1] = p2_aim
		inputs.append(p2)
	return inputs


func _update_wheel(i: int, held: bool, aim: Vector2, move: Vector2) -> int:
	## Hold to open, flick aim (or move) to pick a sector, release to buy.
	## Selection is sticky; releasing with nothing picked cancels. Returns the
	## SimInput.buy value (kind + 1) for exactly one tick on purchase.
	var w := _wheel[i]
	# The sim silently drops a dead player's buy — the wheel must not open (or
	# stay open) for a corpse. Guard here so both call sites are covered.
	if not sim.players[i]["alive"]:
		w["open"] = false
		w["sel"] = -1
		return 0
	if held:
		if not w["open"]:
			w["t"] = 0.0   # entrance envelope: the wheel used to teleport on at full size
			# MOVE only selects after the stick/keys have been seen neutral once —
			# kiting movement at open-time must not silently pick a sector.
			w["move_armed"] = false
		w["open"] = true
		w["t"] = lerpf(float(w.get("t", 1.0)), 1.0, 0.35)
		# Changed your mind mid-hold? The roll button (C / pad B) clears the pick —
		# selection used to be a one-way trap: any flick force-bought on release.
		# Per-device (matches the wheel's own open/aim split): P1 = keyboard C +
		# pad 0, P2 = pad 1 only — so one player's roll can't cancel the OTHER's
		# pick. The rebound roll key matches the roll verb (AZERTY-safe physical read).
		var cancel: bool = (i == 0 and Input.is_physical_key_pressed(bind("roll"))) \
			or pad_pressed(i, "roll")
		if cancel and w["sel"] >= 0:
			w["sel"] = -1
			_sfx.play("click_dry", -12.0, 1.4)   # soft declined tick — the dedicated dry-click voice
		# MOVE only becomes the selector after it has been seen neutral once
		# since the wheel opened — otherwise kiting while holding Q silently
		# picked a sector and release force-bought it (retreat-south = airstrike).
		if move.length() < 0.3:
			w["move_armed"] = true
		var dir := aim if aim.length() > 0.3 \
			else (move if w.get("move_armed", false) else Vector2.ZERO)
		if dir.length() > 0.3:
			var new_sel := int(round(fposmod(dir.angle(), TAU) / (TAU / 8.0))) % 8
			if _SECTOR_TO_ITEM[new_sel] < 0:
				new_sel = w["sel"]   # empty diagonal: keep the sticky pick
			if new_sel != w["sel"]:
				_sfx.play("pickup", -16.0, 1.5)   # hover tick confirms the flick
			w["sel"] = new_sel
		# Selected-socket pop ease: restarts on every new pick, advances at the
		# fixed 60 Hz tick (framerate-independent); reduce-motion draws it full-
		# size immediately instead of animating the growth.
		if w["sel"] != int(w.get("pop_sel", -2)):
			w["pop_sel"] = w["sel"]
			w["pop"] = 0.0
		w["pop"] = 1.0 if _motion < 0.5 else minf(1.0, float(w.get("pop", 0.0)) + 0.18)
		return 0
	if w["open"]:
		w["open"] = false
		var sel: int = w["sel"]
		w["sel"] = -1
		if sel >= 0:
			return WHEEL_ITEMS[_SECTOR_TO_ITEM[sel]]["kind"] + 1
	return 0


func _pad_deadzone(v: Vector2, threshold: float) -> Vector2:
	## Radial deadzone: a stick resting below `threshold` reads as centered.
	## The sim normalizes any nonzero move vector to full speed, so an
	## un-deadzoned drifting stick would be a permanent full-speed crawl.
	return v if v.length() > threshold else Vector2.ZERO


func _quantize_axis(v: float) -> int:
	## The float→int boundary: the sim only ever sees quantized [-256, 256].
	return clampi(int(round(v * 256.0)), -256, 256)


func _to_screen(fx: int, fy: int) -> Vector2:
	return Vector2(fx * PX, (fy - sim.camera_top) * PX)


func _bottom_fade(screen_y: float) -> float:
	# c2 2v: cover in the very bottom of the ratchet view FADES (never culls —
	# the collision AABB stays real) so a hazard or enemy behind it isn't hidden
	# in the instant before it scrolls off the player's back. Smooth over the
	# bottom ~36px so there's no hard alpha seam.
	if screen_y <= 324.0:
		return 1.0
	return lerpf(1.0, 0.45, clampf((screen_y - 324.0) / 36.0, 0.0, 1.0))


func _draw_hazard_telegraphs() -> void:
	# Telegraph aprons (c2 2v, both reviewers' #1): a hazard about to scroll in
	# from the top edge gets a trampled-ground scuff + warning chevron 80px
	# SOUTH of it, so the safe lane reads BEFORE the ratchet commits the player
	# to the row. Hazards already stream 2*VIEW_H ahead — zero sim data needed.
	var top_wy: int = sim.camera_top
	var pulse := 0.5 + 0.5 * Art.pulse(0.08)
	for arr: Array in [sim.mines, sim.barrels]:
		for hz: Dictionary in arr:
			if not hz.get("armed", false):
				continue
			if hz["y"] >= top_wy - 80 * Fixed.ONE and hz["y"] < top_wy + 20 * Fixed.ONE:
				var ap := _to_screen(hz["x"], hz["y"] + 80 * Fixed.ONE)
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(ap - Vector2(12.0, 7.0), Vector2(24.0, 14.0)),
					false, Color(0.14, 0.11, 0.07, 0.45 * pulse))
				draw_line(ap + Vector2(-6.0, 3.0), ap + Vector2(0.0, -4.0), Color(1.0, 0.6, 0.2, 0.75 * pulse), 1.6)
				draw_line(ap + Vector2(6.0, 3.0), ap + Vector2(0.0, -4.0), Color(1.0, 0.6, 0.2, 0.75 * pulse), 1.6)


# 4 diagonal offsets cover both axes at once — visually ≈ the old 8-neighbor rim
# at half the draw calls (~60 of 90 textures are outlined; this is the hot loop).
const _SKYLINE_X: Array[float] = [80.0, 118.0, 150.0, 468.0, 520.0, 560.0]
const _SKYLINE_H: Array[float] = [26.0, 34.0, 22.0, 30.0, 40.0, 24.0]
# Axis-aligned text outline (floattext) — hoisted like _OUTLINE_OFFSETS below.
const _TEXT_OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
const _OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
]

# Pre-built frame names — "explosion%d" % frame allocated a String per particle per frame.
const _EXPLO_NAMES := ["explosion0", "explosion1", "explosion2", "explosion3"]
# Same idiom for the late-run dead canopy — "tree_dead%d" % allocated per tree per frame.
const _TREE_DEAD := ["tree_dead1", "tree_dead2", "tree_dead3"]

# FX kinds that emit light: drawn by _draw_glow on the additive layer, skipped by _draw_fx.
const _BOSS_RIM := {"gunship_body": true, "gunship_barrel": true,
	"colossus_body": true, "colossus_barrel": true, "m_heli_attack2": true}
# Living things wear a heavier rim than scenery (4v: units sank into the prop
# soup): 1.6px vs the fleet's 1.1px; bosses keep their warm 2.2px above both.
const _UNIT_RIM := {"player1": true, "player2": true, "rusher": true, "elite": true,
	"frogman": true, "observer": true, "m_soldier2": true, "m_bombsuit": true,
	"m_pilot": true, "ghillie": true, "courier": true, "sapper": true}
# a1-02 figure-ground: small dark-clad HOSTILES wore the near-black rim and
# merged into dark litter/craters. These get a warm-LIGHT separator rim in _spr
# instead (heroes/frogman/observer/bombsuit keep the neutral rim — they read fine).
const _LIGHT_RIM := {"rusher": true, "elite": true, "m_soldier2": true,
	"sapper": true, "courier": true, "ghillie": true,
	"m_pilot": true}   # sol-08: dropped m_insurgent3-5/m_contractor2 (retired with the enemy_* swap)
# a1-07: craters read as blasted DEPRESSIONS via a soft dark pit under the decal
# (they are holes, so they get no drop-shadow — this is a centered inner-shadow).
const _CRATER_KEYS := {"crater": true, "crater_field": true}
# a1-08: white-hot explosion core — fraction of the blast life that leads white,
# and the two ring base radii (they grow with t as the fireball expands).
const EXPLO_WHITE_T := 0.16
const EXPLO_WHITE_R_OUT := 12.0
const EXPLO_WHITE_R_IN := 6.0
const _GLOW_KINDS := {"muzzle": true, "spark": true, "shockwave": true,
	"light": true, "ember": true, "flash": true}

# Corpse sprite per enemy kind — mirrors the live-draw choices in _draw_enemies.
# sol-08: rusher/elite/sniper corpses follow their new live RED-team sprites (a fallen body must match
# the trooper that just died — a legacy art corpse under a cel-shaded live body popped authorship on death).
const _CORPSE_TEX := {"rusher": "enemy_smg", "elite": "enemy_assault", "sniper": "enemy_sniper",
	"grenadier": "m_soldier2", "shield": "m_bombsuit", "sapper": "sapper",
	"courier": "courier", "frogman": "frogman", "ghillie": "ghillie", "drone": "m_drone",
	"technical": "m_technical", "pilot": "m_pilot", "broadcast": "radio_tower"}

# Rare capsule identity (pickup kinds 4..9): sprite/label/colour shared by the
# ground draw, the collect callout and the off-screen marker. Always index via
# clampi(kind - 4, 0, size-1) — an unknown kind must degrade, never crash (the
# kind-4/5 glyph OOB bug once errored the pickup draw every frame).
const _CAPSULE_TEX: Array[String] = ["cap_pierce", "cap_spread", "cap_triple", "cap_rend",
	"cap_claymore", "cap_smoke", "cap_flash"]
const _CAPSULE_LABEL: Array[String] = ["PIERCE", "SPREAD", "TRIPLE", "REND", "CLAYMORE", "SMOKE", "FLASH"]
const _CAPSULE_CALLOUT: Array[String] = ["PIERCING ROUNDS!", "SPREAD SHOT!", "TRIPLE SHOT!",
	"REND ROUNDS!", "CLAYMORE +1", "SMOKE SCREEN!", "FLASHBANG!"]
const GRENADE_PREVIEW_COL := Color(0.5, 0.85, 1.0)   # a2-15 LEG#5: FRIENDLY grenade preview is COOL (b>r), distinct from the warm/red enemy strike telegraph
const STRIKE_UNDERLAY := {"scale": 2.1, "alpha": 0.30}   # a3-07: the dark seat-underlay — spans ~2.1x the kill radius (soft edge past the amber ring), 0.30a black
# a3-06: muzzle heat caps. The ignition pop is warmed OFF white-hot (pop_lerp toward white
# < 0.4) and every additive term is capped <= 0.66 so MG-spam sums lower and explosions keep
# the white-hot bright-point monopoly. Pinned so the hierarchy can't regress silently.
const MUZZLE_HEAT := {"pop_lerp": 0.32, "pop_a": 0.66, "fan_a": 0.66, "core_a": 0.66}
const FERN_DAB := {"r": 3.5, "a": 0.22}   # a3-08: the tiny contact dab that grounds a fern clump anchor (under the sprite)
const ROCK_TOP_LIGHT := Color(0.97, 0.95, 0.84)   # a3-09: warm lit top-edge on a boulder — reads as RAISED cover (overhead light)
const BOSS_WOUND := {"scar_start": 0.18, "scar_step": 0.15, "spark": 0.6}   # a3-11: wound frac (1-hp) — first scar / per-scar step / hull sparks near death
const ELITE_AURA := Color(0.85, 0.18, 0.12)   # a3-12: warm-red persistent threat halo under EVERY elite
const HERO_APEX := Color(0.86, 0.93, 1.0)   # a4-03: cool crown catch-light — the hero is the brightest+coolest point
const HERO_APEX_A := 0.44   # sol-07: crown alpha bumped from 0.32 so the cool catch-light reads on the infantry set DARK helmet dome
const HERO_APEX_DY := 3.0   # sol-07: crown sits this many px above pos (the helmet dome is just north of the sprite center)
const HERO_APEX_SZ := Vector2(11.0, 9.0)   # sol-07: crown spot size. DY < SZ.y/2 → the spot always covers the sprite center, so it stays on the dome at EVERY aim angle (screen-fixed, dome at the rotation center)

# a4-05 (AD#10, LEG#4): the reticle's dark backing rings the aim point on ALL 8 sides — a
# CENTERED halo, not the old single down-right drop-shadow, so no edge camouflages into an
# orange turret glow / the red foundry floor. Symmetric offsets (each has its negation) = the
# dark keyline is centered on the aim point, never lopsided.
const RETICLE_HALO := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
const RETICLE_HALO_A := 0.42
const RETICLE_HALO_DIAG := 0.6   # diagonal offsets draw at 0.6x so the corner overlap doesn't out-darken the cardinals — an even ring
const ELITE_AURA_ALPHA := {"base": 0.12, "pulse": 0.07}   # a3-12: base holds under REDUCE MOTION; pulse is motion-gated
const MARSH_WET := {"pool_a": 0.30, "sheen_a": 0.17,   # a3-10: wet-silt pool + its cool specular sheen
	"pool_col": Color(0.05, 0.11, 0.10), "sheen_col": Color(0.55, 0.70, 0.72)}   # cool-dark silt / lighter cool glint
const _CAPSULE_COL: Array[Color] = [Color(0.5, 0.9, 1.0), Color(1.0, 0.8, 0.45), Color(1.0, 0.6, 0.9),
	Color(0.78, 0.38, 1.0), Color(0.75, 0.9, 0.6), Color(0.8, 0.85, 0.9), Color(1.0, 1.0, 0.65)]   # a2-15 LEG#8: REND[3] red-orange -> violet, out of the danger family


static func _tiny_decor_no_rim(tex_name: String, screen_w: float) -> bool:
	# a2-05: sub-14px NON-UNIT sprites (litter/decor: ammobox, landmine, barrier,
	# watchtower, mg_tripod, small rocks...) drop the rim so they read as small objects,
	# not black dead-pixel specks. Units/threats/bosses keep their rim regardless of size.
	return screen_w < 14.0 and not _UNIT_RIM.has(tex_name) and not _BOSS_RIM.has(tex_name)


func _spr(tex_name: String, pos: Vector2, angle := 0.0, spr_scale := 1.0, mod := Color.WHITE,
		stretch := 1.0) -> void:
	var t: Texture2D = Art.tex(tex_name)
	var s := spr_scale * Art.draw_scale(tex_name)
	if _CRATER_KEYS.has(tex_name):
		# a1-07: soft dark pit UNDER the crater decal (centered, no offset) so it seats
		# as a depression blasted into the ground instead of a sticker floating on it.
		var cr := t.get_size().x * s * 0.6
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2(cr, cr), Vector2(cr, cr) * 2.0),
			false, Color(0.03, 0.02, 0.02, 0.5))
	var tint := mod * Art.tint(tex_name)
	draw_set_transform(pos, angle, Vector2(s, s * stretch))
	var origin := -t.get_size() / 2.0
	if Art.outlined(tex_name):
		# 1.4px screen-space dark rim so units/vehicles read on any ground.
		# Boss authority (7v): boss-class sprites wear a thicker WARM rim that
		# lerps white with the shipped hit-flash — the fleet rim stays neutral.
		var oc := Color(0.05, 0.06, 0.04, tint.a)
		var d := 1.1 / s
		if _BOSS_RIM.has(tex_name):
			# a3-01: the warm-dark boss rim was tuned for the gunship over GREEN; on the
			# red-brown foundry floor (+ the red last-stand vignette) the colossus went
			# red-on-red-on-red. _boss_rim_base ramps ONLY the hot end toward a cool
			# steel-cyan so the apex silhouette separates in the finale while the gunship
			# keeps its warm rim over the bridge. Hit-flash still whitens on top.
			var rim_base := _boss_rim_base(_sector_march())
			rim_base.a = tint.a
			oc = rim_base.lerp(Color(1, 1, 1, tint.a), clampf(_boss_flash, 0.0, 1.0))
			d = 2.2 / s
		elif _UNIT_RIM.has(tex_name):
			# A/B'd 1.6 vs 1.7 at 640x360 (Grok round-2): 1.7 holds the pop in
			# dense foliage. The two camo units that LIVE in foliage get 1.9 —
			# their whole failure mode is soft-merging into the greens.
			d = (1.9 if tex_name == "ghillie" or tex_name == "courier" else 1.7) / s
		if _LIGHT_RIM.has(tex_name):
			# a1-02: a warm-LIGHT separator rim lifts the dark hostile off BOTH bright
			# ground and dark scenery (the near-black rim vanished into the litter).
			# Widened to 2.2px (the 4 diagonal offsets are thin) + brightened so the
			# small hostile actually reads as a threat, not a dark speck. This 2.2px
			# INTENTIONALLY supersedes the ghillie/courier 1.9 above — when they are
			# revealed the separator IS the read; the cloak alpha (tint.a) still hides it.
			oc = Color(1.0, 0.9, 0.62, tint.a)
			d = 2.2 / s
		# a2-05: tiny DECOR (sub-14px on screen) drops the rim — a 1px dark rim on a
		# sub-16px prop swamps it into a black dead-pixel speck that reads as noise, not
		# an object; without it the litter reads as a small object AND recedes into the
		# ground (threats/units keep their rim regardless of size).
		if not _tiny_decor_no_rim(tex_name, maxf(t.get_size().x, t.get_size().y) * s):
			for o in _OUTLINE_OFFSETS:
				draw_texture(t, origin + o * d, oc)
	draw_texture(t, origin, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _aim_angle(p: Dictionary) -> float:
	return atan2(p["aim_y"] * PX, p["aim_x"] * PX)


static func _ground_stops(mode: String) -> Array:
	# [grass_stops, dirt_stops] — the 5-stop biome ramps the ground marches through.
	# a3-03: ENDLESS gets its OWN base palette (a warm rust/ochre floor that scorches to
	# ash as the wave march climbs) instead of the campaign jungle-green nudged +0.04, so
	# the arena reads as its own PLACE, not the campaign lawn with the a2-10 dressing
	# rearranged on it. Campaign keeps its jungle→marsh→foundry ramp unchanged.
	if mode == "endless":
		# The grass TEXTURE is green, so the modulate must SUPPRESS green/blue (not just
		# out-red them) or the floor reads olive — the campaign foundry stop reads red-
		# brown precisely because its green is low. Low G/B here → a genuine rust/ochre.
		# Ramp: bright warm OCHRE (early waves) -> grey warm ASH (late) as the wave march
		# climbs. Late stops desaturate toward grey ash — deliberately NOT the campaign
		# foundry's saturated RED [4]=(0.52,0.30,0.24), so endless stays its own place even
		# scorched (endless late r-g gap ~0.09 grey vs campaign ~0.22 red).
		return [
			[Color(0.92, 0.46, 0.24), Color(0.84, 0.44, 0.26), Color(0.72, 0.44, 0.30),
				Color(0.60, 0.42, 0.34), Color(0.47, 0.39, 0.36)],
			[Color(0.56, 0.38, 0.24, 0.72), Color(0.52, 0.37, 0.26, 0.74), Color(0.48, 0.36, 0.28, 0.78),
				Color(0.44, 0.35, 0.30, 0.8), Color(0.40, 0.34, 0.32, 0.82)],
		]
	return [
		[Color(1.0, 1.06, 0.75), Color(1.14, 0.86, 0.62), Color(0.94, 0.90, 0.55),
			Color(0.92, 0.88, 0.78), Color(0.52, 0.30, 0.24)],
		[Color(0.58, 0.50, 0.38, 0.7), Color(0.49, 0.42, 0.33, 0.7), Color(0.42, 0.38, 0.24, 0.7),
			Color(0.44, 0.42, 0.40, 0.7), Color(0.32, 0.26, 0.22, 0.8)],
	]


# a3-05: the two feather rings that grade a bare-earth patch into the turf. Outer wide
# faint ring + a stronger inner halo, both scaled off the card size and dirt alpha.
const DIRT_FEATHER := {"out_scale": 2.4, "out_a": 0.16, "in_scale": 1.6, "in_a": 0.52}


# a4-04: the worn spine down the play lane. Warm packed earth (darker than turf) + a faint
# tread pair snapped onto it; SPINE_LANE is the x-band its meandering centerline stays in
# (the play corridor), so the trail is always a route through open ground, never a wall.
const SPINE_COL := Color(0.10, 0.075, 0.03, 0.16)   # a4-04 r2: +a so the continuous spine reads over grass mottle, not just the ford (still faint, <0.2)
const SPINE_TREAD := Color(0.02, 0.04, 0.0, 0.14)
const SPINE_LANE := Vector2(232.0, 408.0)


static func _rock_has_top_light(rtex: String) -> bool:
	# a3-09: only the DOMED boulders (rock1/rock2) get the lit top-edge rim that reads as
	# raised cover; the flat log (tree_dead2) has no raised dome, so no top-light.
	return rtex != "tree_dead2"


static func _has_canopy_dapple(ash: float) -> bool:
	# a3-04: a living tree casts a soft canopy dapple; past the ash midpoint (0.33 — the
	# same threshold that swaps to the dead-canopy set) the dead/charred canopy casts none.
	return ash < 0.33


static func _frogman_tex(submerged: bool) -> String:
	# sol-12: the diver shows a SPEARGUN while submerged (the underwater weapon), a rifle once he
	# surfaces — a pure read of the existing e["submerged"] sim state, so the silhouette telegraphs
	# the dive state with no new field. "frogman" is the surfaced (rifle) key.
	return "frogman_speargun" if submerged else "frogman"


static func _hero_shows_apex(down_residual: float) -> bool:
	# a4-03: the hero value-apex crown catch-light shows only while UP — a downed / reviving
	# body (down_residual > 0) must NOT read as the brightest point on the field.
	return down_residual <= 0.01


static func _spine_center_x(world_y: float) -> float:
	# a4-04: the worn-spine centerline — a slow low-frequency wander around the 320 center
	# lane, a PURE function of absolute world-y so the trail scrolls seamlessly and never
	# teleports laterally as the camera moves. The two sine terms keep it inside SPINE_LANE
	# (|dev| <= 72) and give it an organic, non-repeating meander rather than a road-straight
	# stripe. Continuous by construction: max lateral slope ~0.26 px/px.
	return 320.0 + sin(world_y * 0.0022) * 52.0 + sin(world_y * 0.0071 + 1.3) * 20.0


static func _grade_breather_target(mode: String, intermission_ticks: int) -> float:
	# a4-01/a4-15: the master-grade shop "breather" is ON only during the ENDLESS intermission
	# (shop open) — a calm tonal beat that reads "safe to buy", then eases off for the next wave.
	return 1.0 if (mode == "endless" and intermission_ticks > 0) else 0.0


static func _boss_rim_base(march: float) -> Color:
	# a3-01: the boss separator rim, keyed to the biome march. Warm-dark over the
	# green bridge (low march, where the gunship was tuned) -> cool steel-BLUE on the
	# hot foundry floor (high march, where the colossus fought red-on-red). Ramped on
	# the hot end only (smoothstep 0.6..1.0) so the gunship never gets a muddy teal rim.
	# r2 (judge TO_TEN): the cool endpoint stays DARK (value ~0.48, near the warm rim's
	# ~0.4) so the silhouette language remains "dark separator, hue-shifted" — the red
	# floor is out-contrasted by HUE (blue vs red), not by flipping to a bright white edge.
	return Color(0.4, 0.1, 0.06).lerp(Color(0.16, 0.32, 0.48), smoothstep(0.6, 1.0, march))


func _ground_shadow(pos: Vector2, r: float, a := 0.32, tint := Color(0.0, 0.03, 0.0)) -> void:
	# Soft flattened drop-shadow so units/vehicles sit ON the ground instead of
	# floating over it — a legacy art soft-dark card (fx_shadow) with baked falloff.
	# Weight-graded (7v): heavy armor passes ~0.42 so a tank visually outweighs
	# a rifleman (panel's 0.6 was sourceless — starting at 0.42, screenshot-tuned);
	# wading shadows pass a dimmer, cooler read (light scatters in water).
	var sh := Art.tex("fx_shadow")
	var ss := (r * 1.15) / (sh.get_size().x * 0.5)
	draw_set_transform(pos + Vector2(0, r * 0.32), 0.0, Vector2(ss, ss * 0.45))
	draw_texture(sh, -sh.get_size() / 2.0, Color(tint.r, tint.g, tint.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	# Position the water shader quads under the world and requeue the grass base.
	# Driven from _draw (not _process) so it also runs under the screenshot harness,
	# which disables main's processing but still calls queue_redraw(). The 1-frame
	# lag on _bg_root's requeue only affects decorative grass tiling — the water
	# quads themselves are positioned in-frame here, so they stay aligned to units.
	_sync_water()
	if _bg_root != null:
		# _paint_bg is a pure function of (camera_top, sector march): skip the
		# ~90-rect grass/dirt rebuild whenever the camera is parked (wave fights,
		# pause, debrief) and no gate/wave advanced — its retained canvas
		# commands re-render as-is. _glow_root stays per-frame (animated FX).
		var march := _sector_march()
		if sim.camera_top != _bg_cam or march != _bg_march:
			if march != _bg_march:
				# Freeze the litter-pool threshold for ground already on screen —
				# live march made ~20% of visible props swap identity the frame a
				# gate opened; the wrecked look sweeps in from the top edge instead.
				_litter_cam_snap = sim.camera_top
				_litter_march_prev = maxf(_bg_march, 0.0)   # _bg_march starts -1.0
			_bg_cam = sim.camera_top
			_bg_march = march
			_bg_root.queue_redraw()
	if _glow_root != null:
		_glow_root.queue_redraw()
	_draw_terrain()
	_draw_skyglow()
	_draw_landmark_previews()
	# Water (banks/ford/bridge deck) BEFORE scorch: the deck sprites fully tile
	# the ford choke point, and decals drawn first were overpainted the same
	# frame — every corpse/crater/hulk at a river crossing vanished. The water
	# body itself is a shader quad on _bg_root (z=-2), so it stays below anyway.
	_draw_water()
	_draw_scorch()
	_draw_foundry_arena()
	_draw_vents()
	_draw_hazard_telegraphs()
	_draw_mines()
	_draw_rocks()
	_draw_sandbags()
	_draw_sector_embers()
	_draw_barrels()
	_draw_gates()
	# Gate-locking bunkers are marked so the player knows WHICH to grenade —
	# field bunkers stream in independently and look identical otherwise.
	var lockers: Array = []
	for g in sim.gates:
		if not g["open"] and not g.get("b1", {}).is_empty():
			lockers.append(g["b1"])
			lockers.append(g["b2"])
	for bk in sim.bunkers:
		if bk["alive"]:
			var c := _to_screen(bk["x"], bk["y"]) + Vector2(24, 16)
			# Band cull (same idiom as _draw_barrels): the sim never removes
			# bunkers, so every bypassed one kept paying shadow + outlined bake +
			# hatch glow + orbiting drone (~13 items) off-screen forever.
			if c.y < -60.0 or c.y > 420.0:
				continue
			var is_locker := false
			for lk in lockers:
				if is_same(lk, bk):
					is_locker = true
					break
			if is_locker:
				var lp: float = 1.0 if _motion < 0.5 else Art.pulse(0.15)   # steady-bright under reduce-motion
				draw_arc(c, 26.0, 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.4 + lp * 0.4), 2.0)
			_ground_shadow(c, 17.0, 0.42)
			# Hash-picked bunker variant: bunker / bunker2 / mirrored bunker (the
			# mirror is a free third look — angle PI + stretch -1 = h-flip).
			var bv := Art.cell_hash(bk["x"], bk["y"] * 7) % 3
			if bv == 0:
				_spr("bunker", c, 0.0, 0.78)
			elif bv == 1:
				_spr("bunker2", c, 0.0, 0.78)
			else:
				_spr("bunker", c, PI, 0.78, Color.WHITE, -1.0)
			# Hatch charging: a front-mouth glow that swells as the 120-tick spawn
			# timer nears zero and peaks into a bright emit flash the instant it
			# fires — a rusher popping out of the mouth is no longer a free hit.
			# Derived from the existing spawn_cd; no sim state touched.
			var charge := 1.0 - float(bk["spawn_cd"]) / float(SimWorld.BUNKER_SPAWN_INTERVAL_TICKS)
			if charge > 0.45:
				var cr := ease(clampf((charge - 0.45) / 0.55, 0.0, 1.0), 2.0)
				var mouth := c + Vector2(0, 10)
				draw_texture_rect(Art.tex("fx_softspot"),
					Rect2(mouth - Vector2.ONE * (4.0 + cr * 7.0), Vector2.ONE * (8.0 + cr * 14.0)),
					false, Color(1.0, 0.6, 0.25, 0.22 + cr * 0.5))
				draw_circle(mouth, 1.5 + cr * 2.5, Color(1.0, 0.85, 0.5, 0.4 + cr * 0.5))
			# A recon drone loiters above an active strongpoint — a small orbiting
			# silhouette that reads the bunker as 'watched'. Phase offset per bunker
			# so multiples don't fly in lockstep. Pure ambient view.
			# Loiter angle freezes at each drone's phase-offset rest under reduce-motion
			# (the orbit is pure ambient motion — its siblings, the observer orbit dots,
			# are gated the same way).
			var da := float(bk["x"] / 4096) if _motion < 0.5 \
				else float(Engine.get_physics_frames()) * 0.03 + float(bk["x"] / 4096)
			var dp := c + Vector2(cos(da) * 15.0, sin(da) * 7.0 - 22.0)
			_spr("m_drone", dp, da + PI / 2, 0.4)
	_draw_pickups()
	_draw_tanks()
	_draw_enemies()
	_draw_observer()
	_draw_gunships()
	_draw_colossus()
	# Field dim (NIGHT OPS) sits UNDER the tracers/players/fx — they're "your
	# eyes" in the dark, so it must not wash them out. It draws in screen space:
	# cancel the shake transform, dim, then restore for the world passes below.
	draw_set_transform_matrix(get_transform().affine_inverse())
	_draw_field_dim()
	draw_set_transform_matrix(Transform2D())
	_draw_projectiles()
	_draw_players()
	_draw_fx()
	_draw_telegraphs()
	_draw_wheel()   # world-anchored (rings the player) — must ride the shake
	# From here down everything is screen-anchored HUD/overlay: cancel the node's
	# shake/zoom/roll so bars, markers and banners stay rock-steady while the world
	# judders (mirrors the shake-immune $HUD CanvasLayer the icon HUD lives on).
	draw_set_transform_matrix(get_transform().affine_inverse())
	_draw_threat_edges()
	# Edge-clamped windup arrows live with their sibling edge indicators: drawn in
	# the world block they rode the shake, sat UNDER the NIGHT OPS dim (whose own
	# contract says threat markers are your eyes), and got over-painted by
	# gunships/projectiles/fx — burying the off-screen-lethal-shot warning.
	_draw_threat_pips()
	_draw_objective_markers()
	_draw_progress_rail()
	var top_msg := _top_center_priority()
	_draw_airstrike_telegraph(top_msg)
	_draw_banners(top_msg)
	# Cinematic letterbox: bars snap in on boss-intro/victory beats, hold, then melt.
	# Gated by reduce-motion like every sibling effect — this was the one holdout.
	if _cinematic > 0.01 and _motion >= 0.5:
		var ch := 16.0 * clampf(_cinematic * 4.0, 0.0, 1.0)
		draw_rect(Rect2(0, 0, SCREEN_W, ch), Color(0, 0, 0, 0.9))
		draw_rect(Rect2(0, SCREEN_H - ch, SCREEN_W, ch), Color(0, 0, 0, 0.9))
	# c4 2v: rear-warn bottom-edge wedge — a pulsing strip + an up-pointing wedge
	# at the pending rear spawn x, readable in the forward-locked camera.
	if _rear_wedge_t > 0.0:
		var rpulse := 0.35 + 0.35 * sin(_rear_wedge_t * 12.0)
		var ra := clampf(_rear_wedge_t / 1.5, 0.0, 1.0) * rpulse
		draw_rect(Rect2(0, SCREEN_H - 20.0, SCREEN_W, 20.0), Color(0.8, 0.35, 0.12, ra * 0.4))
		var rwx := clampf(_rear_wedge_x, 20.0, SCREEN_W - 20.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(rwx - 16.0, SCREEN_H), Vector2(rwx + 16.0, SCREEN_H), Vector2(rwx, SCREEN_H - 22.0)]),
			Color(1.0, 0.45, 0.15, ra))


func _draw_field_dim() -> void:
	# NIGHT OPS mutator: dim the field to a blue dusk so the tracers, muzzle
	# flashes and threat markers become your eyes. No hit-radius change — the
	# challenge is visibility, not fairness.
	if sim.mode == "endless" and sim.wave_mod == 5:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.02, 0.03, 0.09, 0.34))
		draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, SCREEN_W, SCREEN_H), false,
			Color(0.0, 0.02, 0.12, 0.55))
		# Sheet-lightning: a silent-thunder flash every ~7s turns "just dark" into a
		# storm — diffuse white-blue sky flash, no bolt. Stateless (frame clock), and
		# reduce-motion scales it to nothing.
		var lt := Engine.get_physics_frames() % 431
		if lt < 3:
			draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0.55, 0.66, 1.0, (1.0 - float(lt) / 3.0) * 0.45 * _motion))


func _draw_landmark_previews() -> void:
	# Wayfinding (c2 2v): distant landmark silhouettes fade in at the frame top
	# 2-3 bands BEFORE a major event, so traversal has anticipation and the
	# jungle stops reading as undifferentiated cover soup. Pure cadence math on
	# the read-only gate/water spacing — no sim access beyond camera_top, no
	# new state. Suppressed once the foundry skyline takes over (march >= 0.6)
	# and in endless (no gate/water streaming there).
	if sim.mode != "campaign" or _sector_march() >= 0.6:
		return
	draw_set_transform_matrix(get_transform().affine_inverse())
	var cam: int = sim.camera_top
	var span: int = 2 * SimWorld.GATE_SPACING   # 2000px preview window
	# Nearest upcoming GATE arena (cadence: gate k at -k*GATE_SPACING, k in 1..5).
	var gate_k: int = int(-cam / SimWorld.GATE_SPACING) + 1
	if gate_k <= SimWorld.FINAL_GATE_INDEX:
		var gate_y: int = -gate_k * SimWorld.GATE_SPACING
		var gd: int = cam - gate_y   # px ahead (positive)
		if gd >= 0 and gd < span:
			var ga := clampf(1.0 - float(gd) / float(span), 0.0, 1.0) * 0.55
			var gtex: String = "watchtower" if gate_k % 2 == 1 else "radio_tower"
			var gx := 92.0 if gate_k % 2 == 1 else 548.0
			var gt := Art.tex(gtex)
			draw_texture_rect(gt, Rect2(gx - 27.0, 4.0, 54.0, 54.0), false, Color(0.06, 0.05, 0.06, ga))
	# Nearest upcoming WATER crossing (bands at -(1500 + m*GATE_SPACING), m>=0).
	# Same fixed-point cadence as the gates (judge r1: the old guard skipped the
	# FIRST band at run start). Band ahead = the nearest one south of the camera.
	var wat_ahead: int = -cam - 1500 * Fixed.ONE   # <0 before the first band, >=0 after
	var wat_m: int = 0 if wat_ahead < 0 else int(wat_ahead / SimWorld.GATE_SPACING) + 1
	var wat_y: int = -(1500 * Fixed.ONE + wat_m * SimWorld.GATE_SPACING)
	var wd: int = cam - wat_y
	if wd >= 0 and wd < span:
		var wa := clampf(1.0 - float(wd) / float(span), 0.0, 1.0) * 0.5
		var wx := 470.0 if wat_m % 2 == 1 else 128.0
		draw_texture_rect(Art.tex("bridge_mid"), Rect2(wx - 30.0, 20.0, 60.0, 34.0),
			false, Color(0.09, 0.08, 0.07, wa))
	draw_set_transform_matrix(Transform2D())


func _draw_skyglow() -> void:
	# Foundry skyglow: as the run pushes toward the finale a warm forge-light bleeds
	# over the top edge — "something huge is burning ahead", a light source above the
	# field rather than just the ground recolor. Near-free when the march is low.
	var march := _sector_march()
	if march < 0.15:
		return
	# Screen-anchored sky: cancel the shake/zoom transform (the _draw_field_dim
	# idiom) so the horizon doesn't judder with ground shake.
	draw_set_transform_matrix(get_transform().affine_inverse())
	var glow := (march - 0.15) / 0.85
	var pul := 1.0 if _motion < 0.5 else (0.85 + 0.15 * Art.pulse(0.1))
	var gcol := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.3, 0.15), glow)
	for b in 5:
		var h := 8.0 + b * 7.0
		var a := glow * 0.16 * (1.0 - b / 5.0) * pul
		draw_rect(Rect2(0, 0, SCREEN_W, h), Color(gcol.r, gcol.g, gcol.b, a))
	# Foundry skyline: once past mid-run, fixed dark silhouettes (smoke stacks + a
	# radio mast) fade in along the top edge — you can SEE where you are headed.
	if march > 0.6:
		var sa := clampf((march - 0.6) / 0.4, 0.0, 1.0) * 0.7
		var sky := Color(0.05, 0.04, 0.05, sa)
		var stx := _SKYLINE_X   # const — was two array literals rebuilt every finale frame
		var sth := _SKYLINE_H
		# Baked side-view silhouettes replace the flat rect stacks + 3-line mast:
		# same anchors (base at _SKYLINE_H, rising to the frame top), same soot
		# tint — `sky` is near-black so the sprite content flattens to silhouette.
		var chim := Art.tex("skyline_chimney")
		for k in stx.size():
			var ch := sth[k] * 1.2
			draw_texture_rect(chim, Rect2(stx[k] - ch * 0.5 + 7.0, sth[k] - ch, ch, ch), false, sky)
		# Mast needs >=60px drawn height or the lattice aliases away.
		draw_texture_rect(Art.tex("skyline_mast"), Rect2(270.0, 0.0, 60.0, 60.0), false, sky)
	draw_set_transform_matrix(Transform2D())


func _biome_ramp(march: float, stops: Array) -> Color:
	## QUANTIZED biome journey (KIMK round-2: a lerp is muddiest exactly at the
	## gates, the one moment the journey should punctuate): each sector wears
	## ONE stop, flat — crossing the gate IS the identity shift, and the
	## litter-freeze machinery already stages that swap off-screen.
	return stops[clampi(int(march * 5.0 + 0.0001), 0, stops.size() - 1)]


func _sector_march() -> float:
	# Sector march: the ground shifts jungle-olive → ashen/scorched as the run
	# pushes toward the Foundry finale (campaign: opened gates; endless: wave).
	# a1-04: the colossus ONLY fights at the Foundry finale — force the full
	# scorched palette so the floor/foliage/water/sky all read foundry-hot and agree
	# with the red vignette, regardless of how many gates opened (the finale used to
	# show GREEN ground under the red frame). LATCHED (r2): the colossus dict persists
	# (alive=false) through the death beat and `victory` holds the win screen, so the
	# scorched read never flickers back to gate-fraction green after the kill.
	if sim.victory or not sim.colossus.is_empty():
		return 1.0
	if sim.mode == "campaign":
		var mopened := 0
		for g in sim.gates:
			if g["open"]:
				mopened += 1
		return clampf(float(mopened) / 5.0, 0.0, 1.0)
	return clampf(float(sim.wave) / 12.0, 0.0, 1.0)


func _draw_terrain() -> void:
# Choke walls (7v corridor modulation): the biting flank renders as rubble
	# over a dark base with a hatched read — the lane narrowing is authored
	# geography, not an invisible wall.
	if sim.mode == "campaign":
		for scan in 5:
			var wy3: int = sim.camera_top + scan * 90 * Fixed.ONE
			var cb: Array = sim._choke_bounds(wy3)
			if cb[0] == SimWorld.WORLD_LEFT and cb[1] == SimWorld.WORLD_RIGHT:
				continue
			var left_bite: bool = cb[0] != SimWorld.WORLD_LEFT
			var seg_off: int = absi(wy3) % SimWorld.GATE_SPACING
			var band_top := _to_screen(0, wy3 + (seg_off - SimWorld.CHOKE_OFF_LO)).y
			var wall_x := 0.0 if left_bite else 400.0
			draw_rect(Rect2(wall_x, band_top - 240.0 * PX * 0.0, 240.0, 240.0), Color(0.12, 0.11, 0.09, 0.85))
			for rb in 12:
				var rh4 := Art.cell_hash(int(wall_x) + rb * 31, absi(wy3) / SimWorld.GATE_SPACING + rb)
				_spr("rock1" if rh4 % 2 == 0 else "rock2",
					Vector2(wall_x + 20.0 + float(rh4 % 200), band_top + 10.0 + float((rh4 / 7) % 220)),
					float(rh4 % 628) / 100.0, 2.0, Color(0.5, 0.5, 0.48))
			break
	# Ridge mounds (2v elevation, view-only): 2-tone dirt swells break the
	# tabletop-flat read — light crest, dark south edge.
	if sim.mode == "campaign":
		var rg_base := int(absi(sim.camera_top) / (64 * Fixed.ONE))
		for rgy in 7:
			for rgx in 10:
				if Art.cell_hash(rgx * 23, rg_base + rgy) % 19 != 0:
					continue
				var rpos := Vector2(rgx * 64.0 + 32.0, float(rgy) * 64.0 - fposmod(float(sim.camera_top) * PX, 64.0))
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(rpos - Vector2(24, 10), Vector2(48, 20)),
					false, Color(0.62, 0.58, 0.42, RIDGE_A_HI))
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(rpos - Vector2(20, 2), Vector2(40, 12)),
					false, Color(0.18, 0.14, 0.08, RIDGE_A_LO + 0.08))
	# Authored setpiece stamps: nameable places every ~800px of corridor.
	if sim.mode == "campaign":
		var spb0 := absi(sim.camera_top) / (400 * Fixed.ONE)
		for spb in range(spb0 - 1, spb0 + 2):
			if spb < 0:
				continue
			var sph := Art.cell_hash(spb * 7, 13)
			if sph % 2 != 0:
				continue
			var stamp: Array = _SETPIECES[(sph / 3) % _SETPIECES.size()]
			var spx := 100.0 + float(sph % 440)
			var spy := _to_screen(0, -(spb * 400 + 200) * Fixed.ONE).y
			if spy < -60.0 or spy > 420.0:
				continue
			for part in stamp:
				var ppos2 := Vector2(spx + part[1], spy + part[2])
				if part[0] != "crater" and part[0] != "crater_field":
					_ground_shadow(ppos2, 7.0)
				_spr(part[0], ppos2, float(Art.cell_hash(int(spx) + part[1], part[2]) % 628) / 100.0, part[3])
	# Endless landmark kit (9/9 arena identity): a neutral comms mast at center
	# with a scorched base + two fixed rocks per quadrant — the arena is now a
	# PLACE you learn, not a screenshot of campaign grass.
	if sim.mode == "endless":
		var lm_pos := _to_screen(320 * Fixed.ONE, -180 * Fixed.ONE)
		# a2-10 ENV#4: a worn CENTER-PAD scuff + a faint PERIMETER-scar ring so the
		# endless arena reads as a fought-over PLACE with its own floor (the ring you
		# circle), not anonymous ground.
		# a2-10 r3: wider/softer pad FIRST, then the tighter hot-center scuff on top -> proper falloff
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(lm_pos - Vector2(96, 70), Vector2(192, 140)),
			false, Color(0.30, 0.26, 0.20, 0.08))
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(lm_pos - Vector2(72, 52), Vector2(144, 104)),
			false, Color(0.30, 0.25, 0.18, 0.16))
		draw_arc(lm_pos, 152.0, 0, TAU, 56, Color(0.32, 0.27, 0.20, 0.22), 2.0)
		draw_arc(lm_pos, 168.0, 0, TAU, 60, Color(0.30, 0.26, 0.20, 0.12), 1.5)   # a2-10 r2: softer wider outer scar (lm_pos IS the arena center = the mast)
		# a2-10 AD#7: a warm dust-haze band along the top edge (wave-keyed), so the
		# arena has a world-edge/sky, not a top-down cutout. Screen-anchored (shake-
		# cancel) like the campaign skyglow.
		draw_set_transform_matrix(get_transform().affine_inverse())
		var haze_a := clampf(0.06 + float(sim.wave) * 0.008, 0.06, 0.18)
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(-40.0, -24.0, SCREEN_W + 80.0, 82.0),
			false, Color(0.52, 0.40, 0.28, haze_a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(Art.tex("fx_shadow"), Rect2(lm_pos - Vector2(20, 8), Vector2(40, 20)),
			false, Color(0.1, 0.08, 0.05, 0.5))
		_spr("radio_tower", lm_pos, 0.0, 1.1, Color(0.85, 0.88, 0.85))
		# (Quadrant rocks now live in sim.rocks — real cover draws itself.)
		# World-anchored grass tiling, darkened toward jungle; deterministic dirt
	# patches and tree lines from a cell hash (decor only, not sim state).
	# The opaque grass/dirt base moved to _paint_bg (renders on _bg_root, below the
	# water quads). Everything below still draws in _draw() over the water.
	var cam_y := sim.camera_top * PX
	# Drifting cloud shadows: large soft dark blobs scrolling diagonally at a
	# slower rate than the camera — instant depth, the jungle feels alive.
	var ct := float(Engine.get_physics_frames()) * 0.15
	for c in 3:
		var cxw := fposmod(ct * (0.6 + c * 0.2) + c * 260.0, 900.0) - 130.0
		var cyw := fposmod(-cam_y * 0.35 + c * 190.0 + ct * 0.3, 620.0) - 130.0
		# Soft-falloff card, not draw_circle: a hard disc rim crawling over bright
		# grass read as a moving outline — clouds get a penumbra like every other
		# shadow in the game. Alpha up vs the flat discs since the card peaks center.
		var cr := 90.0 + c * 22.0
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(Vector2(cxw - cr, cyw - cr), Vector2(cr, cr) * 2.0),
			false, Color(0.0, 0.02, 0.0, 0.09))
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(Vector2(cxw + 40.0 - 70.0, cyw + 24.0 - 70.0), Vector2(140, 140)),
			false, Color(0.0, 0.02, 0.0, 0.08))
	# A jet-shadow streaks across the ground on a long cycle — an aircraft passing
	# high overhead, same shadow idiom as the cloud blobs above (nose-right at PI/2,
	# matching the gunship's PI=down facing). Decor, not the called-airstrike jet.
	var jst := fposmod(ct * 6.0 + 200.0, 1600.0)
	if jst < 820.0:
		_spr("m_jet", Vector2(jst - 90.0, 120.0 + fposmod(-cam_y * 0.2, 300.0)),
			PI / 2, 0.34, Color(0.0, 0.02, 0.0, 0.16))
	# The foliage joins the grass/skyglow in shifting jungle -> scorched toward the
	# Foundry finale (grass already recolors via march; the green ferns/trees used
	# to stay lush, breaking the progression). Lerp their tint ashen by march.
	Art.foliage_march = _sector_march()   # a1-05: ramp the flat FOLIAGE tint so ferns/trees char with the run
	var ash := clampf(_sector_march() * 0.65, 0.0, 0.65)
	var fern_col := Color(0.82, 0.92, 0.72).lerp(Color(0.6, 0.52, 0.42), ash)
	var tree_col := Color(0.75, 0.85, 0.72).lerp(Color(0.55, 0.5, 0.44), ash)
	# Per-band undergrowth SPECIES (c2 3v: same fern table everywhere, only
	# tinted): marsh leans reeds, ruins leans scrub, the foundry chars to
	# stumps outright (see the anchor branch below).
	var ug_band := clampi(int(_sector_march() * 5.0 + 0.0001), 0, 4)
	var ug_species: Array = [["fern", "fern2", "hedge"], ["fern", "fern2", "hedge"],
		["fern2", "fern2", "fern"], ["hedge", "fern", "hedge"], ["hedge", "hedge", "hedge"]][ug_band]
	# Water-band snapshot: sim.waters is append-only (never swept), so the ~50
	# sim._in_water calls below were each scanning EVERY band ever streamed.
	# Only the <=2 bands overlapping the view can matter for on-screen decor —
	# snapshot those once into flat int quads and test cells locally.
	var wbands: Array = []
	# [-64, 460]px covers every cell the three loops below can test (litter
	# reaches ~440px past camera_top), so this is exactly sim._in_water for them.
	var wlo: int = sim.camera_top - 64 * Fixed.ONE
	var whi: int = sim.camera_top + 460 * Fixed.ONE
	for w in sim.waters:
		if w["y"] <= whi and w["y"] + SimWorld.WATER_H >= wlo:
			wbands.append([w["y"], w["y"] + SimWorld.WATER_H,
				w["ford_x"] - SimWorld.FORD_HALF_W, w["ford_x"] + SimWorld.FORD_HALF_W])
	# Low fern understory scattered through the field (hash decorrelated from
	# the tree grid so ferns and trees don't stack on the same cell).
	# Each decor grid anchors to ITS OWN spacing modulus — the shared 64px grass
	# modulus made every layer's sampled world rows jump by 64 (a non-multiple of
	# 40/48/80) whenever cam_y crossed a tile boundary, reshuffling the field.
	var foy := -fposmod(cam_y, 40.0)
	for ty in 10:
		var fy := foy + ty * 40.0
		var fiy := int(floor((cam_y + fy) / 40.0))
		for tx in 16:
			var hf := Art.cell_hash(tx * 17 + 5, fiy * 3)
			if hf % 5 != 0:
				continue
			var fx := tx * 42.0 + float(hf % 20) - 10.0
			var fy_px := fy + float((hf / 5) % 16)
			if _in_wbands(wbands, int(fx / PX), sim.camera_top + int(fy_px / PX)):
				continue
			var fsway := sin(float(Engine.get_physics_frames()) * 0.045 + float(hf)) * 0.07 * _motion
			# 4v variety pass: hash-picked stamp (fern/fern2/hedge shrub), a
			# 0.6/0.8/1.0/1.2 scale ladder, olive->deep-green tint drift, rare
			# dead stump, and CLUMPS — 1-in-5 anchors grow 1-3 satellite tufts
			# so undergrowth reads as drifts, not evenly-spaced speckle.
			# Edge-aware taper (GPT round-3): where the 64px terrain sample
			# changes across a neighbor (a dirt/grass transition), thin ~40% of
			# placements — density GRADES across boundaries instead of snapping.
			var cell_x := int(fx / 64.0)
			var cell_y := int((cam_y + fy_px) / 64.0)
			var here_dirt := Art.cell_hash(cell_x, cell_y) % 6 == 0
			# Graded edge strength (GPT round-4): suppression scales with the
			# FRACTION of disagreeing neighbors (all four), so density falls
			# off smoothly with boundary intensity — 15% per disagreeing side
			# up to 60% at a full crossing, not one fixed rate.
			# Full 8-neighborhood gradient (GPT round-5): cardinals weigh 2,
			# diagonals weigh 1 (max 12) — diagonal and sub-cell boundary
			# shapes now bend the density field too, not just axis edges.
			# Suppression = score * 5% (0..60%), continuous with geometry.
			var edge_s := 0
			for nb in [[1, 0, 2], [-1, 0, 2], [0, 1, 2], [0, -1, 2],
					[1, 1, 1], [1, -1, 1], [-1, 1, 1], [-1, -1, 1]]:
				if here_dirt != (Art.cell_hash(cell_x + nb[0], cell_y + nb[1]) % 6 == 0):
					edge_s += nb[2]
			if edge_s > 0 and (hf >> 11) % 100 < edge_s * 5:
				continue
			# Regional ecology (GPT observation round: open fields still read as
			# "placed instances on a uniform field"): a 512px super-grid gives
			# every region a density lean (sparse/normal/lush) and a DOMINANT
			# SPECIES — wide views now read as ecological zones.
			# Feathered borders (GPT observation round 3): each anchor samples
			# the ecology grid through a personal +/-96px displacement, so
			# regional boundaries interleave irregularly across a ~192px band
			# instead of reading as smooth 512px gradients.
			var reg := Art.cell_hash(int((fx + float((hf >> 6) % 192) - 96.0) / 512.0) + 3,
				int((cam_y + fy_px + float((hf >> 8) % 192) - 96.0) / 512.0))
			var reg_density := reg % 4   # 0 = sparse, 3 = lush
			if reg_density == 0 and (hf >> 13) % 3 == 0:
				continue
			var reg_dom := (reg / 7) % 3
			var f_tex: String = ug_species[reg_dom] if (hf >> 3) % 5 < 3 \
				else ug_species[(hf >> 3) % 3]
			var f_scl := 0.30 * (0.6 + 0.2 * float((hf >> 5) % 4))
			var f_jit := float((hf >> 7) % 5) / 4.0
			var f_col := fern_col.lerp(Color(0.72, 0.78, 0.5), f_jit * 0.5)
			if ug_band == 4:
				# Foundry (c2 3v): no green survives the ash — charred struts only.
				_spr(_TREE_DEAD[hf % 3], Vector2(fx, fy_px), 0.0,
					0.16 + 0.04 * float(hf % 3), Color(0.2, 0.17, 0.15))
			elif hf % 23 == 0:
				_spr(_TREE_DEAD[hf % 3], Vector2(fx, fy_px), 0.0, 0.18, f_col)
			else:
				# a3-08: a tiny dark contact dab grounds the fern CLUMP anchor — ferns got
				# no _ground_shadow (only trees/litter did), so they floated on the lawn.
				# One dab per anchor (satellites cluster on it), not per tuft.
				_ground_shadow(Vector2(fx, fy_px + 2.0), FERN_DAB["r"], FERN_DAB["a"], Color(0.0, 0.04, 0.0))
				_spr(f_tex, Vector2(fx, fy_px), float(hf % 628) / 100.0 + fsway, f_scl, f_col)
				# Context bias (GPT round-2): vegetation drifts hug dirt-patch
				# cells (same 64px hash predicate as the ground painter) — the
				# world's features shape the clustering, not just hash frequency.
				var near_dirt := Art.cell_hash(int(fx / 64.0), int((cam_y + fy_px) / 64.0)) % 6 == 0
				if hf % (4 if reg_density == 3 else 5) == 0 or (near_dirt and hf % 3 == 0):
					for clt in 1 + ((hf >> 9) % 3):
						var ch := Art.cell_hash(hf + clt * 37, clt)
						# Min-distance ring (GPT round-2): satellites sit 6-15px
						# out on a hash angle — never stacked on the anchor.
						var c_ang := float(ch % 628) / 100.0
						var c_dist := 6.0 + float((ch >> 4) % 10)
						var c_tex: String = ug_species[(ch >> 2) % 3]
						_spr(c_tex, Vector2(fx, fy_px) + Vector2.from_angle(c_ang) * c_dist,
							c_ang * 2.0, 0.30 * (0.6 + 0.2 * float((ch >> 5) % 4)) * 0.8,
							fern_col.lerp(Color(0.72, 0.78, 0.5), float((ch >> 7) % 5) / 8.0))

	# Dirt-patch fern fringing (7-vote de-checkerboard, part e): 1-2 ferns on
	# the border of each 64px dirt cell (same hash predicate as _paint_bg) so
	# no 90-degree patch corner survives naked.
	var doy := -fposmod(cam_y, 64.0)
	var dbase_iy := int(floor(cam_y / 64.0))
	for ty in 8:
		for tx in 10:
			var hd := Art.cell_hash(tx, dbase_iy + ty)
			if hd % 6 != 0:
				continue
			var dpos := Vector2(tx * 64.0, floor(doy + ty * 64.0))
			for fr in 1 + (hd % 2):
				var hfr := Art.cell_hash(tx * 7 + fr + 3, dbase_iy + ty)
				var edge_ang := float(hfr % 628) / 100.0
				var fpos := dpos + Vector2(32.0, 32.0) + Vector2.from_angle(edge_ang) * (26.0 + float(hfr % 8))
				if ug_band == 4:
					# Foundry (c2 judge r1: no residual green): fringe with
					# charred scrub, not ferns.
					_spr(_TREE_DEAD[hfr % 3], fpos, 0.0, 0.12, Color(0.2, 0.17, 0.15))
				else:
					_spr("fern", fpos, edge_ang, 0.22 + float(hfr % 3) * 0.03, fern_col)

	# Jungle tree lines on the flanks, sparse singles in the field.
	var toy := -fposmod(cam_y, 48.0)
	for ty in 9:
		var wy := toy + ty * 48.0
		var iy := int(floor((cam_y + wy) / 48.0))
		for tx in 14:
			var h2 := Art.cell_hash(tx * 31, iy)
			var margin: bool = tx < 2 or tx > 11
			if (margin and h2 % 3 != 0) or (not margin and h2 % 19 == 0):
				var px := tx * 48.0 + float(h2 % 24) - 12.0
				var wy_px := wy + float((h2 / 7) % 20)
				var world_x := int(px / PX)
				var world_y := sim.camera_top + int(wy_px / PX)
				if _in_wbands(wbands, world_x, world_y):
					continue
				var big := h2 % 5 == 0
				var tsway := sin(float(Engine.get_physics_frames()) * 0.03 + float(h2)) * 0.04 * _motion
				# a3-04 AD#4/ENV#2: a large soft canopy dapple pooled under each LIVING tree —
				# the committed DARK the open jungle lacked (the grid mottle is uniform and
				# light, so wide fields read flat). Anchored per-tree and offset DOWN-screen so
				# the shade implies a top light direction (nods to ENV#9). Dead canopy casts none.
				if _has_canopy_dapple(ash):
					_ground_shadow(Vector2(px + float(h2 % 9) - 4.0, wy_px + 9.0),
						28.0 if big else 20.0, 0.16, Color(0.0, 0.035, 0.02))
				_ground_shadow(Vector2(px, wy_px), 6.0 if big else 4.0)
				if ash > 0.33:
					# Past the ash midpoint the canopy dies for real: swap to the baked
					# dead-tree set (hash-picked per tree) instead of only tinting green art.
					# Band 4 (c2 judge r3): even the dead set chars to charcoal — no
					# warm bark survives the foundry.
					_spr(_TREE_DEAD[h2 % 3], Vector2(px, wy_px),
						float(h2 % 628) / 100.0 + tsway, 0.42 if big else 0.34,
						Color(0.24, 0.20, 0.18) if ug_band == 4 else Color.WHITE)
				else:
					# a2-08 AD#9/ENV#8: per-instance scale + tint-value jitter (and a rare dead
					# tree) so the tree layer stops reading as one card stamped repeatedly.
					var ti := _tree_instance(h2)
					var tsc: float = (0.42 if big else 0.34) * float(ti["scale_mul"])
					var tval := tree_col.lerp(tree_col.darkened(0.22), float((h2 / 7) % 5) / 4.0)
					if ti["dead"]:
						_spr(_TREE_DEAD[h2 % 3], Vector2(px, wy_px), float(h2 % 628) / 100.0 + tsway,
							tsc, tval.lerp(Color(0.42, 0.36, 0.3), 0.5))
					else:
						_spr("tree_large" if big else "tree_small", Vector2(px, wy_px),
							float(h2 % 628) / 100.0 + tsway, tsc, tval)

	# a3-10 (AD#9/ENV#5): the MARSH floor gets wet — reflective silt patches with a cool
	# sheen so the mid-game sector reads as a WETLAND, not generic green (the water shader
	# wets only water bodies, never the DRY marsh ground). Under the props/signatures.
	if ug_band == 2:
		_draw_marsh_wetness(cam_y)
	# War-torn battlefield litter: sparse, deterministic scatter of the
	# Per-band SIGNATURE silhouettes under the litter (c2 3v): each sector owns
	# one prop family the others never show.
	_draw_band_signatures(cam_y, wbands)
	_draw_ruins_rubble()
	_draw_trenches()
	# legacy art Military props (barrels, crates, wrecks, rocks, wire, tents).
	# Hash grid decorrelated from trees/ferns so nothing stacks on a cell.
	var loy := -fposmod(cam_y, 80.0)
	for ty in 6:
		var ly := loy + ty * 80.0
		var liy := int(floor((cam_y + ly) / 80.0))
		for tx in 8:
			var hl := Art.cell_hash(tx * 53 + 11, liy * 7 + 3)
			if hl % (9 - int(_sector_march() * 3.0)) != 0:   # density ramps with the war (decor only)
				continue
			var lx := tx * 84.0 + float(hl % 40) - 20.0
			var ly_px := ly + float((hl / 9) % 40)
			var row_wy := sim.camera_top + int(ly_px / PX)
			if _in_wbands(wbands, int(lx / PX), row_wy):
				continue
			# Setpiece suppression: no plain scatter within 120px of a stamp —
			# stamps must read as PLACES, not locally denser noise.
			var sp_band := absi(row_wy) / (400 * Fixed.ONE)
			var sp_hash := Art.cell_hash(sp_band * 7, 13)
			if sp_hash % 2 == 0:
				var sp_x := 100.0 + float(sp_hash % 440)
				var sp_wy: int = -(sp_band * 400 + 200) * Fixed.ONE
				if absi(row_wy - sp_wy) < 120 * Fixed.ONE and absf(lx - sp_x) < 120.0:
					continue
			# Rows already on screen when the march last stepped keep their old
			# pool (see the _litter_cam_snap freeze in _draw) — a gate opening
			# must not swap standing props' identity mid-frame.
			var lm := _litter_march_prev if row_wy >= _litter_cam_snap else _sector_march()
			# Band-picked pools (5v biome journey): early jungle scatter, stump
			# fields, crater/wreck marsh, then the late war-torn pool — instead
			# of a two-pool percentage blend that mushed the middle sectors.
			var lband := clampi(int(lm * 5.0 + 0.0001), 0, 4)
			var pool: Array = [_LITTER_EARLY, _LITTER_MID_A, _LITTER_MID_B, _LITTER_LATE, _LITTER_FOUNDRY][lband] \
				if (hl % 100) < 55 + int(lm * 45.0) else _LITTER_EARLY
			var key: String = pool[(hl / 40) % pool.size()]
			# Recessed/flat props cast no disc: a drop shadow under a crater or a
			# fallen body reads as floating art.
			if key != "crater" and key != "corpse_soldier1" and key != "corpse_soldier2":
				_ground_shadow(Vector2(lx, ly_px), 5.0)
			_spr(key, Vector2(lx, ly_px), float(hl % 628) / 100.0, 1.0)


func _in_wbands(wbands: Array, wx: int, wy: int) -> bool:
	# View-local mirror of sim._in_water over the pre-snapshotted in-view bands
	# (see _draw_terrain) — same fixed-point semantics, no per-cell sim scan.
	for b4: Array in wbands:
		if wy >= b4[0] and wy <= b4[1] and (wx < b4[2] or wx > b4[3]):
			return true
	return false


func _draw_ruins_rubble() -> void:
	# c3 5v: the seg-3 half-speed rubble VERB drawn at the sim's exact _in_rubble
	# positions (art==collision) — a debris-strewn slow patch so the zone reads
	# before you slog into it. Re-derives the same _mix as the sim; view-only.
	var seg_h: int = SimWorld.GATE_SPACING
	# Only seg-3 rows can carry rubble; find the seg-3 band(s) on screen.
	var top_wy: int = sim.camera_top
	var bot_wy: int = sim.camera_top + 420 * Fixed.ONE
	for band in range(absi(top_wy) / seg_h, absi(bot_wy) / seg_h + 1):
		if band != SimWorld.RUINS_SEG:
			continue
		for k in 2:
			var rh: int = SimWorld._mix(SimWorld.RUINS_SEG * 100 + k, sim._world_seed)
			var ry_off: int = (250 + k * 380 + rh % 120) * Fixed.ONE
			var rx: int = (100 + (rh >> 8) % 420) * Fixed.ONE
			var wy: int = -(band * seg_h) - ry_off   # band world y (negative) + offset
			var pc := _to_screen(rx, wy)
			if pc.y < -40.0 or pc.y > 400.0:
				continue
			# Slow-zone floor tint (80x40 to match the AABB) + scattered chunks.
			draw_rect(Rect2(pc + Vector2(-40.0, -20.0), Vector2(80.0, 40.0)), Color(0.28, 0.24, 0.2, 0.5))
			for db in 6:
				var dh := Art.cell_hash(rh + db * 29, db)
				draw_rect(Rect2(pc + Vector2(float(dh % 72) - 36.0, float((dh / 5) % 36) - 18.0),
					Vector2(4.0 + float(dh % 5), 3.0 + float(dh % 4))), Color(0.22, 0.19, 0.16, 0.85))


func _draw_trenches() -> void:
	# c3 2v: the sunken TRENCH verb (85% slow + conceal) drawn at the sim's exact
	# _in_trench positions (art==collision) — a recessed ditch with a lit top lip
	# and a shadowed floor so the depth reads before you drop in. Re-derives the
	# same _mix; view-only, band >= COVER_VARIETY_SEG like the sim.
	var seg_h: int = SimWorld.GATE_SPACING
	var top_wy: int = sim.camera_top
	var bot_wy: int = sim.camera_top + 420 * Fixed.ONE
	for band in range(absi(top_wy) / seg_h, absi(bot_wy) / seg_h + 1):
		if band < SimWorld.COVER_VARIETY_SEG:
			continue
		var th: int = SimWorld._mix(band * 70 + 7, sim._world_seed)
		var ty_off: int = (200 + th % 500) * Fixed.ONE
		var tx: int = (120 + (th >> 8) % 380) * Fixed.ONE
		var wy: int = -(band * seg_h) - ty_off
		var pc := _to_screen(tx, wy)
		if pc.y < -60.0 or pc.y > 420.0:
			continue
		# 120x48 AABB (matches _in_trench). Dark recessed floor, a lit top lip and
		# a darker bottom shadow to sell depth on a flat top-down view.
		var w := 120.0
		var h := 48.0
		draw_rect(Rect2(pc + Vector2(-w / 2.0, -h / 2.0), Vector2(w, h)), Color(0.14, 0.15, 0.13, 0.55))
		draw_rect(Rect2(pc + Vector2(-w / 2.0, -h / 2.0), Vector2(w, 4.0)), Color(0.34, 0.35, 0.3, 0.6))
		draw_rect(Rect2(pc + Vector2(-w / 2.0, h / 2.0 - 4.0), Vector2(w, 4.0)), Color(0.05, 0.05, 0.05, 0.5))
		for st in 3:
			var sh := Art.cell_hash(th + st * 17, st)
			var sxx := float(sh % 112) - 56.0
			draw_rect(Rect2(pc + Vector2(sxx, -h / 2.0 + 6.0), Vector2(2.0, h - 12.0)), Color(0.1, 0.1, 0.09, 0.4))


func _draw_band_signatures(cam_y: float, wbands: Array) -> void:
	# Per-band SIGNATURE silhouettes (c2 3v: sectors were palette swaps): band
	# 1 scorched = cracked ember vents, band 2 marsh = field reed screens,
	# band 3 ruins = freestanding half-walls, band 4 foundry = slag ridges
	# with glowing pits. Hash grid (decorrelated salt), march-frozen like
	# litter, water-band aware. Jungle (band 0) stays clean — its identity IS
	# the lushness. All draw-only; densities are the tuning knobs.
	var soy := -fposmod(cam_y, 80.0)
	for ty in 6:
		var sy := soy + ty * 80.0
		var siy := int(floor((cam_y + sy) / 80.0))
		for tx in 8:
			var hs := Art.cell_hash(tx * 71 + 29, siy * 13 + 5)
			var sx := tx * 84.0 + float(hs % 48) - 24.0
			var sy_px := sy + float((hs / 11) % 48)
			var row_wy := sim.camera_top + int(sy_px / PX)
			if _in_wbands(wbands, int(sx / PX), row_wy):
				continue
			var sm := _litter_march_prev if row_wy >= _litter_cam_snap else _sector_march()
			match clampi(int(sm * 5.0 + 0.0001), 0, 4):
				1:
					if hs % 14 == 0:
						# Cracked ground vent: dark crater mouth + breathing ember pit.
						_spr("crater", Vector2(sx, sy_px), float(hs % 628) / 100.0, 0.9,
							Color(0.3, 0.25, 0.22))
						var e_a := (0.5 - absf(fposmod(float(Engine.get_physics_frames() + hs),
							120.0) / 120.0 - 0.5)) * 0.8
						draw_circle(Vector2(sx, sy_px), 1.6, Color(1.0, 0.45, 0.15, e_a))
				2:
					if hs % 10 == 0:
						# Reed screen: a short row of field reeds away from the river.
						for rj in 4 + hs % 3:
							var rh := Art.cell_hash(hs + rj * 41, rj)
							_spr("fern2", Vector2(sx + float(rj * 7) - 12.0 + float(rh % 5),
								sy_px + float((rh / 7) % 7) - 3.0), float(rh % 628) / 100.0,
								0.26 + 0.06 * float(rh % 3), Color(0.62, 0.72, 0.5))
				3:
					if hs % 16 == 0:
						# Half-wall: dark base slab + a broken barrier pair.
						draw_rect(Rect2(Vector2(sx - 14.0, sy_px - 4.0), Vector2(28.0, 8.0)),
							Color(0.16, 0.15, 0.13, 0.8))
						_spr("barrier", Vector2(sx - 7.0, sy_px - 2.0), 0.0, 0.5, Color(0.62, 0.6, 0.55))
						_spr("barrier", Vector2(sx + 7.0, sy_px - 3.0), 0.0, 0.45, Color(0.55, 0.53, 0.5))
				4:
					if hs % 5 == 0:
						# Slag ridge (judge r1+r2: bigger, denser, more opaque):
						# heavy dark cards + a glowing fissure of vent pits.
						for sc in 3 + hs % 2:
							var sh2 := Art.cell_hash(hs + sc * 17, sc)
							draw_set_transform(Vector2(sx + float(sh2 % 33) - 16.0,
								sy_px + float((sh2 / 5) % 17) - 8.0),
								float(sh2 % 628) / 100.0, Vector2.ONE)
							draw_rect(Rect2(Vector2(-28.0, -9.0), Vector2(56.0, 18.0)),
								Color(0.12, 0.10, 0.09, 0.95))
						draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
						var g_a := (0.5 - absf(fposmod(float(Engine.get_physics_frames() + hs),
							90.0) / 90.0 - 0.5)) * 0.9
						draw_circle(Vector2(sx + 6.0, sy_px), 1.8, Color(1.0, 0.5, 0.18, g_a))
						draw_circle(Vector2(sx - 10.0, sy_px + 4.0), 1.4, Color(1.0, 0.4, 0.12, g_a * 0.7))
						draw_circle(Vector2(sx - 2.0, sy_px - 5.0), 1.2, Color(1.0, 0.6, 0.22, g_a * 0.8))


func _draw_foundry_arena() -> void:
	# c4 2v: three tinted concentric RINGS around the boss so the rotating safe
	# annulus reads — an inner melee-risk ring (red) and the outer boundary of the
	# safe belt (green); both radii GROW with the phase (HP thirds), so the safe
	# band visibly migrates outward as the boss escalates. View-only.
	if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
		var cpos := _to_screen(sim.colossus["x"], sim.colossus["y"])
		var ph: int = sim.colossus_phase()
		var ir := float(SimWorld.COLOSSUS_RING_INNER + (ph - 1) * SimWorld.COLOSSUS_RING_STEP)
		var mr := float(SimWorld.COLOSSUS_RING_OUTER + (ph - 1) * SimWorld.COLOSSUS_RING_STEP)
		var ra := 0.12 + 0.06 * Art.pulse(0.05)
		draw_arc(cpos, ir, 0.0, TAU, 48, Color(1.0, 0.3, 0.15, ra), 2.0)   # inner danger ring
		draw_arc(cpos, mr, 0.0, TAU, 48, Color(0.35, 0.8, 0.45, ra), 2.0)  # safe-belt outer edge
	# Foundry ARENA dressing (c2 3v: the finale was "a big enemy in a field").
	# Molten pools ring the three KIMK barrel clusters (drawn UNDER them —
	# each phase-shift cook now torches a molten stage mark), grounded
	# smokestacks flank the rim. View-only, anchored to the read-only final
	# gate; the band-4 species table already chars the undergrowth here.
	for g in sim.gates:
		if not g.get("final", false):
			continue
		var pt := Art.pulse(0.06)
		# Molten CHANNELS (judge r2): glowing feed-lines link the three pools —
		# the floor reads as an active pour circuit, not scattered puddles.
		var pool_pts: Array[Vector2] = []
		for fbx in [100, 296, 500]:   # ring the sim's phase-barrel clusters (c2-10 margin-safe coords)
			pool_pts.append(_to_screen(fbx * Fixed.ONE, g["y"] + 144 * Fixed.ONE))
		for ci in pool_pts.size() - 1:
			var a2 := pool_pts[ci]
			var b2 := pool_pts[ci + 1]
			if maxf(a2.y, b2.y) > -60.0 and minf(a2.y, b2.y) < 420.0:
				draw_line(a2, b2, Color(0.10, 0.07, 0.06, 0.9), 7.0)
				draw_line(a2, b2, Color(1.0, 0.45, 0.12, 0.35 + pt * 0.2), 2.5)
		for pp in pool_pts:
			if pp.y > -60.0 and pp.y < 420.0:
				draw_circle(pp, 24.0, Color(0.12, 0.08, 0.07, 0.85))
				# a1-10: the pool ROILS — hot layers wobble off-center + breathe and ember
				# bubbles rise, so it reads as LIVE molten metal churning, not a static bullseye.
				var pph := float(Engine.get_physics_frames()) * 0.08 + pp.x * 0.05
				var woff := Vector2(sin(pph) * 2.4, cos(pph * 1.3) * 2.0) * _motion
				draw_circle(pp + woff * 0.5, 19.0 + sin(pph * 0.7) * 1.5, Color(0.8, 0.25, 0.08, 0.5 + pt * 0.2))
				draw_circle(pp + woff, 12.0 + sin(pph + 1.0) * 1.8, Color(1.0, 0.5, 0.15, 0.55 + pt * 0.25))
				draw_circle(pp + woff * 1.3, 6.0 + sin(pph * 1.5) * 1.2, Color(1.0, 0.85, 0.45, 0.75 + sin(pph * 2.0) * 0.2))
				for bi in 3:
					var bt := fposmod(pph * 0.5 + float(bi) * 0.33, 1.0)
					# a1-10 r2: embers kept INSIDE the 24px crucible rim (rise 11 + horiz 6 +
					# radius) and fade toward the top so none crawl past the pool edge.
					draw_circle(Vector2(pp.x + sin(pph + float(bi) * 2.1) * 6.0, pp.y - bt * 11.0),
						(1.0 - bt) * 2.0, Color(1.0, 0.7, 0.3, (1.0 - bt) * (1.0 - bt) * 0.85))
				# a2-09 ENV#3: rising HEAT-HAZE — the crucible radiates hot air into the
				# frame (translucent warm blobs rising + fading above the pool), so it reads
				# as a working foundry, not a painted disc.
				for hz in 3:
					var ht := fposmod(pph * 0.22 + float(hz) * 0.34, 1.0)
					var hr := 13.0 + ht * 18.0
					draw_texture_rect(Art.tex("fx_softspot"),
						Rect2(pp.x - hr + sin(pph + float(hz)) * 4.0, pp.y - 6.0 - ht * 28.0, hr * 2.0, hr * 1.5),
						false, Color(1.0, 0.55, 0.25, (1.0 - ht) * 0.14 * _motion))
				# a2-09 r3: a soft STATIC haze cap so the radiate reads in a still frame too.
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(pp.x - 26.0, pp.y - 34.0, 52.0, 40.0),
					false, Color(1.0, 0.5, 0.22, 0.03 + 0.05 * _motion))
				# a2-09 r2 ENV#6: a couple SLAG chunks beside the pool — dark cooled metal
				# with a hot seam — so the floor reads as industrial slag, not bare ground.
				for sg in 2:
					var sgh := int(pp.x) + sg * 37
					var sgp := pp + Vector2(19.0 - 38.0 * float(sg) + float(sgh % 5) - 2.0, 13.0 + float((sgh / 5) % 6))
					var sgr := 3.0 + float(sgh % 3)
					draw_circle(sgp, sgr, Color(0.10, 0.08, 0.07, 0.9))
					draw_circle(sgp + Vector2(0, -1), 1.4, Color(1.0, 0.45, 0.15, 0.5 + pt * 0.2))
					draw_line(sgp + Vector2(-sgr, 1.0), sgp + Vector2(sgr, 1.0), Color(0.05, 0.04, 0.03, 0.7), 1.0)
		# Scrap heaps + pipe run (judge r2): wrecked-industry mass around the
		# boss path, riding loaded litter textures — no new assets.
		var pipe_a := _to_screen(40 * Fixed.ONE, g["y"] + 250 * Fixed.ONE)
		var pipe_b := _to_screen(600 * Fixed.ONE, g["y"] + 250 * Fixed.ONE)
		if pipe_a.y > -60.0 and pipe_a.y < 420.0:
			draw_line(pipe_a, pipe_b, Color(0.22, 0.18, 0.16, 0.9), 5.0)
			for rv in 8:
				draw_circle(pipe_a.lerp(pipe_b, float(rv) / 7.0), 2.2, Color(0.32, 0.26, 0.22))
		for sk in [[160, 90, "wreck_halftrack"], [420, 60, "crater_field"], [250, 230, "wreck_halftrack"]]:
			var sp3 := _to_screen(sk[0] * Fixed.ONE, g["y"] + sk[1] * Fixed.ONE)
			if sp3.y > -60.0 and sp3.y < 420.0:
				_ground_shadow(sp3, 9.0, 0.4)
				_spr(sk[2], sp3, float(sk[0]) * 0.01, 0.9, Color(0.45, 0.38, 0.34))
		# Forge floor (judge r3): crucible platforms on the boss path — low
		# dark slabs with rivets + a molten-cored crucible each, so the floor
		# between the pools reads as a working pour floor.
		for fp in [[200, 190], [440, 250]]:
			var fpp := _to_screen(fp[0] * Fixed.ONE, g["y"] + fp[1] * Fixed.ONE)
			if fpp.y > -60.0 and fpp.y < 420.0:
				draw_rect(Rect2(fpp + Vector2(-24.0, -12.0), Vector2(48.0, 24.0)), Color(0.15, 0.13, 0.12, 0.95))
				for rv2 in 4:
					draw_circle(fpp + Vector2(-18.0 + float(rv2) * 12.0, -9.0), 1.4, Color(0.3, 0.25, 0.22))
				draw_circle(fpp + Vector2(8.0, 4.0), 6.0, Color(0.1, 0.08, 0.07))
				draw_circle(fpp + Vector2(8.0, 4.0), 3.5, Color(1.0, 0.55, 0.18, 0.6 + pt * 0.25))
		# Smokestack CLUSTERS (judge r2/r3: industrial verticals must dominate
		# the MID-ARENA frustum, not just the rims) — five rim stacks plus two
		# big in-fight forge towers on the boss path.
		for ck in [[70, 40, 1.15], [116, 58, 0.9], [560, 70, 1.15], [516, 92, 0.9], [120, 320, 1.0],
				[250, 150, 1.4], [480, 330, 1.3]]:
			var cp := _to_screen(ck[0] * Fixed.ONE, g["y"] + int(ck[1]) * Fixed.ONE)
			if cp.y > -80.0 and cp.y < 440.0:
				_ground_shadow(cp + Vector2(0, 22), 17.0, 0.45)
				_spr("skyline_chimney", cp, 0.0, ck[2], Color(0.36, 0.3, 0.28))
				for pk2 in 3:
					var s_ph := fposmod(float(Engine.get_physics_frames()) / 120.0 + float(pk2) / 3.0, 1.0)
					draw_circle(cp + Vector2(sin(s_ph * TAU + float(ck[0])) * 4.0,
						(-26.0 - s_ph * 34.0) * ck[2]),
						3.0 + s_ph * 6.0, Color(0.25, 0.23, 0.22, (1.0 - s_ph) * 0.45))
		return


func _draw_marsh_wetness(cam_y: float) -> void:
	# a3-10: scattered wet-silt pools with a cool sheen glint — the marsh reads as a
	# waterlogged wetland. Deterministic hash scatter (no rng); pools are dark cool silt,
	# each with a small offset specular highlight so it reads WET, not just dark.
	var woy := -fposmod(cam_y, 96.0)
	var wbase := int(floor(cam_y / 96.0))
	for ty in 5:
		for tx in 7:
			var h := Art.cell_hash(tx * 23 + 7, (wbase + ty) * 5 + 1)
			if h % 3 != 0:
				continue
			var wp := Vector2(tx * 96.0 + float(h % 44), woy + ty * 96.0 + float((h / 7) % 44))
			var ws := 20.0 + float(h % 18)
			# Dark cool silt pool.
			var pc: Color = MARSH_WET["pool_col"]
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(wp - Vector2(ws, ws) / 2.0, Vector2(ws, ws)),
				false, Color(pc.r, pc.g, pc.b, MARSH_WET["pool_a"]))
			# Cool specular sheen, offset up-left so the pool reads WET (a glint off water).
			var sh := ws * 0.42
			var sc: Color = MARSH_WET["sheen_col"]
			draw_texture_rect(Art.tex("fx_softspot"),
				Rect2(wp + Vector2(-sh * 0.35, -sh * 0.55), Vector2(sh, sh * 0.6)),
				false, Color(sc.r, sc.g, sc.b, MARSH_WET["sheen_a"]))


func _draw_rocks() -> void:
	# Cover TIERS (c2 3v: one-size rocks made every LOS puzzle "is there a rock
	# between us"). Kind picks the silhouette class — classic rock, pass-through
	# grass (no hard shadow, you see ground through it), wide ruined-wall slab,
	# and the 2x hero wreck at each hardpoint. Draw size tracks each kind's
	# collision extent (KIMK art==collision pin).
	for rk in sim.rocks:
		var pos := _to_screen(rk["x"], rk["y"])
		if pos.y < -30.0 or pos.y > 390.0:
			continue
		var rh3 := Art.cell_hash(rk["x"] / 65536, rk["y"] / 65536)
		var fade := _bottom_fade(pos.y)   # c2 2v: fade cover off the player's back
		match rk.get("kind", 0):
			1:
				# Tall grass: soft green clump, NO hard shadow — concealment,
				# not a wall. The lighter translucent read telegraphs "you can
				# stand in this but bullets pass through."
				var g_sway := sin(float(Engine.get_physics_frames()) * 0.04 + float(rh3)) * 0.06 * _motion
				for gt in 3:
					var gh := Art.cell_hash(rh3 + gt * 13, gt)
					_spr("hedge", pos + Vector2(float(gh % 44) - 22.0, float((gh / 5) % 30) - 15.0),
						g_sway + float(gh % 628) / 100.0, 0.5, Color(0.5, 0.72, 0.42, 0.82 * fade))
			2:
				# Ruined wall slab: wide, low, hard — the corridor narrows to
				# lanes between slabs (40x10 extent → 80x20 footprint).
				_ground_shadow(pos, 20.0, 0.45 * fade)
				draw_rect(Rect2(pos + Vector2(-40.0, -10.0), Vector2(80.0, 20.0)), Color(0.30, 0.28, 0.26, fade))
				draw_rect(Rect2(pos + Vector2(-40.0, -10.0), Vector2(80.0, 5.0)), Color(0.42, 0.40, 0.37, fade))
				for bk2 in 3:
					draw_rect(Rect2(pos + Vector2(-40.0 + float(bk2) * 26.0, -10.0), Vector2(2.0, 20.0)),
						Color(0.18, 0.16, 0.15, fade))
			3:
				# Hero wreck: the focal ~2x silhouette anchoring each hardpoint.
				# Scale 1.7 reads clearly 1.5-2x a classic rock (judge r1) while
				# still matching the 32x24 collision (art==collision pin).
				_ground_shadow(pos + Vector2(0, 8), 26.0, 0.5 * fade)
				_spr("wreck_halftrack", pos, float(rh3 % 628) / 100.0, 1.7, Color(0.62, 0.56, 0.5, fade))
			_:
				_ground_shadow(pos, 12.0, 0.42 * fade)
				var rtex: String = ["rock1", "rock2", "tree_dead2"][rh3 % 3]   # logs are REAL cover now too
				var rcol := Color(0.78, 0.8, 0.78) if rtex != "tree_dead2" else Color(0.7, 0.62, 0.5)
				var rsc: float = {"rock1": 1.3, "rock2": 1.05, "tree_dead2": 0.35}[rtex]
				_spr(rtex, pos, float(rh3 % 628) / 100.0, rsc, Color(rcol.r, rcol.g, rcol.b, fade))
				# a3-09 (AD#6): a lit top-edge highlight — a thin warm crescent on the
				# boulder's upper rim implies overhead light, so a rock reads as RAISED
				# cover (the inverse of a1-07's crater inner-pit), not a threat or a hole.
				# Only the domed boulders; the flat log (tree_dead2) has no raised rim.
				if _rock_has_top_light(rtex):
					var rr := 9.0 * rsc + 2.0
					draw_arc(pos + Vector2(0.0, 0.5), rr, PI + 0.55, TAU - 0.2, 12,
						Color(ROCK_TOP_LIGHT.r, ROCK_TOP_LIGHT.g, ROCK_TOP_LIGHT.b, 0.5 * fade), 1.8)


func _draw_sandbags() -> void:
	# Player-authored cover: the gate-wall bake at field scale, warm-tinted so
	# YOUR cover reads apart from the neutral gate walls.
	for sb in sim.sandbags:
		var pos := _to_screen(sb["x"], sb["y"])
		if pos.y < -20.0 or pos.y > 380.0:
			continue
		# 9/9 panel: cover must sit as heavy as a barrel (0.42 armor-grade
		# shadow) and live in the khaki band — the old warm tan collided with
		# the warm hulk/threat grammar. Value lifted ~0.1 over the dirt cards.
		var sb_fade := _bottom_fade(pos.y)   # c2 2v: fade off the player's back
		_ground_shadow(pos, 10.0, 0.42 * sb_fade)
		_spr("wall_sandbag", pos, 0.0, 0.62, Color(1.02, 0.98, 0.74, sb_fade))
		# Field weathering (DS round-2 feedback): a soft dirt gradient at the
		# base + sparse hash-placed scuff speckles — planted cover reads
		# dug-in, not factory-fresh. All translucent overdraw, no new assets.
		draw_rect(Rect2(pos + Vector2(-14.0, 3.0), Vector2(28.0, 2.2)), Color(0.25, 0.18, 0.10, 0.10))
		draw_rect(Rect2(pos + Vector2(-12.0, 4.4), Vector2(24.0, 1.4)), Color(0.25, 0.18, 0.10, 0.06))
		for spk in 4:
			var sh2 := Art.cell_hash(sb["x"] / 65536 + spk * 7, sb["y"] / 65536 + spk * 13)
			draw_circle(pos + Vector2(-11.0 + float(sh2 % 23), -2.5 + float((sh2 / 23) % 6)), 0.7,
				Color(0.30, 0.24, 0.14, 0.08 + float(sh2 % 3) * 0.02))

func _draw_mines() -> void:
	for m in sim.mines:
		if not m["armed"]:
			continue
		var mp := _to_screen(m["x"], m["y"])
		# Band cull (same idiom as _draw_barrels): mines stream up to 2 view-
		# heights ahead and each draws ring + claymore + pips invisibly up there.
		if mp.y < -40.0 or mp.y > 400.0:
			continue
		# Danger telegraph keeps the mine FAIR: a pulsing ring + a blinking
		# armed-indicator so you can spot it and herd rushers onto it (or route
		# around it yourself). YOUR planted claymore rings cyan instead of the
		# hostile red — same blast, but "my trap" vs "their trap" must read
		# (both sides still trip both; the color is identity, not safety).
		var mb := Art.pulse(0.1)
		var mc := Art.safe(Color(0.3, 0.9, 0.75)) if m.get("friendly", false) else Color(1.0, 0.35, 0.2)
		draw_circle(mp, 8.0 + mb * 3.0, Color(mc.r, mc.g, mc.b, 0.14 + mb * 0.12))
		if m.get("friendly", false):
			# Dashed ring: ownership must survive colorblindness — shape, not hue.
			for seg in 6:
				var a0 := seg * TAU / 6.0
				draw_arc(mp, 7.0 + mb * 2.0, a0, a0 + TAU / 12.0, 5,
					Color(mc.r, mc.g, mc.b, 0.5 + mb * 0.3), 1.2)
		else:
			draw_arc(mp, 7.0 + mb * 2.0, 0, TAU, 16, Color(mc.r, mc.g, mc.b, 0.5 + mb * 0.3), 1.2)
		# Real claymore silhouette (was the plain 'landmine' decor pip). Scale 1.05
		# ~= the old 4.5x0.07 effective size, so the footprint is unchanged.
		# Ground shadow + dark backing disc (c2 4v): the lethal silhouette gets
		# the same grounding grammar as every collidable, and the dark rim keeps
		# it readable on busy late-run litter.
		_ground_shadow(mp, 5.0, 0.42)
		draw_circle(mp, 4.2, Color(0.05, 0.04, 0.03, 0.85))
		_spr("wep_claymore", mp, 0.0, 1.05)
		draw_circle(mp, 2.0, Color(mc.r, mc.g, mc.b, 0.65 + mb * 0.35))


func _draw_vents() -> void:
	# Foundry heat vents (c2): the view re-derives the sim's tick phase — no
	# state, perfectly synced. Idle grate → 30t rising warn shimmer → 60t jet.
	for v in sim.vents:
		var vp := _to_screen(v["x"], v["y"])
		if vp.y < -40.0 or vp.y > 400.0:
			continue
		var ph := posmod(sim.tick_count + 7 * (v["x"] / Fixed.ONE), SimWorld.VENT_CYCLE_TICKS)
		var jet_at := SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS
		# Grate: dark slotted disc, always visible — the hazard has a silhouette
		# even mid-idle (hazard-vs-litter rule: lethal objects never camouflage).
		_ground_shadow(vp, 9.0, 0.4)
		draw_circle(vp, 8.0, Color(0.16, 0.13, 0.12))
		draw_arc(vp, 8.0, 0, TAU, 16, Color(0.42, 0.2, 0.1, 0.9), 1.4)
		for s in 3:
			var sy := vp + Vector2(0, -3.0 + s * 3.0)
			draw_line(sy - Vector2(4.5, 0), sy + Vector2(4.5, 0), Color(0.55, 0.3, 0.15, 0.8), 1.2)
		if ph >= jet_at:
			# JET: white-hot core + orange column, flicker off the global clock.
			var jf := 0.75 + 0.25 * Art.pulse(0.035)
			draw_circle(vp, 24.0, Color(1.0, 0.42, 0.1, 0.16 * jf))
			draw_circle(vp, 14.0, Color(1.0, 0.62, 0.2, 0.45 * jf))
			draw_circle(vp, 6.5, Color(1.0, 0.93, 0.7, 0.9))
		elif ph >= jet_at - SimWorld.VENT_WARN_TICKS:
			# WARN: ring tightens over the 30t telegraph — read it, step off.
			var wt := float(ph - (jet_at - SimWorld.VENT_WARN_TICKS)) / float(SimWorld.VENT_WARN_TICKS)
			draw_arc(vp, 24.0 - 14.0 * wt, 0, TAU, 20, Color(1.0, 0.5, 0.15, 0.35 + 0.45 * wt), 1.6)


func _draw_barrels() -> void:
	for bl in sim.barrels:
		if not bl["armed"]:
			continue
		var bp := _to_screen(bl["x"], bl["y"])
		# Band cull: barrels stream in up to 2 view-heights above the camera and
		# each draws ~15 primitives (10 dash arcs) — the off-screen field was the
		# priciest invisible thing in the frame (same idiom as _draw_water).
		if bp.y < -40.0 or bp.y > 400.0:
			continue
		_ground_shadow(bp, 4.0)
		# Hazard-orange live ordnance, distinct from the mossy scenery barrels.
		var wb := 1.0 if _motion < 0.5 else Art.pulse(0.09)   # steady under reduce-motion
		# CHAIN-LIT: fuse_ticks counts 8->0 to the boom. The lit barrel goes
		# white-hot and its ring flares — the 8-tick "flee NOW" window existed in
		# the sim but was invisible (3-lens consensus: the anticipation beat is
		# where the drama lives). Fast blink is the tell; reduce-motion holds it
		# at full-bright instead (steady, but unmissably hotter than armed).
		var bfuse: int = bl.get("fuse_ticks", 0)
		if bfuse > 0:
			var bheat := 1.0 - float(bfuse) / 8.0
			var bblink := 1.0 if _motion < 0.5 else (0.55 + 0.45 * sin(float(Engine.get_physics_frames()) * 1.6))
			_spr("barrel", bp, 0.0, 1.4, Color(1.0, 0.75 + bheat * 0.25, 0.55 + bheat * 0.45))
			draw_circle(bp + Vector2(0, -2), 2.2 + bheat * 2.0,
				Color(1.0, 0.95, 0.75, (0.6 + bheat * 0.4) * bblink))
			draw_arc(bp, 7.0 + bheat * 3.0, 0, TAU, 16,
				Color(1.0, 0.85, 0.5, (0.5 + bheat * 0.5) * bblink), 1.6 + bheat)
		else:
			_spr("barrel", bp, 0.0, 1.4, Color(1.0, 0.5, 0.2))   # in-gamut hot orange (1.9 clamped to tan)
			draw_circle(bp + Vector2(0, -2), 1.6, Color(1.0, 0.65, 0.22, 0.45 + wb * 0.4))
			draw_arc(bp, 7.0 + wb * 2.0, 0, TAU, 16, Color(1.0, 0.45, 0.15, 0.25 + wb * 0.2), 1.0)
		# Blast-radius ring: shares GRENADE_RADIUS with the player's grenade circle,
		# but a chained barrel HURTS YOU inside it (the grenade never does) — so draw
		# it as a DASHED RED hazard ring (mine/danger grammar), not the friendly
		# smooth-orange kill circle, to flag "opposite consequence".
		var br := SimWorld.GRENADE_RADIUS * PX
		var brc := Color(1.0, 0.2, 0.15, 0.5 + wb * 0.3)
		for di in range(20):   # every-other-segment dashes read as a hazard boundary
			if di % 2 == 1:
				continue
			var a0 := TAU * di / 20.0
			draw_arc(bp, br, a0, a0 + TAU / 20.0, 3, brc, 1.4)
		# Non-color danger cue: hue-blind players got only orange — the "!" pip
		# carries "live ordnance" on the shape channel (destructive-row grammar).
		Art.text(self, "!", bp + Vector2(-2, -10), 8, Color(1.0, 0.9, 0.5, 0.7 + wb * 0.3))


func _draw_water() -> void:
	# Banks and ford bed scorch with the run like the gates' walls (grass, litter
	# and the shader's wsoot already march) — no postcard-beige strips late-run.
	var soot := clampf(_sector_march() * 0.7, 0.0, 0.7)
	var bank_col := Color(0.9, 0.85, 0.7).lerp(Color(0.5, 0.45, 0.4), soot)
	var ford_col := Color(0.85, 0.8, 0.65).lerp(Color(0.47, 0.43, 0.38), soot)
	for w in sim.waters:
		var wy := _to_screen(0, w["y"]).y
		var wh := SimWorld.WATER_H * PX
		# Band cull (mirrors _sync_water): the sim never removes water bands, so
		# every crossed river kept drawing banks + bridge + rocks off-screen.
		if wy + wh < -20.0 or wy > 380.0:
			continue
		# Water body, wave ripples and sun glint are the water.gdshader quad synced
		# under the units by _sync_water(); here we only draw what sits ON the water.
		# Banks (drawn over the shader's shore edges).
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy - 6, 640, 8), true, bank_col)
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy + wh - 2, 640, 8), true, bank_col)
		# a2-06 AD#8: a lighter/warmer SHALLOWS band hugging each bank so the river reads
		# with DEPTH (shallow at the edges -> deep mid-channel) instead of a flat slab.
		var wsec2 := clampi(int(_sector_march() * 5.0 + 0.0001), 0, 4)
		var shallows: Color = _WATER_SHALLOW_STOPS[wsec2].lerp(Color(0.72, 0.74, 0.62), 0.45)
		draw_rect(Rect2(0, wy + 1.0, 640.0, 5.0), Color(shallows.r, shallows.g, shallows.b, 0.4))
		draw_rect(Rect2(0, wy + wh - 6.0, 640.0, 5.0), Color(shallows.r, shallows.g, shallows.b, 0.4))
		# Mud banks (2v second terrain): brown half-speed strips flanking the
		# band — drawn under the sand lips so the slow zone reads as terrain.
		# Alpha 0.75 -> 0.92 (c2 3v: half-speed ground must not read as a
		# translucent decal you can ignore).
		var mud_c := Color(0.42, 0.32, 0.2, 0.92).lerp(Color(0.3, 0.25, 0.2, 0.92), soot)
		draw_texture_rect(Art.tex("dirt"), Rect2(0, wy - 6 - 40, 640, 40), true, mud_c)
		draw_texture_rect(Art.tex("dirt"), Rect2(0, wy + wh + 2, 640, 40), true, mud_c)
		# Mud OUTER edge (c2 3v): a 2px dark lip + hash notches on the dry
		# side of both strips — the exact line where half-speed begins reads
		# before you step in. Same deterministic notch idiom as the banks.
		# Lips sit fully OUTSIDE the strips (judge r1: the bottom lip was 1px
		# inside), 2.5px and darker so the grass->mud boundary pops.
		var mud_lip := Color(mud_c.r, mud_c.g, mud_c.b, 1.0).darkened(0.45)
		var mseed := Art.cell_hash(int(w["y"] / 4096) * 53, 19)
		draw_rect(Rect2(0, wy - 48.5, 640.0, 2.5), mud_lip)
		draw_rect(Rect2(0, wy + wh + 42.0, 640.0, 2.5), mud_lip)
		for mk in 12:
			var mnh := Art.cell_hash(mseed + mk * 31, mk)
			draw_rect(Rect2(float(mnh % 630), wy - 48.5 - float(mnh % 3),
				5.0 + float(mnh % 6), 2.5), mud_lip)
			draw_rect(Rect2(float((mnh * 13) % 630), wy + wh + 42.0 + float((mnh >> 3) % 3),
				5.0 + float((mnh >> 5) % 6), 2.5), mud_lip)
		# Broken banks (5v: the ruler-straight sand edge was the tell): ~14
		# hash-notches per bank bite into the strip, skipping the ford span.
		var nseed := Art.cell_hash(int(w["y"] / 4096) * 29, 3)
		var nford_l: float = (w["ford_x"] - SimWorld.FORD_HALF_W) * PX - 12.0
		var nford_r: float = (w["ford_x"] + SimWorld.FORD_HALF_W) * PX + 12.0
		var notch_col := bank_col.darkened(0.25)
		# Wet-sand line: a thin damp band hugging the waterline on both banks
		# (Grok round-2: the dry sand met the water with no transition).
		var damp := bank_col.darkened(0.38)
		draw_rect(Rect2(0, wy + 1.0, 640.0, 1.5), Color(damp.r, damp.g, damp.b, 0.5))
		draw_rect(Rect2(0, wy + wh - 1.5, 640.0, 1.5), Color(damp.r, damp.g, damp.b, 0.5))
		# Foam flecks along the damp line (Grok round-3): irregular low-alpha
		# off-white ticks where water worries the sand.
		var fseed := Art.cell_hash(int(w["y"] / 4096) * 41, 11)
		for fk in 8:
			var fh := Art.cell_hash(fseed + fk * 23, fk)
			var ffx := float(fh % 630)
			var ffw := 2.0 + float(fh % 3)
			draw_rect(Rect2(ffx, wy + 1.0 + float(fh % 2), ffw, 1.0), Color(0.9, 0.94, 0.9, 0.22))
			draw_rect(Rect2(float((fh * 5) % 630), wy + wh - 2.0 - float(fh % 2), ffw, 1.0), Color(0.9, 0.94, 0.9, 0.22))
		for nk in 14:
			var nh := Art.cell_hash(nseed + nk * 17, nk)
			var nx := float(nh % 640)
			if nx > nford_l and nx < nford_r:
				continue
			var nw2 := 6.0 + float(nh % 5)
			var njit := float((nh / 7) % 5) - 2.0
			draw_rect(Rect2(nx, wy - 1.0 + njit, nw2, 2.0 + float(nh % 2)), notch_col)
			draw_rect(Rect2(float((nh * 7) % 640), wy + wh + 1.0 + njit, nw2, 2.0 + float((nh / 3) % 2)), notch_col)
			# Second irregularity scale (Grok round-2): wide shallow bites layered
			# under the small notches so the profile stops reading as dashed.
			if nk % 3 == 0:
				var bw := 14.0 + float(nh % 7)
				draw_rect(Rect2(float((nh * 3) % 620), wy - 2.0, bw, 1.4), Color(notch_col.r, notch_col.g, notch_col.b, 0.6))
				draw_rect(Rect2(float((nh * 11) % 620), wy + wh + 2.5, bw, 1.4), Color(notch_col.r, notch_col.g, notch_col.b, 0.6))
		# The dry ford — at the SIM's compressed per-band width (c2 3v BUG: the
		# view drew full FORD_HALF_W on every band while the sim tightens
		# -4px/band; on deep bands walkable ground rendered as water and drawn
		# sand was lethal water. Formulas copied from sim_world.gd _in_water
		# (band_idx/fw, ford2, island) — keep in sync with those lines.
		var band_idx: int = absi(w["y"] / SimWorld.GATE_SPACING)
		var fw_fx: int = maxi(SimWorld.FORD_HALF_W / 2, SimWorld.FORD_HALF_W - (band_idx - 1) * 4 * Fixed.ONE)
		var ford_left: float = (w["ford_x"] - fw_fx) * PX
		var ford_w := fw_fx * 2.0 * PX
		draw_texture_rect(Art.tex("sand"), Rect2(ford_left, wy - 2, ford_w, wh + 4),
			true, ford_col)
		var wh2m: int = SimWorld._mix(band_idx, w["ford_x"] / Fixed.ONE)
		if band_idx % 3 == 2:
			# Second ford (sim: every 3rd band) — it existed, it was walkable,
			# and the view never drew it. Now it's sand like the first.
			var ford2_x: int = 80 * Fixed.ONE + ((w["ford_x"] - 80 * Fixed.ONE) + (180 + wh2m % 121) * Fixed.ONE) % (480 * Fixed.ONE)
			draw_texture_rect(Art.tex("sand"), Rect2((ford2_x - fw_fx) * PX, wy - 2, ford_w, wh + 4),
				true, ford_col)
		if band_idx >= 4 and band_idx % 4 == 0:
			# Dry mid-river island (sim: every 4th band, deep) with wet lips.
			var isl_x2: int
			if band_idx % 12 == 8:
				var f2i: int = 80 * Fixed.ONE + ((w["ford_x"] - 80 * Fixed.ONE) + (180 + wh2m % 121) * Fixed.ONE) % (480 * Fixed.ONE)
				isl_x2 = 80 * Fixed.ONE + (((w["ford_x"] + f2i) / 2 - 80 * Fixed.ONE) + 240 * Fixed.ONE) % (480 * Fixed.ONE)
			else:
				isl_x2 = 80 * Fixed.ONE + ((w["ford_x"] - 80 * Fixed.ONE) + 120 * Fixed.ONE) % (480 * Fixed.ONE)
			var ilx := (isl_x2 - 60 * Fixed.ONE) * PX
			var ily := wy + 20.0
			draw_texture_rect(Art.tex("sand"), Rect2(ilx, ily, 120.0, 40.0), true, ford_col)
			var idamp := ford_col.darkened(0.38)
			draw_rect(Rect2(ilx, ily - 1.5, 120.0, 1.5), Color(idamp.r, idamp.g, idamp.b, 0.6))
			draw_rect(Rect2(ilx, ily + 40.0, 120.0, 1.5), Color(idamp.r, idamp.g, idamp.b, 0.6))
		# Baked bridge deck over the dry ford (decor only — the sim's ford/collision
		# is untouched; the sand bed stays underneath as the shore blend). Mid planks
		# tile the crossing, ramp caps land on each bank.
		var bspan := 220.0 * Art.draw_scale("bridge_mid")   # ~97px square bake
		var bsc := clampf(ford_w / bspan, 0.5, 1.2)         # fit the deck to the ford width
		var bx := ford_left + ford_w / 2.0
		var bseg := maxi(1, int(ceil(wh / (bspan * bsc))))
		# Bridge shadow on the water + support beams at the segment joints —
		# the deck used to float weightless over the current (5v).
		var deck_w := bspan * bsc * 0.9
		draw_rect(Rect2(bx - deck_w / 2.0 + 4.0, wy + 4.0, deck_w, wh), Color(0.0, 0.02, 0.05, 0.28))
		for bj in bseg + 1:
			var bjy := wy + float(bj) * wh / float(bseg)
			draw_line(Vector2(bx - deck_w / 2.0 + 3.0, bjy), Vector2(bx - deck_w / 2.0 + 3.0, minf(bjy + 6.0, wy + wh)), Color(0.28, 0.2, 0.12), 3.0)
			draw_line(Vector2(bx + deck_w / 2.0 - 3.0, bjy), Vector2(bx + deck_w / 2.0 - 3.0, minf(bjy + 6.0, wy + wh)), Color(0.28, 0.2, 0.12), 3.0)
			for bside in [-1.0, 1.0]:
				var bfx: float = bx + bside * (deck_w / 2.0 - 3.0)
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(bfx - 5.0, minf(bjy + 4.0, wy + wh - 3.0), 10.0, 6.0),
					false, Color(0.0, 0.05, 0.08, 0.30))
		# Caustic glints under the deck (Grok round-3): faint elongated light
		# play between the support beams.
		for cg in 2:
			var cgy := wy + wh * (0.3 + 0.4 * float(cg))
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(bx - deck_w * 0.3, cgy - 2.0, deck_w * 0.6, 4.0),
				false, Color(0.55, 0.75, 0.75, 0.14))
		for bi in bseg:
			_spr("bridge_mid", Vector2(bx, wy + (float(bi) + 0.5) * wh / float(bseg)), 0.0, bsc)
		_spr("bridge_ramp", Vector2(bx, wy - 2.0), 0.0, bsc)
		_spr("bridge_ramp", Vector2(bx, wy + wh + 2.0), PI, bsc)
		# A few deterministic rocks break up the deep water (never in the ford).
		var wseed := Art.cell_hash(int(w["y"] / 4096) * 13, 7)
		for r in 3:
			var rx := float((wseed / (r + 2)) % 600 + 20)
			if rx > ford_left - 12.0 and rx < ford_left + ford_w + 12.0:
				continue
			var ry := wy + wh * (0.3 + 0.4 * float((wseed / (r + 5)) % 90) / 90.0)
			# a2-06 ENV#1: a foam collar where the rock breaks the current + a short
			# upstream wake, so it reads as sitting IN the water, not floating on it.
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(rx - 13.0, ry - 7.0, 26.0, 14.0),
				false, Color(0.82, 0.86, 0.82, 0.22))
			draw_line(Vector2(rx - 6.0, ry - 7.0), Vector2(rx - 3.0, ry - 15.0), Color(0.78, 0.84, 0.8, 0.22), 1.5)
			draw_line(Vector2(rx + 6.0, ry - 7.0), Vector2(rx + 3.0, ry - 15.0), Color(0.78, 0.84, 0.8, 0.22), 1.5)
			_spr("rock1" if (wseed + r) % 2 == 0 else "rock2", Vector2(rx, ry),
				float((wseed / (r + 1)) % 628) / 100.0, 1.4, Color(0.5, 0.58, 0.6))
		# Reed scatter at the waterline (5v): fern2 silhouettes soften where
		# grass meets water; never inside the ford approach.
		for rk in 9:
			var rh := Art.cell_hash(nseed + rk * 31, rk + 9)
			var rrx := float(rh % 620) + 10.0
			if rrx > nford_l and rrx < nford_r:
				continue
			var reed_y := (wy - 4.0) if rk % 2 == 0 else (wy + wh + 2.0)
			# Multi-scale clumps (Grok round-2): big anchor reeds + small tufts.
			_spr("fern2", Vector2(rrx, reed_y), float(rh % 628) / 100.0,
				0.4 + float(rh % 5) * 0.1,
				Color(0.8, 0.9, 0.7).lerp(Color(0.5, 0.45, 0.4), soot))
		# Armor-barrier telegraph: a tank can't ford deep water (it just stops
		# dead at the bank, reading as a broken control). When an occupied tank
		# is near this band, hatch the deep-water banks red and flag the ford.
		var tank_near := false
		for tk in sim.tanks:
			if tk["alive"] and tk["occupant"] >= 0 \
					and absf((tk["y"] - w["y"]) * PX) < 90.0:
				tank_near = true
		if tank_near:
			var hy := wy if (w["y"] > sim.camera_top) else wy + wh
			for hx in range(0, 640, 16):
				if hx + 8 < ford_left or hx > ford_left + ford_w:
					draw_line(Vector2(hx, hy - 4), Vector2(hx + 8, hy + 4), Color(1.0, 0.3, 0.2, 0.7), 1.5)
			# Shadowed + colorblind-routed like the gate pips/price tints that share
			# this green — raw unshadowed green over red-hatched sand was the
			# worst-case read for the tank driver it guides.
			Art.text(self, "FORD", Vector2(ford_left + ford_w / 2.0 - 12, wy - 8),
				8, Art.safe(Color(0.6, 1.0, 0.6)))


func _draw_gates() -> void:
	# Fortified sandbag wall: baked wall segments + end caps (was 14 identical
	# sandbag-pile stamps). Alternate flips keyed off a per-gate hash so no two
	# adjacent segments read identical. Flip trick: angle PI + stretch -1 = h-mirror.
	# The one man-made structure in frame scorches with the run too (grass/foliage/
	# sky already do), so the walls at gate 5 aren't pristine beige like gate 1.
	var soot := clampf(_sector_march() * 0.7, 0.0, 0.7)
	var open_wall := Color(0.7, 0.68, 0.62).lerp(Color(0.34, 0.3, 0.3), soot)
	var shut_wall := Color(1, 1, 1).lerp(Color(0.5, 0.44, 0.42), soot)
	for g in sim.gates:
		var gy := _to_screen(0, g["y"]).y
		# Band cull: gates are never removed from the sim — every opened gate
		# kept stamping its end caps (and a streamed-ahead shut gate its full
		# 11-sprite wall) invisibly, +1 per gate forever.
		if gy < -40.0 or gy > 400.0:
			continue
		var gh := Art.cell_hash(g["y"], 3)
		# Sector numeral (5v biome journey): the wall names its gate — the
		# corridor reads as a JOURNEY with mile-markers, not a treadmill.
		var g_idx := 1
		for og in sim.gates:
			if og["y"] > g["y"]:
				g_idx += 1
		var gnum_col := Color(0.30, 0.27, 0.22, 0.85) if not g["open"] else Color(0.5, 0.46, 0.4, 0.6)
		Art.text(self, str(g_idx), Vector2(320.0 - 4.0, gy - 8.0), 24, gnum_col)
		if g["open"]:
			# Blown-open remnants: a lone end cap survives at each flank.
			_spr("wall_sandbag_end", Vector2(24, gy), 0.0, 1.0, open_wall)
			_spr("wall_sandbag_end", Vector2(616, gy), PI, 1.0, open_wall, -1.0)
		else:
			for i in 9:
				var flip: bool = (i + gh) % 2 == 0
				_spr("wall_sandbag", Vector2(70 + i * 60, gy), PI if flip else 0.0, 1.0,
					shut_wall, -1.0 if flip else 1.0)
			_spr("wall_sandbag_end", Vector2(30, gy), 0.0, 1.0, shut_wall)
			_spr("wall_sandbag_end", Vector2(610, gy), PI, 1.0, shut_wall, -1.0)
			# Lock pips: how many of the two locking bunkers are still up —
			# turns a black-box wall into 'one down, one to go'.
			if not g.get("b1", {}).is_empty():
				var down := int(not g["b1"]["alive"]) + int(not g["b2"]["alive"])
				for k in 2:
					var lit: bool = k >= down
					draw_circle(Vector2(300 + k * 40, gy), 5.0,
						Color(1.0, 0.3, 0.2) if lit else Art.safe(Color(0.3, 0.7, 0.3)))
					draw_arc(Vector2(300 + k * 40, gy), 5.0, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)

	# Route-fork lane signposts: the approach band south of gates 2 & 4 reads
	# CACHE (left, supplies + mines) vs BOUNTY (right, elites + marked pay).
	# Choice is pure position, so the telegraph must land before the band does.
	for fk in _forks:
		var fy := _to_screen(0, fk["y"] + 180 * Fixed.ONE).y
		if fy < -20.0 or fy > 380.0:
			continue
		# Physical fork island (7v): stacked wrecks divide the lanes at x=260 —
		# CACHE reads narrow/fortified, BOUNTY reads open killbox. c2 2v: SEVEN
		# segments (+70..+610) span the full deepened +40..+620 blocker so the
		# art never stops short of the collision (was three at +320).
		var isl_x := float(fk.get("x", 260 * Fixed.ONE)) * PX
		for wi in 7:
			var wh2 := Art.cell_hash(fk["y"] / 65536 + wi * 13, wi)
			var wy2 := _to_screen(0, fk["y"] + (70 + wi * 90) * Fixed.ONE).y
			if wy2 < -20.0 or wy2 > 380.0:
				continue
			_ground_shadow(Vector2(isl_x, wy2), 12.0, 0.42)
			_spr(["wreck_apc", "tank_hulk", "wreck_halftrack"][wh2 % 3], Vector2(isl_x, wy2),
				float(wh2 % 628) / 100.0 * 0.2 + (PI if wi % 2 == 0 else 0.0), 0.9, Color(0.6, 0.58, 0.55))
		# CACHE wire strips draw ON the sim's slow-band centers (mechanical truth:
		# _in_fork_wire bands are +90..110/+210..230/+330..350/+450..470, so the
		# sprites sit at +100/+220/+340/+460 — no drift off the real hazard).
		var wire_x0 := 30.0 if isl_x < 320.0 else isl_x + 50.0
		for ci in 4:
			var cy2 := _to_screen(0, fk["y"] + (100 + ci * 120) * Fixed.ONE).y
			if cy2 < -20.0 or cy2 > 380.0:
				continue
			for wseg2 in 3:
				_spr("barbedwire", Vector2(wire_x0 + 30.0 + wseg2 * 55.0, cy2), 0.0, 0.8, Color(0.55, 0.5, 0.45))
		# Bait dressing (c2 2v): the trap lane gets EXTRA sandbag cover so it
		# reads as the better-defended reward lane — deliberately NO warning
		# glyph (reading the bait is the skill). Matches the sim's +490/+530 bags.
		if fk.get("bait", false):
			var bait_x := (isl_x + 120.0) if isl_x < 320.0 else (isl_x - 120.0)
			for bd in 2:
				var bdy := _to_screen(0, fk["y"] + (490 + bd * 40) * Fixed.ONE).y
				if bdy < -20.0 or bdy > 380.0:
					continue
				_ground_shadow(Vector2(bait_x, bdy), 10.0, 0.42)
				_spr("wall_sandbag", Vector2(bait_x + bd * 20.0, bdy), 0.0, 0.62, Color(1.02, 0.98, 0.74))
		# 4v legibility pass: 24px (integer 3x of the 8px pixel font = crisp),
		# HUD-family backing plates, Art.text shadow, mirrored 84px margins.
		var cache_txt := "< CACHE"
		var bounty_txt := "BOUNTY >"
		var cw2 := Art.font().get_string_size(cache_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var bw2 := Art.font().get_string_size(bounty_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_rect(Rect2(80.0, fy - 22.0, cw2 + 8.0, 28.0), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(556.0 - bw2 - 4.0, fy - 22.0, bw2 + 8.0, 28.0), Color(0, 0, 0, 0.55))
		Art.text(self, cache_txt, Vector2(84, fy), 24, Art.safe(Color(0.5, 1.0, 0.7)))
		Art.text(self, bounty_txt, Vector2(556.0 - bw2, fy), 24, Color(1.0, 0.75, 0.3))


func _draw_pickups() -> void:
	for pk in sim.pickups:
		var ppos := _to_screen(pk["x"], pk["y"])
		# Band cull (same idiom as _draw_barrels/_draw_mines): the sim never
		# sweeps pickups behind the ratchet camera, so every uncollected elite
		# drop otherwise pays 4-8 draw ops (and priced crates a player scan)
		# per frame forever.
		if ppos.y < -40.0 or ppos.y > 400.0:
			continue
		var tex_name: String
		var mod := Color.WHITE
		match pk["kind"]:
			0: tex_name = "crate_ammo"
			1: tex_name = "crate_grenade"
			2: tex_name = "pickup_vest"     # real vest bake (was a blue-shifted ammo crate)
			3: tex_name = "crate_airstrike"
			_: tex_name = _CAPSULE_TEX[clampi(pk["kind"] - 4, 0, _CAPSULE_TEX.size() - 1)]
		# Maxed check: the sim clamps a buy via mini() against the ammo/grenade
		# cap (or no-ops if vest is already on), so a priced crate at cap would
		# silently eat the coin — grey the crate and swap price for "MAXED".
		var maxed := false
		if pk.get("cost", 0) > 0 and pk["kind"] <= 2:
			var buyer := sim._nearest_alive_player(pk["x"], pk["y"])
			if not buyer.is_empty():
				match pk["kind"]:
					0: maxed = buyer["mg_ammo"] >= SimWorld.MG_AMMO_MAX
					1: maxed = buyer["grenade_ammo"] >= SimWorld.GRENADE_AMMO_MAX
					2: maxed = buyer["vest"]
		if maxed:
			mod = Color(0.55, 0.55, 0.55)
		# Crates sit on the ground like every other grounded prop (litter, barrels,
		# bunkers all cast the soft ellipse) — without it a priced crate read as a
		# floating sticker. Capsules (kind >= 4) keep their pulsing glow disc instead.
		if pk["kind"] <= 3:
			_ground_shadow(ppos, 6.0)
		if pk.get("drop", 0) > 0:
			# Parachute identity (re-review: after the spawn toast faded the
			# objective crate read as ordinary loot): canopy + cyan TTL arc.
			var dfrac := clampf(float(pk["drop"]) / 600.0, 0.0, 1.0)
			var dcol := Art.safe(Color(0.55, 0.9, 1.0))
			draw_arc(ppos, 13.0, 0, TAU, 20, Color(dcol.r, dcol.g, dcol.b, 0.25), 1.0)
			draw_arc(ppos, 13.0, -PI / 2, -PI / 2 + TAU * dfrac, 20, dcol, 1.5)
			var ctop := ppos + Vector2(0, -16.0)
			draw_colored_polygon(PackedVector2Array([ctop + Vector2(-7, 0), ctop + Vector2(7, 0), ctop + Vector2(0, -6)]),
				Color(dcol.r, dcol.g, dcol.b, 0.8))
			draw_line(ctop + Vector2(-7, 0), ppos + Vector2(0, -6), Color(dcol.r, dcol.g, dcol.b, 0.5), 1.0)
			draw_line(ctop + Vector2(7, 0), ppos + Vector2(0, -6), Color(dcol.r, dcol.g, dcol.b, 0.5), 1.0)
		# Lootable salience (4v): common crates get the capsule grammar at lower
		# intensity — a soft safe-green ring + 2px bob (reduce-motion pins the
		# bob at its raised pose, matching the capsule pulse-freeze).
		var cpg := 1.0 if _motion < 0.5 else Art.pulse(0.15)
		if pk.get("cost", 0) > 0 and sim.mode == "endless":
			# Shop pad: priced crates sit on a hazard-striped supply plate —
			# commerce has a PLACE in the arena now.
			draw_rect(Rect2(ppos + Vector2(-36, -14), Vector2(72, 28)), Color(0.08, 0.07, 0.06, 0.55))
			for hz in 6:
				draw_rect(Rect2(ppos.x - 36 + hz * 12, ppos.y + 11, 6, 3), Color(0.8, 0.7, 0.2, 0.5))
		if pk["kind"] <= 3 and not maxed:
			var crring := Art.safe(Color(0.5, 1.0, 0.5))
			draw_arc(ppos, 11.0, 0, TAU, 20, Color(crring.r, crring.g, crring.b, 0.14 + cpg * 0.14), 1.0)
		_spr(tex_name, ppos + (Vector2(0, -2.0 * cpg) if pk["kind"] <= 3 else Vector2.ZERO), 0.0, 0.55, mod)
		# Identity glyph floats above every crate (the vest crate reuses the
		# ammo sprite, so it's ambiguous without this).
		if pk["kind"] >= 4:
			# Rare power-up capsule (pierce/spread): a pulsing glow + ring + rising
			# beam + label so a 1-in-6 elite drop stands out in the chaos (and the
			# out-of-range glyph lookup below is skipped — those kinds have no icon).
			var cap_i: int = clampi(pk["kind"] - 4, 0, _CAPSULE_LABEL.size() - 1)
			var pcol := _CAPSULE_COL[cap_i]
			var pg := 1.0 if _motion < 0.5 else Art.pulse(0.18)   # steady under reduce-motion
			draw_circle(ppos, 7.0 + pg * 2.0, Color(pcol.r, pcol.g, pcol.b, 0.18 + pg * 0.12))
			draw_arc(ppos, 9.0, 0, TAU, 20, Color(pcol.r, pcol.g, pcol.b, 0.6 + pg * 0.3), 1.5)
			draw_line(ppos, ppos - Vector2(0, 15.0 + pg * 4.0), Color(pcol.r, pcol.g, pcol.b, 0.3), 2.0)
			Art.text(self, _CAPSULE_LABEL[cap_i], ppos + Vector2(-13, -24), 8, pcol)
		else:
			var glyph: String = ["icon_ammo", "icon_grenade", "icon_vest", "icon_airstrike"][pk["kind"]]
			draw_texture_rect(Art.tex(glyph), Rect2(ppos + Vector2(-5, -22), Vector2(10, 10)), false)
		if pk.get("cost", 0) > 0:
			if maxed:
				Art.text(self, "MAXED", ppos + Vector2(-15, -25), 9, Color(0.6, 0.6, 0.6))
			else:
				# Price tinted by affordability (matches the spend-wheel language).
				var afford: bool = sim.war_chest >= pk["cost"]
				var pcol := Art.safe(Color(0.5, 1.0, 0.5)) if afford else Color(1.0, 0.45, 0.35)
				draw_texture_rect(Art.tex("icon_coin"), Rect2(ppos + Vector2(-15, -33), Vector2(9, 9)), false)
				Art.text(self, str(pk["cost"]), ppos + Vector2(-4, -25), 9, pcol)


func _draw_tanks() -> void:
	for ti in sim.tanks.size():
		var t: Dictionary = sim.tanks[ti]
		if not t["alive"]:
			continue
		var c := _to_screen(t["x"], t["y"])
		# Band cull PARKED tanks only (pure drawing — no _tank_hull/_kick_dust
		# state on that path): one parked tank streams per gate and is never
		# despawned, so every bypassed one kept drawing hulk + board ring +
		# glyph off-screen. An occupied tank is always with its player.
		if t["occupant"] < 0 and (c.y < -60.0 or c.y > 420.0):
			continue
		# Convoy graveyard: a dead hulk slumps beside a PARKED tank (position is
		# stable only while unoccupied), so the boardable reads as the last
		# runner of a wiped-out column. Deterministic hulk + side from position.
		if t["occupant"] < 0:
			var wh := Art.cell_hash(t["x"], t["y"])
			var wside := 32.0 if (wh / 3) % 2 == 0 else -32.0
			_spr(_TANK_HULKS[wh % _TANK_HULKS.size()], c + Vector2(wside, 9.0),
				float(wh % 628) / 100.0, 1.0)
		# Board-range ring on a parked tank; tread-crush footprint under an
		# occupied one (mirrors the colossus crush grammar players already know).
		if t["occupant"] < 0 and not t["burning"]:
			draw_arc(c, SimWorld.TANK_BOARD_RADIUS * PX, 0, TAU, 28,
				Color(0.85, 0.95, 0.6, 0.35), 1.0)
		elif t["occupant"] >= 0:
			var cp := Art.pulse(0.2)
			draw_arc(c, SimWorld.TANK_CRUSH_RADIUS * PX, 0, TAU, 24,
				Color(1.0, 0.3, 0.2, 0.25 + cp * 0.2), 1.5)
		var burn_mod := Color.WHITE
		if t["burning"]:
			burn_mod = Color(1.3, 0.6, 0.45) if (t["burn_ticks"] / 6) % 2 == 0 else Color(0.9, 0.5, 0.4)
		if t["occupant"] >= 0 and not t["burning"] and not sim._in_water(t["x"], t["y"]):
			_kick_dust(t["occupant"], t["x"], t["y"], _tank_dust_prev, true)
		_ground_shadow(c, 15.0, 0.42)
		# Hull turns toward travel (eased with lerp_angle, so it swings like treads,
		# not a swivel chair) — a sideways-driving tank no longer slides like a
		# hovercraft with a detached barrel. Parked tanks keep their last heading.
		var hull: float = _tank_hull.get(ti, 0.0)
		if t["occupant"] >= 0:
			var prevp: Vector2 = _tank_prev.get(ti, Vector2(t["x"], t["y"]))
			var dv := Vector2(t["x"] - prevp.x, t["y"] - prevp.y)
			if dv.length_squared() > 4.0e8:   # moved ≥ ~0.3px this frame (16.16 fixed units)
				hull = lerp_angle(hull, dv.angle() + PI / 2, 0.10)
				_tank_hull[ti] = hull
			_tank_prev[ti] = Vector2(t["x"], t["y"])
		_spr("tank_body", c, hull, 0.62, burn_mod)
		# Barrel follows the driver's aim, eased like everything else that turns
		# (player 0.35, enemies 0.18, hull 0.10) — raw _aim_angle snapped the
		# turret in 45° pops on 8-way aim and slewed park→aim in one frame.
		# A vacated tank keeps its last turret heading, matching the hull.
		var barrel_angle: float = _tank_turret.get(ti, -PI / 2)
		if t["occupant"] >= 0:
			barrel_angle = lerp_angle(barrel_angle, _aim_angle(sim.players[t["occupant"]]), 0.35)
			_tank_turret[ti] = barrel_angle
		# Recoil: the barrel kicks back ~4px the instant it fires (fire_cd peaks),
		# then eases forward as the cannon recovers — a fired shot now has weight.
		# Squared, not linear: a raw fire_cd ratio crept the barrel forward at
		# constant speed for the full 45-tick cooldown, which read as machinery.
		# t² front-loads the return (recuperator snap) and settles the tail.
		var br_t := float(t["fire_cd"]) / float(SimWorld.TANK_FIRE_COOLDOWN_TICKS)
		var brecoil := br_t * br_t * 4.0
		_spr("tank_barrel", c + Vector2.from_angle(barrel_angle) * (10.0 - brecoil), barrel_angle + PI / 2, 0.62, burn_mod)
		# Low-fuel telegraph: sputter smoke + warning before the ignite, so a
		# cruising tank doesn't abruptly become 'on fire, 3s to live'.
		if not t["burning"] and t["occupant"] >= 0 and t["fuel"] < 300:
			if (Engine.get_physics_frames() / 8) % 2 == 0:
				_spr("fx_smoke", c + Vector2(randf_range(-4, 4), -12), 0.0, 0.3,
					Color(0.5, 0.5, 0.5, 0.5))
			if (Engine.get_physics_frames() / 14) % 2 == 0:
				Art.text(self, "LOW FUEL", c + Vector2(-16, -26), 8, Color(1.0, 0.7, 0.2))
		if t["burning"]:
			# Vehicle fires burn dirty: dark oily smoke, not the pale dust puff.
			_spr("fx_smoke", c + Vector2(4, -14), 0.0, 0.5, Color(0.3, 0.28, 0.26, 0.8))
			# Bail-out countdown: the hidden ~3s lethal timer, made visible.
			var bail := float(t["burn_ticks"]) / float(SimWorld.TANK_BAIL_TICKS)
			var bc := Color(1.0, 0.35, 0.2) if bail > 0.35 else Color(1.0, 0.85, 0.2)
			draw_arc(c, 20.0, -PI / 2, -PI / 2 + TAU * bail, 28, bc, 2.5)
		elif t["occupant"] < 0:
			Art.draw_glyph(self, "interact", c + Vector2(0, -30), 11.0)
		else:
			# Fuel gauge: the ~20s tank clock was invisible until the 300t LOW FUEL
			# sputter (last 25%). Same ring radius the bail countdown uses, so the
			# slow fuel drain and the 3s burn clock read as one draining dial —
			# dim amber while healthy, hot red once the sputter threshold trips.
			# View-only readout of TANK_FUEL_TICKS; no sim numbers move.
			var ffrac := clampf(float(t["fuel"]) / float(SimWorld.TANK_FUEL_TICKS), 0.0, 1.0)
			var fcol := Color(1.0, 0.75, 0.35, 0.35) if t["fuel"] >= 300 else Color(1.0, 0.4, 0.22, 0.6)
			draw_arc(c, 20.0, -PI / 2, -PI / 2 + TAU * ffrac, 28, fcol, 1.5)
		# Cannon reload ring: the trigger isn't dead, it's cycling.
		if t["occupant"] >= 0 and t["fire_cd"] > 0:
			var rdy := 1.0 - float(t["fire_cd"]) / float(SimWorld.TANK_FIRE_COOLDOWN_TICKS)
			draw_arc(c, 17.0, -PI / 2, -PI / 2 + TAU * rdy, 24, Color(1.0, 0.8, 0.4, 0.6), 2.0)


func _esort_cmp(a: int, b: int) -> bool:
	return _esort_ys[a] < _esort_ys[b]


func _draw_enemies() -> void:
	# ≤2 alive players, cached once — replaces an O(players) sim scan per enemy
	# per frame that existed purely to pick a facing/laser target.
	var alive_players: Array[Dictionary] = []
	for p in sim.players:
		if p["alive"]:
			alive_players.append(p)
	# Y-sorted draw order: in a dense rush a nearer (lower) troop must render over
	# a farther one — sim array order broke that overlap. Buffers + comparator are
	# reused members so the per-frame sort allocates nothing and never hashes a dict.
	var ecount := sim.enemies.size()
	if _esort_order.size() != ecount:
		_esort_order.resize(ecount)
		_esort_ys.resize(ecount)
	for si in ecount:
		_esort_order[si] = si
		_esort_ys[si] = sim.enemies[si]["y"]
	_esort_order.sort_custom(_esort_cmp)
	# Prune per-slot view state past the live range — the sim compacts with
	# remove_at, so an out-of-range key would otherwise leak onto a future
	# same-kind occupant of that slot.
	for sk in _enemy_slot_kind.keys():
		if sk >= ecount:
			_enemy_slot_kind.erase(sk)
			_enemy_face.erase(sk)
			_enemy_pos_prev.erase(sk)
			_tech_lunge_prev.erase(sk)
			_enemy_hp_prev.erase(sk)
			_enemy_flash.erase(sk)
	for eidx in _esort_order:
		var e: Dictionary = sim.enemies[eidx]
		if not e["alive"]:
			_enemy_flash.erase(eidx)
			_enemy_hp_prev.erase(eidx)
			continue
		# First-sighting teaching card: name the archetype + its counter the first
		# time it appears this run (these debut at sector 4 with no introduction).
		var ekind: String = e["kind"]
		# Slot inherited by a different kind after a kill's compaction: seed the
		# face fresh and drop the prev-pos/lunge instead of lerping out of the
		# dead neighbor's heading for ~10 frames.
		if _enemy_slot_kind.get(eidx, "") != ekind:
			_enemy_slot_kind[eidx] = ekind
			_enemy_face.erase(eidx)
			_enemy_pos_prev.erase(eidx)
			_tech_lunge_prev.erase(eidx)
			_enemy_hp_prev.erase(eidx)
			_enemy_flash.erase(eidx)
		if not _seen_kinds.has(ekind) and _KIND_TEACH.has(ekind):
			_seen_kinds[ekind] = true
			_show_banner(_KIND_TEACH[ekind], Color(1.0, 0.55, 0.4))
		var epos := _to_screen(e["x"], e["y"])
		# a2-11 VFX#1: hit-flash + spark + micro-flinch on a NON-LETHAL hit (hp dropped
		# but still alive) — mobs only reacted on death; now every hit reads. The white
		# pop + sparks spawn as ADDITIVE glow fx so they draw on TOP of the body (via
		# _draw_glow); the flinch below is the body offset.
		# Most kinds are one-shot and carry NO "hp" field (only mg_nest/technical/
		# broadcast track it — see _step; frogman/rusher/elite/courier have none).
		# Default to a constant so the edge-detect is a no-op for them (prev==cur ->
		# never flashes; they die in one hit anyway) instead of crashing the draw.
		var ehp: int = e.get("hp", 1)
		if ehp < int(_enemy_hp_prev.get(eidx, ehp)):
			_enemy_flash[eidx] = 1.0
			if _motion >= 0.5:   # a2-11 r3: REDUCE MOTION suppresses the pop + sparks (not just the flinch)
				_fx.append({"x": e["x"], "y": e["y"], "t": 0.0, "kind": "light", "rate": 0.16, "r": 13.0, "col": Color(1.0, 1.0, 0.95)})
				for sp in 4:
					var sa := float(sp) * PI / 2.0 + 0.4
					_fx.append({"x": e["x"], "y": e["y"], "t": 0.0, "kind": "ember", "rate": 0.1,
						"vx": cos(sa) * 2.2, "vy": sin(sa) * 2.2})
		_enemy_hp_prev[eidx] = ehp
		var eflash: float = _enemy_flash.get(eidx, 0.0)
		if eflash > 0.02:
			_enemy_flash[eidx] = eflash - 0.2
			epos.y -= eflash * 1.2 * _motion
		# No shadow for water frogmen, nor for a still-cloaked ghillie (the shadow
		# would give the ambush away — the laser paint is the only warning).
		# Drone excluded: it draws its own OFFSET altitude shadow — a second
		# centered contact shadow under a hovering unit flattened the airborne read.
		# Technical excluded: it gets a vehicle-width shadow in its own branch.
		if e["kind"] != "frogman" and e["kind"] != "drone" and e["kind"] != "technical" \
				and not (e["kind"] == "ghillie" and e.get("submerged", false)):
			# a1-02: warm-dark footprint so a hostile separates from the cool/neutral
			# decor shadows even before its fill resolves (the eye reads "threat here").
			_ground_shadow(epos, 6.0, 0.34, Color(0.12, 0.03, 0.0))
		if e.get("marked", false):
			# Bounty target: a pulsing gold halo + a little crown so the 3× payoff
			# reads across a chaotic field before you commit to chasing it.
			var mb := Art.pulse(0.16)
			draw_arc(epos, 11.0 + mb * 2.0, 0, TAU, 20, Color(1.0, 0.85, 0.3, 0.5 + mb * 0.4), 1.5)
			var cy := epos.y - 12.0
			for ci in 3:
				var cx := epos.x - 4.0 + ci * 4.0
				draw_line(Vector2(cx, cy), Vector2(cx, cy - 3.0), Color(1.0, 0.85, 0.3), 1.5)
			draw_line(Vector2(epos.x - 5, cy), Vector2(epos.x + 5, cy), Color(1.0, 0.85, 0.3), 1.5)
		# Run-cycle bob: a small per-unit-phased vertical hop so a charging
		# swarm has cadence instead of gliding in lockstep (foot infantry only).
		# Gated on actual movement (like the player bob) — a standing unit
		# breathes instead of jogging in place.
		var e_now := Vector2i(e["x"], e["y"])
		var e_moved: bool = _enemy_pos_prev.get(eidx, Vector2i(-1, -1)) != e_now
		_enemy_pos_prev[eidx] = e_now
		if e["kind"] != "frogman":
			if e.get("windup", 0) == 0 and e_moved:
				epos.y += absf(sin(float(Engine.get_physics_frames()) * 0.35 + float(eidx) * 1.7)) * -1.4 * _motion
			else:
				# Winding up / standing: the run-bob stops but a slow breath keeps the
				# unit alive — nothing on the field should be a frozen statue.
				# (Stilled under REDUCE MOTION like the parked jeep/boss hover.)
				epos.y += sin(float(Engine.get_physics_frames()) * 0.12 + float(eidx) * 1.7) * -0.5 * _motion
		var target: Dictionary = {}
		var best_d2 := 0.0
		for p in alive_players:
			var pdx := float(p["x"] - e["x"])
			var pdy := float(p["y"] - e["y"])
			var d2 := pdx * pdx + pdy * pdy
			if target.is_empty() or d2 < best_d2:
				target = p
				best_d2 = d2
		var face := PI / 2
		if not target.is_empty():
			face = atan2(float(target["y"] - e["y"]), float(target["x"] - e["x"]))
		# Smoothed per-slot facing: when the nearest player flips sides the sprite
		# swings instead of snapping 180° in one frame. Slot-keyed like _enemy_water_prev.
		face = lerp_angle(_enemy_face.get(eidx, face), face, 0.18)
		_enemy_face[eidx] = face
		if e["kind"] == "frogman":
			var st: int = e.get("surface_ticks", 0)
			if e["submerged"]:
				# Idle ripple loop so occupied water reads as occupied.
				var ph := float((Engine.get_physics_frames() + eidx * 17) % 90) / 90.0
				draw_arc(epos, 4.0 + ph * 9.0, 0, TAU, 16, Color(0.6, 0.8, 0.9, 0.4 * (1.0 - ph)), 1.0)
				draw_arc(epos, 5.0, 0, TAU, 12, Color(0.6, 0.8, 0.9, 0.55), 1.5)
				# Breath bubbles trickling up from the submerged diver (stateless loop).
				var bph := float((Engine.get_physics_frames() * 2 + eidx * 31) % 120) / 120.0
				_spr("fx_bubble1" if eidx % 2 == 0 else "fx_bubble2",
					epos + Vector2(sin(bph * TAU) * 2.5, -2.0 - bph * 10.0), 0.0,
					0.05 + bph * 0.04, Color(1, 1, 1, 0.55 * (1.0 - bph)))
				_spr(_frogman_tex(e["submerged"]), epos, face, 0.4, Color(0.5, 0.8, 0.8, 0.35))
			elif st > 0:
				# Surfacing telegraph: bold ripple burst + the body rising up.
				var sfrac := 1.0 - float(st) / float(SimWorld.FROGMAN_SURFACE_TICKS)
				for k in 2:
					draw_arc(epos, 6.0 + sfrac * 14.0 + k * 5.0, 0, TAU, 20,
						Color(0.85, 0.95, 1.0, 0.7 - k * 0.25 - sfrac * 0.3), 2.0)
					# Burst bubbles riding the surfacing ripple.
					_spr("fx_bubble1" if k == 0 else "fx_bubble2",
						epos + Vector2(k * 7.0 - 3.5, -3.0 - sfrac * (7.0 + k * 5.0)), 0.0,
						0.06 + sfrac * 0.05, Color(1, 1, 1, 0.8 * (1.0 - sfrac)))
				_spr(_frogman_tex(e["submerged"]), epos, face, 0.4 + sfrac * 0.1,
					Color(0.7, 0.9, 0.95, 0.4 + sfrac * 0.6))
			else:
				var flunge: int = e.get("lunge_ticks", 0)
				if flunge > 0:
					# Lethal lunge: the safe surface window is over — contact now
					# kills. Hot-red tint + a forward wake smear along its facing
					# sell "this is the dangerous frame", so the kill window that
					# just closed isn't followed by a silent death.
					var fdir := Vector2.from_angle(face)
					draw_line(epos - fdir * 10.0, epos + fdir * 2.0, Color(1.0, 0.3, 0.2, 0.5), 3.0)
					_spr(_frogman_tex(e["submerged"]), epos, face, 0.52, Color(1.5, 0.5, 0.4))
				else:
					_spr(_frogman_tex(e["submerged"]), epos, face, 0.5)
		elif e["kind"] == "sniper":
			# Paints a laser line on its target during the long windup — the
			# 'get off this line NOW' telegraph. Break LOS or sidestep.
			var swu: int = e.get("windup", 0)
			if swu > 0:
				# Beam follows the LOCKED shot vector (aim_lx/aim_ly at paint start),
				# not the live target — sidestepping must visibly clear the line the
				# same way it dodges the fired bullet.
				var lp := _to_screen(e["x"] + e.get("aim_lx", 0), e["y"] + e.get("aim_ly", 0))
				var pf := 1.0 - float(swu) / float(SimWorld.SNIPER_WINDUP_TICKS)
				var bdir := lp - epos
				bdir = bdir.normalized() if bdir.length() > 0.001 else Vector2.RIGHT
				# Final moments: strobe white (matches the mortar-telegraph grammar).
				var lcol := Color(1.0, 0.15, 0.12, 0.35 + pf * 0.5)
				if swu <= 10 and (swu / 2) % 2 == 0:
					lcol = Color(1.0, 1.0, 1.0, 0.95)
				draw_line(epos, epos + bdir * 900.0, lcol, 1.0 + pf * 2.0)
				draw_circle(lp, 2.0 + pf * 3.0, Color(lcol.r, lcol.g, lcol.b, 0.4 + pf * 0.5))
			var ssw := (1.0 + (1.0 - float(swu) / float(SimWorld.SNIPER_WINDUP_TICKS)) * 0.14) if swu > 0 else 1.0
			_spr("enemy_sniper", epos, face, 0.5 * ssw)   # sol-08: authored red marksman (scoped-rifle silhouette); the laser + ghillie behaviour identify it, TINT carries the vermilion
		elif e["kind"] == "grenadier":
			var gwu: int = e.get("windup", 0)
			if gwu > 0:
				var gf := 1.0 - float(gwu) / float(SimWorld.GRENADIER_WINDUP_TICKS)
				draw_circle(epos + Vector2(0, -6), 2.0 + gf * 3.0, Color(1.0, 0.7, 0.2, 0.4 + gf * 0.5))
				# Where the mortar lands: a faint amber ground ring at the LIVE
				# target (the grenadier re-aims at fire time, so following it is
				# honest), sized to the real kill footprint and filling as the lob
				# nears — hands straight off to the strike telegraph on fire.
				if not target.is_empty():
					var mtp := _to_screen(target["x"], target["y"])
					var mr := SimWorld.GRENADE_RADIUS * PX
					draw_arc(mtp, mr, 0, TAU, 28, Color(1.0, 0.6, 0.15, 0.12 + gf * 0.35), 1.5)
					draw_arc(mtp, mr * gf, 0, TAU, 24, Color(1.0, 0.55, 0.1, 0.15 + gf * 0.4), 1.5)
			var gsw := (1.0 + (1.0 - float(gwu) / float(SimWorld.GRENADIER_WINDUP_TICKS)) * 0.14) if gwu > 0 else 1.0
			_spr("m_soldier2", epos, face, 0.52 * gsw, Color(1.3, 1.1, 0.55))   # amber lobber, own silhouette
		elif e["kind"] == "drone":
			# Recon drone: airborne spotter. Hover bob + an offset ground shadow
			# sell the altitude; the amber paint-lens swells through the windup
			# (grenadier grammar — it calls the same tracked strike).
			var dwu: int = e.get("windup", 0)
			var hb := sin(float(Engine.get_physics_frames()) * 0.11 + float(eidx) * 1.7) * 1.5
			# Shadow breathes opposite the bob — higher drone, smaller/fainter shadow.
			draw_circle(epos + Vector2(3.0, 8.0), 4.0 - hb * 0.5, Color(0, 0, 0, 0.18 - hb * 0.03))
			if dwu > 0:
				var df := 1.0 - float(dwu) / float(SimWorld.DRONE_WINDUP_TICKS)
				# Lock-line to the tracked target (6-vote panel item): the paint
				# follows YOUR ground, and nothing said so — a dashed amber tether
				# makes "it's tracking me, keep moving" readable mid-windup.
				if not target.is_empty():
					var dtp := _to_screen(target["x"], target["y"])
					# Dark under-line (the chevron under-lay grammar) so the amber
					# dash survives bright grass and hue-blindness; the endpoint
					# ring marks WHO is painted — the tether used to just stop.
					draw_dashed_line(epos + Vector2(1, -4.0 + hb), dtp + Vector2(1, 1),
						Color(0, 0, 0, 0.3 + df * 0.25), 1.0, 6.0)
					draw_dashed_line(epos + Vector2(0, -5.0 + hb), dtp,
						Color(1.0, 0.7, 0.25, 0.35 + df * 0.35), 1.0, 6.0)
					draw_arc(dtp, 9.0 + df * 3.0, 0, TAU, 14,
						Color(1.0, 0.7, 0.25, 0.3 + df * 0.4), 1.2)
				draw_circle(epos + Vector2(0, -8.0 + hb), 2.0 + df * 3.0,
					Color(1.0, 0.7, 0.2, 0.4 + df * 0.5))
			_spr("m_drone", epos + Vector2(0, -5.0 + hb), face, 0.5, Color(1.15, 1.25, 1.35))
		elif e["kind"] == "technical":
			# Charging raider: face the LOCKED line mid-charge (the sprite is the
			# promise), shake + dust while revving, speed streaks while barreling.
			var t_lunge: int = e.get("lunge_ticks", 0)
			# Missed-charge skid: the lethal lunge snapping straight to a quiet
			# cruise read as a state glitch — a dust plume sells the stop (and
			# the vulnerability beat).
			if _tech_lunge_prev.get(eidx, 0) > 0 and t_lunge == 0:
				_burst(e["x"], e["y"], "dust", 5, 0.6, 1.6, 0.5, 0.08)
			_tech_lunge_prev[eidx] = t_lunge
			var t_wu: int = e.get("windup", 0)
			var t_face := face
			# Vehicle-width shadow (the generic 6.0 infantry disc made the truck
			# read as floating on a man's shadow — the tank uses 15.0). Drawn
			# BEFORE the rev shake mutates epos: the shadow staying put while the
			# body vibrates above it is what sells the revving.
			_ground_shadow(epos, 11.0, 0.42)
			if t_lunge > 0:
				t_face = Vector2(float(e.get("aim_lx", 0)), float(e.get("aim_ly", 0))).angle()
				# Hold the smoothed-facing lerp at the locked line — otherwise it
				# keeps tracking the player and lunge-end snaps the sprite ~180°.
				_enemy_face[eidx] = t_face
				var t_dir := Vector2.from_angle(t_face)
				# The LOCKED corridor: the rev line promised a lane, but it used to
				# vanish the moment the charge began — the exact 50-tick window the
				# player must sidestep (6-reviewer consensus). Solid line, remaining
				# travel length (lunge_ticks × 3px), cooling as the charge spends.
				var t_left := float(t_lunge) / float(SimWorld.TECHNICAL_CHARGE_TICKS)
				# Dark under-line (the drone-tether under-lay idiom) so the thin
				# red-orange corridor survives bright grass.
				draw_line(epos + Vector2(1, 1), epos + t_dir * (t_lunge * 3.0 * PX) + Vector2(1, 1),
					Color(0, 0, 0, 0.3), 1.5)
				draw_line(epos, epos + t_dir * (t_lunge * 3.0 * PX),
					Color(1.0, 0.4, 0.25, 0.2 + t_left * 0.35), 1.5)
				draw_line(epos - t_dir * 14.0, epos - t_dir * 26.0,
					Color(0.85, 0.8, 0.7, 0.45), 2.0)
				# Churned-ground dust: the fastest thing on the field was leaving no
				# trail. Frame-clock phase, no state; count halves under reduce-motion.
				var t_ph := float(Engine.get_physics_frames())
				for dk in (1 if _motion < 0.5 else 3):
					var d_off := -t_dir * (16.0 + dk * 9.0 + fmod(t_ph * 2.0 + dk * 13.0, 9.0))
					d_off += Vector2.from_angle(t_face + PI / 2.0) * sin(t_ph * 0.7 + dk * 2.1) * 4.0
					draw_circle(epos + d_off, 2.4 - dk * 0.5,
						Color(0.62, 0.55, 0.42, 0.30 - dk * 0.07))
			elif t_wu > 0:
				var t_rf := 1.0 - float(t_wu) / float(SimWorld.TECHNICAL_REV_TICKS)
				epos.x += sin(float(Engine.get_physics_frames()) * 0.9) * (0.6 + t_rf) * _motion
				# The rev line IS the dodge promise — but DASHED while it still
				# tracks you (the sim locks at rev-end, not rev-start): dashed =
				# "still aiming", the solid charge corridor = "committed".
				# Dark under-line beneath the low-alpha rev dash (drone-tether idiom).
				draw_dashed_line(epos + Vector2(1, 1),
					epos + Vector2.from_angle(face) * (30.0 + t_rf * 30.0) + Vector2(1, 1),
					Color(0, 0, 0, 0.3), 1.5, 5.0)
				draw_dashed_line(epos, epos + Vector2.from_angle(face) * (30.0 + t_rf * 30.0),
					Color(1.0, 0.45, 0.3, 0.25 + t_rf * 0.45), 1.5, 5.0)
			elif e.get("fire_cd", 0) == 0 and _any_player_smoked():
				# Smoke-deny tell: cooldown is spent but the truck can't line up a
				# charge into smoke — without this it read as the AI breaking, and
				# the smoke special never got credit for the block (3 reviewers).
				var qp: float = 1.0 if _motion < 0.5 else Art.pulse(0.2)
				# Threat-family amber on a dark disc (the _pip idiom) — the old 10px
				# neutral grey washed out on bright sand.
				draw_circle(epos + Vector2(0, -26), 7.0, Color(0.08, 0.09, 0.07, 0.6))
				Art.text(self, "?", epos + Vector2(-3, -22), 12, Color(1.0, 0.75, 0.4, 0.5 + qp * 0.4))
			_spr("m_technical", epos, t_face, 0.55, Art.HOSTILE_VEH, 1.1 if t_lunge > 0 else 1.0)   # a2-02: warm-hostile vehicle tint
		elif e["kind"] == "pilot":
			# Downed pilot: the one green thing among hostiles — objective ring +
			# RESCUE label so "touch, don't shoot" reads across a firefight.
			var pi_pulse: float = 1.0 if _motion < 0.5 else Art.pulse(0.15)
			var pi_col := Art.safe(Color(0.45, 1.0, 0.65))
			# Escape imminence: the capture threshold (camera_top - 30) was an
			# invisible cliff — the ransom vanished to geometry the player could
			# not read (6-reviewer consensus). Inside the last 60px the label
			# turns red ESCAPING! and the fail tone pre-fires once, quieter.
			var pi_esc := float(e["y"] - (sim.camera_top - 30 * Fixed.ONE)) / float(Fixed.ONE)
			if pi_esc < 60.0 and not e.get("submerged", false):
				# DANGER stays red even in colorblind mode — Art.safe remaps greens.
				pi_col = Color(1.0, 0.45, 0.35)
				if Engine.get_physics_frames() - _pilot_alarm_frame >= 120:
					_pilot_alarm_frame = Engine.get_physics_frames()
					_sfx.play("alarm", -18.0, 0.6)
				# The warning window plays out near the top edge — pin the label
				# on-screen instead of letting it draw above the viewport.
				Art.text(self, "ESCAPING!", Vector2(epos.x - 20.0, maxf(epos.y - 18.0, 10.0)), 8, pi_col)
			else:
				# Ransom on the label (their gfx panel 6/9 + our panel — two loops,
				# same gap): "is this dive worth it" needs the number up front.
				Art.text(self, "RESCUE +%d¢" % SimWorld.PILOT_RANSOM, epos + Vector2(-26, -18), 8, pi_col)
			draw_arc(epos, 10.0 + pi_pulse * 2.0, 0, TAU, 18,
				Color(pi_col.r, pi_col.g, pi_col.b, 0.55 + pi_pulse * 0.3), 1.5)
			if e.get("submerged", false):
				# Punch-out grace: he's climbing out of the wreck — sprawled and
				# fading in, so the no-shoot window reads as "not up yet", not
				# as bullets mysteriously missing a standing man.
				var pi_up := 1.0 - float(e.get("surface_ticks", 0)) / float(SimWorld.PILOT_PUNCHOUT_TICKS)
				_spr("m_pilot", epos, -PI / 2 + (1.0 - pi_up) * 1.1,
					0.48, Color(1, 1, 1, 0.35 + pi_up * 0.65))
				# Standing on him during the grace: a soft deny chirp instead of
				# silence, so the early touch reads "not yet" rather than "broken".
				for dp in sim.players:
					if dp["alive"] and _to_screen(dp["x"], dp["y"]).distance_to(epos) < 10.0 \
							and Engine.get_physics_frames() - _pilot_deny_frame >= 20:
						_pilot_deny_frame = Engine.get_physics_frames()
						_sfx.play("alarm", -22.0, 2.6)
						break
			else:
				_spr("m_pilot", epos, -PI / 2, 0.48)
		elif e["kind"] == "courier":
			# Fleeing supply runner: real courier bake (the loot pack is in the
			# sprite now); the pulsing gold ring stays — "catch this one" must
			# still read across a chaotic field. Forward lean = closing momentum.
			_spr("courier", epos, face, 0.5, Color.WHITE, 1.12)
			var lb: float = 1.0 if _motion < 0.5 else Art.pulse(0.2)   # steady-bright under reduce-motion
			draw_arc(epos, 9.0 + lb * 1.5, 0, TAU, 16, Color(1.0, 0.85, 0.3, 0.4 + lb * 0.25), 1.3)
		elif e["kind"] == "shield":
			_spr("m_bombsuit", epos, face, 0.55, Color(0.85, 0.9, 1.0))   # armored EOD bulk sells the block
			# The riot shield: the baked plate held across the front — this side
			# deflects. Image-up = shield-top, so rotation = face + PI/2; faint cyan
			# modulate keeps the established deflect-color language.
			_spr("riot_shield", epos + Vector2.from_angle(face) * 11.0, face + PI / 2,
				1.0, Color(0.72, 0.88, 1.05, 0.95))
			# Rear SAFE-arc: the shield only eats the front cone, so its back is the
			# flank counter. A faint green arc behind it (opposite the bright front
			# arc) teaches "get around him" — Art.safe keeps it legible in colorblind.
			var srear := face + PI
			draw_arc(epos, 13.0, srear - 1.15, srear + 1.15, 14,
				Art.safe(Color(0.4, 1.0, 0.5, 0.4)), 2.0)
		elif e["kind"] == "sapper":
			# Mine-layer EOD: real sapper bake; the pulsing armed-satchel pip stays —
			# "he's seeding the ground behind him" is a gameplay telegraph.
			_spr("sapper", epos, face, 0.5, Color.WHITE, 1.12)
			var spp: float = 1.0 if _motion < 0.5 else Art.pulse(0.25)   # steady-bright under reduce-motion
			draw_circle(epos + Vector2(0, 3), 1.8 + spp * 0.8, Color(1.0, 0.5, 0.15, 0.7 + spp * 0.3))
		elif e["kind"] == "broadcast":
			# Rally mast: the decor radio tower militarized — red-keyed, hp pips
			# in the nest grammar, and a faint breathing ring that draws the
			# aura's true 140px reach (truthful telegraph, reduce-motion safe).
			# 4v rework: the faint full-reach 140px arc dominated the playfield
			# while communicating nothing (too faint to read, too big to ignore).
			# Now a TIGHT dark-backed base ring owns the structure identity, and
			# the 90-tick pulse (below) truthfully sweeps the real aura reach.
			var bpul := Art.pulse(0.2) if _motion >= 0.5 else 0.5
			draw_arc(epos, 48.0, 0, TAU, 32, Color(0.1, 0.05, 0.05, 0.5), 3.5)
			draw_arc(epos, 48.0, 0, TAU, 32, Color(1.0, 0.4, 0.35, 0.25 + bpul * 0.35), 2.0)
			_spr("radio_tower", epos, 0.0, 0.9, Color(1.15, 0.62, 0.55))
			var b_hp: int = e.get("hp", SimWorld.BROADCAST_HP)
			for bpi in SimWorld.BROADCAST_HP:
				draw_circle(epos + Vector2(-12.0 + bpi * 6.0, 14.0), 2.0,
					Color(1.0, 0.3, 0.2) if bpi < b_hp else Color(0.25, 0.22, 0.2))
		elif e["kind"] == "mg_nest":
			# Rooted emplacement: sandbag nest + gunner + a full lane lifecycle
			# (6/9 panel reviewers: the old telegraph was one flat 44px stub that
			# only existed mid-burst — aim was invisible, reload erased the lane).
			# Damage state: hp 3->1 darkens the bags and empties the pip row —
			# the one chip-HP enemy was visually identical fresh vs nearly-dead
			# (5/7 lens consensus). Static reads, no reduce-motion gate needed.
			var n_hp: int = e.get("hp", 3)
			var n_dmg := float(clampi(3 - n_hp, 0, 2))
			_spr("sandbag_beige", epos, 0.0, 0.5,
				Color(0.82 - n_dmg * 0.13, 0.8 - n_dmg * 0.15, 0.62 - n_dmg * 0.12))
			# Baked tripod MG on the sandbag ring (was a shrunken red elite gunner).
			# Image-up = muzzle, so the emplacement swivels with the live aim lane;
			# it darkens with the bags as the nest cracks.
			var nlv := Vector2(e.get("aim_lx", 0), e.get("aim_ly", 0))
			var nang: float = nlv.angle() if nlv.length() > 1.0 else face
			_spr("mg_stand", epos + Vector2(0, -2), nang + PI / 2, 1.0,
				Color(1.0 - n_dmg * 0.15, 1.0 - n_dmg * 0.17, 1.0 - n_dmg * 0.15))
			# Armor pips (gate lock-pip grammar): filled = hits still to crack.
			for npi in 3:
				draw_circle(epos + Vector2(-6.0 + npi * 6.0, -14.0), 1.8,
					Color(1.0, 0.78, 0.35, 0.9) if npi < n_hp else Color(0.22, 0.2, 0.18, 0.75))
			# Lane band-cull (7/9 panel): an off-band nest drew its full 640px lane
			# every aim frame. Sandbags + pips above still draw — only the lane skips.
			if nlv.length() > 1.0 and epos.y > -80.0 and epos.y < 420.0:
				var nld := nlv.normalized()
				var nburst: int = e.get("lunge_ticks", 0)
				var nwu: int = e.get("windup", 0)
				# The lane runs the bullet's actual flight, not a 44px stub.
				var lane_end := epos + nld * 640.0
				if nburst == SimWorld.MG_NEST_BURST_ROUNDS and nwu > 0:
					# AIM: locked, winding up (the mg_nest_aim sting's visual twin) —
					# amber lane fades in as the first round closes. Static alphas,
					# so reduce-motion needs no gate.
					# Bright AT lock (windup full, most time to react) and EASES as it
					# commits — the old ramp was inverted (dimmest when you could still
					# dodge, brightest when you couldn't). Firing draws its own hot line.
					var af := float(nwu) / float(SimWorld.MG_NEST_AIM_TICKS)
					draw_line(epos, lane_end, Color(1.0, 0.45, 0.2, 0.15 + af * 0.4), 1.0 + af)
				elif nburst > 0:
					# FIRING: hot lethal-red, sniper-line vocabulary — holds through
					# the 8-tick gaps so the 3-round burst reads as one rake.
					draw_line(epos, lane_end, Color(1.0, 0.15, 0.12, 0.7), 2.0)
					draw_circle(epos + nld * 44.0, 2.0, Color(1.0, 0.4, 0.25, 0.75))
				else:
					# RELOAD: a dim stub down the LAST lane — the rooted-turret
					# threat must not vanish for the whole 1.5s between bursts.
					draw_line(epos, epos + nld * 90.0, Color(1.0, 0.4, 0.2, 0.2), 1.0)   # 0.12 read as a dead lane, not a reloading turret
		elif e["kind"] == "ghillie":
			var gst: int = e.get("surface_ticks", 0)
			var gwu2: int = e.get("windup", 0)
			if e.get("submerged", false):
				# Dug in and cloaked: only a faint foliage shimmer betrays it —
				# the laser paint on reveal is the real warning. Kept very subtle.
				var gcp := Art.pulse(0.08)
				draw_circle(epos, 5.0, Color(0.34, 0.5, 0.24, 0.10 + gcp * 0.06))
			elif gst > 0:
				# Rising out of cover: a bold leaf/dust burst as it reveals.
				var rf := 1.0 - float(gst) / float(SimWorld.GHILLIE_REVEAL_TICKS)
				for k in 2:
					draw_arc(epos, 6.0 + rf * 12.0 + k * 4.0, 0, TAU, 18,
						Color(0.6, 0.75, 0.4, 0.6 - k * 0.2 - rf * 0.3), 2.0)
				_spr("ghillie", epos, face, 0.42 + rf * 0.08, Color(1, 1, 1, 0.4 + rf * 0.6))
			else:
				# Revealed marksman: paints the sniper line during windup, then fires.
				if gwu2 > 0:
					# Beam rides the LOCKED shot vector, not the live target — the
					# fired bullet flies down aim_lx/aim_ly, so must the tell.
					var lp2 := _to_screen(e["x"] + e.get("aim_lx", 0), e["y"] + e.get("aim_ly", 0))
					var pf2 := 1.0 - float(gwu2) / float(SimWorld.SNIPER_WINDUP_TICKS)
					var bdir2 := lp2 - epos
					bdir2 = bdir2.normalized() if bdir2.length() > 0.001 else Vector2.RIGHT
					# Same final-moment white strobe the sniper gets — a revealed
					# ghillie fires the same lethal shot and deserves the same fair
					# 'get off the line NOW' warning, not a silent kill.
					var lcol2 := Color(1.0, 0.15, 0.12, 0.35 + pf2 * 0.5)
					if gwu2 <= 10 and (gwu2 / 2) % 2 == 0:
						lcol2 = Color(1.0, 1.0, 1.0, 0.95)
					draw_line(epos, epos + bdir2 * 900.0, lcol2, 1.0 + pf2)
					draw_circle(lp2, 2.0 + pf2 * 2.0, Color(lcol2.r, lcol2.g, lcol2.b, 0.4 + pf2 * 0.4))
				_spr("ghillie", epos, face, 0.5)   # real ghillie bake (was a green-keyed frogman)
		elif e["elite"]:
			# a3-12 (UNIT#2): a persistent warm aura marks EVERY elite as an elevated
			# threat — not just the ~1-in-7 bounty crown. The warm body tint alone was easy
			# to lose in a busy frame. Soft red halo UNDER the body, gently pulsing; a static
			# floor (base alpha) holds under REDUCE MOTION so the threat read never vanishes.
			var eaura := 0.5 + 0.5 * sin(float(Engine.get_physics_frames()) * 0.06 + float(eidx))
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(epos - Vector2(14.0, 14.0), Vector2(28.0, 28.0)),
				false, Color(ELITE_AURA.r, ELITE_AURA.g, ELITE_AURA.b,
					ELITE_AURA_ALPHA["base"] + eaura * ELITE_AURA_ALPHA["pulse"] * _motion))
			# Wind-up telegraph: muzzle ember swells red before the shot.
			var wu: int = e.get("windup", 0)
			if wu > 0:
				var wfrac := 1.0 - float(wu) / float(SimWorld.ELITE_WINDUP_TICKS)
				draw_circle(epos + Vector2.from_angle(face) * 8.0, 1.5 + wfrac * 3.5,
					Color(1.0, 0.85 - wfrac * 0.55, 0.2, 0.4 + wfrac * 0.6))
				# Aim-stub: a short dashed lane toward the target, borrowing the sniper
				# beam grammar so the elite's "I'm drawing a bead on YOU" reads instead
				# of a lone chest ember. Kept a stub — the sim only aims at fire-time.
				var edir := Vector2.from_angle(face)
				draw_dashed_line(epos + edir * 9.0, epos + edir * (30.0 + wfrac * 8.0),
					Color(1.0, 0.3, 0.2, 0.12 + wfrac * 0.55), 1.0 + wfrac, 3.0)
			var esw := (1.0 + (1.0 - float(wu) / float(SimWorld.ELITE_WINDUP_TICKS)) * 0.14) if wu > 0 else 1.0
			_spr("enemy_assault", epos, face, 0.62 * esw)   # sol-08: elite = the authored red assault trooper, drawn larger than fodder (TINT carries the vermilion; the red aura + size keep it distinct)
		else:
			_spr(_RUSHER_SKINS[e.get("skin", 0)], epos, face, 0.5)
		# Flashbang stun state ON the body: the wash decays in ~0.2s but the
		# freeze lasts 1.5s — and reduce-motion zeroes the wash entirely, so
		# frozen enemies with no mark read as a bug. Steady ring + orbit dots
		# (no strobe); a slow 3Hz blink only in the last 20t is the wake-up
		# warning (under the 3-flashes/s photosensitivity line).
		if sim.flash_ticks > 0 and not e.get("submerged", false):
			if sim.flash_ticks > 20 or (sim.flash_ticks / 10) % 2 == 0:
				# The ring DEPLETES with the stun (4-vote panel item): the whole
				# tactical window is readable per body, not just its edges.
				var stf := float(sim.flash_ticks) / float(SimWorld.FLASH_STUN_TICKS)
				draw_arc(epos + Vector2(0, -10.0), 3.5, -PI / 2, -PI / 2 + TAU * stf, 10,
					Color(0.75, 0.88, 1.0, 0.85), 1.3)
				if _motion >= 0.5:   # orbit dots are motion — the ring alone under reduce-motion
					for sd in 3:
						var sa := float(Engine.get_physics_frames()) * 0.12 + sd * TAU / 3.0
						draw_circle(epos + Vector2(0, -10.0) + Vector2.from_angle(sa) * 5.5, 1.0,
							Color(1.0, 1.0, 0.8, 0.9))


func _draw_observer() -> void:
	if sim.observer.is_empty():
		return
	var op := _to_screen(sim.observer["x"], sim.camera_top + SimWorld.OBSERVER_Y_OFFSET)
	op.y += sin(float(Engine.get_physics_frames()) * 0.07) * 0.8   # engine-idle breath — not a statue
	# The rocket battery the spotter paints for sits alongside — the pair reads
	# as one artillery unit, not a lone jeep with magic mortars.
	_spr("m_rocket_truck", op + Vector2(40, 5), PI / 2, 0.5, Art.HOSTILE_VEH)   # a2-02: warm-hostile
	_spr("m_radar_tank", op, PI / 2, 0.5, Art.HOSTILE_VEH)   # a2-02: warm-hostile spotter vehicle
	draw_line(op + Vector2(8, 0), op + Vector2(8, -12), Color(0.95, 0.8, 0.2), 2.0)
	# Baked flag glyph (last greybox rect on this unit) — same hud_flag the map markers wear.
	_spr("hud_flag", op + Vector2(11.5, -9.5), 0.0, 0.04, Color(0.9, 0.25, 0.2))
	# Radar sweep: a rotating scan beam off the antenna sells the spotter's whole job
	# (actively painting you for artillery) instead of a static flag.
	var sweep := float(Engine.get_physics_frames()) * 0.09
	var atop := op + Vector2(8, -12)
	var sdir := Vector2(cos(sweep), sin(sweep) * 0.5)
	draw_line(atop, atop + sdir * 9.0, Color(0.4, 1.0, 0.5, 0.7), 1.5)
	draw_arc(atop, 9.0, sweep - 0.4, sweep + 0.4, 6, Color(0.4, 1.0, 0.5, 0.25), 2.0)
	# Kill-me target reticle: the spotter is one-hit-killable and killing him
	# ends the barrage — a second way out the ADVANCE directive never mentions.
	var tp := Art.pulse(0.2)
	var tr := 13.0 + tp * 3.0
	var tcol := Color(1.0, 0.3, 0.25, 0.85)
	for q in 4:
		var qa := q * TAU / 4.0 + PI / 4.0
		draw_arc(op, tr, qa - 0.5, qa + 0.5, 8, tcol, 1.5)
	Art.text(self, "SILENCE THE SPOTTER", op + Vector2(-38, -20), 8, Color(1.0, 0.4, 0.3, 0.5 + tp * 0.4))


func _draw_gunships() -> void:
	var slot := 0
	for g in sim.gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		_draw_one_gunship(g["boss"], "BRIDGE GUNSHIP", slot)
		slot += 1
	if not sim.endless_boss.is_empty() and sim.endless_boss["alive"]:
		# Endless miniboss wears the attack-heli bake so it reads as its own threat,
		# not a reskin of the campaign bridge boss (same PI = nose-down convention).
		_draw_one_gunship(sim.endless_boss, "GUNSHIP", slot, "m_heli_attack2")
		slot += 1
		_endless_boss_key = "boss%d" % sim.endless_boss["gate_y"]
	elif _endless_boss_key != "":
		# Prune the dead miniboss's view-side bar state — its key is never reused.
		_boss_hpmax.erase(_endless_boss_key)
		_boss_ghost.erase(_endless_boss_key)
		_endless_boss_key = ""
		# Arena scarring (9/9 identity): the fallen gunship leaves a wreck —
		# by wave 20 the field TELLS the run's story.
		_hulks.append({"x": 320 * Fixed.ONE, "y": -140 * Fixed.ONE + (len(_hulks) % 3) * 30 * Fixed.ONE,
			"t": 0.0, "rot": float(Art.cell_hash(len(_hulks), 7) % 628) / 100.0})
	_boss_bar_slots = slot   # banners read this to duck below the occupied bar band


const LABEL_PLATE_FILL := Color(0.04, 0.05, 0.03, 0.55)   # a2-17: shared boss-label plate fill

static func _label_plate_rect(origin_x: float, top_y: float, w: float) -> Rect2:
	# a2-17: a label-anchored dark plate — starts 3px LEFT of the label origin, 6px wider,
	# so it always sits UNDER the (left-anchored) boss phase label in 1P and 2P.
	return Rect2(origin_x - 3.0, top_y, w + 6.0, 13.0)


const GUNSHIP_PHASE_NAMES := ["STRAFING RUN", "MORTAR VOLLEY"]
const COLOSSUS_PHASE_NAMES := ["ADVANCE", "MORTAR VOLLEYS", "SAPPERS OUT"]


func _draw_one_gunship(boss: Dictionary, label: String, slot: int, body_tex := "gunship_body") -> void:
	if boss["phase_t"] < 0:
		# Endless fly-in presence kit (6v panel): the approach used to be a flat
		# grey smudge. Now: a shadow that grows/darkens toward the engaged
		# 16/0.42 values as it lands, the REAL bake under a clearing high-alt
		# haze (cool, translucent -> full), the warm boss rim (via _BOSS_RIM),
		# and a scaled rotor blur so it reads "helicopter", not "texture bug".
		var eta_f := 1.0 + float(boss["phase_t"]) / 420.0   # 0 -> 1 across the approach
		var ground := _to_screen(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
		_ground_shadow(ground + Vector2(0, 30), 8.0 + eta_f * 18.0, 0.12 + eta_f * 0.30)
		# Diagonal slide-in from the top-right: a straight vertical drop hid the
		# whole approach behind the HUD strip (arrival hovers at screen y~50).
		var apos := ground + Vector2((1.0 - eta_f) * 150.0, -(1.0 - eta_f) * 55.0)
		var asc := 0.5 + eta_f * 0.8   # a1-01: lands at boss-scale (1.3), out-reads a tank
		_spr(body_tex, apos, PI, asc, Color(0.92, 0.94, 1.05, 0.35 + eta_f * 0.65))
		var frr := float(Engine.get_physics_frames()) * 0.9 * maxf(_motion, 0.3)
		var rlen := 42.0 * (asc / 1.3)
		for fri in 2:
			var fra := frr + fri * PI / 2
			draw_line(apos - Vector2.from_angle(fra) * rlen, apos + Vector2.from_angle(fra) * rlen,
				Color(0.85, 0.9, 0.95, 0.20 + eta_f * 0.15), 1.5)
		return
	var bpos := _to_screen(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
	# Idle hover: a slow vertical bob + faint sway so the gunship reads as airborne,
	# not a parked sprite. Slot-offset so two bosses don't bob in lockstep; scaled
	# by _motion so REDUCE MOTION damps it.
	var _bf := float(Engine.get_physics_frames())
	bpos += Vector2(sin(_bf * 0.05 + slot) * 1.5, sin(_bf * 0.08 + slot * 2.0) * 2.5) * _motion
	# Mortar-phase warning: the hull flashes red while volleys are near
	# (they land at phase_t 200/240/280 of the 360-tick cycle).
	var pt: int = boss["phase_t"]
	# Spray telegraph (8v): the chin turret charges over the last 6 ticks of
	# each 12-tick spray interval, and a faint aim hint restores the danger
	# gradient at close range (information, so it survives reduce-motion).
	if pt < SimWorld.BOSS_CYCLE_TICKS / 2:
		var sk := pt % SimWorld.BOSS_SPRAY_INTERVAL_TICKS
		var chin := bpos + Vector2(0, 20)
		if sk >= 6 or _motion < 0.5:
			var ca := 0.3 if _motion < 0.5 else (float(sk - 6) / 5.0) * 0.6
			draw_circle(chin, 3.5, Color(1.0, 0.6, 0.3, ca))
		if sk == 0:
			draw_circle(chin, 6.0, Color(1, 1, 1, 0.85))
		var gt := sim._nearest_alive_player(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
		if not gt.is_empty():
			var gtp := _to_screen(gt["x"], gt["y"])
			draw_line(chin, chin + (gtp - chin).normalized() * 60.0, Color(1.0, 0.3, 0.2, 0.3), 1.0)
	var hull_mod := Color.WHITE
	if pt >= 170 and pt <= 290 and (_motion < 0.5 or (Engine.get_physics_frames() / 6) % 2 == 0):
		hull_mod = Color(1.5, 0.6, 0.5)
	hull_mod = hull_mod.lerp(Color(2.2, 2.2, 2.2), _boss_flash)
	# Ground shadow: the heli was the one unit floating untethered (drone and
	# technical are grounded). Offset down-screen for altitude; bpos carries the
	# hover bob, so the shadow breathes with it and the airborne read holds.
	# a3-01: march-gate the tint — green-black over the bridge, cooling to blue-black
	# only if the gunship is ever fought at the hot end (matches the colossus rule).
	_ground_shadow(bpos + Vector2(0, 30), 26.0, 0.42,
		Color(0.0, 0.03, 0.0).lerp(Color(0.02, 0.02, 0.05), smoothstep(0.6, 1.0, _sector_march())))
	# a1-01 rotor DOWNWASH: a dust ring pulses outward under the hull, selling
	# rotor wash + altitude/mass the small hull alone never conveyed.
	var _dwt := float(Engine.get_physics_frames()) * 0.9
	var dw := fposmod(_dwt * 0.12, 1.0)
	draw_arc(bpos + Vector2(0, 30), 12.0 + dw * 40.0, 0, TAU, 26,
		Color(0.80, 0.78, 0.60, (1.0 - dw) * 0.22 * _motion), 2.0)
	_spr(body_tex, bpos, PI, 1.3, hull_mod)
	# Chin turret: real bake now (was a 4x4 blank). PI matches the hull so the
	# muzzle points down-screen at the players, same convention as the colossus.
	_spr("gunship_barrel", bpos + Vector2(0, 18), PI, 1.3, hull_mod)
	# Rotor blur.
	var rt := float(Engine.get_physics_frames()) * 0.9
	for i in 2:
		var a := rt + i * PI / 2
		draw_line(bpos - Vector2.from_angle(a) * 42.0, bpos + Vector2.from_angle(a) * 42.0,
			Color(0.85, 0.85, 0.85, 0.5), 3.0)
	draw_circle(bpos, 5.0, Color(0.3, 0.3, 0.35))
	# a1-01 hit BLOOM: a heavier white flash bloom on _boss_flash — drawn last so
	# it sits on the full silhouette (hull + chin + rotor), not under the blades.
	if _boss_flash > 0.01:
		draw_circle(bpos, 34.0 + _boss_flash * 12.0, Color(1, 1, 1, _boss_flash * 0.28))
	var bkey := "boss%d" % boss["gate_y"]
	# Divide by the most HP this boss has ever shown, not the campaign constant —
	# exact for any scaling without duplicating the sim's spawn formula.
	_boss_hpmax[bkey] = maxf(_boss_hpmax.get(bkey, 1.0), float(boss["hp"]))
	var bfrac := minf(1.0, float(boss["hp"]) / _boss_hpmax[bkey])
	_boss_wounds(bpos, 1.0 - bfrac, 34.0)   # a3-11: hp-keyed hull damage — the gunship hull/barrel/rotor/core were all drawn above; this overlays on top
	# Fixed top-center HUD slot (mirrors the colossus's fixed bottom-center
	# bar, ~1618): the boss's screen pos can sit above the held camera or
	# off-screen, and a world-anchored bar would go with it. Stacked by
	# slot so two simultaneous bosses don't overlap each other, and started
	# below the corner HUD panel's max height (~60px) so they never clash.
	# Shake-immune: the bar is a fixed HUD slot, so cancel the node's shake/zoom
	# for the rest of this function (restored by the caller's next world draw
	# via the reset at the bottom).
	draw_set_transform_matrix(get_transform().affine_inverse())
	var bar_w := 160.0
	var bar_x := 320.0 - bar_w / 2.0
	var bar_y := HudIcons.BOSS_BAR_TOP + float(slot) * 22.0
	# Same strafe/mortar half-cycle the sim uses to pick behavior in
	# _step_one_boss (t < BOSS_CYCLE_TICKS/2), surfaced the way the
	# colossus bar labels its phase.
	var gphase := 1 if pt < SimWorld.BOSS_CYCLE_TICKS / 2 else 2
	# a2-17 HUD#6: name the phase (actionable) instead of "PHASE 1/2"; HUD#1: plate it
	# so the highest-stakes read has the plate language the rest of the top band has.
	var gplabel := "%s — %s" % [label, GUNSHIP_PHASE_NAMES[gphase - 1]]
	var gpw := Art.font().get_string_size(gplabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_rect(_label_plate_rect(bar_x, bar_y - 2.0, gpw), LABEL_PLATE_FILL)
	Art.text(self, gplabel, Vector2(bar_x, bar_y), 10, Color(1.0, 0.5, 0.4))
	_draw_bar(Rect2(Vector2(bar_x, bar_y + 4), Vector2(bar_w, 8)), bfrac,
		Color(0.85, 0.25, 0.18), _bar_ghost(bkey, bfrac), 2)
	# Next-volley countdown: a tick that sweeps left->right across the HP
	# bar and lands on the right edge exactly as each mortar strike lands
	# (170->200, 200->240, 240->280) — the barrage is now anticipable on
	# the bar you're already watching, not just the hull-flash that can
	# sit off-screen above the held camera.
	if pt >= 170 and pt < SimWorld.BOSS_MORTAR_TICKS[2]:
		var vseg_start := 170
		var vseg_end := SimWorld.BOSS_MORTAR_TICKS[0]
		if pt >= SimWorld.BOSS_MORTAR_TICKS[1]:
			vseg_start = SimWorld.BOSS_MORTAR_TICKS[1]
			vseg_end = SimWorld.BOSS_MORTAR_TICKS[2]
		elif pt >= SimWorld.BOSS_MORTAR_TICKS[0]:
			vseg_start = SimWorld.BOSS_MORTAR_TICKS[0]
			vseg_end = SimWorld.BOSS_MORTAR_TICKS[1]
		var vfrac := float(pt - vseg_start) / float(vseg_end - vseg_start)
		var vx := bar_x + bar_w * vfrac
		draw_line(Vector2(vx, bar_y - 2.0), Vector2(vx, bar_y + 16.0),
			Color(1.0, 0.85, 0.3, 0.9), 2.0)
		draw_arc(Vector2(vx, bar_y - 3.0), 3.0, 0, TAU, 10, Color(1.0, 0.85, 0.3, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # back to world space


static func _boss_wound_scars(wound: float) -> int:
	# a3-11: how many scorch scars (0..4) a boss shows at this wound (1 - hp fraction) —
	# scars accumulate from BOSS_WOUND.scar_start, one per scar_step. Pure so it's testable.
	if wound < BOSS_WOUND["scar_start"]:
		return 0
	var n := 0
	for i in 4:
		if wound >= BOSS_WOUND["scar_start"] + float(i) * BOSS_WOUND["scar_step"]:
			n += 1
	return n


func _boss_wounds(center: Vector2, wound: float, r: float) -> void:
	# a3-11 (UNIT#1): hp-keyed battle damage — as a boss loses hp it accumulates scorch
	# scars, trails smoke, and (near death) sputters sparks, so you can READ how close the
	# kill is off the hull, not just the bar. Pure per-frame draw (NO fx spawn — that would
	# be frame-rate-dependent, per the codebase rule); deterministic phases off physics_frames
	# so smoke/sparks animate without RNG. Scars sit ON the hull; smoke rises ABOVE it; the
	# a3-01 separator rim (drawn per-sprite) stays intact so the silhouette still reads.
	if wound < BOSS_WOUND["scar_start"]:
		return
	var t := float(Engine.get_physics_frames())
	# Scorch scars accumulate at fixed hull offsets as the wound deepens (count driven by
	# _boss_wound_scars off BOSS_WOUND — no parallel magic numbers).
	for i in _boss_wound_scars(wound):
		var sp := center + Vector2.from_angle(float(i) * 1.7 + 0.5) * r * 0.5
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(sp - Vector2(6.0, 6.0), Vector2(12.0, 12.0)),
			false, Color(0.05, 0.04, 0.03, 0.5 * wound))
	# Smoke wisps rising off the hull, denser with the wound (gated by REDUCE MOTION).
	for i in int(wound * 3.0) + 1:
		var ph := fposmod(t * 0.02 + float(i) * 0.37, 1.0)
		var sx := center.x + sin(float(i) * 2.1 + t * 0.03) * r * 0.4
		var sy := center.y - ph * (r + 12.0)
		draw_circle(Vector2(sx, sy), 4.0 + ph * 6.0,
			Color(0.15, 0.14, 0.13, (1.0 - ph) * 0.3 * wound * _motion))
	# Near death: sparks sputter off the hull.
	if wound > BOSS_WOUND["spark"]:
		for i in 3:
			var spp := center + Vector2.from_angle(t * 0.2 + float(i) * 2.0) \
				* r * (0.4 + fposmod(t * 0.05 + float(i), 1.0) * 0.5)
			draw_circle(spp, 1.3, Color(1.0, 0.7, 0.3, (0.6 + 0.4 * sin(t * 0.4 + float(i))) * _motion))


func _draw_colossus() -> void:
	if sim.colossus.is_empty() or not sim.colossus["alive"]:
		return
	var cpos := _to_screen(sim.colossus["x"], sim.colossus["y"])
	var phase := sim.colossus_phase()
	# Crush footprint: the true instant-death contact radius, drawn on the
	# ground like a mortar telegraph — 'do not enter' in the no-revive finale.
	var crush := SimWorld.COLOSSUS_CRUSH_RADIUS * PX
	var cpulse := Art.pulse(0.18)
	draw_arc(cpos, crush, 0, TAU, 28, Color(1.0, 0.2, 0.15, 0.4 + cpulse * 0.35), 2.0)
	draw_circle(cpos, crush, Color(1.0, 0.15, 0.1, 0.08))
	var mod := Color.WHITE if phase < 3 else Color(1.4, 0.62, 0.55)
	mod = mod.lerp(Color(2.2, 2.2, 2.2), _boss_flash)
	# Foundry-stomp: a slow settle-squash gives the heaviest thing on the field weight,
	# so it lands with each stride instead of gliding in flat. Pure per-frame visual
	# (no fx spawn from _draw — that would be frame-rate-dependent).
	var stomp := sin(float(Engine.get_physics_frames()) * 0.12) * 0.5 + 0.5
	var cbody := cpos + Vector2(0, stomp * 2.0)
	var csquash := 1.0 - stomp * 0.06
	# a3-01: cool the contact shadow to a blue-black — the colossus ONLY fights on the
	# hot foundry floor, where the default green-black shadow reads as a wrong-hue smear.
	_ground_shadow(cpos, 30.0, 0.42, Color(0.02, 0.02, 0.05))
	_spr("colossus_body", cbody, PI, 1.9, mod, csquash)
	_spr("colossus_barrel", cbody + Vector2(-24, 26), PI - 0.5, 1.3, mod)
	_spr("colossus_barrel", cbody + Vector2(24, 26), PI + 0.5, 1.3, mod)
	# a3-11: hp-keyed hull damage — drawn HERE in world space, before the HUD bar's
	# transform-cancel below flips to screen space (the same fraction the bar uses).
	_boss_wounds(cbody, 1.0 - float(sim.colossus["hp"]) / float(SimWorld.COLOSSUS_HP), 40.0)
	# Turret warm-up: barrel tips glow brighter as the next spray approaches.
	var warm := 1.0 - float(sim.colossus["spray_cd"]) / float(SimWorld.COLOSSUS_SPRAY_CD_TICKS)
	for bx in [-24.0, 24.0]:
		draw_circle(cpos + Vector2(bx, 34.0), 2.0 + warm * 3.5,
			Color(1.0, 0.55, 0.15, 0.15 + warm * 0.55))
	var pulse := Art.pulse(0.2)
	# Core window: when the plating is retracted, the core glows white-hot and
	# a 'CORE EXPOSED' ring says 'shoot it NOW' — bullets chip it this beat.
	var co: int = sim.colossus.get("core_open", 0)
	if co > 0:
		# About-to-seal cue: in the final ~15 ticks the plating is retracting, so
		# strobe the exposed-core ring toward red AND shrink it — "the window is
		# closing, land it NOW" — instead of the window snapping shut silently and
		# eating late bullets on sealed steel. Reuses the white-strobe grammar.
		var sealf := clampf(1.0 - co / 15.0, 0.0, 1.0)   # 0 until the last 15 ticks, →1 at seal
		var cshrink := 1.0 - sealf * 0.45
		var ccore := Color(1.0, 0.95, 0.7, 0.9)
		var cring := Color(1.0, 1.0, 0.6, 0.9)
		if sealf > 0.0:
			var seal_strobe := Color(1.0, 0.2, 0.15) if (co / 2) % 2 == 0 else Color(1.0, 0.85, 0.45)
			ccore = ccore.lerp(seal_strobe, sealf)
			cring = cring.lerp(Color(1.0, 0.2, 0.15, 0.95), sealf)
		draw_circle(cpos, (9.0 + pulse * 4.0) * cshrink, ccore)
		draw_arc(cpos, (16.0 + pulse * 3.0) * cshrink, 0, TAU, 28, cring, 2.5)
	else:
		draw_circle(cpos, 7.0 + pulse * 2.0, Color(0.95, 0.25, 0.15, 0.85))
	# Bottom-center (y=330) so the fill never hides under the top-left HUD panel — this boss bar
	# deliberately docks OPPOSITE the top-center gunship/mini bars (HudIcons.BOSS_BAR_TOP), so it
	# does NOT use that boundary; the two never share the band. Shake-immune: fixed HUD slot,
	# cancel the node transform for the bar block.
	draw_set_transform_matrix(get_transform().affine_inverse())
	var cfrac := float(sim.colossus["hp"]) / float(SimWorld.COLOSSUS_HP)
	# a2-17 HUD#1: plate the colossus phase label too (highest-stakes fight).
	# a2-17 r2 HUD#6: name the colossus phases (actionable), matching the escalation
	# banners (phase 2 = mortar volleys, phase 3 = sappers out).
	var clabel := "FOUNDRY COLOSSUS — %s" % COLOSSUS_PHASE_NAMES[clampi(phase - 1, 0, 2)]
	var clw := Art.font().get_string_size(clabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_rect(_label_plate_rect(172.0, 324.0, clw), LABEL_PLATE_FILL)
	Art.text(self, clabel, Vector2(172, 326), 10, Color(1.0, 0.55, 0.45))
	_draw_bar(Rect2(Vector2(170, 330), Vector2(300, 13)), cfrac,
		Color(0.85, 0.25, 0.18), _bar_ghost("colossus", cfrac), 3)
	# Next-core-open countdown: same sweeping tick as the gunship's mortar
	# marker above, so the plating-retract window is timeable off the fixed
	# bottom bar instead of the small warm-up glow on the barrels.
	if sim.colossus.get("core_open", 0) == 0:
		var cc: int = sim.colossus.get("core_cd", SimWorld.COLOSSUS_CORE_CYCLE_TICKS)
		var cvfrac := 1.0 - float(cc) / float(SimWorld.COLOSSUS_CORE_CYCLE_TICKS)
		var cvx := 170.0 + 300.0 * clampf(cvfrac, 0.0, 1.0)
		draw_line(Vector2(cvx, 328.0), Vector2(cvx, 345.0), Color(1.0, 0.85, 0.3, 0.9), 2.0)
		draw_arc(Vector2(cvx, 327.0), 3.0, 0, TAU, 10, Color(1.0, 0.85, 0.3, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)   # back to world space


func _draw_projectiles() -> void:
	for g in sim.grenades:
		var base := _to_screen(g["x"], g["y"])
		var zf := clampf(float(g["z"]) * PX * 0.02, 0.0, 0.6)   # shadow shrinks+fades as the frag climbs = reads as height
		draw_circle(base + Vector2(2, 2), 3.0 * (1.0 - zf), Color(0, 0, 0, 0.35 * (1.0 - zf)))
		# Per-grenade spin phase (hashed off x) — a volley no longer rotates in lockstep.
		var spin := float(Engine.get_physics_frames()) * 0.4 + float(g["x"] % 6283) * 0.001
		var body := base - Vector2(0, g["z"] * PX * 0.5)
		# Real frag silhouette (the capsule sprite read as a pill). Shells
		# fly steel-dark and bigger.
		if g.get("shell", false):
			# Real AP shell, nose to velocity (was a re-tinted spinning grenade).
			_spr("tank_shell", body, Vector2(g["vx"], g["vy"]).angle() + PI / 2)
		else:
			draw_set_transform(body, spin, Vector2.ONE)
			draw_texture_rect(Art.tex("wep_grenade"), Rect2(-5, -5, 10, 10), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Fuse ember: live ordnance glows. The frag was the one airborne object
			# emitting nothing — easy to lose over bright terrain despite being the
			# biggest damage source. Flicker desynced per grenade off its x.
			var fz := 0.5 + 0.4 * sin(float(Engine.get_physics_frames()) * 0.9 + float(g["x"] % 6283) * 0.01)
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(body - Vector2(3.5, 3.5), Vector2(7, 7)),
				false, Color(1.0, 0.6, 0.2, 0.8 * fz))
			draw_circle(body, 1.0, Color(1.0, 0.9, 0.6, 0.5 + 0.5 * fz))
		# Landing marker: the parabola is deterministic — solve where it lands.
		var zv := float(g["zv"])
		var grav := float(SimWorld.GRENADE_GRAV)
		var tt := (zv + sqrt(zv * zv + 2.0 * grav * maxf(0.0, float(g["z"])))) / grav
		var land := base + Vector2(g["vx"], g["vy"]) * PX * tt
		var lr := 6.0 if g.get("shell", false) else 4.5
		var lc := Color(1.0, 0.95, 0.7, 0.55)
		# Blast-radius preview: grenades are the ONLY armor damage, so show the
		# true kill circle at the landing point — will this throw catch it?
		var blast := SimWorld.GRENADE_RADIUS * PX
		draw_texture_rect(Art.tex("fx_ring"), Rect2(land - Vector2.ONE * blast, Vector2.ONE * blast * 2.0),
			false, Color(GRENADE_PREVIEW_COL.r, GRENADE_PREVIEW_COL.g, GRENADE_PREVIEW_COL.b, 0.18))   # a2-15 LEG#5
		draw_arc(land, blast, 0, TAU, 28, Color(GRENADE_PREVIEW_COL.r, GRENADE_PREVIEW_COL.g, GRENADE_PREVIEW_COL.b, 0.35), 1.0)
		draw_arc(land, lr, 0, TAU, 16, lc, 1.0)
		draw_line(land + Vector2(-2.5, 0), land + Vector2(2.5, 0), lc, 1.0)
		draw_line(land + Vector2(0, -2.5), land + Vector2(0, 2.5), lc, 1.0)
	# Colossus ricochet: bullets do NOTHING to the finale (grenades only), but
	# the sim never collides them — so ping them off the armor here to teach it.
	var col_on: bool = not sim.colossus.is_empty() and sim.colossus.get("alive", false)
	var col_pos := _to_screen(sim.colossus.get("x", 0), sim.colossus.get("y", 0)) if col_on else Vector2.ZERO
	# Collect submerged-frogman screen positions ONCE — the old per-bullet rescan of
	# sim.enemies was O(bullets × enemies) with a Vector2 alloc per pair.
	var submerged_pos: Array[Vector2] = []
	for e in sim.enemies:
		# kind-gate: a punch-out-grace pilot wears the submerged flag too, but
		# a water-deflect ripple on dry land would misread as a frogman.
		if e["alive"] and e.get("submerged", false) and e["kind"] != "pilot":
			submerged_pos.append(_to_screen(e["x"], e["y"]))
	for b in sim.bullets:
		var bpos := _to_screen(b["x"], b["y"])
		if col_on and bpos.distance_to(col_pos) < SimWorld.COLOSSUS_HIT_RADIUS * PX + 4.0:
			if (b["x"] / 4099 + Engine.get_physics_frames()) % 2 == 0:
				draw_circle(bpos, 2.4, Color(1.0, 0.85, 0.4, 0.8))
				draw_circle(bpos, 1.0, Color(1.0, 1.0, 0.9))
			# Armor plink (9v): heavy plate SOUNDS armored too — deep ping,
			# throttled, silent while the core window is open (those rounds
			# matter), plus a one-shot ARMORED teach hint.
			if sim.colossus.get("core_open", 0) == 0 \
					and Engine.get_physics_frames() - _colossus_ping_frame >= 10:
				_colossus_ping_frame = Engine.get_physics_frames()
				_sfx.play_at("ping_armor", bpos, -14.0, 0.85)
				_hint("colossus_armor", "ARMORED — WAIT FOR THE CORE")
			continue
		# Submerged frogmen are grenades-only too — ping bullets off the ripple
		# so 'I emptied a mag into the water and nothing died' becomes legible.
		var deflect := false
		for sp in submerged_pos:
			if bpos.distance_to(sp) < 7.0:
				draw_circle(bpos, 2.0, Color(0.7, 0.9, 1.0, 0.8))
				deflect = true
				break
		if deflect:
			continue
		var dir := Vector2(b["vx"], b["vy"]).normalized()
		# Real tracer rounds: a thin hot streak with a bright head. Sustained
		# fire heats the barrel — tracers shift yellow → white-hot.
		var owner: int = b.get("owner", 0)
		var heat: float = _heat[owner] if owner < _heat.size() else 0.0
		# Piercing Rounds read as cyan AP tracers, distinct from the hot MG streak.
		var piercing: bool = owner < sim.players.size() and sim.players[owner]["pierce_ticks"] > 0
		var tail := Color(0.5, 0.9, 1.0, 0.7) if piercing \
			else Color(1.0, 0.8, 0.35, 0.45).lerp(Color(1.0, 0.95, 0.85, 0.6), heat)
		# Body: a legacy art streak card (fx_bullettrail) stretched back along -velocity,
		# tinted by the same hot/AP tail color; the crisp core + head stay procedural.
		var tlen := 8.0 + heat * 3.0 + (5.0 if piercing else 0.0)
		var twid := 5.0 if piercing else 4.0
		draw_set_transform(bpos, dir.angle(), Vector2.ONE)
		draw_texture_rect(Art.tex("fx_bullettrail"), Rect2(-tlen, -twid / 2.0, tlen, twid), false, tail)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(bpos - dir * 3.0, bpos, Color(0.7, 0.95, 1.0, 0.95) if piercing else Color(1.0, 0.95, 0.7, 0.95), 1.4)
		draw_circle(bpos, 1.3 if piercing else 1.1, Color(0.9, 1.0, 1.0) if piercing else Color(1.0, 1.0, 0.85))
	for b in sim.enemy_bullets:
		var bpos := _to_screen(b["x"], b["y"])
		# Travel streak behind the orb so incoming fire reads as moving ordnance,
		# not a hovering dot (the player tracers already get this motion read).
		var evel := Vector2(b["vx"], b["vy"])
		var edir := evel.normalized()
		# Streak length scales with speed so a 2× round (sniper/ghillie, speed 6)
		# visibly reads 2× the standard round (speed 3): ~5px → ~11px tail.
		var espd := evel.length() / float(SimWorld.ENEMY_BULLET_SPEED)   # 1.0 standard, ~2.0 fast
		var fast: bool = espd > 1.4
		if edir.length() > 0.5:
			# Same fx_bullettrail streak card the player tracers wear, modulated
			# hostile-red — incoming fire gets the identical motion vocabulary.
			var etlen := 5.0 + maxf(0.0, espd - 1.0) * 6.0
			draw_set_transform(bpos, edir.angle(), Vector2.ONE)
			draw_texture_rect(Art.tex("fx_bullettrail"), Rect2(-etlen, -2.0, etlen, 4.0),
				false, Color(1.0, 0.25, 0.25, 0.55))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Hostile fire: small glowing red orb — ordnance, not infantry. Fast rounds
		# burn a white-hot core so their speed reads before they reach you.
		var egr := 4.4
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(bpos - Vector2.ONE * egr, Vector2.ONE * egr * 2.0),
			false, Color(1.0, 0.3, 0.15, 0.55))
		# Universal white-hot core inside a colored rim (4v — the all-red orb
		# mush was HATE #3): threat hue lives on the rim, the core is ALWAYS
		# white so every live round pops off the red-tinted chaos.
		draw_circle(bpos, 2.6, Color(0.75, 0.9, 1.0) if fast else Color(1.0, 0.35, 0.2))
		draw_circle(bpos, 1.6, Color(1, 1, 1))


static func _player_ident_color(slot: int, a := 1.0) -> Color:
	# a1-18: the co-op identity color — P1 friendly-green routed through Art.safe
	# (colorblind -> blue, never danger-red), P2 gold. Shared by the ring, the
	# off-screen partner chevron, and the downed body so identity reads consistently.
	var base := Art.safe(Color(0.4, 1.0, 0.4)) if slot == 0 else Color(1.0, 0.85, 0.3)
	return Color(base.r, base.g, base.b, a)


static func _body_ident_lean(slot: int) -> Color:
	# a2-03: the subtle identity MULTIPLY folded onto the live hero body — green P1 /
	# gold P2 via the colorblind-safe ident color, kept bright (0.18 lean) so co-op
	# bodies read apart without recoloring the hero.
	return Color.WHITE.lerp(_player_ident_color(slot), 0.18)


static func _player_ring_dashed(slot: int) -> bool:
	# a1-18 LEG#3: P1 ring is SOLID, P2 ring is DASHED — hue-independent identity.
	return slot != 0


static func _tree_instance(h2: int) -> Dictionary:
	# a2-08: per-instance tree variety from the cell hash — scale x0.85..1.138 and a
	# 1-in-11 dead-tree swap — so the canopy stops reading as a repeated stamp.
	return {"scale_mul": 0.85 + float(h2 % 7) * 0.048, "dead": h2 % 11 == 0}


func _draw_players() -> void:
	for i in sim.players.size():
		var p := sim.players[i]
		if p["in_tank"] >= 0:
			# ...except the GUNNER, who rides the deck: small crew sprite + aim
			# tick so the second seat is visible on the field (re-review).
			var g_tank: Dictionary = sim.tanks[p["in_tank"]]
			if g_tank["occupant"] != i:
				# 5v panel: 0.3 scale read as a decal; 0.42 reads as a crewman.
				# Aim line lengthened + brightened so the second gun's threat
				# lane is legible at a glance.
				var gdpos := _to_screen(p["x"], p["y"]) + Vector2(0, -7.0)
				_spr("player2" if i == 1 else "player1", gdpos, 0.0, 0.42, Color(1.1, 1.1, 1.05))
				var gaim := Vector2(p["aim_x"], p["aim_y"])
				if gaim.length() > 0.01:
					draw_line(gdpos, gdpos + gaim.normalized() * 16.0, Color(0.9, 0.97, 1.0, 0.9), 1.0)
			continue   # driver renders as the tank
		var pos := _to_screen(p["x"], p["y"]) + (_recoil[i] if i < _recoil.size() else Vector2.ZERO) + (_hit_flinch[i] if i < _hit_flinch.size() else Vector2.ZERO)
		# Run-cycle bob: a per-step vertical hop while moving, matching the charging
		# enemies' cadence so the player sprite isn't the one flat-gliding thing on the
		# field. _dust_prev still holds LAST frame's pos here (updated by _kick_dust below).
		# sol-13 (FINAL AD LOCK): the infantry set walk/ frames are a 3/4 running pose (taller, centroid-
		# jittery) that clashes with this top-down hero, and no OWNED top-down walk sheet exists (the legacy art
		# bakes are single-pose). So this golden-safe bob is the hero's locomotion by decision, not as a
		# stopgap — the guard test keeps a future edit from re-wiring the 3/4 frames.
		var walk_bob := 0.0
		if p["alive"] and p["roll_ticks"] == 0 and i < _dust_prev.size() and Vector2i(p["x"], p["y"]) != _dust_prev[i]:
			walk_bob = absf(sin(Engine.get_physics_frames() * 0.35 + i * PI)) * 1.2 * _motion
		elif p["alive"] and p["roll_ticks"] == 0:
			# Idle breathing: the standing-still soldier was the one frozen thing on an
			# otherwise fully-animated field — a tiny slow micro-bob keeps it alive.
			# (Both stilled by _motion, like the jeep bob and boss hover already are.)
			walk_bob = sin(Engine.get_physics_frames() * 0.045 + i * PI) * 0.35 * _motion
		var tex_name := "player1" if i == 0 else "player2"
		if p["alive"] and not sim._in_water(p["x"], p["y"]):
			_kick_dust(i, p["x"], p["y"], _dust_prev, false)
		else:
			_dust_prev[i] = Vector2i(p["x"], p["y"])
		if sim._in_water(p["x"], p["y"]):
			_ground_shadow(pos, 7.0, 0.18, Color(0.0, 0.04, 0.10))
		else:
			_ground_shadow(pos, 7.0)
		if not p["alive"]:
			# Downed but not gone: a greyed prone body so a waiting-for-revive
			# teammate is visibly THERE on the field, not just a floating beacon.
			# a1-18 UNIT#5: the downed body keeps its player COLOR (dim) so co-op can tell
			# WHICH teammate is down — P1 safe-green, P2 gold (was an identity-blind grey).
			var down_col := _player_ident_color(i, 0.72)
			_spr(tex_name, pos, PI / 2, 0.46, down_col)
		# Smoke concealment: a drifting grey shroud — drawn UNDER the soldier and
		# the co-op identity ring (drawn over, it buried both for ~4 of its 5
		# seconds, exactly when co-op players need their avatar). Thins over the
		# final second so the expiry never blindsides you.
		if p["alive"] and p["smoke_ticks"] > 0:
			var sm_frac := clampf(float(p["smoke_ticks"]) / float(SimWorld.SMOKE_TICKS), 0.0, 1.0)
			var sm_a := 0.45 * minf(1.0, sm_frac * 5.0)
			# Final-second blink (2.5 flashes/s — under the photosensitivity
			# line): pairs with the pre-expiry tick so the window closing reads.
			if p["smoke_ticks"] <= 60 and (p["smoke_ticks"] / 12) % 2 == 1:
				sm_a *= 0.35
			var sm_ph := float(Engine.get_physics_frames() + i * 43)
			for sm_k in 4:
				var sm_off := Vector2(sin(sm_ph * 0.03 + sm_k * 1.7) * 7.0,
					cos(sm_ph * 0.025 + sm_k * 2.3) * 5.0 - 4.0)
				# Baked smoke cards (alternating fx_smoke/fx_fumes4) with a slow
				# view-side tumble — the 4 flat grey discs read as a UI blob, not
				# gas. Sized via explicit rect: the two cards have different canvas
				# norms (200px vs 1024px), so per-tex draw_scale would mismatch.
				var sm_r := 8.0 + 2.0 * sin(sm_ph * 0.04 + sm_k * 0.9)
				draw_set_transform(pos + sm_off, sm_ph * 0.008 + sm_k * 1.6, Vector2.ONE)
				draw_texture_rect(Art.tex("fx_smoke" if sm_k % 2 == 0 else "fx_fumes4"),
					Rect2(-sm_r * 1.4, -sm_r * 1.4, sm_r * 2.8, sm_r * 2.8),
					false, Color(0.75, 0.78, 0.8, sm_a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Identity ring under each soldier so you never lose your guy in the
		# chaos (P1 green / P2 gold, matching the HUD rows). Now ALSO in 1P
		# (4v: the tiny infantry sprite vanished into ground clutter — the
		# ring is the parked-tank board-ring grammar applied to yourself).
		if p["alive"]:
			# a1-18 LEG#2/LEG#3: P1 ring routes through Art.safe (green->blue in colorblind
			# so it never reads as danger-red), and P1/P2 are SHAPE-distinct — P1 a SOLID
			# ring, P2 a DASHED ring — so identity survives without the green-vs-gold hue.
			var idc := _player_ident_color(i, 0.6)
			if _player_ring_dashed(i):
				for ds in 8:
					var da := ds * TAU / 8.0
					draw_arc(pos + Vector2(0, 5), 10.0, da, da + TAU / 16.0, 3, idc, 1.5)
			else:
				draw_arc(pos + Vector2(0, 5), 10.0, 0, TAU, 20, idc, 1.5)
			# Revive-from-here affordance: revive has NO range check (the buddy
			# teleports to you), but the beacon on the body implies you must run
			# to it. Tell the reviver they can pay from where they stand.
			for q in sim.players.size():
				var dp := sim.players[q]
				if q == i or dp["alive"] or sim.last_stand:
					continue
				var dpos := _to_screen(dp["x"], dp["y"])
				# Off-screen partner: an edge chevron in their colour points the way
				# to the body — shown regardless of affordability so you can FIND a
				# far-south downed buddy even before the chest covers the revive.
				if dpos.x < 8 or dpos.x > 632 or dpos.y < 30 or dpos.y > 352:
					var edge := Vector2(clampf(dpos.x, 12, 628), clampf(dpos.y, 34, 348))
					var pcol := _player_ident_color(q)   # a1-18 LEG#2
					var bdir := (dpos - edge).normalized()
					# Shake-immune like every other screen-edge indicator (the
					# threat edges, the boss bars) — the gunship-bar idiom.
					draw_set_transform_matrix(get_transform().affine_inverse())
					draw_circle(edge, 5.0, Color(pcol.r, pcol.g, pcol.b, 0.85))
					draw_line(edge, edge + bdir * 9.0, pcol, 2.0)
					Art.draw_glyph(self, "revive", edge - bdir * 10.0, 9.0)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var cost := sim.revive_cost(dp)
				if sim.war_chest < cost:
					# Broke reviver still needs the TARGET number — the price was
					# hidden exactly when you're short of it, so "feed the war
					# chest" had no answer to "with how much?". Warm red, no
					# pay-from-here dashes (you can't).
					draw_string(Art.font(), pos + Vector2(-18, -16), "REVIVE %d" % cost,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Art.safe(Color(1.0, 0.5, 0.4)))
					continue
				draw_dashed_line(pos, dpos, Color(0.5, 0.9, 1.0, 0.4), 1.0, 4.0)
				var rtxt := "REVIVE %d" % cost
				draw_string(Art.font(), pos + Vector2(-18, -16), rtxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Art.safe(Color(0.5, 1.0, 0.6)))
				Art.draw_glyph(self, "revive", pos + Vector2(24, -19), 10.0)
		if p["alive"]:
			# 0.35 lerp: faster than the enemies' 0.18 so pad/mouse flicks stay
			# responsive while arrow-key 45° pops still glide instead of snapping.
			var angle := lerp_angle(_player_face[i], _aim_angle(p), 0.35)
			_player_face[i] = angle
			var mod := Color.WHITE
			if p["roll_ticks"] > 0:
				# Roll: spin the sprite through the dodge, ghosts trailing it.
				angle += (1.0 - float(p["roll_ticks"]) / float(SimWorld.ROLL_TICKS)) * TAU
				mod = Color(1.2, 1.2, 1.2, 0.85)
				var rdir := Vector2(p["roll_dx"], p["roll_dy"]) * PX
				_spr(tex_name, pos - rdir * 10.0, angle, 0.52, Color(1, 1, 1, 0.14))
				_spr(tex_name, pos - rdir * 5.0, angle, 0.52, Color(1, 1, 1, 0.28))
			elif p["hurt_iframes"] > 0 and (p["hurt_iframes"] / 4) % 2 == 0:
				mod = Color(1, 1, 1, 0.4)   # mercy-window blink
			# Wading: ripple rings at the feet say "slow, no roll" at a glance.
			if sim._in_water(p["x"], p["y"]):
				var wt := float((Engine.get_physics_frames() + i * 31) % 50) / 50.0
				draw_arc(pos + Vector2(0, 4), 4.0 + wt * 8.0, 0, TAU, 16,
					Color(0.75, 0.9, 1.0, 0.5 * (1.0 - wt)), 1.2)
				draw_arc(pos + Vector2(0, 4), 5.0, 0, TAU, 12, Color(0.75, 0.9, 1.0, 0.4), 1.0)
				# a2-07 ENV#7/VFX#2: a directional BOW-WAVE ahead + trailing V-WAKE when the
				# wader is MOVING — water displaced in the travel direction, so a crossing
				# reads as pushing through the current, not standing in it.
				if i < _dust_prev.size() and Vector2i(p["x"], p["y"]) != _dust_prev[i]:
					var wdir := Vector2(float(p["x"] - _dust_prev[i].x), float(p["y"] - _dust_prev[i].y)).normalized()
					var wperp := Vector2(-wdir.y, wdir.x)
					# bow-wave arc + foot-splash dot AHEAD, on the move frame
					draw_arc(pos + wdir * 5.0, 4.5, wdir.angle() - 1.1, wdir.angle() + 1.1, 8,
						Color(0.86, 0.93, 1.0, 0.45 * _motion), 1.3)
					draw_circle(pos + wdir * 3.0, 1.5, Color(0.92, 0.96, 1.0, 0.4 * _motion))
					# segmented trailing V-wake: edge pairs spread back from just behind the
					# feet (proper displaced-water wake, not rays from center)
					var apex := pos - wdir * 3.0
					for sgn in [1.0, -1.0]:
						var e1: Vector2 = apex - wdir * 6.0 + wperp * (5.0 * float(sgn))
						var e2: Vector2 = apex - wdir * 13.0 + wperp * (9.0 * float(sgn))
						draw_line(apex, e1, Color(0.82, 0.91, 0.98, 0.34 * _motion), 1.3)
						draw_line(e1, e2, Color(0.82, 0.91, 0.98, 0.20 * _motion), 1.1)
			# Get-up: blend the residual knockdown topple back out while the decaying
			# _down_anim drains, so a revive rises instead of snapping upright.
			var da_res: float = _down_anim[i] if i < _down_anim.size() else 0.0
			if da_res > 0.0:
				var de_res := 1.0 - pow(1.0 - da_res, 3.0)
				angle = lerp_angle(angle, PI / 2, de_res)
				mod = mod.lerp(Color(0.35, 0.35, 0.35, 0.6), de_res)
			# a2-03: a subtle IDENTITY lean on the LIVE body (green P1 / gold P2 via the
			# colorblind-safe ident color) so co-op heroes read apart at a glance — the
			# ring was the only differentiator; the pale-white bodies were identical.
			mod = mod * _body_ident_lean(i)
			_spr(tex_name, pos - Vector2(0, walk_bob), angle, 0.52, mod)
			# a4-03 (AD#4): the hero is the VALUE APEX — a small constant COOL catch-light on
			# the helmet crown (an implied overhead key) makes the soldier the brightest AND
			# coolest point in every frame, so the eye snaps to HIM first, not the reticle or a
			# tan dirt splat — especially in the busy foundry. Screen-fixed (not aim-rotated) so
			# the key stays overhead; suppressed while downed (a downed body isn't the apex).
			if _hero_shows_apex(da_res):
				var hcrown := pos - Vector2(0.0, walk_bob + HERO_APEX_DY)   # sol-07: drop onto the new dark helmet dome
				draw_texture_rect(Art.tex("fx_softspot"), Rect2(hcrown - HERO_APEX_SZ / 2.0, HERO_APEX_SZ),
					false, Color(HERO_APEX.r, HERO_APEX.g, HERO_APEX.b, HERO_APEX_A))
			# Empty-clip body cue: the corner ammo icon already blinks, but the
			# eye is on the soldier mid-fight. Same bash-ring idiom as the HUD
			# (draining arc while the bash swing is on cooldown, steady dry
			# pip otherwise), anchored on the body instead of the corner.
			if p["mg_ammo"] == 0:
				var dry_pulse: float = 1.0 if _motion < 0.5 else Art.pulse(0.3)
				if p["fire_cd"] > 0:
					var dry_frac := clampf(float(p["fire_cd"]) / float(SimWorld.BASH_COOLDOWN_TICKS), 0.0, 1.0)
					draw_arc(pos, 8.0, -PI / 2, -PI / 2 + TAU * dry_frac, 14,
						Color(0.9, 0.6, 0.3, 0.55 + 0.35 * dry_pulse), 1.5)
				else:
					draw_arc(pos, 8.0, 0, TAU, 14, Color(1.0, 0.3, 0.25, 0.4 + 0.35 * dry_pulse), 1.5)
			# Directional damage wedge — _hit_dir/_hit_dir_t were set on every hit,
			# decayed in feel, and even aim the death gore, yet nothing ever DREW
			# them: flank fire and frontal fire looked identical. A red arc on the
			# hit body, opening toward the shooter (5 of 9 panel reviewers flagged it).
			if i == _hit_dir_player and _hit_dir_t > 0.02 and _hit_dir.length_squared() > 0.25:
				var wa := _hit_dir.angle()
				draw_arc(pos, 21.0, wa - 0.55, wa + 0.55, 12,
					Color(1.0, 0.18, 0.1, 0.85 * _hit_dir_t), 3.0)
				draw_arc(pos, 24.0, wa - 0.3, wa + 0.3, 8,
					Color(1.0, 0.45, 0.3, 0.5 * _hit_dir_t), 1.5)
			# Adrenaline aura: the 20-streak / tank-bail speed surge (boost_ticks) is a
			# real 1.5x buff that was otherwise invisible. A hot ring that fades as the
			# surge drains says "empowered — and here is when it ends". Hoisted OUT of
			# the vest branch — the surge has zero relation to vest state, and a
			# vestless player earning x20 got the speed with no on-body feedback.
			# Reduce-motion: steady ring + static spokes (the pulse/rotation was the
			# one aura in this file ignoring the gate).
			if p["boost_ticks"] > 0:
				var bo_frac: float = clampf(float(p["boost_ticks"]) / float(SimWorld.BAIL_BOOST_TICKS * 2), 0.0, 1.0)
				var bo_ph := float(Engine.get_physics_frames() + i * 17)
				var bo_pulse := 1.0 if _motion < 0.5 else 0.5 + 0.5 * sin(bo_ph * 0.45)
				var bo_spin := 0.0 if _motion < 0.5 else bo_ph * 0.08
				draw_arc(pos, 16.0 + bo_pulse * 3.0, 0, TAU, 28,
					Color(1.0, 0.55, 0.15, (0.35 + 0.4 * bo_pulse) * bo_frac), 2.0 + bo_frac)
				for bo_s in 6:
					var bo_ang := bo_s * TAU / 6.0 + bo_spin
					var bo_dir := Vector2.from_angle(bo_ang)
					draw_line(pos + bo_dir * 12.0, pos + bo_dir * (17.0 + bo_pulse * 4.0),
						Color(1.0, 0.72, 0.3, 0.5 * bo_frac), 1.5)
			if p["vest"]:
				draw_arc(pos, 14.0, 0, TAU, 24, Color(0.55, 0.7, 1.0, 0.9), 2.0)
			else:
				# No-vest fragility: one hit from death, and the exposed stakes
				# should read where the eye already is. A faint, gapped
				# (broken-looking) desaturated ring in place of the solid
				# vest ring — never as loud as the real thing.
				var frag_pulse: float = 1.0 if _motion < 0.5 else Art.pulse(0.1)
				var frag_col := Color(0.55, 0.4, 0.4, 0.15 + 0.12 * frag_pulse)
				for frag_s in 5:
					var frag_a0 := frag_s * TAU / 5.0 + 0.15
					draw_arc(pos, 14.0, frag_a0, frag_a0 + TAU / 5.0 - 0.3, 4, frag_col, 1.0)
			# Aim reticle: the gun tells you where it points.
			var aim := Vector2(p["aim_x"], p["aim_y"]) * PX
			# HOLD FIRE cue: the reticle warns when the gun is trained on the
			# rescue target — the RANSOM LOST ceremony teaches the rule only
			# AFTER the 100¢ is gone; this is the aim-time save.
			if aim.length_squared() > 0.01:
				for pe2 in sim.enemies:
					if not pe2["alive"] or pe2["kind"] != "pilot":
						continue
					var pi_rel := _to_screen(pe2["x"], pe2["y"]) - pos
					var pi_along := pi_rel.dot(aim)
					if pi_along > 0.0 and pi_along < 160.0 and absf(pi_rel.cross(aim)) < 12.0:
						Art.text(self, "HOLD FIRE", pos + aim * 27.0 + Vector2(-22, -14), 8,
							Color(1.0, 0.45, 0.35))
						break
			# Claymore pre-plant ghost (9/9 panel consensus): WHERE the charge
			# will land if INTERACT fires now — ghost sprite + the 9px trigger
			# ring, so a plant is a plan, not a surprise.
			if p["claymores"] > 0 and aim.length_squared() > 0.01 and p["roll_ticks"] == 0:
				var gpos := pos + aim * 20.0
				_spr("wep_claymore", gpos, 0.0, 1.05, Color(1, 1, 1, 0.28))
				draw_arc(gpos, 9.0, 0, TAU, 12, Art.safe(Color(0.5, 0.95, 0.7, 0.35)), 1.0)
			if aim.length_squared() > 0.01 and p["roll_ticks"] == 0:
				# Heat-bloom: the crosshair spreads with sustained fire (the
				# barrel-heat mechanic, made visible at the point of attention).
				var bloom: float = (_heat[i] if i < _heat.size() else 0.0) * 5.0
				var rrect := Rect2(pos + aim * 27.0 - Vector2(8 + bloom, 8 + bloom),
					Vector2(16 + bloom * 2.0, 16 + bloom * 2.0))
				# Bash-in-range tell: dry MG + an enemy in melee reach + off cooldown
				# → the reticle goes orange and the bash reach ring shows, so you
				# know the empty-clip counter is LIVE before you press fire.
				var bash_ready := false
				if p["mg_ammo"] == 0 and p["fire_cd"] == 0:
					for e in sim.enemies:
						if e["alive"] and not e.get("submerged", false) \
								and sim._dist_lte(p["x"], p["y"], e["x"], e["y"], SimWorld.BASH_RADIUS):
							bash_ready = true
							break
				var rcol := Color(0.9, 1.0, 0.65) if i == 0 else Color(1.0, 0.9, 0.55)
				# Dry-and-waiting: empty MG with bash NOT ready → grey the reticle so
				# "nothing will fire" stops reading as "locked and loaded". Pierce/spread/
				# bash overrides below still win when they apply.
				if p["mg_ammo"] == 0 and not bash_ready:
					rcol = Color(0.55, 0.55, 0.5, 0.6)
				# Weapon-state at the point of attention: cyan while Piercing Rounds
				# are up, amber while the Trench Gun spread is up.
				if p["pierce_ticks"] > 0:
					rcol = Color(0.55, 0.9, 1.0)
				elif p["spread_ticks"] > 0 and not p["triple"]:   # Triple (permanent) fires the same fan; a Spread pickup on top is no gain — do not flip to amber
					rcol = Color(1.0, 0.8, 0.45)
				elif p["triple"]:
					rcol = Color(1.0, 0.6, 0.9)   # permanent Triple Shot: magenta, matches the pickup + HUD x3 pip
				if bash_ready:
					rcol = Color(1.0, 0.55, 0.2)
					var bp := Art.pulse(0.25)
					draw_arc(pos, SimWorld.BASH_RADIUS * PX, 0, TAU, 20,
						Color(1.0, 0.55, 0.2, 0.3 + bp * 0.2), 1.5)
				# Shape follows the fire pattern, not just hue (protan-safe): the
				# pierce octagon rings the point it punches through; the fan
				# (Spread pickup AND permanent Triple) wears a WIDE mirrored
				# bracket pair ( ) — the shotgun-bracket card is a single half,
				# drawn twice (negative rect width = horizontal flip).
				var rtex := Art.tex("ui_reticle")
				var rects: Array[Rect2] = [Rect2(-rrect.size / 2.0, rrect.size)]
				if p["pierce_ticks"] > 0:
					rtex = Art.tex("ui_ret_pierce")
				elif p["spread_ticks"] > 0 or p["triple"]:
					rtex = Art.tex("ui_ret_spread")
					var bw := rrect.size.x * 0.45
					rects = [Rect2(-rrect.size.x * 0.62, -rrect.size.y / 2.0, bw, rrect.size.y),
						Rect2(rrect.size.x * 0.62, -rrect.size.y / 2.0, -bw, rrect.size.y)]
				# Confirm-thump: the reticle itself scale-punches on a landed hit.
				var rpunch := 1.0 + (_hitmarker[i] if i < _hitmarker.size() else 0.0) * 0.3
				var rcen := rrect.get_center()
				draw_set_transform(rcen, 0.0, Vector2.ONE * rpunch)
				# a4-05: centered dark halo (all 8 sides) instead of a one-sided drop-shadow —
				# the aim point keeps a full dark keyline against any hot terrain, never just two edges.
				# Diagonals draw LIGHTER (RETICLE_HALO_DIAG) so the corner double-coverage doesn't
				# stack darker than the cardinals — the ring reads as an EVEN halo, not a boxy corner.
				for off in RETICLE_HALO:
					var ha: float = RETICLE_HALO_A if absf(off.x) + absf(off.y) < 1.5 else RETICLE_HALO_A * RETICLE_HALO_DIAG
					for rd in rects:
						draw_texture_rect(rtex, Rect2(rd.position + off, rd.size),
							false, Color(0, 0, 0, ha))
				for rd in rects:
					draw_texture_rect(rtex, rd, false, rcol)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				# Hitmarker: reticle flicks bright + kicks four ticks on a landed hit.
				if i < _hitmarker.size() and _hitmarker[i] > 0.01:
					var hc := Color(1.0, 1.0, 0.85, _hitmarker[i])
					var rc := rrect.get_center()
					# Eased fling: ticks shoot out fast, then settle.
					var off := 8.0 + (1.0 - _hitmarker[i] * _hitmarker[i]) * 4.0
					var hl := Art.tex("hudfx_hitlines")
					for q in 4:
						var qa := q * TAU / 4.0 + PI / 4.0
						# Soft textured hit-streak radiating from the reticle on a landed hit.
						draw_set_transform(rc, qa, Vector2.ONE)
						draw_texture_rect(hl, Rect2(off, -1.6, 9.0, 3.2), false, hc)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Roll recharge: arc sweeps closed while the dodge is on cooldown.
			if p["roll_cd"] > 0 and p["roll_ticks"] == 0:
				var ready := 1.0 - float(p["roll_cd"]) / float(SimWorld.ROLL_CD_TICKS)
				draw_arc(pos, 11.0, -PI / 2, -PI / 2 + TAU * ready, 20,
					Color(0.7, 0.9, 1.0, 0.55), 1.5)
		else:
			# Knockdown tween: topple from the last aim into the fallen pose, colour
			# and scale settling over ~8 frames instead of snapping in one tick.
			var da: float = _down_anim[i] if i < _down_anim.size() else 1.0
			# Cubic ease-out: the fall decelerates into the dirt instead of ramping linearly.
			var de := 1.0 - pow(1.0 - da, 3.0)
			var dpose := lerp_angle(_aim_angle(p), PI / 2, de)
			var dcol := Color(1, 1, 1, 1).lerp(Color(0.35, 0.35, 0.35, 0.6), de)
			_spr(tex_name, pos, dpose, 0.52 * (1.0 + (1.0 - de) * 0.12), dcol)
			draw_arc(pos, 12.0, 0, TAU, 24, Color(0.8, 0.3, 0.25, 0.8 * da), 1.5)
			# Broke-respawn clock: a downed player with no coins to revive earns a
			# free reinforcement at broke_timer==0 (BROKE_RESPAWN_TICKS from the KO).
			# The co-op partner — and the solo player — had no idea when help lands;
			# surface the ticking countdown over the body. Reads existing sim state.
			var bt: int = p.get("broke_timer", 0)
			if bt > 0:
				var btxt := "REINFORCEMENTS IN %.1fs" % (bt / 60.0)
				var brw := Art.font().get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
				# Warms toward amber in the final second so "almost back" reads.
				var burg := clampf(1.0 - bt / 60.0, 0.0, 1.0)
				Art.text(self, btxt, pos + Vector2(-brw / 2.0, -26), 8,
					Color(0.6, 0.9, 1.0).lerp(Color(1.0, 0.8, 0.35), burg))
			# Downed beacon: when a partner is up, a rising pulse pulls their
			# eye to the body so the revive has a spatial target.
			if _two_players and not sim.last_stand:
				var partner_up := false
				for q in sim.players.size():
					if q != i and sim.players[q]["alive"]:
						partner_up = true
				if partner_up:
					var bp := float(Engine.get_physics_frames() % 45) / 45.0
					draw_arc(pos, 6.0 + bp * 20.0, 0, TAU, 24,
						Color(0.5, 0.9, 1.0, 0.8 * (1.0 - bp)), 2.0)


func _coin_trail(wx: int, wy: int, n: int) -> void:
	# Fling a few bounty coins from a kill toward the HUD War Chest icon.
	for cc in n:
		_fx.append({"x": wx, "y": wy, "t": 0.0, "kind": "coin",
			"rate": 0.028 + cc * 0.005, "ox": randf_range(-6, 6), "oy": randf_range(-6, 6)})


func _coin_pop(x: int, y: int, txt: String, trail_n: int, col: Color, rate: float) -> void:
	# Payoff floattext + a matching coin trail — the common "you got paid" beat.
	_fx.append({"x": x, "y": y, "t": 0.0, "kind": "floattext",
		"rate": rate, "text": txt, "col": col})
	_coin_trail(x, y, trail_n)


func _spawn_ambient_motes() -> void:
	# Sparse world-space drift field, tinted by sector march: cool pollen in
	# the jungle, grey ash mid-run, warm cinders at the Foundry. Background
	# atmosphere only — rate-limited so it can't crowd out combat fx, and
	# gated down (not off) under reduce-motion.
	var reduced := _motion < 0.5
	var cap := 6 if reduced else 16
	if Engine.get_physics_frames() % 3 != 0 or randf() > (0.10 if reduced else 0.35):
		return
	var live := 0
	for fx in _fx:
		if fx["kind"] == "mote":
			live += 1
			if live >= cap:
				return
	var march := _sector_march()
	var col := Color(0.66, 0.78, 0.6)   # cool green-grey pollen
	if march < 0.5:
		col = col.lerp(Color(0.58, 0.56, 0.52), march * 2.0)   # → grey ash
	else:
		# Late-run motes end WARM PALE ASH, not ember-orange (c2 4v hazard-vs-
		# litter rule): the red-orange band belongs to mines/barrels exclusively.
		col = Color(0.58, 0.56, 0.52).lerp(Color(0.82, 0.72, 0.6), (march - 0.5) * 2.0)   # → pale ash
	var wx := int(randf_range(0.0, 640.0) * Fixed.ONE)
	var wy := sim.camera_top + int(randf_range(-40.0, 400.0) * Fixed.ONE)
	_fx.append({"x": wx, "y": wy, "t": 0.0, "kind": "mote",
		"rate": randf_range(0.0025, 0.004), "dx": randf_range(-4.0, 4.0),
		"dy": randf_range(-9.0, -3.0), "col": col, "sz": randf_range(0.7, 1.3)})


func _kick_dust(i: int, wx: int, wy: int, prev: Array, big: bool) -> void:
	# Grounded-motion read: a small puff behind a moving player/tank, rate-limited
	# to a frame-modulo so a whole squad marching doesn't flood _fx.
	var pv: Vector2i = prev[i]
	var dx: int = wx - pv.x
	var dy: int = wy - pv.y
	if (dx != 0 or dy != 0) and (Engine.get_physics_frames() + i * 3) % 5 == 0:
		var mdir := Vector2(dx, dy).normalized()
		var back := mdir * (10.0 if big else 6.0) * Fixed.ONE
		_fx.append({"x": wx - int(back.x), "y": wy - int(back.y), "t": 0.0, "kind": "dust",
			"rate": 0.08, "vx": -mdir.x * (0.5 if big else 0.3), "vy": -mdir.y * (0.5 if big else 0.3),
			"col": Color(0.32, 0.28, 0.2) if big else Color(0.7, 0.65, 0.5), "sz": 1.7 if big else 1.0})
	prev[i] = Vector2i(wx, wy)


func _check_water_entry() -> void:
	# Land->water edge detection: a small one-shot droplet burst under the
	# continuous wading ripple (drawn elsewhere) so entry reads as displaced
	# water, not just a speed change.
	for i in sim.players.size():
		var p := sim.players[i]
		var wet: bool = p["alive"] and sim._in_water(p["x"], p["y"])
		if i < _water_prev.size():
			if wet and not _water_prev[i]:
				_burst(p["x"], p["y"], "splash", 5, 1.0, 2.4, 0.5, 0.1, 1.4, true)
			_water_prev[i] = wet
		# Mud edge-trigger (c2 3v): a brown kick-up on entry, and a once-per-
		# run teach banner — the text matches sim truth (water bans the roll,
		# mud does not; the speed halving is sim_world.gd's _in_mud).
		var muddy: bool = p["alive"] and not wet and sim._in_mud(p["x"], p["y"])
		if i < _mud_prev.size():
			if muddy and not _mud_prev[i]:
				_burst(p["x"], p["y"], "dust", 6, 1.2, 2.5, 0.3, 0.06, 0.0, false,
					Color(0.38, 0.28, 0.16))   # mud-brown, not generic dust (judge r1)
				if not _mud_told:
					_mud_told = true
					_show_banner("MUD — HALF SPEED, ROLLS LEGAL", Color(0.75, 0.6, 0.4))
			_mud_prev[i] = muddy
	_enemy_water_prev.resize(sim.enemies.size())
	for i in sim.enemies.size():
		var e := sim.enemies[i]
		# Frogmen own their submerge/surface ripple already; skip them here.
		var wet: bool = e["alive"] and e["kind"] != "frogman" and sim._in_water(e["x"], e["y"])
		if wet and not _enemy_water_prev[i]:
			_burst(e["x"], e["y"], "splash", 4, 0.8, 1.8, 0.5, 0.1, 1.1, true)
		_enemy_water_prev[i] = wet


func _burst(x: int, y: int, kind: String, n: int, spd_lo: float, spd_hi: float, jitter: float, rate: float = 0.06, vy_bias: float = 0.0, move: bool = false, col := Color(0, 0, 0, 0)) -> void:
	# Clean radial dust/debris ring — evenly spaced directions with a little jitter.
	# vy_bias skews the burst upward (negative Y); move opts these particles into
	# the position-integration pass below without touching other "kind" call sites.
	# col (alpha > 0) overrides the kind's default particle tint.
	if _fx.size() > 260:   # ponytail: soft cap — boss-finale kill spam can't stack unbounded draws
		return
	for d in n:
		var a := d * TAU / float(n) + randf() * jitter
		var entry := {"x": x, "y": y, "t": 0.0, "kind": kind, "rate": rate,
			"vx": cos(a) * randf_range(spd_lo, spd_hi), "vy": sin(a) * randf_range(spd_lo, spd_hi) - vy_bias}
		if move:
			entry["move"] = true
		if col.a > 0.0:
			entry["col"] = col
		_fx.append(entry)


func _draw_sector_embers() -> void:
	# Foundry-ash band (march > 0.8): sparse embers drift up-screen — the air
	# itself says you are close to the end. Hash-driven placement (no shared
	# rng), ridden on the additive ember kind, damped by reduce-motion.
	var march := _sector_march()
	if march <= 0.8:
		return
	var fr := int(Engine.get_physics_frames())
	for k in 3:
		var eh := Art.cell_hash(fr / 40 + k * 17, k)
		if eh % 3 != 0:
			continue
		var ephase := float((fr + eh) % 120) / 120.0
		var ex := float(eh % 640)
		var ey := 360.0 - ephase * 380.0 * maxf(_motion, 0.3)
		# Low-sat ash flecks, NOT ember-orange (c2 4v): drifting motes in the
		# mine/barrel hue band camouflaged real hazards in the foundry sector.
		draw_circle(Vector2(ex + sin(ephase * TAU) * 6.0, ey), 1.2,
			Color(0.85, 0.78, 0.7, (0.5 - absf(ephase - 0.5)) * 0.8))


func _draw_fx() -> void:
	# Floattext anchors drawn so far this frame: a toast only stacks (11px slot)
	# under toasts within 24px of ITS anchor. The old global per-frame index
	# displaced unrelated toasts and made them snap 11px when an earlier one expired.
	var floattext_anchors: Array[Vector2] = []
	for fx in _fx:
		if _GLOW_KINDS.has(fx["kind"]):
			continue   # drawn by _draw_glow on the additive layer
		var pos := _to_screen(fx["x"], fx["y"])
		var t: float = fx["t"]
		if fx["kind"] == "explosion":
			var frame := mini(3, int(t * 4.0))
			# Ease to zero alpha before removal — 1.0-t*0.7 left the last frame at
			# ~0.3 alpha and it blinked out instead of fading (gib already fades to 0).
			_spr(_EXPLO_NAMES[frame], pos, t * 2.0, 0.45 + t * 0.5, Color(1, 1, 1, pow(1.0 - t, 1.5)))
			if t < EXPLO_WHITE_T:
				# a1-08 WHITE-HOT lead: the blast flashes a bright near-white core for the
				# first EXPLO_WHITE_T of its life, then cools to the orange fireball — a
				# concussive flashbulb instead of blooming red-first/muddy.
				var wf := 1.0 - t / EXPLO_WHITE_T
				draw_circle(pos, EXPLO_WHITE_R_OUT + t * 46.0, Color(1.0, 0.98, 0.9, 0.88 * wf))
				draw_circle(pos, EXPLO_WHITE_R_IN + t * 22.0, Color(1.0, 1.0, 0.98, 0.9 * wf))
		elif fx["kind"] == "debris":
			# Flung rock/wood shard: arcs out on vx/vy, tumbling, then rests.
			var dcol: Color = fx.get("col", Color(0.4, 0.38, 0.34))
			var dsz: float = fx.get("sz", 2.0)
			draw_set_transform(pos, fx["spin"] + t * 9.0, Vector2.ONE)
			draw_rect(Rect2(-dsz, -dsz * 0.55, dsz * 2.0, dsz * 1.1),
				Color(dcol.r, dcol.g, dcol.b, 1.0 - t * 0.5))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "alert":
			# Expanding "spotted!" ring (observer arrival).
			var ar1 := 6.0 + t * 42.0
			var ar2 := 3.0 + t * 26.0
			draw_texture_rect(Art.tex("fx_ring"), Rect2(pos - Vector2.ONE * ar1, Vector2.ONE * ar1 * 2.0),
				false, Color(1.0, 0.25, 0.2, 0.8 - t * 0.7))
			draw_texture_rect(Art.tex("fx_ring"), Rect2(pos - Vector2.ONE * ar2, Vector2.ONE * ar2 * 2.0),
				false, Color(1.0, 0.6, 0.2, 0.7 - t * 0.6))
		elif fx["kind"] == "casing":
			draw_set_transform(pos, fx["spin"] + t * 6.0, Vector2.ONE)
			var ccol: Color = fx.get("col", Color(1, 1, 1))   # a1-11: victory casings pass GOLD
			draw_texture_rect(Art.tex("fx_shell"), Rect2(-3.0, -1.5, 6.0, 3.0), false, Color(ccol.r, ccol.g, ccol.b, 1.0 - t))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "chopper":
			# Cinematic flyover (victory extraction / endless-boss escort): sweeps
			# screen-space left->right over its lifetime with a gentle bob + rotor
			# blur. Screen-anchored (ignores world pos); nose-right at PI/2.
			var cx := lerpf(-70.0, SCREEN_W + 70.0, t)
			var cpos := Vector2(cx, fx.get("sy", 70.0) + sin(t * PI) * -6.0)
			_spr(fx.get("tex", "m_heli_transport"), cpos, PI / 2, fx.get("scl", 0.6))
			var rr := float(Engine.get_physics_frames()) * 0.9
			for ri in 2:
				var ra := rr + ri * PI / 2
				draw_line(cpos - Vector2.from_angle(ra) * 15.0, cpos + Vector2.from_angle(ra) * 15.0,
					Color(0.85, 0.85, 0.85, 0.35), 1.5)
		elif fx["kind"] == "fragpop":
			# Mini frag icons flung outward on a grenade multi-kill — extra pop
			# under the "FRAG xN" text. Rides the fx move/aging like a casing.
			var fs := 6.0 * (1.0 - t * 0.4)
			draw_set_transform(pos, fx.get("spin", 0.0) + t * 5.0, Vector2.ONE)
			draw_texture_rect(Art.tex("wep_grenade"), Rect2(-fs, -fs, fs * 2.0, fs * 2.0), false,
				Color(1, 1, 1, 1.0 - t))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "floattext":
			# Stack same-tick texts (e.g. streak + bounty on one kill) so they
			# don't overprint into a smear, and outline each so it reads over
			# bright terrain, not just the 1px shadow used to give.
			var fc: Color = fx["col"]
			fc.a = 1.0 - t * t
			var fsz: int = fx.get("size", 9)   # headline callouts (power-ups) bump this
			var ffont := Art.font()
			var fw := ffont.get_string_size(fx["text"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
			# Ease-out rise (fast at spawn, settling at the top) + a ~3-frame scale
			# punch pivoted on the text center — pops in, then glides.
			var rise := 1.0 - (1.0 - t) * (1.0 - t)
			# A "drop" floater (e.g. LOADOUT LOST) sinks instead of rising — a felt
			# down-beat. Default is the rise every other callout uses.
			var fydir: float = 1.0 if fx.get("drop", false) else -1.0
			var fstack := 0
			for fa in floattext_anchors:
				if fa.distance_to(pos) < 24.0:
					fstack += 1
			floattext_anchors.append(pos)
			var fpivot := pos + Vector2(0.0, fydir * (18.0 + rise * 22.0) - float(fstack) * 11.0)
			var fpunch := 1.0 + maxf(0.0, 0.5 - t * 4.0)
			var oc := Color(0, 0, 0, fc.a * 0.85)
			draw_set_transform(fpivot, 0.0, Vector2.ONE * fpunch)
			var frel := Vector2(-fw / 2.0, 0.0)
			for od in _TEXT_OUTLINE_OFFSETS:
				draw_string(ffont, frel + od, fx["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, oc)
			draw_string(ffont, frel, fx["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, fc)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "smoke":
			# smoothstep ramp-in: puffs swell into view instead of stamping at full alpha.
			# Hash-seeded horizontal sway (grows with rise) so stacked plumes lean and
			# separate instead of sliding up in a rigid column.
			var sway := sin(t * PI * 1.5 + float(fx["x"] % 6283) * 0.001) * 4.0 * t
			_spr("fx_smoke", pos + Vector2(sway, -t * 10.0), t, 0.3 + t * 0.25,
				Color(1, 1, 1, (0.6 - t * 0.55) * smoothstep(0.0, 0.15, t)))
		elif fx["kind"] == "gib":
			var gc: Color = fx.get("col", Color(0.5, 0.1, 0.08))
			draw_circle(pos, 1.6 * (1.0 - t * 0.6), Color(gc.r, gc.g, gc.b, 1.0 - t))
		elif fx["kind"] == "dust":
			var dust_col: Color = fx.get("col", Color(0.7, 0.65, 0.5))
			var dust_sz: float = fx.get("sz", 1.0)
			var dr: float = (2.4 + t * 5.5) * dust_sz
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * dr, Vector2.ONE * dr * 2.0),
				false, Color(dust_col.r, dust_col.g, dust_col.b, 0.4 * (1.0 - t) * smoothstep(0.0, 0.15, t)))
		elif fx["kind"] == "splash":
			var spr := 2.5 + t * 7.0
			draw_texture_rect(Art.tex("fx_ring"), Rect2(pos - Vector2.ONE * spr, Vector2.ONE * spr * 2.0),
				false, Color(0.7, 0.9, 1.0, 0.6 * (1.0 - t)))
			# A rising bubble mote over the ring — the water reacts up, not just out.
			_spr("fx_bubble1" if (fx["x"] / 4099) % 2 == 0 else "fx_bubble2",
				pos + Vector2(float((fx["x"] / 4099) % 7) - 3.0, -2.0 - t * 9.0), 0.0,
				0.07 + t * 0.04, Color(1, 1, 1, 0.6 * (1.0 - t)))
		elif fx["kind"] == "mote":
			# Ambient drift: position offset is computed from age (t) rather than
			# stepped/decayed each frame, so it stays slow and steady for its
			# whole (long) life instead of the burst-style vx/vy decay other
			# kinds use.
			var mpos := pos + Vector2(fx["dx"], fx["dy"]) * t
			var menv := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.7, 1.0, t))
			var mcol: Color = fx["col"]
			draw_circle(mpos, fx["sz"], Color(mcol.r, mcol.g, mcol.b, 0.35 * menv))
		elif fx["kind"] == "coin":
			# Bounty coin arcs from the kill up to the HUD War Chest icon, landing
			# just as the counter pulses — the kill funded the chest, made visible.
			var start := _to_screen(fx["x"], fx["y"]) + Vector2(fx.get("ox", 0.0), fx.get("oy", 0.0))
			var ease := t * t * (3.0 - 2.0 * t)
			var cp := start.lerp(Vector2(16.0, 13.0), ease)
			cp.y -= sin(t * PI) * 16.0
			var csz := 8.0 - t * 3.0
			# Flip the coin as it arcs to the War Chest (horizontal squash oscillation)
			# — the classic tumbling-gold read instead of a disc sliding up the screen.
			var flip := 0.15 + 0.85 * absf(cos(t * TAU * 2.5))
			draw_set_transform(cp, 0.0, Vector2(flip, 1.0))
			draw_texture_rect(Art.tex("icon_coin"), Rect2(-Vector2(csz, csz) / 2.0, Vector2(csz, csz)),
				false, Color(1.0, 0.92, 0.45, 1.0 - t * t))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "tex":
			# Generic textured particle (legacy art Particle_FX): grows + fades over its
			# lifetime t; optional spin. Drives the beefier muzzle/blast/impact FX.
			var tx: Texture2D = Art.tex(fx["tex"])
			var gsz: float = float(fx["sz"]) * (1.0 + t * float(fx.get("grow", 0.0)))
			var tcol: Color = fx.get("col", Color.WHITE)
			var ta: float = tcol.a * pow(1.0 - t, float(fx.get("fade", 1.0)))
			var tsc: float = gsz / maxf(1.0, tx.get_size().x)
			draw_set_transform(pos, float(fx.get("rot", 0.0)) + t * float(fx.get("spin", 0.0)), Vector2(tsc, tsc))
			draw_texture(tx, -tx.get_size() / 2.0, Color(tcol.r, tcol.g, tcol.b, ta))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow() -> void:
	# Additive pass (runs as _glow_root's draw): light-emitting FX brighten the
	# ground instead of tinting/darkening it, which mix-blend always did. Same _fx
	# entries as _draw_fx; _glow_root is a child of main so shake/zoom carry over.
	var g := _glow_root
	# Vehicle fires: a flickering flame card over burning tanks and fresh wrecks —
	# additive, so the fire lights the field. Stateless (frame-clock flicker).
	var flick := 0.82 + 0.18 * sin(float(Engine.get_physics_frames()) * 0.55)
	# Hulk smolder (6v panel: the pulsing rect frame read as a debug gizmo):
	# live cover now smolders DIEGETICALLY — a warm additive bed + hash-
	# flickering embers along the hull, all fading out over the last 3s so
	# the cover expiry stays a truthful telegraph, just an in-world one.
	for hk in sim.tanks:
		if hk["alive"] or hk["burn_ticks"] <= 0:
			continue
		var hpos := _to_screen(hk["x"], hk["y"])
		if hpos.y < -20.0 or hpos.y > 380.0:
			continue
		var hfade := minf(1.0, float(hk["burn_ticks"]) / 180.0)
		var hfl := 0.8 + 0.2 * sin(float(Engine.get_physics_frames()) * 0.31 + hpos.x)
		var hsz := 22.0
		g.draw_texture_rect(Art.tex("fx_softspot"), Rect2(hpos - Vector2.ONE * hsz, Vector2.ONE * hsz * 2.0),
			false, Color(1.0, 0.45, 0.15, 0.20 * hfade * hfl))
		for em in 4:
			var eh := Art.cell_hash(int(hpos.x) + em * 11, int(hk["burn_ticks"] / 40) + em)
			var epos := hpos + Vector2(-12.0 + float(eh % 25), -8.0 + float((eh / 25) % 17))
			g.draw_circle(epos, 1.1, Color(1.0, 0.6 + float(eh % 3) * 0.1, 0.2, (0.5 + float(eh % 4) * 0.1) * hfade))

	for t in sim.tanks:
		if t["alive"] and t["burning"]:
			_draw_flame(g, _to_screen(t["x"], t["y"]), 1.0, flick)
	for h in _hulks:
		var hstr: float = 1.0 - h["t"]
		if hstr > 0.05:
			var hpos := _to_screen(h["x"], h["y"])
			# Same off-screen cull as _draw_scorch's hulk pass — an off-screen
			# wreck smolders for ~8s of invisible flame cards otherwise.
			if hpos.y < -60.0 or hpos.y > 420.0:
				continue
			_draw_flame(g, hpos, hstr, flick)
	for fx in _fx:
		if not _GLOW_KINDS.has(fx["kind"]):
			continue
		var pos := _to_screen(fx["x"], fx["y"])
		var t: float = fx["t"]
		if fx["kind"] == "muzzle":
			# Alphas trimmed ~0.8x vs the old mix-blend draws: a single additive glow
			# stays tasteful, MG-spam stacks still sum white-hot without washing out.
			var sz := (14.0 if fx.get("big", false) else 10.0) * float(fx.get("szj", 1.0)) * (1.0 - t * 0.6)
			var mbase: Color = fx.get("col", Color(1.0, 0.95, 0.55))   # a1-09: enemy muzzles pass RED — see WHO fired
			# a3-06 (AD#7/LEG#7): trim the additive fan/core so MG-spam stacks sum LOWER
			# and explosions keep the bright-point hierarchy (was 0.8, out-blooming blasts).
			var mc := Color(mbase.r, mbase.g, mbase.b, MUZZLE_HEAT["fan_a"] * (0.95 - t * 0.85))
			# Baked semicircle fan (flat edge at image bottom): rotate image-up onto
			# the aim angle so the flat edge sits on the muzzle, fan blooming forward.
			# Same lifetime/fade, still on the additive glow layer; hot core stays.
			var fl := sz * 1.6
			g.draw_set_transform(pos, fx["a"] + PI / 2, Vector2.ONE)
			g.draw_texture_rect(Art.tex("fx_muzzle_fan"), Rect2(-fl * 0.7, -fl, fl * 1.4, fl), false, mc)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var mcore := mbase.lerp(Color(1.0, 1.0, 0.9), 0.6)
			g.draw_circle(pos, sz * 0.32, Color(mcore.r, mcore.g, mcore.b, MUZZLE_HEAT["core_a"] * (0.9 - t * 0.8)))
			# First-frame-only: an oversize pop + 3 radiating slivers — the crack of the
			# shot, gone before the next frame (4v: fan read soft). a3-06: the pop was
			# pure-white (lerp 0.55 @ 0.9a) — the SAME white-hot read as an explosion core,
			# so gunfire competed with blasts for the eye. Warm it OFF white-hot (lerp 0.32)
			# and lower the alpha so the muzzle flare stays warm and explosions own white.
			if t < fx.get("rate", 0.09):
				var mpop := mbase.lerp(Color.WHITE, MUZZLE_HEAT["pop_lerp"])
				if fx.get("pop", false):
					# sol-15/16: the PLAYER shot's crack-pop is the authored card, drawn OVER the fan
					# (which stays the directional primary). Additive, warmed off white-hot + alpha-capped
					# so it never out-blooms an explosion, spun per-shot (view-hashed off pos, no sim RNG)
					# so MG-spam isn't a repeated decal; its transparent core lets the hot core show through.
					# Enemy small-arms have no "pop" flag → the procedural pop — no muzzleflash on the red faction.
					var mspin: float = fx["a"] + float((int(pos.x) * 7 + int(pos.y) * 13) & 255) / 255.0 * TAU
					var mpr := sz * 1.25
					g.draw_set_transform(pos, mspin, Vector2.ONE)
					g.draw_texture_rect(Art.tex("mz_pop"), Rect2(-mpr, -mpr, mpr * 2.0, mpr * 2.0),
						false, Color(mpop.r, mpop.g, mpop.b, MUZZLE_HEAT["pop_a"]))
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					g.draw_circle(pos, sz * 0.9, Color(mpop.r, mpop.g, mpop.b, MUZZLE_HEAT["pop_a"]))
				for ml in 3:
					var mla: float = fx["a"] + (float(ml) - 1.0) * 0.42
					g.draw_line(pos + Vector2.from_angle(mla) * sz * 0.4,
						pos + Vector2.from_angle(mla) * sz * (1.7 + float(ml % 2) * 0.5),
						Color(1, 1, 1, 0.75), 1.2)
		elif fx["kind"] == "spark":
			# Ricochet: legacy art sparkle cards flung radially — armor says no.
			var sc := Color(1.0, 0.9, 0.5, 0.9 - t * 0.9)
			var stex := Art.tex("fx_sparkle")
			var ssz := 5.0 + t * 5.0
			# Hash-seeded base angle + 3-5 count so each ricochet scatters its own
			# way — the fixed k*TAU/3 triad read as one spinning triangle.
			var sbase := float(fx["x"] % 6283) * 0.001
			var scount := 3 + absi(fx["x"]) % 3
			for k in scount:
				var sa := sbase + k * TAU / float(scount) + t * 2.0
				var sp2: Vector2 = pos + Vector2.from_angle(sa) * (3.0 + t * 7.0)
				g.draw_texture_rect(stex, Rect2(sp2 - Vector2.ONE * ssz, Vector2.ONE * ssz * 2.0), false, sc)
		elif fx["kind"] == "shockwave":
			# Concussive ring: a legacy art ring texture with baked inner/outer falloff
			# snaps out — reads as a pressure wave, not a flat UI stroke.
			var swr: float = fx.get("sz", 4.0) + t * fx.get("grow_px", 34.0)
			var swc: Color = fx.get("col", Color(1.0, 0.95, 0.8, 0.7))
			g.draw_texture_rect(Art.tex("fx_ring"), Rect2(pos - Vector2.ONE * swr, Vector2.ONE * swr * 2.0),
				false, Color(swc.r, swc.g, swc.b, swc.a * (1.0 - t)))
		elif fx["kind"] == "light":
			# The gun/blast throws light onto the world — a soft radial card
			# (fx_softspot) instead of two hand-nested flat discs. One draw
			# upgrades muzzle glow, enemy/sniper fire, vest_break, revive, surge.
			var lc: Color = fx["col"]
			var la := (1.0 - t) * 0.45
			var lr: float = fx["r"] * (0.7 + t * 0.4)
			g.draw_texture_rect(Art.tex("fx_softspot"), Rect2(pos - Vector2.ONE * lr, Vector2.ONE * lr * 2.0),
				false, Color(lc.r, lc.g, lc.b, la))
		elif fx["kind"] == "ember":
			# Hot spark: white-hot core over a soft glow, cooling yellow->orange and
			# dimming fast as it flies — now genuinely additive.
			var ea := 1.0 - t
			var ec := Color(1.0, 0.85 - t * 0.4, 0.35 - t * 0.3)
			g.draw_circle(pos, 2.0 * (1.0 - t * 0.5), Color(ec.r, ec.g, ec.b, ea * 0.5))
			g.draw_circle(pos, 0.9, Color(1.0, 0.95, 0.75, ea))
		elif fx["kind"] == "flash":
			# Delayed secondary core: negative t holds it dark for ~2 frames after the
			# main blast, then it pops bright and fades — a two-stage punch.
			if t < 0.0:
				continue
			var la2 := 1.0 - t
			g.draw_circle(pos, 12.0 * (1.0 - t) + 3.0, Color(1.0, 0.95, 0.8, 0.68 * la2 * la2))
			g.draw_circle(pos, 4.5, Color(1.0, 1.0, 0.95, 0.8 * la2))


func _draw_flame(g: CanvasItem, fp: Vector2, strength: float, flick: float) -> void:
	# One baked flame card, flicker on scale + alpha (drawn on the additive layer).
	var ftex := Art.tex("fx_flame")
	var fs := (30.0 + 8.0 * flick) * (0.6 + 0.4 * strength) / float(ftex.get_size().x)
	g.draw_set_transform(fp + Vector2(0, -10.0), 0.0, Vector2(fs, fs))
	g.draw_texture(ftex, -ftex.get_size() / 2.0,
		Color(1.0, 0.6, 0.25, (0.4 + 0.35 * flick) * strength))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _scorch_cap(mode: String) -> int:
	# a2-13: campaign keeps more persistent scars (40) than the churning endless arena (24).
	return 24 if mode == "endless" else 40


static func _scorch_age(tt: float) -> float:
	# a2-13: campaign scorch ages SLOW toward a capped GHOST (0.82) — it never reaches
	# 1.0, so it is never removed by age; it settles into a faint permanent scar.
	return minf(tt + 0.003, 0.82)


func _draw_scorch() -> void:
	# Lingering ground scorch under everything — battlefield keeps its scars.
	for s in _scorch:
		var pos := _to_screen(s["x"], s["y"])
		var a: float = 0.4 * (1.0 - s["t"])
		# Cracked-earth decal (legacy art fx_groundbreak) under the scorch blobs,
		# rotated per-decal off its world x so no two craters look identical.
		var gr: float = s["r"] * 1.7
		draw_set_transform(pos, float(int(s["x"]) % 360) * 0.01745, Vector2.ONE)
		draw_texture_rect(Art.tex("fx_groundbreak"), Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(0.16, 0.13, 0.1, a * 1.15))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(pos, s["r"], Color(0.12, 0.1, 0.08, a))
		draw_circle(pos, s["r"] * 0.6, Color(0.05, 0.04, 0.03, a))
		if s.get("crack", false):
			# Radial fracture lines, stable per-decal via the stored seed.
			var sd: int = s.get("seed", 0)
			var ca: float = 0.55 * (1.0 - s["t"])
			for k in 5:
				var ka := k * TAU / 5.0 + float(sd % 13) * 0.24
				var cl: float = s["r"] * (0.7 + float((sd >> (k * 2)) & 3) * 0.12)
				draw_line(pos, pos + Vector2.from_angle(ka) * cl, Color(0.03, 0.02, 0.02, ca), 1.0)
	# Dead-tank hulks: a persistent burned-out wreck where a tank died — scorch
	# decal under the hulk sprite, plus a drifting smolder fume while fresh.
	for h in _hulks:
		var hp := _to_screen(h["x"], h["y"])
		# Screen cull (same idiom as the parked-tank cull): the ratchet camera
		# leaves every wreck behind, where it kept paying ~7 draw ops per frame
		# until the cap evicted it.
		if hp.y < -60.0 or hp.y > 420.0:
			continue
		var hrot: float = h["rot"]
		draw_set_transform(hp, hrot, Vector2.ONE)
		draw_texture_rect(Art.tex("fx_groundbreak"), Rect2(-26, -26, 52, 52), false,
			Color(0.14, 0.11, 0.09, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(hp, 15.0, Color(0.08, 0.07, 0.06, 0.4))
		_spr("tank_hulk", hp, hrot, 0.62)
		var smf: float = 1.0 - h["t"]
		if smf > 0.05:
			# Looping smolder puff (stateless: phase off the frame clock + rot seed).
			var ph := fposmod(float(Engine.get_physics_frames()) * 0.012 + hrot, 1.0)
			_spr("fx_fumes", hp + Vector2(3.0, -8.0 - ph * 16.0), 0.0, 0.045 + ph * 0.03,
				Color(0.24, 0.22, 0.2, 0.5 * smf * (1.0 - ph)))
	# Fallen bodies: the enemy sprite, darkened and sprawled, fading over ~4s.
	for c in _corpses:
		var cp := _to_screen(c["x"], c["y"])
		var ct: float = c["t"]
		var fade := 1.0 - ct
		# A dark blood pool spreads under it early, then everything fades. Uses the
		# owned Apocalypse-HUD blood-splat card (organic edge) instead of a flat disc.
		# (skipped for water kills — a puddle in a river reads wrong)
		if not c.get("wet", false):
			var bpr := (3.0 + minf(ct, 0.2) * 20.0) * 2.1   # splat radius ≈ the old disc footprint
			draw_texture_rect(Art.tex("hudfx_blood"),
				Rect2(cp + Vector2(0, 2) - Vector2.ONE * bpr, Vector2.ONE * bpr * 2.0),
				false, Color(0.34, 0.04, 0.04, 0.45 * fade))
		# Death squash-pop: a quick scale bump on impact that settles into a
		# flattened corpse (via _spr's stretch param).
		var pop := 1.0 + maxf(0.0, 0.35 - ct * 3.0)
		var squash := 1.0 - minf(ct * 2.5, 1.0) * 0.2
		_spr(c["kind"], cp, c["spin"], 0.5 * pop, Color(0.45, 0.42, 0.4, 0.85 * fade), squash)


func _draw_telegraphs() -> void:
	# Truthful mortar telegraph: the outer ring IS the kill radius, the disc
	# filling toward it is the timer, and the last fifth strobes white.
	for s in sim.strikes:
		var sp := _to_screen(s["x"], s["y"])
		var frac: float = 1.0 - float(s["ticks"]) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
		var r := SimWorld.GRENADE_RADIUS * PX
		# a3-07 (VFX#1/LEG#1): a soft DARK underlay seats the lethal footprint on busy or
		# bright ground — the amber ring + amber timer disc were amber-on-amber with nothing
		# grounding them (they washed out on the foundry floor, over water, in tracer clutter).
		# Drawn FIRST, under the whole kill radius, so the incoming-strike zone reads on any terrain.
		var uw := r * STRIKE_UNDERLAY["scale"]
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(sp - Vector2(uw, uw) / 2.0, Vector2(uw, uw)),
			false, Color(0.0, 0.0, 0.0, STRIKE_UNDERLAY["alpha"]))
		var col := Color(1.0, 0.9 - frac * 0.6, 0.2, 0.9)
		if s["ticks"] <= 10 and (s["ticks"] / 3) % 2 == 0:
			col = Color(1.0, 1.0, 1.0, 0.95)
		draw_arc(sp, r, 0, TAU, 32, col, 1.5)
		draw_circle(sp, r * frac, Color(col.r, col.g, col.b, 0.20))
		draw_arc(sp, r * frac, 0, TAU, 28, col, 2.0)
		draw_line(sp + Vector2(-5, 0), sp + Vector2(5, 0), col, 1.5)
		draw_line(sp + Vector2(0, -5), sp + Vector2(0, 5), col, 1.5)


func _draw_bar(rect: Rect2, frac: float, fill := Color(0.85, 0.25, 0.18),
		ghost := -1.0, ticks := 0) -> void:
	## Sprite-framed progress bar: dark well, draining ghost chip, colored
	## fill, phase-threshold ticks, metal frame on top.
	var inset := Vector2(rect.size.x * 0.06, rect.size.y * 0.22)
	var well := Rect2(rect.position + inset, rect.size - inset * 2.0)
	draw_rect(well, Color(0.08, 0.07, 0.06, 0.9))
	var fw := well.size.x
	frac = clampf(frac, 0.0, 1.0)
	# Ghost chip: the recently-lost HP lingers as a pale chunk, then catches up.
	if ghost > frac:
		draw_rect(Rect2(well.position + Vector2(fw * frac, 0),
			Vector2(fw * (ghost - frac), well.size.y)), Color(1.0, 0.9, 0.6, 0.5))
	draw_rect(Rect2(well.position, Vector2(fw * frac, well.size.y)), fill)
	# Phase ticks: thirds/halves so the fight's structure is legible.
	for k in range(1, ticks):
		var tx := well.position.x + fw * float(k) / float(ticks)
		draw_line(Vector2(tx, well.position.y), Vector2(tx, well.position.y + well.size.y),
			Color(0.05, 0.04, 0.03, 0.8), 1.0)
	draw_texture_rect(Art.tex("ui_bar_frame"), rect, false)


func _bar_ghost(key: String, frac: float) -> float:
	# View-side prev-HP tracker feeding the draining chip; eases toward frac.
	var g: float = _boss_ghost.get(key, frac)
	if frac < g:
		g = maxf(frac, g - 0.02)
	else:
		g = frac
	_boss_ghost[key] = g
	return g


func _draw_progress_rail() -> void:
	# Right-edge vertical rail: the shape of the campaign run — gates (locked
	# red / open green), the Foundry finale up top, and a 'you' dot. Answers
	# 'how far is the next checkpoint' that SECTOR n/5 only says in the abstract.
	if sim.mode != "campaign":
		return
	var rx := 632.0
	var top := 30.0
	var bot := 330.0
	draw_line(Vector2(rx, top), Vector2(rx, bot), Color(0.2, 0.22, 0.18, 0.7), 2.0)
	# Map world-y over the run span to the rail. Gates stream at -1000/unit.
	var span := SimWorld.GATE_SPACING * SimWorld.FINAL_GATE_INDEX
	var to_rail := func(wy: int) -> float:
		return bot - clampf(float(-wy) / float(span), 0.0, 1.0) * (bot - top)
	for g in sim.gates:
		var yy: float = to_rail.call(g["y"])
		var gc := Art.safe(Color(0.4, 0.9, 0.4)) if g["open"] else Color(0.95, 0.3, 0.2)
		if g.get("final", false):
			gc = Color(1.0, 0.6, 0.2)
		draw_circle(Vector2(rx, yy), 3.5, gc)
	# Finale marker at the top even before it streams in.
	draw_rect(Rect2(rx - 3, top - 3, 6, 6), Color(1.0, 0.6, 0.2))
	# You-are-here.
	var you: float = to_rail.call(sim.camera_top + int(SimWorld.VIEW_H / 2))
	draw_circle(Vector2(rx, you), 2.5, Color(1, 1, 1))
	draw_arc(Vector2(rx, you), 4.5, 0, TAU, 12, Color(1, 1, 1, 0.7), 1.0)


func _draw_threat_edges() -> void:
	# One pass over sim.enemies classifies both edges (this used to be two full
	# scans, each allocating a dict per qualifying enemy every frame).
	# Bottom edge: live hostiles below the viewport — bypassed bunkers keep
	# spawning behind you. Top edge: hostiles about to enter from the spawn
	# edge above, otherwise only met as they cross into view.
	var bottom_threats: Array = []
	var top_threats: Array = []
	for e in sim.enemies:
		if not e["alive"] or e.get("submerged", false):
			continue
		var sy: float = (e["y"] - sim.camera_top) * PX
		if sy <= 364.0 and (sy >= 0.0 or sy < -180.0):
			continue
		var danger: bool = e["kind"] == "sniper" or e["kind"] == "grenadier" \
			or e["kind"] == "ghillie" or e["kind"] == "drone"
		if sy > 364.0:
			bottom_threats.append({"e": e, "off": sy, "danger": danger})
		else:
			top_threats.append({"e": e, "off": sy, "danger": danger})
	# A dense endless wave can stack a dozen+ off-screen hostiles on one edge,
	# painting a near-solid chevron row that drowns the lethality signal —
	# cap to the nearest few; ties prefer the lethal ranged killers.
	_draw_edge_chevrons(bottom_threats, false)
	_draw_edge_chevrons(top_threats, true)
	# Off-screen boss/spotter locator: a nearer closed gate can hold the camera
	# while an already-streamed boss (or the observer) sits above the visible
	# view — its HP bar/label live in the fixed HUD but the arena-lock
	# "destroy it" text points at nothing on screen. One double-chevron at the
	# nearest such target, so "look up" is unambiguous.
	var near_sy := -100000.0
	var near_x := 0.0
	var near_found := false
	for g in sim.gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		var gsy: float = (g["boss"]["gate_y"] - SimWorld.BOSS_Y_OFFSET - sim.camera_top) * PX
		if gsy < 0.0 and gsy > near_sy:
			near_sy = gsy
			near_x = clampf(g["boss"]["x"] * PX, 8.0, 632.0)
			near_found = true
	if not sim.endless_boss.is_empty() and sim.endless_boss["alive"]:
		var esy: float = (sim.endless_boss["gate_y"] - SimWorld.BOSS_Y_OFFSET - sim.camera_top) * PX
		if esy < 0.0 and esy > near_sy:
			near_sy = esy
			near_x = clampf(sim.endless_boss["x"] * PX, 8.0, 632.0)
			near_found = true
	if not sim.observer.is_empty():
		var osy: float = SimWorld.OBSERVER_Y_OFFSET * PX
		if osy < 0.0 and osy > near_sy:
			near_sy = osy
			near_x = clampf(sim.observer["x"] * PX, 8.0, 632.0)
			near_found = true
	if near_found:
		var bp := 1.0 if _motion < 0.5 else Art.pulse(0.25)   # steady under reduce-motion
		var bcol := Color(1.0, 0.3, 0.2, 0.55 + bp * 0.35)
		draw_line(Vector2(near_x - 6, 14), Vector2(near_x, 5), bcol, 2.5)
		draw_line(Vector2(near_x, 5), Vector2(near_x + 6, 14), bcol, 2.5)
		draw_line(Vector2(near_x - 6, 22), Vector2(near_x, 13), bcol, 2.5)
		draw_line(Vector2(near_x, 13), Vector2(near_x + 6, 22), bcol, 2.5)
	# Off-screen downed-partner revive locator: the revive beacon + dashed
	# tether in _draw_players only render at the body's on-screen world pos,
	# so a KO'd partner scrolled past the held camera's edge is invisible and
	# the revive has no spatial target. One labeled chevron at the edge
	# nearest the body, same idiom as the boss/spotter locator above.
	if _two_players and not sim.last_stand:
		for i in sim.players.size():
			var dp2 := sim.players[i]
			if dp2["alive"]:
				continue
			var partner_up2 := false
			for q in sim.players.size():
				if q != i and sim.players[q]["alive"]:
					partner_up2 = true
			if not partner_up2 or sim.war_chest < sim.revive_cost(dp2):
				continue
			var rsy: float = (dp2["y"] - sim.camera_top) * PX
			if rsy >= 0.0 and rsy <= 360.0:
				continue   # on screen already — the body beacon covers it
			var rx := clampf(dp2["x"] * PX, 8.0, 632.0)
			var rp := 1.0 if _motion < 0.5 else Art.pulse(0.3)   # steady under reduce-motion
			var rcol := Art.safe(Color(0.5, 0.9, 1.0, 0.6 + rp * 0.3))
			# Label clamps by its own width (rx pins to 8/632 at the corners, and
			# rx-18 used to start the text off-screen there).
			var rlx := clampf(rx - 18.0, 4.0, 596.0)
			if rsy > 360.0:
				draw_line(Vector2(rx - 6, 336), Vector2(rx, 345), rcol, 2.5)
				draw_line(Vector2(rx, 345), Vector2(rx + 6, 336), rcol, 2.5)
				Art.text(self, "REVIVE", Vector2(rlx, 332), 9, rcol)
			else:
				draw_line(Vector2(rx - 6, 40), Vector2(rx, 31), rcol, 2.5)
				draw_line(Vector2(rx, 31), Vector2(rx + 6, 40), rcol, 2.5)
				# Slot bump: the top-center strip owns y46 when a banner/directive
				# is live — drop the label a slot so the two never overprint.
				var rly := 62.0 if _top_center_priority() != "" and absf(rx - 320.0) < 90.0 else 50.0
				Art.text(self, "REVIVE", Vector2(rlx, rly), 9, rcol)


static func _cmp_threat_top(a: Dictionary, b: Dictionary) -> bool:
	# Nearest-first (least negative off), ties prefer the lethal ranged killers.
	if a["off"] != b["off"]:
		return a["off"] > b["off"]
	return a["danger"] and not b["danger"]


static func _cmp_threat_bottom(a: Dictionary, b: Dictionary) -> bool:
	if a["off"] != b["off"]:
		return a["off"] < b["off"]
	return a["danger"] and not b["danger"]


func _draw_edge_chevrons(threats: Array, is_top: bool) -> void:
	## Shared sort->cap->draw pass for the top/bottom off-screen threat
	## chevrons: ties prefer the lethal ranged killers, capped to the
	## nearest 6 so a dense swarm can't paint a solid warning row.
	threats.sort_custom(_cmp_threat_top if is_top else _cmp_threat_bottom)
	var _panel_bot := _hud_icons.panel_bottom()   # single source (incl. 2P strip-drop rule)
	for i in mini(6, threats.size()):
		var e: Dictionary = threats[i]["e"]
		var off: float = threats[i]["off"]
		var danger: bool = threats[i]["danger"]
		if is_top:
			var tx: float = clampf(e["x"] * PX, 8.0, 632.0)
			# Under the corner HUD panel's real footprint (x<262), drop the chevron
			# below the panel's bottom edge instead of skipping it outright — still
			# a warning, just relocated clear of the opaque HUD art.
			var tbase := 28.0
			if tx < _hud_icons.plate_right():
				tbase = _panel_bot + 12.0
			var ta := clampf(1.0 + off / 180.0, 0.2, 0.7)
			if e.get("windup", 0) > 0:
				# Steady full boost under reduce-motion — the windup must still read.
				ta = clampf(ta + (0.3 if _motion < 0.5 else Art.pulse(0.28) * 0.3), 0.2, 1.0)
			var tcol := Color(1.0, 0.1, 0.1, ta) if danger else Color(1.0, 0.55, 0.25, ta)
			var tspr := 6.0 if danger else 4.0   # spikier spread for ranged killers
			var ttip := tbase - (6.0 if danger else 4.0)
			var tuc := Color(0, 0, 0, ta * 0.55)   # 1px drop under-lay: reads over bright terrain
			draw_line(Vector2(tx - tspr, tbase + 1.0), Vector2(tx, ttip + 1.0), tuc, 2.0)
			draw_line(Vector2(tx, ttip + 1.0), Vector2(tx + tspr, tbase + 1.0), tuc, 2.0)
			draw_line(Vector2(tx - tspr, tbase), Vector2(tx, ttip), tcol, 2.0)
			draw_line(Vector2(tx, ttip), Vector2(tx + tspr, tbase), tcol, 2.0)
			if colorblind and danger:
				# Colorblind: red-vs-orange hue alone can't carry "lethal ranged". Add
				# a second nested caret so SHAPE (a doubled chevron) encodes danger too.
				draw_line(Vector2(tx - tspr, tbase + 5.0), Vector2(tx, ttip + 5.0), tcol, 2.0)
				draw_line(Vector2(tx, ttip + 5.0), Vector2(tx + tspr, tbase + 5.0), tcol, 2.0)
		else:
			var sx: float = clampf(e["x"] * PX, 8.0, 632.0)
			if sim.last_stand and sx > 165.0 and sx < 475.0:
				# keep clear of the colossus HP bar / LAST STAND readout parked
				# at bottom-center of the screen in the finale
				sx = 165.0 if sx < 320.0 else 475.0
			var a := clampf(1.2 - (off - 360.0) / 200.0, 0.25, 0.85)
			if e.get("windup", 0) > 0:
				a = clampf(a + (0.35 if _motion < 0.5 else Art.pulse(0.28) * 0.35), 0.25, 1.0)
			var col := Color(1.0, 0.1, 0.1, a) if danger else Color(1.0, 0.35, 0.2, a)
			var spr := 6.0 if danger else 4.0   # spikier spread for ranged killers
			var tip := 361.0 if danger else 358.0
			var uc := Color(0, 0, 0, a * 0.55)   # 1px drop under-lay: reads over bright terrain
			draw_line(Vector2(sx - spr, 354), Vector2(sx, tip + 1.0), uc, 2.0)
			draw_line(Vector2(sx, tip + 1.0), Vector2(sx + spr, 354), uc, 2.0)
			draw_line(Vector2(sx - spr, 353), Vector2(sx, tip), col, 2.0)
			draw_line(Vector2(sx, tip), Vector2(sx + spr, 353), col, 2.0)
			if colorblind and danger:
				# Doubled chevron: shape-redundant danger cue for colorblind mode.
				draw_line(Vector2(sx - spr, 348), Vector2(sx, tip - 5.0), col, 2.0)
				draw_line(Vector2(sx, tip - 5.0), Vector2(sx + spr, 348), col, 2.0)
	if threats.size() > 6:
		# The cap hides the tail — say so, so a drowned edge still reads as "many"
		# instead of "exactly six".
		Art.text(self, "+%d" % (threats.size() - 6),
			Vector2(606.0, 40.0 if is_top else 350.0), 8, Color(1.0, 0.5, 0.3, 0.75))


func _draw_objective_markers() -> void:
	# The battlefield self-labels "go here / kill this / grab this". On-screen
	# objectives get a small bobbing icon overhead; off-screen ones become a
	# directional diamond pinned to the nearest edge (distinct from the red
	# threat chevrons — these are objectives, not generic hostiles).
	var bob := sin(float(Engine.get_physics_frames()) * 0.12) * 2.0 * _motion   # stills under REDUCE MOTION
	# pr: 0 = mission-critical (gate/boss), 1 = kill targets, 2 = loot. Sorted
	# before the edge cap so a crate flood can never evict a gate/boss pointer.
	var marks: Array = []
	for g in sim.gates:
		if not g["open"] and not g.get("final", false):
			marks.append({"sx": 320.0, "sy": (g["y"] - sim.camera_top) * PX,
				"icon": "hud_flag", "col": Color(1.0, 0.9, 0.4), "pr": 0})
			break
	if not sim.endless_boss.is_empty() and sim.endless_boss.get("alive", false):
		marks.append({"sx": sim.endless_boss["x"] * PX,
			"sy": (sim.endless_boss.get("gate_y", sim.camera_top) - sim.camera_top) * PX,
			"icon": "hud_skull", "col": Color(1.0, 0.5, 0.35), "pr": 0})
	if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
		marks.append({"sx": sim.colossus["x"] * PX, "sy": (sim.colossus["y"] - sim.camera_top) * PX,
			"icon": "hud_skull", "col": Color(1.0, 0.45, 0.3), "pr": 0})
	for e in sim.enemies:
		if not e["alive"]:
			continue
		if e["kind"] == "courier":
			marks.append({"sx": e["x"] * PX, "sy": (e["y"] - sim.camera_top) * PX,
				"icon": "hud_vehicle", "col": Color(1.0, 0.85, 0.35), "pr": 1})
		elif e["kind"] == "pilot":
			# The rescue is an OBJECTIVE, not a threat — green mark, top priority,
			# so a pilot drifting off-screen is findable before the edge takes him.
			marks.append({"sx": e["x"] * PX, "sy": (e["y"] - sim.camera_top) * PX,
				"icon": _marker_icon("rescue"), "col": Art.safe(Color(0.45, 1.0, 0.65)), "pr": 1})   # a2-14 LEG#3
		elif e.get("marked", false):
			marks.append({"sx": e["x"] * PX, "sy": (e["y"] - sim.camera_top) * PX,
				"icon": _marker_icon("bounty"), "col": Color(1.0, 0.82, 0.3), "pr": 1})
	for pk in sim.pickups:
		if pk.get("cost", 0) > 0:
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": _marker_icon("priced"), "col": Color(0.6, 0.9, 1.0), "pr": 2})   # a2-14 LEG#4
		elif pk["kind"] >= 4:
			# Rare power-up capsule — the game makes a fuss on pickup but never
			# pointed you to it; colour-keyed to match the ground glow.
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": _marker_icon("capsule"), "pr": 2,   # a2-14 LEG#4
				"col": _CAPSULE_COL[clampi(pk["kind"] - 4, 0, _CAPSULE_COL.size() - 1)]})
		else:
			# Free crate (guaranteed gate cache) — supplies worth pathing to.
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": _marker_icon("free"), "col": Art.safe(Color(0.7, 0.85, 0.6)), "pr": 2})
	# Weight-sort BEFORE the edge cap of 6, so the cap always spends its slots on
	# the highest-priority marks. On-screen icons are uncapped (anchored).
	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pr"] < b["pr"])
	var panel_bot := _hud_icons.panel_bottom()   # single source (incl. 2P strip-drop rule)
	var placed: Array[Vector2] = []
	var edge_used := 0
	for m in marks:
		var mp := Vector2(m["sx"], m["sy"])
		var on := mp.x >= 6.0 and mp.x <= 634.0 and mp.y >= 32.0 and mp.y <= 354.0
		if on:
			# 1px dark under-copy (Art.text's shadow pattern) — a cyan/amber icon
			# washed out over bright water/sand where the outlined pips stay crisp.
			draw_texture_rect(Art.tex(m["icon"]),
				Rect2(mp + Vector2(-4.0, -19.0 + bob), Vector2(10, 10)), false, Color(0, 0, 0, 0.55))
			draw_texture_rect(Art.tex(m["icon"]),
				Rect2(mp + Vector2(-5.0, -20.0 + bob), Vector2(10, 10)), false, m["col"])
		elif edge_used < 6:
			edge_used += 1
			var ep := _marker_edge(mp)
			# Never under the corner HUD panel (it reaches ~y58 in 2P, deeper with
			# the endless shop row) — drop the marker below its bottom edge.
			if ep.x < _hud_icons.plate_right() and ep.y < panel_bot + 8.0:
				ep.y = panel_bot + 8.0
			# Min spacing on a shared edge: slide along the edge until clear so
			# stacked marks can't overprint into one unreadable diamond.
			var on_h_edge: bool = ep.y <= 40.0 or ep.y >= 340.0
			for _guard in 8:
				var crowded := false
				for q in placed:
					if ep.distance_to(q) < 14.0:
						crowded = true
						break
				if not crowded:
					break
				if on_h_edge:
					ep.x = clampf(ep.x + 15.0, 16.0, 624.0)
				else:
					ep.y = clampf(ep.y + 15.0, 36.0, 344.0)
			placed.append(ep)
			# Priority reads at a glance: objectives (gate/boss) get a bigger
			# diamond than loot pointers — no need to parse the 8px icon first.
			var pr: float = 6.5 if int(m["pr"]) == 0 else 4.5
			_marker_diamond(ep, pr, m["col"])
			draw_texture_rect(Art.tex(m["icon"]), Rect2(ep - Vector2(4, 4), Vector2(8, 8)), false, m["col"])


static func _marker_icon(cls: String) -> String:
	# a2-14: one icon per objective/loot class so rescue-vs-kill and the three loot
	# classes read apart — rescue BEACON, bounty KILL reticle, priced=coin, rare=
	# lightning power-up, free supply cache.
	match cls:
		"rescue": return "hud_star"
		"bounty": return "hud_target"
		"priced": return "icon_coin"
		"capsule": return "hud_lightning"
		_: return "hud_gunshop"


func _marker_edge(pos: Vector2) -> Vector2:
	# Project from screen center to the point, clamped to the viewport border.
	var c := Vector2(320.0, 190.0)
	var d := pos - c
	if d.length() < 1.0:
		return pos
	var s := 1.0
	if d.x > 0.01:
		s = minf(s, (624.0 - c.x) / d.x)
	elif d.x < -0.01:
		s = minf(s, (16.0 - c.x) / d.x)
	if d.y > 0.01:
		s = minf(s, (344.0 - c.y) / d.y)
	elif d.y < -0.01:
		s = minf(s, (36.0 - c.y) / d.y)
	return c + d * maxf(s, 0.0)


func _marker_diamond(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0),
		p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))
	# Dark outline, same treatment the threat pips get — keeps the diamond
	# readable over bright water/sand.
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.55), 1.0)


static func _wheel_socket_display(selected: bool, afford: bool) -> String:
	# a1-16: what a spend-wheel socket shows — the SELECTED socket shows full
	# cost+stock; an unselected AFFORDABLE socket shows a compact can-buy dot;
	# otherwise (unselected + unaffordable) neither (the × cue handles that).
	if selected:
		return "full"
	if afford:
		return "dot"
	return "none"


func _draw_wheel() -> void:
	for i in sim.players.size():
		if i >= _wheel.size() or not _wheel[i]["open"]:
			continue
		var p := sim.players[i]
		if not p["alive"]:
			continue
		var c := _to_screen(p["x"], p["y"])
		# Keep the whole wheel readable at the arena edges: hub, pick label
		# (c.y-52) and cue line (c.y+52) must all stay on-screen.
		c.x = clampf(c.x, 78.0, 562.0)
		c.y = clampf(c.y, 96.0, 296.0)
		# (No entrance-scale envelope: the old draw_set_transform pop was clobbered by
		# the first nested _spr's identity reset, so only the plate ever scaled — the
		# hub/sockets/labels popped in at full size, which read worse than no pop at
		# all. Dropped it; the wheel now appears clean, matching the reduce-motion path.)
		# Baked wheel plate behind the hub (the Apocalypse sheet is a 4x2 socket
		# atlas — one cell is the round plate) instead of a flat alpha disc.
		var plate := Art.tex("ui_wheel_plate")
		var pcell := Vector2(plate.get_size().x / 4.0, plate.get_size().y / 2.0)
		# c2 2v: plate alpha 0.92 -> 0.55 (the ~40% cut) so the mast, scars,
		# drops and hazards read THROUGH it during the buy — the sockets/icons
		# and shadowed text stay full-alpha, so clarity rides the text shadows.
		draw_texture_rect_region(plate, Rect2(c - Vector2(51, 51), Vector2(102, 102)),
			Rect2(Vector2.ZERO, pcell), Color(0.72, 0.78, 0.7, 0.55))
		# Center hub: the fuel-cap ring framing the War Chest itself — this
		# wheel drains the same pool that funds revives.
		# Scale off the imported size, not the 600px source — dial_fuel imports
		# at size_limit=64 now (it never draws bigger than 34px).
		_spr("ui_dial_fuel", c, 0.0, 34.0 / Art.tex("ui_dial_fuel").get_size().x)
		var f := Art.font()
		var chest := str(sim.war_chest)
		var cw := f.get_string_size(chest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var cx := c.x - (10.0 + cw) / 2.0
		draw_texture_rect(Art.tex("icon_coin"), Rect2(cx, c.y - 5.0, 9, 9), false)
		Art.text(self, chest, Vector2(cx + 10.0, c.y + 3.0), 8, Color(1.0, 0.95, 0.65))
		for s in 8:
			if _SECTOR_TO_ITEM[s] < 0:
				continue
			var item: Dictionary = WHEEL_ITEMS[_SECTOR_TO_ITEM[s]]
			var ang := s * TAU / 8.0
			var ipos := c + Vector2.from_angle(ang) * 31.0
			var is_token: bool = int(item["kind"]) == 5
			var acost: int = 1 if is_token else sim._supply_cost(item["kind"])   # wave-scaled in endless
			var afford: bool = (sim.tokens >= 1) if is_token else (sim.war_chest >= acost)
			var selected: bool = _wheel[i]["sel"] == s
			# Socket sprite authored nub-down (north slot); +90° per sector
			# keeps the connector nub pointing at the hub.
			var sock_mod := Color.WHITE
			if selected:
				sock_mod = Color(1.3, 1.18, 0.7) if afford else Color(1.2, 0.6, 0.55)
			# Eased 31→38 pop on the picked socket (pop advances in _update_wheel).
			var pop: float = float(_wheel[i].get("pop", 1.0)) if selected else 0.0
			_spr("ui_wheel_socket", ipos, ang + PI / 2.0,
				lerpf(31.0, 38.0, pop) / Art.tex("ui_wheel_socket").get_size().x, sock_mod)
			var icon_mod := Color.WHITE if afford else Color(0.8, 0.35, 0.35, 0.55)
			var isz := lerpf(14.0, 18.0, pop)
			draw_texture_rect(Art.tex(item["icon"]),
				Rect2(ipos - Vector2(isz, isz) / 2.0, Vector2(isz, isz)), false, icon_mod)
			if not afford:
				# Non-color "can't buy" cue beside the socket (colorblind-safe).
				Art.text(self, "×", ipos + Vector2(12.0, -8.0), 9, Color(1.0, 0.5, 0.4))
			# a1-16 HUD#1/LEG#6: the full cost + stock text draws ONLY on the SELECTED
			# socket — the other seven stop crowding every ring with numbers. Unselected
			# AFFORDABLE sockets get a compact green "can-buy" dot; the × already carries
			# the not-afford read (colorblind-safe). Declutters 1P AND relieves 2P stacking.
			var wdisp := _wheel_socket_display(selected, afford)
			if wdisp == "full":
				var cost_txt := ("%d*" % acost) if is_token else str(acost)
				var costw := f.get_string_size(cost_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
				Art.text(self, cost_txt, ipos + Vector2(-costw / 2.0, 24), 8,
					Color(1.0, 0.95, 0.65) if afford else Color(0.9, 0.5, 0.45))
				var stock := ""
				match int(item["kind"]):
					0: stock = "%d/%d" % [p["mg_ammo"], SimWorld.MG_AMMO_MAX]
					1: stock = "%d/%d" % [p["grenade_ammo"], SimWorld.GRENADE_AMMO_MAX]
					2: stock = "VEST ON" if p["vest"] else "NO VEST"
					4: stock = "%d/%d UP" % [sim.sandbags.size(), SimWorld.SANDBAG_FIELD_CAP]
					5: stock = "%d* HELD" % sim.tokens
				if stock != "":
					var empty := stock.begins_with("0/") or stock == "NO VEST"
					var sw2 := f.get_string_size(stock, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
					Art.text(self, stock, ipos + Vector2(-sw2 / 2.0, 33), 8,
						Color(1.0, 0.55, 0.45) if empty else Color(1.0, 0.97, 0.9))
			elif wdisp == "dot":
				# compact "can-buy" dot: affordability reads at a glance, no numbers
				draw_circle(ipos + Vector2(0.0, 14.0), 2.0, Art.safe(Color(0.45, 1.0, 0.55)))
		# Device-aware verb cue under the hub: the wheel states its own controls,
		# and the cancel button is the real glyph (pad B / keycap C), not a letter.
		# Revive-guard (5-vote panel item): with a teammate down, a buy that
		# would price their revive out of the shared chest is a silent trap —
		# name it BEFORE the release commits the coin.
		if _wheel[i]["sel"] >= 0 and not sim.last_stand:
			var gitem: Dictionary = WHEEL_ITEMS[_SECTOR_TO_ITEM[_wheel[i]["sel"]]]
			var gcost: int = sim._supply_cost(gitem["kind"])
			if sim.war_chest >= gcost:
				for q in sim.players.size():
					var dq := sim.players[q]
					if not dq["alive"] and sim.war_chest - gcost < sim.revive_cost(dq):
						Art.text_center(self, "BUY LEAVES NO REVIVE FOR P%d" % (q + 1),
							c.x, c.y - 63.0, 8, Color(1.0, 0.7, 0.3))
						break
		if _wheel[i]["sel"] >= 0:
			# The verb line must not promise a purchase the sim will deny — an
			# unaffordable pick tints its socket red, so the cue says so too
			# (release on it fires the deny path, not a buy).
			var cue_item: Dictionary = WHEEL_ITEMS[_SECTOR_TO_ITEM[_wheel[i]["sel"]]]
			var cue_afford: bool = (sim.tokens >= 1) if int(cue_item["kind"]) == 5 \
				else sim.war_chest >= sim._supply_cost(cue_item["kind"])
			var cue_l := "RELEASE TO BUY · " if cue_afford else "CAN'T AFFORD · "
			var cue_r := " CANCEL"
			var wl := f.get_string_size(cue_l, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var wr := f.get_string_size(cue_r, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var cx0 := c.x - (wl + 10.0 + wr) / 2.0
			Art.text(self, cue_l, Vector2(cx0, c.y + 52.0), 8,
				Color(0.9, 0.92, 0.8, 0.85) if cue_afford else Color(1.0, 0.55, 0.45, 0.9))
			Art.draw_glyph(self, "roll", Vector2(cx0 + wl + 5.0, c.y + 48.5), 10.0,
				Color.WHITE, i == 1)   # P2's wheel is pad-driven — show pad B, not the C keycap
			Art.text(self, cue_r, Vector2(cx0 + wl + 10.0, c.y + 52.0), 8, Color(0.9, 0.92, 0.8, 0.85))
		else:
			Art.text_center(self, "FLICK TO PICK · RELEASE TO CLOSE", c.x, c.y + 52.0, 8,
				Color(0.9, 0.92, 0.8, 0.85))
		# What the selected socket actually delivers.
		var sel: int = _wheel[i]["sel"]
		if sel >= 0:
			var lbl: String = WHEEL_ITEMS[_SECTOR_TO_ITEM[sel]]["label"]
			# Anchored ABOVE this player's hub — the old global y=71 left P2's
			# pick floating at the top of the screen, nowhere near their wheel.
			Art.text_center(self, lbl, c.x, c.y - 52.0, 9, Color(1.0, 0.95, 0.7))
		# Next-wave clock (c2 2v): the intermission buy should take 2 seconds,
		# not 10 — give it a countdown right under the cue line so the decision
		# has its clock. Reads the already-checksummed intermission_ticks.
		if sim.mode == "endless" and sim.intermission_ticks > 0:
			Art.text_center(self, "NEXT WAVE IN %ds" % ceili(sim.intermission_ticks / 60.0),
				c.x, c.y + 63.0, 8, Color(1.0, 0.95, 0.65))


func _top_center_priority() -> String:
	# Arbiter for the top-center text band: AIRSTRIKE INBOUND, MORTARS RANGING,
	# the splash banner, and the closed-gate objective line all want the same
	# ~y46-90 strip and used to overprint into a smear when several fired in
	# the same frame. Only the single most-urgent one renders per frame.
	for g in sim.gates:
		if g["open"] or g.get("final", false):
			continue
		if g["y"] < sim.camera_top or g["y"] > sim.camera_top + SimWorld.VIEW_H:
			continue
		if sim.stall_ticks > 90:
			return "boss"
		break
	if sim.pending_airstrike > 0:
		return "airstrike"
	if sim.mode == "campaign" and sim.observer.is_empty() \
			and sim.stall_ticks > SimWorld.OBSERVER_STALL_TICKS - 180:
		return "mortar"
	if not _banners.is_empty():
		var bn: Dictionary = _banners[0]
		if float(bn["t"]) > 0.01 and not String(bn["text"]).is_empty():
			return "splash"
	# Lowest priority — HOLD THE ARENA (8/9 play-panel): endless pins the camera
	# for the whole wave but nothing SAID so; a player pushing against the top
	# edge read it as the scroll breaking. Cue only while someone is actually
	# leaning on the invisible wall mid-wave.
	if sim.mode == "endless" and sim.intermission_ticks == 0 \
			and not sim.victory and not sim.wiped:
		for p in sim.players:
			if p["alive"] and p["y"] - sim.camera_top < 56 * Fixed.ONE:
				return "hold"
	return ""


func _draw_airstrike_telegraph(top_msg: String) -> void:
	# The called airstrike's incoming window: a red wash that ramps and strobes as
	# impact nears, so the wipe reads as an anticipated event, not a silent zap.
	if sim.pending_airstrike <= 0:
		return
	var frac := 1.0 - float(sim.pending_airstrike) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
	var a := 0.05 + frac * 0.16
	if _motion >= 0.5 and sim.pending_airstrike < 10 and (sim.pending_airstrike / 3) % 2 == 0:
		a = 0.34   # final-second strobe — full-motion only
	# Reduce-motion: no strobe, but the wash must stay VISIBLE — the old
	# a*_motion+0.03 dimmed a lethal warning to alpha 0.03 for exactly the
	# players who asked for a steadier signal, not a hidden one.
	var wash_a := (a * _motion + 0.03) if _motion >= 0.5 else maxf(0.15, a)
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(1.0, 0.2, 0.1, wash_a))
	# A strike jet dives down the field as the payload arrives — turns a bare
	# countdown into an anticipated run. Reuses the gunship's 'facing down' angle
	# (PI) so the nose leads; rides the already-checksummed pending_airstrike int.
	var jy := lerpf(-30.0, SCREEN_H + 30.0, frac)
	_spr("m_jet", Vector2(SCREEN_W * 0.5, jy), PI, 0.6)
	# Ground-zero marker: a billowing smoke column at the strike center for the
	# whole telegraph (scale pulse = billow) — the red wash finally points somewhere.
	# Real plume card (Particle_FX fumes), not the wep_smoke grenade-canister
	# pickup sprite that stood in for it since p2. Second card rides higher and
	# fainter so the column reads as RISING, not a stamped decal.
	var bil := 1.0 + 0.12 * sin(float(Engine.get_physics_frames()) * 0.2)
	var msz := (34.0 + frac * 20.0) * bil
	draw_texture_rect(Art.tex("fx_fumes"), Rect2(SCREEN_CENTER - Vector2(msz / 2.0, msz),
		Vector2(msz, msz)), false, Color(1.0, 0.75, 0.5, 0.45 + frac * 0.3))
	var msz2 := msz * 0.7
	draw_texture_rect(Art.tex("fx_smoke"), Rect2(SCREEN_CENTER - Vector2(msz2 / 2.0, msz + msz2 * 0.6),
		Vector2(msz2, msz2)), false, Color(1.0, 0.8, 0.6, 0.2 + frac * 0.15))
	if top_msg != "airstrike":
		return
	var txt := "AIRSTRIKE INBOUND  %.1fs" % (sim.pending_airstrike / 60.0)
	Art.text_center(self, txt, 320, 46, 12, Color(1.0, 0.85, 0.3))


func _draw_threat_pips() -> void:
	# Off-screen one-shot telegraphs (sniper / grenadier / ghillie winding up) get a
	# clamped screen-edge arrow so a lethal shot from beyond the 640x360 viewport reads
	# as a threat, not a cheap death. Stateless — recomputed from live sim state each
	# frame, so it self-clears when the windup ends or the source scrolls on-screen.
	# Corner-HUD avoidance mirrors the edge chevrons: a pip clamped to the top edge
	# under the opaque icon plate would be over-painted by the $HUD CanvasLayer.
	var plate_r := _hud_icons.plate_right()
	var panel_b := _hud_icons.panel_bottom() + 12.0
	for e in sim.enemies:
		if not e["alive"] or e.get("windup", 0) <= 0:
			continue
		var k: String = e["kind"]
		if k != "sniper" and k != "grenadier" and k != "ghillie" and k != "drone" \
				and k != "technical":
			continue
		var sp := _to_screen(e["x"], e["y"])
		if sp.x >= 0.0 and sp.x <= SCREEN_W and sp.y >= 0.0 and sp.y <= SCREEN_H:
			continue   # on-screen — the on-body telegraph already covers it
		var edge := Vector2(clampf(sp.x, 12.0, SCREEN_W - 12.0), clampf(sp.y, 12.0, SCREEN_H - 12.0))
		if edge.x < plate_r and edge.y < panel_b:
			edge.y = panel_b
		var dir := (sp - edge).normalized()
		if dir == Vector2.ZERO:
			continue
		# Amber = incoming AREA strike (grenadier lob / drone paint), red = aimed shot.
		var col := Color(1.0, 0.7, 0.25) if (k == "grenadier" or k == "drone") else Color(1.0, 0.32, 0.32)
		var pf := 1.0 if _motion < 0.5 else Art.pulse(0.12)   # steady under reduce-motion
		var perp := Vector2(-dir.y, dir.x)
		var tip := edge + dir * (7.0 + pf * 3.0)
		var base := edge - dir * 4.0
		var tri := PackedVector2Array([tip, base + perp * 5.0, base - perp * 5.0])
		draw_circle(edge, 9.0 + pf * 2.0, Color(col.r, col.g, col.b, 0.14 + pf * 0.08))
		if k == "grenadier" or k == "drone":
			# AREA strike incoming = HOLLOW arrow; aimed shot = filled. The
			# amber/red hue split collapses under deuteranopia, so the shape
			# carries the "move off this spot" vs "break the line" semantic.
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
				Color(col.r, col.g, col.b, 0.95), 2.0)
		else:
			draw_colored_polygon(tri, Color(col.r, col.g, col.b, 0.9))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.55), 1.0)
	# Off-screen mortar strikes: a telegraph that scrolls off-frame between cast and
	# impact gave zero warning; clamp an urgency-scaled amber-red wedge to the edge.
	for st in sim.strikes:
		var ssp := _to_screen(st["x"], st["y"])
		if ssp.x >= 0.0 and ssp.x <= SCREEN_W and ssp.y >= 0.0 and ssp.y <= SCREEN_H:
			continue
		var sedge := Vector2(clampf(ssp.x, 12.0, SCREEN_W - 12.0), clampf(ssp.y, 12.0, SCREEN_H - 12.0))
		if sedge.x < plate_r and sedge.y < panel_b:
			sedge.y = panel_b
		var sdir := (ssp - sedge).normalized()
		if sdir == Vector2.ZERO:
			continue
		var urg := 1.0 - float(st.get("ticks", 0)) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
		var sperp := Vector2(-sdir.y, sdir.x)
		var stip := sedge + sdir * (8.0 + urg * 5.0)
		var sbase := sedge - sdir * 4.0
		var stri := PackedVector2Array([stip, sbase + sperp * 6.0, sbase - sperp * 6.0])
		draw_circle(sedge, 10.0 + urg * 3.0, Color(1.0, 0.5, 0.2, 0.14 + urg * 0.14))
		draw_colored_polygon(stri, Color(1.0, 0.5, 0.2, 0.75 + urg * 0.25))
		draw_polyline(PackedVector2Array([stri[0], stri[1], stri[2], stri[0]]), Color(0, 0, 0, 0.55), 1.0)


func _draw_banners(top_msg: String) -> void:
	# Always-on cinematic vignette: a framed arcade-cabinet look on every frame
	# (static, so it stays even under reduce-motion).
	draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, SCREEN_W, SCREEN_H), false,
		Color(0.0, 0.0, 0.0, 0.12))   # a1-12 VFX#5: eased 0.16->0.12 so corners keep dark-enemy contrast
	# Damage vignette: pulses on hits, sustains through the mercy window.
	var vig := _damage_vignette
	for p in sim.players:
		if p["alive"] and p["hurt_iframes"] > 0:
			vig = maxf(vig, 0.3 * float(p["hurt_iframes"]) / float(SimWorld.VEST_IFRAME_TICKS))
	if vig > 0.01:
		draw_texture_rect(Art.tex("hudfx_dmgvig"), Rect2(0, 0, SCREEN_W, SCREEN_H), false,
			Color(0.85, 0.12, 0.08, minf(1.0, vig) * (0.35 + 0.65 * _motion)))
	# Blood on the lens at the death/near-death moment only — gated well above
	# the routine vest-graze pulse (0.3) so a normal hit never triggers it.
	if vig > 0.62:
		var bt := Art.tex("hudfx_blood")
		var qsz: float = bt.get_size().x / 2.0
		var quad := (Engine.get_physics_frames() / 37) % 4
		draw_texture_rect_region(bt, Rect2(0, 0, SCREEN_W, SCREEN_H),
			Rect2(float(quad % 2) * qsz, float(quad / 2) * qsz, qsz, qsz),
			Color(0.5, 0.02, 0.02, (vig - 0.62) * 1.5))
	# Sniper-paint danger: a strobing red edge while any sniper winds up its
	# locked shot, so "you're painted, MOVE" is unmissable even off the reticle.
	var paint := 0.0
	for pe in sim.enemies:
		if pe["alive"] and pe["kind"] == "sniper" and pe.get("windup", 0) > 0:
			paint = maxf(paint, 1.0 - float(pe["windup"]) / float(SimWorld.SNIPER_WINDUP_TICKS))
	if paint > 0.01:
		# 0.25 rad/frame ≈ 2.4 flashes/s — the old 0.4 strobed at ~3.8/s, over
		# the 3/s photosensitivity threshold, sustained for the whole windup.
		var pv := (0.1 + 0.24 * paint) * (0.4 + 0.6 * Art.pulse(0.25))
		draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, SCREEN_W, SCREEN_H), false,
			Color(1.0, 0.15, 0.12, pv * _motion))
		# 'You're being sighted' as an icon, not only a red edge: a binoculars
		# glyph pulses top-center for the windup. Alpha is NOT gated by _motion,
		# so it still warns under reduce-motion (where the vignette is damped).
		var bsz := roundf(15.0 + 4.0 * paint)   # integer-snap: subpixel scale shimmers at nearest-filter
		draw_texture_rect(Art.tex("item_binoculars"),
			Rect2(floorf(SCREEN_W / 2.0 - bsz / 2.0), 22.0, bsz, bsz), false,
			Color(1.0, 0.55, 0.4, 0.4 + 0.45 * paint))
	if _flash_alpha > 0.01:
		# Radial flash: hottest at screen center, falling off toward the edges
		# (oversized softspot card) over a faint flat base — punchier than a
		# uniform white sheet at the same energy.
		# maxf floor (6/9 panel): zeroing the wash under reduce-motion erased the
		# whole-field-stun gestalt entirely; siblings (damage vignette, airstrike
		# wash) keep a dimmed floor. The decay is a fade, not a strobe — RM-safe.
		var fla := _flash_alpha * maxf(_motion, 0.4)
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(1, 1, 1, fla * 0.45))
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(-160, -180, SCREEN_W + 320, SCREEN_H + 360),
			false, Color(1, 1, 1, fla))
	# Last-stand dread: darken the edges + a slow red pulse as the finale
	# closes in (heartbeat plays under it). Scaled by the reduce-motion toggle.
	if _tension > 0.02:
		var hb := Art.pulse(0.11)
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H),
			Color(0.15, 0.0, 0.0, _tension * (0.12 + 0.1 * hb) * _motion))
	# Directional damage wedge: a red arc on the screen edge pointing at the
	# threat that hit you — the "where from?" answer in a one-hit game.
	if _hit_dir_t > 0.01:
		var ang := _hit_dir.angle()
		var origin := SCREEN_CENTER
		if _hit_dir_player >= 0 and _hit_dir_player < sim.players.size():
			var hp: Dictionary = sim.players[_hit_dir_player]
			origin = _to_screen(hp["x"], hp["y"])
		var mid := origin + _hit_dir * 210.0
		# Keep the wedge tip inside an inset rect — near a viewport corner the
		# whole arc used to project off-screen and the "where from?" vanished.
		mid = Vector2(clampf(mid.x, 12.0, 628.0), clampf(mid.y, 12.0, 348.0))
		var perp := Vector2(-_hit_dir.y, _hit_dir.x)
		var wc := Color(1.0, 0.2, 0.15, _hit_dir_t * 0.8)
		var pts := PackedVector2Array([mid + perp * 46.0, mid - perp * 46.0,
			mid + _hit_dir * 26.0])
		draw_colored_polygon(pts, wc)
	# Arena-lock directive: the camera holds at closed gates by design, but
	# the objective must be said out loud (playtest: "scrolling just stops").
	for g in sim.gates:
		if g["open"] or g.get("final", false):
			continue
		if g["y"] < sim.camera_top or g["y"] > sim.camera_top + SimWorld.VIEW_H:
			continue
		if top_msg == "boss" and sim.stall_ticks > 90:
			var gpulse := 1.0 if _motion < 0.5 else Art.pulse(0.15)
			var gtxt := "DESTROY THE GUNSHIP TO ADVANCE" if not g["boss"].is_empty() \
				else "GRENADE THE BUNKERS TO ADVANCE"
			var gy: float = (g["y"] - sim.camera_top) * PX + 30.0
			_banner_plate(gtxt, gy, 11, 1.0)
			Art.text_center(self, gtxt, 320, gy, 11, Color(1.0, 0.9, 0.4, gpulse))
		break
	# Arena hold: a calm statement, not an alarm — the player at the top edge
	# needs the RULE ("the camera stays until the wave dies"), not a red strobe.
	if top_msg == "hold":
		var htxt := "HOLD THE ARENA — CLEAR THE WAVE"
		_banner_plate(htxt, 46.0, 10, 0.8)
		Art.text_center(self, htxt, 320, 46, 10, Color(0.85, 0.88, 0.75, 0.8))
	# Stall warning: the observer's clock is running — telegraph the
	# punishment before it arrives, not after.
	if top_msg == "mortar":
		var pulse := 1.0 if _motion < 0.5 else 0.55 + 0.45 * sin(float(Engine.get_physics_frames()) * 0.25)
		var wtxt := "MORTARS RANGING — ADVANCE!"
		_banner_plate(wtxt, 46.0, 11, 1.0)
		Art.text_center(self, wtxt, 320, 46, 11, Color(1.0, 0.4, 0.25, pulse))
	# Splash banner (wave starts, checkpoints, observer warning).
	if not _banners.is_empty():
		var bn: Dictionary = _banners[0]
		var bt: float = bn["t"]
		var btext: String = bn["text"]
		if top_msg == "splash" and bt > 0.01 and not btext.is_empty() \
				and not _debrief and not sim.victory:   # never overprint the result card
			var a := minf(1.0, bt * 4.0) * minf(1.0, (1.0 - bt) * 8.0 + 0.2)
			var bc: Color = bn.get("col", Color(1.0, 0.92, 0.55))
			# Duck below any active boss bars (they dock at HudIcons.BOSS_BAR_TOP + slot*22 —
			# the same shared boundary hud.gd sizes its corner panel against) instead
			# of overprinting the PHASE label; pop-in scale punch on the first ~10%
			# of life, stilled under reduce-motion.
			var by := HudIcons.BOSS_BAR_TOP + 6.0 + 22.0 * float(_boss_bar_slots)
			var bsize := 16
			if _motion >= 0.5:
				bsize = int(16.0 * (1.0 + 0.4 * clampf((bt - 0.9) * 10.0, 0.0, 1.0)))
			# Shrink-to-fit: long teach strings (TECHNICAL 52ch, COURIER 58ch) at
			# punch sizes overflow the 640px viewport and shove the badge off-screen.
			while bsize > 8 and Art.font().get_string_size(btext, HORIZONTAL_ALIGNMENT_LEFT, -1, bsize).x > 600.0:
				bsize -= 1
			# A badge (if any) sits left of the centered text — the plate must
			# extend to cover it, or the skull/target/lightning floats off the
			# metal onto bare shaking terrain (the plate exists to prevent exactly
			# that). Measure it BEFORE plating so the plate can reserve its width.
			var bic: String = bn.get("icon", "")
			var bis := float(bsize) + 4.0
			var pad_left := (bis + 8.0) if not bic.is_empty() else 0.0
			_banner_plate(btext, by, bsize, a, pad_left)
			Art.text_center(self, btext, 320, by, bsize, Color(bc.r, bc.g, bc.b, a))
			# Threat-callout badge (skull/target/lightning) fronting the text —
			# only set by the alarm banners, so routine splashes stay clean.
			if not bic.is_empty():
				var biw := Art.font().get_string_size(btext, HORIZONTAL_ALIGNMENT_LEFT, -1, bsize).x
				draw_texture_rect(Art.tex(bic),
					Rect2(320.0 - biw / 2.0 - bis - 6.0, by - float(bsize) / 2.0 - bis / 2.0, bis, bis),
					false, Color(bc.r, bc.g, bc.b, a))
	if sim.victory:
		var vpulse := 1.0 if _motion < 0.5 else 0.85 + 0.15 * sin(float(Engine.get_physics_frames()) * 0.12)
		var vrr := _run_rank()
		var vrows: Array = [
			{"text": "RANK  %s — %s" % [vrr.grade, vrr.title], "color": vrr.col, "size": 13,
				"icon": "mi_medal_%d" % ("DCBAS".find(vrr.grade) + 1), "icon_size": 15.0,
				"icon_col": vrr.col},
			{"text": "SCORE  %s" % Art.group_digits(sim.score), "color": Color(0.95, 0.96, 0.9), "size": 13,
				"icon": "icon_medal", "icon_size": 16.0},
			{"text": "%d¢ WAR CHEST BANKED" % sim.war_chest, "color": Color(1.0, 0.92, 0.55),
				"icon": "icon_coin", "icon_size": 14.0},
			{"text": "%dm OF JUNGLE PUSHED" % [-Fixed.to_int(sim.camera_top) / 10], "color": Color(0.8, 0.84, 0.74)},
		]
		if _run_rescues > 0:
			vrows.insert(2, {"text": "PILOTS RESCUED  %d" % _run_rescues,
				"color": Art.safe(Color(0.5, 1.0, 0.7))})
		# a4-16 (HUD#1): the win screen tells the run's STORY too — KILLS + LONGEST STREAK +
		# TOP PREY, the rows the K.I.A. debrief always had. A win is now a full debrief, not a
		# thinner card than a loss. (a3-14 added the NEW BEST/REDEPLOY parity below.)
		for sr in _victory_story_rows(_run_kills, _run_best_streak, _run_kind_kills):
			vrows.append(sr)
		# a3-14 (HUD#4/#8/#10): bring the VICTORY card to K.I.A. parity — the win screen was
		# thinner than the death screen. _victory_extra_rows appends a NEW BEST! flag (shared
		# predicate with the debrief) + a REDEPLOY prompt (redeploy input works on victory too,
		# but the card never told you so — the death card does).
		var vrp := 1.0 if _motion < 0.5 else 0.6 + 0.4 * sin(float(Engine.get_physics_frames()) * 0.15)
		for vr in _victory_extra_rows(sim.score, best_score, vrp):
			vrows.append(vr)
		_draw_result_panel("V I C T O R Y !", Color(1.0, 0.85 * vpulse, 0.3 * vpulse), vrows,
			Color(1, 1, 1, 0.96), true)   # a1-11: gold shine sweep
		# Trophy overlaps blank panel space only (no row text under it), so it's
		# safe to draw after the shared panel/title/rows without reordering.
		var tsz := 52.0 * (0.94 + 0.06 * vpulse)
		draw_texture_rect(Art.tex("trophy"),
			Rect2(Vector2(196.0 - tsz / 2.0, 182.0 - tsz / 2.0), Vector2(tsz, tsz)), false)
	elif _debrief:
		# Defeat debrief: the death bookend the victory tally always had —
		# tells the story of the run and points at 'one more'.
		var opened := 0
		for g in sim.gates:
			if g["open"]:
				opened += 1
		var dist := -Fixed.to_int(sim.camera_top) / 10
		var rows := [
			{"text": "SECTOR %d/5   %dm PUSHED" % [mini(opened + 1, 5), dist], "color": Color(0.9, 0.92, 0.85)},
			{"text": "SCORE %s   KILLS %d" % [Art.group_digits(sim.score), _run_kills], "color": Color(0.9, 0.92, 0.85)},
			{"text": "LONGEST STREAK  x%d" % _run_best_streak, "color": Color(0.9, 0.92, 0.85)},
		]
		# Top-prey row: the kill event carries kind, so the tally can say WHAT the run was
		# spent fighting, not just how many (a4-16: shared _top_prey_text with the victory card).
		var kprey := _top_prey_text(_run_kind_kills)
		if kprey != "":
			rows.append({"text": kprey, "color": Color(0.9, 0.92, 0.85)})
		if _run_rescues > 0:
			rows.append({"text": "PILOTS RESCUED  %d" % _run_rescues,
				"color": Art.safe(Color(0.5, 1.0, 0.7))})
		var rr := _run_rank()
		# Grade medal (D=1 … S=5) rides the panel's existing icon slot.
		rows.insert(0, {"text": "RANK  %s  —  %s" % [rr.grade, rr.title], "color": rr.col,
			"icon": "mi_medal_%d" % ("DCBAS".find(rr.grade) + 1), "icon_size": 15.0,
			"icon_col": rr.col})
		if _downed_by != "":
			rows.insert(1, {"text": "DOWNED BY  %s" % _downed_by, "color": Color(1.0, 0.55, 0.5)})
		if best_score > 0:
			rows.append({"text": "BEST %d" % best_score + ("   NEW BEST!" if sim.score >= best_score else ""),
				"color": Color(0.9, 0.92, 0.85)})
		# Near-miss hook: turn a loss into a legible 'so close' — the strongest
		# one-more-run lever in a session-based arcade loop.
		if sim.mode == "endless" and best_wave > 0 and sim.wave < best_wave:
			var dw := best_wave - sim.wave
			rows.append({"text": "%d WAVE%s SHORT OF YOUR BEST" % [dw, "" if dw == 1 else "S"],
				"color": Color(1.0, 0.85, 0.5)})
		elif sim.mode == "campaign" and best_dist > 0 and dist < best_dist:
			rows.append({"text": "%dm SHORT OF YOUR BEST PUSH" % (best_dist - dist),
				"color": Color(1.0, 0.85, 0.5)})
		var rp := 1.0 if _motion < 0.5 else 0.6 + 0.4 * sin(float(Engine.get_physics_frames()) * 0.15)
		# Device-branched prompt: the actual button glyph (pad START / ENTER key)
		# fronts the row via the panel's icon slot.
		rows.append({"text": "REDEPLOY", "color": Color(1.0, 0.9, 0.4, rp),
			"icon": Art.glyph_key("start"), "icon_size": 14.0})
		_draw_result_panel("K.I.A.", Color(0.95, 0.4, 0.35), rows, Color(1, 1, 1, 0.96))
	elif sim.last_stand:
		# Shadowed + centered via the shared helper — was the one banner holdout
		# still drawing raw, unshadowed, hardcoded-position text.
		Art.text_center(self, "LAST STAND — NO REVIVES", 320.0, 350.0, 10, Color(0.95, 0.4, 0.3))
	# Black fade covering the title→combat cut.
	if _fade > 0.01:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, _fade))
	# Just-in-time onboarding cue (first-time-ever, persisted).
	# Persistent replay chrome: after the one-shot banner decays, SOMETHING must
	# keep saying "this is playback, inputs are frozen" for the whole watch.
	if _watching:
		var wpul := 1.0 if _motion < 0.5 else (0.7 + 0.3 * Art.pulse(0.15))
		Art.text_center(self, "— REPLAY — %s TO EXIT —" % ("START" if Art.use_pad else "R"),
			320, 30, 9, Color(0.55, 0.9, 1.0, wpul))
	if _hint_t > 0.02 and not _hint_text.is_empty() and not _debrief and not sim.victory:
		var ha := minf(1.0, _hint_t * 3.0)
		var hf := Art.font()
		var hw := hf.get_string_size(_hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		# Tooltip plate + the baked attention badge (ui_tooltip is a round "!"
		# badge, not a nine-patch — stretched to text width it smears, so it
		# fronts the plate as the hint's icon instead).
		var hx := 320.0 - hw / 2.0 - 8.0
		# Duck below active boss bars (same 22px/slot offset the splash banner
		# uses) — at one slot the splash lands at y=92 right on this plate.
		var hy := 22.0 * float(_boss_bar_slots)
		_metal_plate(Rect2(hx, 92 + hy, hw + 16, 18), ha)
		draw_texture_rect(Art.tex("ui_tooltip"), Rect2(hx - 22.0, 90.0 + hy, 22, 22), false,
			Color(1.0, 0.95, 0.75, ha))
		Art.text_center(self, _hint_text, 320, 105 + hy, 11, Color(1.0, 0.95, 0.7, ha))


## Shared victory/debrief result-card scaffold: translucent panel + centered
## title + a stack of centered stat rows (each optionally icon-prefixed).
## rows: Array[Dictionary] of {text, color, size?, icon?, icon_size?, icon_col?}.
static func _banner_plate_alpha(text_a: float) -> float:
	# a1-17 HUD#5/LEG#7: the banner plate holds a floor (0.7) while the text is at
	# all visible, so the dark backing LEADS the words in and never washes out at the
	# fade edges over bright terrain (was 0.5*text-alpha, fading WITH the words).
	return (maxf(text_a, 0.7) if text_a > 0.05 else 0.0)


func _banner_plate(txt: String, y: float, size: int, a: float, pad_left := 0.0) -> void:
	# Dark under-plate behind top-strip text: bare glyphs smear over bright
	# jungle + shake; the plate is what makes the words instant.
	var w := Art.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	# pad_left extends the plate leftward under a fronting badge; the text stays
	# centered on 320, so only the left edge grows (right stays symmetric to text).
	var plate_a := _banner_plate_alpha(a)
	_metal_plate(Rect2(320.0 - w / 2.0 - 5.0 - pad_left, y - size - 2.0,
		w + 10.0 + pad_left, size + 7.0), plate_a)


func _metal_plate(r: Rect2, a: float) -> void:
	# Hand 3-slice from the baked plate_metal_* set (190x230 slices): caps at the
	# ends + a stretched center, laid over the old dark rect (text contrast) and
	# tinted way down so it stays muted retro-metal under the text, not chrome.
	draw_rect(r, Color(0.05, 0.06, 0.04, 0.5 * a))
	var cap := minf(r.size.y * (190.0 / 230.0), r.size.x / 2.0)
	var mcol := Color(0.5, 0.52, 0.5, 0.5 * a)
	draw_texture_rect(Art.tex("plate_metal_l"), Rect2(r.position, Vector2(cap, r.size.y)), false, mcol)
	if r.size.x > cap * 2.0:
		draw_texture_rect(Art.tex("plate_metal_c"),
			Rect2(r.position + Vector2(cap, 0.0), Vector2(r.size.x - cap * 2.0, r.size.y)), false, mcol)
	draw_texture_rect(Art.tex("plate_metal_r"),
		Rect2(r.position + Vector2(r.size.x - cap, 0.0), Vector2(cap, r.size.y)), false, mcol)


func _draw_result_panel(title: String, title_col: Color, rows: Array, accent: Color, shine := false) -> void:
	var rf := Art.font()
	var panel_top := 112.0
	var title_y := 150.0
	var row_start_y := 178.0
	var row_h := 19.0
	var panel_h := (row_start_y - panel_top) + maxi(rows.size(), 1) * row_h + 14.0
	# Width adapts to the widest row (icon included) so a long DOWNED-BY line
	# can't escape the plate; 300 stays the floor so short tallies keep their shape.
	var max_w := rf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	for row in rows:
		var rw: float = rf.get_string_size(row["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, row.get("size", 11)).x
		if not String(row.get("icon", "")).is_empty():
			rw += row.get("icon_size", 14.0) + 6.0
		max_w = maxf(max_w, rw)
	var panel_w := clampf(max_w + 44.0, 300.0, 620.0)
	var panel_x := 320.0 - panel_w / 2.0
	# Entrance: the run's final beat scales in over ~12 frames instead of
	# teleporting onto the screen. Composes WITH the shake-cancel matrix the
	# caller set (plain draw_set_transform would clobber it). Pivot sits at the
	# PANEL's center, not screen center — the card used to slide while scaling.
	if _motion >= 0.5 and _result_t < 1.0:
		var re := 1.0 - pow(1.0 - _result_t, 3.0)
		var rscale := 0.92 + 0.08 * re
		draw_set_transform_matrix(get_transform().affine_inverse()
			* Transform2D(0.0, Vector2.ONE * rscale, 0.0,
				Vector2(320.0, panel_top + panel_h / 2.0) * (1.0 - rscale)))
	draw_texture_rect(Art.tex("ui_panel"), Rect2(panel_x, panel_top, panel_w, panel_h), false, accent)
	Art.text_center(self, title, 320, title_y, 24, title_col)
	if shine:
		# a1-11 VFX#10: a soft warm glint sweeps across the title on a slow loop (with
		# a pause) so the run's payoff title catches the light like polished metal.
		var sw := fposmod(float(Engine.get_physics_frames()) * 0.012, 1.5) - 0.2
		if sw >= 0.0 and sw <= 1.0:
			draw_set_transform(Vector2(panel_x + 20.0 + sw * (panel_w - 40.0), title_y), -0.35, Vector2.ONE)
			draw_texture_rect(Art.tex("fx_softspot"), Rect2(-13.0, -22.0, 26.0, 44.0),
				false, Color(1.0, 0.95, 0.7, 0.5 * sin(sw * PI)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var row_text: String = row["text"]
		var col: Color = row["color"]
		var row_size: int = row.get("size", 11)
		var icon: String = row.get("icon", "")
		var icon_size: float = row.get("icon_size", 14.0)
		var y := row_start_y + i * row_h
		var text_w := rf.get_string_size(row_text, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x
		var gap := 6.0
		var total_w := text_w + (icon_size + gap if not icon.is_empty() else 0.0)
		var x := 320.0 - total_w / 2.0
		if not icon.is_empty():
			# icon_col tints white-with-alpha menu-icon art (mi_medal_* grades);
			# untinted rows keep drawing as-authored.
			draw_texture_rect(Art.tex(icon), Rect2(x, y - icon_size + 3.0, icon_size, icon_size),
				false, row.get("icon_col", Color.WHITE))
			x += icon_size + gap
		Art.text(self, row_text, Vector2(x, y), row_size, col)   # shadowed like every other HUD string
	# Back to the plain shake-cancel matrix for whatever the caller draws next.
	draw_set_transform_matrix(get_transform().affine_inverse())


func _update_hud() -> void:
	_hud_icons.queue_redraw()
