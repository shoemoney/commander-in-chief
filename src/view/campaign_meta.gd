class_name CampaignMeta
extends RefCounted
## retry-meta: the view-side rules for Campaign progression. Pure statics, no sim edits:
## Veteran Point payout per mode, which modes get purchased perks, the RETRY SECTOR
## offer on the defeat card, and the honesty tag a perk-boosted run carries to the boards.

const VP_PER_SECTOR := 2    ## per sector reached (sector 1 counts): a sector-4 death banks 8
const VP_WIN_BONUS := 10    ## on top for a clear: a full run is 6 x 2 + 10 = 22
const RETRY_KEY := KEY_T
const RETRY_PAD_BUTTON := JOY_BUTTON_Y
const NEW_CAMPAIGN_KEY := KEY_N                 ## on a retried-arcade debrief: back to a fresh ranked CAMPAIGN
const NEW_CAMPAIGN_PAD_BUTTON := JOY_BUTTON_X
const VET_TAG := "vet"                         ## earned-progression run tag; never conflated with the ASSIST accessibility tags


## Sector the run is in / died in: gates opened + 1, capped at the final sector.
static func sector_reached(opened: int) -> int:
	return mini(opened + 1, SimWorld.FINAL_GATE_INDEX)


static func opened_gates(sim: SimWorld) -> int:
	var opened := 0
	for g in sim.gates:
		if g["open"]:
			opened += 1
	return opened


## VP a verified run banks. Endless keeps its 1-per-wave rule; Campaign pays per sector plus
## a win bonus. The daily (a shared comparable seed), the unranked Arcade retry and Boss
## Rush bank nothing, so a sector can never be farmed.
static func vp_for_run(mode: String, wave: int, sector: int, won: bool, daily: bool) -> int:
	if mode == "endless":
		return wave
	if mode == "campaign" and not daily:
		return sector * VP_PER_SECTOR + (VP_WIN_BONUS if won else 0)
	return 0


## Purchased perks start Endless (as before, no switch), Campaign and Arcade runs (only while the
## persisted VET PERKS setting is ON). Never the daily.
static func perks_apply(mode: String, daily: bool, vet_on := true) -> bool:
	if daily:
		return false
	if mode == "endless":
		return true
	return vet_on and (mode == "campaign" or mode == "arcade")


## Only a lost, ranked Campaign run past sector 1 offers a retry (at sector 1 REDEPLOY is it).
static func retry_sector(mode: String, victory: bool, daily: bool, sector: int) -> int:
	if mode != "campaign" or victory or daily or sector < 2:
		return 0
	return sector


static func retry_row(sector: int, pad_label: String, use_pad: bool, pulse: float) -> Dictionary:
	var keycap := pad_label if use_pad else OS.get_keycode_string(RETRY_KEY)
	return {"text": "[%s] RETRY SECTOR %d  (UNRANKED, NO VP)" % [keycap, sector],
		"color": Color(0.75, 0.9, 1.0, pulse)}


static func vp_row(total: int, gain: int, maxed: bool) -> Dictionary:
	var txt := "%d VP BANKED  (+%d)" % [total, gain] if gain > 0 else "%d VP BANKED" % total
	if maxed:
		txt = "%d VP BANKED  —  ALL PERKS MASTERED" % total
	return {"text": txt, "color": Art.safe(Color(0.7, 0.95, 0.6)), "icon": "mi_trophy", "icon_size": 14.0}


## Steam / board routing tags. A perk-boosted Campaign/Arcade start is a modified start, so it
## still carries the start-loadout "vest" bit that lands it off the clean (unassisted) board,
## exactly as before. This is the routing key only; the player-facing label is *VET (run_tags).
## Endless keeps its precedent (perks, unassisted).
static func board_tags(tags: Array, perked: bool) -> Array[String]:
	var out: Array[String] = []
	for t in tags:
		out.append(String(t))
	if perked and "vest" not in out:
		out.append("vest")
	return out


## Player-facing run tags: the genuine assist tags, plus "vet" for a perked run. ASSIST is an
## accessibility aid and never claims earned progression.
static func run_tags(assist_tags: Array, perked: bool) -> Array[String]:
	var out: Array[String] = []
	for t in assist_tags:
		out.append(String(t))
	if perked and VET_TAG not in out:
		out.append(VET_TAG)
	return out


## Hall cell suffix for a banked run. `short` is the abbreviated form used when the row is tight.
static func hall_tags(run: Dictionary, short: bool) -> String:
	var tag := ""
	if run.get("daily", false):
		tag += "  *D" if short else "  *DAILY"
	if run.get("assist", false):
		tag += "  *A" if short else "  *ASSIST"
	if run.get("vet", false):
		tag += "  *V" if short else "  *VET"
	if run.get("hard", false):
		tag += "  *H" if short else "  *HARD"
	return tag


static func vet_row() -> Dictionary:
	return {"text": "*VET RUN  (PERKS ON, OFF THE CLEAN BOARD)", "color": Color(0.85, 0.8, 1.0)}


## A retried arcade run's way back to the ranked game.
static func new_campaign_row(pad_label: String, use_pad: bool) -> Dictionary:
	var keycap := pad_label if use_pad else OS.get_keycode_string(NEW_CAMPAIGN_KEY)
	return {"text": "[%s] NEW RANKED CAMPAIGN  (FROM SECTOR 1)" % keycap, "color": Color(0.7, 0.95, 0.6)}


## What ENTER / START does on the defeat card. A retried arcade run says so plainly.
static func redeploy_text(retry_sector_k: int) -> String:
	if retry_sector_k > 0:
		return "REDEPLOY  (SECTOR %d, UNRANKED)" % retry_sector_k
	return "REDEPLOY"
