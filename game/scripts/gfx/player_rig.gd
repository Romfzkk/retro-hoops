class_name PlayerRig
extends Node3D

# Segmented humanoid built from primitives at load and driven by joint
# rotations. Every segment is capped with a sphere the same radius as the
# segment end, which is what stops the limbs reading as disconnected tubes.
#
# Local axes: limbs hang down -Y. +X rotation swings a limb forward (-Z),
# +Z swings it out to the player's left.

const JOINTS := [
	"hips", "spine", "chest", "head",
	"shoulder_l", "elbow_l", "shoulder_r", "elbow_r",
	"hip_l", "knee_l", "ankle_l", "hip_r", "knee_r", "ankle_r",
]

const SEGMENTS := 16
const SPHERE_RINGS := 8

var joints: Dictionary = {}
var hand_l: Node3D
var hand_r: Node3D
var head_node: Node3D
var height := 1.98
var shoulder_height := 1.55
var standing_reach := 2.6

var pose: Dictionary = {}
var _target_pose: Dictionary = {}
var _detail := 1
var _visible_body := true


## `with_meshes` off builds the joint hierarchy and the body metrics but no
## geometry. Balance runs spawn ten players and never draw them; skipping the
## ~400 mesh instances each is what makes a headless match faster than a
## watched one.
static func create(player: Dictionary, team: Dictionary, host: Node,
		with_meshes: bool = true) -> PlayerRig:
	var rig := PlayerRig.new()
	rig.name = "Rig"
	rig.height = float(player["h"]) * 0.01
	rig._detail = 0 if OS.has_feature("mobile") else 1
	rig._visible_body = with_meshes
	rig._build(player, team, host)
	return rig


# Proportions in metres, derived once and shared by the skeleton and the
# geometry. `bulk` is the only knob for body type: heavier players carry more
# through the trunk and thighs.
func _proportions(player: Dictionary) -> Dictionary:
	var h := height
	var bulk := 0.90 + float(player["str"]) / 99.0 * 0.26
	var lean := 1.06 - (float(player["str"]) / 99.0) * 0.12
	var ankle_y := 0.052 * h
	var shin := 0.240 * h
	var thigh := 0.238 * h
	return {
		"h": h,
		"bulk": bulk,
		"ankle_y": ankle_y,
		"shin": shin,
		"thigh": thigh,
		"hip_y": ankle_y + shin + thigh,
		"torso": 0.290 * h,
		"neck": 0.046 * h,
		"head_radius": 0.076 * h,
		"shoulder_half": 0.120 * h * lean,
		"hip_half": 0.070 * h,
		"upper_arm": 0.180 * h,
		"forearm": 0.146 * h,
	}


func _build(player: Dictionary, team: Dictionary, host: Node) -> void:
	var body := _proportions(player)
	shoulder_height = body["hip_y"] + body["torso"]
	standing_reach = shoulder_height + body["upper_arm"] + body["forearm"] \
		+ 0.118 * body["h"]

	_build_skeleton(body)
	if _visible_body:
		_build_geometry(player, team, host, body)

	for key in JOINTS:
		pose[key] = Vector3.ZERO
		_target_pose[key] = Vector3.ZERO


# Joints only. A balance run needs the hierarchy and the reach numbers but
# never draws anything, so the geometry pass is skipped entirely.
func _build_skeleton(body: Dictionary) -> void:
	var torso: float = body["torso"]
	var hips := _joint("hips", self, Vector3(0.0, body["hip_y"], 0.0))
	var spine := _joint("spine", hips, Vector3.ZERO)
	var chest := _joint("chest", spine, Vector3(0.0, torso * 0.62, 0.0))
	head_node = _joint("head", chest, Vector3(0.0, torso * 0.38, 0.0))

	for side in [-1.0, 1.0]:
		var tag := "l" if side > 0.0 else "r"
		var shoulder := _joint("shoulder_%s" % tag, chest,
			Vector3(body["shoulder_half"] * 0.88 * side, torso * 0.38, 0.0))
		var elbow := _joint("elbow_%s" % tag, shoulder,
			Vector3(0.0, -body["upper_arm"], 0.0))
		var hand := Node3D.new()
		hand.name = "hand_%s" % tag
		hand.position = Vector3(0.0, -body["forearm"], 0.0)
		elbow.add_child(hand)
		if side > 0.0:
			hand_l = hand
		else:
			hand_r = hand

		var hip_joint := _joint("hip_%s" % tag, hips,
			Vector3(body["hip_half"] * side, 0.0, 0.0))
		var knee := _joint("knee_%s" % tag, hip_joint, Vector3(0.0, -body["thigh"], 0.0))
		_joint("ankle_%s" % tag, knee, Vector3(0.0, -body["shin"], 0.0))


func _build_geometry(player: Dictionary, team: Dictionary, host: Node,
		body: Dictionary) -> void:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var torso: float = body["torso"]
	var shoulder_half: float = body["shoulder_half"]
	var hip_half: float = body["hip_half"]
	var kit := _materials(player, team)

	var hips: Node3D = joints["hips"]
	_segment(hips, kit["shorts"], hip_half * 1.30 * bulk, hip_half * 1.24 * bulk,
		0.095 * h, 0.80, Vector3(0.0, -0.020 * h, 0.0), false, false)

	# One continuous torso. Two stacked cylinders leave a lip across the jersey
	# where their radii meet.
	var spine: Node3D = joints["spine"]
	_segment(spine, kit["jersey"], hip_half * 1.24 * bulk, shoulder_half * 1.00 * bulk,
		torso * 0.98, 0.62, Vector3(0.0, torso * 0.49, 0.0), true, false)

	var chest: Node3D = joints["chest"]
	# Trapezius: a flattened mass across the shoulder line. A full sphere here
	# has the radius of half a shoulder span and swallows the neck.
	var yoke := _ball(chest, kit["jersey"], shoulder_half * 0.78 * bulk,
		Vector3(0.0, torso * 0.30, 0.0))
	yoke.scale = Vector3(1.30, 0.42, 0.72)
	_ring(chest, kit["trim"], shoulder_half * 0.44, 0.012 * h,
		Vector3(0.0, torso * 0.375, 0.0), 0.70)
	_add_number(chest, player, team, host, torso, shoulder_half)

	var head_joint: Node3D = joints["head"]
	_segment(head_joint, kit["skin"], 0.042 * h, 0.038 * h, body["neck"] * 1.5, 1.0,
		Vector3(0.0, body["neck"] * 0.55, 0.0), false, false)
	_add_head(head_joint, kit, body["head_radius"], body["neck"], int(player["hair"]))

	for side in [-1.0, 1.0]:
		var tag := "l" if side > 0.0 else "r"
		_dress_arm(kit, tag, side, body)
		_dress_leg(kit, tag, body)


func _materials(player: Dictionary, team: Dictionary) -> Dictionary:
	var primary := Color(team["primary"])
	var secondary := Color(team["secondary"])
	var accent := Color(team["accent"])
	var jersey := Materials.flat(primary, 0.88)
	# A little sheen difference is what separates fabric from skin.
	jersey.metallic_specular = 0.25
	var shorts := Materials.flat(primary.lerp(accent, 0.35), 0.90)
	shorts.metallic_specular = 0.25
	return {
		"skin": Materials.skin(int(player["skin"])),
		"jersey": jersey,
		"shorts": shorts,
		"trim": Materials.flat(secondary, 0.7),
		"shoe": Materials.flat(secondary.lerp(Color.WHITE, 0.25), 0.45),
		"shoe_accent": Materials.flat(primary, 0.5),
		"sole": Materials.flat(Color(0.94, 0.94, 0.92), 0.55),
		"hair": Materials.flat(Color(0.07, 0.055, 0.05), 0.94),
		"eye": Materials.flat(Color(0.08, 0.07, 0.07), 0.25),
		"sclera": Materials.flat(Color(0.93, 0.92, 0.90), 0.35),
		"mouth": Materials.flat(Color(0.32, 0.20, 0.19), 0.6),
	}


func _dress_arm(kit: Dictionary, tag: String, side: float, body: Dictionary) -> void:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var upper_arm: float = body["upper_arm"]
	var forearm: float = body["forearm"]

	var shoulder: Node3D = joints["shoulder_%s" % tag]
	var deltoid := _ball(shoulder, kit["jersey"], 0.034 * h * bulk,
		Vector3(0.0, -0.014 * h, 0.0))
	deltoid.scale = Vector3(0.98, 1.10, 0.92)
	# No skin cap at the top: the jersey deltoid already closes the shoulder,
	# and a sphere there pokes through the sleeve.
	_segment(shoulder, kit["skin"], 0.036 * h * bulk, 0.031 * h, upper_arm, 1.0,
		Vector3(0.0, -upper_arm * 0.5, 0.0), false, false)
	# Sleeve, sitting proud of the arm so it looks like cloth over muscle.
	_segment(shoulder, kit["jersey"], 0.038 * h * bulk, 0.035 * h * bulk,
		upper_arm * 0.34, 0.96, Vector3(0.0, -upper_arm * 0.17, 0.0), false, false)

	var elbow: Node3D = joints["elbow_%s" % tag]
	_ball(elbow, kit["skin"], 0.034 * h, Vector3.ZERO)
	_segment(elbow, kit["skin"], 0.033 * h, 0.027 * h, forearm, 1.0,
		Vector3(0.0, -forearm * 0.5, 0.0), false, true)
	_add_hand(hand_l if tag == "l" else hand_r, kit["skin"], h, side)


func _dress_leg(kit: Dictionary, tag: String, body: Dictionary) -> void:
	var h: float = body["h"]
	var bulk: float = body["bulk"]
	var thigh: float = body["thigh"]
	var shin: float = body["shin"]

	var hip_joint: Node3D = joints["hip_%s" % tag]
	_segment(hip_joint, kit["skin"], 0.055 * h * bulk, 0.040 * h, thigh, 0.94,
		Vector3(0.0, -thigh * 0.5, 0.0), true, true)
	# Shorts hang off the thigh so they swing with the leg. Long and slightly
	# tapered reads as basketball kit; short and flared reads as a skirt.
	_segment(hip_joint, kit["shorts"], 0.069 * h * bulk, 0.062 * h * bulk,
		thigh * 0.74, 0.90, Vector3(0.0, -thigh * 0.33, 0.0), false, false)
	_ring(hip_joint, kit["trim"], 0.062 * h * bulk, 0.009 * h,
		Vector3(0.0, -thigh * 0.70, 0.0), 0.90)

	var knee: Node3D = joints["knee_%s" % tag]
	_ball(knee, kit["skin"], 0.040 * h, Vector3.ZERO)
	_segment(knee, kit["skin"], 0.040 * h, 0.028 * h, shin, 0.95,
		Vector3(0.0, -shin * 0.5, 0.0), false, true)

	_add_shoe(joints["ankle_%s" % tag], kit, h, body["ankle_y"])


func _add_hand(hand: Node3D, skin: Material, h: float, side: float) -> void:
	# Slightly oversized, the way a stylised athlete reads. Palm, finger block
	# and thumb: three shapes is enough to catch a ball convincingly.
	var palm := _ball(hand, skin, 0.040 * h, Vector3(0.0, -0.030 * h, 0.0))
	palm.scale = Vector3(0.92, 1.10, 0.52)
	if _detail == 0:
		return
	var fingers := _ball(hand, skin, 0.034 * h, Vector3(0.0, -0.078 * h, -0.004 * h))
	fingers.scale = Vector3(0.94, 1.22, 0.46)
	var thumb := _ball(hand, skin, 0.020 * h, Vector3(side * 0.032 * h, -0.040 * h, 0.0))
	thumb.scale = Vector3(0.8, 1.5, 0.7)
	thumb.rotation.z = -side * 0.5


func _add_shoe(ankle: Node3D, kit: Dictionary, h: float, ankle_y: float) -> void:
	var upper := _ball(ankle, kit["shoe"], 0.046 * h,
		Vector3(0.0, -ankle_y * 0.26, -0.026 * h))
	upper.scale = Vector3(0.76, 0.70, 1.58)
	var collar := _ball(ankle, kit["shoe"], 0.036 * h, Vector3(0.0, 0.0, 0.008 * h))
	collar.scale = Vector3(0.84, 0.82, 0.88)
	_slab(ankle, kit["sole"], Vector3(0.066 * h, 0.016 * h, 0.152 * h),
		Vector3(0.0, -ankle_y * 0.80, -0.026 * h))
	if _detail == 0:
		return
	_slab(ankle, kit["shoe_accent"], Vector3(0.070 * h, 0.009 * h, 0.080 * h),
		Vector3(0.0, -ankle_y * 0.44, -0.040 * h))


func _add_head(head_joint: Node3D, kit: Dictionary, radius: float, neck: float,
		style: int) -> void:
	var base := neck + radius * 0.78
	var skull := _ball(head_joint, kit["skin"], radius, Vector3(0.0, base, 0.0))
	skull.scale = Vector3(0.93, 1.12, 1.00)
	# Jaw, which is what keeps the head from reading as an egg.
	var jaw := _ball(head_joint, kit["skin"], radius * 0.72,
		Vector3(0.0, base - radius * 0.30, -radius * 0.18))
	jaw.scale = Vector3(0.92, 0.86, 1.02)
	_add_face(head_joint, kit, radius, base)
	_add_hair(head_joint, kit["hair"], radius, base, style)


func _add_face(head_joint: Node3D, kit: Dictionary, radius: float, base: float) -> void:
	for side in [-1.0, 1.0]:
		var white := _ball(head_joint, kit["sclera"], radius * 0.165,
			Vector3(side * radius * 0.34, base + radius * 0.14, -radius * 0.80))
		white.scale = Vector3(1.15, 0.85, 0.45)
		var pupil := _ball(head_joint, kit["eye"], radius * 0.095,
			Vector3(side * radius * 0.34, base + radius * 0.14, -radius * 0.87))
		pupil.scale = Vector3(1.0, 1.05, 0.45)
		if _detail == 0:
			continue
		var brow := _slab(head_joint, kit["hair"],
			Vector3(radius * 0.36, radius * 0.085, radius * 0.10),
			Vector3(side * radius * 0.34, base + radius * 0.36, -radius * 0.76))
		brow.rotation.z = -side * 0.18
	if _detail == 0:
		return
	var nose := _ball(head_joint, kit["skin"], radius * 0.17,
		Vector3(0.0, base - radius * 0.06, -radius * 0.84))
	nose.scale = Vector3(0.75, 1.15, 0.85)
	_slab(head_joint, kit["mouth"], Vector3(radius * 0.44, radius * 0.10, radius * 0.06),
		Vector3(0.0, base - radius * 0.42, -radius * 0.78))


func _add_hair(head_joint: Node3D, material: Material, radius: float, base: float,
		style: int) -> void:
	# Every style starts from a close crop following the skull and adds to it.
	# Nothing is allowed to sit in front of the face.
	var cap := _ball(head_joint, material, radius * 1.045,
		Vector3(0.0, base + radius * 0.18, radius * 0.03))
	cap.scale = Vector3(1.0, 0.90, 1.0)
	match style:
		1:
			cap.scale = Vector3(1.01, 0.60, 0.98)
			cap.position = Vector3(0.0, base + radius * 0.34, radius * 0.08)
		2:
			cap.scale = Vector3(1.26, 1.12, 1.24)
			cap.position = Vector3(0.0, base + radius * 0.16, radius * 0.02)
		3:
			# Forehead, above the brows. Any lower and it reads as a blindfold.
			cap.scale = Vector3(1.01, 0.72, 0.98)
			cap.position = Vector3(0.0, base + radius * 0.30, radius * 0.08)
			_ring(head_joint, Materials.flat(Color(0.94, 0.94, 0.92), 0.8),
				radius * 0.97, radius * 0.085,
				Vector3(0.0, base + radius * 0.52, 0.0), 1.0)
		4:
			cap.scale = Vector3(1.06, 1.06, 1.02)
			_slab(head_joint, material,
				Vector3(radius * 1.66, radius * 0.28, radius * 1.60),
				Vector3(0.0, base + radius * 0.86, radius * 0.06))


func _joint(key: String, parent: Node3D, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = key
	node.position = offset
	parent.add_child(node)
	joints[key] = node
	return node


# Tapered segment. `depth` squashes it front to back; `cap_top`/`cap_bottom`
# weld the ends with spheres matching the segment radius there.
func _segment(parent: Node3D, material: Material, bottom: float, top: float,
		length: float, depth: float, offset: Vector3,
		cap_bottom: bool, cap_top: bool) -> void:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = bottom
	cylinder.top_radius = top
	cylinder.height = length
	cylinder.radial_segments = SEGMENTS
	cylinder.rings = 1
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = offset
	mesh.scale = Vector3(1.0, 1.0, depth)
	parent.add_child(mesh)

	if cap_bottom:
		var low := _ball(parent, material, bottom, offset - Vector3(0.0, length * 0.5, 0.0))
		low.scale = Vector3(1.0, 0.9, depth)
	if cap_top:
		var high := _ball(parent, material, top, offset + Vector3(0.0, length * 0.5, 0.0))
		high.scale = Vector3(1.0, 0.9, depth)


func _ball(parent: Node3D, material: Material, radius: float,
		offset: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = SEGMENTS
	sphere.rings = SPHERE_RINGS
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.position = offset
	parent.add_child(mesh)
	return mesh


func _ring(parent: Node3D, material: Material, radius: float, thickness: float,
		offset: Vector3, depth: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - thickness, 0.001)
	torus.outer_radius = radius + thickness
	torus.rings = SEGMENTS
	torus.ring_segments = 6
	mesh.mesh = torus
	mesh.material_override = material
	mesh.position = offset
	mesh.scale = Vector3(1.0, 1.0, depth)
	parent.add_child(mesh)
	return mesh


func _slab(parent: Node3D, material: Material, size: Vector3,
		offset: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = offset
	parent.add_child(mesh)
	return mesh


func _add_number(chest: Node3D, player: Dictionary, team: Dictionary, host: Node,
		torso: float, shoulder_half: float) -> void:
	var texture := JerseyNumbers.atlas(host)
	var radius := shoulder_half * 0.99
	# Back number is large, chest number small, both wrapped onto the torso so
	# they sit on the shirt instead of floating in front of it.
	_number_patch(chest, texture, team, int(player["num"]), radius, 1.85,
		torso * 0.40, 0.0, torso * 0.02)
	_number_patch(chest, texture, team, int(player["num"]), radius, 1.15,
		torso * 0.24, PI, torso * 0.10)


func _number_patch(chest: Node3D, texture: Texture2D, team: Dictionary, number: int,
		radius: float, arc: float, patch_height: float, centre_angle: float,
		y: float) -> void:
	const STEPS := 10
	const DEPTH := 0.62
	# Sit a hair proud of the shirt so it never z-fights the torso.
	var r := radius * 1.015
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in STEPS + 1:
		var t := float(i) / float(STEPS)
		var angle := centre_angle + (t - 0.5) * arc
		var outward := Vector3(sin(angle), 0.0, cos(angle) * DEPTH).normalized()
		var ring := Vector3(sin(angle) * r, 0.0, cos(angle) * r * DEPTH)
		vertices.append(ring + Vector3(0.0, y + patch_height * 0.5, 0.0))
		vertices.append(ring + Vector3(0.0, y - patch_height * 0.5, 0.0))
		normals.append(outward)
		normals.append(outward)
		# Mirror U on the chest patch so the digits read the right way round.
		var u := 1.0 - t if centre_angle == 0.0 else t
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	for i in STEPS:
		var base := i * 2
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.45
	material.uv1_scale = JerseyNumbers.uv_scale()
	material.uv1_offset = JerseyNumbers.uv_offset(number)
	material.albedo_color = Color(team["secondary"])
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.85

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	chest.add_child(instance)


func set_target(key: String, euler: Vector3) -> void:
	_target_pose[key] = euler


func apply(delta: float, responsiveness: float = 18.0) -> void:
	var weight := clampf(delta * responsiveness, 0.0, 1.0)
	for key in JOINTS:
		var blended: Vector3 = (pose[key] as Vector3).lerp(_target_pose[key], weight)
		pose[key] = blended
		(joints[key] as Node3D).basis = Basis.from_euler(blended)


func snap_to_target() -> void:
	for key in JOINTS:
		pose[key] = _target_pose[key]
		(joints[key] as Node3D).basis = Basis.from_euler(_target_pose[key])
