class_name Art
extends RefCounted
## Sprite registry for the view. Units/vehicles/props are top-down renders of
## legacy 3D pack Military 3D models, baked to sprites by tools/bake_sprites.gd
## (see assets/legacy-art/). Ground tiles, projectiles and FX remain Kenney CC0
## (kenney.nl) — legacy art ships no seamless 2D tilesets. View-layer only; the sim
## never touches textures.
##
## SCALE folds each legacy art render down to the on-screen footprint of the Kenney
## sprite it replaced, so the draw calls in main.gd keep their original scale
## numbers. TINT is the desert→jungle olive shift, applied in _spr().

const SY := "res://assets/legacy-art/"
const KN := "res://assets/kenney/"

const TEX := {
	# --- legacy 3D pack Military (top-down bakes) ---
	"player1": preload(SY + "player1.png"),
	"player2": preload(SY + "player2.png"),
	"rusher": preload(SY + "rusher.png"),
	"elite": preload(SY + "elite.png"),
	"frogman": preload(SY + "frogman.png"),
	"observer": preload(SY + "observer.png"),
	"tank_body": preload(SY + "tank_body.png"),
	"tank_barrel": preload(SY + "tank_barrel.png"),
	"gunship_body": preload(SY + "gunship_body.png"),
	"gunship_barrel": preload(SY + "gunship_barrel.png"),
	"colossus_body": preload(SY + "colossus_body.png"),
	"colossus_barrel": preload(SY + "colossus_barrel.png"),
	"sandbag": preload(SY + "sandbag.png"),
	"sandbag_beige": preload(SY + "sandbag.png"),
	"crate_ammo": preload(SY + "crate_ammo.png"),
	"crate_grenade": preload(SY + "crate_grenade.png"),
	"crate_airstrike": preload(SY + "crate_airstrike.png"),
	"tree_large": preload(SY + "tree_large.png"),
	"tree_small": preload(SY + "tree_small.png"),
	"fern": preload(SY + "fern.png"),
	# --- legacy art icon bakes (HUD + spend-wheel) ---
	"icon_ammo": preload(SY + "icons/icon_ammo.png"),
	"icon_grenade": preload(SY + "icons/icon_grenade.png"),
	"icon_coin": preload(SY + "icons/icon_coin.png"),
	"icon_fuel": preload(SY + "icons/icon_fuel.png"),
	"icon_vest": preload(SY + "icons/icon_vest.png"),
	"icon_skull": preload(SY + "icons/icon_skull.png"),
	"icon_medal": preload(SY + "icons/icon_medal.png"),
	"icon_airstrike": preload(SY + "icons/icon_airstrike.png"),
	# --- legacy art INTERFACE sprites (Apocalypse HUD + Modern Menus) ---
	"ui_wheel_socket": preload(SY + "ui/wheel_socket.png"),
	"ui_bar_frame": preload(SY + "ui/bar_frame.png"),
	"ui_dial_fuel": preload(SY + "ui/dial_fuel.png"),
	"ui_panel": preload(SY + "ui/panel.png"),
	"ui_key_blank": preload(SY + "ui/key_blank.png"),
	"ui_pad_x": preload(SY + "ui/pad_x.png"),
	"ui_pad_y": preload(SY + "ui/pad_y.png"),
	"ui_pad_b": preload(SY + "ui/pad_b.png"),
	"ui_pad_back": preload(SY + "ui/pad_back.png"),
	"ui_menu_button": preload(SY + "ui/menu_button.png"),
	"ui_menu_button_sel": preload(SY + "ui/menu_button_sel.png"),
	# --- Kenney CC0 (ground tiles, projectiles, FX) ---
	"grass": preload(KN + "grass.png"),
	"dirt": preload(KN + "dirt.png"),
	"sand": preload(KN + "sand.png"),
	"bullet": preload(KN + "bullet.png"),
	"enemy_bullet": preload(KN + "enemy_bullet.png"),
	"grenade": preload(KN + "grenade.png"),
	"explosion0": preload(KN + "explosion0.png"),
	"explosion1": preload(KN + "explosion1.png"),
	"explosion2": preload(KN + "explosion2.png"),
	"explosion3": preload(KN + "explosion3.png"),
	"smoke": preload(KN + "smoke.png"),
}

## Per-sprite draw multiplier so a legacy art bake lands at the Kenney footprint the
## main.gd scale numbers were tuned for. Absent = 1.0.
const SCALE := {
	"player1": 0.81, "player2": 0.77, "rusher": 0.77, "elite": 0.77,
	"frogman": 0.77, "observer": 0.77,
	"tank_body": 0.72, "tank_barrel": 0.69,
	"gunship_body": 0.67, "colossus_body": 0.59,
	"sandbag": 0.83, "sandbag_beige": 0.83,
	"crate_ammo": 0.86, "crate_grenade": 0.86, "crate_airstrike": 0.86,
	"tree_large": 0.89, "tree_small": 0.91, "fern": 0.9,
}

## Desert→jungle shift, multiplied onto the draw modulate. Units/vehicles take
## a darker olive-drab so they read against the bright jungle ground (with the
## outline below); foliage deepens green. Absent = white.
const UNIT := Color(0.85, 0.81, 0.58)
const OLIVE_VEH := Color(0.76, 0.85, 0.52)
const FOLIAGE := Color(0.82, 1.0, 0.66)
const TINT := {
	"player1": Color(0.80, 0.87, 0.62), "player2": Color(0.88, 0.78, 0.5),
	"rusher": UNIT, "elite": UNIT, "frogman": UNIT, "observer": UNIT,
	"tank_body": OLIVE_VEH, "tank_barrel": OLIVE_VEH,
	"gunship_body": OLIVE_VEH, "colossus_body": OLIVE_VEH,
	"sandbag": Color(0.82, 0.88, 0.62), "sandbag_beige": Color(0.88, 0.92, 0.66),
	"crate_ammo": Color(0.82, 0.88, 0.62), "crate_grenade": Color(0.82, 0.88, 0.62),
	"crate_airstrike": Color(0.82, 0.88, 0.62),
	"tree_large": FOLIAGE, "tree_small": FOLIAGE, "fern": FOLIAGE,
}

## Sprites that get a 1px dark outline in _spr() for readability on any ground.
const OUTLINE := {
	"player1": true, "player2": true, "rusher": true, "elite": true,
	"frogman": true, "observer": true,
	"tank_body": true, "tank_barrel": true, "gunship_body": true,
	"colossus_body": true, "sandbag": true, "sandbag_beige": true,
	"crate_ammo": true, "crate_grenade": true, "crate_airstrike": true,
}


static func tex(name: String) -> Texture2D:
	return TEX[name]


static func draw_scale(name: String) -> float:
	return SCALE.get(name, 1.0)


static func tint(name: String) -> Color:
	return TINT.get(name, Color.WHITE)


static func outlined(name: String) -> bool:
	return OUTLINE.has(name)


## Input-prompt glyphs: pad button art when a gamepad is connected, else a
## blank keycap stamped with the key letter. Draws centered at pos.
const _GLYPH_PAD := {"interact": "ui_pad_x", "revive": "ui_pad_y",
	"roll": "ui_pad_b", "wheel": "ui_pad_back"}
const _GLYPH_KEY := {"interact": "F", "revive": "E", "roll": "C", "wheel": "Q"}


static func draw_glyph(ci: CanvasItem, action: String, pos: Vector2, size := 12.0) -> void:
	var rect := Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size))
	if Input.get_connected_joypads().size() > 0:
		ci.draw_texture_rect(tex(_GLYPH_PAD[action]), rect, false)
	else:
		ci.draw_texture_rect(tex("ui_key_blank"), rect, false, Color(0.96, 0.95, 0.88))
		var letter: String = _GLYPH_KEY[action]
		var f := ThemeDB.fallback_font
		var fs := int(size * 0.62)
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, pos + Vector2(-w / 2.0, size * 0.24), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.16, 0.12))


static func cell_hash(ix: int, iy: int) -> int:
	## Cheap deterministic decor hash (view-only; not the sim RNG).
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
