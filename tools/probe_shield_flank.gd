extends SceneTree
## Can a SOLO player earn the riot shield's rear arc by circling it? The banner says
## "FLANK OR BLOW IT OPEN"; this measures whether the first half is true.
## The player circles the shield at full run speed at a held radius (the radial
## component pays for the shield's own advance), clockwise or counter-clockwise,
## from several start bearings. A trial SUCCEEDS the first tick a shot from the
## player's position is NOT blocked. A player who never circles is the control and
## must score 0 (a frontal shot is always blocked).
##
##   godot --headless --path . -s res://tools/probe_shield_flank.gd

const RANGES := [60, 90, 120, 150, 200]
const START_DEG := [0, 45, 90, 135, 180, 225, 270, 315]
const TRIAL_TICKS := 400


func _trial(range_px: int, start_deg: int, dir: int, circle: bool) -> int:
	## Returns the tick of the first unblocked shot, or -1.
	var sim := SimWorld.new(1, 1)
	sim.enemies.clear()
	sim.sandbags.clear()
	sim.rocks.clear()
	var p: Dictionary = sim.players[0]
	var ex := 320 * Fixed.ONE
	var ey := -400 * Fixed.ONE
	var a := deg_to_rad(float(start_deg))
	p["x"] = ex + int(cos(a) * range_px * Fixed.ONE)
	p["y"] = ey + int(sin(a) * range_px * Fixed.ONE)
	sim._spawn_special(ex, ey, "shield")
	var e: Dictionary = sim.enemies[0]
	var spd := float(SimWorld.PLAYER_SPEED) / Fixed.ONE
	var sh := float(SimWorld.SHIELD_SPEED) / Fixed.ONE
	var vt := sqrt(maxf(0.0, spd * spd - sh * sh))
	var dth := vt / float(range_px) * float(dir)
	var ang := a
	for t in TRIAL_TICKS:
		sim._step_enemies()
		if not e["alive"]:
			return -1
		if circle:
			ang += dth
		var r := float(range_px)
		p["x"] = e["x"] + int(cos(ang) * r * Fixed.ONE)
		p["y"] = e["y"] + int(sin(ang) * r * Fixed.ONE)
		var shot := {"vx": e["x"] - p["x"], "vy": e["y"] - p["y"]}
		if not sim._shield_blocks(e, shot):
			return t
	return -1


func _init() -> void:
	print("turn step raw=%d (%.2f deg/tick)" % [SimWorld.SHIELD_TURN_STEP,
		rad_to_deg(float(SimWorld.SHIELD_TURN_STEP) / Fixed.ONE)])
	var ctl_ok := 0
	var ctl_n := 0
	for r in RANGES:
		for s in START_DEG:
			ctl_n += 1
			if _trial(r, s, 1, false) >= 0:
				ctl_ok += 1
	print("control (player never circles): %d / %d unblocked" % [ctl_ok, ctl_n])
	for r in RANGES:
		var ok := 0
		var n := 0
		var tsum := 0
		for s in START_DEG:
			for d in [1, -1]:
				n += 1
				var t := _trial(r, s, d, true)
				if t >= 0:
					ok += 1
					tsum += t
		print("range %3d px: circling flank success %2d / %2d  mean ticks to first open shot %s"
			% [r, ok, n, str(tsum / ok) if ok > 0 else "-"])
	quit()
