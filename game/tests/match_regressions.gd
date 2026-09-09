extends Node

const MatchSceneScript = preload("res://scripts/match/match_scene.gd")

# Suppresses the real _ready so the fixture can assemble a minimal match by
# hand. Extending the script by path string left the class unresolved, which
# loaded the scene without a script and hung the run instead of failing it.
class TestMatch extends MatchSceneScript:
	func _ready() -> void:
		set_physics_process(false)

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_ownership()
	_backcourt_rules()
	_crossover_outcome()
	_pass_expiry()
	_free_throw_scoring()
	_foul_rebound()
	_buzzer_shot()
	_hung_buzzer_shot()
	_finished_match()
	_interception()
	_rim_crossing()
	_shot_clock_flight()
	_rim_clock_once()
	_free_throw_inputs()
	_release_sequence()
	_ai_gather()
	_quick_play_result()
	_network_result()
	_airborne_boundary()
	await _held_boundary()
	print("Match regressions: %d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _fixture() -> TestMatch:
	var game := TestMatch.new()
	add_child(game)
	var teams: Array = League.new_league(1337)["teams"]
	game.setup = MatchSetup.new()
	game.setup.home = teams[0]
	game.setup.away = teams[16]
	game.clock = MatchClock.new(4, 60.0)
	game.clock.quarter_expired.connect(game._on_quarter_expired)
	game.clock.shot_clock_expired.connect(game._on_shot_clock_expired)
	game.camera = BroadcastCamera.new()
	game.add_child(game.camera)
	game.hud = MatchHud.new()
	game.add_child(game.hud)
	game.ball = Ball.create()
	game.add_child(game.ball)
	game.ball.set_physics_process(false)
	game.ctx.ball = game.ball
	for team_index in 2:
		var team: Dictionary = game.setup.home if team_index == 0 else game.setup.away
		var pawn := PlayerPawn.create(team["roster"][0], team, team_index, team_index, game, false)
		game.add_child(pawn)
		pawn.set_physics_process(false)
		pawn.ball = game.ball
		game.squads[team_index].append(pawn)
		game.box.register(pawn.get_instance_id(), team_index, pawn.data)
	game.ctx.teams = game.squads
	game.hud.bind(game)
	game.squads[1][0].position.x = 10.0
	game.ctx.phase = MatchContext.Phase.LIVE
	game._balance_run = true
	return game


func _release(game: TestMatch, team := 0, points := 2) -> PlayerPawn:
	var pawn: PlayerPawn = game.squads[team][0]
	pawn.take_ball(game.ball)
	game.ball.shot_by = pawn.get_instance_id()
	game.ball.shot_points = points
	game.ball.launch(CourtMetrics.rim_position(team) + Vector3.UP, Vector3.DOWN,
		Vector3.ZERO, Ball.State.SHOT)
	pawn.has_ball = false
	game._on_shot_released(pawn, points, 0.7)
	return pawn


func _ownership() -> void:
	var game := _fixture()
	var first: PlayerPawn = game.squads[0][0]
	var second: PlayerPawn = game.squads[1][0]
	first.take_ball(game.ball)
	second.take_ball(game.ball)
	game._update_context()
	_check("catch revokes previous ownership", not first.has_ball and second.has_ball)
	_check("holder and context agree", game.ball.holder == second and game.ctx.carrier == second)
	_check("held ball is at its anchor", game.ball.global_position.is_equal_approx(second.ball_anchor.global_position))
	game.free()


## Both backcourt rules, which are otherwise only exercised by an AI that is
## trying not to break them and so never proves they work.
func _backcourt_rules() -> void:
	var game := _fixture()
	var carrier: PlayerPawn = game.squads[0][0]
	var attack := CourtMetrics.attack_sign(0)
	carrier.take_ball(game.ball)
	game._update_context()

	# Held behind halfway past the count.
	carrier.global_position.x = -attack * 4.0
	game._frontcourt = false
	game._backcourt_time = MatchSceneScript.BACKCOURT_LIMIT - 0.05
	game._tick_backcourt(0.1)
	_check("holding the backcourt past the count is a turnover",
		game.ctx.possession == 1)

	# Over halfway, then back over it.
	var second := _fixture()
	var mover: PlayerPawn = second.squads[0][0]
	mover.take_ball(second.ball)
	second._update_context()
	mover.global_position.x = attack * 3.0
	second._tick_backcourt(0.1)
	_check("crossing halfway establishes the frontcourt", second._frontcourt)
	mover.global_position.x = -attack * 3.0
	second._tick_backcourt(0.1)
	_check("returning over halfway is a turnover", second.ctx.possession == 1)

	# A carrier who never established the frontcourt may sit behind halfway.
	var third := _fixture()
	var waiting: PlayerPawn = third.squads[0][0]
	waiting.take_ball(third.ball)
	third._update_context()
	waiting.global_position.x = -attack * 5.0
	third._tick_backcourt(0.5)
	_check("the count alone is not a violation", third.ctx.possession == 0)

	game.free()
	second.free()
	third.free()


## The crossover contest. `try_crossover` gates on being grounded, which a
## fixture with physics disabled can never be, so the outcome is exercised
## through `shake` and the gating is left to play.
func _crossover_outcome() -> void:
	var game := _fixture()
	var handler: PlayerPawn = game.squads[0][0]
	var mark: PlayerPawn = game.squads[1][0]
	handler.data["hnd"] = 99
	handler.data["acc"] = 99
	mark.data["def"] = 25
	mark.data["acc"] = 25
	handler.global_position = Vector3.ZERO

	var beaten := 0
	for attempt in 16:
		mark._enter(PlayerPawn.State.LOCOMOTION)
		mark.global_position = handler.facing() * 1.2
		if handler.shake(mark) > 0.0:
			beaten += 1
			_check("being beaten leaves the defender recovering",
				mark.state == PlayerPawn.State.STUMBLE)
			break
	_check("a handler beats a defender who cannot stay in front", beaten > 0)

	var even := _fixture()
	var solid: PlayerPawn = even.squads[0][0]
	var wall: PlayerPawn = even.squads[1][0]
	solid.data["hnd"] = 25
	solid.data["acc"] = 25
	wall.data["def"] = 99
	wall.data["acc"] = 99
	solid.global_position = Vector3.ZERO
	var survived := 0
	for attempt in 16:
		wall._enter(PlayerPawn.State.LOCOMOTION)
		wall.global_position = solid.facing() * 2.6
		if solid.shake(wall) <= 0.0:
			survived += 1
	_check("a defender who can stay in front mostly does", survived >= 12)

	# Severity has to mean something, or every shake is the same shake.
	var quick := _fixture()
	var star: PlayerPawn = quick.squads[0][0]
	var cone: PlayerPawn = quick.squads[1][0]
	star.data["hnd"] = 99
	star.data["acc"] = 99
	cone.data["def"] = 25
	cone.data["acc"] = 25
	star.global_position = Vector3.ZERO
	cone.global_position = star.facing() * 1.0
	cone.stumble(1.0)
	var long_recovery := cone._stumble_time
	cone.stumble(0.0)
	_check("a worse beating takes longer to recover from",
		long_recovery > cone._stumble_time)

	game.free()
	even.free()
	quick.free()


func _pass_expiry() -> void:
	var game := _fixture()
	game.ball.release(Vector3.RIGHT, Vector3.ZERO, Ball.State.PASS)
	game.ball.pass_target = game.squads[0][0].get_instance_id()
	game.ball._physics_process(Ball.PASS_LIFETIME + 0.01)
	_check("uncaught pass becomes loose", game.ball.state == Ball.State.LOOSE)
	_check("expired pass releases its target", game.ball.pass_target == -1)
	game.free()


func _free_throw_scoring() -> void:
	var game := _fixture()
	var shooter: PlayerPawn = game.squads[0][0]
	game._begin_free_throws(shooter, 2)
	_release(game)
	_check("free throw release keeps sequence phase", game.ctx.phase == MatchContext.Phase.FREE_THROW)
	game._score(0, 1)
	game._score(0, 1)
	_check("made free throw counts once", game.box.team_points[0] == 1)
	var row: Dictionary = game.box.players[shooter.get_instance_id()]
	_check("free throws have their own attempts", row["fta"] == 1 and row["ftm"] == 1 and row["fga"] == 0)
	game._tick_free_throws(2.0)
	_check("second free throw remains scheduled", game._free_throws.get("remaining") == 1)
	_check("line setup clears the old shooting action", shooter.state == PlayerPawn.State.LOCOMOTION)
	_release(game)
	game.ball.global_position.y = 1.0
	game.ball.rebound_ready = true
	game._tick_free_throws(2.0)
	_check("final miss is live", game.ctx.phase == MatchContext.Phase.LOOSE_BALL)
	_check("missed free throw recorded separately", row["fta"] == 2 and row["fga"] == 0)
	game.free()


func _foul_rebound() -> void:
	var game := _fixture()
	var shooter := _release(game)
	game._pending_foul = {"fouled": shooter, "attempts": 2}
	game.ball.rebound_ready = true
	game._award_possession(game.squads[1][0])
	_check("foul resolution cannot be overwritten by a catch", game.ctx.phase == MatchContext.Phase.FREE_THROW)
	_check("fouled shooter keeps the free throw", game.ball.holder == shooter)
	_check("no rebound on a dead shooting foul", game.box.players[game.squads[1][0].get_instance_id()]["reb"] == 0)
	game.free()


func _buzzer_shot() -> void:
	var game := _fixture()
	game.clock.quarter = 4
	game.clock.remaining = 0.01
	game.box.team_points = [0, 2]
	_release(game, 0, 3)
	game.clock.running = true
	game.clock.tick(0.02)
	_check("horn waits for released shot", game._period_pending and game.ctx.phase != MatchContext.Phase.OVER)
	game._score(0, 3)
	_check("buzzer basket decides final score", game.ctx.phase == MatchContext.Phase.OVER and game.box.team_points == [3, 2])
	_check("finished game stops actions", not game.squads[0][0].actions_enabled)
	game.free()


func _finished_match() -> void:
	var game := _fixture()
	var calls := [0]
	game.finished.connect(func(_result): calls[0] += 1)
	game._phase_timer = 0.1
	game._finish()
	game._finish()
	game._resume_play()
	game._on_shot_clock_expired()
	game._score(0, 2)
	_check("finished emitted once", calls[0] == 1)
	_check("late callbacks leave the final score alone", game.box.team_points == [0, 0])
	_check("finished game cannot resume", game.ctx.phase == MatchContext.Phase.OVER and not game.clock.running and game._phase_timer == 0.0)
	_check("finished ball is parked", game.ball.state == Ball.State.DEAD and game.ball.holder == null)
	game.free()


func _interception() -> void:
	var game := _fixture()
	var passer: PlayerPawn = game.squads[0][0]
	var thief: PlayerPawn = game.squads[1][0]
	passer.take_ball(game.ball)
	game.ball.release(Vector3.RIGHT, Vector3.ZERO, Ball.State.PASS)
	passer.has_ball = false
	game.ball.pass_target = thief.get_instance_id()
	game.clock.shot_clock = 4.0
	game._award_possession(thief)
	_check("scheduled interception credits a steal", game.box.players[thief.get_instance_id()]["stl"] == 1)
	_check("turnover belongs to passer", game.box.players[passer.get_instance_id()]["to"] == 1)
	_check("defensive catch resets the clock", game.clock.shot_clock == 24.0)
	game.free()


func _rim_crossing() -> void:
	var game := _fixture()
	var hoop := Hoop.new()
	game.add_child(hoop)
	hoop.rim_position = CourtMetrics.rim_position(0)
	game.ball.state = Ball.State.SHOT
	game.ball.linear_velocity = Vector3(6.0, -6.0, 0.0)
	var plane := hoop.rim_position - Vector3.UP * Hoop.SCORE_PLANE_DROP
	hoop.reset_tracking(plane + Vector3(-0.3, 0.3, 0.0))
	game.ball.global_position = plane + Vector3(0.3, -0.3, 0.0)
	_check("fast shot scores at crossing, not endpoint", hoop.check_ball(game.ball) == 2)
	_check("same crossing never scores twice", hoop.check_ball(game.ball) == 0)
	game.ball.state = Ball.State.HELD
	hoop.reset_tracking(plane + Vector3.UP)
	game.ball.global_position = plane - Vector3.UP
	_check("held ball cannot score", hoop.check_ball(game.ball) == 0)
	game.free()


func _shot_clock_flight() -> void:
	var clock := MatchClock.new(4, 60.0)
	var horns := [0]
	clock.shot_clock_expired.connect(func(): horns[0] += 1)
	clock.shot_clock = 0.01
	clock.running = true
	clock.shot_in_flight = true
	clock.tick(0.02)
	_check("released shot survives shot clock horn", horns[0] == 0 and clock.running)
	clock.reset_shot_clock(14.0)
	_check("rim reset resumes possession clock", not clock.shot_in_flight and clock.shot_clock == 14.0)


func _rim_clock_once() -> void:
	var game := _fixture()
	_release(game)
	game._on_rim_contact()
	game.clock.shot_clock = 13.5
	game._on_rim_contact()
	_check("rattling on the rim does not keep restoring time", game.clock.shot_clock == 13.5)
	game.free()


func _free_throw_inputs() -> void:
	var game := _fixture()
	var shooter: PlayerPawn = game.squads[0][0]
	shooter.teammates.assign(game.squads[1])
	game._begin_free_throws(shooter, 1)
	shooter.intent.pass_pressed = true
	shooter._offence_inputs()
	_check("free throw cannot turn into a pass", shooter.state == PlayerPawn.State.LOCOMOTION)
	game.free()


func _release_sequence() -> void:
	var game := _fixture()
	var shooter: PlayerPawn = game.squads[0][0]
	shooter.take_ball(game.ball)
	shooter.is_user_controlled = true
	shooter._enter(PlayerPawn.State.SHOOT)
	shooter.state_time = 0.5
	shooter.shot_charge = 0.6
	shooter.intent.shoot_released = true
	shooter._tick_shoot(0.01)
	var charge := shooter.shot_charge
	_check("input release stages the arm extension", game.ball.holder == shooter and shooter._release_delay > 0.0)
	shooter.intent.clear_edges()
	shooter._tick_shoot(PlayerPawn.RELEASE_EXTENSION)
	_check("extension preserves the chosen timing", is_equal_approx(shooter.shot_charge, charge))
	_check("release queues after pose update", shooter._queued_release == "shot")
	shooter._drive_animator(PlayerPawn.RELEASE_EXTENSION)
	shooter._update_ball_anchor(0.0)
	var from := shooter.ball_anchor.global_position
	shooter._release_shot(false)
	_check("shot starts at the animated hand", game.ball.global_position.distance_to(from) < 0.001)
	_check("release clears the holder", game.ball.holder == null and not shooter.has_ball)
	shooter.cancel_action()
	_check("cancel discards queued callbacks", shooter._queued_release.is_empty() and shooter._release_delay < 0.0)
	game.free()


func _quick_play_result() -> void:
	var game := _fixture()
	Game.league = {}
	game._finish()
	_check("quick play carries its team identity into results", Game.last_box_score["home_team"]["abbr"] == game.setup.home["abbr"])
	game.free()


func _network_result() -> void:
	var game := _fixture()
	var sync := MatchSync.new()
	sync.match_scene = game
	game.add_child(sync)
	var payload := {"home_team": game.setup.home, "away_team": game.setup.away,
		"home": 0, "away": 16, "home_score": 2, "away_score": 0,
		"season_day": -1, "box": {"players": game.box.players.duplicate(true),
			"team_points": [2, 0], "quarter_points": [[2], [0]]}}
	sync._receive_final(payload)
	payload["box"]["team_points"] = [99, 99]
	sync._receive_final(payload)
	_check("client final score is delivered once", game.box.team_points == [2, 0])
	_check("client has a usable box score", Game.last_box_score["box"] is BoxScore)
	_check("client shows the final action", not game.hud._final.is_empty())
	game.free()


func _ai_gather() -> void:
	var game := _fixture()
	var shooter: PlayerPawn = game.squads[0][0]
	shooter.take_ball(game.ball)
	shooter.state = PlayerPawn.State.SHOOT
	shooter.shot_charge = 0.3
	var ai := TeamAI.new(0, 0, 33)
	ai.pawns.assign(game.squads[0])
	ai._decision_time = 0.15
	ai.tick(1.0 / 60.0, game.ctx)
	_check("AI keeps gathering between decisions", shooter.intent.shoot_held)
	shooter.shot_charge = 0.7
	ai.tick(1.0 / 60.0, game.ctx)
	_check("AI releases after gathering", not shooter.intent.shoot_held)
	game.free()


func _hung_buzzer_shot() -> void:
	var game := _fixture()
	game.clock.quarter = 4
	game.box.team_points = [1, 0]
	_release(game)
	game.ball.linear_velocity = Vector3.ZERO
	game._on_quarter_expired(4)
	game._pending_shot["age"] = game.SHOT_RESOLUTION_LIMIT
	game._physics_process(1.0 / 60.0)
	_check("ball stuck above rim cannot hold the final horn forever", game.ctx.phase == MatchContext.Phase.OVER)
	game.free()


func _airborne_boundary() -> void:
	var game := _fixture()
	game.ball.go_loose()
	game.ball.global_position = Vector3(CourtMetrics.HALF_LENGTH + 1.0, 4.0, 0.0)
	game.ball.linear_velocity = Vector3(-2.0, -3.0, 0.0)
	game._check_out_of_bounds()
	_check("airborne boundary crossing remains live", game.ctx.is_live())
	game.ball.global_position.y = CourtMetrics.BALL_RADIUS
	game._check_out_of_bounds()
	_check("outside floor contact ends the possession", game.ctx.phase == MatchContext.Phase.DEAD)
	game.free()


func _held_boundary() -> void:
	var game := _fixture()
	ArenaBuilder.build_collision_only(game)
	var handler: PlayerPawn = game.squads[0][0]
	handler.global_position = Vector3(CourtMetrics.HALF_LENGTH + 1.0, 0.02, 0.0)
	for frame in 3:
		await get_tree().physics_frame
		handler.velocity = Vector3.DOWN * 2.0
		handler.move_and_slide()
	_check("boundary fixture is grounded", handler.is_on_floor())
	handler.take_ball(game.ball)
	game._update_context()
	game._check_out_of_bounds()
	game._check_out_of_bounds()
	_check("grounded carrier cannot dribble outside", game.ctx.phase == MatchContext.Phase.DEAD and game.ctx.possession == 1)
	_check("boundary turnover counts once", game.box.players[handler.get_instance_id()]["to"] == 1)
	game.free()
