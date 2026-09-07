class_name BroadcastCamera
extends Camera3D

# Camera rig for the match. Every mode resolves to a wanted eye/target pair and
# the rig damps toward it, so switching modes never snaps.

const SIDELINE_Z := 17.0
const EYE_HEIGHT := 7.6

var mode: int = Settings.CameraMode.BROADCAST
var target: Node3D
var focus_point := Vector3.ZERO
var attack_basket := 0

var _eye := Vector3(0.0, EYE_HEIGHT, SIDELINE_Z)
var _look := Vector3.ZERO
var _fov := 48.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	fov = _fov
	position = _eye
	look_at(_look)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	var wanted_eye := _eye
	var wanted_look := _look
	match mode:
		Settings.CameraMode.BROADCAST:
			var pair := _broadcast()
			wanted_eye = pair[0]
			wanted_look = pair[1]
		Settings.CameraMode.BEHIND:
			var pair := _behind()
			wanted_eye = pair[0]
			wanted_look = pair[1]
		Settings.CameraMode.HIGH:
			wanted_eye = Vector3(focus_point.x * 0.4,
				ArenaBuilder.roof_height() - 2.4, 11.5)
			wanted_look = Vector3(focus_point.x * 0.7, 0.0, focus_point.z * 0.3)
		Settings.CameraMode.COURTSIDE:
			wanted_eye = Vector3(focus_point.x * 0.35, 2.4, SIDELINE_Z - 8.0)
			wanted_look = Vector3(focus_point.x, 1.5, focus_point.z)
		Settings.CameraMode.RAIL:
			var sign_x := CourtMetrics.attack_sign(attack_basket)
			wanted_eye = Vector3(sign_x * (CourtMetrics.HALF_LENGTH + 5.0), 5.4,
				focus_point.z * 0.25)
			wanted_look = Vector3(focus_point.x, 1.6, focus_point.z)

	# Outside the building every mode renders the underside of the roof, which
	# is an unlit black wall filling the screen.
	wanted_eye.y = minf(wanted_eye.y, ArenaBuilder.roof_height() - 1.2)

	var damping := clampf(delta * 3.6, 0.0, 1.0)
	_eye = _eye.lerp(wanted_eye, damping)
	_look = _look.lerp(wanted_look, clampf(delta * 5.2, 0.0, 1.0))

	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 2.4)
		var jolt := Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0),
			_rng.randfn(0.0, 1.0)) * _shake * 0.09
		position = _eye + jolt
	else:
		position = _eye
	look_at(_look, Vector3.UP)
	fov = lerpf(fov, _fov, clampf(delta * 3.0, 0.0, 1.0))


func _broadcast() -> Array:
	# Dolly with the play but stay short of the ball so the camera reads as a
	# camera operator panning, not a chase cam.
	var x := clampf(focus_point.x * 0.52, -8.5, 8.5)
	var depth := SIDELINE_Z - clampf(absf(focus_point.z) * 0.18, 0.0, 1.6)
	_fov = 50.0 + clampf(absf(focus_point.x) * 0.24, 0.0, 7.0)
	return [Vector3(x, EYE_HEIGHT, depth),
		Vector3(focus_point.x * 0.94, 1.55, focus_point.z * 0.45)]


func _behind() -> Array:
	if target == null:
		return _broadcast()
	var rim := CourtMetrics.rim_position(attack_basket)
	var to_rim := (rim - target.global_position)
	to_rim.y = 0.0
	if to_rim.length() < 0.5:
		to_rim = Vector3.FORWARD
	var back := -to_rim.normalized()
	_fov = 55.0
	return [target.global_position + back * 6.4 + Vector3.UP * 3.4,
		target.global_position + Vector3.UP * 1.5 - back * 3.0]
