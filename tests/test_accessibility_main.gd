extends RefCounted

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")
const Robust := preload("res://tests/test_robustness.gd")
const Menu := preload("res://src/view/menu.gd")


class QuietSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


class RawMain extends Main:
	var raw: Array[Dictionary] = [{}, {}]
	func _raw_accessibility_actions(seat: int) -> Dictionary:
		var result := {}
		for action in ["grenade", "roll", "interact", "revive", "buy"]:
			result[action] = bool(raw[seat].get(action, false))
		return result


# Exercise the production tick scheduler and recorder. Only presentation and
# physical sampling are quieted; the actual SimWorld and Replay advance normally.
class ClockMain extends RawMain:
	var sample := SimInput.new()
	var feel_calls := 0
	var hud_calls := 0
	var sample_calls := 0
	func _gather_inputs() -> Array[SimInput]:
		sample_calls += 1
		return [SimInput.decode(sample.encode())]
	func _update_cursor() -> void: pass
	func _consume_events() -> void: pass
	func _check_boss_intro() -> void: pass
	func _check_trench_edges() -> void: pass
	func _check_smoke_edges() -> void: pass
	func _check_dry_throw(_inputs: Array[SimInput]) -> void: pass
	func _check_dry_roll(_inputs: Array[SimInput]) -> void: pass
	func _track_bests() -> void: pass
	func _tick_spawn_yells() -> void: pass
	func _update_feel() -> void: feel_calls += 1
	func _update_hud() -> void: hud_calls += 1


func _prepare(main, players := 1) -> void:
	main._sfx.free()
	main._sfx = QuietSfx.new()
	main.sim = SimWorld.new(7, players, "campaign")
	main._two_players = players == 2
	main._splash_t = 0.0
	main._menu.mode = Menu.Mode.HIDDEN
	main._binds = Main.BIND_DEFAULTS.duplicate()
	main._pad_binds[0] = Main.PAD_DEFAULTS.duplicate()
	main._pad_binds[1] = Main.PAD_DEFAULTS.duplicate()
	main._recorder = Replay.new()
	main._recorder.seed_value = 7
	main._recorder.mode = "campaign"
	main._recorder.player_count = players


func test_default_production_scheduler_keeps_every_input_and_checksum() -> void:
	var main := ClockMain.new()
	_prepare(main)
	var reference := SimWorld.new(7, 1, "campaign")
	for frame in 120:
		main.sample.move_x = 64 if frame < 60 else -64
		main.sample.aim_y = -256
		main.sample.fire = true
		main._physics_process(1.0 / 60.0)
		reference.step([SimInput.decode(main.sample.encode())])
		Runner.T.eq(main.sim.checksum(), reference.checksum(), "default production callback keeps tick %d exact" % frame)
	Runner.T.eq(main.sim.tick_count, 120, "default callbacks keep the original 60Hz tick rate")
	Runner.T.eq(main._recorder.frames.size(), 120, "default recorder stores every input")
	Runner.T.eq(main.sample_calls, 120, "default sampling happens exactly once per tick")
	Runner.T.eq(main._recorder.play(120)[0], main.sim.checksum(), "production recording reproduces the full final state")
	main.free()


func test_production_slow_mode_keeps_view_updates_and_records_resolved_ticks() -> void:
	var main := ClockMain.new()
	_prepare(main)
	main.set_accessibility_setting("slow_mode", true)
	main.sample.aim_y = -256
	main.sample.move_y = -256
	main.sample.fire = true
	for _frame in 600:
		main._physics_process(1.0 / 60.0)
	Runner.T.eq(main.sim.tick_count, 450, "600 eligible callbacks advance exactly 450 sim ticks")
	Runner.T.eq(main._recorder.frames.size(), 450, "no empty pacing frame enters the replay")
	Runner.T.eq(main.feel_calls, 600, "view envelopes keep updating on skipped ticks")
	Runner.T.eq(main.hud_calls, 600, "HUD keeps updating on skipped ticks")
	Runner.T.eq(main.sample_calls, 600, "physical input is sampled on skipped callbacks too")
	Runner.T.ok(main._recorder.slow_at(0), "the recorded run starts at its selected pacing")
	Runner.T.ok("slow_mode" in main._recorder.assist_tags, "slower runs retain their assistance label")
	Runner.T.eq(main._recorder.play(450)[0], main.sim.checksum(), "slow live state reproduces at fixed simulation ticks")
	main.free()


func test_watch_uses_recorded_pacing_changes_without_live_setting_leak() -> void:
	var main := ClockMain.new()
	_prepare(main)
	var replay := Replay.new()
	replay.seed_value = 7
	replay.record_accessibility({"slow_mode": true}, ["slow_mode"])
	for _frame in 12:
		replay.record_tick([SimInput.new()])
	replay.record_accessibility({"slow_mode": false}, [])
	for _frame in 80:
		replay.record_tick([SimInput.new()])
	main._watching = true
	main._watch_replay = replay
	main.set_accessibility_setting("slow_mode", false)
	# The 3-on/1-off cadence delivers the twelfth tick on callback15. The
	# frame12 marker then applies before callback16, with no synthetic wait.
	for _frame in 15:
		main._physics_process(1.0 / 60.0)
	Runner.T.eq(main._watch_frame, 12, "Watch follows the recorded slow interval despite live standard setting")
	main.set_accessibility_setting("slow_mode", true)
	for _frame in 8:
		main._physics_process(1.0 / 60.0)
	Runner.T.eq(main._watch_frame, 20, "Watch returns to recorded standard speed despite live slow setting")
	Runner.T.eq(main._recorder.frames.size(), 0, "Watch never records another run")
	Runner.T.eq(main.feel_calls, 23, "Watch presentation advances on every callback")
	Runner.T.eq(main.sim.checksum(), replay.play(20)[0], "Watch's production sim matches the original inputs")
	main.free()


func test_a_short_action_inside_hitstop_survives_buffered_slow_input() -> void:
	var main := ClockMain.new()
	_prepare(main)
	main.set_accessibility_setting("slow_mode", true)
	main._hitstop_frames = 2
	main.sample.grenade = true
	main._physics_process(1.0 / 60.0)
	main.sample.grenade = false
	main._physics_process(1.0 / 60.0)
	Runner.T.eq(main.sim.tick_count, 0, "hit-stop still freezes the deterministic sim")
	main._physics_process(1.0 / 60.0)
	Runner.T.eq(main._recorder.frames.size(), 1, "first eligible callback delivers a buffered action once")
	Runner.T.ok(SimInput.decode(main._recorder.frames[0][0]).grenade, "press and release wholly inside freeze reach the real recorder")
	main._physics_process(1.0 / 60.0)
	Runner.T.ok(not SimInput.decode(main._recorder.frames[1][0]).grenade, "the following recorded tick releases the buffered action")
	main.free()


func test_real_gather_keeps_toggle_state_separate_for_both_seats() -> void:
	var main := RawMain.new()
	_prepare(main, 2)
	var old_pad := Art.use_pad
	Art.use_pad = true
	main.set_accessibility_setting("toggle_grenade", true)
	main.raw[0]["grenade"] = true
	var first: Array[SimInput] = main._gather_inputs()
	Runner.T.ok(first[0].grenade and not first[1].grenade, "P1 press latches only P1")
	main.raw[0]["grenade"] = false
	main.raw[1]["grenade"] = true
	var second: Array[SimInput] = main._gather_inputs()
	Runner.T.ok(second[0].grenade and second[1].grenade, "released P1 remains toggled while P2 independently starts")
	main.raw[1]["grenade"] = false
	main.raw[0]["grenade"] = true
	var third: Array[SimInput] = main._gather_inputs()
	Runner.T.ok(not third[0].grenade and third[1].grenade, "second P1 press never unlatches P2")
	main.reset_accessibility_input()
	Runner.T.ok(not main._gather_inputs()[0].grenade, "menu/resume reset suppresses a still-held confirmation")
	main.raw[0]["grenade"] = false
	main._gather_inputs()
	main.raw[0]["grenade"] = true
	Runner.T.ok(main._gather_inputs()[0].grenade, "a genuinely new press rearms after release")
	Art.use_pad = old_pad
	main.free()


func test_p2_automatic_aim_never_selects_a_wheel_purchase() -> void:
	var main := RawMain.new()
	_prepare(main, 2)
	var old_pad := Art.use_pad
	Art.use_pad = true
	main.sim.camera_top = 0
	for player in main.sim.players:
		player["x"] = 320 * Fixed.ONE
		player["y"] = 180 * Fixed.ONE
	main.sim.enemies.clear()
	main.sim._spawn_enemy(320 * Fixed.ONE, 100 * Fixed.ONE, false)
	main.set_accessibility_setting("single_stick_p2", true)
	Runner.T.ok(main._gather_inputs()[1].aim_y < 0, "P2 can automatically acquire a real visible hostile")
	main.raw[1]["buy"] = true
	var inputs: Array[SimInput] = main._gather_inputs()
	Runner.T.eq(inputs[1].buy, SimWorld.BUY_WHEEL_OPEN, "P2 opens the real wheel")
	Runner.T.eq(main._wheel[1]["sel"], -1, "automatic target direction never selects a supply")
	Runner.T.ok(not inputs[1].fire, "opening the wheel still suppresses fire")
	main.raw[1]["buy"] = false
	Runner.T.eq(main._gather_inputs()[1].buy, 0, "releasing without an intentional choice never buys")
	Art.use_pad = old_pad
	main.free()


func test_accessibility_settings_normalize_corruption_and_preserve_defaults() -> void:
	var main := Main.new()
	var baseline := main._settings_snapshot()
	for key in Main.ACCESSIBILITY_KEYS:
		Runner.T.eq(baseline[key], Main.SETTINGS_DEFAULTS[key], "%s starts at its authoritative default" % key)
	main.set_accessibility_setting("single_stick_p1", "true")
	main.set_accessibility_setting("slow_mode", 1)
	main.set_accessibility_setting("aim_assist", INF)
	main.set_accessibility_setting("shake_level", -4)
	main.set_accessibility_setting("flash_level", 55)
	main.set_accessibility_setting("unrecognized", true)
	Runner.T.eq(main.accessibility_setting("single_stick_p1"), false, "string cannot turn on a bool setting")
	Runner.T.eq(main.accessibility_setting("slow_mode"), false, "numeric bool corruption restores default")
	Runner.T.eq(main.accessibility_setting("aim_assist"), 0, "nonfinite assist tier restores default")
	Runner.T.eq(main.accessibility_setting("shake_level"), 0, "shake level clamps to the visible rail")
	Runner.T.eq(main.accessibility_setting("flash_level"), 10, "flash level clamps to the visible rail")
	Runner.T.ok(not main._accessibility_settings.has("unrecognized"), "unsupported setting cannot enter persistence")
	main.free()


func test_actual_settings_save_load_roundtrip_keeps_all_accessibility_choices() -> void:
	var fixtures := Robust.new()
	var saved := fixtures._stash_save(".accessibility-test")
	var main := Main.new()
	var old_scale := Art.text_scale
	var old_colorblind := Art.colorblind
	for key in Main.ACCESSIBILITY_KEYS:
		main.set_accessibility_setting(key, 1 if key == "aim_assist" else (4 if key in ["shake_level", "flash_level"] else true))
	var expected := main._accessibility_snapshot()
	main._save_settings()
	var loaded := Main.new()
	loaded._load_bests()
	Runner.T.eq(loaded._accessibility_snapshot(), expected, "real atomic settings save survives a fresh main load")
	main.free()
	loaded.free()
	fixtures._restore_save(saved)
	Art.text_scale = old_scale
	Art.colorblind = old_colorblind


func test_effect_levels_are_independent_of_assist_identity_and_reduce_motion() -> void:
	var main := Main.new()
	main.sim = SimWorld.new(7, 1, "campaign")
	main.set_accessibility_setting("shake_level", 0)
	main.set_accessibility_setting("flash_level", 5)
	Runner.T.eq(main._shake_strength(), 0.0, "zero shake removes the camera channel")
	Runner.T.eq(main._flash_strength(), 0.5, "independent flash rail preserves its own value")
	Runner.T.eq(main._run_assist_tags(), [], "cosmetic reduction never marks gameplay assistance")
	main._motion = 0.0
	main.set_accessibility_setting("shake_level", 10)
	Runner.T.eq(main._shake_strength(), 0.0, "Reduce Motion overrides camera amplitude")
	Runner.T.eq(main._flash_strength(), 0.2, "Reduce Motion also composes with the flash rail")
	main.set_accessibility_setting("flash_level", 0)
	Runner.T.eq(main._flash_strength(), 0.0, "zero flash has no minimum brightness floor")
	main.free()
