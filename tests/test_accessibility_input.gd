extends RefCounted

const Runner := preload("res://tests/run_tests.gd")
const Subject := preload("res://src/view/accessibility_input.gd")


func _world() -> SimWorld:
	var world := SimWorld.new(7, 2, "campaign")
	world.camera_top = 0
	world.enemies.clear()
	world.bunkers.clear()
	world.gates.clear()
	world.rocks.clear()
	world.sandbags.clear()
	world.tanks.clear()
	world.colossus.clear()
	world.endless_boss.clear()
	world.observer.clear()
	for seat in 2:
		world.players[seat]["x"] = 320 * Fixed.ONE
		world.players[seat]["y"] = 180 * Fixed.ONE
	return world


func _enemy(world: SimWorld, offset: Vector2) -> Dictionary:
	world._spawn_enemy(int(round(320.0 + offset.x)) * Fixed.ONE,
		int(round(180.0 + offset.y)) * Fixed.ONE, false)
	return world.enemies.back()


func _direction_at(degrees: float, length: float = 1.0) -> Vector2:
	return Vector2.from_angle(deg_to_rad(degrees)) * length


func _near(actual: Vector2, expected: Vector2, message: String) -> void:
	Runner.T.ok(actual.distance_to(expected) < 0.0001, message)


func test_defaults_preserve_exact_analog_aim_and_zero() -> void:
	var subject := Subject.new()
	var world := _world()
	_enemy(world, Vector2(80, 5))
	for seat in 2:
		for requested in [Vector2.ZERO, Vector2(0.38, -0.61), Vector2(-1, 1)]:
			Runner.T.eq(subject.resolve_aim(seat, Vector2.LEFT, requested, world), requested,
				"default controls retain the resolved axes exactly")


func test_default_actions_preserve_raw_hold_and_release_for_both_seats() -> void:
	var subject := Subject.new()
	for seat in 2:
		for action in ["grenade", "roll", "interact", "revive", "buy"]:
			for pressed in [false, true, true, false, false]:
				Runner.T.eq(subject.transform_action(seat, action, pressed), pressed,
					"default %s input stays held only while its button is held" % action)


func test_each_toggle_stays_active_on_release_and_stops_on_the_second_press() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_grenade": true, "toggle_roll": true,
		"toggle_interact": true, "toggle_revive": true, "toggle_buy": true})
	for seat in 2:
		for action in ["grenade", "roll", "interact", "revive", "buy"]:
			Runner.T.ok(subject.transform_action(seat, action, true), "first %s press activates" % action)
			for tick in 10:
				Runner.T.ok(subject.transform_action(seat, action, true),
					"holding %s cannot toggle it repeatedly" % action)
			Runner.T.ok(subject.transform_action(seat, action, false), "%s stays active on release" % action)
			Runner.T.ok(not subject.transform_action(seat, action, true), "second %s press stops" % action)
			Runner.T.ok(not subject.transform_action(seat, action, false), "%s stays stopped" % action)


func test_toggle_state_is_independent_for_each_seat_and_action() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_revive": true, "toggle_grenade": true})
	Runner.T.ok(subject.transform_action(0, "revive", true), "P1 starts revive")
	Runner.T.ok(not subject.transform_action(1, "revive", false), "P1 revive never activates P2")
	Runner.T.ok(not subject.transform_action(0, "grenade", false), "revive never activates grenade")
	Runner.T.ok(subject.transform_action(1, "grenade", true), "P2 can activate another action")
	Runner.T.ok(subject.transform_action(0, "revive", false), "P2 grenade never cancels P1 revive")
	Runner.T.ok(not subject.transform_action(1, "revive", false), "P2 revive remains inactive")


func test_configure_is_idempotent_for_an_active_toggle() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_buy": true})
	Runner.T.ok(subject.transform_action(0, "buy", true), "open supplies on first press")
	subject.configure({"toggle_buy": true})
	Runner.T.ok(subject.transform_action(0, "buy", false), "unchanged settings preserve the open wheel")


func test_reset_clears_active_toggles_and_allows_a_new_press() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_revive": true, "toggle_buy": true})
	subject.transform_action(0, "revive", true)
	subject.transform_action(1, "buy", true)
	subject.reset()
	Runner.T.ok(not subject.transform_action(0, "revive", false), "a run boundary clears P1 revive")
	Runner.T.ok(not subject.transform_action(1, "buy", false), "a menu boundary clears P2 wheel")
	Runner.T.ok(subject.transform_action(0, "revive", true), "a fresh press can activate again")


func test_restoring_hold_mode_does_not_keep_a_toggle_active() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_grenade": true})
	subject.transform_action(0, "grenade", true)
	subject.configure({})
	Runner.T.ok(not subject.transform_action(0, "grenade", false), "default hold mode cannot inherit a toggle")
	Runner.T.ok(subject.transform_action(0, "grenade", true), "hold mode still responds to a new press")


func test_unknown_actions_and_absent_seats_pass_through() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_revive": true})
	Runner.T.ok(subject.transform_action(0, "pause", true), "the helper never latches menu actions")
	Runner.T.ok(not subject.transform_action(0, "pause", false), "the helper leaves menu releases intact")
	Runner.T.ok(subject.transform_action(2, "revive", true), "an unsupported seat retains its raw input")
	Runner.T.ok(not subject.transform_action(-1, "revive", false), "an absent seat does not borrow P1 state")


func test_canceling_the_supply_wheel_allows_the_next_genuine_press_to_reopen() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_buy": true, "toggle_revive": true})
	subject.transform_action(0, "buy", true)
	subject.transform_action(0, "buy", false)
	subject.transform_action(1, "revive", true)
	subject.cancel_action(0, "buy")
	Runner.T.ok(not subject.transform_action(0, "buy", false), "Cancel clears the supply hold")
	Runner.T.ok(subject.transform_action(0, "buy", true), "the next supply press reopens immediately")
	Runner.T.ok(subject.transform_action(1, "revive", false), "Cancel does not clear the partner's revive")


func test_canceling_a_held_toggle_does_not_invent_another_rising_edge() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_buy": true})
	subject.transform_action(0, "buy", true)
	subject.cancel_action(0, "buy")
	Runner.T.ok(not subject.transform_action(0, "buy", true), "Cancel retains the current raw press history")
	Runner.T.ok(not subject.transform_action(0, "buy", false), "releasing after Cancel stays inactive")
	Runner.T.ok(subject.transform_action(0, "buy", true), "a new press activates after release")


func test_held_menu_confirmation_is_suppressed_until_release_for_each_toggled_action() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_grenade": true, "toggle_roll": true,
		"toggle_interact": true, "toggle_revive": true, "toggle_buy": true})
	for seat in 2:
		for action in ["grenade", "roll", "interact", "revive", "buy"]:
			subject.prime_action(seat, action, true)
			for tick in 5:
				Runner.T.ok(not subject.transform_action(seat, action, true),
					"held menu confirmation cannot activate %s on Resume" % action)
			Runner.T.ok(not subject.transform_action(seat, action, false),
				"the confirmation release is consumed")
			Runner.T.ok(subject.transform_action(seat, action, true),
				"the first new %s press after release activates normally" % action)


func test_neutral_boundary_priming_does_not_swallow_the_first_gameplay_press() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_revive": true})
	subject.reset()
	subject.prime_action(0, "revive", false)
	Runner.T.ok(subject.transform_action(0, "revive", true), "a neutral boundary permits a new first press")
	Runner.T.ok(subject.transform_action(0, "revive", false), "the new revive remains toggled after release")


func test_confirmation_suppression_is_independent_of_other_actions_and_seats() -> void:
	var subject := Subject.new()
	subject.configure({"toggle_revive": true, "toggle_grenade": true})
	subject.prime_action(0, "revive", true)
	Runner.T.ok(subject.transform_action(1, "revive", true), "P1 held confirmation cannot suppress P2 revive")
	Runner.T.ok(subject.transform_action(0, "grenade", true), "P1 grenade remains available immediately")
	Runner.T.ok(not subject.transform_action(0, "revive", true), "P1 confirmation stays suppressed")


func test_single_stick_acquires_the_nearest_visible_hostile() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(120, 0))
	_enemy(world, Vector2(0, -80))
	_near(subject.resolve_aim(0, Vector2.LEFT, Vector2.ZERO, world), Vector2.UP,
		"movement-only input acquires the nearer enemy without an aim stick")


func test_single_stick_respects_a_deliberate_manual_aim_override() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(0, -80))
	var manual := Vector2(0.75, 0.1)
	Runner.T.eq(subject.resolve_aim(0, Vector2.LEFT, manual, world), manual,
		"an explicit aim command overrides automatic acquisition")


func test_single_stick_settings_are_seat_specific() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p2": true})
	var world := _world()
	_enemy(world, Vector2(100, 0))
	Runner.T.eq(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.ZERO,
		"P2 single-stick does not change P1 controls")
	_near(subject.resolve_aim(1, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"P2 receives its own automatic aim")


func test_single_stick_empty_scene_uses_movement_then_persisted_facing() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_near(subject.resolve_aim(0, Vector2(0.3, 0.4), Vector2.ZERO, world), Vector2(0.6, 0.8),
		"without targets, movement gives a deliberate heading")
	world.players[0]["aim_x"] = Fixed.ONE
	world.players[0]["aim_y"] = 0
	_near(subject.resolve_aim(0, Vector2.ZERO, Vector2.ZERO, world), Vector2.RIGHT,
		"stationary single-stick retains the sim's last facing")


func test_dead_offscreen_and_submerged_targets_never_take_automatic_aim() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	var dead := _enemy(world, Vector2(1, 0))
	dead["alive"] = false
	var submerged := _enemy(world, Vector2(2, 0))
	submerged["submerged"] = true
	var above := _enemy(world, Vector2(3, -181))
	above["y"] = -Fixed.ONE
	var outside_x := _enemy(world, Vector2(4, 0))
	outside_x["x"] = -Fixed.ONE
	_enemy(world, Vector2(0, 90))
	_near(subject.resolve_aim(0, Vector2.LEFT, Vector2.ZERO, world), Vector2.DOWN,
		"only a living, visible, surfaced target can acquire aim")


func test_auto_range_and_target_death_release_acquisition() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	world.players[0]["x"] = 100 * Fixed.ONE
	var enemy := _enemy(world, Vector2(100, 0))
	enemy["x"] = 420 * Fixed.ONE
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"a target exactly 320 pixels away is eligible")
	enemy["x"] = 421 * Fixed.ONE
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a target beyond 320 pixels does not acquire aim")
	enemy["x"] = 300 * Fixed.ONE
	enemy["alive"] = false
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a target dying releases automatic acquisition")


func test_rescue_pilots_cannot_attract_automatic_or_assisted_fire() -> void:
	var world := _world()
	var pilot := _enemy(world, Vector2(60, 10))
	pilot["kind"] = "pilot"
	var auto := Subject.new()
	auto.configure({"single_stick_p1": true})
	var high := Subject.new()
	high.configure({"aim_assist": 2})
	_near(auto.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a surfaced rescue pilot is a friendly objective, not an automatic target")
	Runner.T.eq(high.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world), Vector2.RIGHT,
		"aim assistance cannot steer the player into shooting a rescue pilot")
	_enemy(world, Vector2(120, 0))
	_near(auto.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"a real hostile can still acquire aim when a nearer pilot is present")


func test_equal_distance_targets_use_position_order_independent_of_spawn_order() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(60, -80))
	_enemy(world, Vector2(-60, -80))
	var first := subject.resolve_aim(0, Vector2.DOWN, Vector2.ZERO, world)
	world.enemies.reverse()
	_near(first, Vector2(-0.6, -0.8), "equal-distance targets use the leftmost position")
	_near(subject.resolve_aim(0, Vector2.DOWN, Vector2.ZERO, world), first,
		"changing entity order cannot change an equal-distance choice")


func test_low_and_high_assistance_have_distinct_strength_without_changing_magnitude() -> void:
	var world := _world()
	_enemy(world, Vector2(100, 15))
	var off := Subject.new()
	var low := Subject.new()
	var high := Subject.new()
	low.configure({"aim_assist": 1})
	high.configure({"aim_assist": 2})
	var requested := Vector2(0.6, 0)
	var low_aim := low.resolve_aim(0, Vector2.ZERO, requested, world)
	var high_aim := high.resolve_aim(0, Vector2.ZERO, requested, world)
	Runner.T.eq(off.resolve_aim(0, Vector2.ZERO, requested, world), requested, "Off makes no correction")
	Runner.T.ok(low_aim.angle() > 0.0, "Low nudges aim toward a target inside its cone")
	Runner.T.ok(high_aim.angle() > low_aim.angle(), "High corrects more than Low")
	Runner.T.ok(high_aim.angle() < Vector2(100, 15).angle(), "assistance does not replace deliberate aim")
	Runner.T.ok(absf(low_aim.length() - 0.6) < 0.0001, "Low preserves analog magnitude")
	Runner.T.ok(absf(high_aim.length() - 0.6) < 0.0001, "High preserves analog magnitude")


func test_assist_cones_reject_targets_outside_the_selected_tier() -> void:
	var world := _world()
	_enemy(world, _direction_at(18, 200))
	var low := Subject.new()
	var high := Subject.new()
	low.configure({"aim_assist": 1})
	high.configure({"aim_assist": 2})
	Runner.T.eq(low.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world), Vector2.RIGHT,
		"18-degree target is outside the Low 12-degree cone")
	Runner.T.ok(high.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world).y > 0.0,
		"18-degree target is inside the High 24-degree cone")
	world.enemies.clear()
	_enemy(world, _direction_at(25, 200))
	Runner.T.eq(high.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world), Vector2.RIGHT,
		"25-degree target is outside High and leaves aim untouched")


func test_assist_range_rejects_a_target_that_only_high_can_reach() -> void:
	var world := _world()
	_enemy(world, Vector2(280, 10))
	var low := Subject.new()
	var high := Subject.new()
	low.configure({"aim_assist": 1})
	high.configure({"aim_assist": 2})
	Runner.T.eq(low.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world), Vector2.RIGHT,
		"Low leaves a target beyond 240 pixels alone")
	Runner.T.ok(high.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world).y > 0.0,
		"High reaches the same target inside 320 pixels")


func test_assistance_never_invents_aim_when_the_aim_stick_is_released() -> void:
	var subject := Subject.new()
	subject.configure({"aim_assist": 2})
	var world := _world()
	_enemy(world, Vector2(100, 0))
	Runner.T.eq(subject.resolve_aim(0, Vector2.LEFT, Vector2.ZERO, world), Vector2.ZERO,
		"twin-stick release still lets the sim persist its current aim")


func test_cover_blocks_acquisition_but_grass_does_not() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(120, 0))
	world.rocks.append({"x": 380 * Fixed.ONE, "y": 180 * Fixed.ONE, "kind": 0})
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a solid rock blocks the direct fire lane")
	world.rocks[0]["kind"] = 1
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"non-solid grass does not block bullets or target assistance")
	world.rocks.clear()
	world.bunkers.append(world._make_bunker(370 * Fixed.ONE, 165 * Fixed.ONE))
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a live bunker blocks the lane and is not an automatic MG target")
	world.bunkers[0]["alive"] = false
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"destroying the bunker restores the firing lane")


func test_cover_selection_skips_a_blocked_near_enemy_for_a_clear_far_enemy() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(100, 0))
	_enemy(world, Vector2(0, -120))
	world.sandbags.append({"x": 370 * Fixed.ONE, "y": 180 * Fixed.ONE, "vertical": 1})
	_near(subject.resolve_aim(0, Vector2.LEFT, Vector2.ZERO, world), Vector2.UP,
		"a nearer target behind cover cannot steal automatic aim")


func test_tiered_assistance_leaves_an_occluded_target_alone() -> void:
	var subject := Subject.new()
	subject.configure({"aim_assist": 2})
	var world := _world()
	_enemy(world, Vector2(120, 10))
	world.sandbags.append({"x": 380 * Fixed.ONE, "y": 185 * Fixed.ONE, "vertical": 1})
	Runner.T.eq(subject.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world), Vector2.RIGHT,
		"High cannot pull deliberate aim toward a target behind cover")
	world.sandbags.clear()
	Runner.T.ok(subject.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, world).y > 0.0,
		"removing the same obstruction restores High assistance")


func test_empty_tanks_and_smoldering_hulks_block_fire_but_occupied_tanks_do_not() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	_enemy(world, Vector2(120, 0))
	world.tanks.append({"x": 380 * Fixed.ONE, "y": 180 * Fixed.ONE,
		"alive": true, "occupant": -1, "burn_ticks": 0})
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"an empty tank blocks the fire lane and never becomes a hostile target")
	world.tanks[0]["occupant"] = 1
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"an occupied friendly tank does not eat bullets")
	world.tanks[0]["alive"] = false
	world.tanks[0]["burn_ticks"] = 100
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a smoldering hulk blocks the lane even after its crew leaves")
	world.tanks[0]["burn_ticks"] = 0
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"an expired hulk no longer blocks fire")


func test_shield_fronts_are_excluded_until_rend_or_a_rear_angle_can_damage_them() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	var shield := _enemy(world, Vector2(100, 0))
	shield["kind"] = "shield"
	shield["face_x"] = -Fixed.ONE
	shield["face_y"] = 0
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"automatic MG aim does not acquire an invulnerable shield front")
	world.players[0]["rend_ticks"] = 30
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"Rend makes the shield front a valid bullet target")
	world.players[0]["rend_ticks"] = 0
	shield["face_x"] = Fixed.ONE
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"the exposed rear is a valid target without Rend")


func test_colossus_is_acquired_only_during_its_real_core_window() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	world.colossus = {"x": 420 * Fixed.ONE, "y": 180 * Fixed.ONE, "alive": true, "core_open": 0}
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"sealed Colossus armor does not attract automatic MG fire")
	world.colossus["core_open"] = 1
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"the actual open core is an automatic aim target")
	world.colossus["alive"] = false
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"a defeated Colossus cannot retain acquisition")


func test_gunship_target_uses_the_real_endless_flyin_position() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	world.endless_boss = {"x": 300 * Fixed.ONE, "gate_y": 180 * Fixed.ONE,
		"alive": true, "phase_t": -SimWorld.BOSS_FLYIN_TICKS / 2}
	var offset: Array = SimWorld.boss_flyin_offset(world.endless_boss["phase_t"])
	var expected := Vector2(float(300 * Fixed.ONE + int(offset[0])) / Fixed.ONE - 320.0,
		float(180 * Fixed.ONE - SimWorld.BOSS_Y_OFFSET + int(offset[1])) / Fixed.ONE - 180.0).normalized()
	_near(subject.resolve_aim(0, Vector2.LEFT, Vector2.ZERO, world), expected,
		"automatic aim tracks the visible fly-in disc rather than its later arrival point")


func test_campaign_gunships_stop_acquiring_when_their_gate_opens() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true})
	var world := _world()
	world.gates.append({"open": false, "boss": {"x": 420 * Fixed.ONE,
		"gate_y": 220 * Fixed.ONE, "alive": true}})
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.RIGHT,
		"a live gunship at a closed gate acquires aim")
	world.gates[0]["open"] = true
	_near(subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world), Vector2.UP,
		"an opened gate releases its gunship target")


func test_classic_aim_snaps_to_twelve_directions_and_preserves_magnitude() -> void:
	var subject := Subject.new()
	subject.configure({"classic_aim_p1": true})
	for detent in 12:
		var degrees := float(detent * 30)
		_near(subject.resolve_aim(0, Vector2.ZERO, _direction_at(degrees + 14, 0.7), null),
			_direction_at(degrees, 0.7), "Classic retains each of the twelve 30-degree detents")
	_near(subject.resolve_aim(0, Vector2.ZERO, _direction_at(16), null), _direction_at(30),
		"crossing the half-step boundary selects the next detent")
	Runner.T.eq(subject.resolve_aim(1, Vector2.ZERO, _direction_at(16), null), _direction_at(16),
		"P1 Classic does not quantize P2")


func test_detent_cue_is_one_shot_per_change_and_independent_per_seat() -> void:
	var subject := Subject.new()
	subject.configure({"classic_aim_p1": true, "classic_aim_p2": true})
	subject.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, null)
	subject.resolve_aim(1, Vector2.ZERO, Vector2.RIGHT, null)
	Runner.T.ok(not subject.consume_detent_change(0), "initial aim primes without a false change cue")
	subject.resolve_aim(0, Vector2.ZERO, _direction_at(16), null)
	Runner.T.ok(subject.consume_detent_change(0), "crossing a detent exposes its change cue")
	Runner.T.ok(not subject.consume_detent_change(0), "reading the cue consumes it once")
	Runner.T.ok(not subject.consume_detent_change(1), "P1 rotation cannot vibrate P2")
	subject.resolve_aim(0, Vector2.ZERO, _direction_at(29), null)
	Runner.T.ok(not subject.consume_detent_change(0), "motion inside one detent does not cue repeatedly")
	subject.resolve_aim(1, Vector2.ZERO, Vector2.UP, null)
	Runner.T.ok(subject.consume_detent_change(1), "P2 exposes its own independent detent change")


func test_reset_clears_detent_cues_and_preserves_zero_aim() -> void:
	var subject := Subject.new()
	subject.configure({"classic_aim_p1": true})
	subject.resolve_aim(0, Vector2.ZERO, Vector2.RIGHT, null)
	subject.resolve_aim(0, Vector2.ZERO, Vector2.DOWN, null)
	subject.reset()
	Runner.T.ok(not subject.consume_detent_change(0), "a menu boundary clears pending haptic cues")
	Runner.T.eq(subject.resolve_aim(0, Vector2.ZERO, Vector2.ZERO, null), Vector2.ZERO,
		"a neutral stick leaves the existing aim-persist contract intact")
	subject.resolve_aim(0, Vector2.ZERO, Vector2.UP, null)
	Runner.T.ok(not subject.consume_detent_change(0), "the next run primes its own first detent")


func test_resolving_assisted_inputs_never_mutates_simulation_state() -> void:
	var subject := Subject.new()
	subject.configure({"single_stick_p1": true, "classic_aim_p1": true, "aim_assist": 2})
	var world := _world()
	_enemy(world, Vector2(80, 20))
	var before: int = world.checksum()
	for tick in 30:
		subject.resolve_aim(0, Vector2.UP, Vector2.ZERO, world)
		subject.resolve_aim(1, Vector2.LEFT, Vector2.RIGHT, world)
	Runner.T.eq(world.checksum(), before, "view-side assistance cannot change deterministic sim state")
