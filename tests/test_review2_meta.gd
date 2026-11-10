extends RefCounted
## review2-meta: three defects a second independent review found in merged work.
##  1. The SWIFT pars are checked against a LIVE bot run, not a number someone wrote down.
##  2. A veteran save with no [settings] section keeps full captions on upgrade.
##  3. Every action an end card accepts is advertised by a row on that card (the matrix).

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")
const SR := preload("res://src/view/service_record.gd")


class _NullSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


func _main() -> Node2D:
	var main: Node2D = MainScript.new()
	main._sfx.free()
	main._sfx = _NullSfx.new()
	return main


# --- 1. pars vs the live bot ---------------------------------------------------------------

## Seeds measured live inside the blocking suite (about 3.5 s each). 2 and 3 carry the slowest
## sector 4 and sector 5 clears of seeds 1-5. PAR_SEEDS=1,2,3,4,5 widens it (opt-in, ~18 s).
func _par_seeds() -> Array[int]:
	var out: Array[int] = []
	var raw := OS.get_environment("PAR_SEEDS") if OS.has_environment("PAR_SEEDS") else "2,3"
	for t in raw.split(","):
		out.append(int(t))
	return out


func test_pars_leave_1_4x_over_the_live_bot_clears() -> void:
	var slowest: Array[int] = [0, 0, 0, 0, 0, 0]
	for sd in _par_seeds():
		var clears := ParMeasure.bot_sector_clears(sd)
		Runner.T.eq(clears.size(), SR.SECTORS, "seed %d: the bot wins the campaign and reports 6 sector clears" % sd)
		if clears.size() != SR.SECTORS:
			continue
		for i in SR.SECTORS:
			slowest[i] = maxi(slowest[i], clears[i])
	for i in SR.SECTORS:
		Runner.T.ok(slowest[i] > 0, "sector %d was measured" % (i + 1))
		Runner.T.ok(SR.PAR_TICKS[i] >= int(ceil(slowest[i] * 1.4)),
			"sector %d par %d >= 1.4x the slowest live bot clear %d" % [i + 1, SR.PAR_TICKS[i], slowest[i]])


# --- 2. captions on a veteran save with no [settings] --------------------------------------

func _stash_save(tag: String) -> Dictionary:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var stash := path + tag
	var stashb := bak + tag
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, stash)
	if FileAccess.file_exists(bak):
		DirAccess.rename_absolute(bak, stashb)
	return {"path": path, "bak": bak, "stash": stash, "stashb": stashb}


func _restore_save(s: Dictionary) -> void:
	if FileAccess.file_exists(s["path"]):
		DirAccess.remove_absolute(s["path"])
	if FileAccess.file_exists(s["bak"]):
		DirAccess.remove_absolute(s["bak"])
	if FileAccess.file_exists(s["stash"]):
		DirAccess.rename_absolute(s["stash"], s["path"])
	if FileAccess.file_exists(s["stashb"]):
		DirAccess.rename_absolute(s["stashb"], s["bak"])


func _caption_mode_after(sections: Dictionary) -> int:
	var cf := ConfigFile.new()
	for sec in sections:
		for k in sections[sec]:
			cf.set_value(sec, k, sections[sec][k])
	cf.save(MainScript.SAVE_PATH)
	var main := MainScript.new()
	main._load_bests()
	var mode: int = main._caption_mode
	main.free()
	return mode


func test_veteran_save_without_settings_keeps_full_captions() -> void:
	var s := _stash_save(".r2meta")
	var hall_run := {"score": 1200, "mode": "campaign", "sector": 2, "hid": 0}
	Runner.T.eq(_caption_mode_after({"hall": {"runs": [hall_run]}}), CuePolicy.CAP_ALL,
		"[hall] but no [settings]: an existing player keeps ALL")
	Runner.T.eq(_caption_mode_after({"best": {"score": 900}}), CuePolicy.CAP_ALL, "[best] only: ALL")
	Runner.T.eq(_caption_mode_after({"front": {"intro_seen": true}}), CuePolicy.CAP_ALL, "[front] only: ALL")
	Runner.T.eq(_caption_mode_after({"settings": {"captions": CuePolicy.CAP_SMART}}), CuePolicy.CAP_SMART,
		"an explicit saved SMART is respected")
	Runner.T.eq(_caption_mode_after({}), CuePolicy.CAP_SMART, "an empty file is a new install: SMART")
	_restore_save(s)
	s = _stash_save(".r2meta2")
	var fresh := MainScript.new()
	fresh._load_bests()
	Runner.T.eq(fresh._caption_mode, CuePolicy.CAP_SMART, "no save file at all: SMART")
	fresh.free()
	_restore_save(s)


# --- 3. the end-card action matrix ---------------------------------------------------------

func _stage(kind: String, victory: bool) -> Node2D:
	var main := _main()
	main._endless = false
	main._boss_rush = false
	main._daily = false
	main._arcade_chapter = -1
	match kind:
		"arcade":
			main._arcade_chapter = 3
		"endless":
			main._endless = true
		"boss_rush":
			main._boss_rush = true
		"daily":
			main._daily = true
	main._reset()
	if kind == "campaign" or kind == "retried":
		for i in 3:
			main.sim.gates.append({"open": true})
	if kind == "retried":
		main._menu.mode = GameMenu.Mode.HIDDEN
		main._debrief = true
		main._result_t = 1.0
		Runner.T.ok(main._try_retry_sector(), "retried: the retry started")
	main.sim.victory = victory
	main.sim.wiped = not victory
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._debrief = true
	main._result_t = 1.0
	return main


func _card_rows(main: Node2D) -> Array:
	if main.sim.victory:
		return main._victory_tail_rows(1.0)
	return main._debrief_meta_rows(1.0) + [{"text": main.redeploy_label()}]


func _advertised(rows: Array, needle: String) -> bool:
	for r in rows:
		if needle in String(r["text"]):
			return true
	return false


func test_every_end_card_action_is_advertised_where_it_works() -> void:
	for kind in ["campaign", "arcade", "retried", "endless", "boss_rush", "daily"]:
		for victory in [false, true]:
			var tag := "%s/%s" % [kind, "victory" if victory else "defeat"]
			var main := _stage(kind, victory)
			var rows := _card_rows(main)
			var retry_works: bool = main._retry_sector() > 0
			Runner.T.eq(_advertised(rows, "RETRY SECTOR"), retry_works,
				"%s: RETRY SECTOR is advertised exactly when the key works" % tag)
			var ncamp_works: bool = main._try_new_campaign()   # last: it restarts the run
			Runner.T.eq(_advertised(rows, "RANKED CAMPAIGN"), ncamp_works,
				"%s: NEW RANKED CAMPAIGN is advertised exactly when the key works" % tag)
			Runner.T.ok(_advertised(rows, "REDEPLOY"), "%s: REDEPLOY is advertised" % tag)
			Runner.T.ok(_advertised(rows, "[C] COPY"), "%s: the C copy key is advertised (keyboard)" % tag)
			if kind == "retried":
				Runner.T.ok(_advertised(rows, "UNRANKED"),
					"%s: REDEPLOY says it re-runs the sector UNRANKED" % tag)
				Runner.T.eq(ncamp_works, true, "%s: the way back to a ranked campaign works" % tag)
			main.free()
