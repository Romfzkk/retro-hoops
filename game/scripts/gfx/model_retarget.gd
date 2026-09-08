class_name ModelRetarget
extends RefCounted

# Animator rotations use the player's axes. Imported bone poses use their
# parent's axes, after any correction from the authored rest to arms-down.
const LIMB_ENDS := {
	"shoulder_l": "elbow_l", "elbow_l": "wrist_l",
	"shoulder_r": "elbow_r", "elbow_r": "wrist_r",
	"hip_l": "knee_l", "knee_l": "ankle_l",
	"hip_r": "knee_r", "knee_r": "ankle_r",
}

var _neutral: Dictionary = {}
var _frames: Dictionary = {}
var _skeleton: Skeleton3D
var _bones: Dictionary
var _to_rig: Basis


func _init(skeleton: Skeleton3D, bones: Dictionary, to_rig: Transform3D) -> void:
	_skeleton = skeleton
	skeleton.reset_bone_poses()
	_bones = bones
	_to_rig = to_rig.basis.orthonormalized()
	for root in skeleton.get_parentless_bones():
		_prepare(root, Transform3D.IDENTITY)


func _prepare(index: int, parent_pose: Transform3D) -> void:
	var local := _skeleton.get_bone_rest(index)
	var global_pose := parent_pose * local
	var key := String(_bones.find_key(index)) if _bones.find_key(index) != null else ""
	if LIMB_ENDS.has(key):
		var end: int = _bones[LIMB_ENDS[key]]
		var relative := _skeleton.get_bone_global_rest(index).affine_inverse() \
			* _skeleton.get_bone_global_rest(end).origin
		var direction := (global_pose.basis * relative).normalized()
		var down := _to_rig.inverse() * Vector3.DOWN
		if direction.length_squared() > 0.5:
			var correction := Quaternion(direction, down)
			global_pose.basis = Basis(correction) * global_pose.basis
			local.basis = parent_pose.basis.inverse() * global_pose.basis
	# Children inherit the corrected parent. Correcting every limb against the
	# original T-pose would rotate the forearm a second time at the elbow.
	_neutral[index] = local.basis.orthonormalized().get_rotation_quaternion()
	_frames[index] = (_to_rig * parent_pose.basis.orthonormalized()).get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(index, _neutral[index])
	for child in _skeleton.get_bone_children(index):
		_prepare(child, global_pose)


func write(index: int, rotation: Quaternion) -> void:
	var frame: Quaternion = _frames[index]
	var neutral: Quaternion = _neutral[index]
	_skeleton.set_bone_pose_rotation(index,
		(frame.inverse() * rotation * frame * neutral).normalized())
