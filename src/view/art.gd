class_name Art
extends RefCounted
## Sprite registry for the view. Units/vehicles/props are top-down renders of
## legacy 3D pack Military 3D models, baked to sprites by tools/bake_sprites.gd
## (see assets/art/). Ground tiles, projectiles and FX remain Kenney CC0
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

const ART := "res://assets/art/"
const KN := "res://assets/kenney/"
const SOL := "res://assets/soldiers/"   # infantry set pack (authored top-down infantry, size-limited + cleaned)

const TEX := {
	# --- legacy 3D pack Military (top-down bakes) ---
	# Cast v2: heroes are regular army (Leader + Soldier_Female), hostiles
	# are the Insurgent faction — different silhouettes, different wardrobe.
	# sol-03: the pale legacy art hero read as a blob at gameplay zoom — swapped for the authored
	# infantry set top-down infantry. No sim weapon field exists, so ONE canonical class (assault)
	# for both slots; P1/P2 stay distinct via the ident ring + _body_ident_lean + the TINT split below.
	"player1": preload(SOL + "soldier_assault_rifle.png"),
	"player2": preload(SOL + "soldier_assault_rifle.png"),
	"rusher": preload(ART + "cast2/insurgent1.png"),
	"elite": preload(ART + "cast2/insurgent2.png"),
	# sol-08: authored RED-team pack sprites for the shooting infantry (rusher skins / elite / sniper).
	# Team-color is baked in (crimson vs the olive hero) — friend/foe read for free, colorblind-safer
	# than the old warm-tinted insurgents. Single-authorship rotation (all cel) so no cel/legacy art strobe.
	"enemy_assault": preload(SOL + "enemy/enemy_assault_rifle.png"),
	"enemy_smg": preload(SOL + "enemy/enemy_smg.png"),
	"enemy_shotgun": preload(SOL + "enemy/enemy_shotgun.png"),
	"enemy_lmg": preload(SOL + "enemy/enemy_lmg.png"),
	"enemy_sniper": preload(SOL + "enemy/enemy_sniper.png"),
	# sol-12: authored pack diver replaces the legacy art frogman bake. "frogman" is the SURFACED (rifle) pose
	# — the canonical key so corpse/bestiary/markers follow for free; the submerged variant is its own key.
	"frogman": preload(SOL + "frogman_rifle.png"),
	"frogman_speargun": preload(SOL + "frogman_speargun.png"),
	"observer": preload(ART + "cast2/observer2.png"),
	"bunker": preload(ART + "cast2/bunker.png"),
	"trophy": preload(ART + "cast2/trophy.png"),
	# nt-03: bespoke generated player-tank art (fal.ai + Replicate) replacing
	# a plain camo rectangle with no hull/turret/track shape at all. tank_body
	# is now an armored hull with a turret ring + glacis wedge; tank_barrel is
	# an isolated cannon tube (no hull baked in -- main.gd rotates it as its
	# own sprite, independent of the hull). Both pre-rotated front-up to match
	# the hull = dv.angle() + PI/2 correction _draw_tanks() applies -- same
	# filenames, SCALE/TINT carry over unchanged.
	"tank_body": preload(ART + "tank_body.png"),
	"tank_barrel": preload(ART + "tank_barrel.png"),
	# nt-02: bespoke generated boss art (fal.ai + Replicate) replacing the old
	# gunship/colossus bakes, which literally shared tank_body/tank_barrel's
	# camo material and read as up-scaled generic vehicles. gunship_body is
	# now an attack-helicopter silhouette (rotor mast/tail boom/cockpit/
	# weapon pods); colossus_body is a fortress-walker hull with a glowing
	# core hatch baked in under the separately-drawn CORE EXPOSED overlay.
	# Both bodies are pre-rotated 180 so their "nose" lands under the
	# chin-turret/twin-barrel offsets in main.gd once the PI draw rotation
	# flips them to face the players. Same filenames -> SCALE/TINT/BOSS_RIM
	# below carry over unchanged.
	"gunship_body": preload(ART + "gunship_body.png"),
	"gunship_barrel": preload(ART + "gunship_barrel.png"),
	"colossus_body": preload(ART + "colossus_body.png"),
	"colossus_barrel": preload(ART + "colossus_barrel.png"),
	"sandbag_beige": preload(ART + "sandbag.png"),
	"crate_ammo": preload(ART + "crate_ammo.png"),
	"crate_grenade": preload(ART + "crate_grenade.png"),
	"crate_airstrike": preload(ART + "crate_airstrike.png"),
	# Iran desert reskin: nano-banana cactus art (see desert_assets_source.md),
	# baked to the same canvas size as the jungle tree_large/tree_small.png it
	# replaces (120px/96px) so SCALE/TINT below carry over unchanged.
	"cactus_large": preload(ART + "cactus_large.png"),
	"cactus_small": preload(ART + "cactus_small.png"),
	"scrub": preload(ART + "scrub.png"),
	# --- legacy art icon bakes (HUD + spend-wheel) ---
	"icon_ammo": preload(ART + "icons/icon_ammo.png"),
	"icon_grenade": preload(ART + "icons/icon_grenade.png"),
	"icon_coin": preload(ART + "icons/icon_coin.png"),
	# Referenced nowhere (bake tools only write the PNGs) — commented out like
	# hudfx_glow/hudfx_dmgdir above: ~270KB of boot VRAM for zero drawn pixels.
	#"icon_fuel": preload(ART + "icons/icon_fuel.png"),
	"icon_vest": preload(ART + "icons/icon_vest.png"),
	"icon_skull": preload(ART + "icons/icon_skull.png"),
	"icon_medal": preload(ART + "icons/icon_medal.png"),
	"icon_airstrike": preload(ART + "icons/icon_airstrike.png"),
	"icon_rend": preload(ART + "icons/icon_rend.png"),  # 64px canvas (siblings 128) — drawn scaled
	# Apocalypse HUD sprites (imported 2D kit, assets/art/hud/).
	"hud_star": preload(ART + "hud/ICON_Map_Star.png"),
	"hud_flag": preload(ART + "hud/ICON_Map_Flag.png"),
	"hud_skull": preload(ART + "hud/ICON_Map_Skull.png"),
	"hud_target": preload(ART + "hud/ICON_Map_Target.png"),
	"hud_gunshop": preload(ART + "hud/ICON_Map_GunShop.png"),
	"hud_vehicle": preload(ART + "hud/ICON_Map_Vehicle.png"),
	"hud_lightning": preload(ART + "hud/ICON_Map_Lightning.png"),
	"hud_fire": preload(ART + "hud/ICON_Map_Fire.png"),
	"hud_radiation": preload(ART + "hud/ICON_Map_Radiation.png"),
	# --- legacy art INTERFACE sprites (Apocalypse HUD + Modern Menus) ---
	"ui_wheel_socket": preload(ART + "ui/wheel_socket.png"),
	"ui_bar_frame": preload(ART + "ui/bar_frame.png"),
	"ui_dial_fuel": preload(ART + "ui/dial_fuel.png"),
	"ui_panel": preload(ART + "ui/panel.png"),
	"ui_key_blank": preload(ART + "ui/key_blank.png"),
	"ui_pad_x": preload(ART + "ui/pad_x.png"),
	"ui_pad_y": preload(ART + "ui/pad_y.png"),
	"ui_pad_b": preload(ART + "ui/pad_b.png"),
	"ui_pad_back": preload(ART + "ui/pad_back.png"),
	"ui_reticle": preload(ART + "ui/reticle.png"),
	# Weapon-state reticle silhouettes (Apocalypse HUD) — pierce/spread stop being
	# hue-only signals (protan-safe). Bracket_Sml is byte-identical to ui_reticle,
	# so the default keeps its file; these two are genuinely different shapes.
	"ui_ret_spread": preload(ART + "hud/SPR_HUD_Reticle_Bracket_Shotgun.png"),  # 128x256 — draw at half width
	"ui_ret_pierce": preload(ART + "hud/SPR_HUD_Reticle_Circle_Med.png"),
	"ui_vignette": preload(ART + "ui/vignette.png"),
	# Apocalypse HUD screen-space combat-feedback cards.
	"hudfx_hitlines": preload(ART + "hud/hudfx_hitlines.png"),
	"hudfx_blood": preload(ART + "hud/hudfx_blood.png"),
	"hudfx_dmgvig": preload(ART + "hud/hudfx_dmgvig.png"),
	# hudfx_glow / hudfx_dmgdir: preloaded here for months, referenced nowhere —
	# ~0.7 MB of VRAM at boot for zero drawn pixels. Files stay for when a
	# damage-direction or glow pass actually wants them.
	# --- legacy art Military decor (war-torn battlefield litter) ---
	"barrel": preload(ART + "decor/barrel.png"),
	"crate_stack": preload(ART + "decor/crate_stack.png"),
	"rock1": preload(ART + "decor/rock1.png"),
	"rock2": preload(ART + "decor/rock2.png"),
	"wreck": preload(ART + "decor/wreck.png"),
	"tent": preload(ART + "decor/tent.png"),
	"watchtower": preload(ART + "decor/watchtower.png"),
	"barbedwire": preload(ART + "decor/barbedwire.png"),
	"barrier": preload(ART + "decor/barrier.png"),
	"ammobox": preload(ART + "decor/ammobox.png"),
	#"landmine": preload(ART + "decor/landmine.png"),
	# Terrain/skyline set (War FBX bakes). Bridges are grey concrete terrain,
	# skyline pieces are horizon silhouettes (side views, drawn dark, no outline).
	"bridge_mid": preload(ART + "decor/bridge_mid.png"),
	"bridge_ramp": preload(ART + "decor/bridge_ramp.png"),
	"skyline_chimney": preload(ART + "decor/skyline_chimney.png"),
	"skyline_mast": preload(ART + "decor/skyline_mast.png"),
	"crater": preload(ART + "decor/crater.png"),
	# --- POLYGON War / War_Map / Nature FBX bakes (p4 asset pass, forced-atlas) ---
	"tank_trap": preload(ART + "decor/tank_trap.png"),
	"barricade": preload(ART + "decor/barricade.png"),
	"flak_gun": preload(ART + "decor/flak_gun.png"),
	"trench": preload(ART + "decor/trench.png"),
	"flag_marker": preload(ART + "decor/flag_marker.png"),
	# iran-flag: the enemy faction banner hung behind each level-end boss.
	"flag_iran": preload(ART + "decor/flag_iran.png"),
	"radio_tower": preload(ART + "decor/radio_tower.png"),
	"dry_shrub": preload(ART + "decor/dry_shrub.png"),
	"tumbleweed": preload(ART + "decor/tumbleweed.png"),
	"wreck_halftrack": preload(ART + "decor/wreck_halftrack.png"),
	"crater_field": preload(ART + "decor/crater_field.png"),
	"crater_water": preload(ART + "decor/crater_water.png"),
	"mg_tripod": preload(ART + "decor/mg_tripod.png"),
	# BattleRoyale bakes repurposed as battlefield litter (a dropped riot shield
	# + a fallen soldier body) — the live shield enemy keeps its on-theme bombsuit.
	"dropped_shield": preload(ART + "decor/dropped_shield.png"),
	"fallen_merc": preload(ART + "decor/fallen_merc.png"),
	# Apocalypse-HUD capsule pickup glyphs (clean UI-icon set): each power-up
	# capsule floats its own icon (mine for claymore, smoke-grenade for smoke, …).
	"cap_pierce": preload(ART + "icons/cap_pierce.png"),
	"cap_spread": preload(ART + "icons/cap_spread.png"),
	"cap_triple": preload(ART + "icons/cap_triple.png"),
	"cap_rend": preload(ART + "icons/cap_rend.png"),
	"cap_claymore": preload(ART + "icons/cap_claymore.png"),
	"cap_smoke": preload(ART + "icons/cap_smoke.png"),
	"cap_flash": preload(ART + "icons/cap_flash.png"),
	# --- Kenney CC0 (ground tiles, projectiles, FX) ---
	# a5-01 Iran desert reskin: base ground tile is the sand card (was
	# grass.png, now unused and removed — every ground-paint call site in
	# main.gd was renamed from Art.tex("grass") to Art.tex("sand")).
	"dirt": preload(KN + "dirt.png"),
	"sand": preload(KN + "sand.png"),
	# bullet/enemy_bullet/grenade/smoke: Kenney keys RETIRED (files kept) — every
	# live draw site moved on long ago: player rounds are procedural tracers +
	# fx_bullettrail streaks, enemy fire is the red-streak orb, thrown frags wear
	# the wep_grenade bake (AP shells tank_shell), and every smoke puff draws
	# fx_smoke. Dead preloads cost VRAM and mislead asset audits; skip in loops.
	# Explosion frames: VERIFIED vendor non-match (no owned pack ships explosion
	# art — Particle_FX is crystals/trails/rings). nt-01: the flat-cartoon Kenney
	# blobs were replaced in place with a fal.ai-generated painterly top-down
	# 4-frame sequence (flash -> fireball -> big fireball -> smoke); same path,
	# same file names, so no other call site changed. Skip in asset loops.
	"explosion0": preload(KN + "explosion0.png"),
	"explosion1": preload(KN + "explosion1.png"),
	"explosion2": preload(KN + "explosion2.png"),
	"explosion3": preload(KN + "explosion3.png"),
	# --- legacy 3D pack Particle FX (2D textures, assets/art/fx/) ---
	"fx_bullettrail": preload(ART + "fx/fx_bullettrail.png"),
	"fx_smoke": preload(ART + "fx/fx_smoke_01.png"),
	"fx_fumes": preload(ART + "fx/fx_fumes_02.png"),
	"fx_ring": preload(ART + "fx/fx_ring_02.png"),
	"fx_circle": preload(ART + "fx/fx_circle_01.png"),
	"fx_disc": preload(ART + "fx/fx_circle_02.png"),
	"fx_lightning": preload(ART + "fx/fx_lightning_02.png"),
	"fx_groundbreak": preload(ART + "fx/fx_groundbreak.png"),
	"fx_shell": preload(ART + "fx/fx_shell_01.png"),
	"fx_sparkle": preload(ART + "fx/fx_sparkle.png"),
	"fx_swipe": preload(ART + "fx/fx_swipe_01.png"),
	"fx_softspot": preload(ART + "fx/fx_soft_spot.png"),
	"fx_shadow": preload(ART + "fx/fx_shadow.png"),
	"fx_impactdark": preload(ART + "fx/fx_impactdark.png"),
	"fx_wind": preload(ART + "fx/fx_wind.png"),
	"fx_fumes4": preload(ART + "fx/fx_fumes4.png"),
	#"fx_halfcircle": preload(ART + "fx/fx_halfcircle.png"),  # 175KB, never drawn
	"fx_swipe2": preload(ART + "fx/fx_swipe2.png"),
	# Semicircle flash card (512x256, flat edge at BOTTOM — orient flat edge to muzzle).
	"fx_muzzle_fan": preload(ART + "fx/fx_muzzle_fan.png"),
	"mz_pop": preload(SOL + "fx/muzzleflash_small.png"),   # sol-15: authored 8-point crack-pop overlay for the PLAYER shot (transparent core → the hot core shows through)
	# --- POLYGON Military mil2 bake (enemies, vehicles, weapon pickups, items) ---
	"m_bombsuit": preload(ART + "mil2/bombsuit.png"),
	# sol-08: m_contractor2 (sniper) + m_insurgent3/4/5 (rusher skins) retired — the RED enemy_* pack
	# sprites replaced them live + as corpses, so these 300px legacy art bakes were dead boot VRAM. Deleted.
	"m_pilot": preload(ART + "mil2/pilot.png"),
	"m_soldier2": preload(ART + "mil2/soldier2.png"),
	#"m_apc": preload(ART + "mil2/apc.png"),
	# nt-03: bespoke generated art (fal.ai + Replicate) replacing the old
	# radar_tank/rocket_truck/technical bakes -- like tank_body, the same flat
	# camo-rectangle non-vehicle, just re-scaled, so the observer spotter duo
	# and the roaming hostile were unreadable blobs. Now a light armored car
	# with a dish antenna, a flatbed with an MLRS rocket rack, and an armed
	# desert pickup (technical) -- distinct silhouettes, front pre-rotated up
	# to match the static PI/2 (spotter duo) / t_face (technical) draw angles
	# in main.gd. wreck_technical below shares this file, so the litter hulk
	# improves too.
	"m_radar_tank": preload(ART + "mil2/radar_tank.png"),
	"m_rocket_truck": preload(ART + "mil2/rocket_truck.png"),
	"m_jet": preload(ART + "mil2/jet.png"),
	"m_heli_transport": preload(ART + "mil2/heli_transport.png"),
	"m_heli_attack2": preload(ART + "mil2/heli_attack2.png"),
	"m_drone": preload(ART + "mil2/drone.png"),
	#"m_light_tank": preload(ART + "mil2/light_tank.png"),
	"m_technical": preload(ART + "mil2/technical.png"),
	# Wreck variants: same vehicle art, but muted/small/outlined for battlefield
	# litter (see SCALE/TINT below) — dead hulks, not live vehicles.
	"wreck_apc": preload(ART + "mil2/apc.png"),
	"wreck_technical": preload(ART + "mil2/technical.png"),
	"wreck_light_tank": preload(ART + "mil2/light_tank.png"),
	"wep_grenade": preload(ART + "mil2/wep_grenade.png"),
	#"wep_rpg": preload(ART + "mil2/wep_rpg.png"),
	"wep_shotgun": preload(ART + "mil2/wep_shotgun.png"),
	"wep_rifle": preload(ART + "mil2/wep_rifle.png"),
	"wep_mg": preload(ART + "mil2/wep_mg.png"),
	#"wep_pistol": preload(ART + "mil2/wep_pistol.png"),
	"wep_claymore": preload(ART + "mil2/wep_claymore.png"),
	"wep_smoke": preload(ART + "mil2/wep_smoke.png"),
	"wep_flashbang": preload(ART + "mil2/wep_flashbang.png"),
	"item_bullet": preload(ART + "mil2/item_bullet.png"),
	"item_bullet_shotgun": preload(ART + "mil2/item_bullet_shotgun.png"),
	"item_binoculars": preload(ART + "mil2/item_binoculars.png"),
	# MG emplacement (barrel points screen-up at rotation 0; ammo box on left).
	"mg_stand": preload(ART + "mil2/mg_stand.png"),
	# --- POLYGON Military/Battle Royale p2 bake (specialists, hulks, litter) ---
	"ghillie": preload(ART + "p2/ghillie.png"),
	"courier": preload(ART + "p2/courier.png"),
	"sapper": preload(ART + "p2/sapper.png"),
	"tank_shell": preload(ART + "p2/tank_shell.png"),
	"pickup_vest": preload(ART + "p2/pickup_vest.png"),
	"tank_hulk": preload(ART + "p2/tank_hulk.png"),
	# charred dead-cactus for the foundry/late-war canopy set (tree_dead1-3 retired,
	# both from the registry and on disk — Iran has no jungle deadfall to burn).
	"cactus_dead1": preload(ART + "p2/cactus_dead1.png"),
	"cactus_dead2": preload(ART + "p2/cactus_dead2.png"),
	"cactus_dead3": preload(ART + "p2/cactus_dead3.png"),
	"wall_sandbag": preload(ART + "p2/wall_sandbag.png"),
	"wall_sandbag_b": preload(ART + "p2/wall_sandbag_b.png"),
	"wall_sandbag_c": preload(ART + "p2/wall_sandbag_c.png"),
	"wall_sandbag_end": preload(ART + "p2/wall_sandbag_end.png"),
	"bunker2": preload(ART + "p2/bunker2.png"),
	"corpse_soldier1": preload(ART + "p2/corpse_soldier1.png"),
	"corpse_soldier2": preload(ART + "p2/corpse_soldier2.png"),
	# Front face toward viewer, shield-top = image-up; rotate to carrier facing.
	"riot_shield": preload(ART + "p2/riot_shield.png"),
	"fx_flame": preload(ART + "p2/fx_flame.png"),
	"fx_bubble1": preload(ART + "fx/bubble1.png"),
	"fx_bubble2": preload(ART + "fx/bubble2.png"),
	# --- Apocalypse HUD input glyphs (device-aware prompts; see glyph_key) ---
	"glyph_pad_a": preload(ART + "ui/glyphs/pad_a.png"),
	"glyph_pad_start": preload(ART + "ui/glyphs/pad_start.png"),
	"glyph_rt": preload(ART + "ui/glyphs/pad_rt.png"),
	"glyph_lb": preload(ART + "ui/glyphs/pad_lb.png"),
	"glyph_dpad_lr": preload(ART + "ui/glyphs/dpad_lr.png"),
	"glyph_stick_l": preload(ART + "ui/glyphs/stick_l.png"),
	"glyph_stick_r": preload(ART + "ui/glyphs/stick_r.png"),
	"glyph_mouse_l": preload(ART + "ui/glyphs/mouse_l.png"),
	"glyph_mouse_r": preload(ART + "ui/glyphs/mouse_r.png"),
	"glyph_key_enter": preload(ART + "ui/glyphs/key_enter.png"),
	"glyph_key_wide": preload(ART + "ui/glyphs/key_wide.png"),
	# Brand-correct pad sets (PlayStation / Switch), swapped in by pad_brand.
	# PS has no Share sprite in the pack — TouchPad stands in for JOY_BUTTON_BACK
	# (same vendor-gap class as Xbox's missing View button).
	"glyph_ps_a": preload(ART + "ui/glyphs/ps_a.png"),
	"glyph_ps_b": preload(ART + "ui/glyphs/ps_b.png"),
	"glyph_ps_x": preload(ART + "ui/glyphs/ps_x.png"),
	"glyph_ps_y": preload(ART + "ui/glyphs/ps_y.png"),
	"glyph_ps_start": preload(ART + "ui/glyphs/ps_start.png"),
	"glyph_ps_rt": preload(ART + "ui/glyphs/ps_rt.png"),
	"glyph_ps_lb": preload(ART + "ui/glyphs/ps_lb.png"),
	"glyph_ps_back": preload(ART + "ui/glyphs/ps_back.png"),
	"glyph_ps_dpad_lr": preload(ART + "ui/glyphs/ps_dpad_lr.png"),
	"glyph_sw_a": preload(ART + "ui/glyphs/sw_a.png"),
	"glyph_sw_b": preload(ART + "ui/glyphs/sw_b.png"),
	"glyph_sw_x": preload(ART + "ui/glyphs/sw_x.png"),
	"glyph_sw_y": preload(ART + "ui/glyphs/sw_y.png"),
	"glyph_sw_start": preload(ART + "ui/glyphs/sw_start.png"),
	"glyph_sw_rt": preload(ART + "ui/glyphs/sw_rt.png"),
	"glyph_sw_lb": preload(ART + "ui/glyphs/sw_lb.png"),
	"glyph_sw_back": preload(ART + "ui/glyphs/sw_back.png"),
	"glyph_sw_dpad_lr": preload(ART + "ui/glyphs/sw_dpad_lr.png"),
	# --- Modern Menus ortho icons (menu rows / toggles) ---
	"mi_snd_on": preload(ART + "ui/menuicons/snd_on.png"),
	"mi_snd_off": preload(ART + "ui/menuicons/snd_off.png"),
	"mi_mus_on": preload(ART + "ui/menuicons/mus_on.png"),
	"mi_mus_off": preload(ART + "ui/menuicons/mus_off.png"),
	"mi_trophy": preload(ART + "ui/menuicons/trophy.png"),
	"mi_book": preload(ART + "ui/menuicons/book.png"),
	"mi_play": preload(ART + "ui/menuicons/play.png"),
	"mi_controller": preload(ART + "ui/menuicons/controller.png"),
	#"mi_keyboard": preload(ART + "ui/menuicons/keyboard.png"),
	# Modern Menus batch 2 (256px, white with alpha — modulate for color).
	# NOTE: mi_controller.png also landed on disk but the "mi_controller" key
	# above already serves controller.png — kept as-is, duplicate art unregistered.
	"mi_arrow": preload(ART + "ui/menuicons/mi_arrow.png"),  # points RIGHT — flip/rotate at call site
	"mi_medal_1": preload(ART + "ui/menuicons/mi_medal_1.png"),
	"mi_medal_2": preload(ART + "ui/menuicons/mi_medal_2.png"),
	"mi_medal_3": preload(ART + "ui/menuicons/mi_medal_3.png"),
	"mi_medal_4": preload(ART + "ui/menuicons/mi_medal_4.png"),
	"mi_medal_5": preload(ART + "ui/menuicons/mi_medal_5.png"),
	"mi_settings": preload(ART + "ui/menuicons/mi_settings.png"),
	"mi_reload": preload(ART + "ui/menuicons/mi_reload.png"),
	"mi_home": preload(ART + "ui/menuicons/mi_home.png"),
	"mi_camera": preload(ART + "ui/menuicons/mi_camera.png"),
	"mi_back": preload(ART + "ui/menuicons/mi_back.png"),
	"mi_combat": preload(ART + "ui/menuicons/mi_combat.png"),
	"mi_timer": preload(ART + "ui/menuicons/mi_timer.png"),
	"mi_cancel": preload(ART + "ui/menuicons/mi_cancel.png"),
	# --- Apocalypse HUD chrome (tooltip plate, frames, wheel plate, cursor) ---
	"ui_tooltip": preload(ART + "hud/SPR_HUD_Tooltip.png"),
	"ui_frame_lrg": preload(ART + "hud/SPR_HUD_Frame_Lrg.png"),
	"ui_frame_lrg_under": preload(ART + "hud/SPR_HUD_Frame_Lrg_Underlay.png"),
	"ui_wheel_plate": preload(ART + "hud/SPR_Apocalypse_WeaponWheel.png"),
	"ui_cursor": preload(ART + "ui/cursor.png"),
	# Modern Menus 3-slice metal plate (L/C/R, 190x230 each; tile C horizontally).
	"plate_metal_l": preload(ART + "ui/plate_metal_l.png"),
	"plate_metal_c": preload(ART + "ui/plate_metal_c.png"),
	"plate_metal_r": preload(ART + "ui/plate_metal_r.png"),
}

## Per-sprite draw multiplier so a legacy art bake lands at the Kenney footprint the
## main.gd scale numbers were tuned for. Absent = 1.0.
const SCALE := {
	# legacy art Particle_FX cards are large (fx_smoke_01 is 200px vs Kenney smoke.png's
	# 92px), so scale down to keep the same on-screen puff footprint.
	"fx_smoke": 0.46,
	# nt-01: the generated explosion frames render on a shared 128px canvas;
	# the old Kenney frames were each a DIFFERENT size (explosion2 the biggest
	# at 90x99, explosion3 smallest at 79x79) and _draw_fx's spr_scale ramps
	# monotonically UP across the animation (0.45 -> 0.95) — the old per-frame
	# size was what actually made the blast grow-then-plateau instead of
	# growing forever. Per-frame scale = sqrt(orig_w*orig_h)/128 reproduces
	# each original frame's on-screen footprint exactly (128 * scale_i ==
	# orig_i) so that grow/plateau timing, and the EXPLO_WHITE_R_* white-hot
	# core sizing tuned against it, both carry over unchanged.
	"explosion0": 0.680, "explosion1": 0.707, "explosion2": 0.737, "explosion3": 0.617,
	# cast2 bakes use a 300px canvas. Enemies run LARGER than the strict
	# old-footprint math: at ~7px the dark insurgents read as "black dots,
	# or is that a bullet?" — straight from playtest.
	# Sizes per the 1986-anchor readability pass: heroes ~18px on screen,
	# elites largest infantry (they shoot), sprites ≥3× bullet size.
	"player1": 0.25, "player2": 0.25, "rusher": 0.53, "elite": 0.58,   # sol-04: hero folds the 256px pack canvas to the ~18px on-screen footprint (was 0.56/0.47 for the 300px legacy art bake)
	# sol-08: enemy pack sprites fold the 128px canvas to the ~18-20px infantry footprint (call-scale 0.5 × 0.5 × 128 ≈ 32px canvas).
	"enemy_assault": 0.5, "enemy_smg": 0.5, "enemy_shotgun": 0.5, "enemy_lmg": 0.5, "enemy_sniper": 0.5,
	"frogman": 0.5, "frogman_speargun": 0.5, "observer": 0.24, "bunker": 0.17,   # sol-12: frogman folds the 128px pack canvas (was 1.05 for the legacy art bake)
	"tank_body": 0.72, "tank_barrel": 0.69,
	"gunship_body": 0.67, "colossus_body": 0.59,
	# Real barrel bakes replacing the 4x4 blanks: sized so the minigun sits
	# under the ~60px hull and the twin turrets under the ~143px colossus body
	# (main.gd draws them at 0.8 / 1.3). Tune visually.
	"gunship_barrel": 0.5, "colossus_barrel": 0.6,
	"sandbag_beige": 0.83,
	"crate_ammo": 0.86, "crate_grenade": 0.86, "crate_airstrike": 0.86,
	"cactus_large": 0.89, "cactus_small": 0.91, "scrub": 0.9,
	# Decor litter — folded to modest on-screen footprints (call _spr at 1.0).
	"barrel": 0.11, "crate_stack": 0.13, "rock1": 0.13, "rock2": 0.14,
	"wreck": 0.17, "tent": 0.19, "watchtower": 0.16, "barbedwire": 0.16,
	"barrier": 0.13, "ammobox": 0.1,
	# Terrain set is baked big (160-220px) but drawn at 1.0 like the litter;
	# bridges fold to ~96px spans, crater ~48px, skyline to readable silhouettes
	# (mast is a 1.5%-opaque lattice — below ~60px tall it aliases away).
	"bridge_mid": 0.44, "bridge_ramp": 0.44, "crater": 0.3,
	# p4 War/War_Map/Nature props — folded to litter footprints (retuned by eye).
	"tank_trap": 0.14, "barricade": 0.15, "flak_gun": 0.16, "trench": 0.2,
	"flag_marker": 0.16, "radio_tower": 0.18, "dry_shrub": 0.15, "tumbleweed": 0.14,
	"flag_iran": 0.22,   # iran-flag: 306x600 banner -> ~132px tall behind a gunship (call-site scales up for the colossus)
	"wreck_halftrack": 0.3, "crater_field": 0.3, "crater_water": 0.3, "mg_tripod": 0.12,
	"dropped_shield": 0.12, "fallen_merc": 0.2,
	# capsule glyphs: large Apocalypse UI icons folded to pickup footprint
	# (weapons 512x256, explosives 1024²) — retuned by eye.
	"cap_pierce": 0.14, "cap_spread": 0.14, "cap_triple": 0.14, "cap_rend": 0.14,
	"cap_claymore": 0.06, "cap_smoke": 0.06, "cap_flash": 0.06,
	"skyline_chimney": 0.4, "skyline_mast": 0.4,   # bypassed — skyline draw site (main.gd) uses raw draw_texture_rect with its own rects
	# mil2: characters ~unit size, vehicles ~tank size, weapons/items small pickups
	"m_bombsuit": 0.5, "m_pilot": 0.52, "m_soldier2": 0.5,   # sol-08: dropped m_contractor2/m_insurgent3-5 (retired)
	# sie-01: m_bombsuit/m_soldier2 re-baked as authored 1024px cel-shaded infantry (matches the
	# enemy_* red-team convention) at SCALE 0.5 -- same footprint math as enemy_assault (128px
	# imported canvas x 0.5), so the on-screen SHIELD/GRENADIER silhouette lands where the old
	# native-64px legacy art blob used to.
	"m_radar_tank": 0.72, "m_rocket_truck": 0.72, "m_jet": 0.62,
	"m_heli_transport": 0.68, "m_heli_attack2": 0.67, "m_drone": 0.34,
	"m_technical": 0.6,
	"wreck_apc": 0.3, "wreck_technical": 0.28, "wreck_light_tank": 0.28,
	"wep_grenade": 0.34, "wep_shotgun": 0.4, "wep_rifle": 0.4, "wep_mg": 0.4,
	"wep_claymore": 0.3, "wep_smoke": 0.32, "wep_flashbang": 0.3,
	"item_bullet": 0.32, "item_bullet_shotgun": 0.32, "item_binoculars": 0.34,
	"mg_stand": 0.3,   # 160px canvas → ~48px emplacement
	# p2: specialists match cast2 unit footprints (64px canvas vs cast2's 300px,
	# so raw multipliers run larger); litter/hulks fold to their swap targets.
	# sie-01: ghillie/sapper re-baked as authored 1024px cel-shaded infantry too -- SCALE drops from
	# the old native-64px multiplier (2.45) to the same 0.5 family footprint (courier is untouched,
	# still the native legacy art bake, still needs its old multiplier).
	"ghillie": 0.5, "courier": 2.45, "sapper": 0.5,
	"tank_shell": 0.8,               # ~grenade footprint (26px)
	"pickup_vest": 0.86,             # ~crate_ammo (same 56px canvas)
	"tank_hulk": 0.72,               # ~tank_body (same 104px canvas)
	"cactus_dead1": 0.89, "cactus_dead2": 0.89, "cactus_dead3": 0.89,   # ~cactus_large
	"wall_sandbag": 0.28, "wall_sandbag_b": 0.28, "wall_sandbag_c": 0.28,
	"wall_sandbag_end": 0.55,   # fold to sandbag_beige's ~66px span
	"bunker2": 0.17,                 # ~bunker (same 440px canvas)
	"corpse_soldier1": 0.21, "corpse_soldier2": 0.21,   # 140px canvas → ~29px, litter class (1.0 drew a tank-sized corpse)
	"fx_flame": 0.46,                # 200px FX card, same norm as fx_smoke
	# _spr sizes off the IMPORTED texture, so size_limit changes must land here
	# too: bubbles import at 64px now (was 512) — 1.44 keeps the same ~92px FX
	# footprint the 512×0.18 original had (the 0.18 silently shrank them 8×).
	"fx_bubble1": 1.44, "fx_bubble2": 1.44,
	"fx_fumes": 4.0,   # 128px import (was 512-effective) → same _spr plume size
	"fx_muzzle_fan": 0.18,   # 512x256 card, same norm as the bubbles — bypassed: draw site (main.gd) uses raw draw_texture_rect with its own rect
	"mz_pop": 0.5,   # sol-15: draw site uses its own rect off `sz`; SCALE row present so the registry has no dead config
	"riot_shield": 1.1,   # 64px canvas → ~half a p2 specialist's span; tune in wiring
	# aaa3-r2: fx_impactdark is a 200x200 solid octagon card. Its other three call sites
	# (main.gd _consume_events) go through the "kind":"tex" _fx particle path, which sizes
	# off an explicit "sz" pixel footprint and never touches this table. _spr (_wall_seg's
	# damage smear + the open-gate blast center) DOES fold through SCALE, and with no row
	# here it fell back to 1.0 -> a call-site scale of 0.5/1.1 drew a 100-220px hard-edged
	# black polygon over the ground. 0.12 folds it to the same small-scorch-accent family
	# as the other litter (dropped_shield/tank_trap sit at 0.12/0.14).
	"fx_impactdark": 0.12,
}

## Desert→jungle shift, multiplied onto the draw modulate. Units/vehicles take
## a darker olive-drab so they read against the bright jungle ground (with the
## outline below); foliage deepens green. Absent = white.
const UNIT := Color(0.85, 0.81, 0.58)
const OLIVE_VEH := Color(0.76, 0.85, 0.52)
# a2-02: bosses break out of the disposable-tank olive into a heavy desaturated
# GUNMETAL so the gunship + colossus read as an apex tier, not up-scaled jeeps.
const BOSS_VEH := Color(0.60, 0.63, 0.66)
# a2-02 r2: one warm-hostile tint for every enemy vehicle (technical + spotters).
const HOSTILE_VEH := Color(1.22, 0.87, 0.61)
# Iran reskin: cactus_large/cactus_small/scrub/tumbleweed/dry_shrub all share
# ONE desert-flora tint, not the old jungle FOLIAGE green — the green multiply,
# stacked on the already-sage-green cactus art and main.gd's desert_flora_col mod,
# doubled down into a saturated jungle green instead of a dusty desert plant.
# Warmer + lighter so it reads sun-bleached, not lawn.
const DESERT_FOLIAGE := Color(0.92, 0.88, 0.7)
# a1-05: charred late-run foliage. tint() ramps the desert-flora keys toward
# ash by foliage_march (set each frame from _sector_march), compounding with
# main.gd's desert_flora_col so the foundry chars.
const FOLIAGE_ASH := Color(0.66, 0.60, 0.50)
const _DESERT_FLORA_KEYS := {"cactus_large": true, "cactus_small": true,
	"scrub": true, "tumbleweed": true, "dry_shrub": true}   # a1-05 r2: the foundry undergrowth is ALL dry_shrub — char it too
# a2-01: the prop/rock/wreck/hulk/corpse layer chars WITH the ground toward the
# foundry (A1 only ramped ground+foliage, so cool-green jungle rocks sat strewn on
# the molten floor). Each prop lerps from its own muted tint toward this warm charred
# debris color by foliage_march (capped 0.7 so jungle keeps prop variety).
const DECOR_ASH := Color(0.48, 0.40, 0.32)   # a2-01 r2: nudged toward the FOLIAGE_ASH ground family for palette lock
# a4-02: one shared dark ink for every sprite outline rim (main._spr) and HUD
# metal-plate backing (main._metal_plate) — see assets_src/style_bible.md.
const PRINT_INK := Color(0.05, 0.06, 0.04)
# a4-02: one shared HUD steel midtone for the plate_metal_* cap/center tint.
const PLATE_STEEL := Color(0.5, 0.52, 0.5)
const _DECOR_KEYS := {"rock1": true, "rock2": true, "wreck": true, "wreck_apc": true,
	"wreck_halftrack": true, "wreck_technical": true, "wreck_light_tank": true, "tank_hulk": true,
	"corpse_soldier1": true, "corpse_soldier2": true, "barrel": true, "crate_stack": true,
	"tank_trap": true, "barricade": true, "radio_tower": true, "flak_gun": true, "trench": true,
	"barbedwire": true, "watchtower": true, "tent": true}
static var foliage_march := 0.0
const TINT := {
	# Heroes render bright, not olive-washed — the tan Leader model in the
	# old jungle tint was literal camouflage (invisible on grass).
	# sol-05: the pack hero is OLIVE camo — on green jungle that is literal camouflage (the exact tan-Leader
	# trap this comment warns about). Lift value >1 and pull slightly COOL/off-green so he reads on grass;
	# keep P2 visibly WARMER/gold (r>g>b) so co-op identity survives without a per-player sprite.
	"player1": Color(1.16, 1.18, 1.24), "player2": Color(1.34, 1.14, 0.92),
	# Insurgents run BRIGHT and WARM so they read as threats — not as the
	# grey decor rocks, not as the red enemy orbs. Threats pop, scenery
	# recedes (see decor tints below).
	"rusher": Color(2.1, 1.7, 1.15), "elite": Color(1.75, 0.85, 0.68),
	# sol-09: the pack enemies are RED camo — pull them toward warm VERMILION/brick (r>g>b), value-lifted
	# and folded into the a1–a4 grade, but deliberately OFF the pure-red danger family (bullet orbs / elite
	# aura / sniper laser / grenade telegraphs). Hostile-warm, never a saturated tracer-red.
	"enemy_assault": Color(1.35, 0.92, 0.74), "enemy_smg": Color(1.4, 0.95, 0.76),
	"enemy_shotgun": Color(1.32, 0.9, 0.72), "enemy_lmg": Color(1.3, 0.88, 0.72),
	"enemy_sniper": Color(1.36, 0.9, 0.78),
	"frogman": Color(1.35, 1.6, 1.7), "frogman_speargun": Color(1.35, 1.6, 1.7), "observer": Color(1.6, 1.2, 1.0),   # frogman/sol-12: bright cool "wet threat"
	"bunker": Color(1.0, 0.95, 0.82),
	"tank_body": OLIVE_VEH, "tank_barrel": OLIVE_VEH,
	"gunship_body": BOSS_VEH, "gunship_barrel": BOSS_VEH,
	"colossus_body": BOSS_VEH, "colossus_barrel": BOSS_VEH,
	"sandbag_beige": Color(0.88, 0.92, 0.66),
	"crate_ammo": Color(0.82, 0.88, 0.62), "crate_grenade": Color(0.82, 0.88, 0.62),
	"crate_airstrike": Color(0.82, 0.88, 0.62),
	# cactus_large/cactus_small/scrub/tumbleweed/dry_shrub entries below are all
	# shadowed at read time — tint() special-cases _DESERT_FLORA_KEYS before
	# consulting TINT — kept here only as the documented default.
	"cactus_large": DESERT_FOLIAGE, "cactus_small": DESERT_FOLIAGE, "scrub": DESERT_FOLIAGE,
	# Decor is SCENERY — muted and mossy so it recedes into the terrain and
	# never competes with the warm-bright enemies for the player's eye.
	"barrel": Color(0.72, 0.8, 0.6), "crate_stack": Color(0.78, 0.76, 0.62),
	"rock1": Color(0.68, 0.76, 0.62), "rock2": Color(0.68, 0.76, 0.62),
	"wreck": Color(0.62, 0.66, 0.58), "tent": Color(0.72, 0.82, 0.6),
	"watchtower": Color(0.72, 0.78, 0.62), "barbedwire": Color(0.7, 0.74, 0.68),
	"barrier": Color(0.76, 0.76, 0.62), "ammobox": Color(0.72, 0.8, 0.58),
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
	# iran-flag: barely muted so the faction colours still read, but not neon over the dusty scene.
	"flag_iran": Color(0.92, 0.9, 0.84),
	"dry_shrub": DESERT_FOLIAGE, "tumbleweed": DESERT_FOLIAGE,
	"wreck_halftrack": Color(0.55, 0.58, 0.52),
	"crater_field": Color(0.6, 0.6, 0.54), "crater_water": Color(0.62, 0.68, 0.72),
	"mg_tripod": Color(0.66, 0.7, 0.62),
	# fallen merc: heavy desert-olive multiply to pull the BR urban-blue kit onto
	# the battlefield palette; dropped shield muted like the wreck litter.
	"fallen_merc": Color(0.62, 0.64, 0.44), "dropped_shield": Color(0.6, 0.64, 0.56),
	# mil2 enemies read warm/bright (threats); vehicles olive-drab; pickups bright.
	"m_bombsuit": Color(1.7, 1.35, 0.9), "m_pilot": Color(1.5, 1.2, 1.0),   # sol-08: dropped m_contractor2/m_insurgent3-5 (retired)
	"m_soldier2": Color(1.1, 1.12, 0.95),
	"m_radar_tank": OLIVE_VEH, "m_rocket_truck": OLIVE_VEH,
	"m_jet": OLIVE_VEH, "m_heli_transport": OLIVE_VEH, "m_heli_attack2": OLIVE_VEH,
	"m_drone": Color(1.2, 1.3, 1.4), "m_technical": OLIVE_VEH,
	"wreck_apc": Color(0.55, 0.58, 0.52), "wreck_technical": Color(0.55, 0.58, 0.52),
	"wreck_light_tank": Color(0.55, 0.58, 0.52),
	"wep_grenade": Color(1.1, 1.15, 0.95),
	"wep_shotgun": Color(1.1, 1.1, 1.0), "wep_rifle": Color(1.1, 1.1, 1.0),
	"wep_mg": Color(1.1, 1.1, 1.0),
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
	"cactus_dead1": Color(0.72, 0.68, 0.55), "cactus_dead2": Color(0.72, 0.68, 0.55),
	"cactus_dead3": Color(0.72, 0.68, 0.55),
	"corpse_soldier1": Color(0.7, 0.68, 0.58), "corpse_soldier2": Color(0.7, 0.68, 0.58),
	"wall_sandbag": Color(0.88, 0.92, 0.66), "wall_sandbag_b": Color(0.88, 0.92, 0.66),
	"wall_sandbag_c": Color(0.88, 0.92, 0.66), "wall_sandbag_end": Color(0.88, 0.92, 0.66),
}

## Sprites that get a 1px dark outline in _spr() for readability on any ground.
const OUTLINE := {
	# sol-06: player1/player2 are OMITTED — the infantry set hero bakes its own thick black keyline,
	# so the _spr 1.7px rim on top read as a fat sticker and swallowed the 18px silhouette. The baked
	# contour carries the separation now (pin: test asserts the hero keys are NOT in OUTLINE).
	"rusher": true, "elite": true,
	"observer": true, "bunker": true,   # sol-12: frogman dropped — the pack diver bakes its own keyline (no double rim), matching hero/enemy
	"tank_body": true, "tank_barrel": true, "gunship_body": true,
	"gunship_barrel": true, "colossus_body": true, "colossus_barrel": true,
	"sandbag_beige": true, "mg_stand": true, "riot_shield": true,
	"crate_ammo": true, "crate_grenade": true, "crate_airstrike": true,
	"barrel": true, "crate_stack": true, "rock1": true, "rock2": true,
	"wreck": true, "watchtower": true, "barrier": true, "ammobox": true,
	"m_pilot": true,   # sol-08: dropped m_contractor2/m_insurgent3-5 (retired)
	# sie-01: m_bombsuit/m_soldier2 dropped from OUTLINE -- the re-baked authored art carries its
	# own black keyline, matching the enemy_* red-team convention (no double rim).
	"m_radar_tank": true, "m_rocket_truck": true, "m_jet": true,
	"m_heli_transport": true, "m_heli_attack2": true, "m_drone": true,
	"m_technical": true, "wreck_apc": true, "wreck_technical": true, "wreck_light_tank": true,
	"wep_grenade": true, "wep_shotgun": true,
	"wep_rifle": true, "wep_mg": true, "item_bullet": true, "item_bullet_shotgun": true,
	# The rare-capsule set: same ground-pickup class as the rifle/shotgun/mg
	# capsules above (plus the planted claymore + its ghost — rim alpha follows
	# tint.a, so the 0.28-alpha preview stays subtle).
	"icon_rend": true, "wep_claymore": true, "wep_smoke": true, "wep_flashbang": true,
	# sie-01: courier is the one remaining native-bake enemy infantry sprite (SUPPLY COURIER, main.gd
	# "courier"/"courier_escape") -- same blurry 64px legacy art class as the four re-baked below, deliberately
	# LEFT UNTOUCHED here: out of this item's scope, a fine target for a future infantry-family pass.
	"courier": true,
	# sie-01: ghillie/sapper dropped from OUTLINE too -- same re-bake, same baked keyline.
	"bunker2": true, "tank_hulk": true, "pickup_vest": true,
	"wall_sandbag": true, "wall_sandbag_b": true, "wall_sandbag_c": true, "wall_sandbag_end": true,
	"tank_trap": true, "barricade": true, "flak_gun": true, "trench": true,
	"flag_marker": true, "radio_tower": true, "dry_shrub": true, "tumbleweed": true,
	"wreck_halftrack": true, "crater_field": true, "crater_water": true, "mg_tripod": true,
	"dropped_shield": true, "fallen_merc": true,
	"cap_pierce": true, "cap_spread": true, "cap_triple": true, "cap_rend": true,
	"cap_claymore": true, "cap_smoke": true, "cap_flash": true,
}

const _GLYPH_PAD := {"interact": "ui_pad_x", "revive": "ui_pad_y",
	"roll": "ui_pad_b", "wheel": "ui_pad_back", "grenade": "glyph_lb"}
const _GLYPH_KEY := {"interact": "F", "revive": "E", "roll": "C", "wheel": "Q", "grenade": "SHIFT"}
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


static func group_digits(n: int) -> String:
	# a4-17: thousands separators so the big roguelite numbers scan at a glance
	# (264500 -> "264,500"). View-only display formatting.
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


static func tex(name: String) -> Texture2D:
	return TEX[name]


static func draw_scale(name: String) -> float:
	return SCALE.get(name, 1.0)


static func tint(name: String) -> Color:
	if _DESERT_FLORA_KEYS.has(name):
		return DESERT_FOLIAGE.lerp(FOLIAGE_ASH, foliage_march)
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


## Warning tier, passed EXPLICITLY by every caller. The tier is a semantic property of the
## readout — "is this the critical or the caution state?" — that the caller already knows, NOT
## something to re-derive from the tint's green channel. The old green >= 0.5 heuristic meant a
## future palette tweak (nudging a red-critical tint's green up, or an amber's down) could
## SILENTLY flip its tier and skip/apply the remap wrongly; naming the tier at the call site
## removes that whole failure class. CRITICAL is the default so an unclassified warning fails
## SAFE (gets the separating blue lift) rather than washing out.
enum { WARN_CRITICAL, WARN_CAUTION }


## Colorblind-safe warning remap — sibling of safe(); together they ARE the one colorblind
## palette (greens route through safe(), reds/ambers through warn()), so no HUD warning tint is a
## one-off hue shift. The red↔green axis collapses under deuteran/protan vision, so a red-critical
## tier that leaned on hue alone read the same as an amber caution. For the CRITICAL tier we raise
## the blue channel to WARN_CRIT_BLUE (== 0.55 of its red level), pushing it PART-WAY toward
## magenta — far enough that the blue axis (which survives red-green colorblindness) separates
## critical from the blue-poor amber tier, but not a full 1:1 red=blue that would wash the tint
## pink and lose its own hue. maxf() only ever LIFTS blue, so a tint already bluer than that keeps
## its value and its luminance, and the blink on/off pulse still reads. The CAUTION tier and
## non-colorblind pass through unchanged. Driven from main via `colorblind`.
const WARN_CRIT_BLUE := 0.55   # fraction of the red channel the critical tier's blue is lifted to
static func warn(red: Color, tier := WARN_CRITICAL) -> Color:
	if not colorblind or tier == WARN_CAUTION:
		return red
	return Color(red.r, red.g, maxf(red.b, red.r * WARN_CRIT_BLUE), red.a)


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


## LAYOUT-TEST SEAM. Non-null (an Array) only while a headless test is capturing:
## Art.text then RECORDS the box it would have painted and returns without touching the
## CanvasItem. This is the one choke point every string in the view passes through —
## the HUD/menu `_emit_*` seams cover their own primitives, but ~91 direct
## Art.text / Art.text_center callsites (hud/menu/main) bypass them, which made that ink
## structurally invisible to every layout assertion. Always null in the game; view-only,
## so the sim checksum is untouched.
## Records the same {k, id, box, alpha} shape the HUD capture harness uses, so a test can
## simply point this at its existing `boxes`/`ops` array and get merged geometry.
static var text_capture = null


## Shadowed text: black copy offset +1px, then the colored text on top — the
## drop-shadow pattern hand-inlined across the view, now in one place.
## max_w > 0 clips the string to that width instead of letting it bleed past the bound.
static func text(ci: CanvasItem, txt: String, pos: Vector2, size: int, col: Color, max_w := 0.0, outline := 0) -> void:
	var f := font()
	var w := max_w if max_w > 0.0 else -1.0
	# Snap to whole pixels: centered strings land on fractional x (cx - w/2 with
	# odd w), which smears a bitmap pixel font across two source texels under the
	# canvas's linear-mipmap filter. View-only, so golden-safe.
	pos = pos.floor()
	if text_capture != null:
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, w, size)
		text_capture.append({"k": "text", "id": txt, "alpha": col.a, "size": size,
			"box": Rect2(pos - Vector2(0.0, f.get_ascent(size)), sz)})
		return
	# outline > 0: a hard black rim for the mid-fight alert band — a 1px shadow
	# alone loses these glyphs against dirt noise under shake.
	if outline > 0:
		ci.draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, outline, Color(0, 0, 0, col.a))
	ci.draw_string(f, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, Color(0, 0, 0, 0.7))
	ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, w, size, col)


## Same shadow+color text, horizontally centered on cx at y.
static func text_center(ci: CanvasItem, txt: String, cx: float, y: float, size: int, col: Color, max_w := 0.0, outline := 0) -> void:
	var w := font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0:
		w = minf(w, max_w)
	text(ci, txt, Vector2(cx - w / 2.0, y), size, col, max_w, outline)


# Measured off the retired menu_button.png so the primitive plate reproduces the
# shipped value ramp: body 125/255, top rail 164/255, bottom rail 84/255.
const PLATE_BODY := 0.49
const PLATE_HI := 0.64
const PLATE_LO := 0.33
const PLATE_CHAMFER := 3.0

static func _chamfer_fill(ci: CanvasItem, b: Rect2, ch: float, col: Color) -> void:
	ci.draw_rect(Rect2(b.position.x, b.position.y + ch, b.size.x, b.size.y - 2.0 * ch), col)
	ci.draw_rect(Rect2(b.position.x + ch, b.position.y, b.size.x - 2.0 * ch, ch), col)
	ci.draw_rect(Rect2(b.position.x + ch, b.end.y - ch, b.size.x - 2.0 * ch, ch), col)


## Pixel-exact menu button plate. Replaces the 512x512 `ui_menu_button` bitmap,
## which draw_texture_rect squashed 3x-6.6x harder vertically than horizontally
## (222 x 15..36 from a square source) — the mixel tell. Crisp at ANY plate height.
static func menu_plate(ci: CanvasItem, r: Rect2, tint: Color) -> void:
	var b := Rect2(r.position.round(), r.size.round())
	var key := Color(tint.r * PLATE_HI, tint.g * PLATE_HI, tint.b * PLATE_HI, tint.a)
	_chamfer_fill(ci, b, PLATE_CHAMFER, key)                      # 1px keyline silhouette
	_chamfer_fill(ci, b.grow(-1.0), PLATE_CHAMFER - 1.0,
		Color(tint.r * PLATE_BODY, tint.g * PLATE_BODY, tint.b * PLATE_BODY, tint.a))
	ci.draw_rect(Rect2(b.position.x + PLATE_CHAMFER, b.end.y - 2.0,
		b.size.x - 2.0 * PLATE_CHAMFER, 1.0),
		Color(tint.r * PLATE_LO, tint.g * PLATE_LO, tint.b * PLATE_LO, tint.a))


## Hollow chamfered focus ring — the selection/BACK amber, drawn as whole-pixel
## rects (incl. a 1px-per-step corner staircase) so it can never resample.
static func focus_ring(ci: CanvasItem, r: Rect2, col: Color, thick := 1.0) -> void:
	var b := Rect2(r.position.round(), r.size.round())
	var ch := PLATE_CHAMFER
	ci.draw_rect(Rect2(b.position.x + ch, b.position.y, b.size.x - 2.0 * ch, thick), col)
	ci.draw_rect(Rect2(b.position.x + ch, b.end.y - thick, b.size.x - 2.0 * ch, thick), col)
	ci.draw_rect(Rect2(b.position.x, b.position.y + ch, thick, b.size.y - 2.0 * ch), col)
	ci.draw_rect(Rect2(b.end.x - thick, b.position.y + ch, thick, b.size.y - 2.0 * ch), col)
	for i in int(ch):
		ci.draw_rect(Rect2(b.position.x + ch - 1.0 - i, b.position.y + i, thick, thick), col)
		ci.draw_rect(Rect2(b.end.x - ch + i, b.position.y + i, thick, thick), col)
		ci.draw_rect(Rect2(b.position.x + ch - 1.0 - i, b.end.y - 1.0 - i, thick, thick), col)
		ci.draw_rect(Rect2(b.end.x - ch + i, b.end.y - 1.0 - i, thick, thick), col)


static func draw_glyph(ci: CanvasItem, action: String, pos: Vector2, size := 12.0, mod := Color.WHITE, force_pad := false, keycode := -1) -> void:
	# force_pad: P2 is hardwired to pad 1 (main._gather_inputs), so P2's OWN
	# prompts must show pad buttons even while P1's mouse aim keeps the global
	# use_pad false — per-player call sites pass `i == 1`.
	# gfx-loop review panel (Reviewok/ReviewMAX/ReviewGLM/ReviewGEM): the keyboard
	# letter used to be a hardcoded ship-default (_GLYPH_KEY) regardless of the
	# player's actual rebind (main.rebind() persists to _binds, and the REBIND
	# screen itself shows the live key via GameMenu.key_label() — only in-game
	# prompts didn't). `keycode` (a physical keycode from main.bind(action), -1 ==
	# "caller didn't pass one") lets callers route the live bind through here.
	var rect := Rect2(pos - Vector2(size, size) / 2.0, Vector2(size, size))
	if use_pad or force_pad:
		ci.draw_texture_rect(tex(_brand(_GLYPH_PAD[action])), rect, false, mod)
	else:
		ci.draw_texture_rect(tex("ui_key_blank"), rect, false, Color(0.96, 0.95, 0.88) * mod)
		var letter: String = GameMenu.key_label(keycode) if keycode >= 0 else _GLYPH_KEY[action]
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


## --- Pixel-grid draw primitives ---------------------------------------
## Godot's draw_arc/draw_circle/draw_line are smooth vector primitives — on a
## nearest-filtered 640x360 buffer they read as "vector UI over pixel art".
## These stand in with the SAME argument order as the builtins they replace
## (ci prepended), quantized to whole pixels via a cached distance-band
## bitmap, so every ring/line steps like the terrain grid instead of
## anti-aliasing against it. View-layer only — never called from src/sim.
static var _ring_cache := {}   # Vector3i(r, w, filled) -> {offsets, tex}


static func _ring_entry(r: int, w: int, filled: bool) -> Dictionary:
	var key := Vector3i(r, w, 1 if filled else 0)
	if _ring_cache.has(key):
		return _ring_cache[key]
	# ponytail: process-lifetime cache, but radii/widths only span a few dozen
	# distinct values in practice — cap it so a pathological caller can't grow
	# it unbounded. Bumped 64->128: measured live runs pin at 64 distinct keys
	# already, one novel radius from a full clear-and-rebuild hitch.
	if _ring_cache.size() > 128:
		_ring_cache.clear()
	var offs := PackedVector2Array()
	var r2 := r * r
	var inner := 0 if filled else maxi(0, r - w)
	# filled: -1 so d2 == 0 (the centre pixel) always passes d2 > inner2 —
	# otherwise inner2 == 0 excludes the centre and every filled disc ships
	# with a hollow-diamond hole (r=1 becomes 4 pixels instead of a solid dot).
	var inner2 := -1 if filled else inner * inner
	var img := Image.create_empty(r * 2 + 1, r * 2 + 1, false, Image.FORMAT_RGBA8)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 <= r2 and d2 > inner2:
				offs.append(Vector2(dx, dy))
				img.set_pixel(dx + r, dy + r, Color.WHITE)
	var entry := {"offsets": offs, "tex": ImageTexture.create_from_image(img)}
	_ring_cache[key] = entry
	return entry


## Mirrors draw_circle(position, radius, color, filled, width, antialiased) —
## a filled disc or a whole-pixel-width ring, pixel-grid shaped, cached.
static func circle(ci: CanvasItem, position: Vector2, radius: float,
		color: Color, filled := true, width := -1.0, _aa := false) -> void:
	var r := roundi(radius)
	if r <= 0:
		# Sub-pixel decorative dots (0.7 / 1.2 radius embers, grit) stay a
		# single speck instead of inflating to a 5px plus via maxi(1, ...).
		ci.draw_rect(Rect2(position.round(), Vector2.ONE), color)
		return
	var w := r if filled else maxi(1, roundi(width if width > 0.0 else 1.0))
	var entry := _ring_entry(r, w, filled)
	var p := position.round()
	ci.draw_texture_rect(entry["tex"], Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0 + Vector2.ONE),
		false, color)


## Mirrors draw_arc(center, radius, start_angle, end_angle, point_count,
## color, width, antialiased). A full sweep reuses the cached ring texture
## (one draw call); a partial sweep (cooldown dials, telegraphs) stamps the
## same cached offsets per-pixel, filtered to the angle window.
static func arc(ci: CanvasItem, center: Vector2, radius: float,
		start_angle: float, end_angle: float, _point_count: int,
		color: Color, width := 1.0, _aa := false) -> void:
	var r := roundi(radius)
	if r <= 0:
		ci.draw_rect(Rect2(center.round(), Vector2.ONE), color)
		return
	var w := maxi(1, roundi(width))
	var entry := _ring_entry(r, w, false)
	var c := center.round()
	var span := end_angle - start_angle
	if absf(span) >= TAU - 0.001:
		ci.draw_texture_rect(entry["tex"], Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0 + Vector2.ONE),
			false, color)
		return
	var lo := start_angle
	if span < 0.0:
		lo = end_angle
		span = -span
	for o in entry["offsets"]:
		var a: float = fposmod(o.angle() - lo, TAU) + lo
		if a <= lo + span:
			ci.draw_rect(Rect2(c + o, Vector2.ONE), color)


## Viewport + margin used to clip line() so an off-screen-anchored beam (e.g.
## a 900px sniper laser) doesn't emit hundreds of dead draw_rect calls for
## the off-frame portion (the cheap integer walk itself still runs).
const _CLIP := Rect2(-2.0, -2.0, 644.0, 364.0)

## Mirrors draw_line(from, to, color, width, antialiased): Bresenham, stamped
## as one perpendicular strip per major-axis step so thick/translucent lines
## get exactly one coverage per pixel (no compositing overlap) instead of an
## AA'd quad.
static func line(ci: CanvasItem, from: Vector2, to: Vector2,
		color: Color, width := 1.0, _aa := false) -> void:
	var w := maxi(1, roundi(width))
	var x0 := roundi(from.x)
	var y0 := roundi(from.y)
	var x1 := roundi(to.x)
	var y1 := roundi(to.y)
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var half := floori((w - 1) / 2.0)
	# x-major (shallow line): one 1-wide, w-tall strip per x step, thickness
	# applied vertically. y-major (steep line): mirrored. Either way each
	# pixel is covered by exactly one rect — no double-composited alpha.
	var x_major := dx >= -dy
	while true:
		if _CLIP.has_point(Vector2(x0, y0)):
			if x_major:
				ci.draw_rect(Rect2(x0, y0 - half, 1, w), color)
			else:
				ci.draw_rect(Rect2(x0 - half, y0, w, 1), color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## Dashed variant of line() — replaces draw_dashed_line(from, to, color,
## width, dash) call sites (those don't mirror a builtin 1:1, so this is a
## small hand-written helper rather than an argument-mirrored stand-in).
static func dashed_line(ci: CanvasItem, from: Vector2, to: Vector2,
		color: Color, width := 1.0, dash := 4.0) -> void:
	var total := from.distance_to(to)
	if total < 0.01:
		return
	var dir := (to - from) / total
	var t := 0.0
	var on := true
	while t < total:
		var seg_len := minf(dash, total - t)
		if on:
			line(ci, from + dir * t, from + dir * (t + seg_len), color, width)
		t += seg_len
		on = not on


## Closed/open polyline through points, replacing draw_polyline() call sites.
static func polyline(ci: CanvasItem, points: PackedVector2Array, color: Color, width := 1.0) -> void:
	for i in points.size() - 1:
		line(ci, points[i], points[i + 1], color, width)


## Rounds a polygon's points to whole pixels for draw_colored_polygon(), which
## has no pixel-grid substitute of its own (a filled triangle rasterizes fine —
## it's fractional VERTICES that put it off-grid).
static func rnd(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i].round()
	return out
