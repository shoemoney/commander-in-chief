class_name HudIcons
extends Control
## Icon HUD drawn on the shake-immune CanvasLayer. Replaces the P3 plain-text
## readout: War Chest coin, score medal, and per-player ammo/grenade/vest/
## fuel/skull states render as baked legacy art icons (assets/legacy-art/icons/).

const ICON := 13.0
const FONT_SIZE := 10
const RIGHT := 632.0  # safe right margin (design width 640); chips past it drop

var main: Node2D
var _prev_chest := 0
var _chest_pulse := 0.0   # gold flash on the counter when coin comes in
var _prev_score := 0
var _score_pulse := 0.0   # gold flash on the score medal when it ticks up
var _disp_chest := -1.0   # displayed value, catches up to war_chest so big jumps roll up
var _disp_score := -1.0   # displayed value, catches up to score so big jumps roll up
var _prow_r := 0.0        # widest player buff-row right edge (1-frame lag) so the plate covers it
var _plate_r := 262.0     # plate right edge (dynamic up to RIGHT) — markers avoid it, not the 262 floor
var _fit_right := RIGHT    # RIGHT, minus the corner reserved for CB/RM pips when either is live
                          # (so row-0 chips stop short instead of drawing under the pips)
var _plate_ci := RID()    # panel backing on its own canvas item (z -1): drawn
                          # behind the chips but SIZED after the row is laid out,
                          # so it fits THIS frame's content (no 1-frame overhang)


func _ready() -> void:
	_plate_ci = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_plate_ci, get_canvas_item())
	RenderingServer.canvas_item_set_z_index(_plate_ci, -1)
	RenderingServer.canvas_item_set_visible(_plate_ci, is_visible_in_tree())


func _notification(what: int) -> void:
	if not _plate_ci.is_valid():
		return
	match what:
		# PREDELETE fires on every Object destruction (free/queue_free), in or
		# out of the tree — so an _exit_tree-then-free path still lands here.
		NOTIFICATION_PREDELETE:
			RenderingServer.free_rid(_plate_ci)
			_plate_ci = RID()
		# Sync plate visibility only when it can actually change (show/hide or
		# tree membership), never per-frame.
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_ENTER_TREE, NOTIFICATION_EXIT_TREE:
			RenderingServer.canvas_item_set_visible(_plate_ci, is_visible_in_tree())


## Pulse decay + rollup catch-up step here, delta-scaled — they used to tick
## per-_draw (-0.05/frame), which ran 2x fast on a 120 Hz display. Rates match
## the old 60 Hz feel; exp() keeps the ease framerate-independent (menu.gd idiom).
func _process(delta: float) -> void:
	if main == null or main.sim == null:
		return
	var sim: SimWorld = main.sim
	if sim.war_chest > _prev_chest:
		_chest_pulse = 1.0
	_prev_chest = sim.war_chest
	if sim.score > _prev_score:
		_score_pulse = 1.0
	_prev_score = sim.score
	var decay := 3.0 * delta   # == the old -0.05/frame at 60 Hz
	_chest_pulse = maxf(0.0, _chest_pulse - decay)
	_score_pulse = maxf(0.0, _score_pulse - decay)
	if _disp_chest < 0.0:
		_disp_chest = float(sim.war_chest)
	if _disp_score < 0.0:
		_disp_score = float(sim.score)
	if main._motion < 0.5:
		_disp_chest = float(sim.war_chest)   # REDUCE MOTION: snap, no odometer spin-up
		_disp_score = float(sim.score)
	else:
		_disp_chest = _rollup(_disp_chest, float(sim.war_chest), delta)
		_disp_score = _rollup(_disp_score, float(sim.score), delta)


## Emphasis blink that honors REDUCE MOTION: steady-on (no strobe) when reduced,
## so the amber/red states stay legible without flashing.
func _mblink(period: int) -> bool:
	return main._motion < 0.5 or Art.blink(period)


func _buff_col(ticks: int, base: Color) -> Color:
	# Expiry warning (8/9 panel consensus): the last 2s a timed buff's chip goes
	# urgent red — smoke warned before dropping, the others snapped off mid-fight.
	# _mblink holds the red STEADY under reduce-motion (blink only when allowed).
	return (Color(1.0, 0.3, 0.25) if _mblink(10) else base) if ticks < 120 else base


func plate_right() -> float:
	# Dynamic right edge of the corner plate (was hardcoded 262, its MINIMUM) so
	# off-screen markers relocate clear of the ACTUAL panel, not a stale literal.
	return _plate_r


func panel_bottom() -> float:
	# Bottom edge of the corner panel — THE source of the layout rule (incl.
	# the 2P shop-strip height drop). main.gd's overlay-avoidance used to carry
	# its own copy of this formula minus the drop rule and desynced by 16px.
	var sim: SimWorld = main.sim
	var shop_row: bool = sim.mode == "endless" and sim.intermission_ticks > 0
	if shop_row and 26 + (sim.players.size() + 1) * 16 > 60:
		shop_row = false
	return 2.0 + 26.0 + sim.players.size() * 16.0 + (16.0 if shop_row else 0.0)


func _draw() -> void:
	if main == null or main.sim == null:
		# No sim to size the plate against — clear it so no stale panel lingers.
		if _plate_ci.is_valid():
			RenderingServer.canvas_item_clear(_plate_ci)
		return
	var sim: SimWorld = main.sim
	# REDUCE MOTION: the value rollup still runs (_process), but the visual
	# pulse (scale-thump + gold color lerp) holds at 0 — no animated flash.
	var chest_pulse: float = 0.0 if main._motion < 0.5 else _chest_pulse
	var score_pulse: float = 0.0 if main._motion < 0.5 else _score_pulse
	# Shop preview strip adds one row while the SHOP OPEN window is live, so
	# the buy list is readable without holding the spend-wheel open.
	var shop_row := sim.mode == "endless" and sim.intermission_ticks > 0
	# Safe-height clamp: boss HP bars dock at y=64 (main sizes them to a ~60px
	# panel max), so when player rows + strip would cross that line the strip
	# drops first — lowest-priority row, same outrank rule as HOSTILES-vs-vanity
	# on the width axis. Its timer chip in row 0 survives.
	if shop_row and 26 + (sim.players.size() + 1) * 16 > 60:
		shop_row = false
	var panel_h := int(panel_bottom()) - 2
	if _disp_chest < 0.0:
		_disp_chest = float(sim.war_chest)   # first draw can beat first _process
	if _disp_score < 0.0:
		_disp_score = float(sim.score)

	# When a CB/RM pip is live it owns the top-right corner — pull the chip
	# fit-bound in by its width so the rightmost row-0 chip can't draw under it
	# (the pip is the readout the players who set those toggles rely on).
	_fit_right = RIGHT - (18.0 if (Art.colorblind or main._motion < 0.5) else 0.0)
	# Row 0: the shared economy — the twist the whole game hangs on.
	var x := 8.0
	var y := 6.0
	# Two economies, two casts (3-vote play-panel: the numerals were identical
	# and players conflated spendable coin with vanity score): the CHEST reads
	# warm cream (money-gold family), the SCORE cool steel — both still flash
	# gold on their pulse.
	x = _stat("icon_coin", str(int(round(_disp_chest))), x, y,
		Color(1.0, 0.93, 0.78).lerp(Color(1.0, 0.85, 0.3), chest_pulse), chest_pulse)
	x = _stat("icon_medal", str(int(round(_disp_score))), x, y,
		Color(0.84, 0.9, 1.0).lerp(Color(1.0, 0.9, 0.4), score_pulse), score_pulse)
	if sim.tokens > 0:
		# Commendation tokens: minted by play, spent on the wheel's NE socket.
		x = _text("*%d" % sim.tokens, x, y + ICON - 3.0, Color(1.0, 0.85, 0.3)) + 3.0
	# Live kill-streak: the count + a draining timer ring, so the score-bonus
	# tiers (5/10/20) are readable in the moment, not just at milestone pops.
	if sim.kill_streak >= 2:
		var stxt := "x%d" % sim.kill_streak
		if _fits(x, _tw(stxt) + 16.0):
			var scol := Color(1.0, 0.82, 0.32) if sim.kill_streak < 10 else Color(1.0, 0.5, 0.2)
			x = _text(stxt, x, y + ICON - 3.0, scol) + 3.0
			var sfrac := clampf(float(sim.kill_streak_timer) / float(SimWorld.KILL_STREAK_WINDOW_TICKS), 0.0, 1.0)
			var sc := Vector2(x + 4.0, y + ICON / 2.0)
			# Dim full-circle track under the drain, so remaining time reads
			# against a whole instead of a floating partial arc.
			draw_arc(sc, 4.5, 0, TAU, 20, Color(scol.r, scol.g, scol.b, 0.25), 1.5)
			if main._motion < 0.5:
				# REDUCE MOTION: quarter-snapped instead of a per-frame drain —
				# the ring steps 4 times per window rather than animating.
				sfrac = ceilf(sfrac * 4.0) / 4.0
			draw_arc(sc, 4.5, -PI / 2, -PI / 2 + TAU * sfrac, 20, scol, 1.5)
			x += 13.0
			# Next-tier pip: how close to the x5/x10/x20 bonus, since the
			# ring alone only reads "streak alive", not "how close".
			var snext := 0
			if sim.kill_streak < 5:
				snext = 5
			elif sim.kill_streak < 10:
				snext = 10
			elif sim.kill_streak < 20:
				snext = 20
			if snext > 0:
				var shint := ">x%d" % snext
				if _fits(x, _tw(shint) + 6.0):
					x = _text(shint, x, y + ICON - 3.0, Color(0.85, 0.85, 0.8, 0.65)) + 6.0
	# Flawless Gate streak: the compounding clean-checkpoint multiplier, shown as
	# a gold star chip so the discipline reward is visible before the payoff.
	if sim.mode == "campaign" and sim.flawless_streak >= 1:
		draw_texture_rect(Art.tex("hud_star"), Rect2(x, y, ICON, ICON), false, Color(1.0, 0.9, 0.4))
		x = _text("x%d" % sim.flawless_streak, x + ICON + 1.0, y + ICON - 3.0,
			Color(1.0, 0.9, 0.45)) + 8.0
	# Live BEST target: the record to beat, right next to the current score.
	# Crossing it mid-run used to be silent until the K.I.A. debrief -- flip
	# the chip gold and pulse it the instant the live score passes it.
	if main.best_score > 0:
		var beating: bool = sim.score > main.best_score
		var btxt := ("RECORD! %d" % sim.score) if beating else ("BEST %d" % main.best_score)
		if _fits(x, _tw(btxt) + 8.0):
			var bcol := Color(0.75, 0.7, 0.5)
			if beating:
				var rp: float = 1.0 if main._motion < 0.5 else Art.pulse(0.2)
				bcol = Color(0.75, 0.7, 0.5).lerp(Color(1.0, 0.85, 0.25), 0.5 + 0.5 * rp)
			x = _text(btxt, x, y + ICON - 3.0, bcol) + 8.0
	if sim.mode == "endless":
		if sim.intermission_ticks > 0:
			# Closing-soon urgency, same idiom as low ammo: amber under 2s, then
			# blinking red under 1s so the shop window doesn't lapse unnoticed.
			var shop_col := Color(1.0, 0.9, 0.5)
			if sim.intermission_ticks < 60:
				shop_col = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.7, 0.2, 0.18)
			elif sim.intermission_ticks < 120:
				shop_col = Color(1.0, 0.6, 0.3)
			# Ceil: floor division read "SHOP OPEN 0s" for the entire final live second.
			x = _stat("hud_gunshop", "SHOP OPEN %ds" % [(sim.intermission_ticks + 59) / 60], x, y,
				shop_col)
		else:
			x = _stat("hud_flag", "WAVE %d" % sim.wave, x, y) - 2.0
			# Live wave-clear dashboard FIRST: when the row overflows, the
			# push-or-hold gauge must survive and the vanity chips must drop —
			# it used to be the other way around, vanishing exactly mid-chaos.
			var alive := 0
			for e in sim.enemies:
				# The pilot is an optional side objective — the sim's own
				# _wave_hostiles_cleared() skips it, so counting it here made the
				# HUD hunt one more "hostile" that can't be shot (rescued by touch).
				if e["alive"] and e["kind"] != "pilot":
					alive += 1
			var remaining: int = alive + sim.wave_pending
			# The wave's starting budget (same formula _start_wave uses).
			var wave_total: int = maxi(1, SimWorld.WAVE_BASE_ENEMIES
				+ SimWorld.WAVE_ENEMIES_PER_WAVE * (sim.wave - 1))
			var htxt := "HOSTILES %d" % remaining
			if _fits(x, ICON + 3.0 + _tw(htxt) + 54.0):
				x = _stat("hud_skull", htxt, x, y, Color(1.0, 0.55, 0.4)) - 4.0
				var cleared := 1.0 - float(remaining) / float(wave_total)
				_mini_bar(Rect2(x, y + 2, 40, 9), cleared, Art.safe(Color(0.4, 0.85, 0.4)))
				x += 48.0
			# Live WAVE record chip — endless is the mode players grind, but the wave
			# count (the number they chase) only got record feedback in the K.I.A.
			# debrief. Same idiom as the score BEST chip: grey while chasing a prior
			# best, gold the instant this run ties/beats it.
			if main.best_wave > 0:
				var wbeat: bool = sim.wave >= main.best_wave
				var wtxt := "WAVE RECORD!" if wbeat else ("BEST W%d" % main.best_wave)
				if _fits(x, _tw(wtxt) + 8.0):
					var wcol := Color(0.75, 0.7, 0.5)
					if wbeat:
						var wp: float = 1.0 if main._motion < 0.5 else Art.pulse(0.2)
						wcol = Color(0.75, 0.7, 0.5).lerp(Color(1.0, 0.85, 0.25), 0.5 + 0.5 * wp)
					x = _text(wtxt, x, y + ICON - 3.0, wcol) + 8.0
			# Clean-wave (deathless) live badge — endless's answer to the campaign
			# flawless star: lit while this wave's Clean Wave bonus is alive, drops the
			# instant a player goes down. Reads the hashed sim field, no view state.
			if sim.wave > 1 and sim.deaths_this_wave == 0 and _fits(x, _tw("DEATHLESS") + 8.0):
				var dpul: float = 1.0 if main._motion < 0.5 else Art.pulse(0.25)
				var dcol := Art.safe(Color(0.55, 0.9, 0.5)).lerp(Color(1.0, 0.9, 0.5), 0.4 * dpul)
				x = _text("DEATHLESS", x, y + ICON - 3.0, dcol) + 8.0
			# Persistent mutator chip — the wave's identity, not just a one-shot banner.
			if sim.wave_mod > 0:
				var mnames: Array[String] = ["", "BLITZ", "ELITE GUARD", "SPOTTER", "PAYDAY", "NIGHT OPS", "FRENZY"]
				# Icon badge per mutator (every other threat callout got one in p3):
				# lightning=fast spawns, skull=elites, target=spotted, coin=double
				# bounties, radiation=hazard field (vision dims), fire=frenzy speed.
				var micons: Array[String] = ["", "hud_lightning", "hud_skull", "hud_target",
					"icon_coin", "hud_radiation", "hud_fire"]
				var mchip: String = mnames[sim.wave_mod] if sim.wave_mod < mnames.size() else ""
				if mchip != "" and _fits(x, ICON + 3.0 + _tw(mchip) + 8.0):
					var mcol := Color(1.0, 0.6, 0.35)
					# icon_coin is a colored bake — keep it gold; the white map
					# glyphs take the chip tint.
					var micon: String = micons[sim.wave_mod]
					draw_texture_rect(Art.tex(micon), Rect2(x, y, ICON, ICON), false,
						Color.WHITE if micon == "icon_coin" else mcol)
					x = _text(mchip, x + ICON + 3.0, y + ICON - 3.0, mcol) + 8.0
	else:
		# SECTOR n/5: campaign progress toward the Foundry finale.
		var opened := 0
		for g in sim.gates:
			if g["open"]:
				opened += 1
		x = _text("SECTOR %d/%d  %dm" % [mini(opened + 1, 5), 5,
			-Fixed.to_int(sim.camera_top) / 10], x, y + ICON - 3.0) + 10.0
	# Discoverability: the supply wheel exists (hold to open).
	# Suppressed while the endless shop strip is SHOWN — two buy affordances at
	# once (wheel cue + priced strip) read as conflicting instructions. When the
	# strip drops for height, the wheel cue is the buy affordance again.
	if not shop_row and _fits(x, _tw("SUPPLIES") + 25.0):
		Art.draw_glyph(self, "wheel", Vector2(x + 5.0, y + ICON / 2.0), 11.0)
		x = _text("SUPPLIES", x + 13.0, y + ICON - 3.0, Color(0.75, 0.78, 0.7, 0.8)) + 12.0
	# Flashbang stun: a field-wide effect (every enemy skips its step) that had
	# zero HUD read — the countdown says how long the free-fire window lasts.
	if sim.flash_ticks > 0 and _fits(x, 42.0):
		x = _stat("wep_flashbang", "%ds" % ((sim.flash_ticks + 59) / 60), x, y,
			Color(1.0, 0.95, 0.7)) + 4.0
	var row_r := x

	# PRESSURE gauge: the hidden stall→observer timer, made a dial the player
	# can manage — it climbs while the camera isn't advancing, drains on push.
	if sim.mode == "campaign" and sim.observer.is_empty() and sim.stall_ticks > 30:

		# A closed gate/boss/colossus pinning the camera means advancing is
		# impossible until the fight is won — the "advance!" PRESSURE read would be
		# lying, so swap it for the real objective and drop the climbing fill.
		var gate_locked := false
		for g in sim.gates:
			if not g["open"] and sim.camera_top >= g["y"] - SimWorld.GATE_CAMERA_PAD \
					and g["y"] >= sim.camera_top:
				gate_locked = true
				break
		# The punishment telegraph outranks vanity chips: clamp back over the
		# tail of whatever optional chip came before, by MEASURED width — the
		# old fixed 94px was narrower than both the 'PRESSURE'+bar row (the
		# bar's dark well overpainted the label's last ~22px) and 'CLEAR THE
		# GATE' (115px, which ran past the 640px viewport on a full row).
		if gate_locked:
			var gtxt := "CLEAR THE GATE"
			x = minf(x, RIGHT - _tw(gtxt))
			# Dark backing (the _pip plate color) over the clamped footprint — the
			# gauge deliberately overlaps the previous chip's tail, so separate the
			# two strings instead of overprinting them.
			draw_rect(Rect2(x - 2.0, y + 1.0, _tw(gtxt) + 4.0, 12.0), Color(0.1, 0.11, 0.09, 0.85))
			var gp: float = 1.0 if main._motion < 0.5 else Art.pulse(0.2)
			_text(gtxt, x, y + ICON - 3.0, Color(1.0, 0.6, 0.3).lerp(Color(1.0, 0.85, 0.4), 0.5 * gp))
			row_r = x + _tw(gtxt)
		else:
			var pw := ICON + 3.0 + _tw("PRESSURE") + 4.0
			x = minf(x, RIGHT - (pw + 48.0))
			var pf := clampf(float(sim.stall_ticks) / float(SimWorld.OBSERVER_STALL_TICKS), 0.0, 1.0)
			draw_rect(Rect2(x - 2.0, y + 1.0, pw + 50.0, 12.0), Color(0.1, 0.11, 0.09, 0.85))
			_stat("hud_lightning", "PRESSURE", x, y, Color(1.0, 0.55, 0.3))
			_mini_bar(Rect2(x + pw, y + 2, 46, 9), pf,
				Color(1.0, 0.3, 0.2) if pf > 0.7 else Color(1.0, 0.7, 0.25))
			row_r = x + pw + 48.0
	# Scavenged-metal panel backing the whole readout — emitted onto the z:-1
	# plate item now that this frame's row width is known, so new chips and
	# rollover digits never overhang the backing for a frame.
	RenderingServer.canvas_item_clear(_plate_ci)
	_plate_r = clampf(maxf(row_r, _prow_r) + 4.0, 262.0, RIGHT - 2.0)
	RenderingServer.canvas_item_add_texture_rect(_plate_ci,
		Rect2(2, 2, _plate_r, panel_h),
		Art.tex("ui_panel").get_rid(), false, Color(1, 1, 1, 0.9))

	# Shop preview strip: the 4 buyables at a glance (cost + green/red
	# affordability), matching the spend-wheel's own price coloring.
	var ry := y + 17.0
	if shop_row:
		var sx := 8.0
		for kind in 4:
			var icon: String = ["icon_ammo", "icon_grenade", "icon_vest", "icon_airstrike"][kind]
			var cost: int = sim._supply_cost(kind)
			var afford: bool = sim.war_chest >= cost
			var scol := Art.safe(Color(0.55, 0.9, 0.5)) if afford else Color(1.0, 0.45, 0.4)
			# "×" suffix: affordability readable without color vision — same mark
			# the spend wheel (the primary buy surface) draws beside its sockets.
			sx = _stat(icon, str(cost) + ("" if afford else "×"), sx, ry, scol)
		ry += 16.0

	# Player rows.
	var prow := 0.0
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
				# "×" tag = non-color affordability cue (cyan-vs-red is still
				# color-only for protan players even with colorblind mode on) —
				# one dialect with the shop strip and the spend wheel's socket mark.
				var rlabel := ("REVIVE %d" if afford else "REVIVE %d ×") % cost
				var tx := _text(rlabel, px, ry + ICON - 3.0, col)
				Art.draw_glyph(self, "revive", Vector2(tx + 9.0, ry + ICON / 2.0), 11.0,
					Color.WHITE, i == 1)
		elif p["in_tank"] >= 0:
			var t: Dictionary = sim.tanks[p["in_tank"]]
			px = _fuel_dial(t, px, ry)
			var gcol_tank := Color(0.95, 0.96, 0.9)
			if p["grenade_ammo"] == 0:
				# 0 shells = the cannon is dead — same proactive dry escalation as
				# MG ammo (the old dry-flash only fired AFTER a wasted attempt).
				gcol_tank = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.6, 0.2, 0.18)
			elif p["grenade_ammo"] == SimWorld.GRENADE_AMMO_MAX:
				gcol_tank = Color(0.6, 0.85, 1.0)
			var tg_x := px
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry, gcol_tank)
			# Cannon cooldown (45t — longer than bash or grenade): the same draining
			# ring every other fire cooldown got, so a mid-cooldown shot reads as
			# "wait a beat", not dropped input. The cannon draws from the grenade
			# pool, so the ring rides the grenade chip.
			if t["fire_cd"] > 0:
				var tfrac := clampf(float(t["fire_cd"]) / float(SimWorld.TANK_FIRE_COOLDOWN_TICKS), 0.0, 1.0)
				draw_arc(Vector2(tg_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					0, TAU, 16, Color(0.6, 0.8, 1.0, 0.18), 1.5)
				draw_arc(Vector2(tg_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					-PI / 2, -PI / 2 + TAU * tfrac, 16, Color(0.6, 0.8, 1.0, 0.75), 1.5)
			if t["burning"]:
				if _mblink(8):
					# The 3s fuse gets a number, like every other lethal window on
					# this HUD (RALLYING/fuel/SHOP OPEN) — ceil grammar from the
					# fuel dial, so it reads 3s → 2s → 1s → boom.
					var bx := _text("BAIL OUT! %ds" % ((t["burn_ticks"] + 59) / 60), px, ry + ICON - 3.0, Color(1.0, 0.3, 0.2))
					Art.draw_glyph(self, "interact", Vector2(bx + 9.0, ry + ICON / 2.0), 11.0,
						Color.WHITE, i == 1)
			else:
				# The sim decrements pierce/spread/rend/smoke unconditionally while
				# riding — without the shared chip row a Trench Gun expired invisibly
				# mid-ride and the 2s red expiry warning could never fire in a tank.
				px = _buff_chips(p, px, ry, i)
		else:
			# Low-ammo escalation: amber under 20, blinking red when dry.
			var ammo: int = p["mg_ammo"]
			var acol := Color(0.95, 0.96, 0.9)
			if ammo == 0:
				acol = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.6, 0.2, 0.18)
			elif ammo <= 20:
				acol = Color(1.0, 0.75, 0.35)
			elif ammo == SimWorld.MG_AMMO_MAX:
				acol = Color(0.6, 0.85, 1.0)
			var ammo_x := px
			# The ammo glyph reflects what's actually chambered: shotgun shells
			# during the Trench Gun window, AP rounds during Piercing, else MG.
			var acon := "icon_ammo"
			if p["spread_ticks"] > 0:
				acon = "item_bullet_shotgun"
			elif p["pierce_ticks"] > 0:
				acon = "item_bullet"
			px = _stat(acon, "%02d" % ammo, px, ry, acol)
			# Empty-clip bash on cooldown: a draining ring on the dry ammo icon
			# so "melee not ready" reads distinctly from "input ignored".
			if ammo == 0 and p["fire_cd"] > 0:
				var bfrac := clampf(float(p["fire_cd"]) / float(SimWorld.BASH_COOLDOWN_TICKS), 0.0, 1.0)
				draw_arc(Vector2(ammo_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					0, TAU, 16, Color(0.9, 0.6, 0.3, 0.18), 1.5)
				draw_arc(Vector2(ammo_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					-PI / 2, -PI / 2 + TAU * bfrac, 16, Color(0.9, 0.6, 0.3, 0.8), 1.5)
			# Segmented magazine bar next to the numeral — clip fill at a glance.
			px = _mag_bar(px, ry + 4.0, ammo, SimWorld.MG_AMMO_MAX)
			# Grenade pip flashes red on an empty-throw attempt (dry-throw cue).
			var gcol := Color(0.95, 0.96, 0.9)
			if p["grenade_ammo"] == 0:
				# Proactive dry state, matching the MG ammo escalation — the dry-flash
				# below only fires AFTER a wasted throw attempt.
				gcol = Color(1.0, 0.25, 0.2) if _mblink(10) else Color(0.6, 0.2, 0.18)
			elif p["grenade_ammo"] == SimWorld.GRENADE_AMMO_MAX:
				gcol = Color(0.6, 0.85, 1.0)
			if i < main._grenade_dry.size() and main._grenade_dry[i] > 0 and _mblink(4):
				gcol = Color(1.0, 0.3, 0.25)
			var gren_x := px
			px = _stat("icon_grenade", "%02d" % p["grenade_ammo"], px, ry, gcol)
			# Throw on cooldown: a draining ring on the grenade pip so a throw-while-
			# recharging reads as "wait a beat", not a dropped input (matches the bash ring).
			if p["grenade_cd"] > 0:
				var gfrac := clampf(float(p["grenade_cd"]) / float(SimWorld.GRENADE_COOLDOWN_TICKS), 0.0, 1.0)
				draw_arc(Vector2(gren_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					0, TAU, 16, Color(0.6, 0.8, 1.0, 0.18), 1.5)
				draw_arc(Vector2(gren_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					-PI / 2, -PI / 2 + TAU * gfrac, 16, Color(0.6, 0.8, 1.0, 0.75), 1.5)
			# Dodge availability: the roll's long cooldown was only shown as a faint
			# arc at the player's feet — a mashing player couldn't tell recharging
			# from unbound. Bright glyph when ready, dimmed + draining ring while
			# recharging (same grammar as the grenade/bash rings above).
			var roll_x := px
			var roll_ready: bool = p["roll_cd"] == 0
			Art.draw_glyph(self, "roll", Vector2(roll_x + ICON / 2.0, ry + ICON / 2.0), 11.0,
				Color.WHITE if roll_ready else Color(0.55, 0.6, 0.65, 0.6), i == 1)
			px = roll_x + ICON + 2.0
			if p["roll_cd"] > 0:
				var rfrac := clampf(float(p["roll_cd"]) / float(SimWorld.ROLL_CD_TICKS), 0.0, 1.0)
				draw_arc(Vector2(roll_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					0, TAU, 16, Color(0.6, 0.8, 1.0, 0.18), 1.5)
				draw_arc(Vector2(roll_x + ICON / 2.0, ry + ICON / 2.0), ICON * 0.55,
					-PI / 2, -PI / 2 + TAU * rfrac, 16, Color(0.6, 0.8, 1.0, 0.75), 1.5)
			px = _buff_chips(p, px, ry, i)
			# Live status pips: adrenaline speed-boost + wading — state you feel in
			# the hands, surfaced so it also reads on the HUD.
			if p["boost_ticks"] > 0:
				px = _pip(px, ry, Color(0.4, 0.95, 1.0), ">")
			if sim._in_water(p["x"], p["y"]):
				px = _pip(px, ry, Color(0.5, 0.8, 1.0), "~")
		prow = maxf(prow, px)
		ry += 16.0
	_prow_r = prow

	_accessibility_pips()


## Tiny top-right corner pips confirming REDUCE MOTION / COLORBLIND are live —
## both toggles reshape the whole HUD but had no on-screen state readout.
func _accessibility_pips() -> void:
	var acc_y := 8.0
	if Art.colorblind:
		_pip_plate("CB", acc_y)
		_text("CB", RIGHT - _tw("CB"), acc_y, Art.safe(Color(0.6, 0.85, 1.0, 0.85)))
		acc_y += 11.0
	if main._motion < 0.5:
		_pip_plate("RM", acc_y)
		_text("RM", RIGHT - _tw("RM"), acc_y, Art.safe(Color(0.75, 0.95, 0.7, 0.85)))


## Dark backing behind a corner pip — the pips draw over the live battlefield with
## no panel under them (the corner plate is top-LEFT), so they washed out on bright
## grass/water. A small scrim rect restores contrast without a full plate.
func _pip_plate(txt: String, py: float) -> void:
	var w := _tw(txt)
	# Kept fully left of RIGHT (was overhanging by 1px). 0.8 fill + a faint hairline
	# so the pip holds contrast over an explosion flash or bright water, not just grass.
	var r := Rect2(RIGHT - w - 3.0, py - 1.0, w + 3.0, 10.0)
	draw_rect(r, Color(0.05, 0.07, 0.05, 0.8))
	draw_rect(r, Color(0.7, 0.75, 0.7, 0.35), false, 1.0)


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
	return _text("%ds" % maxi(0, (t["fuel"] + 59) / 60), x + ICON + 3.0, y + ICON - 3.0) + 10.0   # ceil: "0s" only when actually empty


## Vest + timed-buff + claymore chip run, shared by the on-foot AND in-tank player
## rows — the sim decrements the buff timers unconditionally while riding, so the
## tank row must show (and expiry-warn) the same chips instead of dropping them.
func _buff_chips(p: Dictionary, px: float, ry: float, pi := 0) -> float:
	if p["vest"]:
		draw_texture_rect(Art.tex("icon_vest"), Rect2(px, ry, ICON, ICON), false)
		px += ICON + 2.0
	# Piercing Rounds / Trench Gun buffs: weapon-icon + countdown, matching
	# the ammo/grenade/vest stat grammar one row up (icon, not bare text).
	if p["pierce_ticks"] > 0:
		# item_bullet, NOT wep_rifle — Rend's chip is wep_rifle below, and the
		# icon is the non-color channel (pierce+rend both active = twin rifles
		# under colorblind). item_bullet echoes pierce's ammo-slot glyph.
		px = _stat("item_bullet", "%ds" % (p["pierce_ticks"] / 60 + 1), px, ry, _buff_col(p["pierce_ticks"], Color(0.6, 0.95, 1.0)))
	if p["spread_ticks"] > 0 and not p["triple"]:   # redundant once Triple is owned (same fan) — no false countdown
		px = _stat("wep_shotgun", "%ds" % (p["spread_ticks"] / 60 + 1), px, ry, _buff_col(p["spread_ticks"], Color(1.0, 0.8, 0.5)))
	if p["triple"]:
		px = _stat("wep_mg", "x3", px, ry, Color(1.0, 0.6, 0.9))
	if p["rend_ticks"] > 0:
		# icon_rend — Rend owns a baked icon now (was wep_rifle=Pierce's, then
		# wep_mg=Triple's; tint-only splits failed protan eyes — both loops' catch).
		px = _stat("icon_rend", "%ds" % (p["rend_ticks"] / 60 + 1), px, ry, _buff_col(p["rend_ticks"], Color(1.0, 0.55, 0.4)))
	if p["smoke_ticks"] > 0:
		px = _stat("wep_smoke", "%ds" % (p["smoke_ticks"] / 60 + 1), px, ry, _buff_col(p["smoke_ticks"], Color(0.8, 0.85, 0.9)))
	# Carried claymore charges: a count, not a countdown — and the verb
	# glyph rides along so "how do I plant this" never dead-ends here.
	if p["claymores"] > 0:
		px = _stat("wep_claymore", "x%d" % p["claymores"], px, ry, Color(0.75, 0.9, 0.6))
		Art.draw_glyph(self, "interact", Vector2(px + 4.0, ry + ICON / 2.0), 10.0,
			Color.WHITE, pi == 1)
		px += 12.0
	return px


## Exponential catch-up toward `target`, snapping once close — a big jump
## visibly rolls up over a few frames instead of teleporting to the new value.
func _rollup(disp: float, target: float, delta: float) -> float:
	var diff := target - disp
	# Threshold snap: a gap past 1000 (huge payout, restart) teleports instead
	# of a multi-second rollup that would lag the whole readout.
	if absf(diff) < 0.6 or absf(diff) > 1000.0:
		return target
	return disp + diff * (1.0 - exp(-9.7 * delta))   # ~0.15/frame at 60 Hz


## Mini sprite-framed gauge: HUD-scale twin of main._draw_bar (dark well,
## colored fill, ui_bar_frame on top) so the HOSTILES/PRESSURE minis share the
## boss/vest bars' chrome instead of floating as naked rects. Local copy —
## main's helper draws on main's canvas item; no ghost/ticks at this size.
func _mini_bar(rect: Rect2, frac: float, fill: Color) -> void:
	var inset := Vector2(rect.size.x * 0.06, rect.size.y * 0.22)
	var well := Rect2(rect.position + inset, rect.size - inset * 2.0)
	draw_rect(well, Color(0.08, 0.07, 0.06, 0.9))
	draw_rect(Rect2(well.position, Vector2(well.size.x * clampf(frac, 0.0, 1.0), well.size.y)), fill)
	draw_texture_rect(Art.tex("ui_bar_frame"), rect, false)


func _stat(icon: String, txt: String, x: float, y: float,
		col := Color(0.95, 0.96, 0.9), pulse := 0.0) -> float:
	# pulse > 0 scale-thumps the icon around its center — a payout visibly hits
	# the badge instead of only tinting the numeral.
	var r := Rect2(x, y, ICON, ICON)
	if pulse > 0.01:
		var gc := r.get_center()
		draw_set_transform(gc, 0.0, Vector2.ONE * (1.0 + pulse * 0.25))
		draw_texture_rect(Art.tex(icon), Rect2(r.position - gc, r.size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(Art.tex(icon), r, false)
	return _text(txt, x + ICON + 3.0, y + ICON - 3.0, col) + 10.0


## Segmented magazine bar: reads the clip fill at a glance (peripheral vision)
## instead of parsing a two-digit numeral. Colors escalate amber→red as it drains.
func _mag_bar(x: float, y: float, ammo: int, maxa: int) -> float:
	var segs := 8
	var frac := clampf(float(ammo) / float(maxa), 0.0, 1.0)
	var filled := int(ceil(frac * segs))
	var lit := Art.safe(Color(0.5, 0.85, 0.45))
	if frac <= 0.2:
		lit = Color(1.0, 0.25, 0.2)
	elif frac <= 0.45:
		lit = Color(1.0, 0.72, 0.32)
	for s in segs:
		draw_rect(Rect2(x + s * 3.6, y, 2.8, 5.0), lit if s < filled else Color(0.22, 0.2, 0.18))
	return x + segs * 3.6 + 4.0


## A small labeled status pip (speed-boost, wading, …) — state you feel in the
## hands, surfaced as a legible chip on the player row.
func _pip(x: float, y: float, col: Color, sym: String) -> float:
	draw_rect(Rect2(x, y + 2.0, 10.0, 9.0), Color(0.1, 0.11, 0.09, 0.85))
	draw_string(Art.font(), Vector2(x + 2.5, y + ICON - 3.0), sym,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, col)
	return x + 12.0


func _text(txt: String, x: float, y: float, col := Color(0.95, 0.96, 0.9)) -> float:
	Art.text(self, txt, Vector2(x, y), FONT_SIZE, col)
	return x + _tw(txt)


## Right-margin fit test for an optional chip of pixel-width `w` starting at `x`.
func _fits(x: float, w: float) -> bool:
	return x + w <= _fit_right


## Measured pixel width of `txt` in the HUD font (for pre-flighting chip fit).
func _tw(txt: String) -> float:
	return Art.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
