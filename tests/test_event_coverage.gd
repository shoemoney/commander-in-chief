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


## THE STATIC HARVEST IS THE GATE. The runtime sample is corroboration only.
##
## This test used to assert `handled.has(t)` for every `t` in a 600-tick, 2-mode
## SAMPLE of what the sim emitted. Measured on 2026-10-03: that sample reaches
## **15 of the 101 event types the sim can emit** — 15%. Pushed to 12,000 scripted
## ticks across all four modes it reaches 38, so 63 types are not reachable by that
## input at all (they need a tank, a shop purchase, a gate route, a boss kill, a
## pilot rescue, and so on).
##
## So the gate was structural for 15% of the seam and silent for the other 85%. Add
## an event, forget the branch in main.gd, and it passes as long as nothing in the
## torture happens to fire it — which is the exact failure this file exists to catch,
## on the majority of the surface.
##
## The static harvest cannot miss one: every `{"t": "..."` literal in src/sim is a
## type the sim can emit, whether or not any run in this suite reaches it. So the
## harvest is now the assertion, and the sample is kept for what only a run can show:
## that the harvest is not reading phantom strings, and that the seam is live.
func test_emitted_events_are_all_handled() -> void:
	var handled := _handled_types()
	var declared := _declared_types()

	# THE GATE: every type the sim can possibly emit must have a view handler.
	var unhandled: Array = []
	for t in declared.keys():
		if not handled.has(t):
			unhandled.append(t)
	Runner.T.eq(unhandled.size(), 0,
		"every event type src/sim can emit has a view handler in main.gd"
		+ (" (unhandled: %s)" % ", ".join(unhandled) if unhandled.size() > 0 else ""))

	# The harvest must not be a regex miss — a silently-empty set would make the gate
	# above vacuous, which is the failure mode of the version this replaced.
	Runner.T.ok(declared.size() >= 80,
		"the static harvest found %d event types across src/sim — a regex break would "
			% declared.size()
		+ "make the gate above vacuous (expected >= 80)")
	Runner.T.ok(handled.size() >= 80,
		"the static parse found %d handled types in main.gd" % handled.size())

	# The runtime sample, as CORROBORATION: it must be a subset of the harvest (no
	# phantom), non-trivial (the seam is live), and every sampled type handled (the
	# original check, kept because a runtime-only emitter would slip past the static one).
	var sampled := {}
	for mode in ["campaign", "endless"]:
		var sim := SimWorld.new(0xC0FFEE, 2, mode)
		for tick in TICKS:
			sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
			for ev in sim.events:
				sampled[ev["t"]] = true
	Runner.T.ok(sampled.size() >= 5,
		"torture emitted only %d event types — the coverage check ran on nothing"
			% sampled.size())
	var phantom: Array = []
	var sampled_unhandled: Array = []
	for t in sampled.keys():
		if not declared.has(t):
			phantom.append(t)
		if not handled.has(t):
			sampled_unhandled.append(t)
	Runner.T.eq(phantom.size(), 0,
		"every runtime-observed type is in the static harvest (no phantom harvest)"
		+ (" (phantom: %s)" % ", ".join(phantom) if phantom.size() > 0 else ""))
	Runner.T.eq(sampled_unhandled.size(), 0,
		"every runtime-observed type has a handler"
		+ (" (unhandled: %s)" % ", ".join(sampled_unhandled)
			if sampled_unhandled.size() > 0 else ""))
	# Stated, so the next reader knows the static gate is carrying the weight and does
	# not "helpfully" go back to sampling only.
	Runner.T.ok(true,
		"the static harvest covers %d types; this run's torture sample reached %d "
			% [declared.size(), sampled.size()]
		+ "(%.0f%%) — the SAMPLE is corroboration, the HARVEST is the gate"
			% (100.0 * float(sampled.size()) / float(maxi(1, declared.size()))))


## Every `{"t": "..."` literal in src/sim — the set of types the sim CAN emit,
## independent of whether any run in this suite reaches it.
##
## Deliberately a text harvest rather than a call into the sim: a runtime set can
## only contain what some run happened to produce, which is the limitation this
## function exists to remove. It reads every .gd in src/sim, so an event added to a
## file other than sim_world.gd is caught too.
func _declared_types() -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("\\{\\s*\"t\"\\s*:\\s*\"([a-z_0-9]+)\"")
	for path in DirAccess.get_files_at("res://src/sim"):
		if not path.ends_with(".gd"):
			continue
		var f := FileAccess.open("res://src/sim/" + path, FileAccess.READ)
		if f == null:
			continue
		for m in re.search_all(f.get_as_text()):
			out[m.get_string(1)] = true
		f.close()
	return out


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
