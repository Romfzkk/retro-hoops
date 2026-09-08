class_name ModelRig
extends RefCounted

# Asset loading, normalization and the bundled texture's kit mask.
# ModelRetarget owns the conversion between animator and imported bone axes.

const ASSET := "res://art/player.fbx"
const KIT_SHADER := "res://shaders/player_kit.gdshader"
const KIT_TEXTURE := "res://art/player_kit.png"

## Animator joint name to the bone that actually moves it. The game's
## "shoulder" is the joint the upper arm pivots about, which is Mixamo's Arm;
## Mixamo's Shoulder is the clavicle and stays where it is.
const BONE_NAMES := {
	"hips": "mixamorig_Hips",
	"spine": "mixamorig_Spine1",
	"chest": "mixamorig_Spine2",
	"head": "mixamorig_Head",
	"shoulder_l": "mixamorig_LeftArm",
	"elbow_l": "mixamorig_LeftForeArm",
	"shoulder_r": "mixamorig_RightArm",
	"elbow_r": "mixamorig_RightForeArm",
	"hip_l": "mixamorig_LeftUpLeg",
	"knee_l": "mixamorig_LeftLeg",
	"ankle_l": "mixamorig_LeftFoot",
	"hip_r": "mixamorig_RightUpLeg",
	"knee_r": "mixamorig_RightLeg",
	"ankle_r": "mixamorig_RightFoot",
}

const WRIST_BONES := {"l": "mixamorig_LeftHand", "r": "mixamorig_RightHand"}

static var _scene: PackedScene
static var _missing := false
static var _asset_path := ASSET


static func preview_asset(path: String) -> void:
	assert(path.begins_with("res://"), "Import the test character into the project first")
	_asset_path = path
	_scene = null
	_missing = false


static func available() -> bool:
	if _missing:
		return false
	if _scene != null:
		return true
	if not ResourceLoader.exists(_asset_path):
		_missing = true
		push_error("Player asset is unavailable: " + _asset_path)
		return false
	_scene = ResourceLoader.load(_asset_path) as PackedScene
	_missing = _scene == null
	return not _missing


## Repaints the model into a team's colours. The kit is baked into the texture,
## so the shader classifies each texel rather than swapping a material.
static func apply_kit(skeleton: Skeleton3D, team: Dictionary, player: Dictionary) -> void:
	if _asset_path != ASSET:
		return
	var shader := ResourceLoader.load(KIT_SHADER) as Shader
	if shader == null:
		push_error("Player kit shader could not be loaded: " + KIT_SHADER)
		return
	const TONES := [
		Color(0.96, 0.79, 0.67), Color(0.86, 0.66, 0.51), Color(0.72, 0.52, 0.38),
		Color(0.55, 0.37, 0.26), Color(0.40, 0.26, 0.18), Color(0.28, 0.19, 0.13),
	]
	var skin_texture := ResourceLoader.load(KIT_TEXTURE) as Texture2D
	if skin_texture == null:
		push_error("Player kit texture could not be loaded: " + KIT_TEXTURE)
		return
	var model_root: Node3D = skeleton.get_meta("model_root")
	for instance: MeshInstance3D in model_root.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("base_texture", skin_texture)
			material.set_shader_parameter("jersey_colour", Color(team["primary"]))
			material.set_shader_parameter("trim_colour", Color(team["secondary"]))
			material.set_shader_parameter("skin_colour",
				TONES[clampi(int(player["skin"]), 0, TONES.size() - 1)])
			instance.set_surface_override_material(surface, material)


static func instantiate(parent: Node3D, height: float) -> Skeleton3D:
	if not available():
		return null
	var root := _scene.instantiate() as Node3D
	if root == null:
		push_error("Player asset root must be Node3D")
		return null
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.size() != 1:
		push_error("Player asset must contain exactly one skeleton")
		root.free()
		return null
	var skeleton: Skeleton3D = found[0]
	var problems := validate(root, skeleton)
	if not problems.is_empty():
		push_error("Player asset rejected: " + "; ".join(problems))
		root.free()
		return null
	# Normalize a wrapper, preserving authored transforms on every imported node.
	var wrapper := Node3D.new()
	wrapper.name = "CharacterModel"
	wrapper.add_child(root)
	var bounds := model_bounds(wrapper)
	if bounds.size.y <= 0.0001:
		push_error("Player asset has no measurable height")
		wrapper.free()
		return null
	var fit := height / bounds.size.y
	wrapper.scale = Vector3.ONE * fit
	# The bundled FBX's toes and face point +Z; gameplay faces -Z.
	wrapper.rotation.y = PI
	wrapper.position = Basis(Vector3.UP, PI) * Vector3(-bounds.get_center().x,
		-bounds.position.y, -bounds.get_center().z) * fit
	parent.add_child(wrapper)
	skeleton.set_meta("model_root", root)
	return skeleton


static func validate(root: Node3D, skeleton: Skeleton3D) -> PackedStringArray:
	var problems := PackedStringArray()
	var names := BONE_NAMES.duplicate()
	names["wrist_l"] = WRIST_BONES["l"]
	names["wrist_r"] = WRIST_BONES["r"]
	for bone_name in names.values():
		if skeleton.find_bone(bone_name) < 0:
			problems.append("missing bone " + bone_name)
	for index in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		if not _rotation_space_supported(rest):
			problems.append("bake nonuniform scale or reflection on " + skeleton.get_bone_name(index))
	if not _rotation_space_supported(root.transform * relative_transform(skeleton, root)):
		problems.append("bake nonuniform scale or reflection above the skeleton")
	var chains := {
		"elbow_l": "shoulder_l", "elbow_r": "shoulder_r",
		"knee_l": "hip_l", "knee_r": "hip_r",
		"ankle_l": "knee_l", "ankle_r": "knee_r",
		"wrist_l": "elbow_l", "wrist_r": "elbow_r",
		"hip_l": "hips", "hip_r": "hips", "spine": "hips",
		"chest": "spine", "head": "chest",
	}
	for child_key in chains:
		var child := skeleton.find_bone(names[child_key])
		var parent := skeleton.find_bone(names[chains[child_key]])
		if child >= 0 and parent >= 0:
			var cursor := skeleton.get_bone_parent(child)
			while cursor >= 0 and cursor != parent:
				cursor = skeleton.get_bone_parent(cursor)
			if cursor != parent:
				problems.append("invalid hierarchy for " + child_key)
	var skinned := false
	for instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			var format: int = instance.mesh.surface_get_format(surface)
			if format & Mesh.ARRAY_FORMAT_BONES and format & Mesh.ARRAY_FORMAT_WEIGHTS:
				skinned = true
	if not skinned:
		problems.append("no skinned mesh surfaces")
	return problems


static func _rotation_space_supported(transform: Transform3D) -> bool:
	if not transform.is_finite() or transform.basis.determinant() <= 0.0:
		return false
	var scale := transform.basis.get_scale()
	return is_equal_approx(scale.x, scale.y) and is_equal_approx(scale.y, scale.z)


static func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor := node
	while cursor != ancestor:
		assert(cursor != null, "Node is not below the requested ancestor")
		result = cursor.transform * result
		cursor = cursor.get_parent_node_3d()
	return result


static func model_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var started := false
	for instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		var local := relative_transform(instance, root) * instance.mesh.get_aabb()
		box = local if not started else box.merge(local)
		started = true
	return box
