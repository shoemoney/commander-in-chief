extends SceneTree
## Probe: capture every content-well (HOWTO/HALL) TEXT box through a REAL draw pass and
## compare it to the frame chrome's ACTUAL interior hole, measured off SPR_HUD_Frame_Lrg.png.
## A CLEAN TREE PRINTS ZERO [OVER] LINES — the footer legend strip (y > 340) is excluded
## because it is drawn on the scrim BELOW the frame by design.
##   tools/run_tests.sh -s res://tools/probe_frame_bounds.gd

const Menu := preload("res://src/view/menu.gd")
const Layout := preload("res://tests/test_menu_layout.gd")

var _screens := [["HOWTO", 0], ["HOWTO", 1], ["HOWTO", 2], ["HOWTO", 3],
	["HOWTO", 4], ["HOWTO", 5], ["HALL", 0]]
var _i := -1
var _frame := 0
var _menu: GameMenu = null
var _stub: Node2D = null
var _ops: Array = []
var _interior := Rect2()


func _initialize() -> void:
	var img := Art.tex("ui_frame_lrg").get_image()
	var tw := img.get_width()
	var th := img.get_height()
	var mid_row := th / 2
	var mid_col := tw / 2
	var lx := 0
	while lx < tw and img.get_pixel(lx, mid_row).a <= 0.06:
		lx += 1
	var ix := lx
	while ix < tw and img.get_pixel(ix, mid_row).a > 0.06:
		ix += 1
	var rx := tw - 1
	while rx >= 0 and img.get_pixel(rx, mid_row).a <= 0.06:
		rx -= 1
	var irx := rx
	while irx >= 0 and img.get_pixel(irx, mid_row).a > 0.06:
		irx -= 1
	var ty := 0
	while ty < th and img.get_pixel(mid_col, ty).a <= 0.06:
		ty += 1
	var ity := ty
	while ity < th and img.get_pixel(mid_col, ity).a > 0.06:
		ity += 1
	var by := th - 1
	while by >= 0 and img.get_pixel(mid_col, by).a <= 0.06:
		by -= 1
	var iby := by
	while iby >= 0 and img.get_pixel(mid_col, iby).a > 0.06:
		iby -= 1
	var fr := Rect2(20, 8, 600, 344)
	var sx := fr.size.x / float(tw)
	var sy := fr.size.y / float(th)
	_interior = Rect2(fr.position.x + ix * sx, fr.position.y + ity * sy,
		(irx + 1 - ix) * sx, (iby + 1 - ity) * sy)
	print("[PROBE] tex %dx%d  h-band %d..%d and %d..%d   v-band %d..%d and %d..%d"
		% [tw, th, lx, ix - 1, irx + 1, rx, ty, ity - 1, iby + 1, by])
	print("[PROBE] frame rect %s  scale %.5f x %.5f" % [fr, sx, sy])
	print("[PROBE] MEASURED INTERIOR x %.2f..%.2f   y %.2f..%.2f"
		% [_interior.position.x, _interior.end.x, _interior.position.y, _interior.end.y])
	print("[PROBE] code: FRAME_INNER_R=%.1f  well=%s" % [Menu.FRAME_INNER_R, Menu._content_well_rect()])
	var f := Art.font()
	for s in [8, 10, 11, 13, 22]:
		print("[PROBE] font %2d ascent %.2f descent %.2f height %.2f"
			% [s, f.get_ascent(s), f.get_descent(s), f.get_height(s)])
	_stub = Layout._StubMain.new()
	get_root().add_child(_stub)
	_menu = GameMenu.new()
	_menu.main = _stub
	_menu.size = Vector2(640, 360)
	get_root().add_child(_menu)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame % 2 == 1:
		if _i >= 0:
			_report()
		_i += 1
		if _i >= _screens.size():
			print("[PROBE] done")
			return true
		var scr: Array = _screens[_i]
		_menu.mode = Menu.Mode.HALL if scr[0] == "HALL" else Menu.Mode.HOWTO
		_menu._howto_page = mini(int(scr[1]), 4)
		_menu._howto_endless_page = 1 if int(scr[1]) == 5 else 0
		_menu._open_t = 1.0
		_ops = []
		Art.text_capture = _ops
		_menu.queue_redraw()
	else:
		Art.text_capture = null
	return false


func _report() -> void:
	var f := Art.font()
	var scr: Array = _screens[_i]
	var tag := "%s/%d" % [scr[0], scr[1]]
	var worst := 0.0
	for op in _ops:
		var box: Rect2 = op["box"]
		# The footer legend strip is drawn on the SCRIM BELOW the frame by design (and is
		# pinned by test_footer_draw_commands_captured_both_devices, not by the frame bound).
		# Without this the probe printed 44 [OVER] lines on a CLEAN tree — all of them the
		# legend — and read as broken. Same exclusion the ratchet uses.
		if box.position.y > 340.0:
			continue
		var sz := int(op.get("size", 11))
		var nat_w: float = f.get_string_size(str(op["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var nat := Rect2(box.position, Vector2(nat_w, box.size.y))
		var over_l: float = _interior.position.x - nat.position.x
		var over_r: float = nat.end.x - _interior.end.x
		var over_t: float = _interior.position.y - nat.position.y
		var over_b: float = nat.end.y - _interior.end.y
		var w: float = maxf(maxf(over_l, over_r), maxf(over_t, over_b))
		if w > 0.5:
			worst = maxf(worst, w)
			print("[OVER] %-8s sz%-3d L%+6.1f R%+6.1f T%+6.1f B%+6.1f  x%.0f..%.0f y%.0f..%.0f  '%s'"
				% [tag, sz, over_l, over_r, over_t, over_b,
					nat.position.x, nat.end.x, nat.position.y, nat.end.y,
					str(op["id"]).substr(0, 56)])
	var top := 999.0
	var bot := -999.0
	var lft := 999.0
	var rgt := -999.0
	for op in _ops:
		var box: Rect2 = op["box"]
		if box.position.y > 340.0:
			continue   # footer legend strip: outside the frame by design
		var nat_w2: float = f.get_string_size(str(op["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(op.get("size", 11))).x
		top = minf(top, box.position.y)
		bot = maxf(bot, box.end.y)
		lft = minf(lft, box.position.x)
		rgt = maxf(rgt, box.position.x + nat_w2)
	print("[PROBE] %s %d strings | body band x %.0f..%.0f y %.0f..%.0f | back_rect %s | worst %.1f"
		% [tag, _ops.size(), lft, rgt, top, bot, _menu._back_rect(), worst])
