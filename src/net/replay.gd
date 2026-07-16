class_name Replay
extends RefCounted
## Deterministic replay recorder/player. A run is fully described by its seed,
## mode, player count, and the ordered per-tick inputs — the sim is pure. This
## records exactly that (inputs via SimInput.encode) and can rebuild a fresh
## SimWorld and re-step it to reproduce the run bit-for-bit.
##
## Uses: desync-repro (attach a replay to a bug report), the audited-seed
## trailer (record once, replay deterministically), and regression captures.
## View-only tooling — the sim is never touched, so it's determinism-safe.

const MAGIC := "IKARI_REPLAY_1"

var seed_value: int = 0
var mode: String = "campaign"
var player_count: int = 1
var frames: Array = []   # each element: Array of per-player encoded SimInput ([move_x,move_y,aim_x,aim_y,flags])


func record_tick(inputs: Array) -> void:
	var frame: Array = []
	for inp in inputs:
		frame.append(inp.encode())
	frames.append(frame)


func to_dict() -> Dictionary:
	return {"magic": MAGIC, "seed": seed_value, "mode": mode,
		"players": player_count, "frames": frames}


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
	var r := Replay.new()
	r.seed_value = int(data["seed"])
	r.mode = str(data["mode"])
	r.player_count = int(data["players"])
	r.frames = data["frames"]
	return r


## Rebuild a fresh sim and re-step the recorded inputs, sampling checksums at
## `sample_every` ticks. The returned samples must equal those from the live
## run on any platform — the cross-arch determinism proof, replayable on demand.
func play(sample_every := 0) -> Array[int]:
	var sim := SimWorld.new(seed_value, player_count, mode)
	var samples: Array[int] = []
	for i in frames.size():
		var inputs: Array = []
		for enc in frames[i]:
			inputs.append(SimInput.decode(enc))
		sim.step(inputs)
		if sample_every > 0 and (i + 1) % sample_every == 0:
			samples.append(sim.checksum())
	return samples
