class_name MenuScreen
extends Control

signal chosen(id: String)
signal cancelled()

const ROW_HEIGHT := 66.0
const ROW_GAP := 4.0
const PANEL_WIDTH := 460.0
const REPEAT_DELAY := 0.34
const REPEAT_RATE := 0.09

# Rows accept id, label, value, enabled and hint. A value adds adjustment buttons.
var rows: Array[Dictionary] = []
var title := ""
var subtitle := ""
var footer := "Navigate: arrows    Select: Enter    Back: Esc"
var selected := 0
var dim_background := true
var art_slot := ""
var art_banner := ""
var back_label := "BACK"
var details_enabled := true

var _hold_direction := 0
var _hold_time := 0.0
var _scroll: ScrollContainer
var _list: VBoxContainer
var _buttons: Array[Button] = []
var _heading: Label
var _subtitle: Label
var _footer: Label
var _back: Button
var _details: Button
var _show_details := false
var _rows_hash := 0
var _last_scale := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading = _label(UiTheme.display_font())
	_subtitle = _label(UiTheme.text_font())
	_footer = _label(UiTheme.text_font())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_back = UiTheme.button("BACK")
	_back.pressed.connect(_go_back)
	add_child(_back)
	_details = UiTheme.button("DETAILS")
	_details.pressed.connect(func():
		_show_details = true
		_back.grab_focus())
	add_child(_details)
	FrameCapture.attach(self)


func _label(font: Font) -> Label:
	var result := Label.new()
	result.add_theme_font_override("font", font)
	result.add_theme_color_override("font_color", UiTheme.TEXT)
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result


func view() -> Vector2:
	return get_viewport_rect().size


func _process(delta: float) -> void:
	_tick_repeat(delta)
	var scale := UiTheme.scale_for(view())
	if hash(rows) != _rows_hash or not is_equal_approx(scale, _last_scale):
		_rebuild_rows(scale)
	_layout(scale)
	queue_redraw()


func _input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if (focus != null and not is_ancestor_of(focus)) or focus is LineEdit or not event.is_pressed():
		return
	if event.is_echo():
		get_viewport().set_input_as_handled()
		return
	if event.is_action("ui_cancel") or event.is_action("pause"):
		_go_back()
	elif _show_details:
		return
	elif event.is_action("move_up") or event.is_action("ui_up"):
		_move(-1)
	elif event.is_action("move_down") or event.is_action("ui_down"):
		_move(1)
	elif event.is_action("move_left") or event.is_action("ui_left"):
		_adjust(-1)
	elif event.is_action("move_right") or event.is_action("ui_right"):
		_adjust(1)
	elif event.is_action("ui_accept") or event.is_action("shoot"):
		if focus == _back or focus == _details:
			(focus as Button).pressed.emit()
		elif focus != null and focus.has_meta("step"):
			_adjust(int(focus.get_meta("step")))
		else:
			_activate()
	else:
		return
	get_viewport().set_input_as_handled()


func _go_back() -> void:
	if _show_details:
		_show_details = false
		_focus_selected.call_deferred()
	else:
		cancelled.emit()


func _tick_repeat(delta: float) -> void:
	if _show_details or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var direction := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	if direction == 0:
		_hold_direction = 0
		_hold_time = 0.0
	elif direction != _hold_direction:
		_hold_direction = direction
		_hold_time = -REPEAT_DELAY
	else:
		_hold_time += delta
		if _hold_time >= REPEAT_RATE:
			_hold_time -= REPEAT_RATE
			_move(direction)


func _move(step: int) -> void:
	if rows.is_empty():
		return
	var next := selected
	for unused in rows.size():
		next = wrapi(next + step, 0, rows.size())
		if bool(rows[next].get("enabled", true)):
			_select(next)
			_focus_selected()
			return


func _select(index: int) -> void:
	if selected != index:
		Sound.play("ui_move", -14.0)
	selected = index


func _adjust(step: int) -> void:
	if rows.is_empty() or not rows[selected].has("value") or not bool(rows[selected].get("enabled", true)):
		return
	Sound.play("ui_move", -14.0)
	on_adjust(String(rows[selected]["id"]), step)


func _activate() -> void:
	if rows.is_empty() or not bool(rows[selected].get("enabled", true)):
		return
	Sound.play("ui_select", -12.0)
	chosen.emit(String(rows[selected]["id"]))


func on_adjust(_id: String, _step: int) -> void:
	pass


func _rebuild_rows(scale: float) -> void:
	_rows_hash = hash(rows)
	_last_scale = scale
	selected = clampi(selected, 0, maxi(rows.size() - 1, 0))
	var focus := get_viewport().gui_get_focus_owner()
	var had_focus := _buttons.is_empty() or focus == null or _scroll.is_ancestor_of(focus)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_list.add_theme_constant_override("separation", int(ROW_GAP * scale))
	for index in rows.size():
		var row: Dictionary = rows[index]
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = maxf(48.0, ROW_HEIGHT * scale)
		line.add_theme_constant_override("separation", 0)
		_list.add_child(line)
		var button := UiTheme.button(String(row["label"]), scale)
		button.name = String(row["id"]).validate_node_name()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not bool(row.get("enabled", true))
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func():
			_select(index)
			_activate())
		button.focus_entered.connect(func(): _select(index))
		button.mouse_entered.connect(func(): _select(index))
		line.add_child(button)
		_buttons.append(button)
		if row.has("value"):
			for step in [-1, 1]:
				var arrow := UiTheme.button("<" if step < 0 else ">", scale)
				arrow.set_meta("step", step)
				arrow.custom_minimum_size.x = 42.0 * scale
				arrow.disabled = button.disabled
				arrow.tooltip_text = "Previous" if step < 0 else "Next"
				arrow.focus_entered.connect(func(): _select(index))
				arrow.pressed.connect(func():
					_select(index)
					_adjust(step))
				line.add_child(arrow)
				if step < 0:
					var value := Label.new()
					value.text = String(row["value"])
					value.tooltip_text = value.text
					value.custom_minimum_size.x = 140.0 * scale
					value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					value.add_theme_font_override("font", UiTheme.bold_font())
					value.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.BODY, scale))
					value.add_theme_color_override("font_color", UiTheme.TEXT)
					line.add_child(value)
	if had_focus:
		_focus_selected.call_deferred()


func _focus_selected() -> void:
	if _buttons.is_empty():
		return
	if _buttons[selected].disabled:
		_move(1)
		return
	_buttons[selected].grab_focus()
	_scroll.ensure_control_visible(_buttons[selected])


func _layout(scale: float) -> void:
	var left := content_left(scale)
	_heading.text = title
	_heading.position = Vector2(left, 38.0 * scale)
	_heading.size = Vector2(view().x - left * 2.0 - 120.0 * scale, 82.0 * scale)
	_heading.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.DISPLAY, scale))
	_subtitle.text = subtitle
	_subtitle.position = Vector2(left, 126.0 * scale)
	_subtitle.size = Vector2(view().x - left * 2.0, 30.0 * scale)
	_subtitle.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.BODY, scale))
	_scroll.position = Vector2(left, rows_top(scale))
	_scroll.size = Vector2(minf(PANEL_WIDTH * scale, view().x - left * 2.0),
		maxf(48.0, view().y - rows_top(scale) - 98.0 * scale))
	_scroll.visible = not _show_details
	_back.text = back_label
	_back.position = Vector2(view().x - left - 104.0 * scale, 48.0 * scale)
	_back.size = Vector2(104.0 * scale, 48.0 * scale)
	var narrow := not _wide_details(scale)
	_details.visible = details_enabled and narrow and not _show_details
	_details.position = Vector2(view().x - left - 112.0 * scale, view().y - 66.0 * scale)
	_details.size = Vector2(112.0 * scale, 48.0 * scale)
	_footer.text = footer
	if not rows.is_empty() and rows[selected].has("hint"):
		_footer.text = String(rows[selected]["hint"])
	_footer.position = Vector2(left, view().y - 54.0 * scale)
	_footer.size = Vector2(view().x - left * 2.0 - (130.0 * scale if narrow else 0.0), 34.0 * scale)
	_footer.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.LABEL, scale))


func _wide_details(scale: float) -> bool:
	return view().x - content_left(scale) * 2.0 - (PANEL_WIDTH + UiTheme.XXL) * scale >= 360.0 * scale


func _draw() -> void:
	var scale := UiTheme.scale_for(view())
	var ink := UiTheme.INK
	ink.a = 0.90 if dim_background or _show_details else 0.78
	var width := view().x if dim_background or _show_details else content_left(scale) + (PANEL_WIDTH + UiTheme.XL) * scale
	draw_rect(Rect2(Vector2.ZERO, Vector2(width, view().y)), ink)
	draw_rect(Rect2(Vector2(content_left(scale), 116.0 * scale), Vector2(80.0 * scale, 3.0)), UiTheme.ORANGE)
	if _wide_details(scale) or _show_details:
		_draw_side_panel(scale)
		_draw_art_banner(scale)


func _draw_side_panel(scale: float) -> void:
	if UiArt.texture(art_slot) == null:
		return
	var area := detail_rect(scale)
	area.size.y = minf(area.size.y, area.size.x / UiArt.aspect(art_slot))
	UiArt.draw_slot(self, area, art_slot, scale)


func content_left(scale: float) -> float:
	return maxf(view().x * 0.055, 24.0 * scale)


func rows_top(scale: float) -> float:
	return 184.0 * scale


func detail_rect(scale: float) -> Rect2:
	var left := content_left(scale)
	if not _show_details:
		left += (PANEL_WIDTH + UiTheme.XXL) * scale
	var height := view().y - rows_top(scale) - 98.0 * scale
	if UiArt.texture(art_banner) != null:
		height -= _banner_rect(scale).size.y + UiTheme.XL * scale
	return Rect2(Vector2(left, rows_top(scale)), Vector2(view().x - left - content_left(scale), height))


func _banner_rect(scale: float) -> Rect2:
	var left := content_left(scale)
	if not _show_details:
		left += (PANEL_WIDTH + UiTheme.XXL) * scale
	var width := view().x - left - content_left(scale)
	var height := minf(width / UiArt.aspect(art_banner), view().y * 0.24)
	return Rect2(Vector2(left, view().y - 98.0 * scale - height), Vector2(width, height))


func _draw_art_banner(scale: float) -> void:
	if UiArt.texture(art_banner) != null:
		UiArt.draw_slot(self, _banner_rect(scale), art_banner, scale)
