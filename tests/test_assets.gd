extends RefCounted
## View-layer ASSET invariants (assets review cycle). These pin the art.gd / main.gd
## registries the readability + art-direction systems depend on, so a stray edit that
## (e.g.) light-rims a hero, or drops a hostile from the separator set, fails HERE
## instead of only showing up in a screenshot. Pure const checks — no draw, no sim.

const Runner := preload("res://tests/run_tests.gd")


func _consts() -> Dictionary:
	# Typed as the Script base (not the class) so the instance method resolves —
	# calling it through the preloaded class type is a static-call error.
	var ms: Script = load("res://src/main.gd")
	return ms.get_script_constant_map()


# --- a1-02: small-hostile figure-ground separator rim ---

func test_a1_light_rim_is_a_subset_of_unit_rims() -> void:
	# Every warm-light separator hostile must also be a full unit rim (the width
	# override rides on top of the unit-rim path; a light-rim key with no unit-rim
	# entry would silently get no rim at all).
	var c := _consts()
	var light: Dictionary = c["_LIGHT_RIM"]
	var unit: Dictionary = c["_UNIT_RIM"]
	Runner.T.ok(light.size() >= 8, "the small-hostile separator set is populated (%d)" % light.size())
	for k in light:
		Runner.T.ok(unit.has(k), "light-rim hostile '%s' must also be a unit rim" % k)


func test_a1_light_rim_excludes_friendlies_and_readable_units() -> void:
	# Heroes carry a bright tint + green ID ring; frogman/observer/bombsuit already
	# read — none may take the warm-light HOSTILE separator (it would misread as enemy).
	var light: Dictionary = _consts()["_LIGHT_RIM"]
	for k in ["player1", "player2", "frogman", "observer", "m_bombsuit"]:
		Runner.T.ok(not light.has(k), "'%s' must keep the neutral rim, not the hostile separator" % k)


# --- a1-03: water body follows the 5-stop biome ramp ---

func test_a1_water_stops_are_five_and_biome_distinct() -> void:
	var c := _consts()
	var shallow: Array = c["_WATER_SHALLOW_STOPS"]
	var deep: Array = c["_WATER_DEEP_STOPS"]
	Runner.T.eq(shallow.size(), 5, "water shallow ramp has one stop per sector")
	Runner.T.eq(deep.size(), 5, "water deep ramp has one stop per sector")
	# jungle stop unchanged (the river opener must stay teal, not go muddy early)
	Runner.T.ok(shallow[0].is_equal_approx(Color(0.21, 0.44, 0.47)), "jungle shallow stays teal")
	# the journey actually MOVES: the foundry water must be far from the jungle water
	# (the old capped soot-lerp left it muddy-blue). Warm/red foundry vs cool jungle.
	Runner.T.ok(deep[4].r > deep[0].r + 0.1, "foundry deep water is warmer (redder) than jungle")
	Runner.T.ok(deep[4].b < deep[0].b - 0.1, "foundry deep water is far less blue than jungle")
	# mid-stops carry their biome, not just the endpoints (judge a1-03 r2):
	Runner.T.ok(shallow[2].g > shallow[2].b and shallow[2].g > shallow[2].r,
		"marsh (sector 2) shallow leans GREEN — murk, not blue")
	Runner.T.ok(deep[3].b < deep[0].b - 0.08 and absf(deep[3].r - deep[3].g) < 0.06,
		"ruins (sector 3) deep is a de-blued neutral SLATE, not the jungle blue")
	# Rendered evidence (jungle river stays teal, no regression):
	# scratchpad/shots_a1_v5/03-river-crossing.png


# --- a1-05: foliage tint ramps to ash (no green re-bias at the foundry) ---

func test_a1_foliage_tint_ramps_to_ash() -> void:
	Art.foliage_march = 0.0
	Runner.T.ok(Art.tint("fern").is_equal_approx(Art.FOLIAGE), "jungle (march 0) keeps the lush FOLIAGE tint")
	Art.foliage_march = 1.0
	var f := Art.tint("fern")
	Runner.T.ok(f.is_equal_approx(Art.FOLIAGE_ASH), "foundry (march 1) foliage chars to FOLIAGE_ASH")
	Runner.T.ok(f.g < Art.FOLIAGE.g - 0.2, "charred foliage loses green — no re-green multiply at the foundry")
	Runner.T.ok(Art.tint("tree_large").is_equal_approx(Art.FOLIAGE_ASH), "trees ramp with ferns")
	# the ramp is foliage-ONLY: unit/decor tints are untouched
	Runner.T.ok(Art.tint("rusher").is_equal_approx(Color(2.1, 1.7, 1.15)), "unit tints ignore foliage_march")
	Art.foliage_march = 0.0   # restore the static for other suites


# --- a1-07: crater depression pit is scorched-only ---

func test_a1_crater_pit_keys() -> void:
	var ck: Dictionary = _consts()["_CRATER_KEYS"]
	Runner.T.ok(ck.has("crater") and ck.has("crater_field"), "scorched craters get the depression pit")
	Runner.T.ok(not ck.has("crater_water"), "water-filled craters are excluded from the dark pit")


# --- a1-08: white-hot explosion core constants ---

func test_a1_explosion_white_core_consts() -> void:
	var c := _consts()
	var wt: float = c["EXPLO_WHITE_T"]
	Runner.T.ok(wt > 0.0 and wt < 0.35, "white-hot lead is a brief opening fraction of the blast life")
	Runner.T.ok(c["EXPLO_WHITE_R_OUT"] > c["EXPLO_WHITE_R_IN"], "the outer white ring is larger than the inner core")
