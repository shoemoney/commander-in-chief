extends RefCounted
## Camera aim-lead + player locator. Both are VIEW-ONLY (nothing here may reach
## SimWorld.checksum()); these pin the behaviours a reviewer would feel:
##   * the lead is bounded, never overshoots, and is EXACTLY zero under reduce-motion / no shake;
##   * the mouse -> aim mapping still round-trips through the canvas transform with a lead applied;
##   * every alive soldier has a locator ring, and spawn / revive / roll-end each fire one pulse;
##   * MEASURED: composited over dense ground the ring is more visible than the pre-change ring.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")


func _players(n := 2) -> Array:
	return SimWorld.new(7, n, "campaign").players


func test_lead_is_bounded_critically_damped_and_leads_toward_the_aim() -> void:
	var lead := CameraLead.new()
	var peak := 0.0
	var prev := 0.0
	var monotone := true
	for _t in 240:
		lead.step(Vector2(0, -1), 1.0)   # aiming up the scroll axis
		peak = maxf(peak, absf(lead.offset.y))
		if absf(lead.offset.y) < prev - 0.0001:
			monotone = false
		prev = absf(lead.offset.y)
	Runner.T.ok(lead.offset.y > 8.0 and lead.offset.y <= 12.0,
		"steady lead is ~8-12 px (got %.2f)" % lead.offset.y)
	Runner.T.ok(peak <= CameraLead.MAX_PX.y + 0.01, "critically damped: never overshoots the target (peak %.3f)" % peak)
	Runner.T.ok(monotone, "the approach is monotone (no wobble)")
	Runner.T.eq(lead.offset.x, 0.0, "no horizontal lead: the 640px water/strips would un-draw a bank stripe")
	var diag := CameraLead.new()
	for _t in 240:
		diag.step(Vector2(1, 1).normalized(), 1.0)
	Runner.T.eq(diag.offset.x, 0.0, "a diagonal aim still leaves X untouched")


func test_lead_is_exactly_zero_when_strength_is_zero() -> void:
	var lead := CameraLead.new()
	for _t in 120:
		lead.step(Vector2(0, 1), 1.0)
	Runner.T.ok(lead.offset != Vector2.ZERO, "precondition: the lead was live")
	lead.step(Vector2(0, 1), 0.0)
	Runner.T.eq(lead.offset, Vector2.ZERO, "strength 0 snaps the offset to exactly zero")
	Runner.T.eq(lead.velocity, Vector2.ZERO, "...and kills the velocity so it cannot creep back")


func test_main_lead_strength_follows_reduce_motion_and_the_harness_flag() -> void:
	var m := Main.new()
	m._motion = 0.0   # reduce-motion
	Runner.T.eq(m._lead_strength(), 0.0, "reduce-motion -> lead strength exactly 0")
	m._motion = 1.0
	Runner.T.ok(m._lead_strength() > 0.0, "motion on -> lead strength live")
	m.no_autopause = true   # the screenshot harnesses' flag
	Runner.T.eq(m._lead_strength(), 0.0, "screenshot harness -> zero lead so posed shots stay byte-reproducible")
	m.free()


func test_mean_aim_ignores_downed_players_and_cancels_opposites() -> void:
	var ps := _players(2)
	ps[0]["aim_x"] = 0; ps[0]["aim_y"] = -Fixed.ONE
	ps[1]["aim_x"] = 0; ps[1]["aim_y"] = Fixed.ONE
	Runner.T.ok(CameraLead.mean_aim(ps).length() < 0.001, "opposed co-op aims cancel: the frame stays put")
	ps[1]["alive"] = false
	Runner.T.ok(CameraLead.mean_aim(ps).y < -0.99, "a downed partner no longer pulls the frame")
	ps[0]["alive"] = false
	Runner.T.eq(CameraLead.mean_aim(ps), Vector2.ZERO, "nobody alive -> no lead")


func test_mouse_aim_round_trips_through_the_canvas_transform_with_a_lead() -> void:
	# main computes aim as get_local_mouse_position() - _to_screen(player): local = inverse(canvas) * screen.
	var lead := CameraLead.new()
	for _t in 240:
		lead.step(Vector2(0, -1), 1.0)
	Runner.T.ok(lead.offset.y > 8.0, "precondition: non-zero lead")
	var xf := Transform2D(0.0, Vector2(3.0, 5.0) + lead.offset)   # kick + lead, as main.position
	var player_local := Vector2(320, 200)
	for dir in [Vector2(0, -1), Vector2(1, 0), Vector2(0.6, 0.8), Vector2(-0.8, -0.6)]:
		var mouse_screen: Vector2 = xf * (player_local + dir * 60.0)
		var to_mouse: Vector2 = (xf.affine_inverse() * mouse_screen) - player_local
		Runner.T.ok(to_mouse.normalized().distance_to(dir) < 0.0001,
			"aim direction %s survives the lead (got %s)" % [dir, to_mouse.normalized()])
		Runner.T.ok(absf(to_mouse.length() - 60.0) < 0.001, "...and so does the distance")
	# Shake-immune HUD edge elements draw through get_transform().affine_inverse(): HUD stays put.
	var hud_pt := Vector2(320, 12)
	Runner.T.eq(xf * (xf.affine_inverse() * hud_pt), hud_pt, "screen-anchored points are exactly cancelled by the inverse")


func test_main_folds_the_lead_into_position_but_not_when_off() -> void:
	var m := Main.new()
	m._camera_lead.offset = Vector2(0, -9.0)
	m._motion = 1.0
	Runner.T.eq(m._lead_shift(), Vector2(0, -9.0), "the live offset is what main adds to position")
	m._motion = 0.0
	Runner.T.eq(m._lead_shift(), Vector2.ZERO, "reduce-motion: shift is zero even if a stale offset is cached")
	m.free()


func test_locator_layers_exist_for_each_alive_player_with_their_own_colour() -> void:
	var ps := _players(2)
	var c0: Color = Main._player_ident_color(0)
	var c1: Color = Main._player_ident_color(1)
	var l0 := PlayerLocator.layers(ps[0]["alive"], c0, -1)
	var l1 := PlayerLocator.layers(ps[1]["alive"], c1, -1)
	Runner.T.ok(l0.size() == 2 and l1.size() == 2, "each alive player: a dark under-ring + a rim")
	Runner.T.ok(l0[1]["col"].r != l1[1]["col"].r or l0[1]["col"].g != l1[1]["col"].g, "P1 and P2 rims differ in colour")
	Runner.T.eq(PlayerLocator.layers(false, c0, -1).size(), 0, "a downed soldier has no ring (the body is the marker)")
	Runner.T.ok(l0[0]["col"].r < 0.1 and l0[0]["col"].g < 0.1 and l0[0]["col"].b < 0.1, "under-ring is dark")
	var hue := c0.h
	Runner.T.ok(hue > 0.2 and hue < 0.7, "P1 rim stays out of the lethal red/orange band (hue %.2f)" % hue)


func test_pulse_fires_on_spawn_revive_and_roll_end_and_expires() -> void:
	var ps := _players(2)
	var loc := PlayerLocator.new()
	var s := loc.observe(ps)
	Runner.T.eq(s, [0, 1], "first sight of alive soldiers == spawn pulse for both")
	for _t in PlayerLocator.PULSE_TICKS + 2:
		s = loc.observe(ps)
	Runner.T.eq(s, [], "no pulse while nothing changes")
	Runner.T.eq(loc.pulse_age[0], -1, "pulse expires")
	ps[1]["alive"] = false
	Runner.T.eq(loc.observe(ps), [], "going down does not pulse")
	ps[1]["alive"] = true   # respawn / revive
	Runner.T.eq(loc.observe(ps), [1], "revive pulses that player only")
	ps[0]["roll_ticks"] = 5
	Runner.T.eq(loc.observe(ps), [], "starting a roll does not pulse")
	ps[0]["roll_ticks"] = 0
	Runner.T.eq(loc.observe(ps), [0], "the end of the roll pulses")
	var mid := PlayerLocator.layers(true, Color.GREEN, 6)
	Runner.T.eq(mid.size(), 4, "a running pulse adds its own dark+rim pair")
	Runner.T.ok(mid[3]["r"] > PlayerLocator.RING_R, "the pulse ring has expanded past the steady ring")


# ---- measured contrast -------------------------------------------------------

static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Dense, high-frequency clutter patch (litter / corpses / craters stand-in) at mixed
## brightness, deterministic.
static func _clutter(seed_v: int, base: float) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var img := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 40:
			var v := clampf(base + rng.randf_range(-0.28, 0.28), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v * 0.95, v * 0.8, 1.0))
	return img


static func _ring_px(layers: Array) -> Dictionary:
	## Composite `layers` ({r,w,col}) with the SAME pixel set Art.arc stamps; returns
	## {Vector2i: [rgb-premultiplied-over function inputs]} as an ordered layer list per pixel.
	var out := {}
	for L in layers:
		var entry := Art._ring_entry(int(L["r"]), maxi(1, int(L["w"])), false)
		for o in entry["offsets"]:
			var k := Vector2i(int(o.x), int(o.y))
			if not out.has(k):
				out[k] = []
			out[k].append(L["col"])
	return out


## Per-bearing ring visibility: for each of 32 angular buckets take the LARGEST luminance
## change any ring pixel in that bucket makes versus the bare ground (a ring is seen where
## some part of its cross-section stands out). Returns (mean, 10th percentile) over buckets
## -- the percentile is the stretch of the ring that is hardest to find.
static func _visibility(layers: Array, bg: Image) -> Vector2:
	var px := _ring_px(layers)
	var best: Array[float] = []
	best.resize(32)
	best.fill(0.0)
	for k in px:
		var base: Color = bg.get_pixel(20 + k.x, 20 + k.y)
		var c := base
		for col in px[k]:
			c = Color(lerpf(c.r, col.r, col.a), lerpf(c.g, col.g, col.a), lerpf(c.b, col.b, col.a), 1.0)
		var bucket := int(fposmod(atan2(float(k.y), float(k.x)), TAU) / TAU * 32.0) % 32
		best[bucket] = maxf(best[bucket], absf(_lum(c) - _lum(base)))
	var sorted := best.duplicate()
	sorted.sort()
	var sum := 0.0
	for d in best:
		sum += d
	return Vector2(sum / 32.0, sorted[3])


func test_ring_contrast_beats_the_old_ring_on_dense_clutter() -> void:
	var ident := Main._player_ident_color(0)
	# The pre-change ring, as it was drawn: soft-footprint excluded (it is unchanged), dark
	# arc r=roundi(11.5)=12 w3 a0.58, then the identity arc r=10 w=roundi(1.5)=2 a0.6.
	var old_layers := [
		{"r": 12, "w": 3, "col": Color(0.01, 0.015, 0.02, 0.58)},
		{"r": 10, "w": 2, "col": Color(ident.r, ident.g, ident.b, 0.6)},
	]
	var new_layers := PlayerLocator.layers(true, ident, -1)
	var total_old := 0.0
	var total_new := 0.0
	for spec in [[11, 0.78], [12, 0.62], [13, 0.45], [14, 0.25]]:
		var bg := _clutter(spec[0], spec[1])
		var o := _visibility(old_layers, bg)
		var n := _visibility(new_layers, bg)
		total_old += o.x
		total_new += n.x
		Runner.T.ok(n.x > o.x, "mean ring visibility improves on clutter base %.2f (%.3f -> %.3f)" % [spec[1], o.x, n.x])
		Runner.T.ok(n.y >= o.y, "worst-bearing visibility does not regress on base %.2f (%.3f -> %.3f)" % [spec[1], o.y, n.y])
	print("  [camera-locator] ring visibility mean over 4 dense patches: old %.4f -> new %.4f" % [total_old / 4.0, total_new / 4.0])
