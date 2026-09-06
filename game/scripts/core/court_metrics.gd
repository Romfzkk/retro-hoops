class_name CourtMetrics
extends RefCounted

# Regulation dimensions in metres. The court runs along X, sidelines along Z,
# and the origin is centre court at floor level.

const LENGTH := 28.65
const WIDTH := 15.24
const HALF_LENGTH := LENGTH * 0.5
const HALF_WIDTH := WIDTH * 0.5

const RIM_HEIGHT := 3.048
const RIM_RADIUS := 0.2286
const RIM_FROM_BASELINE := 1.575
const RIM_X := HALF_LENGTH - RIM_FROM_BASELINE

const BACKBOARD_WIDTH := 1.829
const BACKBOARD_HEIGHT := 1.067
const BACKBOARD_BOTTOM := 2.90
const BACKBOARD_FROM_BASELINE := 1.2192

const BALL_RADIUS := 0.1195
const BALL_MASS := 0.62

const THREE_ARC_RADIUS := 7.24
const THREE_CORNER_Z := 6.70
# Where the arc meets the straight corner run, measured from the baseline.
const THREE_CORNER_DEPTH := 4.267

const PAINT_WIDTH := 4.88
const PAINT_DEPTH := 5.79
const FREE_THROW_X := HALF_LENGTH - PAINT_DEPTH
const CIRCLE_RADIUS := 1.80
const RESTRICTED_RADIUS := 1.25

const LINE_WIDTH := 0.05


static func rim_position(basket: int) -> Vector3:
	# basket 0 defends -X and attacks +X.
	return Vector3(RIM_X if basket == 0 else -RIM_X, RIM_HEIGHT, 0.0)


static func attack_sign(basket: int) -> float:
	return 1.0 if basket == 0 else -1.0


static func is_behind_three(point: Vector3, basket: int) -> bool:
	var rim := rim_position(basket)
	var flat := Vector2(point.x - rim.x, point.z - rim.z)
	if absf(point.z) >= THREE_CORNER_Z:
		# Corners are a straight line, not part of the arc.
		return absf(point.x) < HALF_LENGTH
	return flat.length() >= THREE_ARC_RADIUS


static func inside_court(point: Vector3, margin: float = 0.0) -> bool:
	return absf(point.x) <= HALF_LENGTH + margin and absf(point.z) <= HALF_WIDTH + margin


static func in_paint(point: Vector3, basket: int) -> bool:
	var sign_x := attack_sign(basket)
	return absf(point.z) <= PAINT_WIDTH * 0.5 \
		and point.x * sign_x >= FREE_THROW_X \
		and point.x * sign_x <= HALF_LENGTH
