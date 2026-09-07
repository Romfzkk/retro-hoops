class_name HumanController
extends RefCounted

# Maps one player's input device onto whichever pawn they currently control.
# Player one reads the action map (keyboard or any pad); player two reads a
# specific pad directly so both can play on one screen.

enum Device { ACTIONS, PAD, REMOTE }

const SWITCH_COOLDOWN := 0.25
const STICK_DEADZONE := 0.22

var team_index := 0
var device: Device = Device.ACTIONS
var pad_id := 0
var active: PlayerPawn
var squad: Array[PlayerPawn] = []

## The intent built this frame. On a client this is what gets uploaded.
var local_intent := PlayerIntent.new()

var _switch_cooldown := 0.0
var _touch: TouchControls


func _init(team: int, input_device: Device, pad: int = 0) -> void:
	team_index = team
	device = input_device
	pad_id = pad


func attach_touch(controls: TouchControls) -> void:
	_touch = controls


func tick(delta: float, ctx: MatchContext) -> void:
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
	_follow_possession(ctx)
	if active == null:
		return

	var intent := active.intent
	intent.reset()
	if device == Device.REMOTE:
		_copy_remote(intent)
		return
	intent.move = _stick()
	intent.aim = intent.move
	intent.sprint = _held("sprint")
	intent.shoot_held = _held("shoot")
	intent.shoot_pressed = _pressed("shoot")
	intent.shoot_released = _released("shoot")
	intent.pass_pressed = _pressed("pass_ball")
	intent.special_pressed = _pressed("special")

	if _pressed("switch_player") and _switch_cooldown <= 0.0:
		_switch_cooldown = SWITCH_COOLDOWN
		_switch_to_nearest(ctx)
	_remember(intent)


# The host applies whatever the visiting client last uploaded.
func _copy_remote(intent: PlayerIntent) -> void:
	var source := Net.remote_intent
	intent.move = source.move
	intent.aim = source.aim
	intent.sprint = source.sprint
	intent.shoot_held = source.shoot_held
	intent.shoot_pressed = source.shoot_pressed
	intent.shoot_released = source.shoot_released
	intent.pass_pressed = source.pass_pressed
	intent.special_pressed = source.special_pressed
	source.clear_edges()


func _remember(intent: PlayerIntent) -> void:
	local_intent.move = intent.move
	local_intent.aim = intent.aim
	local_intent.sprint = intent.sprint
	local_intent.shoot_held = intent.shoot_held
	local_intent.shoot_pressed = intent.shoot_pressed
	local_intent.shoot_released = intent.shoot_released
	local_intent.pass_pressed = intent.pass_pressed
	local_intent.special_pressed = intent.special_pressed
	local_intent.switch_pressed = intent.switch_pressed


func _follow_possession(ctx: MatchContext) -> void:
	if squad.is_empty():
		return
	# On offence you always get the ball handler; on defence you keep whoever
	# you switched to until the ball changes hands.
	if ctx.carrier != null and ctx.carrier.team_index == team_index:
		_set_active(ctx.carrier)
		return
	if active == null or (active.team_index != team_index):
		_switch_to_nearest(ctx)


func _switch_to_nearest(ctx: MatchContext) -> void:
	var anchor := ctx.ball.global_position if ctx.ball != null else Vector3.ZERO
	var best: PlayerPawn = null
	var best_distance := INF
	for pawn in squad:
		if pawn == active:
			continue
		var distance := pawn.global_position.distance_squared_to(anchor)
		if distance < best_distance:
			best_distance = distance
			best = pawn
	if best != null:
		_set_active(best)


func _set_active(pawn: PlayerPawn) -> void:
	if active == pawn:
		return
	if active != null:
		active.is_user_controlled = false
		active.intent.reset()
	active = pawn
	active.is_user_controlled = true


func _stick() -> Vector2:
	if _touch != null and _touch.is_active():
		return _touch.move_vector()
	if device == Device.ACTIONS:
		return Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var raw := Vector2(Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(pad_id, JOY_AXIS_LEFT_Y))
	return raw if raw.length() > STICK_DEADZONE else Vector2.ZERO


func _held(action: String) -> bool:
	if _touch != null and _touch.is_active() and _touch.consumes(action):
		return _touch.is_held(action)
	if device == Device.ACTIONS:
		return Input.is_action_pressed(action)
	return Input.is_joy_button_pressed(pad_id, _pad_button(action))


func _pressed(action: String) -> bool:
	if _touch != null and _touch.is_active() and _touch.consumes(action):
		return _touch.was_pressed(action)
	if device == Device.ACTIONS:
		return Input.is_action_just_pressed(action)
	return _pad_edge(action, true)


func _released(action: String) -> bool:
	if _touch != null and _touch.is_active() and _touch.consumes(action):
		return _touch.was_released(action)
	if device == Device.ACTIONS:
		return Input.is_action_just_released(action)
	return _pad_edge(action, false)


var _pad_state: Dictionary = {}


func _pad_edge(action: String, wanted_press: bool) -> bool:
	var button := _pad_button(action)
	var down := Input.is_joy_button_pressed(pad_id, button)
	var was: bool = _pad_state.get(action, false)
	_pad_state[action] = down
	return (down and not was) if wanted_press else (was and not down)


func _pad_button(action: String) -> JoyButton:
	match action:
		"shoot": return JOY_BUTTON_A
		"pass_ball": return JOY_BUTTON_X
		"special": return JOY_BUTTON_B
		"switch_player": return JOY_BUTTON_Y
		"sprint": return JOY_BUTTON_RIGHT_SHOULDER
	return JOY_BUTTON_A
