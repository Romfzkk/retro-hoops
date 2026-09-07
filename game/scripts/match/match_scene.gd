extends Node3D

# Owns a single game: builds the world, spawns both squads, runs the clock and
# the rules, and reports the result back to whoever launched it.

signal finished(result: Dictionary)

const INBOUND_PAUSE := 1.1
const TIPOFF_SET := 1.3
## Puts the apex around 3.9m, above a standing reach but inside a jump.
const TIPOFF_TOSS := 6.3
const TIPOFF_CONTEST_HEIGHT := 3.15
## How much of the tip is a coin flip rather than reach and hops.
const TIPOFF_LUCK := 0.30
const TIPOFF_TAP_TIME := 0.75
const TIPOFF_GIVE_UP := 3.0
const QUARTER_BREAK := 2.4
const CATCH_RADIUS := 0.95
const OUT_OF_BOUNDS_MARGIN := 0.25
## Team fouls in a period before the other side shoots on every foul.
const BONUS_FOULS := 5
const FREE_THROW_SETUP := 1.3
const FREE_THROW_GAP := 0.9
const FREE_THROW_TIMEOUT := 15.0
const BLOCK_REACH := 1.7

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
var crowd: Crowd

var events := {"out_of_bounds": 0, "shot_clock": 0, "possessions": 0,
	"dunks": 0, "shot_quality_sum": 0.0, "shot_distance_sum": 0.0, "shots": 0,
	"passes": 0, "catches": 0, "loose_pickups": 0, "steals_from_pass": 0}

var team_fouls: Array[int] = [0, 0]

var _free_throws := {}
var _pending_foul := {}
var _balance_run := false
var _verbose := false

var _pending_shot := {}
var _phase_timer := 0.0
var _tipoff_step := 0
var _tipoff_timer := 0.0
var _tipoff_jumpers: Array[PlayerPawn] = []
var _resume_phase: MatchContext.Phase = MatchContext.Phase.LIVE
var _elapsed := 0.0
var _pause_layer: CanvasLayer
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
	ball.touched_floor.connect(_on_ball_bounced)
	ball.hit_rim.connect(func(): Sound.play("rim", -4.0, randf_range(0.94, 1.08)))
	ball.hit_backboard.connect(func(): Sound.play("backboard", -3.0))
	add_child(ball)

	_spawn_squads()
	_setup_camera()
	_setup_controllers()
	_setup_hud()

	ctx.ball = ball
	ctx.teams = squads
	ctx.difficulty = setup.difficulty
	crowd = get_tree().get_first_node_in_group("crowd") as Crowd
	_begin_tipoff()
	FrameCapture.attach(self)
	FrameCapture.FpsProbe.attach(self)
	SimProbe.attach(self)
	ControlProbe.attach(self)


func _fill_exhibition_setup() -> void:
	var lg := Game.exhibition_league()
	var teams: Array = lg["teams"]
	# `--home` / `--away` let a balance run pick the matchup, which is how the
	# home/away sides get compared with the rosters swapped.
	var home_arg := FrameCapture.argument("--home")
	var away_arg := FrameCapture.argument("--away")
	var home_id := int(home_arg) if not home_arg.is_empty() else 0
	var away_id := int(away_arg) if not away_arg.is_empty() else 16
	setup.home = teams[posmod(home_id, teams.size())]
	setup.away = teams[posmod(away_id, teams.size())]


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
			pawn.set_random_seed(_rng.randi())
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
			var score := float(player["ovr"]) \
				- absf(float(player["pos"]) - float(position)) * 6.0
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
	if setup.online:
		_setup_online_controllers()
		return
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


# Online is host-authoritative. The host drives its own side locally and the
# visitor's side from uploaded intent; the client simulates nothing.
func _setup_online_controllers() -> void:
	var local := Net.local_team()
	humans.append(HumanController.new(local, HumanController.Device.ACTIONS))
	if Net.is_host():
		humans.append(HumanController.new(1 - local, HumanController.Device.REMOTE))
	else:
		ball.network_remote = true
		for team_index in 2:
			for pawn: PlayerPawn in squads[team_index]:
				pawn.network_remote = true
	for controller in humans:
		controller.squad.assign(squads[controller.team_index])
		if not _balance_run:
			var team: Dictionary = setup.home if controller.team_index == 0 else setup.away
			markers.append(PlayerMarker.create(self, Color(team["primary"])))
	MatchSync.attach(self)


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

	if ctx.phase == MatchContext.Phase.TIPOFF:
		if not setup.online or Net.is_host():
			_tick_tipoff(delta)
		return

	for controller in humans:
		controller.tick(delta, ctx)

	if setup.online and not Net.is_host():
		return
	for ai in ais:
		ai.tick(delta, ctx)

	if ctx.phase == MatchContext.Phase.FREE_THROW:
		_check_scoring()
		_tick_free_throws(delta)
	elif ctx.is_live():
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

	if crowd != null:
		# The stands stand up for the same things the crowd bed reacts to.
		crowd.set_excitement(Sound.crowd_level())

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
	Sound.play("swish", -2.0)
	Sound.react(0.75 if points == 3 else 0.45)
	if ctx.phase == MatchContext.Phase.FREE_THROW:
		# The sequence decides what happens next, not the basket.
		return
	if not _pending_foul.is_empty():
		var fouled: PlayerPawn = _pending_foul["fouled"]
		_pending_foul.clear()
		hud.announce("AND ONE", true)
		Sound.react(0.9)
		_begin_free_throws(fouled, 1)
		return
	hud.announce("%d PTS" % points, points == 3)
	_dead_ball(1 - scoring_team, INBOUND_PAUSE, true)


func _resolve_miss() -> void:
	if _pending_shot.is_empty():
		return
	if not _pending_foul.is_empty():
		var foul := _pending_foul
		_pending_foul = {}
		box.record_miss(int(_pending_shot["shooter"]), int(_pending_shot["points"]))
		_pending_shot.clear()
		_begin_free_throws(foul["fouled"], int(foul["attempts"]))
		return
	if _verbose:
		print("  -> MISS  ball=(%.2f,%.2f,%.2f)" % [ball.global_position.x,
			ball.global_position.y, ball.global_position.z])
	box.record_miss(int(_pending_shot["shooter"]), int(_pending_shot["points"]))
	if not _balance_run:
		Sound.react(0.12)
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
	Sound.play("whistle", -6.0)
	hud.announce("OUT OF BOUNDS", false)
	_dead_ball(to_team, INBOUND_PAUSE * 0.8)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action("pause") or event.is_action("ui_cancel"):
		if ctx.phase == MatchContext.Phase.OVER:
			Game.goto("res://scenes/box_score.tscn")
		elif _pause_layer == null:
			_open_pause_menu()


# Esc used to walk straight out of the match with no way back. The tree is
# paused rather than the scene torn down, so the game is still there behind it.
func _open_pause_menu() -> void:
	var menu := MenuScreen.new()
	menu.title = "PAUSED"
	menu.subtitle = "%s  %d - %d  %s" % [setup.home["abbr"], box.team_points[0],
		box.team_points[1], setup.away["abbr"]]
	menu.footer = "Move  W/S    Select  Enter    Resume  Esc"
	menu.dim_background = false
	menu.rows = [
		{"id": "resume", "label": "RESUME"},
		{"id": "quit", "label": "QUIT TO MENU"},
	]
	menu.chosen.connect(_on_pause_choice)
	menu.cancelled.connect(_close_pause_menu)

	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 10
	_pause_layer.add_child(menu)
	# The layer has to keep running while everything else is stopped.
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	get_tree().paused = true


func _close_pause_menu() -> void:
	if _pause_layer == null:
		return
	get_tree().paused = false
	_pause_layer.queue_free()
	_pause_layer = null


func _on_pause_choice(id: String) -> void:
	_close_pause_menu()
	if id == "quit":
		Game.goto("res://scenes/main_menu.tscn")


func _on_ball_bounced(_position: Vector3) -> void:
	if _balance_run:
		return
	Sound.play("bounce", -9.0, randf_range(0.92, 1.1))


func _last_touch_team() -> int:
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			if pawn.get_instance_id() == ball.last_touched_by:
				return team_index
	return ctx.possession


# `shot_free_throws` of zero is a common foul; anything else sends the fouled
# player to the line for that many.
func _call_foul(offender: PlayerPawn, fouled: PlayerPawn, shot_free_throws: int) -> void:
	var team := offender.team_index
	team_fouls[team] += 1
	box.add(offender.get_instance_id(), "pf")
	Sound.play("whistle", -5.0)

	var in_bonus: bool = team_fouls[team] > BONUS_FOULS
	if shot_free_throws > 0:
		# The shot still counts. Whether it falls decides between an and-one
		# and a full trip to the line, so the free throws wait for it.
		hud.announce("SHOOTING FOUL", false)
		_pending_foul = {"fouled": fouled, "attempts": shot_free_throws}
		return
	if in_bonus:
		hud.announce("FOUL  BONUS", false)
		_resolve_miss()
		_begin_free_throws(fouled, 2)
		return
	hud.announce("FOUL  %d" % team_fouls[team], false)
	_resolve_miss()
	_dead_ball(fouled.team_index, INBOUND_PAUSE * 0.8)


func _begin_free_throws(shooter: PlayerPawn, attempts: int) -> void:
	ctx.phase = MatchContext.Phase.FREE_THROW
	clock.running = false
	_phase_timer = 0.0
	_pending_shot.clear()
	_pending_foul.clear()
	_free_throws = {
		"shooter": shooter,
		"remaining": attempts,
		"timer": FREE_THROW_SETUP,
		"awaiting": false,
		"patience": FREE_THROW_TIMEOUT,
	}
	_line_up_free_throw(shooter)


func _line_up_free_throw(shooter: PlayerPawn) -> void:
	var sign_x := CourtMetrics.attack_sign(shooter.basket)
	var line_x := sign_x * CourtMetrics.FREE_THROW_X
	var slot := 0
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			pawn.velocity = Vector3.ZERO
			pawn.lose_ball()
			if pawn == shooter:
				pawn.global_position = Vector3(line_x - sign_x * 0.4, 0.0, 0.0)
				continue
			# Alternate sides of the lane, defence nearest the rim.
			var side := 1.0 if slot % 2 == 0 else -1.0
			var depth := 1.1 + float(slot / 2) * 1.3
			if pawn.team_index != shooter.team_index:
				depth += 0.55
			pawn.global_position = Vector3(
				sign_x * (CourtMetrics.HALF_LENGTH - depth), 0.0,
				side * CourtMetrics.PAINT_WIDTH * 0.5)
			slot += 1
	ball.set_paused(false)
	shooter.take_ball(ball)


func _tick_free_throws(delta: float) -> void:
	if _free_throws.is_empty():
		return
	var shooter: PlayerPawn = _free_throws["shooter"]
	if not is_instance_valid(shooter):
		_end_free_throws()
		return

	# A player who never takes the shot must not be able to stall the game.
	_free_throws["patience"] = float(_free_throws["patience"]) - delta
	if float(_free_throws["patience"]) <= 0.0:
		_end_free_throws()
		return

	_free_throws["timer"] = float(_free_throws["timer"]) - delta
	if float(_free_throws["timer"]) > 0.0:
		return

	if not bool(_free_throws["awaiting"]):
		# The AI shoots itself; a human uses the meter like any other shot.
		if not shooter.is_user_controlled:
			shooter.intent.shoot_pressed = true
			shooter.intent.shoot_held = true
		if shooter.state == PlayerPawn.State.SHOOT:
			_free_throws["awaiting"] = true
		return

	# Released and resolved: the ball is no longer in the shooter's hands and
	# has finished its trip to the rim.
	if shooter.has_ball:
		return
	if ball.state == Ball.State.SHOT and not ball.rebound_ready:
		return
	_free_throws["remaining"] = int(_free_throws["remaining"]) - 1
	if int(_free_throws["remaining"]) <= 0:
		_end_free_throws()
		return
	_free_throws["timer"] = FREE_THROW_GAP
	_free_throws["awaiting"] = false
	_free_throws["patience"] = FREE_THROW_TIMEOUT
	_line_up_free_throw(shooter)


func _end_free_throws() -> void:
	var shooter: PlayerPawn = _free_throws.get("shooter")
	_free_throws.clear()
	_resolve_miss()
	if shooter == null or not is_instance_valid(shooter):
		ctx.phase = MatchContext.Phase.LIVE
		clock.running = true
		return
	# The last one is live off the rim if it missed, and a dead ball if it fell.
	if ball.state == Ball.State.LOOSE and ball.global_position.y > 0.1:
		ctx.phase = MatchContext.Phase.LOOSE_BALL
		clock.reset_shot_clock()
		clock.running = true
		return
	_dead_ball(1 - shooter.team_index, INBOUND_PAUSE * 0.7)


func _on_shot_released(pawn: PlayerPawn, points: int, quality: float) -> void:
	_resolve_miss()
	if _try_block(pawn):
		return
	if ctx.phase == MatchContext.Phase.FREE_THROW:
		points = 1
		ball.shot_points = 1
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
	_maybe_shooting_foul(pawn, points)
	ctx.phase = MatchContext.Phase.SHOT_IN_FLIGHT


# A defender already in the air, whose reach covers the ball, gets a swing at
# it. Without this the block rating does nothing at all.
func _try_block(shooter: PlayerPawn) -> bool:
	if ctx.phase == MatchContext.Phase.FREE_THROW:
		return false
	var release_height := ball.global_position.y
	for defender: PlayerPawn in squads[1 - shooter.team_index]:
		if defender.is_on_floor():
			continue
		var offset := defender.global_position - shooter.global_position
		if Vector2(offset.x, offset.z).length() > BLOCK_REACH:
			continue
		# Their hand has to actually get up to the ball.
		var reach := defender.global_position.y + defender.standing_reach()
		if reach < release_height - 0.1:
			continue
		var skill := float(defender.data["blk"]) / 99.0
		var over := clampf((reach - release_height) / 0.6, 0.0, 1.0)
		if _rng.randf() >= clampf(0.015 + skill * 0.11 * over, 0.005, 0.14):
			continue
		_reject(defender, shooter)
		return true
	return false


func _reject(defender: PlayerPawn, shooter: PlayerPawn) -> void:
	box.add(defender.get_instance_id(), "blk")
	box.record_miss(shooter.get_instance_id(), ball.shot_points)
	_pending_shot.clear()

	# Swat it away from the rim rather than teleporting possession.
	var away := (shooter.global_position - CourtMetrics.rim_position(shooter.basket))
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	ball.release(away.normalized() * _rng.randf_range(3.5, 6.5)
		+ Vector3.UP * _rng.randf_range(1.0, 2.4), Vector3(4.0, 0.0, 0.0),
		Ball.State.LOOSE)
	ctx.phase = MatchContext.Phase.LOOSE_BALL
	Sound.play("rim", -6.0, 1.25)
	Sound.react(0.85)
	camera.shake(0.55)
	hud.announce("BLOCKED", true)


# Heavy contact on a shot sends the shooter to the line. Decided from how tight
# the nearest defender actually was, so it tracks what you can see.
func _maybe_shooting_foul(shooter: PlayerPawn, points: int) -> void:
	if ctx.phase == MatchContext.Phase.FREE_THROW or _balance_run:
		return
	var nearest: PlayerPawn = null
	var closest := 1.15
	for defender: PlayerPawn in squads[1 - shooter.team_index]:
		var distance := defender.global_position.distance_to(shooter.global_position)
		if distance < closest:
			closest = distance
			nearest = defender
	if nearest == null or nearest.is_on_floor():
		return
	# Only a defender who left their feet into the shooter draws it.
	var clumsiness := 1.0 - float(nearest.data["def"]) / 150.0
	if _rng.randf() >= clampf(0.05 + clumsiness * 0.13, 0.02, 0.20):
		return
	_call_foul(nearest, shooter, points)


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
		# A reach that misses is a reach that might get called. Poor defenders
		# foul more, which is what the defence rating should actually cost you.
		var clumsiness := 1.0 - float(thief.data["def"]) / 140.0
		if _rng.randf() < clampf(0.06 + clumsiness * 0.16, 0.03, 0.24):
			_call_foul(thief, target, 0)
			return
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
	Sound.play("squeak", -8.0)
	Sound.react(0.5)
	hud.announce("STEAL", false)


func _on_dunk(pawn: PlayerPawn) -> void:
	events["dunks"] = int(events["dunks"]) + 1
	# A walk-up put-down and a full-speed hammer should not land the same.
	var power := pawn.dunk_power
	camera.shake(0.7 + power * 0.9)
	if not _balance_run:
		hoops[pawn.basket].flex(0.75 + power * 0.6)
	Sound.play("rim", -2.0 + power * 4.0, 0.92 - power * 0.12)
	Sound.play("cheer", -6.0 + power * 5.0)
	Sound.react(0.7 + power * 0.3)
	Sound.react(1.0)
	hud.announce("SLAM", true)


func _on_shot_clock_expired() -> void:
	events["shot_clock"] = int(events["shot_clock"]) + 1
	Sound.play("buzzer", -8.0)
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
	Sound.play("buzzer", -4.0)
	hud.announce("END OF %s" % clock.period_name(), false)


func _begin_tipoff() -> void:
	ctx.phase = MatchContext.Phase.TIPOFF
	clock.running = false
	_phase_timer = 0.0
	_tipoff_jumpers = [_tallest(squads[0]), _tallest(squads[1])]
	_position_for_tipoff()
	_tipoff_step = 0
	_tipoff_timer = TIPOFF_SET
	hud.announce("JUMP BALL", false)


func _tallest(squad: Array) -> PlayerPawn:
	var best: PlayerPawn = squad[0]
	for pawn: PlayerPawn in squad:
		if pawn.standing_reach() > best.standing_reach():
			best = pawn
	return best


func _position_for_tipoff() -> void:
	for team_index in 2:
		var sign_x := CourtMetrics.attack_sign(team_index)
		var others: Array[PlayerPawn] = []
		for pawn: PlayerPawn in squads[team_index]:
			pawn.velocity = Vector3.ZERO
			pawn.lose_ball()
			pawn.intent.reset()
			if pawn == _tipoff_jumpers[team_index]:
				pawn.global_position = Vector3(-sign_x * 0.55, 0.0, 0.0)
				continue
			others.append(pawn)
		# The rest ring their own half of the circle, facing the toss.
		for i in others.size():
			var spread := float(i) / maxf(float(others.size() - 1), 1.0) - 0.5
			var angle := spread * PI * 0.75
			var spot := Vector3(-sign_x * cos(angle) * (CourtMetrics.CIRCLE_RADIUS + 1.4),
				0.0, sin(angle) * (CourtMetrics.CIRCLE_RADIUS + 2.8))
			others[i].global_position = spot
	ball.go_loose()
	ball.set_paused(true)
	ball.global_position = Vector3(0.0, 1.7, 0.0)


func _tick_tipoff(delta: float) -> void:
	_tipoff_timer -= delta
	match _tipoff_step:
		0:
			if _tipoff_timer <= 0.0:
				_toss_tipoff()
		1:
			# Both go up as the toss tops out, not on the way to it.
			if ball.linear_velocity.y <= 0.0 or _tipoff_timer < -TIPOFF_GIVE_UP:
				for jumper in _tipoff_jumpers:
					jumper.contest_jump()
				_tipoff_step = 2
		2:
			# The give-up is not decoration: a toss that catches the jumbotron
			# would otherwise leave the match sitting on a dead clock forever.
			if ball.global_position.y <= TIPOFF_CONTEST_HEIGHT 					or _tipoff_timer < -TIPOFF_GIVE_UP * 2.0:
				_resolve_tipoff()


func _toss_tipoff() -> void:
	ball.set_paused(false)
	ball.launch(Vector3(0.0, 1.9, 0.0), Vector3.UP * TIPOFF_TOSS,
		Vector3.ZERO, Ball.State.LOOSE)
	Sound.play("whistle", -10.0)
	_tipoff_step = 1


func _resolve_tipoff() -> void:
	var reach: Array[float] = []
	for jumper in _tipoff_jumpers:
		reach.append(jumper.standing_reach() + jumper.jump_height()
			+ _rng.randf_range(0.0, TIPOFF_LUCK))
	var winner := 0 if reach[0] >= reach[1] else 1
	var tipper: PlayerPawn = _tipoff_jumpers[winner]
	var target := _tip_target(tipper)

	# Tapped, not caught: it stays a loose ball anyone can go and get.
	var from := ball.global_position
	ball.launch(from, ShotSolver.launch_velocity(from,
		target.global_position + Vector3.UP * 1.2, TIPOFF_TAP_TIME),
		Vector3.ZERO, Ball.State.LOOSE)

	ctx.phase = MatchContext.Phase.LIVE
	ctx.possession = winner
	clock.reset_shot_clock()
	clock.running = true
	hud.announce("%s WINS THE TIP" % (setup.home if winner == 0 else setup.away)["abbr"], false)
	Sound.react(0.45)


func _tip_target(tipper: PlayerPawn) -> PlayerPawn:
	var best: PlayerPawn = null
	var best_distance := INF
	for pawn: PlayerPawn in squads[tipper.team_index]:
		if pawn == tipper:
			continue
		var distance := pawn.global_position.distance_to(tipper.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pawn
	return best if best != null else tipper


func _dead_ball(to_team: int, pause: float, from_baseline := false) -> void:
	ctx.phase = MatchContext.Phase.DEAD
	clock.running = false
	ball.go_loose()
	ball.set_paused(true)
	_phase_timer = pause
	_resume_phase = MatchContext.Phase.LIVE
	_position_for_inbound(to_team, from_baseline)


func _resume_play() -> void:
	if _resume_phase == MatchContext.Phase.INBOUND:
		team_fouls = [0, 0] as Array[int]
		if not clock.advance_quarter():
			if box.team_points[0] == box.team_points[1]:
				clock.start_overtime()
				_begin_tipoff()
				return
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


func _position_for_inbound(to_team: int, from_baseline := false) -> void:
	var sign_x := CourtMetrics.attack_sign(to_team)
	for team_index in 2:
		for pawn: PlayerPawn in squads[team_index]:
			pawn.velocity = Vector3.ZERO
			pawn.lose_ball()
			pawn.global_position = _formation_spot(pawn, team_index, to_team,
				from_baseline)
	var handler: PlayerPawn = squads[to_team][0]
	for pawn: PlayerPawn in squads[to_team]:
		if int(pawn.data["pos"]) == League.Pos.PG:
			handler = pawn
			break
	if from_baseline:
		# Behind the endline, where the ball is actually taken from. A held
		# ball is exempt from the out of bounds check, so standing there is
		# legal until they step in with it.
		handler.global_position = Vector3(
			-sign_x * (CourtMetrics.HALF_LENGTH + 0.8), 0.0,
			clampf(handler.global_position.z, -2.4, 2.4))
	ball.set_paused(false)
	handler.take_ball(ball)
	ctx.possession = to_team
	clock.reset_shot_clock()


func _formation_spot(pawn: PlayerPawn, team_index: int, offence_team: int,
		from_baseline := false) -> Vector3:
	var attack_sign := CourtMetrics.attack_sign(offence_team)
	var slot := pawn.lineup_slot
	var spread := (float(slot) - float(squads[team_index].size() - 1) * 0.5) * 2.9
	var across := clampf(spread, -CourtMetrics.HALF_WIDTH + 1.0,
		CourtMetrics.HALF_WIDTH - 1.0)
	if from_baseline:
		# Conceding a basket restarts you under your own rim, with the ball to
		# bring up. Spawning the inbounding side in the half they attack meant
		# a made basket teleported them into the other team's third.
		var back_depth := 3.2 if team_index == offence_team else 10.2
		return Vector3(
			-attack_sign * (CourtMetrics.HALF_LENGTH - back_depth - float(slot) * 0.4),
			0.0, across)
	# Offence sets up in their attacking half, defence drops back in front.
	var depth := 9.5 if team_index == offence_team else 6.2
	return Vector3(attack_sign * (CourtMetrics.HALF_LENGTH - depth - float(slot) * 0.4),
		0.0, across)


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
