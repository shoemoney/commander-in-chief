extends RefCounted
## ONE PIXEL GRID for non-infantry art: vehicles, bosses, bunker, crates, cover and
## rocks are BAKED (tools/bake_sprites.py PROP_FAMILIES) to their exact on-screen size
## and drawn at NET scale 1.0. Everything here measures what Art serves: the
## texture's own pixels, the SCALE the draw path applies, and the opaque footprint
## that results. The DESIGN footprints are the pre-bake values (alpha>0.35 bbox of the
## old source x call scale x old SCALE) -- they come from the old art, not from the
## rows this change edited, so a bake that drifts fails against the old design.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")

const INK := Color8(13, 15, 10)

## key -> [canonical call scale read off the draw site in main.gd, design footprint px]
const PROPS := {
	"tank_body": [0.62, Vector2(32.1, 28.6)], "tank_barrel": [0.62, Vector2(7.7, 21.8)],
	"m_technical": [0.55, Vector2(20.5, 26.1)], "tank_hulk": [0.62, Vector2(28.1, 33.5)],
	"gunship_body": [1.3, Vector2(85.4, 67.9)], "gunship_barrel": [1.3, Vector2(7.8, 24.1)],
	"colossus_body": [1.9, Vector2(112.1, 109.9)], "colossus_barrel": [1.3, Vector2(21.8, 40.6)],
	"bunker": [0.78, Vector2(47.9, 41.1)], "bunker2": [0.78, Vector2(47.9, 41.1)],
	"crate_ammo": [0.55, Vector2(21.3, 19.9)], "crate_grenade": [0.55, Vector2(21.3, 19.9)],
	"crate_airstrike": [0.55, Vector2(21.3, 19.9)], "sandbag_beige": [0.484, Vector2(31.7, 15.7)],
	"barrel": [1.4, Vector2(20.6, 21.1)], "tank_trap": [0.9, Vector2(20.9, 20.9)],
	"wreck": [1.0, Vector2(22.8, 27.7)], "rock1": [1.3, Vector2(24.7, 23.5)],
	"rock2": [1.05, Vector2(29.3, 26.8)],
}


static func _image(key: String) -> Image:
	var img: Image = Art.tex(key).get_image()
	if img.is_compressed():
		img.decompress()
	return img


static func _alpha_hardness(img: Image) -> float:
	var hard := 0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a < 0.004 or a > 0.996:
				hard += 1
	return float(hard) / float(img.get_width() * img.get_height())


static func _keyline_ratio(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var ring := 0
	var ink := 0
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
				or img.get_pixel(x - 1, y).a < 0.5 or img.get_pixel(x + 1, y).a < 0.5 \
				or img.get_pixel(x, y - 1).a < 0.5 or img.get_pixel(x, y + 1).a < 0.5
			if edge:
				ring += 1
				var c := img.get_pixel(x, y)
				if absf(c.r - INK.r) < 0.01 and absf(c.g - INK.g) < 0.01 and absf(c.b - INK.b) < 0.01:
					ink += 1
	return float(ink) / float(maxi(ring, 1))


static func _footprint(img: Image) -> Vector2:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return Vector2(x1 - x0 + 1, y1 - y0 + 1)


func test_net_draw_scale_is_one() -> void:
	for key in PROPS:
		var call_scale: float = PROPS[key][0]
		var net: float = call_scale * Art.draw_scale(key)
		Runner.T.ok(absf(net - 1.0) < 0.001,
			"%s draws at net scale 1.0 (call %.3f x SCALE %.3f = %.4f): no draw-time resample" % [key, call_scale, Art.draw_scale(key), net])
		Runner.T.ok(Art.tex(key).resource_path.contains("/baked/"),
			"%s serves a baked PNG, not the raw source (%s)" % [key, Art.tex(key).resource_path])


func test_baked_props_have_hard_alpha_and_a_keyline() -> void:
	for key in PROPS:
		var img := _image(key)
		Runner.T.ok(_alpha_hardness(img) >= 0.99, "%s has hard alpha (no soft edge to shimmer)" % key)
		Runner.T.ok(_keyline_ratio(img) >= 0.95, "%s wears the shared 1px ink keyline (%.2f)" % [key, _keyline_ratio(img)])


func test_opaque_footprint_stays_where_the_design_put_it() -> void:
	for key in PROPS:
		var call_scale: float = PROPS[key][0]
		var want: Vector2 = PROPS[key][1]
		var got := _footprint(_image(key)) * call_scale * Art.draw_scale(key)
		var tol_x := maxf(2.0, want.x * 0.06)
		var tol_y := maxf(2.0, want.y * 0.06)
		Runner.T.ok(absf(got.x - want.x) <= tol_x and absf(got.y - want.y) <= tol_y,
			"%s footprint %.1fx%.1f is within tolerance of the design %.1fx%.1f" % [key, got.x, got.y, want.x, want.y])


func test_baked_canvas_has_an_even_size_so_the_pivot_stays_on_a_pixel_edge() -> void:
	for key in PROPS:
		var sz := _image(key).get_size()
		Runner.T.ok(sz.x % 2 == 0 and sz.y % 2 == 0, "%s canvas %s is even" % [key, sz])


func test_the_checks_can_fail() -> void:
	# Controls: a soft, ringless copy must be rejected by the same predicates.
	var img := _image("crate_ammo")
	var soft := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a *= 0.5 if c.a > 0.5 else 0.0
			soft.set_pixel(x, y, c)
	Runner.T.ok(_alpha_hardness(soft) < 0.99, "control: a half-alpha sprite is rejected as soft")
	var ringless := img.duplicate() as Image
	for y in ringless.get_height():
		for x in ringless.get_width():
			var c := ringless.get_pixel(x, y)
			if absf(c.r - INK.r) < 0.01 and c.a > 0.5:
				ringless.set_pixel(x, y, Color(0.8, 0.8, 0.8, 1.0))
	Runner.T.ok(_keyline_ratio(ringless) < 0.5, "control: a sprite with no ink ring is rejected")
