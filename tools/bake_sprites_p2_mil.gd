extends SceneTree
## p2 bake — military-pack half of assets/legacy-art/p2/ (ghillie/courier/sapper/
## tank_shell). Same recipe as tools/bake_sprites.gd; "attach" adds an
## attachment prefab at "attach_pos" so kit reads on the character from above.
##
## To reproduce (vendor stays read-only; only PNGs are written):
##
##   SRC="<GameAssets>/vendor/alt Military/Godot/polygon-military-01"
##   cp -R "$SRC/Assets" "$SRC/project.godot" /tmp/legacy-art-bake-p2/mil/
##   # patch /tmp/legacy-art-bake-p2/mil/project.godot renderer → "gl_compatibility"
##   cp tools/bake_sprites_p2_mil.gd /tmp/legacy-art-bake-p2/mil/
##   godot --headless --path /tmp/legacy-art-bake-p2/mil --import
##   SHOT_DIR=<repo>/assets/legacy-art/p2 godot --path /tmp/legacy-art-bake-p2/mil \
##       --rendering-method gl_compatibility -s res://bake_sprites_p2_mil.gd

const A := "res://Assets/legacy art/PolygonMilitary/Prefabs/"
const CH := A + "Characters/"
const AT := A + "Characters/Attachments/"
const VA := A + "Vehicles/Veh_Attachments/"

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

	jobs = [
		{"name": "ghillie", "src": CH + "SM_Chr_Ghillie_Male_01.tscn", "kind": "char", "px": 64},
		{"name": "courier", "src": CH + "SM_Chr_Insurgent_Male_01.tscn", "kind": "char", "px": 64,
			"attach": AT + "SM_Chr_Attach_Backpack_02.tscn", "attach_pos": Vector3(0, 1.25, 0.22)},
		{"name": "sapper", "src": CH + "SM_Chr_Insurgent_Male_02.tscn", "kind": "char", "px": 64,
			"attach": AT + "SM_Chr_Attach_Bomb_Kit_01.tscn", "attach_pos": Vector3(0, 1.25, 0.22)},
		{"name": "tank_shell", "src": VA + "SM_Veh_Attach_Tank_Round_01.tscn", "kind": "obj", "px": 32},
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
		var path := "%s/%s.png" % [out_dir, job["name"]]
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

	if job.has("attach"):
		var ascn := load(job["attach"]) as PackedScene
		if ascn:
			var att: Node3D = ascn.instantiate()
			stage.add_child(att)
			att.position = job["attach_pos"]
		else:
			push_error("MISSING ATTACH: " + job["attach"])

	if _frame_camera(stage):
		wait = 4
	else:
		_save_blank(job)
		call_deferred("_advance")


func _save_blank(job: Dictionary) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.save_png("%s/%s.png" % [out_dir, job["name"]])
	print("BLANK ", job["name"], " (no visible mesh)")


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
