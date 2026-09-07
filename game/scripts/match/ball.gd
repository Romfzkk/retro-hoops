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
## After this long an uncaught pass is anybody's ball.
const PASS_LIFETIME := 1.5
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
## A shot cannot be rebounded until it has hit iron or dropped below the ring.
## Without this, defenders pluck live shots out of the air mid-flight.
var rebound_ready := true
var touched_rim := false

var _floor_cooldown := 0.0
var _pass_age := 0.0
var _reached_rim_height := false
var network_remote := false
var _net_position := Vector3.ZERO


static func create() -> Ball:
	var ball := Ball.new()
	ball.name = "Ball"
	ball.mass = CourtMetrics.BALL_MASS
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	# REPLACE, not the default COMBINE: the world's default area damping is
	# still added under COMBINE, and even 0.1 bleeds enough speed over a 1.3s
	# flight to drop every shot a metre short of the aim point.
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 0.0
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp = 0.35

	var physics := PhysicsMaterial.new()
	physics.bounce = BOUNCE
	physics.friction = FRICTION
	ball.physics_material_override = physics
	CollisionLayers.apply_to_ball(ball)

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


func apply_network_state(position_: Vector3, velocity: Vector3, new_state: int) -> void:
	_net_position = position_
	linear_velocity = velocity
	state = new_state as State


func _physics_process(delta: float) -> void:
	if network_remote:
		# Snapshots arrive at 24Hz, so smooth between them rather than popping.
		global_position = global_position.lerp(_net_position,
			clampf(delta * 18.0, 0.0, 1.0))
		return
	_floor_cooldown = maxf(0.0, _floor_cooldown - delta)
	if state == State.HELD and is_instance_valid(hold_anchor):
		global_position = hold_anchor.global_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	elif state == State.PASS:
		_pass_age += delta
		if _pass_age >= PASS_LIFETIME:
			go_loose()
	elif state == State.SHOT and not rebound_ready:
		_track_shot_flight()


# A shot only becomes reboundable once it has actually been up at the rim.
# Arming purely on "below rim height" is true the instant it leaves the hand,
# which lets the nearest player catch every attempt a frame after release.
func _track_shot_flight() -> void:
	var height := global_position.y
	if height > CourtMetrics.RIM_HEIGHT + 0.05:
		_reached_rim_height = true
		return
	if _reached_rim_height and height < CourtMetrics.RIM_HEIGHT - 0.35:
		rebound_ready = true
		return
	# An air ball that never got up there is live again once it is falling.
	if linear_velocity.y < 0.0 and height < CourtMetrics.RIM_HEIGHT - 1.2:
		rebound_ready = true


func hold(new_holder: Node3D, anchor: Node3D, player_index: int) -> void:
	holder = new_holder
	hold_anchor = anchor
	last_touched_by = player_index
	state = State.HELD
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = anchor.global_position
	shot_by = -1
	pass_target = -1


## Teleport and throw in one step. Order matters: a frozen body has to be
## released before it is moved, or the physics server keeps the stale transform
## for the first step and the shot leaves from the wrong place.
func launch(from: Vector3, velocity: Vector3, spin: Vector3, new_state: State) -> void:
	holder = null
	hold_anchor = null
	freeze = false
	global_position = from
	release(velocity, spin, new_state)


func release(velocity: Vector3, spin: Vector3, new_state: State) -> void:
	holder = null
	hold_anchor = null
	state = new_state
	freeze = false
	linear_velocity = velocity
	angular_velocity = spin
	rebound_ready = new_state != State.SHOT
	_reached_rim_height = false
	touched_rim = false
	_pass_age = 0.0


func go_loose() -> void:
	holder = null
	hold_anchor = null
	state = State.LOOSE
	pass_target = -1
	rebound_ready = true
	freeze = false


## Parked between whistles. Held balls stay frozen either way, so the match
## never has to reason about freeze itself.
func set_paused(paused: bool) -> void:
	if state == State.HELD:
		return
	freeze = paused


func park() -> void:
	holder = null
	hold_anchor = null
	state = State.DEAD
	pass_target = -1
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func shot_has_fallen() -> bool:
	return rebound_ready and linear_velocity.y <= 0.0 \
		and global_position.y < CourtMetrics.RIM_HEIGHT - 0.35


func is_live() -> bool:
	return state != State.DEAD


func speed() -> float:
	return linear_velocity.length()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("rim"):
		rebound_ready = true
		touched_rim = true
		hit_rim.emit()
	elif body.is_in_group("backboard"):
		rebound_ready = true
		hit_backboard.emit()
	elif _floor_cooldown <= 0.0 and global_position.y < CourtMetrics.BALL_RADIUS * 3.0:
		_floor_cooldown = 0.12
		rebound_ready = true
		if state == State.PASS:
			state = State.LOOSE
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
