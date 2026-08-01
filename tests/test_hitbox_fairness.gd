extends RefCounted
## HITBOX FAIRNESS — the collision-vs-silhouette ratchet.
##
## The player dies in ONE hit, so a lethal radius a few pixels wider than the
## thing it belongs to is the whole difference between "I made a mistake" and
## "this game is unfair". The sim's radii are plain numbers with no memory of
## the art, and the art is regenerated from tools/gen_*.py — so a sprite tweak
## could silently make an incoming hitbox larger than what it looks like and
## nothing in the suite would notice.
##
## This suite closes that loop. It MEASURES each sprite the way the game draws
## it — the opaque alpha bounding box of the imported texture, times the
## art.gd SCALE row, times the main.gd call-site scale — and asserts each sim
## radius against it. The house rule, and the direction every assertion points:
##
##   INCOMING lethal hitboxes must be SMALLER than they look.
##   The player's OWN weapons may be more generous than they look.
##
## Sim world units ARE screen pixels (VIEW_H 360 / SCREEN_W 640 in Fixed), so a
## radius converts with a plain / Fixed.ONE — no camera zoom in between.
##
## If a re-baked sprite moves a ratio out of band, FIX THE RATIO, don't widen
## the band: the band IS the design.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")

## Call-site spr_scale for each texture, read off src/main.gd. Kept here beside
## the assertion rather than derived, because the point of the test is to fail
## when the two drift apart.
const CALL_SCALE := {
	"player1": 0.52,        # main.gd _draw_players (alive body)
	"enemy_smg": 0.5,       # _draw_enemies, plain rusher
	"enemy_assault": 0.62,  # elite
	"frogman": 0.5,
	"m_technical": 0.55,
	"colossus_body": 1.9,
	"wep_claymore": 1.05,   # mines / claymores
	"bunker": 0.78,         # _draw_bunkers
	"courier": 0.5,         # _draw_enemies, fleeing supply runner
	"crate_ammo": 0.55,     # _draw_pickups — every pickup shares one spr_scale
	"pickup_vest": 0.55,
	"cap_pierce": 0.55,
	"cap_claymore": 0.55,
	"enemy_lmg": 0.5,       # _draw_enemies, widest rusher skin
	"enemy_sniper": 0.5,
	"m_soldier2": 0.52,     # grenadier
	"m_bombsuit": 0.55,     # shield
	"sapper": 0.5,
	"ghillie": 0.5,
	"radio_tower": 0.9,     # broadcast mast
	"mg_stand": 1.0,        # MG nest
	"m_radar_tank": 0.5,    # _draw_observer
	"tank_body": 0.62,      # _draw_tanks — the parked hull you hide behind
}


func _px(fixed_radius: int) -> float:
	return float(fixed_radius) / float(Fixed.ONE)


func _silhouette(tex_name: String) -> Vector2:
	## The drawn opaque footprint in screen px: alpha bbox x SCALE x call scale.
	## Returns Vector2.ZERO when the texture is missing so the caller can skip
	## rather than assert against a phantom (art.gd guards every lookup too).
	if not Art.TEX.has(tex_name):
		return Vector2.ZERO
	var t: Texture2D = Art.tex(tex_name)
	if t == null:
		return Vector2.ZERO
	var img := t.get_image()
	if img == null:
		return Vector2.ZERO
	var sz := img.get_size()
	var x0 := sz.x
	var y0 := sz.y
	var x1 := -1
	var y1 := -1
	for y in sz.y:
		for x in sz.x:
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Vector2.ZERO
	var s: float = float(CALL_SCALE[tex_name]) * Art.draw_scale(tex_name)
	return Vector2(float(x1 - x0 + 1) * s, float(y1 - y0 + 1) * s)


func _half(tex_name: String) -> float:
	## Mean half-extent — the single "visual radius" a circular sim hitbox is
	## fairly compared against for a roughly-square top-down sprite.
	var d := _silhouette(tex_name)
	if d == Vector2.ZERO:
		return 0.0
	return (d.x + d.y) / 4.0


func _anim_silhouette(t: Texture2D, scale: float, x_stretch := 1.0) -> Vector2:
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	var sz := img.get_size()
	var x0 := sz.x
	var y0 := sz.y
	var x1 := -1
	var y1 := -1
	for y in sz.y:
		for x in sz.x:
			if img.get_pixel(x, y).a > 0.35:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Vector2.ZERO
	return Vector2(float(x1 - x0 + 1) * scale * x_stretch,
		float(y1 - y0 + 1) * scale)


func _band(label: String, ratio: float, lo: float, hi: float) -> void:
	Runner.T.ok(ratio >= lo and ratio <= hi,
		"%s: collision is %.0f%% of the drawn silhouette (band %.0f-%.0f%%)"
			% [label, ratio * 100.0, lo * 100.0, hi * 100.0])


# --- INCOMING: must be smaller than it looks -------------------------------

func test_enemy_bullet_is_smaller_than_the_soldier_it_kills() -> void:
	# The round that one-shots you. Compared against the player's INSCRIBED
	# radius (the largest circle that fits inside the drawn body), because the
	# sim test is a circle: anything at or above 1.0 means the whole visible
	# soldier is lethal surface, which in a one-hit-kill game is the single
	# most-reported unfairness in the genre.
	var d := _silhouette("player1")
	if d == Vector2.ZERO:
		Runner.T.ok(true, "player1 texture absent — silhouette check skipped")
		return
	var inscribed := minf(d.x, d.y) / 2.0
	var r := _px(SimWorld.ENEMY_BULLET_HIT_RADIUS)
	_band("enemy bullet vs player", r / inscribed, 0.60, 0.80)
	Runner.T.ok(r < inscribed,
		"an enemy round must land visibly INSIDE the soldier, never on his outline")


func test_enemy_bullet_stays_inside_every_vulnerable_player_pose() -> void:
	# Animation used to be able to invalidate a fair static sprite: a narrow step
	# could put the same lethal circle outside the newly drawn body. Measure every
	# hittable pose with the live horizontal correction; downed is not targetable
	# and roll is invulnerable, so those intentionally different silhouettes skip.
	var ms: Dictionary = load("res://src/main.gd").get_script_constant_map()
	var x_stretch: float = ms["PLAYER_POSE_X_STRETCH"]
	var scale := float(CALL_SCALE["player1"]) * Art.draw_scale("player1")
	var r := _px(SimWorld.ENEMY_BULLET_HIT_RADIUS)
	for state in ["idle", "move_forward_0", "move_forward_1", "move_backward_0",
			"move_backward_1", "crouch", "shoot", "throw", "interact", "bash"]:
		var d := _anim_silhouette(Art.player_anim(state), scale, x_stretch)
		Runner.T.ok(d != Vector2.ZERO, "%s player pose has an opaque silhouette" % state)
		if d == Vector2.ZERO:
			continue
		var inscribed := minf(d.x, d.y) / 2.0
		Runner.T.ok(r < inscribed,
			"enemy round (%.1fpx) stays visibly inside player/%s (%.1fpx inscribed radius)"
				% [r, state, inscribed])


func test_contact_death_demands_deep_visual_overlap() -> void:
	# Body contact is checked centre-to-centre, so the honest comparison is the
	# distance at which the two SILHOUETTES touch (sum of the half-extents).
	# Arcade bias: you should already look buried in the man before it kills.
	var ph := _half("player1")
	if ph == 0.0:
		Runner.T.ok(true, "player1 texture absent — contact check skipped")
		return
	var r := _px(SimWorld.ENEMY_TOUCH_RADIUS)
	for foe in ["enemy_smg", "enemy_assault", "frogman", "m_technical"]:
		var fh := _half(foe)
		if fh == 0.0:
			continue
		_band("contact death vs %s" % foe, r / (ph + fh), 0.35, 0.60)


func test_colossus_crush_never_outgrows_its_hull() -> void:
	# The crawler's treads. 143px of drawn monster with a 26px crush ring is
	# wildly player-favourable and that is the correct direction — the ratchet
	# here only guards the other way, i.e. a future re-bake shrinking the sprite
	# under the crush radius, which would kill you outside the machine.
	var ch := _half("colossus_body")
	if ch == 0.0:
		Runner.T.ok(true, "colossus_body texture absent — crush check skipped")
		return
	var r := _px(SimWorld.COLOSSUS_CRUSH_RADIUS)
	Runner.T.ok(r < ch,
		"colossus crush (%.0fpx) must stay inside its own drawn hull (%.0fpx half-extent)" % [r, ch])
	_band("colossus crush vs hull", r / ch, 0.20, 0.75)


func test_mine_trigger_needs_the_player_standing_on_it() -> void:
	# A 9px trigger around an 8px claymore reads as generous ON THE MINE, but
	# the player's own 19px body is what actually has to reach it: at 9px of
	# centre separation the soldier is unambiguously stood on the thing.
	var ph := _half("player1")
	var mh := _half("wep_claymore")
	if ph == 0.0 or mh == 0.0:
		Runner.T.ok(true, "mine/player texture absent — trigger check skipped")
		return
	_band("mine trigger", _px(SimWorld.MINE_TRIGGER_RADIUS) / (ph + mh), 0.45, 0.80)


func test_the_bunker_wall_that_eats_rounds_is_the_wall_you_can_see() -> void:
	# The strongpoint blocks bullets BOTH ways via a hard 48x32 AABB
	# (_point_in_aabb). Its SCALE row was tuned against a 440px source, then an
	# import sweep capped the texture at 128px without re-tuning — and _spr sizes
	# off the IMPORTED texture, so the sprite silently shrank 3.44x to 14x12px
	# while the AABB stayed 48x32. That is 343% collision-to-silhouette: rounds
	# died in invisible armour most of a sprite-width off the drawn wall, which
	# is the "no visible cause" failure pointed at the player's own offense.
	# The drawn body must COVER the AABB it enforces.
	var d := _silhouette("bunker")
	if d == Vector2.ZERO:
		Runner.T.ok(true, "bunker texture absent — armour check skipped")
		return
	var aw := float(SimWorld.BUNKER_W) / float(Fixed.ONE)
	var ah := float(SimWorld.BUNKER_H) / float(Fixed.ONE)
	Runner.T.ok(d.x >= aw * 0.95,
		"drawn bunker is %.0fpx wide vs a %.0fpx blocking AABB — armour must not be invisible"
			% [d.x, aw])
	Runner.T.ok(d.y >= ah * 0.95,
		"drawn bunker is %.0fpx tall vs a %.0fpx blocking AABB" % [d.y, ah])
	Runner.T.ok(d.x <= aw * 1.6 and d.y <= ah * 1.9,
		"...and must not overhang so far that visible wall stops nothing (%.0fx%.0f drawn)"
			% [d.x, d.y])


func test_incoming_blast_radius_is_exactly_what_the_telegraph_draws() -> void:
	# main.gd _draw_telegraphs draws its ring at GRENADE_RADIUS * PX, so the
	# mortar/airstrike/grenadier kill line is truthful BY CONSTRUCTION — and
	# _resolve_strikes / _detonate_barrel must keep using that same constant.
	# The split introduced for the player's own frag must never leak into the
	# incoming side: that is the whole point of having two names.
	Runner.T.ok(SimWorld.BLAST_KILL_RADIUS > SimWorld.GRENADE_RADIUS,
		"the outgoing kill scan is the generous one")
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	Runner.T.ok(not src.is_empty(), "sim source readable")
	for lethal in ["_resolve_strikes", "_detonate_barrel"]:
		var i := src.find("func %s(" % lethal)
		Runner.T.ok(i >= 0, "%s exists" % lethal)
		var j := src.find("\nfunc ", i + 1)
		var body := src.substr(i, (len(src) if j < 0 else j) - i)
		Runner.T.ok(body.contains("_hurt_player"), "%s is a player-lethal path" % lethal)
		Runner.T.ok(not body.contains("BLAST_KILL_RADIUS"),
			"%s must stay on the honest 28px GRENADE_RADIUS the telegraph ring draws — "
			% lethal + "the widened blast is for killing ENEMIES only")


# --- OUTGOING: may be more generous than it looks ---------------------------

func test_player_bullet_is_generous_against_infantry() -> void:
	# The player's own round. Below 1.0 the bullet has to be inside the sprite
	# to count, which is the wrong bias for the weapon you aim yourself.
	var fh := _half("enemy_smg")
	if fh == 0.0:
		Runner.T.ok(true, "enemy_smg texture absent — bullet check skipped")
		return
	var r := _px(SimWorld.BULLET_HIT_RADIUS)
	Runner.T.ok(r > fh, "a player round grazing the silhouette must count as a hit")
	_band("player bullet vs fodder", r / fh, 1.00, 1.30)
	# The courier is the same infantry class and the same 10px bullet test, but its
	# SCALE was left behind by two separate re-bakes (cast2 300->256, then the
	# sie-01 specialists onto a 128px canvas). It drew 47x37px — 2.09x its own
	# hittable half-extent — so rounds visibly through the runner did nothing, on
	# the ONE enemy the game asks you to shoot before it escapes.
	var ch := _half("courier")
	if ch > 0.0:
		_band("player bullet vs courier", r / ch, 1.00, 1.30)


func _clear_field(sim: SimWorld) -> void:
	## _step_bullets scans bunkers/sandbags/tanks/rocks BEFORE the enemy loop, so a
	## probe round can die on cover for the wrong reason. Strip the field first.
	sim.enemies.clear()
	sim.bullets.clear()
	sim.rocks.clear()
	sim.bunkers.clear()
	sim.sandbags.clear()
	sim.tanks.clear()
	sim.barrels.clear()


func _edge_probe(sim: SimWorld, e: Dictionary, off_px: float) -> bool:
	## Fire one zero-velocity round off_px to the RIGHT of the body's centre and
	## report whether it registered (killed it, or chipped its armor). Zero
	## velocity is deliberate: _shield_blocks returns false when blen == 0, so the
	## shieldman's front arc cannot confound a pure reach measurement.
	var hp0: int = e.get("hp", 1)
	sim.bullets.append({"x": e["x"] + int(off_px * Fixed.ONE), "y": e["y"],
		"vx": 0, "vy": 0, "ttl": 10, "owner": 0})
	sim._step_bullets()
	return not e["alive"] or e.get("hp", 1) < hp0


func _spawn_probe_target(sim: SimWorld, kind: String) -> Dictionary:
	var x: int = 320 * Fixed.ONE
	var y: int = sim.camera_top + 200 * Fixed.ONE
	match kind:
		"rusher":
			sim._spawn_enemy(x, y, false)
		"elite":
			sim._spawn_enemy(x, y, true)
		"mg_nest":
			sim._spawn_mg_nest(x, y)
		"broadcast":
			sim._spawn_broadcast(x, y)
		"courier":
			sim.enemies.append({"x": x, "y": y, "alive": true, "elite": false,
				"kind": "courier", "fire_cd": 0, "windup": 0})
		_:
			sim._spawn_special(x, y, kind)
	var e: Dictionary = sim.enemies[sim.enemies.size() - 1]
	e["submerged"] = false   # a dug-in ghillie is bullet-proof by design, not by size
	if kind == "rusher":
		e["skin"] = 3        # enemy_lmg — the WIDEST rusher skin, so the family is pinned honestly
	return e


func test_a_round_on_the_visible_edge_of_every_enemy_counts_as_a_hit() -> void:
	# One 10px BULLET_HIT_RADIUS served every enemy kind, and four of them are
	# drawn far larger than the fodder silhouette it was tuned against: the
	# elite (11.75px half-extent), the technical (11.63), the MG nest (14.62)
	# and the broadcast mast (15.51). A round landing squarely INSIDE their own
	# drawn bodies passed straight through. Fixing this view-side is wrong —
	# an elite is DELIBERATELY drawn larger than fodder, a nest is an
	# emplacement — so the reach follows the art.
	var roster := {"rusher": "enemy_lmg", "elite": "enemy_assault",
		"sniper": "enemy_sniper", "grenadier": "m_soldier2",
		"shield": "m_bombsuit", "sapper": "sapper", "ghillie": "ghillie",
		"courier": "courier", "technical": "m_technical",
		"broadcast": "radio_tower", "mg_nest": "mg_stand"}
	for kind in roster:
		var h := _half(roster[kind])
		if h == 0.0:
			continue   # texture absent — art.gd guards its lookups too
		var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
		_clear_field(sim)
		var e := _spawn_probe_target(sim, kind)
		Runner.T.ok(_edge_probe(sim, e, h - 1.0),
			"%s: a round 1px INSIDE its own drawn silhouette (%.1fpx off centre) must register"
				% [kind, h - 1.0])
	# ...and the reach must still stop at the body. Only the four overridden
	# kinds — drone/pilot/frogman are deliberately far more generous than they
	# look and must not get swept into this ceiling.
	for kind in ["elite", "technical", "mg_nest", "broadcast"]:
		var h := _half(roster[kind])
		if h == 0.0:
			continue
		var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
		_clear_field(sim)
		var e := _spawn_probe_target(sim, kind)
		Runner.T.ok(not _edge_probe(sim, e, h * 1.45),
			"%s: a round clearly OUTSIDE the drawn body (%.1fpx off centre) still misses"
				% [kind, h * 1.45])


func test_the_spotter_dies_inside_the_reticle_the_hud_paints_on_it() -> void:
	# The worst honesty lie of the set: main.gd draws a pulsing 13-16px
	# "SILENCE THE SPOTTER" reticle on m_radar_tank, which itself draws at a
	# 13.4px half-extent — over a 10px hitbox. A round on the hull, inside the
	# game's own kill marker, did nothing.
	var h := _half("m_radar_tank")
	if h == 0.0:
		Runner.T.ok(true, "m_radar_tank texture absent — spotter check skipped")
		return
	var sim := SimWorld.new(0xC0FFEE, 1, "campaign")
	_clear_field(sim)
	sim.observer = {"x": 320 * Fixed.ONE, "strike_cd": SimWorld.OBSERVER_STRIKE_CD_TICKS,
		"spawn_cam": sim.camera_top}
	sim.bullets.append({"x": 320 * Fixed.ONE + int((h - 1.0) * Fixed.ONE),
		"y": sim.camera_top + SimWorld.OBSERVER_Y_OFFSET, "vx": 0, "vy": 0,
		"ttl": 10, "owner": 0})
	sim._step_bullets()
	Runner.T.ok(sim.observer.is_empty(),
		"a round %.1fpx off the spotter's centre — on its hull and inside its own reticle — kills it"
			% (h - 1.0))


func test_a_pickup_is_the_size_of_the_radius_that_collects_it() -> void:
	# PICKUP_RADIUS is one constant for the whole drop family — crates, the vest,
	# and the rare capsules — so every one of them has to be drawn at roughly the
	# size that constant reaches. The capsule glyphs were not: their SCALE rows
	# were eyeballed against uncapped 512/1024px sources and a later import sweep
	# capped them to 128px, so the 1-in-6 elite reward drew at THREE PIXELS inside
	# a 12px collect ring. Nothing failed — a reward you cannot see is not an
	# error, it is just a reward nobody notices. Band both ways: below 1.0 the
	# drop out-grows the ring that takes it (you stand on loot and it ignores
	# you); far above it the ring is a vacuum around an invisible speck.
	var r := _px(SimWorld.PICKUP_RADIUS)
	for drop in ["crate_ammo", "pickup_vest", "cap_pierce", "cap_claymore"]:
		var dh := _half(drop)
		if dh == 0.0:
			continue
		_band("pickup radius vs %s" % drop, r / dh, 0.90, 2.00)


func test_pilot_rescue_reaches_further_than_the_touch_that_kills() -> void:
	# The one FRIENDLY touch in the game. It shared ENEMY_TOUCH_RADIUS with the
	# lethal contact ring, so the grab was as stingy as the kill; a friendly
	# interaction is exactly where generosity belongs.
	Runner.T.ok(SimWorld.PILOT_RESCUE_RADIUS > SimWorld.ENEMY_TOUCH_RADIUS,
		"the rescue grab must out-reach the contact-kill ring, not match it")
	var ph := _half("player1")
	if ph == 0.0:
		return
	_band("pilot rescue", _px(SimWorld.PILOT_RESCUE_RADIUS) / (ph * 2.0), 0.55, 1.05)


func test_frag_reaches_the_flame_the_player_watches() -> void:
	# The drawn fireball peaks around a 33px radius (explosion frames on a 128px
	# canvas, SCALE ~0.68-0.74, ramped by _draw_fx's 0.45->0.95 spr_scale). An
	# enemy standing in visible flame surviving is the outgoing mirror of the
	# same complaint. Keep the kill scan inside that flame, not beyond it.
	var r := _px(SimWorld.BLAST_KILL_RADIUS)
	Runner.T.ok(r >= 30.0 and r <= 34.0,
		"frag kill radius %.0fpx sits inside the ~33px drawn fireball" % r)


# --- ORDER + no-invisible-damage ------------------------------------------

func test_contact_death_resolves_after_the_players_own_offense() -> void:
	# Dying to something you had already killed that tick is its own class of
	# unfairness. Pin the ORDER in step(): the contact pass must come after the
	# bullet and grenade passes (so a tie goes to the player) and before the
	# enemy step (so nothing kills you from a position that was never drawn).
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var i := src.find("func step(")
	Runner.T.ok(i >= 0, "step() found")
	var j := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (len(src) if j < 0 else j) - i)
	var bullets := body.find("_step_bullets()")
	var grenades := body.find("_step_grenades()")
	var contact := body.find("_step_contact_deaths()")
	var foes := body.find("_step_enemies()")
	Runner.T.ok(contact >= 0, "step() runs the contact-death pass")
	Runner.T.ok(contact > bullets, "contact death resolves AFTER the player's bullets")
	Runner.T.ok(contact > grenades, "contact death resolves AFTER the player's grenades")
	Runner.T.ok(contact < foes, "contact death resolves BEFORE enemies move")


func test_a_bullet_kill_on_the_touching_tick_saves_the_player() -> void:
	# The behavioural half of the order test: a rusher sitting exactly on the
	# player, with a player round already on top of it, must die WITHOUT taking
	# the player with it.
	var sim := SimWorld.new(11, 1, "campaign")
	var p := sim.players[0]
	sim.enemies.clear()
	sim.bullets.clear()
	sim._spawn_enemy(p["x"], p["y"], false)
	var e: Dictionary = sim.enemies[sim.enemies.size() - 1]
	# A round one step short of the rusher, closing on it this tick.
	sim.bullets.append({"x": p["x"], "y": p["y"] + SimWorld.BULLET_SPEED,
		"vx": 0, "vy": -SimWorld.BULLET_SPEED, "ttl": 60, "owner": 0, "pierce": 0})
	sim.step([SimInput.new()])
	Runner.T.ok(not e["alive"], "the round killed the rusher on the contact tick")
	Runner.T.ok(p["alive"],
		"a rusher killed by the player's own round on tick T can no longer kill the player on tick T")


func test_every_lethal_check_honours_the_dodge_iframes() -> void:
	# _hurt_player is the single funnel, but each CALLER decides whether the
	# roll protects. One of them keyed on `roll_ticks == 0` instead of
	# `roll_iframe` — and they differ by exactly one tick (the final roll tick
	# decrements roll_ticks to 0 and THEN raises roll_iframe), so a barrel could
	# kill through a dodge that stopped everything else. A one-frame hole in
	# i-frames is invisible and therefore unlearnable: pin the flag.
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var lines := src.split("\n")
	for n in lines.size():
		if not lines[n].contains("_hurt_player(p)"):
			continue
		# Walk back over the (wrapped) guard that leads to this call.
		var guard := ""
		for k in range(maxi(0, n - 6), n):
			guard += lines[k]
		if not guard.contains("roll"):
			continue   # in-tank / vest paths guard on other state
		Runner.T.ok(guard.contains("roll_iframe"),
			"the lethal check at line %d guards on roll_iframe, not the off-by-one-tick roll_ticks" % (n + 1))


func test_no_lethal_radius_is_invisible_to_the_view() -> void:
	# "Damage with no visible cause" audit. Every player-lethal AREA hazard has
	# to be drawn at a radius the sim actually kills at, and the only safe way
	# to guarantee that is for the draw to READ the sim constant instead of
	# hardcoding a number that drifts. Pin the two that used to hardcode.
	var view := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(view.contains("SimWorld.GRENADE_RADIUS * PX"),
		"the mortar/airstrike telegraph ring is drawn from the kill radius itself")
	Runner.T.ok(view.contains("SimWorld.VENT_HURT_RADIUS"),
		"the foundry vent's jet and warn ring are drawn from VENT_HURT_RADIUS — "
		+ "they used to hardcode 24/10 while killing at 24, so the telegraph shrank "
		+ "onto a hazard that never did")


func test_the_parked_hull_stops_you_at_the_steel_you_can_see() -> void:
	## A parked tank is the only mid-lane cover you can hide BEHIND, and it is
	## the one blocker whose sprite fills its whole canvas. Walk a player
	## dead-on into its north face and measure where the sim actually stops him.
	## Both sides are measured: the standoff is behavioural, the RHS is the
	## shipped PNG's alpha bbox. Neither reads HULK_HALF_H.
	var d := _silhouette("tank_body")
	if d == Vector2.ZERO:
		return
	var sim := SimWorld.new(71, 1)
	sim.tanks.clear()
	var tx: int = 300 * SimWorld.F_ONE
	var ty: int = sim.camera_top + 200 * SimWorld.F_ONE
	sim.tanks.append({"x": tx, "y": ty, "alive": true, "burning": false,
		"fuel": 99999, "burn_ticks": 0, "fire_cd": 0, "occupant": -1})
	var p := sim.players[0]
	p["x"] = tx
	p["y"] = ty - 45 * SimWorld.F_ONE          # 45px north, clear of any box
	var walk := SimInput.new()
	walk.move_y = 256                           # straight south, into the hull
	for _n in 25:
		sim.enemies.clear()                     # scratch sim: keep the lane inert
		sim.enemy_bullets.clear()
		sim.step([walk])
	var standoff := float(ty - p["y"]) / SimWorld.F_ONE
	Runner.T.ok(standoff >= d.y * 0.45,
		"parked hull: player halts %.1fpx from centre, drawn hull half-height is %.1fpx"
			% [standoff, d.y * 0.5])


func test_board_reach_exceeds_the_hull_standoff_on_every_axis_including_the_corner() -> void:
	# Honest cover and a usable verb are one constraint, not two. HULK_HALF_H grew
	# 12 -> 23 so the parked hull stops you at the steel you can see — correct — but
	# TANK_BOARD_RADIUS did not follow, so the collision face pushed you OUTSIDE the
	# reach of the E you press to get in. Measured before the fix: the corner
	# standoff sqrt(16^2 + 23^2) = 28.02 against a 24 reach, i.e. a diagonal
	# approach could NEVER board, and the north face cleared by 1px — inside the
	# per-tick step remainder, so head-on boarding worked on roughly half the
	# stopping phases. A phase-dependent flaky control is worse than a refusal.
	#
	# Every existing hulk assertion gets EASIER as the box grows (they all check the
	# player ends up outside it), so nothing in the suite could catch this. This one
	# gets HARDER, which is the point.
	var hw: int = SimWorld.HULK_HALF_W
	var hh: int = SimWorld.HULK_HALF_H
	var reach: int = SimWorld.TANK_BOARD_RADIUS
	Runner.T.ok(reach > hw, "board reach clears the east/west hull face")
	Runner.T.ok(reach > hh, "board reach clears the north/south hull face")
	# The corner is the binding case and the one that regressed.
	var corner_sq: int = (hw / SimWorld.F_ONE) * (hw / SimWorld.F_ONE) \
		+ (hh / SimWorld.F_ONE) * (hh / SimWorld.F_ONE)
	var reach_px: int = reach / SimWorld.F_ONE
	Runner.T.ok(reach_px * reach_px > corner_sq,
		"board reach (%dpx) clears the hull CORNER (%.1fpx), so a diagonal walk-up can board"
			% [reach_px, sqrt(float(corner_sq))])
