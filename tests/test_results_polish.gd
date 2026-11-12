extends RefCounted
## results-polish: the after-action report's table, count-up, stamp and wiring.

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const RP := preload("res://src/view/results_polish.gd")


func test_rows_split_into_label_and_value_cells() -> void:
	Runner.T.eq(RP.split_cells("SCORE  264,500"), ["SCORE", "264,500"], "score row splits")
	Runner.T.eq(RP.split_cells("RANK  B  —  EXTERMINATOR"), ["RANK", "B — EXTERMINATOR"], "rank row")
	Runner.T.eq(RP.split_cells("214 KILLS  ·  LONGEST STREAK  x17"), ["214 KILLS", "LONGEST STREAK  x17"], "dot cells")
	Runner.T.eq(RP.split_cells("SECTOR 5/6   36m PUSHED"), ["SECTOR 5/6", "36m PUSHED"], "wide gap")
	Runner.T.eq(RP.split_cells("36m OF DESERT PUSHED"), ["36m OF DESERT PUSHED", ""], "single cell")
	Runner.T.eq(RP.split_cells("NEW MEDALS  S1 FLAWLESS  +8"), ["NEW MEDALS", "S1 FLAWLESS  +8"], "medal")
	Runner.T.eq(RP.split_cells("61 VP BANKED  —  ALL PERKS MASTERED"), ["61 VP BANKED", "ALL PERKS MASTERED"], "dash trimmed")


func test_action_and_medal_rows_are_recognised() -> void:
	Runner.T.ok(RP.is_action_row({"text": "[C] COPY RESULT"}), "keycap prompt")
	Runner.T.ok(RP.is_action_row({"text": "REDEPLOY", "icon": "glyph_key_enter"}), "redeploy")
	Runner.T.ok(not RP.is_action_row({"text": "SCORE  1"}), "stat row is not a button")
	Runner.T.ok(RP.is_medal_row({"text": "NEW MEDAL  S1"}), "medal call-out")


func test_tally_counts_up_and_never_ticks_non_tallies() -> void:
	Runner.T.eq(RP.tally_text("264,500", 0.5), "132,250", "half way, grouped")
	Runner.T.eq(RP.tally_text("264,500", 1.0), "264,500", "final frame is verbatim")
	Runner.T.eq(RP.tally_text("KILLS 121", 0.0), "KILLS 0", "starts at zero")
	Runner.T.eq(RP.tally_text("SECTOR 5/6", 0.3), "SECTOR 5/6", "sector never ticks")
	Runner.T.eq(RP.tally_text("» +12,400", 0.25), "» +3,100", "bank gain ticks")


func test_clock_is_instant_when_posed_reduced_or_skipped() -> void:
	var c := RP.new()
	c.update("V", 1.0, 1.0, 100, false)
	Runner.T.eq(c.row_progress(3), 1.0, "settled card shows final numbers")
	var d := RP.new()
	d.update("V", 0.08, 1.0, 100, false)
	Runner.T.ok(d.row_progress(0) < 1.0, "a fresh card counts up")
	Runner.T.eq(d.stamp_age(5), -1, "stamp waits for the tally")
	d.update("V", 0.5, 1.0, 100 + RP.LEAD + 5 * RP.STAGGER + RP.TALLY_FRAMES + 2, false)
	Runner.T.ok(d.stamp_age(5) >= 0, "stamp lands after the tally")
	var e := RP.new()
	e.update("V", 0.08, 0.0, 100, false)
	Runner.T.eq(e.row_progress(0), 1.0, "reduce-motion is static")
	var f := RP.new()
	f.update("V", 0.08, 1.0, 100, false)
	f.update("V", 0.1, 1.0, 101, true)
	Runner.T.eq(f.row_progress(0), 1.0, "skip jumps to final")
	var g := RP.new()
	g.update("V", 1.0, 1.0, 10, false)
	g.update("V", 0.08, 1.0, 11, false)
	Runner.T.ok(g.row_progress(0) < 1.0, "restart replays")


func test_rank_stamp_reads_grade_and_colour_from_rows() -> void:
	var rows := [{"text": "RANK  A — EXTERMINATOR", "color": Color(1, 0, 0)}, {"text": "SCORE  1", "color": Color.WHITE}]
	Runner.T.eq(RP.rank_grade(rows), "A", "grade letter")
	Runner.T.eq(RP.rank_color(rows), Color(1, 0, 0), "grade colour")
	Runner.T.eq(RP.rank_grade([{"text": "SCORE  1", "color": Color.WHITE}]), "", "no rank row, no stamp")


func test_result_panel_is_wired_through_the_polish_module() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var body := src.substr(src.find("func _draw_result_panel("))
	body = body.substr(0, body.find("\nfunc "))
	for call in ["_rp.update(", "ResultsPolish.draw_headline(", "_rp.draw_row(", "ResultsPolish.draw_stamp(", "ResultsPolish.draw_table_bg("]:
		Runner.T.ok(body.contains(call), "_draw_result_panel calls " + call)
	var m = MainScript.new()
	Runner.T.ok(m.get("_rp") is RP, "the real main carries the polish painter")
	m.free()
