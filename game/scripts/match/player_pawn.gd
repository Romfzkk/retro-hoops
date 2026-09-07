class_name PlayerPawn
extends CharacterBody3D

# Movement, action timing and ball releases for one player.

signal shot_released(pawn: PlayerPawn, points: int, quality: float)
signal ball_passed(pawn: PlayerPawn, target: PlayerPawn)
signal ball_gathered(pawn: PlayerPawn)
signal dunked(pawn: PlayerPawn)
signal steal_attempted(pawn: PlayerPawn, target: PlayerPawn)

enum State { LOCOMOTION, SHOOT, PASS, DUNK, LAYUP, JUMP, STEAL, STUMBLE }

const GRAVITY := 9.806
const CHARGE_TIME := 0.85
## Where on the meter a release counts as clean. Wide enough to hit without
## staring at the bar; the earlier window was 0.18s long, which meant a tap
## produced the worst shot in the game and nobody could tell why.
const IDEAL_RELEASE := Vector2(0.44, 0.86)
const OVERCHARGE := 1.30
## Even a panicked release is a basketball shot, not a throw at the wall.
const MIN_RELEASE_QUALITY := 0.30
const RELEASE_EXTENSION := 0.08
const STEAL_TIME := 0.42
const STUMBLE_TIME := 0.55
const DUNK_RANGE := 3.4
## How long the dunk owns the player: the rise, the hang and the landing. It
## used to hand back 0.4s after touchdown, which cut the animation in half.
const DUNK_HANG := 0.95
const LAYUP_RANGE := 4.2
## Below this you go up with it whether or not you are running.
const STANDING_LAYUP_RANGE := 2.3
const DRIVE_SPEED := 1.2
## Dribbles per second, walking to sprinting.
const DRIBBLE_RATE := Vector2(2.2, 4.1)
const BODY_RADIUS := 0.38
const INTERCEPT_REACH := 0.85
const INTERCEPT_BASE := 0.07

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
var match_difficulty := 1
var has_ball := false
var actions_enabled := true
var movement_enabled := true
var free_throw_attempt := false
var _took_off := false
var _release_delay := -1.0
var _forced_release := false
var _queued_release := ""
var _released_at := 0.0
var last_release_charge := 0.0
var last_shot_kind := "JUMPER"

var state: State = State.LOCOMOTION
var state_time := 0.0
var shot_charge := 0.0
var shot_released_this_attempt := false
var ball_hand := 1.0
var pickup_cooldown := 0.0
## Set on clients in an online game: this pawn is drawn from host snapshots
## and never simulates locally.
var network_remote := false

var _max_speed := 7.0
var _acceleration := 24.0
var _jump_height := 0.7
var _rng := RandomNumberGenerator.new()
var dunk_power := 0.0
var _dribble_phase := 0.0
var _last_bounce := 0
var _facing := Vector3.FORWARD
var _pending_pass: PlayerPawn
var _net_position := Vector3.ZERO
var _net_yaw := 0.0
var _net_speed := 0.0
var _net_flags := 0
var _net_stamina := 1.0


static func create(player: Dictionary, team: Dictionary, team_idx: int,
		attacking_basket: int, host: Node, with_meshes: bool = true) -> PlayerPawn:
	var pawn := PlayerPawn.new()
	pawn.data = player
	pawn.team_index = team_idx
	pawn.basket = attacking_basket
	pawn.name = "P%d_%d" % [team_idx, int(player["id"])]
	pawn._setup(team, host, with_meshes)
	return pawn


## Mixed with the match seed so a player does not make the same sequence of
## misses in every single game. Seeding from the id alone made whole matches
## replay identically.
func set_random_seed(value: int) -> void:
	_rng.seed = int(data["id"]) * 7919 + 13 + value


func _setup(team: Dictionary, host: Node, with_meshes: bool) -> void:
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
	CollisionLayers.apply_to_player(self)

	rig = PlayerRig.create(data, team, host, with_meshes)
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


func apply_network_state(position_: Vector3, yaw: float, speed: float,
		flags: int, stamina_: float) -> void:
	_net_position = position_
	_net_yaw = yaw
	_net_speed = speed
	_net_flags = flags
	_net_stamina = stamina_


func _physics_process(delta: float) -> void:
	if network_remote:
		_tick_remote(delta)
		return
	state_time += delta
	pickup_cooldown = maxf(0.0, pickup_cooldown - delta)
	_tick_dribble(delta)

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

	var was_grounded := is_on_floor()
	var fall_speed := velocity.y
	_apply_gravity(delta)
	move_and_slide()
	if not was_grounded and is_on_floor() and fall_speed < -1.0:
		animator.landing = clampf(-fall_speed / 7.0, 0.0, 1.0)
	_separate_from_others()
	_update_stamina(delta)
	_drive_animator(delta)
	_update_ball_anchor(delta)
	var release := _queued_release
	_queued_release = ""
	match release:
		"shot": _release_shot(_forced_release)
		"pass":
			if is_instance_valid(_pending_pass):
				_send_pass(_pending_pass)
		"dunk": _finish_dunk()
		"layup": _release_layup()
	intent.clear_edges()


# Interpolate toward the last snapshot and drive the rig from the packed
# flags. Nothing here decides anything; the host already did.
func _tick_remote(delta: float) -> void:
	var blend := clampf(delta * 14.0, 0.0, 1.0)
	global_position = global_position.lerp(_net_position, blend)
	rotation.y = lerp_angle(rotation.y, _net_yaw, blend)
	stamina = _net_stamina

	var next_state := (_net_flags & 0x0F) as State
	state_time = 0.0 if next_state != state else state_time + delta
	state = next_state
	has_ball = bool(_net_flags & (1 << 4))
	ball_hand = 1.0 if bool(_net_flags & (1 << 6)) else -1.0

	animator.speed = _net_speed
	animator.grounded = bool(_net_flags & (1 << 5))
	animator.airborne = 0.0
	animator.has_ball = has_ball
	animator.ball_hand = ball_hand
	animator.defending = not has_ball
	animator.action = _animator_action()
	animator.action_t = _action_progress()
	animator.tick(delta)


# The ball is put on the floor and comes back, at a rate that follows the
# player. It used to bob at a fixed rate whatever they were doing, which is why
# moving with it looked like carrying rather than dribbling.
func _tick_dribble(delta: float) -> void:
	if not has_ball or has_ball_gathered() or not is_on_floor():
		# Park at the top of the bounce, where the ball sits in the hand, so
		# picking it back up never starts with it stuck to the floor.
		_dribble_phase = PI * 0.5
		_last_bounce = 0
		return
	var travel := Vector3(velocity.x, 0.0, velocity.z)
	var gait := clampf(travel.length() / maxf(_max_speed, 0.01), 0.0, 1.0)
	_dribble_phase += delta * PI * lerpf(DRIBBLE_RATE.x, DRIBBLE_RATE.y, gait)

	var bounce := int(_dribble_phase / PI)
	if bounce == _last_bounce:
		return
	_last_bounce = bounce
	Sound.play("bounce", -13.0, _rng.randf_range(0.94, 1.12))
	# Moving hard sideways puts the ball in the outside hand, so a change of
	# direction reads as a crossover instead of the ball sticking to one side.
	var lateral := _facing.cross(Vector3.UP).dot(travel.normalized())
	if gait > 0.35 and absf(lateral) > 0.5:
		ball_hand = signf(lateral) * rig.lateral_side(1.0)


func _tick_locomotion(delta: float) -> void:
	_walk(delta, 1.0)
	_face_travel(delta)
	if actions_enabled:
		if has_ball:
			_offence_inputs()
		else:
			_defence_inputs()


func _offence_inputs() -> void:
	if intent.shoot_pressed:
		_begin_shot_attempt()
	elif intent.pass_pressed and not free_throw_attempt:
		_begin_pass()


func _defence_inputs() -> void:
	if intent.shoot_pressed:
		contest_jump()
	elif intent.pass_pressed and _ball_carrier_in_reach() != null:
		_begin_steal()


## 0 is a routine put-down, 1 is a full-speed hammer. Fixed as the dunk starts
## so the hang, the slam and the crowd all agree on the same one.
func _dunk_power() -> float:
	var approach := clampf(Vector3(velocity.x, 0.0, velocity.z).length()
		/ maxf(_max_speed, 0.01), 0.0, 1.0)
	var skill := clampf((float(data["dnk"]) - 55.0) / 44.0, 0.0, 1.0)
	return clampf(approach * 0.55 + skill * 0.45, 0.0, 1.0)


func _begin_shot_attempt() -> void:
	# Cleared for every finish, not just jump shots: a dunk that inherited a
	# stale release skipped its own jump.
	shot_charge = 0.0
	shot_released_this_attempt = false
	_took_off = false
	_release_delay = -1.0
	if free_throw_attempt:
		_enter(State.SHOOT)
		return
	var to_rim := distance_to_rim()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var heading := (rim() - global_position)
	heading.y = 0.0
	var driving := flat.length() > DRIVE_SPEED and heading.normalized().dot(
		flat.normalized()) > 0.2
	if to_rim < DUNK_RANGE and can_dunk() and driving \
			and (intent.sprint or intent.special_pressed):
		dunk_power = _dunk_power()
		_enter(State.DUNK)
		return
	# Close in and pointed at the rim, going up with it is the shot. Requiring a
	# hard drive meant a defender bumping you off your run turned the layup you
	# asked for into a jump shot from two feet.
	var facing_rim := _facing.dot(heading.normalized()) > 0.3
	if to_rim < LAYUP_RANGE and (driving or facing_rim or to_rim < STANDING_LAYUP_RANGE):
		_enter(State.LAYUP)
		return
	_enter(State.SHOOT)


func _tick_shoot(delta: float) -> void:
	_walk(delta, 0.25)
	_face_point(rim(), delta, 14.0)
	if shot_released_this_attempt:
		if is_on_floor() and state_time - _released_at > 0.25:
			_enter(State.LOCOMOTION)
		return

	if _release_delay >= 0.0:
		_release_delay = maxf(0.0, _release_delay - delta)
		if _release_delay <= 0.0:
			_queued_release = "shot"
		return
	shot_charge = minf(shot_charge + delta / CHARGE_TIME, OVERCHARGE)
	if state_time > 0.16 and is_on_floor() and not _took_off and not free_throw_attempt:
		_took_off = true
		velocity.y = sqrt(2.0 * GRAVITY * jump_height() * 0.55)
	var auto_release := shot_charge >= OVERCHARGE
	if free_throw_attempt and not is_user_controlled:
		intent.shoot_held = shot_charge < 0.65
	if intent.shoot_released or (not intent.shoot_held and state_time > 0.1) or auto_release:
		_release_delay = RELEASE_EXTENSION
		_forced_release = auto_release
		last_release_charge = shot_charge


func _release_shot(forced: bool) -> void:
	shot_released_this_attempt = true
	_released_at = state_time
	if ball == null or ball.holder != self:
		return
	var to_rim := distance_to_rim()
	var behind_arc := CourtMetrics.is_behind_three(global_position, basket)
	var quality := _release_quality(forced)
	var contest := ShotSolver.contest_level(global_position, rig.shoulder_height, opponents)
	var movement := clampf(velocity.length() / maxf(_max_speed, 0.01), 0.0, 1.0)
	var accuracy := ShotSolver.accuracy(data, to_rim, behind_arc, quality, contest,
		movement, 1.0 - stamina, match_difficulty)

	var from := ball_anchor.global_position
	var target := ShotSolver.aim_point(rim(), from, accuracy, _rng)
	var arc_bias := clampf(1.0 - to_rim / 9.0, 0.15, 0.95)
	var time := ShotSolver.flight_time(from.distance_to(target), arc_bias)
	var launch := ShotSolver.launch_velocity(from, target, time)

	ball.shot_by = get_instance_id()
	ball.shot_points = 3 if behind_arc else 2
	ball.shot_from = global_position
	ball.launch(from, launch, -_facing.cross(Vector3.UP) * 12.0, Ball.State.SHOT)
	has_ball = false
	pickup_cooldown = 0.35
	last_shot_kind = "FREE THROW" if free_throw_attempt else "JUMPER"
	shot_released.emit(self, ball.shot_points, accuracy)


func _release_quality(forced: bool) -> float:
	var style := int(Settings.get_value("shot_style"))
	if style == Settings.ShotStyle.AUTO or not is_user_controlled:
		# AI and assisted shooting lean on the rating instead of the meter.
		return 0.34 + float(data["mid"] if not is_user_controlled else 70) / 99.0 * 0.34
	if forced:
		return MIN_RELEASE_QUALITY
	var centre := (IDEAL_RELEASE.x + IDEAL_RELEASE.y) * 0.5
	var half_window := (IDEAL_RELEASE.y - IDEAL_RELEASE.x) * 0.5
	var error := absf(shot_charge - centre)
	if error <= half_window:
		return 1.0 - error / maxf(half_window, 0.001) * 0.15
	return clampf(0.85 - (error - half_window) * 1.6, MIN_RELEASE_QUALITY, 0.85)


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
		_queued_release = "pass"
	if state_time > 0.32:
		_enter(State.LOCOMOTION)


func _send_pass(target: PlayerPawn) -> void:
	if ball == null or ball.holder != self:
		return
	var from := ball_anchor.global_position
	# Lead the receiver so a moving target does not have to stop.
	var lead := target.velocity * 0.22
	var to := target.global_position + lead + Vector3.UP * (target.rig.shoulder_height * 0.8)
	var distance := from.distance_to(to)
	var zip := clampf(0.16 + distance * 0.026, 0.18, 0.55)
	var accuracy := clampf(float(data["pas"]) / 99.0, 0.2, 1.0)
	var wobble := (1.0 - accuracy) * 0.35
	to += Vector3(_rng.randfn(0.0, wobble), _rng.randfn(0.0, wobble * 0.4),
		_rng.randfn(0.0, wobble))

	# Whether the pass is picked off is decided here, from who is actually
	# sitting in the lane. Letting any nearby defender grab it in flight turns
	# every pass into a coin toss.
	var thief := _lane_thief(from, to)
	ball.pass_target = thief.get_instance_id() if thief != null \
		else target.get_instance_id()
	ball.last_touched_by = get_instance_id()
	ball.launch(from, ShotSolver.launch_velocity(from, to, zip), Vector3.ZERO,
		Ball.State.PASS)
	has_ball = false
	pickup_cooldown = 0.2
	target.pickup_cooldown = 0.0
	ball_passed.emit(self, target)


# A defender close to the line of the pass gets one roll to jump it, weighted
# by their steal rating against the passer's vision.
func _lane_thief(from: Vector3, to: Vector3) -> PlayerPawn:
	var lane := to - from
	var length := lane.length()
	if length < 0.5:
		return null
	var direction := lane / length
	for defender in opponents:
		var offset := defender.global_position + Vector3.UP * 1.0 - from
		var along := offset.dot(direction)
		if along < 0.6 or along > length - 0.35:
			continue
		if (offset - direction * along).length() > INTERCEPT_REACH:
			continue
		var edge := (float(defender.data["stl"]) - float(data["pas"])) / 260.0
		if _rng.randf() < clampf(INTERCEPT_BASE + edge, 0.02, 0.30):
			return defender
	return null


func _tick_dunk(delta: float) -> void:
	var target := rim()
	if state_time < 0.12:
		_walk(delta, 0.9)
	_face_point(target, delta, 18.0)
	if state_time >= 0.10 and is_on_floor() and not _took_off:
		_took_off = true
		var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		# A hard approach goes higher, so a fast break finishes above the rim
		# rather than scraping it.
		var rise := sqrt(2.0 * GRAVITY * jump_height() * (1.0 + dunk_power * 0.22))
		velocity = flat.normalized() * minf(flat.length() * 1.9, _max_speed * 1.15)
		velocity.y = rise
	var hand_height := global_position.y + standing_reach()
	# Put it down at the top of the jump rather than on the way up, which is
	# what made the dunk read as letting go early.
	if has_ball and hand_height > CourtMetrics.RIM_HEIGHT + 0.02 and velocity.y < 0.35:
		_queued_release = "dunk"
	if _took_off and is_on_floor() and state_time > 0.4 and has_ball:
		_enter(State.LOCOMOTION)
	if is_on_floor() and state_time > DUNK_HANG and not has_ball:
		_enter(State.LOCOMOTION)


func _finish_dunk() -> void:
	if ball == null or ball.holder != self:
		return
	var target := rim()
	var from := ball_anchor.global_position
	var flat := Vector2(from.x - target.x, from.z - target.z).length()
	if flat > 0.65 or from.y < target.y + 0.04:
		_release_layup()
		return
	ball.shot_by = get_instance_id()
	ball.shot_points = 2
	ball.shot_from = global_position
	ball.launch(from, ShotSolver.launch_velocity(from, target - Vector3.UP * 0.16, 0.14),
		Vector3(6.0, 0.0, 0.0), Ball.State.SHOT)
	has_ball = false
	pickup_cooldown = 0.5
	shot_released_this_attempt = true
	last_shot_kind = "DUNK"
	dunked.emit(self)
	shot_released.emit(self, 2, 0.99)


func _tick_layup(delta: float) -> void:
	var target := rim()
	if state_time < 0.14:
		_walk(delta, 0.85)
	_face_point(target, delta, 16.0)
	if state_time >= 0.12 and is_on_floor() and not _took_off:
		_took_off = true
		var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		velocity = flat.normalized() * minf(flat.length() * 1.2, _max_speed * 0.8)
		velocity.y = sqrt(2.0 * GRAVITY * jump_height() * 0.82)
	if has_ball and velocity.y < 0.6 and not is_on_floor():
		_queued_release = "layup"
	if is_on_floor() and state_time > 0.4:
		_enter(State.LOCOMOTION)


func _release_layup() -> void:
	if ball == null or ball.holder != self:
		return
	var contest := ShotSolver.contest_level(global_position, rig.shoulder_height, opponents)
	var accuracy := ShotSolver.accuracy(data, distance_to_rim(), false, 0.82,
		contest, 0.35, 1.0 - stamina, match_difficulty)
	var from := ball_anchor.global_position
	# Aim off the glass rather than straight at the ring.
	var board_point := rim() + Vector3.UP * 0.28
	var target := ShotSolver.aim_point(board_point, from, accuracy, _rng)
	var time := ShotSolver.flight_time(from.distance_to(target), 0.85)
	ball.shot_by = get_instance_id()
	ball.shot_points = 2
	ball.shot_from = global_position
	ball.launch(from, ShotSolver.launch_velocity(from, target, time),
		Vector3(0.0, 0.0, 6.0), Ball.State.SHOT)
	has_ball = false
	shot_released_this_attempt = true
	pickup_cooldown = 0.4
	last_shot_kind = "LAYUP"
	shot_released.emit(self, 2, accuracy)


## Straight up off both feet, for a contested rebound or the opening tip.
func contest_jump() -> void:
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
	var wish := Vector3(intent.move.x, 0.0, intent.move.y) if movement_enabled else Vector3.ZERO
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


func _update_ball_anchor(_delta: float) -> void:
	if not has_ball or ball == null:
		return
	var grip := rig.grip_position(ball_hand)
	if has_ball_gathered() or free_throw_attempt or not is_on_floor():
		ball_anchor.global_position = grip + Vector3.UP * CourtMetrics.BALL_RADIUS
	else:
		var bounce := absf(sin(_dribble_phase))
		var floor_y := global_position.y + CourtMetrics.BALL_RADIUS + 0.01
		ball_anchor.global_position = Vector3(grip.x,
			lerpf(floor_y, maxf(floor_y, grip.y), bounce), grip.z)
	# The ball processes before the pawns. Updating here removes a frame of lag
	# between the current pose and the held ball's transform.
	if ball.holder == self:
		ball.global_position = ball_anchor.global_position


func take_ball(new_ball: Ball) -> void:
	if new_ball.holder is PlayerPawn and new_ball.holder != self:
		(new_ball.holder as PlayerPawn).lose_ball()
	cancel_action()
	ball = new_ball
	has_ball = true
	ball_hand = 1.0 if _rng.randf() < 0.72 else -1.0
	_update_ball_anchor(0.0)
	ball.hold(self, ball_anchor, get_instance_id())
	Sound.play("catch", -12.0, randf_range(0.9, 1.15))
	ball_gathered.emit(self)


func lose_ball() -> void:
	if ball != null and ball.holder == self:
		ball.go_loose()
	has_ball = false
	pickup_cooldown = 0.25


func cancel_action() -> void:
	if state != State.LOCOMOTION:
		_enter(State.LOCOMOTION)
	_pending_pass = null
	shot_charge = 0.0
	shot_released_this_attempt = false
	_took_off = false
	_release_delay = -1.0
	_queued_release = ""
	intent.reset()


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
	animator.dribble_driven = true
	animator.dribble_phase = _dribble_phase
	animator.tick(delta)


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
			if _release_delay >= 0.0:
				return lerpf(0.42, 0.62, 1.0 - _release_delay / RELEASE_EXTENSION)
			return clampf(shot_charge / IDEAL_RELEASE.x, 0.0, 1.0) * 0.42
		State.PASS:
			return clampf(state_time / 0.32, 0.0, 1.0)
		State.DUNK:
			return clampf(state_time / 0.82, 0.0, 1.0)
		State.LAYUP:
			return clampf(state_time / 0.55, 0.0, 1.0)
		State.JUMP:
			return clampf(state_time / 0.35, 0.0, 1.0)
		State.STEAL:
			return clampf(state_time / STEAL_TIME, 0.0, 1.0)
	return 0.0


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
