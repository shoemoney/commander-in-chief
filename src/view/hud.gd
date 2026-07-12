class_name HudIcons
extends Control
## Icon HUD drawn on the shake-immune CanvasLayer. Replaces the P3 plain-text
## readout: War Chest coin, score medal, and per-player ammo/grenade/vest/
## fuel/skull states render as baked legacy art icons (assets/legacy-art/icons/).

const ICON := 13.0
const FONT_SIZE := 10

var main: Node2D
var _prev_chest := 0
var _chest_pulse := 0.0   # gold flash on the counter when coin comes in
var _prev_score := 0
var _score_pulse := 0.0   # gold flash on the score medal when it ticks up


## Emphasis blink that honors REDUCE MOTION: steady-on (no strobe) when reduced,
## so the amber/red states stay legible without flashing.
func _mblink(period: int) -> bool:
	return main._motion < 0.5 or Art.blink(period)


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: SimWorld = main.sim

	# Scavenged-metal panel backing the whole readout.
	draw_texture_rect(Art.tex("ui_panel"),
		Rect2(2, 2, 262, 26 + sim.players.size() * 16), false, Color(1, 1, 1, 0.9))

	# Row 0: the shared economy — the twist the whole game hangs on.
	if sim.war_chest > _prev_chest:
		_chest_pulse = 1.0
	_prev_chest = sim.war_chest
	_chest_pulse = maxf(0.0, _chest_pulse - 0.05)
	var x := 8.0
	var y := 6.0
	x = _stat("icon_coin", str(sim.war_chest), x, y,
		Color(0.95, 0.96, 0.9).lerp(Color(1.0, 0.85, 0.3), _chest_pulse))
	if sim.score > _prev_score:
		_score_pulse = 1.0
	_prev_score = sim.score
	_score_pulse = maxf(0.0, _score_pulse - 0.05)
	x = _stat("icon_medal", str(sim.score), x, y,
		Color(0.95, 0.96, 0.9).lerp(Color(1.0, 0.9, 0.4), _score_pulse))
	# Live kill-streak: the count + a draining timer ring, so the score-bonus
	# tiers (5/10/20) are readable in the moment, not just at milestone pops.
	if sim.kill_streak >= 2:
		var scol := Color(1.0, 0.82, 0.32) if sim.kill_streak < 10 else Color(1.0, 0.5, 0.2)
		x = _text("x%d" % sim.kill_streak, x, y + ICON - 3.0, scol) + 3.0
		var sfrac := clampf(float(sim.kill_streak_timer) / float(SimWorld.KILL_STREAK_WINDOW_TICKS), 0.0, 1.0)
		draw_arc(Vector2(x + 4.0, y + ICON / 2.0), 4.5, -PI / 2, -PI / 2 + TAU * sfrac, 14, scol, 1.5)
		x += 13.0
	# Live BEST target: the record to beat, right next to the current score.
	if main.best_score > 0:
		x = _text("BEST %d" % main.best_score, x, y + ICON - 3.0,
			Color(0.75, 0.7, 0.5)) + 8.0
	if sim.mode == "endless":
		if sim.intermission_ticks > 0:
			# Closing-soon urgency, same idiom as low ammo: amber under 2s, then
			# blinking red under 1s so the shop window doesn't lapse unnoticed.
			var shop_col := Color(1.0, 0.9, 0.5)
			if sim.intermission_ticks < 60:
				shop_col = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.7, 0.2, 0.18)
			elif sim.intermission_ticks < 120:
				shop_col = Color(1.0, 0.6, 0.3)
			x = _text("SHOP OPEN %ds" % [sim.intermission_ticks / 60], x, y + ICON - 3.0,
				shop_col) + 10.0
		else:
			x = _text("WAVE %d" % sim.wave, x, y + ICON - 3.0) + 8.0
			# Persistent mutator chip — the wave's identity, not just a one-shot banner.
			if sim.wave_mod > 0:
				var mchip: String = ["", "BLITZ", "ELITE GUARD", "SPOTTER"][sim.wave_mod]
				x = _text(mchip, x, y + ICON - 3.0, Color(1.0, 0.6, 0.35)) + 8.0
			# Live wave-clear dashboard: how close is this wave to done? (the
			# push-or-hold decision was blind — enemy count already computed
			# every frame for the music bed).
			var alive := 0
			for e in sim.enemies:
				if e["alive"]:
					alive += 1
			var remaining: int = alive + sim.wave_pending
			# The wave's starting budget (same formula _start_wave uses).
			var wave_total: int = maxi(1, SimWorld.WAVE_BASE_ENEMIES
				+ SimWorld.WAVE_ENEMIES_PER_WAVE * (sim.wave - 1))
			x = _text("HOSTILES %d" % remaining, x, y + ICON - 3.0, Color(1.0, 0.55, 0.4)) + 6.0
			var cleared := 1.0 - float(remaining) / float(wave_total)
			draw_rect(Rect2(x, y + 3, 40, 7), Color(0.1, 0.09, 0.08))
			draw_rect(Rect2(x, y + 3, 40 * clampf(cleared, 0.0, 1.0), 7), Art.safe(Color(0.4, 0.85, 0.4)))
			x += 48.0
	else:
		# SECTOR n/5: campaign progress toward the Foundry finale.
		var opened := 0
		for g in sim.gates:
			if g["open"]:
				opened += 1
		x = _text("SECTOR %d/%d  %dm" % [mini(opened + 1, 5), 5,
			-Fixed.to_int(sim.camera_top) / 10], x, y + ICON - 3.0) + 10.0
	# Discoverability: the supply wheel exists (hold to open).
	Art.draw_glyph(self, "wheel", Vector2(x + 5.0, y + ICON / 2.0), 11.0)
	x = _text("SUPPLIES", x + 13.0, y + ICON - 3.0, Color(0.75, 0.78, 0.7, 0.8)) + 12.0

	# PRESSURE gauge: the hidden stall→observer timer, made a dial the player
	# can manage — it climbs while the camera isn't advancing, drains on push.
	if sim.mode == "campaign" and sim.observer.is_empty() and sim.stall_ticks > 30:
		var pf := clampf(float(sim.stall_ticks) / float(SimWorld.OBSERVER_STALL_TICKS), 0.0, 1.0)
		_text("PRESSURE", x, y + ICON - 3.0, Color(1.0, 0.55, 0.3))
		draw_rect(Rect2(x + 48, y + 3, 46, 7), Color(0.1, 0.09, 0.08))
		draw_rect(Rect2(x + 48, y + 3, 46 * pf, 7),
			Color(1.0, 0.3, 0.2) if pf > 0.7 else Color(1.0, 0.7, 0.25))

	# Player rows.
	var ry := y + 17.0
	for i in sim.players.size():
		var p := sim.players[i]
		var px := 8.0
		var pcol := Color(0.75, 0.95, 0.7) if i == 0 else Color(0.95, 0.85, 0.6)
		px = _text("P%d" % (i + 1), px, ry + ICON - 3.0, pcol) + 7.0
		if not p["alive"]:
			px = _stat("icon_skull", "x%d" % p["deaths"], px, ry)
			if sim.last_stand:
				_text("K.I.A.", px, ry + ICON - 3.0, Color(0.9, 0.35, 0.3))
			elif p["broke_timer"] > 0:
				# A free rescue is already ticking — say so, or it reads as death.
				_text("RALLYING %ds" % (p["broke_timer"] / 60 + 1), px, ry + ICON - 3.0,
					Color(0.6, 0.85, 1.0))
			else:
				# Affordability at a glance: green if the chest covers it, red
				# if not — the revive-or-hoard decision made legible.
				var cost := sim.revive_cost(p)
				var afford: bool = sim.war_chest >= cost
				var blink := _mblink(20)
				var col: Color
				if afford:
					col = Art.safe(Color(0.5, 1.0, 0.5) if blink else Color(0.4, 0.8, 0.4))
				else:
					col = Color(1.0, 0.4, 0.35) if blink else Color(0.8, 0.35, 0.3)
				var tx := _text("REVIVE %d" % cost, px, ry + ICON - 3.0, col)
				Art.draw_glyph(self, "revive", Vector2(tx + 9.0, ry + ICON / 2.0), 11.0)
		elif p["in_tank"] >= 0:
			var t: Dictionary = sim.tanks[p["in_tank"]]
			px = _fuel_dial(t, px, ry)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry)
			if t["burning"] and _mblink(8):
				var bx := _text("BAIL OUT!", px, ry + ICON - 3.0, Color(1.0, 0.3, 0.2))
				Art.draw_glyph(self, "interact", Vector2(bx + 9.0, ry + ICON / 2.0), 11.0)
		else:
			# Low-ammo escalation: amber under 20, blinking red when dry.
			var ammo: int = p["mg_ammo"]
			var acol := Color(0.95, 0.96, 0.9)
			if ammo == 0:
				acol = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.6, 0.2, 0.18)
			elif ammo <= 20:
				acol = Color(1.0, 0.75, 0.35)
			var ammo_x := px
			px = _stat("icon_ammo", "%02d" % ammo, px, ry, acol)
			# Empty-clip bash on cooldown: a draining ring on the dry ammo icon
			# so "melee not ready" reads distinctly from "input ignored".
			if ammo == 0 and p["fire_cd"] > 0:
				var bfrac := clampf(float(p["fire_cd"]) / float(SimWorld.BASH_COOLDOWN_TICKS), 0.0, 1.0)
				draw_arc(Vector2(ammo_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					-PI / 2, -PI / 2 + TAU * bfrac, 16, Color(0.9, 0.6, 0.3, 0.8), 1.5)
			# Grenade pip flashes red on an empty-throw attempt (dry-throw cue).
			var gcol := Color(0.95, 0.96, 0.9)
			if main._grenade_dry > 0 and _mblink(4):
				gcol = Color(1.0, 0.3, 0.25)
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry, gcol)
			if p["vest"]:
				draw_texture_rect(Art.tex("icon_vest"), Rect2(px, ry, ICON, ICON), false)
		ry += 16.0


func _fuel_dial(t: Dictionary, x: float, y: float) -> float:
	# Fuel-cap gauge: ring frames an arc that drains green → red.
	var frac := clampf(float(t["fuel"]) / float(SimWorld.TANK_FUEL_TICKS), 0.0, 1.0)
	var c := Vector2(x + ICON / 2.0, y + ICON / 2.0)
	draw_circle(c, ICON * 0.34, Color(0.08, 0.07, 0.06))
	if frac > 0.0:
		# Full→empty reads red↔green normally; red↔blue under colorblind (green is
		# the indistinguishable end), so the drain stays legible either way.
		var fuel_col := Color(0.9 - frac * 0.7, 0.15, 0.12 + frac * 0.75) if Art.colorblind \
			else Color(0.9 - frac * 0.7, 0.15 + frac * 0.65, 0.12)
		draw_arc(c, ICON * 0.27, -PI / 2, -PI / 2 + TAU * frac, 20, fuel_col, 2.5)
	draw_texture_rect(Art.tex("ui_dial_fuel"), Rect2(x - 1, y - 1, ICON + 2, ICON + 2), false)
	return _text("%ds" % maxi(0, t["fuel"] / 60), x + ICON + 3.0, y + ICON - 3.0) + 10.0


func _stat(icon: String, txt: String, x: float, y: float,
		col := Color(0.95, 0.96, 0.9)) -> float:
	draw_texture_rect(Art.tex(icon), Rect2(x, y, ICON, ICON), false)
	return _text(txt, x + ICON + 3.0, y + ICON - 3.0, col) + 10.0


func _text(txt: String, x: float, y: float, col := Color(0.95, 0.96, 0.9)) -> float:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(x + 1, y + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		Color(0, 0, 0, 0.65))
	draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
	return x + f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
