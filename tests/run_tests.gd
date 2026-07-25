extends SceneTree
## Headless test runner: godot --headless --path . -s res://tests/run_tests.gd
##
## Zero-dependency (no GUT addon needed in P0). Each test script extends
## RefCounted and exposes methods named test_*; assertions go through T.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/test_fixed.gd",
	"res://tests/test_sim_rng.gd",
	"res://tests/test_gameplay.gd",
	"res://tests/test_archetypes.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_war_chest.gd",
	"res://tests/test_shop.gd",
	"res://tests/test_tank.gd",
	"res://tests/test_observer.gd",
	"res://tests/test_gates.gd",
	"res://tests/test_mechanics.gd",
	"res://tests/test_water.gd",
	"res://tests/test_biomes.gd",
	"res://tests/test_boss.gd",
	"res://tests/test_lockstep.gd",
	"res://tests/test_endless.gd",
	"res://tests/test_mutators.gd",
	"res://tests/test_colossus.gd",
	"res://tests/test_determinism.gd",
	"res://tests/test_checksum_coverage.gd",
	"res://tests/test_event_coverage.gd",
	"res://tests/test_replay.gd",
	"res://tests/test_leaderboard.gd",
	"res://tests/test_endless_meta.gd",
	"res://tests/test_robustness.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_main.gd",
	"res://tests/test_steam_bridge.gd",
	"res://tests/test_menu_layout.gd",
	"res://tests/test_localization.gd",
	"res://tests/test_hud.gd",
	"res://tests/test_perf.gd",
	"res://tests/test_soak.gd",
]


class T:
	static var failures: Array[String] = []
	static var checks := 0

	static func ok(cond: bool, msg: String) -> void:
		checks += 1
		if not cond:
			failures.append(msg)
			push_error("FAIL: " + msg)

	static func eq(a, b, msg: String) -> void:
		ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

	# --- shared 2D layout assertion -------------------------------------------------------------
	# Kinds that are BACKINGS by design — a dark scrim, a plate, a legend strip, a gauge track, the
	# arm-point marker riding its own bar. They earn an overlap pass ONLY where the backing encloses
	# what it sits under; a scrim that merely clips a neighbouring widget is still a layout bug.
	const BACKING_KINDS := ["bg", "marker", "bar", "rect", "tex", "plate"]

	# A scrim is sized to the glyph INK, but a captured text box carries the font's full LINE box —
	# ascent plus a descent that every all-caps HUD/menu label leaves empty. Allow a backing that
	# misses by less than that when judging enclosure, or every correctly-backed label reads as a
	# collision. Small enough that two genuinely distinct widgets can't hide behind it.
	const BACKING_SLACK := 3.0

	# True when this pair is allowed to share pixels: one is a backing that ENCLOSES the other, or
	# it is the same string re-emitted at the same spot (a label's outline/shadow pass).
	static func overlap_is_intentional(a: Dictionary, b: Dictionary) -> bool:
		if String(a["k"]) == String(b["k"]) and String(a["id"]) == String(b["id"]) \
				and a["box"].position.distance_to(b["box"].position) < 2.0:
			return true
		if String(a["k"]) in BACKING_KINDS and a["box"].grow(BACKING_SLACK).encloses(b["box"]):
			return true
		if String(b["k"]) in BACKING_KINDS and b["box"].grow(BACKING_SLACK).encloses(a["box"]):
			return true
		return false

	## THE 2D collision assertion. Sorting captured draw ops by x and comparing x-extents — what the
	## HUD/menu layout tests used to do — is blind to anything stacked VERTICALLY, which is how the
	## same UI overlaps kept surviving review after review. This runs Rect2.intersects over every
	## pair, both axes, whitelisting only enclosing backings. Boxes are shrunk 0.5px so pixel-kissing
	## neighbours (one chip ending exactly where the next begins) are not flagged.
	## `boxes` is the capture shape the view harnesses record: {k, id, box}.
	static func no_overlap(boxes: Array, tag: String) -> void:
		for i in boxes.size():
			var a: Rect2 = boxes[i]["box"]
			if a.size.x <= 0.0 or a.size.y <= 0.0:
				continue
			var hits := PackedStringArray()
			for j in boxes.size():
				if i == j:
					continue
				var c: Rect2 = boxes[j]["box"]
				if c.size.x <= 0.0 or c.size.y <= 0.0:
					continue
				if not a.grow(-0.5).intersects(c.grow(-0.5)):
					continue
				if overlap_is_intentional(boxes[i], boxes[j]):
					continue
				hits.append("%s '%s' %s" % [boxes[j]["k"], boxes[j]["id"], str(c)])
			ok(hits.is_empty(), "%s: %s '%s' %s overlaps nothing (hit: %s)"
				% [tag, boxes[i]["k"], boxes[i]["id"], str(a), ", ".join(hits)])


func _init() -> void:
	var suite_filter := OS.get_environment("SUITE")
	var scripts: Array[String] = TEST_SCRIPTS if suite_filter.is_empty() else \
		TEST_SCRIPTS.filter(func(p: String) -> bool: return p.contains(suite_filter))
	var total_methods := 0
	for path in scripts:
		var script: GDScript = load(path)
		var suite: RefCounted = script.new()
		for m in suite.get_method_list():
			if m["name"].begins_with("test_"):
				total_methods += 1
				print("  • %s :: %s" % [path.get_file(), m["name"]])
				suite.call(m["name"])
	print("")
	if T.failures.is_empty():
		print("PASS — %d test methods, %d assertions, 0 failures" % [total_methods, T.checks])
		quit(0)
	else:
		print("FAIL — %d of %d assertions failed:" % [T.failures.size(), T.checks])
		for f in T.failures:
			print("   ✗ " + f)
		quit(1)
