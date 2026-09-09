class_name ControlProbe
extends Node

# Drives real input actions on a timeline and reports what the controlled
# player actually did. Balance was measured with AI-vs-AI runs, which never
# touched the human control path at all; this exercises the same route a
# player's keyboard takes.
#
# godot --headless --path game res://scenes/match.tscn -- --control

const ARG := "--control"

var match_scene: Node
var _elapsed := 0.0
var _step := 0
var _last_state := -1
var _log: Array[String] = []
var _script: Array[Dictionary] = []


static func attach(host: Node) -> void:
	if not FrameCapture.has_flag(ARG):
		return
	var probe := ControlProbe.new()
	probe.name = "ControlProbe"
	probe.match_scene = host
	host.add_child(probe)


func _ready() -> void:
	_script = [
		{"at": 1.2, "do": "note", "text": "--- hand the ball to the player ---"},
		{"at": 1.2, "do": "give_ball"},

		{"at": 1.6, "do": "note", "text": "--- walk with the ball for 1.2s ---"},
		{"at": 1.6, "do": "press", "action": "move_right"},
		{"at": 2.8, "do": "release", "action": "move_right"},

		{"at": 3.2, "do": "note", "text": "--- tap pass ---"},
		{"at": 3.2, "do": "tap", "action": "pass_ball"},

		{"at": 5.0, "do": "note", "text": "--- give it back, hold shoot 0.55s ---"},
		{"at": 5.0, "do": "give_ball"},
		{"at": 5.4, "do": "press", "action": "shoot"},
		{"at": 5.95, "do": "release", "action": "shoot"},

		{"at": 8.0, "do": "note", "text": "--- give it back, drive at the rim ---"},
		{"at": 8.0, "do": "give_ball"},
		{"at": 8.1, "do": "face_rim"},
		{"at": 8.2, "do": "press", "action": "sprint"},
		{"at": 8.2, "do": "press", "action": "drive"},
		{"at": 10.4, "do": "note", "text": "--- shoot from the drive ---"},
		{"at": 10.4, "do": "tap", "action": "shoot"},
		{"at": 10.6, "do": "release", "action": "drive"},
		{"at": 10.6, "do": "release", "action": "sprint"},

		{"at": 12.5, "do": "note", "text": "--- walk in slowly, no sprint ---"},
		{"at": 12.5, "do": "give_ball"},
		{"at": 12.6, "do": "face_rim", "at_m": 5.0},
		{"at": 12.7, "do": "press", "action": "drive"},
		{"at": 14.2, "do": "tap", "action": "shoot"},
		{"at": 14.4, "do": "release", "action": "drive"},

		{"at": 15.0, "do": "note", "text": "--- crossover with the ball ---"},
		{"at": 15.0, "do": "give_ball"},
		{"at": 15.2, "do": "mark_up"},
		{"at": 15.3, "do": "tap", "action": "special"},
		{"at": 15.8, "do": "mark_up"},
		{"at": 15.9, "do": "tap", "action": "special"},
		{"at": 16.3, "do": "mark_up"},
		{"at": 16.4, "do": "tap", "action": "special"},
		{"at": 16.8, "do": "mark_up"},
		{"at": 16.9, "do": "tap", "action": "special"},
		{"at": 17.3, "do": "mark_up"},
		{"at": 17.4, "do": "tap", "action": "special"},
		{"at": 17.8, "do": "mark_up"},
		{"at": 17.9, "do": "tap", "action": "special"},

		{"at": 16.0, "do": "note", "text": "--- mid range, clean release (5.0m) ---"},
		{"at": 16.0, "do": "give_ball"},
		{"at": 16.1, "do": "face_rim", "at_m": 5.0},
		{"at": 16.3, "do": "press", "action": "shoot"},
		{"at": 16.86, "do": "release", "action": "shoot"},

		{"at": 19.0, "do": "note", "text": "--- mid range, clean release (5.0m) ---"},
		{"at": 19.0, "do": "give_ball"},
		{"at": 19.1, "do": "face_rim", "at_m": 5.0},
		{"at": 19.3, "do": "press", "action": "shoot"},
		{"at": 19.86, "do": "release", "action": "shoot"},

		{"at": 22.0, "do": "note", "text": "--- three, clean release (7.4m) ---"},
		{"at": 22.0, "do": "give_ball"},
		{"at": 22.1, "do": "face_rim", "at_m": 7.4},
		{"at": 22.3, "do": "press", "action": "shoot"},
		{"at": 22.86, "do": "release", "action": "shoot"},

		{"at": 25.0, "do": "note", "text": "--- three, clean release (7.4m) ---"},
		{"at": 25.0, "do": "give_ball"},
		{"at": 25.1, "do": "face_rim", "at_m": 7.4},
		{"at": 25.3, "do": "press", "action": "shoot"},
		{"at": 25.86, "do": "release", "action": "shoot"},

		{"at": 28.0, "do": "note", "text": "--- mid range, panic tap (5.0m) ---"},
		{"at": 28.0, "do": "give_ball"},
		{"at": 28.1, "do": "face_rim", "at_m": 5.0},
		{"at": 28.3, "do": "press", "action": "shoot"},
		{"at": 28.35, "do": "release", "action": "shoot"},

		{"at": 32.5, "do": "report"},
	]
	for hoop in match_scene.hoops:
		hoop.scored.connect(func(points): _log.append(
			"  t=%5.2f  >>> SCORED %d" % [_elapsed, points]))
	for pawn in _all_pawns():
		pawn.crossed_over.connect(func(handler, beaten, severity): _log.append(
			"  t=%5.2f  CROSSOVER %s beat %s (severity %.2f)" % [_elapsed,
				handler.data["ln"], beaten.data["ln"], severity]))
		pawn.shot_released.connect(_on_shot)
		pawn.ball_passed.connect(_on_pass)
		pawn.ball_gathered.connect(_on_gather)


func _all_pawns() -> Array:
	var out: Array = []
	for team_index in 2:
		for pawn in match_scene.squads[team_index]:
			out.append(pawn)
	return out


func _physics_process(delta: float) -> void:
	# The timeline starts once the tip is over; nothing the probe presses is
	# read while the match is still setting up.
	if match_scene.ctx.phase == MatchContext.Phase.TIPOFF:
		return
	_elapsed += delta
	while _step < _script.size() and _elapsed >= float(_script[_step]["at"]):
		_run(_script[_step])
		_step += 1
	_watch_state()
	_sample_stick()


func _run(entry: Dictionary) -> void:
	var pawn: PlayerPawn = _active()
	match String(entry["do"]):
		"note":
			_log.append("\n%s" % String(entry["text"]))
		"press":
			_press(String(entry["action"]), true)
		"release":
			_press(String(entry["action"]), false)
		"tap":
			_press(String(entry["action"]), true)
			await get_tree().physics_frame
			await get_tree().physics_frame
			_press(String(entry["action"]), false)
		"give_ball":
			if pawn != null:
				pawn.pickup_cooldown = 0.0
				match_scene.ball.set_paused(false)
				pawn.take_ball(match_scene.ball)
				_log.append("  [given the ball]")
		"face_rim":
			if pawn != null:
				var rim := CourtMetrics.rim_position(pawn.basket)
				var away: float = float(entry.get("at_m", 6.5))
				pawn.velocity = Vector3.ZERO
				pawn.global_position = Vector3(
					rim.x - CourtMetrics.attack_sign(pawn.basket) * away, 0.0, rim.z)
		"mark_up":
			# Puts the nearest opponent right in front, which is the only situation
			# a crossover has anything to say about.
			if pawn != null:
				var rival: PlayerPawn = match_scene.squads[1 - pawn.team_index][0]
				rival.velocity = Vector3.ZERO
				rival.global_position = pawn.global_position + pawn.facing() * 1.15
				# The probe is checking that the button reaches the move, not whether
				# an even contest happens to go one way, so the contest is loaded.
				pawn.data["hnd"] = 99
				pawn.data["acc"] = 99
				rival.data["def"] = 25
				rival.data["acc"] = 25
				_log.append("  [defender placed: marker=%s floor=%s gathered=%s state=%s]" % [
					pawn.has_marker(), pawn.is_on_floor(), pawn.has_ball_gathered(),
					_state_name(pawn.state)])
		"report":
			_report()


# `drive` is not a real action; it means "hold the stick toward the basket".
func _press(action: String, down: bool) -> void:
	if action == "drive":
		var pawn := _active()
		var toward := "move_left"
		if pawn != null and CourtMetrics.attack_sign(pawn.basket) > 0.0:
			toward = "move_right"
		_press(toward, down)
		return
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _active() -> PlayerPawn:
	var humans: Array = match_scene.humans
	if humans.is_empty():
		return null
	return humans[0].active


var _next_sample := 0.0

# Distinguishes "the pawn ignored the stick" from "the stick was never pressed".
func _sample_stick() -> void:
	if _elapsed < _next_sample:
		return
	_next_sample = _elapsed + 0.5
	var pawn := _active()
	if pawn == null:
		return
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if raw.length() < 0.01 and pawn.velocity.length() < 0.01:
		return
	_log.append("    t=%5.2f  stick=%s  intent=%s  vel=%.2f  x=%.2f" % [
		_elapsed, raw, pawn.intent.move,
		Vector3(pawn.velocity.x, 0.0, pawn.velocity.z).length(),
		pawn.global_position.x])


func _watch_state() -> void:
	var pawn := _active()
	if pawn == null:
		return
	if int(pawn.state) == _last_state:
		return
	_last_state = int(pawn.state)
	_log.append("  t=%5.2f  state -> %s  (ball=%s, speed=%.1f, rim=%.1fm)" % [
		_elapsed, _state_name(pawn.state), pawn.has_ball,
		Vector3(pawn.velocity.x, 0.0, pawn.velocity.z).length(),
		pawn.distance_to_rim()])


func _state_name(state: int) -> String:
	return ["LOCOMOTION", "SHOOT", "PASS", "DUNK", "LAYUP", "JUMP", "STEAL",
		"STUMBLE"][clampi(state, 0, 7)]


func _on_shot(pawn: PlayerPawn, points: int, quality: float) -> void:
	if pawn != _active():
		return
	var defenders: Array = match_scene.squads[1 - pawn.team_index]
	_log.append("  t=%5.2f  SHOT %dpt acc %.2f charge %.2f | rim %.2fm arc=%s contest %.2f y=%.2f" % [
		_elapsed, points, quality, pawn.shot_charge, pawn.distance_to_rim(),
		CourtMetrics.is_behind_three(pawn.global_position, pawn.basket),
		ShotSolver.contest_level(pawn.global_position, pawn.rig.shoulder_height, defenders),
		pawn.global_position.y])


func _on_pass(passer: PlayerPawn, target: PlayerPawn, kind: int) -> void:
	const NAMES := ["chest", "bounce", "lob", "outlet"]
	_log.append("  t=%5.2f  PASS (%s) from %s to %s" % [_elapsed,
		NAMES[clampi(kind, 0, NAMES.size() - 1)],
		passer.data["ln"], target.data["ln"]])


func _on_gather(pawn: PlayerPawn) -> void:
	_log.append("  t=%5.2f  gathered by %s%s" % [_elapsed, pawn.data["ln"],
		"  <- the player" if pawn == _active() else ""])


func _report() -> void:
	print("--- control probe ---")
	for line in _log:
		print(line)
	get_tree().quit()
