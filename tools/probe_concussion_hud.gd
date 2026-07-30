extends SceneTree
## Pixel pin for the concussion low-pass (the measured half of smoke.gd's
## structural layer pin): the effect must blur the WORLD and leave the HUD
## chrome — boss-bar dock band, corner plate, control prompts — bit-crisp.
##
## It boots the real main scene, starts a campaign run (the title hides
## _hud_icons, so gameplay is the state that carries the chrome under test),
## then captures three frames: A at concussion 0, B at concussion 0.7, C back
## at 0. It asserts:
##   1. baseline HUD motion diff(A,C) is small  (window stability — a noisy
##      window reads as INCONCLUSIVE, never as a verdict)
##   2. B keeps >= 85% of A's strong HUD edges  (THE PIN — the HUD plates are
##      translucent, so a world-only blur still moves the composite under the
##      ink and a pixel diff CANNOT tell crisp from smeared; what a blur over
##      the HUD cannot fake is edge survival. On the pre-fix layering the
##      concussion rect rode above the HUD and radial-blurred it: top edges
##      measured 1383->882, bottom 611->391 = FAIL. Post-fix 1383->1337,
##      611->586 = OK.)
##   3. a mid-screen WORLD band differs A<->B (the effect actually rendered —
##      a check that passes because nothing drew is decoration)
##
## Needs a GL context (the screen-reading shader is a no-op without one):
##   godot --path . --rendering-method gl_compatibility -s res://tools/probe_concussion_hud.gd
## No sampling-window hazard: the probe sets _concussion directly and captures
## at peak; decay is x0.9/frame from 0.7 (~47 frames to 0.01), the capture is 2.

const LOGICAL_H := 360.0
const HUD_TOP_LOGICAL := 64.0      # HudIcons.BOSS_BAR_TOP — the top HUD band
const HUD_BOTTOM_LOGICAL := 30.0   # bottom control-prompt strip (VERB_LEGEND_Y 344)
const WORLD_Y0_LOGICAL := 180.0    # mid-screen world band, clear of both HUD strips
const WORLD_Y1_LOGICAL := 260.0
const MIN_WORLD_DIFF_PIXELS := 500
const STABLE_CEILING_PX := 400   # max baseline HUD motion before the window reads as noisy
const EDGE_LUMA_JUMP := 0.19     # ~48/255 — a strong ink/plate or ink/world edge
const EDGE_KEEP_RATIO := 0.85    # concussion frame must keep >= 85% of the band's strong edges

var _main: Node2D


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("probe_concussion_hud: --headless has no framebuffer — run under a GL context, e.g. --rendering-method gl_compatibility")
		print("PROBE UNUSABLE — headless has no framebuffer; nothing was captured")
		quit(1)
		return
	seed(0xC0FFEE)   # same reason screenshots.gd does: fx jitter off the engine RNG
	_main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_main.no_autopause = true   # the probe window never holds focus
	_run()


func _run() -> void:
	# Boot settle, then retire the splash and start a real campaign run so the
	# HUD carries its gameplay chrome (boss-bar dock, corner plate, prompts).
	for _i in 30:
		await process_frame
	_main._splash_t = 0.0
	if _main._splash_layer != null:
		_main._splash_layer.visible = false
	_main.start_game(false)
	# Settle just past the run-in banner / verb-legend fade, but BEFORE combat
	# reaches the idle player: late captures sit in a particle-filled firefight
	# whose smoke drifts on the RENDER thread (physics freeze does not stop it —
	# measured 40k/41k px of top-band motion at frame 900, with and without the
	# freeze). Early game is near-static: ~170 px of HUD motion at frame 120.
	for _i in 150:
		await process_frame
	# Take the always-on grade + scanline passes out of the frame: their animated /
	# FRAGCOORD content is not under test, and A/B may differ ONLY through the
	# concussion pass. Matched by identity against main's own material refs so the
	# concussion rect (a fx_layer sibling on the pre-fix layout) stays up.
	for layer in _main.get_children():
		if not layer is CanvasLayer:
			continue
		for c in layer.get_children():
			var mat: Variant = c.get("material")
			if mat != null and (mat == _main._grade_mat or (_main._scan_mat != null and mat == _main._scan_mat)):
				c.visible = false
	# Freeze the sim for the capture window: a LIVE game ticks score/coin/pressure
	# and spawns floattexts into the HUD bands, so no two frames of a running game
	# are ever bit-identical (measured: 60k px of baseline HUD motion in a god-mode
	# firefight). With physics off the values stop moving; _process still runs, so
	# the concussion uniform push + decay are unaffected.
	_main.set_physics_process(false)
	await process_frame
	var a := await _capture()
	_main._concussion = 0.7
	await process_frame   # _process pushes the uniform this frame
	var b := await _capture()
	_main._concussion = 0.0
	await process_frame
	var c := await _capture()
	_main.set_physics_process(true)

	var dump := OS.get_environment("PROBE_SHOT_DIR")
	if not dump.is_empty():
		a.save_png(dump.path_join("probe_a.png"))
		b.save_png(dump.path_join("probe_b.png"))
		c.save_png(dump.path_join("probe_c.png"))

	var scale := a.get_height() / LOGICAL_H
	var top0 := 0
	var top1 := int(HUD_TOP_LOGICAL * scale)
	var bot0 := int((LOGICAL_H - HUD_BOTTOM_LOGICAL) * scale)
	var bot1 := a.get_height()
	var wy0 := int(WORLD_Y0_LOGICAL * scale)
	var wy1 := int(WORLD_Y1_LOGICAL * scale)

	var fail := false
	# Window stability: baseline HUD motion across two concussion-0 frames. Early
	# game this is near-zero, but not exactly — a verb-legend glyph idles (~60 px
	# measured at frame 150). Bit-identity is therefore the WRONG assertion; the
	# pin is "concussion adds no motion of its own": diff(A,B) must not exceed the
	# baseline diff(A,C). The ceiling keeps a genuinely noisy window INCONCLUSIVE
	# rather than letting baseline motion ratchet the bar up to the blur's reach.
	var ac_top := _band_diff(a, c, top0, top1)
	var ac_bot := _band_diff(a, c, bot0, bot1)
	if ac_top > STABLE_CEILING_PX or ac_bot > STABLE_CEILING_PX:
		push_error("probe_concussion_hud: baseline HUD motion across the window is %d px top / %d px bottom (> %d) — the capture window is noisy, so this run is INCONCLUSIVE, not a verdict" % [ac_top, ac_bot, STABLE_CEILING_PX])
		print("PROBE INCONCLUSIVE — baseline HUD motion %d px top / %d px bottom" % [ac_top, ac_bot])
		quit(1)
		return
	var ab_top := _band_diff(a, b, top0, top1)
	var ab_bot := _band_diff(a, b, bot0, bot1)
	# THE PIN, measured in edges, not pixels: the HUD plates are TRANSLUCENT, so a
	# world-only blur still moves the composite under the ink (measured post-fix:
	# ~39k px of top-band change with the ink perfectly crisp). What a blur over
	# the HUD CANNOT fake is edge survival — smeared text loses its strong luma
	# jumps, crisp text keeps them. So census strong edges per band and require
	# the concussion frame to keep nearly all of them.
	var ea_top := _band_edges(a, top0, top1)
	var eb_top := _band_edges(b, top0, top1)
	var ea_bot := _band_edges(a, bot0, bot1)
	var eb_bot := _band_edges(b, bot0, bot1)
	print("probe measurements: baseline motion %d/%d px, concussion motion %d/%d px, edges top %d->%d, bottom %d->%d" % [ac_top, ac_bot, ab_top, ab_bot, ea_top, eb_top, ea_bot, eb_bot])
	if eb_top < int(ea_top * EDGE_KEEP_RATIO) or eb_bot < int(ea_bot * EDGE_KEEP_RATIO):
		push_error("probe_concussion_hud: concussion 0.7 destroyed HUD edge detail (top %d->%d, bottom %d->%d strong-edge px) — the low-pass smears HUD chrome" % [ea_top, eb_top, ea_bot, eb_bot])
		fail = true
	var world := _band_diff(a, b, wy0, wy1)
	if world < MIN_WORLD_DIFF_PIXELS:
		push_error("probe_concussion_hud: the world band changed only %d px under concussion 0.7 (< %d) — the effect did not render, so the HUD checks above prove nothing" % [world, MIN_WORLD_DIFF_PIXELS])
		fail = true
	if fail:
		print("PROBE FAILED — HUD edges lost to concussion: top %d->%d, bottom %d->%d (world diff=%d px)" % [ea_top, eb_top, ea_bot, eb_bot, world])
		quit(1)
		return
	print("PROBE OK — HUD edges survive concussion (top %d->%d, bottom %d->%d), world blurred (%d px differ)" % [ea_top, eb_top, ea_bot, eb_bot, world])
	quit(0)


func _capture() -> Image:
	_main.queue_redraw()   # physics is frozen — force the frame to re-render
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _band_diff(a: Image, b: Image, y0: int, y1: int) -> int:
	var n := 0
	for y in range(y0, mini(y1, a.get_height())):
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func _band_edges(img: Image, y0: int, y1: int) -> int:
	# Strong-edge census: pixels whose luma jumps hard against the right
	# neighbour. Text ink on a plate is nothing BUT such edges; a radial blur
	# over the ink destroys them, while a blur confined to the world behind a
	# translucent plate leaves the ink's edges standing.
	var n := 0
	for y in range(y0, mini(y1, img.get_height())):
		for x in img.get_width() - 1:
			if absf(_luma(img.get_pixel(x, y)) - _luma(img.get_pixel(x + 1, y))) > EDGE_LUMA_JUMP:
				n += 1
	return n


static func _luma(px: Color) -> float:
	return px.r * 0.299 + px.g * 0.587 + px.b * 0.114
