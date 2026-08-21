extends SceneTree
## Bot-driven world-label overlap census — opt-in measuring tape, NOT in the suite.
## Run: tools/run_tests.sh -s res://tools/probe_droplabels.gd
##
## Drives demo_input through campaign/endless/arcade x 2 seeds x 3,600 ticks, samples
## every 3rd tick (7,200 frames per text scale), and replays the SHIPPED pickup-label
## claim math against the shipped player exclusion + HUD corner-panel reservation.
## A label counts as a collision when the arbiter hands it pixels already taken.
##
## MEASURED (2026-08-21, this tree):
##   BEFORE (claim_label_slot's keep-place clamp, no off-frame gate):
##     100% text size: 3,335 / 7,200 frames carried >=1 overlap (46.32%), 9,758 labels
##     200% text size: 3,385 / 7,200 frames (47.01%), 14,233 labels
##   AFTER (extended in-frame search + the _world_label off-SUBJECT gate):
##     100%: 0 / 7,200 (0.00%), 0 labels     200%: 0 / 7,200 (0.00%), 0 labels
##
## WINDOW CAVEAT: this SAMPLES (3,600 ticks/run, every 3rd tick). The suite ratchet
## tests/test_main.gd::test_world_label_arbiter_never_returns_occupied_pixels does NOT
## sample — it is exhaustive over 13,653 staged claims per text scale — so the ratchet,
## not this probe, is the gate. This exists to show the defect in real play.
##
## INSTRUMENT TRAP, recorded because it cost a full cycle: PX is `1.0 / Fixed.ONE`,
## not 1.0. A first version of this probe hard-coded PX := 1.0, so every pickup landed
## ~65,536x off-screen, failed _draw_pickups' band cull, and the probe reported a
## confident 0 overlaps on the UNFIXED tree. A zero here means "check PX first".
const MS := preload("res://src/main.gd")
const PX := 1.0 / Fixed.ONE

func _init() -> void:
	var ms: Script = MS
	var panel := Rect2(HudIcons.PLATE_ORIGIN, HudIcons.PLATE_ORIGIN, HudIcons.PLATE_MIN_W,
		HudIcons.PLATE_ORIGIN + HudIcons.HEAD_H + HudIcons.ROW_H)
	# READ THE SHIPPED RECT, never restate it. This probe used to hardcode
	# Rect2(0,0,640,360) and detect the gate by the presence of WORLD_LABEL_FRAME —
	# so when the subject gate gained a top-edge tolerance (WORLD_LABEL_SUBJECT_FRAME,
	# WORLD_LABEL_FRAME grown upward by WORLD_LABEL_TOP_TOL), the probe kept measuring
	# the STRICT rect while the game used the tolerant one, and its `gate` flag stayed
	# true because the old constant still exists. A measuring rig whose numbers describe
	# code the game no longer runs is worse than no rig: it reports failures against
	# behaviour the suite calls correct.
	var consts: Dictionary = ms.get_script_constant_map()
	var frame_r: Rect2 = consts.get("WORLD_LABEL_SUBJECT_FRAME", Rect2(0.0, 0.0, 640.0, 360.0))
	var gate: bool = consts.has("WORLD_LABEL_SUBJECT_FRAME")
	for scale in [1.0, 2.0]:
		Art.text_scale = scale
		Art.flush_tw()
		var sz: int = Art.fs(8)
		var frames := 0
		var bad_frames := 0
		var pairs := 0
		for mode in ["campaign", "endless", "arcade"]:
			for seed_v in [0xC0FFEE, 12345]:
				var sim := SimWorld.new(seed_v, 1, mode)
				for t in 3600:
					sim.step([ms.demo_input(t, sim)])
					if t % 3 != 0:
						continue
					frames += 1
					var taken: Array[Rect2] = [panel]
					for p in sim.players:
						if p["alive"]:
							taken.append(ms.player_label_exclusion(Vector2(
								roundf(p["x"] * PX), roundf((p["y"] - sim.camera_top) * PX))))
					var n0 := taken.size()
					for pk in sim.pickups:
						var pp := Vector2(roundf(pk["x"] * PX), roundf((pk["y"] - sim.camera_top) * PX))
						if pp.y < -40.0 or pp.y > 400.0:
							continue
						var txt: String = "SPREAD" if pk["kind"] >= 4 else "MAXED"
						var w: float = Art.tw(txt, sz)
						var want: Rect2 = ms._label_plate_rect(pp.x - w / 2.0, pp.y - 24.0, w, sz)
						# The SHIPPED gate is on the SUBJECT (the crate), not on the plate:
						# a crate visible in the top 21px has its plate entirely above
						# y=0, and gating on `want` there drops the label off something
						# the player can see. Mirror main.gd exactly or this probe stops
						# measuring the game.
						if gate and not frame_r.has_point(pp):
							continue
						var got: Rect2 = ms.claim_label_slot(want, taken)
						if got.get_area() <= 0.0:
							continue
						taken.append(got)
					var hit := 0
					for i in range(n0, taken.size()):
						for j in taken.size():
							if j == i:
								continue
							if (taken[i] as Rect2).grow(-0.5).intersects((taken[j] as Rect2).grow(-0.5)):
								hit += 1
								break
					if hit > 0:
						bad_frames += 1
						pairs += hit
		print("scale=%d%%  gate=%s  frames=%d  frames_with_overlap=%d (%.2f%%)  overlapping_labels=%d"
			% [int(scale * 100.0), str(gate), frames, bad_frames,
				100.0 * float(bad_frames) / float(maxi(frames, 1)), pairs])
	quit()
