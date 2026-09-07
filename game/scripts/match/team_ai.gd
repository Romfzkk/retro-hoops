class_name TeamAI
extends RefCounted

# Fills in PlayerIntent for every pawn on one team that no human is driving.
# Offence is spacing plus a decision on the ball; defence is man-to-man with
# help on drives.

const DECISION_INTERVAL := 0.22
const OPEN_CONTEST := 0.34
const DRIVE_LANE_WIDTH := 1.55
const HELP_DISTANCE := 4.2
const CUT_DURATION := 1.6
## Seconds of shot clock to burn before the offence starts hunting a shot.
const PATIENCE := 4.0
const SHOT_APPETITE := 0.40
const PASS_APPETITE := 0.30
## Rolled once per decision, not once per frame.
const REACH_IN_CHANCE := 0.05

# Half-court spots as (distance from baseline, offset from centre), indexed by
# lineup slot. The lineup is built in position order, so slot 0 is the point.
const SPOTS_FIVE: Array[Vector2] = [
	Vector2(9.6, 0.0),    # point
	Vector2(7.8, 6.1),    # right wing
	Vector2(7.8, -6.1),   # left wing
	Vector2(2.6, 3.6),    # short corner
	Vector2(3.4, -2.2),   # post
]

const SPOTS_THREE: Array[Vector2] = [
	Vector2(9.2, 0.0),
	Vector2(7.4, 5.8),
	Vector2(3.2, -3.0),
]

var team_index := 0
var basket := 0
var pawns: Array[PlayerPawn] = []
var difficulty := 1

var _decision_time := 0.0
var _assignments: Dictionary = {}
var _cuts: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(index: int, attacking_basket: int, seed_value: int) -> void:
	team_index = index
	basket = attacking_basket
	_rng.seed = seed_value


func tick(delta: float, ctx: MatchContext) -> void:
	_decision_time -= delta
	var refresh := _decision_time <= 0.0
	if refresh:
		_decision_time = DECISION_INTERVAL
		_assign_matchups(ctx)

	for pawn in pawns:
		if pawn.is_user_controlled:
			continue
		pawn.intent.reset()
		if not ctx.is_live():
			_idle(pawn, ctx)
			continue
		if ctx.phase == MatchContext.Phase.SHOT_IN_FLIGHT \
				or ctx.phase == MatchContext.Phase.LOOSE_BALL:
			_chase_ball(pawn, ctx)
		elif ctx.possession == team_index:
			if pawn.has_ball:
				_drive_decision(pawn, ctx, refresh)
			else:
				_space(pawn, ctx, delta)
		else:
			_defend(pawn, ctx, refresh)


func _idle(pawn: PlayerPawn, ctx: MatchContext) -> void:
	var home := _spot_for(pawn, ctx)
	_steer(pawn, home, 0.4)


func _chase_ball(pawn: PlayerPawn, ctx: MatchContext) -> void:
	var landing := ctx.predicted_rebound
	var mine := ctx.nearest(landing, pawns)
	if mine == pawn:
		_steer(pawn, landing, 1.0, true)
		# Go up for it once you are underneath.
		if pawn.global_position.distance_to(landing) < 1.5 \
				and ctx.ball.global_position.y > 2.2:
			pawn.intent.shoot_pressed = true
	else:
		# Everyone else fills the floor rather than crowding the rebound.
		_steer(pawn, landing + _spread_offset(pawn) * 2.6, 0.55)


func _drive_decision(pawn: PlayerPawn, ctx: MatchContext, refresh: bool) -> void:
	var rim := CourtMetrics.rim_position(basket)
	var distance := pawn.distance_to_rim()
	var contest := ShotSolver.contest_level(pawn.global_position,
		pawn.rig.shoulder_height, ctx.opponents_of(team_index))
	var range_limit := ShotSolver.shooting_range(pawn.data)
	var desperate := ctx.shot_clock < 4.0
	var lane_is_open := _lane_is_open(pawn, ctx)

	if refresh:
		var lane_open := lane_is_open
		var shoot_score := 0.0
		if contest < OPEN_CONTEST:
			shoot_score += 0.45
		if distance < range_limit:
			shoot_score += 0.35
		else:
			shoot_score -= 0.45
		# Only a genuinely open lane is worth attacking; otherwise take the
		# jumper rather than charging into help every single possession.
		if distance < 2.8 and lane_open:
			shoot_score += 0.20
		elif distance < 2.8:
			shoot_score -= 0.30
		# An open look from range is worth as much as a contested drive.
		if contest < OPEN_CONTEST 				and CourtMetrics.is_behind_three(pawn.global_position, basket):
			shoot_score += 0.28
		if desperate:
			shoot_score += 0.9
		shoot_score += float(difficulty) * 0.04
		# Hold the ball for a beat before hunting a shot. Without this the AI
		# fires on the catch and a 20 minute game runs 350 possessions.
		var settled := ctx.shot_clock < MatchClock.SHOT_CLOCK - PATIENCE
		var wide_open := distance < 2.4 and contest < 0.2 and lane_open
		if (settled or wide_open) and _rng.randf() < shoot_score * SHOT_APPETITE:
			pawn.intent.shoot_pressed = true
			pawn.intent.shoot_held = true
			# Finishing at the rim needs the drive flag, otherwise the pawn
			# settles for a jumper from under the basket.
			var at_rim := distance < PlayerPawn.DUNK_RANGE and lane_open
			pawn.intent.sprint = at_rim
			pawn.intent.special_pressed = at_rim and pawn.can_dunk() 				and contest < OPEN_CONTEST
			if at_rim:
				_steer(pawn, rim, 1.0, true)
			return

		var receiver := _best_pass(pawn, ctx)
		if receiver != null and _rng.randf() < PASS_APPETITE:
			pawn.intent.pass_pressed = true
			pawn.intent.pass_target = receiver.lineup_slot
			var offset := receiver.global_position - pawn.global_position
			pawn.intent.aim = Vector2(offset.x, offset.z).normalized()
			return

	if lane_is_open or distance > range_limit + 2.0:
		_steer(pawn, rim, 1.0, distance > 2.0)
	else:
		# Probe sideways to make the defender commit.
		var across := (rim - pawn.global_position).cross(Vector3.UP).normalized()
		var probe := pawn.global_position + across * signf(_rng.randfn(0.0, 1.0)) * 2.4
		_steer(pawn, probe, 0.7)


func _space(pawn: PlayerPawn, ctx: MatchContext, delta: float) -> void:
	var key := pawn.get_instance_id()
	var cut: Dictionary = _cuts.get(key, {"wait": _rng.randf_range(3.0, 8.0), "for": 0.0})
	_cuts[key] = cut

	if float(cut["for"]) > 0.0:
		cut["for"] = float(cut["for"]) - delta
		var rim := CourtMetrics.rim_position(basket)
		# A cut is time-boxed. Ending it only on arrival means a cutter whose
		# lane is blocked keeps driving forever, and eventually all five end up
		# stacked under the basket.
		if float(cut["for"]) <= 0.0 or pawn.global_position.distance_to(rim) < 1.8:
			cut["for"] = 0.0
			cut["wait"] = _rng.randf_range(4.5, 9.5)
		else:
			_steer(pawn, rim, 0.95, true)
			return

	cut["wait"] = float(cut["wait"]) - delta
	if float(cut["wait"]) <= 0.0:
		cut["for"] = CUT_DURATION
		return
	_steer(pawn, _spot_for(pawn, ctx), 0.62)


func _defend(pawn: PlayerPawn, ctx: MatchContext, refresh: bool) -> void:
	var man: PlayerPawn = _assignments.get(pawn.get_instance_id())
	if man == null:
		man = ctx.nearest(pawn.global_position, ctx.opponents_of(team_index))
	if man == null:
		return
	var rim := CourtMetrics.rim_position(1 - basket)
	var to_rim := (rim - man.global_position)
	to_rim.y = 0.0
	var gap := 0.95 if man.has_ball else 1.7
	var station := man.global_position + to_rim.normalized() * gap

	if not man.has_ball and _should_help(pawn, ctx):
		var carrier := ctx.carrier
		if carrier != null:
			station = carrier.global_position \
				+ (rim - carrier.global_position).normalized() * 1.3

	_steer(pawn, station, 1.0, pawn.global_position.distance_to(station) > 3.0)

	if man.has_ball:
		var separation := pawn.global_position.distance_to(man.global_position)
		if man.state == PlayerPawn.State.SHOOT and separation < 2.1:
			pawn.intent.shoot_pressed = true
		elif refresh and separation < 1.4 				and _rng.randf() < REACH_IN_CHANCE + float(difficulty) * 0.01:
			pawn.intent.pass_pressed = true


func _should_help(pawn: PlayerPawn, ctx: MatchContext) -> bool:
	var carrier := ctx.carrier
	if carrier == null:
		return false
	if not CourtMetrics.in_paint(carrier.global_position, 1 - basket):
		return false
	return pawn.global_position.distance_to(carrier.global_position) < HELP_DISTANCE


func _assign_matchups(ctx: MatchContext) -> void:
	_assignments.clear()
	var available: Array = ctx.opponents_of(team_index).duplicate()
	for pawn in pawns:
		var best: PlayerPawn = null
		var best_score := INF
		for candidate: PlayerPawn in available:
			# Match on position first, then on who is actually nearby.
			var score: float = absf(float(candidate.data["pos"]) - float(pawn.data["pos"])) * 3.0
			score += pawn.global_position.distance_to(candidate.global_position) * 0.35
			if score < best_score:
				best_score = score
				best = candidate
		if best != null:
			_assignments[pawn.get_instance_id()] = best
			available.erase(best)


func _best_pass(pawn: PlayerPawn, ctx: MatchContext) -> PlayerPawn:
	var rim := CourtMetrics.rim_position(basket)
	var best: PlayerPawn = null
	var best_score := 0.55
	for mate in pawns:
		if mate == pawn:
			continue
		var contest := ShotSolver.contest_level(mate.global_position,
			mate.rig.shoulder_height, ctx.opponents_of(team_index))
		var distance := mate.global_position.distance_to(rim)
		var score := (1.0 - contest) * 0.8
		if distance < ShotSolver.shooting_range(mate.data):
			score += 0.3
		if distance < 3.0:
			score += 0.25
		if pawn._passing_lane_blocked(mate):
			score -= 0.9
		if score > best_score:
			best_score = score
			best = mate
	return best


func _lane_is_open(pawn: PlayerPawn, ctx: MatchContext) -> bool:
	var rim := CourtMetrics.rim_position(basket)
	var lane := rim - pawn.global_position
	lane.y = 0.0
	var length := lane.length()
	if length < 0.5:
		return true
	var direction := lane / length
	for defender: PlayerPawn in ctx.opponents_of(team_index):
		var offset := defender.global_position - pawn.global_position
		offset.y = 0.0
		var along := offset.dot(direction)
		if along < 0.2 or along > length:
			continue
		if (offset - direction * along).length() < DRIVE_LANE_WIDTH:
			return false
	return true


func _spot_for(pawn: PlayerPawn, ctx: MatchContext) -> Vector3:
	var table := SPOTS_THREE if pawns.size() <= 3 else SPOTS_FIVE
	var spot: Vector2 = table[clampi(pawn.lineup_slot, 0, table.size() - 1)]
	var sign_x := CourtMetrics.attack_sign(basket)
	var offset := spot.y
	# Drift off the ball side so the handler always has a lane.
	if ctx.carrier != null and absf(offset) > 0.5 			and signf(ctx.carrier.global_position.z) == signf(offset):
		offset *= 1.18
	return Vector3(sign_x * (CourtMetrics.HALF_LENGTH - spot.x), 0.0,
		clampf(offset, -CourtMetrics.HALF_WIDTH + 0.8, CourtMetrics.HALF_WIDTH - 0.8))


func _spread_offset(pawn: PlayerPawn) -> Vector3:
	var angle := float(pawn.lineup_slot) * TAU / 5.0
	return Vector3(cos(angle), 0.0, sin(angle))


func _steer(pawn: PlayerPawn, to: Vector3, urgency: float, sprint: bool = false) -> void:
	var offset := to - pawn.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance < 0.35:
		pawn.intent.move = Vector2.ZERO
		return
	var direction := offset / distance
	pawn.intent.move = Vector2(direction.x, direction.z) * clampf(urgency, 0.0, 1.0)
	pawn.intent.aim = Vector2(direction.x, direction.z)
	pawn.intent.sprint = sprint and distance > 2.5
