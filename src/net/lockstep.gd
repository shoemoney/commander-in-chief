class_name LockstepSession
extends RefCounted
## Transport-agnostic deterministic lockstep for 2-player co-op.
##
## The plan's netcode story: both peers run the same SimWorld; only inputs
## cross the wire. Local inputs are scheduled `input_delay` ticks in the
## future and handed to a pluggable send callback; the sim advances a tick
## only when BOTH players' inputs for that tick are present (stall
## otherwise). Every CHECKSUM_INTERVAL ticks the sim checksum is recorded
## for exchange — a mismatch is a desync, detected within one interval.
##
## No sockets, no floats, no wall clock: the same rules as src/sim. The
## Steam Networking Messages transport plugs into `on_send` /
## `receive_remote_input` later without touching this loop.
##
## That transport will be UDP-shaped: datagrams get lost, duplicated,
## reordered, and forged. So every send carries a redundancy window instead of
## a single input (loss is covered by the next packet — no acks, no resends,
## no timeouts), `receive_remote_input` is idempotent and first-write-wins, and
## it validates everything at the trust boundary the same way replay.gd does
## for the same wire format. Peers also exchange `session_hash` before the
## first tick, because a mismatched run config (input_delay especially) can
## only deadlock, and a silent deadlock is the worst bug to be handed.

const CHECKSUM_INTERVAL := 60
## Every send re-ships the last REDUNDANCY inputs, so a lost datagram is
## covered by the next one instead of stalling the session forever. There is
## no ack/resend/timeout path and there doesn't need to be: lockstep already
## re-sends every tick, and 8 ticks of cover survives a ~130 ms outage.
const REDUNDANCY := 8
## Wire-validation ceiling: an input more than this far ahead of our sim is
## garbage or a flood, never a peer that is merely early (a peer legitimately
## runs at most a few ticks + jitter ahead). Also bounds buffer growth.
const MAX_LEAD := 600
## checksum_at() for a tick we never recorded. Distinguishable from a real
## checksum so "the peer hasn't got there yet" can't read as a desync.
const CHECKSUM_UNKNOWN := -1
## compare_remote_checksum() results.
const CMP_MISMATCH := -1
const CMP_UNKNOWN := 0
const CMP_MATCH := 1
## Increment whenever deterministic simulation rules change incompatibly.
## Replays and lockstep share this exact value so both trust boundaries reject
## an input stream authored for a different simulation before stepping it.
const CURRENT_RULESET_VERSION := Replay.CURRENT_RULESET_VERSION
const HANDSHAKE_PROTOCOL := "DETERMINISTIC_LOCKSTEP_1"

var sim: SimWorld
var local_player: int
var input_delay: int
## Called with (tick: int, payloads: Array) whenever a local input is
## scheduled — the transport ships it to the peer. `payloads` is the
## redundancy window (up to REDUNDANCY encoded inputs, oldest first) ENDING at
## `tick`; ship it whole, it is what makes packet loss survivable.
var on_send: Callable
var desynced: bool = false
var stalled_ticks: int = 0
## Set by handshake_matches(): the peer's run config differs from ours, so the
## session can never converge. Without this a mismatched input_delay just
## deadlocks with no explanation.
var handshake_mismatch: bool = false
## Separate from a same-ruleset config mismatch: an absent/foreign ruleset is
## unsupported, not a desync and never evidence of tampering.
var unsupported_ruleset: bool = false
## Snapshot of this run's config, taken at construction — build the sim,
## configure it (assist/hard/chapter), THEN wrap it in a session.
var session_hash: int = 0
## Wire inputs rejected by validation, by reason. Diagnostics only.
var rejected: Dictionary = {"past": 0, "far_future": 0, "malformed": 0, "duplicate": 0}

var _buffers: Array[Dictionary] = [{}, {}]   # player index -> {tick: encoded input}
var _next_local_tick: int = 0
var _checksums: Dictionary = {}              # tick -> checksum
var _sent: Array = []                        # redundancy window of local payloads


func _init(sim_world: SimWorld, local_player_index: int, delay: int = 3) -> void:
	sim = sim_world
	local_player = local_player_index
	input_delay = delay
	_next_local_tick = delay + 1
	session_hash = compute_session_hash(sim._world_seed, sim.mode, sim.players.size(),
		delay, sim.assist_mode, sim.hard, sim._gate_counter + 1, CURRENT_RULESET_VERSION)
	# Convention both peers share: the first `delay` ticks run on empty inputs,
	# so neither side waits on the wire to start.
	var empty := SimInput.new().encode()
	for t in range(1, delay + 1):
		_buffers[0][t] = empty
		_buffers[1][t] = empty


## The run config both peers must agree on before a single tick is exchanged —
## exactly the set replay.gd persists (seed/mode/players/assist/hard/chapter),
## plus input_delay, which only lockstep has. Any difference makes the two sims
## diverge or (for input_delay) deadlock, so it is cheaper to refuse the
## connection than to debug it later.
static func compute_session_hash(seed_value: int, mode: String, player_count: int,
		delay: int, assist: bool, hard: bool, chapter: int,
		ruleset_version: int = CURRENT_RULESET_VERSION) -> int:
	return [ruleset_version, seed_value, mode, player_count, delay, int(assist), int(hard), chapter].hash()


func handshake_payload() -> Dictionary:
	return {"protocol": HANDSHAKE_PROTOCOL, "ruleset": CURRENT_RULESET_VERSION,
		"session_hash": session_hash}


func handshake_matches(remote: Variant) -> bool:
	# The handshake is an envelope, not a bare hash: hashing the ruleset prevents
	# accidental equality, while this explicit field lets us report the real
	# cause instead of calling an incompatible peer a desync or cheater.
	if typeof(remote) != TYPE_DICTIONARY or not remote.has("ruleset") \
			or typeof(remote.get("ruleset")) not in [TYPE_INT, TYPE_FLOAT] \
			or int(remote.get("ruleset")) != CURRENT_RULESET_VERSION:
		unsupported_ruleset = true
		push_warning("LockstepSession: peer uses a missing or unsupported simulation ruleset. Refuse the connection before stepping inputs.")
		return false
	if remote.get("protocol", "") != HANDSHAKE_PROTOCOL:
		handshake_mismatch = true
		push_warning("LockstepSession: unsupported handshake protocol. Refuse the connection.")
		return false
	if int(remote.get("session_hash", -1)) == session_hash:
		return true
	handshake_mismatch = true
	push_warning("LockstepSession: handshake mismatch — peer's run config differs (seed/mode/players/input_delay/assist/hard/chapter). Refuse the connection; it can only deadlock or desync.")
	return false


func remote_player() -> int:
	return 1 - local_player


func submit_local_input(inp: SimInput) -> Dictionary:
	## Schedule the local input `input_delay` ticks ahead and emit it for the
	## transport. Returns {tick, payload, payloads} — `payloads` is the
	## redundancy window ending at `tick` and is what on_send receives.
	var tick := _next_local_tick
	_next_local_tick += 1
	var payload := inp.encode()
	_buffers[local_player][tick] = payload
	_sent.append(payload)
	if _sent.size() > REDUNDANCY:
		_sent.pop_front()
	var window := _sent.duplicate()
	if on_send.is_valid():
		on_send.call(tick, window)
	return {"tick": tick, "payload": payload, "payloads": window}


func receive_remote_input(tick: int, payload: Array) -> void:
	## TRUST BOUNDARY — everything here arrives from another machine.
	## `payload` is either ONE encoded input (an array of ints) or a redundancy
	## window of them (an array of arrays) whose LAST element is for `tick`.
	## Re-sends are expected and normal, so this is idempotent: every input is
	## range-checked and the first copy of a tick wins.
	if payload.is_empty():
		rejected["malformed"] += 1
		return
	if typeof(payload[0]) == TYPE_ARRAY:
		var first := tick - payload.size() + 1
		for i in payload.size():
			_accept(first + i, payload[i])
	else:
		_accept(tick, payload)


func _accept(tick: int, payload: Variant) -> void:
	# Mirrors replay.gd's load_from() shape gate (same wire format, same reason:
	# an input shorter than the 5 fields SimInput.decode indexes crashes mid-step).
	if typeof(payload) != TYPE_ARRAY or not _valid_payload(payload):
		rejected["malformed"] += 1
		return
	if tick <= sim.tick_count:
		# Already consumed (or pre-seeded). try_advance erases spent ticks, so
		# re-inserting one would leak it forever — and the redundancy window
		# makes that happen every single send.
		rejected["past"] += 1
		return
	if tick > sim.tick_count + MAX_LEAD:
		rejected["far_future"] += 1
		return
	var buf := _buffers[remote_player()]
	if buf.has(tick):
		# First write wins. Overwriting a still-buffered future tick with a
		# differing copy is an instant desync (we would step an input the peer
		# never stepped) and would make re-sends non-idempotent.
		rejected["duplicate"] += 1
		return
	buf[tick] = payload


static func _valid_payload(payload: Array) -> bool:
	if payload.size() < 5:
		return false
	for i in 5:
		# decode() clamps ranges already; it cannot survive a non-numeric field
		# (int(Array) is a hard cast error mid-step). Floats pass because a
		# JSON-based transport round-trips ints as floats.
		var t := typeof(payload[i])
		if t != TYPE_INT and t != TYPE_FLOAT:
			return false
	return true


func can_advance() -> bool:
	var t := sim.tick_count + 1
	return _buffers[0].has(t) and _buffers[1].has(t)


func try_advance() -> bool:
	## Step the sim one tick if both inputs are present. Returns false (and
	## counts a stall) when the wire is behind — lockstep semantics.
	var t := sim.tick_count + 1
	if not can_advance():
		stalled_ticks += 1
		return false
	var i0 := SimInput.decode(_buffers[0][t])
	var i1 := SimInput.decode(_buffers[1][t])
	sim.step([i0, i1])
	# Inputs for consumed ticks are no longer needed; keep memory flat.
	_buffers[0].erase(t)
	_buffers[1].erase(t)
	if t % CHECKSUM_INTERVAL == 0:
		_checksums[t] = sim.checksum()
	return true


func has_checksum(tick: int) -> bool:
	return _checksums.has(tick)


func checksum_at(tick: int) -> int:
	## CHECKSUM_UNKNOWN (not 0) for a tick we haven't reached — 0 is a legal
	## checksum value, so returning it made "behind" indistinguishable from
	## "diverged" on the receiving peer.
	return _checksums.get(tick, CHECKSUM_UNKNOWN)


func checksum_ticks() -> Array[int]:
	var ticks: Array[int] = []
	ticks.assign(_checksums.keys())   # keys() is untyped; assign() types it (a bare return throws)
	ticks.sort()
	return ticks


func compare_remote_checksum(tick: int, remote_value: int) -> int:
	## Tri-state compare of the peer's reported checksum for a tick against
	## ours: CMP_MATCH / CMP_MISMATCH / CMP_UNKNOWN. UNKNOWN means one side
	## simply hasn't reached the tick — a peer that is merely behind must not
	## read as desynced, and a frozen peer reporting nothing must not read as
	## clean. A real mismatch marks the session desynced (the shipping game
	## then triggers the desync auto-report + host-snapshot resync path).
	if remote_value == CHECKSUM_UNKNOWN or not _checksums.has(tick):
		return CMP_UNKNOWN
	if _checksums[tick] != remote_value:
		desynced = true
		return CMP_MISMATCH
	return CMP_MATCH


func verify_remote_checksum(tick: int, remote_value: int) -> bool:
	## Boolean view of compare_remote_checksum: false ONLY on a proven
	## mismatch. Use compare_remote_checksum when "unknown" matters.
	return compare_remote_checksum(tick, remote_value) != CMP_MISMATCH
