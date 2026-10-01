extends SceneTree
## CAMPAIGN CONTACT SHEET — real-run evidence, not a staged pose.
##
## WHY THIS EXISTS
##
## gpt-6.1-sol named THE ONE thing blocking a 10/10, twice: "authored encounter
## geography — the same rock and debris placements recur across the jungle, tank,
## bridge and foundry frames, making major encounters read as variations on one
## clearing." Then it said exactly what would settle it: "A continuous campaign
## capture would establish whether this repetition extends beyond these selected
## frames."
##
## It could not check, because every frame it has ever seen comes from
## tools/screenshots.gd — and every one of those poses the world the SAME way:
## `SimWorld.new(7, 1)`, a single fixed seed, a fresh world, the opening tick. So
## the rocks, the litter and the layout are byte-identical across all fourteen
## "different" frames. The repetition it measured is the HARNESS, not the game.
##
## This tool removes the harness. It starts a REAL campaign on a REAL seed, lets
## the sim actually advance, drives the player up the map, and grabs frames as the
## run crosses genuinely different world regions. That is the evidence the reviewer
## asked for and did not have.
##
## It also makes the ground/rock layout hash-visible: each frame is captured with
## the world Y it was taken at, so "does the layout repeat" is a question about
## the PNGs' captions rather than a vibe.
##
## Run:  SHOT_DIR=/tmp/cs Godot --path . --rendering-method gl_compatibility \
##         -s res://tools/campaign_contact_sheet.gd
##       CS_FRAMES=12  CS_TICKS=240   (optional: how many shots, ticks between)

var main: Node2D
var out_dir := "/tmp/cs"
var want := 12
var every := 240
var taken := 0
var bot_t := 0
var shots: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("campaign_contact_sheet: --headless has no framebuffer (needs gl_compatibility + a display)")
		print("SHOTS UNUSABLE — headless has no framebuffer")
		quit(1)
		return
	seed(0xC0FFEE)   # the VIEW's engine rng, so the sheet is diffable run-to-run
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp/cs"
	DirAccess.make_dir_recursive_absolute(out_dir)
	want = int(OS.get_environment("CS_FRAMES")) if not OS.get_environment("CS_FRAMES").is_empty() else 12
	every = int(OS.get_environment("CS_TICKS")) if not OS.get_environment("CS_TICKS").is_empty() else 240
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true
	_run()


## A deliberately dumb bot: hold forward, sweep the aim, fire. It is not here to
## win — it is here to MOVE UP THE MAP so the capture sees new world. The point
## is the scenery and the layout, not the combat.
## M1.1/M1.2 — ROLE_ROW mode. Six separate capture tools (tools/role_sheet.gd and
## five throwaway probes) tried to reproduce this file's frame priming and EVERY one
## produced a 0%-lit frame, including a minimal probe whose boot was a line-for-line
## copy of this file's. Recreating the priming is the bug. So this mode injects the
## one-of-each-kind row INTO the tool that already works, and inherits the priming
## instead of guessing at it.
const ROLE_KINDS := [
	"rusher", "elite", "enemy_smg", "enemy_assault", "enemy_shotgun",
	"enemy_lmg", "enemy_sniper", "sapper", "ghillie", "courier",
]


func _role_row() -> void:
	if OS.get_environment("ROLE_ROW") != "1":
		return
	var sim = main.sim
	if sim == null or sim.players.is_empty():
		return
	var cam: int = int(sim.camera_top)
	var row_y: int = cam + int(190 * Fixed.ONE)
	sim.enemies.clear()
	for j in ROLE_KINDS.size():
		sim.enemies.append({
			"x": int((52 + j * 58) * Fixed.ONE), "y": row_y, "alive": true,
			"elite": ROLE_KINDS[j] == "elite", "kind": ROLE_KINDS[j],
			# Defensive superset: the draw path reads several of these with [] not
			# .get(), so a field the SPAWNER happens not to set is still a hard error.
			"windup": 999, "fire_cd": 999, "submerged": false,
			"surface_ticks": 0, "lunge_ticks": 0, "hp": 40, "max_hp": 40,
		})


func _drive() -> void:
	if main == null or main.sim == null or main.sim.players.is_empty():
		return
	_role_row()
	# The sim reads PHYSICAL keys (main.gd _gather_inputs: is_physical_key_pressed
	# on bind("move_up") etc.), NOT InputMap actions, so Input.action_press() does
	# nothing here and the player stands still -- which is exactly what happened on
	# the first two attempts: a contact sheet of ONE spot wearing ten filenames.
	# Real key events have to go through Input.parse_input_event. Hold W to march
	# up the map and sweep A/D so the frames are not a corridor of one lane.
	var sway := int(sin(float(bot_t) * 0.02) * 40.0)
	_key(KEY_W, true)
	_key(KEY_D, sway > 0)
	_key(KEY_A, sway <= 0)
	_key(KEY_UP, true)     # aim keys default to the arrow cluster
	# Force gameplay every driven frame. The boot/splash flow re-asserts TITLE
	# asynchronously, so setting it once during warm-up loses the race: the tool
	# printed "boot settled into gameplay" and then captured menu=TITLE on every
	# single frame. Re-asserting here is idempotent and cannot be raced.
	main._menu.mode = GameMenu.Mode.HIDDEN
	bot_t += 1


## Send one real physical key event (down or up) through the engine's input queue.
func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _run() -> void:
	await _warm()
	var frames := 0
	while taken < want:
		await process_frame
		if main.sim == null:
			continue
		_drive()      # drive EVERY frame, or the player never moves between shots
		# Keyed on PROCESS frames, not sim ticks. The first version gated on
		# sim.tick_count, and a run that pauses (death screen, gate, the window
		# losing focus) stops advancing ticks while process_frame keeps firing --
		# so one pause after the first capture and the sheet produced ONE frame
		# and sat there. Wall frames always advance; the sim state is recorded
		# per-frame instead of being used as the clock.
		if frames < every:
			frames += 1
			continue
		frames = 0
		_drive()
		# The world Y is the caption that makes "does the layout repeat" falsifiable.
		var wy: int = main.sim.camera_top
		var shot := "%s/cs-%02d-wy%05d.png" % [out_dir, taken, wy]
		var img := root.get_texture().get_image()
		# M1.1: a saved PNG is not a usable PNG. This tool's own ancestor printed
		# SAVED on 0%-lit frames seven times. Count first, save second, and say so
		# loudly when the frame is blank instead of writing a black file.
		if img != null:
			var litp := 0
			for ly in range(0, img.get_height(), 8):
				for lx in range(0, img.get_width(), 8):
					if img.get_pixel(lx, ly).r + img.get_pixel(lx, ly).g + img.get_pixel(lx, ly).b > 96.0:
						litp += 1
			if litp <= 20:
				print("BLANK FRAME at %d (lit %d) — not saving a black PNG" % [taken, litp])
				taken += 1
				await process_frame
				continue
		if img != null:
			img.save_png(shot)
			shots.append(shot)
			# The caption is the evidence: gate, camera Y and whether the menu is up
			# are what turn "does the layout repeat" into a question about the sheet.
			print("SAVED ", shot, "  gate=", main.sim.current_sector(),
				" menu=", main._menu.mode, " tick=", main.sim.tick_count)
		taken += 1
		await process_frame
	print("CONTACT SHEET DONE — ", taken, " frames, seed 0x", String.num_int64(main.sim._world_seed, 16))
	for s in shots:
		print("  ", s)
	await preload("res://tools/quiesce.gd").teardown(self, main)
	quit(0)


func _warm() -> void:
	# The scene boots behind a "PRESS ANY BUTTON TO SKIP" splash and a title fade.
	# The first attempt at this tool called start_game() IMMEDIATELY and then
	# captured 10 frames of the boot splash and the TITLE SCREEN -- while printing
	# a world-Y and a gate number that both looked plausible, because the title's
	# live background runs the same world. So: boot to completion FIRST, THEN
	# start the run, THEN wait out the fade, and only capture once we are actually
	# in gameplay. A frame that is not gameplay must not be capturable.
	for i in 150:
		await process_frame
	# The boot splash completes AFTER the frames above and puts the game back on
	# TITLE (Mode.TITLE == 1), so an early start_game() is silently undone and the
	# sheet captures the TITLE over a scrolling background -- which is what the
	# first two attempts did. Re-assert until it actually sticks.
	for attempt in 8:
		main.start_game(false)               # a REAL campaign run on a real seed
		for i in 40:
			await process_frame
			if main._menu.mode == GameMenu.Mode.HIDDEN and main.sim != null:
				break
		if main._menu.mode == GameMenu.Mode.HIDDEN:
			print("boot settled into gameplay after attempt ", attempt + 1)
			break
	for i in 60:
		await process_frame
