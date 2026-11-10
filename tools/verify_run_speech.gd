extends SceneTree

const Quiesce := preload("res://tools/quiesce.gd")

var main: Node2D
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(passed: bool, description: String) -> void:
	checks += 1
	if not passed:
		failures.append(description)
		print("RUN SPEECH FAIL: ", description)


func _run() -> void:
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.no_autopause = true
	await process_frame
	await process_frame
	main._end_splash()
	var sfx = main._sfx
	sfx.unlock_startup_audio()
	var samples := PackedByteArray()
	samples.resize(44100 * 4)
	var old_line := AudioStreamWAV.new()
	old_line.format = AudioStreamWAV.FORMAT_16_BITS
	old_line.mix_rate = 44100
	old_line.data = samples
	sfx._vo_streams["probe-ending"] = old_line
	sfx._vo_streams["probe-warning"] = old_line
	sfx.play_vo("probe-ending", 3)
	check(sfx._vo.playing, "old terminal radio line actually starts")
	sfx._vo_pending = {"key": "probe-ending", "priority": 3, "dry": false,
		"until": Engine.get_physics_frames() + 120}
	sfx._cmd_next_frame = Engine.get_physics_frames() + 600
	sfx._sfx_cap_next["armor_block"] = Engine.get_physics_frames() + 600
	main._reset()
	check(not sfx._vo.playing, "reset stops previous-run terminal radio speech")
	check(sfx._vo_pending.is_empty(), "reset removes previous-run deferred speech")
	check(sfx._vo_priority == -1, "reset releases previous-run speech priority")
	check(sfx._sfx_cap_next.is_empty(), "reset clears previous-run caption cooldowns")
	sfx._cmd.stop()
	sfx.play_vo("probe-warning", 1)
	check(sfx._vo.playing and sfx._vo_priority == 1,
		"new-run warning starts after the old terminal line")
	sfx.stop_vo()
	sfx._vo_dry.stream = old_line
	sfx._vo_dry.play()
	sfx._cmd.stream = old_line
	sfx._cmd.play()
	check(sfx._vo_dry.playing and sfx._cmd.playing,
		"old dry speech and commander channel actually start")
	main._reset()
	check(not sfx._vo_dry.playing, "reset stops previous-run dry speech")
	check(not sfx._cmd.playing or sfx._cmd.stream != old_line,
		"reset stops previous-run commander speech")
	sfx._cmd.stop()
	sfx._vo_dry.stream = old_line
	sfx._vo_dry.play()
	sfx._fade_then_stop(sfx._vo_dry, true)
	main._reset()
	sfx.play_vo("probe-warning", 1, true)
	await create_timer(0.08, true, false, true).timeout
	check(sfx._vo_dry.playing and sfx._vo_priority == 1,
		"a canceled prior-run fade cannot stop new-run speech")
	check(sfx._vo_dry.volume_db == sfx.VO_DRY_VOLUME_DB,
		"reset restores dry speech volume after an interrupted fade")
	sfx.stop_vo()
	sfx.lock_startup_audio()
	sfx._vo_streams["probe-startup"] = old_line
	check(sfx.play_startup_line("probe-startup"), "startup narration control starts")
	sfx._arm_caption("STARTUP CONTROL", old_line, false, true, sfx.CaptionTier.OBJECTIVE)
	var startup_caption: String = sfx._cap_text
	sfx._cap_queue.append({"text": "OLD COMBAT", "is_vo": true})
	sfx._vo_pending = {"key": "probe-ending", "priority": 3, "dry": false,
		"until": Engine.get_physics_frames() + 120}
	main._reset()
	check(sfx._vo_dry.playing and sfx._startup_line_playing,
		"run reset preserves intentionally continuing startup narration")
	check(sfx._cap_text == startup_caption and sfx._cap_queue.is_empty(),
		"reset keeps the startup caption and clears queued combat captions")
	check(sfx._vo_pending.is_empty() and sfx.is_startup_audio_locked(),
		"reset clears old pending speech without releasing the startup lock")
	var deadline := Time.get_ticks_msec() + 4000
	while sfx._startup_line_playing and Time.get_ticks_msec() < deadline:
		await create_timer(0.01, true, false, true).timeout
	check(not sfx._startup_line_playing and not sfx.is_startup_audio_locked(),
		"preserved narration finishes naturally and releases startup audio")
	await Quiesce.teardown(self, main)
	print("RUN SPEECH %s: %d checks, %d failures" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
