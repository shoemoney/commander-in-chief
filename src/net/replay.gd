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

## File-format and simulation compatibility are deliberately separate. The
## envelope may grow without changing game rules, while a ruleset bump means
## recorded inputs can no longer be trusted to produce the same run.
const MAGIC := "DETERMINISTIC_REPLAY_2"
const LEGACY_MAGIC := "IKARI_REPLAY_1"
const CURRENT_RULESET_VERSION := 1

const VALIDATION_OK := 0
const VALIDATION_MALFORMED := 1
const VALIDATION_SCORE_MISMATCH := 2
const VALIDATION_UNSUPPORTED_VERSION := 3
const ACCESSIBILITY_BOOL_KEYS: Array[String] = [
	"single_stick_p1", "single_stick_p2", "classic_aim_p1", "classic_aim_p2",
	"toggle_grenade", "toggle_roll", "toggle_interact", "toggle_revive", "toggle_buy", "slow_mode",
]
const ACCESSIBILITY_INTEGER_MAX := {"aim_assist": 2, "shake_level": 10, "flash_level": 10}
const ASSIST_SETTING_KEYS: Array[String] = [
	"single_stick_p1", "single_stick_p2", "classic_aim_p1", "classic_aim_p2", "aim_assist",
	"toggle_grenade", "toggle_roll", "toggle_interact", "toggle_revive", "toggle_buy", "slow_mode",
]

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
var slow_mode: bool = false
var accessibility: Dictionary = {}
var accessibility_changes: Array = []
var assist_tags: Array[String] = []
var verified: bool = false


func record_tick(inputs: Array) -> void:
	var frame: Array = []
	for inp in inputs:
		frame.append(inp.encode())
	frames.append(frame)


func to_dict() -> Dictionary:
	return {"magic": MAGIC, "ruleset": CURRENT_RULESET_VERSION,
		"seed": seed_value, "mode": mode,
		"players": player_count, "assist": assist, "hard": hard, "chapter": chapter,
		"start_vest": start_vest, "start_chest": start_chest, "start_tokens": start_tokens,
		"frames": frames, "score": claimed_score, "verified": verified,
		"slow_mode": slow_mode, "accessibility": accessibility.duplicate(true),
		"accessibility_changes": accessibility_changes.duplicate(true), "assist_tags": assist_tags.duplicate()}


func record_accessibility(config: Dictionary, tags: Array[String]) -> void:
	if frames.is_empty():
		accessibility = config.duplicate(true)
		slow_mode = bool(config.get("slow_mode", false))
	if accessibility_changes.is_empty() or accessibility_changes[-1]["settings"] != config:
		var change := {"frame": frames.size(), "settings": config.duplicate(true)}
		if not accessibility_changes.is_empty() and int(accessibility_changes[-1]["frame"]) == frames.size():
			accessibility_changes[-1] = change
		else:
			accessibility_changes.append(change)
	_merge_assist_tags(tags)
	_merge_assist_tags(assist_tags_for_config(config, player_count, assist))


static func assist_tags_for_config(config: Dictionary, players: int, vest: bool = false) -> Array[String]:
	var tags: Array[String] = []
	if vest:
		tags.append("vest")
	for key in ASSIST_SETTING_KEYS:
		if key.ends_with("p2") and players < 2:
			continue
		if key == "aim_assist":
			var tier: int = int(config.get(key, 0))
			if tier == 1:
				tags.append("aim_low")
			elif tier == 2:
				tags.append("aim_high")
		elif bool(config.get(key, false)):
			tags.append(key)
	return tags


func _merge_assist_tags(tags: Array[String]) -> void:
	for tag in tags:
		if tag not in assist_tags:
			assist_tags.append(tag)


func slow_at(frame: int) -> bool:
	var result := slow_mode
	for change in accessibility_changes:
		if int(change["frame"]) > frame:
			break
		result = bool(change["settings"].get("slow_mode", false))
	return result


static func _valid_accessibility_metadata(data: Dictionary, frame_count: int) -> bool:
	if typeof(data.get("slow_mode", false)) != TYPE_BOOL \
			or typeof(data.get("accessibility", {})) != TYPE_DICTIONARY \
			or typeof(data.get("accessibility_changes", [])) != TYPE_ARRAY \
			or typeof(data.get("assist_tags", [])) != TYPE_ARRAY:
		return false
	var initial: Dictionary = data.get("accessibility", {})
	if not _valid_accessibility_config(initial):
		return false
	if initial.has("slow_mode") and initial["slow_mode"] != data.get("slow_mode", false):
		return false
	var changes: Array = data.get("accessibility_changes", [])
	if changes.size() > frame_count + 1:
		return false
	var previous := -1
	for change in changes:
		if typeof(change) != TYPE_DICTIONARY or typeof(change.get("frame")) not in [TYPE_INT, TYPE_FLOAT] \
				or typeof(change.get("settings")) != TYPE_DICTIONARY:
			return false
		var at := float(change["frame"])
		if not is_finite(at) or at != floor(at) or at < 0 or at > frame_count or int(at) <= previous:
			return false
		if not _valid_accessibility_config(change["settings"]):
			return false
		if int(at) == 0 and data.has("accessibility") and change["settings"] != initial:
			return false
		previous = int(at)
	var tags: Array = data.get("assist_tags", [])
	if tags.size() > 64:
		return false
	var seen := {}
	for tag in tags:
		if typeof(tag) != TYPE_STRING or tag.is_empty() or tag.length() > 64 or seen.has(tag):
			return false
		seen[tag] = true
	return true


static func _valid_accessibility_config(config: Dictionary) -> bool:
	for key in ACCESSIBILITY_BOOL_KEYS:
		if config.has(key) and typeof(config[key]) != TYPE_BOOL:
			return false
	for key in ACCESSIBILITY_INTEGER_MAX:
		if not config.has(key):
			continue
		if typeof(config[key]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var value := float(config[key])
		if not is_finite(value) or value != floor(value) or value < 0 or value > ACCESSIBILITY_INTEGER_MAX[key]:
			return false
	return true


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
	var envelope := _read_envelope(path)
	if envelope["status"] != "ok":
		return null
	return _from_data(envelope["data"])


static func _read_envelope(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"status": "malformed"}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {"status": "malformed"}
	var magic := str(data.get("magic", ""))
	# A recognizable legacy/future envelope is not corrupt and is certainly not
	# evidence of cheating: this executable simply cannot simulate its rules.
	if magic == LEGACY_MAGIC or (magic.begins_with("DETERMINISTIC_REPLAY_") and magic != MAGIC):
		return {"status": "unsupported_version"}
	if magic != MAGIC:
		return {"status": "malformed"}
	# Missing ruleset is legacy-by-definition. Reject it explicitly instead of
	# replaying under today's rules and mislabeling the resulting score mismatch.
	if not data.has("ruleset") or typeof(data["ruleset"]) not in [TYPE_INT, TYPE_FLOAT] \
			or int(data["ruleset"]) != CURRENT_RULESET_VERSION:
		return {"status": "unsupported_version"}
	return {"status": "ok", "data": data}


static func _from_data(data: Dictionary) -> Replay:
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
	if not _valid_accessibility_metadata(data, data["frames"].size()):
		return null
	var r := Replay.new()
	r.slow_mode = data.get("slow_mode", false)
	r.accessibility = data.get("accessibility", {}).duplicate(true)
	r.accessibility_changes = data.get("accessibility_changes", []).duplicate(true)
	for tag in data.get("assist_tags", []):
		r.assist_tags.append(tag)
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
	r._merge_assist_tags(assist_tags_for_config(r.accessibility, r.player_count, r.assist))
	if r.slow_mode:
		r._merge_assist_tags(["slow_mode"])
	for change in r.accessibility_changes:
		r._merge_assist_tags(assist_tags_for_config(change["settings"], r.player_count, r.assist))
	if r.assist_tags.size() > 64:
		return null
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
##   {"code": 3, "reason": "unsupported_version"}             -- valid envelope, foreign rules
static func validate_file(path: String) -> Dictionary:
	var envelope := _read_envelope(path)
	if envelope["status"] == "unsupported_version":
		return {"code": VALIDATION_UNSUPPORTED_VERSION, "reason": "unsupported_version"}
	if envelope["status"] != "ok":
		return {"code": VALIDATION_MALFORMED}
	var r := _from_data(envelope["data"])
	if r == null:
		return {"code": VALIDATION_MALFORMED}
	var actual := r.replay_final_score()
	if actual == r.claimed_score:
		return {"code": VALIDATION_OK, "mode": r.mode, "score": actual, "frames": r.frames.size()}
	return {"code": VALIDATION_SCORE_MISMATCH, "claimed": r.claimed_score, "actual": actual}
