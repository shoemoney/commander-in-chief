extends RefCounted
## Lockstep loopback proof: two peers, two independent SimWorlds, an
## in-memory "network" with deterministic latency/jitter. If the loop is
## right, both sims stay bit-identical while only inputs cross the wire.
##
## The wire is DELIBERATELY hostile — it drops, duplicates, reorders and
## corrupts — because a lossless in-order FakeWire can only prove the happy
## path, and the happy path was never what broke real netcode.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const SEED := 0xBADC0DE
const FRAMES := 1200


class FakeWire:
	## Deterministic in-order-ish wire with per-message latency jitter, and
	## optional loss / duplication on a fixed schedule (no RNG — the failure
	## pattern must be reproducible).
	var queue: Array = []   # [{deliver_at, tick, payload}]
	var drop_every: int = 0   # drop every Nth datagram (0 = lossless)
	var dup_every: int = 0    # deliver every Nth datagram twice
	var sent_count: int = 0
	var dropped: int = 0

	func send(frame: int, tick: int, payload: Array, jitter: int) -> void:
		sent_count += 1
		if drop_every > 0 and sent_count % drop_every == 0:
			dropped += 1
			return
		queue.append({"deliver_at": frame + 1 + jitter, "tick": tick, "payload": payload})
		if dup_every > 0 and sent_count % dup_every == 0:
			# A duplicate arriving LATER than the original — the case that used
			# to overwrite a still-buffered future tick.
			queue.append({"deliver_at": frame + 2 + jitter, "tick": tick, "payload": payload})

	func deliver_due(frame: int, session: LockstepSession) -> void:
		for i in range(queue.size() - 1, -1, -1):
			if queue[i]["deliver_at"] <= frame:
				session.receive_remote_input(queue[i]["tick"], queue[i]["payload"])
				queue.remove_at(i)


static func _corrupt_window(tick: int, window: Array, target: int) -> Array:
	## Flip the stick on the copy of `target` inside a redundancy window,
	## leaving the rest untouched. Every window carrying `target` gets the
	## same treatment, so first-write-wins can't accidentally heal the
	## corruption with a clean re-send.
	var first: int = tick - window.size() + 1
	if target < first or target > tick:
		return window
	var out := window.duplicate()
	var p: Array = (out[target - first] as Array).duplicate()
	p[0] = -p[0] if p[0] != 0 else 128
	out[target - first] = p
	return out


func _run_loopback(opts: Dictionary = {}) -> Array:
	## Returns [session_a, session_b]. Options:
	##   corrupt_at_tick — corrupt B's input for that tick on the wire to A
	##   drop_every / dup_every — wire loss / duplication schedule
	##   redundancy — false ships only the newest payload (pre-hardening behavior)
	var corrupt_at_tick: int = opts.get("corrupt_at_tick", 0)
	var redundancy: bool = opts.get("redundancy", true)
	var sess_a := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var sess_b := LockstepSession.new(SimWorld.new(SEED, 2), 1)
	var wire_ab := FakeWire.new()
	var wire_ba := FakeWire.new()
	wire_ab.drop_every = opts.get("drop_every", 0)
	wire_ba.drop_every = opts.get("drop_every", 0)
	wire_ab.dup_every = opts.get("dup_every", 0)
	wire_ba.dup_every = opts.get("dup_every", 0)

	for frame in FRAMES:
		# Each peer samples its local player's input from the shared torture
		# script (phase-shifted per player inside scripted_input).
		var msg_a := sess_a.submit_local_input(Determinism.scripted_input(frame, 0))
		var msg_b := sess_b.submit_local_input(Determinism.scripted_input(frame, 1))
		var out_a: Array = msg_a["payloads"] if redundancy else msg_a["payload"]
		var out_b: Array = msg_b["payloads"] if redundancy else msg_b["payload"]
		if corrupt_at_tick != 0:
			if redundancy:
				out_b = _corrupt_window(msg_b["tick"], out_b, corrupt_at_tick)
			elif msg_b["tick"] == corrupt_at_tick:
				out_b = out_b.duplicate()
				out_b[0] = -out_b[0] if out_b[0] != 0 else 128
		# Deterministic jitter schedule: 0-3 extra frames, from the frame number.
		wire_ab.send(frame, msg_a["tick"], out_a, (frame * 7) % 4)
		wire_ba.send(frame, msg_b["tick"], out_b, (frame * 3) % 4)

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
	var pair := _run_loopback()
	var a: LockstepSession = pair[0]
	var b: LockstepSession = pair[1]
	Runner.T.ok(a.sim.tick_count > 1000, "session A advanced through the wire (got %d ticks)" % a.sim.tick_count)
	Runner.T.eq(a.sim.tick_count, b.sim.tick_count, "both sims fully caught up to the same tick")
	Runner.T.eq(a.sim.checksum(), b.sim.checksum(), "final state bit-identical across the wire")
	# Exchange per-second checksums both ways: zero desyncs.
	for t in a.checksum_ticks():
		Runner.T.eq(b.compare_remote_checksum(t, a.checksum_at(t)), LockstepSession.CMP_MATCH,
			"B matches A's checksum @%d" % t)
		Runner.T.eq(a.compare_remote_checksum(t, b.checksum_at(t)), LockstepSession.CMP_MATCH,
			"A matches B's checksum @%d" % t)
	Runner.T.ok(not a.desynced and not b.desynced, "no desync in a clean run")


func test_survives_packet_loss() -> void:
	# THE regression this hardening exists for: with no redundancy window one
	# lost datagram stalls the session forever (no ack, no resend, no timeout).
	var lossy := _run_loopback({"drop_every": 3})
	var a: LockstepSession = lossy[0]
	var b: LockstepSession = lossy[1]
	Runner.T.ok(a.sim.tick_count > 1000, "1-in-3 packet loss survived — A still advanced (%d ticks)" % a.sim.tick_count)
	Runner.T.eq(a.sim.tick_count, b.sim.tick_count, "both peers caught up despite loss")
	Runner.T.eq(a.sim.checksum(), b.sim.checksum(), "lossy wire still produced bit-identical sims")
	Runner.T.ok(not a.desynced and not b.desynced, "loss is not a desync")
	# Control: the SAME loss schedule without the redundancy window wedges the
	# session at the first drop. If this ever passes, the test above proves nothing.
	var bare := _run_loopback({"drop_every": 3, "redundancy": false})
	var bare_a: LockstepSession = bare[0]
	Runner.T.ok(bare_a.sim.tick_count < 10,
		"control: a single-payload send stalls forever on the first drop (got %d ticks)" % bare_a.sim.tick_count)
	Runner.T.ok(bare_a.stalled_ticks > 100, "control: the wedged session counted stalls")


func test_buffers_do_not_leak_under_redundancy() -> void:
	# Re-sent inputs for ticks the sim already consumed must be dropped, not
	# re-inserted: try_advance erases spent ticks, so a re-insert is a permanent
	# leak — and a redundancy window re-sends every tick 8 times.
	var pair := _run_loopback({"drop_every": 3, "dup_every": 5})
	var a: LockstepSession = pair[0]
	Runner.T.ok(a._buffers[0].size() < 64, "local buffer stayed flat (%d entries)" % a._buffers[0].size())
	Runner.T.ok(a._buffers[1].size() < 64, "remote buffer stayed flat (%d entries)" % a._buffers[1].size())
	Runner.T.ok(a.rejected["past"] > 1000, "re-sends of consumed ticks were rejected, not buffered")


func test_duplicate_and_reorder_are_idempotent() -> void:
	# End-to-end: a wire that duplicates every 5th datagram must not change a thing.
	var pair := _run_loopback({"dup_every": 5})
	var a: LockstepSession = pair[0]
	var b: LockstepSession = pair[1]
	Runner.T.eq(a.sim.checksum(), b.sim.checksum(), "duplicated datagrams left both sims identical")
	Runner.T.ok(not a.desynced, "duplicates are not a desync")


func test_first_write_wins_on_conflicting_duplicate() -> void:
	# A duplicate for a still-buffered FUTURE tick used to overwrite. If the two
	# copies differ (corruption, or a peer that re-encoded), we would step an
	# input the peer never stepped — an instant desync with no way back.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var t := sess.input_delay + 4
	var first := [10, 20, 30, 40, 1]
	var second := [-99, 0, 0, 0, 0]
	sess.receive_remote_input(t, first)
	sess.receive_remote_input(t, second)
	Runner.T.eq(sess._buffers[1][t], first, "the first copy of a tick wins; the conflicting resend is dropped")
	Runner.T.eq(sess.rejected["duplicate"], 1, "the conflicting duplicate was counted, not applied")
	# Same rule inside a batch: an overlapping window cannot rewrite history.
	sess.receive_remote_input(t + 2, [[1, 1, 1, 1, 0], [2, 2, 2, 2, 0], [3, 3, 3, 3, 0]])
	Runner.T.eq(sess._buffers[1][t], first, "overlapping redundancy window kept the first copy of tick %d" % t)
	Runner.T.eq(sess._buffers[1][t + 1], [2, 2, 2, 2, 0], "the window's NEW ticks were still accepted")
	Runner.T.eq(sess._buffers[1][t + 2], [3, 3, 3, 3, 0], "the window's newest tick landed on `tick`")


func test_batch_maps_ticks_from_the_end() -> void:
	# The wire's tick field names the LAST payload in the window; earlier ones
	# walk backwards from it. Off-by-one here would silently mis-attribute
	# every input — a desync that only shows up under loss.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var last := sess.input_delay + 8
	var window: Array = []
	for i in 4:
		window.append([i, 0, 0, 0, 0])
	sess.receive_remote_input(last, window)
	for i in 4:
		Runner.T.eq(sess._buffers[1][last - 3 + i], window[i], "window slot %d landed on tick %d" % [i, last - 3 + i])


func test_malformed_wire_input_is_rejected() -> void:
	# TRUST BOUNDARY: everything here is bytes from another machine. replay.gd
	# already gates the same wire format; lockstep had no gate at all.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var base := sess._buffers[1].size()
	var t := sess.input_delay + 2
	sess.receive_remote_input(t, [])                       # empty
	sess.receive_remote_input(t, [1, 2, 3])                # short — decode() would index past the end
	sess.receive_remote_input(t, [1, 2, 3, 4])             # one field short
	sess.receive_remote_input(t, [1, 2, 3, 4, {"a": 1}])   # well-sized, non-numeric field
	sess.receive_remote_input(t, [[1, 2, 3]])              # short payload inside a batch
	Runner.T.eq(sess._buffers[1].size(), base, "no malformed payload reached the buffer")
	Runner.T.eq(sess.rejected["malformed"], 5, "every malformed payload was counted")
	# Past ticks: already consumed (or pre-seeded), and re-inserting leaks them.
	sess.receive_remote_input(0, [0, 0, 0, 0, 0])
	sess.receive_remote_input(-5, [0, 0, 0, 0, 0])
	Runner.T.eq(sess.rejected["past"], 2, "ticks at or behind the sim were rejected")
	# Far future: a flood or garbage, never a peer that is merely early.
	sess.receive_remote_input(LockstepSession.MAX_LEAD + 1, [0, 0, 0, 0, 0])
	sess.receive_remote_input(1 << 40, [0, 0, 0, 0, 0])
	Runner.T.eq(sess.rejected["far_future"], 2, "absurdly-far-ahead ticks were rejected")
	Runner.T.eq(sess._buffers[1].size(), base, "the remote buffer is untouched after the whole barrage")
	# And the session still runs: rejection is not a crash.
	sess.submit_local_input(SimInput.new())
	sess.receive_remote_input(t, [0, 0, 0, 0, 0])
	Runner.T.ok(sess.try_advance(), "a valid input after the barrage still advances the sim")


func test_handshake_catches_config_mismatch() -> void:
	# Mismatched input_delay used to deadlock silently: both peers wait on ticks
	# the other will never send, with nothing to point at.
	var a := LockstepSession.new(SimWorld.new(SEED, 2), 0, 3)
	var b := LockstepSession.new(SimWorld.new(SEED, 2), 1, 3)
	var c := LockstepSession.new(SimWorld.new(SEED, 2), 1, 5)
	Runner.T.ok(a.handshake_matches(b.session_hash), "identical config handshakes clean")
	Runner.T.ok(not a.handshake_mismatch, "a clean handshake leaves no flag")
	Runner.T.ok(not a.handshake_matches(c.session_hash), "mismatched input_delay is refused")
	Runner.T.ok(a.handshake_mismatch, "the mismatch is flagged instead of deadlocking silently")
	# Every field replay.gd persists must move the hash, or a mismatched run
	# config sails through the handshake and desyncs on tick 1.
	var ref := LockstepSession.compute_session_hash(SEED, "campaign", 2, 3, false, false, 1)
	var variants := {
		"seed": LockstepSession.compute_session_hash(SEED + 1, "campaign", 2, 3, false, false, 1),
		"mode": LockstepSession.compute_session_hash(SEED, "endless", 2, 3, false, false, 1),
		"player_count": LockstepSession.compute_session_hash(SEED, "campaign", 1, 3, false, false, 1),
		"input_delay": LockstepSession.compute_session_hash(SEED, "campaign", 2, 4, false, false, 1),
		"assist": LockstepSession.compute_session_hash(SEED, "campaign", 2, 3, true, false, 1),
		"hard": LockstepSession.compute_session_hash(SEED, "campaign", 2, 3, false, true, 1),
		"chapter": LockstepSession.compute_session_hash(SEED, "campaign", 2, 3, false, false, 2),
	}
	for field in variants:
		Runner.T.ok(variants[field] != ref, "%s changes the session hash" % field)
	Runner.T.eq(LockstepSession.compute_session_hash(SEED, "campaign", 2, 3, false, false, 1), ref,
		"the same config always hashes the same")


func test_handshake_reads_the_live_sim_config() -> void:
	# The hash must come from the sim it wraps, not from constructor defaults —
	# main.gd sets assist/hard/chapter on the sim, and a session that ignored
	# them would handshake clean between an assist run and a vanilla one.
	var plain := SimWorld.new(SEED, 2)
	var assisted := SimWorld.new(SEED, 2)
	assisted.assist_mode = true
	var harder := SimWorld.new(SEED, 2)
	harder.hard = true
	Runner.T.ok(LockstepSession.new(plain, 0).session_hash != LockstepSession.new(assisted, 0).session_hash,
		"an assist-mode sim handshakes differently")
	Runner.T.ok(LockstepSession.new(plain, 0).session_hash != LockstepSession.new(harder, 0).session_hash,
		"a HARD sim handshakes differently")
	var endless := LockstepSession.new(SimWorld.new(SEED, 2, "endless"), 0)
	Runner.T.ok(LockstepSession.new(plain, 0).session_hash != endless.session_hash,
		"a different mode handshakes differently")
	Runner.T.eq(LockstepSession.new(plain, 0).session_hash, LockstepSession.new(SimWorld.new(SEED, 2), 0).session_hash,
		"two identically-configured runs agree")


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
	# the checksum exchange must flag it within one interval.
	var pair := _run_loopback({"corrupt_at_tick": 240})
	var a: LockstepSession = pair[0]
	var b: LockstepSession = pair[1]
	Runner.T.ok(a.sim.checksum() != b.sim.checksum(), "corrupted wire produced divergent sims")
	var caught := false
	for t in a.checksum_ticks():
		if a.compare_remote_checksum(t, b.checksum_at(t)) == LockstepSession.CMP_MISMATCH:
			caught = true
			break
	Runner.T.ok(caught, "checksum exchange caught the desync")
	Runner.T.ok(a.desynced, "session flagged desynced")


func test_unknown_checksum_is_distinguishable_from_desync() -> void:
	# 0 is a legal checksum, so "peer hasn't reached this tick" used to be
	# indistinguishable from "peer diverged to 0" — a merely-behind peer read as
	# desynced, and a frozen diverged peer read as clean.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	Runner.T.ok(not sess.has_checksum(60), "no checksum recorded before the sim gets there")
	Runner.T.eq(sess.checksum_at(60), LockstepSession.CHECKSUM_UNKNOWN, "an unrecorded tick reads as UNKNOWN, not 0")
	# We are behind: unknown, NOT a clean match.
	Runner.T.eq(sess.compare_remote_checksum(60, 12345), LockstepSession.CMP_UNKNOWN,
		"a tick WE haven't reached is unknown, not agreement")
	Runner.T.ok(not sess.desynced, "being behind never flags a desync")
	# Advance far enough to record a real checksum, then hear from a peer that
	# hasn't got there yet.
	var empty := SimInput.new().encode()
	for t in range(1, 80):
		sess.receive_remote_input(t, empty)
		sess.submit_local_input(SimInput.new())
	while sess.try_advance():
		pass
	Runner.T.ok(sess.has_checksum(60), "checksum recorded at the interval")
	Runner.T.eq(sess.compare_remote_checksum(60, LockstepSession.CHECKSUM_UNKNOWN), LockstepSession.CMP_UNKNOWN,
		"a peer reporting UNKNOWN is behind, not desynced")
	Runner.T.ok(not sess.desynced, "a behind peer does not trip the desync flag")
	Runner.T.eq(sess.compare_remote_checksum(60, sess.checksum_at(60)), LockstepSession.CMP_MATCH,
		"a real agreeing checksum still matches")
	Runner.T.eq(sess.compare_remote_checksum(60, sess.checksum_at(60) + 1), LockstepSession.CMP_MISMATCH,
		"a real disagreeing checksum is a mismatch")
	Runner.T.ok(sess.desynced, "a proven mismatch flags the desync")


func test_checksum_ticks_is_actually_typed() -> void:
	# The signature says Array[int]; Dictionary.keys() returns an untyped Array,
	# and returning it throws at any typed call site.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var empty := SimInput.new().encode()
	for t in range(1, 140):
		sess.receive_remote_input(t, empty)
		sess.submit_local_input(SimInput.new())
	while sess.try_advance():
		pass
	var ticks: Array[int] = sess.checksum_ticks()   # this line is the test
	Runner.T.eq(ticks, [60, 120] as Array[int], "checksum ticks come back sorted and typed")


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


func test_on_send_dispatches_redundancy_window() -> void:
	# The on_send transport seam is how a real transport (Steam Networking) ships local input.
	# No other test assigns on_send, so submit_local_input's dispatch path was fully uncovered —
	# a regression there would break real netplay while every loopback test (which drives
	# receive_remote_input directly, bypassing on_send) stayed green.
	var sess := LockstepSession.new(SimWorld.new(SEED, 2), 0)
	var sent: Array = []
	sess.on_send = func(tick: int, payloads: Array) -> void:
		sent.append({"tick": tick, "payloads": payloads})
	var inp := SimInput.new()
	inp.move_x = 128
	inp.fire = true
	var msg := sess.submit_local_input(inp)
	Runner.T.eq(sent.size(), 1, "on_send fired once for one submitted input")
	Runner.T.eq(sent[0]["tick"], msg["tick"], "on_send tick matches the returned msg tick")
	Runner.T.eq(sent[0]["payloads"], msg["payloads"], "on_send window matches the returned msg window")
	Runner.T.eq(sent[0]["payloads"][-1], msg["payload"], "the window's last slot is the tick's own payload")
	var decoded := SimInput.decode(sent[0]["payloads"][-1])
	Runner.T.eq(decoded.move_x, 128, "dispatched payload round-trips move_x")
	Runner.T.ok(decoded.fire, "dispatched payload round-trips fire")
	# The window grows to REDUNDANCY and then slides — a fixed cost per datagram.
	for i in 20:
		sess.submit_local_input(SimInput.new())
	Runner.T.eq(sent.size(), 21, "every submit dispatched")
	Runner.T.eq(sent[4]["payloads"].size(), 5, "the window fills up one input at a time")
	Runner.T.eq(sent[-1]["payloads"].size(), LockstepSession.REDUNDANCY, "and then caps at REDUNDANCY")
	Runner.T.eq(sent[-1]["tick"], sess._next_local_tick - 1, "the window's tick names its newest slot")
