extends RefCounted
## c1-02: TITLE-menu decompression regression guards. Pins the button-column
## geometry that the row-height crush fix bought — every TITLE state (with and
## without BEST / CAREER / WATCH LAST RUN) must clear a >=20px hit plate and a
## 16px icon, seat clear of the record header, and clear the y322 input legend.
## Also pins the pure mouse hit-test and the BACK-navigation targets through
## SETUP and OPTIONS. All checks call menu.gd's extracted PURE statics, so no
## Control / Art / `main` / scene tree is needed — this runs headless.

const Runner := preload("res://tests/run_tests.gd")
const Menu := preload("res://src/view/menu.gd")
const MainScript := preload("res://src/main.gd")

# _draw floors the icon at clampf(bh - 3, 9, 16); a >=16px icon needs bh >= 19.
const MIN_PLATE := 20.0
const LEGEND_Y := 322.0   # input-legend strip top; no plate may reach it


func _icon_size(bh: float) -> float:
	return clampf(bh - 3.0, 9.0, 16.0)


# Minimal stand-in for main.gd so _menu_items() can run headless — supplies just
# the fields the TITLE / SETUP / OPTIONS branches read. Lets the tests couple to
# the REAL generated row counts instead of hard-coding them (so a future added
# row is caught by the plate-height guards, not silently under-counted).
class _StubSfx extends RefCounted:
	func play(_a: String, _b: float = 0.0, _c: float = 1.0) -> void: pass


# A real Sfx subclass whose play() is a guaranteed no-op — injected into a live
# main.gd so _step_vol()'s view-side cue never needs a readied audio graph. Being
# a Sfx it satisfies main._sfx's static type; the override removes any doubt that
# the AudioServer integration tests below touch playback.
class _NullSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


class _StubMain extends Node2D:
	var best_score := 0
	var _life_runs := 0
	var _two_players := false
	var _hard := false
	var _motion := 1.0
	var colorblind := false
	var _rumble_on := true
	var _assist := false
	var _saved := 0
	var _set_calls: Array = []       # records every _set_bus_vol(name, v) the menu makes
	var _levels := {"SFX": 8, "Music": 8}   # STATEFUL: a step reads back what the last one wrote
	var _sfx := _StubSfx.new()
	func _bus_vol(n: String) -> int: return _levels.get(n, 8)
	func _set_bus_vol(name: String, v: int) -> void:
		_levels[name] = v
		_set_calls.append([name, v])
	func _save_settings() -> void: _saved += 1


# Real generated row count for a mode, via a throwaway Menu bound to a stub main.
func _row_count(mode_id: int, has_replay: bool) -> int:
	var m: Control = Menu.new()
	var stub := _StubMain.new()
	m.main = stub
	m.mode = mode_id
	m._has_replay = has_replay
	var n: int = m._menu_items().size()
	m.free()
	stub.free()
	return n


# Every TITLE row count (real generated: base verbs+config+options+quit, plus
# WATCH LAST RUN when a replay exists) crossed with every record-header state
# must decompress to legible plates.
func test_title_states_all_clear_20px_plate_and_16px_icon() -> void:
	var counts := [_row_count(Menu.Mode.TITLE, false), _row_count(Menu.Mode.TITLE, true)]
	Runner.T.ok(counts.max() >= 8, "fullest TITLE reaches its 8-row cap (got %d)" % counts.max())
	for n in counts:                       # real list sizes, not hard-coded
		for has_best in [false, true]:
			for has_career in [false, true]:
				var head: float = Menu.title_head_bottom(has_best, has_career)
				var g: Dictionary = Menu.compute_geometry(Menu.Mode.TITLE, n, head)
				var bh: float = g["bh"]
				var top: float = g["top"]
				var gap: float = g["gap"]
				var tag := "TITLE n=%d best=%s career=%s" % [n, has_best, has_career]
				Runner.T.ok(bh >= MIN_PLATE, "%s: hit plate %dpx must be >= 20" % [tag, int(bh)])
				Runner.T.ok(_icon_size(bh) >= 16.0, "%s: icon %dpx must be >= 16" % [tag, int(_icon_size(bh))])
				# No header overlap: the first plate must open below the header block.
				Runner.T.ok(top > head, "%s: first plate top %d must clear header bottom %d" % [tag, int(top), int(head)])
				# No legend overlap: the last plate's bottom must stay above y322.
				var last_bottom := floorf(top + float(n - 1) * gap) + bh
				Runner.T.ok(last_bottom < LEGEND_Y, "%s: last plate bottom %d must clear legend %d" % [tag, int(last_bottom), int(LEGEND_Y)])
				# Plates must not overlap (gap >= bh) so hit boxes stay distinct.
				Runner.T.ok(gap >= bh, "%s: gap %d must be >= plate %d" % [tag, int(gap), int(bh)])


# The 2px inter-row inset must leave a real gap between plates at the fullest
# 8-row state so group dividers stay legible (not fused into one slab).
func test_title_fullest_state_keeps_a_visible_inter_row_gap() -> void:
	var head: float = Menu.title_head_bottom(true, true)   # worst case: record block pushes rows down
	var g: Dictionary = Menu.compute_geometry(Menu.Mode.TITLE, 8, head)
	var dead: float = float(g["gap"]) - float(g["bh"])
	Runner.T.ok(dead >= 2.0, "fullest TITLE keeps a >=2px dead band for dividers (got %d)" % int(dead))


# The open-settle drop-in (top slides up to +12px low while opening) must never
# push the last TITLE plate into the y322 input legend, at ANY point of the
# animation (_open_t 0 -> 1). TITLE is the only screen that draws the legend.
func test_open_settle_never_overlaps_title_legend() -> void:
	var g: Dictionary = Menu.compute_geometry(Menu.Mode.TITLE, 8, Menu.title_head_bottom(true, true))
	for step in 11:
		var open_t := float(step) / 10.0            # 0.0 (fully dropped) .. 1.0 (settled)
		var off: float = Menu.settle_offset(g, open_t, 1.0, 321.0)   # motion ON, TITLE legend floor
		var last_bottom := floorf(float(g["top"]) + off + 7.0 * float(g["gap"])) + float(g["bh"])
		Runner.T.ok(last_bottom < LEGEND_Y, "TITLE @open_t=%.1f: last plate bottom %d must clear legend" % [open_t, int(last_bottom)])
	# Reduce-motion (motion < 0.5) disables the drop-in entirely.
	Runner.T.eq(Menu.settle_offset(g, 0.0, 0.0, 321.0), 0.0, "reduce-motion yields no drop-in offset")
	# Sub-screens (no legend) keep their FULL 12px drop-in against the canvas floor.
	var opts: Dictionary = Menu.compute_geometry(Menu.Mode.OPTS, _row_count(Menu.Mode.OPTS, false), -1.0)
	Runner.T.eq(Menu.settle_offset(opts, 0.0, 1.0, 358.0), 12.0, "OPTIONS keeps the full drop-in (no legend to clear)")


# Mouse hit-test: each row's vertical center must resolve to that row, and
# adjacent plates must meet (a point between them can't fall through to -1).
func test_hit_test_maps_centers_and_leaves_no_dead_gap() -> void:
	var head: float = Menu.title_head_bottom(true, true)
	var g: Dictionary = Menu.compute_geometry(Menu.Mode.TITLE, 8, head)
	var top: float = g["top"]
	var gap: float = g["gap"]
	var bh: float = g["bh"]
	for k in 8:
		var cy := floorf(top + float(k) * gap) + bh / 2.0
		Runner.T.eq(Menu.hit_row(g, cy), k, "center of row %d hits row %d" % [k, k])
		if k < 7:
			# The seam midway to the next plate must belong to k or k+1, never -1.
			var seam := floorf(top + float(k) * gap) + bh + (gap - bh) / 2.0
			Runner.T.ok(Menu.hit_row(g, seam) != -1, "seam below row %d does not fall through" % k)
	# A point up in the header region is above the column entirely.
	Runner.T.eq(Menu.hit_row(g, head - 4.0), -1, "point in the header region hits no row")


# Non-TITLE screens (OPTIONS at its fullest, RUN SETUP) also stay >=20px plates.
func test_setup_and_options_rows_stay_legible() -> void:
	# OPTIONS & INFO fronts HALL + HOW TO PLAY + the settings rows + BACK.
	var on := _row_count(Menu.Mode.OPTS, false)
	var opts: Dictionary = Menu.compute_geometry(Menu.Mode.OPTS, on, -1.0)
	Runner.T.ok(float(opts["bh"]) >= MIN_PLATE, "OPTIONS %d-row plate %d >= 20" % [on, int(opts["bh"])])
	# RUN SETUP is CO-OP + NG+ HARD + BACK.
	var sn := _row_count(Menu.Mode.SETUP, false)
	var setup: Dictionary = Menu.compute_geometry(Menu.Mode.SETUP, sn, -1.0)
	Runner.T.ok(float(setup["bh"]) >= MIN_PLATE, "RUN SETUP %d-row plate %d >= 20" % [sn, int(setup["bh"])])


# BACK / Esc must climb exactly one level: SETUP + OPTIONS -> TITLE (their
# parent), HALL + HOW TO PLAY -> OPTIONS (where they were relocated), and the
# roots (TITLE/PAUSE/HIDDEN) have no back target.
func test_back_navigation_targets() -> void:
	Runner.T.eq(Menu.back_dest(Menu.Mode.SETUP), {"mode": Menu.Mode.TITLE, "sel": "run_setup"}, "SETUP back -> TITLE/run_setup")
	Runner.T.eq(Menu.back_dest(Menu.Mode.OPTS), {"mode": Menu.Mode.TITLE, "sel": "options"}, "OPTIONS back -> TITLE/options")
	Runner.T.eq(Menu.back_dest(Menu.Mode.HALL), {"mode": Menu.Mode.OPTS, "sel": "hall"}, "HALL back -> OPTIONS/hall")
	Runner.T.eq(Menu.back_dest(Menu.Mode.HOWTO), {"mode": Menu.Mode.OPTS, "sel": "howto"}, "HOWTO back -> OPTIONS/howto")
	Runner.T.ok(Menu.back_dest(Menu.Mode.TITLE).is_empty(), "TITLE is a root: no back target")
	Runner.T.ok(Menu.back_dest(Menu.Mode.PAUSE).is_empty(), "PAUSE handles its own back (HIDDEN)")
	Runner.T.ok(Menu.back_dest(Menu.Mode.HIDDEN).is_empty(), "HIDDEN is a root: no back target")


# c1-03: the SFX/MUSIC row shares ONE model between its label, its segment bar,
# and both input paths (◄/► and Enter/click) — a clamped 0..10 level where
# 0 == MUTED. These pin the pure helpers that model unifies through.
func test_volume_row_is_mute_aware() -> void:
	# A muted bus reads MUTED with an EMPTY bar, even if a stale volume_db lingers
	# at a nonzero level — the surface can never show a full bar while silent.
	Runner.T.eq(Menu.effective_vol(true, 8), 0, "muted-at-8 -> effective level 0 (empty bar)")
	Runner.T.eq(Menu.vol_label(true, 8), "MUTED", "muted-at-8 label reads MUTED, not '8'")
	Runner.T.eq(Menu.vol_label(true, 0), "MUTED", "muted-at-0 label reads MUTED")
	# 0 == MUTED even without the mute flag stamped yet (contract consistency).
	Runner.T.eq(Menu.vol_label(false, 0), "MUTED", "level 0 reads MUTED regardless of flag")
	# An audible bus shows its number and the matching bar level.
	Runner.T.eq(Menu.effective_vol(false, 7), 7, "audible bus keeps its level")
	Runner.T.eq(Menu.vol_label(false, 7), "7", "audible label is the number")


func test_volume_step_is_clamped_both_ways() -> void:
	# ◄/► and Enter all clamp to 0..10 — no input wraps a nudge into a mute.
	Runner.T.eq(Menu.step_level(0, 1), 1, "step up from muted (0) unmutes to 1")
	Runner.T.eq(Menu.step_level(10, 1), 10, "step up at max clamps at 10 (Enter can't mute)")
	Runner.T.eq(Menu.step_level(1, -1), 0, "step down to 0 is the deliberate mute")
	Runner.T.eq(Menu.step_level(0, -1), 0, "step down at min clamps at 0")
	Runner.T.eq(Menu.step_level(5, 1), 6, "mid-range step up")
	Runner.T.eq(Menu.step_level(5, -1), 4, "mid-range step down")


# Integration: the real _settings_rows() on a live Menu produces mute-aware rows
# (headless buses read unmuted, so the stub level shows through as a number+bar).
func test_settings_rows_integration_reflects_level() -> void:
	var m: Control = Menu.new()
	var stub := _StubMain.new()
	m.main = stub
	m.mode = Menu.Mode.OPTS
	var rows: Array[Dictionary] = m._settings_rows()
	Runner.T.eq(rows[0]["label"], "SFX: 8", "SFX row label carries the level")
	Runner.T.eq(rows[0]["vol"], 8, "SFX bar level matches the label")
	Runner.T.eq(rows[1]["label"], "MUSIC: 8", "MUSIC row label carries the level")
	m.free()
	stub.free()


# Integration: _step_vol() (the one path ◄/► AND Enter/click share) routes every
# change through _set_bus_vol and persists it — up clamps, down reaches 0 (mute).
func test_step_vol_routes_through_shared_setter() -> void:
	var m: Control = Menu.new()
	var stub := _StubMain.new()
	m.main = stub
	m.mode = Menu.Mode.OPTS
	m._step_vol("SFX", 1)      # stub level 8, unmuted -> 9
	m._step_vol("Music", -1)   # 8 -> 7
	Runner.T.eq(stub._set_calls, [["SFX", 9], ["Music", 7]], "both buses move via _set_bus_vol")
	Runner.T.eq(stub._saved, 2, "each step persists settings once")
	m.free()
	stub.free()


# Integration: Enter (_activate) and ◄ (_nav) on a volume row BOTH reach the one
# shared _step_vol — the unified model, proven at the input layer (keyboard and
# mouse arrows both funnel through _nav, so this covers all three input paths).
func test_activate_and_nav_reach_step_vol() -> void:
	var m: Control = Menu.new()
	var stub := _StubMain.new()
	m.main = stub
	m.mode = Menu.Mode.OPTS
	var rows: Array[Dictionary] = m._menu_items()
	var sfx_i := -1
	for i in rows.size():
		if rows[i]["id"] == "sfx":
			sfx_i = i
	Runner.T.ok(sfx_i >= 0, "OPTS exposes an SFX volume row")
	m.sel = sfx_i
	m._activate()      # Enter/click path -> +1 (stateful stub 8 -> 9)
	m._nav(0, -1)      # ◄ path (keyboard + mouse arrows both call _nav): reads 9 -> 8
	Runner.T.eq(stub._set_calls, [["SFX", 9], ["SFX", 8]], "Enter (+1) then arrow (-1) compound on the live level")
	m.free()
	stub.free()


# Enter/click clamps at 10 and never wraps into a mute — a stateful stub proves
# consecutive steps ride the written level and the top rail stops writing.
func test_enter_clamps_at_max_and_never_wraps_to_mute() -> void:
	var m: Control = Menu.new()
	var stub := _StubMain.new()
	stub._levels["SFX"] = 9
	m.main = stub
	m.mode = Menu.Mode.OPTS
	var sfx_i := -1
	var rows: Array[Dictionary] = m._menu_items()
	for i in rows.size():
		if rows[i]["id"] == "sfx":
			sfx_i = i
	m.sel = sfx_i
	m._activate()   # 9 -> 10
	m._activate()   # already 10: clamps, no further write (never wraps to 0/MUTED)
	Runner.T.eq(stub._set_calls, [["SFX", 10]], "Enter tops out at 10 and stops — no wrap to mute")
	m.free()
	stub.free()


# Mirror sfx.gd's bus layout so the real _set_bus_vol/_bus_vol can run headless
# (no Sfx node, hence no _ready to create the buses). Idempotent: only adds a
# missing bus, so a suite ordering that already stood the buses up is fine.
func _ensure_audio_buses() -> void:
	for name in ["SFX", "Music", "UI", "VO"]:
		if AudioServer.get_bus_index(name) == -1:
			var i := AudioServer.get_bus_count()
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")


# Snapshot mute+volume for EVERY bus these tests can touch (SFX and its slaved
# UI/VO, plus Music) so the exact prior global state is restored — no suite can
# inherit a muted bus. Runner.T.ok never aborts the method, so the paired restore
# at each test's tail always runs even when an assertion fails.
func _snapshot_buses() -> Dictionary:
	var s := {}
	for name in ["SFX", "Music", "UI", "VO"]:
		var i := AudioServer.get_bus_index(name)
		if i != -1:
			s[name] = [AudioServer.is_bus_mute(i), AudioServer.get_bus_volume_db(i)]
	return s


func _restore_buses(s: Dictionary) -> void:
	for name in s:
		var i := AudioServer.get_bus_index(name)
		if i != -1:
			AudioServer.set_bus_mute(i, s[name][0])
			AudioServer.set_bus_volume_db(i, s[name][1])


# END-TO-END: the REAL main.gd _set_bus_vol/_bus_vol against LIVE AudioServer
# buses — the failure-prone piece the stubbed tests above can't reach. Proves
# level 0 actually mutes the hardware bus, stepping off 0 unmutes it, the
# SFX-slaved UI + VO buses stay in lockstep with SFX, and Music is independent.
func test_set_bus_vol_mutes_and_slaves_on_real_audioserver() -> void:
	_ensure_audio_buses()
	var saved := _snapshot_buses()
	var mn: Node2D = MainScript.new()   # real main.gd; _ready never fires (not in tree)
	var sfx_i := AudioServer.get_bus_index("SFX")
	var ui_i := AudioServer.get_bus_index("UI")
	var vo_i := AudioServer.get_bus_index("VO")
	var mus_i := AudioServer.get_bus_index("Music")

	# Level 0 == MUTED: the SFX bus AND both slaved buses (UI jingles, VO radio)
	# actually go silent on the AudioServer — not just the UI number.
	mn._set_bus_vol("SFX", 0)
	Runner.T.ok(AudioServer.is_bus_mute(sfx_i), "level 0 mutes the real SFX bus")
	Runner.T.ok(AudioServer.is_bus_mute(ui_i), "SFX 0 also mutes the slaved UI bus")
	Runner.T.ok(AudioServer.is_bus_mute(vo_i), "SFX 0 also mutes the slaved VO bus")
	Runner.T.eq(mn._bus_vol("SFX"), 0, "_bus_vol reads 0 while the bus is muted")

	# Stepping OFF 0 unmutes every slaved bus and restores an audible level.
	mn._set_bus_vol("SFX", 6)
	Runner.T.ok(not AudioServer.is_bus_mute(sfx_i), "stepping to 6 unmutes SFX")
	Runner.T.ok(not AudioServer.is_bus_mute(ui_i), "stepping off 0 unmutes the UI bus too")
	Runner.T.ok(not AudioServer.is_bus_mute(vo_i), "stepping off 0 unmutes the VO bus too")
	Runner.T.eq(mn._bus_vol("SFX"), 6, "_bus_vol reads back the restored level")

	# Music is a separate knob: muting it must not touch the SFX-slaved buses.
	mn._set_bus_vol("Music", 0)
	Runner.T.ok(AudioServer.is_bus_mute(mus_i), "Music 0 mutes the Music bus")
	Runner.T.ok(not AudioServer.is_bus_mute(sfx_i), "muting Music leaves SFX audible")
	Runner.T.ok(not AudioServer.is_bus_mute(ui_i), "muting Music leaves the UI bus audible")
	mn.free()
	_restore_buses(saved)   # every touched bus (SFX/UI/VO/Music) back to entry state


# END-TO-END, THE ORIGINAL BUG: a bus muted externally (e.g. an OS/legacy mute)
# while its stored volume_db still reads a full level. The row must show MUTED /
# empty bar (not the stale "8" + full green), and a single ◄/►/Enter step must
# unmute it to 1 — never restore the hidden level. Bus state is saved + restored
# so this can't leak a muted SFX bus into a later suite. main._sfx is unreadied,
# so its play() is a null-safe no-op (no audio playback needed here).
func test_externally_muted_bus_shows_muted_and_step_unmutes_to_one() -> void:
	_ensure_audio_buses()
	var saved := _snapshot_buses()
	var sfx_i := AudioServer.get_bus_index("SFX")

	# Reproduce the failure state: level 8 stored, but the bus is muted.
	AudioServer.set_bus_volume_db(sfx_i, linear_to_db(0.8))
	AudioServer.set_bus_mute(sfx_i, true)
	var floor_db := AudioServer.get_bus_volume_db(sfx_i)   # as the bus stored it (float32)

	var mn: Node2D = MainScript.new()
	mn._sfx = _NullSfx.new()   # inject the no-op cue so _step_vol needs no audio graph
	var m: Control = Menu.new()
	m.main = mn
	m.mode = Menu.Mode.OPTS
	var rows: Array[Dictionary] = m._settings_rows()
	Runner.T.eq(rows[0]["label"], "SFX: MUTED", "externally-muted bus reads MUTED, not the stale '8'")
	Runner.T.eq(rows[0]["vol"], 0, "muted bus shows an empty bar (vol 0), never a full green one")

	# Direction matters from the muted floor: ◄ (down) must NOT write — the bus
	# stays muted at the stored db (step clamps 0 -> 0, a no-op, not a re-mute).
	m._step_vol("SFX", -1)
	Runner.T.ok(AudioServer.is_bus_mute(sfx_i), "◄ at the muted floor leaves the bus muted")
	Runner.T.eq(AudioServer.get_bus_volume_db(sfx_i), floor_db,
		"◄ at the floor writes nothing — stored db is untouched")

	# ►/Enter (up) lifts it off mute to level 1 (0 -> 1), not back to the hidden 8.
	m._step_vol("SFX", 1)
	Runner.T.ok(not AudioServer.is_bus_mute(sfx_i), "► unmutes the bus off the floor")
	Runner.T.eq(mn._bus_vol("SFX"), 1, "unmute lands on level 1, not the stale stored level")

	m.free()
	mn.free()
	_restore_buses(saved)   # SFX/UI/VO/Music all back to entry state


# END-TO-END via the ACTIVATION path: Enter (_activate) on an externally-muted
# SFX row must unmute it to level 1 — proving the real key/click activation
# wiring (not just _step_vol in isolation) recovers a silenced bus.
func test_enter_on_externally_muted_row_unmutes_via_activate() -> void:
	_ensure_audio_buses()
	var saved := _snapshot_buses()
	var sfx_i := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx_i, linear_to_db(0.8))
	AudioServer.set_bus_mute(sfx_i, true)

	var mn: Node2D = MainScript.new()
	mn._sfx = _NullSfx.new()
	var m: Control = Menu.new()
	m.main = mn
	m.mode = Menu.Mode.OPTS
	var rows: Array[Dictionary] = m._menu_items()
	var sfx_row := -1
	for i in rows.size():
		if rows[i]["id"] == "sfx":
			sfx_row = i
	Runner.T.ok(sfx_row >= 0, "OPTS exposes an SFX row to activate")
	m.sel = sfx_row
	m._activate()   # Enter/click path -> _step_vol("SFX", 1)
	Runner.T.ok(not AudioServer.is_bus_mute(sfx_i), "Enter on the muted row unmutes it")
	Runner.T.eq(mn._bus_vol("SFX"), 1, "Enter unmutes to level 1, not the stale stored level")

	m.free()
	mn.free()
	_restore_buses(saved)
