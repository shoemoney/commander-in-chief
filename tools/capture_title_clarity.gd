extends "res://tools/screenshots.gd"
## Matched staged QA: identical battlefield/banner, with and without title UI.
## These are not storefront gameplay captures.

func _process(_delta: float) -> bool:
	RenderingServer.force_draw.call_deferred(false, 1.0 / 60.0)
	return false


func _build_shots() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("TITLE CAPTURE FAIL: deadline exceeded")
		quit(1))
	shots = [
		{"name": "title", "build": _field, "dress": _title},
		{"name": "gameplay", "build": _field, "dress": _gameplay},
	]


func _field() -> SimWorld:
	var sw := SimWorld.new(3, 1, "campaign")
	sw.tick_count = 600
	return sw


func _common(m: Node2D) -> void:
	m._motion = 0.0
	m._hint_text = ""
	m._hint_t = 0.0
	m._banners.append({"text": "GATE SECURED — 8.2s", "t": 0.7,
		"col": Color(1.0, 0.92, 0.55), "tier": m.PresentationTier.OBJECTIVE})
	m._hud_icons._sync_visibility()


func _title(m: Node2D) -> void:
	_common(m)
	m._menu.open(GameMenu.Mode.TITLE)
	m._menu._open_t = 0.6
	m._hud_icons.hide()


func _gameplay(m: Node2D) -> void:
	_common(m)
	m._menu.mode = GameMenu.Mode.HIDDEN
	m._hud_icons.show()
