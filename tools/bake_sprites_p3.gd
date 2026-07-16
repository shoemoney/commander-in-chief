extends SceneTree
## p3 bake — FBX-only props from SIMPLE Military + POLYGON War for the p3
## asset pass: MG emplacement, bridge segments, skyline silhouettes, crater.
## Same pipeline as tools/bake_sprites_p2.gd (ortho cam, transparent
## SubViewport, premultiply→Lanczos→unpremultiply) and the same FBX gotcha:
## FBX meshes import with BLANK materials, so every surface gets a
## StandardMaterial3D with the pack's texture atlas as albedo or it bakes grey.
## Two p3 wrinkles found the hard way:
##   * The bridge FBXes EMBED their texture (importer extracts
##     SM_Env_Bridge_*_0.png) — overriding with the War atlas scrambles them.
##     Jobs without "atlas" reuse the embedded albedo instead.
##   * Bridge deck faces are back-culled from a top-down camera — "nocull"
##     bakes with CULL_DISABLED so the walkable deck actually renders.
##   * The Mg stand maps to Tex_Military_Green (Textures_Props puts blue
##     crate texels on the gun).
## "face_on" jobs bake a SIDE view (camera on +Z) for horizon silhouettes.
##
## Runs inside a staging dir (FBX + atlas PNGs copied from the read-only
## vendor; only PNGs are written):
##
##   T=$(mktemp -d)
##   V=/Users/shoemoney/Projects/GameAssets/vendor
##   cp "$V/Military/Fbx/SM_Prop_Mg_stand_01.fbx" \
##      "$V/Military/Textures/Tex_Military_Green.png" \
##      "$V/War/FBX/SM_Env_Bridge_Middle.fbx" "$V/War/FBX/SM_Env_Bridge_Ramp.fbx" \
##      "$V/War/FBX/SM_Prop_Chimney_01.fbx" "$V/War/FBX/SM_Prop_Radio_Tower_01.fbx" \
##      "$V/War/FBX/SM_Env_Crater_02.fbx" \
##      "$V/War/Textures/PolygonWar_Texture_01_A.png" \
##      tools/bake_sprites_p3.gd "$T/"
##   printf 'config_version=5\n[application]\nconfig/name="bake"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n' > "$T/project.godot"
##   godot --headless --path "$T" --import
##   SHOT_DIR=<repo>/assets/legacy-art godot --path "$T" \
##       --rendering-method gl_compatibility -s res://bake_sprites_p3.gd

const WAR_ATLAS := "res://PolygonWar_Texture_01_A.png"
const MIL_ATLAS := "res://Tex_Military_Green.png"

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

	# px = baked square size, decor-convention resolution (160-260 like the
	# shipped decor/); art.gd draw-scales down to on-screen size (~48/~96 px).
	# "out" is the subdir under SHOT_DIR (= assets/legacy-art).
	jobs = [
		{"name": "mg_stand", "out": "mil2", "src": "res://SM_Prop_Mg_stand_01.fbx",
			"atlas": MIL_ATLAS, "px": 160},
		{"name": "bridge_mid", "out": "decor", "src": "res://SM_Env_Bridge_Middle.fbx",
			"px": 220, "nocull": true},
		{"name": "bridge_ramp", "out": "decor", "src": "res://SM_Env_Bridge_Ramp.fbx",
			"px": 220, "nocull": true},
		{"name": "skyline_chimney", "out": "decor", "src": "res://SM_Prop_Chimney_01.fbx",
			"atlas": WAR_ATLAS, "px": 160, "face_on": true},
		{"name": "skyline_mast", "out": "decor", "src": "res://SM_Prop_Radio_Tower_01.fbx",
			"atlas": WAR_ATLAS, "px": 200, "face_on": true},
		{"name": "crater", "out": "decor", "src": "res://SM_Env_Crater_02.fbx",
			"atlas": WAR_ATLAS, "px": 160},
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
		# Premultiply → resize → unpremultiply kills the Lanczos dark-halo fringe.
		img.premultiply_alpha()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_unpremultiply(img)
		var path := "%s/%s/%s.png" % [out_dir, job["out"], job["name"]]
		img.save_png(path)
		print("SAVED ", path, "  (", px, "px)")
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

	# FBX gotcha: blank materials → assign pack atlas as albedo on every surface.
	# Jobs without "atlas" (the bridges) reuse the FBX's own embedded texture.
	var mis := _all_mesh_instances(model)
	var mat := StandardMaterial3D.new()
	if job.has("atlas"):
		mat.albedo_texture = load(job["atlas"])
	elif not mis.is_empty():
		var own := mis[0].mesh.surface_get_material(0) as BaseMaterial3D
		if own:
			mat.albedo_texture = own.albedo_texture
	mat.roughness = 1.0
	mat.metallic = 0.0
	if job.get("nocull", false):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in mis:
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)

	if _frame_camera(model, job.get("face_on", false)):
		wait = 4
	else:
		_save_blank(job)
		call_deferred("_advance")


func _save_blank(job: Dictionary) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.save_png("%s/%s/%s.png" % [out_dir, job["out"], job["name"]])
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
		# SIDE view: camera on +Z looking at the model (horizon silhouette).
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
