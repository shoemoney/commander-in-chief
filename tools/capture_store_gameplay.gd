extends "res://tools/gif_capture.gd"
## Actual bot-driven gameplay, not the hand-posed screenshots.gd harness.
## GIF_* controls are inherited. CAPTURE_SEED defaults to 3. Output includes the
## original viewport and the exact nearest-filtered 3x presentation a player sees.

var _present: SubViewport
var _card: TextureRect
var _records: Array[Dictionary] = []
var _sources: Dictionary = {}


func _hash_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		if not name.ends_with(".import"):
			var file := path.path_join(name)
			_sources[file] = FileAccess.get_sha256(file)
	for name in DirAccess.get_directories_at(path):
		if not name.begins_with("."):
			_hash_tree(path.path_join(name))


func _verify_frames(replay: Replay) -> bool:
	var sim := replay._new_sim()
	var next := 0
	for i in replay.frames.size():
		var inputs: Array = []
		for encoded in replay.frames[i]:
			inputs.append(SimInput.decode(encoded))
		sim.step(inputs)
		while next < _records.size() and _records[next]["replay_frame"] == i + 1:
			if sim.checksum() != _records[next]["sim_checksum"]:
				return false
			next += 1
	return next == _records.size()


func _finish(code: int) -> void:
	if _finishing:
		return
	if is_instance_valid(_card):
		_card.texture = null
	if is_instance_valid(_present):
		_present.queue_free()
	await super._finish(code)


func _run() -> void:
	# The bot supplies simulation input directly. Keep desktop keypresses from
	# restarting/changing the run midway through a capture and its replay receipt.
	root.set_disable_input(true)
	await RenderingServer.frame_post_draw
	_kill_splash()
	_hash_tree("res://src")
	_hash_tree("res://assets")
	for path in ["res://project.godot", "res://tools/capture_store_gameplay.gd",
			"res://tools/gif_capture.gd", "res://tools/quiesce.gd"]:
		_sources[path] = FileAccess.get_sha256(path)
	main._seed_override = _env_i("CAPTURE_SEED", 3)
	var chapter := _env_i("GIF_CHAPTER", 0)
	if chapter > 0:
		main.start_arcade(chapter)
	else:
		main.start_game(OS.get_environment("GIF_MODE") == "endless")
	main.demo_autoplay = true
	var captured_sim: SimWorld = main.sim
	_present = SubViewport.new()
	_present.size = Vector2i(1920, 1080)
	_present.disable_3d = true
	_present.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_card = TextureRect.new()
	_card.size = Vector2(1920, 1080)
	_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_present.add_child(_card)
	root.add_child(_present)
	for f in skip + total:
		await process_frame
		await RenderingServer.frame_post_draw
		_kill_splash()
		if main.sim != captured_sim:
			push_error("store capture: simulation replaced during the take")
			await _finish(1)
			return
		if f < skip or (f - skip) % every != 0:
			continue
		var raw := root.get_texture().get_image()
		if raw == null or raw.get_size() != Vector2i(640, 360):
			push_error("store capture: expected the unmodified 640x360 game viewport")
			await _finish(1)
			return
		var meta := {"tick": main.sim.tick_count, "score": main.sim.score,
			"replay_frame": main._recorder.frames.size(), "sim_checksum": main.sim.checksum(),
			"environment_march": main._sector_march(), "ground_march": main._bg_march,
			"retained_ground_march": main._litter_march_prev,
			"mode": main.sim.mode, "seed": main._current_seed,
			"chapter": main._recorder.chapter, "god_mode": main.sim.god_mode,
			"assist": main.sim.assist_mode, "hard": main.sim.hard,
			"alive": main.sim.players[0]["alive"], "in_tank": main.sim.players[0]["in_tank"],
			"wiped": main.sim.wiped, "debrief": main._debrief,
			"menu_visible": main._menu.is_active(), "enemies": main.sim.enemies.size()}
		if meta["god_mode"]:
			push_error("store capture: god mode is forbidden")
			await _finish(1)
			return
		_card.texture = ImageTexture.create_from_image(raw)
		# Render the captured texture, not a later simulation frame. This is the
		# same nearest-filtered integer presentation as the game window, with no
		# enhancement, crop, text or replacement content.
		await process_frame
		await RenderingServer.frame_post_draw
		var presented := _present.get_texture().get_image()
		shot += 1
		var raw_name := "raw-%03d.png" % shot
		var name := "gameplay-%03d.png" % shot
		if raw.save_png(out_dir.path_join(raw_name)) != OK \
				or presented.save_png(out_dir.path_join(name)) != OK:
			push_error("store capture: image write failed")
			await _finish(1)
			return
		meta.merge({"file": name, "raw_file": raw_name,
			"sha256": FileAccess.get_sha256(out_dir.path_join(name)),
			"raw_sha256": FileAccess.get_sha256(out_dir.path_join(raw_name))})
		_records.append(meta)
		print("STORE FRAME %d tick=%d alive=%s score=%d" % [shot, meta["tick"], meta["alive"], meta["score"]])
	var replay_path := out_dir.path_join("take.replay")
	var recorder: Replay = main._recorder
	recorder.claimed_score = main.sim.score
	if recorder.save(replay_path) != OK:
		push_error("store capture: replay write failed")
		await _finish(1)
		return
	var disk_replay := Replay.load_from(replay_path)
	var replay_ok := disk_replay != null and disk_replay.verify_score(main.sim.score)
	var frames_ok := disk_replay != null and _verify_frames(disk_replay)
	var sources_ok := true
	for path in _sources:
		if FileAccess.get_sha256(path) != _sources[path]:
			sources_ok = false
	var manifest := {"kind": "actual bot-driven gameplay capture",
		"source_revision": OS.get_environment("CAPTURE_REVISION"),
		"source_dirty": true, "renderer": "gl_compatibility",
		"engine": Engine.get_version_info()["string"],
		"presentation": "640x360 game canvas rendered at exact nearest-filtered 3x",
		"size": [1920, 1080], "staged_entities": false,
		"os_gameplay_input_disabled": root.is_input_disabled(),
		"replay": "take.replay", "replay_sha256": FileAccess.get_sha256(replay_path),
		"replay_score_verified": replay_ok, "replay_frames_verified": frames_ok,
		"source_files": _sources, "sources_unchanged": sources_ok,
		"frames": _records}
	var file := FileAccess.open(out_dir.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		push_error("store capture: manifest write failed")
		await _finish(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("STORE CAPTURE DONE frames=%d replay_verified=%s frame_checksums=%s sources_unchanged=%s" % [shot, replay_ok, frames_ok, sources_ok])
	await _finish(0 if replay_ok and frames_ok and sources_ok else 1)
