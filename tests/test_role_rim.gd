extends RefCounted
## RATCHET for the a3-33 role-coded hostile contour.
##
## WHY THIS FILE EXISTS. The a3-33 change claimed "nine roles read as nine
## roles" and shipped on the strength of three checks, all of which passed
## forever:
##
##   1. it PARSES;
##   2. the suite is GREEN;
##   3. the contours RENDER.
##
## None of those can see a colour that is never applied, and none of them can
## see two colours 2.8 degrees apart. Both defects were live and shipped:
##
##   - FOUR ROWS WERE DEAD CODE. sapper / ghillie / frogman / m_bombsuit are
##     absent from Art.OUTLINE (art.gd:779-794), and the role hue was applied
##     from INSIDE `if Art.outlined(...)`. Two of the roles the change existed
##     to tell apart — the sniper and the sapper — could never differ on screen.
##     `elite` was a FIFTH dead row: the elite draws as `enemy_assault`, so
##     "elite" was never a style_key at all.
##   - THE HUES DID NOT SEPARATE. Worst pair rusher(36.0) vs enemy_assault(33.2)
##     = 2.8 degrees, on a 2.2px rim around an 18px sprite at 640x360. Three
##     exact duplicates too, one of them (m_pilot == enemy_sniper) between two
##     sprites GUARANTEED to co-occur: a pilot outlives the wave that spawned it
##     (sim_world.gd:6571-6577).
##
## A measurement that cannot fail is a machine that produces confident
## sentences. tools/role_sheet.gd is the pixel-level probe for the RENDERED
## result; this file is the static invariant that says a row cannot move without
## someone reading why. Both were needed: the probe missed the dead code because
## it measures what is drawn, not what is configured.
##
## The structural ratchet is the important one. Every assertion here is
## computable from the source, so it runs in the headless suite on every CI
## machine and costs no GL context.

const Runner := preload("res://tests/run_tests.gd")

const HERO_COOL := Color(0.72, 0.93, 1.0)      # HERO_LIGHT_RIM_COL — cool = you
const GENERIC_WARM := Color(1.0, 0.9, 0.62)    # _ROLE_RIM_DEFAULT — role unknown
const LETHAL_RED := 0.0                        # hue, degrees — the bullet colour

# The floor. A 2.2px rim on an 18px sprite at 640x360 has to survive the
# downscale and a player glancing at a moving screen; below ~25 degrees two
# contours converge to the same colour at that size. Measured floor for the
# shipped palette is 34; 25 is the margin, not the ambition.
const MIN_SEPARATION_DEG := 25.0
# Every role hue must stay this far from the reserved red and from the hero's
# own cool contour. A role rim at 195 reads as "you"; one near 0 reads as a
# round coming at you.
const MIN_FROM_RED_DEG := 25.0
const MIN_FROM_HERO_DEG := 25.0

# The rusher family's four cosmetic skins. main.gd:63 `_RUSHER_SKINS` picks one
# by POSITION HASH — sim_world.gd:4725 `e["skin"] = (x/F_ONE + y/F_ONE) & 3` —
# so they are one archetype wearing four outfits. They MUST share a hue: a
# difference here would encode information the game does not have, and it costs
# two slots that real roles need.
const RUSHER_FAMILY := ["rusher", "enemy_smg", "enemy_assault", "enemy_shotgun", "enemy_lmg"]

# Rows deliberately ABSENT from the table, each with the fact that earns it.
# A hue for either of these could never be drawn, so listing one would be a
# claim the code cannot honour — which is the defect this file exists to catch.
const EXCLUDED_ON_PURPOSE := {
	"frogman": "sol-12 keeps the diver out of _LIGHT_RIM so a warm-light HOSTILE "
		+ "separator does not read as land infantry (test_assets.gd:1368, :1484); "
		+ "its read is the cool wet-threat tint plus submerged ripples",
	"elite": "never a style_key — the elite draws as enemy_assault "
		+ "(main.gd:11821), and its distinct signal is the a3-12 pulsing aura",
}

# The ONLY groups permitted to wear an identical hue, each with its reason.
# Anything else matching is a failure naming the two roles — see
# test_only_documented_roles_may_share_a_hue.
const DOCUMENTED_SHARES := [
	# One archetype, four cosmetic skins. sim_world.gd:4725 picks the skin by
	# POSITION HASH (`e["skin"] = (x/F_ONE + y/F_ONE) & 3`), so a hue difference
	# between them would encode a distinction the game does not have.
	["rusher", "enemy_smg", "enemy_assault", "enemy_shotgun", "enemy_lmg"],
	# Co-present BY DESIGN and told apart by something other than the rim: a pilot
	# is a rescue objective that outlives the wave that spawned it
	# (sim_world.gd:6571-6577), carries the non-hostile marker, and giving it its
	# own hue spent a slot a real role needed.
	["enemy_sniper", "m_pilot"],
]


func _consts() -> Dictionary:
	var ms: Script = load("res://src/main.gd")
	return ms.get_script_constant_map()


static func hue_deg(c: Color) -> float:
	# HSV hue in degrees. A near-grey colour has no meaningful hue, and reporting
	# one anyway is how a washed-out row sneaks past a hue test — so those are
	# reported as -1 and every separation check refuses them.
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	var mn: float = minf(c.r, minf(c.g, c.b))
	var d: float = mx - mn
	if d < 0.04:
		return -1.0
	var h: float
	if mx == c.r:
		h = fposmod((c.g - c.b) / d, 6.0)
	elif mx == c.g:
		h = (c.b - c.r) / d + 2.0
	else:
		h = (c.r - c.g) / d + 4.0
	return h * 60.0


static func sat(c: Color) -> float:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	var mn: float = minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


static func hue_gap(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 360.0 - d)


# --- 1. reachability: the defect that shipped ---------------------------

func test_every_role_rim_row_can_actually_be_applied() -> void:
	# THE STRUCTURAL RATCHET. The role hue is drawn by a block gated on
	# `with_rim and _LIGHT_RIM.has(style_key)` — deliberately NOT on
	# Art.outlined(), which is the fix. A row in _ROLE_RIM that is not also in
	# _LIGHT_RIM is therefore unreachable, which is exactly how four rows sat
	# dead for the life of the change without a single red test.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var light: Dictionary = c["_LIGHT_RIM"]
	var unreachable: Array = []
	for k in roles:
		if not light.has(k):
			unreachable.append(k)
	Runner.T.eq(unreachable.size(), 0,
		"every _ROLE_RIM row is also a _LIGHT_RIM member, so none can be dead code"
		+ (" (unreachable: %s)" % str(unreachable) if unreachable.size() > 0 else ""))


func test_no_role_rim_row_is_a_dead_style_key() -> void:
	# `elite` was a row in the first version of this table and was NEVER a
	# style_key: the elite draws as `enemy_assault` (main.gd:11821), so the
	# "orchid" entry could not execute. The general form of the bug is "a row
	# naming something the draw path never passes", so pin the drawn set.
	var drawn := {
		"rusher": true, "enemy_smg": true, "enemy_assault": true,
		"enemy_shotgun": true, "enemy_lmg": true, "sapper": true,
		"ghillie": true, "courier": true, "frogman": true,
		"m_soldier2": true, "m_bombsuit": true, "m_pilot": true,
		"enemy_sniper": true,
	}
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var phantom: Array = []
	for k in roles:
		if not drawn.has(k):
			phantom.append(k)
	Runner.T.eq(phantom.size(), 0,
		"no _ROLE_RIM row names a style_key the draw path never emits"
		+ (" (phantom: %s)" % str(phantom) if phantom.size() > 0 else ""))


# --- 2. THE DRAW PATH. A table-only ratchet is vacuous here. ------------
#
# Everything above reads CONFIGURATION. The defect this file exists for was a
# configuration row that the draw path could never apply, so a test that stops
# at the table cannot see it — and that is not hypothetical: with the entire
# role-rim draw call deleted, every table assertion in section 1 still passed.
# These three call the SAME function _spr_texture calls, so they fail when the
# draw path is re-gated.

func test_draw_path_paints_a_role_contour_for_a_self_keylined_hostile() -> void:
	# THE PLANTED CASE. `ghillie` and `sapper` are absent from Art.OUTLINE
	# (art.gd:794, sie-01: they bake their own black keyline). Under the original
	# nesting they therefore got NO contour at all — the a3-33 change was inert
	# for exactly the two roles the reviewer said you could not tell apart.
	var ms: Script = load("res://src/main.gd")
	for k in ["ghillie", "sapper"]:
		var col: Color = ms.role_rim_color(k)
		Runner.T.ok(col.a > 0.0,
			"'%s' — self-keylined, absent from Art.OUTLINE — still gets a painted contour" % k)
		if col.a > 0.0:
			Runner.T.eq(col, ms.get_script_constant_map()["_ROLE_RIM"][k],
				"'%s' is painted in its own declared role hue, not the generic default" % k)


func test_draw_path_is_not_gated_on_art_outline() -> void:
	# The gate must not depend on Art.OUTLINE membership. If a role key is ever
	# OUTLINE-less and unlit, that is the original defect returning.
	var ms: Script = load("res://src/main.gd")
	var art: Script = load("res://src/view/art.gd")
	var roles: Dictionary = ms.get_script_constant_map()["_ROLE_RIM"]
	for k in roles:
		Runner.T.ok(ms.role_rim_color(k).a > 0.0,
			"'%s' is painted regardless of Art.OUTLINE (in OUTLINE: %s)"
			% [k, str(art.OUTLINE.has(k))])


func test_draw_path_refuses_a_key_that_never_asked_for_a_contour() -> void:
	# The other direction, and the reason the gate is _LIGHT_RIM and not
	# _ROLE_RIM: a sprite that is not a light-rimmed hostile must get NOTHING,
	# not the generic separator. Getting this wrong is what would have put a
	# hostile contour on the diver and broken the two sol-12 pins.
	var ms: Script = load("res://src/main.gd")
	for k in ["frogman", "player1", "observer", "rock1", "barrel", "wreck"]:
		var col: Color = ms.role_rim_color(k)
		Runner.T.eq(col.a, 0.0, "'%s' wears no role contour (diver pinned by sol-12)" % k)


# --- 3. the rusher family must not lie about its own variety -------------

func test_rusher_family_shares_one_hue() -> void:
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var base: Color = roles["rusher"]
	var divergent: Array = []
	for k in RUSHER_FAMILY:
		if k != "rusher" and (roles[k] as Color) != base:
			divergent.append(k)
	Runner.T.eq(divergent.size(), 0,
		"the four cosmetic rusher skins share ONE hue — a skin is chosen by a "
		+ "position hash (sim_world.gd:4725), so a hue difference would encode "
		+ "a distinction the game does not have"
		+ (" (divergent: %s)" % str(divergent) if divergent.size() > 0 else ""))


# --- 3. separation: the defect that made the palette decorative ----------

func test_only_documented_roles_may_share_a_hue() -> void:
	# THE HOLE THIS FILE HAD, found by planting the shipped defect.
	#
	# test_role_hues_are_pairwise_distinguishable builds a dict KEYED BY HUE and
	# then compares only DISTINCT keys — so two roles on the SAME hue merge into
	# one entry and are never compared. Planting `sapper` = the sniper's violet
	# (a 0-degree gap, the exact shape of the three exact duplicates the palette
	# shipped with) left the whole suite GREEN. A separation test that cannot see
	# an identical pair is blind to the most severe case there is.
	#
	# So shares are enumerated EXPLICITLY and matched against the two documented
	# reasons. Anything else sharing a hue is a named failure.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var groups := {}
	for k in roles:
		var col: Color = roles[k]
		var key := "%.3f/%.3f/%.3f" % [col.r, col.g, col.b]
		if groups.has(key):
			groups[key].append(k)
		else:
			groups[key] = [k]
	for key in groups:
		var group: Array = groups[key]
		if group.size() < 2:
			continue
		var excused := false
		for ok in DOCUMENTED_SHARES:
			if group.size() == ok.size():
				var same := true
				for k in group:
					if not (k in ok):
						same = false
				if same:
					excused = true
		Runner.T.ok(excused,
			"'%s' share one hue — documented" % ", ".join(group)
			if excused else "UNDOCUMENTED HUE SHARE: %s are identical (%s), and nothing "
				% [", ".join(group), str(key)]
				+ "explains why two real roles would be indistinguishable")


func test_role_hues_are_pairwise_distinguishable() -> void:
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	# Distinct HUES, so the four rusher skins — which deliberately share one —
	# do not each contribute a self-comparison of 0.
	var hues := {}
	for k in roles:
		var col: Color = roles[k]
		var h: float = hue_deg(col)
		Runner.T.ok(h >= 0.0, "'%s' has a real hue (not a washed-out grey)" % k)
		if h < 0.0:
			continue
		if hues.has(h):
			hues[h].append(k)
		else:
			hues[h] = [k]
	var keys: Array = hues.keys()
	var worst: float = 999.0
	var worst_pair := ""
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var gap: float = hue_gap(keys[i], keys[j])
			if gap < worst:
				worst = gap
				worst_pair = "%s / %s" % [str(hues[keys[i]]), str(hues[keys[j]])]
	Runner.T.ok(worst >= MIN_SEPARATION_DEG,
		"every two role hues are >= %.0f deg apart (worst %.1f deg at %s); a 2.2px rim "
		% [MIN_SEPARATION_DEG, worst, worst_pair]
		+ "on an 18px sprite cannot carry less — the shipped palette's worst pair was 2.8")


func test_excluded_rows_stay_excluded() -> void:
	# The inverse of the dead-code ratchet, and the reason the table is honest
	# rather than merely small. Each of these is a real drawable hostile, so it
	# is a tempting place to add a hue — and adding one is exactly what the first
	# version of this table did, shipping a claim the gate made unreachable.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var light: Dictionary = c["_LIGHT_RIM"]
	for k in EXCLUDED_ON_PURPOSE:
		Runner.T.ok(not roles.has(k),
			"'%s' is NOT given a role hue it cannot draw (%s)" % [k, EXCLUDED_ON_PURPOSE[k]])
		# And the exclusion is the ONLY reason — if the gate ever opens to it,
		# this fails so the table is revisited deliberately rather than by accident.
		if k == "frogman":
			Runner.T.ok(not light.has(k),
				"the diver stays out of _LIGHT_RIM, which is why it has no contour")


# --- 4. the reserved colours --------------------------------------------

func test_role_hues_avoid_lethal_red() -> void:
	# main.gd:7784 — red is this game's lethal-projectile colour (a3-28), so a
	# red enemy contour collides with a round coming at you. Enforced, not
	# commented.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	for k in roles:
		var h: float = hue_deg(roles[k] as Color)
		if h < 0.0:
			continue
		var gap: float = hue_gap(h, LETHAL_RED)
		Runner.T.ok(gap >= MIN_FROM_RED_DEG,
			"'%s' stays >= %.0f deg clear of the lethal red (%.1f deg)"
			% [k, MIN_FROM_RED_DEG, gap])


func test_role_hues_avoid_the_hero_cool_contour() -> void:
	# Cool = you (main.gd:7749). A hostile wearing the hero's own contour hue is
	# worse than one wearing no contour at all.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var hero_h: float = hue_deg(HERO_COOL)
	for k in roles:
		var h: float = hue_deg(roles[k] as Color)
		if h < 0.0:
			continue
		var gap: float = hue_gap(h, hero_h)
		Runner.T.ok(gap >= MIN_FROM_HERO_DEG,
			"'%s' stays >= %.0f deg clear of the hero's cool contour (%.1f deg)"
			% [k, MIN_FROM_HERO_DEG, gap])


func test_role_hues_are_more_saturated_than_the_generic_separator() -> void:
	# The one margin hue alone cannot carry: rusher-family sits ~14 deg from the
	# generic warm separator. The SATURATION gap is what separates them — every
	# role is 0.80, the generic default is 0.38 — so "a hostile I have no name
	# for" reads flatter and dimmer than "a role I can act on". If a role row is
	# ever desaturated toward the default, this catches it.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	var gen_sat: float = sat(GENERIC_WARM)
	for k in roles:
		var s: float = sat(roles[k] as Color)
		Runner.T.ok(s >= gen_sat + 0.25,
			"'%s' is at least 0.25 more saturated than the generic separator "
			% k
			+ "(%.2f vs %.2f), so the two never read as the same colour"
			% [s, gen_sat])


# --- 5. the table still does its job -------------------------------------

func test_role_rim_covers_every_light_rimmed_hostile() -> void:
	# An unlisted kind falls back to the generic warm separator, which is correct
	# and safe. This only asserts the table is POPULATED — the point of a3-33 was
	# that the roles which need naming have names.
	var c := _consts()
	var roles: Dictionary = c["_ROLE_RIM"]
	Runner.T.ok(roles.size() >= 12, "the role table is populated (%d rows)" % roles.size())
	# Every _LIGHT_RIM hostile EXCEPT the deliberately-excluded diver must have a
	# named hue — that is the completeness half of the ratchet. The reachability
	# half (no row can be dead) is test_every_role_rim_row_can_actually_be_applied,
	# and between them a row cannot appear or vanish without a red test.
	var light: Dictionary = c["_LIGHT_RIM"]
	var unnamed: Array = []
	for k in light:
		if k == "frogman" or k == "frogman_speargun":
			continue   # sol-12, pinned above
		if not roles.has(k):
			unnamed.append(k)
	Runner.T.eq(unnamed.size(), 0,
		"every light-rimmed hostile except the diver has a named contour hue"
		+ (" (unnamed: %s)" % str(unnamed) if unnamed.size() > 0 else ""))
	for k in ["rusher", "enemy_sniper", "sapper", "ghillie", "courier",
			"m_soldier2", "m_bombsuit", "m_pilot", "enemy_smg", "enemy_assault",
			"enemy_shotgun", "enemy_lmg"]:
		Runner.T.ok(roles.has(k), "'%s' has a named contour hue" % k)