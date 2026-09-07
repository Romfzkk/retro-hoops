extends Node

class TestMatch extends "res://scripts/match/match_scene.gd":
	func _ready() -> void:
		set_physics_process(false)

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_ownership()
	_pass_expiry()
	_free_throw_scoring()
	_foul_rebound()
	_buzzer_shot()
	_finished_match()
	_interception()
	_rim_crossing()
	_shot_clock_flight()
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
