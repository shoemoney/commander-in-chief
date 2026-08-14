extends SceneTree
## AUDIT probe: verify the TRIPLE SHOT finding's specifics.
## (1) per-seed run outcome (ticks / deaths / kills) so the aggregate kill delta
##     is not confounded by triple-runs ending early.
## (2) kills and enemy-hits per ROUND SPENT and per TICK — the swarm case probe E
##     could not see (it fired at one static point).
## (3) the exact range at which the +/-12 deg outer pellets stop landing on each
##     hitbox in the game.

const F := 65536
const MAXT := 6000

func run_bot(triple: bool) -> void:
	var MainScript: GDScript = load("res://src/main.gd")
	var tot_ticks := 0
	var tot_kills := 0
	var tot_rounds := 0
	var tot_hits := 0
	var tot_deaths := 0
	var wipes := 0
	for seed_v in [0xC0FFEE, 1, 2, 3]:
		var sim := SimWorld.new(seed_v, 1, "campaign")
		var p: Dictionary = sim.players[0]
		var t := 0
		var kills := 0
		var hits := 0
		var rounds := 0
		var prev_ammo: int = p["mg_ammo"]
		while t < MAXT and not sim.wiped:
			p["triple"] = triple
			var inp: SimInput = MainScript.demo_input(sim.tick_count, sim)
			prev_ammo = p["mg_ammo"]
			sim.step([inp])
			p = sim.players[0]
			# rounds actually billed this tick (ignore refills/pickups: only count drops)
			if p["mg_ammo"] < prev_ammo:
				rounds += prev_ammo - p["mg_ammo"]
			for ev in sim.events:
				if ev["t"] == "kill":
					kills += 1
				elif ev["t"] == "boss_hit":
					hits += 1
			t += 1
		tot_ticks += t
		tot_kills += kills
		tot_rounds += rounds
		tot_hits += hits
		tot_deaths += int(sim.players[0].get("deaths", 0))
		if sim.wiped:
			wipes += 1
		print("    seed %-8d ticks=%4d wiped=%s deaths=%d kills=%3d rounds=%4d hits=%3d" % [
			seed_v, t, sim.wiped, int(sim.players[0].get("deaths", 0)), kills, rounds, hits])
	print("  triple=%s TOTAL ticks=%d wipes=%d deaths=%d kills=%d rounds=%d hits=%d | kills/1k ticks=%.1f  kills/100 rounds=%.2f  hits/100 rounds=%.2f" % [
		triple, tot_ticks, wipes, tot_deaths, tot_kills, tot_rounds, tot_hits,
		1000.0 * tot_kills / tot_ticks, 100.0 * tot_kills / maxi(1, tot_rounds),
		100.0 * tot_hits / maxi(1, tot_rounds)])

func outer_pellet_reach() -> void:
	## Geometric: closest approach of a +/-12 deg pellet to a target at range R is
	## R*sin(12). Walk R until the outer pellet stops landing, per hitbox.
	for entry in [["rusher/fodder", SimWorld.BULLET_HIT_RADIUS],
			["elite/technical", 13 * F], ["mg_nest", 16 * F], ["broadcast", 17 * F],
			["gunship boss", SimWorld.BOSS_HIT_RADIUS], ["colossus", SimWorld.COLOSSUS_HIT_RADIUS]]:
		var r: int = entry[1]
		var last_ok := 0
		for rng_px in range(8, 400, 1):
			# simulate one outer pellet flight, same 6px/tick sampling the sim uses
			var ax: int = Fixed.mul(0, SimWorld.SPREAD_COS) - Fixed.mul(-F, SimWorld.SPREAD_SIN)
			var ay: int = Fixed.mul(0, SimWorld.SPREAD_SIN) + Fixed.mul(-F, SimWorld.SPREAD_COS)
			var bx := 0
			var by := 0
			var tx := 0
			var ty := -rng_px * F
			var hit := false
			for t in SimWorld.BULLET_TTL_TICKS:
				bx += Fixed.mul(ax, SimWorld.BULLET_SPEED)
				by += Fixed.mul(ay, SimWorld.BULLET_SPEED)
				if Fixed.length(bx - tx, by - ty) <= r:
					hit = true
					break
			if hit:
				last_ok = rng_px
			else:
				break
		print("  %-16s r=%2dpx  outer pellet lands out to %d px, misses beyond" % [
			entry[0], r / F, last_ok])

func _init() -> void:
	print("== outer (+/-12 deg) pellet reach per hitbox ==")
	outer_pellet_reach()
	print("")
	print("== repo bot, 4 seeds, 6000-tick cap ==")
	run_bot(false)
	run_bot(true)
	quit()
