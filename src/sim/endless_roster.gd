class_name EndlessRoster
extends RefCounted
## Endless War's tiered roster and miniboss identities. Pure integer functions of
## (wave, roll, tier): no state, no RNG, no scene tree, so there is nothing new to
## hash and lint_sim stays clean.
##
## THE ROSTER USED TO BE FULLY REVEALED BY WAVE 7: from wave 3 every elite roll could
## land on any of seven archetypes, so the player met the whole cast in the first two
## minutes and nothing new ever appeared. Now each archetype DEBUTS on its own wave,
## once, as a single unit on a fixed spawn slot (the view's first-sight card names it),
## and only joins the rotation from the wave after.
##
## ORDER (by what each one teaches):
##   3 grenadier  - run TOWARD the lob          6 shield   - flank, do not plink
##   4 sniper     - break the line              7 mg_nest  - rooted guns: cover / grenade
##   5 MINIBOSS   - the first gunship           8 sapper   - mind the mine trail
##   9 ghillie    - close in on the cloak      11 drone    - tracked AoE, shoot it down
##  12 technical  - sidestep the charge        14 broadcast - kill the mast
##  10 / 15 / 20  - the next gunship opens differently (see boss_variant)
##
## Locked rolls fall back to plain elites and the
## wave carries bonus_count() extra bodies, so pressure never drops versus the old
## roster at any wave (test_endless_variety pins threat_new >= threat_old per wave).

const DEBUT := {
	"grenadier": 3, "sniper": 4, "shield": 6, "mg_nest": 7, "sapper": 8,
	"ghillie": 9, "drone": 11, "technical": 12, "broadcast": 14,
}
## Elite roll -> archetype, the order the spawner has always used.
const ROLL_KIND := ["grenadier", "sniper", "shield", "sapper", "ghillie", "drone",
	"mg_nest", "technical", "broadcast", "elite"]
## Static pressure proxy (relative, not a damage number): a rifleman 1, an elite 2,
## a ranged/area special 3, a rooted/aerial/vehicle one 4.
const THREAT := {
	"rusher": 1, "elite": 2, "grenadier": 3, "sniper": 3, "shield": 3, "sapper": 3,
	"ghillie": 4, "drone": 4, "mg_nest": 4, "technical": 4, "broadcast": 4,
}
const MAX_BONUS := 24
## c3 2v composition themes: the wave mutator -> the rolls it remaps every elite draw onto
## (the SAME draw, no extra rng) and the archetypes that make up the theme.
const THEME_MARKSMEN := 7
const THEME_BOMBARDMENT := 8
const THEME_REMAP := {
	7: [1, 4, 5, 1, 4, 5, 1, 4, 5, 4],   # sniper / ghillie / drone, even weights
	8: [0, 3, 0, 3, 0, 3, 0, 3, 0, 3],   # grenadier / sapper, 50/50
}
const THEME_MEMBERS := {
	7: ["sniper", "ghillie", "drone"],
	8: ["grenadier", "sapper"],
}


static func unlocked(kind: String, wave: int) -> bool:
	## True once `kind` is in the ROTATION (the wave AFTER its debut wave).
	return kind == "elite" or wave > int(DEBUT.get(kind, 0))


static func legacy_kind(roll: int, wave: int) -> String:
	## The pre-tiering resolution of an elite roll (kept for the before/after proxy).
	var k: String = ROLL_KIND[roll]
	if k == "drone" and wave < 5:
		return "sniper"
	if k == "broadcast" and wave < 7:
		return "elite"
	return k


static func kind_for(roll: int, wave: int) -> String:
	## Archetype an elite roll resolves to at `wave` under the tiered roster.
	var k: String = ROLL_KIND[roll]
	if unlocked(k, wave):
		return k
	# Locked: a plain elite. Falling back to the already-debuted specials was tried and
	# measured worse: a scripted bot that reached wave 13-18 on the old roster died at
	# 5-10 once waves 3-8 repeated grenadiers/snipers, so the early waves stay rifle
	# pressure and the specials are only ever met as the debut or in full rotation.
	return "elite"


static func theme_of(mod_a: int, mod_b: int = 0) -> int:
	## The composition theme a wave runs (7 or 8), 0 for none. Same precedence the spawner
	## has always had: MARKSMEN is checked before BOMBARDMENT, either mutator slot counts.
	if mod_a == THEME_MARKSMEN or mod_b == THEME_MARKSMEN:
		return THEME_MARKSMEN
	if mod_a == THEME_BOMBARDMENT or mod_b == THEME_BOMBARDMENT:
		return THEME_BOMBARDMENT
	return 0


static func themed_roll(roll: int, theme: int) -> int:
	if theme == 0:
		return roll
	return THEME_REMAP[theme][roll]


static func themed_kind(roll: int, wave: int, theme: int) -> String:
	## Archetype a THEMED elite roll resolves to. `roll` is the already-remapped roll. A theme
	## member that is still locked falls back to the NEAREST UNLOCKED member of the same theme
	## (next in the theme's own order, wrapping), and only when the whole theme is still locked
	## to a plain elite -- the theme used to dissolve into elites on every early themed wave.
	var k: String = ROLL_KIND[roll]
	if unlocked(k, wave) or theme == 0:
		return kind_for(roll, wave)
	var members: Array = THEME_MEMBERS[theme]
	var at: int = members.find(k)
	for off in range(1, members.size()):
		var cand: String = members[(at + off) % members.size()]
		if unlocked(cand, wave):
			return cand
	return "elite"


static func debut_kind(wave: int) -> String:
	for k in DEBUT:
		if DEBUT[k] == wave:
			return k
	return ""


static func debut_slot(total: int, elite_every: int) -> int:
	## The wave_pending value (post-decrement) at which the debuting archetype
	## spawns: the elite slot nearest the middle of the wave, so the player is
	## already warmed up and the unit arrives alone.
	var mid: int = maxi(total / 2, elite_every)
	return mini((mid / elite_every) * elite_every, ((total - 1) / elite_every) * elite_every)


static func elite_every(wave: int) -> int:
	return maxi(2, 4 - wave / 5)


static func base_total(wave: int) -> int:
	return SimWorld.WAVE_BASE_ENEMIES + SimWorld.WAVE_ENEMIES_PER_WAVE * (wave - 1)


static func wave_budget(wave: int, theme: int = 0) -> int:
	## Enemies a wave spawns from the trickle (bonus bodies included). Boss and
	## escorts are not counted here.
	return base_total(wave) + bonus_count(wave, theme)


static func _threat10(wave: int, total: int, tiered: bool, theme: int = 0) -> int:
	## Sum of the trickle's threat x10 (the elite roll is uniform over 10 faces). A themed
	## wave remaps every roll first; the debut slot keeps the debuting archetype.
	var every: int = elite_every(wave)
	var dk: String = debut_kind(wave) if tiered else ""
	var slot: int = debut_slot(total, every)
	var sum := 0
	for wp in range(total - 1, -1, -1):
		if wp % every != 0:
			sum += 10
		elif wave < 3:
			sum += 20
		elif tiered and dk != "" and wp == slot:
			sum += THREAT[dk] * 10
		else:
			for r in 10:
				var rr: int = themed_roll(r, theme)
				if tiered:
					sum += THREAT[themed_kind(rr, wave, theme)]
				else:
					sum += THREAT[legacy_kind(rr, wave)]
	return sum


static func threat_old(wave: int, theme: int = 0) -> int:
	return _threat10(wave, base_total(wave), false, theme)


static func threat_new(wave: int, theme: int = 0) -> int:
	return _threat10(wave, wave_budget(wave, theme), true, theme)


static func bonus_count(wave: int, theme: int = 0) -> int:
	## Extra trickle bodies that keep the tiered wave at least as heavy as the old one.
	if wave < 3:
		return 0
	var want: int = threat_old(wave, theme)
	var base: int = base_total(wave)
	for b in MAX_BONUS + 1:
		if _threat10(wave, base + b, true, theme) >= want:
			return b
	return MAX_BONUS


# --- Miniboss identities -------------------------------------------------------

const BOSS_NAMES := ["VANGUARD GUNSHIP", "BROADSIDE GUNSHIP", "WARDEN GUNSHIP", "REAPER GUNSHIP"]
## Per variant: the act the gunship OPENS in (a floor under its HP-third act) and
## how many escorts touch down with it.
const BOSS_OPEN_ACT := [1, 2, 1, 2]
const BOSS_ESCORTS := [0, 0, 2, 2]


static func boss_variant(tier: int) -> int:
	return posmod(tier - 1, BOSS_NAMES.size())


static func boss_name(tier: int) -> String:
	return BOSS_NAMES[boss_variant(tier)]


static func boss_act(tier: int, hp: int, max_hp: int) -> int:
	## The act the gunship fights in: its HP third, never below its opening act.
	var act: int = GunshipPhases.phase_of(hp, max_hp)
	if tier <= 0:
		return act
	return maxi(act, BOSS_OPEN_ACT[boss_variant(tier)])


static func boss_escorts(tier: int) -> int:
	if tier <= 0:
		return 0
	return BOSS_ESCORTS[boss_variant(tier)]
