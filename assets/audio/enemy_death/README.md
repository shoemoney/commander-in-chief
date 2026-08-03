# Enemy death yells — agony bank

Male Arabic death cries played on **infantry kills** (not drones/techs/nests).

| Phrase | Arabic |
|--------|--------|
| Ya Zahra | يا زهراء |
| Ya Hossein | يا حسين |

**Voices (user-approved):** bill, daniel, brian, callum, harry, roger  
**Delivery:** agony / pain / dying (synthesis audio tags)  
**Pipeline:** commissioned through a hosted TTS service — the stock voice roster above is
ElevenLabs', so that is the inferred source. Inferred from the recorded parameters, not from
a logged API call; see `ASSETS.md` for what that means for downstream licensing.  

Wired in `src/view/sfx.gd` → `play_death_yell()`, called from `main._ev_kill`.
