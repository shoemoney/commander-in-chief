class_name CuePolicy
extends RefCounted
## CUES NOT WORDS: the pure decision rules for how loudly the HUD talks.
##
## View-only and render-free (nothing here touches the sim or the checksum). The rules live in one
## static home so main.gd / sfx.gd / menu.gd carry hook lines, and so the tests can drive the
## decision without a scene tree.
##
## State is plain Dictionaries of ints keyed by short strings, persisted beside main._seen.

## CAPTIONS setting. ALL is the accessibility guarantee: the full bracketed caption, every cue,
## every time, and pickup words never retire. SMART is the compact chip (glyph plus one word); a
## cue's WORD retires after SMART_EXPOSURES showings and the glyph alone remains, and the word
## returns when the SFX bus is muted or quiet. OFF is no sound-cue captions.
enum CaptionMode { ALL, SMART, OFF }
const CAP_ALL := CaptionMode.ALL
const CAP_SMART := CaptionMode.SMART
const CAP_OFF := CaptionMode.OFF

const SMART_EXPOSURES := 3
## SFX level is stepped 0..10 (0 == muted). "Under 20% volume" is a step below 2.
const QUIET_SFX_STEP := 2

## A pickup or status word is spelled out for the first WORD_PICKUPS grabs of each kind, then it
## is an icon with a pulse ring.
const WORD_PICKUPS := 2

## Armor blocks the player has caused, never having thrown a grenade, before the armor hint
## is re-queued (once).
const ARMOR_BLOCKS_TO_REARM := 3

const KEY_CAP := "cap:"       # per-cue caption exposure counters
const KEY_PICK := "pk:"       # per-kind pickup/status counters
const KEY_ARMOR_BLOCKS := "m:armor_blocks"
const KEY_THREW := "m:grenade_thrown"
const KEY_REARMED := "m:armor_rearmed"


## A saved `captions` value to a CaptionMode. The old setting was a bool: true -> ALL, false ->
## OFF. Anything unreadable lands on ALL, the accessibility-safe side.
static func migrate_caption_mode(v: Variant) -> int:
	if typeof(v) == TYPE_BOOL:
		return CAP_ALL if v else CAP_OFF
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var i := int(v)
		if i >= CAP_ALL and i <= CAP_OFF:
			return i
	return CAP_ALL


static func next_mode(mode: int) -> int:
	return (clampi(mode, CAP_ALL, CAP_OFF) + 1) % 3


static func mode_label(mode: int) -> String:
	match mode:
		CAP_SMART: return "SMART"
		CAP_OFF: return "OFF"
	return "ALL"


## True when SMART mode has retired a cue's WORD (glyph alone remains; the cue itself is never
## hidden). `count` is the exposures INCLUDING the one being drawn, so the word is spelled for
## exposures 1..SMART_EXPOSURES and retires from the next. The player who has muted or nearly
## muted the SFX bus cannot hear the cue, so for them the word always comes back.
static func word_retired(count: int, sfx_step: int) -> bool:
	if count <= SMART_EXPOSURES:
		return false
	return sfx_step >= QUIET_SFX_STEP


## The three modes, as the HUD resolves one cue's presentation. "full" is the whole bracketed
## caption at the full caption size (ALL, or any mode under an enlarged TEXT SIZE: a player who
## asked for bigger text asked for text); "chip" is glyph plus one word; "glyph" is the glyph
## alone; "none" is OFF. A lethal cue is never "none" outside OFF.
static func caption_form(mode: int, count: int, sfx_step: int, text_scale: float) -> String:
	if mode == CAP_OFF:
		return "none"
	if mode == CAP_ALL or text_scale > 1.001:
		return "full"
	return "glyph" if word_retired(count, sfx_step) else "chip"


## Does this pickup/status grab still spell its word? ALL always does; so does any mode under an
## enlarged TEXT SIZE. Otherwise only the first WORD_PICKUPS grabs of each kind.
static func pickup_word(mode: int, prior_pickups: int, text_scale: float) -> bool:
	if mode == CAP_ALL or text_scale > 1.001:
		return true
	return show_word(prior_pickups)


static func caption_allowed(mode: int) -> bool:
	return mode != CAP_OFF


static func bump(counts: Dictionary, key: String) -> int:
	var n := int(counts.get(key, 0)) + 1
	counts[key] = n
	return n


static func count_of(counts: Dictionary, key: String) -> int:
	return int(counts.get(key, 0))


## Pickups of `kind_key` already collected -> does this one still get its word?
static func show_word(prior_pickups: int) -> bool:
	return prior_pickups < WORD_PICKUPS


## The armor/grenade mastery re-arm: fires once, only for a player who keeps bouncing rounds off
## armor and has never thrown a grenade.
static func rearm_due(counts: Dictionary) -> bool:
	if count_of(counts, KEY_REARMED) > 0 or count_of(counts, KEY_THREW) > 0:
		return false
	return count_of(counts, KEY_ARMOR_BLOCKS) >= ARMOR_BLOCKS_TO_REARM


## Where the flank chevron sits and which way it points. A breach whose screen position is off the
## frame pins to the nearest margin of the 640x360 viewport and points along the line from the
## screen centre to the breach; an on-screen breach is marked in place, pointing down at it.
const EDGE_INSET := 10.0
const VIEW_W := 640.0
const VIEW_H := 360.0

static func edge_chevron(screen_pos: Vector2) -> Dictionary:
	var lo := Vector2(EDGE_INSET, EDGE_INSET)
	var hi := Vector2(VIEW_W - EDGE_INSET, VIEW_H - EDGE_INSET)
	var clamped := Vector2(clampf(screen_pos.x, lo.x, hi.x), clampf(screen_pos.y, lo.y, hi.y))
	if clamped.is_equal_approx(screen_pos):
		return {"pos": screen_pos, "angle": PI / 2.0}
	return {"pos": clamped, "angle": (screen_pos - Vector2(VIEW_W, VIEW_H) / 2.0).angle()}
