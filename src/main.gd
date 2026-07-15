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
# Battlefield-litter prop pool, scattered deterministically in _draw_terrain().
const _LITTER := ["barrel", "crate_stack", "rock1", "rock2", "wreck", "tent",
	"watchtower", "barbedwire", "barrier", "ammobox",
	"wreck_apc", "wreck_technical", "wreck_light_tank"]
# Base-rusher sprite variants indexed by the sim's cosmetic per-enemy "skin"
# (spawn-derived, checksum-excluded) so a rush reads as varied troops.
const _RUSHER_SKINS := ["rusher", "m_insurgent3", "m_insurgent4", "m_insurgent5"]
# Dead hulks that slump beside a parked tank (convoy-graveyard set-dressing).
const _TANK_HULKS := ["wreck_apc", "wreck_technical", "wreck_light_tank"]

var sim: SimWorld
var _recorder: Replay             # captures this run's inputs → user://last_run.replay (view-only)
var _watching := false            # Watch Last Run playback mode
var _watch_replay: Replay = null
var _watch_frame := 0
var _replay_saved := false        # save the replay once per run, at the debrief
var _two_players := false
var _endless := false
var _daily := false              # seed-of-the-day challenge run
var _seed_override := -1         # CHALLENGE SEED: one-shot forced seed (-1 = none)
# Feel stack (view-only; the sim never sees any of this).
var _trauma := 0.0
var _hitstop_frames := 0
var _flash_alpha := 0.0
var _fx: Array[Dictionary] = []   # explosion/smoke animations from sim events
var _pending_blasts: Array[Dictionary] = []   # scheduled boss-death secondary detonations
var _scorch: Array[Dictionary] = []   # lingering ground scorch decals (drawn under units)
var _corpses: Array[Dictionary] = []  # fallen enemies, fading (drawn under units)
var _sfx := Sfx.new()
var _recoil: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # per-player gun kick
var _hit_flinch: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # per-player body kick when hit
var _kick := Vector2.ZERO         # directional screen nudge from firing
var _kill_streak := 0             # decaying combo counter for kill-blip pitch
var _last_kill_frame := -100
var _rumble := 0.0                # pending gamepad vibration this frame
var _rumble_on := true            # accessibility: gamepad vibration on/off
var no_autopause := false         # set by dev harnesses whose window never holds focus
var _heat: Array[float] = [0.0, 0.0]   # per-player MG barrel heat (sustained-fire feel)
var _boss_flash := 0.0           # white-hot flash on the boss/colossus body when shot
var _down_anim: Array[float] = [0.0, 0.0]   # per-player death-knockdown tween (0→1)
var _motion := 1.0               # accessibility: 0 = reduce shake/flash/vignette
var colorblind := false          # deuteran-safe: remap 'affordable/safe' green → cyan
var _assist := false             # accessibility: permanent 2-hit vest (flagged on the leaderboard)
var _hard := false               # New Game+ HARD: tighter campaign spawn curve
var _last_gate_tick := 0         # view-side gate-split timer (speedrun read)
var _best_gate_split := 0        # fastest gate split this run
var _punch := 0.0                # camera zoom-punch on heavy impacts
var _fade := 0.0                 # black fade-in on boot-into-combat
var _duck := 0.0                 # music-duck under heavy hits
var _concussion := 0.0           # low-pass 'ears ringing' after a near-death
var _screen_fx_mat: ShaderMaterial   # full-screen concussion warp (view-only)
var _screen_fx_rect: ColorRect       # hidden unless concussed → normal play untouched
var _water_shader: Shader            # animated river water (view-only, see water.gdshader)
var _water_rects: Array[ColorRect] = []   # pooled per-band water quads (z=-1, under units)
var _bg_root: Node2D                 # opaque grass/dirt base (z=-2, under the water quads)
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
var _water_prev: Array[bool] = [false, false]   # per-player prev in-water state (edge-triggers entry droplets)
var _enemy_water_prev: Array[bool] = []         # per-enemy-slot prev in-water state (index-keyed; ponytail: a
                                                 # death mid-array can misalign one slot for a frame — cosmetic only)
var _hit_dir := Vector2.ZERO     # screen-edge damage wedge direction
var _hit_dir_t := 0.0
var _hit_dir_player := 0         # which player's body the wedge emanates from
var _record_fired := false       # NEW RECORD banner once per run
var _boss_ghost := {}            # view-side prev-HP fraction per boss, for the draining chip
var _seen := {}                  # persisted first-time-hint flags
var _current_seed := 0           # this run's RNG seed (shown on pause)
var _hint_text := ""             # current just-in-time onboarding cue
var _hint_t := 0.0
var _hint_queue: Array[String] = []      # pending first-time hints, drained one at a time
var _run_kills := 0              # this-run tally for the debrief card
var _run_best_streak := 0
var _down_frames := 0            # sustained all-players-down → debrief
var _debrief := false
var _damage_vignette := 0.0       # red screen-edge pulse on hits/deaths
var _banners: Array[Dictionary] = []          # FIFO of center-screen splashes {text, t, col}
var _dry_frame := -100            # rate-limits the dry-FIRE (MG) click
var _dry_grenade_frame := -100    # separate clock for the dry-THROW (grenade) click
var _grenade_dry: Array[int] = [0, 0]   # HUD grenade-pip red flash on empty throw (per-player)
var _seen_bosses := {}            # gate_y → true once the gunship intro played
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
var _best_dirty := false
var _prev_colossus_phase := 0     # phase-change escalation banners
# War Chest spend-wheel (hold Q / pad BACK, flick a direction, release to buy).
var _wheel: Array[Dictionary] = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]
const WHEEL_ITEMS := [
	{"kind": 0, "icon": "icon_ammo", "cost": SimWorld.SHOP_AMMO_COST, "label": "AMMO +30"},
	{"kind": 1, "icon": "icon_grenade", "cost": SimWorld.SHOP_GRENADE_COST, "label": "GRENADES +4"},
	{"kind": 2, "icon": "icon_vest", "cost": SimWorld.SHOP_VEST_COST, "label": "FLAK VEST"},
	{"kind": 3, "icon": "icon_airstrike", "cost": SimWorld.SHOP_AIRSTRIKE_COST, "label": "AIRSTRIKE"},
]
const BUY_FLOAT := ["+30 AMMO", "+4 GRENADES", "FLAK VEST ON", "AIRSTRIKE INBOUND"]
const _SECTOR_TO_ITEM: Array[int] = [2, 3, 0, 1]   # right=vest, down=airstrike, left=ammo, up=grenade

## Sim event → [sound, volume dB, pitch]. Pickups are special-cased on cost.
const _EVENT_SOUND := {
	"shot": ["shot", -9.0, 1.0],
	"tank_shot": ["tank_shot", -3.0, 1.0],
	"throw": ["throw", -8.0, 1.0],
	"roll": ["roll", -8.0, 1.0],
	"explosion": ["explosion", -2.0, 1.0],
	# "kill" plays in the match branch with streak-scaled pitch, not here.
	"player_down": ["player_down", 0.0, 1.0],
	"vest_break": ["vest_break", -2.0, 1.0],
	"gate_open": ["gate_open", -4.0, 1.0],
	"revive": ["revive", -5.0, 1.0],
	"tank_board": ["tank_board", -5.0, 1.0],
	"tank_ignite": ["alarm", -4.0, 1.1],
	"observer_spawn": ["alarm", -3.0, 1.0],
	"strike_warn": ["whistle", -6.0, 1.0],
	"enemy_shot": ["enemy_shot", -12.0, 1.0],
	"elite_windup": ["pickup", -10.0, 0.7],
	"grenadier_windup": ["throw", -8.0, 0.7],
	"sniper_paint": ["alarm", -12.0, 1.4],
	"sniper_fire": ["shot", -4.0, 0.6],
	"bunker_break": ["explosion", -4.0, 0.72],
	"bash": ["vest_break", -3.0, 0.8],
	"frogman_surface": ["splash", -4.0, 1.0],
	"wave_start": ["wave_start", -5.0, 1.0],
	"wave_clear": ["wave_clear", -5.0, 1.0],
	"colossus_engage": ["alarm", 0.0, 0.75],
	"victory": ["victory", 0.0, 1.0],
	"buy": ["buy", -4.0, 1.0],
	"deny": ["deny", -6.0, 1.0],
}

var _hud_icons := HudIcons.new()
var _menu := GameMenu.new()


func _ready() -> void:
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
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_root.material = glow_mat
	_glow_root.draw.connect(_draw_glow)
	add_child(_glow_root)
	_load_bests()
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
	_screen_fx_rect = ColorRect.new()
	_screen_fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_fx_rect.size = get_viewport_rect().size
	_screen_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eats input
	_screen_fx_rect.visible = false
	_screen_fx_mat = ShaderMaterial.new()
	_screen_fx_mat.shader = load("res://src/view/screen_fx.gdshader")
	_screen_fx_rect.material = _screen_fx_mat
	fx_layer.add_child(_screen_fx_rect)


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


func _sync_water() -> void:
	# Place a shader quad over every on-screen water band, faithful to _draw_water's
	# geometry (full width, WATER_H tall, at the band's screen-y). View-only: reads
	# sim state, never writes it. Called from _draw() so it also runs under the
	# screenshot harness (which disables _process). Unused pool entries are hidden.
	if sim == null:
		return
	var vis := 0
	for w in sim.waters:
		if vis >= _water_rects.size():
			break
		var wy: float = (w["y"] - sim.camera_top) * PX
		if wy > 360.0 or wy + SimWorld.WATER_H * PX < 0.0:
			continue   # band fully off-screen
		var rect := _water_rects[vis]
		vis += 1
		rect.visible = true
		rect.position = Vector2(0.0, wy)
		rect.size = Vector2(640.0, SimWorld.WATER_H * PX)
		var mat: ShaderMaterial = rect.material
		mat.set_shader_parameter("ford_center", (w["ford_x"] * PX) / 640.0)
		mat.set_shader_parameter("ford_halfw", (SimWorld.FORD_HALF_W * PX) / 640.0)
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
	for ty in 8:
		for tx in 10:
			var pos := Vector2(tx * 64.0, oy + ty * 64.0)
			var h := Art.cell_hash(tx, base_iy + ty)
			var shade := 0.48 + float(h % 7) * 0.024   # wider turf contrast
			canvas.draw_texture_rect(Art.tex("grass"), Rect2(pos, Vector2(64, 64)), false,
				Color(shade + march * 0.14, (shade + 0.06) * (1.0 - march * 0.4), shade * 0.82 * (1.0 - march * 0.35)))
			if h % 6 == 0:
				canvas.draw_texture_rect(Art.tex("dirt"), Rect2(pos + Vector2(6.0 + float(h % 7), 6.0 + float((h / 7) % 7)), Vector2(40.0 + float(h % 5) * 6.0, 34.0 + float(h % 4) * 6.0)), false,
					Color(0.58 - march * 0.18, 0.5 - march * 0.16, 0.38 - march * 0.1, 0.7))   # churned dirt, cinders late


func _process(_delta: float) -> void:
	# Sync the concussion overlay every rendered frame (covers gameplay, attract,
	# and pause — where _concussion is force-zeroed). Hidden at zero = pure no-op.
	if _screen_fx_rect == null:
		return
	var on := _concussion > 0.001
	_screen_fx_rect.visible = on
	if on:
		_screen_fx_mat.set_shader_parameter("concussion", _concussion)


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


func start_seed_from_clipboard() -> void:
	# CHALLENGE SEED: pull the seed out of the clipboard — accepts a bare integer or
	# a full share-card line ("... seed 12345"), grabbing the LAST digit run.
	var clip := DisplayServer.clipboard_get()
	var seed_str := ""
	for i in range(clip.length() - 1, -1, -1):
		var c := clip[i]
		if c >= "0" and c <= "9":
			seed_str = c + seed_str
		elif not seed_str.is_empty():
			break
	if seed_str.is_empty():
		_show_banner("CLIPBOARD HAS NO SEED")
		return
	start_seeded(seed_str.to_int())


func start_watch() -> void:
	# Watch Last Run: re-step the saved replay through the real draw pipeline — the
	# replay's recorded inputs drive the sim in _physics_process instead of the pad.
	# Reuses _reset() (via _seed_override) to build the matching sim; nothing recorded,
	# no bests banked. The whole record→replay path was built but never player-facing.
	var r := Replay.load_from("user://last_run.replay")
	if r == null or r.frames.is_empty():
		_show_banner("NO REPLAY SAVED YET")
		return
	_endless = r.mode == "endless"
	_two_players = r.player_count >= 2
	_seed_override = r.seed_value
	_reset()
	_watch_replay = r
	_watch_frame = 0
	_watching = true
	_show_banner("REPLAY — PRESS R TO EXIT", Color(0.55, 0.9, 1.0))


func _reset() -> void:
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
	_trauma = 0.0
	_hitstop_frames = 0
	_flash_alpha = 0.0
	_fx.clear()
	_pending_blasts.clear()
	_scorch.clear()
	_corpses.clear()
	_tank_hull.clear()
	_tank_prev.clear()
	_recoil = [Vector2.ZERO, Vector2.ZERO]
	_kick = Vector2.ZERO
	_kill_streak = 0
	_last_kill_frame = -100
	_rumble = 0.0
	_wheel = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]
	_damage_vignette = 0.0
	_banners.clear()
	_seen_bosses = {}
	_prev_colossus_phase = 0
	_hitmarker = [0.0, 0.0]
	_hit_dir_t = 0.0
	_record_fired = false
	_boss_ghost.clear()
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
	_last_gate_tick = 0
	_best_gate_split = 0
	_run_best_streak = 0
	_down_frames = 0
	_debrief = false


func _input(event: InputEvent) -> void:
	# Track the LAST-USED device so glyphs/legends teach the right buttons —
	# a merely-connected idle pad shouldn't override an active keyboard.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
			return
		Art.use_pad = true
	elif event is InputEventKey or event is InputEventMouse:
		Art.use_pad = false


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
				_menu.open(GameMenu.Mode.TITLE)
			else:
				_reset()
		elif event.keycode == KEY_C and (_debrief or sim.victory):
			_copy_share_text()


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
	var txt := "IKARI — SCORE %d · %s · RANK %s (%s) · seed %d" % [sim.score, where, rr.grade, rr.title, _current_seed]
	DisplayServer.clipboard_set(txt)
	_show_banner("COPIED TO CLIPBOARD")


func _notification(what: int) -> void:
	# One-death sim: alt-tabbing away keeps sim.step() ticking blind and hands the
	# player a death that reads as a bug, not a loss. Auto-open pause the instant the
	# window loses focus during live play. sim.step() is already gated behind
	# _menu.is_active(), so this is a pure view gate with zero sim contact — golden-safe.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# no_autopause: the screenshot harness runs unfocused by design — without
		# this every staged gameplay shot captures the pause overlay instead.
		if _menu.mode == GameMenu.Mode.HIDDEN and not sim.wiped and not sim.victory and not no_autopause:
			_menu.open(GameMenu.Mode.PAUSE)
			queue_redraw()


func _physics_process(_delta: float) -> void:
	Art.colorblind = colorblind   # apply on menu/attract frames too, not just gameplay
	if _menu.is_active():
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
			_update_feel()
		else:
			# Pause: clear the underwater LPF/duck so the menu sounds clean.
			_concussion = 0.0
			_duck = 0.0
			_sfx.set_concussion(0.0)
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
		_check_boss_intro()
		_track_bests()
	_update_feel()
	queue_redraw()
	_update_hud()


func _consume_events() -> void:
	var armor_pinged := false   # one ricochet ping per tick, not per bullet
	var boss_pinged := false    # one boss-hit ping per tick, not per bullet
	for ev in sim.events:
		var kind: String = ev["t"]
		if kind == "pickup":
			_sfx.play("buy" if ev.get("cost", 0) > 0 else "pickup", -5.0)
			# Rare power-up grab (pierce=4 / spread=5): a bold rising callout + a
			# celebratory kick so collecting a 1-in-6 drop lands as an event, not a
			# silent stat bump. floattext + sfx + trauma are all view-only.
			if ev.get("kind", 0) >= 4:
				var is_pierce: bool = ev["kind"] == 4
				_fx.append({"x": ev["x"], "y": ev["y"] - 6, "t": 0.0, "kind": "floattext",
					"rate": 0.013, "size": 13, "text": "PIERCING ROUNDS!" if is_pierce else "SPREAD SHOT!",
					"col": Color(0.55, 0.95, 1.0) if is_pierce else Color(1.0, 0.82, 0.45)})
				_trauma = minf(1.0, _trauma + 0.12)
				_sfx.play("buy", -2.0, 1.4)
		elif _EVENT_SOUND.has(kind):
			var snd: Array = _EVENT_SOUND[kind]
			_sfx.play(snd[0], snd[1], snd[2])
		match kind:
			"armor_block":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.3})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
					"sz": 8.0, "fade": 1.5, "rate": 0.15, "col": Color(0.15, 0.13, 0.12, 0.7)})
				_hint("armor", "GRENADES CRACK ARMOR — BUNKERS TAKE NO BULLETS")
				if not armor_pinged:
					armor_pinged = true
					_sfx.play("vest_break", -16.0, 1.7)
			"boss_hit":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "spark", "rate": 0.3})
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
					"sz": 8.0, "fade": 1.5, "rate": 0.15, "col": Color(0.15, 0.13, 0.12, 0.7)})
				_hitmarker[_hit_owner(ev["x"], ev["y"])] = 1.0
				_boss_flash = minf(1.0, _boss_flash + 0.35)   # the big body reacts, not just a spark
				if not boss_pinged:
					boss_pinged = true
					_sfx.play("vest_break", -10.0, 1.35)
			"dry_fire":
				if Engine.get_physics_frames() - _dry_frame >= 14:
					_dry_frame = Engine.get_physics_frames()
					_sfx.play("tank_board", -12.0, 2.2)
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
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "NEED COINS", "col": Color(1.0, 0.45, 0.35)})
			"shot":
				_ev_shot(ev)
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
			"kill":
				_ev_kill(ev)
			"bounty_kill":
				# Marked target down — a gold coin fountain + a distinct sting.
				_coin_pop(ev["x"], ev["y"], "BOUNTY +%d¢" % ev["coin"], 5, Color(1.0, 0.85, 0.3), 0.02)
				_sfx.play("buy", -3.0, 1.6)
			"frag_bonus":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.02, "text": "FRAG x%d" % ev["n"], "col": Color(1.0, 0.7, 0.35)})
				# One mini frag icon per kill (capped at 4) flung outward for the pop.
				for fk in mini(int(ev["n"]), 4):
					var fa := float(fk) * TAU / 3.0 + 0.4
					_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "fragpop",
						"rate": 0.03, "move": true, "spin": fa,
						"vx": cos(fa) * 2.2, "vy": sin(fa) * 2.2 - 0.8})
				_sfx.play("buy", -6.0, 1.2)
			"bunker_break":
				_ev_bunker_break(ev)
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
				_hint("revive", "FEED THE WAR CHEST TO REVIVE — [E] / [Y]")
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
			"roll":
				# Launch poof grounds the dodge.
				_burst(ev["x"], ev["y"], "dust", 4, 0.6, 1.4, 0.5, 0.08)
				var rp: Dictionary = sim.players[ev["i"]]
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_wind",
					"sz": 15.0, "grow": 0.4, "fade": 1.2, "rate": 0.05,
					"rot": Vector2(rp["aim_x"], rp["aim_y"]).angle(), "col": Color(1, 1, 1, 0.5)})
			"gate_flawless":
				# A disciplined, deathless checkpoint clear — gold payoff + sting,
				# louder as the clean-gate streak compounds.
				var fm: int = ev.get("mult", 1)
				var ftxt := "FLAWLESS  +%d¢  +%d" % [50 * fm, 2000 * fm]
				if fm > 1:
					ftxt = "FLAWLESS x%d  +%d¢  +%d" % [fm, 50 * fm, 2000 * fm]
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.016, "text": ftxt, "col": Color(1.0, 0.92, 0.45)})
				_sfx.play("buy", -3.0, 1.4 + fm * 0.08)
			"avenge":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "AVENGED +5¢", "col": Color(0.7, 0.9, 1.0)})
				_sfx.play("avenge", -5.0)
			"surge":
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
			"gate_open":
				_ev_gate_open(ev)
			"revive":
				_ev_revive(ev)
			"enemy_shot":
				# Incoming fire was audio-only — a brief red muzzle glow so you can
				# SEE where a shot left from in the chaos.
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.2,
					"r": 12.0, "col": Color(1.0, 0.4, 0.3)})
			"vest_break":
				_ev_vest_break(ev)
			"wave_start":
				var mod_name: String = ["", "  — BLITZ", "  — ELITE GUARD", "  — SPOTTER", "  — PAYDAY", "  — NIGHT OPS", "  — FRENZY"][ev.get("mod", 0)]
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
					"rate": 0.015, "text": "CLEAN WAVE  +40¢  +1500", "col": Color(0.5, 1.0, 0.7)})
				_sfx.play("buy", -3.0, 1.5)
			"courier_escape":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
					"rate": 0.03, "text": "GOT AWAY!", "col": Color(0.85, 0.78, 0.5)})
			"observer_spawn":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.025})
				_show_banner("MORTAR OBSERVER SPOTTED")
			"colossus_engage":
				_trauma = 1.0
				_hitstop_frames = maxi(_hitstop_frames, 8)
				_punch = maxf(_punch, 0.08)
				_music_hold = 48   # held breath before the finale
			"endless_boss":
				_trauma = minf(1.0, _trauma + 0.4)
				_music_hold = maxi(_music_hold, 48)
				_show_banner("GUNSHIP INBOUND")
				_sfx.play("alarm", -4.0, 0.9)
				# A fast attack-heli escort streaks the top band ahead of the boss.
				_fx.append({"x": 0, "y": 0, "t": 0.0, "kind": "chopper", "rate": 0.02,
					"tex": "m_heli_attack2", "scl": 0.5, "sy": 52.0})
			"core_open":
				_show_banner("CORE EXPOSED — OPEN FIRE")
				_sfx.play("alarm", -6.0, 1.3)
			"airstrike_called":
				# Commit beat: the strike is inbound, not instant — announce it.
				_show_banner("AIRSTRIKE INBOUND")
				_sfx.play("whistle", -3.0, 0.85)
			"wiped":
				# Whole squad down with no rescue — the endless run is over.
				_trauma = minf(1.0, _trauma + 0.6)
				_flash_alpha = maxf(_flash_alpha, 0.4)
				_hitstop_frames = maxi(_hitstop_frames, 8)
				_rumble = maxf(_rumble, 1.0)
				_show_banner("OVERRUN — RUN OVER")
				_sfx.play("wiped", -2.0)
			"victory":
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
		"t": 0.0, "kind": "muzzle", "rate": 0.34,
		"a": aim.angle() + randf_range(-0.09, 0.09), "szj": randf_range(0.82, 1.18)})
	# Textured muzzle bloom (legacy art Particle_FX soft-spot) under the line flash.
	_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 12), "y": ev["y"] + int(shooter["aim_y"] * 12),
		"t": 0.0, "kind": "tex", "tex": "fx_softspot", "sz": 12.0, "grow": 0.5, "fade": 1.7,
		"rate": 0.3, "col": Color(1.0, 0.92, 0.55, 0.65)})
	var perp := Vector2(-aim.y, aim.x) * (1.0 if randf() < 0.5 else -1.0)
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing",
		"rate": 0.055, "spin": randf() * TAU,
		"vx": perp.x * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4),
		"vy": perp.y * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4)})
	# Faint muzzle light on the ground (rate-capped so MG spam can't wash out).
	if Engine.get_physics_frames() % 2 == 0:
		_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 11), "y": ev["y"] + int(shooter["aim_y"] * 11),
			"t": 0.0, "kind": "light", "rate": 0.28, "r": 16.0,
			"col": Color(1.0, 0.9, 0.5)})


func _ev_explosion(ev: Dictionary) -> void:
	_trauma = minf(1.0, _trauma + 0.35)
	_hitstop_frames = maxi(_hitstop_frames, 4)
	_rumble = maxf(_rumble, 0.7)
	_punch = maxf(_punch, 0.05)
	_duck = maxf(_duck, 0.7)
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "explosion"})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.12})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.09,
		"r": 60.0, "col": Color(1.0, 0.7, 0.35)})
	# Textured hot-disc flash (legacy art fx_disc) over the procedural burst.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_disc",
		"sz": 30.0, "grow": 0.55, "fade": 1.8, "rate": 0.12, "col": Color(1.0, 0.82, 0.5, 0.85)})
	# Dark crater stamp bridges the instant flash and the slow-building scorch.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "tex", "tex": "fx_impactdark",
		"sz": 20.0, "grow": 0.2, "fade": 0.8, "rate": 0.02, "col": Color(1, 1, 1, 0.6)})
	var wet: bool = sim._in_water(ev["x"], ev["y"])
	_burst(ev["x"], ev["y"], "splash" if wet else "dust", 8, 1.5, 3.0, 0.3)
	_blast_debris(ev["x"], ev["y"], wet)
	if not wet:
		_scorch.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "r": randf_range(11.0, 16.0)})


func _ev_kill(ev: Dictionary) -> void:
	# No screen flash here: at kill-spam rates it strobes
	# (photosensitivity); smoke + gib burst + blip + coin carry it.
	# A per-type death throe + a fading corpse so a cleared field
	# reads as fought-over, not swept clean.
	var kkind: String = ev.get("kind", "rusher")
	var kwet: bool = sim._in_water(ev["x"], ev["y"])
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
		_sfx.play("splash", -10.0, 1.2)
		for d in 6:
			var wa := d * TAU / 6.0
			_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "splash", "rate": 0.08,
				"vx": cos(wa) * randf_range(0.8, 1.8), "vy": sin(wa) * randf_range(0.8, 1.8)})
	else:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "smoke"})
	# Directional gib/spark burst — the kill hits back.
	for g in 5:
		var ga := randf() * TAU
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "gib", "rate": 0.07,
			"vx": cos(ga) * randf_range(1.0, 2.6), "vy": sin(ga) * randf_range(1.0, 2.6),
			"spin": randf() * TAU})
	_hitmarker[_hit_owner(ev["x"], ev["y"])] = 1.0   # kill confirms on the shooter's reticle
	_run_kills += 1
	# Kill-streak: rising blip pitch + milestone combo pop.
	var big: bool = ev.get("coin", 0) >= 25
	if Engine.get_physics_frames() - _last_kill_frame < 90:
		_kill_streak += 1
	else:
		_kill_streak = 1
	_last_kill_frame = Engine.get_physics_frames()
	_sfx.play("kill", -7.0, 1.0 + minf(0.9, _kill_streak * 0.06))
	if big:
		_hitstop_frames = maxi(_hitstop_frames, 2)   # elites/bosses only
		_rumble = maxf(_rumble, 0.35)
		_punch = maxf(_punch, 0.03)
	if _kill_streak == 5 or _kill_streak == 10 or _kill_streak == 20:
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "floattext",
			"rate": 0.02, "text": "x%d STREAK" % _kill_streak, "col": Color(1.0, 0.75, 0.3)})
		_sfx.play("buy", -8.0, 1.0 + _kill_streak * 0.02)
	# Big bounties get a coin moment; rusher pennies would be spam.
	if big:
		_coin_pop(ev["x"], ev["y"], "+%d¢" % ev["coin"], 3, Color(1.0, 0.9, 0.45), 0.025)
	# A downed gunship is a finale, not a kill blip — ripple it apart.
	if kkind == "boss":
		_boss_death_finale(ev["x"], ev["y"])


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
	# Dark tumbling chunks thrown with wide speed variance — the blast throws material.
	for _d in 5:
		var da := randf() * TAU
		_fx.append({"x": x, "y": y, "t": 0.0, "kind": "gib", "rate": 0.05,
			"vx": cos(da) * randf_range(1.0, 4.5), "vy": sin(da) * randf_range(1.0, 4.5),
			"col": Color(0.2, 0.17, 0.14), "spin": randf() * TAU})
	# Secondary inner flash: a bright core that pops ~2 frames after the main flash.
	_fx.append({"x": x, "y": y, "t": -0.24, "kind": "flash", "rate": 0.16})
	# Slow rising smoke curl lingers after the fire.
	for _s in 2:
		_fx.append({"x": x + (randi() % 9 - 4) * Fixed.ONE, "y": y, "t": 0.0,
			"kind": "smoke", "rate": 0.035})


func _boss_death_finale(x: int, y: int) -> void:
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
	if not reduced:
		_rumble = maxf(_rumble, 1.0)
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
	# The one win-state of the whole run deserves a payoff: a gold
	# shockwave + light bloom off the wreck and a fountain of gold
	# confetti casings, not just a bare white flash.
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "shockwave", "rate": 0.08})
	_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "light", "rate": 0.05,
		"r": 80.0, "col": Color(1.0, 0.85, 0.4)})
	for d in 22:
		var vca := randf() * TAU
		_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing",
			"rate": 0.018, "spin": randf() * TAU,
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
		_show_banner("BRIDGE GUNSHIP")
		_sfx.play("alarm", -2.0, 0.85)
		_trauma = minf(1.0, _trauma + 0.3)
		_punch = maxf(_punch, 0.12)   # boss sighting gets a zoom hit, not just shake
		_music_hold = 48
	# Colossus escalation announcements.
	var phase := sim.colossus_phase()
	if phase > _prev_colossus_phase and phase >= 2:
		_show_banner("COLOSSUS ENRAGED — MORTAR VOLLEYS" if phase == 2
			else "COLOSSUS CRITICAL — SAPPERS OUT")
		_sfx.play("alarm", -3.0, 0.7)
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


func _persist(section: String, values: Dictionary) -> void:
	# Shared load-then-merge-then-save boilerplate: load first so sibling
	# sections ([best]/[hall]/[seen]/[settings]) already on disk never get
	# clobbered by a save that only knows about its own section.
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	for k in values:
		cf.set_value(section, k, values[k])
	_save_cfg(cf)


func _load_bests() -> void:
	var cf := ConfigFile.new()
	# Fall back to the .bak snapshot if the primary is missing/corrupt, before
	# giving up to zeros (a silent wipe).
	if cf.load(SAVE_PATH) == OK or cf.load(SAVE_BAK) == OK:
		best_score = cf.get_value("best", "score", 0)
		best_wave = cf.get_value("best", "wave", 0)
		best_dist = cf.get_value("best", "dist", 0)
		_seen = cf.get_value("seen", "hints", {})
		hall.assign(cf.get_value("hall", "runs", []))
		_life_runs = cf.get_value("life", "runs", 0)
		_life_kills = cf.get_value("life", "kills", 0)
		_life_wins = cf.get_value("life", "wins", 0)
		colorblind = cf.get_value("settings", "colorblind", false)
		_assist = cf.get_value("settings", "assist", false)
		_motion = 0.0 if cf.get_value("settings", "reduce_motion", false) else 1.0
		_rumble_on = cf.get_value("settings", "rumble", true)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"),
			cf.get_value("settings", "sfx_muted", false))
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"),
			cf.get_value("settings", "music_muted", false))


func _save_settings() -> void:
	# Persist only the [settings] keys; load-then-set so we never clobber
	# [best]/[hall]/[seen]. Called from the pause-menu a11y/audio toggles.
	_persist("settings", {
		"colorblind": colorblind,
		"assist": _assist,
		"reduce_motion": _motion < 0.5,
		"rumble": _rumble_on,
		"sfx_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"music_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
	})


func _record_run() -> void:
	# Bank the finished run into the top-8 Hall of Fame (by score).
	var opened := 0
	for g in sim.gates:
		if g["open"]:
			opened += 1
	hall.append({"score": sim.score, "mode": sim.mode, "wave": sim.wave,
		"sector": mini(opened + 1, 5), "dist": -Fixed.to_int(sim.camera_top) / 10,
		"streak": _run_best_streak, "won": sim.victory, "daily": _daily, "assist": _assist})
	hall.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	if hall.size() > 8:
		hall = hall.slice(0, 8)
	_persist("hall", {"runs": hall})
	_life_runs += 1
	_life_kills += _run_kills
	if sim.victory:
		_life_wins += 1
	_persist("life", {"runs": _life_runs, "kills": _life_kills, "wins": _life_wins})


func _hint(id: String, text: String) -> void:
	# Fire a just-in-time onboarding cue the FIRST time ever, then never again.
	# Never during attract mode — the demo bot would burn every hint to disk
	# before the player ever plays.
	if _menu.mode == GameMenu.Mode.TITLE:
		return
	if _seen.get(id, false):
		return
	_seen[id] = true
	_hint_queue.append(text)
	_persist("seen", {"hints": _seen})


func _track_bests() -> void:
	_run_best_streak = maxi(_run_best_streak, _kill_streak)
	# Supply-wheel discoverability: the first time the chest can afford the
	# cheapest buy, nudge the player toward the hold-to-open wheel.
	if sim.war_chest >= SimWorld.SHOP_AMMO_COST:
		_hint("supply", "HOLD [Q] / BACK FOR THE SUPPLY WHEEL")
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
				_recorder.save("user://last_run.replay")   # replayable capture of the finished run
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
		best_wave = sim.wave
		_best_dirty = true
	var dist := -Fixed.to_int(sim.camera_top) / 10
	if sim.mode == "campaign" and dist > best_dist:
		best_dist = dist
		_best_dirty = true
	if _best_dirty and Engine.get_physics_frames() % 60 == 0:
		_best_dirty = false
		_persist("best", {"score": best_score, "wave": best_wave, "dist": best_dist})


func _show_banner(text: String, col := Color(1.0, 0.92, 0.55)) -> void:
	_banners.append({"text": text, "t": 1.0, "col": col})


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
	if Engine.get_physics_frames() - _dodge_frame >= 24:
		for b in sim.enemy_bullets:
			for p in sim.players:
				if not p["alive"] or p["roll_ticks"] == 0:
					continue
				if sim._dist_lte(b["x"], b["y"], p["x"], p["y"], 11 * Fixed.ONE):
					_dodge_frame = Engine.get_physics_frames()
					_show_banner("PERFECT DODGE!", Color(0.5, 0.95, 1.0))
					_hitstop_frames = maxi(_hitstop_frames, 3)
					_sfx.play("buy", -4.0, 1.8)
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
				_sfx.play("whiz", -13.0, randf_range(0.95, 1.1))
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
	for b in sim.enemy_bullets:
		var d: int = (b["x"] - px) * (b["x"] - px) + (b["y"] - py) * (b["y"] - py)
		if d < best:
			best = d
			dir = Vector2(b["x"] - px, b["y"] - py)
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var d2: int = (e["x"] - px) * (e["x"] - px) + (e["y"] - py) * (e["y"] - py)
		if d2 < best:
			best = d2
			dir = Vector2(e["x"] - px, e["y"] - py)
	# Mortar strikes and the colossus crush kill too — a wedge that only
	# scanned bullets/infantry pointed at the wrong threat for those deaths.
	for s in sim.strikes:
		var ds: int = (s["x"] - px) * (s["x"] - px) + (s["y"] - py) * (s["y"] - py)
		if ds < best:
			best = ds
			dir = Vector2(s["x"] - px, s["y"] - py)
	if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
		var cx: int = sim.colossus["x"] - px
		var cy: int = sim.colossus["y"] - py
		if cx * cx + cy * cy < best:
			dir = Vector2(cx, cy)
	if dir.length() > 1.0:
		_hit_dir = dir.normalized()
		_hit_dir_t = 1.0
		_hit_dir_player = pidx
		if pidx >= 0 and pidx < _hit_flinch.size():
			_hit_flinch[pidx] -= _hit_dir * 3.0   # shove the body AWAY from the source


func _update_feel() -> void:
	_trauma = maxf(0.0, _trauma - 0.03)
	# Impact envelopes decay multiplicatively (fast drop, long tail) so hits snap;
	# linear release reads flat. Floors avoid a lingering near-zero tail.
	_flash_alpha = _flash_alpha * 0.7 if _flash_alpha > 0.01 else 0.0
	_damage_vignette = maxf(0.0, _damage_vignette - 0.02)
	if not _banners.is_empty():
		_banners[0]["t"] -= 0.008
		if _banners[0]["t"] <= 0.0:
			_banners.pop_front()
	for _hi in _hitmarker.size():
		_hitmarker[_hi] = _hitmarker[_hi] * 0.6 if _hitmarker[_hi] > 0.01 else 0.0
	_hit_dir_t = maxf(0.0, _hit_dir_t - 0.03)
	_punch = _punch * 0.82 if _punch > 0.002 else 0.0
	_fade = maxf(0.0, _fade - 0.06)
	_duck = maxf(0.0, _duck - 0.05)
	_concussion = maxf(0.0, _concussion - 0.035)
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
	for i in range(_fx.size() - 1, -1, -1):
		var fx := _fx[i]
		fx["t"] += fx.get("rate", 0.09)
		if fx["kind"] == "casing" or fx["kind"] == "gib" or fx["kind"] == "dust" or fx.get("move", false):
			fx["x"] += int(fx["vx"] * Fixed.ONE)
			fx["y"] += int(fx["vy"] * Fixed.ONE)
			fx["vx"] *= 0.86
			fx["vy"] *= 0.86
		if fx["t"] >= 1.0:
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
			if _motion >= 0.5:
				_trauma = minf(1.0, _trauma + 0.12)
				_rumble = maxf(_rumble, 0.4)
			_pending_blasts.remove_at(i)
	for i in range(_scorch.size() - 1, -1, -1):
		_scorch[i]["t"] += 0.012
		if _scorch[i]["t"] >= 1.0:
			_scorch.remove_at(i)
	for i in range(_corpses.size() - 1, -1, -1):
		_corpses[i]["t"] += 0.004   # linger ~4s
		if _corpses[i]["t"] >= 1.0:
			_corpses.remove_at(i)
	while _corpses.size() > 40:     # cap the field's body count
		_corpses.remove_at(0)
	for i in _recoil.size():
		_recoil[i] *= 0.72
		if i < _hit_flinch.size():
			_hit_flinch[i] *= 0.8
	for i in _heat.size():
		_heat[i] = maxf(0.0, _heat[i] - 0.02)
	_boss_flash = _boss_flash * 0.8 if _boss_flash > 0.01 else 0.0
	for i in mini(_down_anim.size(), sim.players.size()):
		if sim.players[i]["alive"]:
			_down_anim[i] = 0.0
		else:
			_down_anim[i] = minf(1.0, _down_anim[i] + 0.12)
	_kick *= 0.78
	# Gamepad rumble: one pooled pulse per frame across connected pads.
	if _rumble > 0.01:
		if _rumble_on:
			for pad in Input.get_connected_joypads():
				Input.start_joy_vibration(pad, _rumble * 0.4, _rumble, 0.12)
		_rumble = 0.0
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
	var rot := sin(float(Engine.get_physics_frames()) * 2.9) * _trauma * _trauma * 0.035 * _motion
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
	_sfx.set_music_intensity(intensity, _duck)
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
	var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var ky := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
	var ax := (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
	var ay := (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0)
	# Explicit aim only (arrow keys / pad stick, NOT the mouse fallback) — the
	# spend-wheel selects from this so tapping Q with the mouse off-center
	# can't auto-buy on release.
	var wheel_dir := Vector2(ax, ay)
	var pad_move := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
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
	p1.fire = Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	p1.grenade = Input.is_physical_key_pressed(KEY_SHIFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	p1.roll = Input.is_physical_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	p1.interact = Input.is_physical_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	p1.revive = Input.is_physical_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	p1.buy = _update_wheel(0,
		Input.is_physical_key_pressed(KEY_Q) or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK),
		wheel_dir, Vector2(kx, ky))
	inputs.append(p1)

	if _two_players:
		var p2 := SimInput.new()
		var p2_move := _pad_deadzone(Vector2(
			Input.get_joy_axis(1, JOY_AXIS_LEFT_X), Input.get_joy_axis(1, JOY_AXIS_LEFT_Y)), 0.2)
		var p2_aim := _pad_deadzone(Vector2(
			Input.get_joy_axis(1, JOY_AXIS_RIGHT_X), Input.get_joy_axis(1, JOY_AXIS_RIGHT_Y)), 0.25)
		p2.move_x = _quantize_axis(p2_move.x)
		p2.move_y = _quantize_axis(p2_move.y)
		p2.aim_x = _quantize_axis(p2_aim.x)
		p2.aim_y = _quantize_axis(p2_aim.y)
		p2.fire = Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
			or Input.is_joy_button_pressed(1, JOY_BUTTON_RIGHT_SHOULDER)
		p2.grenade = Input.is_joy_button_pressed(1, JOY_BUTTON_LEFT_SHOULDER)
		p2.roll = Input.is_joy_button_pressed(1, JOY_BUTTON_B)
		p2.interact = Input.is_joy_button_pressed(1, JOY_BUTTON_X)
		p2.revive = Input.is_joy_button_pressed(1, JOY_BUTTON_Y)
		p2.buy = _update_wheel(1, Input.is_joy_button_pressed(1, JOY_BUTTON_BACK),
			p2_aim, p2_move)
		inputs.append(p2)
	return inputs


func _update_wheel(i: int, held: bool, aim: Vector2, move: Vector2) -> int:
	## Hold to open, flick aim (or move) to pick a sector, release to buy.
	## Selection is sticky; releasing with nothing picked cancels. Returns the
	## SimInput.buy value (kind + 1) for exactly one tick on purchase.
	var w := _wheel[i]
	if held:
		w["open"] = true
		var dir := aim if aim.length() > 0.3 else move
		if dir.length() > 0.3:
			var new_sel := int(round(fposmod(dir.angle(), TAU) / (TAU / 4.0))) % 4
			if new_sel != w["sel"]:
				_sfx.play("pickup", -16.0, 1.5)   # hover tick confirms the flick
			w["sel"] = new_sel
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


# 4 diagonal offsets cover both axes at once — visually ≈ the old 8-neighbor rim
# at half the draw calls (~60 of 90 textures are outlined; this is the hot loop).
const _OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
]

# Pre-built frame names — "explosion%d" % frame allocated a String per particle per frame.
const _EXPLO_NAMES := ["explosion0", "explosion1", "explosion2", "explosion3"]

# FX kinds that emit light: drawn by _draw_glow on the additive layer, skipped by _draw_fx.
const _GLOW_KINDS := {"muzzle": true, "spark": true, "shockwave": true,
	"light": true, "ember": true, "flash": true}

# Corpse sprite per enemy kind — mirrors the live-draw choices in _draw_enemies.
const _CORPSE_TEX := {"rusher": "rusher", "elite": "elite", "sniper": "m_contractor2",
	"grenadier": "m_soldier2", "shield": "m_bombsuit", "sapper": "rusher",
	"courier": "rusher", "frogman": "frogman", "ghillie": "frogman"}


func _spr(tex_name: String, pos: Vector2, angle := 0.0, spr_scale := 1.0, mod := Color.WHITE,
		stretch := 1.0) -> void:
	var t: Texture2D = Art.tex(tex_name)
	var s := spr_scale * Art.draw_scale(tex_name)
	var tint := mod * Art.tint(tex_name)
	draw_set_transform(pos, angle, Vector2(s, s * stretch))
	var origin := -t.get_size() / 2.0
	if Art.outlined(tex_name):
		# 1.4px screen-space dark rim so units/vehicles read on any ground.
		var oc := Color(0.05, 0.06, 0.04, tint.a)
		var d := 1.1 / s
		for o in _OUTLINE_OFFSETS:
			draw_texture(t, origin + o * d, oc)
	draw_texture(t, origin, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _aim_angle(p: Dictionary) -> float:
	return atan2(p["aim_y"] * PX, p["aim_x"] * PX)


func _ground_shadow(pos: Vector2, r: float) -> void:
	# Soft flattened drop-shadow so units/vehicles sit ON the ground instead of
	# floating over it — a legacy art soft-dark card (fx_shadow) with baked falloff
	# replaces the hard-edged squashed circle, so the shadow edge feathers out.
	var sh := Art.tex("fx_shadow")
	var ss := (r * 1.15) / (sh.get_size().x * 0.5)
	draw_set_transform(pos + Vector2(0, r * 0.32), 0.0, Vector2(ss, ss * 0.45))
	draw_texture(sh, -sh.get_size() / 2.0, Color(0.0, 0.03, 0.0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	# Position the water shader quads under the world and requeue the grass base.
	# Driven from _draw (not _process) so it also runs under the screenshot harness,
	# which disables main's processing but still calls queue_redraw(). The 1-frame
	# lag on _bg_root's requeue only affects decorative grass tiling — the water
	# quads themselves are positioned in-frame here, so they stay aligned to units.
	_sync_water()
	if _bg_root != null:
		_bg_root.queue_redraw()
	if _glow_root != null:
		_glow_root.queue_redraw()
	_draw_terrain()
	_draw_skyglow()
	_draw_scorch()
	_draw_water()
	_draw_mines()
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
			var is_locker := false
			for lk in lockers:
				if is_same(lk, bk):
					is_locker = true
					break
			if is_locker:
				var lp := Art.pulse(0.15)
				draw_arc(c, 26.0, 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.4 + lp * 0.4), 2.0)
			_ground_shadow(c, 17.0)
			_spr("bunker", c, 0.0, 0.78)
			# A recon drone loiters above an active strongpoint — a small orbiting
			# silhouette that reads the bunker as 'watched'. Phase offset per bunker
			# so multiples don't fly in lockstep. Pure ambient view.
			var da := float(Engine.get_physics_frames()) * 0.03 + float(bk["x"] / 4096)
			var dp := c + Vector2(cos(da) * 15.0, sin(da) * 7.0 - 22.0)
			_spr("m_drone", dp, da + PI / 2, 0.4)
	_draw_pickups()
	_draw_tanks()
	_draw_enemies()
	_draw_threat_pips()
	_draw_observer()
	_draw_gunships()
	_draw_colossus()
	_draw_projectiles()
	_draw_players()
	_draw_fx()
	_draw_telegraphs()
	_draw_threat_edges()
	_draw_objective_markers()
	_draw_progress_rail()
	_draw_wheel()
	var top_msg := _top_center_priority()
	_draw_airstrike_telegraph(top_msg)
	_draw_banners(top_msg)


func _draw_skyglow() -> void:
	# Foundry skyglow: as the run pushes toward the finale a warm forge-light bleeds
	# over the top edge — "something huge is burning ahead", a light source above the
	# field rather than just the ground recolor. Near-free when the march is low.
	var march := _sector_march()
	if march < 0.15:
		return
	var glow := (march - 0.15) / 0.85
	var pul := 1.0 if _motion < 0.5 else (0.85 + 0.15 * Art.pulse(0.1))
	var gcol := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.3, 0.15), glow)
	for b in 5:
		var h := 8.0 + b * 7.0
		var a := glow * 0.16 * (1.0 - b / 5.0) * pul
		draw_rect(Rect2(0, 0, SCREEN_W, h), Color(gcol.r, gcol.g, gcol.b, a))


func _sector_march() -> float:
	# Sector march: the ground shifts jungle-olive → ashen/scorched as the run
	# pushes toward the Foundry finale (campaign: opened gates; endless: wave).
	if sim.mode == "campaign":
		var mopened := 0
		for g in sim.gates:
			if g["open"]:
				mopened += 1
		return clampf(float(mopened) / 5.0, 0.0, 1.0)
	return clampf(float(sim.wave) / 12.0, 0.0, 1.0)


func _draw_terrain() -> void:
	# World-anchored grass tiling, darkened toward jungle; deterministic dirt
	# patches and tree lines from a cell hash (decor only, not sim state).
	# The opaque grass/dirt base moved to _paint_bg (renders on _bg_root, below the
	# water quads). Everything below still draws in _draw() over the water.
	var cam_y := sim.camera_top * PX
	var oy := -fposmod(cam_y, 64.0)
	# Drifting cloud shadows: large soft dark blobs scrolling diagonally at a
	# slower rate than the camera — instant depth, the jungle feels alive.
	var ct := float(Engine.get_physics_frames()) * 0.15
	for c in 3:
		var cxw := fposmod(ct * (0.6 + c * 0.2) + c * 260.0, 900.0) - 130.0
		var cyw := fposmod(-cam_y * 0.35 + c * 190.0 + ct * 0.3, 620.0) - 130.0
		draw_circle(Vector2(cxw, cyw), 90.0 + c * 22.0, Color(0.0, 0.02, 0.0, 0.05))
		draw_circle(Vector2(cxw + 40, cyw + 24), 70.0, Color(0.0, 0.02, 0.0, 0.045))
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
	var ash := clampf(_sector_march() * 0.65, 0.0, 0.65)
	var fern_col := Color(0.82, 0.92, 0.72).lerp(Color(0.6, 0.52, 0.42), ash)
	var tree_col := Color(0.75, 0.85, 0.72).lerp(Color(0.55, 0.5, 0.44), ash)
	# Low fern understory scattered through the field (hash decorrelated from
	# the tree grid so ferns and trees don't stack on the same cell).
	for ty in 10:
		var fy := oy + ty * 40.0
		var fiy := int(floor((cam_y + fy) / 40.0))
		for tx in 16:
			var hf := Art.cell_hash(tx * 17 + 5, fiy * 3)
			if hf % 5 != 0:
				continue
			var fx := tx * 42.0 + float(hf % 20) - 10.0
			var fy_px := fy + float((hf / 5) % 16)
			if sim._in_water(int(fx / PX), sim.camera_top + int(fy_px / PX)):
				continue
			var fsway := sin(float(Engine.get_physics_frames()) * 0.045 + float(hf)) * 0.07
			_spr("fern", Vector2(fx, fy_px), float(hf % 628) / 100.0 + fsway,
				0.28 + float(hf % 3) * 0.03, fern_col)

	# Jungle tree lines on the flanks, sparse singles in the field.
	for ty in 9:
		var wy := oy + ty * 48.0
		var iy := int(floor((cam_y + wy) / 48.0))
		for tx in 14:
			var h2 := Art.cell_hash(tx * 31, iy)
			var margin: bool = tx < 2 or tx > 11
			if (margin and h2 % 3 != 0) or (not margin and h2 % 19 == 0):
				var px := tx * 48.0 + float(h2 % 24) - 12.0
				var wy_px := wy + float((h2 / 7) % 20)
				var world_x := int(px / PX)
				var world_y := sim.camera_top + int(wy_px / PX)
				if sim._in_water(world_x, world_y):
					continue
				var big := h2 % 5 == 0
				var tsway := sin(float(Engine.get_physics_frames()) * 0.03 + float(h2)) * 0.04
				_spr("tree_large" if big else "tree_small", Vector2(px, wy_px),
					float(h2 % 628) / 100.0 + tsway, 0.42 if big else 0.34, tree_col)

	# War-torn battlefield litter: sparse, deterministic scatter of the
	# legacy art Military props (barrels, crates, wrecks, rocks, wire, tents).
	# Hash grid decorrelated from trees/ferns so nothing stacks on a cell.
	for ty in 6:
		var ly := oy + ty * 80.0
		var liy := int(floor((cam_y + ly) / 80.0))
		for tx in 8:
			var hl := Art.cell_hash(tx * 53 + 11, liy * 7 + 3)
			if hl % 9 != 0:   # ~1 in 9 cells gets a prop
				continue
			var lx := tx * 84.0 + float(hl % 40) - 20.0
			var ly_px := ly + float((hl / 9) % 40)
			if sim._in_water(int(lx / PX), sim.camera_top + int(ly_px / PX)):
				continue
			_spr(_LITTER[(hl / 40) % _LITTER.size()], Vector2(lx, ly_px),
				float(hl % 628) / 100.0, 1.0)


func _draw_mines() -> void:
	for m in sim.mines:
		if not m["armed"]:
			continue
		var mp := _to_screen(m["x"], m["y"])
		# Danger telegraph keeps the mine FAIR: a pulsing red ring + a blinking
		# armed-indicator so you can spot it and herd rushers onto it (or route
		# around it yourself).
		var mb := Art.pulse(0.1)
		draw_circle(mp, 8.0 + mb * 3.0, Color(0.9, 0.2, 0.15, 0.14 + mb * 0.12))
		draw_arc(mp, 7.0 + mb * 2.0, 0, TAU, 16, Color(1.0, 0.35, 0.2, 0.5 + mb * 0.3), 1.2)
		# Real claymore silhouette (was the plain 'landmine' decor pip). Scale 1.05
		# ~= the old 4.5x0.07 effective size, so the footprint is unchanged.
		_spr("wep_claymore", mp, 0.0, 1.05)
		draw_circle(mp, 2.0, Color(0.95, 0.3, 0.18, 0.65 + mb * 0.35))


func _draw_water() -> void:
	for w in sim.waters:
		var wy := _to_screen(0, w["y"]).y
		var wh := SimWorld.WATER_H * PX
		# Water body, wave ripples and sun glint are the water.gdshader quad synced
		# under the units by _sync_water(); here we only draw what sits ON the water.
		# Banks (drawn over the shader's shore edges).
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy - 6, 640, 8), true, Color(0.9, 0.85, 0.7))
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy + wh - 2, 640, 8), true, Color(0.9, 0.85, 0.7))
		# The dry ford.
		var ford_left: float = (w["ford_x"] - SimWorld.FORD_HALF_W) * PX
		var ford_w := SimWorld.FORD_HALF_W * 2.0 * PX
		draw_texture_rect(Art.tex("sand"), Rect2(ford_left, wy - 2, ford_w, wh + 4),
			true, Color(0.85, 0.8, 0.65))
		# A few deterministic rocks break up the deep water (never in the ford).
		var wseed := Art.cell_hash(int(w["y"] / 4096) * 13, 7)
		for r in 3:
			var rx := float((wseed / (r + 2)) % 600 + 20)
			if rx > ford_left - 12.0 and rx < ford_left + ford_w + 12.0:
				continue
			var ry := wy + wh * (0.3 + 0.4 * float((wseed / (r + 5)) % 90) / 90.0)
			_spr("rock1" if (wseed + r) % 2 == 0 else "rock2", Vector2(rx, ry),
				float((wseed / (r + 1)) % 628) / 100.0, 1.4, Color(0.5, 0.58, 0.6))
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
			draw_string(ThemeDB.fallback_font, Vector2(ford_left + ford_w / 2.0 - 12, wy - 8),
				"FORD", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.6, 1.0, 0.6))


func _draw_gates() -> void:
	for g in sim.gates:
		var gy := _to_screen(0, g["y"]).y
		if g["open"]:
			for i in 2:
				_spr("sandbag_beige", Vector2(24 + i * 592, gy), 0.0, 0.6, Color(0.7, 0.68, 0.62))
		else:
			for i in 14:
				_spr("sandbag_beige", Vector2(24 + i * 46, gy), 0.0, 0.72)
			# Lock pips: how many of the two locking bunkers are still up —
			# turns a black-box wall into 'one down, one to go'.
			if not g.get("b1", {}).is_empty():
				var down := int(not g["b1"]["alive"]) + int(not g["b2"]["alive"])
				for k in 2:
					var lit: bool = k >= down
					draw_circle(Vector2(300 + k * 40, gy), 5.0,
						Color(1.0, 0.3, 0.2) if lit else Art.safe(Color(0.3, 0.7, 0.3)))
					draw_arc(Vector2(300 + k * 40, gy), 5.0, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)


func _draw_pickups() -> void:
	for pk in sim.pickups:
		var ppos := _to_screen(pk["x"], pk["y"])
		var tex_name: String
		var mod := Color.WHITE
		match pk["kind"]:
			0: tex_name = "crate_ammo"
			1: tex_name = "crate_grenade"
			2:
				tex_name = "crate_ammo"
				mod = Color(0.6, 0.7, 1.4)   # vest = blue-shifted barrel
			4: tex_name = "wep_rifle"        # Piercing Rounds capsule (elite drop)
			5: tex_name = "wep_shotgun"      # Trench Gun / Spread capsule (elite drop)
			_: tex_name = "crate_airstrike"
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
		_spr(tex_name, ppos, 0.0, 0.55, mod)
		# Identity glyph floats above every crate (the vest crate reuses the
		# ammo sprite, so it's ambiguous without this).
		if pk["kind"] >= 4:
			# Rare power-up capsule (pierce/spread): a pulsing glow + ring + rising
			# beam + label so a 1-in-6 elite drop stands out in the chaos (and the
			# out-of-range glyph lookup below is skipped — those kinds have no icon).
			var pcol := Color(0.5, 0.9, 1.0) if pk["kind"] == 4 else Color(1.0, 0.8, 0.45)
			var pg := Art.pulse(0.18)
			draw_circle(ppos, 7.0 + pg * 2.0, Color(pcol.r, pcol.g, pcol.b, 0.18 + pg * 0.12))
			draw_arc(ppos, 9.0, 0, TAU, 20, Color(pcol.r, pcol.g, pcol.b, 0.6 + pg * 0.3), 1.5)
			draw_line(ppos, ppos - Vector2(0, 15.0 + pg * 4.0), Color(pcol.r, pcol.g, pcol.b, 0.3), 2.0)
			Art.text(self, "PIERCE" if pk["kind"] == 4 else "SPREAD", ppos + Vector2(-13, -24), 8, pcol)
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
		_ground_shadow(c, 15.0)
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
		# Barrel follows the driver's aim; parked barrel points up.
		var barrel_angle := -PI / 2
		if t["occupant"] >= 0:
			barrel_angle = _aim_angle(sim.players[t["occupant"]])
		_spr("tank_barrel", c + Vector2.from_angle(barrel_angle) * 10.0, barrel_angle + PI / 2, 0.62, burn_mod)
		# Low-fuel telegraph: sputter smoke + warning before the ignite, so a
		# cruising tank doesn't abruptly become 'on fire, 3s to live'.
		if not t["burning"] and t["occupant"] >= 0 and t["fuel"] < 300:
			if (Engine.get_physics_frames() / 8) % 2 == 0:
				_spr("fx_smoke", c + Vector2(randf_range(-4, 4), -12), 0.0, 0.3,
					Color(0.5, 0.5, 0.5, 0.5))
			if (Engine.get_physics_frames() / 14) % 2 == 0:
				Art.text(self, "LOW FUEL", c + Vector2(-16, -26), 8, Color(1.0, 0.7, 0.2))
		if t["burning"]:
			_spr("fx_smoke", c + Vector2(4, -14), 0.0, 0.5, Color(1, 1, 1, 0.75))
			# Bail-out countdown: the hidden ~3s lethal timer, made visible.
			var bail := float(t["burn_ticks"]) / float(SimWorld.TANK_BAIL_TICKS)
			var bc := Color(1.0, 0.35, 0.2) if bail > 0.35 else Color(1.0, 0.85, 0.2)
			draw_arc(c, 20.0, -PI / 2, -PI / 2 + TAU * bail, 28, bc, 2.5)
		elif t["occupant"] < 0:
			Art.draw_glyph(self, "interact", c + Vector2(0, -30), 11.0)
		# Cannon reload ring: the trigger isn't dead, it's cycling.
		if t["occupant"] >= 0 and t["fire_cd"] > 0:
			var rdy := 1.0 - float(t["fire_cd"]) / float(SimWorld.TANK_FIRE_COOLDOWN_TICKS)
			draw_arc(c, 17.0, -PI / 2, -PI / 2 + TAU * rdy, 24, Color(1.0, 0.8, 0.4, 0.6), 2.0)


func _draw_enemies() -> void:
	# ≤2 alive players, cached once — replaces an O(players) sim scan per enemy
	# per frame that existed purely to pick a facing/laser target.
	var alive_players: Array[Dictionary] = []
	for p in sim.players:
		if p["alive"]:
			alive_players.append(p)
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var epos := _to_screen(e["x"], e["y"])
		# No shadow for water frogmen, nor for a still-cloaked ghillie (the shadow
		# would give the ambush away — the laser paint is the only warning).
		if e["kind"] != "frogman" and not (e["kind"] == "ghillie" and e.get("submerged", false)):
			_ground_shadow(epos, 6.0)
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
		if e["kind"] != "frogman":
			if e.get("windup", 0) == 0:
				epos.y += absf(sin(float(Engine.get_physics_frames()) * 0.35 + float(e["x"] / 4093))) * -1.4
			else:
				# Winding up: the run-bob stops but a slow breath keeps the unit alive —
				# nothing on the field should be a frozen statue.
				epos.y += sin(float(Engine.get_physics_frames()) * 0.12 + float(e["x"] / 4093)) * -0.5
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
		if e["kind"] == "frogman":
			var st: int = e.get("surface_ticks", 0)
			if e["submerged"]:
				# Idle ripple loop so occupied water reads as occupied.
				var ph := float((Engine.get_physics_frames() + e["x"] / 7919) % 90) / 90.0
				draw_arc(epos, 4.0 + ph * 9.0, 0, TAU, 16, Color(0.6, 0.8, 0.9, 0.4 * (1.0 - ph)), 1.0)
				draw_arc(epos, 5.0, 0, TAU, 12, Color(0.6, 0.8, 0.9, 0.55), 1.5)
				_spr("frogman", epos, face, 0.4, Color(0.5, 0.8, 0.8, 0.35))
			elif st > 0:
				# Surfacing telegraph: bold ripple burst + the body rising up.
				var sfrac := 1.0 - float(st) / float(SimWorld.FROGMAN_SURFACE_TICKS)
				for k in 2:
					draw_arc(epos, 6.0 + sfrac * 14.0 + k * 5.0, 0, TAU, 20,
						Color(0.85, 0.95, 1.0, 0.7 - k * 0.25 - sfrac * 0.3), 2.0)
				_spr("frogman", epos, face, 0.4 + sfrac * 0.1,
					Color(0.7, 0.9, 0.95, 0.4 + sfrac * 0.6))
			else:
				_spr("frogman", epos, face, 0.5)
		elif e["kind"] == "sniper":
			# Paints a laser line on its target during the long windup — the
			# 'get off this line NOW' telegraph. Break LOS or sidestep.
			var swu: int = e.get("windup", 0)
			if swu > 0 and not target.is_empty():
				var tp := _to_screen(target["x"], target["y"])
				var pf := 1.0 - float(swu) / float(SimWorld.SNIPER_WINDUP_TICKS)
				# Final moments: strobe white (matches the mortar-telegraph grammar).
				var lcol := Color(1.0, 0.15, 0.12, 0.35 + pf * 0.5)
				if swu <= 10 and (swu / 2) % 2 == 0:
					lcol = Color(1.0, 1.0, 1.0, 0.95)
				draw_line(epos, tp, lcol, 1.0 + pf * 2.0)
				draw_circle(tp, 2.0 + pf * 3.0, Color(lcol.r, lcol.g, lcol.b, 0.4 + pf * 0.5))
			var ssw := (1.0 + (1.0 - float(swu) / float(SimWorld.SNIPER_WINDUP_TICKS)) * 0.14) if swu > 0 else 1.0
			_spr("m_contractor2", epos, face, 0.5 * ssw, Color(1.1, 0.6, 1.2))   # spec-ops marksman, violet-keyed
		elif e["kind"] == "grenadier":
			var gwu: int = e.get("windup", 0)
			if gwu > 0:
				var gf := 1.0 - float(gwu) / float(SimWorld.GRENADIER_WINDUP_TICKS)
				draw_circle(epos + Vector2(0, -6), 2.0 + gf * 3.0, Color(1.0, 0.7, 0.2, 0.4 + gf * 0.5))
			var gsw := (1.0 + (1.0 - float(gwu) / float(SimWorld.GRENADIER_WINDUP_TICKS)) * 0.14) if gwu > 0 else 1.0
			_spr("m_soldier2", epos, face, 0.52 * gsw, Color(1.3, 1.1, 0.55))   # amber lobber, own silhouette
		elif e["kind"] == "courier":
			# Fleeing supply runner: gold-tinted, a bobbing loot sack overhead +
			# a pulsing ring so "catch this one" reads across the field.
			_spr("rusher", epos, face, 0.5, Color(1.4, 1.15, 0.4))
			var lb := Art.pulse(0.2)
			draw_arc(epos, 9.0 + lb * 1.5, 0, TAU, 16, Color(1.0, 0.85, 0.3, 0.4 + lb * 0.25), 1.3)
			draw_circle(epos + Vector2(0, -11 - lb * 1.5), 2.6, Color(1.0, 0.85, 0.3))
		elif e["kind"] == "shield":
			_spr("m_bombsuit", epos, face, 0.55, Color(0.85, 0.9, 1.0))   # armored EOD bulk sells the block
			# The riot shield: a bright arc across the front — this side deflects.
			draw_arc(epos, 11.0, face - 1.05, face + 1.05, 14, Color(0.7, 0.85, 1.0, 0.95), 3.0)
			draw_arc(epos, 11.0, face - 1.05, face + 1.05, 14, Color(0.3, 0.5, 0.8, 0.6), 5.0)
		elif e["kind"] == "sapper":
			# Mine-layer EOD: a warm-tinted insurgent with a pulsing armed-satchel
			# pip so "he's seeding the ground behind him" reads before the trail does.
			_spr("rusher", epos, face, 0.5, Color(1.5, 1.05, 0.5))
			var spp := Art.pulse(0.25)
			draw_circle(epos + Vector2(0, 3), 1.8 + spp * 0.8, Color(1.0, 0.5, 0.15, 0.7 + spp * 0.3))
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
				_spr("frogman", epos, face, 0.42 + rf * 0.08, Color(0.7, 0.85, 0.5, 0.4 + rf * 0.6))
			else:
				# Revealed marksman: paints the sniper line during windup, then fires.
				if gwu2 > 0 and not target.is_empty():
					var tp2 := _to_screen(target["x"], target["y"])
					var pf2 := 1.0 - float(gwu2) / float(SimWorld.SNIPER_WINDUP_TICKS)
					draw_line(epos, tp2, Color(1.0, 0.15, 0.12, 0.35 + pf2 * 0.5), 1.0 + pf2)
					draw_circle(tp2, 2.0 + pf2 * 2.0, Color(1.0, 0.2, 0.15, 0.4 + pf2 * 0.4))
				_spr("frogman", epos, face, 0.5, Color(0.7, 0.95, 0.5))   # ghillie-green
		elif e["elite"]:
			# Wind-up telegraph: muzzle ember swells red before the shot.
			var wu: int = e.get("windup", 0)
			if wu > 0:
				var wfrac := 1.0 - float(wu) / float(SimWorld.ELITE_WINDUP_TICKS)
				draw_circle(epos + Vector2.from_angle(face) * 8.0, 1.5 + wfrac * 3.5,
					Color(1.0, 0.85 - wfrac * 0.55, 0.2, 0.4 + wfrac * 0.6))
			var esw := (1.0 + (1.0 - float(wu) / float(SimWorld.ELITE_WINDUP_TICKS)) * 0.14) if wu > 0 else 1.0
			_spr("elite", epos, face, 0.5 * esw, Color(1.35, 0.75, 0.7))
		else:
			_spr(_RUSHER_SKINS[e.get("skin", 0)], epos, face, 0.5)


func _draw_observer() -> void:
	if sim.observer.is_empty():
		return
	var op := _to_screen(sim.observer["x"], sim.camera_top + SimWorld.OBSERVER_Y_OFFSET)
	op.y += sin(float(Engine.get_physics_frames()) * 0.07) * 0.8   # engine-idle breath — not a statue
	_spr("m_radar_tank", op, PI / 2, 0.5)   # radar-spotter vehicle: reads as "painting you for artillery"
	draw_line(op + Vector2(8, 0), op + Vector2(8, -12), Color(0.95, 0.8, 0.2), 2.0)
	draw_rect(Rect2(op + Vector2(8, -12), Vector2(7, 5)), Color(0.9, 0.25, 0.2))
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
		_draw_one_gunship(sim.endless_boss, "GUNSHIP", slot)


func _draw_one_gunship(boss: Dictionary, label: String, slot: int) -> void:
	var bpos := _to_screen(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
	# Mortar-phase warning: the hull flashes red while volleys are near
	# (they land at phase_t 200/240/280 of the 360-tick cycle).
	var pt: int = boss["phase_t"]
	var hull_mod := Color.WHITE
	if pt >= 170 and pt <= 290 and (_motion < 0.5 or (Engine.get_physics_frames() / 6) % 2 == 0):
		hull_mod = Color(1.5, 0.6, 0.5)
	hull_mod = hull_mod.lerp(Color(2.2, 2.2, 2.2), _boss_flash)
	_spr("gunship_body", bpos, PI, 0.8, hull_mod)
	_spr("gunship_barrel", bpos + Vector2(0, 12), 0.0, 0.8, hull_mod)
	# Rotor blur.
	var rt := float(Engine.get_physics_frames()) * 0.9
	for i in 2:
		var a := rt + i * PI / 2
		draw_line(bpos - Vector2.from_angle(a) * 26.0, bpos + Vector2.from_angle(a) * 26.0,
			Color(0.85, 0.85, 0.85, 0.5), 2.0)
	draw_circle(bpos, 3.5, Color(0.3, 0.3, 0.35))
	var bfrac := minf(1.0, float(boss["hp"]) / float(SimWorld.BOSS_HP))
	var bkey := "boss%d" % boss["gate_y"]
	# Fixed top-center HUD slot (mirrors the colossus's fixed bottom-center
	# bar, ~1618): the boss's screen pos can sit above the held camera or
	# off-screen, and a world-anchored bar would go with it. Stacked by
	# slot so two simultaneous bosses don't overlap each other, and started
	# below the corner HUD panel's max height (~60px) so they never clash.
	var bar_w := 160.0
	var bar_x := 320.0 - bar_w / 2.0
	var bar_y := 64.0 + float(slot) * 22.0
	# Same strafe/mortar half-cycle the sim uses to pick behavior in
	# _step_one_boss (t < BOSS_CYCLE_TICKS/2), surfaced the way the
	# colossus bar labels its phase.
	var gphase := 1 if pt < SimWorld.BOSS_CYCLE_TICKS / 2 else 2
	Art.text(self, "%s — PHASE %d/2" % [label, gphase], Vector2(bar_x, bar_y), 10, Color(1.0, 0.5, 0.4))
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
	_ground_shadow(cpos, 30.0)
	_spr("colossus_body", cbody, PI, 1.9, mod, csquash)
	_spr("colossus_barrel", cbody + Vector2(-24, 26), PI - 0.5, 1.3, mod)
	_spr("colossus_barrel", cbody + Vector2(24, 26), PI + 0.5, 1.3, mod)
	# Turret warm-up: barrel tips glow brighter as the next spray approaches.
	var warm := 1.0 - float(sim.colossus["spray_cd"]) / float(SimWorld.COLOSSUS_SPRAY_CD_TICKS)
	for bx in [-24.0, 24.0]:
		draw_circle(cpos + Vector2(bx, 34.0), 2.0 + warm * 3.5,
			Color(1.0, 0.55, 0.15, 0.15 + warm * 0.55))
	var pulse := Art.pulse(0.2)
	# Core window: when the plating is retracted, the core glows white-hot and
	# a 'CORE EXPOSED' ring says 'shoot it NOW' — bullets chip it this beat.
	if sim.colossus.get("core_open", 0) > 0:
		draw_circle(cpos, 9.0 + pulse * 4.0, Color(1.0, 0.95, 0.7, 0.9))
		draw_arc(cpos, 16.0 + pulse * 3.0, 0, TAU, 28, Color(1.0, 1.0, 0.6, 0.9), 2.5)
	else:
		draw_circle(cpos, 7.0 + pulse * 2.0, Color(0.95, 0.25, 0.15, 0.85))
	# Bottom-center so the fill never hides under the HUD panel.
	var cfrac := float(sim.colossus["hp"]) / float(SimWorld.COLOSSUS_HP)
	Art.text(self, "FOUNDRY COLOSSUS — PHASE %d/3" % phase, Vector2(172, 326), 10, Color(1.0, 0.55, 0.45))
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


func _draw_projectiles() -> void:
	for g in sim.grenades:
		var base := _to_screen(g["x"], g["y"])
		draw_circle(base + Vector2(2, 2), 3.0, Color(0, 0, 0, 0.35))   # shadow
		var spin := float(Engine.get_physics_frames()) * 0.4
		var body := base - Vector2(0, g["z"] * PX * 0.5)
		# Real frag silhouette (the capsule sprite read as a pill). Shells
		# fly steel-dark and bigger.
		if g.get("shell", false):
			draw_set_transform(body, spin, Vector2.ONE)
			draw_texture_rect(Art.tex("wep_grenade"), Rect2(-6, -6, 12, 12), false,
				Color(0.55, 0.6, 0.7))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_set_transform(body, spin, Vector2.ONE)
			draw_texture_rect(Art.tex("wep_grenade"), Rect2(-5, -5, 10, 10), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
			false, Color(1.0, 0.55, 0.25, 0.18))
		draw_arc(land, blast, 0, TAU, 28, Color(1.0, 0.55, 0.25, 0.35), 1.0)
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
		if e["alive"] and e.get("submerged", false):
			submerged_pos.append(_to_screen(e["x"], e["y"]))
	for b in sim.bullets:
		var bpos := _to_screen(b["x"], b["y"])
		if col_on and bpos.distance_to(col_pos) < SimWorld.COLOSSUS_HIT_RADIUS * PX + 4.0:
			if (b["x"] / 4099 + Engine.get_physics_frames()) % 2 == 0:
				draw_circle(bpos, 2.4, Color(1.0, 0.85, 0.4, 0.8))
				draw_circle(bpos, 1.0, Color(1.0, 1.0, 0.9))
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
		# Hostile fire: small glowing red orb — ordnance, not infantry.
		var egr := 4.4
		draw_texture_rect(Art.tex("fx_softspot"), Rect2(bpos - Vector2.ONE * egr, Vector2.ONE * egr * 2.0),
			false, Color(1.0, 0.3, 0.15, 0.55))
		draw_circle(bpos, 1.6, Color(1.0, 0.55, 0.35))
		draw_circle(bpos, 0.9, Color(1.0, 0.9, 0.7))


func _draw_players() -> void:
	for i in sim.players.size():
		var p := sim.players[i]
		if p["in_tank"] >= 0:
			continue   # rendered as the tank
		var pos := _to_screen(p["x"], p["y"]) + (_recoil[i] if i < _recoil.size() else Vector2.ZERO) + (_hit_flinch[i] if i < _hit_flinch.size() else Vector2.ZERO)
		# Run-cycle bob: a per-step vertical hop while moving, matching the charging
		# enemies' cadence so the player sprite isn't the one flat-gliding thing on the
		# field. _dust_prev still holds LAST frame's pos here (updated by _kick_dust below).
		var walk_bob := 0.0
		if p["alive"] and p["roll_ticks"] == 0 and i < _dust_prev.size() and Vector2i(p["x"], p["y"]) != _dust_prev[i]:
			walk_bob = absf(sin(Engine.get_physics_frames() * 0.35 + i * PI)) * 1.2
		elif p["alive"] and p["roll_ticks"] == 0:
			# Idle breathing: the standing-still soldier was the one frozen thing on an
			# otherwise fully-animated field — a tiny slow micro-bob keeps it alive.
			walk_bob = sin(Engine.get_physics_frames() * 0.045 + i * PI) * 0.35
		var tex_name := "player1" if i == 0 else "player2"
		if p["alive"] and not sim._in_water(p["x"], p["y"]):
			_kick_dust(i, p["x"], p["y"], _dust_prev, false)
		else:
			_dust_prev[i] = Vector2i(p["x"], p["y"])
		_ground_shadow(pos, 7.0)
		if not p["alive"]:
			# Downed but not gone: a greyed prone body so a waiting-for-revive
			# teammate is visibly THERE on the field, not just a floating beacon.
			_spr(tex_name, pos, PI / 2, 0.46, Color(0.55, 0.55, 0.6, 0.7))
		# Co-op identity ring under each soldier so you never lose your guy in
		# the chaos (P1 green / P2 gold, matching the HUD rows). 1P: skip it.
		if _two_players and p["alive"]:
			var idc := Color(0.4, 1.0, 0.4, 0.6) if i == 0 else Color(1.0, 0.85, 0.3, 0.6)
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
					var pcol := Color(0.4, 1.0, 0.4) if q == 0 else Color(1.0, 0.85, 0.3)
					var bdir := (dpos - edge).normalized()
					draw_circle(edge, 5.0, Color(pcol.r, pcol.g, pcol.b, 0.85))
					draw_line(edge, edge + bdir * 9.0, pcol, 2.0)
					Art.draw_glyph(self, "revive", edge - bdir * 10.0, 9.0)
				var cost := sim.revive_cost(dp)
				if sim.war_chest < cost:
					continue
				draw_dashed_line(pos, dpos, Color(0.5, 0.9, 1.0, 0.4), 1.0, 4.0)
				var rtxt := "REVIVE %d" % cost
				draw_string(ThemeDB.fallback_font, pos + Vector2(-18, -16), rtxt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Art.safe(Color(0.5, 1.0, 0.6)))
				Art.draw_glyph(self, "revive", pos + Vector2(24, -19), 10.0)
		if p["alive"]:
			var angle := _aim_angle(p)
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
			_spr(tex_name, pos - Vector2(0, walk_bob), angle, 0.52, mod)
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
			if p["vest"]:
				draw_arc(pos, 14.0, 0, TAU, 24, Color(0.55, 0.7, 1.0, 0.9), 2.0)
				# Adrenaline aura: the 20-streak / tank-bail speed surge (boost_ticks) is a
				# real 1.5x buff that was otherwise invisible. A hot ring that fades as the
				# surge drains says "empowered — and here is when it ends".
				if p["boost_ticks"] > 0:
					var bo_frac: float = clampf(float(p["boost_ticks"]) / float(SimWorld.BAIL_BOOST_TICKS * 2), 0.0, 1.0)
					var bo_ph := float(Engine.get_physics_frames() + i * 17)
					var bo_pulse := 0.5 + 0.5 * sin(bo_ph * 0.45)
					draw_arc(pos, 16.0 + bo_pulse * 3.0, 0, TAU, 28,
						Color(1.0, 0.55, 0.15, (0.35 + 0.4 * bo_pulse) * bo_frac), 2.0 + bo_frac)
					for bo_s in 6:
						var bo_ang := bo_s * TAU / 6.0 + bo_ph * 0.08
						var bo_dir := Vector2.from_angle(bo_ang)
						draw_line(pos + bo_dir * 12.0, pos + bo_dir * (17.0 + bo_pulse * 4.0),
							Color(1.0, 0.72, 0.3, 0.5 * bo_frac), 1.5)
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
				elif p["spread_ticks"] > 0:
					rcol = Color(1.0, 0.8, 0.45)
				if bash_ready:
					rcol = Color(1.0, 0.55, 0.2)
					var bp := Art.pulse(0.25)
					draw_arc(pos, SimWorld.BASH_RADIUS * PX, 0, TAU, 20,
						Color(1.0, 0.55, 0.2, 0.3 + bp * 0.2), 1.5)
				# Confirm-thump: the reticle itself scale-punches on a landed hit.
				var rpunch := 1.0 + (_hitmarker[i] if i < _hitmarker.size() else 0.0) * 0.3
				var rcen := rrect.get_center()
				draw_set_transform(rcen, 0.0, Vector2.ONE * rpunch)
				draw_texture_rect(Art.tex("ui_reticle"), Rect2(rrect.position - rcen + Vector2(1, 1), rrect.size),
					false, Color(0, 0, 0, 0.55))
				draw_texture_rect(Art.tex("ui_reticle"), Rect2(rrect.position - rcen, rrect.size), false, rcol)
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
			var dpose := lerp_angle(_aim_angle(p), PI / 2, da)
			var dcol := Color(1, 1, 1, 1).lerp(Color(0.35, 0.35, 0.35, 0.6), da)
			_spr(tex_name, pos, dpose, 0.52 * (1.0 + (1.0 - da) * 0.12), dcol)
			draw_arc(pos, 12.0, 0, TAU, 24, Color(0.8, 0.3, 0.25, 0.8 * da), 1.5)
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
		col = Color(0.58, 0.56, 0.52).lerp(Color(1.0, 0.55, 0.18), (march - 0.5) * 2.0)   # → ember
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
	_enemy_water_prev.resize(sim.enemies.size())
	for i in sim.enemies.size():
		var e := sim.enemies[i]
		# Frogmen own their submerge/surface ripple already; skip them here.
		var wet: bool = e["alive"] and e["kind"] != "frogman" and sim._in_water(e["x"], e["y"])
		if wet and not _enemy_water_prev[i]:
			_burst(e["x"], e["y"], "splash", 4, 0.8, 1.8, 0.5, 0.1, 1.1, true)
		_enemy_water_prev[i] = wet


func _burst(x: int, y: int, kind: String, n: int, spd_lo: float, spd_hi: float, jitter: float, rate: float = 0.06, vy_bias: float = 0.0, move: bool = false) -> void:
	# Clean radial dust/debris ring — evenly spaced directions with a little jitter.
	# vy_bias skews the burst upward (negative Y); move opts these particles into
	# the position-integration pass below without touching other "kind" call sites.
	if _fx.size() > 260:   # ponytail: soft cap — boss-finale kill spam can't stack unbounded draws
		return
	for d in n:
		var a := d * TAU / float(n) + randf() * jitter
		var entry := {"x": x, "y": y, "t": 0.0, "kind": kind, "rate": rate,
			"vx": cos(a) * randf_range(spd_lo, spd_hi), "vy": sin(a) * randf_range(spd_lo, spd_hi) - vy_bias}
		if move:
			entry["move"] = true
		_fx.append(entry)


func _draw_fx() -> void:
	var floattext_i := 0
	for fx in _fx:
		if _GLOW_KINDS.has(fx["kind"]):
			continue   # drawn by _draw_glow on the additive layer
		var pos := _to_screen(fx["x"], fx["y"])
		var t: float = fx["t"]
		if fx["kind"] == "explosion":
			var frame := mini(3, int(t * 4.0))
			_spr(_EXPLO_NAMES[frame], pos, t * 2.0, 0.45 + t * 0.5, Color(1, 1, 1, 1.0 - t * 0.7))
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
			draw_texture_rect(Art.tex("fx_shell"), Rect2(-3.0, -1.5, 6.0, 3.0), false, Color(1, 1, 1, 1.0 - t * 0.8))
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
			var fw := ThemeDB.fallback_font.get_string_size(fx["text"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
			# Ease-out rise (fast at spawn, settling at the top) + a ~3-frame scale
			# punch pivoted on the text center — pops in, then glides.
			var rise := 1.0 - (1.0 - t) * (1.0 - t)
			var fpivot := pos + Vector2(0.0, -18.0 - rise * 22.0 - floattext_i * 11.0)
			var fpunch := 1.0 + maxf(0.0, 0.5 - t * 4.0)
			var oc := Color(0, 0, 0, fc.a * 0.85)
			draw_set_transform(fpivot, 0.0, Vector2.ONE * fpunch)
			var frel := Vector2(-fw / 2.0, 0.0)
			for od in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(ThemeDB.fallback_font, frel + od, fx["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, oc)
			draw_string(ThemeDB.fallback_font, frel, fx["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, fc)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			floattext_i += 1
		elif fx["kind"] == "smoke":
			# smoothstep ramp-in: puffs swell into view instead of stamping at full alpha
			_spr("fx_smoke", pos - Vector2(0, t * 10.0), t, 0.3 + t * 0.25,
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
	for fx in _fx:
		if not _GLOW_KINDS.has(fx["kind"]):
			continue
		var pos := _to_screen(fx["x"], fx["y"])
		var t: float = fx["t"]
		if fx["kind"] == "muzzle":
			var sz := (13.0 if fx.get("big", false) else 9.0) * float(fx.get("szj", 1.0)) * (1.0 - t * 0.6)
			var dirv := Vector2.from_angle(fx["a"])
			var pv := Vector2(-dirv.y, dirv.x)
			var mc := Color(1.0, 0.95, 0.55, 0.95 - t * 0.85)
			g.draw_line(pos, pos + dirv * sz * 1.6, mc, 2.5)
			g.draw_line(pos - pv * sz * 0.55, pos + pv * sz * 0.55, mc, 2.0)
			g.draw_circle(pos, sz * 0.45, Color(1.0, 1.0, 0.8, 0.9 - t * 0.8))
		elif fx["kind"] == "spark":
			# Ricochet: legacy art sparkle cards flung radially — armor says no.
			var sc := Color(1.0, 0.9, 0.5, 0.9 - t * 0.9)
			var stex := Art.tex("fx_sparkle")
			var ssz := 5.0 + t * 5.0
			for k in 3:
				var sa := k * TAU / 3.0 + t * 2.0
				var sp2: Vector2 = pos + Vector2.from_angle(sa) * (3.0 + t * 7.0)
				g.draw_texture_rect(stex, Rect2(sp2 - Vector2.ONE * ssz, Vector2.ONE * ssz * 2.0), false, sc)
		elif fx["kind"] == "shockwave":
			# Concussive ring: a legacy art ring texture with baked inner/outer falloff
			# snaps out — reads as a pressure wave, not a flat UI stroke.
			var swr := 4.0 + t * 34.0
			g.draw_texture_rect(Art.tex("fx_ring"), Rect2(pos - Vector2.ONE * swr, Vector2.ONE * swr * 2.0),
				false, Color(1.0, 0.95, 0.8, 0.7 * (1.0 - t)))
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
			g.draw_circle(pos, 12.0 * (1.0 - t) + 3.0, Color(1.0, 0.95, 0.8, 0.85 * la2 * la2))
			g.draw_circle(pos, 4.5, Color(1.0, 1.0, 0.95, la2))


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
	# Fallen bodies: the enemy sprite, darkened and sprawled, fading over ~4s.
	for c in _corpses:
		var cp := _to_screen(c["x"], c["y"])
		var ct: float = c["t"]
		var fade := 1.0 - ct
		# A dark blood pool spreads under it early, then everything fades.
		# (skipped for water kills — a puddle in a river reads wrong)
		if not c.get("wet", false):
			draw_circle(cp + Vector2(0, 2), 3.0 + minf(ct, 0.2) * 20.0, Color(0.28, 0.03, 0.03, 0.4 * fade))
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
	# Chevrons on the bottom edge for live hostiles below the viewport —
	# bypassed bunkers keep spawning behind you.
	var _bottom_threats: Array = []
	for e in sim.enemies:
		if not e["alive"] or e.get("submerged", false):
			continue
		var sy: float = (e["y"] - sim.camera_top) * PX
		if sy <= 364.0:
			continue
		var danger: bool = e["kind"] == "sniper" or e["kind"] == "grenadier" or e["kind"] == "ghillie"
		_bottom_threats.append({"e": e, "off": sy, "danger": danger})
	# A dense endless wave can stack a dozen+ off-screen hostiles on one edge,
	# painting a near-solid chevron row that drowns the lethality signal —
	# cap to the nearest few; ties prefer the lethal ranged killers.
	_draw_edge_chevrons(_bottom_threats, false)
	# Top-edge chevrons for hostiles about to enter from the spawn edge above —
	# an off-screen threat you'd otherwise only meet as it crosses into view.
	var _top_threats: Array = []
	for e in sim.enemies:
		if not e["alive"] or e.get("submerged", false):
			continue
		var ty: float = (e["y"] - sim.camera_top) * PX
		if ty >= 0.0 or ty < -180.0:
			continue
		var tdanger: bool = e["kind"] == "sniper" or e["kind"] == "grenadier" or e["kind"] == "ghillie"
		_top_threats.append({"e": e, "off": ty, "danger": tdanger})
	# Same swarm cap as the bottom edge — nearest few only, ties favor the
	# lethal ranged killers.
	_draw_edge_chevrons(_top_threats, true)
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
		var bp := Art.pulse(0.25)
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
			var rp := Art.pulse(0.3)
			var rcol := Art.safe(Color(0.5, 0.9, 1.0, 0.6 + rp * 0.3))
			if rsy > 360.0:
				draw_line(Vector2(rx - 6, 336), Vector2(rx, 345), rcol, 2.5)
				draw_line(Vector2(rx, 345), Vector2(rx + 6, 336), rcol, 2.5)
				Art.text(self, "REVIVE", Vector2(rx - 18, 332), 9, rcol)
			else:
				draw_line(Vector2(rx - 6, 40), Vector2(rx, 31), rcol, 2.5)
				draw_line(Vector2(rx, 31), Vector2(rx + 6, 40), rcol, 2.5)
				Art.text(self, "REVIVE", Vector2(rx - 18, 50), 9, rcol)


func _draw_edge_chevrons(threats: Array, is_top: bool) -> void:
	## Shared sort->cap->draw pass for the top/bottom off-screen threat
	## chevrons: ties prefer the lethal ranged killers, capped to the
	## nearest 6 so a dense swarm can't paint a solid warning row.
	if is_top:
		threats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["off"] != b["off"]:
				return a["off"] > b["off"]
			return a["danger"] and not b["danger"])
	else:
		threats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["off"] != b["off"]:
				return a["off"] < b["off"]
			return a["danger"] and not b["danger"])
	var _shop_row := sim.mode == "endless" and sim.intermission_ticks > 0
	var _panel_bot := 2.0 + 26.0 + sim.players.size() * 16.0 + (16.0 if _shop_row else 0.0)
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
			if tx < 262.0:
				tbase = _panel_bot + 12.0
			var ta := clampf(1.0 + off / 180.0, 0.2, 0.7)
			if e.get("windup", 0) > 0:
				ta = clampf(ta + Art.pulse(0.28) * 0.3, 0.2, 1.0)
			var tcol := Color(1.0, 0.1, 0.1, ta) if danger else Color(1.0, 0.55, 0.25, ta)
			var tspr := 6.0 if danger else 4.0   # spikier spread for ranged killers
			var ttip := tbase - (6.0 if danger else 4.0)
			draw_line(Vector2(tx - tspr, tbase), Vector2(tx, ttip), tcol, 2.0)
			draw_line(Vector2(tx, ttip), Vector2(tx + tspr, tbase), tcol, 2.0)
		else:
			var sx: float = clampf(e["x"] * PX, 8.0, 632.0)
			if sim.last_stand and sx > 165.0 and sx < 475.0:
				# keep clear of the colossus HP bar / LAST STAND readout parked
				# at bottom-center of the screen in the finale
				sx = 165.0 if sx < 320.0 else 475.0
			var a := clampf(1.2 - (off - 360.0) / 200.0, 0.25, 0.85)
			if e.get("windup", 0) > 0:
				a = clampf(a + Art.pulse(0.28) * 0.35, 0.25, 1.0)
			var col := Color(1.0, 0.1, 0.1, a) if danger else Color(1.0, 0.35, 0.2, a)
			var spr := 6.0 if danger else 4.0   # spikier spread for ranged killers
			var tip := 361.0 if danger else 358.0
			draw_line(Vector2(sx - spr, 353), Vector2(sx, tip), col, 2.0)
			draw_line(Vector2(sx, tip), Vector2(sx + spr, 353), col, 2.0)


func _draw_objective_markers() -> void:
	# The battlefield self-labels "go here / kill this / grab this". On-screen
	# objectives get a small bobbing icon overhead; off-screen ones become a
	# directional diamond pinned to the nearest edge (distinct from the red
	# threat chevrons — these are objectives, not generic hostiles).
	var bob := sin(float(Engine.get_physics_frames()) * 0.12) * 2.0
	var marks: Array = []
	for g in sim.gates:
		if not g["open"] and not g.get("final", false):
			marks.append({"sx": 320.0, "sy": (g["y"] - sim.camera_top) * PX,
				"icon": "hud_flag", "col": Color(1.0, 0.9, 0.4)})
			break
	if not sim.endless_boss.is_empty() and sim.endless_boss.get("alive", false):
		marks.append({"sx": sim.endless_boss["x"] * PX,
			"sy": (sim.endless_boss.get("gate_y", sim.camera_top) - sim.camera_top) * PX,
			"icon": "hud_skull", "col": Color(1.0, 0.5, 0.35)})
	if not sim.colossus.is_empty() and sim.colossus.get("alive", false):
		marks.append({"sx": sim.colossus["x"] * PX, "sy": (sim.colossus["y"] - sim.camera_top) * PX,
			"icon": "hud_skull", "col": Color(1.0, 0.45, 0.3)})
	for e in sim.enemies:
		if not e["alive"]:
			continue
		if e["kind"] == "courier":
			marks.append({"sx": e["x"] * PX, "sy": (e["y"] - sim.camera_top) * PX,
				"icon": "hud_vehicle", "col": Color(1.0, 0.85, 0.35)})
		elif e.get("marked", false):
			marks.append({"sx": e["x"] * PX, "sy": (e["y"] - sim.camera_top) * PX,
				"icon": "hud_target", "col": Color(1.0, 0.82, 0.3)})
	for pk in sim.pickups:
		if pk.get("cost", 0) > 0:
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": "hud_gunshop", "col": Color(0.6, 0.9, 1.0)})
		elif pk["kind"] >= 4:
			# Rare power-up capsule (pierce/spread) — the game makes a fuss on pickup but
			# never pointed you to it; colour-keyed cyan/amber like the ground glow.
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": "hud_gunshop", "col": Color(0.5, 0.9, 1.0) if pk["kind"] == 4 else Color(1.0, 0.8, 0.45)})
		else:
			# Free crate (guaranteed gate cache) — supplies worth pathing to.
			marks.append({"sx": pk["x"] * PX, "sy": (pk["y"] - sim.camera_top) * PX,
				"icon": "hud_gunshop", "col": Color(0.7, 0.85, 0.6)})
	for m in marks:
		var mp := Vector2(m["sx"], m["sy"])
		var on := mp.x >= 6.0 and mp.x <= 634.0 and mp.y >= 32.0 and mp.y <= 354.0
		if on:
			draw_texture_rect(Art.tex(m["icon"]),
				Rect2(mp + Vector2(-5.0, -20.0 + bob), Vector2(10, 10)), false, m["col"])
		else:
			var ep := _marker_edge(mp)
			_marker_diamond(ep, 5.0, m["col"])
			draw_texture_rect(Art.tex(m["icon"]), Rect2(ep - Vector2(4, 4), Vector2(8, 8)), false, m["col"])


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
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0),
		p + Vector2(0, r), p + Vector2(-r, 0)]), Color(col.r, col.g, col.b, 0.85))


func _draw_wheel() -> void:
	for i in sim.players.size():
		if i >= _wheel.size() or not _wheel[i]["open"]:
			continue
		var p := sim.players[i]
		if not p["alive"]:
			continue
		var c := _to_screen(p["x"], p["y"])
		draw_circle(c, 42.0, Color(0.04, 0.07, 0.04, 0.55))
		# Center hub: the fuel-cap ring framing the War Chest itself — this
		# wheel drains the same pool that funds revives.
		_spr("ui_dial_fuel", c, 0.0, 34.0 / 600.0)
		var f := ThemeDB.fallback_font
		var chest := str(sim.war_chest)
		var cw := f.get_string_size(chest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var cx := c.x - (10.0 + cw) / 2.0
		draw_texture_rect(Art.tex("icon_coin"), Rect2(cx, c.y - 5.0, 9, 9), false)
		draw_string(f, Vector2(cx + 10.0, c.y + 3.0), chest,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.95, 0.65))
		for s in 4:
			var item: Dictionary = WHEEL_ITEMS[_SECTOR_TO_ITEM[s]]
			var ang := s * TAU / 4.0
			var ipos := c + Vector2.from_angle(ang) * 31.0
			var acost: int = sim._supply_cost(item["kind"])   # wave-scaled in endless
			var afford: bool = sim.war_chest >= acost
			var selected: bool = _wheel[i]["sel"] == s
			# Socket sprite authored nub-down (north slot); +90° per sector
			# keeps the connector nub pointing at the hub.
			var sock_mod := Color.WHITE
			if selected:
				sock_mod = Color(1.3, 1.18, 0.7) if afford else Color(1.2, 0.6, 0.55)
			_spr("ui_wheel_socket", ipos, ang + PI / 2.0,
				(38.0 if selected else 31.0) / 512.0, sock_mod)
			var icon_mod := Color.WHITE if afford else Color(0.8, 0.35, 0.35, 0.55)
			var isz := 18.0 if selected else 14.0
			draw_texture_rect(Art.tex(item["icon"]),
				Rect2(ipos - Vector2(isz, isz) / 2.0, Vector2(isz, isz)), false, icon_mod)
			draw_string(f, ipos + Vector2(-7, 24), str(acost),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(1.0, 0.95, 0.65) if afford else Color(0.9, 0.5, 0.45))
			# Current stock vs cap under each socket — the buy decision no longer
			# needs an eye-flick to the corner HUD.
			var stock := ""
			match int(item["kind"]):
				0: stock = "%d/%d" % [p["mg_ammo"], SimWorld.MG_AMMO_MAX]
				1: stock = "%d/%d" % [p["grenade_ammo"], SimWorld.GRENADE_AMMO_MAX]
				2: stock = "VEST ON" if p["vest"] else "NO VEST"
			if stock != "":
				var sw2 := f.get_string_size(stock, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
				draw_string(f, ipos + Vector2(-sw2 / 2.0, 33), stock,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.72, 0.77, 0.66, 0.85))
		# What the selected socket actually delivers.
		var sel: int = _wheel[i]["sel"]
		if sel >= 0:
			var lbl: String = WHEEL_ITEMS[_SECTOR_TO_ITEM[sel]]["label"]
			Art.text_center(self, lbl, c.x, 71.0, 9, Color(1.0, 0.95, 0.7))


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
	return ""


func _draw_airstrike_telegraph(top_msg: String) -> void:
	# The called airstrike's incoming window: a red wash that ramps and strobes as
	# impact nears, so the wipe reads as an anticipated event, not a silent zap.
	if sim.pending_airstrike <= 0:
		return
	var frac := 1.0 - float(sim.pending_airstrike) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
	var a := 0.05 + frac * 0.16
	if sim.pending_airstrike < 10 and (sim.pending_airstrike / 3) % 2 == 0:
		a = 0.34
	draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(1.0, 0.2, 0.1, a * _motion + 0.03))
	# A strike jet dives down the field as the payload arrives — turns a bare
	# countdown into an anticipated run. Reuses the gunship's 'facing down' angle
	# (PI) so the nose leads; rides the already-checksummed pending_airstrike int.
	var jy := lerpf(-30.0, SCREEN_H + 30.0, frac)
	_spr("m_jet", Vector2(SCREEN_W * 0.5, jy), PI, 0.6)
	if top_msg != "airstrike":
		return
	var txt := "AIRSTRIKE INBOUND  %.1fs" % (sim.pending_airstrike / 60.0)
	Art.text_center(self, txt, 320, 46, 12, Color(1.0, 0.85, 0.3))


func _draw_threat_pips() -> void:
	# Off-screen one-shot telegraphs (sniper / grenadier / ghillie winding up) get a
	# clamped screen-edge arrow so a lethal shot from beyond the 640x360 viewport reads
	# as a threat, not a cheap death. Stateless — recomputed from live sim state each
	# frame, so it self-clears when the windup ends or the source scrolls on-screen.
	for e in sim.enemies:
		if not e["alive"] or e.get("windup", 0) <= 0:
			continue
		var k: String = e["kind"]
		if k != "sniper" and k != "grenadier" and k != "ghillie":
			continue
		var sp := _to_screen(e["x"], e["y"])
		if sp.x >= 0.0 and sp.x <= SCREEN_W and sp.y >= 0.0 and sp.y <= SCREEN_H:
			continue   # on-screen — the on-body telegraph already covers it
		var edge := Vector2(clampf(sp.x, 12.0, SCREEN_W - 12.0), clampf(sp.y, 12.0, SCREEN_H - 12.0))
		var dir := (sp - edge).normalized()
		if dir == Vector2.ZERO:
			continue
		var col := Color(1.0, 0.7, 0.25) if k == "grenadier" else Color(1.0, 0.32, 0.32)
		var pf := Art.pulse(0.12)
		var perp := Vector2(-dir.y, dir.x)
		var tip := edge + dir * (7.0 + pf * 3.0)
		var base := edge - dir * 4.0
		var tri := PackedVector2Array([tip, base + perp * 5.0, base - perp * 5.0])
		draw_circle(edge, 9.0 + pf * 2.0, Color(col.r, col.g, col.b, 0.14 + pf * 0.08))
		draw_colored_polygon(tri, Color(col.r, col.g, col.b, 0.9))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.55), 1.0)
	# Off-screen mortar strikes: a telegraph that scrolls off-frame between cast and
	# impact gave zero warning; clamp an urgency-scaled amber-red wedge to the edge.
	for st in sim.strikes:
		var ssp := _to_screen(st["x"], st["y"])
		if ssp.x >= 0.0 and ssp.x <= SCREEN_W and ssp.y >= 0.0 and ssp.y <= SCREEN_H:
			continue
		var sedge := Vector2(clampf(ssp.x, 12.0, SCREEN_W - 12.0), clampf(ssp.y, 12.0, SCREEN_H - 12.0))
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
		Color(0.0, 0.0, 0.0, 0.16))
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
		var pv := (0.1 + 0.24 * paint) * (0.4 + 0.6 * Art.pulse(0.4))
		draw_texture_rect(Art.tex("ui_vignette"), Rect2(0, 0, SCREEN_W, SCREEN_H), false,
			Color(1.0, 0.15, 0.12, pv * _motion))
		# 'You're being sighted' as an icon, not only a red edge: a binoculars
		# glyph pulses top-center for the windup. Alpha is NOT gated by _motion,
		# so it still warns under reduce-motion (where the vignette is damped).
		var bsz := 15.0 + 4.0 * paint
		draw_texture_rect(Art.tex("item_binoculars"),
			Rect2(SCREEN_W / 2.0 - bsz / 2.0, 22.0, bsz, bsz), false,
			Color(1.0, 0.55, 0.4, 0.4 + 0.45 * paint))
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
	if _flash_alpha > 0.01:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(1, 1, 1, _flash_alpha * _motion))
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
			Art.text_center(self, gtxt, 320, gy, 11, Color(1.0, 0.9, 0.4, gpulse))
		break
	# Stall warning: the observer's clock is running — telegraph the
	# punishment before it arrives, not after.
	if top_msg == "mortar":
		var pulse := 1.0 if _motion < 0.5 else 0.55 + 0.45 * sin(float(Engine.get_physics_frames()) * 0.25)
		var wtxt := "MORTARS RANGING — ADVANCE!"
		Art.text_center(self, wtxt, 320, 46, 11, Color(1.0, 0.4, 0.25, pulse))
	# Splash banner (wave starts, checkpoints, observer warning).
	if not _banners.is_empty():
		var bn: Dictionary = _banners[0]
		var bt: float = bn["t"]
		var btext: String = bn["text"]
		if top_msg == "splash" and bt > 0.01 and not btext.is_empty():
			var a := minf(1.0, bt * 4.0) * minf(1.0, (1.0 - bt) * 8.0 + 0.2)
			var bc: Color = bn.get("col", Color(1.0, 0.92, 0.55))
			Art.text_center(self, btext, 320, 70, 16, Color(bc.r, bc.g, bc.b, a))
	if sim.victory:
		var vpulse := 1.0 if _motion < 0.5 else 0.85 + 0.15 * sin(float(Engine.get_physics_frames()) * 0.12)
		_draw_result_panel("V I C T O R Y !", Color(1.0, 0.85 * vpulse, 0.3 * vpulse), [
			{"text": "SCORE  %d" % sim.score, "color": Color(0.95, 0.96, 0.9), "size": 13,
				"icon": "icon_medal", "icon_size": 16.0},
			{"text": "WAR CHEST BANKED", "color": Color(1.0, 0.92, 0.55),
				"icon": "icon_coin", "icon_size": 14.0},
			{"text": "%dm OF JUNGLE PUSHED" % [-Fixed.to_int(sim.camera_top) / 10], "color": Color(0.8, 0.84, 0.74)},
		], Color(1, 1, 1, 0.96))
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
			{"text": "SCORE %d   KILLS %d" % [sim.score, _run_kills], "color": Color(0.9, 0.92, 0.85)},
			{"text": "LONGEST STREAK  x%d" % _run_best_streak, "color": Color(0.9, 0.92, 0.85)},
		]
		var rr := _run_rank()
		rows.insert(0, {"text": "RANK  %s  —  %s" % [rr.grade, rr.title], "color": rr.col})
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
		rows.append({"text": "PRESS  R  — REDEPLOY", "color": Color(1.0, 0.9, 0.4, rp)})
		_draw_result_panel("K.I.A.", Color(0.95, 0.4, 0.35), rows, Color(1, 1, 1, 0.96))
	elif sim.last_stand:
		# Shadowed + centered via the shared helper — was the one banner holdout
		# still drawing raw, unshadowed, hardcoded-position text.
		Art.text_center(self, "LAST STAND — NO REVIVES", 320.0, 350.0, 10, Color(0.95, 0.4, 0.3))
	# Black fade covering the title→combat cut.
	if _fade > 0.01:
		draw_rect(Rect2(0, 0, SCREEN_W, SCREEN_H), Color(0, 0, 0, _fade))
	# Just-in-time onboarding cue (first-time-ever, persisted).
	if _hint_t > 0.02 and not _hint_text.is_empty():
		var ha := minf(1.0, _hint_t * 3.0)
		var hf := ThemeDB.fallback_font
		var hw := hf.get_string_size(_hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_rect(Rect2(320 - hw / 2.0 - 8, 92, hw + 16, 18), Color(0.05, 0.07, 0.05, 0.8 * ha))
		Art.text_center(self, _hint_text, 320, 105, 11, Color(1.0, 0.95, 0.7, ha))


## Shared victory/debrief result-card scaffold: translucent panel + centered
## title + a stack of centered stat rows (each optionally icon-prefixed).
## rows: Array[Dictionary] of {text, color, size?, icon?, icon_size?}.
func _draw_result_panel(title: String, title_col: Color, rows: Array, accent: Color) -> void:
	var rf := Art.font()
	var panel_x := 170.0
	var panel_w := 300.0
	var panel_top := 112.0
	var title_y := 150.0
	var row_start_y := 178.0
	var row_h := 19.0
	var panel_h := (row_start_y - panel_top) + maxi(rows.size(), 1) * row_h + 14.0
	draw_texture_rect(Art.tex("ui_panel"), Rect2(panel_x, panel_top, panel_w, panel_h), false, accent)
	Art.text_center(self, title, 320, title_y, 24, title_col)
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
			draw_texture_rect(Art.tex(icon), Rect2(x, y - icon_size + 3.0, icon_size, icon_size), false)
			x += icon_size + gap
		draw_string(rf, Vector2(x, y), row_text, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size, col)


func _update_hud() -> void:
	_hud_icons.queue_redraw()
