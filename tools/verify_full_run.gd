extends SceneTree

const Quiesce := preload("res://tools/quiesce.gd")
const SAMPLE_INTERVAL := 600
const CASES := {
	"campaign_solo": {"entry": "campaign", "players": 1, "expect": "full_victory", "ticks": 36000},
	"campaign_coop": {"entry": "campaign", "players": 2, "expect": "full_victory", "ticks": 36000},
	"arcade_solo": {"entry": "arcade", "players": 1, "expect": "full_victory", "ticks": 36000},
	"boss_rush_solo": {"entry": "boss_rush", "players": 1, "expect": "full_victory", "ticks": 36000},
	"daily_solo": {"entry": "daily", "players": 1, "expect": "full_victory", "ticks": 36000},
	"endless_solo": {"entry": "endless", "players": 1, "expect": "waves", "ticks": 18000},
	"campaign_debug_traversal": {"entry": "campaign", "players": 1, "expect": "full_victory", "ticks": 36000, "god_mode": true},
	"staged_finale_victory": {"entry": "arcade", "chapter": 6, "players": 1, "expect": "staged_victory", "ticks": 1200},
	"staged_last_stand_wipe": {"entry": "campaign", "players": 1, "expect": "staged_wipe", "ticks": 240},
	"campaign_controller_solo": {"entry": "campaign", "players": 1, "expect": "full_victory", "ticks": 36000, "controller": true},
	"campaign_controller_coop": {"entry": "campaign", "players": 2, "expect": "full_victory", "ticks": 36000, "controller": true},
	"arcade_controller_solo": {"entry": "arcade", "players": 1, "expect": "full_victory", "ticks": 36000, "controller": true},
	"boss_rush_controller_solo": {"entry": "boss_rush", "players": 1, "expect": "full_victory", "ticks": 36000, "controller": true},
	"daily_controller_solo": {"entry": "daily", "players": 1, "expect": "full_victory", "ticks": 36000, "controller": true},
	"endless_controller_solo": {"entry": "endless", "players": 1, "expect": "waves", "ticks": 18000, "controller": true},
}

var main: Node2D
var case_name := "campaign_solo"
var output_path := "res://build/completion-audit/full-run/campaign_solo.json"
var tick_limit := -1
var seed_value := 0xC0FFEE
var failures: Array[String] = []
var report: Dictionary = {}
var samples: Array[int] = []
var event_counts: Dictionary = {}
var gate_events: Array[int] = []
var observed_open_gates: Array[int] = []
var notable_events: Array[Dictionary] = []
var mutations: Array[Dictionary] = []
var final_stage_applied := false
var wave_clear_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(passed: bool, reason: String) -> void:
	if not passed and reason not in failures:
		failures.append(reason)
		print("FULL RUN CHECK FAIL: ", reason)


func _args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_name = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--max-ticks="):
			tick_limit = int(arg.trim_prefix("--max-ticks="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))


func _run() -> void:
	_args()
	if not CASES.has(case_name):
		print("FULL RUN NOT VERIFIED: unknown case ", case_name)
		quit(2)
		return
	var spec: Dictionary = CASES[case_name]
	if tick_limit < 0:
		tick_limit = int(spec["ticks"])
	tick_limit = maxi(tick_limit, 1)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var debug_restore := bool(spec.get("god_mode", false))
	var staged := String(spec["expect"]).begins_with("staged_")
	report = {
		"schema": 1, "case": case_name, "requested_entry": spec["entry"],
		"player_count": spec["players"], "normal_full_run_eligible": not debug_restore and not staged,
		"input_driver": "production demo_autoplay through main._physics_process",
		"p2_independent_human_input_verified": false,
		"permitted_staging": ["fixed starting seed", "configured player count", "no_autopause", "demo_autoplay", "manual physics clock"],
		"tick_limit": tick_limit, "god_mode": debug_restore, "staged": staged,
		"acceptance": spec["expect"], "limitations": [
			"Headless execution does not verify rendered pixels, audible mix, physical controllers, or live Steam.",
			"The two-player demo driver plans both inputs relative to player one. It does not prove independent human co-op inputs."],
	}
	if debug_restore:
		report["permitted_staging"].append("debug auto-restore enabled for traversal only")
	if staged:
		report["permitted_staging"].append("explicit ending-state mutation recorded in mutations")
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	if bool(spec.get("controller", false)):
		var detached_members: Array[Node] = []
		for property in main.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var member = main.get(String(property["name"]))
			if member is Node and member != main and member.get_parent() == null and member not in detached_members:
				detached_members.append(member)
		for member in detached_members:
			member.free()
		main.set_script(load("res://tools/full_run_input.gd"))
		report["input_driver"] = "test-only legal SimInput controller; inherited production physics, record, view, and save"
		report["observation_policy"] = main.OBSERVATION_POLICY
		report["permitted_staging"].append("test-only legal input decision override")
		report["limitations"][1] = "The legal controller chooses each player's input relative to that player's own position. Physical inputs and independent human co-op remain unverified."
	main.no_autopause = true
	main.demo_autoplay = true
	main.god_mode = debug_restore
	main.set_physics_process(false)
	root.add_child(main)
	main.set_physics_process(false)
	await process_frame
	await process_frame
	main._end_splash()
	main._two_players = int(spec["players"]) == 2
	if String(spec["entry"]) != "daily":
		main._seed_override = seed_value
	match String(spec["entry"]):
		"campaign": main.start_game(false)
		"endless": main.start_game(true)
		"arcade": main.start_arcade(int(spec.get("chapter", 1)))
		"boss_rush": main.start_boss_rush()
		"daily": main.start_daily()
	_check(not main.is_physics_processing(), "automatic_physics_was_not_disabled")
	_check(main._menu.mode == GameMenu.Mode.HIDDEN, "production_entry_did_not_hide_menu")
	_check(main.sim.players.size() == int(spec["players"]), "production_entry_player_count_mismatch")
	var expected_mode := "campaign" if String(spec["entry"]) == "daily" else String(spec["entry"])
	_check(main.sim.mode == expected_mode, "production_entry_mode_mismatch")
	report["mode"] = main.sim.mode
	report["seed"] = main._current_seed
	report["starting_state"] = _state()
	report["verdict"] = "RUNNING"
	_save_report()
	report["daily_spent_on_start"] = main.daily_done() if String(spec["entry"]) == "daily" else null
	if String(spec["entry"]) == "daily":
		_check(main._daily and main.daily_done(), "daily_attempt_was_not_spent_on_start")
	if String(spec["expect"]) == "staged_wipe":
		main.sim.last_stand = true
		main.sim._kill_player(main.sim.players[0])
		mutations.append({"tick": main.sim.tick_count, "changes": "last_stand=true; _kill_player(player[0])"})
		_capture_events()
		main._consume_events()
	var calls := 0
	var last_tick: int = main.sim.tick_count
	var idle_calls := 0
	var began := Time.get_ticks_msec()
	while main.sim.tick_count < tick_limit and calls < tick_limit * 4 + 240:
		main._physics_process(1.0 / 60.0)
		calls += 1
		if main.sim.tick_count > last_tick:
			last_tick = main.sim.tick_count
			idle_calls = 0
			_capture_events()
			if last_tick % SAMPLE_INTERVAL == 0:
				samples.append(main.sim.checksum())
				if not report.has("tick_samples"):
					report["tick_samples"] = []
				report["tick_samples"].append(_state())
				report["latest_observed_state"] = _state()
				report["observed_open_gate_sequence"] = observed_open_gates.duplicate()
				_save_report()
				print("FULL RUN PROGRESS: %s tick=%d gates=%s wave=%d" % [case_name, last_tick, observed_open_gates, main.sim.wave])
		else:
			idle_calls += 1
		if String(spec["expect"]) == "staged_victory" and not final_stage_applied and not main.sim.colossus.is_empty():
			main.sim.events.clear()
			main.sim._damage_colossus(int(main.sim.colossus["hp"]) + 1)
			mutations.append({"tick": main.sim.tick_count, "changes": "clear already-consumed events; _damage_colossus(remaining_hp+1)"})
			final_stage_applied = true
			_capture_events()
			main._consume_events()
		if main._debrief:
			break
		if String(spec["expect"]) == "waves" and main.sim.wave >= 3 and wave_clear_count >= 2:
			break
		if idle_calls > 240:
			_check(false, "production_physics_stalled_before_required_finish")
			break
		if calls % 60 == 0:
			await process_frame
	_check(main.sim.god_mode == debug_restore, "production_debug_restore_gate_mismatch")
	_check(main._recorder.frames.size() == main.sim.tick_count, "recorded_frames_do_not_match_actual_sim_ticks")
	report["physics_calls"] = calls
	report["elapsed_ms"] = Time.get_ticks_msec() - began
	report["end_state"] = _state()
	report["tick_samples"] = report.get("tick_samples", [])
	report["event_counts"] = event_counts
	report["notable_events"] = notable_events
	report["gate_open_event_sequence"] = gate_events
	report["observed_open_gate_sequence"] = observed_open_gates
	report["mutations"] = mutations
	if bool(spec.get("controller", false)):
		report["controller_intents"] = main.controller_history.duplicate(true)
		report["controller_player_intents"] = main.controller_player_history.duplicate(true)
		report["controller_navigation_events"] = main.controller_navigation_events.duplicate(true)
	_evaluate_finish(spec)
	await _verify_replay_and_save(spec, debug_restore or staged)
	report["failures"] = failures
	report["verdict"] = "VERIFIED" if failures.is_empty() else "NOT VERIFIED"
	report["normal_full_campaign_verified"] = failures.is_empty() and case_name in ["campaign_solo", "campaign_coop", "campaign_controller_solo", "campaign_controller_coop"] and not debug_restore and not staged
	_save_report()
	await Quiesce.teardown(self, main)
	print("FULL RUN %s: %s" % ["PASS" if failures.is_empty() else "NOT VERIFIED", case_name])
	quit(0 if failures.is_empty() else 1)


func _state() -> Dictionary:
	var players: Array[Dictionary] = []
	for p in main.sim.players:
		players.append({"alive": p["alive"], "deaths": p["deaths"], "x": p["x"], "y": p["y"],
			"mg_ammo": p["mg_ammo"], "grenade_ammo": p["grenade_ammo"], "in_tank": p["in_tank"]})
	return {"tick": main.sim.tick_count, "checksum": main.sim.checksum(), "score": main.sim.score,
		"camera_top": main.sim.camera_top, "wave": main.sim.wave, "last_stand": main.sim.last_stand,
		"victory": main.sim.victory, "wiped": main.sim.wiped, "debrief": main._debrief,
		"war_chest": main.sim.war_chest, "players": players}


func _capture_events(start_event := 0) -> void:
	for event_i in range(start_event, main.sim.events.size()):
		var ev: Dictionary = main.sim.events[event_i]
		var kind := String(ev.get("t", ""))
		event_counts[kind] = int(event_counts.get(kind, 0)) + 1
		if kind == "wave_clear":
			wave_clear_count += 1
		if kind == "gate_open":
			var gate_idx := absi(int(ev["y"]) / SimWorld.GATE_SPACING)
			gate_events.append(gate_idx)
		if kind in ["gate_open", "colossus_engage", "victory", "wipe", "wave_clear", "wave_start", "tank_board", "tank_dismount", "respawn", "purchase"]:
			var data: Dictionary = ev.duplicate(true)
			data["tick"] = main.sim.tick_count
			notable_events.append(data)
	for gate in main.sim.gates:
		if bool(gate["open"]):
			var gate_idx := absi(int(gate["y"]) / SimWorld.GATE_SPACING)
			if gate_idx not in observed_open_gates:
				observed_open_gates.append(gate_idx)


func _evaluate_finish(spec: Dictionary) -> void:
	match String(spec["expect"]):
		"full_victory":
			_check(main.sim.victory, "deadline_before_required_finish" if not main.sim.wiped else "normal_run_wiped_before_victory")
			_check(main._debrief, "victory_debrief_not_reached")
			_check(main.sim.last_stand, "last_stand_not_reached")
			_check(int(event_counts.get("colossus_engage", 0)) == 1, "colossus_engage_event_not_seen_once")
			_check(int(event_counts.get("victory", 0)) == 1, "victory_event_not_seen_once")
			var last_gate := SimWorld.BOSS_RUSH_COUNT + 1 if main.sim.mode == "boss_rush" else SimWorld.FINAL_GATE_INDEX
			var expected: Array[int] = []
			var expected_events: Array[int] = []
			for i in range(1, last_gate + 1):
				expected.append(i)
				if i < last_gate:
					expected_events.append(i)
			_check(observed_open_gates == expected, "full_ordered_gate_sequence_not_seen")
			_check(gate_events == expected_events, "full_ordered_gate_open_events_not_seen")
		"waves":
			_check(main.sim.wave >= 3 and wave_clear_count >= 2, "normal_endless_did_not_clear_two_waves")
			_check(not main.sim.victory, "endless_incorrectly_reached_campaign_victory")
		"staged_victory":
			_check(final_stage_applied and main.sim.victory and main._debrief, "staged_finale_did_not_reach_victory_debrief")
			_check(main.sim.last_stand and int(event_counts.get("colossus_engage", 0)) == 1, "staged_finale_did_not_engage_last_stand")
			_check(int(event_counts.get("victory", 0)) == 1, "staged_victory_event_missing")
		"staged_wipe":
			_check(main.sim.last_stand and main.sim.wiped and main._debrief, "staged_last_stand_did_not_reach_wipe_debrief")
			_check(main.sim._all_players_down(), "staged_last_stand_players_not_down")
	if main._debrief:
		var frozen_at: int = main.sim.tick_count
		for i in 180:
			main._physics_process(1.0 / 60.0)
		_check(main.sim.tick_count == frozen_at, "production_debrief_did_not_freeze_simulation")
		report["debrief_freeze_verified"] = main.sim.tick_count == frozen_at


func _verify_replay_and_save(spec: Dictionary, altered_run: bool) -> void:
	var actual_score: int = main.sim.score
	var actual_checksum: int = main.sim.checksum()
	var recorded: Replay = main._recorder
	recorded.claimed_score = actual_score
	var replay_samples := recorded.play(SAMPLE_INTERVAL)
	var replay_sim: SimWorld = recorded._new_sim()
	for frame in recorded.frames:
		var inputs: Array[SimInput] = []
		for encoded in frame:
			inputs.append(SimInput.decode(encoded))
		replay_sim.step(inputs)
	var matches := replay_samples == samples and replay_sim.checksum() == actual_checksum and replay_sim.score == actual_score
	report["replay"] = {"frames": recorded.frames.size(), "sample_checksums_match": replay_samples == samples,
		"final_checksum_match": replay_sim.checksum() == actual_checksum, "score_match": replay_sim.score == actual_score,
		"live_score": actual_score, "replayed_score": replay_sim.score, "replayed_checksum": replay_sim.checksum(),
		"altered_run_not_eligible_for_normal_replay_acceptance": altered_run}
	if not altered_run:
		_check(matches, "recorded_inputs_do_not_reproduce_the_live_run")
	if main._replay_task != -1:
		WorkerThreadPool.wait_for_task_completion(main._replay_task)
		main._replay_task = -1
	var save := ConfigFile.new()
	var save_loaded := save.load(main.SAVE_PATH) == OK
	var disk_replay := Replay.load_from("user://last_run.replay")
	var disk_valid := disk_replay != null and disk_replay.verify_score(actual_score)
	var save_info := {"debrief_reached": main._debrief, "config_loaded": save_loaded,
		"production_replay_saved": disk_replay != null, "production_replay_score_valid": disk_valid,
		"saved_replay_verified_flag": disk_replay.verified if disk_replay != null else null,
		"saved_score": save.get_value("replay", "last_score", -1) if save_loaded else -1,
		"hall_latest": main.hall_latest.duplicate(true)}
	if main._debrief and not altered_run:
		_check(save_loaded and disk_valid, "terminal_save_or_production_replay_not_valid")
		_check(disk_replay != null and disk_replay.frames.size() == recorded.frames.size(), "saved_replay_frame_count_mismatch")
		_check(save_loaded and int(save.get_value("replay", "last_score", -1)) == actual_score, "saved_last_score_mismatch")
		_check(not main.hall_latest.is_empty() and int(main.hall_latest.get("score", -1)) == actual_score, "verified_terminal_run_not_banked_in_hall")
		_check(bool(main.hall_latest.get("won", false)) == main.sim.victory, "banked_terminal_result_mismatch")
		if String(spec["entry"]) == "daily":
			_check(bool(main.hall_latest.get("daily", false)), "daily_result_did_not_keep_daily_tag")
		main.start_watch()
		_check(main._watching, "production_watch_last_run_did_not_start")
		var playback_calls := 0
		while main._watching and playback_calls <= recorded.frames.size() + 2:
			main._physics_process(1.0 / 60.0)
			playback_calls += 1
			if playback_calls % 120 == 0:
				await process_frame
		save_info["watch_playback_ticks"] = main.sim.tick_count
		save_info["watch_playback_final_checksum_match"] = main.sim.checksum() == actual_checksum
		_check(not main._watching and main._menu.mode == GameMenu.Mode.TITLE, "production_watch_last_run_did_not_return_to_title")
		_check(main.sim.checksum() == actual_checksum, "production_watch_last_run_final_state_mismatch")
		_check(main.replay_watched_score == actual_score, "watch_last_run_did_not_persist_watched_score")
		save.load(main.SAVE_PATH)
		_check(int(save.get_value("replay", "watched_score", -1)) == actual_score, "watched_score_missing_from_disk")
		var relaunched: Node2D = (load("res://src/main.tscn") as PackedScene).instantiate()
		relaunched.no_autopause = true
		relaunched.set_physics_process(false)
		root.add_child(relaunched)
		relaunched.set_physics_process(false)
		await process_frame
		await process_frame
		save_info["relaunch_last_score_match"] = relaunched.last_run_score == actual_score
		save_info["relaunch_watched_score_match"] = relaunched.replay_watched_score == actual_score
		var banked_on_relaunch := false
		for entry in relaunched.hall:
			if entry == save_info["hall_latest"]:
				banked_on_relaunch = true
		save_info["relaunch_hall_entry_match"] = banked_on_relaunch
		_check(relaunched.last_run_score == actual_score and relaunched.replay_watched_score == actual_score,
			"terminal_replay_metadata_did_not_survive_scene_relaunch")
		_check(banked_on_relaunch, "terminal_hall_result_did_not_survive_scene_relaunch")
		await Quiesce.teardown(self, relaunched)
	if save_loaded:
		save.save(output_path.get_base_dir().path_join(case_name + ".cfg"))
	if disk_replay != null:
		disk_replay.save(output_path.get_base_dir().path_join(case_name + ".replay"))
	else:
		recorded.save(output_path.get_base_dir().path_join(case_name + ".partial.replay"))
	report["save"] = save_info


func _save_report() -> void:
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_check(false, "report_could_not_be_written")
		return
	file.store_string(JSON.stringify(report, "\t"))
