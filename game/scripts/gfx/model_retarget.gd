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

	# Parents first: a limb is straightened against what its parent has already
	# done to it, not against the bind pose it started from.
	var ordered: Array = bones.keys()
	ordered.sort_custom(func(a, b): return _depth(bones[a]) < _depth(bones[b]))
	for key in ordered:
		var index: int = bones[key]
		if index >= 0:
			_fixes[index] = _straighten(index, String(key), _inherited_fix(index))
	for key in bones:
		var index: int = bones[key]
		if index >= 0:
			write(index, Quaternion.IDENTITY)
	flush()


## Skeleton3D recomputes global poses during the process step, so anything that
## sets poses and reads them back in the same frame - the rig measuring its own
## reach, a test asserting a limb hangs down - otherwise sees the rest pose and
## concludes nothing was written.
## The bone's transform built from the poses actually set on it.
##
## get_bone_global_pose does not reflect a pose rotation in its children's
## origins here - rotating a bone ninety degrees leaves the child exactly where
## it was - so anything measuring where a limb points has to compose the chain
## itself.
func posed(index: int) -> Transform3D:
	var result := _skeleton.get_bone_pose(index)
	var cursor := _skeleton.get_bone_parent(index)
	while cursor >= 0:
		result = _skeleton.get_bone_pose(cursor) * result
		cursor = _skeleton.get_bone_parent(cursor)
	return result


func flush() -> void:
	_skeleton.force_update_all_bone_transforms()


## Rotation from where a limb actually rests to straight down, in the player's
## axes. Taken from bone positions rather than bone bases: this skeleton carries
## non-uniform scale, and orthonormalising a scaled basis does not recover the
## rotation it was built from, which leaves each limb short of vertical by a
## different amount.
func _straighten(index: int, key: String,
		inherited: Quaternion) -> Quaternion:
	if not LIMB_ENDS.has(key) or not _bones.has(LIMB_ENDS[key]):
		return Quaternion.IDENTITY
	var end: int = _bones[LIMB_ENDS[key]]
	if end < 0:
		return Quaternion.IDENTITY
	var span: Vector3 = _to_rig * (_skeleton.get_bone_global_rest(end).origin
		- _skeleton.get_bone_global_rest(index).origin)
	if span.length_squared() < 0.000001:
		return Quaternion.IDENTITY
	# Aim at where down ends up once the parents have had their turn, so the
	# chain composes to vertical instead of each joint overshooting by whatever
	# the one above it did.
	return Quaternion(span.normalized(), (inherited.inverse() * Vector3.DOWN).normalized())


## How deep a bone sits, so a pass can be ordered from the root down.
func _depth(index: int) -> int:
	var steps := 0
	var cursor := _skeleton.get_bone_parent(index)
	while cursor >= 0:
		steps += 1
		cursor = _skeleton.get_bone_parent(cursor)
	return steps


## The straightening already applied above this bone, root first.
func _inherited_fix(index: int) -> Quaternion:
	var chain: Array[Quaternion] = []
	var cursor := _skeleton.get_bone_parent(index)
	while cursor >= 0:
		if _fixes.has(cursor):
			chain.push_front(_fixes[cursor])
		cursor = _skeleton.get_bone_parent(cursor)
	var total := Quaternion.IDENTITY
	for step in chain:
		total = total * step
	return total


func write(index: int, rotation: Quaternion) -> void:
	if not _rest.has(index):
		_skeleton.set_bone_pose_rotation(index, rotation)
		return
	var frame: Quaternion = _frames[index]
	var straightened: Quaternion = rotation * (_fixes[index] as Quaternion)
	_skeleton.set_bone_pose_rotation(index,
		((frame.inverse() * straightened * frame) * (_rest[index] as Quaternion))
			.normalized())
