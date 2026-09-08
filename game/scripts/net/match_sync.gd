class_name MatchSync
extends Node

# State replication for an online game.
#
# The host simulates everything and sends a snapshot at SNAPSHOT_HZ. The client
# never simulates: it uploads its intent every frame and interpolates toward
# whatever the host last said. That keeps both sides watching one authoritative
# game rather than two diverging ones.

const SNAPSHOT_HZ := 24.0
## Per pawn: x, y, z, yaw, speed, flags, stamina.
const PAWN_FLOATS := 7
## Ball: x, y, z, vx, vy, vz, state.
const BALL_FLOATS := 7

var match_scene: Node
var _accumulator := 0.0
var _received_final := false


static func attach(scene: Node) -> MatchSync:
	var sync := MatchSync.new()
	sync.name = "MatchSync"
	sync.match_scene = scene
	scene.add_child(sync)
	scene.finished.connect(sync._publish_final)
	return sync


func _physics_process(delta: float) -> void:
	if not Net.is_online():
		return
	if Net.is_host():
		_accumulator += delta
		var interval := 1.0 / SNAPSHOT_HZ
		if _accumulator >= interval:
			_accumulator -= interval
			_send_snapshot()
	else:
		_send_intent()



func _send_snapshot() -> void:
	if Net.client_id == 0:
		return
	var pawns := PackedFloat32Array()
	for team_index in 2:
		for pawn: PlayerPawn in match_scene.squads[team_index]:
			pawns.append(pawn.global_position.x)
			pawns.append(pawn.global_position.y)
			pawns.append(pawn.global_position.z)
			pawns.append(pawn.rotation.y)
			pawns.append(Vector3(pawn.velocity.x, 0.0, pawn.velocity.z).length())
			pawns.append(float(_pack_flags(pawn)))
			pawns.append(pawn.stamina)

	var ball_state := PackedFloat32Array([
		match_scene.ball.global_position.x,
		match_scene.ball.global_position.y,
		match_scene.ball.global_position.z,
		match_scene.ball.linear_velocity.x,
		match_scene.ball.linear_velocity.y,
		match_scene.ball.linear_velocity.z,
		float(match_scene.ball.state),
	])

	var clock: MatchClock = match_scene.clock
	var scoreboard := PackedInt32Array([
		match_scene.box.team_points[0], match_scene.box.team_points[1],
		clock.quarter, int(clock.remaining * 10.0), int(clock.shot_clock * 10.0),
		int(match_scene.ctx.phase), match_scene.ctx.possession, int(clock.shot_in_flight),
		int(match_scene._period_pending), int(match_scene._free_throws.get("remaining", 0)),
		int(match_scene._free_throws.get("total", 0)),
	])
	_apply_snapshot.rpc_id(Net.client_id, pawns, ball_state, scoreboard)


func _pack_flags(pawn: PlayerPawn) -> int:
	var flags := int(pawn.state)
	if pawn.has_ball:
		flags |= 1 << 4
	if pawn.is_on_floor():
		flags |= 1 << 5
	if pawn.ball_hand > 0.0:
		flags |= 1 << 6
	return flags


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_snapshot(pawns: PackedFloat32Array, ball_state: PackedFloat32Array,
		scoreboard: PackedInt32Array) -> void:
	if _received_final:
		return
	var index := 0
	for team_index in 2:
		for pawn: PlayerPawn in match_scene.squads[team_index]:
			var base := index * PAWN_FLOATS
			if base + PAWN_FLOATS > pawns.size():
				break
			pawn.apply_network_state(
				Vector3(pawns[base], pawns[base + 1], pawns[base + 2]),
				pawns[base + 3], pawns[base + 4], int(pawns[base + 5]),
				pawns[base + 6])
			index += 1

	if ball_state.size() >= BALL_FLOATS:
		match_scene.ball.apply_network_state(
			Vector3(ball_state[0], ball_state[1], ball_state[2]),
			Vector3(ball_state[3], ball_state[4], ball_state[5]),
			int(ball_state[6]))

	if scoreboard.size() >= 7:
		match_scene.box.team_points[0] = scoreboard[0]
		match_scene.box.team_points[1] = scoreboard[1]
		var clock: MatchClock = match_scene.clock
		clock.quarter = scoreboard[2]
		clock.remaining = float(scoreboard[3]) * 0.1
		clock.shot_clock = float(scoreboard[4]) * 0.1
		match_scene.ctx.phase = scoreboard[5] as MatchContext.Phase
		match_scene.ctx.possession = scoreboard[6]
		match_scene.ctx.carrier = null
		for squad in match_scene.squads:
			for pawn: PlayerPawn in squad:
				if bool(pawn._net_flags & (1 << 4)):
					match_scene.ctx.carrier = pawn
		if scoreboard.size() >= 11:
			clock.shot_in_flight = bool(scoreboard[7])
			match_scene._period_pending = bool(scoreboard[8])
			match_scene._free_throws = {"remaining": scoreboard[9], "total": scoreboard[10]}



func _send_intent() -> void:
	var controllers: Array = match_scene.humans
	if controllers.is_empty():
		return
	var controller: HumanController = controllers[0]
	var intent: PlayerIntent = controller.local_intent
	_receive_intent.rpc_id(1, intent.move, intent.aim, _pack_buttons(intent))


func _pack_buttons(intent: PlayerIntent) -> int:
	var bits := 0
	if intent.sprint:
		bits |= 1 << 0
	if intent.shoot_held:
		bits |= 1 << 1
	if intent.shoot_pressed:
		bits |= 1 << 2
	if intent.shoot_released:
		bits |= 1 << 3
	if intent.pass_pressed:
		bits |= 1 << 4
	if intent.special_pressed:
		bits |= 1 << 5
	if intent.switch_pressed:
		bits |= 1 << 6
	return bits


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_intent(move: Vector2, aim: Vector2, buttons: int) -> void:
	if not Net.is_host() or multiplayer.get_remote_sender_id() != Net.client_id:
		return
	if match_scene.ctx.phase == MatchContext.Phase.OVER or not move.is_finite() or not aim.is_finite():
		return
	var intent := Net.remote_intent
	intent.move = move.limit_length(1.0)
	intent.aim = aim.limit_length(1.0)
	intent.sprint = bool(buttons & (1 << 0))
	intent.shoot_held = bool(buttons & (1 << 1))
	intent.shoot_pressed = bool(buttons & (1 << 2))
	intent.shoot_released = bool(buttons & (1 << 3))
	intent.pass_pressed = bool(buttons & (1 << 4))
	intent.special_pressed = bool(buttons & (1 << 5))
	intent.switch_pressed = bool(buttons & (1 << 6))
	intent.switch_pressed = bool(buttons & (1 << 6))


func _publish_final(result: Dictionary) -> void:
	if not Net.is_host() or Net.client_id == 0:
		return
	var payload := result.duplicate()
	var box: BoxScore = result["box"]
	payload["box"] = {"players": box.players, "team_points": box.team_points,
		"quarter_points": box.quarter_points}
	_receive_final.rpc_id(Net.client_id, payload)


@rpc("authority", "call_remote", "reliable")
func _receive_final(payload: Dictionary) -> void:
	if _received_final:
		return
	_received_final = true
	var box := BoxScore.new()
	box.players = payload["box"]["players"]
	box.team_points = payload["box"]["team_points"]
	box.quarter_points = payload["box"]["quarter_points"]
	var result := payload.duplicate()
	result["box"] = box
	match_scene.box = box
	match_scene.ctx.phase = MatchContext.Phase.OVER
	match_scene.ctx.carrier = null
	match_scene.clock.running = false
	match_scene._period_pending = false
	match_scene.ball.park()
	match_scene._cancel_player_actions()
	for squad in match_scene.squads:
		for pawn: PlayerPawn in squad:
			pawn._net_flags = 1 << 5
			pawn._net_speed = 0.0
			pawn._net_position = pawn.global_position
	match_scene.ball.apply_network_state(match_scene.ball.global_position, Vector3.ZERO, Ball.State.DEAD)
	match_scene._set_play_permissions()
	Game.last_box_score = result
	match_scene.hud.show_final(result)
