extends RefCounted

const Runner := preload("res://tests/run_tests.gd")
const InputHelper := preload("res://src/view/accessibility_input.gd")
const Policy := preload("res://src/view/accessibility_policy.gd")

var _file_index := 0


func _record_blank_frames(replay: Replay, count: int) -> void:
	for tick in count:
		var inputs: Array[SimInput] = []
		for seat in replay.player_count:
			inputs.append(SimInput.new())
		replay.record_tick(inputs)


func _fixture() -> Dictionary:
	var replay := Replay.new()
	replay.seed_value = 71
	replay.player_count = 2
	_record_blank_frames(replay, 8)
	var first := SimInput.new()
	first.move_x = 127
	first.move_y = -63
	first.aim_x = -256
	first.aim_y = 17
	first.fire = true
	var second := SimInput.new()
	second.move_x = -128
	second.move_y = -256
	second.aim_x = 90
	second.aim_y = -240
	second.roll = true
	second.revive = true
	replay.frames[0] = [first.encode(), second.encode()]
	replay.claimed_score = replay.replay_final_score()
	return replay.to_dict()


func _write(data: Dictionary) -> String:
	_file_index += 1
	var path := "user://accessibility_replay_%d.json" % _file_index
	Runner.T.eq(Replay.save_dict(data, path), OK, "replay fixture saved to private user storage")
	return path


func _load(data: Dictionary) -> Replay:
	return Replay.load_from(_write(data))


func _reject(data: Dictionary, reason: String) -> void:
	var path := _write(data)
	Runner.T.ok(Replay.load_from(path) == null, reason)
	Runner.T.eq(Replay.validate_file(path)["code"], Replay.VALIDATION_MALFORMED,
		"malformed metadata is rejected before score simulation")


func test_pre_accessibility_replay_retains_standard_pacing_and_inputs() -> void:
	var data := _fixture()
	for field in ["slow_mode", "accessibility", "accessibility_changes", "assist_tags"]:
		data.erase(field)
	var loaded := _load(data)
	Runner.T.ok(loaded != null, "current-ruleset replays predating accessibility metadata still load")
	if loaded == null:
		return
	Runner.T.eq(loaded.accessibility, {}, "older recordings have empty view settings")
	Runner.T.eq(loaded.accessibility_changes, [], "older recordings have no setting transitions")
	Runner.T.eq(loaded.assist_tags, [], "a standard older run stays unassisted")
	for frame in 8:
		Runner.T.ok(not loaded.slow_at(frame), "older recordings play at standard speed")
	Runner.T.eq(loaded.frames.size(), data["frames"].size(), "older recordings retain every input frame")
	for frame in loaded.frames.size():
		Runner.T.eq(loaded.frames[frame].size(), 2, "older recordings retain both seats")
		for seat in loaded.frames[frame].size():
			Runner.T.eq(SimInput.decode(loaded.frames[frame][seat]).encode(), data["frames"][frame][seat],
				"older quantized axes and independent action bits remain exact after JSON decoding")
	Runner.T.eq(loaded.to_dict()["ruleset"], 1, "view metadata does not change the simulation ruleset")
	Runner.T.ok(loaded.verify_score(loaded.claimed_score), "older resolved input recording still verifies")


func test_empty_new_metadata_preserves_the_existing_replay_checksums() -> void:
	var data := _fixture()
	var plain := _load(data)
	for field in ["slow_mode", "accessibility", "accessibility_changes", "assist_tags"]:
		data.erase(field)
	var older := _load(data)
	Runner.T.ok(plain != null and older != null, "both envelope shapes load")
	if plain == null or older == null:
		return
	Runner.T.eq(plain.play(1), older.play(1), "empty metadata cannot alter any per-tick checksum")


func test_frame_zero_replacement_updates_the_initial_pacing_and_settings() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"slow_mode": true, "aim_assist": 1}, [])
	replay.record_accessibility({"slow_mode": false, "aim_assist": 2}, [])
	Runner.T.eq(replay.accessibility_changes.size(), 1, "changes before the first tick share one marker")
	Runner.T.eq(replay.accessibility, {"slow_mode": false, "aim_assist": 2},
		"the initial snapshot matches the settings that reach frame zero")
	Runner.T.ok(not replay.slow_mode and not replay.slow_at(0), "the obsolete initial speed is replaced")
	_record_blank_frames(replay, 1)
	var loaded := _load(replay.to_dict())
	Runner.T.ok(loaded != null, "replaced frame-zero metadata survives a disk round trip")
	if loaded != null:
		Runner.T.ok(not loaded.slow_at(0), "loaded playback uses the replacement speed")


func test_same_frame_later_replacement_keeps_only_the_last_settings_marker() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"slow_mode": false}, [])
	_record_blank_frames(replay, 2)
	replay.record_accessibility({"slow_mode": true}, [])
	replay.record_accessibility({"slow_mode": false, "classic_aim_p1": true}, [])
	_record_blank_frames(replay, 1)
	Runner.T.eq(replay.accessibility_changes.size(), 2, "one starting marker and one frame-two marker")
	Runner.T.eq(replay.accessibility_changes[1]["frame"], 2, "later replacement stays at its actual frame")
	Runner.T.eq(replay.accessibility_changes[1]["settings"],
		{"slow_mode": false, "classic_aim_p1": true}, "the last settings replace the pending frame")
	Runner.T.ok(not replay.slow_at(1) and not replay.slow_at(2), "replacement does not alter prior frames")
	Runner.T.ok(replay.assist_tags.has("slow_mode"), "changing settings back cannot erase the assist history")


func test_first_metadata_record_after_existing_frames_does_not_retime_the_prefix() -> void:
	var replay := Replay.new()
	_record_blank_frames(replay, 4)
	replay.record_accessibility({"slow_mode": true}, [])
	_record_blank_frames(replay, 2)
	Runner.T.eq(replay.accessibility, {}, "late recording preserves the implicit original view defaults")
	Runner.T.ok(not replay.slow_mode, "the original prefix stays at standard speed")
	for frame in 4:
		Runner.T.ok(not replay.slow_at(frame), "a later assist cannot change an earlier frame's pacing")
	Runner.T.ok(replay.slow_at(4) and replay.slow_at(5), "the actual transition changes later frames")
	var loaded := _load(replay.to_dict())
	Runner.T.ok(loaded != null, "a late initial marker is a valid replay timeline")
	if loaded != null:
		Runner.T.ok(not loaded.slow_at(3) and loaded.slow_at(4), "disk loading retains the precise boundary")


func test_mid_run_speed_changes_drive_the_integer_pacer_at_recorded_frame_boundaries() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"slow_mode": false}, [])
	_record_blank_frames(replay, 2)
	replay.record_accessibility({"slow_mode": true}, [])
	_record_blank_frames(replay, 5)
	replay.record_accessibility({"slow_mode": false}, [])
	_record_blank_frames(replay, 2)
	var loaded := _load(replay.to_dict())
	Runner.T.ok(loaded != null, "mixed-speed metadata round trip")
	if loaded == null:
		return
	for frame in 9:
		Runner.T.eq(loaded.slow_at(frame), frame >= 2 and frame < 7,
			"playback pacing follows the frame-two and frame-seven transitions")
	var pacer := Policy.new()
	var completed_at: Array[int] = []
	var frame := 0
	var callbacks := 0
	while frame < loaded.frames.size() and callbacks < 20:
		callbacks += 1
		if pacer.should_step(loaded.slow_at(frame)):
			completed_at.append(callbacks)
			frame += 1
	Runner.T.eq(completed_at, [1, 2, 3, 4, 5, 7, 8, 9, 10],
		"only the recorded slow interval inserts a callback without a sim step")


func test_missing_slow_key_in_a_later_snapshot_restores_the_standard_default() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"slow_mode": true}, [])
	_record_blank_frames(replay, 2)
	replay.record_accessibility({}, [])
	_record_blank_frames(replay, 1)
	Runner.T.ok(replay.slow_at(1), "the initial snapshot is slow")
	Runner.T.ok(not replay.slow_at(2), "a default snapshot cannot inherit stale slow mode")


func test_recording_equal_settings_does_not_add_transition_noise() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"slow_mode": false, "aim_assist": 1}, [])
	_record_blank_frames(replay, 3)
	replay.record_accessibility({"slow_mode": false, "aim_assist": 1}, [])
	Runner.T.eq(replay.accessibility_changes.size(), 1, "unchanged settings do not create another transition")


func test_recorded_settings_and_serialized_metadata_do_not_alias_live_caller_data() -> void:
	var replay := Replay.new()
	var settings := {"slow_mode": false, "future_view": {"label": "original"}}
	replay.record_accessibility(settings, [])
	settings["slow_mode"] = true
	settings["future_view"]["label"] = "changed outside recorder"
	Runner.T.eq(replay.accessibility["future_view"]["label"], "original", "recording captures nested settings")
	Runner.T.ok(not replay.slow_at(0), "caller mutation cannot change recorded pacing")
	var snapshot := replay.to_dict()
	_record_blank_frames(replay, 1)
	replay.record_accessibility({"slow_mode": true}, [])
	Runner.T.eq(snapshot["accessibility_changes"].size(), 1, "a saved snapshot cannot gain later markers")
	snapshot["accessibility"]["future_view"]["label"] = "changed outside snapshot"
	Runner.T.eq(replay.accessibility["future_view"]["label"], "original", "snapshot mutation cannot edit the recorder")


func test_assist_tag_mapper_distinguishes_tiers_seats_vest_and_visual_settings() -> void:
	var settings := {"single_stick_p1": true, "single_stick_p2": true, "classic_aim_p2": true,
		"aim_assist": 1, "toggle_revive": true, "slow_mode": true, "shake_level": 0, "flash_level": 0}
	Runner.T.eq(Replay.assist_tags_for_config(settings, 1, true),
		["vest", "single_stick_p1", "aim_low", "toggle_revive", "slow_mode"],
		"solo identity ignores an absent second seat and visual-only settings")
	settings["aim_assist"] = 2
	Runner.T.eq(Replay.assist_tags_for_config(settings, 2),
		["single_stick_p1", "single_stick_p2", "classic_aim_p2", "aim_high", "toggle_revive", "slow_mode"],
		"co-op identity describes both seats and the actual selected tier")


func test_assist_identity_is_the_union_even_when_all_settings_are_disabled_later() -> void:
	var replay := Replay.new()
	replay.record_accessibility({"aim_assist": 1, "single_stick_p1": true}, ["future_access_aid"])
	_record_blank_frames(replay, 1)
	replay.record_accessibility({"aim_assist": 2, "slow_mode": true}, [])
	_record_blank_frames(replay, 1)
	replay.record_accessibility({}, [])
	Runner.T.eq(replay.assist_tags,
		["future_access_aid", "single_stick_p1", "aim_low", "aim_high", "slow_mode"],
		"the final identity preserves every recorded assist and supplied extension tag once")


func test_omitted_caller_tags_cannot_label_an_enabled_assist_as_standard() -> void:
	var replay := Replay.new()
	replay.assist = true
	replay.record_accessibility({"single_stick_p1": true, "aim_assist": 2, "toggle_buy": true}, [])
	Runner.T.eq(replay.assist_tags, ["vest", "single_stick_p1", "aim_high", "toggle_buy"],
		"enabled settings derive their identity even when the caller supplies no tags")


func test_loading_underreported_tags_restores_the_union_from_settings_history() -> void:
	var data := _fixture()
	data["accessibility"] = {"slow_mode": false, "aim_assist": 1}
	data["accessibility_changes"] = [
		{"frame": 0, "settings": {"slow_mode": false, "aim_assist": 1}},
		{"frame": 3, "settings": {"slow_mode": true, "single_stick_p2": true}},
		{"frame": 6, "settings": {}},
	]
	data["assist_tags"] = []
	var loaded := _load(data)
	Runner.T.ok(loaded != null, "underreported view identity can be reconstructed from valid metadata")
	if loaded != null:
		Runner.T.eq(loaded.assist_tags, ["aim_low", "single_stick_p2", "slow_mode"],
			"disabling assists at the end cannot erase earlier assist markers")
	data = _fixture()
	data["slow_mode"] = true
	for field in ["accessibility", "accessibility_changes", "assist_tags"]:
		data.erase(field)
	loaded = _load(data)
	Runner.T.ok(loaded != null, "the initial pacing flag can accompany omitted optional view metadata")
	if loaded != null:
		Runner.T.ok(loaded.slow_at(0), "the separate initial pacing flag still slows the first frame")
		Runner.T.eq(loaded.assist_tags, ["slow_mode"],
			"omitting optional settings and tags cannot conceal the initial slow interval")


func test_loading_rejects_wrong_outer_metadata_types() -> void:
	for malformed in [{"slow_mode": 1}, {"accessibility": []},
		{"accessibility_changes": {}}, {"assist_tags": {}}]:
		var data := _fixture()
		data.merge(malformed, true)
		_reject(data, "metadata containers and pacing flag require their declared types")


func test_loading_rejects_non_boolean_control_settings_in_base_and_transitions() -> void:
	for key in ["single_stick_p1", "single_stick_p2", "classic_aim_p1", "classic_aim_p2",
		"toggle_grenade", "toggle_roll", "toggle_interact", "toggle_revive", "toggle_buy", "slow_mode"]:
		var data := _fixture()
		data["accessibility"] = {key: "on"}
		_reject(data, "a string cannot enable a boolean accessibility control")
		data = _fixture()
		data["accessibility_changes"] = [{"frame": 2, "settings": {key: 1}}]
		_reject(data, "an integer in a transition cannot masquerade as a boolean control")


func test_loading_rejects_fractional_out_of_range_and_non_numeric_setting_levels() -> void:
	for key in ["aim_assist", "shake_level", "flash_level"]:
		var maximum: int = 2 if key == "aim_assist" else 10
		for invalid in [-1, maximum + 1, 0.5, "high", true, null]:
			var data := _fixture()
			data["accessibility"] = {key: invalid}
			_reject(data, "invalid tier or slider values must be rejected at the disk boundary")
			data = _fixture()
			data["accessibility_changes"] = [{"frame": 2, "settings": {key: invalid}}]
			_reject(data, "invalid transition levels cannot reach Watch")


func test_loading_rejects_duplicate_and_reversed_transition_frames() -> void:
	for positions in [[2, 2], [3, 1]]:
		var data := _fixture()
		data["accessibility_changes"] = [
			{"frame": positions[0], "settings": {"slow_mode": true}},
			{"frame": positions[1], "settings": {"slow_mode": false}},
		]
		_reject(data, "transition frames must increase strictly after same-frame replacement")


func test_loading_rejects_fractional_negative_past_end_and_wrong_type_transition_frames() -> void:
	for invalid in [-1, 0.5, 9, "2", true, null]:
		var data := _fixture()
		data["accessibility_changes"] = [{"frame": invalid, "settings": {"slow_mode": true}}]
		_reject(data, "only integral transition positions within the recording are accepted")


func test_loading_rejects_missing_or_malformed_transition_settings() -> void:
	for malformed in [[], {"frame": 2}, {"frame": 2, "settings": []}]:
		var data := _fixture()
		data["accessibility_changes"] = [malformed]
		_reject(data, "each transition requires a frame and settings dictionary")


func test_loading_rejects_conflicting_initial_pacing_and_frame_zero_snapshots() -> void:
	var data := _fixture()
	data["accessibility"] = {"slow_mode": true}
	_reject(data, "the initial settings cannot disagree with the saved pacing flag")
	data = _fixture()
	data["accessibility"] = {"slow_mode": false}
	data["accessibility_changes"] = [{"frame": 0, "settings": {"slow_mode": true}}]
	_reject(data, "a frame-zero marker cannot contradict its starting snapshot")


func test_loading_rejects_empty_oversized_duplicate_and_non_string_assist_tags() -> void:
	for invalid_tags in [[""], ["x".repeat(65)], ["aim_high", "aim_high"], [1], [{}]]:
		var data := _fixture()
		data["assist_tags"] = invalid_tags
		_reject(data, "assist identities require bounded unique non-empty strings")


func test_unknown_future_view_metadata_and_tags_remain_optional_and_opaque() -> void:
	var data := _fixture()
	data["accessibility"] = {"future_visual_preset": {"label": "clear"}}
	data["assist_tags"] = ["future_access_aid"]
	var loaded := _load(data)
	Runner.T.ok(loaded != null, "unknown view-only keys do not require a simulation ruleset bump")
	if loaded != null:
		Runner.T.eq(loaded.accessibility, data["accessibility"], "future view metadata remains intact")
		Runner.T.eq(loaded.assist_tags, ["future_access_aid"], "future assist tags remain intact")
		Runner.T.ok(not loaded.slow_at(0), "unknown settings cannot alter standard pacing")


func test_recorded_resolved_assisted_inputs_reproduce_live_per_tick_checksums() -> void:
	var replay := Replay.new()
	replay.seed_value = 0xABCDEF
	replay.player_count = 2
	var settings := {"single_stick_p1": true, "single_stick_p2": true,
		"classic_aim_p1": true, "aim_assist": 2, "toggle_grenade": true, "slow_mode": true}
	replay.record_accessibility(settings, [])
	var helper := InputHelper.new()
	helper.configure(settings)
	var world := SimWorld.new(replay.seed_value, replay.player_count, replay.mode)
	var live: Array[int] = []
	var transformed_aim_frames := 0
	for tick in 240:
		var inputs: Array[SimInput] = []
		for seat in 2:
			var movement := Vector2(-0.5 if seat == 0 else 0.5, -1.0)
			var resolved: Vector2 = helper.resolve_aim(seat, movement, Vector2.ZERO, world)
			var input := SimInput.new()
			input.move_x = int(movement.x * SimInput.AXIS_MAX)
			input.move_y = -SimInput.AXIS_MAX
			input.aim_x = clampi(int(round(resolved.x * SimInput.AXIS_MAX)), -SimInput.AXIS_MAX, SimInput.AXIS_MAX)
			input.aim_y = clampi(int(round(resolved.y * SimInput.AXIS_MAX)), -SimInput.AXIS_MAX, SimInput.AXIS_MAX)
			input.fire = true
			input.grenade = helper.transform_action(seat, "grenade", tick == 30 or tick == 90)
			if input.aim_x != 0 or input.aim_y != 0:
				transformed_aim_frames += 1
			inputs.append(input)
		replay.record_tick(inputs)
		world.step(inputs)
		live.append(world.checksum())
	replay.claimed_score = world.score
	Runner.T.ok(transformed_aim_frames > 0, "movement-only controls produced real recorded aim")
	Runner.T.ok(world.tick_count > 0, "the live simulation advanced under the resolved input stream")
	var loaded := _load(replay.to_dict())
	Runner.T.ok(loaded != null, "resolved assisted input recording survives disk loading")
	if loaded == null:
		return
	Runner.T.eq(loaded.play(1), live, "every replay tick matches the live sim despite recorded view controls")
	Runner.T.eq(loaded.last_score, world.score, "the recorded resolved inputs retain the real score")
	Runner.T.ok(loaded.verify_score(world.score), "score validation consumes the same resolved stream")
	var incompatible_live_settings := InputHelper.new()
	incompatible_live_settings.configure({})
	Runner.T.eq(loaded.play(1), live, "current live input settings cannot re-transform the saved replay")
