extends RefCounted
## time-fx: slow-motion beats, the hit-stop budget and enemy flinch. All view-side; the sim only
## ever sees fewer-or-equal step() calls with the SAME inputs, which these tests check against a
## reference SimWorld.

const Runner := preload("res://tests/run_tests.gd")
const Acc := preload("res://tests/test_accessibility_main.gd")


func _main() -> Acc.ClockMain:
	var main := Acc.ClockMain.new()
	Acc.new()._prepare(main)
	return main


func _steps_over(main, frames: int) -> int:
	var before: int = main.sim.tick_count
	for _f in frames:
		main._physics_process(1.0 / 60.0)
	return main.sim.tick_count - before


func test_boss_beat_drops_the_designed_steps_then_returns_to_one_to_one() -> void:
	var main := _main()
	Runner.T.ok(main._time_fx.start("boss", main._motion), "a boss beat starts under normal motion")
	var steps := _steps_over(main, 60)
	# Measured with the 36-frame / 0.40-floor curve (see the eq below for the pinned number).
	Runner.T.eq(steps, 45, "60 frames after a boss death advance 45 sim steps (designed: 15 skipped)")
	Runner.T.ok(not main._time_fx.active(), "the beat has ended inside the 60 frames")
	Runner.T.eq(_steps_over(main, 60), 60, "afterwards stepping is back to exactly 1:1")
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "audio pitch is restored exactly")
	main.free()


func test_dilation_never_drops_or_duplicates_input_or_changes_the_sim() -> void:
	var main := _main()
	main.sample.move_y = -256
	main.sample.aim_y = -256
	main.sample.fire = true
	main._time_fx.start("victory", main._motion)
	_steps_over(main, 90)
	var n: int = main.sim.tick_count
	Runner.T.ok(n < 90 and n > 60, "victory beat dilates 90 frames to %d steps" % n)
	var ref := SimWorld.new(7, 1, "campaign")
	for _t in n:
		ref.step([SimInput.decode(main.sample.encode())])
	Runner.T.eq(main.sim.checksum(), ref.checksum(), "sim state equals a reference stepped the same count with the same inputs")
	Runner.T.eq(main._recorder.frames.size(), n, "the recorder holds exactly one input frame per sim step")
	main.free()


func test_reduce_motion_and_disabled_flag_lose_no_steps() -> void:
	var main := _main()
	main._motion = 0.0
	Runner.T.ok(not main._time_fx.start("boss", main._motion), "reduce-motion refuses the beat")
	Runner.T.eq(_steps_over(main, 60), 60, "reduce-motion: zero steps lost")
	main._motion = 1.0
	TimeFx.enabled = false
	Runner.T.ok(not main._time_fx.start("boss", main._motion), "a step-counting harness can switch the layer off")
	Runner.T.eq(_steps_over(main, 60), 60, "disabled: zero steps lost")
	TimeFx.enabled = true
	main.free()


func test_pitch_is_restored_after_a_mid_beat_restart_and_after_watch() -> void:
	var main := _main()
	main._time_fx.start("wipe", main._motion)
	_steps_over(main, 14)
	Runner.T.ok(AudioServer.playback_speed_scale < 0.95, "pitch is dipped mid-beat (%.3f)" % AudioServer.playback_speed_scale)
	main._reset()
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "a mid-beat restart restores pitch")
	Runner.T.ok(not main._time_fx.active(), "and ends the beat")
	main._time_fx.start("boss", main._motion)
	_steps_over(main, 10)
	main._watching = true
	main._watch_replay = Replay.new()
	main._physics_process(1.0 / 60.0)
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "entering Watch/replay cancels the beat")
	main.free()


func test_a_shorter_beat_does_not_cut_a_running_one() -> void:
	var fx := TimeFx.new()
	Runner.T.ok(fx.start("victory", 1.0), "victory starts")
	for _i in 10:
		fx.advance(false)
	Runner.T.ok(not fx.start("blast", 1.0), "a shorter blast beat cannot cut the running victory beat")
	Runner.T.ok(fx.speed() < 1.0, "still dilated")
	fx.cancel()
	Runner.T.eq(AudioServer.playback_speed_scale, 1.0, "cancel restores pitch")


func test_hitstop_holds_the_beat_clock() -> void:
	var fx := TimeFx.new()
	fx.start("boss", 1.0)
	for _i in 20:
		Runner.T.ok(not fx.advance(true), "frozen frames never skip a step on top of the freeze")
	Runner.T.ok(fx.active() and fx.speed() == 1.0, "the clock has not moved while frozen")
	fx.cancel()


func test_ten_kills_in_twelve_ticks_freeze_at_most_the_budget() -> void:
	var main := _main()
	var frozen := 0
	for i in 10:
		main.sim.tick_count = i      # one kill per tick, 10 kills inside 12 ticks
		main._hitstop_frames = 0     # consume the previous freeze
		main._ev_kill({"t": "kill", "kind": "rusher", "x": 0, "y": 0, "coin": 5, "tier": 0})
		frozen += main._hitstop_frames
	# Before: every kill armed its own frame, so this measured 10 frozen frames (a freeze on
	# 10 of 12 ticks). After: a 6-tick window allows 1 ordinary frame, so 2 across 10 ticks.
	Runner.T.ok(frozen <= 2, "10 kills in 12 ticks freeze at most 2 frames (got %d)" % frozen)
	Runner.T.ok(frozen >= 1, "but the first kill still lands with weight")
	main.free()


func test_limiter_windows_tiers_and_folding() -> void:
	var fx := TimeFx.new()
	Runner.T.eq(fx.grant_hitstop(100, 1, false), 1, "first ordinary kill freezes 1")
	Runner.T.eq(fx.grant_hitstop(101, 1, false), 0, "second kill inside the window is folded")
	Runner.T.ok(fx.punch_bonus() > 0.0, "the folded kill becomes extra punch instead")
	Runner.T.eq(fx.grant_hitstop(102, 2, true), 1, "a heavy kill tops the window up to 2")
	Runner.T.eq(fx.grant_hitstop(103, 2, true), 0, "and no more")
	Runner.T.eq(fx.grant_hitstop(106, 1, false), 1, "a new window opens after 6 ticks")
	Runner.T.eq(fx.grant_hitstop(200, 2, true), 2, "a lone heavy kill gets both frames")


func test_flinch_pushes_along_the_bullet_decays_and_respects_reduce_motion() -> void:
	var fx := TimeFx.new()
	fx.flinch_hit(3, Vector2(0, -5))
	var o := fx.flinch_offset(3, 1.0)
	Runner.T.ok(absf(o.y + TimeFx.FLINCH_PX) < 0.001 and absf(o.x) < 0.001, "offset is 2px along the incoming direction %s" % o)
	var sq := fx.flinch_scale(3, 1.0)
	Runner.T.ok(sq.x > 1.0 and sq.y == 1.0 and sq.x <= 1.0 + TimeFx.FLINCH_SQUASH + 0.0001,
		"a vertical hit widens x by at most 8%% and never scales below 1.0 (%s)" % sq)
	Runner.T.eq(fx.flinch_offset(3, 0.0), Vector2.ZERO, "reduce-motion: no offset")
	Runner.T.eq(fx.flinch_scale(3, 0.0), Vector2.ONE, "reduce-motion: no squash")
	for _i in TimeFx.FLINCH_TICKS:
		fx.flinch_tick()
	Runner.T.eq(fx.flinch_offset(3, 1.0), Vector2.ZERO, "flinch is gone after %d ticks" % TimeFx.FLINCH_TICKS)
	Runner.T.eq(fx.flinch_scale(3, 1.0), Vector2.ONE, "squash too")


func test_a_real_hp_edge_on_a_multi_hp_enemy_triggers_the_flinch_away_from_the_shooter() -> void:
	var main := _main()
	var p: Dictionary = main.sim.players[0]
	main.sim.enemies.append({"kind": "mg_nest", "x": p["x"], "y": p["y"] - 100 * Fixed.ONE,
		"alive": true, "hp": 6, "windup": 0})
	main._check_enemy_hits()                     # seed hp_prev
	Runner.T.ok(not main._time_fx.flinch_active(0), "no flinch before the hit")
	main.sim.enemies[0]["hp"] = 4
	main._check_enemy_hits()
	Runner.T.ok(main._time_fx.flinch_active(0), "the hp edge starts a flinch")
	Runner.T.ok(main._time_fx.flinch_offset(0, 1.0).y < 0.0, "the nest is pushed up-screen, away from the player below it")
	Runner.T.ok(main._hitstop_frames <= 1, "a non-lethal hit costs at most 1 frozen frame")
	main.free()
