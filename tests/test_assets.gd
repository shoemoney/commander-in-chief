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
