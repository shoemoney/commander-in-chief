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
# Pitch-laddered grammar sounds: their exact pitch IS the information (alarm's
# threat-ID steps, the kill blip's +0.06/streak rise), so the ±6% humanize would
# swamp adjacent steps — play them dead on pitch.
const _LADDERED := {"alarm": true, "kill": true}

var _sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _player := AudioStreamPlayer.new()
var _ui_player := AudioStreamPlayer.new()   # jingles/stings: own bus, no combat limiter
var _music := AudioStreamPlayer.new()
var _shot_rr := 0   # MG shot round-robin cursor
var _music_lull := AudioStreamPlayer.new()   # sparse lull bed, phase-locked to _music
var _pb: AudioStreamPlaybackPolyphonic
var _ui_pb: AudioStreamPlaybackPolyphonic
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
	if AudioServer.get_bus_index("UI") == -1:
		# Reward jingles bypass the SFX limiter: MG-spam pumping was ducking the
		# buy/pickup/victory cues at the exact moment they fired (8/9 panel vote).
		# Master's own limiter still backstops the sum.
		var ui := AudioServer.get_bus_count()
		AudioServer.add_bus(ui)
		AudioServer.set_bus_name(ui, "UI")
		AudioServer.set_bus_send(ui, "Master")
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
	var ui_poly := AudioStreamPolyphonic.new()
	ui_poly.polyphony = 8
	_ui_player.stream = ui_poly
	_ui_player.bus = "UI"
	add_child(_ui_player)
	_ui_player.play()
	_ui_pb = _ui_player.get_stream_playback()
	# Positional pool: the game draws in 640x360 screen space with no Camera2D,
	# so a listener pinned at screen center anchors the stereo pan. Gentle
	# attenuation only — arcade panning, not distance silence. (Sfx is a plain
	# Node, so these Node2Ds sit outside main's shake/zoom chain — shake-immune.)
	var listener := AudioListener2D.new()
	listener.position = Vector2(320, 180)
	add_child(listener)
	listener.make_current()
	for i in 12:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 700.0
		p.attenuation = 1.0
		add_child(p)
		_pool.append(p)
	_synth_all()
	# War-drums bed: synthesized like everything else, looping under the SFX.
	# TWO phase-locked loops on the same 110 BPM grid — full combat phrase and a
	# sparse kick/low-tom lull — crossfaded by set_music_intensity, so a lull is
	# a different PATTERN, not just full combat played quieter. Both start
	# together and always share a pitch_scale, so the bars never drift.
	# 4-bar A+B combat loop (3-vote: the single 2-bar phrase was the HATE) —
	# same grid/BPM, so the lull loop stays bar-aligned at half length.
	var _combat_ab: Array[Array] = []
	_combat_ab.append_array(_PATTERN_COMBAT)
	_combat_ab.append_array(_PATTERN_COMBAT_B)
	_music.stream = _synth_drums(_combat_ab)
	_music.bus = "Music"
	_music.volume_db = -15.0
	add_child(_music)
	_music_lull.stream = _synth_drums(_PATTERN_LULL)
	_music_lull.bus = "Music"
	_music_lull.volume_db = -60.0
	add_child(_music_lull)
	_music.play()
	_music_lull.play()


func _rr_shot(sound: String) -> String:
	## MG round-robin: view-only variety, no determinism stake (randf detune
	## precedent) — a counter, not a hash.
	if sound == "shot":
		_shot_rr = (_shot_rr + 1) % 3
		return "shot" if _shot_rr == 0 else "shot%d" % _shot_rr
	return sound


func play(sound: String, vol_db := 0.0, pitch := 1.0) -> void:
	sound = _rr_shot(sound)
	if _pb == null or not _sounds.has(sound):
		return
	if _MUSICAL.has(sound):
		if _ui_pb != null:   # jingles ride the unlimited UI bus, in key
			_ui_pb.play_stream(_sounds[sound], 0.0, vol_db, pitch)
		return
	if not _LADDERED.has(sound):   # pitch-ladder grammar plays dead on pitch
		pitch *= randf_range(0.94, 1.06)
	_pb.play_stream(_sounds[sound], 0.0, vol_db, pitch)


func play_at(sound: String, screen_pos: Vector2, vol_db := 0.0, pitch := 1.0) -> void:
	sound = _rr_shot(sound)
	if _pool.is_empty() or not _sounds.has(sound):
		return
	if _MUSICAL.has(sound):
		# Jingles are screen-global rewards: same UI-bus routing as play() (the
		# MG-spam limiter was ducking positional gate_open/revive cues), centered.
		if _ui_pb != null:
			_ui_pb.play_stream(_sounds[sound], 0.0, vol_db, pitch)
		return
	if not _LADDERED.has(sound):
		pitch *= randf_range(0.94, 1.06)
	# Steal policy: prefer an idle voice; else take the one closest to finishing —
	# index-0 stealing cut long booms mid-tail under heavy fire.
	var p: AudioStreamPlayer2D = _pool[0]
	var best_done := -1.0
	for c in _pool:
		if not c.playing:
			p = c
			break
		var done := c.get_playback_position() / maxf(0.05, c.stream.get_length())
		if done > best_done:
			best_done = done
			p = c
	p.position = screen_pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.stream = _sounds[sound]
	p.play()


func set_music_intensity(level: float, duck := 0.0) -> void:
	## Ease the drum bed toward a target intensity (0 = sparse lull pattern,
	## 1 = full-tilt combat phrase), minus a fast-attack duck under heavy hits.
	## Equal-power crossfade between the two phase-locked loops; mix by volume
	## only — never stop/restart one, or the bars lose phase alignment.
	level = clampf(level, 0.0, 1.0)
	var rate := 0.15 if duck > 0.3 else 0.04
	var base_db := lerpf(-24.0, -9.0, level) - duck * 16.0
	var combat_db := base_db + linear_to_db(maxf(0.001, sin(level * PI / 2.0)))
	var lull_db := base_db + linear_to_db(maxf(0.001, cos(level * PI / 2.0)))
	_music.volume_db = lerpf(_music.volume_db, combat_db, rate)
	_music_lull.volume_db = lerpf(_music_lull.volume_db, lull_db, rate)
	var p := lerpf(_music.pitch_scale, lerpf(0.9, 1.08, level), 0.04)
	_music.pitch_scale = p
	_music_lull.pitch_scale = p   # identical playback speed = zero drift


func set_concussion(amount: float) -> void:
	## amount 0 = clear (20.5kHz), 1 = fully muffled (~500Hz).
	if _lpf != null:
		var a := clampf(amount, 0.0, 1.0)
		_lpf.cutoff_hz = lerpf(20500.0, 500.0, a)
		# Resonant peak at the cutoff: a flat LPF sweep is just a blanket — the
		# bump adds the boxy 'underwater, ears ringing' coloration the beat wants.
		_lpf.resonance = lerpf(0.5, 2.4, a)


# --- Synthesis toolkit -------------------------------------------------------

static func _nz(i: int) -> float:
	# Stateless hash noise: same sound every run, no RNG state.
	var x := sin(float(i) * 12.9898) * 43758.5453
	return 2.0 * (x - floor(x)) - 1.0


static func _sq(t: float, f: float) -> float:
	return 1.0 if sin(TAU * f * t) >= 0.0 else -1.0


static func _sqbl(t: float, f: float) -> float:
	# Band-limited square: odd-harmonic sum capped below Nyquist. The naive ±1
	# square aliases its upper harmonics into inharmonic grit — audible on the
	# tonal cues even at 44.1k. Synthesis is load-time, so the loop is free.
	var v := 0.0
	var k := 1.0
	while k * f < RATE * 0.45 and k <= 19.0:
		v += sin(TAU * f * k * t) / k
		k += 2.0
	return v * (4.0 / PI) * 0.85


static func _sweep(t: float, f0: float, f1: float, dur: float) -> float:
	# Sine with linearly swept frequency (integrated phase).
	return sin(TAU * (f0 * t + (f1 - f0) * t * t / (2.0 * dur)))


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	# Shared tail declick: several exp-decay buffers (explosion ~0.05-0.10,
	# splash ~0.07) are still audible at the hard cut — ramp the last 5ms to
	# zero here so every synth inherits it (the 6ms ramp in _notes is note-level).
	var fade := mini(int(0.005 * RATE), samples.size())
	for k in fade:
		samples[samples.size() - fade + k] *= 1.0 - float(k + 1) / float(fade)
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
			var v := (_sqbl(t, f) if square else sin(TAU * f * t)) * exp(-t * 9.0) * 0.5
			# 6ms release ramp: the decay envelope is still ~53% when the note ends,
			# and that hard step is an audible click on every pickup/buy jingle.
			v *= minf(1.0, (note_dur - t) / 0.006)
			b[start + j] += v
	return b


func _synth_all() -> void:
	var s := {}

	# MG shot: noise crack + swept thump. Short and punchy — it plays a lot.
	# 3 variants round-robined in play() — the +/-6% detune alone couldn't hide
	# one buffer firing 8x/sec (4-vote). Same recipe, offset noise seed, crack
	# decay {55,46,64}, thump mix {0.5,0.62,0.40}; variant 0 IS the old shot.
	var shot_seed := [0, 1000, 2000]
	var shot_decay := [55.0, 46.0, 64.0]
	var shot_thump := [0.5, 0.62, 0.40]
	for sv in 3:
		var shot := _buf(0.09)
		for i in shot.size():
			var t := float(i) / RATE
			shot[i] = _nz(i + shot_seed[sv]) * exp(-t * shot_decay[sv]) * 0.9 \
				+ _sweep(t, 240.0, 150.0, 0.09) * exp(-t * 28.0) * shot_thump[sv]
		s["shot" if sv == 0 else "shot%d" % sv] = shot

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
		# 3-vote: a 2.2 kHz band-limited tick ahead of the falling blip — the
		# confirmation lands above explosion rumble instead of inside it.
		kill[i] = _sqbl(t, maxf(60.0, 400.0 - t * 2000.0)) * exp(-t * 18.0) * 0.45 \
			+ _sqbl(t, 2200.0) * exp(-t * 250.0) * 0.4
	s["kill"] = kill

	# Player down: dramatic dive + noise — must cut through everything.
	var down := _buf(0.6)
	for i in down.size():
		var t := float(i) / RATE
		# The one sound allowed to own the mix (7-vote): a 60->30 Hz sub layer
		# under the dive + a 60 ms attack ramp so it swells INTO the duck the
		# view already applies, instead of clipping on at full scale.
		var dv := _sqbl(t, maxf(50.0, 320.0 - t * 450.0)) * exp(-t * 5.0) * 0.6 \
			+ _nz(i) * exp(-t * 9.0) * 0.35 + _sweep(t, 60.0, 30.0, 0.6) * 0.5
		down[i] = dv * minf(1.0, t / 0.06)
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
	var aph := 0.0   # accumulated phase: sin(TAU*f*t) with stepping f jumped
	for i in alarm.size():   # phase at each 820<->620 toggle = a click every 0.11s
		var t := float(i) / RATE
		var f := 820.0 if fmod(t, 0.22) < 0.11 else 620.0
		aph += TAU * f / RATE
		# Band-limited square on the ACCUMULATED phase (the naive sign-square
		# aliased its upper harmonics into fatigue grit — 7-vote panel HATE).
		# Same odd-harmonic recipe as _sqbl, kept inline to ride aph.
		var av := 0.0
		var ak := 1.0
		while ak * f < RATE * 0.45 and ak <= 19.0:
			av += sin(aph * ak) / ak
			ak += 2.0
		alarm[i] = av * (4.0 / PI) * 0.85 * 0.3 * minf(1.0, (0.44 - t) * 14.0)
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
	# Whiz v2 (5-vote): the old 2600->900 Hz zip lived inside the shot cracks'
	# spectrum and vanished under fire. Now a high-passed air CRACK with a thin
	# 4000->2200 Hz zip for pitch identity — above both shot voices.
	var whiz := _buf(0.07)
	var wlp := 0.0
	for i in whiz.size():
		var t := float(i) / RATE
		wlp = wlp * 0.9 + _nz(i) * 0.1
		whiz[i] = (_nz(i) - wlp) * exp(-t * 45.0) * 0.5 + _sweep(t, 4000.0, 2200.0, 0.07) * 0.15
	s["whiz"] = whiz

	# Wiped: descending death-march resolve — the endless run is over.
	s["wiped"] = _notes([294.0, 247.0, 196.0, 147.0], 0.2, 0.03, false)

	# Avenge: short rising two-note sting — a kill by a downed ally.
	s["avenge"] = _notes([523.0, 784.0], 0.09, 0.0, false)

	# Rev: rising engine growl — the technical's charge counter-tell. Sawtooth
	# body sweeping ~55→160 Hz (accumulated phase, like the alarm) under a
	# swelling envelope, plus a thin lowpassed-noise intake layer.
	var rev := _buf(0.35)
	var rph := 0.0
	var lp5 := 0.0
	for i in rev.size():
		var t := float(i) / RATE
		rph += (55.0 + 300.0 * t) / RATE   # 55 Hz idle rising to ~160 Hz at the top
		lp5 = lp5 * 0.9 + _nz(i) * 0.1
		rev[i] = ((fmod(rph, 1.0) * 2.0 - 1.0) * 0.4 + lp5 * 1.2) \
			* (0.25 + 0.75 * t / 0.35) * minf(1.0, (0.35 - t) * 30.0)
	s["rev"] = rev

	# Flash: flashbang detonation — ~8 ms full-scale noise snap, then a decaying
	# ~3.2 kHz sine ring whose fade telegraphs the stun window closing.
	var flash := _buf(0.5)
	var fbell_lp := 0.0
	for i in flash.size():
		var t := float(i) / RATE
		# Soften (3-vote): pure 3.2 kHz sine ring -> dual-sine bell through a
		# CLOSING one-pole, so the ring darkens as it fades. The exp(-t*7)
		# envelope is untouched — that decay IS the loved stun-window telegraph.
		var fbell := sin(TAU * 1800.0 * t) + 0.7 * sin(TAU * 3100.0 * t)
		var fa := lerpf(0.5, 0.05, minf(1.0, t * 2.0))
		fbell_lp = fbell_lp * (1.0 - fa) + fbell * fa
		flash[i] = _nz(i) * exp(-t * 120.0) * 0.9 + fbell_lp * exp(-t * 7.0) * 0.3
	s["flash"] = flash

	for k in s:
		_sounds[k] = _to_wav(s[k])


# Per 8th step: [kick, tom_hi, tom_lo, snare]. Same 16-step grid, same BPM —
# the two loops are the same length in samples, so they stay bar-aligned.
const _PATTERN_COMBAT: Array[Array] = [
	[1, 0, 0, 0], [0, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
	[0, 0, 0, 1], [0, 0, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0],
	[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 0],
	[0, 0, 0, 1], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1],
]
const _PATTERN_COMBAT_B: Array[Array] = [   # answer phrase: same kick anchors,
	[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0],   # snare displaced to
	[0, 0, 0, 0], [0, 0, 0, 1], [0, 1, 0, 0], [0, 0, 0, 0],   # off-beats, tom fill
	[1, 0, 0, 0], [0, 0, 0, 1], [0, 0, 1, 0], [0, 1, 0, 0],   # call-and-response
	[0, 1, 0, 0], [0, 0, 1, 0], [0, 1, 1, 0], [0, 0, 0, 1],   # closing the 4 bars
]
const _PATTERN_LULL: Array[Array] = [   # kick + low tom only: a wary heartbeat
	[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
	[0, 0, 1, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
	[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 1, 0], [0, 0, 0, 0],
	[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
]


func _synth_drums(pattern: Array[Array]) -> AudioStreamWAV:
	# Two bars of jungle war drums at 110 BPM (8th-note grid), seamless loop.
	var step := int(RATE * 60.0 / 110.0 / 2.0)
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
