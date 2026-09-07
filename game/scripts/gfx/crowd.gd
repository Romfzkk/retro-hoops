class_name Crowd
extends MultiMeshInstance3D

# The stands, as one MultiMesh. Each spectator is a body and a head welded into
# a single mesh so the whole bowl is one draw call, and the sway/cheer motion
# happens in the vertex shader rather than on the CPU.

const SEAT_SPACING := 0.60
const ROW_SKIP_CHANCE := 0.10

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float sway = 0.035;
uniform float excitement = 0.0;

varying vec3 seat_colour;

void vertex() {
	float phase = float(INSTANCE_ID) * 0.7391;
	float t = TIME * 1.3 + phase * 6.2831;
	// Lean side to side, and jump out of the seat when the crowd is up.
	float height = max(VERTEX.y + 0.45, 0.0);
	VERTEX.x += sin(t) * sway * height;
	VERTEX.z += cos(t * 0.7) * sway * 0.6 * height;
	VERTEX.y += max(sin(t * 2.1), 0.0) * excitement * 0.22;
	seat_colour = COLOR.rgb;
}

void fragment() {
	ALBEDO = seat_colour;
	ROUGHNESS = 0.95;
}
"""

var _material: ShaderMaterial


static func build(parent: Node3D, team: Dictionary, seats: Array[Transform3D],
		rng: RandomNumberGenerator) -> Crowd:
	if seats.is_empty():
		return null
	var crowd := Crowd.new()
	crowd.name = "Crowd"
	crowd.multimesh = _make_multimesh(seats, team, rng)
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := Shader.new()
	shader.code = SHADER
	crowd._material = ShaderMaterial.new()
	crowd._material.shader = shader
	crowd.material_override = crowd._material
	parent.add_child(crowd)
	return crowd


static func _make_multimesh(seats: Array[Transform3D], team: Dictionary,
		rng: RandomNumberGenerator) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _spectator_mesh()
	mm.instance_count = seats.size()

	var kit := [Color(team["primary"]), Color(team["secondary"]), Color(team["accent"])]
	for i in seats.size():
		mm.set_instance_transform(i, seats[i])
		var colour: Color
		if rng.randf() < 0.40:
			colour = kit[rng.randi() % kit.size()]
		else:
			colour = Color.from_hsv(rng.randf(), rng.randf_range(0.05, 0.45),
				rng.randf_range(0.18, 0.62))
		mm.set_instance_color(i, colour)
	return mm


static func _spectator_mesh() -> ArrayMesh:
	# Torso and head in one surface. Two MultiMeshes would double the draw
	# calls for no visible gain at this distance.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.70
	torso.radial_segments = 6
	torso.rings = 2
	tool.append_from(torso, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)))

	var head := SphereMesh.new()
	head.radius = 0.105
	head.height = 0.21
	head.radial_segments = 6
	head.rings = 4
	tool.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.44, 0.0)))

	tool.generate_normals()
	return tool.commit()


func set_excitement(value: float) -> void:
	_material.set_shader_parameter("excitement", clampf(value, 0.0, 1.0))
