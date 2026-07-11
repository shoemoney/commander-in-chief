extends Node2D
## Sprite view over the deterministic sim. All floats live here, never in src/sim.
## Art: Kenney CC0 (see src/view/art.gd). The sim remains pure state; this file
## only reads it.
##
## Controls (P3):
##   P1 — WASD move, arrow keys aim, Space fire, Shift grenade, C roll,
##        F interact (board/exit tank), E revive, Q (hold) spend-wheel
##   Gamepad — LS move, RS aim, RT/R1 fire, L1 grenade, B roll, X interact,
##        Y revive, BACK (hold) spend-wheel
##   F2 toggles local 2P · F3 toggles Endless War · R restarts.

const PX := 1.0 / Fixed.ONE

var sim: SimWorld
var _two_players := false
var _endless := false
# Feel stack (view-only; the sim never sees any of this).
var _trauma := 0.0
var _hitstop_frames := 0
var _flash_alpha := 0.0
var _fx: Array[Dictionary] = []   # explosion/smoke animations from sim events
var _sfx := Sfx.new()
var _recoil: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]   # per-player gun kick
var _kick := Vector2.ZERO         # directional screen nudge from firing
# War Chest spend-wheel (hold Q / pad BACK, flick a direction, release to buy).
var _wheel: Array[Dictionary] = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]
const WHEEL_ITEMS := [
	{"kind": 0, "icon": "icon_ammo", "cost": SimWorld.SHOP_AMMO_COST},
	{"kind": 1, "icon": "icon_grenade", "cost": SimWorld.SHOP_GRENADE_COST},
	{"kind": 2, "icon": "icon_vest", "cost": SimWorld.SHOP_VEST_COST},
	{"kind": 3, "icon": "icon_airstrike", "cost": SimWorld.SHOP_AIRSTRIKE_COST},
]
const _SECTOR_TO_ITEM := [2, 3, 0, 1]   # right=vest, down=airstrike, left=ammo, up=grenade

## Sim event → [sound, volume dB, pitch]. Pickups are special-cased on cost.
const _EVENT_SOUND := {
	"shot": ["shot", -9.0, 1.0],
	"tank_shot": ["tank_shot", -3.0, 1.0],
	"throw": ["throw", -8.0, 1.0],
	"roll": ["roll", -8.0, 1.0],
	"explosion": ["explosion", -2.0, 1.0],
	"kill": ["kill", -7.0, 1.0],
	"player_down": ["player_down", 0.0, 1.0],
	"vest_break": ["vest_break", -2.0, 1.0],
	"gate_open": ["gate_open", -4.0, 1.0],
	"revive": ["revive", -5.0, 1.0],
	"tank_board": ["tank_board", -5.0, 1.0],
	"tank_ignite": ["alarm", -4.0, 1.1],
	"observer_spawn": ["alarm", -3.0, 1.0],
	"strike_warn": ["whistle", -6.0, 1.0],
	"enemy_shot": ["enemy_shot", -12.0, 1.0],
	"bunker_break": ["explosion", -4.0, 0.72],
	"frogman_surface": ["splash", -4.0, 1.0],
	"wave_start": ["wave_start", -5.0, 1.0],
	"wave_clear": ["wave_clear", -5.0, 1.0],
	"colossus_engage": ["alarm", 0.0, 0.75],
	"victory": ["victory", 0.0, 1.0],
	"buy": ["buy", -4.0, 1.0],
	"deny": ["deny", -6.0, 1.0],
}

@onready var hud: Label = $HUD/Label
var _hud_icons := HudIcons.new()


func _ready() -> void:
	add_child(_sfx)
	hud.visible = false   # superseded by the icon HUD
	_hud_icons.main = self
	$HUD.add_child(_hud_icons)
	_reset()


func _reset() -> void:
	sim = SimWorld.new(0xC0FFEE, 2 if _two_players else 1, "endless" if _endless else "campaign")
	_trauma = 0.0
	_hitstop_frames = 0
	_flash_alpha = 0.0
	_fx.clear()
	_recoil = [Vector2.ZERO, Vector2.ZERO]
	_kick = Vector2.ZERO
	_wheel = [{"open": false, "sel": -1}, {"open": false, "sel": -1}]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_two_players = not _two_players
			_reset()
		elif event.keycode == KEY_F3:
			_endless = not _endless
			_reset()
		elif event.keycode == KEY_R:
			_reset()


func _physics_process(_delta: float) -> void:
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
	else:
		sim.step(_gather_inputs())
		_consume_events()
	_update_feel()
	queue_redraw()
	_update_hud()


func _consume_events() -> void:
	for ev in sim.events:
		var kind: String = ev["t"]
		if kind == "pickup":
			_sfx.play("buy" if ev.get("cost", 0) > 0 else "pickup", -5.0)
		elif _EVENT_SOUND.has(kind):
			var snd: Array = _EVENT_SOUND[kind]
			_sfx.play(snd[0], snd[1], snd[2])
		match kind:
			"shot":
				var shooter := sim.players[ev["i"]]
				var aim := Vector2(shooter["aim_x"], shooter["aim_y"]) * PX
				_recoil[ev["i"]] -= aim * 2.2
				_kick -= aim * 0.5
				_fx.append({"x": ev["x"] + int(shooter["aim_x"] * 13),
					"y": ev["y"] + int(shooter["aim_y"] * 13),
					"t": 0.0, "kind": "muzzle", "rate": 0.34, "a": aim.angle()})
				var perp := Vector2(-aim.y, aim.x) * (1.0 if randf() < 0.5 else -1.0)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "casing",
					"rate": 0.055, "spin": randf() * TAU,
					"vx": perp.x * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4),
					"vy": perp.y * randf_range(1.2, 2.4) + randf_range(-0.4, 0.4)})
			"tank_shot":
				var gunner := sim.players[ev["i"]]
				var taim := Vector2(gunner["aim_x"], gunner["aim_y"]) * PX
				_kick -= taim * 2.5
				_trauma = minf(1.0, _trauma + 0.15)
				_fx.append({"x": ev["x"] + int(gunner["aim_x"] * 18),
					"y": ev["y"] + int(gunner["aim_y"] * 18),
					"t": 0.0, "kind": "muzzle", "rate": 0.22, "a": taim.angle(), "big": true})
			"explosion":
				_trauma = minf(1.0, _trauma + 0.35)
				_hitstop_frames = maxi(_hitstop_frames, 4)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "explosion"})
			"kill":
				_flash_alpha = maxf(_flash_alpha, 0.2)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "smoke"})
			"player_down":
				_trauma = minf(1.0, _trauma + 0.5)
				_hitstop_frames = maxi(_hitstop_frames, 6)
				_flash_alpha = maxf(_flash_alpha, 0.35)
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "smoke"})
			"gate_open":
				_trauma = minf(1.0, _trauma + 0.2)
			"vest_break":
				_flash_alpha = maxf(_flash_alpha, 0.35)
			"observer_spawn":
				_fx.append({"x": ev["x"], "y": ev["y"], "t": 0.0, "kind": "alert", "rate": 0.025})
			"colossus_engage":
				_trauma = 1.0
				_hitstop_frames = maxi(_hitstop_frames, 8)
			"victory":
				_trauma = 1.0
				_flash_alpha = 0.6


func _update_feel() -> void:
	_trauma = maxf(0.0, _trauma - 0.03)
	_flash_alpha = maxf(0.0, _flash_alpha - 0.08)
	for i in range(_fx.size() - 1, -1, -1):
		var fx := _fx[i]
		fx["t"] += fx.get("rate", 0.09)
		if fx["kind"] == "casing":
			fx["x"] += int(fx["vx"] * Fixed.ONE)
			fx["y"] += int(fx["vy"] * Fixed.ONE)
			fx["vx"] *= 0.86
			fx["vy"] *= 0.86
		if fx["t"] >= 1.0:
			_fx.remove_at(i)
	for i in _recoil.size():
		_recoil[i] *= 0.72
	_kick *= 0.78
	var mag := _trauma * _trauma * 6.0
	var shake := Vector2.ZERO
	if mag > 0.01:
		var t := float(Engine.get_physics_frames())
		shake = Vector2(sin(t * 1.7) * mag, cos(t * 2.3) * mag)
	position = shake + _kick


func _gather_inputs() -> Array:
	var inputs: Array = []
	var p1 := SimInput.new()
	var kx := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var ky := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
	var ax := (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
	var ay := (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0)
	var pad_move := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if pad_move.length() > 0.2:
		kx = pad_move.x
		ky = pad_move.y
	if pad_aim.length() > 0.25:
		ax = pad_aim.x
		ay = pad_aim.y
	p1.move_x = _quantize_axis(kx)
	p1.move_y = _quantize_axis(ky)
	p1.aim_x = _quantize_axis(ax)
	p1.aim_y = _quantize_axis(ay)
	p1.fire = Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	p1.grenade = Input.is_physical_key_pressed(KEY_SHIFT) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	p1.roll = Input.is_physical_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	p1.interact = Input.is_physical_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	p1.revive = Input.is_physical_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	p1.buy = _update_wheel(0,
		Input.is_physical_key_pressed(KEY_Q) or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK),
		Vector2(ax, ay), Vector2(kx, ky))
	inputs.append(p1)

	if _two_players:
		var p2 := SimInput.new()
		p2.move_x = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_LEFT_X))
		p2.move_y = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_LEFT_Y))
		p2.aim_x = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_RIGHT_X))
		p2.aim_y = _quantize_axis(Input.get_joy_axis(1, JOY_AXIS_RIGHT_Y))
		p2.fire = Input.get_joy_axis(1, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
			or Input.is_joy_button_pressed(1, JOY_BUTTON_RIGHT_SHOULDER)
		p2.grenade = Input.is_joy_button_pressed(1, JOY_BUTTON_LEFT_SHOULDER)
		p2.roll = Input.is_joy_button_pressed(1, JOY_BUTTON_B)
		p2.interact = Input.is_joy_button_pressed(1, JOY_BUTTON_X)
		p2.revive = Input.is_joy_button_pressed(1, JOY_BUTTON_Y)
		p2.buy = _update_wheel(1, Input.is_joy_button_pressed(1, JOY_BUTTON_BACK),
			Vector2(Input.get_joy_axis(1, JOY_AXIS_RIGHT_X), Input.get_joy_axis(1, JOY_AXIS_RIGHT_Y)),
			Vector2(Input.get_joy_axis(1, JOY_AXIS_LEFT_X), Input.get_joy_axis(1, JOY_AXIS_LEFT_Y)))
		inputs.append(p2)
	return inputs


func _update_wheel(i: int, held: bool, aim: Vector2, move: Vector2) -> int:
	## Hold to open, flick aim (or move) to pick a sector, release to buy.
	## Selection is sticky; releasing with nothing picked cancels. Returns the
	## SimInput.buy value (kind + 1) for exactly one tick on purchase.
	var w := _wheel[i]
	if held:
		w["open"] = true
		var dir := aim if aim.length() > 0.3 else move
		if dir.length() > 0.3:
			w["sel"] = int(round(fposmod(dir.angle(), TAU) / (TAU / 4.0))) % 4
		return 0
	if w["open"]:
		w["open"] = false
		var sel: int = w["sel"]
		w["sel"] = -1
		if sel >= 0:
			return WHEEL_ITEMS[_SECTOR_TO_ITEM[sel]]["kind"] + 1
	return 0


func _quantize_axis(v: float) -> int:
	## The float→int boundary: the sim only ever sees quantized [-256, 256].
	return clampi(int(round(v * 256.0)), -256, 256)


func _to_screen(fx: int, fy: int) -> Vector2:
	return Vector2(fx * PX, (fy - sim.camera_top) * PX)


const _OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1),
]


func _spr(name: String, pos: Vector2, angle := 0.0, scale := 1.0, mod := Color.WHITE,
		stretch := 1.0) -> void:
	var t: Texture2D = Art.tex(name)
	var s := scale * Art.draw_scale(name)
	var tint := mod * Art.tint(name)
	draw_set_transform(pos, angle, Vector2(s, s * stretch))
	var origin := -t.get_size() / 2.0
	if Art.outlined(name):
		# 1.4px screen-space dark rim so units/vehicles read on any ground.
		var oc := Color(0.05, 0.06, 0.04, tint.a)
		var d := 1.1 / s
		for o in _OUTLINE_OFFSETS:
			draw_texture(t, origin + o * d, oc)
	draw_texture(t, origin, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _aim_angle(p: Dictionary) -> float:
	return atan2(p["aim_y"] * PX, p["aim_x"] * PX)


func _draw() -> void:
	_draw_terrain()
	_draw_water()
	_draw_gates()
	for bk in sim.bunkers:
		if bk["alive"]:
			var c := _to_screen(bk["x"], bk["y"]) + Vector2(24, 16)
			_spr("sandbag", c, 0.0, 0.78)
	_draw_pickups()
	_draw_tanks()
	_draw_enemies()
	_draw_observer()
	_draw_gunships()
	_draw_colossus()
	_draw_projectiles()
	_draw_players()
	_draw_fx()
	_draw_telegraphs()
	_draw_wheel()
	_draw_banners()


func _draw_terrain() -> void:
	# World-anchored grass tiling, darkened toward jungle; deterministic dirt
	# patches and tree lines from a cell hash (decor only, not sim state).
	var cam_y := sim.camera_top * PX
	var oy := -fposmod(cam_y, 64.0)
	var base_iy := int(floor(cam_y / 64.0))
	for ty in 8:
		for tx in 10:
			var pos := Vector2(tx * 64.0, oy + ty * 64.0)
			var h := Art.cell_hash(tx, base_iy + ty)
			var shade := 0.52 + float(h % 7) * 0.012
			draw_texture_rect(Art.tex("grass"), Rect2(pos, Vector2(64, 64)), false,
				Color(shade, shade + 0.06, shade * 0.82))
			if h % 6 == 0:
				draw_texture_rect(Art.tex("dirt"), Rect2(pos + Vector2(8, 8), Vector2(48, 48)), false,
					Color(0.65, 0.6, 0.5, 0.55))
	# Low fern understory scattered through the field (hash decorrelated from
	# the tree grid so ferns and trees don't stack on the same cell).
	for ty in 10:
		var fy := oy + ty * 40.0
		var fiy := int(floor((cam_y + fy) / 40.0))
		for tx in 16:
			var hf := Art.cell_hash(tx * 17 + 5, fiy * 3)
			if hf % 5 != 0:
				continue
			var fx := tx * 42.0 + float(hf % 20) - 10.0
			var fy_px := fy + float((hf / 5) % 16)
			if sim._in_water(int(fx / PX), sim.camera_top + int(fy_px / PX)):
				continue
			_spr("fern", Vector2(fx, fy_px), float(hf % 628) / 100.0,
				0.28 + float(hf % 3) * 0.03, Color(0.82, 0.92, 0.72))

	# Jungle tree lines on the flanks, sparse singles in the field.
	for ty in 9:
		var wy := oy + ty * 48.0
		var iy := int(floor((cam_y + wy) / 48.0))
		for tx in 14:
			var h2 := Art.cell_hash(tx * 31, iy)
			var margin: bool = tx < 2 or tx > 11
			if (margin and h2 % 3 != 0) or (not margin and h2 % 19 == 0):
				var px := tx * 48.0 + float(h2 % 24) - 12.0
				var wy_px := wy + float((h2 / 7) % 20)
				var world_x := int(px / PX)
				var world_y := sim.camera_top + int(wy_px / PX)
				if sim._in_water(world_x, world_y):
					continue
				var big := h2 % 5 == 0
				_spr("tree_large" if big else "tree_small", Vector2(px, wy_px),
					float(h2 % 628) / 100.0, 0.42 if big else 0.34, Color(0.75, 0.85, 0.72))


func _draw_water() -> void:
	for w in sim.waters:
		var wy := _to_screen(0, w["y"]).y
		var wh := SimWorld.WATER_H * PX
		# Banks.
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy - 6, 640, 8), true, Color(0.9, 0.85, 0.7))
		draw_texture_rect(Art.tex("sand"), Rect2(0, wy + wh - 2, 640, 8), true, Color(0.9, 0.85, 0.7))
		# Water body + animated wave lines.
		draw_rect(Rect2(0, wy, 640, wh), Color(0.16, 0.30, 0.42))
		var t := float(Engine.get_physics_frames()) * 0.03
		for i in 4:
			var ly := wy + wh * (0.2 + 0.2 * i) + sin(t + i * 1.7) * 2.0
			draw_line(Vector2(0, ly), Vector2(640, ly), Color(0.35, 0.5, 0.6, 0.35), 1.0)
		# The dry ford.
		var ford_left: float = (w["ford_x"] - SimWorld.FORD_HALF_W) * PX
		draw_texture_rect(Art.tex("sand"), Rect2(ford_left, wy - 2, SimWorld.FORD_HALF_W * 2.0 * PX, wh + 4),
			true, Color(0.85, 0.8, 0.65))


func _draw_gates() -> void:
	for g in sim.gates:
		var gy := _to_screen(0, g["y"]).y
		if g["open"]:
			for i in 2:
				_spr("sandbag_beige", Vector2(24 + i * 592, gy), 0.0, 0.6, Color(0.7, 0.68, 0.62))
		else:
			for i in 14:
				_spr("sandbag_beige", Vector2(24 + i * 46, gy), 0.0, 0.72)


func _draw_pickups() -> void:
	for pk in sim.pickups:
		var ppos := _to_screen(pk["x"], pk["y"])
		var tex_name: String
		var mod := Color.WHITE
		match pk["kind"]:
			0: tex_name = "crate_ammo"
			1: tex_name = "crate_grenade"
			2:
				tex_name = "crate_ammo"
				mod = Color(0.6, 0.7, 1.4)   # vest = blue-shifted barrel
			_: tex_name = "crate_airstrike"
		_spr(tex_name, ppos, 0.0, 0.55, mod)
		if pk.get("cost", 0) > 0:
			draw_texture_rect(Art.tex("icon_coin"), Rect2(ppos + Vector2(-15, -21), Vector2(9, 9)), false)
			draw_string(ThemeDB.fallback_font, ppos + Vector2(-4, -13), str(pk["cost"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.95, 0.65))


func _draw_tanks() -> void:
	for t in sim.tanks:
		if not t["alive"]:
			continue
		var c := _to_screen(t["x"], t["y"])
		var burn_mod := Color.WHITE
		if t["burning"]:
			burn_mod = Color(1.3, 0.6, 0.45) if (t["burn_ticks"] / 6) % 2 == 0 else Color(0.9, 0.5, 0.4)
		_spr("tank_body", c, 0.0, 0.62, burn_mod)
		# Barrel follows the driver's aim; parked barrel points up.
		var barrel_angle := -PI / 2
		if t["occupant"] >= 0:
			barrel_angle = _aim_angle(sim.players[t["occupant"]])
		_spr("tank_barrel", c + Vector2.from_angle(barrel_angle) * 10.0, barrel_angle + PI / 2, 0.62, burn_mod)
		if t["burning"]:
			_spr("smoke", c + Vector2(4, -14), 0.0, 0.5, Color(1, 1, 1, 0.75))
		elif t["occupant"] < 0:
			Art.draw_glyph(self, "interact", c + Vector2(0, -30), 11.0)


func _draw_enemies() -> void:
	for e in sim.enemies:
		if not e["alive"]:
			continue
		var epos := _to_screen(e["x"], e["y"])
		var target := sim._nearest_alive_player(e["x"], e["y"])
		var face := PI / 2
		if not target.is_empty():
			face = atan2(float(target["y"] - e["y"]), float(target["x"] - e["x"]))
		if e["kind"] == "frogman":
			var st: int = e.get("surface_ticks", 0)
			if e["submerged"]:
				# Idle ripple loop so occupied water reads as occupied.
				var ph := float((Engine.get_physics_frames() + e["x"] / 7919) % 90) / 90.0
				draw_arc(epos, 4.0 + ph * 9.0, 0, TAU, 16, Color(0.6, 0.8, 0.9, 0.4 * (1.0 - ph)), 1.0)
				draw_arc(epos, 5.0, 0, TAU, 12, Color(0.6, 0.8, 0.9, 0.55), 1.5)
				_spr("frogman", epos, face, 0.4, Color(0.5, 0.8, 0.8, 0.35))
			elif st > 0:
				# Surfacing telegraph: bold ripple burst + the body rising up.
				var sfrac := 1.0 - float(st) / float(SimWorld.FROGMAN_SURFACE_TICKS)
				for k in 2:
					draw_arc(epos, 6.0 + sfrac * 14.0 + k * 5.0, 0, TAU, 20,
						Color(0.85, 0.95, 1.0, 0.7 - k * 0.25 - sfrac * 0.3), 2.0)
				_spr("frogman", epos, face, 0.4 + sfrac * 0.1,
					Color(0.7, 0.9, 0.95, 0.4 + sfrac * 0.6))
			else:
				_spr("frogman", epos, face, 0.5)
		elif e["elite"]:
			_spr("elite", epos, face, 0.5, Color(1.35, 0.75, 0.7))
		else:
			_spr("rusher", epos, face, 0.5)


func _draw_observer() -> void:
	if sim.observer.is_empty():
		return
	var op := _to_screen(sim.observer["x"], sim.camera_top + SimWorld.OBSERVER_Y_OFFSET)
	_spr("observer", op, PI / 2, 0.5)
	draw_line(op + Vector2(8, 0), op + Vector2(8, -12), Color(0.95, 0.8, 0.2), 2.0)
	draw_rect(Rect2(op + Vector2(8, -12), Vector2(7, 5)), Color(0.9, 0.25, 0.2))


func _draw_gunships() -> void:
	for g in sim.gates:
		if g["boss"].is_empty() or not g["boss"]["alive"] or g["open"]:
			continue
		var boss: Dictionary = g["boss"]
		var bpos := _to_screen(boss["x"], boss["gate_y"] - SimWorld.BOSS_Y_OFFSET)
		# Mortar-phase warning: the hull flashes red while volleys are near
		# (they land at phase_t 200/240/280 of the 360-tick cycle).
		var pt: int = boss["phase_t"]
		var hull_mod := Color.WHITE
		if pt >= 170 and pt <= 290 and (Engine.get_physics_frames() / 6) % 2 == 0:
			hull_mod = Color(1.5, 0.6, 0.5)
		_spr("gunship_body", bpos, PI, 0.8, hull_mod)
		_spr("gunship_barrel", bpos + Vector2(0, 12), 0.0, 0.8, hull_mod)
		# Rotor blur.
		var rt := float(Engine.get_physics_frames()) * 0.9
		for i in 2:
			var a := rt + i * PI / 2
			draw_line(bpos - Vector2.from_angle(a) * 26.0, bpos + Vector2.from_angle(a) * 26.0,
				Color(0.85, 0.85, 0.85, 0.5), 2.0)
		draw_circle(bpos, 3.5, Color(0.3, 0.3, 0.35))
		_draw_bar(Rect2(bpos + Vector2(-23, -32), Vector2(46, 10)),
			float(boss["hp"]) / float(SimWorld.BOSS_HP))


func _draw_colossus() -> void:
	if sim.colossus.is_empty() or not sim.colossus["alive"]:
		return
	var cpos := _to_screen(sim.colossus["x"], sim.colossus["y"])
	var phase := sim.colossus_phase()
	var mod := Color.WHITE if phase < 3 else Color(1.4, 0.62, 0.55)
	_spr("colossus_body", cpos, PI, 1.9, mod)
	_spr("colossus_barrel", cpos + Vector2(-24, 26), PI - 0.5, 1.3, mod)
	_spr("colossus_barrel", cpos + Vector2(24, 26), PI + 0.5, 1.3, mod)
	# Turret warm-up: barrel tips glow brighter as the next spray approaches.
	var warm := 1.0 - float(sim.colossus["spray_cd"]) / float(SimWorld.COLOSSUS_SPRAY_CD_TICKS)
	for bx in [-24.0, 24.0]:
		draw_circle(cpos + Vector2(bx, 34.0), 2.0 + warm * 3.5,
			Color(1.0, 0.55, 0.15, 0.15 + warm * 0.55))
	var pulse := 0.5 + 0.5 * sin(float(Engine.get_physics_frames()) * 0.2)
	draw_circle(cpos, 7.0 + pulse * 2.0, Color(0.95, 0.25, 0.15, 0.85))
	_draw_bar(Rect2(Vector2(170, 5), Vector2(300, 13)),
		float(sim.colossus["hp"]) / float(SimWorld.COLOSSUS_HP))


func _draw_projectiles() -> void:
	for g in sim.grenades:
		var base := _to_screen(g["x"], g["y"])
		draw_circle(base + Vector2(2, 2), 3.0, Color(0, 0, 0, 0.35))   # shadow
		var spin := float(Engine.get_physics_frames()) * 0.4
		var body := base - Vector2(0, g["z"] * PX * 0.5)
		_spr("grenade", body, spin, 0.75 if g.get("shell", false) else 0.55)
	for b in sim.bullets:
		var bpos := _to_screen(b["x"], b["y"])
		var vel := Vector2(b["vx"], b["vy"]) * PX
		# Tracer: a fading tail plus a stretched round.
		draw_line(bpos - vel * 1.8, bpos - vel * 0.4, Color(1.0, 0.9, 0.5, 0.35), 1.2)
		_spr("bullet", bpos, vel.angle() + PI / 2, 0.42, Color.WHITE, 2.2)
	for b in sim.enemy_bullets:
		var a2 := Vector2(b["vx"], b["vy"]).angle()
		var bpos := _to_screen(b["x"], b["y"])
		# Soft red glow underlay: lethal things must read at a glance.
		draw_circle(bpos, 5.0, Color(1.0, 0.3, 0.2, 0.28))
		_spr("enemy_bullet", bpos, a2 + PI / 2, 0.55)


func _draw_players() -> void:
	for i in sim.players.size():
		var p := sim.players[i]
		if p["in_tank"] >= 0:
			continue   # rendered as the tank
		var pos := _to_screen(p["x"], p["y"]) + (_recoil[i] if i < _recoil.size() else Vector2.ZERO)
		var tex_name := "player1" if i == 0 else "player2"
		if p["alive"]:
			var angle := _aim_angle(p)
			var mod := Color.WHITE
			if p["roll_ticks"] > 0:
				# Roll: spin the sprite through the dodge, ghosts trailing it.
				angle += (1.0 - float(p["roll_ticks"]) / float(SimWorld.ROLL_TICKS)) * TAU
				mod = Color(1.2, 1.2, 1.2, 0.85)
				var rdir := Vector2(p["roll_dx"], p["roll_dy"]) * PX
				_spr(tex_name, pos - rdir * 10.0, angle, 0.52, Color(1, 1, 1, 0.14))
				_spr(tex_name, pos - rdir * 5.0, angle, 0.52, Color(1, 1, 1, 0.28))
			elif p["hurt_iframes"] > 0 and (p["hurt_iframes"] / 4) % 2 == 0:
				mod = Color(1, 1, 1, 0.4)   # mercy-window blink
			_spr(tex_name, pos, angle, 0.52, mod)
			if p["vest"]:
				draw_arc(pos, 14.0, 0, TAU, 24, Color(0.55, 0.7, 1.0, 0.9), 2.0)
		else:
			_spr(tex_name, pos, PI / 2, 0.52, Color(0.35, 0.35, 0.35, 0.6))
			draw_arc(pos, 12.0, 0, TAU, 24, Color(0.8, 0.3, 0.25, 0.8), 1.5)


func _draw_fx() -> void:
	for fx in _fx:
		var pos := _to_screen(fx["x"], fx["y"])
		var t: float = fx["t"]
		if fx["kind"] == "explosion":
			var frame := mini(3, int(t * 4.0))
			_spr("explosion%d" % frame, pos, t * 2.0, 0.45 + t * 0.5, Color(1, 1, 1, 1.0 - t * 0.7))
		elif fx["kind"] == "alert":
			# Expanding "spotted!" ring (observer arrival).
			draw_arc(pos, 6.0 + t * 42.0, 0, TAU, 28, Color(1.0, 0.25, 0.2, 0.8 - t * 0.7), 2.5)
			draw_arc(pos, 3.0 + t * 26.0, 0, TAU, 24, Color(1.0, 0.6, 0.2, 0.7 - t * 0.6), 1.5)
		elif fx["kind"] == "muzzle":
			var sz := (13.0 if fx.get("big", false) else 9.0) * (1.0 - t * 0.6)
			var dirv := Vector2.from_angle(fx["a"])
			var pv := Vector2(-dirv.y, dirv.x)
			var mc := Color(1.0, 0.95, 0.55, 0.95 - t * 0.85)
			draw_line(pos, pos + dirv * sz * 1.6, mc, 2.5)
			draw_line(pos - pv * sz * 0.55, pos + pv * sz * 0.55, mc, 2.0)
			draw_circle(pos, sz * 0.45, Color(1.0, 1.0, 0.8, 0.9 - t * 0.8))
		elif fx["kind"] == "casing":
			draw_set_transform(pos, fx["spin"] + t * 6.0, Vector2.ONE)
			draw_rect(Rect2(-1.5, -0.75, 3.0, 1.5), Color(0.95, 0.8, 0.3, 1.0 - t * 0.8))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif fx["kind"] == "smoke":
			_spr("smoke", pos - Vector2(0, t * 10.0), t, 0.3 + t * 0.25, Color(1, 1, 1, 0.6 - t * 0.55))


func _draw_telegraphs() -> void:
	# Truthful mortar telegraph: the outer ring IS the kill radius, the disc
	# filling toward it is the timer, and the last fifth strobes white.
	for s in sim.strikes:
		var sp := _to_screen(s["x"], s["y"])
		var frac: float = 1.0 - float(s["ticks"]) / float(SimWorld.STRIKE_TELEGRAPH_TICKS)
		var r := SimWorld.GRENADE_RADIUS * PX
		var col := Color(1.0, 0.9 - frac * 0.6, 0.2, 0.9)
		if s["ticks"] <= 10 and (s["ticks"] / 3) % 2 == 0:
			col = Color(1.0, 1.0, 1.0, 0.95)
		draw_arc(sp, r, 0, TAU, 32, col, 1.5)
		draw_circle(sp, r * frac, Color(col.r, col.g, col.b, 0.20))
		draw_arc(sp, r * frac, 0, TAU, 28, col, 2.0)
		draw_line(sp + Vector2(-5, 0), sp + Vector2(5, 0), col, 1.5)
		draw_line(sp + Vector2(0, -5), sp + Vector2(0, 5), col, 1.5)


func _draw_bar(rect: Rect2, frac: float, fill := Color(0.85, 0.25, 0.18)) -> void:
	## Sprite-framed progress bar: dark well, colored fill, metal frame on top.
	var inset := Vector2(rect.size.x * 0.06, rect.size.y * 0.22)
	var well := Rect2(rect.position + inset, rect.size - inset * 2.0)
	draw_rect(well, Color(0.08, 0.07, 0.06, 0.9))
	well.size.x *= clampf(frac, 0.0, 1.0)
	draw_rect(well, fill)
	draw_texture_rect(Art.tex("ui_bar_frame"), rect, false)


func _draw_wheel() -> void:
	for i in sim.players.size():
		if i >= _wheel.size() or not _wheel[i]["open"]:
			continue
		var p := sim.players[i]
		if not p["alive"]:
			continue
		var c := _to_screen(p["x"], p["y"])
		draw_circle(c, 42.0, Color(0.04, 0.07, 0.04, 0.55))
		# Center hub: the fuel-cap ring framing the War Chest itself — this
		# wheel drains the same pool that funds revives.
		_spr("ui_dial_fuel", c, 0.0, 34.0 / 600.0)
		var f := ThemeDB.fallback_font
		var chest := str(sim.war_chest)
		var cw := f.get_string_size(chest, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var cx := c.x - (10.0 + cw) / 2.0
		draw_texture_rect(Art.tex("icon_coin"), Rect2(cx, c.y - 5.0, 9, 9), false)
		draw_string(f, Vector2(cx + 10.0, c.y + 3.0), chest,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.95, 0.65))
		for s in 4:
			var item: Dictionary = WHEEL_ITEMS[_SECTOR_TO_ITEM[s]]
			var ang := s * TAU / 4.0
			var ipos := c + Vector2.from_angle(ang) * 31.0
			var afford: bool = sim.war_chest >= item["cost"]
			var selected: bool = _wheel[i]["sel"] == s
			# Socket sprite authored nub-down (north slot); +90° per sector
			# keeps the connector nub pointing at the hub.
			var sock_mod := Color.WHITE
			if selected:
				sock_mod = Color(1.3, 1.18, 0.7) if afford else Color(1.2, 0.6, 0.55)
			_spr("ui_wheel_socket", ipos, ang + PI / 2.0,
				(38.0 if selected else 31.0) / 512.0, sock_mod)
			var icon_mod := Color.WHITE if afford else Color(0.8, 0.35, 0.35, 0.55)
			var isz := 18.0 if selected else 14.0
			draw_texture_rect(Art.tex(item["icon"]),
				Rect2(ipos - Vector2(isz, isz) / 2.0, Vector2(isz, isz)), false, icon_mod)
			draw_string(f, ipos + Vector2(-7, 24), str(item["cost"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(1.0, 0.95, 0.65) if afford else Color(0.9, 0.5, 0.45))


func _draw_banners() -> void:
	if _flash_alpha > 0.01:
		draw_rect(Rect2(0, 0, 640, 360), Color(1, 1, 1, _flash_alpha))
	if sim.victory:
		draw_rect(Rect2(160, 150, 320, 60), Color(0, 0, 0, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(238, 186), "V I C T O L Y !",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.3))
	elif sim.last_stand:
		draw_string(ThemeDB.fallback_font, Vector2(250, 350), "LAST STAND — NO REVIVES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.4, 0.3))


func _update_hud() -> void:
	_hud_icons.queue_redraw()
