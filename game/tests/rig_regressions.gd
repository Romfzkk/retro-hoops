extends Node3D

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	if not ModelRig.available():
		push_error("The bundled player must import before rig tests run")
		get_tree().quit(1)
		return
	var team: Dictionary = League.new_league(11)["teams"][7]
	var player: Dictionary = team["roster"][0]
	var visible_rig := PlayerRig.create(player, team, self, true)
	var simulation_rig := PlayerRig.create(player, team, self, false)
	add_child(visible_rig)
	add_child(simulation_rig)
	_check("imported model accepted", visible_rig._retarget != null)
	_check("reach does not depend on renderer", is_equal_approx(visible_rig.standing_reach, simulation_rig.standing_reach))
	_check("shoulder measurement does not depend on renderer", is_equal_approx(visible_rig.shoulder_height, simulation_rig.shoulder_height))
	_check("left wrist anchor uses its bone", (visible_rig.hand_l.get_parent() as BoneAttachment3D).bone_idx == visible_rig._bone("wrist_l"))
	_check("right wrist anchor uses its bone", (visible_rig.hand_r.get_parent() as BoneAttachment3D).bone_idx == visible_rig._bone("wrist_r"))
	_check("headless release anchor matches the rendered player", visible_rig.grip_position(1.0).distance_to(simulation_rig.grip_position(1.0)) < 0.001)
	var skeleton := visible_rig._skeleton
	var space := ModelRig.relative_transform(skeleton, visible_rig)
	for start in ModelRetarget.LIMB_ENDS:
		var end: String = ModelRetarget.LIMB_ENDS[start]
		var a := space * skeleton.get_bone_global_pose(visible_rig._bone(start)).origin
		var b := space * skeleton.get_bone_global_pose(visible_rig._bone(end)).origin
		_check(start + " hangs down once", (b - a).normalized().dot(Vector3.DOWN) > 0.99)
	var before := visible_rig.grip_position(1.0)
	visible_rig.set_target("shoulder_l", Vector3(PI, 0.0, 0.0))
	visible_rig.snap_to_target()
	_check("overhead pose raises the same wrist", visible_rig.grip_position(1.0).y > before.y + 0.5)
	visible_rig.set_target("shoulder_l", Vector3.ZERO)
	visible_rig.snap_to_target()
	_check("return to neutral restores wrist", visible_rig.grip_position(1.0).distance_to(before) < 0.001)
	visible_rig.ground_feet()
	_check("support foot meets the floor", absf(minf(visible_rig.anchor_position(visible_rig.foot_l).y, visible_rig.anchor_position(visible_rig.foot_r).y)) < 0.001)
	_skin_weights(visible_rig)
	_transformed_bounds()
	print("Rig regressions: %d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _skin_weights(rig: PlayerRig) -> void:
	var model: Node3D = rig._skeleton.get_meta("model_root")
	var invalid := 0
	var checked := 0
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var bindings := instance.skin.get_bind_count() if instance.skin != null else rig._skeleton.get_bone_count()
			if vertices.is_empty() or weights.is_empty() or weights.size() != bones.size():
				invalid += 1
				continue
			var influences := weights.size() / vertices.size()
			for vertex in vertices.size():
				var total := 0.0
				for influence in influences:
					var index := vertex * influences + influence
					var weight := weights[index]
					if not is_finite(weight) or weight < 0.0 or (weight > 0.0 and (bones[index] < 0 or bones[index] >= bindings)):
						invalid += 1
					total += weight
				if absf(total - 1.0) > 0.001:
					invalid += 1
				checked += 1
	_check("imported skin has normalized weights and valid bindings", checked > 0 and invalid == 0)


func _transformed_bounds() -> void:
	var model := Node3D.new()
	var nested := Node3D.new()
	nested.position = Vector3(0.0, 3.0, 0.0)
	nested.scale = Vector3.ONE * 2.0
	model.add_child(nested)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	nested.add_child(mesh)
	var bounds := ModelRig.model_bounds(model)
	_check("bounds include nested scale", is_equal_approx(bounds.size.y, 2.0))
	_check("bounds include nested translation", is_equal_approx(bounds.position.y, 2.0))
	model.free()


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
