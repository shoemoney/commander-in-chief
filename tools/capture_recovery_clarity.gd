extends "res://tools/screenshots.gd"
## Staged recovery states rendered through the real game, not store screenshots.

func _build_shots() -> void:
	shots = [
		{"name": "free-checkpoint-rally", "build": func(): return _down("campaign", 0), "dress": _teach},
		{"name": "paid-revive", "build": func(): return _down("campaign", 100), "dress": _teach},
		{"name": "endless-last-breath", "build": func(): return _down("endless", 0), "dress": _teach},
	]


func _down(mode: String, chest: int) -> SimWorld:
	var sw := SimWorld.new(7, 1, mode)
	sw.war_chest = chest
	sw.players[0]["alive"] = false
	sw.players[0]["deaths"] = 1
	sw.players[0]["broke_timer"] = 180 if chest == 0 else 0
	return sw


func _teach(m: Node2D) -> void:
	m._hint_id = "revive"
	m._hint_text = m._recovery_hint_text()
	m._hint_t = 1.0
	m._hint_tier = m.PresentationTier.PLAYER_STATE
	m._motion = 0.0
