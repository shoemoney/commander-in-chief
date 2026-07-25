extends RefCounted
## STUB-PARITY RATCHET.
##
## src/view/menu.gd and src/view/hud.gd both read a `main` reference. Headless tests hand them a
## hand-written Node2D stub instead of the real src/main.gd. Nothing kept those stubs in sync with
## the view code, and the failure is SILENT-BUT-GREEN: a missing field makes GDScript log
## "Invalid access to property or key '<x>'" and abandon the rest of that call, so the row under
## test simply measures as ABSENT — every assertion still passes. That is exactly how the c4-18
## `last_run_score` / `replay_watched_score` gap shipped (see the note on _StubMain); the only
## evidence was an error line nobody was grepping.
##
## So: parse every `main.<x>` and `main.get("<x>")` the two view scripts actually execute (comments
## stripped) and assert each stub that gets passed in as `main` really answers it. Source text is
## parsed, never called — this stays a read-only check with no view/sim behavior.
##
## Sibling of tests/test_event_coverage.gd, which pins the same shape for the sim->view event seam.

const Runner := preload("res://tests/run_tests.gd")
const MenuTests := preload("res://tests/test_menu_layout.gd")
const HudTests := preload("res://tests/test_hud.gd")


func test_menu_stub_mirrors_every_main_access() -> void:
	_assert_parity("res://src/view/menu.gd", MenuTests._StubMain,
		"_StubMain (tests/test_menu_layout.gd)")


func test_hud_stubs_mirror_every_main_access() -> void:
	# Every stub that is assigned to HudIcons.main must answer everything hud.gd reads — a narrow
	# stub is precisely how a missing field hides, since the test that uses it is narrow too.
	for pair in [[HudTests._VerbMain, "_VerbMain"], [HudTests._RowMain, "_RowMain"],
			[HudTests._FrameMain, "_FrameMain"], [HudTests._ShopMain, "_ShopMain"]]:
		_assert_parity("res://src/view/hud.gd", pair[0], "%s (tests/test_hud.gd)" % pair[1])


## Fail for each name `path` reads off `main` that `stub_class` can't answer.
func _assert_parity(path: String, stub_class: GDScript, stub_name: String) -> void:
	var wanted := _main_accesses(path)
	# Guard against a vacuously-green run: if the parse finds nothing, the ratchet is dead.
	Runner.T.ok(wanted.size() >= 5,
		"%s reads only %d names off `main` — the stub-parity parse matched nothing" % [path, wanted.size()])
	var stub: Node = stub_class.new()
	var have := {}
	for p in stub.get_property_list():
		have[p["name"]] = true
	for name in wanted:
		Runner.T.ok(have.has(name) or stub.has_method(name),
			"%s reads main.%s but %s has no such property or method — the stub answers nothing, so the code path silently measures as absent and every assertion still passes" \
				% [path.get_file(), name, stub_name])
	stub.free()


## Every distinct name `path` reads off its `main` reference, comments stripped. Both the direct
## `main.x` form and the `main.get("x")` form (which the HUD uses deliberately, and which returns a
## silent null rather than erroring — the quietest way for a stub gap to hide).
func _main_accesses(path: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	Runner.T.ok(not src.is_empty(), "could not read %s for the stub-parity parse" % path)
	var direct := RegEx.create_from_string('\\bmain\\.([A-Za-z_][A-Za-z_0-9]*)')
	var dynamic := RegEx.create_from_string('\\bmain\\.get\\("([A-Za-z_][A-Za-z_0-9]*)"\\)')
	var names := {}
	for line in src.split("\n"):
		# Cut at the first '#'. Neither view script puts a '#' inside a string literal (no hex
		# colors, no format specifiers), so this needs no lexer.
		var code := line.substr(0, line.find("#")) if line.contains("#") else line
		for m in direct.search_all(code):
			names[m.get_string(1)] = true
		for m in dynamic.search_all(code):
			names[m.get_string(1)] = true
	names.erase("get")   # Object.get — the accessor itself, not a member of main
	return names.keys()
