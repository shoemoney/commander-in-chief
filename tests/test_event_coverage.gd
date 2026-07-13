extends RefCounted
## Event seam-coverage tripwire. SimWorld.events is the sim→view decoupling seam:
## the sim emits transient per-tick triggers, and src/main.gd is the ONLY thing
## that turns them into sound/feel. Nothing enforces that every emitted ev["t"]
## actually has a view handler — add a new event in the sim, forget the branch in
## main.gd, and it's silently dropped (no sound, no juice) with a green build.
##
## This test drives a real 2P sim in BOTH modes, collects the SET of every emitted
## event type, then statically reads src/main.gd to build the view's HANDLED set
## (the _EVENT_SOUND dict keys + the `match kind:` case labels in _consume_events +
## the "pickup"/"kill" special-cases). It fails if the sim emits anything the view
## never handles. Handled is parsed from source text — not called — so it stays a
## pure view/read-only check with zero sim-behavior impact.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const TICKS := 600


func test_emitted_events_are_all_handled() -> void:
	var handled := _handled_types()
	var emitted := {}   # used as a set: ev["t"] -> true
	for mode in ["campaign", "endless"]:
		var sim := SimWorld.new(0xC0FFEE, 2, mode)
		for tick in TICKS:
			sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
			for ev in sim.events:
				emitted[ev["t"]] = true

	# Guard against a vacuously-green run: the torture must actually fire events.
	Runner.T.ok(emitted.size() >= 5,
		"torture emitted only %d event types — the coverage check ran on nothing" % emitted.size())

	for t in emitted.keys():
		Runner.T.ok(handled.has(t),
			"sim emits event '%s' but the view never handles it (not in _EVENT_SOUND, not a `match kind:` case in _consume_events, not pickup/kill) — it is silently dropped" % t)


## Build the view's HANDLED set by statically reading src/main.gd as text.
## _EVENT_SOUND entries sit at exactly 1 tab; the `match kind:` case labels sit at
## exactly 3 tabs (branch bodies are 4+); both look like  "key":  once stripped.
func _handled_types() -> Dictionary:
	var f := FileAccess.open("res://src/main.gd", FileAccess.READ)
	Runner.T.ok(f != null, "could not open res://src/main.gd to parse handled events")
	if f == null:
		return {}
	var lines := f.get_as_text().split("\n")
	f.close()

	var key := RegEx.new()
	key.compile('^"([a-z_0-9]+)"\\s*:')   # a bare quoted key followed by a colon

	var handled := {"pickup": true, "kill": true}   # known view special-cases
	var in_sound := false
	var in_match := false
	for ln in lines:
		# _EVENT_SOUND dictionary block.
		if ln.begins_with("const _EVENT_SOUND"):
			in_sound = true
			continue
		if in_sound:
			if ln.begins_with("}"):
				in_sound = false
			elif ln.begins_with("\t") and not ln.begins_with("\t\t"):
				var m := key.search(ln.strip_edges())
				if m:
					handled[m.get_string(1)] = true
			continue
		# `match kind:` case labels inside _consume_events (ends at next top-level func).
		if ln.strip_edges() == "match kind:":
			in_match = true
			continue
		if in_match:
			if ln.begins_with("func "):
				in_match = false
			elif ln.begins_with("\t\t\t") and not ln.begins_with("\t\t\t\t"):
				var m2 := key.search(ln.strip_edges())
				if m2:
					handled[m2.get_string(1)] = true

	# Sanity: parsing must have found a rich handled set, not an empty regex miss.
	Runner.T.ok(handled.size() >= 20,
		"parsed only %d handled event types from main.gd — the static parser likely broke" % handled.size())
	return handled
