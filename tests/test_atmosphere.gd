extends RefCounted
## Atmosphere (src/view/atmosphere.gd): per-sector weather and drifting light.
## The ratchets here MEASURE the planner's output and a CPU composite of it --
## ops, rects, colours, and rendered pixels -- not constants the implementation
## declares about itself.

const Runner := preload("res://tests/run_tests.gd")

const FRAMES := [0, 137, 411, 900, 1733, 4096]
const SOFT := 64

var _soft: Image = null


func _soft_img() -> Image:
	if _soft == null:
		_soft = Art.tex("fx_softspot").get_image()
		if _soft.is_compressed():
			_soft.decompress()
		_soft.resize(SOFT, SOFT, Image.INTERPOLATE_BILINEAR)
	return _soft


func _all_ops(sector: int, frames: int, motion := 1.0, cam := 0.0) -> Array:
	var ops: Array = []
	for layer in [Atmosphere.Layer.UNDER, Atmosphere.Layer.MID, Atmosphere.Layer.OVER]:
		ops.append_array(Atmosphere.plan(sector, frames, motion, cam, layer))
	return ops


## Source-over composite of ops onto img, exactly what draw_texture_rect / draw_rect
## with a modulate colour do. Returns nothing; mutates img.
func _composite(img: Image, ops: Array) -> void:
	var soft := _soft_img()
	for op in ops:
		var r: Rect2 = op["r"]
		var c: Color = op["c"]
		var x0 := maxi(0, int(r.position.x))
		var y0 := maxi(0, int(r.position.y))
		var x1 := mini(img.get_width(), int(ceil(r.end.x)))
		var y1 := mini(img.get_height(), int(ceil(r.end.y)))
		for y in range(y0, y1):
			for x in range(x0, x1):
				var a := c.a
				if op["tex"]:
					var sx := clampi(int((float(x) - r.position.x) / r.size.x * SOFT), 0, SOFT - 1)
					var sy := clampi(int((float(y) - r.position.y) / r.size.y * SOFT), 0, SOFT - 1)
					a *= soft.get_pixel(sx, sy).a
				if a <= 0.0:
					continue
				var d := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(
					d.r + (c.r - d.r) * a, d.g + (c.g - d.g) * a, d.b + (c.b - d.b) * a, 1.0))


func _ground(col: Color) -> Image:
	var img := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return img


func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## RGB distance between a mark's centre and the mean of the ground ring 5px around it.
func _contrast(img: Image, p: Vector2i) -> float:
	var sum := Vector3.ZERO
	var ring := [Vector2i(5, 0), Vector2i(-5, 0), Vector2i(0, 5), Vector2i(0, -5),
		Vector2i(4, 4), Vector2i(-4, -4), Vector2i(4, -4), Vector2i(-4, 4)]
	for o in ring:
		var q := img.get_pixel(p.x + o.x, p.y + o.y)
		sum += Vector3(q.r, q.g, q.b)
	sum /= float(ring.size())
	var c := img.get_pixel(p.x, p.y)
	return Vector3(c.r, c.g, c.b).distance_to(sum)


func test_every_sector_has_air_and_the_early_return_is_gone() -> void:
	for s in Atmosphere.SECTORS:
		var n := 0
		for f in FRAMES:
			n = maxi(n, _all_ops(s, f).size())
		Runner.T.ok(n >= 8, "sector %d has visible atmosphere (max %d ops over sampled frames)" % [s, n])


func test_draw_budget_and_viewport_cull() -> void:
	var peak := 0
	for s in Atmosphere.SECTORS:
		for f in FRAMES:
			var ops := _all_ops(s, f, 1.0, float(f) * 0.7)
			peak = maxi(peak, ops.size())
			Runner.T.ok(ops.size() <= Atmosphere.MAX_OPS,
				"sector %d frame %d: %d ops within budget %d" % [s, f, ops.size(), Atmosphere.MAX_OPS])
			var vp := Rect2(0, 0, 640, 360)
			for op in ops:
				Runner.T.ok(vp.intersects(op["r"]), "sector %d op %s is culled to the viewport" % [s, op["k"]])
	print("ATMOS peak draw ops per frame: %d (+3 legacy embers)" % peak)


func test_colours_stay_out_of_the_lethal_band() -> void:
	# Bullets are hue 0 (LETHAL_RED), mines/hazards are saturated amber: an atmosphere
	# colour must be near-grey (low saturation) or cool blue, and never opaque.
	for kind in Atmosphere.KINDS:
		var c: Color = Atmosphere.KINDS[kind]["col"]
		var h := c.h * 360.0
		var cool := h >= 170.0 and h <= 260.0
		Runner.T.ok(c.s <= 0.25 or cool,
			"%s colour sat %.2f hue %.0f is near-grey or cool, not the warm/red band" % [kind, c.s, h])
		Runner.T.ok(c.a <= Atmosphere.MAX_ALPHA + 0.001, "%s alpha %.2f is capped" % [kind, c.a])
	for s in Atmosphere.SECTORS:
		for kind in Atmosphere.PROFILES[s]:
			Runner.T.ok(Atmosphere.KINDS.has(kind), "sector %d names a real kind: %s" % [s, kind])


func test_planner_is_deterministic_and_motion_actually_moves_it() -> void:
	for s in Atmosphere.SECTORS:
		Runner.T.eq(_all_ops(s, 500), _all_ops(s, 500), "sector %d plan is a pure function of its inputs" % s)
		Runner.T.ok(_all_ops(s, 500) != _all_ops(s, 800), "sector %d drifts over time" % s)


func test_reduce_motion_freezes_and_thins() -> void:
	for s in Atmosphere.SECTORS:
		var a := _all_ops(s, 100, 0.0)
		var b := _all_ops(s, 9000, 0.0)
		Runner.T.eq(a, b, "sector %d under reduce-motion is static (no drift)" % s)
		Runner.T.ok(a.size() <= _all_ops(s, 100, 1.0).size(), "sector %d reduce-motion never adds ops" % s)
		for op in a:
			var kind: String = op["k"]
			Runner.T.ok(not Atmosphere.KINDS[kind].get("motion_only", false),
				"sector %d reduce-motion drops motion-only kind %s" % [s, kind])


func test_endless_picks_air_from_the_wave_tier() -> void:
	Runner.T.eq(Atmosphere.sector_for(0.0, true, 1), 0, "wave 1 breathes sector-1 air")
	Runner.T.eq(Atmosphere.sector_for(0.0, true, 7), 3, "wave 7 -> tier 3")
	Runner.T.eq(Atmosphere.sector_for(0.0, true, 40), 5, "late waves clamp to the foundry")
	Runner.T.eq(Atmosphere.sector_for(0.4, false, 0), 2, "campaign follows the sector march")
	Runner.T.eq(Atmosphere.sector_for(1.0, false, 0), 5, "the finale march is the ember air")


func test_coverage_stays_low() -> void:
	# Fraction of pixels visibly changed (> 6/255 luma) versus a no-atmosphere render.
	for s in Atmosphere.SECTORS:
		var worst := 0.0
		for f in [200, 2600]:
			var base := _ground(Color(0.42, 0.45, 0.3) if s < 3 else Color(0.5, 0.45, 0.38))
			var img := base.duplicate() as Image
			_composite(img, _all_ops(s, f))
			var changed := 0
			for y in range(0, 360, 2):
				for x in range(0, 640, 2):
					if absf(_luma(img.get_pixel(x, y)) - _luma(base.get_pixel(x, y))) > 6.0 / 255.0:
						changed += 1
			worst = maxf(worst, float(changed) / float(320 * 180))
		Runner.T.ok(worst < 0.15, "sector %d visibly alters %.1f%% of pixels (limit 15%%)" % [s, worst * 100.0])
		print("ATMOS coverage sector %d: %.2f%%" % [s, worst * 100.0])


func test_bullets_and_mines_stay_as_readable_with_atmosphere() -> void:
	# Staged frame: ground, atmosphere UNDER+MID, then actors (bullets, mines), then OVER.
	# Contrast = RGB distance between the mark centre and the mean of the ground ring around it.
	var worst := 9.0
	var total := 0.0
	var n := 0
	for s in Atmosphere.SECTORS:
		for f in [150, 1900]:
			var ground := Color(0.42, 0.45, 0.3) if s < 3 else Color(0.5, 0.45, 0.38)
			var bare := _ground(ground)
			var live := _ground(ground)
			var under_mid: Array = Atmosphere.plan(s, f, 1.0, 40.0, Atmosphere.Layer.UNDER) \
				+ Atmosphere.plan(s, f, 1.0, 40.0, Atmosphere.Layer.MID)
			var over: Array = Atmosphere.plan(s, f, 1.0, 40.0, Atmosphere.Layer.OVER)
			_composite(live, under_mid)
			var marks: Array = []
			for gy in 5:
				for gx in 8:
					var p := Vector2i(40 + gx * 76, 50 + gy * 60)
					var col := Color(1.0, 0.15, 0.1) if (gx + gy) % 2 == 0 else Color(1.0, 0.6, 0.1)
					marks.append(p)
					for img in [bare, live]:
						for dy in range(-1, 2):
							for dx in range(-1, 2):
								img.set_pixel(p.x + dx, p.y + dy, col)
			_composite(live, over)
			for p in marks:
				var cb := _contrast(bare, p)
				var cl := _contrast(live, p)
				var ratio := cl / cb
				worst = minf(worst, ratio)
				total += ratio
				n += 1
	var mean := total / float(n)
	print("ATMOS readability: worst contrast ratio %.3f, mean %.3f over %d marks" % [worst, mean, n])
	Runner.T.ok(worst >= 0.75, "no bullet/mine loses more than 25%% of its contrast (worst %.3f)" % worst)
	Runner.T.ok(mean >= 0.93, "average contrast is essentially preserved (mean %.3f)" % mean)


func test_main_wires_the_atmosphere_in_the_right_order() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("func _draw_atmosphere_ground()"), "ground-level pass exists")
	Runner.T.ok(src.contains("func _draw_atmosphere_over()"), "foreground pass exists")
	var i_ground := src.find("\t_draw_atmosphere_ground()\n\t_draw_hazard_telegraphs()")
	var i_mines := src.find("\t_draw_mines()\n\t_draw_rocks()")
	var i_actors := src.find("\t_draw_players()\n")
	var i_over := src.find("\t_draw_atmosphere_over()\n\t_draw_telegraphs()")
	Runner.T.ok(i_ground > 0 and i_ground < i_mines, "weather is laid down BEFORE mines and hazard telegraphs")
	Runner.T.ok(i_over > i_actors, "foreground specks come after the actors")
	Runner.T.ok(i_over > 0, "foreground specks sit below the telegraphs")
