class_name MusicDirector
extends RefCounted
## Per-place score. Owned by Sfx; knows nothing about the sim.
##
## A "track" is two sample-locked stems (assets/music/<id>_combat.ogg + <id>_lull.ogg) that
## crossfade equal-power on the same intensity the synthesized beds use. A track change is
## only ever COMMITTED on a bar boundary and runs a short crossfade between two stem pairs,
## so the music turns a corner on the downbeat instead of mid-phrase. A stinger ducks the
## score and the score re-enters on the NEXT bar, not the instant the sting's tail ends.
##
## A track with a missing, unloadable or mismatched-length stem falls back to the
## synthesized beds Sfx has always played (synth_offset_db() returns 0): never an engine
## error, never silence. Everything observable here is plain state so the headless
## runner (dummy audio driver) can assert on it.

const MUSIC_DIR := "res://assets/music/"
const TRACK_IDS: Array[String] = ["title", "sector1", "sector2", "sector3", "sector4",
	"sector5", "sector6", "boss", "shop", "laststand"]
const STINGERS: Array[String] = ["boss_intro", "sector_clear", "victory", "defeat"]
const FALLBACK_BPM := 110.0          # the synthesized drum grid
const FALLBACK_BEATS := 4
const FALLBACK_STING_SEC := 1.2
const XFADE_SEC := 0.6
const STING_DUCK := 0.85
const OFF_DB := -80.0

## Screens the caller can be on (see pick_track).
const SCREEN_TITLE := "title"
const SCREEN_HOLD := "hold"       # pause / options: keep whatever is playing
const SCREEN_PLAY := "play"
const SCREEN_DEBRIEF := "debrief"

var current_id := ""
var pending_id := ""
var bar_len := 60.0 / FALLBACK_BPM * FALLBACK_BEATS
var manifest: Dictionary = {}
var loader: Callable = Callable(self, "_default_loader")   # tests inject fixture streams
var stems_on := false           # does the CURRENT track play from stems (vs the synth beds)?
var start_count := 0            # bumped each time a stem pair is started (both in one call)
var last_started: Array = []    # [combat path, lull path] of the last started pair
var commit_log: Array[String] = []   # ids in the order they were committed
var sting_left := 0.0           # seconds of sting remaining
var sting_hold := false         # ducked until the next bar after the sting ends
var last_sting := ""

var _pairs: Array = []          # [[combat, lull], [combat, lull]] AudioStreamPlayers
var _sting_player := AudioStreamPlayer.new()
var _slot := 0
var _pair_ok: Array[bool] = [false, false]
var _pair_gain: Array[float] = [0.0, 0.0]   # 0..1 linear presence of each pair
var _xfade := 1.0
var _pos := 0.0
var _bar_idx := 0
var _stem_mix := 0.0            # 0 = synth beds, 1 = stems own the score
var _duck_sm := 0.0


func _init() -> void:
	for _i in 2:
		var pr: Array = []
		for _j in 2:
			var p := AudioStreamPlayer.new()
			p.bus = "Music"
			p.volume_db = OFF_DB
			pr.append(p)
		_pairs.append(pr)
	_sting_player.bus = "UI"
	_load_manifest()


func players() -> Array:
	var out: Array = [_sting_player]
	for pr in _pairs:
		out.append_array(pr)
	return out


func attach(owner_node: Node) -> void:
	for p in players():
		if p.get_parent() == null:
			owner_node.add_child(p)


func free_unparented() -> void:
	for p in players():
		if is_instance_valid(p) and p.get_parent() == null:
			p.free()


# --- decisions (pure) --------------------------------------------------------------

static func pick_track(screen: String, sector: int, boss: bool, shop: bool,
		last_stand: bool, current: String) -> String:
	## Which loop id the score should be on. sector is the 0-based sim sector.
	match screen:
		SCREEN_TITLE, SCREEN_DEBRIEF:
			return "title"
		SCREEN_HOLD:
			return current if current != "" else "title"
	if last_stand:
		return "laststand"
	if boss:
		return "boss"
	if shop:
		return "shop"
	return "sector%d" % clampi(sector + 1, 1, 6)


static func danger_intensity(last_stand: bool, standups_left: int) -> float:
	## Intensity FLOOR from how close the squad is to losing the sector, so a thin line
	## sounds thin even when few enemies are alive. standups_left < 0 = unbounded (endless).
	if last_stand:
		return 0.9
	if standups_left < 0 or standups_left > 2:
		return 0.0
	return 0.7 if standups_left <= 1 else 0.45


# --- state machine -----------------------------------------------------------------

func request(id: String) -> void:
	## Ask for a track. The first request commits at once; later ones wait for a bar line.
	if id == "":
		return
	if current_id == "":
		_commit(id)
		return
	pending_id = "" if id == current_id else id


func update(dt: float, pos := -1.0) -> void:
	## Advance the director. pos is the active loop's playback position in seconds, or
	## < 0 when nothing is playing (then an internal clock advances instead).
	var prev_idx := _bar_idx
	_pos = pos if pos >= 0.0 else _pos + dt
	_bar_idx = int(floor(_pos / bar_len))
	var on_bar := _bar_idx != prev_idx   # a loop wrap lands on bar 0, so it counts too
	if on_bar:
		if pending_id != "":
			var id := pending_id
			pending_id = ""
			_commit(id)
		if sting_hold and sting_left <= 0.0:
			sting_hold = false
	if sting_left > 0.0:
		sting_left = maxf(0.0, sting_left - dt)
	if _xfade < 1.0:
		_xfade = minf(1.0, _xfade + dt / XFADE_SEC)
		if _xfade >= 1.0:
			_finish_xfade()
	_stem_mix = move_toward(_stem_mix, 1.0 if stems_on else 0.0, dt / XFADE_SEC)
	_duck_sm = lerpf(_duck_sm, STING_DUCK if (sting_hold or sting_left > 0.0) else 0.0,
		0.2 if (sting_hold or sting_left > 0.0) else 0.05)
	_pair_gain_update()


func position_source() -> AudioStreamPlayer:
	## The player whose position drives the bar clock, or null.
	var pr: Array = _pairs[_slot]
	var p: AudioStreamPlayer = pr[0]
	return p if (stems_on and p.playing) else null


func synth_offset_db() -> float:
	## Added to the synthesized beds' targets: 0 when they own the score, deep negative when
	## stems do.
	return lerpf(0.0, -60.0, _stem_mix)


func sting_duck() -> float:
	return _duck_sm


func mix(level: float, duck: float, boss: bool) -> void:
	## Equal-power combat/lull crossfade, the same law Sfx.set_music_intensity uses.
	level = clampf(level, 0.0, 1.0)
	var d := maxf(duck, _duck_sm)
	var base := lerpf(-20.0, -7.0, level) - d * 16.0
	var c_db := base + linear_to_db(maxf(0.001, sin(level * PI / 2.0))) + (2.0 if boss else 0.0)
	var l_db := base + linear_to_db(maxf(0.001, cos(level * PI / 2.0)))
	for s in 2:
		var pr: Array = _pairs[s]
		var g := linear_to_db(maxf(0.001, _pair_gain[s]))
		var tc := c_db + g
		var tl := l_db + g
		pr[0].volume_db = lerpf(pr[0].volume_db, tc, 0.08)
		pr[1].volume_db = lerpf(pr[1].volume_db, tl, 0.08)


func play_sting(name: String) -> bool:
	## Duck the score and fire the one-shot. Returns true when a real stinger file played;
	## false means the (silent) duck-only fallback, which the existing synth cues cover.
	last_sting = name
	var seconds := float(manifest.get("stingers", {}).get(name, {}).get("seconds", FALLBACK_STING_SEC))
	var stream: AudioStream = loader.call("%ssting_%s.ogg" % [MUSIC_DIR, name])
	sting_hold = true
	if stream == null:
		sting_left = FALLBACK_STING_SEC
		return false
	sting_left = maxf(seconds, stream.get_length())
	_sting_player.stream = stream
	_sting_player.volume_db = -4.0
	if _sting_player.is_inside_tree():
		_sting_player.play()
	return true


# --- internals ---------------------------------------------------------------------

func _commit(id: String) -> void:
	current_id = id
	commit_log.append(id)
	var info: Dictionary = manifest.get("tracks", {}).get(id, {})
	var bpm := float(info.get("bpm", FALLBACK_BPM))
	var bpb := int(info.get("beats_per_bar", FALLBACK_BEATS))
	bar_len = 60.0 / maxf(1.0, bpm) * float(maxi(1, bpb))
	var c: AudioStream = _stem(id, "combat")
	var l: AudioStream = _stem(id, "lull")
	var ok := c != null and l != null and absf(c.get_length() - l.get_length()) < 0.01
	if not ok:
		# A stem is missing, unloadable or the pair isn't the same length (it could never stay
		# sample-locked): the synthesized beds carry this track.
		stems_on = false
		if _pair_ok[_slot]:
			_slot = 1 - _slot         # the live pair becomes the outgoing one
			_pair_ok[_slot] = false
			_xfade = 0.0
		else:
			_xfade = 1.0
		_pos = 0.0
		_bar_idx = 0
		_pair_gain_update()
		return
	_slot = 1 - _slot
	var pr: Array = _pairs[_slot]
	pr[0].stream = c
	pr[1].stream = l
	pr[0].volume_db = OFF_DB
	pr[1].volume_db = OFF_DB
	# Both stems start in the same call => the same audio frame => sample-locked.
	if pr[0].is_inside_tree() and pr[1].is_inside_tree():
		pr[0].play()
		pr[1].play()
	start_count += 1
	last_started = [id + "_combat", id + "_lull"]
	_pair_ok[_slot] = true
	stems_on = true
	_xfade = 0.0
	_pos = 0.0
	_bar_idx = 0
	_pair_gain_update()


func _pair_gain_update() -> void:
	var x := _xfade
	var inn := sin(x * PI / 2.0)
	var out := cos(x * PI / 2.0)
	_pair_gain[_slot] = inn if _pair_ok[_slot] else 0.0
	_pair_gain[1 - _slot] = out if _pair_ok[1 - _slot] else 0.0


func _finish_xfade() -> void:
	var old: Array = _pairs[1 - _slot]
	for p in old:
		p.stop()
		p.stream = null
		p.volume_db = OFF_DB
	_pair_ok[1 - _slot] = false


func _stem(id: String, kind: String) -> AudioStream:
	var s: AudioStream = loader.call("%s%s_%s.ogg" % [MUSIC_DIR, id, kind])
	if s == null:
		return null
	_set_loop(s)
	return s


static func _set_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var bytes_per := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
		w.loop_end = w.data.size() / bytes_per
	elif "loop" in s:
		s.set("loop", true)


func _default_loader(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var r = load(path)
	return r as AudioStream


func _load_manifest() -> void:
	var path := MUSIC_DIR + "manifest.json"
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		manifest = parsed
