class_name SiegeBoss
extends RefCounted
## The Crashed Convoy's SIEGE TANK (sector-5 gate): the convoy's surviving armor, a
## ground boss that lives in the same gate["boss"] slot the Bridge Gunship does (so
## the HP bar, the music director, the "destroy it to advance" band and the gate-open
## plumbing all work unchanged) and tells itself apart with boss["kind"] == "siege".
##
## An enum-based state machine (godot-prompter:state-machine) over three HP-third
## acts (GunshipPhases.phase_of, so 2P / Hard scaling shifts the thresholds with the
## pool). Which states an act runs is DATA (shell_plan / the act ladders below), not a
## branch pile in step():
##
##   act 1  SHELLING     slow turret tracking, telegraphed shells; every other shell
##                        is aimed at the player's COVER and craters it.
##   act 2  CHARGE       shells, then REV (lane locked + drawn) -> CHARGE down that lane
##                        -> STUN: the hull is winded and its REAR WEAK POINT is open.
##   act 3  LAST GASP    short shelling, an MG SWEEP (the fan is drawn first), escorts
##                        dismount, then the same charge on a shorter fuse.
##
## ARMOR: bullets ping off the hull everywhere EXCEPT the rear weak point, and that
## only while the stun window is open (bullet_result is the one rule; the view draws
## weak_point() exactly while weak_open()). Grenades, rockets and every other blast
## hurt it at any time (the sim's boss blast branches). The flamethrower only ever
## targets enemies[], so it never touches the hull at all.
##
## Every lethal attack is telegraphed from the sim's OWN numbers and the view reads
## them back through lane() / sweep_arc() / weak_point() / the strike list, never
## from constants of its own. Reaction floor: MIN_TELEGRAPH_TICKS (24) -- shells use
## STRIKE_TELEGRAPH_TICKS (45), the charge rev and the sweep warning are tabled below.
##
## Pure integer maths, no engine RNG, no clock, no scene tree (lint_sim clean). The
## SimWorld is passed in untyped to keep the two scripts free of a load cycle.

const F := 65536
const HP := 80
const WEAK_DAMAGE := 3                    # a bullet through the open rear plate (grenade = 8)
const MIN_TELEGRAPH_TICKS := 24           # the project's reaction floor

const HIT_R := 24 * F                     # hull disc: bullets, blasts, rockets
const REAR_OFF := 14 * F                  # weak point sits this far BEHIND the hull centre
const WEAK_R := 12 * F                    # ...and is this wide
const RAM_R := 22 * F                     # lethal radius of the hull while it CHARGES (lane half-width)
const REST_DY := 60 * F                   # rest row: this far south of the gate wall
const X_MIN := 90 * F
const X_MAX := 550 * F
const Y_LIMIT_DY := 300 * F               # a charge never ends further south than the gate + this
const MUZZLE := 22 * F                    # MG / strike origin ahead of the hull centre
const COVER_SNAP := 120 * F               # a bag this close to the player is "his cover"

# Arena dressing (px relative to the gate wall): cover the shells crater, wrecks that stop a
# charge, kept off the centre lane. Stamped by SimWorld._stamp_siege_cover.
const COVER_BAGS := [[170, 150], [210, 150], [430, 190], [470, 190]]
const WRECKS := [[96, 130, 2], [544, 130, 2]]
# Every gameplay field the gunship dict does not already carry: fed to SimWorld.checksum().
const HASHED_KEYS := ["y", "fx", "fy", "st", "st_t", "wp", "wpm", "rv", "sx", "sy", "ex", "ey", "cn"]

enum St { SHELL, SWEEP_WARN, SWEEP, REV, CHARGE, STUN, RETURN }
const ST_NAMES := ["SHELL", "SWEEP_WARN", "SWEEP", "REV", "CHARGE", "STUN", "RETURN"]

# Per-act tables, index = act - 1.
const DRIFT := [F * 4 / 5, F * 4 / 5, F]                    # px/tick sideways while shelling
const SHELL_LEN := [150, 100, 40]
const REV_TICKS := [0, 36, 28]                              # >= MIN_TELEGRAPH_TICKS where used
const CHARGE_SPEED := [0, F * 14 / 5, F * 17 / 5]           # px/tick
const CHARGE_TICKS := 56                                    # nominal lane length = this * speed
const STUN_TICKS := [0, 120, 84]                            # the rear window
const RETURN_SPEED := [0, F * 11 / 5, F * 3]
const SWEEP_WARN_TICKS := 30
const SWEEP_TICKS := 54
const SWEEP_BEAMS := 9                                      # beam i fires for SWEEP_TICKS / SWEEP_BEAMS ticks
const SWEEP_FIRE_EVERY := 2
const SWEEP_RANGE := 540 * F                                # ENEMY_BULLET_SPEED (3) * ENEMY_BULLET_TTL (180)
const ESCORTS := 2

# Shell plan per act: [tick-in-state, kind] with kind 0 = lead the player, 1 = crater his cover.
const SHELL_PLAN := [
	[[20, 1], [60, 0], [100, 1]],
	[[14, 1], [54, 0]],
	[[10, 0]],
]

# Sweep fan: beam angles -40..+40 deg in 10 deg steps as [cos, sin] raw 16.16.
const FAN := [[50203, -42126], [56756, -32768], [61584, -22415], [64540, -11380], [65536, 0],
	[64540, 11380], [61584, 22415], [56756, 32768], [50203, 42126]]
const FAN_COS_MIN := 50203                                   # cos(40 deg): every beam is inside this cone


static func is_siege(boss: Dictionary) -> bool:
	return boss.get("kind", "") == "siege"


static func make(gate_y: int, max_hp: int) -> Dictionary:
	## The boss dict stamped into gates[]. x/dir/phase_t/hp/alive/gate_y are the
	## gunship's keys, so every generic boss reader keeps working; the rest is ours.
	return {"alive": true, "hp": max_hp, "max_hp": max_hp, "x": 320 * F, "dir": 1,
		"phase_t": 0, "gate_y": gate_y, "kind": "siege",
		"y": gate_y + REST_DY, "fx": 0, "fy": F, "st": St.SHELL, "st_t": 0,
		"wp": 0, "wpm": 0, "rv": 0, "sx": 0, "sy": 0, "ex": 0, "ey": 0, "cn": 0}


static func act_of(boss: Dictionary) -> int:
	return GunshipPhases.phase_of(boss["hp"], boss.get("max_hp", HP))


static func rest_y(boss: Dictionary) -> int:
	return boss["gate_y"] + REST_DY


# --- queries the view and the damage seams share -------------------------------------

static func weak_open(boss: Dictionary) -> bool:
	return boss["alive"] and boss["wp"] > 0


static func weak_point(boss: Dictionary) -> Array:
	## [x, y] fixed: the rear plate, REAR_OFF behind the hull centre along its facing.
	return [boss["x"] - Fixed.mul(boss["fx"], REAR_OFF), boss["y"] - Fixed.mul(boss["fy"], REAR_OFF)]


static func bullet_result(boss: Dictionary, bx: int, by: int) -> String:
	## THE bullet armor rule. "weak" = the open rear plate (damage), "armor" = a ping off
	## the hull (the bullet is absorbed, the view sparks it), "miss" = not on the hull.
	if weak_open(boss):
		var w := weak_point(boss)
		if _near(bx, by, w[0], w[1], WEAK_R):
			return "weak"
	if _near(bx, by, boss["x"], boss["y"], HIT_R):
		return "armor"
	return "miss"


static func lane(boss: Dictionary) -> Dictionary:
	## The charge lane while it is promised (REV) or being driven (CHARGE): the segment
	## the hull sweeps and the half-width that kills. {} otherwise.
	var st: int = boss["st"]
	if st != St.REV and st != St.CHARGE:
		return {}
	return {"sx": boss["sx"], "sy": boss["sy"], "ex": boss["ex"], "ey": boss["ey"],
		"half_w": RAM_R, "live": st == St.CHARGE,
		"left": (boss["rv"] - boss["st_t"]) if st == St.REV else 0}


static func fan_dir(fx: int, fy: int, i: int) -> Array:
	## Beam i of the sweep fan, rotated off the locked facing. Unit vector, fixed.
	var c: int = FAN[i][0]
	var s: int = FAN[i][1]
	return [Fixed.mul(fx, c) - Fixed.mul(fy, s), Fixed.mul(fx, s) + Fixed.mul(fy, c)]


static func sweep_arc(boss: Dictionary) -> Dictionary:
	## The MG fan while it is warned (SWEEP_WARN) or firing (SWEEP): apex, the two
	## outer edge directions, the range the rounds actually fly, and which beam is hot.
	var st: int = boss["st"]
	if st != St.SWEEP_WARN and st != St.SWEEP:
		return {}
	var apex := _muzzle(boss)
	var lo := fan_dir(boss["fx"], boss["fy"], 0)
	var hi := fan_dir(boss["fx"], boss["fy"], SWEEP_BEAMS - 1)
	return {"x": apex[0], "y": apex[1], "lo": lo, "hi": hi, "range": SWEEP_RANGE,
		"live": st == St.SWEEP, "beam": beam_index(boss) if st == St.SWEEP else -1,
		"left": (SWEEP_WARN_TICKS - boss["st_t"]) if st == St.SWEEP_WARN else 0}


static func beam_index(boss: Dictionary) -> int:
	## Which fan beam is firing at st_t (1-based inside SWEEP). dir flips the sweep direction.
	var i: int = clampi((boss["st_t"] - 1) * SWEEP_BEAMS / SWEEP_TICKS, 0, SWEEP_BEAMS - 1)
	return i if boss["dir"] >= 0 else SWEEP_BEAMS - 1 - i


static func act_name(act: int) -> String:
	return ["SHELLING", "CHARGE", "LAST GASP"][clampi(act, 1, 3) - 1]


# --- the state machine ----------------------------------------------------------------

static func step(sim, boss: Dictionary) -> void:
	boss["phase_t"] = boss["phase_t"] + 1
	boss["st_t"] = boss["st_t"] + 1
	var act: int = act_of(boss)
	match boss["st"]:
		St.SHELL:
			_step_shell(sim, boss, act)
		St.SWEEP_WARN:
			if boss["st_t"] == 1:
				_dismount(sim, boss)
			if boss["st_t"] >= SWEEP_WARN_TICKS:
				_enter(boss, St.SWEEP)
		St.SWEEP:
			_step_sweep(sim, boss)
		St.REV:
			if boss["st_t"] >= boss["rv"]:
				_enter(boss, St.CHARGE)
		St.CHARGE:
			_step_charge(sim, boss)
		St.STUN:
			boss["wp"] = maxi(0, boss["wp"] - 1)
			if boss["wp"] == 0:
				_enter(boss, St.RETURN)
		St.RETURN:
			_step_return(boss, act)


static func _enter(boss: Dictionary, st: int) -> void:
	boss["st"] = st
	boss["st_t"] = 0


static func _step_shell(sim, boss: Dictionary, act: int) -> void:
	_drift(boss, act)
	var target: Dictionary = sim._nearest_alive_player(boss["x"], boss["y"])
	_face(boss, target)
	var t: int = boss["st_t"]
	for entry in SHELL_PLAN[act - 1]:
		if t == entry[0] and not target.is_empty():
			_shell(sim, boss, target, entry[1] == 1)
	if t >= SHELL_LEN[act - 1]:
		match act:
			1:
				_enter(boss, St.SHELL)
			2:
				_begin_rev(sim, boss, target)
			_:
				_enter(boss, St.SWEEP_WARN)


static func _drift(boss: Dictionary, act: int) -> void:
	boss["x"] = boss["x"] + DRIFT[act - 1] * boss["dir"]
	if boss["x"] < X_MIN or boss["x"] > X_MAX:
		boss["dir"] = -boss["dir"]
		boss["x"] = clampi(boss["x"], X_MIN, X_MAX)


static func _face(boss: Dictionary, target: Dictionary) -> void:
	## Turret tracking: the hull faces the nearest player. No player alive -> south.
	if target.is_empty():
		boss["fx"] = 0
		boss["fy"] = F
		return
	var dx: int = target["x"] - boss["x"]
	var dy: int = target["y"] - boss["y"]
	var dl: int = Fixed.length(dx, dy)
	if dl > F:
		boss["fx"] = Fixed.div(dx, dl)
		boss["fy"] = Fixed.div(dy, dl)


static func _muzzle(boss: Dictionary) -> Array:
	return [boss["x"] + Fixed.mul(boss["fx"], MUZZLE), boss["y"] + Fixed.mul(boss["fy"], MUZZLE)]


static func _near(x1: int, y1: int, x2: int, y2: int, r: int) -> bool:
	if absi(x1 - x2) > r or absi(y1 - y2) > r:
		return false
	var dx: int = x1 - x2
	var dy: int = y1 - y2
	return Fixed.mul(dx, dx) + Fixed.mul(dy, dy) <= Fixed.mul(r, r)


static func cover_point(sim, px: int, py: int) -> Array:
	## [x, y] of the sandbag nearest the player within COVER_SNAP, else his own feet.
	var best: Array = [px, py]
	var best_d: int = COVER_SNAP
	for sb in sim.sandbags:
		var d: int = Fixed.length(sb["x"] - px, sb["y"] - py)
		if d < best_d:
			best_d = d
			best = [sb["x"], sb["y"]]
	return best


static func _shell(sim, boss: Dictionary, target: Dictionary, crater: bool) -> void:
	## A plain tracked strike (STRIKE_TELEGRAPH_TICKS, ring == GRENADE_RADIUS). The
	## crater flag makes its landing break the sandbags inside that same ring.
	var aim: Array
	if crater:
		aim = cover_point(sim, target["x"], target["y"])
	else:
		var lead: Array = sim._lead_aim(target)
		var sc: Array = sim._blind_scatter(target)   # area fire: smoke scatters it, never stops it
		aim = [clampi(lead[0] + sc[0], sim.WORLD_LEFT, sim.WORLD_RIGHT), lead[1] + sc[1]]
	sim._add_strike(aim[0], aim[1])
	sim.strikes[sim.strikes.size() - 1]["crater"] = crater
	sim.events.append({"t": "siege_fire", "x": boss["x"], "y": boss["y"]})


static func _begin_rev(sim, boss: Dictionary, target: Dictionary) -> void:
	## Lock the lane NOW and draw it for the whole rev: from the hull through the
	## player's position (scattered when he hides in smoke), travelling a fixed
	## CHARGE_TICKS * speed -- so the tank overshoots and runs past a player who steps
	## off it. The end is clamped to the arena; the number of drive ticks follows it.
	var act: int = act_of(boss)
	var dx := 0
	var dy: int = F
	if not target.is_empty():
		var sc: Array = sim._blind_scatter(target)
		dx = target["x"] + sc[0] - boss["x"]
		dy = target["y"] + sc[1] - boss["y"]
	var dl: int = Fixed.length(dx, dy)
	if dl > F:
		boss["fx"] = Fixed.div(dx, dl)
		boss["fy"] = Fixed.div(dy, dl)
	else:
		boss["fx"] = 0
		boss["fy"] = F
	var speed: int = CHARGE_SPEED[act - 1]
	var travel: int = CHARGE_TICKS * speed
	travel = mini(travel, _room(boss["x"], boss["fx"], X_MIN, X_MAX))
	travel = mini(travel, _room(boss["y"], boss["fy"], boss["gate_y"] + 14 * F + HIT_R, boss["gate_y"] + Y_LIMIT_DY))
	travel = maxi(travel, speed)
	boss["sx"] = boss["x"]
	boss["sy"] = boss["y"]
	boss["ex"] = boss["x"] + Fixed.mul(boss["fx"], travel)
	boss["ey"] = boss["y"] + Fixed.mul(boss["fy"], travel)
	boss["cn"] = (travel + speed - 1) / speed
	boss["rv"] = REV_TICKS[act - 1]
	_enter(boss, St.REV)
	sim.events.append({"t": "technical_rev", "x": boss["x"], "y": boss["y"]})


static func _room(pos: int, comp: int, lo: int, hi: int) -> int:
	## How far (fixed) we can travel along a unit-vector component before leaving [lo, hi].
	if comp > 0:
		return Fixed.div(maxi(0, hi - pos), comp)
	if comp < 0:
		return Fixed.div(maxi(0, pos - lo), -comp)
	return 1 << 40


static func _step_charge(sim, boss: Dictionary) -> void:
	var k: int = boss["st_t"]
	var n: int = boss["cn"]
	var nx: int = boss["sx"] + (boss["ex"] - boss["sx"]) * k / n
	var ny: int = boss["sy"] + (boss["ey"] - boss["sy"]) * k / n
	# A wreck stops it dead (the slam is the stun); bags are crushed under it.
	for rk in sim.rocks:
		if sim._rk_solid(rk) and absi(nx - rk["x"]) <= sim._rk_hw(rk) + HIT_R / 2 \
				and absi(ny - rk["y"]) <= sim._rk_hh(rk) + HIT_R / 2:
			sim.events.append({"t": "siege_slam", "x": nx, "y": ny})
			_begin_stun(sim, boss)
			return
	boss["x"] = nx
	boss["y"] = ny
	var si: int = sim.sandbags.size() - 1
	while si >= 0:
		var sb: Dictionary = sim.sandbags[si]
		if absi(nx - sb["x"]) <= sim._sb_hw(sb) + 8 * F and absi(ny - sb["y"]) <= sim._sb_hh(sb) + 8 * F:
			sim._break_sandbag_at(si)
			si = mini(si - 1, sim.sandbags.size() - 1)
		else:
			si -= 1
	for p in sim.players:
		if p["alive"] and not p["roll_iframe"] and sim._exposed(p) \
				and _near(p["x"], p["y"], nx, ny, RAM_R):
			if sim._hazard_paused(p):
				sim.events.append({"t": "hazard_hold", "why": "strike", "x": p["x"], "y": p["y"], "i": p["idx"]})
				continue
			sim._hurt_player(p)
	if k >= n:
		_begin_stun(sim, boss)


static func _begin_stun(sim, boss: Dictionary) -> void:
	var act: int = act_of(boss)
	boss["wp"] = STUN_TICKS[act - 1]
	boss["wpm"] = boss["wp"]
	_enter(boss, St.STUN)
	sim.events.append({"t": "siege_vent", "x": boss["x"], "y": boss["y"]})


static func _step_return(boss: Dictionary, act: int) -> void:
	var speed: int = RETURN_SPEED[act - 1]
	var ry: int = rest_y(boss)
	var dy: int = ry - boss["y"]
	if absi(dy) <= speed:
		boss["y"] = ry
		_enter(boss, St.SHELL)
	else:
		boss["y"] = boss["y"] + (speed if dy > 0 else -speed)


static func _step_sweep(sim, boss: Dictionary) -> void:
	var t: int = boss["st_t"]
	if t % SWEEP_FIRE_EVERY == 0:
		var d := fan_dir(boss["fx"], boss["fy"], beam_index(boss))
		var m := _muzzle(boss)
		sim.events.append({"t": "enemy_shot", "x": m[0], "y": m[1]})
		sim._spawn_enemy_bullet(m[0], m[1], d[0], d[1], F)
	if t >= SWEEP_TICKS:
		_begin_rev(sim, boss, sim._nearest_alive_player(boss["x"], boss["y"]))


static func _dismount(sim, boss: Dictionary) -> void:
	## Escorts pour out of the rear hatches at the start of the sweep warning.
	var alive := 0
	for e in sim.enemies:
		if e["alive"] and e.get("escort", false):
			alive += 1
	var w := weak_point(boss)
	for i in maxi(0, ESCORTS - alive):
		var ox: int = (-1 if i % 2 == 0 else 1) * 26 * F
		sim._spawn_enemy(clampi(w[0] + ox, sim.WORLD_LEFT, sim.WORLD_RIGHT), w[1], false)
		sim.enemies[sim.enemies.size() - 1]["escort"] = true
		sim.events.append({"t": "siege_dismount", "x": w[0] + ox, "y": w[1]})
