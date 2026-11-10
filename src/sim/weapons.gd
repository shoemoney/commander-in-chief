class_name Weapons
extends RefCounted
## Special-weapon table, keyed by p["weapon"] (0 = the MG, the default).
##
## Pure data + pure geometry: no state, no rng, no floats. Plain const Dictionaries
## rather than .tres Resources on purpose — the sim must not touch the ResourceLoader
## (a resource read is I/O, and a hand-edited .tres could silently fork the goldens).
##
## Rules in one place (the view reads the SAME numbers, so what is drawn is what hits):
##  * A pickup REPLACES the held special and refills it; it is held until death or until
##    its own magazine (wpn_ammo) runs dry, then the player falls back to the MG.
##  * MG mods (pierce / trench / triple / rend) belong to the MG: they keep ticking but are
##    dormant while a special is in hand, and wake up when it runs out.
##  * Always-fire has no trigger, so a special only fires when it has something to hit
##    (flame: a non-armored hostile in the cone; rocket: a target in its lane). It never
##    burns its magazine on an empty field.

const F := Fixed.ONE

const NONE := 0
const FLAME := 1
const ROCKET := 2

## Supply (pickup) kinds, continuing the existing grammar (4..10 capsules, 11 sandbag).
const KIND_FLAME := 12
const KIND_ROCKET := 13

const TABLE := {
	FLAME: {
		"kind": KIND_FLAME,
		"cd": 4,                   # ticks between bursts (MG: 8)
		"grant": 90,               # pickup refill, in bursts (6 s of continuous fire)
		"cap": 99,
		"reach": 70 * F,           # cone length, px
		"tan": 30802,              # tan(25.2 deg) in 16.16: the cone half-width per px of length
		"pad": 6 * F,              # body radius added to the cone test
		"cover_hits": 6,           # bursts to burn through a sandbag (24 ticks)
		"min_sector": 1,           # 0-based sector index: campaign sector 2
		"shop": 80,                # Endless crate base price
	},
	ROCKET: {
		"kind": KIND_ROCKET,
		"cd": 36,                  # 0.6 s between rockets (MG: 7.5 rounds/s)
		"grant": 10,
		"cap": 14,
		"speed": 4 * F,            # px per tick (MG bullet: 6): visibly slower, you can lead and dodge-read it
		"reach": 280 * F,          # auto-trigger range = speed * ttl
		"ttl": 70,                 # 280 px of flight
		"blast": 22 * F,           # splash radius (grenade: 28 / 30 kill)
		"armor_dmg": 3,            # hp stripped per rocket: one kills a nest / technical (hp 3), a mast (hp 5) takes two
		"boss_dmg": 6,             # gunship / miniboss (MG round: 1, grenade: 8)
		"colossus_dmg": 2,         # same as a grenade
		"lane": 12 * F,            # lateral tolerance of the auto-trigger
		"min_sector": 2,           # campaign sector 3
		"shop": 90,
	},
}

## Armor the flame cannot cook: the inherent heavies. (Veteran armor on bulk infantry
## is hp > 1 too, but fire chews through it one hp per burst.)
const FLAME_IMMUNE: PackedStringArray = ["mg_nest", "technical", "broadcast"]


static func id_for_kind(kind: int) -> int:
	if kind == KIND_FLAME:
		return FLAME
	if kind == KIND_ROCKET:
		return ROCKET
	return NONE


static func in_cone(dx: int, dy: int, ax: int, ay: int, reach: int, tan_half: int, pad: int) -> bool:
	## True if the offset (dx,dy) from the muzzle lies in the cone of unit heading (ax,ay).
	var along: int = Fixed.mul(dx, ax) + Fixed.mul(dy, ay)
	if along < -pad or along > reach + pad:
		return false
	var cross: int = Fixed.mul(dx, ay) - Fixed.mul(dy, ax)
	return absi(cross) <= Fixed.mul(maxi(along, 0), tan_half) + pad


static func in_lane(dx: int, dy: int, ax: int, ay: int, reach: int, half_w: int) -> bool:
	## True if (dx,dy) is ahead of the muzzle within `reach` and within `half_w` of the aim line.
	var along: int = Fixed.mul(dx, ax) + Fixed.mul(dy, ay)
	if along < 0 or along > reach:
		return false
	var cross: int = Fixed.mul(dx, ay) - Fixed.mul(dy, ax)
	return absi(cross) <= half_w
