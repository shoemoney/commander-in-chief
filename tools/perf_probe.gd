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
	# REQUIRED for the cpu_ms/gpu_ms sample below. Without it the two
	# viewport_get_measured_render_time_* getters return 0.0 forever and silently -- which
	# is exactly what this probe reported on every run until 2026-08-02, so any opt-loop
	# pass that quoted a frame-time delta from here was comparing 0 against 0. Measurement
	# is valid from the next frame; probe_frame is 150, so no extra warmup is needed.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if Engine.get_process_frames() != probe_frame:
		return
	var vp_rid := root.get_viewport_rid()
	# cpu_ms is PER-VIEWPORT and, per the Godot docs, excludes frame setup -- so the honest
	# CPU render total is cpu_ms + setup_ms. Kept as separate fields so a regression can be
	# attributed to the viewport's own work rather than to engine-side setup.
	# gpu_ms measured 0.0 on macOS 2026-08-02 under BOTH forward_plus and gl_compatibility
	# even with measurement enabled -- the GPU timestamp path is not wired up on this
	# platform. cpu_ms is the number to trend here; treat a 0 gpu_ms as "unmeasured",
	# not as "free", and re-check it on Linux before quoting a GPU delta.
	print("draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		" video_mem=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		" objects=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		" orphans=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" cpu_ms=", RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
		" setup_ms=", RenderingServer.get_frame_setup_time_cpu(),
		" gpu_ms=", RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
	quit()
