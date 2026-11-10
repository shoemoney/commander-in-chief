class_name ServiceRecord
extends RefCounted
## service-record: what a finished run leaves behind besides a number. VIEW-ONLY, persisted
## by Main in the existing save under [service]; nothing here touches src/sim or the checksum.
##
##   * per-sector MEDALS (Campaign only, earned forever): FLAWLESS (no knockdown in the sector),
##     SWIFT (cleared under PAR_TICKS) and HOARDER (cleared without the war chest ever dropping).
##   * BEST RANK + best reach per mode (campaign, endless, boss rush, arcade, daily).
##
## Honesty: medals and bests are only ever COMMITTED from Main._record_run, i.e. after the run
## cleared replay verification, and never for a run the Hall itself files as assisted (accessibility
## vest/assist tags or purchased perks). Medals additionally need a plain, unretried Campaign
## run (Arcade is where RETRY SECTOR and CHAPTER SELECT live), so no start-mid-sector run counts.
##
## The tracker watches the sim's own per-tick event list (player_down, gate_open, victory,
## wiped) and war_chest; it never writes the sim.

const FLAWLESS := 1
const SWIFT := 2
const HOARDER := 4
const MEDALS: Array[int] = [FLAWLESS, SWIFT, HOARDER]
const MEDAL_NAMES := {FLAWLESS: "FLAWLESS", SWIFT: "SWIFT", HOARDER: "HOARDER"}
const MEDAL_TEX := {FLAWLESS: "medal_flawless", SWIFT: "medal_swift", HOARDER: "medal_hoarder"}
const SECTORS := 6

## SWIFT par per sector, in 60 Hz sim ticks. Anchored to MEASURED clears of the combat bot
## (main.gd demo_input, GOD MODE ON - god mode restores ammo and stand-ups, so these are
## bot-with-god-mode times, not a human's). Re-measured 2026-11-10 on the tree WITH the Siege
## Tank (ParMeasure.bot_sector_clears, seeds 1-5): slowest clear per sector was
## 553 / 1024 / 2803 / 3092 / 4886 / 1827 ticks; each par is that x 1.75, rounded to 100.
## (Sector 5 was 1860 on the pre-Siege-Tank tree the first pars were cut from.)
## tests/test_review2_meta.gd re-measures live and fails if any par drops under 1.4x.
## A human who plays the sector at all carefully has a wide margin.
const PAR_TICKS: Array[int] = [1000, 1800, 4900, 5400, 8600, 3200]

const MODES: Array[String] = ["campaign", "endless", "boss_rush", "arcade", "daily"]
const MODE_LABELS := {"campaign": "CAMPAIGN", "endless": "ENDLESS", "boss_rush": "BOSS RUSH",
	"arcade": "ARCADE", "daily": "DAILY"}
const GRADES: Array[String] = ["D", "C", "B", "A", "S"]
const GRADE_COLS := {"S": Color(1.0, 0.85, 0.3), "A": Color(0.55, 0.9, 1.0),
	"B": Color(0.6, 0.9, 0.5), "C": Color(0.85, 0.85, 0.8), "D": Color(0.7, 0.7, 0.7)}

# --- persisted ---------------------------------------------------------------
var medals: Array[int] = [0, 0, 0, 0, 0, 0]      ## bitmask per sector, index 0 = sector 1
var best_grade := {}                              ## mode key -> "S".."D"
var best_reach := {}                              ## mode key -> int (see reach_value)

# --- this run (not persisted) --------------------------------------------------
var new_medals: Array = []                        ## [{sector, medal}] earned FIRST time by the last commit
var _live := false
var _earned: Array[int] = [0, 0, 0, 0, 0, 0]
var _sector := 1
var _t0 := 0
var _downs := 0
var _spent := false
var _prev_chest := 0


# --- pure rules ----------------------------------------------------------------
static func par_ticks(sector: int) -> int:
	return PAR_TICKS[clampi(sector, 1, SECTORS) - 1]


## "0:17" for a tick count at 60 Hz.
static func clock_text(ticks: int) -> String:
	var s := ticks / 60
	return "%d:%02d" % [s / 60, s % 60]


## Which medals a sector clear earns, from the three observed numbers.
static func medals_for_clear(sector: int, ticks: int, knockdowns: int, spent: bool) -> int:
	var m := 0
	if knockdowns == 0:
		m |= FLAWLESS
	if ticks <= par_ticks(sector):
		m |= SWIFT
	if not spent:
		m |= HOARDER
	return m


## Medals are banked only for a plain Campaign run: not the daily, not Arcade/retry/Endless/Rush,
## and not anything the Hall files as assisted (vest, accessibility assists, purchased perks).
static func medals_eligible(mode: String, daily: bool, assisted: bool) -> bool:
	return mode == "campaign" and not daily and not assisted


static func mode_key(mode: String, daily: bool) -> String:
	return "daily" if daily else mode


## One comparable "how far" integer per mode. Campaign-shaped modes: sector reached, +1 for a win.
## Boss Rush: gunships downed, +1 for a win. Endless: wave.
static func reach_value(mode: String, sector: int, bosses: int, wave: int, won: bool) -> int:
	if mode == "endless":
		return maxi(wave, 0)
	if mode == "boss_rush":
		return clampi(bosses, 0, SimWorld.BOSS_RUSH_COUNT) + (1 if won else 0)
	return clampi(sector, 1, SECTORS) + (1 if won else 0)


static func reach_text(key: String, v: int) -> String:
	if v <= 0:
		return ""
	if key == "endless":
		return "WAVE %d" % v
	if key == "boss_rush":
		return "VICTORY" if v > SimWorld.BOSS_RUSH_COUNT else "BOSS %d/%d" % [v, SimWorld.BOSS_RUSH_COUNT]
	return "VICTORY" if v > SECTORS else "SECTOR %d" % v


static func grade_rank(g: String) -> int:
	return GRADES.find(g)


static func medal_label(sector: int, medal: int) -> String:
	return "S%d %s" % [sector, MEDAL_NAMES.get(medal, "")]


# --- run tracking --------------------------------------------------------------
func begin_run(sim: SimWorld) -> void:
	new_medals.clear()
	_earned = [0, 0, 0, 0, 0, 0]
	_live = sim != null and sim.mode == "campaign"
	_sector = 1
	_t0 = sim.tick_count if sim != null else 0
	_downs = 0
	_spent = false
	_prev_chest = sim.war_chest if sim != null else 0


## Called after every sim.step() of a live run. Reads only the sim's per-tick events + chest.
func observe(sim: SimWorld) -> void:
	if not _live or sim == null:
		return
	var terminal := false
	for ev in sim.events:
		var t: String = ev.get("t", "")
		if t == "wiped" or t == "victory":
			terminal = true
	# The terminal chest bank (a win/wipe pays the chest out) is not a purchase.
	if sim.war_chest < _prev_chest and not terminal:
		_spent = true
	_prev_chest = sim.war_chest
	for ev in sim.events:
		match ev.get("t", ""):
			"player_down":
				_downs += 1
			"gate_open":
				_close_sector(sim.tick_count)
			"victory":
				if _sector == SECTORS:
					_close_sector(sim.tick_count)


func _close_sector(tick: int) -> void:
	if _sector > SECTORS:
		return
	_earned[_sector - 1] = medals_for_clear(_sector, tick - _t0, _downs, _spent)
	_sector += 1
	_t0 = tick
	_downs = 0
	_spent = false


## Medals this run cleared so far (mask per sector) - read by tests and the debrief preview.
func earned_this_run() -> Array[int]:
	return _earned.duplicate()


## Bank the run. Returns (and remembers) the FIRST-TIME medals; a second call finds nothing new.
func commit_run(eligible: bool, key: String, grade: String, reach: int, assisted: bool) -> Array:
	new_medals.clear()
	if eligible:
		for i in SECTORS:
			var fresh := _earned[i] & ~medals[i]
			for m in MEDALS:
				if fresh & m:
					new_medals.append({"sector": i + 1, "medal": m})
			medals[i] |= _earned[i]
		_earned = [0, 0, 0, 0, 0, 0]
	if not assisted and key in MODES:
		if grade_rank(grade) > grade_rank(str(best_grade.get(key, ""))):
			best_grade[key] = grade
		best_reach[key] = maxi(int(best_reach.get(key, 0)), reach)
	return new_medals


func medal_total() -> int:
	var n := 0
	for i in SECTORS:
		for m in MEDALS:
			if medals[i] & m:
				n += 1
	return n


func medal_max() -> int:
	return SECTORS * MEDALS.size()


## The debrief one-liner, or {} when the run earned nothing new.
func callout_row() -> Dictionary:
	if new_medals.is_empty():
		return {}
	var first: Dictionary = new_medals[0]
	var txt := "NEW MEDAL  " + medal_label(int(first["sector"]), int(first["medal"]))
	if new_medals.size() > 1:
		txt = "NEW MEDALS  " + medal_label(int(first["sector"]), int(first["medal"])) \
			+ "  +%d" % (new_medals.size() - 1)
	return {"text": txt, "color": Color(1.0, 0.86, 0.35),
		"icon": MEDAL_TEX[int(first["medal"])], "icon_size": 14.0}


# --- persistence ----------------------------------------------------------------
func to_section() -> Dictionary:
	var d := {}
	for i in SECTORS:
		d["m%d" % (i + 1)] = medals[i]
	for k in best_grade:
		d["rank_" + str(k)] = best_grade[k]
	for k in best_reach:
		d["reach_" + str(k)] = best_reach[k]
	return d


func load_from(cf: ConfigFile) -> void:
	medals = [0, 0, 0, 0, 0, 0]
	best_grade = {}
	best_reach = {}
	var all := FLAWLESS | SWIFT | HOARDER
	for i in SECTORS:
		var v: Variant = cf.get_value("service", "m%d" % (i + 1), 0)
		medals[i] = (int(v) & all) if (v is int or v is float) else 0
	for k in MODES:
		var g: Variant = cf.get_value("service", "rank_" + k, "")
		if g is String and g in GRADES:
			best_grade[k] = g
		var r: Variant = cf.get_value("service", "reach_" + k, 0)
		if (r is int or r is float) and int(r) > 0:
			best_reach[k] = clampi(int(r), 0, 999)


# --- page layout (pure; the Hall's RECORD tab draws exactly these) --------------
const X_L := 112.0
const COL0_X := 250.0          ## centre of the sector-1 column
const COL_PITCH := 52.0
const ICON := 16.0
const ROW_Y: Array[float] = [140.0, 160.0, 180.0]        ## icon-row centres, one per medal
const SUMMARY_Y := 96.0
const HEAD_Y := 116.0
const PAR_Y := 126.0
const RULE_Y := 193.0
const RANK_LABEL_Y := 208.0
const RANK_GRADE_Y := 229.0
const RANK_REACH_Y := 243.0
const LEGEND_Y := 258.0
const NOTE_Y := 268.0
const RANK_X0 := 112.0
const RANK_PITCH := 90.0


static func sector_col_x(sector: int) -> float:
	return COL0_X + float(sector - 1) * COL_PITCH


static func icon_rect(sector: int, medal_idx: int) -> Rect2:
	return Rect2(sector_col_x(sector) - ICON / 2.0, ROW_Y[medal_idx] - ICON / 2.0, ICON, ICON)


static func rank_cell_x(mode_idx: int) -> float:
	return RANK_X0 + float(mode_idx) * RANK_PITCH
