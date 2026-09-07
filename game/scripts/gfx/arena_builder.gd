class_name ArenaBuilder
extends RefCounted

# Builds the static world: floor, seating bowl, crowd, courtside furniture,
# rigging and lights. Everything is generated, so the repo carries no art.

const TIER_COUNT := 16
const TIER_RISE := 0.40
const TIER_DEPTH := 0.82
const SEAT_SPACING := 0.60
const VOMITORY_EVERY := 22
const COURTSIDE_Z := CourtSurface.FLOOR_WIDTH * 0.5 - 0.6


static func build(parent: Node3D, home: Dictionary, away: Dictionary,
		arena: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var court_viewport := CourtSurface.render_to_texture(parent, home, arena, seed_value)
	_bake_floor_mipmaps(_add_floor(parent, court_viewport.get_texture()), court_viewport)
	if bool(arena.get("outdoor", false)):
		_add_outdoor_surround(parent, arena)
	else:
		_add_bowl(parent, home, arena)
		Crowd.build(parent, home, _seat_transforms(rng), rng)
		_add_rigging(parent, home, away, arena)
	_add_courtside(parent, home, away, arena)
	_add_lights(parent, arena)
	_add_environment(parent, arena)


## Floor collision and nothing else, for headless balance runs.
static func build_collision_only(parent: Node3D) -> void:
	_add_floor_body(parent)


static func roof_height() -> float:
	return TIER_RISE * TIER_COUNT + 10.0


static func _add_floor(parent: Node3D, texture: Texture2D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(CourtSurface.FLOOR_LENGTH, CourtSurface.FLOOR_WIDTH)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	mesh.mesh = plane
	mesh.material_override = Materials.floor_material(texture)
	parent.add_child(mesh)

	_add_floor_body(parent)
	return mesh


# A ViewportTexture carries no mip levels, so the floor material's request for
# anisotropic mipmap filtering was quietly sampling level 0 everywhere. Grain
# and lines are sub-pixel once the floor tilts away, which is why the court
# boiled whenever the camera moved. Bake the render once it exists and hand the
# material a texture that can actually be filtered.
static func _bake_floor_mipmaps(mesh: MeshInstance3D, viewport: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(mesh) or not is_instance_valid(viewport):
		return
	var image := viewport.get_texture().get_image()
	if image == null:
		push_warning("Court texture never rendered; floor stays unfiltered")
		return
	image.generate_mipmaps()
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(image)
	viewport.queue_free()


static func _add_floor_body(parent: Node3D) -> void:
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
	CollisionLayers.apply_to_world(body)
	parent.add_child(body)


static func _add_bowl(parent: Node3D, home: Dictionary, arena: Dictionary) -> void:
	var concrete := Materials.flat(Color(arena["wall"]), 0.96)
	var riser := Materials.flat(Color(arena["wall"]).darkened(0.25), 0.96)
	var seat := Materials.flat(Color(arena["seats"]), 0.85)
	var inner_x := CourtSurface.FLOOR_LENGTH * 0.5
	var inner_z := CourtSurface.FLOOR_WIDTH * 0.5

	for tier in TIER_COUNT:
		var y := TIER_RISE * float(tier)
		var out := float(tier) * TIER_DEPTH
		_ring_slab(parent, inner_x + out, inner_z + out, y, TIER_DEPTH, TIER_RISE,
			seat if tier % 4 != 0 else riser)

	# Fascia below the first tier, carrying the team colour like an LED ribbon.
	var ribbon := Materials.emissive(Color(home["primary"]).lightened(0.15), 0.8)
	_ring_slab(parent, inner_x - 0.05, inner_z - 0.05, 0.0, 0.12, 0.55, ribbon)

	var wall_out := float(TIER_COUNT) * TIER_DEPTH
	_ring_slab(parent, inner_x + wall_out, inner_z + wall_out,
		TIER_RISE * TIER_COUNT, 1.2, 10.0, concrete)


static func _add_outdoor_surround(parent: Node3D, arena: Dictionary) -> void:
	var fence := Materials.flat(Color(arena["wall"]).lightened(0.15), 0.9)
	_ring_slab(parent, CourtSurface.FLOOR_LENGTH * 0.5, CourtSurface.FLOOR_WIDTH * 0.5,
		0.0, 0.25, 3.2, fence)


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


static func _seat_transforms(rng: RandomNumberGenerator) -> Array[Transform3D]:
	var seats: Array[Transform3D] = []
	var inner_x := CourtSurface.FLOOR_LENGTH * 0.5
	var inner_z := CourtSurface.FLOOR_WIDTH * 0.5
	for tier in range(1, TIER_COUNT):
		var y := TIER_RISE * float(tier) + 0.44
		var out := float(tier) * TIER_DEPTH
		var half_x := inner_x + out + TIER_DEPTH * 0.3
		var half_z := inner_z + out + TIER_DEPTH * 0.3
		seats.append_array(_seat_row(-half_x, half_x, half_z, y, PI, rng, false))
		seats.append_array(_seat_row(-half_x, half_x, -half_z, y, 0.0, rng, false))
		seats.append_array(_seat_row(-half_z, half_z, half_x, y, -PI * 0.5, rng, true))
		seats.append_array(_seat_row(-half_z, half_z, -half_x, y, PI * 0.5, rng, true))
	return seats


static func _seat_row(from: float, to: float, offset: float, y: float, yaw: float,
		rng: RandomNumberGenerator, swap_axes: bool) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var index := 0
	var pos := from
	while pos < to:
		pos += SEAT_SPACING
		index += 1
		# Leave a gangway every so often; a solid wall of people looks fake.
		if index % VOMITORY_EVERY < 2 or rng.randf() < 0.09:
			continue
		var origin := Vector3(pos, y, offset) if not swap_axes else Vector3(offset, y, pos)
		out.append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.22, 0.22)),
			origin))
	return out


static func _add_courtside(parent: Node3D, home: Dictionary, away: Dictionary,
		arena: Dictionary) -> void:
	var dark := Materials.flat(Color(0.10, 0.10, 0.12), 0.8)
	# Scorer's table at centre, on the far side from the broadcast camera.
	var table := MeshInstance3D.new()
	var table_box := BoxMesh.new()
	table_box.size = Vector3(7.2, 0.78, 0.72)
	table.mesh = table_box
	table.material_override = Materials.flat(Color(home["accent"]), 0.7)
	table.position = Vector3(0.0, 0.39, -COURTSIDE_Z)
	parent.add_child(table)

	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(7.4, 0.06, 0.86)
	top.mesh = top_box
	top.material_override = dark
	top.position = Vector3(0.0, 0.80, -COURTSIDE_Z)
	parent.add_child(top)

	_add_bench(parent, home, Vector3(-8.0, 0.0, -COURTSIDE_Z - 0.3))
	_add_bench(parent, away, Vector3(8.0, 0.0, -COURTSIDE_Z - 0.3))
	_add_camera_side_seating(parent, arena)


static func _add_bench(parent: Node3D, team: Dictionary, at: Vector3) -> void:
	var seat := Materials.flat(Color(team["primary"]), 0.8)
	var frame := Materials.flat(Color(0.12, 0.12, 0.14), 0.7)
	for i in 8:
		var chair := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.46, 0.46, 0.46)
		chair.mesh = box
		chair.material_override = seat
		chair.position = at + Vector3(float(i) * 0.56 - 1.96, 0.23, 0.0)
		parent.add_child(chair)

		var back := MeshInstance3D.new()
		var back_box := BoxMesh.new()
		back_box.size = Vector3(0.46, 0.46, 0.07)
		back.mesh = back_box
		back.material_override = frame
		back.position = chair.position + Vector3(0.0, 0.34, -0.22)
		parent.add_child(back)


static func _add_camera_side_seating(parent: Node3D, arena: Dictionary) -> void:
	# A row of courtside seats on the broadcast side gives the camera something
	# in the foreground other than empty floor.
	var material := Materials.flat(Color(arena["seats"]).darkened(0.25), 0.85)
	for i in 26:
		var chair := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		chair.mesh = box
		chair.material_override = material
		chair.position = Vector3(float(i) * 1.2 - 15.0, 0.25, COURTSIDE_Z + 0.2)
		chair.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(chair)


static func _add_rigging(parent: Node3D, home: Dictionary, away: Dictionary,
		arena: Dictionary) -> void:
	var roof_y := roof_height()
	var roof := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CourtSurface.FLOOR_LENGTH + TIER_COUNT * TIER_DEPTH * 2.0,
		0.8, CourtSurface.FLOOR_WIDTH + TIER_COUNT * TIER_DEPTH * 2.0)
	roof.mesh = box
	roof.material_override = Materials.flat(Color(arena["wall"]).darkened(0.55), 1.0)
	roof.position = Vector3(0.0, roof_y, 0.0)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(roof)

	var truss := Materials.flat(Color(0.13, 0.13, 0.15), 0.6, 0.4)
	for x in [-14.0, -7.0, 7.0, 14.0]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(0.45, 0.45, box.size.z * 0.9)
		beam.mesh = beam_mesh
		beam.material_override = truss
		beam.position = Vector3(x, roof_y - 0.7, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(beam)

	_add_banners(parent, home, away, roof_y)


static func _add_banners(parent: Node3D, home: Dictionary, away: Dictionary,
		roof_y: float) -> void:
	var colours := [Color(home["primary"]), Color(home["secondary"]),
		Color(home["accent"]), Color(away["primary"])]
	for i in 8:
		var banner := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.5, 2.6)
		banner.mesh = quad
		var material := Materials.flat(colours[i % colours.size()], 0.95)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		banner.material_override = material
		var side := 1.0 if i % 2 == 0 else -1.0
		banner.position = Vector3(float(i / 2) * 4.4 - 6.6, roof_y - 3.2,
			side * (CourtSurface.FLOOR_WIDTH * 0.5 + 5.5))
		banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(banner)


static func _add_lights(parent: Node3D, arena: Dictionary) -> void:
	var outdoor := bool(arena.get("outdoor", false))

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-58.0, 34.0, 0.0)
	key.light_energy = 1.05 if outdoor else 0.62
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 55.0
	key.directional_shadow_blend_splits = true
	key.shadow_blur = 1.4
	parent.add_child(key)

	# Fill from the opposite side with no shadow, so darker skin tones keep
	# their form instead of falling into black.
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-24.0, -142.0, 0.0)
	fill.light_energy = 0.30
	fill.light_color = Color(0.82, 0.88, 1.0)
	fill.shadow_enabled = false
	parent.add_child(fill)

	if outdoor:
		return

	var height := TIER_RISE * TIER_COUNT + 8.0
	for x in [-9.5, -3.2, 3.2, 9.5]:
		for z in [-5.0, 5.0]:
			var spot := SpotLight3D.new()
			spot.position = Vector3(x, height, z)
			spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			spot.spot_range = height + 9.0
			spot.spot_angle = 56.0
			spot.spot_attenuation = 1.5
			spot.light_energy = 1.15
			spot.light_color = Color(1.0, 0.98, 0.94)
			# Only one rank casts shadows; eight shadow maps buys nothing.
			spot.shadow_enabled = z > 0.0
			spot.shadow_blur = 2.0
			spot.light_volumetric_fog_energy = 1.6
			parent.add_child(spot)


static func _add_environment(parent: Node3D, arena: Dictionary) -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var outdoor := bool(arena.get("outdoor", false))

	env.background_mode = Environment.BG_SKY if outdoor else Environment.BG_COLOR
	env.background_color = Color(arena["wall"]).darkened(0.62)
	if outdoor:
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.24, 0.36, 0.58)
		sky_material.sky_horizon_color = Color(0.62, 0.58, 0.52)
		sky_material.ground_bottom_color = Color(0.16, 0.16, 0.18)
		sky.sky_material = sky_material
		env.sky = sky

	# Ambient is fill, not lighting. Carrying half the exposure from every
	# direction at once flattens every surface and is most of why the court
	# read as cartoon: nothing had a dark side.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.38, 0.48)
	env.ambient_light_energy = 0.46 if outdoor else 0.20

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 4.0
	env.tonemap_exposure = 1.05

	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.6

	# Contact shadows do most of the work of sitting a player on the floor
	# rather than floating above it.
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.6
	env.ssao_power = 2.0
	env.ssao_light_affect = 0.25

	env.ssil_enabled = not OS.has_feature("mobile")
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.9

	# Pushing saturation above 1 is the other half of the cartoon look. Let the
	# kit colours carry it instead, and buy the punch back with contrast.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.97

	# Haze in the air so the rigs throw visible shafts down onto the floor.
	# Volumetric fog is a Forward+ feature, and it is not cheap enough to ask a
	# phone for.
	if not outdoor and not OS.has_feature("mobile"):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0025
		env.volumetric_fog_albedo = Color(0.80, 0.84, 0.94)
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_length = 42.0
		env.volumetric_fog_gi_inject = 0.0

	world.environment = env
	parent.add_child(world)
