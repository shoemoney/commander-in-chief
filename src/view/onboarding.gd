class_name OnboardingTutorial
extends CanvasLayer

# onboarding-first-ten-minutes: the first-boot "firing range" beat. A brand-new
# player LEARNS the core verbs by doing them once each -- aim, throw a grenade
# at armor, roll a bullet, board a tank, go down, spend the War Chest to get
# back up -- instead of reading the HOW TO PLAY tabs cold or dying blind in
# Zone 1 to find out the hard way. Entirely view-layer: it reads real input
# through main.bind()/pad_pressed() but never calls sim.step() or touches
# SimWorld state, so it can never affect the golden checksum. main.gd gates
# the real sim + attract-mode firefight behind `_onboarding != null` so
# nothing else steps while this plays.
#
# Skippable at any moment (ESC / pad BACK -- shown as a permanent footer
# prompt) and inherently one-shot: main.gd only ever opens this once, gated
# by the dedicated user://onboarding.cfg flag (see Main.load_onboard_seen /
# save_onboard_seen) which is written to disk the instant this finishes or
# is skipped -- independent of the high-score save, so a corrupt/missing/
# wiped save (or a save-file heuristic) can never re-trigger it.

signal finished

enum Step { AIM, GRENADE, ROLL, BOARD, REVIVE, DONE }

const W := 640.0
const H := 360.0
const PLAYER_POS := Vector2(140.0, 250.0)
const RANGE_POS := Vector2(470.0, 150.0)   # AIM/GRENADE/BOARD target all sit on the same mark
const AIM_HOLD_NEEDED := 0.45      # seconds of continuous on-target aim to "hit"
const AIM_TOLERANCE_DEG := 16.0
const ROLL_PASS_TIME := 1.1        # seconds a single incoming "bullet" takes to cross
const ROLL_MAX_PASSES := 3         # forgiving cap -- auto-clears so this can never soft-lock
const BEAT_PAUSE := 0.85          # hang time after a step clears, before the next opens

var _main: Node
var _root: Control
var _step := Step.AIM
var _t := 0.0             # seconds elapsed in the current step (or its clear-flash)
var _hold_t := 0.0         # AIM: continuous on-target seconds this attempt
var _cleared := false      # current step's success flash is playing
var _roll_bt := 0.0        # ROLL: seconds into the current bullet pass
var _roll_pass := 0
var _done := false         # guards against double-emitting `finished`
var _prev_pressed := {}    # edge-detect: action name -> was-down last frame


func _init(main: Node) -> void:
	_main = main
	layer = 102   # above the boot splash (101, main._setup_splash) so it can follow it directly


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw)
	add_child(_root)
	set_process(true)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_root.queue_redraw()
	if _skip_pressed():
		_finish(true)
		return
	if _cleared:
		if _t >= BEAT_PAUSE:
			_advance()
		return
	match _step:
		Step.AIM: _tick_aim(delta)
		Step.GRENADE: _tick_grenade()
		Step.ROLL: _tick_roll(delta)
		Step.BOARD: _tick_board()
		Step.REVIVE: _tick_revive()
		Step.DONE:
			# Player-paced exit: the FIRE bind ("shoot" -- the one verb every other
			# beat already taught) sends them off, instead of a timed auto-advance
			# nobody controls. ESC/pad BACK (checked above, every frame) still skips
			# straight out if they'd rather not linger on the card.
			if _t >= BEAT_PAUSE and _edge("fire"):
				_finish(false)


func _pressed_now(action: String) -> bool:
	var p: bool = Input.is_physical_key_pressed(_main.bind(action)) or _main.pad_pressed(0, action)
	if action == "grenade":
		p = p or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)   # matches _gather_inputs' RMB fallback
	elif action == "fire":
		p = p or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)    # matches _gather_inputs' LMB fallback
	return p


func _edge(action: String) -> bool:
	var now := _pressed_now(action)
	var was: bool = _prev_pressed.get(action, false)
	_prev_pressed[action] = now
	return now and not was


func _skip_pressed() -> bool:
	# menu_bind("menu_cancel") is the game's own rebindable ESC/back action (defaults to
	# KEY_ESCAPE, immutable per Main.immutable_menu_role) -- reading it live, not a
	# hardcoded KEY_ESCAPE, keeps this in step with any future rebind. Pad BACK/Select
	# (not B -- B is the default ROLL button this very range teaches, so it must stay free).
	return Input.is_physical_key_pressed(_main.menu_bind("menu_cancel")) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK)


func _aim_dir() -> Vector2:
	# Mirrors main._gather_inputs' P1 aim priority (arrow/pad-stick keys > mouse fallback),
	# scoped down to a read-only direction for the range target -- no SimInput is built.
	var ax := (1.0 if Input.is_physical_key_pressed(_main.bind("aim_right")) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(_main.bind("aim_left")) else 0.0)
	var ay := (1.0 if Input.is_physical_key_pressed(_main.bind("aim_down")) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(_main.bind("aim_up")) else 0.0)
	var pad_aim := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if ax == 0.0 and ay == 0.0 and _root != null:
		var to_mouse: Vector2 = _root.get_local_mouse_position() - PLAYER_POS
		if to_mouse.length() > 4.0:
			var md := to_mouse.normalized()
			ax = md.x
			ay = md.y
	if pad_aim.length() > 0.25:
		ax = pad_aim.x
		ay = pad_aim.y
	if ax == 0.0 and ay == 0.0:
		return Vector2.ZERO
	return Vector2(ax, ay).normalized()


## Pure + static so it's headless-testable: is `aim_dir` pointed within
## `tolerance_deg` of the direction to the target? Vector2.ZERO (no input yet,
## or a degenerate target) never counts as a hit.
static func aim_hits_target(aim_dir: Vector2, to_target: Vector2, tolerance_deg: float) -> bool:
	if aim_dir == Vector2.ZERO or to_target == Vector2.ZERO:
		return false
	var ang := rad_to_deg(aim_dir.angle_to(to_target.normalized()))
	return absf(ang) <= tolerance_deg


func _tick_aim(delta: float) -> void:
	# AIM teaches FIRE too (the one basic verb none of the other beats cover, and the
	# one DONE's "FIRE: DEPLOY" prompt presumes): hold on-target, then actually pull
	# the trigger, same as combat. Pure hold time alone taught aim without ever asking
	# for a shot.
	if aim_hits_target(_aim_dir(), RANGE_POS - PLAYER_POS, AIM_TOLERANCE_DEG):
		_hold_t += delta
		if _hold_t >= AIM_HOLD_NEEDED and _pressed_now("fire"):
			_clear_step()
	else:
		_hold_t = 0.0


func _tick_grenade() -> void:
	if _edge("grenade"):
		_clear_step()


func _tick_roll(delta: float) -> void:
	_roll_bt += delta
	if _edge("roll"):
		_clear_step()
		return
	if _roll_bt >= ROLL_PASS_TIME:
		_roll_bt = 0.0
		_roll_pass += 1
		if _roll_pass >= ROLL_MAX_PASSES:
			_clear_step()   # forgiving cap: never softlocks a player who can't find ROLL


func _tick_board() -> void:
	if _edge("interact"):
		_clear_step()


func _tick_revive() -> void:
	if _edge("revive"):
		_clear_step()


const _CLEAR_SOUND := {
	Step.AIM: "tink", Step.GRENADE: "explosion", Step.ROLL: "whiz",
	Step.BOARD: "tank_board", Step.REVIVE: "revive",
}


func _clear_step() -> void:
	_cleared = true
	_t = 0.0
	# Tactile per-verb feedback -- the same cues combat itself plays (tink/target ding,
	# explosion, bullet whiz, tank clunk, revive jingle), so the range teaches the SOUND
	# of each verb landing too, not just the button.
	_main._sfx.play(_CLEAR_SOUND.get(_step, ""), -8.0)


func _advance() -> void:
	_cleared = false
	_t = 0.0
	_hold_t = 0.0
	_roll_bt = 0.0
	_roll_pass = 0
	match _step:
		Step.AIM: _step = Step.GRENADE
		Step.GRENADE: _step = Step.ROLL
		Step.ROLL: _step = Step.BOARD
		Step.BOARD: _step = Step.REVIVE
		Step.REVIVE: _step = Step.DONE
		Step.DONE: pass


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	# onboarding-first-ten-minutes: cheap skip/complete analytics -- lets a later
	# pass measure how many first boots skip vs. finish the range, and where.
	print("[onboarding] boot tutorial %s at step %d" % ["skipped" if skipped else "completed", _step])
	finished.emit()
	queue_free()


func _step_title() -> String:
	match _step:
		Step.AIM: return "AIM AT THE TARGET, THEN FIRE"
		Step.GRENADE: return "RIFLE ROUNDS DON'T SCRATCH ARMOR -- THROW A GRENADE"
		Step.ROLL: return "INCOMING FIRE -- ROLL THROUGH IT"
		Step.BOARD: return "WALK UP AND BOARD THE TANK"
		Step.REVIVE: return "ONE HIT DROPS YOU -- SPEND THE WAR CHEST TO GET BACK UP"
		Step.DONE: return "READY FOR DEPLOYMENT"
	return ""


func _clear_text() -> String:
	match _step:
		Step.AIM: return "TARGET HIT"
		Step.GRENADE: return "ARMOR CRACKED"
		Step.ROLL: return "DODGED"
		Step.BOARD: return "BOARDED"
		Step.REVIVE: return "BACK IN THE FIGHT"
	return ""


func _draw() -> void:
	_root.draw_rect(Rect2(0.0, 0.0, W, H), Color(0.05, 0.08, 0.06, 0.94))
	_root.draw_rect(Rect2(0.0, 300.0, W, 60.0), Color(0.22, 0.2, 0.14, 0.94))   # range floor
	Art.text_center(_root, "FIRING RANGE", W / 2.0, 26.0, 18, Color(0.95, 0.85, 0.35))
	if _step != Step.DONE:
		Art.text_center(_root, _step_title(), W / 2.0, 50.0, 11, Color(0.85, 0.9, 0.95), W - 60.0)
	_draw_player()
	if not _cleared:
		match _step:
			Step.AIM: _draw_aim()
			Step.GRENADE: _draw_grenade()
			Step.ROLL: _draw_roll()
			Step.BOARD: _draw_board()
			Step.REVIVE: _draw_revive()
	if _step == Step.DONE:
		Art.text_center(_root, "READY FOR DEPLOYMENT", W / 2.0, H / 2.0, 20, Color(0.4, 1.0, 0.5))
		if _t >= BEAT_PAUSE:
			# "fire" already has a device-aware icon via Art.glyph_key/_HINT_PAD+_HINT_KB
			# (used by the game's own fire-prompt hints) -- no draw_glyph() needed here.
			_root.draw_texture_rect(Art.tex(Art.glyph_key("fire")), Rect2(W / 2.0 - 58.0, H / 2.0 + 24.0, 14.0, 14.0), false)
			Art.text_center(_root, "FIRE: DEPLOY", W / 2.0 + 8.0, H / 2.0 + 34.0, 10, Color(0.85, 0.95, 0.85))
	elif _cleared:
		_draw_clear_flash()
		Art.text_center(_root, _clear_text(), W / 2.0, 200.0, 16, Color(0.5, 1.0, 0.55))
	_draw_progress_dots()
	Art.text_center(_root, "ESC / BACK: SKIP TUTORIAL", W / 2.0, H - 12.0, 9, Color(0.6, 0.65, 0.6, 0.85))


func _draw_progress_dots() -> void:
	# A quiet "how much range is left" strip -- 5 beats, filled as each clears --
	# so the tutorial reads as a short guided sequence, not an open-ended slideshow.
	var n := 5
	var x0 := W / 2.0 - (n - 1) * 9.0
	for i in n:
		var lit := i < _step or (i == _step and _cleared) or _step == Step.DONE
		_root.draw_circle(Vector2(x0 + i * 18.0, 66.0), 3.0, Color(0.5, 1.0, 0.55) if lit else Color(0.4, 0.42, 0.38, 0.7))


func _draw_clear_flash() -> void:
	# The same pop every real hit gets -- an expanding, fading ring on whatever
	# just landed (the target/dummy/tank for most beats, the player for REVIVE).
	var frac := clampf(_t / BEAT_PAUSE, 0.0, 1.0)
	var center := PLAYER_POS if _step == Step.REVIVE else RANGE_POS
	_root.draw_arc(center, 10.0 + frac * 30.0, 0.0, TAU, 24, Color(0.5, 1.0, 0.55, 1.0 - frac), 2.0)


func _draw_player() -> void:
	if _step == Step.REVIVE and not _cleared:
		_draw_player_down()
		return
	_root.draw_texture_rect(Art.tex("player1"), Rect2(PLAYER_POS - Vector2(10.0, 14.0), Vector2(20.0, 28.0)), false)


func _draw_player_down() -> void:
	# Knocked-down beat: the same soldier sprite, laid on its side and red-tinted --
	# sells "one hit drops you" as something that just happened to THIS body, not a
	# caption. _draw_clear_flash + the normal upright draw take over once REVIVE clears.
	var tex := Art.tex("player1")
	var xf := Transform2D(PI / 2.0, PLAYER_POS + Vector2(4.0, 6.0))
	_root.draw_set_transform_matrix(xf)
	_root.draw_texture_rect(tex, Rect2(Vector2(-10.0, -14.0), Vector2(20.0, 28.0)), false, Color(1.3, 0.55, 0.5))
	_root.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_aim() -> void:
	_root.draw_texture_rect(Art.tex("elite"), Rect2(RANGE_POS - Vector2(11.0, 15.0), Vector2(22.0, 30.0)), false)
	var dir := _aim_dir()
	if dir != Vector2.ZERO:
		_root.draw_line(PLAYER_POS, PLAYER_POS + dir * 200.0, Color(1.0, 1.0, 1.0, 0.5), 1.5)
	# "aim" is an existing hint key -- Art._HINT_PAD/_HINT_KB (art.gd) already map it to
	# glyph_stick_r / glyph_key_wide; glyph_key()/tex() is the same lookup the game's own
	# move/aim hints already use, unmodified by this attempt.
	_root.draw_texture_rect(Art.tex(Art.glyph_key("aim")), Rect2(PLAYER_POS.x - 7.0, PLAYER_POS.y - 30.0, 14.0, 14.0), false)
	var frac := clampf(_hold_t / AIM_HOLD_NEEDED, 0.0, 1.0)
	_root.draw_rect(Rect2(RANGE_POS.x - 16.0, RANGE_POS.y - 26.0, 32.0, 4.0), Color(0.15, 0.15, 0.15, 0.8))
	if frac > 0.0:
		_root.draw_rect(Rect2(RANGE_POS.x - 16.0, RANGE_POS.y - 26.0, 32.0 * frac, 4.0), Color(0.4, 0.95, 0.5))
	if frac >= 1.0:
		_root.draw_texture_rect(Art.tex(Art.glyph_key("fire")), Rect2(RANGE_POS.x - 7.0, RANGE_POS.y - 44.0, 14.0, 14.0), false)
		Art.text_center(_root, "FIRE!", RANGE_POS.x, RANGE_POS.y - 48.0, 10, Color(1.0, 0.85, 0.3))


func _draw_grenade() -> void:
	_root.draw_texture_rect(Art.tex("elite"), Rect2(RANGE_POS - Vector2(11.0, 15.0), Vector2(22.0, 30.0)), false, Color(0.7, 0.75, 0.85))
	Art.text_center(_root, "ARMORED", RANGE_POS.x, RANGE_POS.y - 30.0, 9, Color(0.9, 0.7, 0.3))
	Art.draw_glyph(_root, "grenade", RANGE_POS + Vector2(0.0, 26.0), 14.0, Color.WHITE, false, _main.bind("grenade"))


func _draw_roll() -> void:
	var frac := clampf(_roll_bt / ROLL_PASS_TIME, 0.0, 1.0)
	var bullet_x := lerpf(W - 20.0, PLAYER_POS.x + 14.0, frac)
	_root.draw_rect(Rect2(bullet_x - 4.0, PLAYER_POS.y - 2.0, 8.0, 4.0), Color(1.0, 0.85, 0.3))
	Art.draw_glyph(_root, "roll", PLAYER_POS + Vector2(0.0, -22.0), 14.0, Color.WHITE, false, _main.bind("roll"))


func _draw_board() -> void:
	_root.draw_texture_rect(Art.tex("tank_body"), Rect2(RANGE_POS - Vector2(18.0, 12.0), Vector2(36.0, 24.0)), false)
	Art.draw_glyph(_root, "interact", RANGE_POS + Vector2(0.0, -30.0), 14.0, Color.WHITE, false, _main.bind("interact"))


func _draw_revive() -> void:
	Art.text_center(_root, "YOU WENT DOWN", PLAYER_POS.x, PLAYER_POS.y - 34.0, 12, Color(0.95, 0.35, 0.3))
	Art.draw_glyph(_root, "revive", PLAYER_POS + Vector2(0.0, -14.0), 14.0, Color.WHITE, false, _main.bind("revive"))
