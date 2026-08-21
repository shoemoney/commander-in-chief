extends SceneTree
## opt-loop perf probe: boots the real game (src/main.tscn) running normally (not posed/frozen
## like screenshots.gd), drives it with the scripted demo bot so the scene isn't an idle standing
## soldier, and samples RenderingServer/Performance counters over a window of frames, so
## before/after opt-loop passes have a repeatable, scriptable number instead of an eyeballed
## single-frame snapshot under the boot splash. Pair with --write-movie for a deterministic run:
##   godot --path . --write-movie /tmp/perf/out.avi --fixed-fps 15 --quit-after 300 \
##       --resolution 1280x720 -s res://tools/perf_probe.gd
## Add --rendering-method gl_compatibility as a SECOND, explicit comparison run — the default
## (no flag) matches the shipped desktop build's forward_plus backend.
## PROBE_FRAME (default 150) picks the sample window start (150..270). Dev tool only — never shipped.

const Quiesce := preload("res://tools/quiesce.gd")

var main: Node2D
var probe_frame := 150
var samples: Array[Dictionary] = []


func _initialize() -> void:
	var pf := OS.get_environment("PROBE_FRAME")
	if not pf.is_empty():
		probe_frame = pf.to_int()
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true    # headless window never holds focus; don't pause-overlay the run
	main.demo_autoplay = true   # drive the scripted bot -- an idle player under the splash was
	                            # the same "45 review cycles of a soldier standing still" bug
	                            # tests/test_main.gd:815-817 already paid for once.
	main._end_splash()          # idempotent (src/main.gd:694-696) -- skip the 16s opaque splash
	                            # and its 6.5MB keyart poster so the sample reflects real gameplay.
	# REQUIRED for the cpu_ms/gpu_ms sample below. Without it the two
	# viewport_get_measured_render_time_* getters return 0.0 forever and silently -- which
	# is exactly what this probe reported on every run until 2026-08-02, so any opt-loop
	# pass that quoted a frame-time delta from here was comparing 0 against 0. Measurement
	# is valid from the next frame; probe_frame is 150, so no extra warmup is needed.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	var f := Engine.get_process_frames()
	if f < probe_frame:
		return
	if f > probe_frame + 120:
		process_frame.disconnect(_on_frame)   # teardown awaits; do not re-enter
		_report()
		await Quiesce.teardown(self, main)
		quit()
		return
	var vp_rid := root.get_viewport_rid()
	# cpu_ms is PER-VIEWPORT and, per the Godot docs, excludes frame setup -- so the honest
	# CPU render total is cpu_ms + setup_ms. Kept as separate fields so a regression can be
	# attributed to the viewport's own work rather than to engine-side setup.
	# gpu_ms measured 0.0 on macOS 2026-08-02 under BOTH forward_plus and gl_compatibility
	# even with measurement enabled -- the GPU timestamp path is not wired up on this
	# platform. cpu_ms is the number to trend here; treat a 0 gpu_ms as "unmeasured",
	# not as "free", and re-check it on Linux before quoting a GPU delta.
	samples.append({
		"frame": f,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
	})


func _report() -> void:
	var draw_calls: Array[int] = []
	var cpu_ms: Array[float] = []
	var peak_frame := 0
	var peak_cpu := -1.0
	for s in samples:
		draw_calls.append(s.draw_calls)
		cpu_ms.append(s.cpu_ms)
		if s.cpu_ms > peak_cpu:
			peak_cpu = s.cpu_ms
			peak_frame = s.frame
	draw_calls.sort()
	cpu_ms.sort()
	var vp_rid := root.get_viewport_rid()
	print("method=", RenderingServer.get_current_rendering_method(),
		" frames=", samples.size(),
		" draw_calls_min=", draw_calls.front(), " draw_calls_avg=", _avg(draw_calls), " draw_calls_max=", draw_calls.back(),
		" cpu_ms_min=", cpu_ms.front(), " cpu_ms_avg=", _avg(cpu_ms), " cpu_ms_max=", cpu_ms.back(),
		" peak_frame=", peak_frame,
		" video_mem=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		" objects=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		" orphans=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" setup_ms=", RenderingServer.get_frame_setup_time_cpu(),
		" gpu_ms=", RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))


func _avg(vals: Array) -> float:
	var total := 0.0
	for v in vals:
		total += v
	return total / vals.size()
