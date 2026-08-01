# Soldier sprite generation record

Generated: 2026-07-31

The player soldier and five red-team enemy soldiers were regenerated with the
OpenAI built-in image-generation tool, using the former flat sprites as
composition references. The generated images used a uniform magenta chroma-key
background. That background was removed locally with the Codex image-generation
skill's `remove_chroma_key.py` helper using border auto-keying, a soft matte, and
despill. The six base assets were normalized to RGBA 1024 x 1024 canvases while
retaining the existing Godot import size limits (256 for the player, 128 for
enemies). Action sheets and projectile cards were generated in the same session,
keyed, sliced into individual transparent PNGs, and saved at their native runtime
sizes (256 x 256 player poses, 128 x 128 enemy poses, 128 x 32 projectiles).

## Files

- `soldier_assault_rifle.png`
- `enemy/enemy_assault_rifle.png`
- `enemy/enemy_smg.png`
- `enemy/enemy_shotgun.png`
- `enemy/enemy_lmg.png`
- `enemy/enemy_sniper.png`
- `anim/player/*.png` (12 poses)
- `anim/enemy_assault/*.png` (8 poses)
- `anim/enemy_smg/*.png` (8 poses)
- `anim/enemy_shotgun/*.png` (8 poses)
- `anim/enemy_lmg/*.png` (8 poses)
- `anim/enemy_sniper/*.png` (8 poses)
- `../projectiles/bullet_player.png`
- `../projectiles/bullet_piercing.png`
- `../projectiles/bullet_enemy.png`
- `../projectiles/bullet_sniper.png`

## Final player prompt

Redesign the existing player as one polished, strict 90-degree top-down soldier
facing north with an assault rifle pointing north. Preserve a centered gameplay
footprint and use crisp cel shading, dark keylines, believable anatomy, olive
combat clothing, tan webbing, dark boots, and large value shapes readable at
about 32 pixels tall. Give the hero a distinctive golden-orange/honey-blond
comb-over: long fine hair swept forward from the crown and diagonally across the
head in broad overlapping layers, a curved spiral flow, a voluminous rolled
front wave, swept-back sides, darker amber roots, visible comb lines, controlled
flyaways, and a smooth hairsprayed finish. Keep one isolated sprite on a flat
magenta chroma-key background, with no shadow, scenery, text, watermark,
isometric angle, helmet, or target-like head.

## Final enemy prompt family

Match the player's crisp cel-shaded overhead style while keeping a strong
friend/foe split: deep burgundy and brick-red clothing, dark helmet or hood,
tan/charcoal equipment, no orange hair, and no olive-dominant hero uniform.
Each file contains one centered north-facing soldier with its weapon pointing
north. Assault uses a balanced rifle silhouette; SMG is lean and lightly
equipped; shotgun is a broad breacher with a shell bandolier; LMG is the widest
gunner with an ammo belt and box magazine; sniper is narrow with a long scoped
rifle. Use clean readable value shapes, crisp opaque edges, one flat magenta
chroma-key background, and no shadows, scenery, text, watermark, extra figures,
or angled/isometric camera.

## Animation prompts and frame maps

The player sheet requested one exact 4 x 3 grid in the base hero's strict
overhead cel-shaded style. Its frame map is: idle, two forward steps, backward
step A; backward step B, concealed crouch, rifle recoil, grenade throw; dodge
roll, downed, interact/revive reach, empty-mag rifle bash. The prompt repeated
the golden-orange swept comb-over, olive/tan friend palette, north-facing
orientation, equal cell centers, flat magenta background, and exclusions for
text, shadows, scenery, extra figures, perspective drift, and clipped cells.

Each enemy weapon class used an exact 4 x 2 grid: idle, move A, move B, crouch;
wind-up, recoil, stunned, downed. The five prompts preserved their base weapon
silhouettes and shared burgundy/red hostile palette while requiring consistent
centering, north-facing strict overhead projection, matching proportions, equal
cell spacing, and a flat isolated magenta background.

## Projectile prompt and frame map

The projectile sheet requested an exact four-column row of right-facing cards:
a compact warm gold friendly rifle tracer, a longer cyan-white friendly armor-
piercing tracer, a crimson-rimmed white-core hostile rifle round, and a long
thin crimson/white hostile sniper penetrator. It required ample flat magenta
separation and excluded guns, casings, muzzle flashes, explosions, shadows,
labels, borders, scenery, watermarks, and extra objects. Godot rotates these
right-facing cards onto the existing projectile velocity vectors at draw time.

## Processing record

The original generated sheets and keyed intermediates are retained under
`.gsd/runs/character-animation/generated/`. Review montages are under
`.gsd/runs/character-animation/previews/`. Magenta was removed with the
image-generation skill's border auto-key, soft matte, and despill workflow;
frames were then sliced, disconnected cross-cell fragments removed, centered,
and normalized without altering gameplay scale, timing, or collision data.
