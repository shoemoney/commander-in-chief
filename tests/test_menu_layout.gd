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

# _draw floors the icon at clampf(bh - 3, 9, 16); a >=16px icon needs bh >= 19.
const MIN_PLATE := 20.0
const LEGEND_Y := 322.0   # input-legend strip top; no plate may reach it


func _icon_size(bh: float) -> float:
	return clampf(bh - 3.0, 9.0, 16.0)


# Minimal stand-in for main.gd so _menu_items() can run headless — supplies just
# the fields the TITLE / SETUP / OPTIONS branches read. Lets the tests couple to
# the REAL generated row counts instead of hard-coding them (so a future added
# row is caught by the plate-height guards, not silently under-counted).
class _StubMain extends Node2D:
	var best_score := 0
	var _life_runs := 0
	var _two_players := false
	var _hard := false
	var _motion := 1.0
	var colorblind := false
	var _rumble_on := true
	var _assist := false
	func _bus_vol(_n: String) -> int: return 8


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
