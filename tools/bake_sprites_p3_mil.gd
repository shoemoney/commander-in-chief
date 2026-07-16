extends SceneTree
## p3 bake (military native-Godot pack) — replaces the blank gunship_barrel /
## colossus_barrel placeholders (assets/legacy-art/) and adds icons/icon_rend.png.
## Same recipe as tools/bake_sprites.gd (SubViewport, ortho cam, premultiply→
## Lanczos→unpremultiply); adds "yaw" (spin subject so the muzzle lands where
## the draw code expects) and "cam": "iso" (front three-quarter, icon style).
##
## Orientation contract (from src/main.gd draw calls):
##   colossus_barrel — muzzle UP in the PNG (drawn at rotation PI±0.5 → down).
##   gunship_barrel  — muzzle DOWN in the PNG (drawn at rotation 0.0).
##
## To reproduce (vendor stays read-only; only PNGs are written):
##
##   SRC="<GameAssets>/vendor/alt Military/Godot/polygon-military-01"
##   cp -R "$SRC/Assets" "$SRC/project.godot" $STAGE/
##   # patch $STAGE/project.godot renderer → "gl_compatibility"
##   cp tools/bake_sprites_p3_mil.gd $STAGE/
##   godot --headless --path $STAGE --import
##   SHOT_DIR=<repo>/assets/legacy-art godot --path $STAGE \
##       --rendering-method gl_compatibility -s res://bake_sprites_p3_mil.gd
##   mv <repo>/assets/legacy-art/icon_rend.png <repo>/assets/legacy-art/icons/

const A := "res://Assets/legacy art/PolygonMilitary/Prefabs/"
const VE := A + "Vehicles/"
const VA := A + "Vehicles/Veh_Attachments/"
const IT := A + "Items/"

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
		# APC Heavy turret+gun subtree reparented out of the hull (tank_barrel
		# trick). Gun models point +Z (screen-down) — yaw PI puts the muzzle up.
		{"name": "colossus_barrel", "src": VE + "SM_Veh_APC_Heavy_01.tscn",
			"only": ["Turret"], "px": 72, "yaw": PI},
		# Chin minigun already bakes muzzle-down (draw rotation 0.0 wants down).
		{"name": "gunship_barrel", "src": VA + "SM_Veh_Heli_Attach_Minigun.tscn",
			"px": 48, "yaw": 0.0},
		# Big AP round, front three-quarter like the existing icons/ bakes.
		# Model points tip-down (-Y); roll 180° so the tip reads up like icon_ammo.
		{"name": "icon_rend", "src": IT + "SM_Item_Bullet_Large_01.tscn",
			"px": 64, "cam": "iso", "rot": Vector3(0, 0, 180)},
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

	var subject: Node3D = model
	if job.has("only"):
		# Turret is parented under the hull mesh — reparent it out, drop the hull.
		var turret := _find_named(model, job["only"]) as Node3D
		if turret:
			var gt := turret.global_transform
			turret.get_parent().remove_child(turret)
			stage.add_child(turret)
			turret.global_transform = gt
			model.queue_free()
			subject = turret

	subject.rotate_y(job.get("yaw", 0.0))
	if job.has("rot"):
		subject.rotation_degrees = job["rot"]

	if _frame_camera(subject, job.get("cam", "top")):
		wait = 4
	else:
		_save_blank(job)
		call_deferred("_advance")


func _save_blank(job: Dictionary) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.save_png("%s/%s.png" % [out_dir, job["name"]])
	print("BLANK ", job["name"], " (no visible mesh)")


func _frame_camera(model: Node3D, kind: String) -> bool:
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
	if kind == "iso":
		# Front three-quarter: raised camera on +Z, matches assets/legacy-art/icons/.
		var d := aabb.size.length() + 4.0
		cam.global_position = center + Vector3(0, d * 0.85, d)
		cam.look_at(center, Vector3.UP)
		cam.size = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 1.3
		cam.near = 0.05
		cam.far = d * 4.0
	else:
		cam.global_position = center + Vector3(0, aabb.size.y + maxf(aabb.size.x, aabb.size.z) + 4.0, 0)
		cam.look_at(center, Vector3(0, 0, -1))   # world -Z = screen up
		cam.size = maxf(aabb.size.x, aabb.size.z) * 1.14
		cam.near = 0.05
		cam.far = cam.global_position.y - center.y + aabb.size.y + 10.0
	return true


func _all_mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _find_named(n: Node, tokens: Array) -> Node:
	for t in tokens:
		if String(n.name).findn(t) >= 0:
			return n
	for c in n.get_children():
		var r := _find_named(c, tokens)
		if r:
			return r
	return null
