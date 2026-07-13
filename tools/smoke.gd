extends SceneTree
## Headless boot smoke-test: instantiates the real main scene, lets it run
## _ready() + a couple hundred physics ticks, then exits clean. Catches
## parse/runtime errors in main.gd/view that the sim-only test suite can't
## see (it never touches src/main.gd or the scene tree).
## Run:  godot --headless -s res://tools/smoke.gd
## Godot prints "SCRIPT ERROR"/"Parse Error" to stderr on any fault — the
## caller greps for that; this script just needs to survive to the end.

const FRAMES := 200

var _elapsed := 0


func _initialize() -> void:
	var main := (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_elapsed += 1
	if _elapsed >= FRAMES:
		print("SMOKE OK")
		quit(0)
