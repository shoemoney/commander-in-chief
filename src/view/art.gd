class_name Art
extends RefCounted
## Sprite registry for the view. Units/vehicles/props are top-down renders of
## legacy 3D pack Military 3D models, baked to sprites by tools/bake_sprites.gd
## (see assets/legacy-art/). Ground tiles, projectiles and FX remain Kenney CC0
## (kenney.nl). POLYGON_Nature DOES ship tiling terrain PNGs (vendor
## Ground_Textures/: Grass, Mud, Sand + normals) — swapping the ground is
## parked on an art-direction call: painterly terrain vs the pixel-integer
## look. View-layer only; the sim never touches textures.
##
## VERIFIED non-fits (asset loops: skip): City/Nightclubs/Heist/Gang_Warfare/
## Spy_Kit/Racer are off-theme (urban/neon) for this jungle war; War_Map is WWI
## tabletop props; no owned pack ships audio (all SFX/music stay synthesized).
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
	# Referenced nowhere (bake tools only write the PNGs) — commented out like
	# hudfx_glow/hudfx_dmgdir above: ~270KB of boot VRAM for zero drawn pixels.
	#"icon_fuel": preload(SY + "icons/icon_fuel.png"),
	"icon_vest": preload(SY + "icons/icon_vest.png"),
	"icon_skull": preload(SY + "icons/icon_skull.png"),
	"icon_medal": preload(SY + "icons/icon_medal.png"),
	"icon_airstrike": preload(SY + "icons/icon_airstrike.png"),
	"icon_rend": preload(SY + "icons/icon_rend.png"),  # 64px canvas (siblings 128) — drawn scaled
	# Apocalypse HUD sprites (imported 2D kit, assets/legacy-art/hud/).
	"hud_star": preload(SY + "hud/ICON_Map_Star.png"),
	"hud_flag": preload(SY + "hud/ICON_Map_Flag.png"),
	"hud_skull": preload(SY + "hud/ICON_Map_Skull.png"),
	"hud_target": preload(SY + "hud/ICON_Map_Target.png"),
	"hud_gunshop": preload(SY + "hud/ICON_Map_GunShop.png"),
	"hud_vehicle": preload(SY + "hud/ICON_Map_Vehicle.png"),
	"hud_lightning": preload(SY + "hud/ICON_Map_Lightning.png"),
	"hud_fire": preload(SY + "hud/ICON_Map_Fire.png"),
	"hud_radiation": preload(SY + "hud/ICON_Map_Radiation.png"),
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
	# Weapon-state reticle silhouettes (Apocalypse HUD) — pierce/spread stop being
	# hue-only signals (protan-safe). Bracket_Sml is byte-identical to ui_reticle,
	# so the default keeps its file; these two are genuinely different shapes.
	"ui_ret_spread": preload(SY + "hud/SPR_HUD_Reticle_Bracket_Shotgun.png"),  # 128x256 — draw at half width
	"ui_ret_pierce": preload(SY + "hud/SPR_HUD_Reticle_Circle_Med.png"),
	"ui_vignette": preload(SY + "ui/vignette.png"),
	# Apocalypse HUD screen-space combat-feedback cards.
	"hudfx_hitlines": preload(SY + "hud/hudfx_hitlines.png"),
	"hudfx_blood": preload(SY + "hud/hudfx_blood.png"),
	"hudfx_dmgvig": preload(SY + "hud/hudfx_dmgvig.png"),
	# hudfx_glow / hudfx_dmgdir: preloaded here for months, referenced nowhere —
	# ~0.7 MB of VRAM at boot for zero drawn pixels. Files stay for when a
	# damage-direction or glow pass actually wants them.
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
	#"landmine": preload(SY + "decor/landmine.png"),
	# Terrain/skyline set (War FBX bakes). Bridges are grey concrete terrain,
	# skyline pieces are horizon silhouettes (side views, drawn dark, no outline).
	"bridge_mid": preload(SY + "decor/bridge_mid.png"),
	"bridge_ramp": preload(SY + "decor/bridge_ramp.png"),
	"skyline_chimney": preload(SY + "decor/skyline_chimney.png"),
	"skyline_mast": preload(SY + "decor/skyline_mast.png"),
	"crater": preload(SY + "decor/crater.png"),
	# --- POLYGON War / War_Map / Nature FBX bakes (p4 asset pass, forced-atlas) ---
	"tank_trap": preload(SY + "decor/tank_trap.png"),
	"barricade": preload(SY + "decor/barricade.png"),
	"flak_gun": preload(SY + "decor/flak_gun.png"),
	"trench": preload(SY + "decor/trench.png"),
	"flag_marker": preload(SY + "decor/flag_marker.png"),
	"radio_tower": preload(SY + "decor/radio_tower.png"),
	"hedge": preload(SY + "decor/hedge.png"),
	"fern2": preload(SY + "decor/fern2.png"),
	"wreck_halftrack": preload(SY + "decor/wreck_halftrack.png"),
	"crater_field": preload(SY + "decor/crater_field.png"),
	"crater_water": preload(SY + "decor/crater_water.png"),
	"mg_tripod": preload(SY + "decor/mg_tripod.png"),
	# BattleRoyale bakes repurposed as battlefield litter (a dropped riot shield
	# + a fallen soldier body) — the live shield enemy keeps its on-theme bombsuit.
	"dropped_shield": preload(SY + "decor/dropped_shield.png"),
	"fallen_merc": preload(SY + "decor/fallen_merc.png"),
	# Apocalypse-HUD capsule pickup glyphs (clean UI-icon set): each power-up
	# capsule floats its own icon (mine for claymore, smoke-grenade for smoke, …).
	"cap_pierce": preload(SY + "icons/cap_pierce.png"),
	"cap_spread": preload(SY + "icons/cap_spread.png"),
	"cap_triple": preload(SY + "icons/cap_triple.png"),
	"cap_rend": preload(SY + "icons/cap_rend.png"),
	"cap_claymore": preload(SY + "icons/cap_claymore.png"),
	"cap_smoke": preload(SY + "icons/cap_smoke.png"),
	"cap_flash": preload(SY + "icons/cap_flash.png"),
	# --- Kenney CC0 (ground tiles, projectiles, FX) ---
	"grass": preload(KN + "grass.png"),
	"dirt": preload(KN + "dirt.png"),
	"sand": preload(KN + "sand.png"),
	# bullet/enemy_bullet/grenade/smoke: Kenney keys RETIRED (files kept) — every
	# live draw site moved on long ago: player rounds are procedural tracers +
	# fx_bullettrail streaks, enemy fire is the red-streak orb, thrown frags wear
	# the wep_grenade bake (AP shells tank_shell), and every smoke puff draws
	# fx_smoke. Dead preloads cost VRAM and mislead asset audits; skip in loops.
	# Explosion frames: VERIFIED vendor non-match (no owned pack ships explosion
	# art — Particle_FX is crystals/trails/rings). Keep Kenney; skip in asset loops.
	"explosion0": preload(KN + "explosion0.png"),
	"explosion1": preload(KN + "explosion1.png"),
	"explosion2": preload(KN + "explosion2.png"),
	"explosion3": preload(KN + "explosion3.png"),
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
	#"fx_halfcircle": preload(SY + "fx/fx_halfcircle.png"),  # 175KB, never drawn
	"fx_swipe2": preload(SY + "fx/fx_swipe2.png"),
	# Semicircle flash card (512x256, flat edge at BOTTOM — orient flat edge to muzzle).
	"fx_muzzle_fan": preload(SY + "fx/fx_muzzle_fan.png"),
	# --- POLYGON Military mil2 bake (enemies, vehicles, weapon pickups, items) ---
	"m_bombsuit": preload(SY + "mil2/bombsuit.png"),
	"m_contractor2": preload(SY + "mil2/contractor2.png"),
	"m_insurgent3": preload(SY + "mil2/insurgent3.png"),
	"m_insurgent4": preload(SY + "mil2/insurgent4.png"),
	"m_insurgent5": preload(SY + "mil2/insurgent5.png"),
	"m_pilot": preload(SY + "mil2/pilot.png"),
	"m_soldier2": preload(SY + "mil2/soldier2.png"),
	#"m_apc": preload(SY + "mil2/apc.png"),
	"m_radar_tank": preload(SY + "mil2/radar_tank.png"),
	"m_rocket_truck": preload(SY + "mil2/rocket_truck.png"),
	"m_jet": preload(SY + "mil2/jet.png"),
	"m_heli_transport": preload(SY + "mil2/heli_transport.png"),
	"m_heli_attack2": preload(SY + "mil2/heli_attack2.png"),
	"m_drone": preload(SY + "mil2/drone.png"),
	#"m_light_tank": preload(SY + "mil2/light_tank.png"),
	"m_technical": preload(SY + "mil2/technical.png"),
	# Wreck variants: same vehicle art, but muted/small/outlined for battlefield
	# litter (see SCALE/TINT below) — dead hulks, not live vehicles.
	"wreck_apc": preload(SY + "mil2/apc.png"),
	"wreck_technical": preload(SY + "mil2/technical.png"),
	"wreck_light_tank": preload(SY + "mil2/light_tank.png"),
	"wep_grenade": preload(SY + "mil2/wep_grenade.png"),
	#"wep_rpg": preload(SY + "mil2/wep_rpg.png"),
	"wep_shotgun": preload(SY + "mil2/wep_shotgun.png"),
	"wep_rifle": preload(SY + "mil2/wep_rifle.png"),
	"wep_mg": preload(SY + "mil2/wep_mg.png"),
	#"wep_pistol": preload(SY + "mil2/wep_pistol.png"),
	"wep_claymore": preload(SY + "mil2/wep_claymore.png"),
	"wep_smoke": preload(SY + "mil2/wep_smoke.png"),
	"wep_flashbang": preload(SY + "mil2/wep_flashbang.png"),
	"item_bullet": preload(SY + "mil2/item_bullet.png"),
	"item_bullet_shotgun": preload(SY + "mil2/item_bullet_shotgun.png"),
	"item_binoculars": preload(SY + "mil2/item_binoculars.png"),
	# MG emplacement (barrel points screen-up at rotation 0; ammo box on left).
	"mg_stand": preload(SY + "mil2/mg_stand.png"),
	# --- POLYGON Military/Battle Royale p2 bake (specialists, hulks, litter) ---
	"ghillie": preload(SY + "p2/ghillie.png"),
	"courier": preload(SY + "p2/courier.png"),
	"sapper": preload(SY + "p2/sapper.png"),
	"tank_shell": preload(SY + "p2/tank_shell.png"),
	"pickup_vest": preload(SY + "p2/pickup_vest.png"),
	"tank_hulk": preload(SY + "p2/tank_hulk.png"),
	"tree_dead1": preload(SY + "p2/tree_dead1.png"),
	"tree_dead2": preload(SY + "p2/tree_dead2.png"),
	"tree_dead3": preload(SY + "p2/tree_dead3.png"),
	"wall_sandbag": preload(SY + "p2/wall_sandbag.png"),
	"wall_sandbag_end": preload(SY + "p2/wall_sandbag_end.png"),
	"bunker2": preload(SY + "p2/bunker2.png"),
	"corpse_soldier1": preload(SY + "p2/corpse_soldier1.png"),
	"corpse_soldier2": preload(SY + "p2/corpse_soldier2.png"),
	# Front face toward viewer, shield-top = image-up; rotate to carrier facing.
	"riot_shield": preload(SY + "p2/riot_shield.png"),
	"fx_flame": preload(SY + "p2/fx_flame.png"),
	"fx_bubble1": preload(SY + "fx/bubble1.png"),
	"fx_bubble2": preload(SY + "fx/bubble2.png"),
	# --- Apocalypse HUD input glyphs (device-aware prompts; see glyph_key) ---
	"glyph_pad_a": preload(SY + "ui/glyphs/pad_a.png"),
	"glyph_pad_start": preload(SY + "ui/glyphs/pad_start.png"),
	"glyph_rt": preload(SY + "ui/glyphs/pad_rt.png"),
	"glyph_lb": preload(SY + "ui/glyphs/pad_lb.png"),
	"glyph_dpad_lr": preload(SY + "ui/glyphs/dpad_lr.png"),
	"glyph_stick_l": preload(SY + "ui/glyphs/stick_l.png"),
	"glyph_stick_r": preload(SY + "ui/glyphs/stick_r.png"),
	"glyph_mouse_l": preload(SY + "ui/glyphs/mouse_l.png"),
	"glyph_mouse_r": preload(SY + "ui/glyphs/mouse_r.png"),
	"glyph_key_space": preload(SY + "ui/glyphs/key_space.png"),
	"glyph_key_enter": preload(SY + "ui/glyphs/key_enter.png"),
	"glyph_key_wide": preload(SY + "ui/glyphs/key_wide.png"),
	# Brand-correct pad sets (PlayStation / Switch), swapped in by pad_brand.
	# PS has no Share sprite in the pack — TouchPad stands in for JOY_BUTTON_BACK
	# (same vendor-gap class as Xbox's missing View button).
	"glyph_ps_a": preload(SY + "ui/glyphs/ps_a.png"),
	"glyph_ps_b": preload(SY + "ui/glyphs/ps_b.png"),
	"glyph_ps_x": preload(SY + "ui/glyphs/ps_x.png"),
	"glyph_ps_y": preload(SY + "ui/glyphs/ps_y.png"),
	"glyph_ps_start": preload(SY + "ui/glyphs/ps_start.png"),
	"glyph_ps_rt": preload(SY + "ui/glyphs/ps_rt.png"),
	"glyph_ps_lb": preload(SY + "ui/glyphs/ps_lb.png"),
	"glyph_ps_back": preload(SY + "ui/glyphs/ps_back.png"),
	"glyph_ps_dpad_lr": preload(SY + "ui/glyphs/ps_dpad_lr.png"),
	"glyph_sw_a": preload(SY + "ui/glyphs/sw_a.png"),
	"glyph_sw_b": preload(SY + "ui/glyphs/sw_b.png"),
	"glyph_sw_x": preload(SY + "ui/glyphs/sw_x.png"),
	"glyph_sw_y": preload(SY + "ui/glyphs/sw_y.png"),
	"glyph_sw_start": preload(SY + "ui/glyphs/sw_start.png"),
	"glyph_sw_rt": preload(SY + "ui/glyphs/sw_rt.png"),
	"glyph_sw_lb": preload(SY + "ui/glyphs/sw_lb.png"),
	"glyph_sw_back": preload(SY + "ui/glyphs/sw_back.png"),
	"glyph_sw_dpad_lr": preload(SY + "ui/glyphs/sw_dpad_lr.png"),
	# --- Modern Menus ortho icons (menu rows / toggles) ---
	"mi_snd_on": preload(SY + "ui/menuicons/snd_on.png"),
	"mi_snd_off": preload(SY + "ui/menuicons/snd_off.png"),
	"mi_mus_on": preload(SY + "ui/menuicons/mus_on.png"),
	"mi_mus_off": preload(SY + "ui/menuicons/mus_off.png"),
	"mi_trophy": preload(SY + "ui/menuicons/trophy.png"),
	"mi_book": preload(SY + "ui/menuicons/book.png"),
	"mi_play": preload(SY + "ui/menuicons/play.png"),
	"mi_controller": preload(SY + "ui/menuicons/controller.png"),
	#"mi_keyboard": preload(SY + "ui/menuicons/keyboard.png"),
	# Modern Menus batch 2 (256px, white with alpha — modulate for color).
	# NOTE: mi_controller.png also landed on disk but the "mi_controller" key
	# above already serves controller.png — kept as-is, duplicate art unregistered.
	"mi_arrow": preload(SY + "ui/menuicons/mi_arrow.png"),  # points RIGHT — flip/rotate at call site
	"mi_medal_1": preload(SY + "ui/menuicons/mi_medal_1.png"),
	"mi_medal_2": preload(SY + "ui/menuicons/mi_medal_2.png"),
	"mi_medal_3": preload(SY + "ui/menuicons/mi_medal_3.png"),
	"mi_medal_4": preload(SY + "ui/menuicons/mi_medal_4.png"),
	"mi_medal_5": preload(SY + "ui/menuicons/mi_medal_5.png"),
	"mi_settings": preload(SY + "ui/menuicons/mi_settings.png"),
	"mi_reload": preload(SY + "ui/menuicons/mi_reload.png"),
	"mi_home": preload(SY + "ui/menuicons/mi_home.png"),
	"mi_camera": preload(SY + "ui/menuicons/mi_camera.png"),
	"mi_back": preload(SY + "ui/menuicons/mi_back.png"),
	"mi_combat": preload(SY + "ui/menuicons/mi_combat.png"),
	"mi_timer": preload(SY + "ui/menuicons/mi_timer.png"),
	"mi_cancel": preload(SY + "ui/menuicons/mi_cancel.png"),
	# --- Apocalypse HUD chrome (tooltip plate, frames, wheel plate, cursor) ---
	"ui_tooltip": preload(SY + "hud/SPR_HUD_Tooltip.png"),
	"ui_frame_lrg": preload(SY + "hud/SPR_HUD_Frame_Lrg.png"),
	"ui_frame_lrg_under": preload(SY + "hud/SPR_HUD_Frame_Lrg_Underlay.png"),
	"ui_wheel_plate": preload(SY + "hud/SPR_Apocalypse_WeaponWheel.png"),
	"ui_cursor": preload(SY + "ui/cursor.png"),
	# Modern Menus 3-slice metal plate (L/C/R, 190x230 each; tile C horizontally).
	"plate_metal_l": preload(SY + "ui/plate_metal_l.png"),
	"plate_metal_c": preload(SY + "ui/plate_metal_c.png"),
	"plate_metal_r": preload(SY + "ui/plate_metal_r.png"),
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
	"player1": 0.56, "player2": 0.47, "rusher": 0.53, "elite": 0.58,
	"frogman": 1.05, "observer": 0.24, "bunker": 0.17,
	"tank_body": 0.72, "tank_barrel": 0.69,
	"gunship_body": 0.67, "colossus_body": 0.59,
	# Real barrel bakes replacing the 4x4 blanks: sized so the minigun sits
	# under the ~60px hull and the twin turrets under the ~143px colossus body
	# (main.gd draws them at 0.8 / 1.3). Tune visually.
	"gunship_barrel": 0.5, "colossus_barrel": 0.6,
	"sandbag_beige": 0.83,
	"crate_ammo": 0.86, "crate_grenade": 0.86, "crate_airstrike": 0.86,
	"tree_large": 0.89, "tree_small": 0.91, "fern": 0.9,
	# Decor litter — folded to modest on-screen footprints (call _spr at 1.0).
	"barrel": 0.11, "crate_stack": 0.13, "rock1": 0.13, "rock2": 0.14,
	"wreck": 0.17, "tent": 0.19, "watchtower": 0.16, "barbedwire": 0.16,
	"barrier": 0.13, "ammobox": 0.1, "landmine": 0.07,
	# Terrain set is baked big (160-220px) but drawn at 1.0 like the litter;
	# bridges fold to ~96px spans, crater ~48px, skyline to readable silhouettes
	# (mast is a 1.5%-opaque lattice — below ~60px tall it aliases away).
	"bridge_mid": 0.44, "bridge_ramp": 0.44, "crater": 0.3,
	# p4 War/War_Map/Nature props — folded to litter footprints (retuned by eye).
	"tank_trap": 0.14, "barricade": 0.15, "flak_gun": 0.16, "trench": 0.2,
	"flag_marker": 0.16, "radio_tower": 0.18, "hedge": 0.15, "fern2": 0.14,
	"wreck_halftrack": 0.3, "crater_field": 0.3, "crater_water": 0.3, "mg_tripod": 0.12,
	"dropped_shield": 0.12, "fallen_merc": 0.2,
	# capsule glyphs: large Apocalypse UI icons folded to pickup footprint
	# (weapons 512x256, explosives 1024²) — retuned by eye.
	"cap_pierce": 0.14, "cap_spread": 0.14, "cap_triple": 0.14, "cap_rend": 0.14,
	"cap_claymore": 0.06, "cap_smoke": 0.06, "cap_flash": 0.06,
	"skyline_chimney": 0.4, "skyline_mast": 0.4,   # bypassed — skyline draw site (main.gd) uses raw draw_texture_rect with its own rects
	# mil2: characters ~unit size, vehicles ~tank size, weapons/items small pickups
	"m_bombsuit": 0.56, "m_contractor2": 0.56, "m_insurgent3": 0.53, "m_insurgent4": 0.53,
	"m_insurgent5": 0.53, "m_pilot": 0.52, "m_soldier2": 0.56,
	"m_apc": 0.7, "m_radar_tank": 0.72, "m_rocket_truck": 0.72, "m_jet": 0.62,
	"m_heli_transport": 0.68, "m_heli_attack2": 0.67, "m_drone": 0.34, "m_light_tank": 0.6,
	"m_technical": 0.6,
	"wreck_apc": 0.3, "wreck_technical": 0.28, "wreck_light_tank": 0.28,
	"wep_grenade": 0.34, "wep_rpg": 0.4, "wep_shotgun": 0.4, "wep_rifle": 0.4, "wep_mg": 0.4,
	"wep_pistol": 0.32, "wep_claymore": 0.3, "wep_smoke": 0.32, "wep_flashbang": 0.3,
	"item_bullet": 0.32, "item_bullet_shotgun": 0.32, "item_binoculars": 0.34,
	"mg_stand": 0.3,   # 160px canvas → ~48px emplacement
	# p2: specialists match cast2 unit footprints (64px canvas vs cast2's 300px,
	# so raw multipliers run larger); litter/hulks fold to their swap targets.
	"ghillie": 2.45, "courier": 2.45, "sapper": 2.45,
	"tank_shell": 0.8,               # ~grenade footprint (26px)
	"pickup_vest": 0.86,             # ~crate_ammo (same 56px canvas)
	"tank_hulk": 0.72,               # ~tank_body (same 104px canvas)
	"tree_dead1": 0.89, "tree_dead2": 0.89, "tree_dead3": 0.89,   # ~tree_large
	"wall_sandbag": 0.28, "wall_sandbag_end": 0.55,   # fold to sandbag_beige's ~66px span
	"bunker2": 0.17,                 # ~bunker (same 440px canvas)
	"corpse_soldier1": 0.21, "corpse_soldier2": 0.21,   # 140px canvas → ~29px, litter class (1.0 drew a tank-sized corpse)
	"fx_flame": 0.46,                # 200px FX card, same norm as fx_smoke
	# _spr sizes off the IMPORTED texture, so size_limit changes must land here
	# too: bubbles import at 64px now (was 512) — 1.44 keeps the same ~92px FX
	# footprint the 512×0.18 original had (the 0.18 silently shrank them 8×).
	"fx_bubble1": 1.44, "fx_bubble2": 1.44,
	"fx_fumes": 4.0,   # 128px import (was 512-effective) → same _spr plume size
	"fx_muzzle_fan": 0.18,   # 512x256 card, same norm as the bubbles — bypassed: draw site (main.gd) uses raw draw_texture_rect with its own rect
	"riot_shield": 1.1,   # 64px canvas → ~half a p2 specialist's span; tune in wiring
}

## Desert→jungle shift, multiplied onto the draw modulate. Units/vehicles take
## a darker olive-drab so they read against the bright jungle ground (with the
## outline below); foliage deepens green. Absent = white.
const UNIT := Color(0.85, 0.81, 0.58)
const OLIVE_VEH := Color(0.76, 0.85, 0.52)
const FOLIAGE := Color(0.82, 1.0, 0.66)
# a1-05: charred late-run foliage. The flat FOLIAGE green used to multiply back
# into every fern/tree even after main.gd browned them (fern_col), so the foundry
# re-greened. tint() now ramps the FOLIAGE keys toward ash by foliage_march (set
# each frame from _sector_march), compounding with fern_col so the foundry chars.
const FOLIAGE_ASH := Color(0.66, 0.60, 0.50)
const _FOLIAGE_KEYS := {"tree_large": true, "tree_small": true, "fern": true,
	"fern2": true, "hedge": true}   # a1-05 r2: the foundry undergrowth is ALL hedges — char them too
# a2-01: the prop/rock/wreck/hulk/corpse layer chars WITH the ground toward the
# foundry (A1 only ramped ground+foliage, so cool-green jungle rocks sat strewn on
# the molten floor). Each prop lerps from its own muted tint toward this warm charred
# debris color by foliage_march (capped 0.7 so jungle keeps prop variety).
const DECOR_ASH := Color(0.48, 0.40, 0.32)   # a2-01 r2: nudged toward the FOLIAGE_ASH ground family for palette lock
const _DECOR_KEYS := {"rock1": true, "rock2": true, "wreck": true, "wreck_apc": true,
	"wreck_halftrack": true, "wreck_technical": true, "wreck_light_tank": true, "tank_hulk": true,
	"corpse_soldier1": true, "corpse_soldier2": true, "barrel": true, "crate_stack": true,
	"tank_trap": true, "barricade": true, "radio_tower": true, "flak_gun": true, "trench": true,
	"barbedwire": true, "watchtower": true, "tent": true}
static var foliage_march := 0.0
const TINT := {
	# Heroes render bright, not olive-washed — the tan Leader model in the
	# old jungle tint was literal camouflage (invisible on grass).
	"player1": Color(1.1, 1.12, 0.95), "player2": Color(1.18, 1.05, 0.85),
	# Insurgents run BRIGHT and WARM so they read as threats — not as the
	# grey decor rocks, not as the red enemy orbs. Threats pop, scenery
	# recedes (see decor tints below).
	"rusher": Color(2.1, 1.7, 1.15), "elite": Color(1.75, 0.85, 0.68),
	"frogman": Color(1.35, 1.6, 1.7), "observer": Color(1.6, 1.2, 1.0),   # frogman: bright cool "wet threat" — dark bake vanished against rocks (3v)
	"bunker": Color(1.0, 0.95, 0.82),
	"tank_body": OLIVE_VEH, "tank_barrel": OLIVE_VEH,
	"gunship_body": OLIVE_VEH, "gunship_barrel": OLIVE_VEH,
	"colossus_body": OLIVE_VEH, "colossus_barrel": OLIVE_VEH,
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
	# Bridges are TERRAIN, not litter — warm neutral concrete (no mossy wash,
	# same class as the sandbag walls, not the receding scenery).
	"bridge_mid": Color(0.94, 0.9, 0.8), "bridge_ramp": Color(0.94, 0.9, 0.8),
	# Skyline pieces read as dark horizon silhouettes.
	# bypassed — skyline draw site (main.gd) passes its own `sky` color to draw_texture_rect
	"skyline_chimney": Color(0.3, 0.33, 0.38), "skyline_mast": Color(0.3, 0.33, 0.38),
	"crater": Color(0.6, 0.6, 0.54),   # scorched ground, recedes like the wrecks
	# p4 props: mossy/muted recede like the rest of the decor; craters + wreck
	# darker like the scorch/hulk litter; flag stays a touch brighter (landmark).
	"tank_trap": Color(0.72, 0.76, 0.62), "barricade": Color(0.74, 0.76, 0.64),
	"flak_gun": Color(0.66, 0.72, 0.6), "trench": Color(0.72, 0.76, 0.64),
	"flag_marker": Color(0.85, 0.86, 0.76), "radio_tower": Color(0.68, 0.72, 0.64),
	"hedge": Color(0.66, 0.78, 0.58), "fern2": Color(0.64, 0.8, 0.56),
	"wreck_halftrack": Color(0.55, 0.58, 0.52),
	"crater_field": Color(0.6, 0.6, 0.54), "crater_water": Color(0.62, 0.68, 0.72),
	"mg_tripod": Color(0.66, 0.7, 0.62),
	# fallen merc: heavy desert-olive multiply to pull the BR urban-blue kit onto
	# the battlefield palette; dropped shield muted like the wreck litter.
	"fallen_merc": Color(0.62, 0.64, 0.44), "dropped_shield": Color(0.6, 0.64, 0.56),
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
	"mg_stand": OLIVE_VEH,
	"riot_shield": Color(1.1, 1.1, 1.05),
	# p2 specialists are threats — warm/bright per the insurgent readability rule.
	"ghillie": Color(1.7, 1.5, 1.05), "courier": Color(2.1, 1.7, 1.15),
	"sapper": Color(1.7, 1.35, 0.9),
	"bunker2": Color(1.0, 0.95, 0.82),
	"pickup_vest": Color(0.82, 0.88, 0.62),
	# Dead things recede like the wreck/decor litter.
	"tank_hulk": Color(0.55, 0.58, 0.52),
	"tree_dead1": Color(0.72, 0.68, 0.55), "tree_dead2": Color(0.72, 0.68, 0.55),
	"tree_dead3": Color(0.72, 0.68, 0.55),
	"corpse_soldier1": Color(0.7, 0.68, 0.58), "corpse_soldier2": Color(0.7, 0.68, 0.58),
	"wall_sandbag": Color(0.88, 0.92, 0.66), "wall_sandbag_end": Color(0.88, 0.92, 0.66),
}

## Sprites that get a 1px dark outline in _spr() for readability on any ground.
const OUTLINE := {
	"player1": true, "player2": true, "rusher": true, "elite": true,
	"frogman": true, "observer": true, "bunker": true,
	"tank_body": true, "tank_barrel": true, "gunship_body": true,
	"gunship_barrel": true, "colossus_body": true, "colossus_barrel": true,
	"sandbag_beige": true, "mg_stand": true, "riot_shield": true,
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
	# The rare-capsule set: same ground-pickup class as the rifle/shotgun/mg
	# capsules above (plus the planted claymore + its ghost — rim alpha follows
	# tint.a, so the 0.28-alpha preview stays subtle).
	"icon_rend": true, "wep_claymore": true, "wep_smoke": true, "wep_flashbang": true,
	"ghillie": true, "courier": true, "sapper": true,
	"bunker2": true, "tank_hulk": true, "pickup_vest": true,
	"wall_sandbag": true, "wall_sandbag_end": true,
	"tank_trap": true, "barricade": true, "flak_gun": true, "trench": true,
	"flag_marker": true, "radio_tower": true, "hedge": true, "fern2": true,
	"wreck_halftrack": true, "crater_field": true, "crater_water": true, "mg_tripod": true,
	"dropped_shield": true, "fallen_merc": true,
	"cap_pierce": true, "cap_spread": true, "cap_triple": true, "cap_rend": true,
	"cap_claymore": true, "cap_smoke": true, "cap_flash": true,
}

const _GLYPH_PAD := {"interact": "ui_pad_x", "revive": "ui_pad_y",
	"roll": "ui_pad_b", "wheel": "ui_pad_back"}
const _GLYPH_KEY := {"interact": "F", "revive": "E", "roll": "C", "wheel": "Q"}
# (Hint-toast button WORDS live in _PAD_LABELS / pad_label below — the two
# parallel loops built the same helper twice; pad_label won: its Switch table
# is positionally correct where the duplicate transplanted Xbox letters.)

## Semantic hint → registry key for the device-aware prompt sprites (see
## glyph_key below). Pad column mirrors the bindings in main._gather_inputs;
## keyboard column favors the mouse/keycap art (WASD/arrows land on the wide
## blank keycap for callers to stamp, per the ui_key_blank letter pattern).
const _HINT_PAD := {"confirm": "glyph_pad_a", "back": "ui_pad_b",
	"start": "glyph_pad_start", "fire": "glyph_rt", "grenade": "glyph_lb",
	"move": "glyph_stick_l", "aim": "glyph_stick_r", "nav_lr": "glyph_dpad_lr"}
const _HINT_KB := {"confirm": "glyph_key_enter", "back": "ui_key_blank",
	"start": "glyph_key_enter", "fire": "glyph_mouse_l", "grenade": "glyph_mouse_r",
	"move": "glyph_key_wide", "aim": "glyph_key_wide", "nav_lr": "glyph_key_wide"}


static func tex(name: String) -> Texture2D:
	return TEX[name]


static func draw_scale(name: String) -> float:
	return SCALE.get(name, 1.0)


static func tint(name: String) -> Color:
	if _FOLIAGE_KEYS.has(name):
		return FOLIAGE.lerp(FOLIAGE_ASH, foliage_march)
	if _DECOR_KEYS.has(name):
		return TINT.get(name, Color(0.7, 0.76, 0.62)).lerp(DECOR_ASH, foliage_march * 0.7)
	return TINT.get(name, Color.WHITE)


static func outlined(name: String) -> bool:
	return OUTLINE.has(name)


## Input-prompt glyphs: pad button art when the pad is the LAST-USED device,
## else a blank keycap stamped with the key letter. `use_pad` is driven from
## main by the last InputEvent class — a merely-connected idle pad no longer
## mis-teaches a keyboard player pad buttons. Draws centered at pos.
static var use_pad := false
## Last-used pad's glyph family: "xbox" (default/fallback), "ps", "switch".
## Driven from main._input via the joy name; every pad-glyph lookup routes
## through _brand() so unknown pads safely teach Xbox labels.
static var pad_brand := "xbox"

const _BRAND_MAP := {
	"ps": {"glyph_pad_a": "glyph_ps_a", "ui_pad_b": "glyph_ps_b",
		"ui_pad_x": "glyph_ps_x", "ui_pad_y": "glyph_ps_y",
		"glyph_pad_start": "glyph_ps_start", "glyph_rt": "glyph_ps_rt",
		"glyph_lb": "glyph_ps_lb", "ui_pad_back": "glyph_ps_back",
		"glyph_dpad_lr": "glyph_ps_dpad_lr"},
	"switch": {"glyph_pad_a": "glyph_sw_a", "ui_pad_b": "glyph_sw_b",
		"ui_pad_x": "glyph_sw_x", "ui_pad_y": "glyph_sw_y",
		"glyph_pad_start": "glyph_sw_start", "glyph_rt": "glyph_sw_rt",
		"glyph_lb": "glyph_sw_lb", "ui_pad_back": "glyph_sw_back",
		"glyph_dpad_lr": "glyph_sw_dpad_lr"},
}


static func _brand(key: String) -> String:
	return _BRAND_MAP.get(pad_brand, {}).get(key, key)


## Brand-correct button NAMES for text hints (the glyph twin of _brand):
## semantic verbs → what's printed on the last-used pad. Unknown brands
## fall back to Xbox labels, same as the glyph lookups.
const _PAD_LABELS := {
	"xbox": {"interact": "X", "revive": "Y", "wheel": "BACK"},
	"ps": {"interact": "SQUARE", "revive": "TRIANGLE", "wheel": "SHARE"},
	"switch": {"interact": "Y", "revive": "X", "wheel": "MINUS"},
}


static func pad_label(verb: String) -> String:
	return _PAD_LABELS.get(pad_brand, _PAD_LABELS["xbox"]).get(verb, verb.to_upper())
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


## The game font — PixelOperator8 (public domain), replacing the antialiased
## proportional ThemeDB fallback that rasterized to grey mush at 7-13px inside
## the 640x360 integer-scaled frame. Rendering flags are forced here at the
## single hand-out site instead of via .import surgery: no AA, no hinting, no
## subpixel — glyphs land on whole pixels and upscale crisp.
static var _font: Font = null


static func font() -> Font:
	if _font == null:
		var f: FontFile = preload("res://assets/fonts/PixelOperator8.ttf")
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = f
	return _font


## Shadowed text: black copy offset +1px, then the colored text on top — the
## drop-shadow pattern hand-inlined across the view, now in one place.
## max_w > 0 clips the string to that width instead of letting it bleed past the bound.
static func text(ci: CanvasItem, txt: String, pos: Vector2, size: int, col: Color, max_w := 0.0) -> void:
	var f := font()
	var w := max_w if max_w > 0.0 else -1.0
	# Snap to whole pixels: centered strings land on fractional x (cx - w/2 with
	# odd w), which smears a bitmap pixel font across two source texels under the
	# canvas's linear-mipmap filter. View-only, so golden-safe.
	pos = pos.floor()
	ci.draw_string(f, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, Color(0, 0, 0, 0.7))
	ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, col)


## Same shadow+color text, horizontally centered on cx at y.
static func text_center(ci: CanvasItem, txt: String, cx: float, y: float, size: int, col: Color, max_w := 0.0) -> void:
	var w := font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0:
		w = minf(w, max_w)
	text(ci, txt, Vector2(cx - w / 2.0, y), size, col, max_w)


static func draw_glyph(ci: CanvasItem, action: String, pos: Vector2, size := 12.0, mod := Color.WHITE, force_pad := false) -> void:
	# force_pad: P2 is hardwired to pad 1 (main._gather_inputs), so P2's OWN
	# prompts must show pad buttons even while P1's mouse aim keeps the global
	# use_pad false — per-player call sites pass `i == 1`.
	var rect := Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size))
	if use_pad or force_pad:
		ci.draw_texture_rect(tex(_brand(_GLYPH_PAD[action])), rect, false, mod)
	else:
		ci.draw_texture_rect(tex("ui_key_blank"), rect, false, Color(0.96, 0.95, 0.88) * mod)
		var letter: String = _GLYPH_KEY[action]
		var f := font()
		# Floor at the font's native 8px: PixelOperator8 with AA/hinting off drops
		# whole strokes below native scale (a 6px 'E' loses horizontals).
		var fs := maxi(8, int(size * 0.62))
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(f, pos + Vector2(-w / 2.0, size * 0.24), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.16, 0.12))


## Device-aware prompt lookup: semantic action hint ('confirm', 'back',
## 'start', 'fire', 'grenade', 'move', 'aim', 'nav_lr') → TEX registry key for
## the current device (use_pad). Total: unknown hints fall back to the
## confirm glyph so callers always get a drawable key.
static func glyph_key(action_hint: String) -> String:
	if use_pad:
		return _brand(_HINT_PAD.get(action_hint, "glyph_pad_a"))
	return _HINT_KB.get(action_hint, "glyph_key_enter")


static func cell_hash(ix: int, iy: int) -> int:
	## Cheap deterministic decor hash (view-only; not the sim RNG).
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
