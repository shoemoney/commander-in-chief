extends RefCounted

const Runner := preload("res://tests/run_tests.gd")
const Policy := preload("res://src/view/accessibility_policy.gd")


func _sample(policy: AccessibilityPolicy, input: SimInput) -> void:
	policy.buffer_inputs([input])


func _events(world: SimWorld, kind: String) -> int:
	var count := 0
	for event in world.events:
		if event.get("t") == kind:
			count += 1
	return count


func test_default_speed_steps_every_callback() -> void:
	var policy := Policy.new()
	var steps := 0
	for _i in 600:
		steps += int(policy.should_step(false))
	Runner.T.eq(steps, 600, "default speed advances every eligible callback")


func test_slow_speed_steps_exactly_three_of_four_callbacks() -> void:
	var policy := Policy.new()
	var steps := 0
	for i in 600:
		var step := policy.should_step(true)
		Runner.T.eq(step, i % 4 != 3, "slow mode starts immediately and skips each fourth callback")
		steps += int(step)
	Runner.T.eq(steps, 450, "600 callbacks produce exactly 450 integer simulation ticks")


func test_switching_to_default_speed_restarts_the_slow_phase() -> void:
	var policy := Policy.new()
	for _i in 3:
		policy.should_step(true)
	Runner.T.ok(policy.should_step(false), "disabling slow mode always permits the next step")
	Runner.T.ok(policy.should_step(true), "re-enabling slow mode does not inherit a skipped callback")


func test_pause_reset_discards_pending_actions_and_restarts_the_clock() -> void:
	var policy := Policy.new()
	for _i in 3:
		policy.should_step(true)
	var pressed := SimInput.new()
	pressed.grenade = true
	pressed.roll = true
	pressed.interact = true
	pressed.revive = true
	pressed.buy = 2
	_sample(policy, pressed)
	policy.reset_clock()
	_sample(policy, SimInput.new())
	Runner.T.eq(policy.take_inputs()[0].encode(), SimInput.new().encode(),
		"pause and reset discard unconsumed gameplay actions")
	Runner.T.ok(policy.should_step(true), "resume starts with an immediate simulation tick")


func test_shake_and_flash_levels_preserve_the_legacy_defaults() -> void:
	Runner.T.eq(Policy.shake_scale(10, false), 1.0, "full shake retains the existing amplitude")
	Runner.T.eq(Policy.flash_scale(10, false), 1.0, "full flash retains the existing amplitude")
	Runner.T.eq(Policy.shake_scale(10, true), 0.0, "Reduce Motion still removes camera shake")
	Runner.T.eq(Policy.flash_scale(10, true), 0.4, "Reduce Motion retains its existing dimmed flash")


func test_independent_levels_can_disable_both_effects() -> void:
	for reduced in [false, true]:
		Runner.T.eq(Policy.shake_scale(0, reduced), 0.0, "zero shake remains off with either motion preset")
		Runner.T.eq(Policy.flash_scale(0, reduced), 0.0, "zero flash remains off with either motion preset")
	Runner.T.eq(Policy.shake_scale(3, false), 0.3, "shake level is independent of flash level")
	Runner.T.eq(Policy.flash_scale(8, false), 0.8, "flash level is independent of shake level")
	Runner.T.ok(is_equal_approx(Policy.flash_scale(5, true), 0.2),
		"Reduce Motion composes with a chosen flash level")
	Runner.T.eq(Policy.shake_scale(-1, false), 0.0, "out of range shake cannot invert camera motion")
	Runner.T.eq(Policy.flash_scale(11, false), 1.0, "out of range flash cannot exceed its default amplitude")


func test_buffered_actions_use_the_latest_movement_aim_and_fire() -> void:
	var policy := Policy.new()
	var pressed := SimInput.new()
	pressed.move_x = 256
	pressed.aim_y = -256
	pressed.fire = true
	pressed.grenade = true
	_sample(policy, pressed)
	var latest := SimInput.new()
	latest.move_x = -128
	latest.move_y = 64
	latest.aim_x = 32
	latest.aim_y = 128
	_sample(policy, latest)
	var input := policy.take_inputs()[0]
	Runner.T.eq([input.move_x, input.move_y, input.aim_x, input.aim_y, input.fire],
		[-128, 64, 32, 128, false], "a skipped callback never freezes axes or the fire refusal")
	Runner.T.ok(input.grenade, "the earlier grenade pulse survives the latest sample")


func test_each_discrete_pulse_survives_a_skipped_callback_once() -> void:
	for action in Policy.EDGE_ACTIONS:
		var policy := Policy.new()
		var pressed := SimInput.new()
		pressed.set(action, true)
		_sample(policy, pressed)
		_sample(policy, SimInput.new())
		Runner.T.ok(bool(policy.take_inputs()[0].get(action)), "%s pulse reaches the next sim step" % action)
		_sample(policy, SimInput.new())
		Runner.T.ok(not bool(policy.take_inputs()[0].get(action)), "%s pulse does not repeat" % action)


func test_held_edge_actions_stay_held_without_repeat_edges() -> void:
	var policy := Policy.new()
	var world := SimWorld.new(7, 1, "campaign")
	var pressed := SimInput.new()
	pressed.grenade = true
	pressed.roll = true
	var throws := 0
	for _i in 100:
		_sample(policy, pressed)
		world.events.clear()
		world._step_players(policy.take_inputs())
		throws += _events(world, "throw")
	Runner.T.eq(throws, 1, "holding grenade through slow callbacks creates one real throw")
	Runner.T.ok(world.players[0]["grenade_prev"], "the grenade hold reaches the real sim")
	Runner.T.ok(world.players[0]["roll_prev"], "the roll hold reaches the real sim")


func test_release_and_repress_during_a_skip_create_a_new_sim_edge() -> void:
	for action in Policy.EDGE_ACTIONS:
		var policy := Policy.new()
		var pressed := SimInput.new()
		pressed.set(action, true)
		_sample(policy, pressed)
		Runner.T.ok(bool(policy.take_inputs()[0].get(action)), "%s first press is delivered" % action)
		_sample(policy, SimInput.new())
		_sample(policy, pressed)
		Runner.T.ok(not bool(policy.take_inputs()[0].get(action)), "%s release reaches the sim first" % action)
		_sample(policy, pressed)
		Runner.T.ok(bool(policy.take_inputs()[0].get(action)), "%s new press follows the release" % action)


func test_buffered_grenade_repress_reaches_the_real_sim_buffer() -> void:
	var policy := Policy.new()
	var world := SimWorld.new(7, 1, "campaign")
	var pressed := SimInput.new()
	pressed.grenade = true
	_sample(policy, pressed)
	world._step_players(policy.take_inputs())
	Runner.T.eq(_events(world, "throw"), 1, "first grenade press produces a throw")
	world.players[0]["grenade_cd"] = 0
	world.events.clear()
	_sample(policy, SimInput.new())
	_sample(policy, pressed)
	world._step_players(policy.take_inputs())
	Runner.T.eq(_events(world, "throw"), 0, "the queued release does not throw")
	_sample(policy, pressed)
	world._step_players(policy.take_inputs())
	Runner.T.eq(_events(world, "throw"), 1, "the buffered new press produces one additional throw")


func test_revive_preserves_a_short_pulse_and_continuous_hold() -> void:
	var policy := Policy.new()
	var pressed := SimInput.new()
	pressed.revive = true
	_sample(policy, pressed)
	_sample(policy, SimInput.new())
	Runner.T.ok(policy.take_inputs()[0].revive, "a revive tap survives the skipped callback")
	_sample(policy, SimInput.new())
	Runner.T.ok(not policy.take_inputs()[0].revive, "a revive tap is consumed once")
	for _i in 3:
		_sample(policy, pressed)
		Runner.T.ok(policy.take_inputs()[0].revive, "holding revive remains held on each sim step")


func test_wheel_hold_and_canceled_release_never_queue_a_purchase() -> void:
	var policy := Policy.new()
	var open := SimInput.new()
	open.buy = SimWorld.BUY_WHEEL_OPEN
	open.fire = false
	_sample(policy, open)
	Runner.T.eq(policy.take_inputs()[0].buy, SimWorld.BUY_WHEEL_OPEN, "wheel hold reaches the sim as a hold")
	_sample(policy, open)
	_sample(policy, SimInput.new())
	Runner.T.eq(policy.take_inputs()[0].buy, 0, "a canceled wheel release cannot become a purchase")


func test_open_wheel_discards_a_pending_roll() -> void:
	var policy := Policy.new()
	var pressed := SimInput.new()
	pressed.roll = true
	_sample(policy, pressed)
	var open := SimInput.new()
	open.buy = SimWorld.BUY_WHEEL_OPEN
	_sample(policy, open)
	Runner.T.ok(not policy.take_inputs()[0].roll, "wheel owns cancel and suppresses a pending dodge")
	_sample(policy, SimInput.new())
	Runner.T.ok(not policy.take_inputs()[0].roll, "closing the canceled wheel cannot replay the old dodge")


func test_wheel_purchase_survives_a_skipped_callback_once() -> void:
	var policy := Policy.new()
	var purchase := SimInput.new()
	purchase.buy = 2
	_sample(policy, purchase)
	_sample(policy, SimInput.new())
	Runner.T.eq(policy.take_inputs()[0].buy, 2, "committed wheel release survives the skip")
	_sample(policy, SimInput.new())
	Runner.T.eq(policy.take_inputs()[0].buy, 0, "committed purchase is not repeated")


func test_rapid_wheel_reopen_keeps_only_the_committed_purchase() -> void:
	var policy := Policy.new()
	var purchase := SimInput.new()
	purchase.buy = 3
	_sample(policy, purchase)
	var open := SimInput.new()
	open.buy = SimWorld.BUY_WHEEL_OPEN
	open.fire = false
	_sample(policy, open)
	var input := policy.take_inputs()[0]
	Runner.T.eq(input.buy, 3, "rapid reopen does not lose the previously committed release")
	Runner.T.ok(not input.fire, "latest wheel fire refusal remains active")
	_sample(policy, open)
	Runner.T.eq(policy.take_inputs()[0].buy, SimWorld.BUY_WHEEL_OPEN,
		"following callback returns to the current wheel hold without repeating the spend")


func test_back_to_back_purchase_edges_include_a_neutral_tick() -> void:
	var policy := Policy.new()
	var first := SimInput.new()
	first.buy = 1
	_sample(policy, first)
	Runner.T.eq(policy.take_inputs()[0].buy, 1, "first purchase reaches the sim")
	_sample(policy, SimInput.new())
	var second := SimInput.new()
	second.buy = 4
	_sample(policy, second)
	Runner.T.eq(policy.take_inputs()[0].buy, 0, "rapid second purchase first clears the sim buy edge")
	_sample(policy, SimInput.new())
	Runner.T.eq(policy.take_inputs()[0].buy, 4, "second committed purchase reaches the next sim edge")


func test_held_purchase_command_never_generates_another_spend() -> void:
	var policy := Policy.new()
	var purchase := SimInput.new()
	purchase.buy = 2
	var commands: Array[int] = []
	for _i in 8:
		_sample(policy, purchase)
		commands.append(policy.take_inputs()[0].buy)
	Runner.T.eq(commands, [2, 0, 0, 0, 0, 0, 0, 0], "a held positive buy command produces exactly one purchase")


func test_rapid_purchase_releases_keep_their_order_without_loss() -> void:
	var policy := Policy.new()
	var commands: Array[int] = []
	for kind in [1, 2, 3, 4]:
		var open := SimInput.new()
		open.buy = SimWorld.BUY_WHEEL_OPEN
		_sample(policy, open)
		var release := SimInput.new()
		release.buy = kind
		_sample(policy, release)
		var command := policy.take_inputs()[0].buy
		if command > 0 and command < SimWorld.BUY_WHEEL_OPEN:
			commands.append(command)
	for _i in 8:
		_sample(policy, SimInput.new())
		var command := policy.take_inputs()[0].buy
		if command > 0 and command < SimWorld.BUY_WHEEL_OPEN:
			commands.append(command)
	Runner.T.eq(commands, [1, 2, 3, 4], "each committed rapid release reaches one sim buy edge in original order")


func test_player_seats_have_independent_pending_actions() -> void:
	var policy := Policy.new()
	var first := SimInput.new()
	first.grenade = true
	var second := SimInput.new()
	second.roll = true
	second.buy = 6
	policy.buffer_inputs([first, second])
	policy.buffer_inputs([SimInput.new(), SimInput.new()])
	var inputs := policy.take_inputs()
	Runner.T.ok(inputs[0].grenade and not inputs[0].roll and inputs[0].buy == 0,
		"P1 keeps only P1 grenade")
	Runner.T.ok(not inputs[1].grenade and inputs[1].roll and inputs[1].buy == 6,
		"P2 keeps only P2 roll and token purchase")


func test_buffered_and_delivered_inputs_are_copied() -> void:
	var policy := Policy.new()
	var input := SimInput.new()
	input.move_x = 128
	_sample(policy, input)
	input.move_x = -256
	var delivered := policy.take_inputs()[0]
	Runner.T.eq(delivered.move_x, 128, "caller mutation cannot change a buffered sample")
	delivered.move_x = 64
	Runner.T.eq(policy.take_inputs()[0].move_x, 128, "consumer mutation cannot change the next sample")


func test_player_count_change_discards_old_pending_seat_inputs() -> void:
	var policy := Policy.new()
	var second := SimInput.new()
	second.grenade = true
	policy.buffer_inputs([SimInput.new(), second])
	policy.buffer_inputs([SimInput.new()])
	Runner.T.eq(policy.take_inputs().size(), 1, "removed P2 does not retain an output seat")
	policy.buffer_inputs([SimInput.new(), SimInput.new()])
	Runner.T.ok(not policy.take_inputs()[1].grenade, "new P2 seat does not inherit an old pending grenade")


func test_default_speed_preserves_real_sim_checksums() -> void:
	var policy := Policy.new()
	var direct := SimWorld.new(123, 1, "campaign")
	var buffered := SimWorld.new(123, 1, "campaign")
	for i in 120:
		var input := SimInput.new()
		input.move_x = 256 if i % 8 < 4 else -256
		input.aim_y = -256
		input.fire = i % 4 != 0
		input.grenade = i % 30 == 0
		input.roll = i % 20 == 0
		input.interact = i % 17 == 0
		input.revive = i % 13 == 0
		input.buy = SimWorld.BUY_WHEEL_OPEN if i % 12 < 3 else 0
		if input.buy == SimWorld.BUY_WHEEL_OPEN:
			input.roll = false
			input.fire = false
		_sample(policy, input)
		Runner.T.ok(policy.should_step(false), "default callback advances")
		var delivered := policy.take_inputs()
		Runner.T.eq(delivered[0].encode(), input.encode(), "each post-gather default input is preserved exactly")
		direct.step([input])
		buffered.step(delivered)
		Runner.T.eq(buffered.checksum(), direct.checksum(), "default policy preserves the complete real sim state")


func test_slow_speed_keeps_the_sim_tick_contract() -> void:
	var policy := Policy.new()
	var slow := SimWorld.new(123, 1, "campaign")
	var direct := SimWorld.new(123, 1, "campaign")
	var input := SimInput.new()
	input.move_y = -256
	for _i in 60:
		_sample(policy, input)
		if policy.should_step(true):
			slow.step(policy.take_inputs())
	for _i in 45:
		direct.step([input])
	Runner.T.eq(slow.tick_count, 45, "slow mode changes callback cadence while ticks keep their original meaning")
	Runner.T.eq(slow.checksum(), direct.checksum(), "45 scheduled ticks equal 45 ordinary integer sim ticks")
