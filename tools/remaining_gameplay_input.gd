extends "res://tools/full_run_input.gd"

var probe_inputs: Array[SimInput] = []
var probe_decisions: Array[int] = [0, 0]


func _gather_inputs() -> Array[SimInput]:
	if probe_inputs.is_empty():
		return super._gather_inputs()
	var before := sim.checksum()
	var result: Array[SimInput] = []
	for pi in sim.players.size():
		result.append(SimInput.decode(probe_inputs[pi].encode()))
		probe_decisions[pi] += 1
	if before != sim.checksum():
		push_error("Remaining-gameplay input selection mutated simulation")
	return result
