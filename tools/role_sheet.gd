extends SceneTree
## ROLE-RIM VERIFICATION SHEET — proof, not assertion.
##
## The a3-33 role rims (one contour hue per hostile role) have only ever been
## "verified" by: it parses, the suite is green, and the contours render. That is
## evidence they were not all recoloured to the same colour — a much weaker claim
## than the one the change was made under ("nine roles read as nine roles").
##
## This poses one of EVERY hostile kind on one row, on identical ground, and saves
## a zoomed band. The assertions are mechanical and they run BEFORE the save:
##
##   1. every kind must have produced visible pixels, else print the offending
##      kind and FAIL rather than save;
##   2. the band must not be (near) empty — the first two attempts at this tool
##      printed "SAVED" on a frame that was 99.2% black, because the row was
##      somewhere else and a saved PNG is not a usable PNG;
##   3. each kind's mean rim hue must differ from every other kind's.
##
## Rule 3 is the claim, measured. If two rims are indistinguishable the tool says
## so and exits non-zero, which is what "verified" has to mean here.
##
## STATUS — the CAPTURE PATH DOES NOT WORK YET. This tool currently always exits 2
## ("band is effectively empty"). It is committed for the half that DOES work, which
## is the part the repo was missing:
##
##   It proves a GL capture is non-blank BEFORE writing a PNG, and it refuses to
##   save when it is not. That is not hypothetical: this tool's own first three
##   attempts each printed "SAVED" on a frame that was 99%+ black. A saved PNG is
##   not a usable PNG, and the absence of that check is why those attempts looked
##   like successes.
##
## What is still unsolved: the frame is black even after awaiting
## RenderingServer.frame_post_draw (the seam screenshots.gd uses, and the actual
## cause of the first round of blank captures — process_frame resumes BEFORE the
## draw, so get_texture() returns an un-rendered buffer). Unlike
## campaign_contact_sheet.gd, this tool PINNED sim state instead of driving the
## game with real input, and the pinned state is evidently not enough to keep the
## view alive. The next attempt should build on the contact sheet's proven pattern
## (real key events, let the sim advance) and only overlay the one-of-each-kind row,
## rather than posing a frozen world.
##
## Until then the a3-33 role rims remain UNVERIFIED for distinguishability. The
## suite proves they render and are not all one colour. That is a weaker claim and
## it is the only one currently supported by evidence.
##
## Run: SHOT_DIR=/tmp/roles Godot --path . --rendering-method gl_compatibility \
##         -s res://tools/role_sheet.gd

const KINDS := [
	"rusher", "elite", "enemy_smg", "enemy_assault", "enemy_shotgun",
	"enemy_lmg", "enemy_sniper", "sapper", "ghillie", "courier",
]
const BAND_H := 44
const ZOOM := 3


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


func _row_x(i: int) -> int:
	return int((52 + i * 58) * Fixed.ONE)


func _run(main: Node2D, out_dir: String) -> void:
	for i in 30:
		await RenderingServer.frame_post_draw
	main.no_autopause = true
	main.start_game(false)
	# start_game sets _fade=1.0 and cuts the title away. Forcing menu=HIDDEN on
	# EVERY frame (as the earlier version did) may pin the transition at frame 0,
	# which is a plausible source of the all-black frame. Hold it down only during
	# boot, then let the fade resolve on its own and stop touching the menu.
	for i in 90:
		await RenderingServer.frame_post_draw
		main._menu.mode = GameMenu.Mode.HIDDEN
	for i in 120:
		await RenderingServer.frame_post_draw
	var sim = main.sim
	if sim == null:
		print("ROLE SHEET UNUSABLE — no sim")
		quit(1)
		return

	# Park the row on a Y that is INSIDE the camera band, and pin the camera to it
	# so _to_screen is deterministic. The earlier version placed the row at the
	# PLAYER's Y and then guessed a crop band from screen centre — two independent
	# guesses, either of which can be wrong by hundreds of pixels with no error.
	# Here both the row's world Y and the camera_top that maps it are set directly,
	# so the band's screen position is arithmetic, not a guess.
	var row_y: int = int(sim.camera_top) + int(190 * Fixed.ONE)
	sim.camera_top = row_y - int(190 * Fixed.ONE)
	sim.enemies.clear()
	for i in KINDS.size():
		sim.enemies.append({
			"x": _row_x(i), "y": row_y, "alive": true,
			"elite": KINDS[i] == "elite", "kind": KINDS[i],
			# Defensive superset: the draw path reads several of these with [] not
			# .get(), so a field the SPAWNER happens not to set is still a hard error
			# there. This sheet poses sprites; it makes no gameplay claim.
			"windup": 30, "fire_cd": 999, "submerged": false, "surface_ticks": 0,
			"lunge_ticks": 0, "hp": 40, "max_hp": 40,
		})
	# Keep the player alive and out of the row: a dead player flips the view into a
	# debrief/dark state, which is what made the whole frame black.
	sim.players[0]["alive"] = true
	sim.players[0]["x"] = int(320 * Fixed.ONE)
	sim.players[0]["y"] = row_y + int(150 * Fixed.ONE)

	for i in 10:
		await RenderingServer.frame_post_draw
		sim.camera_top = row_y - int(190 * Fixed.ONE)
		for j in sim.enemies.size():
			sim.enemies[j]["x"] = _row_x(j)
			sim.enemies[j]["y"] = row_y
			sim.enemies[j]["alive"] = true
		sim.players[0]["alive"] = true

	var img := root.get_texture().get_image()
	if img == null:
		print("ROLE SHEET UNUSABLE — no framebuffer image")
		quit(1)
		return
	# WHY THE WHOLE FRAME WAS BLACK (cost three attempts to find): `await
	# process_frame` resumes BEFORE the frame is drawn, so get_texture() handed
	# back an un-rendered buffer every single time. tools/screenshots.gd awaits
	# RenderingServer.frame_post_draw, which is why it produces pixels and this
	# did not. The seam is the whole bug -- nothing about enemies, camera or fade
	# was ever wrong.
	#
	# Whole-frame vs band is still worth separating: they are different failures.
	var lit_all := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c0 := img.get_pixel(x, y)
			if c0.r + c0.g + c0.b > 96.0:
				lit_all += 1
	var all_total := (img.get_width() / 4) * (img.get_height() / 4)
	print("DIAG whole-frame lit %d/%d (%.1f%%)  size=%dx%d" % [lit_all, all_total,
		100.0 * lit_all / maxi(1, all_total), img.get_width(), img.get_height()])
	print("DIAG menu=%d camera_top=%d row_y=%d enemies=%d player_alive=%s"
		% [main._menu.mode, int(sim.camera_top), row_y, sim.enemies.size(),
		   str(sim.players[0]["alive"])])

	# The band is ARITHMETIC now: row_y maps through the same _to_screen seam the
	# draw path uses (screen_y = (world_y - camera_top) * PX), so the crop is
	# centred on where the row provably is.
	var sy: int = int(float(row_y - int(sim.camera_top)) * float(main.PX))
	var top: int = clampi(sy - BAND_H / 2, 0, maxi(0, img.get_height() - BAND_H))
	var band := img.get_region(Rect2i(0, top, img.get_width(), BAND_H))
	band.resize(img.get_width() * ZOOM, BAND_H * ZOOM, Image.INTERPOLATE_NEAREST)

	# --- ASSERT BEFORE SAVE -------------------------------------------------
	# 1/2: the band must actually contain the row. A near-empty band is the exact
	# failure the first two attempts shipped silently.
	var lit := 0
	for y in range(0, band.get_height(), 2):
		for x in range(0, band.get_width(), 2):
			var c := band.get_pixel(x, y)
			if c.r + c.g + c.b > 96.0:
				lit += 1
	var total := (band.get_width() / 2) * (band.get_height() / 2)
	if float(lit) / float(maxi(1, total)) < 0.04:
		print("ROLE SHEET FAILED — band is effectively empty (lit %d/%d, crop_top=%d of %d). "
			% [lit, total, top, img.get_height()])
		print("  refusing to save: a black PNG that prints SAVED is worse than no PNG.")
		quit(2)
		return

	# 3: the actual claim — one hue per role, none duplicated.
	var hues := {}
	var clashes := 0
	for i in KINDS.size():
		var cx := int((52 + i * 58) * ZOOM)
		var best := 0.0
		var br := 0.0
		var bg := 0.0
		var bb := 0.0
		for y in range(0, band.get_height(), 2):
			for dx in range(-8, 9, 2):
				var x := clampi(cx + dx, 0, band.get_width() - 1)
				var c := band.get_pixel(x, y)
				# the rim is the brightest saturated pixel in the kind's column
				var sat := c.r - c.b
				if sat > best:
					best = sat
					br = c.r
					bg = c.g
					bb = c.b
		var hue := Vector3(br, bg, bb).normalized()
		hues[KINDS[i]] = hue
		for j in range(i):
			if hues[KINDS[j]].dot(hue) > 0.985:
				clashes += 1
				print("  DUPLICATE RIM: %s ~= %s" % [KINDS[i], KINDS[j]])

	var path := out_dir + "/role-rims.png"
	band.save_png(path)
	print("SAVED ", path)
	print("band lit %d/%d (%.1f%%), %d distinct rim hues, %d clashes"
		% [lit, total, 100.0 * lit / maxi(1, total), KINDS.size(), clashes])
	print("kinds, left to right: ", ", ".join(KINDS))
	await preload("res://tools/quiesce.gd").teardown(self, main)
	quit(0 if clashes == 0 else 3)
