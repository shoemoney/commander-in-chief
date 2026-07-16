class_name Sfx
extends Node
## Procedural SFX for the view layer. Every sound is synthesized once at load
## into an AudioStreamWAV (no audio assets, nothing to license), then fired
## through a single polyphonic player on a dedicated "SFX" bus with a hard
## limiter so stacked MG fire can't clip. View-only: the sim never hears this.

const RATE := 44100   # square-wave synth aliased at 22050 (Nyquist ~11kHz); buffers are tiny

# Tonal jingles/stings keep their key — the ±6% humanizing detune in play() is
# for noise/percussive SFX only (a pitch-wandering "buy" arpeggio reads as a bug).
const _MUSICAL := {"pickup": true, "buy": true, "deny": true, "revive": true,
	"gate_open": true, "wave_start": true, "wave_clear": true, "victory": true,
	"wiped": true, "avenge": true}

var _sounds: Dictionary = {}
var _player := AudioStreamPlayer.new()
var _music := AudioStreamPlayer.new()
var _pb: AudioStreamPlaybackPolyphonic
var _lpf: AudioEffectLowPassFilter   # held by reference, not effect-index


func _ready() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.get_bus_count()
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.add_bus_effect(idx, AudioEffectHardLimiter.new())
	if AudioServer.get_bus_index("Music") == -1:
		var mi := AudioServer.get_bus_count()
		AudioServer.add_bus(mi)
		AudioServer.set_bus_name(mi, "Music")
		AudioServer.set_bus_send(mi, "Master")
	# Concussion low-pass on Master: swept open normally, clamped down for the
	# 'ears ringing, world underwater' beat right after a near-death hit. Held
	# by reference so a later Master effect can't shift its index out from us.
	_lpf = AudioEffectLowPassFilter.new()
	_lpf.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(0, _lpf)
	# Master safety limiter AFTER the LPF: the SFX bus limits itself, but the drum
	# bed sums into Master past it — loud combat + a kick could land ~+2dBFS.
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 32
	_player.stream = poly
	_player.bus = "SFX"
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback()
	_synth_all()
	# War-drums bed: synthesized like everything else, looping under the SFX.
	_music.stream = _synth_drums()
	_music.bus = "Music"
	_music.volume_db = -15.0
	add_child(_music)
	_music.play()


func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _pb == null or not _sounds.has(sound):
		return
	if not _MUSICAL.has(sound):
		pitch *= randf_range(0.94, 1.06)
	_pb.play_stream(_sounds[sound], 0.0, vol_db, pitch)


func set_music_intensity(level: float, duck := 0.0) -> void:
	## Ease the drum bed toward a target intensity (0 = quiet lull heartbeat,
	## 1 = full-tilt combat), minus a fast-attack duck under heavy hits.
	level = clampf(level, 0.0, 1.0)
	var target_db := lerpf(-24.0, -9.0, level) - duck * 16.0
	_music.volume_db = lerpf(_music.volume_db, target_db, 0.15 if duck > 0.3 else 0.04)
	_music.pitch_scale = lerpf(_music.pitch_scale, lerpf(0.9, 1.08, level), 0.04)


func set_concussion(amount: float) -> void:
	## amount 0 = clear (20.5kHz), 1 = fully muffled (~500Hz).
	if _lpf != null:
		_lpf.cutoff_hz = lerpf(20500.0, 500.0, clampf(amount, 0.0, 1.0))


# --- Synthesis toolkit -------------------------------------------------------

static func _nz(i: int) -> float:
	# Stateless hash noise: same sound every run, no RNG state.
	var x := sin(float(i) * 12.9898) * 43758.5453
	return 2.0 * (x - floor(x)) - 1.0


static func _sq(t: float, f: float) -> float:
	return 1.0 if sin(TAU * f * t) >= 0.0 else -1.0


static func _sweep(t: float, f0: float, f1: float, dur: float) -> float:
	# Sine with linearly swept frequency (integrated phase).
	return sin(TAU * (f0 * t + (f1 - f0) * t * t / (2.0 * dur)))


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _notes(freqs: Array[float], note_dur: float, gap := 0.0, square := true) -> PackedFloat32Array:
	# Simple arpeggio: each note decays, optional gap between notes.
	var step := note_dur + gap
	var b := _buf(freqs.size() * step)
	for k in freqs.size():
		var f: float = freqs[k]
		var start := int(k * step * RATE)
		for j in int(note_dur * RATE):
			var t := float(j) / RATE
			var v := (_sq(t, f) if square else sin(TAU * f * t)) * exp(-t * 9.0) * 0.5
			# 6ms release ramp: the decay envelope is still ~53% when the note ends,
			# and that hard step is an audible click on every pickup/buy jingle.
			v *= minf(1.0, (note_dur - t) / 0.006)
			b[start + j] += v
	return b


func _synth_all() -> void:
	var s := {}

	# MG shot: noise crack + swept thump. Short and punchy — it plays a lot.
	var shot := _buf(0.09)
	for i in shot.size():
		var t := float(i) / RATE
		shot[i] = _nz(i) * exp(-t * 55.0) * 0.9 + _sweep(t, 240.0, 150.0, 0.09) * exp(-t * 28.0) * 0.5
	s["shot"] = shot

	# Enemy fire: duller, quieter cousin of the MG so it reads as "not yours".
	var eshot := _buf(0.08)
	for i in eshot.size():
		var t := float(i) / RATE
		eshot[i] = _nz(i * 3 + 7) * exp(-t * 40.0) * 0.5 + sin(TAU * 130.0 * t) * exp(-t * 30.0) * 0.4
	s["enemy_shot"] = eshot

	# Tank cannon: long low sweep + heavy noise.
	var cannon := _buf(0.5)
	for i in cannon.size():
		var t := float(i) / RATE
		cannon[i] = _sweep(t, 150.0, 45.0, 0.5) * exp(-t * 6.0) * 0.9 + _nz(i) * exp(-t * 12.0) * 0.6
	s["tank_shot"] = cannon

	# Grenade throw: quick airy fwip.
	var fwip := _buf(0.12)
	for i in fwip.size():
		var t := float(i) / RATE
		fwip[i] = _sweep(t, 520.0, 160.0, 0.12) * sin(PI * t / 0.12) * 0.5
	s["throw"] = fwip

	# Explosion: crack, darkened-noise body, sub rumble.
	var boom := _buf(0.7)
	var lp := 0.0
	for i in boom.size():
		var t := float(i) / RATE
		lp = lp * 0.96 + _nz(i) * 0.04   # one-pole lowpass = dark rumble noise (coef sqrt'd for 44.1k)
		boom[i] = _nz(i) * exp(-t * 60.0) * 0.9 + lp * 11.0 * exp(-t * 5.0) \
			+ _sweep(t, 95.0, 40.0, 0.7) * exp(-t * 4.5) * 0.7
	s["explosion"] = boom

	# Enemy kill: classic arcade falling blip.
	var kill := _buf(0.15)
	for i in kill.size():
		var t := float(i) / RATE
		kill[i] = _sq(t, 400.0 - t * 2000.0) * exp(-t * 18.0) * 0.45
	s["kill"] = kill

	# Player down: dramatic dive + noise — must cut through everything.
	var down := _buf(0.6)
	for i in down.size():
		var t := float(i) / RATE
		down[i] = _sq(t, 320.0 - t * 450.0) * exp(-t * 5.0) * 0.6 + _nz(i) * exp(-t * 9.0) * 0.35
	s["player_down"] = down

	# Roll: short whoosh (shaped noise).
	var roll := _buf(0.16)
	var lp2 := 0.0
	for i in roll.size():
		var t := float(i) / RATE
		lp2 = lp2 * 0.92 + _nz(i) * 0.08
		var env := sin(PI * t / 0.16)
		roll[i] = lp2 * 4.2 * env * env * 0.8
	s["roll"] = roll

	# Splash: frogman surfacing — dark noise burst with a falling body.
	var splash := _buf(0.3)
	var lp3 := 0.0
	for i in splash.size():
		var t := float(i) / RATE
		lp3 = lp3 * 0.95 + _nz(i) * 0.05
		splash[i] = lp3 * 7.0 * exp(-t * 11.0) + _sweep(t, 300.0, 90.0, 0.3) * exp(-t * 10.0) * 0.4
	s["splash"] = splash

	# Mortar whistle: the falling shell — long, quiet, unmistakable.
	var whis := _buf(0.55)
	for i in whis.size():
		var t := float(i) / RATE
		whis[i] = _sweep(t, 1500.0, 650.0, 0.55) * sin(PI * t / 0.55) * 0.28
	s["whistle"] = whis

	# Alarm: two-tone siren beep (observer spotted, tank on fire).
	var alarm := _buf(0.44)
	for i in alarm.size():
		var t := float(i) / RATE
		var f := 820.0 if fmod(t, 0.22) < 0.11 else 620.0
		alarm[i] = _sq(t, f) * 0.3 * minf(1.0, (0.44 - t) * 14.0)
	s["alarm"] = alarm

	# Vest break: metallic clang — detuned partials + noise snap.
	var clang := _buf(0.28)
	for i in clang.size():
		var t := float(i) / RATE
		clang[i] = (sin(TAU * 1180.0 * t) + sin(TAU * 1620.0 * t) * 0.7 + sin(TAU * 2140.0 * t) * 0.5) \
			* exp(-t * 13.0) * 0.35 + _nz(i) * exp(-t * 50.0) * 0.5
	s["vest_break"] = clang

	# Tank board: mechanical clunk.
	var clunk := _buf(0.18)
	for i in clunk.size():
		var t := float(i) / RATE
		clunk[i] = sin(TAU * 85.0 * t) * exp(-t * 25.0) * 0.9 + _nz(i) * exp(-t * 70.0) * 0.6
	s["tank_board"] = clunk

	# Jingles and blips.
	s["pickup"] = _notes([660.0, 990.0], 0.07)
	s["buy"] = _notes([523.0, 659.0, 784.0], 0.07)
	s["deny"] = _notes([220.0, 196.0], 0.09)
	s["revive"] = _notes([392.0, 523.0, 659.0], 0.08, 0.0, false)
	s["gate_open"] = _notes([392.0, 494.0, 587.0, 784.0], 0.1)
	s["wave_start"] = _notes([262.0, 330.0], 0.14)
	s["wave_clear"] = _notes([523.0, 659.0, 784.0], 0.1)
	s["victory"] = _notes([523.0, 587.0, 659.0, 784.0, 1047.0], 0.16)

	# Heartbeat: lub-dub for the last-stand dread bed.
	var heart := _buf(0.5)
	for i in heart.size():
		var t := float(i) / RATE
		var v := _sweep(t, 90.0, 45.0, 0.12) * exp(-t * 22.0) * 0.9
		if t > 0.18:
			var t2 := t - 0.18
			v += _sweep(t2, 78.0, 40.0, 0.12) * exp(-t2 * 22.0) * 0.6
		heart[i] = v
	s["heartbeat"] = heart

	# Whiz: a short descending zip for a round cracking past the ear.
	var whiz := _buf(0.09)
	for i in whiz.size():
		var t := float(i) / RATE
		whiz[i] = _sweep(t, 2600.0, 900.0, 0.09) * sin(PI * t / 0.09) * 0.35
	s["whiz"] = whiz

	# Wiped: descending death-march resolve — the endless run is over.
	s["wiped"] = _notes([294.0, 247.0, 196.0, 147.0], 0.2, 0.03, false)

	# Avenge: short rising two-note sting — a kill by a downed ally.
	s["avenge"] = _notes([523.0, 784.0], 0.09, 0.0, false)

	for k in s:
		_sounds[k] = _to_wav(s[k])


func _synth_drums() -> AudioStreamWAV:
	# Two bars of jungle war drums at 110 BPM (8th-note grid), seamless loop.
	var step := int(RATE * 60.0 / 110.0 / 2.0)
	var pattern: Array[Array] = [   # per 8th step: [kick, tom_hi, tom_lo, snare]
		[1, 0, 0, 0], [0, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
		[0, 0, 0, 1], [0, 0, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0],
		[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 0],
		[0, 0, 0, 1], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1],
	]
	var buf := _buf(float(step * pattern.size()) / RATE)
	for k in pattern.size():
		var ofs := k * step
		var hit := pattern[k]
		for j in int(0.25 * RATE):
			if ofs + j >= buf.size():
				break
			var t := float(j) / RATE
			var v := 0.0
			if hit[0]:
				v += _sweep(t, 95.0, 42.0, 0.25) * exp(-t * 14.0) * 0.85
			if hit[1]:
				v += sin(TAU * 138.0 * t) * exp(-t * 20.0) * 0.4
			if hit[2]:
				v += sin(TAU * 96.0 * t) * exp(-t * 16.0) * 0.45
			if hit[3]:
				v += _nz(ofs + j) * exp(-t * 24.0) * 0.3 + sin(TAU * 190.0 * t) * exp(-t * 28.0) * 0.2
			buf[ofs + j] += v
	var wav := _to_wav(buf)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = buf.size()
	return wav
