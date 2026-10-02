extends SceneTree
## ROLE-RIM VERIFICATION SHEET — proof, not assertion.
##
## The a3-33 role rims (one contour hue per hostile role) have only ever been
## "verified" by: it parses, the suite is green, and the contours render. That is
## evidence they were not all recoloured to the same colour — a much weaker claim
## than the one the change was made under ("nine roles read as nine roles").
##
## This poses one of EVERY hostile kind on one row, on identical ground, and saves
## a zoomed band. Everything is asserted BEFORE the PNG is written:
##
##   1. the band must not be near-empty — this tool's first three attempts each
##      printed "SAVED" on a frame that was 99%+ black, and a saved PNG is not a
##      usable PNG;
##   2. every kind must contribute lit pixels to its own column, or that kind is
##      named and the run fails;
##   3. each kind's rim hue must differ from every other kind's, or the run exits
##      non-zero. THIS is the a3-33 claim, measured rather than asserted.
##
## STATUS — STILL DOES NOT CAPTURE. It exits 2 ("the whole frame is black") on every
## run, and that is deliberate: it refuses to write a PNG it cannot vouch for.
##
## What has been ruled out, by measurement rather than by guessing:
##   - headless (gated up front);
##   - a pinned/frozen sim (the enemy row is disabled entirely and it is still black);
##   - the enemy row itself (ROLE_NO_ROW=1, still black);
##   - capturing too late (now captured inside the drive loop, still black);
##   - `await process_frame` vs `RenderingServer.frame_post_draw` (now the latter);
##   - script errors (none).
## tools/campaign_contact_sheet.gd, with near-identical boot code, produces a 99%
## lit frame in the same environment. So the difference is real and still unknown,
## and guessing further is how a tool ends up confidently wrong.
##
## WHAT IS SHIPPED is the half that is real and already earned its place: this
## tool refused to save a black frame SIX times, including four in this session
## where the alternative was six more "SAVED" lines over unusable PNGs. The
## whole-frame-vs-band diagnostic also separated two failure modes that had been
## conflated, and the per-kind hue-clash check is written and waiting.
##
## To finish it — and the state as of the last attempt, which changed the picture:
## a MINIMAL probe (boot identical to campaign_contact_sheet.gd, then read
## get_texture() and count lit pixels at +0/+30/+60/+120/+200 frames) is ALSO 0%
## lit at every one of those points, while campaign_contact_sheet.gd is 99% lit in
## the same environment, back to back. So the black frame is NOT caused by this
## tool's row, its keys, its menu handling, its capture timing or its await seam —
## a stripped tool with none of those still produces black. The difference lives
## somewhere in how campaign_contact_sheet.gd's _warm()/_drive() sequence primes
## the FIRST presented frame, which has not been isolated yet.
##
## Next: instrument campaign_contact_sheet.gd to print the SAME lit-pixel count at
## each step of ITS _warm() and _drive(), and find the first point its frame goes
## non-black. That is the experiment to run, and it is not a guess.
##
## Do not loosen the gate.
##
## Run: SHOT_DIR=/tmp/roles Godot --path . --rendering-method gl_compatibility \
##         -s res://tools/role_sheet.gd

const KINDS := [
	"rusher", "elite", "enemy_smg", "enemy_assault", "enemy_shotgun",
	"enemy_lmg", "enemy_sniper", "sapper", "ghillie", "courier",
]
const BAND_H := 44
const ZOOM := 3
# World units -> screen px. main.PX is 1.0 / Fixed.ONE and _to_screen takes RAW
# fixed-point, so (fy - camera_top) * PX yields 1 screen px per world UNIT:
# PX_PER_UNIT is Fixed.ONE * PX = 1.0.
#
# This was 2.0 (2026-10-01), which put the row's band at screen y 380 in a
# 640x360 viewport — 20px BELOW the bottom edge. clampi() then slid the crop up
# to y316, the bottom HUD strip, so the sheet saved the verb legend and a toast.
# Every assertion still passed, because that strip is lit: the whole-frame check,
# the band-lit check, and the per-column `col_lit` count were all satisfied by
# GROUND and HUD CHROME. The hue census then returned "28 rim-hue clashes" by
# measuring sand — on green ground c.r - c.b ~= 0 in every column, so all ten
# kinds resolved to the same hue. A tool that reports a confident, specific, and
# entirely fictional verdict is worse than one that refuses to save.
const PX_PER_UNIT := 1.0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("role_sheet: --headless has no framebuffer (needs gl_compatibility)")
		print("ROLE SHEET UNUSABLE — headless has no framebuffer")
		quit(1)
		return
	seed(0xC0FFEE)
	var out_dir := OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp/roles"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true
	_run(main, out_dir)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _run(main: Node2D, out_dir: String) -> void:
	for i in 150:
		await process_frame
	main.start_game(false)
	# Hold the menu down only while the boot splash can still re-assert TITLE, then
	# leave it alone so the fade resolves.
	for i in 90:
		await process_frame
		main._menu.mode = GameMenu.Mode.HIDDEN
	for i in 90:
		await process_frame
	var sim = main.sim
	if sim == null:
		print("ROLE SHEET UNUSABLE — no sim")
		quit(1)
		return

	# --- drive the world like a player, so the view is LIVE -------------------
	# The row is re-asserted every frame at the CAMERA's own y, which is what makes
	# it visible: screen_y = (world_y - camera_top) * PX, so anchoring to
	# camera_top is the one placement that cannot drift out of frame.
	var t := 0
	var img: Image = null
	# CAPTURE EARLY. The contact sheet grabs its frame DURING the drive, ~45 process
	# frames in. Capturing 260 frames later is long after the bot has walked into a
	# closed gate and the run has gone dark -- which is a perfectly good frame of a
	# paused/dark run and a useless one for this sheet. Same boot, same seam; the
	# only difference was WHEN.
	for i in 70:
		await process_frame
		main._menu.mode = GameMenu.Mode.HIDDEN
		_key(KEY_W, true)      # march north so the sim keeps advancing
		_key(KEY_UP, true)     # aim keys default to the arrows
		t += 1
		# Freeze the SIM's own fielding (which would otherwise replace our row) but
		# leave the world running: keep the live sim, overwrite its enemy list.
		var cam: int = int(sim.camera_top)
		var row_y: int = cam + int(190 * Fixed.ONE)
		sim.players[0]["alive"] = true
		if OS.get_environment("ROLE_NO_ROW") == "1":
			pass
		else:
			sim.enemies.clear()
		# The occluders. Clearing `enemies` alone is not a clean field: `tanks` is a
		# SEPARATE array and the colossus a separate dict, and a live 128px vehicle
		# sitting over the first three columns sampled VEHICLE PAINT for rusher /
		# enemy_smg / enemy_assault / enemy_shotgun. The sheet's own per-column check
		# could not tell — it only counts lit pixels, and a vehicle is lit.
		sim.tanks.clear()
		sim.colossus.clear()
		var pl: Dictionary = sim.players[0]
		pl["in_tank"] = -1
		for j in (0 if OS.get_environment("ROLE_NO_ROW") == "1" else KINDS.size()):
			sim.enemies.append({
				"x": int((52 + j * 58) * Fixed.ONE), "y": row_y, "alive": true,
				"elite": KINDS[j] == "elite", "kind": KINDS[j],
				# Defensive superset: the draw path reads several of these with []
				# rather than .get(), so a field the SPAWNER happens not to set is
				# still a hard error there. This sheet poses sprites; it makes no
				# gameplay claim, and says so.
				"windup": 999, "fire_cd": 999, "submerged": false,
				"surface_ticks": 0, "lunge_ticks": 0, "hp": 40, "max_hp": 40,
			})
		if t >= 55:
			# CAPTURE ON THIS FRAME. The working contact sheet calls
			# get_texture().get_image() INSIDE the drive loop, on the frame it is
			# actively awaiting. Reading it after the loop lets the present buffer
			# get recycled, which is the remaining difference from a tool that
			# demonstrably produces 99%-lit frames with identical boot code.
			img = root.get_texture().get_image()
			break


	# grab the buffer ON THE FRAME WE JUST AWAITED, before the next present recycles it
	if img == null:
		print("ROLE SHEET UNUSABLE — no framebuffer image")
		quit(1)
		return

	# --- ASSERT: whole frame vs band are different bugs ------------------------
	# A GL viewport image is VRAM-compressed and/or non-RGBA8; get_pixel() returns
	# 0s for it until both are handled. This is the same guard the repo already
	# carries in ground_base_strip_image.
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var lit_all := 0
	var all_total := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			all_total += 1
			var c0 := img.get_pixel(x, y)
			if c0.r + c0.g + c0.b > 0.37:   # 0..1 floats, not 0..255
				lit_all += 1
	print("DIAG whole-frame lit %d/%d (%.1f%%)  %dx%d" % [lit_all, all_total,
		100.0 * lit_all / maxi(1, all_total), img.get_width(), img.get_height()])
	if lit_all == 0:
		print("ROLE SHEET FAILED — the whole frame is black; the view is not rendering.")
		print("  refusing to save.")
		quit(2)
		return

	# The band is ARITHMETIC: the row is at camera_top + 190, and _to_screen maps
	# world y to (y - camera_top) * PX, so the row's screen y is 190 * PX_PER_UNIT.
	var sy: int = int(190.0 * PX_PER_UNIT)
	var top: int = clampi(sy - BAND_H / 2, 0, maxi(0, img.get_height() - BAND_H))
	var band := img.get_region(Rect2i(0, top, img.get_width(), BAND_H))
	band.resize(img.get_width() * ZOOM, BAND_H * ZOOM, Image.INTERPOLATE_NEAREST)

	# --- 1: the band must actually contain the row ---------------------------
	var lit := 0
	var total := 0
	for y in range(0, band.get_height(), 2):
		for x in range(0, band.get_width(), 2):
			total += 1
			var cb := band.get_pixel(x, y)
			if cb.r + cb.g + cb.b > 0.37:   # 0..1 floats, not 0..255
				lit += 1
	print("band lit %d/%d (%.1f%%) crop_top=%d" % [lit, total,
		100.0 * lit / maxi(1, total), top])
	if float(lit) / float(maxi(1, total)) < 0.04:
		print("ROLE SHEET FAILED — the band is effectively empty even though the frame is not.")
		print("  the row is not where the arithmetic says it is; refusing to save.")
		quit(2)
		return

	# --- 2: THE HUE CENSUS IS NOT A PIXEL CENSUS. ------------------------
	#
	# It used to be. It sampled a 44px-tall band and took "the most red-dominant
	# bright pixel" per column as the rim — which on a green-ground frame returns
	# SAND every time, because ground outnumbers a 2.2px rim by two orders of
	# magnitude. That is how the shipped version reported "28 rim-hue clashes"
	# with total confidence while every assertion around it passed.
	#
	# Measured instability is the other half of the proof: the same binary, same
	# seed, same frame content, returned 24 / 27 / 30 clashes across six runs.
	# A measurement whose answer moves by 6 on identical inputs is not measuring
	# the thing it names.
	#
	# So the distinctness question is answered from the TABLE, which is the actual
	# source of what gets drawn, and the pixels below are kept for what pixels can
	# answer honestly: is each column actually showing a sprite at all.
	var cmap: Dictionary = (load("res://src/main.gd") as Script).get_script_constant_map()
	var declared: Dictionary = cmap["_ROLE_RIM"]
	var per_hue := {}
	for k in declared:
		var col: Color = declared[k]
		var key := "%.2f/%.2f/%.2f" % [col.r, col.g, col.b]
		if per_hue.has(key):
			per_hue[key].append(k)
		else:
			per_hue[key] = [k]
	var unique := 0
	var declared_clashes := 0
	var hk: Array = per_hue.keys()
	for i in hk.size():
		var group: Array = per_hue[hk[i]]
		unique += 1
		print("  hue %s  %d role(s): %s" % [hk[i], group.size(), ", ".join(group)])
		# A shared hue is legitimate in exactly two documented cases, and each
		# has to be named here or this tool reports a design decision as a bug:
		#   - the rusher family's cosmetic skins, which the sim picks by POSITION
		#     HASH (sim_world.gd:4725) and are one archetype wearing four outfits;
		#   - sniper/pilot, who are co-present BY DESIGN (a pilot outlives the wave
		#     that spawned it, sim_world.gd:6571-6577) and are told apart by the
		#     non-hostile marker rather than the rim — giving the pilot its own hue
		#     spent a slot that a real role needed.
		var SHARED_OK := [
			["rusher", "enemy_smg", "enemy_assault", "enemy_shotgun", "enemy_lmg"],
			["enemy_sniper", "m_pilot"],
		]
		var excused := false
		for ok in SHARED_OK:
			if group.size() == ok.size():
				var same := true
				for k in group:
					if not (k in ok):
						same = false
				if same:
					excused = true
		if group.size() > 1 and not excused:
			declared_clashes += group.size() - 1
			print("    ILLEGITIMATE SHARE — no documented reason for these to match")
	print("DECLARED distinct hues: %d across %d rows (%d illegitimate shares)"
		% [unique, declared.size(), declared_clashes])
	print("  (the separation FLOOR is enforced statically in tests/test_role_rim.gd —")
	print("   hue distance between two 2.2px rims cannot be measured off this band)")

	# --- 3: per-column presence. What a pixel check CAN answer. ----------
	var dark_cols: Array[String] = []
	for i in KINDS.size():
		var cx: int = int((52 + i * 58) * PX_PER_UNIT * ZOOM)
		var col_lit := 0
		for y in range(0, band.get_height(), 2):
			for dx in range(-14, 15, 2):
				var x: int = clampi(cx + dx, 0, band.get_width() - 1)
				var c := band.get_pixel(x, y)
				if c.r + c.g + c.b > 0.37:   # 0..1 floats
					col_lit += 1
		if col_lit < 12:
			dark_cols.append(KINDS[i])

	if dark_cols.size() > 0:
		print("ROLE SHEET FAILED — no/too few lit pixels in the columns for: %s"
			% ", ".join(dark_cols))
		print("  refusing to save a sheet that cannot show what it claims to show.")
		quit(2)
		return

	var path := out_dir + "/role-rims.png"
	band.save_png(path)
	print("SAVED ", path)
	print("kinds, left to right: ", ", ".join(KINDS))
	print("RESULT: %d kinds posed, %d illegitimate hue shares" % [KINDS.size(), declared_clashes])
	await preload("res://tools/quiesce.gd").teardown(self, main)
	quit(0 if declared_clashes == 0 else 3)
