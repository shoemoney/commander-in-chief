# Enemy spawn shouts — first-sight battle cries

Played when an **infantry** unit first enters the viewport (not machines).

| Phrase | Script | Files |
|--------|--------|-------|
| Marg bar Amrika | مرگ بر آمریکا (fa) | `marg_bar_amrika_*` |
| Marg bar Esrail | مرگ بر اسرائیل (fa) | `marg_bar_esrail_*` |
| Allahu Akbar | الله أكبر (ar) | `allahu_akbar_*` |

**Voices:** bill, daniel, brian, callum, harry, roger  
**Takes:** 3–4 per voice × phrase  
**Pipeline:** in-house text-to-speech synthesis

Wired in `Sfx.play_spawn_shout()` ← `main._tick_spawn_yells()` (55% chance + 0.37s cooldown).
