extends SceneTree
## Throwaway probe: when does the 2P camera leash first bind in the determinism torture?
## The leash binds exactly when trailing.y - leading.y > CAMERA_LEAD - CAMERA_BAND_BOTTOM
## (260 - 344 = -84, i.e. a vertical separation over 84px). Pure position read.

const Det := preload("res://tests/test_determinism.gd")


func _init() -> void:
	var sim := SimWorld.new(0xDEADBEEF, 2)
	var first := -1
	var worst := 0
	for t in 3600:
		sim.step([Det.scripted_input(t, 0), Det.scripted_input(t, 1)])
		var lead := 0
		var trail := 0
		var n := 0
		for p in sim.players:
			if not p["alive"]:
				continue
			if n == 0 or p["y"] < lead:
				lead = p["y"]
			if n == 0 or p["y"] > trail:
				trail = p["y"]
			n += 1
		if n == 0:
			continue
		var sep: int = (trail - lead) / SimWorld.F_ONE
		worst = maxi(worst, sep)
		if sep > 84 and first < 0:
			first = t
	print("first leash bind tick=%d  worst separation=%dpx  sample=%d" % [first, worst, first / 600])
	quit()
