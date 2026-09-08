class_name TouchControls
extends Control

# On-screen stick and buttons for phones. The stick is floating: it appears
# wherever the left thumb lands, which beats a fixed pad on varied screen sizes.

const STICK_RADIUS := 108.0
const BUTTON_RADIUS := 58.0
const LEFT_ZONE := 0.45

var buttons := {
	"shoot": {"offset": Vector2(-96.0, -104.0), "label": "SHOOT"},
	"pass_ball": {"offset": Vector2(-210.0, -60.0), "label": "PASS"},
	"sprint": {"offset": Vector2(-96.0, -222.0), "label": "TURBO"},
	"switch_player": {"offset": Vector2(-232.0, -186.0), "label": "SWITCH"},
}

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_current := Vector2.ZERO
var _held: Dictionary = {}
var _pressed: Dictionary = {}
var _released: Dictionary = {}
var _button_touch: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = Settings.wants_touch_controls()
	for key in buttons:
		_held[key] = false


func is_active() -> bool:
	return visible


func consumes(action: String) -> bool:
	return buttons.has(action)


func move_vector() -> Vector2:
	if _stick_touch < 0:
		return Vector2.ZERO
	var delta := (_stick_current - _stick_origin) / STICK_RADIUS
	return delta if delta.length() <= 1.0 else delta.normalized()


func is_held(action: String) -> bool:
	return bool(_held.get(action, false))


func was_pressed(action: String) -> bool:
	return bool(_pressed.get(action, false))


func was_released(action: String) -> bool:
	return bool(_released.get(action, false))


func release_all() -> void:
	_stick_touch = -1
	_button_touch.clear()
	for action in _held:
		_held[action] = false
	clear_edges()
	queue_redraw()


func clear_edges() -> void:
	_pressed.clear()
	_released.clear()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if event.position.x < size.x * LEFT_ZONE:
			if _stick_touch < 0:
				_stick_touch = event.index
				_stick_origin = event.position
				_stick_current = event.position
			return
		var hit := _button_at(event.position)
		if not hit.is_empty():
			_button_touch[event.index] = hit
			if not bool(_held.get(hit, false)):
				_pressed[hit] = true
			_held[hit] = true
			queue_redraw()
		return

	if event.index == _stick_touch:
		_stick_touch = -1
		queue_redraw()
	elif _button_touch.has(event.index):
		var action: String = _button_touch[event.index]
		_button_touch.erase(event.index)
		if not _button_touch.values().has(action):
			_held[action] = false
			_released[action] = true
		queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _stick_touch:
		_stick_current = event.position
		queue_redraw()


func _button_at(point: Vector2) -> String:
	for key in buttons:
		if point.distance_to(_button_centre(key)) <= BUTTON_RADIUS * 1.25:
			return key
	return ""


func _button_centre(key: String) -> Vector2:
	return size + (buttons[key]["offset"] as Vector2)


func _draw() -> void:
	var ink := Color(1, 1, 1, 0.20)
	if _stick_touch >= 0:
		draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, ink, 4.0, true)
		var knob := _stick_origin + move_vector() * STICK_RADIUS
		draw_circle(knob, 34.0, Color(1, 1, 1, 0.30))
	for key in buttons:
		var centre := _button_centre(key)
		var down: bool = bool(_held.get(key, false))
		draw_circle(centre, BUTTON_RADIUS, Color(1, 1, 1, 0.26 if down else 0.12))
		draw_arc(centre, BUTTON_RADIUS, 0.0, TAU, 32, ink, 3.0, true)
		var font := ThemeDB.fallback_font
		var label: String = buttons[key]["label"]
		var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		draw_string(font, centre + Vector2(-extent.x * 0.5, 7.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.75))
