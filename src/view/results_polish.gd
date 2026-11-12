class_name ResultsPolish
extends RefCounted
## VIEW ONLY. The after-action report's presentation: the headline treatment, the rank
## stamp, the aligned two-column tally with its count-up, the action-prompt pills and the
## new-medal call-out. main._draw_result_panel owns the layout (panel, row pitch, title y --
## all pinned by tests); this module owns how the ink inside it looks.
##
## Rows arrive as {"text", "color", "icon"?...} dictionaries built by callers that only know
## strings, so the label/value split is derived from the text (split_cells), never from a
## second parallel row format. Nothing here touches the sim.

const TALLY_FRAMES := 36      ## frames one row's number takes to count up
const STAGGER := 3            ## frames between consecutive rows starting
const LEAD := 8               ## frames after the card lands before the first row counts
const STAMP_R := 26.0
const TABLE_PAD := 20.0       ## panel edge -> table edge
const MIN_GAP := 8.0          ## narrowest label/value gap before a row falls back to centred
const GOLD := Color(1.0, 0.85, 0.3)
const NUM_PREFIXES := ["", "SCORE ", "KILLS ", "» +", "x", "(+", "BEST "]

# --- count-up clock ---------------------------------------------------------------------
var _key := ""
var _last_t := 0.0
var _start := 0
var _frames := 0
var _settled := true


## Call once per draw. A card that is first seen already settled (result_t >= 1, as the
## capture harness poses it), under reduce-motion, or skipped, shows final numbers at once.
func update(key: String, result_t: float, motion: float, frames: int, skip: bool) -> void:
	if key != _key or result_t < _last_t:
		_key = key
		_start = frames
		_settled = result_t >= 1.0
	_last_t = result_t
	_frames = frames
	if skip or motion < 0.5:
		_settled = true


func row_progress(i: int) -> float:
	if _settled:
		return 1.0
	var f := float(_frames - _start - LEAD - i * STAGGER)
	var p := clampf(f / float(TALLY_FRAMES), 0.0, 1.0)
	return 1.0 - pow(1.0 - p, 3.0)


## Frames since the last number landed; -1 while the tally is still running.
func stamp_age(n: int) -> int:
	if _settled:
		return 999
	var end := _start + LEAD + n * STAGGER + TALLY_FRAMES
	return -1 if _frames < end else _frames - end


## Tab or a left click skips the count-up (ENTER/SPACE are REDEPLOY, so they cannot).
static func skip_pressed() -> bool:
	return Input.is_key_pressed(KEY_TAB) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


# --- text model -------------------------------------------------------------------------

## [left, right]. "right" is "" for a row that is one cell. Two cells come from a "·"
## separator or from the LAST run of two-plus spaces (the callers' own column gap).
static func split_cells(text: String) -> Array:
	if text.begins_with("RANK ") and text.length() > 6:
		var rest := text.substr(5).strip_edges()
		while rest.contains("  "):
			rest = rest.replace("  ", " ")
		return ["RANK", rest]
	for lead in ["NEW MEDALS", "NEW MEDAL"]:
		if text.begins_with(lead + " "):
			return [lead, text.substr(lead.length()).strip_edges()]
	if text.contains("·"):
		var p := text.split("·", false, 1)
		if p.size() == 2:
			return [String(p[0]).strip_edges(), String(p[1]).strip_edges()]
	var gap := -1
	var i := text.length() - 1
	while i > 0:
		if text[i] == " " and text[i - 1] == " ":
			var j := i
			while j > 0 and text[j - 1] == " ":
				j -= 1
			gap = j
			break
		i -= 1
	if gap <= 0:
		return [text, ""]
	var left := text.substr(0, gap).strip_edges()
	var right := text.substr(gap).strip_edges()
	while left.ends_with("—") or left.ends_with("-"):
		left = left.substr(0, left.length() - 1).strip_edges()
	if left.is_empty() or right.is_empty():
		return [text, ""]
	return [left, right]


static func is_action_row(row: Dictionary) -> bool:
	var t := String(row.get("text", ""))
	return t.begins_with("[") or t.begins_with("REDEPLOY") \
		or String(row.get("icon", "")).begins_with("glyph_")


static func is_medal_row(row: Dictionary) -> bool:
	return String(row.get("text", "")).begins_with("NEW MEDAL")


## The grade letter of a "RANK  A — TITLE" row, or "".
static func rank_grade(rows: Array) -> String:
	for r in rows:
		var t := String(r["text"])
		if t.begins_with("RANK"):
			var rest := t.substr(4).strip_edges()
			return rest.substr(0, 1) if not rest.is_empty() else ""
	return ""


static func rank_color(rows: Array) -> Color:
	for r in rows:
		if String(r["text"]).begins_with("RANK"):
			return r["color"]
	return GOLD


## `cell` with its first number replaced by the in-flight count at progress p (0..1).
## Only numbers after a known lead-in count (SCORE / KILLS / + / x / bare), so "SECTOR 5/6"
## never ticks through sectors that were not reached. The final frame returns `cell` as-is.
static func tally_text(cell: String, p: float) -> String:
	if p >= 1.0:
		return cell
	var s := -1
	for k in cell.length():
		if cell[k] >= "0" and cell[k] <= "9":
			s = k
			break
	if s < 0 or not NUM_PREFIXES.has(cell.substr(0, s)):
		return cell
	var e := s
	while e < cell.length() and ((cell[e] >= "0" and cell[e] <= "9") or cell[e] == ","):
		e += 1
	var digits := cell.substr(s, e - s)
	var v := int(digits.replace(",", ""))
	var shown := int(round(float(v) * p))
	var txt := Art.group_digits(shown) if digits.contains(",") else str(shown)
	return cell.substr(0, s) + txt + cell.substr(e)


static func _plain(c: Color) -> bool:
	return c.r > 0.78 and absf(c.r - c.g) < 0.06 and c.b > 0.7


# --- drawing ----------------------------------------------------------------------------

## Backdrop + flanks + outlined headline. `win` picks the language: gold sparkle for a win,
## red hazard stripes for a loss.
static func draw_headline(ci: CanvasItem, title: String, title_y: float, title_col: Color,
		panel_x: float, panel_w: float, panel_top: float, win: bool, ea: float, motion: float) -> void:
	var cx := panel_x + panel_w / 2.0
	var tw := Art.tw(title, 24)
	var base := Color(1.0, 0.8, 0.25) if win else Color(0.9, 0.22, 0.18)
	var cy := title_y - 8.0
	if win:
		ci.draw_texture_rect(Art.tex("fx_softspot"), Rect2(cx - 150.0, cy - 30.0, 300.0, 60.0),
			false, Color(1.0, 0.8, 0.3, 0.5 * ea))
	else:
		ci.draw_rect(Rect2(panel_x + 4.0, cy - 17.0, panel_w - 8.0, 34.0), Color(0.45, 0.05, 0.05, 0.4 * ea))
	var lx0 := panel_x + 14.0
	var lx1 := cx - tw / 2.0 - 10.0
	var rx0 := cx + tw / 2.0 + 10.0
	var rx1 := panel_x + panel_w - 14.0
	for side in 2:
		var x0 := lx0 if side == 0 else rx0
		var x1 := lx1 if side == 0 else rx1
		if x1 - x0 < 14.0:
			continue
		if not win:
			var k := x0
			while k + 8.0 <= x1:
				ci.draw_line(Vector2(k, cy + 9.0), Vector2(k + 8.0, cy - 9.0), Color(base, 0.34 * ea), 1.0)
				k += 6.0
		ci.draw_rect(Rect2(x0, cy - 1.0, x1 - x0, 1.0), Color(base, 0.85 * ea))
		ci.draw_rect(Rect2(x0, cy + 2.0, x1 - x0, 1.0), Color(base, 0.35 * ea))
		var tip := x1 if side == 0 else x0
		var s := 1.0 if side == 0 else -1.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(tip, cy - 4.0), Vector2(tip + 4.0 * s, cy + 1.0),
			Vector2(tip, cy + 4.0), Vector2(tip - 4.0 * s, cy + 1.0)]), Color(base, ea))
	if win and motion >= 0.5:
		var ph := float(Engine.get_frames_drawn()) * 0.06
		for sp: Vector2 in [Vector2(-tw / 2.0 - 4.0, -14.0), Vector2(tw / 2.0 + 2.0, 6.0), Vector2(-tw / 4.0, 8.0),
				Vector2(tw / 3.0, -16.0)]:
			var tw_a := maxf(0.0, sin(ph + sp.x * 0.13))
			var c := Vector2(cx, cy) + sp
			var a := Color(1.0, 0.95, 0.7, tw_a * ea)
			ci.draw_rect(Rect2(c.x - 3.0, c.y, 7.0, 1.0), a)
			ci.draw_rect(Rect2(c.x, c.y - 3.0, 1.0, 7.0), a)
	Art.text_center(ci, title, cx, title_y, 24, title_col, 0.0, 2)


static func draw_table_bg(ci: CanvasItem, panel_x: float, panel_w: float, top: float,
		bottom: float, accent: Color, ea: float) -> void:
	var r := Rect2(panel_x + 10.0, top, panel_w - 20.0, bottom - top)
	ci.draw_rect(r, Color(0.0, 0.0, 0.0, 0.34 * ea))
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1.0), Color(accent, 0.22 * ea))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(accent, 0.22 * ea))


## One table row at baseline y. Returns nothing; every datum of the text is drawn, either as
## label-left / value-right cells or (action prompts, rows too wide for two cells) centred.
func draw_row(ci: CanvasItem, row: Dictionary, i: int, y: float, row_h: float, x0: float,
		x1: float, ea: float) -> void:
	var text: String = row["text"]
	var col: Color = row["color"]
	col.a *= ea
	var size: int = row.get("size", 11)
	var icon: String = row.get("icon", "")
	var isz: float = row.get("icon_size", 14.0)
	var icol: Color = row.get("icon_col", Color.WHITE)
	icol.a *= ea
	var mid := y - 4.0
	var action := is_action_row(row)
	var medal := is_medal_row(row)
	var cells := [text, ""] if action else split_cells(text)
	var left: String = cells[0]
	var right: String = cells[1]
	var p := row_progress(i)
	var lshow := tally_text(left, p)
	var rshow := tally_text(right, p)
	var iw := isz + 6.0 if not icon.is_empty() else 0.0
	var fit := Art.tw(left, size) + Art.tw(right, size) + iw + MIN_GAP <= x1 - x0
	var plate_h := minf(row_h - 1.0, 15.0)
	# banding / plates, under the ink
	if action:
		var pw := minf(Art.tw(text, size) + iw + 28.0, x1 - x0 + 12.0)
		var pr := Rect2(320.0 - pw / 2.0, mid - plate_h / 2.0, pw, plate_h).abs()
		pr.position = pr.position.round()
		ci.draw_rect(pr, Color(col.r, col.g, col.b, 0.14 * ea))
		ci.draw_rect(Rect2(pr.position.x, pr.position.y, pr.size.x, 1.0), Color(col.r, col.g, col.b, 0.55 * col.a))
		ci.draw_rect(Rect2(pr.position.x, pr.end.y - 1.0, pr.size.x, 1.0), Color(col.r, col.g, col.b, 0.55 * col.a))
	elif medal:
		var mr := Rect2(x0 - 6.0, mid - plate_h / 2.0, x1 - x0 + 12.0, plate_h)
		ci.draw_rect(mr, Color(GOLD, 0.2 * ea))
		ci.draw_rect(Rect2(mr.position.x, mr.position.y, mr.size.x, 1.0), Color(GOLD, 0.7 * ea))
		ci.draw_rect(Rect2(mr.position.x, mr.end.y - 1.0, mr.size.x, 1.0), Color(GOLD, 0.7 * ea))
	elif i % 2 == 1:
		ci.draw_rect(Rect2(x0 - 6.0, mid - plate_h / 2.0, x1 - x0 + 12.0, plate_h), Color(1, 1, 1, 0.05 * ea))
	if action or not fit:
		# centred whole-row fallback (the original layout), numbers still count up
		var whole := tally_text(text, p) if not action else text
		var tot := Art.tw(whole, size) + iw
		var x := 320.0 - tot / 2.0
		if not icon.is_empty():
			ci.draw_texture_rect(Art.tex(icon), Rect2(x, y - isz + 3.0, isz, isz), false, icol)
			x += iw
		Art.text(ci, whole, Vector2(x, y), size, col)
		return
	var x := x0
	if not icon.is_empty():
		ci.draw_texture_rect(Art.tex(icon), Rect2(x, y - isz + 3.0, isz, isz), false, icol)
		x += iw
	if right.is_empty():
		Art.text(ci, lshow, Vector2(x, y), size, col)
		return
	var lcol := col
	var rcol := col
	if _plain(col):
		lcol = Color(0.68, 0.72, 0.66, col.a)
		rcol = Color(1.0, 1.0, 0.94, col.a)
	if right.contains("NEW BEST"):
		rcol = Color(GOLD, col.a)
	Art.text(ci, lshow, Vector2(x, y), size, lcol)
	# right cell is right-aligned on its FINAL width so the digits do not jitter
	var rx := x1 - Art.tw(rshow, size)
	Art.text(ci, rshow, Vector2(rx, y), size, rcol)


## The grade seal straddling the plate's top-right corner. Appears when the tally lands.
static func draw_stamp(ci: CanvasItem, center: Vector2, grade: String, col: Color,
		age: int, ea: float, motion: float) -> void:
	if grade.is_empty() or age < 0:
		return
	var a := ea
	if motion >= 0.5 and age < 6:
		a *= float(age + 1) / 6.0
	var c := center.round()
	var r := STAMP_R
	ci.draw_circle(c + Vector2(1, 2), r + 3.0, Color(0, 0, 0, 0.45 * a))
	ci.draw_circle(c, r + 3.0, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, a))
	ci.draw_circle(c, r, Color(0.07, 0.07, 0.06, 0.96 * a))
	for k in 24:
		var ang := TAU * float(k) / 24.0
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(c + d * (r + 3.0), c + d * (r + 5.0), Color(col, 0.9 * a), 2.0)
	ci.draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(col, a), 2.0)
	ci.draw_arc(c, r - 5.0, 0.0, TAU, 32, Color(col, 0.45 * a), 1.0)
	Art.text_center(ci, grade, c.x, c.y + 8.0, 24, Color(col, a), 0.0, 1)
	if motion >= 0.5 and age >= 0 and age < 14:
		var fr := r + 4.0 + float(age) * 1.6
		ci.draw_arc(c, fr, 0.0, TAU, 40, Color(1, 1, 1, 0.6 * (1.0 - float(age) / 14.0) * ea), 2.0)
