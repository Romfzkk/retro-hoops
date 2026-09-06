class_name ShotSolver
extends RefCounted

# Turns a shot attempt into a launch velocity. Accuracy is applied by moving
# the aim point, never by nudging the ball in flight, so every miss is a real
# trajectory that can still rattle in.

const GRAVITY := 9.806
const MIN_FLIGHT := 0.62
const MAX_FLIGHT := 1.55
const MAX_AIM_ERROR := 0.55

# How far a defender's hand has to be from the ball before the shot is clean.
const CONTEST_RADIUS := 1.9
const CONTEST_HEIGHT := 0.75


static func flight_time(distance: float, arc_bias: float) -> float:
	# Longer shots get a flatter, faster arc; floaters near the rim hang.
	var base := 0.70 + distance * 0.052
	return clampf(base * lerpf(0.88, 1.22, clampf(arc_bias, 0.0, 1.0)),
		MIN_FLIGHT, MAX_FLIGHT)


static func launch_velocity(from: Vector3, to: Vector3, time: float) -> Vector3:
	var delta := to - from
	return Vector3(
		delta.x / time,
		delta.y / time + 0.5 * GRAVITY * time,
		delta.z / time)


# 0 is a hopeless attempt, 1 is dead centre. The pieces are deliberately
# additive so a bad release can be carried by a great shooter and vice versa.
static func accuracy(player: Dictionary, distance: float, behind_arc: bool,
		release_quality: float, contest: float, movement: float,
		fatigue: float, difficulty: int) -> float:
	var rating: float
	if behind_arc:
		rating = float(player["thr"])
	elif distance > 4.6:
		rating = float(player["mid"])
	else:
		rating = float(player["cls"])

	var skill := clampf((rating - 30.0) / 62.0, 0.0, 1.0)
	var range_penalty := clampf((distance - shooting_range(player)) * 0.055, 0.0, 0.45)
	var contest_penalty := clampf(contest, 0.0, 1.0) * lerpf(0.42, 0.22, skill)
	var movement_penalty := clampf(movement, 0.0, 1.0) * 0.20
	var fatigue_penalty := clampf(fatigue, 0.0, 1.0) * 0.18
	var release := clampf(release_quality, 0.0, 1.0)

	var value := 0.30 + skill * 0.42 + release * 0.30
	value -= range_penalty + contest_penalty + movement_penalty + fatigue_penalty
	# The difficulty dial moves the AI's edge, not the player's ceiling.
	value -= float(difficulty) * 0.012
	return clampf(value, 0.02, 0.995)


static func shooting_range(player: Dictionary) -> float:
	# Where a shooter stops being comfortable, in metres from the rim.
	return 5.0 + float(player["thr"]) * 0.045


static func aim_point(rim: Vector3, from: Vector3, accuracy_value: float,
		rng: RandomNumberGenerator) -> Vector3:
	var miss := pow(1.0 - accuracy_value, 1.55) * MAX_AIM_ERROR
	# Split the error into depth (short/long) and drift (left/right); real
	# misses are far more often short or long than sideways.
	var to_rim := Vector3(rim.x - from.x, 0.0, rim.z - from.z).normalized()
	var across := to_rim.cross(Vector3.UP)
	var depth := rng.randfn(0.0, miss)
	var drift := rng.randfn(0.0, miss * 0.55)
	var vertical := rng.randfn(0.0, miss * 0.28)
	return rim + to_rim * depth + across * drift + Vector3.UP * vertical


# 0 when nobody is near, 1 when a hand is right in the shooter's face.
static func contest_level(shooter: Vector3, shooter_height: float,
		defenders: Array) -> float:
	var worst := 0.0
	for defender in defenders:
		var pawn := defender as Node3D
		if pawn == null:
			continue
		var offset := pawn.global_position - shooter
		var flat := Vector2(offset.x, offset.z).length()
		if flat > CONTEST_RADIUS:
			continue
		var closeness := 1.0 - flat / CONTEST_RADIUS
		var height_edge := clampf((offset.y + CONTEST_HEIGHT) / CONTEST_HEIGHT, 0.0, 1.6)
		worst = maxf(worst, closeness * height_edge)
	return clampf(worst, 0.0, 1.0)


# Where the ball should leave the hand: above and slightly in front of the head.
static func release_point(pawn: Node3D, shoulder_height: float,
		facing: Vector3) -> Vector3:
	return pawn.global_position + Vector3.UP * (shoulder_height + 0.42) \
		+ facing * 0.22
