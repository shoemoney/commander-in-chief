# Enemy death yells — agony bank

Male Arabic death cries played on **infantry kills** (not drones/techs/nests).

| Phrase | Arabic |
|--------|--------|
| Ya Zahra | يا زهراء |
| Ya Hossein | يا حسين |

**Voices (user-approved):** bill, daniel, brian, callum, harry, roger  
**Delivery:** agony / pain / dying (synthesis audio tags)  
**Pipeline:** in-house text-to-speech synthesis  

Wired in `src/view/sfx.gd` → `play_death_yell()`, called from `main._ev_kill`.
