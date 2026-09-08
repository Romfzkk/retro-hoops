extends Node

# Autoload: user options plus the keyboard/gamepad action map. Written to
# user://settings.json on change.

signal changed(key: String)

const PATH := "user://settings.json"

enum CameraMode { BROADCAST, BEHIND, HIGH, COURTSIDE, RAIL }
enum ShotStyle { HYBRID, TIMING, POWER, AUTO }

const DEFAULTS := {
	"master_volume": 0.9,
	"sfx_volume": 1.0,
	"music_volume": 0.6,
	"crowd_volume": 0.8,
	"render_scale": 1.0,
	"retro_filter": true,
	"retro_strength": 0.6,
	"scanlines": false,
	"shadows": true,
	"camera_mode": CameraMode.BROADCAST,
	"shot_style": ShotStyle.HYBRID,
	"shot_meter_visible": true,
	"quarter_minutes": 5,
	"difficulty": 1,
	"fullscreen": false,
	"touch_controls": 0, # 0 auto, 1 always, 2 never
	"vibration": true,
	"player_name": "Player",
}

var _values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	_register_actions()
	Input.joy_connection_changed.connect(_assign_primary_pad)
	_assign_primary_pad(0, true)
	load_from_disk()
	apply_window()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_error("Unknown setting: %s" % key)
		return
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key)
	save_to_disk()


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Cannot read %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Settings file is not a JSON object, using defaults")
		return
	# Only accept keys we know, and coerce to the default's type so a hand
	# edited file cannot inject a string where a float is expected.
	for key in DEFAULTS:
		if not parsed.has(key):
			continue
		var wanted := typeof(DEFAULTS[key])
		var value: Variant = parsed[key]
		if typeof(value) == wanted:
			_values[key] = value
		elif wanted == TYPE_FLOAT and typeof(value) == TYPE_INT:
			_values[key] = float(value)
		elif wanted == TYPE_INT and typeof(value) == TYPE_FLOAT:
			_values[key] = int(value)


func save_to_disk() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write %s: %s" % [PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(_values, "\t"))


func apply_window() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func wants_touch_controls() -> bool:
	match int(get_value("touch_controls")):
		1: return true
		2: return false
	return OS.has_feature("mobile")


# Actions are declared here rather than in project.godot so the bindings live
# next to the code that reads them.
const ACTION_KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"shoot": [KEY_SPACE],
	"pass_ball": [KEY_E],
	"special": [KEY_Q],
	"switch_player": [KEY_F],
	"call_play": [KEY_R],
	"pause": [KEY_ESCAPE],
	"ui_accept_alt": [KEY_ENTER],
}

const ACTION_BUTTONS := {
	"shoot": [JOY_BUTTON_A],
	"pass_ball": [JOY_BUTTON_X],
	"special": [JOY_BUTTON_B],
	"switch_player": [JOY_BUTTON_Y],
	"call_play": [JOY_BUTTON_LEFT_SHOULDER],
	"pause": [JOY_BUTTON_START],
}


func _register_actions() -> void:
	for action in ACTION_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTION_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in ACTION_BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for button in ACTION_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	_add_stick_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_stick_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_stick_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_stick_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_stick_axis("sprint", JOY_AXIS_TRIGGER_RIGHT, 1.0)


func _add_stick_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _assign_primary_pad(_device: int, _connected: bool) -> void:
	var pads := Input.get_connected_joypads()
	var primary := pads[0] if not pads.is_empty() else 0
	for action in ACTION_KEYS:
		if action == "pause":
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
				event.device = primary
				InputMap.action_add_event(action, event)
