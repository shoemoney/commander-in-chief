extends SceneTree
## legacy 3D pack Military → top-down sprite baker for Commander In Chief.
## Regenerates assets/art/*.png (units, vehicles, props, foliage) from the
## purchased legacy art pack. Renders each model through an orthographic top-down
## Camera3D into a transparent SubViewport and saves a per-sized PNG.
##
## This runs INSIDE a copy of the legacy 3D pack Military *native Godot project*
## (never the game project — it needs the pack's meshes/materials imported).
## To reproduce (vendor stays read-only; only PNGs are written):
##
##   SRC="<GameAssets>/vendor/alt Military/Godot/polygon-military-01"   # (vendor flattened 2026-07)
##   cp -R "$SRC/Assets" "$SRC/project.godot" /tmp/legacy-art-bake/
##   # patch /tmp/legacy-art-bake/project.godot renderer → "gl_compatibility"
##   cp tools/bake_sprites.gd /tmp/legacy-art-bake/
##   godot --headless --path /tmp/legacy-art-bake --import
##   SHOT_DIR=<repo>/assets/art godot --path /tmp/legacy-art-bake \
##       --rendering-method gl_compatibility -s res://bake_sprites.gd
##
## Tint + per-sprite draw-scale live in src/view/art.gd, applied in main._spr().

const A := "res://Assets/legacy art/PolygonMilitary/Prefabs/"
const CH := A + "Characters/"
const VE := A + "Vehicles/"
const PR := A + "Props/"
const BL := A + "Buildings/"
const EN := A + "Environment/"
const WE := A + "Weapons/"
const IT := A + "Items/"

# Turret/weapon name tokens used to split hull (body) from turret (barrel).
const TANK_T := ["Turret", "Barrel"]
const HELI_T := ["Minigun", "Gun", "Rocket", "Weapon", "Barrel"]
const APC_T := ["Turret", "Barrel", "Gun", "Weapon"]

var out_dir := "/tmp"
var vp: SubViewport
var cam: Camera3D
var stage: Node3D
var jobs: Array[Dictionary] = []
var idx := -1
var wait := 0


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"

	vp = SubViewport.new()
	vp.size = Vector2i(320, 320)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)

	# Muted lighting: top-down sees top faces, so keep energy low or they clip
	# to white. Steep-ish key gives a shadowed side for readable silhouettes.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.85)
	env.ambient_light_energy = 0.32
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, 28, 0)
	key.light_energy = 0.9
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-90, 0, 0)
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	vp.add_child(fill)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)

	stage = Node3D.new()
	vp.add_child(stage)

	# px = output square size (≈ the Kenney sprite it replaces; scales retuned in-game).
	jobs = [
		# --- New enemy characters ---
		{"name": "contractor2", "src": CH + "SM_Chr_Contractor_Male_02.tscn", "kind": "char", "px": 64},
		{"name": "bombsuit", "src": CH + "SM_Chr_Bombsuit_Male_01.tscn", "kind": "char", "px": 64},
		{"name": "insurgent3", "src": CH + "SM_Chr_Insurgent_Male_03.tscn", "kind": "char", "px": 64},
		{"name": "insurgent4", "src": CH + "SM_Chr_Insurgent_Male_04.tscn", "kind": "char", "px": 64},
		{"name": "insurgent5", "src": CH + "SM_Chr_Insurgent_Male_05.tscn", "kind": "char", "px": 64},
		{"name": "pilot", "src": CH + "SM_Chr_Pilot_Male_01.tscn", "kind": "char", "px": 56},
		{"name": "soldier2", "src": CH + "SM_Chr_Soldier_Male_02.tscn", "kind": "char", "px": 64},
		# --- New vehicles ---
		{"name": "apc", "src": VE + "SM_Veh_APC_01.tscn", "kind": "obj", "px": 104},
		{"name": "radar_tank", "src": VE + "SM_Veh_Radar_Tank_01.tscn", "kind": "obj", "px": 104},
		{"name": "rocket_truck", "src": VE + "SM_Veh_Rocket_Truck_01.tscn", "kind": "obj", "px": 104},
		{"name": "jet", "src": VE + "SM_Veh_Jet_01.tscn", "kind": "obj", "px": 128},
		{"name": "heli_transport", "src": VE + "SM_Veh_Helicopter_Transport_01.tscn", "kind": "obj", "px": 112},
		{"name": "heli_attack2", "src": VE + "SM_Veh_Helicopter_Attack_02.tscn", "kind": "obj", "px": 112},
		{"name": "drone", "src": VE + "SM_Veh_Drone_01.tscn", "kind": "obj", "px": 48},
		{"name": "light_tank", "src": VE + "SM_Veh_Light_Tank_01.tscn", "kind": "obj", "px": 96},
		{"name": "technical", "src": VE + "SM_Veh_Pickup_Technical_01.tscn", "kind": "obj", "px": 96},
		# --- Weapon pickup sprites ---
		{"name": "wep_grenade", "src": WE + "SM_Wep_Grenade_01.tscn", "kind": "obj", "px": 40},
		{"name": "wep_rpg", "src": WE + "SM_Wep_RPG_01.tscn", "kind": "obj", "px": 64},
		{"name": "wep_shotgun", "src": WE + "SM_Wep_Shotgun_01.tscn", "kind": "obj", "px": 56},
		{"name": "wep_rifle", "src": WE + "SM_Wep_Rifle_01.tscn", "kind": "obj", "px": 56},
		{"name": "wep_mg", "src": WE + "SM_Wep_MachineGun_USA_01.tscn", "kind": "obj", "px": 56},
		{"name": "wep_pistol", "src": WE + "SM_Wep_Pistol_01.tscn", "kind": "obj", "px": 40},
		{"name": "wep_claymore", "src": WE + "SM_Wep_Claymore_01.tscn", "kind": "obj", "px": 40},
		{"name": "wep_smoke", "src": WE + "SM_Wep_Grenade_Smoke_01.tscn", "kind": "obj", "px": 40},
		{"name": "wep_flashbang", "src": WE + "SM_Wep_Flashbang_01.tscn", "kind": "obj", "px": 40},
		# --- Items ---
		{"name": "item_bullet", "src": IT + "SM_Item_Bullet_01.tscn", "kind": "obj", "px": 32},
		{"name": "item_bullet_shotgun", "src": IT + "SM_Item_Bullet_Shotgun_01.tscn", "kind": "obj", "px": 32},
		{"name": "item_binoculars", "src": IT + "SM_Item_Binoculars_01.tscn", "kind": "obj", "px": 40},
	]

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if idx == -1:
		_advance()
		return
	if idx >= jobs.size():
		return
	wait -= 1
	if wait <= 0:
		var job := jobs[idx]
		var img := vp.get_texture().get_image()
		var px: int = job["px"]
		# Premultiply → resize → unpremultiply: kills the Lanczos dark-halo fringe
		# (straight-alpha resize drags transparent black into edge texels).
		img.premultiply_alpha()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_unpremultiply(img)
		var path := "%s/%s.png" % [out_dir, job["name"]]
		img.save_png(path)
		print("SAVED ", path, "  (", px, "px)")
		_advance()


func _unpremultiply(img: Image) -> void:
	# Inverse of premultiply_alpha (Godot has no built-in): divide RGB back out.
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.001:
				img.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0),
					minf(c.b / c.a, 1.0), c.a))


func _advance() -> void:
	idx += 1
	if idx >= jobs.size():
		print("ALL SPRITES BAKED")
		quit(0)
		return
	for c in stage.get_children():
		c.queue_free()
		stage.remove_child(c)

	var job := jobs[idx]
	if job.get("blank", false):
		_save_blank(job)
		call_deferred("_advance")
		return
	var scn := load(job["src"]) as PackedScene
	if scn == null:
		push_error("MISSING PREFAB: " + job["src"])
		_save_blank(job)
		call_deferred("_advance")
		return
	var model: Node3D = scn.instantiate()
	stage.add_child(model)

	if job["kind"] == "char":
		var sk: Skeleton3D = _find_first(model, "Skeleton3D")
		if sk:
			_aim_bone(sk, "Shoulder_L", "Elbow_L", Vector3(-0.25, -1.0, 0.15))
			_aim_bone(sk, "Shoulder_R", "Elbow_R", Vector3(0.25, -1.0, 0.15))

	var subject: Node3D = model
	if job.has("hide"):
		_filter(model, job["hide"], false)
	elif job.has("only"):
		# These vehicles parent everything under the hull mesh, so hiding the
		# hull would hide the turret too. Reparent the turret out instead.
		var turret := _find_named(model, job["only"]) as Node3D
		if turret:
			var gt := turret.global_transform
			turret.get_parent().remove_child(turret)
			stage.add_child(turret)
			turret.global_transform = gt
			model.queue_free()
			subject = turret

	if _frame_camera(subject):
		wait = 4
	else:
		_save_blank(job)
		call_deferred("_advance")


func _save_blank(job: Dictionary) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.save_png("%s/%s.png" % [out_dir, job["name"]])
	print("BLANK ", job["name"], " (no visible mesh)")


# Hide (keep=false) or isolate (keep=true) meshes whose name — or an ancestor's —
# contains any token.
func _filter(model: Node, tokens: Array, keep: bool) -> void:
	for mi in _all_meshes_any(model):
		var matched := false
		var n: Node = mi
		while n != null and n != model.get_parent():
			for t in tokens:
				if String(n.name).findn(t) >= 0:
					matched = true
					break
			if matched:
				break
			n = n.get_parent()
		mi.visible = (matched == keep)


func _frame_camera(model: Node3D) -> bool:
	var aabb := AABB()
	var first := true
	for mi in _all_mesh_instances(model):
		var a := mi.global_transform * mi.get_aabb()
		if first:
			aabb = a
			first = false
		else:
			aabb = aabb.merge(a)
	if first:
		return false
	var center := aabb.position + aabb.size * 0.5
	cam.global_position = center + Vector3(0, aabb.size.y + maxf(aabb.size.x, aabb.size.z) + 4.0, 0)
	cam.look_at(center, Vector3(0, 0, -1))   # world -Z = screen up
	cam.size = maxf(aabb.size.x, aabb.size.z) * 1.14
	cam.near = 0.05
	cam.far = cam.global_position.y - center.y + aabb.size.y + 10.0
	return true


func _aim_bone(sk: Skeleton3D, bone: String, child: String, target_dir: Vector3) -> void:
	var bi := sk.find_bone(bone)
	var ci := sk.find_bone(child)
	if bi < 0 or ci < 0:
		return
	var g := sk.get_bone_global_pose(bi)
	var cg := sk.get_bone_global_pose(ci)
	var cur := (cg.origin - g.origin).normalized()
	var q := Quaternion(cur, target_dir.normalized())
	var new_basis := Basis(q) * g.basis
	var pi := sk.get_bone_parent(bi)
	var parent_basis := sk.get_bone_global_pose(pi).basis if pi >= 0 else Basis()
	var local := parent_basis.inverse() * new_basis
	sk.set_bone_pose_rotation(bi, local.get_rotation_quaternion())


func _all_mesh_instances(n: Node) -> Array[MeshInstance3D]:
	# Visible-in-tree meshes only — used for framing.
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _all_meshes_any(n: Node) -> Array[MeshInstance3D]:
	# Every mesh regardless of visibility — used for the turret filter.
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes_any(c))
	return out


func _find_named(n: Node, tokens: Array) -> Node:
	# First node (depth-first) whose name contains any token.
	for t in tokens:
		if String(n.name).findn(t) >= 0:
			return n
	for c in n.get_children():
		var r := _find_named(c, tokens)
		if r:
			return r
	return null


func _find_first(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null
