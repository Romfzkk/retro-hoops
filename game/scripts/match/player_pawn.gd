class_name PlayerPawn
extends CharacterBody3D

# A single player on court. Reads a PlayerIntent, moves, and owns the ball
# actions. Ratings map to real units - metres per second, metres of vertical -
# so a 99 vertical actually gets a hand over the rim and a 40 does not.

signal shot_released(pawn: PlayerPawn, points: int, quality: float)
signal ball_passed(pawn: PlayerPawn, target: PlayerPawn)
signal ball_gathered(pawn: PlayerPawn)
signal dunked(pawn: PlayerPawn)
signal steal_attempted(pawn: PlayerPawn, target: PlayerPawn)

enum State { LOCOMOTION, SHOOT, PASS, DUNK, LAYUP, JUMP, STEAL, STUMBLE }

const GRAVITY := 9.806
const CHARGE_TIME := 0.72
const IDEAL_RELEASE := Vector2(0.56, 0.80)
const OVERCHARGE := 1.25
const GATHER_TIME := 0.16
const STEAL_TIME := 0.42
const STUMBLE_TIME := 0.55
const DUNK_RANGE := 3.4
const LAYUP_RANGE := 3.1
const BODY_RADIUS := 0.38
const PICKUP_RADIUS := 0.95

var data: Dictionary
var team_index := 0
var basket := 0
var lineup_slot := 0
var is_user_controlled := false

var intent := PlayerIntent.new()
var ball: Ball
var teammates: Array[PlayerPawn] = []
var opponents: Array[PlayerPawn] = []

var rig: PlayerRig
var animator: PlayerAnimator
var ball_anchor: Node3D
var stamina := 1.0
var has_ball := false

var state: State = State.LOCOMOTION
var state_time := 0.0
var shot_charge := 0.0
var shot_released_this_attempt := false
var ball_hand := 1.0
var pickup_cooldown := 0.0

var _max_speed := 7.0
var _acceleration := 24.0
var _jump_height := 0.7
var _rng := RandomNumberGenerator.new()
var _dribble_phase := 0.0
var _facing := Vector3.FORWARD
var _pending_pass: PlayerPawn


static func create(player: Dictionary, team: Dictionary, team_idx: int,
		attacking_basket: int, host: Node) -> PlayerPawn:
	var pawn := PlayerPawn.new()
	pawn.data = player
	pawn.team_index = team_idx
	pawn.basket = attacking_basket
	pawn.name = "P%d_%d" % [team_idx, int(player["id"])]
	pawn._setup(team, host)
	return pawn


func _setup(team: Dictionary, host: Node) -> void:
	_rng.seed = int(data["id"]) * 7919 + 13
	_max_speed = 5.1 + float(data["spd"]) / 99.0 * 3.0
	_acceleration = 13.0 + float(data["acc"]) / 99.0 * 17.0
	_jump_height = 0.40 + float(data["vrt"]) / 99.0 * 0.70

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = float(data["h"]) * 0.01
	shape.shape = capsule
	shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(shape)

	rig = PlayerRig.create(data, team, host)
	add_child(rig)
	animator = PlayerAnimator.new(rig)
	animator.top_speed = _max_speed

	ball_anchor = Node3D.new()
	ball_anchor.name = "BallAnchor"
	add_child(ball_anchor)


func standing_reach() -> float:
	return rig.standing_reach


func jump_height() -> float:
	return _jump_height * (0.72 + 0.28 * stamina)


func max_reach() -> float:
	return standing_reach() + jump_height()


func can_dunk() -> bool:
	return max_reach() > CourtMetrics.RIM_HEIGHT + 0.16


func rim() -> Vector3:
	return CourtMetrics.rim_position(basket)


func facing() -> Vector3:
	return _facing


func distance_to_rim() -> float:
	var r := rim()
	return Vector2(global_position.x - r.x, global_position.z - r.z).length()


func _physics_process(delta: float) -> void:
	state_time += delta
	pickup_cooldown = maxf(0.0, pickup_cooldown - delta)
	_dribble_phase += delta * TAU * 2.0

	match state:
		State.LOCOMOTION:
			_tick_locomotion(delta)
		State.SHOOT:
			_tick_shoot(delta)
		State.PASS:
			_tick_pass(delta)
		State.DUNK:
			_tick_dunk(delta)
		State.LAYUP:
			_tick_layup(delta)
		State.JUMP:
			_tick_jump(delta)
		State.STEAL:
			_tick_steal(delta)
		State.STUMBLE:
			_tick_stumble(delta)

	_apply_gravity(delta)
	move_and_slide()
	_separate_from_others()
	_update_stamina(delta)
	_update_ball_anchor(delta)
	_drive_animator(delta)
	intent.clear_edges()


func _tick_locomotion(delta: float) -> void:
	_walk(delta, 1.0)
	_face_travel(delta)
	if has_ball:
		_offence_inputs()
	else:
		_defence_inputs()


func _offence_inputs() -> void:
	if intent.shoot_pressed:
		_begin_shot_attempt()
	elif intent.pass_pressed:
		_begin_pass()


func _defence_inputs() -> void:
	if intent.shoot_pressed:
		_begin_contest_jump()
	elif intent.pass_pressed and _ball_carrier_in_reach() != null:
		_begin_steal()


func _begin_shot_attempt() -> void:
	var to_rim := distance_to_rim()
	var heading := (rim() - global_position)
	heading.y = 0.0
	var driving := velocity.length() > 2.0 and heading.normalized().dot(
		Vector3(velocity.x, 0.0, velocity.z).normalized()) > 0.35
	if to_rim < DUNK_RANGE and can_dunk() and driving \
			and (intent.sprint or intent.special_pressed):
		_enter(State.DUNK)
		return
	if to_rim < LAYUP_RANGE and driving:
		_enter(State.LAYUP)
		return
	_enter(State.SHOOT)
	shot_charge = 0.0
	shot_released_this_attempt = false


func _tick_shoot(delta: float) -> void:
	_walk(delta, 0.25)
	_face_point(rim(), delta, 14.0)
	if shot_released_this_attempt:
		if is_on_floor() and state_time > 0.35:
			_enter(State.LOCOMOTION)
		return

	shot_charge = minf(shot_charge + delta / CHARGE_TIME, OVERCHARGE)
	if state_time > 0.16 and is_on_floor():
		velocity.y = sqrt(2.0 * GRAVITY * jump_height() * 0.55)
	var auto_release := shot_charge >= OVERCHARGE
	if intent.shoot_released or (not intent.shoot_held and state_time > 0.1) or auto_release:
		_release_shot(auto_release)


func _release_shot(forced: bool) -> void:
	shot_released_this_attempt = true
	if ball == null or ball.holder != self:
		return
	var to_rim := distance_to_rim()
	var behind_arc := CourtMetrics.is_behind_three(global_position, basket)
	var quality := _release_quality(forced)
	var contest := ShotSolver.contest_level(global_position, rig.shoulder_height, opponents)
	var movement := clampf(velocity.length() / maxf(_max_speed, 0.01), 0.0, 1.0)
	var accuracy := ShotSolver.accuracy(data, to_rim, behind_arc, quality, contest,
		movement, 1.0 - stamina, Settings.get_value("difficulty"))

	var from := ShotSolver.release_point(self, rig.shoulder_height, _facing)
	var target := ShotSolver.aim_point(rim(), from, accuracy, _rng)
	var arc_bias := clampf(1.0 - to_rim / 9.0, 0.15, 0.95)
	var time := ShotSolver.flight_time(from.distance_to(target), arc_bias)
	var launch := ShotSolver.launch_velocity(from, target, time)

	ball.global_position = from
	ball.shot_by = get_instance_id()
	ball.shot_points = 3 if behind_arc else 2
	ball.shot_from = global_position
	ball.release(launch, -_facing.cross(Vector3.UP) * 12.0, Ball.State.SHOT)
	has_ball = false
	pickup_cooldown = 0.35
	shot_released.emit(self, ball.shot_points, accuracy)


func _release_quality(forced: bool) -> float:
	var style := int(Settings.get_value("shot_style"))
	if style == Settings.ShotStyle.AUTO or not is_user_controlled:
		# AI and assisted shooting lean on the rating instead of the meter.
		return 0.52 + float(data["mid"] if not is_user_controlled else 70) / 99.0 * 0.30
	if forced:
		return 0.10
	var centre := (IDEAL_RELEASE.x + IDEAL_RELEASE.y) * 0.5
	var half_window := (IDEAL_RELEASE.y - IDEAL_RELEASE.x) * 0.5
	var error := absf(shot_charge - centre)
	if error <= half_window:
		return 1.0 - error / maxf(half_window, 0.001) * 0.15
	return clampf(0.85 - (error - half_window) * 2.2, 0.0, 0.85)


func _begin_pass() -> void:
	_pending_pass = _pick_pass_target()
	if _pending_pass == null:
		return
	_enter(State.PASS)


func _pick_pass_target() -> PlayerPawn:
	if intent.pass_target >= 0:
		for mate in teammates:
			if mate.lineup_slot == intent.pass_target:
				return mate
	var aim := Vector3(intent.aim.x, 0.0, intent.aim.y)
	if aim.length() < 0.2:
		aim = _facing
	var best: PlayerPawn = null
	var best_score := -INF
	for mate in teammates:
		if mate == self:
			continue
		var offset := mate.global_position - global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		var distance := flat.length()
		if distance < 1.0:
			continue
		var alignment := aim.normalized().dot(flat.normalized())
		var score := alignment * 2.0 - distance * 0.03
		if _passing_lane_blocked(mate):
			score -= 1.5
		if score > best_score:
			best_score = score
			best = mate
	return best


func _passing_lane_blocked(target: PlayerPawn) -> bool:
	var from := global_position + Vector3.UP * 1.1
	var to := target.global_position + Vector3.UP * 1.1
	var lane := to - from
	var length := lane.length()
	if length < 0.01:
		return false
	var direction := lane / length
	for defender in opponents:
		var offset := defender.global_position + Vector3.UP * 1.1 - from
		var along := offset.dot(direction)
		if along < 0.4 or along > length - 0.4:
			continue
		if (offset - direction * along).length() < 0.65:
			return true
	return false


func _tick_pass(delta: float) -> void:
	_walk(delta, 0.4)
	if _pending_pass != null:
		_face_point(_pending_pass.global_position, delta, 16.0)
	if state_time >= 0.14 and has_ball and _pending_pass != null:
		_send_pass(_pending_pass)
	if state_time > 0.32:
		_enter(State.LOCOMOTION)


func _send_pass(target: PlayerPawn) -> void:
	if ball == null or ball.holder != self:
		return
	var from := global_position + Vector3.UP * (rig.shoulder_height * 0.92)
	# Lead the receiver so a moving target does not have to stop.
	var lead := target.velocity * 0.22
	var to := target.global_position + lead + Vector3.UP * (target.rig.shoulder_height * 0.8)
	var distance := from.distance_to(to)
	var zip := clampf(0.16 + distance * 0.026, 0.18, 0.55)
	var accuracy := clampf(float(data["pas"]) / 99.0, 0.2, 1.0)
	var wobble := (1.0 - accuracy) * 0.35
	to += Vector3(_rng.randfn(0.0, wobble), _rng.randfn(0.0, wobble * 0.4),
		_rng.randfn(0.0, wobble))

	ball.global_position = from
	ball.pass_target = target.get_instance_id()
	ball.release(ShotSolver.launch_velocity(from, to, zip), Vector3.ZERO, Ball.State.PASS)
	has_ball = false
	pickup_cooldown = 0.2
	target.pickup_cooldown = 0.0
	ball_passed.emit(self, target)


func _tick_dunk(delta: float) -> void:
	var target := rim()
	if state_time < 0.12:
		_walk(delta, 0.9)
	_face_point(target, delta, 18.0)
	if state_time >= 0.10 and is_on_floor():
		var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		var rise := sqrt(2.0 * GRAVITY * jump_height())
		velocity = flat.normalized() * minf(flat.length() * 1.9, _max_speed * 1.15)
		velocity.y = rise
	var hand_height := global_position.y + standing_reach()
	if has_ball and hand_height > CourtMetrics.RIM_HEIGHT + 0.05 and velocity.y < 1.2:
		_finish_dunk()
	if is_on_floor() and state_time > 0.4:
		_enter(State.LOCOMOTION)


func _finish_dunk() -> void:
	if ball == null or ball.holder != self:
		return
	var target := rim()
	ball.global_position = target + Vector3.UP * 0.10
	ball.shot_by = get_instance_id()
	ball.shot_points = 2
	ball.shot_from = global_position
	ball.release(Vector3(0.0, -4.4, 0.0) + velocity * 0.15,
		Vector3(6.0, 0.0, 0.0), Ball.State.SHOT)
	has_ball = false
	pickup_cooldown = 0.5
	dunked.emit(self)
	shot_released.emit(self, 2, 0.99)


func _tick_layup(delta: float) -> void:
	var target := rim()
	if state_time < 0.14:
		_walk(delta, 0.85)
	_face_point(target, delta, 16.0)
	if state_time >= 0.12 and is_on_floor():
		var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		velocity = flat.normalized() * minf(flat.length() * 1.2, _max_speed * 0.8)
		velocity.y = sqrt(2.0 * GRAVITY * jump_height() * 0.82)
	if has_ball and velocity.y < 0.6 and not is_on_floor():
		_release_layup()
	if is_on_floor() and state_time > 0.4:
		_enter(State.LOCOMOTION)


func _release_layup() -> void:
	if ball == null or ball.holder != self:
		return
	var contest := ShotSolver.contest_level(global_position, rig.shoulder_height, opponents)
	var accuracy := ShotSolver.accuracy(data, distance_to_rim(), false, 0.82,
		contest, 0.35, 1.0 - stamina, Settings.get_value("difficulty"))
	var from := global_position + Vector3.UP * (standing_reach() - 0.15) + _facing * 0.15
	# Aim off the glass rather than straight at the ring.
	var board_point := rim() + Vector3.UP * 0.28
	var target := ShotSolver.aim_point(board_point, from, accuracy, _rng)
	var time := ShotSolver.flight_time(from.distance_to(target), 0.85)
	ball.global_position = from
	ball.shot_by = get_instance_id()
	ball.shot_points = 2
	ball.shot_from = global_position
	ball.release(ShotSolver.launch_velocity(from, target, time),
		Vector3(0.0, 0.0, 6.0), Ball.State.SHOT)
	has_ball = false
	pickup_cooldown = 0.4
	shot_released.emit(self, 2, accuracy)


func _begin_contest_jump() -> void:
	if not is_on_floor():
		return
	_enter(State.JUMP)
	velocity.y = sqrt(2.0 * GRAVITY * jump_height())


func _tick_jump(delta: float) -> void:
	_walk(delta, 0.35)
	if is_on_floor() and state_time > 0.25:
		_enter(State.LOCOMOTION)


func _begin_steal() -> void:
	_enter(State.STEAL)
	steal_attempted.emit(self, _ball_carrier_in_reach())


func _tick_steal(delta: float) -> void:
	_walk(delta, 0.45)
	if state_time > STEAL_TIME:
		_enter(State.LOCOMOTION)


func _tick_stumble(delta: float) -> void:
	_walk(delta, 0.15)
	if state_time > STUMBLE_TIME:
		_enter(State.LOCOMOTION)


func stumble() -> void:
	_enter(State.STUMBLE)


func _ball_carrier_in_reach() -> PlayerPawn:
	for defender in opponents:
		if defender.has_ball and global_position.distance_to(defender.global_position) < 1.6:
			return defender
	return null


func _walk(delta: float, control: float) -> void:
	var wish := Vector3(intent.move.x, 0.0, intent.move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var sprinting := intent.sprint and stamina > 0.05 and not has_ball_gathered()
	var top := _max_speed * (1.16 if sprinting else 1.0) * (0.78 + 0.22 * stamina)
	if has_ball:
		top *= 0.94
	var wanted := wish * top * control
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var rate := _acceleration * (1.0 if wish.length() > 0.1 else 1.6)
	var next := current.move_toward(wanted, rate * delta)
	velocity.x = next.x
	velocity.z = next.z


func has_ball_gathered() -> bool:
	return state == State.SHOOT or state == State.PASS or state == State.DUNK \
		or state == State.LAYUP


func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.6:
		_turn_towards(flat.normalized(), delta, 12.0)
	elif not has_ball and ball != null:
		_face_point(ball.global_position, delta, 8.0)


func _face_point(point: Vector3, delta: float, rate: float) -> void:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if flat.length() > 0.05:
		_turn_towards(flat.normalized(), delta, rate)


func _turn_towards(direction: Vector3, delta: float, rate: float) -> void:
	_facing = _facing.slerp(direction, clampf(delta * rate, 0.0, 1.0)).normalized()
	# The rig is modelled facing -Z, which is Godot's forward.
	rotation.y = atan2(-_facing.x, -_facing.z)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _separate_from_others() -> void:
	for other in teammates + opponents:
		if other == self:
			continue
		var offset := global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		var minimum := BODY_RADIUS * 2.0
		if distance < 0.001 or distance >= minimum:
			continue
		# Push apart rather than letting capsules grind; heavier players win.
		var mine := float(data["str"])
		var theirs := float(other.data["str"])
		var share := theirs / maxf(mine + theirs, 1.0)
		global_position += offset.normalized() * (minimum - distance) * share


func _update_stamina(delta: float) -> void:
	var effort := Vector3(velocity.x, 0.0, velocity.z).length() / maxf(_max_speed, 0.01)
	var endurance := 0.55 + float(data["sta"]) / 99.0 * 0.85
	if intent.sprint and effort > 0.5:
		stamina -= delta * 0.09 / endurance
	elif effort > 0.35:
		stamina -= delta * 0.035 / endurance
	else:
		stamina += delta * 0.085 * endurance
	stamina = clampf(stamina, 0.0, 1.0)


func _update_ball_anchor(delta: float) -> void:
	if not has_ball or ball == null:
		return
	var side := _facing.cross(Vector3.UP) * ball_hand * 0.34
	match state:
		State.SHOOT:
			var lift := lerpf(1.05, 1.42, clampf(shot_charge, 0.0, 1.0))
			ball_anchor.global_position = global_position \
				+ Vector3.UP * (rig.shoulder_height * lift) + _facing * 0.16 + side * 0.4
		State.PASS:
			ball_anchor.global_position = global_position \
				+ Vector3.UP * (rig.shoulder_height * 0.92) + _facing * 0.34
		State.DUNK, State.LAYUP:
			ball_anchor.global_position = global_position \
				+ Vector3.UP * (standing_reach() - 0.22) + _facing * 0.18 + side * 0.5
		_:
			var bounce := absf(sin(_dribble_phase))
			var height := lerpf(CourtMetrics.BALL_RADIUS + 0.02, rig.shoulder_height * 0.62,
				bounce)
			ball_anchor.global_position = global_position + Vector3.UP * height \
				+ _facing * 0.32 + side


func take_ball(new_ball: Ball) -> void:
	ball = new_ball
	has_ball = true
	ball_hand = 1.0 if _rng.randf() < 0.72 else -1.0
	_update_ball_anchor(0.0)
	ball.hold(self, ball_anchor, get_instance_id())
	ball_gathered.emit(self)


func lose_ball() -> void:
	has_ball = false
	pickup_cooldown = 0.25


func can_pick_up() -> bool:
	return pickup_cooldown <= 0.0 and state != State.STUMBLE


func _drive_animator(delta: float) -> void:
	animator.speed = Vector3(velocity.x, 0.0, velocity.z).length()
	animator.grounded = is_on_floor()
	animator.airborne = clampf(velocity.y / 4.0, -1.0, 1.0)
	animator.has_ball = has_ball
	animator.ball_hand = ball_hand
	animator.defending = not has_ball and _team_on_defence()
	animator.action = _animator_action()
	animator.action_t = _action_progress()
	animator.tick(delta)
	if animator.defending:
		animator.apply_defensive_arms()


func _team_on_defence() -> bool:
	if ball == null:
		return false
	for mate in teammates:
		if mate.has_ball:
			return false
	return not has_ball


func _animator_action() -> PlayerAnimator.Action:
	match state:
		State.SHOOT:
			return PlayerAnimator.Action.SHOOT
		State.PASS:
			return PlayerAnimator.Action.PASS
		State.DUNK:
			return PlayerAnimator.Action.DUNK
		State.LAYUP:
			return PlayerAnimator.Action.LAYUP
		State.JUMP:
			return PlayerAnimator.Action.BLOCK
		State.STEAL:
			return PlayerAnimator.Action.STEAL
	return PlayerAnimator.Action.NONE


func _action_progress() -> float:
	match state:
		State.SHOOT:
			if shot_released_this_attempt:
				return 1.0
			return clampf(shot_charge / OVERCHARGE, 0.0, 1.0)
		State.PASS:
			return clampf(state_time / 0.32, 0.0, 1.0)
		State.DUNK, State.LAYUP:
			return clampf(state_time / 0.55, 0.0, 1.0)
		State.JUMP:
			return clampf(state_time / 0.35, 0.0, 1.0)
		State.STEAL:
			return clampf(state_time / STEAL_TIME, 0.0, 1.0)
	return 0.0


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
