extends SceneTree
## TEMP probe: how far off is the DRAWN mg_nest telegraph lane from the bullet
## that lane promised? Also sweeps the other four aim-locked shooters.

const F := 65536


const Main := preload("res://src/main.gd")


func _lane_dir(sim: SimWorld, e: Dictionary) -> Vector2:
	# EXACTLY what the enemy draw path paints — same single source.
	return Main.telegraph_dir(sim, e)


func _run(kind: String, range_px: int, label: String) -> void:
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	var p: Dictionary = sim.players[0]
	var nx: int = 320 * F
	var ny: int = p["y"] - range_px * F
	if kind == "mg_nest":
		sim._spawn_mg_nest(nx, ny)
	else:
		sim._spawn_special(nx, ny, kind)
	var e: Dictionary = sim.enemies[-1]
	var inp := SimInput.new()
	inp.move_x = 256
	var worst := 0.0
	var worst_perp := 0.0
	var rounds := 0
	var prev_dir := Vector2.ZERO
	var prev_bullets := sim.enemy_bullets.size()
	for t in 400:
		prev_dir = _lane_dir(sim, e)
		var pxx: float = float(p["x"]) / F
		var pyy: float = float(p["y"]) / F
		var exx: float = float(e["x"]) / F
		var eyy: float = float(e["y"]) / F
		sim.step([inp])
		if not e.get("alive", false):
			break
		if sim.enemy_bullets.size() > prev_bullets:
			var b: Dictionary = sim.enemy_bullets[-1]
			var bd := Vector2(float(b["vx"]), float(b["vy"]))
			if prev_dir.length() > 1.0 and bd.length() > 0.0:
				var ang: float = rad_to_deg(absf(prev_dir.normalized().angle_to(bd.normalized())))
				# perpendicular miss distance of the DRAWN lane from the player at fire time
				var ld := prev_dir.normalized()
				var rel := Vector2(pxx - exx, pyy - eyy)
				var perp: float = absf(rel.x * ld.y - rel.y * ld.x)
				rounds += 1
				worst = maxf(worst, ang)
				worst_perp = maxf(worst_perp, perp)
				print("   [%s r%d] t=%d lane-vs-bullet %.1f deg, drawn lane misses player by %.1f px"
					% [label, rounds, t, ang, perp])
		prev_bullets = sim.enemy_bullets.size()
	print("[%s @%dpx] rounds=%d WORST angle %.1f deg, worst perp %.1f px"
		% [label, range_px, rounds, worst, worst_perp])


func _initialize() -> void:
	for r in [140, 213, 318]:
		_run("mg_nest", r, "mg_nest")
	for k in ["sniper", "ghillie", "technical"]:
		_run(k, 213, k)
	quit()
