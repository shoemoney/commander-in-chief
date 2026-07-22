extends SceneTree
## Raw-FBX → top-down sprite baker for Commander In Chief's War/War_Map/Nature props.
## legacy art FBX import grey (their atlas albedo isn't auto-assigned), so each job names
## the atlas to force onto every surface. Same ortho top-down rig + premultiply-resize
## as tools/bake_sprites_decor.gd so these read consistent with the shipped bakes.
## Run: SHOT_DIR=<out> godot --path <this project> --rendering-method gl_compatibility -s res://bake.gd

var out_dir := "/tmp"
var vp: SubViewport
var cam: Camera3D
var stage: Node3D
var jobs: Array[Dictionary] = []
var idx := -1
var wait := 0

const T := "res://tex/"
const F := "res://fbx/"


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

	# name = output PNG, fbx = source, atlas = albedo to force, px = output size.
	jobs = [
		{"name": "prop_tanktrap", "fbx": F + "SM_Prop_TankTrap_01.fbx", "atlas": T + "war_env.png", "px": 200},
		{"name": "prop_barricade", "fbx": F + "SM_Prop_Barricade_01.fbx", "atlas": T + "warmap_env.png", "px": 200},
		{"name": "prop_flak", "fbx": F + "SM_Prop_German_Flak_01.fbx", "atlas": T + "war_env.png", "px": 220},
		{"name": "env_trench", "fbx": F + "SM_Env_Trench_Straight_03.fbx", "atlas": T + "war_env.png", "px": 260},
		{"name": "env_flagwall", "fbx": F + "SM_Env_Flag_Wall_02_USA.fbx", "atlas": T + "war_flags.png", "px": 200},
		{"name": "prop_radiotower", "fbx": F + "SM_Prop_Radio_Tower_01.fbx", "atlas": T + "war_env.png", "px": 220},
		{"name": "env_hedge", "fbx": F + "SM_Env_Hedge_Bush_04.fbx", "atlas": T + "war_env.png", "px": 220},
		{"name": "wreck_halftrack", "fbx": F + "SM_Veh_German_Halftrack_01.fbx", "atlas": T + "war_vehicle.png", "px": 240},
		{"name": "env_crater_land", "fbx": F + "SM_Env_Crater_NomansLand_01.fbx", "atlas": T + "warmap_env.png", "px": 240},
		{"name": "env_crater_water", "fbx": F + "SM_Env_Crater_Water_01.fbx", "atlas": T + "warmap_env.png", "px": 240},
		{"name": "wep_mg_tripod", "fbx": F + "SM_Wep_British_HeavyMachineGun_Tripod_01.fbx", "atlas": T + "warmap_env.png", "px": 160},
		{"name": "plant_fern2", "fbx": F + "SM_Plant_Fern_03.fbx", "atlas": T + "nature.png", "px": 200},
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
		img.premultiply_alpha()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_unpremultiply(img)
		img.save_png("%s/%s.png" % [out_dir, job["name"]])
		print("SAVED ", job["name"], "  (", px, "px)")
		_advance()


func _unpremultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.001:
				img.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0),
					minf(c.b / c.a, 1.0), c.a))


func _advance() -> void:
	idx += 1
	if idx >= jobs.size():
		print("ALL BAKED")
		quit(0)
		return
	for c in stage.get_children():
		c.queue_free()
		stage.remove_child(c)

	var job := jobs[idx]
	var scn := load(job["fbx"]) as PackedScene
	if scn == null:
		push_error("MISSING FBX: " + job["fbx"])
		call_deferred("_advance")
		return
	var model: Node3D = scn.instantiate()
	stage.add_child(model)

	# Force the legacy art atlas onto every surface (FBX imports grey otherwise).
	var atlas := load(job["atlas"]) as Texture2D
	var meshcount := 0
	for mi in _all_meshes(model):
		meshcount += 1
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = atlas
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 0.85
		mat.metallic = 0.0
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)
	print("  ", job["name"], ": ", meshcount, " mesh(es)")

	if _frame_camera(model):
		wait = 4
	else:
		push_error("NO MESH: " + job["name"])
		call_deferred("_advance")


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _frame_camera(model: Node3D) -> bool:
	var aabb := AABB()
	var first := true
	for mi in _all_meshes(model):
		if not mi.is_visible_in_tree():
			continue
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
