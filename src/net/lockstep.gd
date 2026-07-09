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

const CHECKSUM_INTERVAL := 60

var sim: SimWorld
var local_player: int
var input_delay: int
## Called with (tick: int, payload: Array[int]) whenever a local input is
## scheduled — the transport ships it to the peer.
var on_send: Callable
var desynced: bool = false
var stalled_ticks: int = 0

var _buffers: Array[Dictionary] = [{}, {}]   # player index -> {tick: encoded input}
var _next_local_tick: int = 0
var _checksums: Dictionary = {}              # tick -> checksum


func _init(sim_world: SimWorld, local_player_index: int, delay: int = 3) -> void:
	sim = sim_world
	local_player = local_player_index
	input_delay = delay
	_next_local_tick = delay + 1
	# Convention both peers share: the first `delay` ticks run on empty inputs,
	# so neither side waits on the wire to start.
	var empty := SimInput.new().encode()
	for t in range(1, delay + 1):
		_buffers[0][t] = empty
		_buffers[1][t] = empty


func remote_player() -> int:
	return 1 - local_player


func submit_local_input(inp: SimInput) -> Dictionary:
	## Schedule the local input `input_delay` ticks ahead and emit it for the
	## transport. Returns {tick, payload} (also passed to on_send if set).
	var tick := _next_local_tick
	_next_local_tick += 1
	var payload := inp.encode()
	_buffers[local_player][tick] = payload
	var msg := {"tick": tick, "payload": payload}
	if on_send.is_valid():
		on_send.call(tick, payload)
	return msg


func receive_remote_input(tick: int, payload: Array) -> void:
	_buffers[remote_player()][tick] = payload


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


func checksum_at(tick: int) -> int:
	return _checksums.get(tick, 0)


func checksum_ticks() -> Array:
	var ticks := _checksums.keys()
	ticks.sort()
	return ticks


func verify_remote_checksum(tick: int, remote_value: int) -> bool:
	## Compare the peer's reported checksum for a tick against ours. A
	## mismatch marks the session desynced (the shipping game then triggers
	## the desync auto-report + host-snapshot resync path).
	if not _checksums.has(tick):
		return true   # not reached yet; nothing to dispute
	if _checksums[tick] != remote_value:
		desynced = true
		return false
	return true
