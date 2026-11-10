class_name FrontDoor
extends RefCounted
## Title-screen "front door" state and pure rules: first-boot intro flag, furthest sector
## reached (unlocks the CHAPTER SELECT row), and the Daily Run streak / score / countdown.
## VIEW-ONLY: wall-clock is read here (never in src/sim) and none of this feeds the checksum.
## Persisted by Main in the existing save file under [front]; the rules are static + pure so
## tests drive them with explicit day numbers instead of the real clock.

const SPLASH_SHORT := 3.0          # repeat boots: the studio card only
const CHAPTER_UNLOCK_SECTOR := 2   # reaching sector 2+ once surfaces CHAPTER SELECT on the title
const DAY_SECONDS := 86400

## Test seam: when >= 0 it replaces the system clock (local unix seconds).
static var clock_override := -1

var intro_seen := false
var max_sector := 1
var streak := 0
var streak_day := -1       # day ordinal the streak last advanced on
var daily_day := -1        # day ordinal of the banked daily score
var daily_score := -1
var daily_grade := ""


static func local_unix() -> int:
	if clock_override >= 0:
		return clock_override
	return int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system()))


static func day_ordinal(unix_local: int) -> int:
	return unix_local / DAY_SECONDS


static func today() -> int:
	return day_ordinal(local_unix())


static func seconds_to_next_board(unix_local: int) -> int:
	return DAY_SECONDS - (unix_local % DAY_SECONDS)


static func splash_length(seen: bool, full: float) -> float:
	return SPLASH_SHORT if seen else full


static func chapters_unlocked(sector: int) -> bool:
	return sector >= CHAPTER_UNLOCK_SECTOR


## Streak value after a daily is DEALT on `today_d`: same day keeps, consecutive day grows,
## any gap restarts at 1.
static func streak_after_play(last_day: int, cur: int, today_d: int) -> int:
	if last_day == today_d:
		return maxi(cur, 1)
	if last_day == today_d - 1:
		return cur + 1
	return 1


## Streak to DISPLAY: a streak whose last play is older than yesterday is already broken.
static func live_streak(last_day: int, cur: int, today_d: int) -> int:
	return cur if (cur > 0 and last_day >= today_d - 1) else 0


static func countdown_text(secs: int) -> String:
	var s := maxi(secs, 0)
	return "%dH%02dM" % [s / 3600, (s % 3600) / 60]


static func score_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## Right-aligned badge for the DAILY RUN row. Locked: today's score (+grade) and the countdown
## to the next board. Open: nothing (the streak rides the row label as streak_chip).
func daily_badge(locked: bool, unix_local: int) -> String:
	var d := day_ordinal(unix_local)
	if locked:
		var parts: Array[String] = []
		if daily_day == d and daily_score >= 0:
			parts.append(score_text(daily_score) + (" " + daily_grade if daily_grade != "" else ""))
		else:
			parts.append("COMPLETED")
		parts.append(countdown_text(seconds_to_next_board(unix_local)))
		return "  ".join(parts)
	return ""


## Label suffix shown on the locked row's streak chip.
func streak_chip(unix_local: int) -> String:
	var st := live_streak(streak_day, streak, day_ordinal(unix_local))
	return "x%d" % st if st > 0 else ""


func note_daily_dealt(today_d: int) -> void:
	streak = streak_after_play(streak_day, streak, today_d)
	streak_day = today_d


func note_daily_score(today_d: int, score: int, grade: String) -> void:
	daily_day = today_d
	daily_score = score
	daily_grade = grade


func note_sector(sector: int) -> bool:
	if sector > max_sector:
		max_sector = sector
		return true
	return false


func to_section() -> Dictionary:
	return {"intro_seen": intro_seen, "max_sector": max_sector, "streak": streak,
		"streak_day": streak_day, "daily_day": daily_day, "daily_score": daily_score,
		"daily_grade": daily_grade}


static func _i(cf: ConfigFile, key: String, def: int) -> int:
	var v: Variant = cf.get_value("front", key, def)
	return int(v) if (v is int or v is float) else def


func load_from(cf: ConfigFile) -> void:
	var seen: Variant = cf.get_value("front", "intro_seen", false)
	intro_seen = seen if seen is bool else false
	max_sector = maxi(_i(cf, "max_sector", 1), 1)
	streak = maxi(_i(cf, "streak", 0), 0)
	streak_day = _i(cf, "streak_day", -1)
	daily_day = _i(cf, "daily_day", -1)
	daily_score = _i(cf, "daily_score", -1)
	var g: Variant = cf.get_value("front", "daily_grade", "")
	daily_grade = g if g is String else ""
