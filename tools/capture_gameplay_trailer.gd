extends "res://tools/capture_store_gameplay.gd"
## Movie Maker owns the PNG sequence and synchronized WAV. This script records
## actual autoplay inputs and pixel/checksum receipts; it never stages entities.
## Use an empty SHOT_DIR and --write-movie SHOT_DIR/take.png --fixed-fps 60.

static func isolate_capture_input(viewport: Viewport) -> void:
	# Bot inputs enter the simulation directly; OS keyboard/mouse events must not
	# restart, pause, reconfigure or otherwise contaminate an unattended take.
	viewport.set_disable_input(true)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or Engine.get_write_movie_path().is_empty():
		push_error("trailer capture requires a real renderer and Movie Maker")
		quit(1)
		return
	out_dir = OS.get_environment("SHOT_DIR")
	total = _env_i("TRAILER_FRAMES", 900)
	if not DirAccess.dir_exists_absolute(out_dir) or total < 60 or total > 3600:
		push_error("trailer capture requires an existing SHOT_DIR and 60..3600 frames")
		quit(1)
		return
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true
	isolate_capture_input(root)
	_capture_started_ms = Time.get_ticks_msec()
	# An occluded macOS window may stop automatic draws while Movie Maker still
	# writes the previous framebuffer. Own exactly one draw per process iteration.
	RenderingServer.render_loop_enabled = false
	_run()

func _process(_delta: float) -> bool:
	# Automatic drawing is disabled above, so this is the sole draw, not an extra.
	if not _finishing:
		_force_capture_draw.call_deferred()
	if not _finishing and Time.get_ticks_msec() - _capture_started_ms > 180000:
		push_error("trailer capture exceeded its wall-clock deadline")
		_finish(1)
	return false

func _run() -> void:
	await RenderingServer.frame_post_draw
	_kill_splash()
	_hash_tree("res://src")
	_hash_tree("res://assets")
	for path in ["res://project.godot", "res://tools/capture_gameplay_trailer.gd",
			"res://tools/capture_store_gameplay.gd", "res://tools/gif_capture.gd", "res://tools/quiesce.gd"]:
		_sources[path] = FileAccess.get_sha256(path)
	main._seed_override = _env_i("CAPTURE_SEED", 3)
	var chapter := _env_i("GIF_CHAPTER", 0)
	if chapter > 0:
		main.start_arcade(chapter)
	else:
		main.start_game(OS.get_environment("GIF_MODE") == "endless")
	main.demo_autoplay = true
	var captured_sim: SimWorld = main.sim
	for index in total:
		await process_frame
		await RenderingServer.frame_post_draw
		_kill_splash()
		if main.sim != captured_sim:
			push_error("trailer capture changed simulation mid-take")
			await _finish(1)
			return
		var raw := root.get_texture().get_image()
		if raw == null or raw.get_size() != Vector2i(640, 360) or main.sim.god_mode:
			push_error("trailer capture requires the unchanged 640x360 viewport and no god mode")
			await _finish(1)
			return
		raw.convert(Image.FORMAT_RGBA8)
		var pixel_hash := HashingContext.new()
		pixel_hash.start(HashingContext.HASH_SHA256)
		pixel_hash.update(raw.get_data())
		var movie_frame := Engine.get_process_frames()
		if not _records.is_empty() and movie_frame != int(_records[-1]["engine_frame"]) + 1:
			push_error("trailer capture skipped or duplicated a movie frame")
			await _finish(1)
			return
		# PNGWAV increments its file index once per main-loop iteration, not per
		# automatic draw. Before the current iteration is written, process_frames
		# is exactly its zero-based file index; frames_drawn stays zero in this mode.
		_records.append({"engine_frame": movie_frame,
			"pixel_sha256": pixel_hash.finish().hex_encode(),
			"replay_frame": main._recorder.frames.size(), "sim_checksum": main.sim.checksum(),
			"tick": main.sim.tick_count, "score": main.sim.score,
			"alive": main.sim.players[0]["alive"], "in_tank": main.sim.players[0]["in_tank"],
			"wiped": main.sim.wiped, "debrief": main._debrief,
			"menu_visible": main._menu.is_active(), "enemies": main.sim.enemies.size(),
			"environment_march": main._sector_march()})
		if (index + 1) % 120 == 0:
			print("TRAILER PROGRESS frames=%d tick=%d score=%d" % [index + 1, main.sim.tick_count, main.sim.score])
	var recorder: Replay = main._recorder
	recorder.claimed_score = main.sim.score
	var replay_path := out_dir.path_join("take.replay")
	if recorder.save(replay_path) != OK:
		push_error("trailer replay save failed")
		await _finish(1)
		return
	var disk_replay := Replay.load_from(replay_path)
	var replay_ok := disk_replay != null and disk_replay.verify_score(main.sim.score)
	var frames_ok := disk_replay != null and _verify_frames(disk_replay)
	var sources_ok := true
	for path in _sources:
		if FileAccess.get_sha256(path) != _sources[path]:
			sources_ok = false
	var manifest := {"kind": "actual gameplay movie", "fps": 60,
		"draw_driver": "one explicit draw per process iteration; automatic rendering disabled",
		"frame_index_source": "Engine.get_process_frames before MovieWriter write",
		"os_gameplay_input_disabled": root.is_input_disabled(),
		"source_revision": OS.get_environment("CAPTURE_REVISION"), "source_dirty": true,
		"engine": Engine.get_version_info()["string"], "renderer": "gl_compatibility",
		"mode": main.sim.mode, "chapter": recorder.chapter, "seed": main._current_seed,
		"god_mode": false, "staged_entities": false, "audio": "unaltered game mix; rights review pending",
		"replay": "take.replay", "replay_sha256": FileAccess.get_sha256(replay_path),
		"replay_score_verified": replay_ok, "replay_frames_verified": frames_ok,
		"source_files": _sources, "sources_unchanged": sources_ok, "frames": _records}
	var receipt := FileAccess.open(out_dir.path_join("movie.json"), FileAccess.WRITE)
	if receipt == null:
		push_error("trailer receipt save failed")
		await _finish(1)
		return
	receipt.store_string(JSON.stringify(manifest, "\t"))
	receipt.close()
	print("TRAILER CAPTURE DONE frames=%d replay=%s checksums=%s sources=%s" % [total, replay_ok, frames_ok, sources_ok])
	await _finish(0 if replay_ok and frames_ok and sources_ok else 1)
