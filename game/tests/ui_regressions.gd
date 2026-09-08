extends Node

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_input_edges()
	_touch_holds()
	_save_validation()
	await _menu_layouts()
	print("UI regressions: %d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _input_edges() -> void:
	var controller := HumanController.new(1, HumanController.Device.PAD, 1)
	controller._pad_previous = {"shoot": false}
	controller._pad_state = {"shoot": true}
	_check("press survives checking for release", not controller._released("shoot") and controller._pressed("shoot"))
	controller._pad_previous = {"shoot": true}
	controller._pad_state = {"shoot": false}
	_check("release survives checking for press", not controller._pressed("shoot") and controller._released("shoot"))
	for event in InputMap.action_get_events("shoot"):
		if event is InputEventJoypadButton:
			_check("primary input does not accept every pad", event.device >= 0)


func _touch_holds() -> void:
	var controls := TouchControls.new()
	add_child(controls)
	controls.size = Vector2(1280.0, 720.0)
	for index in 2:
		var event := InputEventScreenTouch.new()
		event.position = controls._button_centre("shoot")
		event.index = index
		event.pressed = true
		controls._handle_touch(event)
	controls.clear_edges()
	var release := InputEventScreenTouch.new()
	release.index = 0
	controls._handle_touch(release)
	_check("one finger does not release another", controls.is_held("shoot") and not controls.was_released("shoot"))
	release.index = 1
	controls._handle_touch(release)
	_check("last finger releases the action", not controls.is_held("shoot") and controls.was_released("shoot"))
	controls.release_all()
	_check("pause clears touch edges", not controls.was_pressed("shoot") and not controls.was_released("shoot"))
	controls.free()


func _save_validation() -> void:
	_check("invalid league rejected before assignment", not Game.validate_save({"version": 1, "league": []}).is_empty())
	_check("missing teams rejected", not Game.validate_save({"version": 1, "league": {}}).is_empty())
	var league := League.new_league(33)
	league["user_team"] = 0
	_check("current save shape accepted", Game.validate_save({"version": 1, "league": league}).is_empty())


func _menu_layouts() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child(viewport)
	var previous_focus := Button.new()
	viewport.add_child(previous_focus)
	previous_focus.grab_focus()
	var menu := MenuScreen.new()
	menu.title = "QUICK PLAY"
	for index in 12:
		menu.rows.append({"id": str(index), "label": "OPTION %d" % index, "value": "HOME TEAM"})
	viewport.add_child(menu)
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(720, 400)]:
		viewport.size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		_check("new menu takes focus from the previous screen", menu._scroll.is_ancestor_of(viewport.gui_get_focus_owner()))
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check("menu list fits %s" % dimensions, bounds.encloses(menu._scroll.get_rect()))
		_check("back action fits %s" % dimensions, bounds.encloses(menu._back.get_rect()))
		_check("long menu can scroll %s" % dimensions, menu._list.size.y > menu._scroll.size.y)
	menu.selected = 11
	menu._move(1)
	_check("navigation wraps to first row", menu.selected == 0)
	viewport.free()
