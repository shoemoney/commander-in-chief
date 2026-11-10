extends SceneTree

const Quiesce := preload("res://tools/quiesce.gd")
const SAMPLE_INTERVAL := 600

var main: Node2D
var case_name := "chapter_2"
var output_path := "res://build/completion-audit/remaining-gameplay/chapter_2.json"
var max_ticks := 36000
var expected_chapter := -1
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var mutations: Array[Dictionary] = []
var events: Array[Dictionary] = []
var gate_events: Array[int] = []
var open_gates: Array[int] = []
var samples: Array[int] = []
var report: Dictionary = {}
var physics_calls := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, reason: String) -> void:
	checks.append({"pass": ok, "reason": reason, "tick": main.sim.tick_count if main != null else -1})
	if not ok:
		failures.append(reason)
		print("REMAINING GAMEPLAY CHECK FAIL: ", reason)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_name = arg.trim_prefix("--case=")
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=")
		elif arg.begins_with("--max-ticks="):
			max_ticks = int(arg.trim_prefix("--max-ticks="))
		elif arg.begins_with("--expect-chapter="):
			expected_chapter = int(arg.trim_prefix("--expect-chapter="))
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report = {"schema": 1, "case": case_name, "verdict": "RUNNING", "normal_full_run_eligible": case_name.begins_with("chapter_"),
		"input_driver": "actual keyboard menu events; test-only typed SimInput selection; inherited production physics/view/record/save",
		"permitted_setup": ["fixed seed 0xC0FFEE", "configured player count", "no_autopause", "manual production physics clock", "splash ended before menu navigation"],
		"limitations": ["Headless source scene does not verify rendered pixels, physical controllers, human co-op feel, native foreign builds or live Steam.",
			"Staged integration setups are listed in mutations and cannot establish ordinary full-run replay validity."],
		"profile_path": OS.get_user_data_dir(), "profile_is_private": OS.get_user_data_dir().begins_with(OS.get_environment("HOME"))}
	_check(bool(report["profile_is_private"]), "canonical_private_profile_is_in_effect")
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	var detached: Array[Node] = []
	for property in main.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var member = main.get(String(property["name"]))
		if member is Node and member != main and member.get_parent() == null and member not in detached:
			detached.append(member)
	for member in detached:
		member.free()
	main.set_script(load("res://tools/remaining_gameplay_input.gd"))
	main.no_autopause = true
	main.god_mode = false
	main.set_physics_process(false)
	root.add_child(main)
	main.set_physics_process(false)
	await process_frame
	await process_frame
	main._end_splash()
	main._two_players = not case_name.begins_with("chapter_")
	main._seed_override = 0xC0FFEE
	var began := Time.get_ticks_msec()
	if case_name.begins_with("chapter_"):
		await _chapter(int(case_name.trim_prefix("chapter_")))
	elif case_name == "tank_recovery" or case_name == "tank_no_bail_control":
		await _tank(case_name == "tank_no_bail_control")
	elif case_name == "remote_rally":
		await _rally()
	elif case_name == "unanimous_shop" or case_name == "downed_shop_control":
		await _shop(case_name == "downed_shop_control")
	else:
		_check(false, "known_case_required")
	_check(not main.sim.god_mode and not main.god_mode, "debug_restore_never_enabled")
	_check(main._recorder.frames.size() == main.sim.tick_count, "production_recorder_has_one_frame_per_sim_tick")
	var seat_totals: Array[int] = []
	for pi in main.sim.players.size():
		var total: int = main.probe_decisions[pi]
		for count in main.controller_player_history.get(str(pi), {}).values():
			total += int(count)
		seat_totals.append(total)
		_check(total == main.sim.tick_count, "seat_%d_has_exactly_one_input_decision_per_sim_tick" % (pi + 1))
	_copy_profile()
	report.merge({"elapsed_ms": Time.get_ticks_msec() - began, "physics_calls": physics_calls, "checks": checks,
		"failures": failures, "mutations": mutations, "events": events, "gate_open_events": gate_events,
		"observed_open_gates": open_gates, "seat_decisions": seat_totals, "end_state": _state(),
		"source_main_sha256": FileAccess.get_sha256("res://src/main.gd"),
		"source_sim_sha256": FileAccess.get_sha256("res://src/sim/sim_world.gd"),
		"driver_sha256": FileAccess.get_sha256("res://tools/remaining_gameplay_input.gd"),
		"harness_sha256": FileAccess.get_sha256("res://tools/verify_remaining_gameplay.gd"),
		"verdict": "PASS" if failures.is_empty() else "ISSUES"}, true)
	var out := FileAccess.open(output_path, FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t") + "\n")
	out.close()
	await Quiesce.teardown(self, main)
	main = null
	print("REMAINING GAMEPLAY %s: %s" % ["PASS" if failures.is_empty() else "ISSUES", case_name])
	quit(0 if failures.is_empty() else 1)


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.device = InputEvent.DEVICE_ID_KEYBOARD
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.get_viewport().push_input(event, true)
	await process_frame


func _tap(code: Key) -> void:
	await _key(code)
	await _key(code, false)


func _select(id: String) -> void:
	var found := false
	for _i in 20:
		var items: Array[Dictionary] = main._menu._menu_items()
		if not items.is_empty() and String(items[main._menu.sel]["id"]) == id:
			found = true
			break
		await _tap(KEY_UP if id == "modes" else KEY_DOWN)
	_check(found, "menu_row_%s_reachable_by_keyboard" % id)
	if found:
		await _tap(KEY_ENTER)


func _chapter(chapter: int) -> void:
	await _select("setup")
	await _select("modes")
	await _select("chapter_select")
	_check(main._menu.mode == GameMenu.Mode.CHAPTERS, "production_menu_reached_chapter_picker")
	for _i in chapter - 1:
		await _tap(KEY_DOWN)
	var chosen: String = main._menu._menu_items()[main._menu.sel]["id"]
	_check(chosen == "ch%d" % chapter, "keyboard_focus_resolves_requested_chapter")
	var untouched_tick: int = main.sim.tick_count
	await _key(KEY_ENTER, false)
	_check(main._menu.mode == GameMenu.Mode.CHAPTERS and main.sim.tick_count == untouched_tick,
		"release_without_confirmation_cannot_start_chapter")
	await _tap(KEY_ENTER)
	_check(main._menu.mode == GameMenu.Mode.HIDDEN and main.sim.mode == "arcade", "confirmed_chapter_starts_live_arcade_scene")
	var resolved := chapter if expected_chapter < 0 else expected_chapter
	var skip := (resolved - 1) * SimWorld.GATE_SPACING
	_check(main._arcade_chapter == resolved and main._recorder.chapter == resolved, "requested_chapter_recorded_in_live_and_replay_config")
	_check(main.sim.camera_top == -SimWorld.VIEW_H - skip, "selected_chapter_has_exact_start_camera")
	_check(main.sim._gate_counter == resolved - 1, "selected_chapter_has_exact_gate_stream_cursor")
	report["resolved_entry"] = {"requested": chapter, "expected": resolved, "menu_row": chosen, "mode": main.sim.mode,
		"recorder_chapter": main._recorder.chapter, "start": _state()}
	var idle := SimInput.new()
	main.probe_inputs.assign([idle])
	for _i in 30:
		await _tick()
	_check(open_gates.is_empty() and gate_events.is_empty(), "idle_control_cannot_claim_forward_gate_progression")
	main.probe_inputs.clear()
	var calls := 0
	while not main._debrief and main.sim.tick_count < max_ticks and calls < max_ticks * 4:
		await _tick()
		calls += 1
		if main.sim.tick_count % 600 == 0:
			print("REMAINING GAMEPLAY PROGRESS: %s tick=%d gates=%s" % [case_name, main.sim.tick_count, open_gates])
	_check(main.sim.victory and main._debrief and main.sim.last_stand, "chapter_reaches_last_stand_victory_and_debrief_with_legal_inputs")
	var expected: Array[int] = []
	var expected_events: Array[int] = []
	for gi in range(chapter, SimWorld.FINAL_GATE_INDEX + 1):
		expected.append(gi)
		if gi < SimWorld.FINAL_GATE_INDEX:
			expected_events.append(gi)
	_check(open_gates == expected and gate_events == expected_events, "chapter_crosses_exact_remaining_gate_sequence")
	_check(_event_count("victory") == 1 and _event_count("colossus_engage") == 1, "chapter_has_one_colossus_engagement_and_one_victory")
	var frozen: int = main.sim.tick_count
	for _i in 60:
		await _tick()
	_check(main.sim.tick_count == frozen, "chapter_debrief_freezes_simulation")
	await _replay()


func _clean_campaign() -> void:
	main.start_game(false)
	var fields := ["enemies", "bullets", "enemy_bullets", "grenades", "strikes", "mines", "rocks", "barrels", "waters", "vents", "bunkers", "pickups", "tanks", "sandbags"]
	var cleared := {}
	var before: int = main.sim.checksum()
	for field in fields:
		cleared[field] = main.sim.get(field).duplicate(true)
		main.sim.get(field).clear()
	main.sim._spawn_grace = 100000
	mutations.append({"tick": main.sim.tick_count, "name": "bounded_empty_campaign_arena", "cleared": cleared,
		"_spawn_grace": 100000, "before_checksum": before, "after_checksum": main.sim.checksum()})
	report["normal_full_run_eligible"] = false


func _inputs(p1: SimInput, p2: SimInput) -> void:
	main.probe_inputs.assign([p1, p2])


func _tank(no_bail: bool) -> void:
	_clean_campaign()
	var p0: Dictionary = main.sim.players[0]
	var p1: Dictionary = main.sim.players[1]
	var tank := {"x": p0["x"], "y": p0["y"], "alive": true, "burning": false, "fuel": SimWorld.TANK_FUEL_TICKS,
		"burn_ticks": 0, "fire_cd": 0, "occupant": -1}
	main.sim.tanks.append(tank)
	p1["x"] = p0["x"]
	p1["y"] = p0["y"]
	main.sim.war_chest = 500
	mutations.append({"tick": 0, "name": "parked_tank_and_nearby_two_seats", "tank": tank.duplicate(true), "players": main.sim.players.duplicate(true), "war_chest": 500})
	var idle := SimInput.new()
	var board := SimInput.new()
	board.interact = true
	_inputs(board, idle)
	await _tick()
	_check(p0["in_tank"] == 0 and tank["occupant"] == 0 and p1["in_tank"] == -1, "first_interact_boards_driver_only")
	_inputs(idle, board)
	await _tick()
	_check(p1["in_tank"] == 0 and main.sim._tank_gunner(0) == 1 and _event_count("tank_crew") == 1, "independent_second_interact_boards_coax_gunner")
	_inputs(idle, idle)
	await _tick()
	if not no_bail:
		_stage_down(1)
		var cost: int = main.sim.revive_cost(p1)
		var chest: int = main.sim.war_chest
		for _i in 5:
			await _tick()
		_check(not p1["alive"] and main.sim.war_chest == chest, "tank_rescue_control_without_revive_cannot_recover_partner")
		var rescue := SimInput.new()
		rescue.revive = true
		_inputs(rescue, idle)
		await _tick()
		_check(p1["alive"] and p1["x"] == p0["x"] and p1["y"] == p0["y"] and p0["in_tank"] == 0,
			"living_tank_driver_remote_revive_restores_partner_at_hull")
		_check(chest - main.sim.war_chest == cost and _event_count("revive") == 1, "tank_rescue_debits_exact_shared_chest_cost_and_emits_view_event")
		_inputs(idle, idle)
		await _tick()
		_inputs(idle, board)
		await _tick()
		_check(p1["in_tank"] == 0, "rescued_partner_can_rejoin_coax_seat")
		_inputs(idle, idle)
		await _tick()
	var shell := {"x": tank["x"], "y": tank["y"], "ticks": 1, "obs": false}
	main.sim.strikes.append(shell)
	for p in main.sim.players:
		p["vest"] = false
		p["hurt_iframes"] = 0
	mutations.append({"tick": main.sim.tick_count, "name": "real_detonating_strike_at_crewed_tank", "strike": shell.duplicate(true), "vest": false, "hurt_iframes": 0})
	await _tick()
	_check(tank["burning"] and tank.get("crew_ring_ticks", 0) > 0 and p0["alive"] and p1["alive"], "actual_strike_ignites_hull_with_actionable_crew_grace")
	if no_bail:
		for _i in SimWorld.TANK_BAIL_TICKS + 2:
			await _tick()
		_check(not p0["alive"] and not p1["alive"] and p0["in_tank"] == -1 and p1["in_tank"] == -1,
			"no_bail_control_does_not_preserve_crew_after_burning_window")
		_check(not tank["alive"] and tank["occupant"] == -1, "no_bail_control_leaves_no_live_or_phantom_tank_occupant")
	else:
		_inputs(board, board)
		await _tick()
		_check(p0["alive"] and p1["alive"] and p0["in_tank"] == -1 and p1["in_tank"] == -1 and tank["occupant"] == -1,
			"both_independent_interact_edges_bail_out_living_crew")
		_check(p0["boost_ticks"] > 0 and p1["boost_ticks"] > 0, "burning_hull_bail_applies_recovery_boost_to_both_seats")
		_check(main._last_inputs.size() == 2 and main._last_inputs[0].interact and main._last_inputs[1].interact,
			"production_scene_retains_both_independent_bail_inputs")


func _stage_down(pi: int) -> void:
	var before: int = main.sim.checksum()
	main.sim.events.clear()
	main.sim._kill_player(main.sim.players[pi])
	mutations.append({"tick": main.sim.tick_count, "name": "declared_partner_knockdown", "player": pi,
		"before_checksum": before, "after_checksum": main.sim.checksum(), "player_state": main.sim.players[pi].duplicate(true)})
	_capture()
	main._consume_events()


func _rally() -> void:
	_clean_campaign()
	var p0: Dictionary = main.sim.players[0]
	var p1: Dictionary = main.sim.players[1]
	p0["x"] = 120 * Fixed.ONE
	p0["y"] = main.sim.camera_top + 250 * Fixed.ONE
	p1["x"] = 600 * Fixed.ONE
	p1["y"] = main.sim.camera_top + 300 * Fixed.ONE
	main.sim.war_chest = 500
	mutations.append({"tick": 0, "name": "remote_partner_positions_and_shared_chest", "players": main.sim.players.duplicate(true), "war_chest": 500})
	_stage_down(1)
	var idle := SimInput.new()
	var rescue := SimInput.new()
	rescue.revive = true
	_inputs(idle, idle)
	for _i in 5:
		await _tick()
	_check(not p1["alive"] and p1["x"] != p0["x"], "remote_rally_control_without_rescue_keeps_downed_partner_remote")
	var chest: int = main.sim.war_chest
	var cost: int = main.sim.revive_cost(p1)
	_inputs(rescue, idle)
	await _tick()
	_check(p1["alive"] and p1["x"] == p0["x"] and p1["y"] == p0["y"], "paid_remote_rally_restores_partner_on_both_rescuer_axes")
	_check(chest - main.sim.war_chest == cost, "paid_remote_rally_debits_exact_revive_cost")
	main.sim.war_chest = 0
	mutations.append({"tick": main.sim.tick_count, "name": "empty_chest_before_second_downed_partner", "war_chest": 0})
	_stage_down(1)
	_inputs(rescue, idle)
	await _tick()
	_check(not p1["alive"] and _event_count("revive_deny") > 0 and main.sim.war_chest == 0,
		"unaffordable_remote_rescue_control_is_denied_without_coin_creation")
	_check(p1["broke_timer"] == main.sim.broke_wait_ticks(p1) - 1, "broke_rally_arms_full_production_wait")
	_inputs(idle, idle)
	var remaining: int = p1["broke_timer"]
	for _i in remaining - 1:
		await _tick()
	_check(not p1["alive"] and p1["broke_timer"] == 1, "free_rally_control_cannot_respawn_one_tick_early")
	await _tick()
	_check(p1["alive"] and p1["y"] == main.sim._checkpoint_y() and main.sim.war_chest == 0,
		"free_rally_respawns_at_checkpoint_on_exact_expiry_without_charging")
	_check(_event_count("revive") == 2, "paid_and_free_rallies_emit_distinct_production_revive_events")


func _shop(downed: bool) -> void:
	main.start_game(true)
	var calls := 0
	while main.sim.intermission_ticks == 0 and not main._debrief and main.sim.tick_count < 18000 and calls < 72000:
		await _tick()
		calls += 1
	_check(main.sim.intermission_ticks > SimWorld.READY_HOLD_TICKS * 5 and main.sim.wave == 1,
		"normal_legal_two_seat_inputs_reach_first_shop_window")
	report["shop_entry"] = _state()
	var idle := SimInput.new()
	var ready := SimInput.new()
	ready.revive = true
	if downed:
		main.sim.war_chest = 0
		mutations.append({"tick": main.sim.tick_count, "name": "empty_chest_for_downed_shop_vote", "war_chest": 0})
		_stage_down(1)
		_inputs(ready, ready)
		for _i in SimWorld.READY_HOLD_TICKS + 5:
			await _tick()
		_check(main.sim.intermission_ticks > 0 and main.sim.wave == 1 and main.sim.ready_hold == 0 and not main.sim.players[1]["alive"],
			"downed_partner_control_returns_revive_to_rescue_and_cannot_vote_shop_closed")
		_check(_event_count("wave_ready") == 0, "downed_partner_control_never_emits_wave_ready")
		return
	_inputs(ready, idle)
	for _i in SimWorld.READY_HOLD_TICKS + 5:
		await _tick()
	_check(main.sim.intermission_ticks > 0 and main.sim.wave == 1 and main.sim.ready_hold == 0,
		"p1_only_vote_control_cannot_deploy_p2")
	_inputs(idle, ready)
	for _i in SimWorld.READY_HOLD_TICKS + 5:
		await _tick()
	_check(main.sim.intermission_ticks > 0 and main.sim.wave == 1 and main.sim.ready_hold == 0,
		"p2_only_vote_control_cannot_deploy_p1")
	_inputs(ready, ready)
	for _i in SimWorld.READY_HOLD_TICKS - 1:
		await _tick()
	_check(main.sim.intermission_ticks > 0 and main.sim.ready_hold == SimWorld.READY_HOLD_TICKS - 1,
		"unanimous_vote_control_cannot_deploy_one_tick_early")
	_inputs(idle, ready)
	await _tick()
	_check(main.sim.intermission_ticks > 0 and main.sim.ready_hold == 0, "released_party_hold_control_resets_ready_progress")
	_inputs(ready, ready)
	for _i in SimWorld.READY_HOLD_TICKS:
		await _tick()
	_check(main.sim.intermission_ticks == 0 and main.sim.wave == 2 and main.sim.ready_hold == 0,
		"unanimous_sustained_ready_hold_starts_next_wave_on_threshold_tick")
	_check(_event_count("wave_ready") == 1, "unanimous_shop_has_exactly_one_early_deploy_view_event")
	var paid_stock := 0
	for pickup in main.sim.pickups:
		if pickup.get("cost", 0) > 0:
			paid_stock += 1
	_check(paid_stock == 0, "unanimous_shop_deploy_clears_unbought_paid_stock")


func _tick() -> void:
	var tick: int = main.sim.tick_count
	var calls := 0
	while calls == 0 or (main.sim.tick_count == tick and not main._debrief and calls < 120):
		main._physics_process(1.0 / 60.0)
		physics_calls += 1
		calls += 1
		if physics_calls % 60 == 0:
			await process_frame
	if not main._debrief:
		_check(main.sim.tick_count == tick + 1, "bounded_production_physics_advances_exactly_one_tick")
	if main.sim.tick_count != tick:
		_capture()
		if main.sim.tick_count % SAMPLE_INTERVAL == 0:
			samples.append(main.sim.checksum())


func _capture() -> void:
	for ev in main.sim.events:
		if ev.get("t", "") in ["gate_open", "colossus_engage", "victory", "player_down", "revive", "revive_deny", "tank_board", "tank_crew", "tank_ignite", "tank_dismount", "wave_clear", "wave_start", "wave_ready"]:
			var retained: Dictionary = ev.duplicate(true)
			retained["tick"] = main.sim.tick_count
			events.append(retained)
		if ev.get("t", "") == "gate_open":
			gate_events.append(absi(int(ev["y"]) / SimWorld.GATE_SPACING))
	for gate in main.sim.gates:
		var gi := absi(int(gate["y"]) / SimWorld.GATE_SPACING)
		if gate["open"] and gi not in open_gates:
			open_gates.append(gi)


func _event_count(kind: String) -> int:
	var total := 0
	for ev in events:
		if ev.get("t", "") == kind:
			total += 1
	return total


func _state() -> Dictionary:
	return {"tick": main.sim.tick_count, "checksum": main.sim.checksum(), "mode": main.sim.mode,
		"camera_top": main.sim.camera_top, "gate_cursor": main.sim._gate_counter, "score": main.sim.score,
		"victory": main.sim.victory, "wiped": main.sim.wiped, "last_stand": main.sim.last_stand, "debrief": main._debrief,
		"wave": main.sim.wave, "intermission_ticks": main.sim.intermission_ticks, "ready_hold": main.sim.ready_hold,
		"war_chest": main.sim.war_chest, "players": main.sim.players.duplicate(true), "tanks": main.sim.tanks.duplicate(true)}


func _replay() -> void:
	var recorded: Replay = main._recorder
	var sim: SimWorld = recorded._new_sim()
	var replay_samples: Array[int] = []
	for frame in recorded.frames:
		var inputs: Array[SimInput] = []
		for encoded in frame:
			inputs.append(SimInput.decode(encoded))
		sim.step(inputs)
		if sim.tick_count % SAMPLE_INTERVAL == 0:
			replay_samples.append(sim.checksum())
	_check(sim.checksum() == main.sim.checksum() and sim.score == main.sim.score and replay_samples == samples,
		"chapter_inputs_replay_to_exact_samples_final_checksum_and_score")
	if main._replay_task != -1:
		WorkerThreadPool.wait_for_task_completion(main._replay_task)
		main._replay_task = -1
	var disk := Replay.load_from("user://last_run.replay")
	_check(disk != null and disk.chapter == main._arcade_chapter and disk.verify_score(main.sim.score),
		"production_saved_chapter_replay_verifies_score_and_preserves_selected_entry")
	main._recorder.save(output_path.get_basename() + ".replay")
	report["replay"] = {"frames": recorded.frames.size(), "sample_checksums": samples, "final_checksum": sim.checksum(), "score": sim.score,
		"live_checksum": main.sim.checksum(), "disk_verified": disk != null and disk.verified}


func _copy_profile() -> void:
	var target := output_path.get_basename() + "-profile"
	DirAccess.make_dir_recursive_absolute(target)
	var dir := DirAccess.open("user://")
	var copied: Array[Dictionary] = []
	for filename in dir.get_files():
		if filename.begins_with("ikari_best") or filename.ends_with(".replay"):
			var path := "user://".path_join(filename)
			var destination := target.path_join(filename)
			_check(DirAccess.copy_absolute(path, destination) == OK, "private_profile_artifact_copy_%s" % filename)
			copied.append({"file": filename, "sha256": FileAccess.get_sha256(destination)})
	var logs := DirAccess.open("user://logs")
	_check(logs != null, "private_profile_contains_engine_log_directory")
	if logs != null:
		DirAccess.make_dir_recursive_absolute(target.path_join("logs"))
		for filename in logs.get_files():
			var destination := target.path_join("logs").path_join(filename)
			_check(DirAccess.copy_absolute("user://logs".path_join(filename), destination) == OK,
				"private_engine_log_copy_%s" % filename)
			copied.append({"file": "logs/" + filename, "sha256": FileAccess.get_sha256(destination)})
	report["retained_profile"] = copied
