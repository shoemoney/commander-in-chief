extends SceneTree
## Regression: audio teardown must allow real time even during accelerated captures.
const Quiesce := preload("res://tools/quiesce.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var prior_scale := Engine.time_scale
	for frozen in [false, true]:
		var owned := Node.new()
		root.add_child(owned)
		Engine.time_scale = 0.0 if frozen else 20.0
		paused = frozen
		var started := Time.get_ticks_msec()
		await Quiesce.teardown(self, owned)
		var elapsed := Time.get_ticks_msec() - started
		paused = false
		Engine.time_scale = prior_scale
		if elapsed < int(Quiesce.AUDIO_DRAIN_SEC * 1000.0) or is_instance_valid(owned):
			push_error("QUIESCE FAIL frozen=%s elapsed_ms=%d: teardown must drain in real time and free its node" % [frozen, elapsed])
			quit(1)
			return
		print("QUIESCE PASS frozen=%s elapsed_ms=%d" % [frozen, elapsed])
	quit(0)
