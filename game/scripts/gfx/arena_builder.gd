class_name ArenaBuilder
extends RefCounted

# Builds the static world: floor, seating bowl, crowd, rigging and lights.
# Everything here is generated so the repo carries no binary art.

const APRON := 2.6
const TIER_COUNT := 14
const TIER_RISE := 0.42
const TIER_DEPTH := 0.85
const CROWD_SEAT_SPACING := 0.62


static func build(parent: Node3D, team: Dictionary, arena: Dictionary,
		seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var court_viewport := CourtSurface.render_to_texture(parent, team, arena, seed_value)
	_add_floor(parent, court_viewport.get_texture())
	_add_bowl(parent, arena, rng)
	_add_crowd(parent, team, arena, rng)
	_add_rigging(parent, arena)
	_add_lights(parent, arena)
	_add_environment(parent, arena)


static func _add_floor(parent: Node3D, texture: Texture2D) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(CourtSurface.FLOOR_LENGTH, CourtSurface.FLOOR_WIDTH)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	mesh.mesh = plane
	mesh.material_override = Materials.floor_material(texture)
	parent.add_child(mesh)

	var body := StaticBody3D.new()
	body.name = "FloorBody"
	var physics := PhysicsMaterial.new()
	physics.bounce = 0.72
	physics.friction = 0.9
	body.physics_material_override = physics
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90.0, 0.4, 70.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	parent.add_child(body)


static func _add_bowl(parent: Node3D, arena: Dictionary, rng: RandomNumberGenerator) -> void:
	if bool(arena.get("outdoor", false)):
		_add_outdoor_surround(parent, arena)
		return

	var concrete := Materials.flat(Color(arena["wall"]), 0.95)
	var seat_colour := Materials.flat(Color(arena["seats"]), 0.8)
	var inner_x := CourtSurface.FLOOR_LENGTH * 0.5
	var inner_z := CourtSurface.FLOOR_WIDTH * 0.5

	for tier in TIER_COUNT:
		var y := TIER_RISE * float(tier)
		var out := float(tier) * TIER_DEPTH
		var material := seat_colour if tier % 3 != 0 else concrete
		_ring_slab(parent, inner_x + out, inner_z + out, y, TIER_DEPTH, TIER_RISE, material)

	# Back wall closing the bowl off.
	var wall_out := float(TIER_COUNT) * TIER_DEPTH
	_ring_slab(parent, inner_x + wall_out, inner_z + wall_out,
		TIER_RISE * TIER_COUNT, 1.2, 9.0, concrete)


static func _add_outdoor_surround(parent: Node3D, arena: Dictionary) -> void:
	var fence := Materials.flat(Color(arena["wall"]).lightened(0.15), 0.9)
	var inner_x := CourtSurface.FLOOR_LENGTH * 0.5
	var inner_z := CourtSurface.FLOOR_WIDTH * 0.5
	_ring_slab(parent, inner_x, inner_z, 0.0, 0.25, 3.2, fence)


static func _ring_slab(parent: Node3D, half_x: float, half_z: float, y: float,
		depth: float, height: float, material: Material) -> void:
	var spans := [
		[Vector3(0.0, y + height * 0.5, half_z + depth * 0.5),
			Vector3((half_x + depth) * 2.0, height, depth)],
		[Vector3(0.0, y + height * 0.5, -half_z - depth * 0.5),
			Vector3((half_x + depth) * 2.0, height, depth)],
		[Vector3(half_x + depth * 0.5, y + height * 0.5, 0.0),
			Vector3(depth, height, half_z * 2.0)],
		[Vector3(-half_x - depth * 0.5, y + height * 0.5, 0.0),
			Vector3(depth, height, half_z * 2.0)],
	]
	for span in spans:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = span[1]
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = span[0]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)


static func _add_crowd(parent: Node3D, team: Dictionary, arena: Dictionary,
		rng: RandomNumberGenerator) -> void:
	if bool(arena.get("outdoor", false)):
		return
	var seats: Array[Transform3D] = []
	var inner_x := CourtSurface.FLOOR_LENGTH * 0.5
	var inner_z := CourtSurface.FLOOR_WIDTH * 0.5
	for tier in range(1, TIER_COUNT):
		var y := TIER_RISE * float(tier) + 0.42
		var out := float(tier) * TIER_DEPTH
		var half_x := inner_x + out + TIER_DEPTH * 0.25
		var half_z := inner_z + out + TIER_DEPTH * 0.25
		seats.append_array(_seat_row(-half_x, half_x, half_z, y, 0.0, rng))
		seats.append_array(_seat_row(-half_x, half_x, -half_z, y, PI, rng))
		seats.append_array(_seat_row(-half_z, half_z, half_x, y, PI * 0.5, rng, true))
		seats.append_array(_seat_row(-half_z, half_z, -half_x, y, -PI * 0.5, rng, true))
	if seats.is_empty():
		return

	var multi := MultiMeshInstance3D.new()
	multi.name = "Crowd"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var body := CapsuleMesh.new()
	body.radius = 0.19
	body.height = 0.86
	body.radial_segments = 6
	body.rings = 2
	mm.mesh = body
	mm.instance_count = seats.size()

	var team_colours := [Color(team["primary"]), Color(team["secondary"]),
		Color(team["accent"])]
	for i in seats.size():
		mm.set_instance_transform(i, seats[i])
		var colour: Color = team_colours[rng.randi() % team_colours.size()] \
			if rng.randf() < 0.45 \
			else Color.from_hsv(rng.randf(), rng.randf_range(0.05, 0.4),
				rng.randf_range(0.25, 0.75))
		mm.set_instance_color(i, colour)
	multi.multimesh = mm
	var material := Materials.flat(Color.WHITE, 0.95)
	material.vertex_color_use_as_albedo = true
	multi.material_override = material
	multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(multi)


static func _seat_row(from: float, to: float, offset: float, y: float,
		yaw: float, rng: RandomNumberGenerator, swap_axes: bool = false) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var pos := from
	while pos < to:
		pos += CROWD_SEAT_SPACING
		if rng.randf() < 0.12:
			continue
		var origin := Vector3(pos, y, offset) if not swap_axes \
			else Vector3(offset, y, pos)
		var basis := Basis(Vector3.UP, yaw + rng.randf_range(-0.25, 0.25))
		out.append(Transform3D(basis, origin))
	return out


static func _add_rigging(parent: Node3D, arena: Dictionary) -> void:
	if bool(arena.get("outdoor", false)):
		return
	var truss := Materials.flat(Color(0.14, 0.14, 0.16), 0.6, 0.4)
	var roof_y := TIER_RISE * TIER_COUNT + 9.0
	var roof := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CourtSurface.FLOOR_LENGTH + TIER_COUNT * TIER_DEPTH * 2.0,
		0.6, CourtSurface.FLOOR_WIDTH + TIER_COUNT * TIER_DEPTH * 2.0)
	roof.mesh = box
	roof.material_override = Materials.flat(Color(arena["wall"]).darkened(0.4), 1.0)
	roof.position = Vector3(0.0, roof_y, 0.0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(roof)

	for x in [-9.0, 0.0, 9.0]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(0.5, 0.5, box.size.z)
		beam.mesh = beam_mesh
		beam.material_override = truss
		beam.position = Vector3(x, roof_y - 0.6, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(beam)


static func _add_lights(parent: Node3D, arena: Dictionary) -> void:
	var outdoor := bool(arena.get("outdoor", false))
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-62.0, 38.0, 0.0)
	key.light_energy = 1.15 if outdoor else 0.75
	key.light_color = Color(1.0, 0.96, 0.90)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60.0
	key.directional_shadow_blend_splits = true
	parent.add_child(key)

	if outdoor:
		return

	# Rigs over the court so players carry a real shadow under them. Kept wide
	# and soft: tight cones burn out the polished boards.
	var height := TIER_RISE * TIER_COUNT + 7.0
	for x in [-9.0, -3.0, 3.0, 9.0]:
		for z in [-4.5, 4.5]:
			var spot := SpotLight3D.new()
			spot.position = Vector3(x, height, z)
			spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			spot.spot_range = height + 8.0
			spot.spot_angle = 58.0
			spot.spot_attenuation = 1.4
			spot.light_energy = 1.1
			spot.light_color = Color(1.0, 0.97, 0.92)
			spot.shadow_enabled = z > 0.0
			parent.add_child(spot)


static func _add_environment(parent: Node3D, arena: Dictionary) -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var outdoor := bool(arena.get("outdoor", false))

	env.background_mode = Environment.BG_SKY if outdoor else Environment.BG_COLOR
	env.background_color = Color(arena["wall"]).darkened(0.55)
	if outdoor:
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.24, 0.36, 0.58)
		sky_material.sky_horizon_color = Color(0.62, 0.58, 0.52)
		sky_material.ground_bottom_color = Color(0.16, 0.16, 0.18)
		sky.sky_material = sky_material
		env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.55 if outdoor else 0.35

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4

	world.environment = env
	world.camera_attributes = _camera_attributes()
	parent.add_child(world)


static func _camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.auto_exposure_enabled = false
	return attributes
