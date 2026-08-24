extends SceneTree
## OFF-SCREEN AIMED FIRE.
##
## _draw_threat_pips (src/main.gd) exists so "a lethal shot from beyond the
## 640x360 viewport reads as a threat, not a cheap death" -- but its kind filter
## is {sniper, grenadier, ghillie, drone, technical, mg_nest}. The two commonest
## aimed shooters in the game, the RIFLEMAN (kind "rusher") and the ELITE, are
## not in it.
##
## Meanwhile _step_enemies keeps enemies alive out to camera_top + 420 while the
## drawn viewport is camera_top .. camera_top + VIEW_H (360), and _clamp_actor
## pins the player at camera_top + 344. So there is a 60px live band BELOW the
## screen. Under the ratchet camera, everything you walk past ends up in it.
##
## Count, over real campaign runs: rifleman/elite windups that START from a
## position the view does not draw, and the enemy rounds fired from there.
##
##   godot --headless --path . -s res://tools/probe_offscreen_fire.gd

const TICKS := 9000
const VIEW_BOTTOM := 360      # SimWorld.VIEW_H in px -- the drawn edge

var _above := 0
var _below := 0
var _side := 0
var _worst_above := 0

func _drive(sim, p: Dictionary) -> SimInput:
	var inp := SimInput.new()
	inp.move_y = -256
	inp.fire = true
	var best := {}
	var bd := 1 << 60
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var d: int = absi(e["x"] - p["x"]) + absi(e["y"] - p["y"])
		if d < bd:
			bd = d
			best = e
	if best.is_empty():
		inp.aim_y = -256
	else:
		var dx: int = (best["x"] - p["x"]) / SimWorld.F_ONE
		var dy: int = (best["y"] - p["y"]) / SimWorld.F_ONE
		var l: int = maxi(1, absi(dx) + absi(dy))
		inp.aim_x = clampi(dx * 256 / l, -256, 256)
		inp.aim_y = clampi(dy * 256 / l, -256, 256)
	return inp


func _run(seed_v: int) -> Array:
	var sim := SimWorld.new(seed_v, 1, "campaign")
	sim.god_mode = true       # the run must not end -- we are counting, not surviving
	var p: Dictionary = sim.players[0]
	var offscreen_windups := 0
	var onscreen_windups := 0
	var offscreen_shots := 0
	var onscreen_shots := 0
	var was_winding := {}
	var deepest := 0
	for t in TICKS:
		var inp := _drive(sim, p)
		# Snapshot which rifleman/elite windups exist BEFORE the step, keyed by
		# a stable-enough identity (position + kind), so a windup that STARTS
		# this tick is attributed to where the shooter stood when it started.
		sim.step([inp] as Array[SimInput])
		p = sim.players[0]
		var top: int = sim.camera_top
		for ev in sim.events:
			if ev["t"] != "rifleman_windup" and ev["t"] != "elite_windup" \
					and ev["t"] != "enemy_shot":
				continue
			var sy: int = (ev["y"] - top) / SimWorld.F_ONE
			var sx: int = ev["x"] / SimWorld.F_ONE
			var off: bool = sy < 0 or sy > VIEW_BOTTOM or sx < 0 or sx > 640
			if ev["t"] == "enemy_shot":
				# NOTE: enemy_shot is ALSO emitted by mg_nest/colossus/boss, which do
				# get pips (or are drawn specially), so this column is an UPPER BOUND.
				if off:
					offscreen_shots += 1
				else:
					onscreen_shots += 1
			else:
				# rifleman_windup / elite_windup only -- the two kinds with NO pip.
				if off:
					offscreen_windups += 1
					if sy < 0:
						_above += 1
						_worst_above = mini(_worst_above, sy)
					elif sy > VIEW_BOTTOM:
						_below += 1
						deepest = maxi(deepest, sy - VIEW_BOTTOM)
					else:
						_side += 1
				else:
					onscreen_windups += 1
	return [offscreen_windups, onscreen_windups, offscreen_shots, onscreen_shots,
		deepest, sim.camera_top / SimWorld.F_ONE]


func _init() -> void:
	print("VIEW_H = %d px (drawn edge). Enemies are swept only at camera_top + 420,"
		% (SimWorld.VIEW_H / SimWorld.F_ONE))
	print("and _clamp_actor pins the player at camera_top + %d."
		% (SimWorld.CAMERA_BAND_BOTTOM / SimWorld.F_ONE))
	print("So a %dpx band below the drawn screen holds LIVE, FIRING enemies.\n"
		% (420 - SimWorld.VIEW_H / SimWorld.F_ONE))
	print("%-10s %-14s %-14s %-14s %-14s %-10s"
		% ["seed", "wind OFF", "wind on", "SHOTS OFF", "shots on", "deepest"])
	var tw_off := 0
	var tw_on := 0
	var ts_off := 0
	var ts_on := 0
	for s in [0xC0FFEE, 1, 7, 99]:
		var r := _run(s)
		tw_off += r[0]; tw_on += r[1]; ts_off += r[2]; ts_on += r[3]
		print("%-10s %-14d %-14d %-14d %-14d %-10d"
			% [str(s), r[0], r[1], r[2], r[3], r[4]])
	print("")
	print("TOTAL over 4 seeds x %d ticks: %d of %d rifleman/elite windups (%.1f%%) began"
		% [TICKS, tw_off, tw_off + tw_on, 100.0 * tw_off / maxi(1, tw_off + tw_on)])
	print("      from a position the view does not draw; %d of %d aimed rounds (%.1f%%)"
		% [ts_off, ts_off + ts_on, 100.0 * ts_off / maxi(1, ts_off + ts_on)])
	print("      were fired off-screen (UPPER BOUND -- enemy_shot also covers mg_nest/boss).")
	print("      Direction of the %d unpipped OFF-SCREEN WINDUPS: %d above the top edge"
		% [tw_off, _above])
	print("      (worst %d px above), %d below the bottom edge, %d off the sides."
		% [-_worst_above, _below, _side])
	quit()
