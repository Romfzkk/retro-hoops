class_name Hoop
extends Node3D

# One basket: backboard, rim, net and stanchion. The rim is a ring of small
# sphere colliders rather than a trimesh torus, which keeps rattle-outs cheap
# and stops the ball tunnelling through a thin ring at speed.

signal scored(points: int)

const RIM_COLLIDERS := 20
const RIM_TUBE_RADIUS := 0.019
const NET_LENGTH := 0.45
const SCORE_PLANE_DROP := 0.03

var basket: int = 0
var rim_position: Vector3

var _net_material: ShaderMaterial
var _previous_ball_y := 0.0
var _armed := false
var _swish := 0.0

const NET_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 net_colour : source_color = vec4(0.92, 0.92, 0.90, 1.0);
uniform float swish = 0.0;
uniform float strands = 12.0;
uniform float rings = 7.0;

void vertex() {
	// UV.y runs 0 at the rim to 1 at the hem; the hem reacts most.
	float t = clamp(UV.y, 0.0, 1.0);
	VERTEX.y -= swish * t * t * 0.10;
	VERTEX.x *= 1.0 + swish * t * 0.28;
	VERTEX.z *= 1.0 + swish * t * 0.28;
}

void fragment() {
	vec2 grid = vec2(UV.x * strands, UV.y * rings);
	vec2 diag = vec2(grid.x + grid.y, grid.x - grid.y);
	vec2 cell = abs(fract(diag) - 0.5);
	float line = min(cell.x, cell.y);
	if (line > 0.13) {
		discard;
	}
	ALBEDO = net_colour.rgb;
	ROUGHNESS = 0.9;
}
"""


static func create(basket_index: int, backboard_tint: Color) -> Hoop:
	var hoop := Hoop.new()
	hoop.basket = basket_index
	hoop.name = "Hoop%d" % basket_index
	hoop.rim_position = CourtMetrics.rim_position(basket_index)
	hoop._build(backboard_tint)
	return hoop


func _build(backboard_tint: Color) -> void:
	var facing := -CourtMetrics.attack_sign(basket)
	var baseline_x := -facing * CourtMetrics.HALF_LENGTH
	var board_x := baseline_x + facing * CourtMetrics.BACKBOARD_FROM_BASELINE
	var board_centre := Vector3(board_x, CourtMetrics.BACKBOARD_BOTTOM
		+ CourtMetrics.BACKBOARD_HEIGHT * 0.5, 0.0)

	_add_backboard(board_centre, backboard_tint)
	_add_rim()
	_add_net()
	_add_stanchion(baseline_x, board_centre)


func _add_backboard(centre: Vector3, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "Backboard"
	body.position = centre
	body.add_to_group("backboard")

	var box := BoxShape3D.new()
	box.size = Vector3(0.06, CourtMetrics.BACKBOARD_HEIGHT, CourtMetrics.BACKBOARD_WIDTH)
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)

	var glass := MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = box.size
	glass.mesh = glass_mesh
	glass.material_override = Materials.glass()
	body.add_child(glass)

	# Perimeter padding only. A full box behind the glass turns the whole
	# backboard into a coloured panel.
	var pad := Materials.flat(tint, 0.6, 0.1)
	var half_h := CourtMetrics.BACKBOARD_HEIGHT * 0.5
	var half_w := CourtMetrics.BACKBOARD_WIDTH * 0.5
	var bars := [
		[Vector3(0.0, half_h, 0.0), Vector3(0.08, 0.07, CourtMetrics.BACKBOARD_WIDTH + 0.07)],
		[Vector3(0.0, -half_h, 0.0), Vector3(0.08, 0.07, CourtMetrics.BACKBOARD_WIDTH + 0.07)],
		[Vector3(0.0, 0.0, half_w), Vector3(0.08, CourtMetrics.BACKBOARD_HEIGHT, 0.07)],
		[Vector3(0.0, 0.0, -half_w), Vector3(0.08, CourtMetrics.BACKBOARD_HEIGHT, 0.07)],
	]
	for bar in bars:
		var mesh := MeshInstance3D.new()
		var bar_box := BoxMesh.new()
		bar_box.size = bar[1]
		mesh.mesh = bar_box
		mesh.material_override = pad
		mesh.position = bar[0]
		body.add_child(mesh)

	_add_shooter_square(body)
	CollisionLayers.apply_to_world(body)
	add_child(body)


func _add_shooter_square(parent: Node3D) -> void:
	# 59cm x 45cm, sitting just above the rim on the court-facing side.
	const SQUARE_W := 0.59
	const SQUARE_H := 0.45
	var facing := -CourtMetrics.attack_sign(basket)
	var offset_y := CourtMetrics.RIM_HEIGHT + SQUARE_H * 0.5 \
		- (CourtMetrics.BACKBOARD_BOTTOM + CourtMetrics.BACKBOARD_HEIGHT * 0.5)
	var material := Materials.unshaded(Color(0.95, 0.95, 0.93))
	var bars := [
		[Vector3(0.0, offset_y + SQUARE_H * 0.5, 0.0), Vector3(0.01, 0.03, SQUARE_W)],
		[Vector3(0.0, offset_y - SQUARE_H * 0.5, 0.0), Vector3(0.01, 0.03, SQUARE_W)],
		[Vector3(0.0, offset_y, SQUARE_W * 0.5), Vector3(0.01, SQUARE_H, 0.03)],
		[Vector3(0.0, offset_y, -SQUARE_W * 0.5), Vector3(0.01, SQUARE_H, 0.03)],
	]
	for bar in bars:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar[1]
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = bar[0] + Vector3(facing * 0.035, 0.0, 0.0)
		parent.add_child(mesh)


func _add_rim() -> void:
	var body := StaticBody3D.new()
	body.name = "Rim"
	body.position = rim_position
	body.add_to_group("rim")
	var physics := PhysicsMaterial.new()
	physics.bounce = 0.42
	physics.friction = 0.5
	body.physics_material_override = physics

	for i in RIM_COLLIDERS:
		var angle := TAU * float(i) / float(RIM_COLLIDERS)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = RIM_TUBE_RADIUS
		shape.shape = sphere
		shape.position = Vector3(cos(angle), 0.0, sin(angle)) * CourtMetrics.RIM_RADIUS
		body.add_child(shape)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = CourtMetrics.RIM_RADIUS - RIM_TUBE_RADIUS
	torus.outer_radius = CourtMetrics.RIM_RADIUS + RIM_TUBE_RADIUS
	torus.rings = 32
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = Materials.flat(Color(0.92, 0.32, 0.09), 0.35, 0.6)
	body.add_child(ring)

	_add_rim_bracket(body)
	CollisionLayers.apply_to_world(body)
	add_child(body)


func _add_rim_bracket(parent: Node3D) -> void:
	var facing := -CourtMetrics.attack_sign(basket)
	var bracket := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CourtMetrics.RIM_FROM_BASELINE
		- CourtMetrics.BACKBOARD_FROM_BASELINE + 0.1, 0.05, 0.12)
	bracket.mesh = box
	bracket.material_override = Materials.flat(Color(0.15, 0.15, 0.17), 0.4, 0.7)
	bracket.position = Vector3(-facing * (CourtMetrics.RIM_RADIUS + box.size.x * 0.4),
		-0.01, 0.0)
	parent.add_child(bracket)


func _add_net() -> void:
	var net := MeshInstance3D.new()
	net.name = "Net"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = CourtMetrics.RIM_RADIUS * 0.98
	cylinder.bottom_radius = CourtMetrics.RIM_RADIUS * 0.62
	cylinder.height = NET_LENGTH
	cylinder.radial_segments = 24
	cylinder.rings = 6
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	net.mesh = cylinder
	var shader := Shader.new()
	shader.code = NET_SHADER
	_net_material = ShaderMaterial.new()
	_net_material.shader = shader
	net.material_override = _net_material
	net.position = rim_position - Vector3(0.0, NET_LENGTH * 0.5, 0.0)
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(net)


func _add_stanchion(baseline_x: float, board_centre: Vector3) -> void:
	var facing := -CourtMetrics.attack_sign(basket)
	var dark := Materials.flat(Color(0.11, 0.11, 0.13), 0.45, 0.4)
	var padded := Materials.flat(Color(0.08, 0.08, 0.09), 0.9)

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.28, board_centre.y + 0.4, 0.34)
	post.mesh = post_mesh
	post.material_override = padded
	post.position = Vector3(baseline_x - facing * 0.65, post_mesh.size.y * 0.5, 0.0)
	add_child(post)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(absf(post.position.x - board_centre.x), 0.13, 0.16)
	arm.mesh = arm_mesh
	arm.material_override = dark
	arm.position = Vector3((post.position.x + board_centre.x) * 0.5,
		board_centre.y - 0.1, 0.0)
	add_child(arm)

	var base := StaticBody3D.new()
	var base_shape := CollisionShape3D.new()
	var base_box := BoxShape3D.new()
	base_box.size = Vector3(1.1, 0.9, 1.9)
	base_shape.shape = base_box
	base.add_child(base_shape)
	var base_mesh := MeshInstance3D.new()
	var base_box_mesh := BoxMesh.new()
	base_box_mesh.size = base_box.size
	base_mesh.mesh = base_box_mesh
	base_mesh.material_override = padded
	base.add_child(base_mesh)
	base.position = Vector3(baseline_x - facing * 1.0, base_box.size.y * 0.5, 0.0)
	CollisionLayers.apply_to_world(base)
	add_child(base)


func _process(delta: float) -> void:
	if _swish > 0.0:
		_swish = maxf(0.0, _swish - delta * 2.6)
		_net_material.set_shader_parameter("swish", _swish)


# Called by the match each physics tick. Returns the points scored, or 0.
func check_ball(ball: Ball) -> int:
	var plane_y := rim_position.y - SCORE_PLANE_DROP
	var y := ball.global_position.y
	var previous := _previous_ball_y
	_previous_ball_y = y

	if y > plane_y + 0.25:
		_armed = true
	if not _armed or previous <= plane_y or y > plane_y:
		return 0
	if ball.linear_velocity.y >= 0.0:
		return 0
	var flat := Vector2(ball.global_position.x - rim_position.x,
		ball.global_position.z - rim_position.z).length()
	if flat > CourtMetrics.RIM_RADIUS - CourtMetrics.BALL_RADIUS * 0.35:
		return 0

	_armed = false
	_swish = 1.0
	_net_material.set_shader_parameter("swish", 1.0)
	var points := ball.shot_points if ball.state == Ball.State.SHOT else 2
	scored.emit(points)
	return points
