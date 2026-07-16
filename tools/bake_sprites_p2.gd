extends SceneTree
## legacy 3D pack War (FBX-only pack) → top-down sprite baker for Project Ikari.
## Same pipeline as tools/bake_sprites_decor.gd (ortho top-down, transparent
## SubViewport, premultiply→Lanczos→unpremultiply) but the FBX packs ship
## meshes with BLANK materials, so every surface gets a StandardMaterial3D
## with the pack's texture atlas assigned as albedo — skip that and bakes
## come out grey.
##
## Runs inside /tmp/legacy-art-bake-war/ (FBX files + atlas PNGs copied from the
## read-only vendor; only PNGs are written):
##
##   godot --headless --path /tmp/legacy-art-bake-war --import
##   SHOT_DIR=<repo>/assets/legacy-art/p2 godot --path /tmp/legacy-art-bake-war \
##       --rendering-method gl_compatibility -s res://bake_p2.gd

const WAR_ATLAS := "res://PolygonWar_Texture_01_A.png"
const FX_ATLAS := "res://PolygonParticles_Texture_01_A.png"

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
	vp.size = Vector2i(640, 640)
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

	# px = output square size; matched to the shipped sprite each replaces
	# (tree_large.png 120 / sandbag scale / cast2/bunker.png 440).
	jobs = [
		{"name": "tree_dead1", "src": "res://SM_Env_Tree_Dead_01.fbx", "atlas": WAR_ATLAS, "px": 120},
		{"name": "tree_dead2", "src": "res://SM_Env_Tree_Dead_02.fbx", "atlas": WAR_ATLAS, "px": 120},
		{"name": "tree_dead3", "src": "res://SM_Env_Tree_Dead_03.fbx", "atlas": WAR_ATLAS, "px": 120},
		{"name": "wall_sandbag", "src": "res://SM_Env_Sandbag_Wall_Long_01.fbx", "atlas": WAR_ATLAS, "px": 240},
		{"name": "wall_sandbag_end", "src": "res://SM_Env_Sandbag_Wall_End_01.fbx", "atlas": WAR_ATLAS, "px": 120},
		{"name": "bunker2", "src": "res://SM_Bld_Bunker_02.fbx", "atlas": WAR_ATLAS, "px": 440},
		{"name": "corpse_soldier1", "src": "res://SM_Char_DeadBody_01.fbx", "atlas": WAR_ATLAS, "px": 140},
		{"name": "corpse_soldier2", "src": "res://SM_Char_DeadBody_02.fbx", "atlas": WAR_ATLAS, "px": 140},
		# Flame card baked FACE-ON (billboard) + unshaded so it keeps the flat
		# legacy art particle style like the shipped assets/legacy-art/fx/ cards. Keeps
		# the FBX's own diffuse-color materials (the ParticleFX atlas is a
		# palette sheet — this mesh's colors live in the FBX materials).
		{"name": "fx_flame", "src": "res://SM_Flame_FX.fbx", "px": 200,
			"face_on": true, "unshaded": true},
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
	var scn := load(job["src"]) as PackedScene
	if scn == null:
		push_error("MISSING FBX: " + job["src"])
		_save_blank(job)
		call_deferred("_advance")
		return
	var model: Node3D = scn.instantiate()
	stage.add_child(model)

	# FBX meshes import with blank materials — assign the pack atlas or the
	# bake comes out grey. Jobs without an atlas keep the FBX's own materials
	# (flattened unshaded so they read as flat particle cards).
	if job.has("atlas"):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(job["atlas"])
		mat.roughness = 1.0
		mat.metallic = 0.0
		if job.get("unshaded", false):
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mi in _all_mesh_instances(model):
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)
	elif job.get("unshaded", false):
		# legacy art colors the flame with a Unity gradient shader the FBX can't
		# carry (its material is flat grey) — recreate it: flat unshaded
		# yellow-core → orange-red tip gradient along local Y.
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float y_min;
uniform float y_max;
varying float h;
void vertex() { h = VERTEX.y; }
void fragment() {
	float t = clamp((h - y_min) / max(y_max - y_min, 0.0001), 0.0, 1.0);
	ALBEDO = mix(vec3(1.0, 0.82, 0.25), vec3(0.93, 0.32, 0.08), t);
}
"""
		for mi in _all_mesh_instances(model):
			var ab := mi.get_aabb()
			var grad := ShaderMaterial.new()
			grad.shader = sh
			grad.set_shader_parameter("y_min", ab.position.y)
			grad.set_shader_parameter("y_max", ab.position.y + ab.size.y)
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, grad)

	if _frame_camera(model, job.get("face_on", false)):
		wait = 4
	else:
		_save_blank(job)
		call_deferred("_advance")


func _save_blank(job: Dictionary) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.save_png("%s/%s.png" % [out_dir, job["name"]])
	print("BLANK ", job["name"], " (no visible mesh)")


func _frame_camera(model: Node3D, face_on: bool) -> bool:
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
	print("AABB ", jobs[idx]["name"], " size=", aabb.size)
	var center := aabb.position + aabb.size * 0.5
	if face_on:
		# Camera looks straight at the card from +Z (billboard read).
		cam.global_position = center + Vector3(0, 0, aabb.size.z + maxf(aabb.size.x, aabb.size.y) + 4.0)
		cam.look_at(center, Vector3(0, 1, 0))
		cam.size = maxf(aabb.size.x, aabb.size.y) * 1.14
		cam.far = cam.global_position.z - center.z + aabb.size.z + 10.0
	else:
		cam.global_position = center + Vector3(0, aabb.size.y + maxf(aabb.size.x, aabb.size.z) + 4.0, 0)
		cam.look_at(center, Vector3(0, 0, -1))   # world -Z = screen up
		cam.size = maxf(aabb.size.x, aabb.size.z) * 1.14
		cam.far = cam.global_position.y - center.y + aabb.size.y + 10.0
	cam.near = 0.05
	return true


func _all_mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _find_first(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null
