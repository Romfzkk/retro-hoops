class_name ModelRetarget
extends RefCounted

# The animator writes rotations as if every limb hangs straight down from its
# joint and +X swings it forward. An imported skeleton agrees with neither: its
# bones run along their own axes, and it is bound in whatever pose the artist
# chose, a T-pose here. This closes both gaps.
#
# A bone's local transform is measured against its parent, so a rotation meant
# in the player's axes is carried into the parent's frame rather than the
# bone's own. The straightening is folded in ahead of the rotation, so that a
# zero rotation is arms-down instead of whatever the bind happened to be.

## Limb joints and the joint below each one. Everything else keeps its bind
## orientation, which already stacks the way the animator expects of a spine.
const LIMB_ENDS := {
	"shoulder_l": "elbow_l", "elbow_l": "wrist_l",
	"shoulder_r": "elbow_r", "elbow_r": "wrist_r",
	"hip_l": "knee_l", "knee_l": "ankle_l",
	"hip_r": "knee_r", "knee_r": "ankle_r",
}

var _rest: Dictionary = {}
var _frames: Dictionary = {}
var _fixes: Dictionary = {}
var _skeleton: Skeleton3D
var _bones: Dictionary
var _to_rig: Basis


func _init(skeleton: Skeleton3D, bones: Dictionary, to_rig: Transform3D) -> void:
	_skeleton = skeleton
	skeleton.reset_bone_poses()
	_bones = bones
	_to_rig = to_rig.basis.orthonormalized()
	for key in bones:
		var index: int = bones[key]
		if index < 0:
			continue
		# The bone's own rest, relative to its parent, is what a pose rotation
		# is applied on top of.
		_rest[index] = skeleton.get_bone_rest(index).basis.orthonormalized() \
			.get_rotation_quaternion()
		var parent := skeleton.get_bone_parent(index)
		var parent_basis := Basis.IDENTITY if parent < 0 \
			else skeleton.get_bone_global_rest(parent).basis
		_frames[index] = (_to_rig * parent_basis.orthonormalized()) \
			.get_rotation_quaternion()
		_fixes[index] = _straighten(index, String(key))
	for key in bones:
		var index: int = bones[key]
		if index >= 0:
			write(index, Quaternion.IDENTITY)
	flush()


## Skeleton3D recomputes global poses during the process step, so anything that
## sets poses and reads them back in the same frame - the rig measuring its own
## reach, a test asserting a limb hangs down - otherwise sees the rest pose and
## concludes nothing was written.
func flush() -> void:
	_skeleton.force_update_all_bone_transforms()


## Rotation from where a limb actually rests to straight down, in the player's
## axes. Taken from bone positions rather than bone bases: this skeleton carries
## non-uniform scale, and orthonormalising a scaled basis does not recover the
## rotation it was built from, which leaves each limb short of vertical by a
## different amount.
func _straighten(index: int, key: String) -> Quaternion:
	if not LIMB_ENDS.has(key) or not _bones.has(LIMB_ENDS[key]):
		return Quaternion.IDENTITY
	var end: int = _bones[LIMB_ENDS[key]]
	if end < 0:
		return Quaternion.IDENTITY
	var span: Vector3 = _to_rig * (_skeleton.get_bone_global_rest(end).origin
		- _skeleton.get_bone_global_rest(index).origin)
	if span.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	return Quaternion(span.normalized(), Vector3.DOWN)


func write(index: int, rotation: Quaternion) -> void:
	if not _rest.has(index):
		_skeleton.set_bone_pose_rotation(index, rotation)
		return
	var frame: Quaternion = _frames[index]
	var straightened: Quaternion = rotation * (_fixes[index] as Quaternion)
	_skeleton.set_bone_pose_rotation(index,
		((frame.inverse() * straightened * frame) * (_rest[index] as Quaternion))
			.normalized())
