extends SceneTree
## Time-to-kill table: MG vs flamethrower vs rocket launcher, one scenario per row.
## Runs the SAME scenario code the test suite asserts on (tests/test_weapons.gd::ttk), so the
## numbers printed here are the numbers the tests pin.
##   tools/run_tests.sh -s res://tools/probe_weapons.gd

const Suite := preload("res://tests/test_weapons.gd")
const Review := preload("res://tests/test_review_fixes.gd")


func _init() -> void:
	var s := Suite.new()
	var names := {Weapons.NONE: "MG", Weapons.FLAME: "FLAME", Weapons.ROCKET: "ROCKET"}
	print("time-to-kill in ticks (60/s) [ammo spent]; -1 = never")
	print("%-22s %-14s %-14s %-14s" % ["scenario", "MG", "FLAME", "ROCKET"])
	for sc in Suite.SCENARIOS:
		var cells: Array[String] = []
		for wid in [Weapons.NONE, Weapons.FLAME, Weapons.ROCKET]:
			var r: Array = s.ttk(wid, sc)
			cells.append("%d [%d]" % [r[0], r[1]])
		print("%-22s %-14s %-14s %-14s" % [sc, cells[0], cells[1], cells[2]])
	# Rockets vs a drifting gunship (same scenario code as tests/test_review_fixes.gd).
	var rv := Review.new()
	print("\nrocket launcher vs the drifting gunship, 900 ticks: [rockets fired, hull hp lost (6 per hit), hull hp]")
	for rng in [60, 120, 200]:
		print("  range %3d px: %s" % [rng, str(rv._gunship_duel(rng, 900))])
	quit()
