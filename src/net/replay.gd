class_name Replay
extends RefCounted
## Deterministic replay recorder/player. A run is fully described by its seed,
## mode, player count, and the ordered per-tick inputs — the sim is pure. This
## records exactly that (inputs via SimInput.encode) and can rebuild a fresh
## SimWorld and re-step it to reproduce the run bit-for-bit.
##
## Uses: desync-repro (attach a replay to a bug report), the audited-seed
## trailer (record once, replay deterministically), regression captures, and
## replay-validated leaderboards (verify_score() below) -- a Daily/Endless
## submission is only as trustworthy as the deterministic re-simulation that
## can reproduce it, so every saved replay carries the score it claims to
## have earned and can be checked against its own recorded inputs.
## View-only tooling — the sim is never touched, so it's determinism-safe.

const MAGIC := "IKARI_REPLAY_1"

var seed_value: int = 0
var mode: String = "campaign"
var player_count: int = 1
var assist: bool = false   # accessibility 2-hit vest — MUST be restored on replay or the sim diverges
var hard: bool = false     # NG+ HARD spawn curve — alters the RNG stream + checksum, restore on replay
var chapter: int = 1       # authored-campaign-and-modes: Arcade's jump_to_chapter() start gate (1 = no jump)
# run-config-single-owner: the RESOLVED starting loadout the live run was seeded with,
# never the rules that produced it. main._reset() applies Endless perk TIERS post-
# construction from LIVE _perk_levels; a replay rebuilt from tiers would pick up
# whatever the player owns TODAY. Recording resolved values makes the replay
# self-describing, so Replay never learns a perk system exists.
var start_vest: bool = false   # every player begins with a Flak Vest (assist OR VETERAN VEST perk)
var start_chest: int = 0       # War Chest at tick 0 (HEAD START perk tiers)
var start_tokens: int = 0      # Commendations at tick 0 (SIGNAL FLARE perk tiers)
var frames: Array = []   # each element: Array of per-player encoded SimInput ([move_x,move_y,aim_x,aim_y,flags])
# replay-validated-leaderboards: the score the live run's sim reported, carried
# alongside the recorded inputs so ANY leaderboard/Hall submission can be
# re-checked against the deterministic replay that (allegedly) earned it.
var claimed_score: int = 0
var last_score: int = 0   # set by play() -- the score the re-simulated frames actually produced
# Whether the score above already cleared main.gd's synchronous pre-bank gate
# (Replay.verify_score) at the moment this replay was saved. save_and_verify
# corrects this in place if it ever disagrees with a fresh disk-read-back check.
var verified: bool = false


func record_tick(inputs: Array) -> void:
	var frame: Array = []
	for inp in inputs:
		frame.append(inp.encode())
	frames.append(frame)


func to_dict() -> Dictionary:
	return {"magic": MAGIC, "seed": seed_value, "mode": mode,
		"players": player_count, "assist": assist, "hard": hard, "chapter": chapter,
		"start_vest": start_vest, "start_chest": start_chest, "start_tokens": start_tokens,
		"frames": frames, "score": claimed_score, "verified": verified}


func save(path: String) -> Error:
	return save_dict(to_dict(), path)


static func save_dict(d: Dictionary, path: String) -> Error:
	## Pure-data write, safe to run on a WorkerThreadPool thread (no scene tree,
	## no member state) — main.gd hands it a snapshot so the debrief frame
	## doesn't pay for JSON.stringify of the whole run.
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d))
	return OK


## Same as save_dict, but immediately re-simulates the frames just written and
## re-writes the file if its own "verified" flag turns out to be wrong. Runs
## on the SAME WorkerThreadPool task as the save (see main.gd), so it never
## costs a debrief-frame hitch. A mismatch can't happen from a legit run --
## the sim is pure and deterministic, so replaying the exact recorded inputs
## always reproduces the exact score they earned -- it only fires when disk
## I/O itself corrupted something, or the caller's "verified" flag (main.gd's
## own pre-write gate) somehow disagreed with what's actually on disk. Either
## way the on-disk flag is corrected here so it never contradicts the real
## check. tools/validate_replay.gd runs the same underlying check
## (Replay.validate_file) offline against any submitted replay file.
static func save_and_verify(d: Dictionary, path: String) -> Error:
	var err := save_dict(d, path)
	if err != OK:
		return err
	var r := load_from(path)
	var actually_verified := r != null and r.verify_score(int(d.get("score", 0)))
	if not actually_verified:
		push_warning("Replay: saved run's score does not match its own replay -- flagging as unverified for the leaderboard")
	if bool(d.get("verified", true)) != actually_verified:
		# The claimed "verified" flag disagreed with the disk-read-back check --
		# correct it in place so a stale/wrong flag is never left on disk.
		d["verified"] = actually_verified
		return save_dict(d, path)
	return err


static func load_from(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or data.get("magic", "") != MAGIC:
		return null
	# These files arrive from other machines (bug reports) — a trust boundary.
	# Validate every field rather than relying on error-abort behavior.
	if not (data.has("seed") and data.has("mode") and data.has("players") and data.has("frames")):
		return null
	if typeof(data["frames"]) != TYPE_ARRAY:
		return null
	# Validate each frame's SHAPE, not just that `frames` is an array — a malformed but
	# well-typed file (frame not an array, or an encoded input shorter than the 5 fields
	# SimInput.decode indexes) would pass the outer gate and crash later in decode(). Reject
	# it at the trust boundary instead.
	for frame in data["frames"]:
		if typeof(frame) != TYPE_ARRAY:
			return null
		for enc in frame:
			if typeof(enc) != TYPE_ARRAY or (enc as Array).size() < 5:
				return null
	var r := Replay.new()
	r.seed_value = int(data["seed"])
	r.mode = str(data["mode"])
	r.player_count = int(data["players"])
	# assist/hard default false for pre-existing replays that predate these fields (back-compat).
	r.assist = bool(data.get("assist", false))
	r.hard = bool(data.get("hard", false))
	r.chapter = int(data.get("chapter", 1))   # pre-existing replays predate Arcade -> chapter 1 (no jump)
	# Defaults are the vanilla loadout, so replays predating the perk system load unchanged.
	r.start_vest = bool(data.get("start_vest", false))
	r.start_chest = int(data.get("start_chest", 0))
	r.start_tokens = int(data.get("start_tokens", 0))
	r.frames = data["frames"]
	# score/verified default 0/false for pre-existing replays that predate
	# replay-validated leaderboards.
	r.claimed_score = int(data.get("score", 0))
	r.verified = bool(data.get("verified", false))
	return r


## THE single owner of "what configuration was this run started with". Used by
## _new_sim() (replay verification) AND by main.start_watch(), whose _reset() builds
## from the LIVE assist/HARD toggles and the perk tiers owned right now. Every field is
## ASSIGNED, never accumulated, so this also OVERWRITES a config _reset() already
## applied from stale live state. Safe on a fresh sim: SimWorld starts at
## war_chest 0 / tokens 0 / vest false, so a legacy replay's defaults are a no-op.
func apply_config(sim: SimWorld) -> void:
	sim.assist_mode = assist
	sim.hard = hard
	for pl in sim.players:
		pl["vest"] = assist or start_vest
	sim.war_chest = start_chest
	sim.tokens = start_tokens


func _new_sim() -> SimWorld:
	# Shared setup between play() and replay_final_score() — mirrors the
	# post-construction config main.gd applies to the LIVE run (see _reset),
	# or an assist/hard/arcade/perked run replays as a vanilla one: those all feed
	# checksum()/score, so omitting any of them makes the replay diverge.
	var sim := SimWorld.new(seed_value, player_count, mode)
	apply_config(sim)
	if mode == "arcade":
		# Deliberately OUTSIDE apply_config: start_watch()'s _reset() already performs
		# this jump from _arcade_chapter, and jump_to_chapter is not known-idempotent.
		sim.jump_to_chapter(chapter)   # mirror main._reset()'s post-construction Arcade jump
	return sim


## Rebuild a fresh sim and re-step the recorded inputs, sampling checksums at
## `sample_every` ticks. The returned samples must equal those from the live
## run on any platform — the cross-arch determinism proof, replayable on demand.
## Also stashes the final score in last_score for replay_final_score()/verify_score().
func play(sample_every := 0) -> Array[int]:
	var sim := _new_sim()
	var samples: Array[int] = []
	for i in frames.size():
		var inputs: Array = []
		for enc in frames[i]:
			inputs.append(SimInput.decode(enc))
		sim.step(inputs)
		if sample_every > 0 and (i + 1) % sample_every == 0:
			samples.append(sim.checksum())
	last_score = sim.score
	return samples


## Re-simulates every recorded frame from scratch and returns the TRUE final
## score -- the anti-cheat ground truth a leaderboard submission is checked
## against. A memory-edited sim.score never touches the recorded inputs, so
## this always recomputes the score the player actually earned from them.
func replay_final_score() -> int:
	play()
	return last_score


## True iff replaying the recorded inputs from scratch actually produces
## `claimed` -- the check every Hall of Fame bank / Steam leaderboard upload
## and tools/validate_replay.gd run before trusting a submitted score.
func verify_score(claimed: int) -> bool:
	return replay_final_score() == claimed


## The decision logic behind tools/validate_replay.gd, factored out here so it
## is unit-testable (see tests/test_leaderboard.gd) without spawning a nested
## Godot process just to exercise exit-code plumbing. Returns a Dictionary:
##   {"code": 0, "mode": ..., "score": ..., "frames": ...}  -- verified
##   {"code": 1}                                            -- missing/malformed file
##   {"code": 2, "claimed": ..., "actual": ...}              -- CHEAT DETECTED
static func validate_file(path: String) -> Dictionary:
	var r := load_from(path)
	if r == null:
		return {"code": 1}
	var actual := r.replay_final_score()
	if actual == r.claimed_score:
		return {"code": 0, "mode": r.mode, "score": actual, "frames": r.frames.size()}
	return {"code": 2, "claimed": r.claimed_score, "actual": actual}
