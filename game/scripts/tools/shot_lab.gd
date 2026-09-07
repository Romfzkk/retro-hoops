extends Node3D

# Two modes, both headless:
#
#   (default)     Fires real shots through the physics engine from a spread of
#                 distances, aimed dead centre. Any miss means the solver or
#                 the rim geometry is wrong. This is the correctness check.
#
#   --calibrate   Integrates the same trajectories analytically and reports the
#                 make rate per accuracy band. No physics, so it finishes in a
#                 frame instead of half an hour. Valid because the default mode
#                 confirms the physics tracks the analytic arc.
#
# godot --headless --path game res://scenes/dev_shot_lab.tscn [-- --calibrate]

const DISTANCES: Array[float] = [1.5, 2.5, 4.0, 5.5, 7.0, 8.5, 10.0]
const CALIBRATION_DISTANCES: Array[float] = [1.8, 4.5, 7.24, 9.0]
const CALIBRATION_ACCURACIES: Array[float] = [0.35, 0.50, 0.65, 0.80, 0.92]
const SAMPLES := 4000
const RELEASE_HEIGHT := 2.15
const TIMEOUT := 4.0

# Clean drop: the ball clears the ring with this much room either side.
const CLEAN_MARGIN := CourtMetrics.RIM_RADIUS - CourtMetrics.BALL_RADIUS
# Past that it catches iron, and some of those still fall.
const RATTLE_MARGIN := CLEAN_MARGIN + 0.075
const RATTLE_MAKE_CHANCE := 0.33

var hoop: Hoop
var ball: Ball

var _index := -1
var _elapsed := 0.0
var _scored := false
var _results: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260907
	if FrameCapture.has_flag("--calibrate"):
		_calibrate()
		return

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.4, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	floor_body.add_child(shape)
	CollisionLayers.apply_to_world(floor_body)
	add_child(floor_body)

	hoop = Hoop.create(0, Color.WHITE)
	add_child(hoop)
	hoop.scored.connect(func(_points): _scored = true)

	ball = Ball.create()
	add_child(ball)
	_next_shot()


func _physics_process(delta: float) -> void:
	if hoop == null:
		return
	_elapsed += delta
	hoop.check_ball(ball)
	if _scored:
		_record("MADE")
		return
	if _elapsed > TIMEOUT or ball.global_position.y < 0.3:
		_record("MISS  ended %.2fm from rim" % Vector2(
			ball.global_position.x - hoop.rim_position.x,
			ball.global_position.z - hoop.rim_position.z).length())


func _record(outcome: String) -> void:
	_results.append("%.1fm  %s" % [DISTANCES[_index], outcome])
	_next_shot()


func _next_shot() -> void:
	_index += 1
	_scored = false
	_elapsed = 0.0
	if _index >= DISTANCES.size():
		print("--- shot lab: physics ---")
		for line in _results:
			print(line)
		get_tree().quit()
		return

	var distance := DISTANCES[_index]
	var rim := hoop.rim_position
	var from := Vector3(rim.x - distance, RELEASE_HEIGHT, 0.0)
	var time := ShotSolver.flight_time(from.distance_to(rim), _arc_bias(distance))
	ball.go_loose()
	ball.global_position = from
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.release(ShotSolver.launch_velocity(from, rim, time), Vector3.ZERO,
		Ball.State.SHOT)
	ball.shot_points = 2


func _calibrate() -> void:
	print("--- shot lab: accuracy calibration ---")
	var rim := CourtMetrics.rim_position(0)
	for distance in CALIBRATION_DISTANCES:
		for accuracy in CALIBRATION_ACCURACIES:
			var from := Vector3(rim.x - distance, RELEASE_HEIGHT, 0.0)
			var made := 0
			for i in SAMPLES:
				if _drops(from, rim, accuracy, distance):
					made += 1
			print("%5.2fm  acc %.2f  ->  %5.1f%%" % [
				distance, accuracy, float(made) / float(SAMPLES) * 100.0])
	get_tree().quit()


func _drops(from: Vector3, rim: Vector3, accuracy: float, distance: float) -> bool:
	var target := ShotSolver.aim_point(rim, from, accuracy, _rng)
	var time := ShotSolver.flight_time(from.distance_to(target), _arc_bias(distance))
	var launch := ShotSolver.launch_velocity(from, target, time)
	var crossing: Variant = _rim_plane_crossing(from, launch, rim.y)
	if crossing == null:
		return false
	var point: Vector3 = crossing
	var offset := Vector2(point.x - rim.x, point.z - rim.z).length()
	if offset <= CLEAN_MARGIN:
		return true
	if offset <= RATTLE_MARGIN:
		return _rng.randf() < RATTLE_MAKE_CHANCE
	return false


# Where the shot passes down through the ring plane, or null if it never gets
# that high.
func _rim_plane_crossing(from: Vector3, launch: Vector3, plane_y: float) -> Variant:
	var g := ShotSolver.GRAVITY
	var dy := from.y - plane_y
	var discriminant := launch.y * launch.y + 2.0 * g * dy
	if discriminant < 0.0:
		return null
	var time := (launch.y + sqrt(discriminant)) / g
	if time <= 0.0:
		return null
	return from + Vector3(launch.x * time, 0.0, launch.z * time)


func _arc_bias(distance: float) -> float:
	return clampf(1.0 - distance / 9.0, 0.15, 0.95)
