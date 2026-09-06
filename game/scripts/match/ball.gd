class_name Ball
extends RigidBody3D

# The ball is honest rigid-body physics at all times. Shot accuracy is applied
# by aiming at an offset target, never by steering the ball mid-flight, so a
# miss rims out for a reason you can see.

signal touched_floor(position: Vector3)
signal hit_rim()
signal hit_backboard()

enum State { LOOSE, HELD, SHOT, PASS, DEAD }

const BOUNCE := 0.78
const FRICTION := 0.62

var state: State = State.LOOSE
var holder: Node3D = null
var hold_anchor: Node3D = null
## Who released it and what they were attempting; read by the match rules.
var shot_by: int = -1
var shot_points: int = 2
var shot_from := Vector3.ZERO
var pass_target: int = -1
var last_touched_by: int = -1

var _floor_cooldown := 0.0


static func create() -> Ball:
	var ball := Ball.new()
	ball.name = "Ball"
	ball.mass = CourtMetrics.BALL_MASS
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball.linear_damp = 0.06
	ball.angular_damp = 0.35

	var physics := PhysicsMaterial.new()
	physics.bounce = BOUNCE
	physics.friction = FRICTION
	ball.physics_material_override = physics

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CourtMetrics.BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = CourtMetrics.BALL_RADIUS
	sphere_mesh.height = CourtMetrics.BALL_RADIUS * 2.0
	sphere_mesh.radial_segments = 24
	sphere_mesh.rings = 16
	mesh.mesh = sphere_mesh
	var material := Materials.ball_material()
	material.albedo_texture = _build_skin()
	mesh.mesh.surface_set_material(0, material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ball.add_child(mesh)
	return ball


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_floor_cooldown = maxf(0.0, _floor_cooldown - delta)
	if state == State.HELD and is_instance_valid(hold_anchor):
		global_position = hold_anchor.global_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func hold(new_holder: Node3D, anchor: Node3D, player_index: int) -> void:
	holder = new_holder
	hold_anchor = anchor
	last_touched_by = player_index
	state = State.HELD
	freeze = true
	shot_by = -1
	pass_target = -1


func release(velocity: Vector3, spin: Vector3, new_state: State) -> void:
	holder = null
	hold_anchor = null
	state = new_state
	freeze = false
	linear_velocity = velocity
	angular_velocity = spin


func go_loose() -> void:
	holder = null
	hold_anchor = null
	state = State.LOOSE
	freeze = false


func is_live() -> bool:
	return state != State.DEAD


func speed() -> float:
	return linear_velocity.length()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("rim"):
		hit_rim.emit()
	elif body.is_in_group("backboard"):
		hit_backboard.emit()
	elif _floor_cooldown <= 0.0 and global_position.y < CourtMetrics.BALL_RADIUS * 3.0:
		_floor_cooldown = 0.12
		touched_floor.emit(global_position)


static func _build_skin() -> ImageTexture:
	const W := 256
	const H := 128
	var base := Color(0.80, 0.40, 0.13)
	var seam := Color(0.12, 0.09, 0.08)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var v := float(y) / float(H)
		for x in W:
			var u := float(x) / float(W)
			var colour := base.lightened(0.06 * sin(v * PI))
			# Two great circles plus the pair of curved seams a real ball has.
			var on_seam := absf(fposmod(u, 0.5) - 0.25) < 0.012
			on_seam = on_seam or absf(v - 0.5) < 0.012
			var wave := 0.5 + 0.26 * sin(u * TAU * 2.0)
			on_seam = on_seam or absf(v - wave) < 0.013
			on_seam = on_seam or absf(v - (1.0 - wave)) < 0.013
			img.set_pixel(x, y, seam if on_seam else colour)
	return ImageTexture.create_from_image(img)
