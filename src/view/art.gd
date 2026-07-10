class_name Art
extends RefCounted
## Sprite registry for the view. All art is Kenney CC0 (kenney.nl) from the
## "Top-down Shooter" and "Top-down Tanks" packs — see assets/kenney/LICENSE-CC0.txt.
## View-layer only; the sim never touches textures.

const TEX := {
	"player1": preload("res://assets/kenney/player1.png"),
	"player2": preload("res://assets/kenney/player2.png"),
	"rusher": preload("res://assets/kenney/rusher.png"),
	"elite": preload("res://assets/kenney/elite.png"),
	"frogman": preload("res://assets/kenney/frogman.png"),
	"observer": preload("res://assets/kenney/observer.png"),
	"tank_body": preload("res://assets/kenney/tank_body.png"),
	"tank_barrel": preload("res://assets/kenney/tank_barrel.png"),
	"gunship_body": preload("res://assets/kenney/gunship_body.png"),
	"gunship_barrel": preload("res://assets/kenney/gunship_barrel.png"),
	"colossus_body": preload("res://assets/kenney/colossus_body.png"),
	"colossus_barrel": preload("res://assets/kenney/colossus_barrel.png"),
	"grass": preload("res://assets/kenney/grass.png"),
	"dirt": preload("res://assets/kenney/dirt.png"),
	"sand": preload("res://assets/kenney/sand.png"),
	"tree_large": preload("res://assets/kenney/tree_large.png"),
	"tree_small": preload("res://assets/kenney/tree_small.png"),
	"sandbag": preload("res://assets/kenney/sandbag.png"),
	"sandbag_beige": preload("res://assets/kenney/sandbag_beige.png"),
	"crate_ammo": preload("res://assets/kenney/crate_ammo.png"),
	"crate_grenade": preload("res://assets/kenney/crate_grenade.png"),
	"crate_airstrike": preload("res://assets/kenney/crate_airstrike.png"),
	"bullet": preload("res://assets/kenney/bullet.png"),
	"enemy_bullet": preload("res://assets/kenney/enemy_bullet.png"),
	"grenade": preload("res://assets/kenney/grenade.png"),
	"explosion0": preload("res://assets/kenney/explosion0.png"),
	"explosion1": preload("res://assets/kenney/explosion1.png"),
	"explosion2": preload("res://assets/kenney/explosion2.png"),
	"explosion3": preload("res://assets/kenney/explosion3.png"),
	"smoke": preload("res://assets/kenney/smoke.png"),
}


static func tex(name: String) -> Texture2D:
	return TEX[name]


static func cell_hash(ix: int, iy: int) -> int:
	## Cheap deterministic decor hash (view-only; not the sim RNG).
	var h := ix * 374761393 + iy * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
