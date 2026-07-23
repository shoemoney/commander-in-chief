extends RefCounted
## View-layer GAMEPLAY-SEMANTICS guards over src/main.gd. Unlike test_assets.gd (pure
## asset-registry/const-value checks), these pin what a piece of cover/geometry MEANS
## to the player — e.g. "is this pass-through concealment or a hard wall" — so an asset
## reskin can silently change art without silently changing what the art communicates.

const Runner := preload("res://tests/run_tests.gd")


func _consts() -> Dictionary:
	# Typed as the Script base (not the class) so the instance method resolves —
	# calling it through the preloaded class type is a static-call error.
	var ms: Script = load("res://src/main.gd")
	return ms.get_script_constant_map()


# --- preserve-concealment-semantics: _draw_rocks() kind==1 cover ("hedge" pre-reskin)
# is pass-through tall-grass concealment, not a hard wall — a cactus reskin would falsely
# imply blocking cover. ROCK_KIND_COVER (main.gd) is the single source of truth the draw
# switch itself reads the sprite name from, so this reads the const directly rather than
# parsing _draw_rocks()'s source text: the mapping can't drift out of sync with the actual
# draw call, and the guard survives re-indents/comment edits that broke a line-based scan. ---

func test_kind1_rock_cover_stays_concealment_not_blocking() -> void:
	var cover: Dictionary = _consts().get("ROCK_KIND_COVER", {})
	Runner.T.ok(cover.has(1), "ROCK_KIND_COVER must define kind==1 (concealment)")
	if not cover.has(1):
		return
	var k1: Dictionary = cover[1]
	Runner.T.eq(k1.get("blocking", true), false, "kind==1 (concealment) must be marked non-blocking")
	Runner.T.eq(k1.get("sprite", ""), "dry_shrub", "kind==1 (concealment) must draw dry_shrub")
	Runner.T.ok(str(k1.get("sprite", "")).find("cactus") == -1,
		"kind==1 (concealment) must not be reskinned to cactus — that reads as blocking cover")
