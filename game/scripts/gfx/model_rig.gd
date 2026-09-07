class_name ModelRig
extends RefCounted

# Binds an externally authored, rigged character to the joint names the animator
# writes to, so the same procedural animation drives an artist's mesh.
#
# Two things stop the animator's output from being usable as-is. The animator's
# convention is that a bone hangs down -Y and +X swings it forward; every bone
# in a Mixamo skeleton runs along +Y in its own space instead. And the bind pose
# is an A-pose, not an axis-aligned rest, so a pose rotation has to be applied
# as a delta on top of the rest rather than replacing it.

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


static func available() -> bool:
	if _missing:
		return false
	if _scene != null:
		return true
	if not ResourceLoader.exists(ASSET):
		_missing = true
		return false
	_scene = ResourceLoader.load(ASSET) as PackedScene
	_missing = _scene == null
	return not _missing


## Instances the model under `parent`, scaled so it stands `height` metres.
## Returns the skeleton, or null when the asset is not usable.
## Repaints the model into a team's colours. The kit is baked into the texture,
## so the shader classifies each texel rather than swapping a material.
static func apply_kit(skeleton: Skeleton3D, team: Dictionary, player: Dictionary,
		height: float) -> void:
	var shader := ResourceLoader.load(KIT_SHADER) as Shader
	if shader == null:
		return
	const TONES := [
		Color(0.96, 0.79, 0.67), Color(0.86, 0.66, 0.51), Color(0.72, 0.52, 0.38),
		Color(0.55, 0.37, 0.26), Color(0.40, 0.26, 0.18), Color(0.28, 0.19, 0.13),
	]
	for instance: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			# Always the masked copy: the imported material's own texture has no
			# head mask in its alpha.
			var skin_texture := ResourceLoader.load(KIT_TEXTURE) as Texture2D
			if skin_texture == null:
				# The importer can hand back a material with the image detached.
				# Without a texture every texel reads as black and the whole
				# player comes out one flat team colour.
				skin_texture = ResourceLoader.load(KIT_TEXTURE) as Texture2D
			if skin_texture == null:
				push_warning("No player texture; kit colours will be flat")
				continue
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
		return null
	parent.add_child(root)
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("%s has no skeleton" % ASSET)
		root.queue_free()
		return null
	var skeleton: Skeleton3D = found[0]
	# Mixamo works in centimetres and the export lands about two hundred times
	# too small, so derive the factor from the mesh rather than hard-coding it.
	var bounds := _model_bounds(root)
	if bounds.size.y > 0.0001:
		var fit := height / bounds.size.y
		root.scale = Vector3.ONE * fit
		# The skeleton is rooted at the hips, and the game rigs everything from
		# the floor up. Without this the whole player stands a metre low, which
		# reads as the feet sinking through the court.
		root.position.y = -bounds.position.y * fit
	return skeleton


static func _model_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var started := false
	for instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		var local := instance.mesh.get_aabb()
		box = local if not started else box.merge(local)
		started = true
	return box
