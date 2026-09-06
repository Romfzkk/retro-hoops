class_name MatchContext
extends RefCounted

# Snapshot of the live state, refreshed once per frame and handed to the AI and
# the camera so neither has to reach back into the match scene.

enum Phase { TIPOFF, LIVE, SHOT_IN_FLIGHT, LOOSE_BALL, DEAD, INBOUND, FREE_THROW, OVER }

var phase: Phase = Phase.TIPOFF
var ball: Ball
var carrier: PlayerPawn
var possession := 0
var shot_clock := 24.0
var quarter_remaining := 300.0
var difficulty := 1
var teams: Array[Array] = [[], []]
var predicted_rebound := Vector3.ZERO


func is_live() -> bool:
	return phase == Phase.LIVE or phase == Phase.SHOT_IN_FLIGHT \
		or phase == Phase.LOOSE_BALL


func opponents_of(team_index: int) -> Array:
	return teams[1 - team_index]


func nearest(to: Vector3, candidates: Array) -> PlayerPawn:
	var best: PlayerPawn = null
	var best_distance := INF
	for pawn: PlayerPawn in candidates:
		var distance: float = pawn.global_position.distance_squared_to(to)
		if distance < best_distance:
			best_distance = distance
			best = pawn
	return best


## Where a live ball will next be catchable, used for rebounds and loose balls.
static func landing_point(ball_node: Ball, floor_height: float = 1.0) -> Vector3:
	var position := ball_node.global_position
	var velocity := ball_node.linear_velocity
	var gravity := ShotSolver.GRAVITY
	var height := position.y - floor_height
	if height <= 0.0 and velocity.y <= 0.0:
		return position
	# Solve the downward crossing of the catch height.
	var discriminant := velocity.y * velocity.y + 2.0 * gravity * height
	if discriminant < 0.0:
		return position
	var time := (velocity.y + sqrt(discriminant)) / gravity
	return position + Vector3(velocity.x * time, 0.0, velocity.z * time)
