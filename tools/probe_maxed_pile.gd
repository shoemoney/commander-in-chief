extends SceneTree

# Measures the REAL pickup-label pile: builds each tick's tags with the SHIPPED
# Main.pickup_label_requests() and counts pairwise overlaps + suppressed tags.
#
# HEAD=1 reproduces the pre-fix claim (draw order, non-droppable, so a saturated tag
# keeps its place and prints anyway); unset uses the shipped Main.claim_pickup_labels.
var head := OS.get_environment("HEAD") == "1"

func _init() -> void:
	var ms: Script = load("res://src/main.gd")
	var modes := ["campaign", "arcade", "endless"]
	for mode in modes:
		for seed_i in [7, 11, 23]:
			var sim := SimWorld.new(seed_i, 1, mode)
			var worst := 0
			var frames_with_overlap := 0
			var total_overlap := 0
			var max_labels := 0
			var drops := 0
			var t := 0
			while t < 5400 and not sim.wiped:
				sim.step([ms.demo_input(t, sim)])
				t += 1
				var slots: Array[Rect2] = []
				var reqs: Array = ms.pickup_label_requests(sim)
				var got: Array[Rect2] = []
				if head:
					for rq in reqs:
						var r: Rect2 = ms.claim_label_slot(rq["want"], slots, 0.0, false)
						slots.append(r)
						got.append(r)
				else:
					got = ms.claim_pickup_labels(reqs, slots)
				var live: Array[Rect2] = []
				for r in got:
					if r.has_area():
						live.append(r)
					else:
						drops += 1
				var over := 0
				for i in live.size():
					for j in range(i + 1, live.size()):
						if live[i].grow(-0.5).intersects(live[j].grow(-0.5)):
							over += 1
				max_labels = maxi(max_labels, reqs.size())
				if over > 0:
					if frames_with_overlap == 0:
						print("FIRST OFFENDING TICK %d labels=%d" % [t, live.size()])
						for r in live:
							print("   %s" % str(r))
					frames_with_overlap += 1
					total_overlap += over
					worst = maxi(worst, over)
			print("%s seed %d ticks=%d maxlabels=%d frames_overlap=%d worst=%d total=%d drops=%d"
				% [mode, seed_i, t, max_labels, frames_with_overlap, worst, total_overlap, drops])
	quit()
