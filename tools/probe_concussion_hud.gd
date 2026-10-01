extends SceneTree
## Pixel pin for the concussion low-pass (the measured half of smoke.gd's
## structural layer pin): the effect must blur the WORLD and leave the HUD
## chrome — boss-bar dock band, corner plate, control prompts — bit-crisp.
##
## It boots the real main scene, starts a campaign run (the title hides
## _hud_icons, so gameplay is the state that carries the chrome under test),
## then SWEEPS the soldier across the play field — see SWEEP_X — and at each
## pose captures three frames: A at concussion 0, B at the peak, C back at 0.
## It asserts, at EVERY pose:
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
##   4. the PLAYER BOX — derived from the live soldier's screen position, not
##      hardcoded — keeps >= CENTRE_KEEP_RATIO of its strong edges (the player
##      must stay legible while downed). Three of the four warp channels used to
##      be distance-INdependent — the chroma split threw `dist` away through
##      normalize(), the wobble was a whole-image shove, and the fold weight was
##      a flat 0.5 — so the one pixel the radial blur was careful to leave alone
##      got smeared by everything else. Note this is the mirror image of check 2:
##      the HUD is spared because it is a different canvas layer, the player's
##      patch because the warp ramps away from a FOCUS point that main.gd pushes
##      from his own screen position. Both are "keeps its edges", one structural,
##      one shaped. Guarded by MIN_CENTRE_EDGES: if the box held no legible
##      detail at baseline the check proves nothing and says so instead of
##      passing. Exposure-matched — see the comment in _pose; a screen-centred
##      vignette darkening the box is not a smear and must not read as one.
##
## WHY THE SWEEP: there is no horizontal camera in this game. main._to_screen()
## is `Vector2(round(fx * PX), round((fy - camera_top) * PX))` — no x term at
## all — so the soldier's world x IS his screen x over the 16..624 play field
## (SimWorld.WORLD_LEFT/WORLD_RIGHT). He is routinely 200+ px from the middle of
## the frame, and an earlier revision of this probe posed him at exactly one x
## (wherever the boot left him, ~280 — near the centre) and therefore could not
## tell "the warp spares the PLAYER" from "the warp spares a fixed disc of
## SCREEN". Those are different fixes and only one of them is the one asked for.
##
## Needs a GL context (the screen-reading shader is a no-op without one), and
## --fixed-fps 60 -- REQUIRED under a slow/software renderer (xvfb's llvmpipe in
## CI), same reason tools/screenshots.gd pairs it with its own capture: without it,
## `delta` reports the real (inflated) per-frame render time, which (1) makes
## Godot's physics catch-up run extra ticks per rendered frame, landing the
## "150-frame settle" far later/busier than intended, and (2) makes every
## delta-eased HUD polish (odometer rollup, chest/score pulse decay, shop-strip
## ease, verb-legend fade) take one huge step per real frame instead of many small
## ones -- both read as "baseline HUD motion" and fail check 1 as INCONCLUSIVE even
## though concussion never ran. Reproduced locally 2026-09-05 via `--fixed-fps 5`
## (forces the same oversized delta): baseline motion jumped from ~150px to
## 700-2300px and the run went PROBE FAILED, matching CI's ~1000px top-band
## signature; `--fixed-fps 60` restores ~150px and PROBE OK on the same tree.
##   godot --path . --rendering-method gl_compatibility --fixed-fps 60 -s res://tools/probe_concussion_hud.gd
## No sampling-window hazard: the probe sets _concussion directly and captures
## at peak; decay is x0.9/frame from 1.0 (~50 frames to 0.01), the capture is 2.

const LOGICAL_W := 640.0
const LOGICAL_H := 360.0
# THE SHIPPED PEAK. main.gd:3155 is `_concussion = maxf(_concussion, down_scale)`
# and down_self_scale(partner_standing=false) returns 1.0 (main.gd:3735) — a SOLO
# knockdown, the exact case this probe exists for, peaks at 1.0. 0.7 is the
# FLAK-VEST break (main.gd:4372), a lesser beat. Measure the loud one.
const PEAK := 1.0
# Sweep the soldier across the play field: left edge, middle, right edge, all
# inside SimWorld.WORLD_LEFT..WORLD_RIGHT (16..624). Logical px == world px.
const SWEEP_X: Array[float] = [40.0, 320.0, 600.0]
const HUD_TOP_LOGICAL := HudIcons.BOSS_BLOCK_TOP   # the top HUD band (was a mirrored 64.0)
const HUD_BOTTOM_LOGICAL := 30.0   # bottom control-prompt strip (VERB_LEGEND_Y 344)
const WORLD_Y0_LOGICAL := 180.0    # mid-screen world band, clear of both HUD strips
const WORLD_Y1_LOGICAL := 260.0
const MIN_WORLD_DIFF_PIXELS := 500
# The PLAYER box, DERIVED from the live soldier's screen position rather than
# hardcoded — an earlier revision of this probe guessed a box at the geometric
# centre of the frame (240..400 x 135..225) and it turned out to be aimed at bare
# ground: in the posed frame the soldier stands at roughly (278, 292) logical,
# BELOW that box, which carried only ~99 strong edges at baseline and therefore
# could not have measured anything. Half-extents around the soldier, clamped
# clear of both HUD strips so the census never eats chrome.
const PLAYER_BOX_HALF_W := 120.0
const PLAYER_BOX_HALF_H := 45.0
const STABLE_CEILING_PX := 400   # max baseline HUD motion before the window reads as noisy
const EDGE_LUMA_JUMP := 0.19     # ~48/255 — a strong ink/plate or ink/world edge
const EDGE_KEEP_RATIO := 0.85    # concussion frame must keep >= 85% of the band's strong edges
# Signal floor: below this the box held nothing to protect and the run says so
# instead of passing. RE-DERIVED FOR THE SWEEP, not inherited: _player_box_logical
# clamps to the frame, so an edge pose gets a 160px-wide box instead of 240 and
# carries proportionally fewer edges. Measured baselines on this tree:
# x=40 -> 190, x=320 -> 350, x=600 -> 264. 150 sits under the thinnest of those
# and two orders of magnitude above what the defect leaves (0 and 5 edges).
const MIN_CENTRE_EDGES := 150
# SET FROM MEASUREMENT AT THE WORST SWEPT POSE, not taste. Exposure-matched
# strong-edge retention in the player box at concussion 1.0. The shipped column
# is the median of 3 runs (Apple M4 Max / OpenGL 4.1 Metal). The two controls
# reproduce to within a hundredth run-to-run; the shipped column does NOT — it
# spreads ~0.98..1.12 — so quote its median, never a bare triple:
#
#                       no ramp   ramp @ vec2(0.5)   ramp @ focus (shipped)
#   x=40                 0.00          0.01                1.01
#   x=320                0.09          0.98                1.07
#   x=600                0.00          0.04                1.03
#
# Across all 9 shipped-column samples the worst single sample 0.98. THAT is the
# number this floor has to clear — the median is not the binding constraint.
#
# Two CONTROLS, both run against this exact census, both hard-fail: `no ramp`
# is the shader with `spare` pinned to 0 (the pre-fix behaviour, and still the
# blast heat-shock's path); `ramp @ vec2(0.5)` is the ramp anchored at screen
# centre, which passes ONLY at x=320 and is exactly the bug this sweep exists to
# expose. So the floor has to sit well above 0.04 and
# well below the 0.98 worst sample: 0.85 leaves 13 points of headroom under the
# worst measured pose and is more than an order of magnitude above the worst
# defect value. Raised from 0.75 because the exposure match (see _pose) removed
# the vignette's contribution to the number.
# The probe prints both halves of every ratio each run — re-derive, don't trust.
const CENTRE_KEEP_RATIO := 0.70

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
	var fail := false
	if await _instrument_check():
		fail = true
	for px in SWEEP_X:
		if await _pose(px):
			fail = true
	_main.set_physics_process(true)
	if fail:
		print("PROBE FAILED")
		quit(1)
		return
	print("PROBE OK — every swept pose kept the soldier legible at concussion %.2f" % PEAK)
	quit(0)


## THE CONTROL for the whole probe, and the reason its verdict can be trusted.
##
## Every pin in _pose is "keep >= N% of the strong edges". A gate phrased as a
## floor is only worth anything if the instrument can report BELOW that floor —
## otherwise "no HUD smear" and "this census cannot see a smear at all" are the
## same PASS, and the second one is what a broken threshold silently becomes.
## (That is not hypothetical here: this probe's raw band census had exactly that
## property, reading a 2.1x vignette as blur for weeks while the centre box next
## door carried an exposure match.)
##
## So: capture the CLEAN frame, blur it with the same instrument's own kernel,
## and require the census to notice. No shader edit, no second boot — the smear
## is manufactured in-image, which is strictly stronger than trusting that some
## future shader change would trip the pin.
##
## It also pins the property the fix depends on: exposure-matching must NOT make
## the instrument blind to a DARKENED blur. So the planted frame is darkened to
## roughly the top band's real concussion gain as well as blurred. A census that
## divides out exposure still has to report this as destroyed edges.
func _instrument_check() -> bool:
	_main._concussion = 0.0
	await process_frame
	await process_frame
	var clean := await _capture()
	var top1 := int(HUD_TOP_LOGICAL * (clean.get_height() / LOGICAL_H))
	if top1 <= 1:
		push_error("probe_concussion_hud: instrument control could not resolve the top HUD band (top1=%d)" % top1)
		return true
	var before := _band_edges(clean, 0, top1)
	var smeared := _smeared_copy(clean, top1)
	var ma := _band_mean_luma(clean, 0, top1)
	var mb := _band_mean_luma(smeared, 0, top1)
	var gain := 1.0 if mb < 0.001 else ma / mb
	var after := _band_edges(smeared, 0, top1, gain)
	var keep := 0.0 if before == 0 else float(after) / float(before)
	print("INSTRUMENT CONTROL: planted 6px blur + %.2fx darkening on the top band — %d -> %d strong edges, keep %.3f (must fall below the %.2f floor the HUD pin uses)"
		% [gain, before, after, keep, EDGE_KEEP_RATIO])
	if before < MIN_CENTRE_EDGES:
		push_error("probe_concussion_hud: instrument control found only %d strong edges in the top band (< %d) — there is no legible ink here to blur, so this control proves nothing" % [before, MIN_CENTRE_EDGES])
		return true
	if keep >= EDGE_KEEP_RATIO:
		push_error("probe_concussion_hud: INSTRUMENT CONTROL FAILED — a planted blur + darkening still reads keep %.3f, at or above the %.2f floor. The census cannot detect smear, so every 'no HUD smear' verdict from this run is vacuous" % [keep, EDGE_KEEP_RATIO])
		return true
	print("INSTRUMENT CONTROL OK — the census reports a real smear as one, so a PASS here means something")
	return false


## A copy of `img` with its top band horizontally box-blurred and uniformly
## darkened — the two halves of what the concussion pass does to that strip,
## applied without touching the shader.
func _smeared_copy(img: Image, band_h: int) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, img.get_format())
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	const R := 3   # half-width, so a 6px kernel — wider than HUD ink strokes
	for y in range(0, mini(band_h, img.get_height())):
		for x in img.get_width():
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var n := 0
			for k in range(-R, R + 1):
				var sx := clampi(x + k, 0, img.get_width() - 1)
				var px := out.get_pixel(sx, y)
				r += px.r
				g += px.g
				b += px.b
				n += 1
			var m := Color(r / float(n), g / float(n), b / float(n), 1.0)
			out.set_pixel(x, y, m.darkened(0.35))
	return out


func _pose(player_x: float) -> bool:	## Drive the soldier to `player_x` (logical px == world px: there is no
	## horizontal camera), capture A/B/C around the peak, and run every check.
	## Returns true on failure. Physics is already frozen, so the write sticks.
	var p: Dictionary = _main.sim.players[0]
	p["x"] = int(player_x * Fixed.ONE)
	# `_concussion_p` is the field main.gd's own player_down / vest_break triggers
	# set to name whose knockdown owns the focus; 0 is its default and its value
	# for the solo case this probe measures, so posing it here is a no-op that
	# documents the coupling rather than a fixture that hides it.
	_main._concussion_p = 0
	await process_frame
	var a := await _capture()
	_main._concussion = PEAK
	await process_frame   # _process pushes the uniform this frame
	var b := await _capture()
	_main._concussion = 0.0
	await process_frame
	var c := await _capture()

	var dump := OS.get_environment("PROBE_SHOT_DIR")
	if not dump.is_empty():
		var tag := "x%d" % int(player_x)
		a.save_png(dump.path_join("probe_a_%s.png" % tag))
		b.save_png(dump.path_join("probe_b_%s.png" % tag))
		c.save_png(dump.path_join("probe_c_%s.png" % tag))

	var scale := a.get_height() / LOGICAL_H
	var top0 := 0
	var top1 := int(HUD_TOP_LOGICAL * scale)
	var bot0 := int((LOGICAL_H - HUD_BOTTOM_LOGICAL) * scale)
	var bot1 := a.get_height()
	var wy0 := int(WORLD_Y0_LOGICAL * scale)
	var wy1 := int(WORLD_Y1_LOGICAL * scale)
	# The player box, derived from where the soldier actually is on screen in THIS
	# posed frame (see _player_box_logical) and clamped clear of the HUD strips.
	var pbox := _player_box_logical()
	var cx0 := int(pbox.position.x * scale)
	var cx1 := int(pbox.end.x * scale)
	var cy0 := int(pbox.position.y * scale)
	var cy1 := int(pbox.end.y * scale)
	print("probe pose x=%.0f: player box logical %s (soldier at %s)" % [player_x, pbox, _player_screen_logical()])

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
		print("PROBE INCONCLUSIVE at x=%.0f — baseline HUD motion %d px top / %d px bottom" % [player_x, ac_top, ac_bot])
		return true
	var ab_top := _band_diff(a, b, top0, top1)
	var ab_bot := _band_diff(a, b, bot0, bot1)
	# THE PIN, measured in edges, not pixels: the HUD plates are TRANSLUCENT, so a
	# world-only blur still moves the composite under the ink (measured post-fix:
	# ~39k px of top-band change with the ink perfectly crisp). What a blur over
	# the HUD CANNOT fake is edge survival — smeared text loses its strong luma
	# jumps, crisp text keeps them. So census strong edges per band and require
	# the concussion frame to keep nearly all of them.
	#
	# EXPOSURE-MATCHED, and that qualifier is load-bearing (fixed 2026-10-01). The
	# concussion pass GRADES as well as DISPLACES: screen_fx.gdshader multiplies
	# the frame by `mix(1.0, vig * pulse, 0.55)` with vig = 1 - smoothstep(0.3,
	# 0.75, |to_center|) — a ~2.1x exposure swing, ~0.945 at the middle down to
	# ~0.45 in the corners. The centre box below was already matched for exactly
	# this reason; these bands were left on a raw fixed-threshold census, so they
	# read the vignette's darkening as blur. Measured on the shipped tree: the top
	# band kept 922/1101 = 0.837 raw and FAILED the 0.85 floor, but with its own
	# exposure divided back out it keeps 0.872. The top strip is worst-hit because
	# the vignette anchors at SCREEN centre while the warp anchors at the SOLDIER
	# (y~300), so the top corners take the full darkening while the bottom strip,
	# nearer the bright middle, barely moves. Nothing about the blur changed; the
	# instrument was grading its own threshold. This is why gl-capture has been red
	# on every push since the ramp landed.
	#
	# NOT a loosened bar. 0.85 still bounds the REAL blur loss: after the match the
	# top strip is genuinely down ~12.8% (the warp does reach the top ink by design
	# — periph is 0.48..1.0 there), so the pin clears by only 2.2 points, and
	# _instrument_check plants a smear to prove the gate can still go red.
	#
	# MEASURED SENSITIVITY — read this before trusting this pin. Two shader
	# mutations, each reverted, on the shipped tree:
	#   blur fold 0.5 -> 1.0 * periph ......... top keep 0.872 -> 0.879 (UP)
	#   blur tap stride 0.018 -> 0.120 (6.7x) .. top keep 0.872 -> 0.860
	#   periph forced to 1.0 (no ramp) ........ top keep 0.872 -> 0.872, but the
	#     CENTRE pin fired 0.00/0.13/0.00 against its 0.70 floor and PROBE FAILED.
	# So this band pin is a WEAK instrument against blur STRENGTH — the top band's
	# strong edges are dominated by HUD plate borders and frame geometry, which no
	# blur destroys, more than by text ink, which it would. It cannot be the thing
	# that catches a stronger warp; the centre pin is, and it is excellent at it.
	# What this pin is good for is catching a blur that genuinely DESTROYS the strip
	# (a wrong layer, a wrong sample source, a full-frame wash), which is why the
	# exposure match matters: unmeasured it fired on a 2.1x vignette for weeks.
	var ea_top := _band_edges(a, top0, top1)
	var eb_top := _band_edges(b, top0, top1)
	var ea_bot := _band_edges(a, bot0, bot1)
	var eb_bot := _band_edges(b, bot0, bot1)
	var gta := _band_mean_luma(a, top0, top1)
	var gtb := _band_mean_luma(b, top0, top1)
	var gain_top := 1.0 if gtb < 0.001 else gta / gtb
	var gba := _band_mean_luma(a, bot0, bot1)
	var gbb := _band_mean_luma(b, bot0, bot1)
	var gain_bot := 1.0 if gbb < 0.001 else gba / gbb
	# The census that GATES is the matched one. The raw counts are kept for the log
	# only: the raw-vs-matched spread IS the diagnostic that the confound is live.
	var eb_top_gate := _band_edges(b, top0, top1, gain_top)
	var eb_bot_gate := _band_edges(b, bot0, bot1, gain_bot)
	# The CENTRE pin, same instrument aimed at the player's own patch of screen —
	# but EXPOSURE-MATCHED first. The concussion pass has two distinguishable
	# halves, and only one of them is the defect: it DISPLACES samples (the smear
	# this check exists to catch) and it GRADES them (desaturate + a screen-centred
	# vignette pulse, deliberate, and by design NOT following the soldier). A raw
	# luma-jump census cannot tell them apart: at an edge pose the vignette alone
	# multiplies the box by ~0.66, which drags real edges under a fixed 0.19
	# threshold and reads as smear. Measured with the fix in and no exposure match:
	# x=40 keep 0.62 / x=600 keep 0.70 — versus 0.99 at x=320, where the same
	# soldier sits in the vignette's bright middle. That spread is the GRADE, not
	# the WARP. So census B's edges against a threshold scaled by the box's own
	# mean-luma ratio: a uniform darkening cancels, a smear does not.
	var ma := _box_mean_luma(a, cx0, cx1, cy0, cy1)
	var mb := _box_mean_luma(b, cx0, cx1, cy0, cy1)
	var gain := 1.0 if mb < 0.001 else ma / mb
	var ea_mid := _box_edges(a, cx0, cx1, cy0, cy1, 1.0)
	var eb_raw := _box_edges(b, cx0, cx1, cy0, cy1, 1.0)
	var eb_mid := _box_edges(b, cx0, cx1, cy0, cy1, gain)
	var mid_ratio := 0.0 if ea_mid == 0 else float(eb_mid) / float(ea_mid)
	var raw_ratio := 0.0 if ea_mid == 0 else float(eb_raw) / float(ea_mid)
	var world := _band_diff(a, b, wy0, wy1)
	print("probe x=%.0f amt=%.2f: baseline motion %d/%d px, concussion motion %d/%d px, edges top %d->%d, bottom %d->%d, centre %d->%d (keep %.2f, floor %.2f; ungraded %d keep %.2f, vignette gain %.2f), world diff %d px"
		% [player_x, PEAK, ac_top, ac_bot, ab_top, ab_bot, ea_top, eb_top, ea_bot, eb_bot, ea_mid, eb_mid, mid_ratio, CENTRE_KEEP_RATIO, eb_raw, raw_ratio, gain, world])
	print("  HUD BANDS: top %d->%d keep %.3f (raw %.3f, gain %.3f) | bottom %d->%d keep %.3f (raw %.3f, gain %.3f) | floor %.2f"
		% [ea_top, eb_top_gate, float(eb_top_gate) / float(ea_top), float(eb_top) / float(ea_top), gain_top,
			ea_bot, eb_bot_gate, float(eb_bot_gate) / float(ea_bot), float(eb_bot) / float(ea_bot), gain_bot,
			EDGE_KEEP_RATIO])
	if ea_mid < MIN_CENTRE_EDGES:
		push_error("probe_concussion_hud: at x=%.0f the player box only carried %d strong edges at baseline (< %d) — nothing legible was there to protect, so the centre check proves nothing" % [player_x, ea_mid, MIN_CENTRE_EDGES])
		fail = true
	elif eb_mid < int(ea_mid * CENTRE_KEEP_RATIO):
		push_error("probe_concussion_hud: concussion %.2f smeared the PLAYER'S OWN PATCH of screen at x=%.0f (%d->%d strong-edge px, keep %.2f < %.2f) — the warp is hitting the soldier at full strength instead of ramping toward the periphery of HIS view"
			% [PEAK, player_x, ea_mid, eb_mid, mid_ratio, CENTRE_KEEP_RATIO])
		fail = true
	if eb_top_gate < int(ea_top * EDGE_KEEP_RATIO) or eb_bot_gate < int(ea_bot * EDGE_KEEP_RATIO):
		push_error("probe_concussion_hud: concussion %.2f destroyed HUD edge detail at x=%.0f (top %d->%d, bottom %d->%d strong-edge px, exposure-matched) — the low-pass smears HUD chrome" % [PEAK, player_x, ea_top, eb_top_gate, ea_bot, eb_bot_gate])
		fail = true
	if world < MIN_WORLD_DIFF_PIXELS:
		push_error("probe_concussion_hud: at x=%.0f the world band changed only %d px under concussion %.2f (< %d) — the effect did not render, so the checks above prove nothing" % [player_x, world, PEAK, MIN_WORLD_DIFF_PIXELS])
		fail = true
	return fail


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


func _player_screen_logical() -> Vector2:
	# main._to_screen() is the SHIPPED world->screen seam, so this lands wherever
	# the view actually drew the soldier — no second copy of the camera math.
	var p: Dictionary = _main.sim.players[0]
	return _main._to_screen(p["x"], p["y"])


func _player_box_logical() -> Rect2:
	# A box around the soldier, clamped to the frame and clear of both HUD strips
	# so the edge census never counts chrome as world detail.
	var c := _player_screen_logical()
	var x0 := clampf(c.x - PLAYER_BOX_HALF_W, 0.0, 640.0)
	var x1 := clampf(c.x + PLAYER_BOX_HALF_W, 0.0, 640.0)
	var y0 := clampf(c.y - PLAYER_BOX_HALF_H, float(HUD_TOP_LOGICAL), LOGICAL_H - HUD_BOTTOM_LOGICAL)
	var y1 := clampf(c.y + PLAYER_BOX_HALF_H, float(HUD_TOP_LOGICAL), LOGICAL_H - HUD_BOTTOM_LOGICAL)
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func _box_edges(img: Image, x0: int, x1: int, y0: int, y1: int, gain: float) -> int:
	# Same instrument as _band_edges, windowed in x as well as y: strong horizontal
	# luma jumps. A smear kills them; a colour grade does not — PROVIDED the census
	# is exposure-matched, which is what `gain` is for (1.0 = raw). A uniform
	# multiply on the whole box scales every jump by the same factor, so undoing it
	# leaves a genuine edge exactly where it was and a smeared one still gone.
	var n := 0
	var xhi := mini(x1, img.get_width() - 1)
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), xhi):
			if absf(_luma(img.get_pixel(x, y)) - _luma(img.get_pixel(x + 1, y))) * gain > EDGE_LUMA_JUMP:
				n += 1
	return n


func _box_mean_luma(img: Image, x0: int, x1: int, y0: int, y1: int) -> float:
	# Mean luma over the box — the exposure the grade left it at, so _box_edges can
	# be matched against the clean frame's.
	var sum := 0.0
	var n := 0
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), mini(x1, img.get_width())):
			sum += _luma(img.get_pixel(x, y))
			n += 1
	return 0.0 if n == 0 else sum / float(n)


func _band_edges(img: Image, y0: int, y1: int, gain: float = 1.0) -> int:
	# Strong-edge census: pixels whose luma jumps hard against the right
	# neighbour. Text ink on a plate is nothing BUT such edges; a radial blur
	# over the ink destroys them, while a blur confined to the world behind a
	# translucent plate leaves the ink's edges standing.
	var n := 0
	for y in range(y0, mini(y1, img.get_height())):
		for x in img.get_width() - 1:
			if absf(_luma(img.get_pixel(x, y)) - _luma(img.get_pixel(x + 1, y))) * gain > EDGE_LUMA_JUMP:
				n += 1
	return n


func _band_mean_luma(img: Image, y0: int, y1: int) -> float:
	# Mean luma of a full-width band, y-windowed. The exposure the grade left
	# that strip at, so a gain-matched census can undo it the way _box_mean_luma
	# does for the centre box.
	var sum := 0.0
	var n := 0
	for y in range(y0, mini(y1, img.get_height())):
		for x in img.get_width():
			sum += _luma(img.get_pixel(x, y))
			n += 1
	return 0.0 if n == 0 else sum / float(n)


static func _luma(px: Color) -> float:
	return px.r * 0.299 + px.g * 0.587 + px.b * 0.114
