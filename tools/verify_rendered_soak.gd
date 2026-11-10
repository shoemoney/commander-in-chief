extends SceneTree

const Quiesce := preload("res://tools/quiesce.gd")

var main: Node2D
var spec: Dictionary = {}
var output_path := ""
var began_us := 0
var began_unix := 0.0
var previous_frame_us := 0
var sampled_us := 0
var frame_count := 0
var max_frame_interval_us := 0
var interval_bins: Array[int] = []
var samples: Array[Dictionary] = []
var completed: Array[Dictionary] = []
var failures: Array[String] = []
var case_index := 0
var finishing := false
var live_state: Dictionary = {}
var active_render_us := 0
var health_us := 0
var sampled_progress := 0
var sampled_drawn_frames := 0
var period_draw_checks := 0
var period_audio_signal_checks := 0
var period_audio_progress_checks := 0
var last_music_position := -1.0
var fault_injected := false
var audio_state: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var spec_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spec="):
			spec_path = arg.trim_prefix("--spec=")
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
	var file := FileAccess.open(spec_path, FileAccess.READ)
	if file == null or output_path.is_empty():
		print("RENDERED SOAK FAIL: missing specification or output path")
		quit(2)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("cases") or parsed["cases"].is_empty():
		print("RENDERED SOAK FAIL: invalid case specification")
		quit(2)
		return
	spec = parsed
	if DisplayServer.get_name() == "headless" or Engine.has_singleton("Steam"):
		print("RENDERED SOAK FAIL: real offline display renderer required")
		quit(2)
		return
	var private_root := String(spec["profile"]).simplify_path()
	if not ProjectSettings.globalize_path("user://").simplify_path().begins_with(private_root + "/"):
		print("RENDERED SOAK FAIL: profile escaped isolated directory")
		quit(2)
		return
	interval_bins.resize(201)
	interval_bins.fill(0)
	Engine.max_fps = 60
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	main.no_autopause = true
	main.god_mode = false
	main.set_physics_process(false)
	root.add_child(main)
	main.set_physics_process(false)
	await process_frame
	await process_frame
	main._end_splash()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	began_us = Time.get_ticks_usec()
	began_unix = Time.get_unix_time_from_system()
	sampled_us = began_us
	previous_frame_us = began_us
	_start_case()
	if finishing:
		return
	physics_frame.connect(_on_physics)
	process_frame.connect(_on_frame)
	main.set_physics_process(true)
	print("RENDERED SOAK START duration_seconds=%s profile=%s" % [spec["duration_seconds"], private_root])
	_write_report("RUNNING")


func _start_case() -> void:
	var current: Dictionary = spec["cases"][case_index]
	var replay := Replay.load_from(String(current["replay"]))
	if replay == null or replay.frames.size() != int(current["frames"]) or FileAccess.get_sha256(String(current["replay"])) != String(current["replay_sha256"]):
		_fail("fixture_replay_missing_or_frame_count_mismatch")
		return
	var config: Dictionary = current["config"]
	var envelope := replay.to_dict()
	for key in config:
		if envelope.get(key) != config[key]:
			_fail("fixture_replay_configuration_mismatch")
			return
	if replay.save("user://last_run.replay") != OK:
		_fail("fixture_could_not_be_saved_into_private_profile")
		return
	main.start_watch()
	if not main._watching or main._watch_frame != 0 or main.sim.god_mode:
		_fail("production_watch_did_not_start_cleanly")
	elif str(main.sim.checksum()) != String(current["starting_checksum"]) or main.sim.mode != String(config["mode"]) or main.sim.players.size() != int(config["players"]):
		_fail("production_watch_start_configuration_mismatch")


func _on_physics() -> void:
	if finishing:
		return
	var current: Dictionary = spec["cases"][case_index]
	if main._watch_frame >= int(current["frames"]) or main.sim.victory or main.sim.wiped:
		var actual := {"case": current["name"], "mode": current["config"]["mode"], "players": current["config"]["players"], "tick": main.sim.tick_count,
			"frames": main._watch_frame, "score": main.sim.score, "checksum": str(main.sim.checksum()),
			"victory": main.sim.victory, "wave": main.sim.wave,
			"elapsed_seconds": float(Time.get_ticks_usec() - began_us) / 1000000.0}
		for key in ["tick", "frames", "score", "checksum", "victory"]:
			if actual[key] != current[key]:
				_fail("terminal_%s_mismatch" % key)
		if finishing:
			live_state = actual
			return
		completed.append(actual)
		print("RENDERED SOAK REPLAY PASS case=%s tick=%s score=%s cycle=%s" % [current["name"], actual["tick"], actual["score"], completed.size()])
		case_index = (case_index + 1) % spec["cases"].size()
		_start_case()
	elif not main._watching or main._menu.is_active() or main.sim.god_mode:
		_fail("production_replay_stalled_or_left_watch")
	if not finishing and active_render_us >= int(float(spec["duration_seconds"]) * 1000000.0):
		_finish.call_deferred()
		finishing = true


func _on_frame() -> void:
	if finishing:
		return
	var now := Time.get_ticks_usec()
	if previous_frame_us > 0:
		var frame_interval_us := now - previous_frame_us
		if frame_interval_us > 2000000:
			_fail("frame_activity_gap_exceeded")
			return
		active_render_us += mini(frame_interval_us, 250000)
		max_frame_interval_us = maxi(max_frame_interval_us, frame_interval_us)
		var bucket := clampi(int(frame_interval_us / 1000), 0, 200)
		interval_bins[bucket] += 1
	previous_frame_us = now
	frame_count += 1
	var elapsed := float(now - began_us) / 1000000.0
	if not fault_injected and elapsed >= 3.0:
		if spec.get("pilot_fault", "") == "disabled-physics":
			main.set_physics_process(false)
			fault_injected = true
		elif spec.get("pilot_fault", "") == "disabled-render":
			RenderingServer.render_loop_enabled = false
			fault_injected = true
		elif spec.get("pilot_fault", "") == "quiet-sfx":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -80.0)
			fault_injected = true
		elif spec.get("pilot_fault", "") == "muted-audio":
			AudioServer.set_bus_mute(0, true)
			fault_injected = true
	if now - health_us >= 250000:
		health_us = now
		_observe_activity(elapsed)
		if finishing:
			return
	if now - sampled_us < 5000000:
		return
	var progress: int = main._watch_frame
	for run in completed:
		progress += int(run["frames"])
	if progress <= sampled_progress:
		_fail("production_replay_progress_stalled")
		return
	if period_draw_checks == 0 or period_audio_signal_checks == 0 or period_audio_progress_checks == 0:
		_fail("distributed_render_or_audio_activity_missing")
		return
	var drawn := Engine.get_frames_drawn()
	if drawn <= sampled_drawn_frames:
		_fail("distributed_render_frames_stalled")
		return
	sampled_drawn_frames = drawn
	sampled_progress = progress
	sampled_us = now
	live_state = {"case": spec["cases"][case_index]["name"], "tick": main.sim.tick_count,
		"watch_frame": main._watch_frame, "score": main.sim.score, "wave": main.sim.wave}
	var view_rid := root.get_viewport_rid()
	samples.append({"elapsed_seconds": float(now - began_us) / 1000000.0,
		"completed_replays": completed.size(), "rendered_process_frames": frame_count,
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"fps_monitor": Performance.get_monitor(Performance.TIME_FPS),
		"cpu_render_ms": RenderingServer.viewport_get_measured_render_time_cpu(view_rid),
		"gpu_render_ms": RenderingServer.viewport_get_measured_render_time_gpu(view_rid),
		"active_render_seconds": float(active_render_us) / 1000000.0,
		"total_replay_frames": progress, "actual_engine_frames_drawn": drawn, "period_draw_checks": period_draw_checks,
		"period_audio_signal_checks": period_audio_signal_checks,
		"period_audio_progress_checks": period_audio_progress_checks,
		"audio": audio_state.duplicate(), "live": live_state.duplicate()})
	if samples.size() == 2:
		var pixels := root.get_texture().get_image()
		if pixels.get_size() != Vector2i(640, 360) or pixels.save_png(output_path.get_base_dir().path_join("render-liveness.png")) != OK:
			_fail("render_liveness_pixels_missing_or_wrong_dimensions")
			return
	period_draw_checks = 0
	period_audio_signal_checks = 0
	period_audio_progress_checks = 0
	_write_report("RUNNING")


func _observe_activity(elapsed: float) -> void:
	if not RenderingServer.render_loop_enabled:
		_fail("render_loop_disabled")
		return
	if main._watch_replay != null and main._watch_replay.slow_at(main._watch_frame):
		_fail("production_watch_rate_mismatch")
		return
	if not main.is_physics_processing() or not main.can_process() or paused:
		_fail("production_physics_disabled")
		return
	if Engine.time_scale != 1.0 or Engine.physics_ticks_per_second != 60 or AudioServer.playback_speed_scale != 1.0 or root.size != Vector2i(1280, 720):
		_fail("actual_clock_or_window_configuration_mismatch")
		return
	if int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) > 0:
		period_draw_checks += 1
	if elapsed < 1.0:
		return
	var master := AudioServer.get_bus_index("Master")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if master < 0 or music < 0 or sfx < 0 or AudioServer.get_driver_name().to_lower() == "dummy" or AudioServer.is_bus_mute(master) or AudioServer.is_bus_mute(music) or AudioServer.is_bus_mute(sfx) or AudioServer.get_bus_volume_db(master) <= -60.0 or AudioServer.get_bus_volume_db(music) <= -60.0 or AudioServer.get_bus_volume_db(sfx) <= -60.0 or not main._sfx.can_process() or main._sfx._shutting_down:
		_fail("audio_path_muted_or_disabled")
		return
	var player: AudioStreamPlayer = main._sfx._music
	var position := player.get_playback_position()
	var peak := maxf(AudioServer.get_bus_peak_volume_left_db(master, 0), AudioServer.get_bus_peak_volume_right_db(master, 0))
	var playing := player.playing and not player.stream_paused and player.has_stream_playback()
	if playing and last_music_position >= 0.0 and absf(position - last_music_position) > 0.001:
		period_audio_progress_checks += 1
	if playing and peak > -80.0:
		period_audio_signal_checks += 1
	last_music_position = position
	audio_state = {"driver": AudioServer.get_driver_name(), "mix_rate": AudioServer.get_mix_rate(),
		"master_peak_db": peak, "music_playing": playing, "music_position_seconds": position,
		"seconds_since_last_mix": AudioServer.get_time_since_last_mix()}


func _fail(reason: String) -> void:
	if reason not in failures:
		failures.append(reason)
		print("RENDERED SOAK CHECK FAIL: ", reason)
	if not finishing:
		if main != null:
			live_state = {"case": spec["cases"][case_index]["name"], "tick": main.sim.tick_count, "frames": main._watch_frame, "watch_frame": main._watch_frame, "score": main.sim.score}
		finishing = true
		_finish.call_deferred()


func _finish() -> void:
	finishing = true
	if physics_frame.is_connected(_on_physics):
		physics_frame.disconnect(_on_physics)
	if process_frame.is_connected(_on_frame):
		process_frame.disconnect(_on_frame)
	var elapsed := float(Time.get_ticks_usec() - began_us) / 1000000.0
	if elapsed < float(spec["duration_seconds"]) and failures.is_empty():
		failures.append("wall_clock_duration_not_reached")
	if completed.size() < int(spec["minimum_completed_replays"]) and failures.is_empty():
		failures.append("required_full_replays_not_completed")
	if float(active_render_us) / 1000000.0 < float(spec["duration_seconds"]) and failures.is_empty():
		failures.append("active_render_duration_not_reached")
	var campaign_count := completed.filter(func(run: Dictionary) -> bool: return run["mode"] == "campaign").size()
	if campaign_count < int(spec["minimum_completed_campaigns"]) and failures.is_empty():
		failures.append("required_three_full_campaigns_not_completed")
	if samples.size() < 2 and failures.is_empty():
		failures.append("distributed_activity_samples_missing")
	await Quiesce.teardown(self, main)
	main = null
	_write_report("VERIFIED" if failures.is_empty() else "NOT VERIFIED")
	print("RENDERED SOAK %s elapsed_seconds=%.3f completed_replays=%d frames=%d" % ["PASS" if failures.is_empty() else "FAIL", elapsed, completed.size(), frame_count])
	quit(0 if failures.is_empty() else 1)


func _write_report(verdict: String) -> void:
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail("report_write_failed")
		return
	file.store_string(JSON.stringify({"schema": 1, "verdict": verdict,
		"render_origin_unix_seconds": began_unix,
		"duration_seconds_requested": spec.get("duration_seconds", 0),
		"active_render_seconds": float(active_render_us) / 1000000.0,
		"elapsed_seconds": float(Time.get_ticks_usec() - began_us) / 1000000.0,
		"display_server": DisplayServer.get_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"engine_version": Engine.get_version_info(), "production_automatic_physics": true,
		"replay_route": "main.start_watch + observed automatic production physics/render/audio",
		"pilot_fault_injected": fault_injected, "audio_driver": AudioServer.get_driver_name(),
		"activity_gate": {"maximum_frame_gap_seconds": 2.0, "credited_frame_interval_cap_seconds": 0.25, "sample_period_seconds": 5.0, "continuous_physics_enabled_checked": true},
		"god_mode": false, "gameplay_mutations": [], "process_frames": frame_count,
		"maximum_process_frame_interval_us": max_frame_interval_us,
		"frame_interval_bins_ms": interval_bins, "completed_replays": completed,
		"samples": samples, "live": live_state, "failures": failures,
		"limitations": ["Source-project standard Godot renderer; native release, foreign hardware and live Steam are separate.",
			"Recorded normal input playback tests rendering, audio and reset lifetime; it is not human/controller-feel evidence.",
			"Audio observations establish production player/mixer activity, not human listening or physical speaker output.",
			"Zero GPU timing or VRAM counters mean unmeasured; frame pacing is reported for this shared local machine only."]}, "\t"))
