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
	# Apocalypse HUD sprites (imported 2D kit, assets/legacy-art/hud/).
	"hud_star": preload(SY + "hud/ICON_Map_Star.png"),
	"hud_flag": preload(SY + "hud/ICON_Map_Flag.png"),
	"hud_skull": preload(SY + "hud/ICON_Map_Skull.png"),
	"hud_target": preload(SY + "hud/ICON_Map_Target.png"),
	"hud_gunshop": preload(SY + "hud/ICON_Map_GunShop.png"),
	"hud_vehicle": preload(SY + "hud/ICON_Map_Vehicle.png"),
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
	# Apocalypse HUD screen-space combat-feedback cards.
	"hudfx_hitlines": preload(SY + "hud/hudfx_hitlines.png"),
	"hudfx_blood": preload(SY + "hud/hudfx_blood.png"),
	"hudfx_dmgvig": preload(SY + "hud/hudfx_dmgvig.png"),
	"hudfx_glow": preload(SY + "hud/hudfx_glow.png"),
	"hudfx_dmgdir": preload(SY + "hud/hudfx_dmgdir.png"),
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
	# --- legacy 3D pack Particle FX (2D textures, assets/legacy-art/fx/) ---
	"fx_bullettrail": preload(SY + "fx/fx_bullettrail.png"),
	"fx_smoke": preload(SY + "fx/fx_smoke_01.png"),
	"fx_fumes": preload(SY + "fx/fx_fumes_02.png"),
	"fx_ring": preload(SY + "fx/fx_ring_02.png"),
	"fx_circle": preload(SY + "fx/fx_circle_01.png"),
	"fx_disc": preload(SY + "fx/fx_circle_02.png"),
	"fx_lightning": preload(SY + "fx/fx_lightning_02.png"),
	"fx_groundbreak": preload(SY + "fx/fx_groundbreak.png"),
	"fx_shell": preload(SY + "fx/fx_shell_01.png"),
	"fx_sparkle": preload(SY + "fx/fx_sparkle.png"),
	"fx_swipe": preload(SY + "fx/fx_swipe_01.png"),
	"fx_softspot": preload(SY + "fx/fx_soft_spot.png"),
	"fx_shadow": preload(SY + "fx/fx_shadow.png"),
	"fx_impactdark": preload(SY + "fx/fx_impactdark.png"),
	"fx_wind": preload(SY + "fx/fx_wind.png"),
	"fx_fumes4": preload(SY + "fx/fx_fumes4.png"),
	"fx_halfcircle": preload(SY + "fx/fx_halfcircle.png"),
	"fx_swipe2": preload(SY + "fx/fx_swipe2.png"),
	# --- POLYGON Military mil2 bake (enemies, vehicles, weapon pickups, items) ---
	"m_bombsuit": preload(SY + "mil2/bombsuit.png"),
	"m_contractor2": preload(SY + "mil2/contractor2.png"),
	"m_insurgent3": preload(SY + "mil2/insurgent3.png"),
	"m_insurgent4": preload(SY + "mil2/insurgent4.png"),
	"m_insurgent5": preload(SY + "mil2/insurgent5.png"),
	"m_pilot": preload(SY + "mil2/pilot.png"),
	"m_soldier2": preload(SY + "mil2/soldier2.png"),
	"m_apc": preload(SY + "mil2/apc.png"),
	"m_radar_tank": preload(SY + "mil2/radar_tank.png"),
	"m_rocket_truck": preload(SY + "mil2/rocket_truck.png"),
	"m_jet": preload(SY + "mil2/jet.png"),
	"m_heli_transport": preload(SY + "mil2/heli_transport.png"),
	"m_heli_attack2": preload(SY + "mil2/heli_attack2.png"),
	"m_drone": preload(SY + "mil2/drone.png"),
	"m_light_tank": preload(SY + "mil2/light_tank.png"),
	"m_technical": preload(SY + "mil2/technical.png"),
	# Wreck variants: same vehicle art, but muted/small/outlined for battlefield
	# litter (see SCALE/TINT below) — dead hulks, not live vehicles.
	"wreck_apc": preload(SY + "mil2/apc.png"),
	"wreck_technical": preload(SY + "mil2/technical.png"),
	"wreck_light_tank": preload(SY + "mil2/light_tank.png"),
	"wep_grenade": preload(SY + "mil2/wep_grenade.png"),
	"wep_rpg": preload(SY + "mil2/wep_rpg.png"),
	"wep_shotgun": preload(SY + "mil2/wep_shotgun.png"),
	"wep_rifle": preload(SY + "mil2/wep_rifle.png"),
	"wep_mg": preload(SY + "mil2/wep_mg.png"),
	"wep_pistol": preload(SY + "mil2/wep_pistol.png"),
	"wep_claymore": preload(SY + "mil2/wep_claymore.png"),
	"wep_smoke": preload(SY + "mil2/wep_smoke.png"),
	"wep_flashbang": preload(SY + "mil2/wep_flashbang.png"),
	"item_bullet": preload(SY + "mil2/item_bullet.png"),
	"item_bullet_shotgun": preload(SY + "mil2/item_bullet_shotgun.png"),
	"item_binoculars": preload(SY + "mil2/item_binoculars.png"),
}

## Per-sprite draw multiplier so a legacy art bake lands at the Kenney footprint the
## main.gd scale numbers were tuned for. Absent = 1.0.
const SCALE := {
	# legacy art Particle_FX cards are large (fx_smoke_01 is 200px vs Kenney smoke.png's
	# 92px), so scale down to keep the same on-screen puff footprint.
	"fx_smoke": 0.46,
	# cast2 bakes use a 300px canvas. Enemies run LARGER than the strict
	# old-footprint math: at ~7px the dark insurgents read as "black dots,
	# or is that a bullet?" — straight from playtest.
	# Sizes per the 1986-anchor readability pass: heroes ~18px on screen,
	# elites largest infantry (they shoot), sprites ≥3× bullet size.
	"player1": 0.50, "player2": 0.42, "rusher": 0.47, "elite": 0.52,
	"frogman": 1.05, "observer": 0.24, "bunker": 0.17,
	"tank_body": 0.72, "tank_barrel": 0.69,
	"gunship_body": 0.67, "colossus_body": 0.59,
	"sandbag_beige": 0.83,
	"crate_ammo": 0.86, "crate_grenade": 0.86, "crate_airstrike": 0.86,
	"tree_large": 0.89, "tree_small": 0.91, "fern": 0.9,
	# Decor litter — folded to modest on-screen footprints (call _spr at 1.0).
	"barrel": 0.11, "crate_stack": 0.13, "rock1": 0.13, "rock2": 0.14,
	"wreck": 0.17, "tent": 0.19, "watchtower": 0.16, "barbedwire": 0.16,
	"barrier": 0.13, "ammobox": 0.1, "landmine": 0.07,
	# mil2: characters ~unit size, vehicles ~tank size, weapons/items small pickups
	"m_bombsuit": 0.5, "m_contractor2": 0.5, "m_insurgent3": 0.47, "m_insurgent4": 0.47,
	"m_insurgent5": 0.47, "m_pilot": 0.46, "m_soldier2": 0.5,
	"m_apc": 0.7, "m_radar_tank": 0.72, "m_rocket_truck": 0.72, "m_jet": 0.62,
	"m_heli_transport": 0.68, "m_heli_attack2": 0.67, "m_drone": 0.34, "m_light_tank": 0.6,
	"m_technical": 0.6,
	"wreck_apc": 0.3, "wreck_technical": 0.28, "wreck_light_tank": 0.28,
	"wep_grenade": 0.34, "wep_rpg": 0.4, "wep_shotgun": 0.4, "wep_rifle": 0.4, "wep_mg": 0.4,
	"wep_pistol": 0.32, "wep_claymore": 0.3, "wep_smoke": 0.32, "wep_flashbang": 0.3,
	"item_bullet": 0.32, "item_bullet_shotgun": 0.32, "item_binoculars": 0.34,
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
	"sandbag_beige": Color(0.88, 0.92, 0.66),
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
	# mil2 enemies read warm/bright (threats); vehicles olive-drab; pickups bright.
	"m_bombsuit": Color(1.7, 1.35, 0.9), "m_contractor2": Color(1.75, 0.85, 0.68),
	"m_insurgent3": Color(2.1, 1.7, 1.15), "m_insurgent4": Color(2.1, 1.7, 1.15),
	"m_insurgent5": Color(2.1, 1.7, 1.15), "m_pilot": Color(1.5, 1.2, 1.0),
	"m_soldier2": Color(1.1, 1.12, 0.95),
	"m_apc": OLIVE_VEH, "m_radar_tank": OLIVE_VEH, "m_rocket_truck": OLIVE_VEH,
	"m_jet": OLIVE_VEH, "m_heli_transport": OLIVE_VEH, "m_heli_attack2": OLIVE_VEH,
	"m_drone": Color(1.2, 1.3, 1.4), "m_light_tank": OLIVE_VEH, "m_technical": OLIVE_VEH,
	"wreck_apc": Color(0.55, 0.58, 0.52), "wreck_technical": Color(0.55, 0.58, 0.52),
	"wreck_light_tank": Color(0.55, 0.58, 0.52),
	"wep_grenade": Color(1.1, 1.15, 0.95), "wep_rpg": Color(1.15, 1.05, 0.9),
	"wep_shotgun": Color(1.1, 1.1, 1.0), "wep_rifle": Color(1.1, 1.1, 1.0),
	"wep_mg": Color(1.1, 1.1, 1.0), "wep_pistol": Color(1.1, 1.1, 1.0),
	"wep_claymore": Color(1.1, 1.1, 0.95), "wep_smoke": Color(1.05, 1.1, 1.1),
	"wep_flashbang": Color(1.1, 1.1, 1.0),
	"item_bullet": Color(1.3, 1.2, 0.9), "item_bullet_shotgun": Color(1.3, 1.2, 0.9),
	"item_binoculars": Color(1.15, 1.2, 1.1),
}

## Sprites that get a 1px dark outline in _spr() for readability on any ground.
const OUTLINE := {
	"player1": true, "player2": true, "rusher": true, "elite": true,
	"frogman": true, "observer": true, "bunker": true,
	"tank_body": true, "tank_barrel": true, "gunship_body": true,
	"colossus_body": true, "sandbag_beige": true,
	"crate_ammo": true, "crate_grenade": true, "crate_airstrike": true,
	"barrel": true, "crate_stack": true, "rock1": true, "rock2": true,
	"wreck": true, "watchtower": true, "barrier": true, "ammobox": true,
	"m_bombsuit": true, "m_contractor2": true, "m_insurgent3": true, "m_insurgent4": true,
	"m_insurgent5": true, "m_pilot": true, "m_soldier2": true,
	"m_apc": true, "m_radar_tank": true, "m_rocket_truck": true, "m_jet": true,
	"m_heli_transport": true, "m_heli_attack2": true, "m_drone": true, "m_light_tank": true,
	"m_technical": true, "wreck_apc": true, "wreck_technical": true, "wreck_light_tank": true,
	"wep_grenade": true, "wep_rpg": true, "wep_shotgun": true,
	"wep_rifle": true, "wep_mg": true, "item_bullet": true, "item_bullet_shotgun": true,
}

const _GLYPH_PAD := {"interact": "ui_pad_x", "revive": "ui_pad_y",
	"roll": "ui_pad_b", "wheel": "ui_pad_back"}
const _GLYPH_KEY := {"interact": "F", "revive": "E", "roll": "C", "wheel": "Q"}


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
## Deuteran-safe remap: 'affordable/safe/open' greens become cyan-blue when
## colorblind mode is on (red↔blue is distinguishable where red↔green isn't).
## Reds are left alone. Driven from main.
static var colorblind := false


static func safe(green: Color) -> Color:
	if not colorblind:
		return green
	return Color(0.35, 0.75, 1.0, green.a)


## Shared view-clock helpers — one source for the sine-pulse and square-blink
## expressions that were retyped ~10× across main.gd/hud.gd.
static func pulse(rate: float) -> float:
	return 0.5 + 0.5 * sin(float(Engine.get_physics_frames()) * rate)


static func blink(period: int) -> bool:
	return (Engine.get_physics_frames() / period) % 2 == 0


## Cached fallback font — ThemeDB.fallback_font was being re-fetched at every
## call site; fetch once and hand back the same Font resource.
static var _font: Font = null


static func font() -> Font:
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font


## Shadowed text: black copy offset +1px, then the colored text on top — the
## drop-shadow pattern hand-inlined across the view, now in one place.
## max_w > 0 clips the string to that width instead of letting it bleed past the bound.
static func text(ci: CanvasItem, txt: String, pos: Vector2, size: int, col: Color, max_w := 0.0) -> void:
	var f := font()
	var w := max_w if max_w > 0.0 else -1.0
	var flags := TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_KASHIDA
	ci.draw_string(f, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, Color(0, 0, 0, 0.7), flags)
	ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, col, flags)


## Same shadow+color text, horizontally centered on cx at y.
static func text_center(ci: CanvasItem, txt: String, cx: float, y: float, size: int, col: Color, max_w := 0.0) -> void:
	var w := font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0:
		w = minf(w, max_w)
	text(ci, txt, Vector2(cx - w / 2.0, y), size, col, max_w)


static func draw_glyph(ci: CanvasItem, action: String, pos: Vector2, size := 12.0) -> void:
	var rect := Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size))
	if use_pad:
		ci.draw_texture_rect(tex(_GLYPH_PAD[action]), rect, false)
	else:
		ci.draw_texture_rect(tex("ui_key_blank"), rect, false, Color(0.96, 0.95, 0.88))
		var letter: String = _GLYPH_KEY[action]
		var f := font()
		var fs := int(size * 0.62)
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, pos + Vector2(-w / 2.0, size * 0.24), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.16, 0.12))


static func cell_hash(ix: int, iy: int) -> int:
	## Cheap deterministic decor hash (view-only; not the sim RNG).
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
