extends RefCounted
## TEACH THE TRUTH - every first-sighting card, help line and edge pip is asserted
## against what the sim actually does. Sibling of test_view_honesty.gd.

const Runner := preload("res://tests/run_tests.gd")
const Art := preload("res://src/view/art.gd")
const Main := preload("res://src/main.gd")
const Menu := preload("res://src/view/menu.gd")
const F := 65536


func _gunner(kind: String, x: float, y: float, windup: int) -> Dictionary:
	return {"alive": true, "kind": kind, "x": int(x * F), "y": int(y * F), "windup": windup}


func _pips(enemies: Array, top := 0) -> Array:
	var to_screen := func(x: int, y: int) -> Vector2:
		return Vector2(roundf(x / float(F)), roundf((y - top) / float(F)))
	return TeachTruth.gunner_pips(enemies, to_screen, 640.0, 360.0, 150.0, 40.0)


# --- 5. off-screen gunners ---------------------------------------------------

func test_offscreen_gunner_in_windup_gets_a_pip_and_idle_one_does_not() -> void:
	Runner.T.eq(_pips([_gunner("rusher", -30, 180, 12)]).size(), 1, "rifleman winding up past the left edge: a pip")
	Runner.T.eq(_pips([_gunner("elite", 700, 180, 12)]).size(), 1, "elite winding up past the right edge: a pip")
	Runner.T.eq(_pips([_gunner("rusher", -30, 180, 0)]).size(), 0, "same rifleman NOT in windup: no pip")
	Runner.T.eq(_pips([_gunner("rusher", 320, 180, 12)]).size(), 0, "on-screen windup: the body telegraph covers it")
	Runner.T.eq(_pips([_gunner("rusher", 320, -40, 12)]).size(), 1, "above the frame in windup: a pip")
	var dead := _gunner("rusher", -30, 180, 12)
	dead["alive"] = false
	Runner.T.eq(_pips([dead]).size(), 0, "a corpse never pips")


func test_gunner_pips_cluster_and_cap() -> void:
	var squad: Array = []
	for i in 6:
		squad.append(_gunner("rusher", -20 - i * 3, 60 + i * 4, 10 + i))
	var p := _pips(squad)
	Runner.T.eq(p.size(), 1, "six riflemen in one breach collapse into one pip")
	if p.size() == 1:
		Runner.T.eq(int(p[0]["count"]), 6, "...that remembers how many are behind it")
	var spread: Array = []
	for i in 8:
		spread.append(_gunner("elite", -20, 20 + i * 45, 10))
	Runner.T.ok(_pips(spread).size() <= TeachTruth.MAX_PIPS,
		"a long column never carpets the edge (cap %d)" % TeachTruth.MAX_PIPS)


func test_sim_produces_an_offscreen_windup_the_pip_reads() -> void:
	## Measured, not constructed: a real rifleman beyond the side edge, inside the Y band,
	## really does open fire (the sim only gates Y), and the pip tracks exactly that window.
	var sim := SimWorld.new(7, 1, "campaign")
	var p: Dictionary = sim.players[0]
	p["x"] = 60 * F   # inside RIFLEMAN_STANDOFF of a rifleman standing 30px past the edge
	sim._spawn_enemy(-30 * F, p["y"], false)
	var e: Dictionary = sim.enemies[sim.enemies.size() - 1]
	e["x"] = -30 * F
	e["y"] = p["y"]
	var seen := 0
	var pipped := 0
	var idle_pips := 0
	for t in 300:
		sim.step([SimInput.new()])
		if not e["alive"]:
			break
		var winding: bool = int(e.get("windup", 0)) > 0 and int(e["x"]) < 0
		var n := _pips(sim.enemies, sim.camera_top).size()
		if winding:
			seen += 1
			if n > 0:
				pipped += 1
		elif n > 0:
			idle_pips += 1
	Runner.T.ok(seen > 0, "the sim let an off-screen rifleman wind up (%d ticks)" % seen)
	Runner.T.eq(pipped, seen, "a pip was up on every off-screen windup tick (%d/%d)" % [pipped, seen])
	Runner.T.eq(idle_pips, 0, "and none outside a windup")


func test_draw_threat_pips_uses_the_gunner_pips() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var body := src.substr(src.find("func _draw_threat_pips"), 9000)
	Runner.T.ok(body.contains("TeachTruth.gunner_pips"), "_draw_threat_pips draws the gunner pips")


# --- 1/2. teaching cards -----------------------------------------------------

func test_mg_nest_card_does_not_promise_a_flank() -> void:
	var card := String(Main._KIND_TEACH["mg_nest"]).to_upper()
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var nest := src.substr(src.find("func _step_mg_nest"), 1200)
	Runner.T.ok(nest.contains("_nearest_alive_player"), "premise: the nest re-aims at the nearest player each round")
	Runner.T.ok(not card.contains("FLANK"), "no flank promise on a facing-less turret: %s" % card)
	Runner.T.ok(card.contains("TRACKS"), "the card says it tracks you: %s" % card)
	Runner.T.ok(card.contains("GRENADE"), "...and names a real answer: %s" % card)


func test_grenadier_card_teaches_the_line_not_the_spot() -> void:
	var card := String(Main._KIND_TEACH["grenadier"]).to_upper()
	Runner.T.ok(not card.contains("MOVE OFF YOUR GROUND"), "the drone's dodge is not the grenadier's: %s" % card)
	Runner.T.ok(SimWorld.GRENADIER_CLUSTER_SPREAD > 0, "premise: the lobs are spread across the firing line")
	Runner.T.ok(card.contains("3 LOBS") or card.contains("THREE"), "names the three lobs: %s" % card)
	Runner.T.ok(card.contains("TOWARD") or card.contains("ALONG"), "teaches running the line: %s" % card)


func test_new_cards_fit_the_banner_plate() -> void:
	for k in ["mg_nest", "grenadier"]:
		var s: String = Main._KIND_TEACH[k]
		var sz: int = Main.banner_fit_size(s, 16)
		var r: Rect2 = Main.banner_plate_rect(s, 70.0, sz, 24.0)
		Runner.T.ok(r.size.x <= 0.72 * Main.SCREEN_W and sz >= 12, "'%s' fits (%dpx, size %d)" % [s, int(r.size.x), sz])


# --- 4. airstrike discloses the forfeit --------------------------------------

func test_airstrike_blurb_discloses_no_bounty_because_the_sim_mints_none() -> void:
	var sim := SimWorld.new(5, 1, "campaign")
	for i in 12:
		sim._spawn_enemy((200 + i * 20) * F, sim.camera_top + (80 + (i % 3) * 20) * F, false)
	sim.war_chest = 500
	var before := sim.war_chest
	sim._fire_mission()
	Runner.T.eq(sim.war_chest, before, "premise: a strike on 12 enemies returns +0 to the chest")
	var blurb := String(Main.WHEEL_ITEMS[3]["blurb"]).to_upper()
	Runner.T.ok(blurb.contains("NO BOUNTY"), "the wheel card for AIRSTRIKE says so: %s" % blurb)
	for i in [0, 1, 2, 4]:
		Runner.T.ok(not String(Main.WHEEL_ITEMS[i]["blurb"]).to_upper().contains("NO BOUNTY"),
			"other wheel items don't carry the disclosure")
	var card := "%s — %s" % [Main.WHEEL_ITEMS[3]["label"], Main.WHEEL_ITEMS[3]["blurb"]]
	Runner.T.ok(Art.tw(card, 8) < 300.0, "the card stays inside the frame (%dpx)" % int(Art.tw(card, 8)))


# --- 3. war chest page -------------------------------------------------------

func test_war_chest_page_states_the_true_trade_off() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/sim_world.gd")
	var rv := src.substr(src.find("func _try_revive"), 2400)
	Runner.T.ok(rv.contains("war_chest -= cost") and not rv.contains("score +="),
		"premise: a revive spends coin and credits no score")
	Runner.T.ok(SimWorld.SPEND_SCORE_MULT < SimWorld.VICTORY_SCORE_MULT, "premise: banking beats spending")
	var m = Menu.new()
	var corpus := ""
	for en in m._howto_large_entries(1):
		corpus += String(en["text"]) + "\n"
	m.free()
	Runner.T.ok(corpus.contains("%d×" % SimWorld.SPEND_SCORE_MULT), "page states the spend rate")
	Runner.T.ok(corpus.contains("%d×" % SimWorld.VICTORY_SCORE_MULT), "page states the bank rate")
	Runner.T.ok(corpus.to_upper().contains("REVIVES PAY NONE"), "page says revives pay no score")
