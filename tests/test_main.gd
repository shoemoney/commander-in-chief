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


# --- Pins that concealment cover READS as tan scrub, not the retired green hedge:
# raw asset, tint, and rendered (texture*tint) composite, at both foliage_march ends. ---

func test_kind1_cover_reads_as_scrub_not_hedge() -> void:
	var tex: Texture2D = load("res://assets/art/decor/dry_shrub.png")
	if tex == null:
		Runner.T.ok(false, "assets/art/decor/dry_shrub.png failed to load")
		return
	var shrub_img: Image = tex.get_image()
	if shrub_img == null:
		Runner.T.ok(false, "dry_shrub.png texture has no Image data")
		return
	if shrub_img.is_compressed():
		shrub_img.decompress()

	var src_sum := Color(0, 0, 0)
	var src_n := 0
	for y in range(0, shrub_img.get_height(), 2):   # every-other-pixel, same sampling stride as test_assets.gd
		for x in range(0, shrub_img.get_width(), 2):
			var px := shrub_img.get_pixel(x, y)
			if px.a > 0.12:   # skip transparent/AA-fringe pixels
				src_sum += Color(px.r, px.g, px.b)
				src_n += 1
	Runner.T.ok(src_n > 0, "dry_shrub.png must have opaque pixels to sample")
	if src_n == 0:
		return
	var src_avg: Color = src_sum / src_n
	# Guard the ASSET ITSELF, independent of the tint multiply below — a future
	# reskin to a green-dominant source image must fail even if tint math is fine.
	Runner.T.ok(src_avg.r >= src_avg.g,
		"dry_shrub.png source average must be tan/khaki (r>=g), not green like the retired hedge")

	var saved_march: float = Art.foliage_march   # static var — restore so other tests aren't perturbed
	for march in [0.0, 1.0]:
		Art.foliage_march = march
		var shrub_tint: Color = Art.tint("dry_shrub")
		Runner.T.ok(shrub_tint.is_equal_approx(Art.DESERT_FOLIAGE.lerp(Art.FOLIAGE_ASH, march)),
			"dry_shrub tint at march=%.1f must be the documented DESERT_FOLIAGE->FOLIAGE_ASH ramp" % march)
		var rendered: Color = src_avg * shrub_tint   # Godot's own componentwise Color*Color multiply
		Runner.T.ok(rendered.r >= rendered.g,
			"dry_shrub RENDERED pixel (texture*tint) at march=%.1f must read tan/khaki (r>=g), not green" % march)
	Art.foliage_march = saved_march


# --- boot-splash focus-out must NOT strand a PAUSE menu ---
# The menu is HIDDEN under the opaque boot splash (main._setup_splash suspends the title).
# The focus-out auto-pause keys off HIDDEN too, so a focus-out DURING the splash — exactly
# what a Terminal `open …; exit` launch fires as focus leaves the closing shell — used to
# open PAUSE under the splash; _end_splash then refused to reveal the title (its `mode ==
# HIDDEN` gate failed), stranding a RESUME with no run behind it. should_autopause_on_focus_out
# is the pure decision (headless-assertable, like needs_refit) — pin every branch of it.
func test_focus_out_autopause_decision() -> void:
	var ms: Script = load("res://src/main.gd")
	var GM: Script = load("res://src/view/menu.gd")
	var HIDDEN: int = GM.Mode.HIDDEN
	var TITLE: int = GM.Mode.TITLE

	# THE BUG: HIDDEN under the splash (splash_up=true) must NOT auto-pause.
	Runner.T.ok(not ms.should_autopause_on_focus_out(HIDDEN, false, false, false, true),
		"focus-out during the boot splash must NOT auto-pause (would strand a dead RESUME)")

	# A live run (HIDDEN, splash gone, no wipe/victory) MUST auto-pause — the anti-blind-death feature.
	Runner.T.ok(ms.should_autopause_on_focus_out(HIDDEN, false, false, false, false),
		"focus-out during a live run STILL auto-pauses (anti-blind-death feature preserved)")

	# Every other carve-out stays a no-op: on the title, mid-wipe, at victory, and under no_autopause.
	Runner.T.ok(not ms.should_autopause_on_focus_out(TITLE, false, false, false, false),
		"focus-out on the TITLE/attract screen must not auto-pause (menu already up)")
	Runner.T.ok(not ms.should_autopause_on_focus_out(HIDDEN, true, false, false, false),
		"a wiped run must not auto-pause on focus-out")
	Runner.T.ok(not ms.should_autopause_on_focus_out(HIDDEN, false, true, false, false),
		"a victorious run must not auto-pause on focus-out")
	Runner.T.ok(not ms.should_autopause_on_focus_out(HIDDEN, false, false, true, false),
		"no_autopause (screenshot harness) must not auto-pause on focus-out")




# --- feel-stack-juice-haptics: _prox_falloff/_rumble_merge are the pure math
# behind the per-player HD/adaptive haptics (_blast_prox_for/_buzz) — pin them
# directly rather than driving a live Main+SimWorld just to reach two numbers. ---

func test_prox_falloff_matches_reference_points() -> void:
	var ms: Script = load("res://src/main.gd")
	Runner.T.eq(ms._prox_falloff(0.0), 1.0, "point-blank (and anything under 60px) must be full-force 1.0")
	Runner.T.eq(ms._prox_falloff(60.0), 1.0, "60px is the full-force floor")
	Runner.T.eq(ms._prox_falloff(340.0), 0.35, "340px is the far-corner floor of 0.35")
	Runner.T.eq(ms._prox_falloff(9999.0), 0.35, "anything past 340px must clamp to 0.35, never fall further")
	Runner.T.eq(ms._prox_falloff(200.0), 0.675, "the midpoint (200px) must land exactly halfway between 1.0 and 0.35")


func test_rumble_merge_clamps_and_keeps_louder() -> void:
	var ms: Script = load("res://src/main.gd")
	Runner.T.eq(ms._rumble_merge(0.0, 0.4), 0.4, "an empty pad picks up the new pulse")
	Runner.T.eq(ms._rumble_merge(0.6, 0.4), 0.6, "a quieter pulse must not stomp a louder one already queued this frame")
	Runner.T.eq(ms._rumble_merge(0.2, 0.9), 0.9, "a louder pulse must win over a quieter one already queued")
	Runner.T.eq(ms._rumble_merge(0.0, 5.0), 1.0, "magnitude must clamp to 1.0 even if a caller passes something absurd")
	Runner.T.eq(ms._rumble_merge(0.0, -3.0), 0.0, "magnitude must clamp to 0.0, never go negative")


# --- kill-the-copy-pasted-sandbag-wall-tiling: wall_variant/cap_flags are the pure
# per-segment jitter + run-termination math behind _wall_seg (main.gd). Pinning them
# directly means a "flatten the wall back to one repeated sprite" regression fails a
# test, not just a screenshot diff. ---

func test_wall_variant_is_stable_and_varied() -> void:
	var ms: Script = load("res://src/main.gd")
	# Frame-stability: the wall must not crawl while the camera scrolls — the same
	# world cell must always produce the exact same variant.
	var first: Dictionary = ms.wall_variant(37, -912)
	for _n in 5:
		Runner.T.eq(ms.wall_variant(37, -912), first, "wall_variant must be a pure function of (ix, iy)")
	# Actually varied: across a spread of cells, ds/flip must not collapse to one value,
	# and neither can outgrow the sim's 36x10 sandbag collision box.
	var ds_seen := {}
	var flip_seen := {}
	for ix in 8:
		for iy in 8:
			var v: Dictionary = ms.wall_variant(ix * 41, iy * 67)
			ds_seen[v["ds"]] = true
			flip_seen[v["flip"]] = true
			Runner.T.ok(v["ds"] >= 0.93 and v["ds"] <= 1.063, "ds must stay inside [0.93, 1.063]")
			Runner.T.ok(absf(v["dy"]) <= 2.0, "dy must stay inside +-2.0px (the sim's 36x10 bag AABB)")
	Runner.T.ok(ds_seen.size() >= 12,
		"64 sampled cells must produce at least 12 distinct ds values, got %d" % ds_seen.size())
	Runner.T.eq(flip_seen.size(), 2, "64 sampled cells must show both flip states")


func test_cap_flags_terminates_runs() -> void:
	var ms: Script = load("res://src/main.gd")
	var step: int = ms.BAG_LINK_RAW / 2   # 24px pitch (the sim's sandbag row pitch)
	# A 3-bag row: the middle bag has neighbours on both sides (no cap), the two
	# ends cap outward toward the missing neighbour.
	var xs := PackedInt64Array([0, step, step * 2])
	var ys := PackedInt64Array([0, 0, 0])
	Runner.T.eq(ms.cap_flags(xs, ys, 0), ms.CAP_LEFT, "the row's left end must cap CAP_LEFT")
	Runner.T.eq(ms.cap_flags(xs, ys, 1), 0, "the row's middle bag has neighbours both sides — no cap")
	Runner.T.eq(ms.cap_flags(xs, ys, 2), ms.CAP_RIGHT, "the row's right end must cap CAP_RIGHT")
	# A lone bag with no neighbours at all is a corner post, not a wall stub.
	Runner.T.eq(ms.cap_flags(PackedInt64Array([0]), PackedInt64Array([0]), 0),
		ms.CAP_LEFT | ms.CAP_RIGHT | ms.CAP_CORNER,
		"a lone bag with no neighbours must read as a corner post")
	# A genuine corner: a row that terminates into a LONE perpendicular bag (the
	# run turns 90deg) must flag CAP_CORNER on the joint bag.
	var stack_xs := PackedInt64Array([0, step, 0])
	var stack_ys := PackedInt64Array([0, 0, 14 * Fixed.ONE])
	Runner.T.ok(ms.cap_flags(stack_xs, stack_ys, 0) & ms.CAP_CORNER != 0,
		"a row-end bag whose only y-neighbour is a lone perpendicular bag must flag CAP_CORNER")
	# Regression (aaa3-r2): the shop's stacked FULL rows (14px pitch, main.gd's own
	# comment) must NOT flag CAP_CORNER just because a bag has a y-neighbour above/
	# below it — that y-neighbour is itself part of a parallel row, so this is two
	# rows of wall stacked deep, not a turn. Getting this wrong flattened the whole
	# shop cluster into identical corner-mound stamps (the tell come back re-skinned).
	var full_xs := PackedInt64Array([0, step, step * 2, 0, step, step * 2])
	var full_ys := PackedInt64Array([0, 0, 0, 14 * Fixed.ONE, 14 * Fixed.ONE, 14 * Fixed.ONE])
	Runner.T.eq(ms.cap_flags(full_xs, full_ys, 1), 0,
		"a middle bag in one of two full stacked rows must render as an ordinary middle segment, not CAP_CORNER")
	Runner.T.eq(ms.cap_flags(full_xs, full_ys, 4), 0,
		"same for the row directly below it — stacked rows are not corners")


# The campaign ramps continuously desert -> scorched -> marsh -> ruins -> Foundry (see
# _sector_march), so hardcoding ANY biome noun into player-facing copy is wrong somewhere along
# that ramp, not just at launch. FOUNDRY is a real authored sector name (sim_world.gd's "FOUNDRY
# WORKS", main.gd's "FOUNDRY COLOSSUS — %s"), not leaked biome copy, so it's deliberately excluded.
# DESERT / SCORCHED DESERT are likewise excluded: they're band-driven authored terrain words
# from main.gd's TERRAIN_WORDS (fed by _terrain_word(_sector_march())), not a hardcoded literal
# that drifts when the campaign ramps to another biome — same status as FOUNDRY above.
func test_no_hardcoded_biome_word_in_player_copy() -> void:
	var re := RegEx.new()
	re.compile("\"[^\"\\n]*\\b(JUNGLE|SWAMP|SNOW|TUNDRA|FOREST|ARCTIC)\\b[^\"\\n]*\"")
	var hits: Array = []
	var paths: Array = ["res://src/main.gd"]
	var dir := DirAccess.open("res://src/view")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".gd"):
				paths.append("res://src/view/%s" % fname)
			fname = dir.get_next()
		dir.list_dir_end()
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var src := f.get_as_text()
		f.close()
		var code_lines: Array = []
		for line in src.split("\n"):
			var hpos := line.find("#")
			code_lines.append(line if hpos < 0 else line.substr(0, hpos))
		var code := "\n".join(code_lines)
		for m in re.search_all(code):
			hits.append("%s: %s" % [path, m.get_string()])
	Runner.T.eq(hits.size(), 0,
		"no hardcoded biome noun in player-facing copy, found: %s" % str(hits))
# --- c-onboard: the 16s boot intro IS skippable after its first second, but nothing on
# screen said so. The affordance and the input gate must share ONE arm point, or the prompt
# advertises a skip that gets swallowed (a prompt that lies is worse than no prompt). ---

func test_splash_skip_prompt_only_appears_once_skip_is_armed() -> void:
	var ms: Script = load("res://src/main.gd")
	var arm: float = ms.SPLASH_SKIP_ARM
	# Disarmed: the medallion's guaranteed opening. No prompt, and the gate agrees.
	for el in [0.0, arm * 0.5, arm - 0.001]:
		Runner.T.ok(not ms.splash_skip_armed(el), "skip is disarmed at el=%.3f" % el)
		Runner.T.eq(ms.splash_skip_alpha(el), 0.0,
			"no skip prompt drawn while the skip is disarmed (el=%.3f)" % el)
	# Armed: the gate opens and the prompt starts fading in on the SAME frame.
	Runner.T.ok(ms.splash_skip_armed(arm), "skip arms exactly at SPLASH_SKIP_ARM")
	Runner.T.ok(ms.splash_skip_alpha(arm + 0.4) > 0.99,
		"the prompt reaches full alpha shortly after arming")
	Runner.T.ok(ms.splash_skip_alpha(arm + 0.2) > 0.0,
		"the prompt is already visible mid-fade-in")
	# It never re-hides while the splash is still running (the veil handles the dissolve).
	Runner.T.ok(ms.splash_skip_alpha(float(ms.SPLASH_DUR) - 0.1) > 0.99,
		"the prompt stays up for the whole armed stretch of the intro")
	# And it is drawn inside the 360px canvas, low-center, clear of the crawl/wordmark rows.
	Runner.T.ok(float(ms.SPLASH_SKIP_Y) < 360.0 and float(ms.SPLASH_SKIP_Y) > 300.0,
		"the skip prompt sits low-center inside the canvas (y=%d)" % int(ms.SPLASH_SKIP_Y))
# --- 2P co-op pad-assignment gate ---

func test_p2_pad_gate_asks_for_device_1_not_a_pad_count() -> void:
	# P2 is HARDWIRED to pad device 1 in _gather_inputs, so a
	# `get_connected_joypads().size() < 2` count is the wrong question: with
	# devices {0, 2} connected the count passes and P2 silently receives zero
	# input for the whole run. The warning also has to live in ONE place — it was
	# copy-pasted into three of the seven run entry points, so DAILY, SEEDED, the
	# replay watcher and the F2 toggle never warned at all, and a pad yanked
	# mid-run benched P2 with no message ever again.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.find("get_connected_joypads().size() < 2") == -1,
		"the pad-COUNT predicate is gone (it passes on a non-contiguous device id)")
	Runner.T.ok(src.find("Input.get_connected_joypads().has(1)") != -1,
		"the gate asks whether P2's actual device is present")
	Runner.T.eq(src.count("show_banner(\"P2: CONNECT A CONTROLLER\""), 1,
		"the co-op pad warning has exactly one call site (reached from _reset)")
	Runner.T.ok(src.find("Input.joy_connection_changed.connect(_on_pad_count_changed)") != -1,
		"...and a pad yanked mid-run re-raises it")



# --- 2P co-op: a partner's KO must not detonate the survivor's screen ---

func test_partner_ko_ducks_only_the_self_directed_channels() -> void:
	# player_down fired the whole concussive kit GLOBALLY: a 10-frame freeze, a red
	# damage vignette and an ears-ringing lowpass. In 2P that told the player still
	# STANDING they were hit — they weren't — and froze their fight for a sixth of a
	# second at the exact moment they need to move. down_self_scale ducks the
	# self-directed half while a squadmate is up; with nobody standing it is a hard
	# 1.0, so solo (and a team wipe) plays the old beat bit-for-bit.
	var ms: Script = load("res://src/main.gd")
	Runner.T.eq(ms.down_self_scale(false), 1.0,
		"nobody left standing -> the full death beat, unchanged")
	Runner.T.ok(ms.down_self_scale(true) < 1.0,
		"a partner still up -> the self-directed channels duck")
	Runner.T.ok(ms.down_self_scale(true) > 0.0,
		"...ducked, not muted — the KO still has to register on the shared screen")
	Runner.T.ok(int(10.0 * ms.down_self_scale(true)) < 10,
		"the freeze shortens for the player who still has agency")
	# The SHARED channels (one camera, one music bus) must NOT be scaled — a squadmate
	# hitting the dirt still shakes the frame and ducks the music for both seats.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.find("_damage_vignette = maxf(_damage_vignette, down_scale)") != -1,
		"the damage vignette routes through the scale")
	Runner.T.ok(src.find("_concussion = maxf(_concussion, down_scale)") != -1,
		"the concussion lowpass routes through the scale")
	Runner.T.eq(src.count("down_self_scale("), 2,
		"exactly one caller plus the definition — one place, every KO")
	Runner.T.ok(src.find("_duck = 1.0") != -1 and src.find("_punch = maxf(_punch, 0.14)") != -1,
		"the shared music duck / camera punch stay unscaled")


# --- OS cursor baking (src/main.gd::_bake_cursor / bake_cursor_image / menu_hotspot) ---
# The menu pointer shipped ENORMOUS: it baked at `native_size * window_scale`, which is
# not a size at all — it is whatever the source art happens to be. cursor.png is 64px, so
# a 2x window (the DEFAULT 1280x720) drew a 128px pointer and 3x drew 192px, against a
# ~24-32px system norm. Its hotspot was a flat (2,2)*s while the arrow's tip sits at
# (8,2) of that 64px canvas, so every menu click landed 6*s physical px LEFT of where the
# arrow visibly pointed. And the resize ran IN PLACE on the texture's own Image, so each
# re-bake (resize / fullscreen / options) compounded off an already-mangled source.
#
# These rows are the missing half of CURSOR_PX / CURSOR_TIP_SRC — the source canvas and
# tip position those constants were measured against. Same deal as SPRITE_CANVAS in
# test_view_honesty.gd: re-bake cursor.png at another resolution or nudge the arrow, and
# the constants silently stop describing the art. Kept as literals ON PURPOSE — deriving
# them from the import this is checking would assert nothing. When a row moves, re-measure
# the tip and update CURSOR_TIP_SRC, THEN the row — never the row alone. ---

const CURSOR_ART_CANVAS := 64          # imported square both cursor sprites must stay
const CURSOR_TIP_ALPHA := 8            # /255 — above the fix_alpha_border fringe, at the visible tip
const CURSOR_ARROW_BBOX := Rect2i(8, 2, 42, 60)   # opaque bbox of cursor.png at that alpha
# Battlefield yardsticks the gameplay crosshair is sized against, in LOGICAL px of the
# 640x360 viewport. Measured off a real gameplay capture, not guessed: the player soldier
# renders ~20px, and main.gd's own in-world aim reticle (`rrect`) is a 16px square.
const PLAYER_SPRITE_PX := 20
const INGAME_RETICLE_PX := 16


static func _opaque_bbox(img: Image, alpha: int) -> Rect2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			if int(img.get_pixel(x, y).a * 255.0) >= alpha:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


static func _raw(key: String) -> Image:
	var img: Image = Art.tex(key).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	return img


func test_both_os_cursors_bake_to_one_fixed_canvas_smaller_than_the_source() -> void:
	var c := _consts()
	var px: int = c.get("CURSOR_PX", 0)
	Runner.T.ok(px > 0 and px < CURSOR_ART_CANVAS,
		"CURSOR_PX (%d) must be a real target SIZE below the %dpx source canvas — a pointer that "
			% [px, CURSOR_ART_CANVAS]
		+ "bakes at native*scale is not sized, it is whatever the art happens to be")
	Runner.T.eq(c.get("CURSOR_SRC_PX", 0), CURSOR_ART_CANVAS,
		"CURSOR_SRC_PX must state the canvas the tip was actually measured on")
	# The two cursors are NOT one object and must not share one size. The crosshair rode
	# CURSOR_PX (sized against a title-screen menu row) onto the BATTLEFIELD, where 24
	# logical px is wider than the ~20px player sprite and wider than the enemies it aims
	# at — 48 physical px at the default 1280x720 window. RETICLE_PX is anchored to the aim
	# marker main.gd already draws for itself (`rrect`, 16 logical px at the player).
	var rpx: int = c.get("RETICLE_PX", 0)
	Runner.T.ok(rpx > 0 and rpx <= PLAYER_SPRITE_PX,
		"RETICLE_PX (%d) must not exceed the ~%dpx player sprite it aims past — an aim mark "
			% [rpx, PLAYER_SPRITE_PX]
		+ "bigger than the character occludes the thing you are shooting at")
	Runner.T.eq(rpx, INGAME_RETICLE_PX,
		"RETICLE_PX must equal the %dpx aim reticle main.gd draws in-world — one game, one aim "
			% INGAME_RETICLE_PX
		+ "mark. Re-measure `rrect` at the player draw and move BOTH, never this row alone")
	var ms: Script = load("res://src/main.gd")
	for s in [1, 2, 3]:
		for key in ["ui_cursor", "ui_reticle"]:
			var kpx: int = px if key == "ui_cursor" else rpx
			var src := _raw(key)
			var baked: Image = ms.bake_cursor_image(src, kpx * s)
			Runner.T.eq(Vector2i(baked.get_width(), baked.get_height()), Vector2i(kpx * s, kpx * s),
				"'%s' at window scale %dx must bake to %dpx square, not %dpx"
					% [key, s, kpx * s, baked.get_width()])
			# The bake must not eat its own source: Texture2D.get_image() returns the
			# texture's OWN Image, so an in-place resize here poisons every later re-bake.
			Runner.T.eq(src.get_width(), CURSOR_ART_CANVAS,
				"baking '%s' must leave the source art at %dpx — resize a COPY, or the next "
					% [key, CURSOR_ART_CANVAS]
				+ "re-bake (resize/fullscreen/options) scales an already-shrunk image")


func test_menu_hotspot_tracks_the_arrow_tip_at_every_window_scale() -> void:
	var c := _consts()
	var px: int = c.get("CURSOR_PX", 0)
	var tip: Vector2 = c.get("CURSOR_TIP_SRC", Vector2.ZERO)
	var ms: Script = load("res://src/main.gd")
	for s in [1, 2, 3]:
		var hs: Vector2 = ms.menu_hotspot(s)
		Runner.T.ok(hs.is_equal_approx(tip * (float(px) / float(CURSOR_ART_CANVAS)) * float(s)),
			"menu_hotspot(%d) = %s must be the source tip carried through the SAME normalisation "
				% [s, str(hs)]
			+ "the art gets — a hand-tuned constant drifts off the pointer the moment either moves")
		Runner.T.ok(hs.x >= 0.0 and hs.y >= 0.0 and hs.x < float(px * s) and hs.y < float(px * s),
			"menu_hotspot(%d) = %s must land inside the %dpx baked image" % [s, str(hs), px * s])
	# An arrow aims from its TIP; a crosshair aims from its dead CENTRE. This row used to be
	# `eq(px / 2.0 * 2.0, px)` — an identity that asserted nothing about the crosshair at all,
	# and it stayed green while the crosshair hotspot was hard-wired to CURSOR_PX/2 inside
	# _apply_cursor. Pin it the same way menu_hotspot is pinned.
	var rpx: int = c.get("RETICLE_PX", 0)
	for s in [1, 2, 3]:
		var chs: Vector2 = ms.crosshair_hotspot(s)
		Runner.T.ok(chs.is_equal_approx(Vector2.ONE * (rpx / 2.0) * float(s)),
			"crosshair_hotspot(%d) = %s must be the dead CENTRE of the %dpx bake — off-centre and "
				% [s, str(chs), rpx * s]
			+ "every mouse-aimed shot leaves by that offset")
		Runner.T.ok(chs.x > 0.0 and chs.x < float(rpx * s) and chs.y == chs.x,
			"crosshair_hotspot(%d) = %s must be square and inside the baked image" % [s, str(chs)])


func test_cursor_source_art_still_matches_the_constants_measured_off_it() -> void:
	for key in ["ui_cursor", "ui_reticle"]:
		var img := _raw(key)
		Runner.T.eq(Vector2i(img.get_width(), img.get_height()),
			Vector2i(CURSOR_ART_CANVAS, CURSOR_ART_CANVAS),
			"'%s' imports at %dx%d but CURSOR_SRC_PX / CURSOR_TIP_SRC were measured on a %dpx "
				% [key, img.get_width(), img.get_height(), CURSOR_ART_CANVAS]
			+ "canvas — re-measure the tip and re-tune the constants, THEN update this row")
	var arrow := _opaque_bbox(_raw("ui_cursor"), CURSOR_TIP_ALPHA)
	Runner.T.eq(arrow, CURSOR_ARROW_BBOX,
		"cursor.png's arrow now occupies %s, not the %s CURSOR_TIP_SRC was read off — the menu "
			% [str(arrow), str(CURSOR_ARROW_BBOX)]
		+ "click point no longer sits on the visible tip. Re-measure, update CURSOR_TIP_SRC, THEN this row")
	Runner.T.eq(Vector2(arrow.position), _consts().get("CURSOR_TIP_SRC", Vector2.ZERO),
		"CURSOR_TIP_SRC must BE the arrow bbox corner — the tip is this art's top-left pixel")
	# The crosshair takes canvas-centre as its hotspot; that is only honest while the
	# reticle art is actually centred in its canvas.
	var ret := _raw("ui_reticle").get_used_rect()
	var off := (Vector2(ret.position) + Vector2(ret.size) * 0.5) - Vector2.ONE * (CURSOR_ART_CANVAS * 0.5)
	Runner.T.ok(off.length() <= 2.0,
		"reticle art sits %s off its canvas centre, but the crosshair hotspot IS the canvas "
			% str(off)
		+ "centre — re-centre the art or stop assuming centre")


func test_reticle_art_is_a_crosshair_and_not_a_bracket() -> void:
	# ui/reticle.png was a single CHEVRON (`<`) — a UI angle-bracket reused as the aim mark —
	# while _bake_cursor's comment called it "a crosshair" and the OS cursor baked it 48px
	# wide. On screen it read as a boomerang that pointed at nothing. Nothing measured the
	# SHAPE, so the lie survived every pass. Four cardinal ticks around an open centre is a
	# crosshair; a bracket has arms on the diagonals and mass on one side only.
	var img := _raw("ui_reticle")
	var lo := CURSOR_ART_CANVAS / 2 - 1   # 64px canvas: the centre falls BETWEEN 31 and 32
	var hi := CURSOR_ART_CANVAS / 2
	var a := func(x: int, y: int) -> int: return int(img.get_pixel(x, y).a * 255.0)
	# 1. Open centre. The aim point must not be under ink — you shoot what you can see.
	for r in range(0, 5):
		for v in [a.call(hi + r, lo), a.call(lo - r, lo), a.call(lo, hi + r), a.call(lo, lo - r)]:
			Runner.T.ok(v < 16, "the crosshair's centre gap is opaque %d/255 at radius %d — the "
				% [v, r] + "aim mark is covering the thing being aimed at")
	# 2. All FOUR cardinal ticks present, at the same reach. A chevron/bracket fails this:
	#    its mass sits on one side, so two of these four come back empty.
	for r in [12, 20, 28]:
		for probe in [[hi + r, lo, "E"], [lo - r, lo, "W"], [lo, hi + r, "S"], [lo, lo - r, "N"]]:
			Runner.T.ok(a.call(probe[0], probe[1]) > 200,
				"no %s tick at radius %d (alpha %d) — a crosshair reaches out all four cardinals; "
					% [probe[2], r, a.call(probe[0], probe[1])]
				+ "one-sided art is a bracket, and it reads on screen as a boomerang")
	# 3. Diagonals EMPTY — the discriminator a chevron cannot pass, since its arms are diagonal.
	for r in [10, 14, 18, 22]:
		Runner.T.ok(a.call(hi + r, hi + r) < 16 and a.call(lo - r, lo - r) < 16 \
				and a.call(hi + r, lo - r) < 16 and a.call(lo - r, hi + r) < 16,
			"ink on the diagonals at radius %d — a crosshair's arms are cardinal only" % r)
	# 4. A dark keyline flanks each tick. The OS cursor gets NO in-game halo (RETICLE_HALO only
	#    backs the in-world draw), so without baked-in ink it vanishes on pale sand.
	var side := img.get_pixel(lo - 4, lo - 20)
	Runner.T.ok(side.a > 0.7 and side.get_luminance() < 0.2,
		"the pixel beside a tick is %s — the crosshair needs a dark keyline baked in or it "
			% str(side) + "disappears against the desert the moment it leaves dark cover")


# --- THE top-center message band's one arbiter (main.band_rows) -----------------------------
# Observed live at sector 1: a pickup teach line ("PIERCING ROUNDS — SHOTS PUNCH THROUGH. AIM
# DOWN THE COLUMN") and the closed-gate objective line ("GRENADE THE BUNKERS TO ADVANCE")
# printed on the SAME baseline and smeared into unreadable mush. `_top_center_priority()`
# arbitrated WHICH alert owned the band but never where anything DREW: the objective line
# anchored itself to the gate's world y, and the hint sat on its own hard offset. Every band
# message is now dealt a row by main.band_rows(), so this pins the thing that actually broke —
# two band messages sharing pixels — rather than the one string pair that happened to be caught.

const _BAND_RAIL_MIN := 40.0    # the rail bottoms out at the 1P corner plate…
const _BAND_RAIL_MAX := 132.0   # …and tops out at 2P + shop strip + 3 boss bars + replay ribbon


## Every band string src/main.gd actually ships, scraped from the calls that produce them, so
## a NEW hint or banner is covered by this test the day it lands instead of the day it collides.
## Split by slot: `show_banner()` copy can only ever land in the alert row, `_hint()` copy only
## in the hint row, and the two rows have different size floors.
func _shipped_band_strings(token: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string("res://src/main.gd").split("\n"):
		if line.find(token) == -1:
			continue
		var parts := line.split("\"")
		var i := 1
		while i < parts.size():
			var lit: String = parts[i]
			# Odd-index splits are the quoted literals; keep the sentence-shaped ones (the
			# short ones are hint ids and format fragments, which never reach the band alone).
			if lit.length() >= 12 and lit.find(" ") != -1:
				out.append(lit)
			i += 2
	return out


func test_band_rows_never_share_pixels() -> void:
	var ms: Script = load("res://src/main.gd")
	var alerts := _shipped_band_strings("show_banner(")
	var hints := _shipped_band_strings("_hint(")
	Runner.T.ok(alerts.size() >= 10 and hints.size() >= 10,
		"scraped the shipped band copy (%d alerts / %d hints) — the scrape itself must not silently find nothing"
			% [alerts.size(), hints.size()])
	# TEXT SIZE is an accessibility multiplier on the small label sizes; a bigger one can only
	# make a collision MORE likely, so the band is measured at BOTH ends of the setting.
	var was_scale: float = Art.text_scale
	var worst_hits := 0
	var worst_wide := 0
	for scale in [1.0, float(ms.get_script_constant_map()["TEXT_SCALE_MAX"]) / 100.0]:
		Art.text_scale = scale
		Art.flush_tw()
		for top in alerts:
			for hint in hints:
				# Sweep the whole rail: band_top() moves with player count, the shop strip,
				# live boss bars and the replay ribbon, and none of those may open a gap.
				var y := _BAND_RAIL_MIN
				while y <= _BAND_RAIL_MAX:
					var rows: Array = ms.band_rows(y, top, 16, false, hint)
					if rows.size() == 2:
						var a: Rect2 = rows[0]["rect"]
						var b: Rect2 = rows[1]["rect"]
						if a.grow(-0.5).intersects(b.grow(-0.5)):
							worst_hits += 1
							if worst_hits <= 3:
								Runner.T.ok(false, "band rows overlap at y=%.0f scale=%.2f: '%s' %s vs '%s' %s"
									% [y, scale, top, str(a), hint, str(b)])
					for r in rows:
						var rect: Rect2 = r["rect"]
						if rect.position.x < -0.5 or rect.end.x > 640.5 or rect.end.y > 360.5:
							worst_wide += 1
							if worst_wide <= 3:
								Runner.T.ok(false, "band row '%s' %s escapes the 640x360 frame (scale=%.2f)"
									% [r["text"], str(rect), scale])
					y += 2.0
	Art.text_scale = was_scale
	Art.flush_tw()
	Runner.T.eq(worst_hits, 0, "no two band messages ever occupy the same rect")
	Runner.T.eq(worst_wide, 0, "no band row ever escapes the frame")


func test_band_reserves_row_zero_so_a_live_hint_never_jumps() -> void:
	var ms: Script = load("res://src/main.gd")
	var hint := "GRENADES CRACK ARMOR — BUNKERS TAKE NO BULLETS"
	var alone: Array = ms.band_rows(56.0, "", 16, false, hint)
	var under: Array = ms.band_rows(56.0, "MORTARS RANGING — ADVANCE!", 11, false, hint)
	Runner.T.eq(alone.size(), 1, "no alert -> the band is the hint row only")
	Runner.T.eq(under.size(), 2, "alert + hint -> two rows")
	Runner.T.eq(alone[0]["baseline"], under[1]["baseline"],
		"row 0 is RESERVED: a live hint must not jump 22px when a banner arrives or decays above it")


func test_band_hint_shrinks_to_fit_the_frame() -> void:
	var ms: Script = load("res://src/main.gd")
	var consts: Dictionary = ms.get_script_constant_map()
	# The hint tooltip had no width cap at all; the longest shipped teach line already spans
	# ~525 of the 640px frame, so one longer translation walked it off both edges.
	var long_hint := "CLAYMORE — PLANT WITH [INTERACT] AWAY FROM TANKS BECAUSE IT HURTS BOTH SIDES"
	var rows: Array = ms.band_rows(56.0, "", 16, false, long_hint)
	Runner.T.eq(rows.size(), 1, "the over-wide hint still gets a row")
	Runner.T.ok(int(rows[0]["size"]) < int(consts["BAND_HINT_SIZE"]),
		"an over-wide hint is shrunk to fit, not printed off the edge (size %d)" % int(rows[0]["size"]))
	Runner.T.ok(rows[0]["rect"].position.x >= -0.5 and rows[0]["rect"].end.x <= 640.5,
		"...and the shrunk row, badge included, lands inside the frame: %s" % str(rows[0]["rect"]))


func test_no_band_message_computes_its_own_y() -> void:
	# The defect was structural, not cosmetic: the objective line derived its y from the GATE's
	# world position while still claiming the band's slot. If any band draw goes back to
	# inventing a y, the geometry test above passes and the screen smears anyway.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.eq(src.count("sim.camera_top) * PX + 30.0"), 0,
		"the closed-gate objective line must not re-anchor itself to the gate's world y")
	Runner.T.eq(src.count("_band = _band_rows("), 1,
		"exactly one writer of the frame's band")
	# Every band consumer reads its row through band_row(_band, ...) — the choke point.
	Runner.T.ok(src.count("band_row(_band, \"top\")") >= 2 and src.count("band_row(_band, \"hint\")") == 1,
		"the alert draws and the hint draw all pull their row from the band, not from a local y")
# --- Dev-harness autoplay: the AAA capture harness screenshotted 45 review cycles of a
# soldier standing still, dying and respawning at sector 1, because nothing injected input.
# demo_input() (the scripted bot the trailer/attract screen already run) was reachable only
# behind OS.has_feature("movie"). demo_autoplay is the second opt-in. It must default OFF —
# a build that boots with it set ignores the human holding the controller. ---

func test_demo_autoplay_defaults_off_and_feeds_the_scripted_bot() -> void:
	var ms: Script = load("res://src/main.gd")
	var m: Node2D = ms.new()
	Runner.T.eq(m.demo_autoplay, false,
		"demo_autoplay MUST default off — on, the sim ignores every real input")
	m.sim = SimWorld.new(0xC0FFEE, 2)
	m.demo_autoplay = true
	var got: Array = m._gather_inputs()
	Runner.T.eq(got.size(), 2,
		"one scripted input per player — a 2P capture must not leave P2 standing still")
	var want: SimInput = ms.demo_input(m.sim.tick_count, m.sim)
	Runner.T.eq(str(got[0].encode()), str(want.encode()),
		"P1 is exactly demo_input() — the same bot movie mode drives")
	Runner.T.ok(got[0].move_y < 0, "the bot marches north (an idle capture never leaves sector 1)")
	Runner.T.ok(got[0].fire, "...and holds the trigger, so the reviewer sees combat")
	m.free()
	# The flag is dev-harness-only: nothing under src/ may set it, or it ships enabled.
	for f in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd"]:
		Runner.T.ok(FileAccess.get_file_as_string(f).find("demo_autoplay = true") == -1,
			"%s must never set demo_autoplay — only dev harnesses may" % f)


# --- _draw_enemies' painter-sort cache: _esort_order holds INDICES into sim.enemies.
# resize() truncates but never revalidates them, and the opt-loop hitstop short-circuit
# skipped the re-sort — so a tick that swept dead enemies AND armed hitstop (i.e. any
# big kill) left stale out-of-range indices and threw "Out of bounds get index" out of
# _draw, aborting the rest of the frame. Only reproducible while the game is actually
# being played, which is why it survived until the capture harness got input. ---

func test_enemy_sort_cache_revalidates_when_the_count_moves() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.find("if _hitstop_frames <= 0 or ecount_changed:") != -1,
		"a changed enemy count must force the painter re-sort even during hitstop — "
		+ "reusing the cache there indexes sim.enemies past its end")
	Runner.T.ok(src.find("var ecount_changed := _esort_order.size() != ecount") != -1,
		"the resize and the re-sort must read the SAME changed-flag — computing it after "
		+ "the resize would always be false")


# --- DEBUG-ONLY god mode. Nothing has ever seen the back half of this game: a human playtest
# died 8x in sector 1, and the scripted bot dies in sector 2. God mode is the instrument that
# makes sectors 3-6, the Colossus and the victory card observable. It is auto-RESTORE, not
# invulnerability — the player still gets hit and still goes down (so hit reactions, the downed
# state, the revive prompt and the difficulty signal all stay real), the run just cannot END.
#
# It must be IMPOSSIBLE to ship enabled. This repo has form: a dev-only autoload regressed into
# project.godot twice and now carries its own ratchet (test_assets.gd). Same seriousness here. ---

func test_god_mode_defaults_off_everywhere() -> void:
	var ms: Script = load("res://src/main.gd")
	var m: Node2D = ms.new()
	Runner.T.eq(m.god_mode, false,
		"main.god_mode MUST default off — a build that boots god-mode cannot be lost")
	m.free()
	Runner.T.eq(SimWorld.new(0xC0FFEE, 1).god_mode, false,
		"SimWorld.god_mode MUST default off — the sim is what actually grants it")
	Runner.T.eq(SimWorld.new(0xC0FFEE, 2, "endless").god_mode, false,
		"...in every mode, not just campaign")


func test_god_mode_cannot_ship_enabled() -> void:
	# 1. Nothing under src/ may turn it on. The ONE write to sim.god_mode is the per-tick
	#    re-assertion in _physics_process, and that write must carry the debug-build gate on
	#    the same line — a gate one line above is a gate a future edit walks out from under.
	var writes := 0
	for f in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd",
			"res://src/sim/sim_world.gd", "res://src/net/lockstep.gd"]:
		var src := FileAccess.get_file_as_string(f)
		Runner.T.eq(src.count("god_mode = true"), 0,
			"%s must never set god_mode true — only a dev harness or the F8 toggle may" % f)
		for line in src.split("\n"):
			if line.lstrip("\t").begins_with("#") or line.find("sim.god_mode =") == -1:
				continue
			writes += 1
			Runner.T.ok(line.find("OS.is_debug_build()") != -1,
				"every write to sim.god_mode must carry the debug-build gate ON THE SAME LINE: %s"
					% line.strip_edges())
	Runner.T.eq(writes, 1,
		"exactly ONE writer of sim.god_mode — a second one is a second thing to forget to gate")
	# 2. The live toggle is debug-gated too, so a release build's F8 is inert.
	var mgd := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(mgd.find("event.keycode == KEY_F8 and OS.is_debug_build()") != -1,
		"the F8 toggle must be gated on OS.is_debug_build() at the keycode test")
	# 3. F8 is FREE — it must not collide with the existing F2/F3/F4/R/C debug + card keys.
	Runner.T.eq(mgd.count("KEY_F8"), 1, "F8 is claimed exactly once")


func test_god_mode_restores_the_downed_through_the_real_respawn_path() -> void:
	# The whole design: the player DIES normally, then comes back on a fixed heartbeat via the
	# same _respawn() the coin reader uses. If this ever becomes "cannot be hit", every system a
	# reviewer needs to judge (hit reaction, downed state, revive economy) stops being observable.
	var sim := SimWorld.new(0xC0FFEE, 1)
	sim.god_mode = true
	sim.war_chest = 0          # broke: the normal fallback is 300 ticks away, so any revive
	                           # inside 61 ticks can only be god mode's
	sim._kill_player(sim.players[0])
	Runner.T.eq(sim.players[0]["alive"], false,
		"god mode must NOT make the player unhittable — the death still happens")
	Runner.T.eq(sim.players[0]["deaths"], 1,
		"...and it still COUNTS, so knockdowns-per-sector stays real difficulty telemetry")
	var down_ticks := 0
	for _i in SimWorld.GOD_RESTORE_TICKS + 1:
		sim.step([SimInput.new()])
		if not sim.players[0]["alive"]:
			down_ticks += 1
	Runner.T.eq(sim.players[0]["alive"], true,
		"the downed player is back on their feet within one GOD_RESTORE_TICKS heartbeat")
	Runner.T.ok(down_ticks > 0,
		"...but not instantly — the downed state must actually be entered and drawn")
	Runner.T.ok(sim.players[0]["mg_ammo"] >= SimWorld.MG_AMMO_MAX,
		"the heartbeat tops ammo up: a run that stalls out of ammo never reaches sector 3")
	Runner.T.eq(sim.players[0]["grenade_ammo"], SimWorld.GRENADE_AMMO_MAX,
		"...grenades too — they are the only armor-cracker, so a dry belt cannot open a gate")


func test_god_mode_off_leaves_the_run_losable() -> void:
	var sim := SimWorld.new(0xC0FFEE, 1)
	sim.war_chest = 0
	sim._kill_player(sim.players[0])
	for _i in SimWorld.GOD_RESTORE_TICKS + 1:
		sim.step([SimInput.new()])
	Runner.T.eq(sim.players[0]["alive"], false,
		"with god mode OFF a broke death stays down for the full broke fallback — no free rescue")


func test_god_mode_clears_both_run_enders_but_never_a_victory() -> void:
	# `wiped` is a LATCH that freezes step() before any stepper runs, and it is set by BOTH the
	# endless wipe and the Last Stand terminal state — i.e. by the Colossus finale, the single
	# piece of content this mode exists to let us watch.
	var sim := SimWorld.new(0xC0FFEE, 1, "endless")
	sim.god_mode = true
	sim.wiped = true
	for _i in SimWorld.GOD_RESTORE_TICKS + 1:
		sim.step([SimInput.new()])
	Runner.T.eq(sim.wiped, false, "god mode un-freezes a wiped run, or the sim never steps again")
	var won := SimWorld.new(0xC0FFEE, 1)
	won.god_mode = true
	won.victory = true
	won._kill_player(won.players[0])
	for _i in SimWorld.GOD_RESTORE_TICKS + 1:
		won.step([SimInput.new()])
	Runner.T.eq(won.victory, true, "winning is a real end state — god mode must not restore past it")
	Runner.T.eq(won.players[0]["alive"], false, "...and must not resurrect anyone behind the card")


func test_god_mode_is_in_the_checksum_but_leaves_goldens_untouched() -> void:
	# CLAUDE.md: a gameplay-affecting field belongs in the checksum. Fed CONDITIONALLY (the
	# assist_mode/hard precedent) so an OFF flag leaves the hash stream byte-identical and the
	# committed goldens hold — which the determinism suite proves independently.
	var off := SimWorld.new(0xC0FFEE, 2)
	var on := SimWorld.new(0xC0FFEE, 2)
	on.god_mode = true
	Runner.T.ok(off.checksum() != on.checksum(),
		"god mode must perturb the checksum — an ungated desync must not be able to hide in it")
	var plain := SimWorld.new(0xC0FFEE, 2)
	Runner.T.eq(off.checksum(), plain.checksum(),
		"...and an OFF flag must leave the stream identical, so no golden moves")


func test_god_mode_badge_gets_its_own_band_row_and_never_collides() -> void:
	# The indicator is not decoration. A tester who forgets god mode is on reports "the
	# difficulty feels fine" about a run that cannot end, and that false signal is worse than no
	# testing. It is dealt by band_rows() — the single arbiter of the top-centre rail — so it can
	# neither be painted over nor SUPPRESS the banners god mode exists to let you observe.
	var ms: Script = load("res://src/main.gd")
	var consts: Dictionary = ms.get_script_constant_map()
	var top := "DESTROY THE GUNSHIP TO ADVANCE"
	var hint := "GRENADES CRACK ARMOR — BUNKERS TAKE NO BULLETS"
	Runner.T.eq(ms.band_rows(56.0, top, 11, false, hint).size(), 2,
		"god OFF is the shipped band, unchanged — two rows")
	var was_scale: float = Art.text_scale
	var collisions := 0
	var escapes := 0
	var missing := 0
	for scale in [1.0, float(consts["TEXT_SCALE_MAX"]) / 100.0]:
		Art.text_scale = scale
		Art.flush_tw()
		var y := _BAND_RAIL_MIN
		while y <= _BAND_RAIL_MAX:
			var rows: Array = ms.band_rows(y, top, 11, false, hint, true)
			if rows.size() != 3 or rows[0]["id"] != "god":
				missing += 1
			for a in rows.size():
				var ra: Rect2 = rows[a]["rect"]
				if ra.position.x < -0.5 or ra.end.x > 640.5 or ra.end.y > 360.5:
					escapes += 1
				for b in range(a + 1, rows.size()):
					if ra.grow(-0.5).intersects(rows[b]["rect"].grow(-0.5)):
						collisions += 1
			y += 2.0
	Art.text_scale = was_scale
	Art.flush_tw()
	Runner.T.eq(missing, 0, "god ON always deals a 'god' row FIRST, whatever else owns the rail")
	Runner.T.eq(collisions, 0, "the god badge never shares pixels with a banner or a hint")
	Runner.T.eq(escapes, 0, "...and nothing on the god-shifted rail escapes the 640x360 frame")
	# The badge must SAY it, in the copy, not just be a coloured pip.
	var txt: String = consts["BAND_GOD_TEXT"]
	Runner.T.ok(txt.find("GOD MODE") != -1 and txt.find("DEBUG") != -1,
		"the badge names itself AND names the build it only exists in: '%s'" % txt)
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.eq(src.count("band_row(_band, \"god\")"), 1,
		"the badge draw pulls its row from the band like every other consumer")
	Runner.T.ok(src.find("_draw_god_badge()   #") != -1,
		"the badge is drawn from the screen-anchored pass, last, so nothing paints over it")

# --- Anti-softlock ratchet for the scripted bot -------------------------------
# The 2026-07-25 difficulty study could not be trusted until this held. On seed 7
# the bot pinned itself against gate 2's fork divider and burned 44,000+ ticks and
# 358 knockdowns without ever opening the gate — two independent causes, both since
# fixed: the divider's move-revert ate northward progress (see
# test_mechanics.gd::test_fork_divider_denies_the_crossing_without_eating_north_progress),
# and demo_input's tank chase had no give-up condition, so it y-aligned with a tank
# parked across the divider, zeroed its own march and pushed into the wall forever.
#
# A capture harness that cannot traverse the game photographs sector 1 and calls it
# a review; a difficulty probe that cannot traverse the game reports the bot's
# pathing luck as the game's difficulty curve. This pins traversal itself.

func test_scripted_bot_clears_the_fork_gate_that_used_to_trap_it() -> void:
	var ms: Script = load("res://src/main.gd")
	var sim := SimWorld.new(7, 1, "campaign")
	sim.god_mode = true   # the run must not be able to END, so a stall reads as a stall
	var best_y: int = sim.players[0]["y"]
	for t in 4000:
		sim.step([ms.demo_input(t, sim)] as Array[SimInput])
		best_y = mini(best_y, sim.players[0]["y"])
		if best_y < -2 * SimWorld.GATE_SPACING:
			break
	Runner.T.ok(best_y < -2 * SimWorld.GATE_SPACING,
		"the bot gets north of gate 2 within 4000 ticks (it once never got there at all)")


func test_scripted_bot_locks_a_target_in_endless_where_every_campaign_branch_is_dead() -> void:
	## _demo_boss_target's colossus / gate / tank branches are all written only by
	## _step_camera and _step_colossus, neither of which endless calls — so in endless
	## the function returned {} and the bot fell back to its open-loop +-30deg north
	## sweep. Endless bodies enter anywhere in x 24..616 and converge diagonally, and
	## killing is the ONLY way a wave advances, so the bot never left wave 1: measured
	## 30,000 ticks x 3 seeds at wave 1 / score 350 / 4 live enemies — which is exactly
	## the "wave 1, 350 points" the backlog reported. With the lock: wave 11 / 50,220.
	## Asserted here at the function, not by a 30k-tick run, to keep the suite fast.
	var ms: Script = load("res://src/main.gd")
	var sim := SimWorld.new(7, 1, "endless")
	var p: Dictionary = sim.players[0]
	sim.enemies.clear()
	# A flanker the north sweep could never cover: far off-lane, well above.
	sim.enemies.append({"x": 40 * Fixed.ONE, "y": p["y"] - 200 * Fixed.ONE,
		"alive": true, "kind": 0, "hp": 1})
	var lock: Dictionary = ms._demo_boss_target(sim, p)
	Runner.T.ok(not lock.is_empty(), "endless returns a target instead of falling through to the sweep")
	Runner.T.eq(lock["x"], 40 * Fixed.ONE, "and it is the flanker's x, not the lane's")

	# Nearest wins when several are up, so the bot answers what is actually on it.
	sim.enemies.append({"x": p["x"], "y": p["y"] - 30 * Fixed.ONE,
		"alive": true, "kind": 0, "hp": 1})
	lock = ms._demo_boss_target(sim, p)
	Runner.T.eq(lock["y"], p["y"] - 30 * Fixed.ONE, "the nearer body wins the lock")

	# Campaign must be untouched by the endless branch — it returns {} with no gates.
	var csim := SimWorld.new(7, 1, "campaign")
	csim.enemies.clear()
	csim.enemies.append({"x": 40 * Fixed.ONE, "y": 0, "alive": true, "kind": 0, "hp": 1})
	Runner.T.ok(ms._demo_boss_target(csim, csim.players[0]).is_empty(),
		"campaign still ignores loose infantry — the boss-only policy that measured best on 8 seeds")
