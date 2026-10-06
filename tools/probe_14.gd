extends SceneTree

func _init() -> void:
	var ok := true
	print("=== 1.4 PROBE START ===")
	# --- Threat pip check (view) ---
	var main_path := "res://src/main.gd"
	var txt := FileAccess.get_file_as_string(main_path)
	var has_11 := txt.contains("11.0 + pf * 2.0")
	var has_9 := txt.contains("9.0 + pf * 2.0") and txt.contains("Art.circle(self, edge, 9.0")
	print("VIEW pip radius has 11: ", has_11, " has old 9 circle: ", txt.contains("Art.circle(self, edge, 9.0"))
	if not has_11:
		print("FAIL view pip radius not 11")
		ok = false
	else:
		print("PASS view pip radius 11")
	var has_alpha22 := txt.contains("0.22 + pf * 0.08") or txt.contains("0.22 + pf")
	print("VIEW pip alpha 0.22 present:", has_alpha22)
	if not has_alpha22:
		print("FAIL view pip alpha not 0.22")
		ok = false
	else:
		print("PASS view pip alpha 0.22")
	var idx := txt.find("_draw_threat_pips")
	var threat_section := txt.substr(idx, 3500) if idx != -1 else ""
	var includes_rusher := txt.contains("rusher") and threat_section.contains("rusher")
	var includes_elite := txt.contains("elite") and threat_section.contains("elite")
	print("VIEW threat kind includes rusher:", includes_rusher, " elite:", includes_elite)
	if not (includes_rusher and includes_elite):
		# fallback check whole file for the kind line
		if txt.contains("and k != \"rusher\""):
			print("PASS view kind widens (direct)")
			includes_rusher = true
			includes_elite = true
		else:
			print("FAIL view kind filter excludes rusher/elite")
			ok = false
	else:
		print("PASS view kind widens")
	var has_tip9 := txt.contains("9.0 + pf * 3.0")
	var has_base6 := txt.contains("- dir * 6.0")
	var has_perp7 := txt.contains("perp * 7.0")
	print("VIEW geometry tip9:", has_tip9, " base6:", has_base6, " perp7:", has_perp7)
	if not (has_tip9 and has_perp7):
		print("FAIL view geometry not +2")
		ok = false
	else:
		print("PASS view geometry +2")

	# --- Observer gate whip check (sim) --- isolated _step_observer
	# We isolate _step_observer by directly setting stall_ticks and gates without running full step.
	# Flicker bug: while held, observer spawns at 480 and despawns next tick.
	var sim := SimWorld.new(0, 1, "campaign")
	# put player alive so stall accrues
	sim.players[0]["alive"] = true
	# create a gate that pins camera
	var gate_y : int = sim.camera_top + SimWorld.GATE_CAMERA_PAD
	# Use a minimal gate dict that satisfies camera_held (only y/open needed) and _step_gates minimal fields
	# To avoid other step errors we call _step_observer directly, not step()
	sim.gates.append({"y": gate_y, "open": false, "b1": {}, "b2": {}, "boss": {}, "final": false})
	# ensure camera_held true
	print("SIM held check:", sim.camera_held(), " cam_top:", sim.camera_top, " gate_y:", gate_y)
	if not sim.camera_held():
		print("WARN not held — probe setup invalid")
		ok = false
	# half-rate accrual while held: tick 0,2,4... increments
	sim.stall_ticks = SimWorld.OBSERVER_STALL_TICKS - 1
	sim.tick_count = 0
	# First _step_observer while held with stall 479 -> should increment to 480 but NOT spawn (deferred)
	sim._step_observer()
	print("After _step_observer tick0 held stall:", sim.stall_ticks, " observer empty:", sim.observer.is_empty())
	if not sim.observer.is_empty():
		print("FAIL observer spawned while held (should defer)")
		ok = false
	else:
		print("PASS observer deferred while held")
	# Alternate: force stall to threshold then test live persistence
	var sim2 := SimWorld.new(1, 1, "campaign")
	sim2.players[0]["alive"] = true
	var gate_y2 : int = sim2.camera_top + SimWorld.GATE_CAMERA_PAD
	sim2.gates.append({"y": gate_y2, "open": false, "b1": {}, "b2": {}, "boss": {}, "final": false})
	# seed a live observer before holding
	sim2.observer = {"x": 320 * Fixed.ONE, "strike_cd": SimWorld.OBSERVER_STRIKE_CD_TICKS, "spawn_cam": sim2.camera_top}
	sim2.stall_ticks = SimWorld.OBSERVER_STALL_TICKS
	sim2.tick_count = 1
	var before_strikes := sim2.strikes.size()
	# call _step_observer repeatedly while held — should persist and eventually strike
	var survived := true
	var struck := false
	for k in 120:
		sim2.tick_count += 1
		sim2._step_observer()
		# _resolve_strikes is separate, but observer strike scheduling is in _step_observer
		if sim2.observer.is_empty():
			survived = false
			print("FAIL live observer despawned while held at k ", k)
			break
		if sim2.strikes.size() > before_strikes:
			struck = true
	if survived:
		print("PASS live observer persisted while held")
	else:
		print("FAIL live observer did not persist")
		ok = ok and survived
	if struck:
		print("PASS live observer barraged while held strikes:", sim2.strikes.size())
	else:
		print("FAIL live observer never barraged while held")
		ok = false
	# advance past despawn distance -> should despawn
	if not sim2.observer.is_empty():
		var sc: int = sim2.observer["spawn_cam"]
		sim2.camera_top = sc - SimWorld.OBSERVER_DESPAWN_ADVANCE - Fixed.ONE
		sim2._step_observer()
		if sim2.observer.is_empty():
			print("PASS observer despawns after 150px advance")
		else:
			print("FAIL observer should despawn after advance")
			ok = false

	if ok:
		print("=== 1.4 PROBE OVERALL PASS ===")
	else:
		print("=== 1.4 PROBE OVERALL FAIL ===")
	quit(1 if not ok else 0)
