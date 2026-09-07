extends Node3D

# Development scene: loads a .glb from anywhere on disk, reports what it does
# and does not carry, and renders it next to a reference figure the height of a
# player. Character art arrives from outside the project, so this is the first
# thing to point at a new export.
#
# godot --path game res://scenes/dev_model.tscn -- --model C:/path/to/file.glb --shot out.png

const REFERENCE_HEIGHT := 1.98


func _ready() -> void:
	var path := FrameCapture.argument("--model")
	if path.is_empty():
		push_error("--model <path to .glb> is required")
		get_tree().quit(1)
		return
	_build_stage()
	var model := _load_glb(path)
	if model == null:
		get_tree().quit(1)
		return
	add_child(model)
	_report(path, model)
	_frame_camera(model)
	FrameCapture.attach(self)


func _load_glb(path: String) -> Node3D:
	# Anything already inside the project has been through the importer, which
	# is the only way FBX and Collada get read at all. Loose .glb files are
	# parsed straight off disk so an export can be checked without copying it in.
	if path.begins_with("res://"):
		var scene := ResourceLoader.load(path) as PackedScene
		if scene == null:
			push_error("%s did not import as a scene" % path)
			return null
		return scene.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		push_error("No file at %s" % path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("%s is not readable as glTF: %s" % [path, error_string(err)])
		return null
	return doc.generate_scene(state) as Node3D


func _report(path: String, root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	var skeletons := root.find_children("*", "Skeleton3D", true, false)

	var vertices := 0
	var surfaces := 0
	var has_normals := false
	var has_uvs := false
	var has_bone_weights := false
	var named_materials := 0
	var textures := 0
	for instance in meshes:
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			surfaces += 1
			var format: int = mesh.surface_get_format(surface)
			has_normals = has_normals or bool(format & Mesh.ARRAY_FORMAT_NORMAL)
			has_uvs = has_uvs or bool(format & Mesh.ARRAY_FORMAT_TEX_UV)
			has_bone_weights = has_bone_weights \
				or bool(format & Mesh.ARRAY_FORMAT_BONES)
			var material := mesh.surface_get_material(surface)
			if material != null:
				named_materials += 1
				if material is BaseMaterial3D \
						and (material as BaseMaterial3D).albedo_texture != null:
					textures += 1
			var arrays := mesh.surface_get_arrays(surface)
			vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	var bounds := _bounds(meshes)
	print("\n--- %s ---" % path.get_file())
	print("  meshes            %d  (%d surfaces, %d vertices)"
		% [meshes.size(), surfaces, vertices])
	print("  size              %.3f x %.3f x %.3f  (a player is about 1.98 tall)"
		% [bounds.size.x, bounds.size.y, bounds.size.z])
	if bounds.size.y > 0.001 and absf(bounds.size.y - REFERENCE_HEIGHT) > 0.4:
		print("  scale needed      x%.1f to stand %.2fm"
			% [REFERENCE_HEIGHT / bounds.size.y, REFERENCE_HEIGHT])
	print("  normals           %s" % _mark(has_normals))
	print("  UVs               %s" % _mark(has_uvs))
	print("  skin weights      %s" % _mark(has_bone_weights))
	print("  skeleton          %s" % _mark(not skeletons.is_empty()))
	print("  materials         %s" % _mark(named_materials > 0))
	print("  textures          %s" % _mark(textures > 0))
	print("  animations        %s"
		% _mark(not root.find_children("*", "AnimationPlayer", true, false).is_empty()))
	var blocked := not has_uvs or not has_bone_weights or skeletons.is_empty()
	print("  usable as a player: %s" % ("no" if blocked else "yes"))
	for skeleton: Skeleton3D in skeletons:
		print("  skeleton '%s': %d bones" % [skeleton.name, skeleton.get_bone_count()])
		for bone in skeleton.get_bone_count():
			print("      %2d %-28s parent %d" % [bone, skeleton.get_bone_name(bone),
				skeleton.get_bone_parent(bone)])


func _mark(present: bool) -> String:
	return "yes" if present else "no"


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


func _bounds(meshes: Array[MeshInstance3D]) -> AABB:
	var box := AABB()
	var started := false
	for instance in meshes:
		if instance.mesh == null:
			continue
		var local := instance.mesh.get_aabb()
		box = local if not started else box.merge(local)
		started = true
	return box


# A featureless capsule the height of a player, so scale and proportion are
# obvious instead of guessed at.
func _build_stage() -> void:
	var reference := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = REFERENCE_HEIGHT
	capsule.radius = 0.26
	reference.mesh = capsule
	reference.position = Vector3(1.4, REFERENCE_HEIGHT * 0.5, 0.0)
	reference.material_override = Materials.flat(Color(0.22, 0.24, 0.28), 0.9)
	add_child(reference)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	ground.material_override = Materials.flat(Color(0.10, 0.11, 0.13), 0.95)
	add_child(ground)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 2.4, 2.8)
	fill.omni_range = 14.0
	fill.light_energy = 0.7
	add_child(fill)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.44, 0.5)
	env.ambient_light_energy = 0.55
	world.environment = env
	add_child(world)


func _frame_camera(model: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect(model, meshes)
	var box := _bounds(meshes)
	# Mixamo exports in centimetres and other tools vary, so normalise to a
	# player's height for the preview rather than rendering a speck or a tower.
	if box.size.y > 0.001:
		var fit := REFERENCE_HEIGHT / box.size.y
		if absf(fit - 1.0) > 0.2:
			model.scale = Vector3.ONE * fit
			box = AABB(box.position * fit, box.size * fit)
	# Sit the model on the floor whatever origin it was exported around.
	model.position.y = -box.position.y
	var height := maxf(box.size.y, 0.5)

	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0.9, height * 0.62, height * 2.1)
	add_child(camera)
	camera.look_at(Vector3(0.7, height * 0.5, 0.0))
