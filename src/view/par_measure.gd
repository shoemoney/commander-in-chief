class_name ParMeasure
extends RefCounted
## Measures how long the scripted combat bot (main.gd demo_input) takes to clear each campaign
## sector, so ServiceRecord.PAR_TICKS can be checked against the live sim instead of a number
## someone once wrote down. GOD MODE is on (it restores ammo and stand-ups), so these are
## bot-with-god-mode times. Pure SimWorld + demo_input: no scene tree.

## Per-sector clear ticks for one seed: sector n = ticks between gate n-1 opening and gate n
## opening (sector 1 starts at tick 0, sector 6 ends on victory) - the same boundaries
## ServiceRecord.observe uses. Returns [] if the bot did not win within `cap` ticks.
static func bot_sector_clears(sd: int, cap: int = 24000) -> Array[int]:
	var main_script: Script = load("res://src/main.gd")
	var sim := SimWorld.new(sd, 1, "campaign")
	sim.god_mode = true
	var bounds: Array[int] = []
	var t := 0
	var won := false
	while t < cap and not won:
		sim.step([main_script.demo_input(t, sim)])
		t += 1
		for ev in sim.events:
			var k: String = ev.get("t", "")
			if k == "gate_open":
				bounds.append(t)
			elif k == "victory":
				bounds.append(t)
				won = true
	var out: Array[int] = []
	if not won or bounds.size() != ServiceRecord.SECTORS:
		return out
	var prev := 0
	for b in bounds:
		out.append(b - prev)
		prev = b
	return out
