extends RefCounted
## Shut a booted src/main.tscn down QUIETLY, so a headless tool's exit is not
## indistinguishable from a real leak.
##
## THE PROBLEM. Godot destroys the AudioServer AFTER ObjectDB::cleanup, so every
## stream still mid-playback when quit() lands is reported as a leaked object, and
## its stream as `ERROR: N resources still in use at exit`. Measured on
## tools/e2e_playthrough.gd before this existed: 30 ObjectDB (16
## AudioStreamPlaybackWAV, 10 AudioStreamWAV, 2 AudioStreamPlaybackPolyphonic, an
## MP3 pair) plus `Resource still in use: res://assets/vo/cmd/cmd_levelstart_6.mp3`
## -- on a run reporting `=== 80 checks, 0 FAIL ===`. None of it is a defect; it is
## a 240-frame gameplay drive quitting mid-cue. But it prints the SAME lines as the
## orphaned-Node leak tools/run_tests.sh gates on, so the tools stop making the
## noise rather than the gate learning to ignore it.
##
## TWO DETAILS ARE LOAD-BEARING, both measured, both easy to get wrong:
##   1. process_mode goes DISABLED *before* the players are stopped. With the order
##      reversed, the wait below lets _process fire FRESH cues and the count goes
##      UP -- e2e_playthrough measured 30 -> 34.
##   2. The release runs on the AUDIO thread, so the wait is in WALL TIME, not
##      frames. With two idle frames instead of a timer, e2e_playthrough came back
##      dirty on 4 of 6 runs and clean on 2 -- a race, not a leak.
## With both, e2e_playthrough and smoke each report ZERO leaked objects on 6 of 6
## runs. There is no residual engine floor to exempt.
##
## Usage, from any SceneTree tool, before quit():
##     const Quiesce := preload("res://tools/quiesce.gd")
##     await Quiesce.teardown(self, main)

const AUDIO_DRAIN_SEC := 0.5


static func teardown(tree: SceneTree, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for n in node.find_children("*", "", true, false):
		if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
			n.stop()
			n.stream = null
	await tree.create_timer(AUDIO_DRAIN_SEC).timeout
	node.free()
