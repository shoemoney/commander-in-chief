extends RefCounted
## Lockstep loopback proof: two peers, two independent SimWorlds, an
## in-memory "network" with deterministic latency/jitter. If the loop is
## right, both sims stay bit-identical while only inputs cross the wire.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const SEED := 0xBADC0DE
const FRAMES := 1200


class FakeWire:
	## Deterministic lossless in-order wire with per-message latency jitter.
	var queue: Array = []   # [{deliver_at, tick, payload}]

	func send(frame: int, tick: int, payload: Array, jitter: int) -> void:
		queue.append({"deliver_at": frame + 1 + jitter, "tick": tick, "payload": payload})

	func deliver_due(frame: int, session: LockstepSession) -> void:
		for i in range(queue.size() - 1, -1, -1):
			if queue[i]["deliver_at"] <= frame:
				session.receive_remote_input(queue[i]["tick"], queue[i]["payload"])
				queue.remove_at(i)


func _run_loopback(corrupt_at_tick: int) -> Array:
	## Returns [session_a, session_b]. Optionally corrupts one in-flight
	## payload to player B at the given tick (0 = no corruption).
	var sess_a := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var sess_b := LockstepSession.new(SimWorld.new(SEED, 2), 1)
	var wire_ab := FakeWire.new()
	var wire_ba := FakeWire.new()

	for frame in FRAMES:
		# Each peer samples its local player's input from the shared torture
		# script (phase-shifted per player inside scripted_input).
		var msg_a := sess_a.submit_local_input(Determinism.scripted_input(frame, 0))
		var msg_b := sess_b.submit_local_input(Determinism.scripted_input(frame, 1))
		# Deterministic jitter schedule: 0-3 extra frames, from the frame number.
		wire_ab.send(frame, msg_a["tick"], msg_a["payload"], (frame * 7) % 4)
		var payload_b: Array = msg_b["payload"]
		if corrupt_at_tick != 0 and msg_b["tick"] == corrupt_at_tick:
			payload_b = payload_b.duplicate()
			payload_b[0] = -payload_b[0] if payload_b[0] != 0 else 128   # flipped stick
		wire_ba.send(frame, msg_b["tick"], payload_b, (frame * 3) % 4)

		wire_ba.deliver_due(frame, sess_a)
		wire_ab.deliver_due(frame, sess_b)

		# Each peer advances as far as its buffers allow this frame.
		while sess_a.try_advance():
			pass
		while sess_b.try_advance():
			pass

	# Drain: deliver everything and let both catch up fully.
	wire_ba.deliver_due(FRAMES + 10, sess_a)
	wire_ab.deliver_due(FRAMES + 10, sess_b)
	while sess_a.try_advance():
		pass
	while sess_b.try_advance():
		pass
	return [sess_a, sess_b]


func test_loopback_identity() -> void:
	var pair := _run_loopback(0)
	var a: LockstepSession = pair[0]
	var b: LockstepSession = pair[1]
	Runner.T.ok(a.sim.tick_count > 1000, "session A advanced through the wire (got %d ticks)" % a.sim.tick_count)
	Runner.T.eq(a.sim.tick_count, b.sim.tick_count, "both sims fully caught up to the same tick")
	Runner.T.eq(a.sim.checksum(), b.sim.checksum(), "final state bit-identical across the wire")
	# Exchange per-second checksums both ways: zero desyncs.
	for t in a.checksum_ticks():
		Runner.T.ok(b.verify_remote_checksum(t, a.checksum_at(t)), "B accepts A's checksum @%d" % t)
		Runner.T.ok(a.verify_remote_checksum(t, b.checksum_at(t)), "A accepts B's checksum @%d" % t)
	Runner.T.ok(not a.desynced and not b.desynced, "no desync in a clean run")


func test_stall_without_remote_input() -> void:
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	# Local inputs alone: the first `delay` ticks are pre-seeded, then lockstep
	# must refuse to outrun the missing remote inputs.
	for frame in 30:
		sess.submit_local_input(SimInput.new())
		while sess.try_advance():
			pass
	Runner.T.eq(sess.sim.tick_count, sess.input_delay, "advanced only through the pre-seeded delay window")
	Runner.T.ok(sess.stalled_ticks > 0, "stalls were counted while the wire was silent")
	# Feed the missing remote inputs; the session catches up.
	var empty := SimInput.new().encode()
	for t in range(sess.input_delay + 1, 20):
		sess.receive_remote_input(t, empty)
	while sess.try_advance():
		pass
	Runner.T.ok(sess.sim.tick_count > sess.input_delay, "resumed once remote inputs arrived")


func test_desync_detection_on_corruption() -> void:
	# Corrupt one of B's payloads on the wire to A: A simulates a different
	# input for B than B simulated for itself → checksums must diverge and
	# verify_remote_checksum must flag it within one interval.
	var pair := _run_loopback(240)
	var a: LockstepSession = pair[0]
	var b: LockstepSession = pair[1]
	Runner.T.ok(a.sim.checksum() != b.sim.checksum(), "corrupted wire produced divergent sims")
	var caught := false
	for t in a.checksum_ticks():
		if not a.verify_remote_checksum(t, b.checksum_at(t)):
			caught = true
			break
	Runner.T.ok(caught, "checksum exchange caught the desync")
	Runner.T.ok(a.desynced, "session flagged desynced")


func test_encode_decode_roundtrip() -> void:
	var inp := SimInput.new()
	inp.move_x = -128
	inp.move_y = 256
	inp.aim_x = 33
	inp.aim_y = -256
	inp.fire = true
	inp.roll = true
	inp.interact = true
	var back := SimInput.decode(inp.encode())
	Runner.T.eq(back.hash_ints(), inp.hash_ints(), "encode/decode roundtrip preserves every field")