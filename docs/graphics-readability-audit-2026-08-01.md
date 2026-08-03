# Battlefield graphics readability audit — 2026-08-01

Observed in the live Godot build at the native 640×360 presentation. The title,
pause screen, and Field Manual already have a strong hierarchy and cohesive
field-document language, so this pass concentrates on the battlefield.

1. **Give the hero a short-lived command chevron.** The player is only about 20 px tall
   and can disappear during the first visual scan; an opening/respawn locator answers
   “where am I?” without becoming permanent HUD clutter.
2. **Put a dark seat beneath the hero identity ring.** The existing green/gold ring loses
   contrast on pale sand and water; a neutral under-ring preserves its shape everywhere.
3. **Paint a brief northbound route through the landing zone.** New players are told to
   advance, but the broad tan field has no immediate directional rhythm.
4. **Give living riflemen a restrained warm footprint halo.** Their dark-red bodies share
   the value range of rocks, litter, and blast marks; a living-only floor card separates
   threats without changing their sprite family.
5. **Add a living-only chevron above ordinary riflemen.** Corpse piles contain the same
   uniforms, so a small consistent shape is a faster alive/dead read than pose details.
6. **Slightly enlarge the live rifleman silhouette.** The live body should own more area
   than its flattened corpse while remaining below elite visual weight.
7. **Back rifleman aim tells with a dark keyline.** The current amber line disappears on
   bright sand and inside orange/red combat effects.
8. **Add a white final-lock tick to rifleman tells.** The end of the short windup needs a
   frame-independent “shot is imminent” value change, not only a growing amber ember.
9. **Move hostile bullet glow behind the projectile.** Drawing glow over the card softens
   its outline and makes incoming fire resemble stationary impact sparks.
10. **Give hostile rounds a dark directional under-streak.** A keyline keeps the travel
    direction readable across sand, water, corpse pools, and explosions.
11. **Give hostile rounds a white-hot nose.** The bright head makes movement direction
    legible at a glance and separates live ordnance from red ground debris.
12. **Settle corpses smaller, flatter, darker, and less saturated.** Uniform color alone is
    not enough when several bodies overlap into a formation-sized mass.
13. **Shrink and dull blood pools.** Large saturated red splats compete with live enemies
    and hostile rounds for the danger color.
14. **Strengthen mission-critical edge markers.** The gate pointer currently reads like a
    second tiny diamond; a larger backed/rayed mark should outrank loot pointers.
15. **Give common supply crates a clearer plinth and beacon.** Grey crates resemble nearby
    rocks until the player is already close; the pickup grammar should read from the spawn.

All 15 are implemented in the accompanying readability pass. Timing and intensity values
are deliberately view-only and can be screenshot-tuned without changing simulation rules.
