extends RefCounted
## ONLY A CLOSED GATE MAY SWITCH THE ECONOMY OFF.
##
## 1.3 (`067f70a`, "closed-gate coin farm plugged") routed three economy throttles —
## kill payout (_kill_enemy), the bunker drip (_step_bunkers) and the field spawn
## cadence (_step_spawner) — through `camera_held()`. That predicate has TWO branches
## and only the second one is a gate: the first is the trailing-partner CAMERA LEASH.
## So the throttles also fired whenever a player was pinned at the band bottom, which
## in solo is nothing more exotic than backpedalling under pressure.
##
## Measured on 8cdc17b before the fix, campaign / god_mode / 6000 ticks, four seeds,
## a backpedal driver (300t north, 300t south):
##     1P: 174 leash-only held ticks per run,  5-7 kills paid nothing
##     2P: 1020-1038 leash-only held ticks,   14-18 kills paid nothing
## against 60-170 coin actually banked. The leash alone deleted more than the run
## earned. The GATE branch is 5.4-7.1x (2P) / 21-30x (1P) larger and is untouched —
## the anti-farm intent of 1.3 stands, only the predicate changed.
##
## SAMPLING WINDOW: 8 runs x 6000 ticks = 48,000 ticks. The longest probe defect ever
## measured in this repo is ~764 ticks, so the window is 7.9x that; the first HEAD
## violation lands by tick ~300 (the 60s determinism torture's first leash-only tick
## is 111), so the window is not the thing under test.

const Runner := preload("res://tests/run_tests.gd")


## Records, for every kill the SIM forces to pay nothing, whether a closed gate was
## actually holding the camera. Overriding _kill_enemy is the only seam that can see
## the difference between "this kill was already free" (pilot, barrel) and "the sim
## took the payout away".
class EconProbe extends SimWorld:
	var forced_no_pay := 0        ## kills the sim zeroed that would otherwise have paid
	var forced_without_gate := 0  ## ...of those, the ones with NO closed gate holding

	func _kill_enemy(e: Dictionary, no_coin := false, no_score := false, score_pct := 100) -> void:
		var would_have_paid: bool = not no_coin and e["kind"] != "pilot"
		var chest_before: int = war_chest
		var gate: bool = gate_held()
		super(e, no_coin, no_score, score_pct)
		if would_have_paid and war_chest == chest_before:
			forced_no_pay += 1
			if not gate:
				forced_without_gate += 1


static func _drive(t: int) -> SimInput:
	## Backpedal driver: 300 ticks pushing north, 300 ticks retreating south. The
	## retreat is what pins a player at the band bottom and binds the leash — a bot
	## that only ever marches north (like the shipped attract bot) measures exactly
	## ZERO leash-only ticks, which is how this defect read as "2P only" and hid.
	var inp := SimInput.new()
	var north: bool = (t % 600) < 300
	inp.move_y = -256 if north else 256
	inp.aim_y = -256
	inp.fire = (t % 8) != 0
	return inp


func test_only_a_closed_gate_may_switch_off_the_kill_economy() -> void:
	var total_forced := 0
	var total_bad := 0
	for pc in [1, 2]:
		for seed in [3, 11, 101, 7919]:
			var sim := EconProbe.new(seed, pc, "campaign")
			sim.god_mode = true
			for t in 6000:
				var inp := _drive(t)
				var inputs: Array = [inp] if pc == 1 else [inp, inp]
				sim.step(inputs)
			total_forced += sim.forced_no_pay
			total_bad += sim.forced_without_gate
			Runner.T.eq(sim.forced_without_gate, 0,
				("%dP seed %d: %d kill(s) of %d paid NOTHING with no closed gate holding the " +
				"camera — the camera LEASH is not a gate, and backpedalling is not farming") \
					% [pc, seed, sim.forced_without_gate, sim.forced_no_pay])
	Runner.T.ok(total_forced > 0,
		"the driver never triggered the closed-gate payout throttle at all (%d forced) — this leg ran on nothing" \
			% total_forced)
	Runner.T.eq(total_bad, 0,
		"%d of %d sim-forced zero-payout kills happened away from a closed gate across 48,000 ticks" \
			% [total_bad, total_forced])


func test_only_a_closed_gate_may_throttle_the_bunker_drip() -> void:
	## Behavioural, not predicate-shaped: a throttled tick is one where an alive
	## bunker's spawn_cd did NOT decrement. Reading the skip off the state means this
	## keeps its teeth even if the throttle is later rewritten to read something else.
	var total_skips := 0
	var total_bad := 0
	for pc in [1, 2]:
		for seed in [3, 11, 101, 7919]:
			var sim := SimWorld.new(seed, pc, "campaign")
			sim.god_mode = true
			var skips := 0
			var bad := 0
			for t in 6000:
				var watched: Array = []
				for bk in sim.bunkers:
					if bk["alive"] and bk["spawn_cd"] > 1:
						watched.append([bk, int(bk["spawn_cd"])])
				var gate: bool = sim.gate_held()
				var inp := _drive(t)
				sim.step([inp] if pc == 1 else [inp, inp])
				for w in watched:
					var bk: Dictionary = w[0]
					var live := false
					for b2 in sim.bunkers:
						if is_same(b2, bk):
							live = true
							break
					if not live or not bk["alive"]:
						continue
					if int(bk["spawn_cd"]) == int(w[1]):
						skips += 1
						if not gate:
							bad += 1
			total_skips += skips
			total_bad += bad
			Runner.T.eq(bad, 0,
				("%dP seed %d: the bunker half-rate drip skipped %d of %d tick(s) with no closed " +
				"gate holding the camera — the leash must not starve the open field") \
					% [pc, seed, bad, skips])
	Runner.T.ok(total_skips > 0,
		"no bunker drip tick was ever throttled across 48,000 ticks (%d) — this leg ran on nothing" % total_skips)
	Runner.T.eq(total_bad, 0, "%d of %d throttled bunker ticks happened away from a closed gate" % [total_bad, total_skips])


func test_no_bounty_pop_congratulates_a_zero_coin_kill() -> void:
	## `bounty_kill` is emitted from inside the `marked` block BEFORE no_coin is
	## honoured, so main.gd:2987 popped "BOUNTY +N¢" and a fanfare sting for a kill
	## that banked 0. The ordinary `kill` event never lied (it ships `0 if no_coin`),
	## so exactly one view element congratulated a free kill. Keeps teeth after the
	## predicate fix: the GATE branch still zeroes payouts, and bounty targets still
	## die there.
	var lies := 0
	var bounties := 0
	for pc in [1, 2]:
		for seed in [3, 11, 101, 7919]:
			var sim := SimWorld.new(seed, pc, "campaign")
			sim.god_mode = true
			for t in 6000:
				var inp := _drive(t)
				sim.step([inp] if pc == 1 else [inp, inp])
				for i in sim.events.size():
					var ev: Dictionary = sim.events[i]
					if ev["t"] != "bounty_kill":
						continue
					bounties += 1
					# the paired `kill` is the very next event by construction
					if i + 1 < sim.events.size() and sim.events[i + 1]["t"] == "kill" \
							and int(sim.events[i + 1]["coin"]) == 0 and int(ev["coin"]) > 0:
						lies += 1
	Runner.T.eq(lies, 0,
		"%d of %d bounty_kill event(s) advertised coin the paired kill banked as 0 — the HUD pop is a receipt, not a compliment" \
			% [lies, bounties])


const ECON_FIELDS: Array[String] = ["war_chest", "no_coin", "no_score", "kill_streak", "spawn_cd", "interval"]

## Sites where reading camera_held() next to an economy field is deliberate and correct.
## Adding an entry needs a written justification, same rule as run_tests.gd's ERROR_ALLOW.
const ECON_ALLOW: Array[String] = []


func test_no_economy_throttle_reads_camera_held() -> void:
	## Source-derived sibling of test_view_honesty.gd's stall_ticks scrape, so a FOURTH
	## throttle added next cycle goes red the day it lands rather than the day someone
	## notices their coin vanishing. On 8cdc17b this named exactly three sites:
	## sim_world.gd:3501 (kill payout), :4288 (bunker drip), :4457 (field cadence).
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	Runner.T.ok(not src.is_empty(), "could not read src/sim/sim_world.gd")
	var lines := src.split("\n")
	var offenders: Array[String] = []
	for i in lines.size():
		var line: String = lines[i]
		if not line.contains("camera_held()"):
			continue
		if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
			continue
		if line.contains("func camera_held"):
			continue
		var hits: Array[String] = []
		for j in range(maxi(0, i - 6), mini(lines.size(), i + 7)):
			var near: String = lines[j]
			if near.strip_edges().begins_with("#"):
				continue
			for f in ECON_FIELDS:
				if near.contains(f) and not hits.has(f):
					hits.append(f)
		if hits.is_empty():
			continue
		var tag := "sim_world.gd:%d" % (i + 1)
		if ECON_ALLOW.has(tag):
			continue
		offenders.append("%s (%s) -> %s" % [tag, ", ".join(hits), line.strip_edges()])
	Runner.T.eq(offenders.size(), 0,
		("%d camera_held() call site(s) sit inside economy code: %s\n" +
		"camera_held() includes the trailing-partner LEASH. An economy throttle must read " +
		"gate_held() — a closed gate is a wall the player can open, the leash is one they make " +
		"by standing still.") % [offenders.size(), "; ".join(offenders)])
