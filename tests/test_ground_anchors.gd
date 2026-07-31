extends RefCounted
## GROUND ANCHORS — the heavy-vehicle contact-shadow ratchet.
##
## Every heavy unit calls _ground_shadow, but each call site's radius was
## hand-tuned with no reference to the sprite's on-screen opaque footprint —
## and on the worst offenders the ellipse renders and is then 100% painted
## over by the unit's own sprite (the Foundry Colossus: a 143.5px fully-opaque
## body over a 69x31 shadow whose dark peak ends 47px ABOVE the hull base).
## The units read as 2D stickers pasted on a background.
##
## The fix single-sources the heavy set in main.gd's VEHICLE_CONTACT and
## DERIVES each shadow from the measured opaque footprint (alpha bbox x
## Art.draw_scale x call-site scale — the same measure test_hitbox_fairness
## uses), so a re-bake or re-tint rescales the shadow automatically instead of
## silently re-burying it. This suite pins the three geometric rules a contact
## shadow must satisfy, per unit, from the table itself — a unit added
## tomorrow is asserted the day it lands:
##
##   side skirts    — the ellipse spills past the hull's flanks
##   southern skirt — the ellipse's bottom edge reaches south of the hull base
##   tucked         — the ellipse's top edge starts UNDER the hull (a contact
##                    shadow, not a detached disc floating below the sprite)
##
## All access to the new symbols goes through the Script resource + Callables:
## a direct `MainScript.VEHICLE_CONTACT` reference is a PARSE error on a tree
## that predates the const, which would take the whole suite file down instead
## of failing one assertion.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")
const MainScript := preload("res://src/main.gd")

## The five live heavy units plus the three convoy-graveyard hulks.
const EXPECTED := ["tank_body", "m_technical", "gunship_body", "m_heli_attack2",
	"colossus_body", "wreck_apc", "wreck_technical", "wreck_light_tank"]


func _footprint(tex_name: String, call_scale: float) -> Vector2:
	## The drawn opaque footprint in screen px: alpha bbox x SCALE x call scale.
	## Returns Vector2.ZERO when the texture is missing so the caller can skip
	## rather than assert against a phantom (same idiom as test_hitbox_fairness).
	if not Art.TEX.has(tex_name):
		return Vector2.ZERO
	var t: Texture2D = Art.tex(tex_name)
	if t == null:
		return Vector2.ZERO
	var img := t.get_image()
	if img == null:
		return Vector2.ZERO
	var sz := img.get_size()
	var x0 := sz.x
	var y0 := sz.y
	var x1 := -1
	var y1 := -1
	for y in sz.y:
		for x in sz.x:
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Vector2.ZERO
	var s := call_scale * Art.draw_scale(tex_name)
	return Vector2(float(x1 - x0 + 1) * s, float(y1 - y0 + 1) * s)


func _table() -> Dictionary:
	## VEHICLE_CONTACT, or {} after asserting (guards every method against the
	## silent-abort trap: a missing symbol must fail the run, not skip it).
	var res: Script = MainScript
	var consts: Dictionary = res.get_script_constant_map()
	Runner.T.ok(consts.has("VEHICLE_CONTACT"),
		"main.gd single-sources the heavy unit set in a VEHICLE_CONTACT const")
	if not consts.has("VEHICLE_CONTACT"):
		return {}
	return consts["VEHICLE_CONTACT"]


func _statics() -> Dictionary:
	var res: Script = MainScript
	var methods := {}
	for m in res.get_script_method_list():
		methods[m["name"]] = true
	return methods


func test_vehicle_contact_table_covers_the_heavy_set() -> void:
	var table := _table()
	if table.is_empty():
		return
	for tex in EXPECTED:
		Runner.T.ok(table.has(tex), "VEHICLE_CONTACT covers %s" % tex)
	for tex in table.keys():
		var row: Dictionary = table[tex]
		Runner.T.ok(row.has("call_scale") and row.has("hover"),
			"VEHICLE_CONTACT[%s] carries call_scale + hover" % tex)


func test_heavy_units_cast_visible_contact_shadows() -> void:
	var table := _table()
	if table.is_empty():
		return
	var methods := _statics()
	var spec_fn := Callable(MainScript, "_vehicle_shadow_spec")
	var ellipse_fn := Callable(MainScript, "_shadow_ellipse")
	Runner.T.ok(methods.has("_vehicle_shadow_spec") and methods.has("_shadow_ellipse")
		and spec_fn.is_valid() and ellipse_fn.is_valid(),
		"main.gd hoists _vehicle_shadow_spec + _shadow_ellipse so draw and test share the geometry")
	if not (methods.has("_vehicle_shadow_spec") and methods.has("_shadow_ellipse")
			and spec_fn.is_valid() and ellipse_fn.is_valid()):
		return
	for tex in table.keys():
		var row: Dictionary = table[tex]
		var foot := _footprint(tex, float(row["call_scale"]))
		Runner.T.ok(foot != Vector2.ZERO, "%s: texture measures a non-zero opaque footprint" % tex)
		if foot == Vector2.ZERO:
			continue
		var hover: float = float(row["hover"])
		var spec: Dictionary = spec_fn.call(tex)
		# The drawn rect: the shadow's own ellipse offset south by the spec's
		# y_off — exactly what _vehicle_contact_shadow hands _ground_shadow.
		var rect: Rect2 = ellipse_fn.call(Vector2(0.0, spec["y_off"]), spec["r"])
		var base := foot.y * 0.5 + hover   # hull bottom edge, screen px below pos
		Runner.T.ok(rect.size.x >= foot.x * 1.10,
			"%s: side skirts — shadow %.1fpx wide vs %.1fpx hull (want >=110%%)" % [
				tex, rect.size.x, foot.x])
		Runner.T.ok(rect.end.y >= base + 4.0,
			"%s: southern skirt — shadow bottom +%.1f vs hull base +%.1f (want >= +4px past)" % [
				tex, rect.end.y, base])
		Runner.T.ok(rect.position.y < base,
			"%s: tucked — shadow top +%.1f starts under the hull (base +%.1f), not a detached disc" % [
				tex, rect.position.y, base])
