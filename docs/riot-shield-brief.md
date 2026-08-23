# Riot Shield — the advertised flank is kinematically impossible

Filed by the behaviour lens, `/triple-a-game` cycle 1, 2026-08-22. Every number below was
MEASURED by driving the real sim headlessly, not derived from reading constants.

## The arithmetic

| constant | value | source |
|---|---|---|
| `PLAYER_SPEED` | 2.4 px/tick | `sim_world.gd:23` |
| `SHIELD_TURN_STEP` | 1/32 rad/tick = 1.79°/tick | `sim_world.gd:180` |
| `SHIELD_SPEED` | 1 px/tick | `sim_world.gd:177` |
| `ENEMY_TOUCH_RADIUS` | 10 px (instant kill) | `sim_world.gd:197` |

Orbiting at radius `r`, your bearing changes at `PLAYER_SPEED / r` rad/tick. The shield out-turns
you whenever `2.4 / r < 1/32`, i.e. for any **r > 76.8 px**.

## Measured — tangential strafe at full speed, 4,000 ticks (66 s)

```
r=20  -> arc opens in  11 ticks
r=40  ->               36
r=60  ->              119
r=70  ->              344
r=77, 80, 90, 100, 120, 150, 200, 240 -> NEVER
```

At r >= 77 the facing's **maximum lag behind your bearing across all 4,000 ticks is 0.0°** — not
"slowly loses ground", literally zero. `_turn_shield_toward`'s snap
(`if dot >= 0 and absi(cross) <= SHIELD_TURN_STEP`) lands it exactly on your bearing every tick.

**Every standoff range the game ships is outside the bubble:**
RIFLEMAN 100 · ELITE 120 · DRONE 130 · GRENADIER 150 · SNIPER 240.
So `sim_world.gd:179`'s own claim — "a player circling at safe standoff can get outside the
120-degree block cone" — is false at every standoff it ships.

## Measured — real duel, real auto-fire, shield closing (`SHIELD_SPEED` 1 px/tick)

| start range | ticks to open | separation when it opened | rounds fired | blocked |
|---|---|---|---|---|
| 240 px | 536 (8.9 s) | **13 px** | 51 | 30 (59%) |
| 120 px | 106 | 20 px | 14 | 13 (93%) |
| control: plain elite @120 | 18 | — | 3 | 0 |

The arc only opens because the shield walks INTO you. 13 px is **3 px outside
`ENEMY_TOUCH_RADIUS`**, which kills outright. The shield costs ~6x the time and ~5x the ammo of an
equivalent elite, and the counter the game names FIRST is the one that cannot be executed.

## The three promises, all still shipping

1. `src/main.gd:391` — hint card `"RIOT SHIELD — FLANK OR BLOW IT OPEN"`
2. `src/view/menu.gd:5630` — Field Manual `"SHIELD — front eats bullets. Flank it, blast it, or use Rend."`
3. `src/main.gd:10331` — a **persistent green rear SAFE-arc drawn on his back every frame**,
   commented "teaches 'get around him'"

A persistent green arc on an enemy's back is the strongest "go here" signal a top-down shooter
has, and this one is welded to a vector that is provably unreachable. A player will try it, orbit
for seconds, burn half a magazine into the plate, and get nothing — which reads as a broken enemy,
not a hard one.

## The fork — OWNER DECISION, not a defect fix

**A. Make the promise true (SIM, goldens move).** Slow the turn so the flank works at the ranges
the game actually fights at. Break-even `r = PLAYER_SPEED / SHIELD_TURN_STEP`, so opening the
flank at ELITE_STANDOFF (120) needs `SHIELD_TURN_STEP <= 2.4/120 = 0.02` rad/tick — i.e. `F_ONE/50`
against today's `F_ONE/32`. That is a **balance change**: it makes the shield materially easier
everywhere, and this project's own doctrine says the loop must not tune balance unasked.
*Starting value, needs a play test: `F_ONE/50` opens the arc at <=120px; pass condition is that a
committed lateral move earns the rear arc inside ~2s at ELITE_STANDOFF without making the shield
a non-threat at close range.*

**B. Delete the promise (VIEW only, golden-free).** Stop drawing the rear SAFE-arc, and reword
both strings to name the counters that DO work — explosives and Rend Rounds — since
`_shield_blocks` only gates bullets. Honest immediately, costs nothing, and loses a mechanic the
game currently advertises but does not have.

**C. Both, split.** Ship B now (the lie is live in every run), and treat A as a separate balance
pass with its own play test.

Recommendation: **C**. The lie is shipping today and B is free; A changes how every shieldman
fights and deserves to be judged on its own, not smuggled in under a bug fix.
