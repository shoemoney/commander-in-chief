extends SceneTree
## opt-loop perf probe: boots the real game (src/main.tscn) running normally (not posed/frozen
## like screenshots.gd) and samples RenderingServer/Performance counters at a fixed frame, so
## before/after opt-loop passes have a repeatable, scriptable number instead of an eyeballed
## console print. Pair with --write-movie for a deterministic run:
##   godot --path . --write-movie /tmp/perf/out.avi --fixed-fps 15 --quit-after 200 \
##       --resolution 1280x720 --rendering-method gl_compatibility -s res://tools/perf_probe.gd
## PROBE_FRAME (default 150) picks the sample frame. Dev tool only — never shipped.

var main: Node2D
var probe_frame := 150


func _initialize() -> void:
	var pf := OS.get_environment("PROBE_FRAME")
	if not pf.is_empty():
		probe_frame = pf.to_int()
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true   # headless window never holds focus; don't pause-overlay the run
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if Engine.get_process_frames() != probe_frame:
		return
	var vp := root.get_viewport()
	print("draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		" video_mem=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		" objects=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		" orphans=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" cpu_ms=", RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()),
		" gpu_ms=", RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	quit()
