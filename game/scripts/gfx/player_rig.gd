class_name PlayerRig
extends Node3D

# A skinned humanoid on a real skeleton, generated at load.
#
# The body is one continuous lofted surface bound to bones, so bending an elbow
# deforms the skin. The previous rig hung a separate primitive off every joint,
# which is exactly what made it read as parts bolted together.
#
# Kit is two more skinned surfaces over the same skeleton, so a jersey moves
# with the chest instead of floating near it.
#
# Local axes: bones hang down -Y. +X rotation swings a limb forward (-Z),
# +Z swings it out to the player's left.

## Joints the animator writes to. Order is irrelevant; names must match.
const JOINTS := [
	"hips", "spine", "chest", "head",
	"shoulder_l", "elbow_l", "shoulder_r", "elbow_r",
	"hip_l", "knee_l", "ankle_l", "hip_r", "knee_r", "ankle_r",
]

var joints: Dictionary = {}
var hand_l: Node3D
var hand_r: Node3D
var head_node: Node3D
var height := 1.98
var shoulder_height := 1.55
var standing_reach := 2.6

var pose: Dictionary = {}
var _target_pose: Dictionary = {}
var _bones: Dictionary = {}
var _skeleton: Skeleton3D
var _detail := 1
var _visible_body := true


static func create(player: Dictionary, team: Dictionary, host: Node,
		with_meshes: bool = true) -> PlayerRig:
	var rig := PlayerRig.new()
	rig.name = "Rig"
	rig.height = float(player["h"]) * 0.01
	rig._detail = 0 if OS.has_feature("mobile") else 1
	rig._visible_body = with_meshes
	rig._build(player, team, host)
	return rig


func _build(player: Dictionary, team: Dictionary, host: Node) -> void:
	var body := _proportions(player)
	shoulder_height = body["hip_y"] + body["torso"]
	standing_reach = shoulder_height + body["upper_arm"] + body["forearm"] \
		+ body["hand"]

	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	_build_skeleton(body)

	for key in JOINTS:
		pose[key] = Vector3.ZERO
		_target_pose[key] = Vector3.ZERO

	hand_l = _attach_to_bone("hand_l", "wrist_l",
		Vector3(0.0, -body["hand"] * 0.5, 0.0))
	hand_r = _attach_to_bone("hand_r", "wrist_r",
		Vector3(0.0, -body["hand"] * 0.5, 0.0))
	head_node = _attach_to_bone("head_anchor", "head", Vector3.ZERO)

	if _visible_body:
		_build_surfaces(player, team, host, body)


# Everything the body is measured from. `bulk` is the one knob for body type:
# a heavier player carries more through the trunk, thighs and arms.
func _proportions(player: Dictionary) -> Dictionary:
	var h := height
	var bulk := 0.94 + float(player["str"]) / 99.0 * 0.16
	var ankle_y := 0.042 * h
	var shin := 0.252 * h
	var thigh := 0.252 * h
	var torso := 0.278 * h
	return {
		"h": h,
		"bulk": bulk,
		"ankle_y": ankle_y,
		"shin": shin,
		"thigh": thigh,
		"hip_y": ankle_y + shin + thigh,
		"torso": torso,
		"neck": 0.034 * h,
		# Roughly seven and a half heads tall. A bigger head is what made the
		# earlier build read as stumpy.
		"head_radius": 0.068 * h,
		# Broad shoulders over a narrow waist is most of what reads as athletic.
		"shoulder_half": 0.122 * h,
		"hip_half": 0.070 * h,
		"upper_arm": 0.178 * h,
		"forearm": 0.152 * h,
		"hand": 0.092 * h,

		# Trunk cross-sections, shared by the body and the kit so a shell can
		# never end up narrower than the body it is supposed to cover.
		"r_pelvis": 0.086 * h * bulk,
		"r_hip": 0.090 * h * bulk,
		"r_waist": 0.078 * h * bulk,
		"r_ribs": 0.096 * h * bulk,
		"r_chest": 0.108 * h * bulk,
		"r_shoulders": 0.114 * h * bulk,
		"r_collar": 0.074 * h,
		## How far the kit sits proud of the skin.
		"kit": 0.011 * h,
	}


func _build_skeleton(body: Dictionary) -> void:
	var torso: float = body["torso"]
	_add_bone("hips", -1, Vector3(0.0, body["hip_y"], 0.0))
	_add_bone("spine", "hips", Vector3(0.0, torso * 0.32, 0.0))
	_add_bone("chest", "spine", Vector3(0.0, torso * 0.34, 0.0))
	_add_bone("neck", "chest", Vector3(0.0, torso * 0.34, 0.0))
	_add_bone("head", "neck", Vector3(0.0, body["neck"], 0.0))

	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		_add_bone("shoulder_%s" % tag, "chest",
			Vector3(body["shoulder_half"] * side, torso * 0.34, 0.0))
		_add_bone("elbow_%s" % tag, "shoulder_%s" % tag,
			Vector3(0.0, -body["upper_arm"], 0.0))
		_add_bone("wrist_%s" % tag, "elbow_%s" % tag,
			Vector3(0.0, -body["forearm"], 0.0))

		_add_bone("hip_%s" % tag, "hips", Vector3(body["hip_half"] * side, 0.0, 0.0))
		_add_bone("knee_%s" % tag, "hip_%s" % tag, Vector3(0.0, -body["thigh"], 0.0))
		_add_bone("ankle_%s" % tag, "knee_%s" % tag, Vector3(0.0, -body["shin"], 0.0))


func _add_bone(bone_name: String, parent: Variant, offset: Vector3) -> int:
	var index := _skeleton.add_bone(bone_name)
	_bones[bone_name] = index
	if typeof(parent) == TYPE_STRING:
		_skeleton.set_bone_parent(index, int(_bones[parent]))
	_skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
	_skeleton.set_bone_pose_position(index, offset)
	return index


func _bone(bone_name: String) -> int:
	return int(_bones.get(bone_name, 0))


func _attach_to_bone(node_name: String, bone_name: String,
		offset: Vector3) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = node_name
	attachment.bone_name = bone_name
	attachment.bone_idx = _bone(bone_name)
	_skeleton.add_child(attachment)
	var anchor := Node3D.new()
	anchor.name = "Anchor"
	anchor.position = offset
	attachment.add_child(anchor)
	return anchor


# --- surfaces -------------------------------------------------------------

func _build_surfaces(player: Dictionary, team: Dictionary, host: Node,
		body: Dictionary) -> void:
	var kit := _materials(player, team)
	_add_surface(_build_body_surface(body), kit["skin"])
	_add_surface(_build_jersey_surface(body), kit["jersey"])
	_add_surface(_build_shorts_surface(body), kit["shorts"])
	_add_surface(_build_shoe_surface(body), kit["shoe"])
	_add_surface(_build_sole_surface(body), kit["sole"])
	_add_face(kit, body)
	_add_hair(kit, body, int(player["hair"]))
	_add_number(player, team, host, body)


func _add_surface(mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	if mesh.get_surface_count() == 0:
		return null
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	_skeleton.add_child(instance)
	# Set after entering the tree so the path resolves, and bind the skin the
	# skeleton itself generates from its rest pose.
	instance.skeleton = instance.get_path_to(_skeleton)
	instance.skin = _skeleton.create_skin_from_rest_transforms()
	return instance


func _build_body_surface(body: Dictionary) -> ArrayMesh:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var torso: float = body["torso"]
	var loft := BodyMesh.new()
	loft.begin()

	# Trunk: pelvis, a waist that pulls in, then a chest that flares out.
	var hips_y: float = body["hip_y"]
	loft.chain(Vector3(0.0, hips_y - 0.052 * h, 0.0),
		Vector3(0.0, hips_y + torso * 0.32, 0.0),
		_bone("hips"), _bone("spine"), [
			BodyMesh.station(0.0, body["r_pelvis"], 0.76),
			BodyMesh.station(0.45, body["r_hip"], 0.76),
			BodyMesh.station(1.0, body["r_waist"], 0.74),
		])
	loft.chain(Vector3(0.0, hips_y + torso * 0.32, 0.0),
		Vector3(0.0, hips_y + torso * 0.66, 0.0),
		_bone("spine"), _bone("chest"), [
			BodyMesh.station(0.30, body["r_ribs"], 0.74),
			BodyMesh.station(1.0, body["r_chest"], 0.74),
		])
	loft.chain(Vector3(0.0, hips_y + torso * 0.66, 0.0),
		Vector3(0.0, hips_y + torso, 0.0),
		_bone("chest"), _bone("neck"), [
			BodyMesh.station(0.35, body["r_shoulders"], 0.74),
			BodyMesh.station(0.85, body["r_chest"], 0.72),
			BodyMesh.station(1.0, body["r_collar"], 0.82),
		], 0.9)
	# Neck.
	loft.chain(Vector3(0.0, hips_y + torso, 0.0),
		Vector3(0.0, hips_y + torso + body["neck"], 0.0),
		_bone("neck"), _bone("head"), [
			BodyMesh.station(0.0, 0.044 * h, 0.95),
			BodyMesh.station(1.0, 0.040 * h, 0.95),
		])
	loft.cut()

	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		_loft_arm(loft, body, tag, side)
		_loft_leg(loft, body, tag, side)

	# Head last so it closes on its own.
	var head_y: float = hips_y + torso + body["neck"] + body["head_radius"] * 0.86
	loft.blob(Vector3(0.0, head_y, 0.0),
		Vector3(body["head_radius"] * 0.92, body["head_radius"] * 1.14,
			body["head_radius"]), _bone("head"), 10)
	# Jaw, which is what stops the head reading as an egg.
	loft.blob(Vector3(0.0, head_y - body["head_radius"] * 0.42,
		-body["head_radius"] * 0.16),
		Vector3(body["head_radius"] * 0.78, body["head_radius"] * 0.62,
			body["head_radius"] * 0.86), _bone("head"), 6)
	return loft.commit()


func _loft_arm(loft: BodyMesh, body: Dictionary, tag: String, side: float) -> void:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var shoulder := Vector3(body["shoulder_half"] * side,
		body["hip_y"] + body["torso"], 0.0)
	var elbow := shoulder + Vector3(0.0, -body["upper_arm"], 0.0)
	var wrist := elbow + Vector3(0.0, -body["forearm"], 0.0)

	loft.cut()
	# Deltoid, bicep taper, then the elbow.
	loft.chain(shoulder + Vector3(0.0, 0.030 * h, 0.0), elbow,
		_bone("shoulder_%s" % tag), _bone("elbow_%s" % tag), [
			BodyMesh.station(0.0, 0.043 * h * bulk, 1.0),
			BodyMesh.station(0.16, 0.050 * h * bulk, 1.0),
			BodyMesh.station(0.45, 0.041 * h * bulk, 1.0),
			BodyMesh.station(0.80, 0.033 * h, 1.0),
			BodyMesh.station(1.0, 0.030 * h, 1.0),
		])
	loft.chain(elbow, wrist, _bone("elbow_%s" % tag), _bone("wrist_%s" % tag), [
		BodyMesh.station(0.0, 0.031 * h, 1.0),
		BodyMesh.station(0.24, 0.034 * h * bulk, 1.0),
		BodyMesh.station(0.70, 0.025 * h, 1.0),
		BodyMesh.station(1.0, 0.021 * h, 1.0),
	])
	loft.cut()

	# Hand: a flattened blob plus a finger block, deliberately a little large.
	var hand_centre := wrist + Vector3(0.0, -body["hand"] * 0.34, 0.0)
	loft.blob(hand_centre, Vector3(0.034 * h, 0.042 * h, 0.017 * h),
		_bone("wrist_%s" % tag), 6)
	loft.blob(wrist + Vector3(0.0, -body["hand"] * 0.78, -0.004 * h),
		Vector3(0.030 * h, 0.038 * h, 0.015 * h), _bone("wrist_%s" % tag), 6)
	loft.blob(wrist + Vector3(side * 0.030 * h, -body["hand"] * 0.36, 0.008 * h),
		Vector3(0.014 * h, 0.022 * h, 0.013 * h), _bone("wrist_%s" % tag), 5)


func _loft_leg(loft: BodyMesh, body: Dictionary, tag: String, side: float) -> void:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var hip := Vector3(body["hip_half"] * side, body["hip_y"], 0.0)
	var knee := hip + Vector3(0.0, -body["thigh"], 0.0)
	var ankle := knee + Vector3(0.0, -body["shin"], 0.0)

	loft.cut()
	loft.chain(hip + Vector3(0.0, 0.035 * h, 0.0), knee,
		_bone("hip_%s" % tag), _bone("knee_%s" % tag), [
			BodyMesh.station(0.0, 0.062 * h * bulk, 0.94),
			BodyMesh.station(0.22, 0.068 * h * bulk, 0.94),
			BodyMesh.station(0.60, 0.057 * h * bulk, 0.94),
			BodyMesh.station(0.88, 0.046 * h, 0.96),
			BodyMesh.station(1.0, 0.043 * h, 0.96),
		])
	# Calf sits high and behind, which is what gives the leg its shape.
	loft.chain(knee, ankle, _bone("knee_%s" % tag), _bone("ankle_%s" % tag), [
		BodyMesh.station(0.0, 0.044 * h, 0.96),
		BodyMesh.station(0.22, 0.052 * h * bulk, 1.0),
		BodyMesh.station(0.58, 0.038 * h, 0.98),
		BodyMesh.station(0.88, 0.028 * h, 0.96),
		BodyMesh.station(1.0, 0.026 * h, 0.96),
	])
	loft.cut()


func _build_jersey_surface(body: Dictionary) -> ArrayMesh:
	var h: float = body["h"]
	var torso: float = body["torso"]
	var hips_y: float = body["hip_y"]
	var kit: float = body["kit"]
	var loft := BodyMesh.new()
	loft.begin()

	# The same cross-sections as the trunk, pushed out by the kit thickness.
	loft.chain(Vector3(0.0, hips_y - 0.070 * h, 0.0),
		Vector3(0.0, hips_y + torso * 0.32, 0.0),
		_bone("hips"), _bone("spine"), [
			BodyMesh.station(0.0, body["r_hip"] + kit, 0.80),
			BodyMesh.station(1.0, body["r_waist"] + kit, 0.78),
		])
	loft.chain(Vector3(0.0, hips_y + torso * 0.32, 0.0),
		Vector3(0.0, hips_y + torso * 0.66, 0.0),
		_bone("spine"), _bone("chest"), [
			BodyMesh.station(0.30, body["r_ribs"] + kit, 0.78),
			BodyMesh.station(1.0, body["r_chest"] + kit, 0.78),
		])
	loft.chain(Vector3(0.0, hips_y + torso * 0.66, 0.0),
		Vector3(0.0, hips_y + torso * 0.97, 0.0),
		_bone("chest"), _bone("neck"), [
			BodyMesh.station(0.35, body["r_shoulders"] + kit, 0.78),
			BodyMesh.station(0.88, body["r_chest"] + kit * 0.6, 0.76),
			BodyMesh.station(1.0, body["r_collar"] + kit * 0.4, 0.86),
		], 0.9)
	loft.cut()

	# Short sleeves, cut off above the elbow.
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var shoulder := Vector3(body["shoulder_half"] * side, hips_y + torso, 0.0)
		var elbow := shoulder + Vector3(0.0, -body["upper_arm"], 0.0)
		loft.chain(shoulder + Vector3(0.0, 0.012 * h, 0.0), elbow,
			_bone("shoulder_%s" % tag), _bone("elbow_%s" % tag), [
				BodyMesh.station(0.0, 0.047 * h * body["bulk"] + kit * 0.5, 1.0),
				BodyMesh.station(0.20, 0.048 * h * body["bulk"] + kit * 0.5, 1.0),
				BodyMesh.station(0.44, 0.042 * h * body["bulk"] + kit * 0.4, 1.0),
			], 0.95)
		loft.cut()
	return loft.commit()


func _build_shorts_surface(body: Dictionary) -> ArrayMesh:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var kit: float = body["kit"]
	var loft := BodyMesh.new()
	loft.begin()

	loft.chain(Vector3(0.0, body["hip_y"] + 0.062 * h, 0.0),
		Vector3(0.0, body["hip_y"] - 0.042 * h, 0.0),
		_bone("hips"), -1, [
			BodyMesh.station(0.0, body["r_waist"] + kit * 2.0, 0.82),
			BodyMesh.station(0.55, body["r_hip"] + kit * 2.2, 0.84),
			BodyMesh.station(1.0, body["r_hip"] + kit * 2.2, 0.84),
		])
	loft.cut()

	# Down to just above the knee, tapering rather than flaring.
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var hip := Vector3(body["hip_half"] * side, body["hip_y"], 0.0)
		var knee := hip + Vector3(0.0, -body["thigh"], 0.0)
		loft.chain(hip + Vector3(0.0, 0.012 * h, 0.0), knee, _bone("hip_%s" % tag),
			_bone("knee_%s" % tag), [
				BodyMesh.station(0.0, 0.076 * h * bulk + kit * 1.6, 0.96),
				BodyMesh.station(0.40, 0.070 * h * bulk + kit, 0.98),
				BodyMesh.station(0.74, 0.062 * h * bulk + kit * 0.8, 0.98),
				BodyMesh.station(0.78, 0.060 * h * bulk + kit * 0.6, 0.98),
			], 0.95)
		loft.cut()
	return loft.commit()


func _build_shoe_surface(body: Dictionary) -> ArrayMesh:
	var h: float = body["h"]
	var loft := BodyMesh.new()
	loft.begin()
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var ankle := Vector3(body["hip_half"] * side,
			body["hip_y"] - body["thigh"] - body["shin"], 0.0)
		loft.blob(ankle + Vector3(0.0, -0.014 * h, -0.038 * h),
			Vector3(0.034 * h, 0.026 * h, 0.098 * h), _bone("ankle_%s" % tag), 6)
		loft.blob(ankle + Vector3(0.0, 0.010 * h, 0.002 * h),
			Vector3(0.031 * h, 0.030 * h, 0.036 * h), _bone("ankle_%s" % tag), 5)
	return loft.commit()


func _build_sole_surface(body: Dictionary) -> ArrayMesh:
	var h: float = body["h"]
	var loft := BodyMesh.new()
	loft.begin()
	for side in [1.0, -1.0]:
		var tag := "l" if side > 0.0 else "r"
		var ankle := Vector3(body["hip_half"] * side,
			body["hip_y"] - body["thigh"] - body["shin"], 0.0)
		loft.blob(ankle + Vector3(0.0, -0.032 * h, -0.038 * h),
			Vector3(0.036 * h, 0.010 * h, 0.100 * h), _bone("ankle_%s" % tag), 4)
	return loft.commit()


func _add_face(kit: Dictionary, body: Dictionary) -> void:
	var radius: float = body["head_radius"]
	var head_y: float = body["hip_y"] + body["torso"] + body["neck"] + radius * 0.86
	var bone := _bone("head")

	var eyes := BodyMesh.new()
	eyes.begin()
	var whites := BodyMesh.new()
	whites.begin()
	var brows := BodyMesh.new()
	brows.begin()
	for side in [-1.0, 1.0]:
		var eye_centre := Vector3(side * radius * 0.35, head_y + radius * 0.06,
			-radius * 0.79)
		whites.blob(eye_centre, Vector3(radius * 0.21, radius * 0.15,
			radius * 0.08), bone, 5)
		eyes.blob(eye_centre + Vector3(0.0, 0.0, -radius * 0.06),
			Vector3(radius * 0.105, radius * 0.115, radius * 0.06), bone, 5)
		if _detail > 0:
			brows.blob(Vector3(side * radius * 0.35, head_y + radius * 0.26,
				-radius * 0.75), Vector3(radius * 0.24, radius * 0.055,
				radius * 0.08), bone, 4)
	_add_surface(whites.commit(), kit["sclera"])
	_add_surface(eyes.commit(), kit["eye"])
	if _detail == 0:
		return
	_add_surface(brows.commit(), kit["hair"])

	var features := BodyMesh.new()
	features.begin()
	features.blob(Vector3(0.0, head_y - radius * 0.06, -radius * 0.84),
		Vector3(radius * 0.13, radius * 0.19, radius * 0.13), bone, 5)
	for side in [-1.0, 1.0]:
		features.blob(Vector3(side * radius * 0.92, head_y + radius * 0.04, 0.0),
			Vector3(radius * 0.07, radius * 0.15, radius * 0.11), bone, 5)
	_add_surface(features.commit(), kit["skin"])

	var mouth := BodyMesh.new()
	mouth.begin()
	mouth.blob(Vector3(0.0, head_y - radius * 0.44, -radius * 0.76),
		Vector3(radius * 0.21, radius * 0.045, radius * 0.06), bone, 4)
	_add_surface(mouth.commit(), kit["mouth"])


func _add_hair(kit: Dictionary, body: Dictionary, style: int) -> void:
	var radius: float = body["head_radius"]
	var head_y: float = body["hip_y"] + body["torso"] + body["neck"] + radius * 0.86
	var bone := _bone("head")
	var hair := BodyMesh.new()
	hair.begin()

	# Every style is a crop following the skull, then something added to it.
	# Nothing sits in front of the face.
	var crop := Vector3(radius * 0.99, radius * 0.86, radius * 1.03)
	var crop_centre := Vector3(0.0, head_y + radius * 0.38, radius * 0.12)
	match style:
		1:
			crop = Vector3(radius * 0.97, radius * 0.60, radius * 1.00)
			crop_centre.y = head_y + radius * 0.52
		2:
			crop = Vector3(radius * 1.22, radius * 1.06, radius * 1.22)
			crop_centre.y = head_y + radius * 0.34
		4:
			crop = Vector3(radius * 1.03, radius * 0.94, radius * 1.04)
	hair.blob(crop_centre, crop, bone, 8)
	if style == 4:
		hair.blob(Vector3(0.0, head_y + radius * 0.92, radius * 0.06),
			Vector3(radius * 0.92, radius * 0.16, radius * 0.90), bone, 4)
	_add_surface(hair.commit(), kit["hair"])

	if style == 3:
		var band := BodyMesh.new()
		band.begin()
		band.blob(Vector3(0.0, head_y + radius * 0.30, 0.0),
			Vector3(radius * 1.02, radius * 0.15, radius * 1.06), bone, 5)
		_add_surface(band.commit(), kit["band"])


func _add_number(player: Dictionary, team: Dictionary, host: Node,
		body: Dictionary) -> void:
	var texture := JerseyNumbers.atlas(host)
	var torso: float = body["torso"]
	var radius: float = body["r_chest"] + body["kit"] * 1.6
	var chest_y: float = body["hip_y"] + torso * 0.72
	_number_patch(texture, team, int(player["num"]), radius, 1.75,
		torso * 0.26, 0.0, chest_y)
	_number_patch(texture, team, int(player["num"]), radius, 1.05,
		torso * 0.15, PI, chest_y + torso * 0.10)


# Wrapped onto the chest so the digits sit on the shirt rather than floating in
# front of it. Bound to the chest bone so it moves with the torso.
func _number_patch(texture: Texture2D, team: Dictionary, number: int,
		radius: float, arc: float, patch_height: float, centre_angle: float,
		y: float) -> void:
	const STEPS := 10
	const DEPTH := 0.76
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bone := PackedInt32Array([_bone("chest"), 0, 0, 0])
	var weight := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

	for i in STEPS + 1:
		var t := float(i) / float(STEPS)
		var angle := centre_angle + (t - 0.5) * arc
		var ring := Vector3(sin(angle) * radius, 0.0, cos(angle) * radius * DEPTH)
		var u := 1.0 - t if is_zero_approx(centre_angle) else t
		for edge in 2:
			tool.set_uv(Vector2(u, float(edge)))
			tool.set_bones(bone)
			tool.set_weights(weight)
			tool.add_vertex(ring + Vector3(0.0,
				y + patch_height * (0.5 - float(edge)), 0.0))
	for i in STEPS:
		var base := i * 2
		for index in [base, base + 1, base + 2, base + 1, base + 3, base + 2]:
			tool.add_index(index)
	tool.generate_normals()

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.45
	material.uv1_scale = JerseyNumbers.uv_scale()
	material.uv1_offset = JerseyNumbers.uv_offset(number)
	material.albedo_color = Color(team["secondary"])
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	_add_surface(tool.commit(), material)


func _materials(player: Dictionary, team: Dictionary) -> Dictionary:
	var primary := Color(team["primary"])
	var secondary := Color(team["secondary"])
	var accent := Color(team["accent"])
	# Kit is an open-ended shell: it has a hem, a collar and armholes. Drawing
	# it single sided means looking straight through those openings into the
	# body, so cloth is double sided, like real cloth.
	var jersey := Materials.flat(primary, 0.88)
	jersey.metallic_specular = 0.28
	jersey.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shorts := Materials.flat(primary.lerp(accent, 0.35), 0.90)
	shorts.metallic_specular = 0.28
	shorts.cull_mode = BaseMaterial3D.CULL_DISABLED
	return {
		"skin": Materials.skin(int(player["skin"])),
		"jersey": jersey,
		"shorts": shorts,
		"trim": Materials.flat(secondary, 0.7),
		"shoe": Materials.flat(secondary.lerp(Color.WHITE, 0.2), 0.45),
		"sole": Materials.flat(Color(0.95, 0.95, 0.93), 0.55),
		"hair": Materials.flat(Color(0.07, 0.055, 0.05), 0.94),
		"band": Materials.flat(Color(0.94, 0.94, 0.92), 0.8),
		"eye": Materials.flat(Color(0.07, 0.06, 0.06), 0.25),
		"sclera": Materials.flat(Color(0.93, 0.92, 0.90), 0.35),
		"mouth": Materials.flat(Color(0.30, 0.18, 0.17), 0.6),
	}


# --- posing ---------------------------------------------------------------

func set_target(key: String, euler: Vector3) -> void:
	_target_pose[key] = euler


func apply(delta: float, responsiveness: float = 18.0) -> void:
	var weight := clampf(delta * responsiveness, 0.0, 1.0)
	for key in JOINTS:
		var blended: Vector3 = (pose[key] as Vector3).lerp(_target_pose[key], weight)
		pose[key] = blended
		_skeleton.set_bone_pose_rotation(_bone(key),
			Quaternion.from_euler(blended))


func snap_to_target() -> void:
	for key in JOINTS:
		pose[key] = _target_pose[key]
		_skeleton.set_bone_pose_rotation(_bone(key),
			Quaternion.from_euler(_target_pose[key]))
	if OS.is_stdout_verbose():
		var idx := _bone("shoulder_l")
		print("snap shoulder=%s elbow=%s wrist=%s" % [
			_skeleton.get_bone_global_pose(idx).origin,
			_skeleton.get_bone_global_pose(_bone("elbow_l")).origin,
			_skeleton.get_bone_global_pose(_bone("wrist_l")).origin])
