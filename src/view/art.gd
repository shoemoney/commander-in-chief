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
	# Cast v2: heroes are regular army (Leader + Soldier_Female), hostiles
	# are the Insurgent faction — different silhouettes, different wardrobe.
	"player1": preload(SY + "cast2/hero1.png"),
	"player2": preload(SY + "cast2/hero2.png"),
	"rusher": preload(SY + "cast2/insurgent1.png"),
	"elite": preload(SY + "cast2/insurgent2.png"),
	"frogman": preload(SY + "frogman.png"),
	"observer": preload(SY + "cast2/observer2.png"),
	"bunker": preload(SY + "cast2/bunker.png"),
	"trophy": preload(SY + "cast2/trophy.png"),
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
	"ui_reticle": preload(SY + "ui/reticle.png"),
	"ui_vignette": preload(SY + "ui/vignette.png"),
	# --- legacy art Military decor (war-torn battlefield litter) ---
	"barrel": preload(SY + "decor/barrel.png"),
	"crate_stack": preload(SY + "decor/crate_stack.png"),
	"rock1": preload(SY + "decor/rock1.png"),
	"rock2": preload(SY + "decor/rock2.png"),
	"wreck": preload(SY + "decor/wreck.png"),
	"tent": preload(SY + "decor/tent.png"),
	"watchtower": preload(SY + "decor/watchtower.png"),
	"barbedwire": preload(SY + "decor/barbedwire.png"),
	"barrier": preload(SY + "decor/barrier.png"),
	"ammobox": preload(SY + "decor/ammobox.png"),
	"landmine": preload(SY + "decor/landmine.png"),
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
	# cast2 bakes use a 300px canvas. Enemies run LARGER than the strict
	# old-footprint math: at ~7px the dark insurgents read as "black dots,
	# or is that a bullet?" — straight from playtest.
	# Sizes per the 1986-anchor readability pass: heroes ~18px on screen,
	# elites largest infantry (they shoot), sprites ≥3× bullet size.
	"player1": 0.50, "player2": 0.42, "rusher": 0.47, "elite": 0.52,
	"frogman": 1.05, "observer": 0.24, "bunker": 0.17,
	"tank_body": 0.72, "tank_barrel": 0.69,
	"gunship_body": 0.67, "colossus_body": 0.59,
	"sandbag": 0.83, "sandbag_beige": 0.83,
	"crate_ammo": 0.86, "crate_grenade": 0.86, "crate_airstrike": 0.86,
	"tree_large": 0.89, "tree_small": 0.91, "fern": 0.9,
	# Decor litter — folded to modest on-screen footprints (call _spr at 1.0).
	"barrel": 0.11, "crate_stack": 0.13, "rock1": 0.13, "rock2": 0.14,
	"wreck": 0.17, "tent": 0.19, "watchtower": 0.16, "barbedwire": 0.16,
	"barrier": 0.13, "ammobox": 0.1, "landmine": 0.07,
}

## Desert→jungle shift, multiplied onto the draw modulate. Units/vehicles take
## a darker olive-drab so they read against the bright jungle ground (with the
## outline below); foliage deepens green. Absent = white.
const UNIT := Color(0.85, 0.81, 0.58)
const OLIVE_VEH := Color(0.76, 0.85, 0.52)
const FOLIAGE := Color(0.82, 1.0, 0.66)
const TINT := {
	# Heroes render bright, not olive-washed — the tan Leader model in the
	# old jungle tint was literal camouflage (invisible on grass).
	"player1": Color(1.1, 1.12, 0.95), "player2": Color(1.18, 1.05, 0.85),
	# Insurgents run BRIGHT and WARM so they read as threats — not as the
	# grey decor rocks, not as the red enemy orbs. Threats pop, scenery
	# recedes (see decor tints below).
	"rusher": Color(2.1, 1.7, 1.15), "elite": Color(1.75, 0.85, 0.68),
	"frogman": UNIT, "observer": Color(1.6, 1.2, 1.0),
	"bunker": Color(1.0, 0.95, 0.82),
	"tank_body": OLIVE_VEH, "tank_barrel": OLIVE_VEH,
	"gunship_body": OLIVE_VEH, "colossus_body": OLIVE_VEH,
	"sandbag": Color(0.82, 0.88, 0.62), "sandbag_beige": Color(0.88, 0.92, 0.66),
	"crate_ammo": Color(0.82, 0.88, 0.62), "crate_grenade": Color(0.82, 0.88, 0.62),
	"crate_airstrike": Color(0.82, 0.88, 0.62),
	"tree_large": FOLIAGE, "tree_small": FOLIAGE, "fern": FOLIAGE,
	# Decor is SCENERY — muted and mossy so it recedes into the terrain and
	# never competes with the warm-bright enemies for the player's eye.
	"barrel": Color(0.72, 0.8, 0.6), "crate_stack": Color(0.78, 0.76, 0.62),
	"rock1": Color(0.68, 0.76, 0.62), "rock2": Color(0.68, 0.76, 0.62),
	"wreck": Color(0.62, 0.66, 0.58), "tent": Color(0.72, 0.82, 0.6),
	"watchtower": Color(0.72, 0.78, 0.62), "barbedwire": Color(0.7, 0.74, 0.68),
	"barrier": Color(0.76, 0.76, 0.62), "ammobox": Color(0.72, 0.8, 0.58),
	"landmine": Color(0.7, 0.72, 0.62),
}

## Sprites that get a 1px dark outline in _spr() for readability on any ground.
const OUTLINE := {
	"player1": true, "player2": true, "rusher": true, "elite": true,
	"frogman": true, "observer": true, "bunker": true,
	"tank_body": true, "tank_barrel": true, "gunship_body": true,
	"colossus_body": true, "sandbag": true, "sandbag_beige": true,
	"crate_ammo": true, "crate_grenade": true, "crate_airstrike": true,
	"barrel": true, "crate_stack": true, "rock1": true, "rock2": true,
	"wreck": true, "watchtower": true, "barrier": true, "ammobox": true,
}


static func tex(name: String) -> Texture2D:
	return TEX[name]


static func draw_scale(name: String) -> float:
	return SCALE.get(name, 1.0)


static func tint(name: String) -> Color:
	return TINT.get(name, Color.WHITE)


static func outlined(name: String) -> bool:
	return OUTLINE.has(name)


## Input-prompt glyphs: pad button art when the pad is the LAST-USED device,
## else a blank keycap stamped with the key letter. `use_pad` is driven from
## main by the last InputEvent class — a merely-connected idle pad no longer
## mis-teaches a keyboard player pad buttons. Draws centered at pos.
static var use_pad := false
const _GLYPH_PAD := {"interact": "ui_pad_x", "revive": "ui_pad_y",
	"roll": "ui_pad_b", "wheel": "ui_pad_back"}
const _GLYPH_KEY := {"interact": "F", "revive": "E", "roll": "C", "wheel": "Q"}


static func draw_glyph(ci: CanvasItem, action: String, pos: Vector2, size := 12.0) -> void:
	var rect := Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size))
	if use_pad:
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
