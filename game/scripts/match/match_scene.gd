extends Node3D

# Owns a single game: builds the world, spawns both squads, runs the clock and
# the rules, and reports the result back to whoever launched it.

signal finished(result: Dictionary)

const INBOUND_PAUSE := 1.1
const TIPOFF_PAUSE := 1.4
const QUARTER_BREAK := 2.4
const CATCH_RADIUS := 0.95
const OUT_OF_BOUNDS_MARGIN := 0.25

var setup: MatchSetup
var ctx := MatchContext.new()
var clock: MatchClock
var box := BoxScore.new()

var ball: Ball
var hoops: Array[Hoop] = []
var camera: BroadcastCamera
var squads: Array[Array] = [[], []]
var ais: Array[TeamAI] = []
var humans: Array[HumanController] = []
var hud: MatchHud
var touch: TouchControls
var markers: Array[PlayerMarker] = []

var events := {"out_of_bounds": 0, "shot_clock": 0, "possessions": 0,
	"dunks": 0, "shot_quality_sum": 0.0, "shot_distance_sum": 0.0, "shots": 0,
	"passes": 0, "catches": 0, "loose_pickups": 0, "steals_from_pass": 0}

var _balance_run := false
var _verbose := false

var _pending_shot := {}
var _phase_timer := 0.0
var _resume_phase: MatchContext.Phase = MatchContext.Phase.LIVE
var _elapsed := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_balance_run = not FrameCapture.argument(SimProbe.SIM_ARG).is_empty()
	_verbose = FrameCapture.has_flag("--verbose")
	setup = Game.setup
	if setup.home.is_empty():
		_fill_exhibition_setup()
	_rng.randomize()

	clock = MatchClock.new(setup.quarters, float(setup.quarter_seconds))
	clock.quarter_expired.connect(_on_quarter_expired)
	clock.shot_clock_expired.connect(_on_shot_clock_expired)

	var arena: Dictionary = Teams.ARENAS[clampi(setup.arena, 0, Teams.ARENAS.size() - 1)]
	if _balance_run:
		ArenaBuilder.build_collision_only(self)
	else:
		ArenaBuilder.build(self, setup.home, setup.away, arena,
			int(setup.home["id"]) * 31 + 7)
	hoops.append(Hoop.create(0, Color(setup.home["primary"])))
	hoops.append(Hoop.create(1, Color(setup.away["primary"])))
	for hoop in hoops:
		add_child(hoop)

	if not _balance_run and not bool(arena.get("outdoor", false)):
		Jumbotron.create(self, ArenaBuilder.roof_height() - 4.5, self)

	ball = Ball.create()
	add_child(ball)

	_spawn_squads()
	_setup_camera()
	_setup_controllers()
	_setup_hud()

	ctx.ball = ball
	ctx.teams = squads
	ctx.difficulty = setup.difficulty
	_begin_tipoff()
	FrameCapture.attach(self)
	SimProbe.attach(self)


func _fill_exhibition_setup() -> void:
	var lg := Game.exhibition_league()
	setup.home = lg["teams"][0]
	setup.away = lg["teams"][16]


func _spawn_squads() -> void:
	var size := setup.lineup_size()
	for team_index in 2:
		var team: Dictionary = setup.home if team_index == 0 else setup.away
		var attacking := team_index
		var roster := _starting_lineup(team["roster"], size)
		for slot in size:
			var pawn := PlayerPawn.create(roster[slot], team, team_index, attacking,
				self, not _balance_run)
			pawn.lineup_slot = slot
			pawn.ball = ball
			add_child(pawn)
			squads[team_index].append(pawn)
			box.register(pawn.get_instance_id(), team_index, roster[slot])
			pawn.shot_released.connect(_on_shot_released)
			pawn.ball_passed.connect(_on_ball_passed)
			pawn.dunked.connect(_on_dunk)
			pawn.steal_attempted.connect(_on_steal_attempt)

	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			pawn.teammates.assign(squads[team_index])
			pawn.opponents.assign(squads[1 - team_index])

	for team_index in 2:
		var ai := TeamAI.new(team_index, team_index, int(_rng.randi()))
		ai.pawns.assign(squads[team_index])
		ai.difficulty = setup.difficulty
		ais.append(ai)


# Best available body at each spot, so a team never fields three point guards
# just because they happen to be the highest rated players on the roster.
func _starting_lineup(roster: Array, size: int) -> Array:
	var wanted: Array = [League.Pos.PG, League.Pos.SG, League.Pos.SF,
		League.Pos.PF, League.Pos.C]
	if size == 3:
		wanted = [League.Pos.PG, League.Pos.SF, League.Pos.C]
	var pool: Array = roster.duplicate()
	var lineup: Array = []
	for position in wanted:
		var best: Dictionary = {}
		var best_score := -INF
		for player: Dictionary in pool:
			# Rating first, minus a penalty for playing out of position.
			var score := float(player["ovr"]) 				- absf(float(player["pos"]) - float(position)) * 6.0
			if score > best_score:
				best_score = score
				best = player
		if best.is_empty():
			break
		lineup.append(best)
		pool.erase(best)
	return lineup


func _setup_camera() -> void:
	camera = BroadcastCamera.new()
	camera.mode = int(Settings.get_value("camera_mode"))
	add_child(camera)


func _setup_controllers() -> void:
	if _balance_run:
		# A headless balance run has nobody at the keyboard, so let the AI
		# drive both benches.
		setup.home_controller = MatchSetup.Controller.AI
		setup.away_controller = MatchSetup.Controller.AI
	if setup.home_controller == MatchSetup.Controller.LOCAL_1:
		humans.append(HumanController.new(0, HumanController.Device.ACTIONS))
	elif setup.home_controller == MatchSetup.Controller.LOCAL_2:
		humans.append(HumanController.new(0, HumanController.Device.PAD, 1))
	if setup.away_controller == MatchSetup.Controller.LOCAL_1:
		humans.append(HumanController.new(1, HumanController.Device.ACTIONS))
	elif setup.away_controller == MatchSetup.Controller.LOCAL_2:
		humans.append(HumanController.new(1, HumanController.Device.PAD, 1))
	for controller in humans:
		controller.squad.assign(squads[controller.team_index])
		if not _balance_run:
			var team: Dictionary = setup.home if controller.team_index == 0 else setup.away
			markers.append(PlayerMarker.create(self, Color(team["primary"])))


func _setup_hud() -> void:
	touch = TouchControls.new()
	hud = MatchHud.new()
	hud.bind(self)
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	layer.add_child(touch)
	add_child(layer)
	if not humans.is_empty():
		humans[0].attach_touch(touch)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_update_context()

	if _phase_timer > 0.0:
		_phase_timer -= delta
		if _phase_timer <= 0.0:
			_resume_play()

	for controller in humans:
		controller.tick(delta, ctx)
	for ai in ais:
		ai.tick(delta, ctx)

	if ctx.is_live():
		# Score before catches: a made basket has to register before anyone is
		# credited with grabbing the ball out of the net.
		_check_scoring()
		_check_catches()
		_check_out_of_bounds()
		clock.tick(delta)

	if touch != null:
		touch.clear_edges()


func _update_context() -> void:
	ctx.carrier = null
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			if pawn.has_ball:
				ctx.carrier = pawn
				ctx.possession = team_index
	ctx.shot_clock = clock.shot_clock
	ctx.quarter_remaining = clock.remaining
	ctx.predicted_rebound = MatchContext.landing_point(ball, 1.2)

	if ctx.phase == MatchContext.Phase.LIVE and ctx.carrier == null:
		ctx.phase = MatchContext.Phase.SHOT_IN_FLIGHT if ball.state == Ball.State.SHOT \
			else MatchContext.Phase.LOOSE_BALL
	elif ctx.carrier != null and (ctx.phase == MatchContext.Phase.SHOT_IN_FLIGHT
			or ctx.phase == MatchContext.Phase.LOOSE_BALL):
		ctx.phase = MatchContext.Phase.LIVE

	for i in markers.size():
		markers[i].target = humans[i].active if i < humans.size() else null

	camera.focus_point = ball.global_position
	camera.attack_basket = ctx.possession
	if not humans.is_empty() and humans[0].active != null:
		camera.target = humans[0].active


func _check_catches() -> void:
	if ball.state == Ball.State.HELD or ball.state == Ball.State.DEAD:
		return
	if ball.state == Ball.State.SHOT and not ball.rebound_ready:
		return
	if ball.state == Ball.State.PASS:
		# The receiver was decided at release, including any interception.
		_offer_pass_to_target()
		return
	var best: PlayerPawn = null
	var best_distance := CATCH_RADIUS
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			if not pawn.can_pick_up():
				continue
			var offset := ball.global_position - pawn.global_position
			var flat := Vector2(offset.x, offset.z).length()
			var reachable := offset.y < pawn.standing_reach() * (
				1.0 if pawn.is_on_floor() else 1.25)
			if not reachable or offset.y < -0.4:
				continue
			# A pass intended for you is easier to bring in than a loose ball.
			var bonus := 0.45 if ball.pass_target == pawn.get_instance_id() else 0.0
			if flat - bonus < best_distance:
				best_distance = flat - bonus
				best = pawn
	if best == null:
		return
	_award_possession(best)


func _offer_pass_to_target() -> void:
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			if pawn.get_instance_id() != ball.pass_target or not pawn.can_pick_up():
				continue
			var offset := ball.global_position - pawn.global_position
			if Vector2(offset.x, offset.z).length() > CATCH_RADIUS * 1.4:
				return
			if offset.y > pawn.standing_reach() or offset.y < -0.4:
				return
			_award_possession(pawn)
			return


func _award_possession(pawn: PlayerPawn) -> void:
	var previous_team := ctx.possession
	var was_shot := ball.state == Ball.State.SHOT
	if was_shot and not _pending_shot.is_empty():
		_resolve_miss()
		if pawn.team_index == previous_team:
			clock.offensive_rebound_reset()
			box.add(pawn.get_instance_id(), "reb")
		else:
			clock.reset_shot_clock()
			box.add(pawn.get_instance_id(), "reb")
	elif ball.state == Ball.State.PASS and ball.pass_target != pawn.get_instance_id():
		# Intercepted.
		events["steals_from_pass"] = int(events["steals_from_pass"]) + 1
		box.add(pawn.get_instance_id(), "stl")
		if ctx.carrier != null:
			box.add(ctx.carrier.get_instance_id(), "to")
		clock.reset_shot_clock()

	events["catches"] = int(events["catches"]) + 1
	if ball.state == Ball.State.LOOSE:
		events["loose_pickups"] = int(events["loose_pickups"]) + 1
	if pawn.team_index != previous_team:
		events["possessions"] = int(events["possessions"]) + 1
	pawn.take_ball(ball)
	ctx.possession = pawn.team_index
	ctx.phase = MatchContext.Phase.LIVE
	clock.running = true


func _check_scoring() -> void:
	for hoop in hoops:
		var points := hoop.check_ball(ball)
		if points <= 0:
			continue
		_score(hoop.basket, points)
		return


func _score(basket: int, points: int) -> void:
	var scoring_team := basket
	var shooter_id := -1
	if not _pending_shot.is_empty():
		shooter_id = int(_pending_shot["shooter"])
		points = int(_pending_shot["points"])
		scoring_team = int(_pending_shot["team"])
		_pending_shot.clear()

	if shooter_id >= 0:
		box.record_basket(shooter_id, points, clock.quarter)
		box.credit_assist(shooter_id, _elapsed)
	else:
		box.team_points[scoring_team] += points

	if _verbose:
		print("  -> MADE %d" % points)
	camera.shake(0.6 if points == 3 else 0.35)
	hud.announce("%d PTS" % points, points == 3)
	_dead_ball(1 - scoring_team, INBOUND_PAUSE)


func _resolve_miss() -> void:
	if _pending_shot.is_empty():
		return
	if _verbose:
		print("  -> MISS  ball=(%.2f,%.2f,%.2f)" % [ball.global_position.x,
			ball.global_position.y, ball.global_position.z])
	box.record_miss(int(_pending_shot["shooter"]), int(_pending_shot["points"]))
	_pending_shot.clear()


func _check_out_of_bounds() -> void:
	var position := ball.global_position
	var outside := absf(position.x) > CourtMetrics.HALF_LENGTH + OUT_OF_BOUNDS_MARGIN \
		or absf(position.z) > CourtMetrics.HALF_WIDTH + OUT_OF_BOUNDS_MARGIN
	if not outside or ball.state == Ball.State.HELD:
		return
	# Only whistle it once the ball is actually down, so a shot from the corner
	# that drifts over the line mid-flight still counts.
	if position.y > 0.6 and ball.linear_velocity.y > -0.5:
		return
	_resolve_miss()
	var to_team := 1 - _last_touch_team()
	events["out_of_bounds"] = int(events["out_of_bounds"]) + 1
	hud.announce("OUT OF BOUNDS", false)
	_dead_ball(to_team, INBOUND_PAUSE * 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action("pause") or event.is_action("ui_cancel"):
		if ctx.phase == MatchContext.Phase.OVER:
			Game.goto("res://scenes/box_score.tscn")
		else:
			Game.goto("res://scenes/main_menu.tscn")


func _last_touch_team() -> int:
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			if pawn.get_instance_id() == ball.last_touched_by:
				return team_index
	return ctx.possession


func _on_shot_released(pawn: PlayerPawn, points: int, quality: float) -> void:
	_resolve_miss()
	_pending_shot = {"shooter": pawn.get_instance_id(), "points": points,
		"team": pawn.team_index, "quality": quality}
	events["shots"] = int(events["shots"]) + 1
	if _verbose:
		print("SHOT dist=%.2f acc=%.3f from=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f)" % [
			pawn.distance_to_rim(), quality,
			ball.global_position.x, ball.global_position.y, ball.global_position.z,
			ball.linear_velocity.x, ball.linear_velocity.y, ball.linear_velocity.z])
	events["shot_quality_sum"] = float(events["shot_quality_sum"]) + quality
	events["shot_distance_sum"] = float(events["shot_distance_sum"]) \
		+ pawn.distance_to_rim()
	ctx.phase = MatchContext.Phase.SHOT_IN_FLIGHT


func _on_ball_passed(passer: PlayerPawn, target: PlayerPawn) -> void:
	events["passes"] = int(events["passes"]) + 1
	box.note_pass(passer.get_instance_id(), target.get_instance_id(), _elapsed)


# A reach-in either takes the ball or leaves the defender out of the play.
# Handling it here rather than in the pawn keeps the box score in one place.
func _on_steal_attempt(thief: PlayerPawn, target: PlayerPawn) -> void:
	if target == null or not target.has_ball:
		return
	var edge := (float(thief.data["stl"]) - float(target.data["hnd"])) / 220.0
	if _rng.randf() >= clampf(0.12 + edge, 0.03, 0.42):
		thief.stumble()
		return
	target.lose_ball()
	ball.go_loose()
	# Knock it toward the thief rather than teleporting it into their hands.
	var away := (thief.global_position - target.global_position).normalized()
	ball.linear_velocity = away * 3.4 + Vector3.UP * 1.2
	box.add(thief.get_instance_id(), "stl")
	box.add(target.get_instance_id(), "to")
	clock.reset_shot_clock()
	hud.announce("STEAL", false)


func _on_dunk(pawn: PlayerPawn) -> void:
	events["dunks"] = int(events["dunks"]) + 1
	camera.shake(1.0)
	hud.announce("SLAM", true)


func _on_shot_clock_expired() -> void:
	events["shot_clock"] = int(events["shot_clock"]) + 1
	hud.announce("SHOT CLOCK", false)
	_resolve_miss()
	_dead_ball(1 - ctx.possession, INBOUND_PAUSE * 0.8)


func _on_quarter_expired(_quarter: int) -> void:
	_resolve_miss()
	if clock.quarter >= clock.quarters and box.team_points[0] != box.team_points[1]:
		_finish()
		return
	ctx.phase = MatchContext.Phase.DEAD
	_phase_timer = QUARTER_BREAK
	_resume_phase = MatchContext.Phase.INBOUND
	hud.announce("END OF %s" % clock.period_name(), false)


func _begin_tipoff() -> void:
	ctx.phase = MatchContext.Phase.TIPOFF
	_position_for_inbound(_rng.randi_range(0, 1))
	_phase_timer = TIPOFF_PAUSE
	_resume_phase = MatchContext.Phase.LIVE


func _dead_ball(to_team: int, pause: float) -> void:
	ctx.phase = MatchContext.Phase.DEAD
	clock.running = false
	ball.go_loose()
	ball.set_paused(true)
	_phase_timer = pause
	_resume_phase = MatchContext.Phase.LIVE
	_position_for_inbound(to_team)


func _resume_play() -> void:
	if _resume_phase == MatchContext.Phase.INBOUND:
		if not clock.advance_quarter():
			if box.team_points[0] == box.team_points[1]:
				clock.start_overtime()
			else:
				_finish()
				return
		hud.announce(clock.period_name(), false)
		_position_for_inbound(_rng.randi_range(0, 1))
		_phase_timer = INBOUND_PAUSE
		_resume_phase = MatchContext.Phase.LIVE
		return
	ball.set_paused(false)
	ctx.phase = MatchContext.Phase.LIVE
	clock.reset_shot_clock()
	clock.running = true


func _position_for_inbound(to_team: int) -> void:
	var sign_x := CourtMetrics.attack_sign(to_team)
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			pawn.velocity = Vector3.ZERO
			pawn.lose_ball()
			pawn.global_position = _formation_spot(pawn, team_index, to_team)
	var handler: PlayerPawn = squads[to_team][0]
	for pawn: PlayerPawn in squads[to_team]:
		if int(pawn.data["pos"]) == League.Pos.PG:
			handler = pawn
			break
	ball.set_paused(false)
	handler.take_ball(ball)
	ctx.possession = to_team
	clock.reset_shot_clock()


func _formation_spot(pawn: PlayerPawn, team_index: int, offence_team: int) -> Vector3:
	# Offence sets up in their attacking half, defence drops back in front.
	var attack_sign := CourtMetrics.attack_sign(offence_team)
	var slot := pawn.lineup_slot
	var spread := (float(slot) - float(squads[team_index].size() - 1) * 0.5) * 2.9
	var depth := 9.5 if team_index == offence_team else 6.2
	return Vector3(attack_sign * (CourtMetrics.HALF_LENGTH - depth - float(slot) * 0.4),
		0.0, clampf(spread, -CourtMetrics.HALF_WIDTH + 1.0, CourtMetrics.HALF_WIDTH - 1.0))


func _finish() -> void:
	ctx.phase = MatchContext.Phase.OVER
	clock.running = false
	var result := {
		"home": int(setup.home["id"]),
		"away": int(setup.away["id"]),
		"home_score": box.team_points[0],
		"away_score": box.team_points[1],
		"box": box,
		"season_day": setup.season_day,
	}
	Game.last_box_score = result
	finished.emit(result)
	hud.show_final(result)
	if not _balance_run:
		await get_tree().create_timer(4.0).timeout
		Game.goto("res://scenes/box_score.tscn")
