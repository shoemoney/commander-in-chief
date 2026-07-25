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
