extends SceneTree
## Offline seed/balance sweep — the "40-seed audition".
##
##   godot --headless --path . -s res://tools/sweep.gd
##
## Fans out NUM_SEEDS independent SimWorld runs across WorkerThreadPool
## (each SimWorld is a self-contained RefCounted, so one per task is
## thread-safe — no shared sim state). Each run steps a fixed light
## fire/move input policy for TICKS ticks, then records a digest.
## Results print as a table sorted by a simple "drama" score.

const NUM_SEEDS := 40
const TICKS := 3600

var results: Array[Dictionary] = []


func _init() -> void:
	results.resize(NUM_SEEDS)
	var group_id := WorkerThreadPool.add_group_task(_run_one, NUM_SEEDS)
	WorkerThreadPool.wait_for_group_task_completion(group_id)

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["drama"] > b["drama"])

	print("%-6s %-8s %-6s %-8s %-8s %s" % ["seed", "drama", "wave", "score", "deaths", "checksum"])
	for r in results:
		print("%-6d %-8d %-6d %-8d %-8d %d" % [r["seed"], r["drama"], r["wave"], r["score"], r["deaths"], r["checksum"]])
	quit(0)


func _run_one(index: int) -> void:
	var sim := SimWorld.new(index, 1, "campaign")
	for tick in TICKS:
		sim.step([_scripted_input(tick)])
	var deaths: int = sim.players[0]["deaths"]
	results[index] = {
		"seed": index,
		"score": sim.score,
		"wave": sim.wave,
		"deaths": deaths,
		"checksum": sim.checksum(),
		"drama": sim.score + sim.wave * 1000 - deaths * 100,
	}


## Light fire/move policy: walk forward, strafe gently, fire almost always,
## toss the odd grenade. Not the determinism-test torture script — this is
## meant to look like a plausible casual run, not stress every system.
static func _scripted_input(tick: int) -> SimInput:
	var inp := SimInput.new()
	inp.move_x = [-128, 0, 128, 0][(tick / 50) % 4]
	inp.move_y = -256
	inp.aim_x = 0
	inp.aim_y = -256
	inp.fire = true
	inp.grenade = (tick % 180) == 0
	return inp
