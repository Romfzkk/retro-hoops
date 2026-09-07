class_name MenuScreen
extends Control

# Base for every menu. Handles the shared chrome (title block, footer hints),
# keyboard/pad navigation and the row drawing, so each screen only has to
# describe its own rows and react to a choice.

signal chosen(id: String)
signal cancelled()

const ROW_HEIGHT := 62.0
const ROW_GAP := 4.0
const PANEL_WIDTH := 460.0
const REPEAT_DELAY := 0.34
const REPEAT_RATE := 0.09

## Rows are {id, label, value?, enabled?, hint?}. `value` turns a row into a
## left/right setting rather than a button.
var rows: Array[Dictionary] = []
var title := ""
var subtitle := ""
var footer := "Move  W/S    Select  Enter    Back  Esc"
var selected := 0
## False keeps a live 3D scene readable behind the menu.
var dim_background := true

var _hold_direction := 0
var _hold_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	set_process(true)


## Anchors do not always resolve before the first frame inside a CanvasLayer,
## so the layout measures the viewport rather than trusting `size`.
func view() -> Vector2:
	return get_viewport_rect().size


func _process(delta: float) -> void:
	_tick_repeat(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action("move_up") or event.is_action("ui_up"):
		_move(-1)
	elif event.is_action("move_down") or event.is_action("ui_down"):
		_move(1)
	elif event.is_action("move_left") or event.is_action("ui_left"):
		_adjust(-1)
	elif event.is_action("move_right") or event.is_action("ui_right"):
		_adjust(1)
	elif event.is_action("ui_accept") or event.is_action("shoot"):
		_activate()
	elif event.is_action("ui_cancel") or event.is_action("pause"):
		cancelled.emit()


func _tick_repeat(delta: float) -> void:
	var direction := 0
	if Input.is_action_pressed("move_down"):
		direction = 1
	elif Input.is_action_pressed("move_up"):
		direction = -1
	if direction == 0:
		_hold_direction = 0
		_hold_time = 0.0
		return
	if direction != _hold_direction:
		_hold_direction = direction
		_hold_time = -REPEAT_DELAY
		return
	_hold_time += delta
	if _hold_time >= REPEAT_RATE:
		_hold_time = 0.0
		_move(direction)


func _move(step: int) -> void:
	if rows.is_empty():
		return
	var next := selected
	for i in rows.size():
		next = wrapi(next + step, 0, rows.size())
		if bool(rows[next].get("enabled", true)):
			break
	selected = next


func _adjust(step: int) -> void:
	if rows.is_empty() or not rows[selected].has("value"):
		return
	on_adjust(String(rows[selected]["id"]), step)


func _activate() -> void:
	if rows.is_empty() or not bool(rows[selected].get("enabled", true)):
		return
	chosen.emit(String(rows[selected]["id"]))


## Screens with settings rows override this.
func on_adjust(_id: String, _step: int) -> void:
	pass


func _draw() -> void:
	var scale := UiTheme.scale_for(view())
	_draw_backdrop()
	_draw_header(scale)
	_draw_rows(scale)
	_draw_side_panel(scale)
	_draw_footer(scale)


## Screens over live 3D keep the scene visible and rely on the column block
## for contrast; the rest tint the whole frame down.
func _draw_backdrop() -> void:
	if dim_background:
		var wash := UiTheme.INK
		wash.a = 0.72
		draw_rect(Rect2(Vector2.ZERO, view()), wash)
		return
	# Broadcast lower-third: a solid band down the left so the type always has
	# something to sit on, whatever the camera is looking at.
	var scale := UiTheme.scale_for(view())
	var band := Rect2(Vector2.ZERO,
		Vector2(content_left(scale) + (PANEL_WIDTH + UiTheme.XXL) * scale, view().y))
	var ink := UiTheme.INK
	ink.a = 0.82
	draw_rect(band, ink)
	draw_line(Vector2(band.end.x, 0.0), Vector2(band.end.x, view().y),
		UiTheme.LINE, UiTheme.HAIRLINE)


func _draw_header(scale: float) -> void:
	var left := content_left(scale)
	var top := 96.0 * scale
	draw_rect(Rect2(Vector2(left, top - 46.0 * scale),
		Vector2(UiTheme.ACCENT_BAR * scale * 2.0, 58.0 * scale)), UiTheme.ORANGE)
	UiTheme.label(self, title, Vector2(left + UiTheme.L * scale, top),
		UiTheme.display_font(), UiTheme.size(UiTheme.TITLE, scale), UiTheme.TEXT)
	if not subtitle.is_empty():
		UiTheme.label(self, subtitle,
			Vector2(left + UiTheme.L * scale, top + 30.0 * scale),
			UiTheme.text_font(), UiTheme.size(UiTheme.BODY, scale), UiTheme.TEXT_DIM)


func _draw_rows(scale: float) -> void:
	var left := content_left(scale)
	var y := rows_top(scale)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var rect := Rect2(Vector2(left, y),
			Vector2(PANEL_WIDTH * scale, ROW_HEIGHT * scale))
		_draw_row(rect, row, i == selected, scale)
		y += (ROW_HEIGHT + ROW_GAP) * scale


func _draw_row(rect: Rect2, row: Dictionary, is_selected: bool, scale: float) -> void:
	var enabled := bool(row.get("enabled", true))
	var fill := UiTheme.SURFACE_HI if is_selected else UiTheme.SURFACE
	UiTheme.panel(self, rect, fill, 0.98 if is_selected else 0.86)
	if is_selected:
		draw_rect(Rect2(rect.position, Vector2(UiTheme.ACCENT_BAR * scale * 1.6,
			rect.size.y)), UiTheme.ORANGE)

	var ink := UiTheme.TEXT if enabled else UiTheme.TEXT_DIM.darkened(0.25)
	if is_selected:
		ink = UiTheme.TEXT
	UiTheme.label(self, String(row["label"]),
		Vector2(rect.position.x + UiTheme.XL * scale, rect.position.y + 42.0 * scale),
		UiTheme.display_font(), UiTheme.size(UiTheme.HEAD, scale), ink)

	if row.has("value"):
		var value := String(row["value"])
		UiTheme.label_right(self, value, rect.end.x - UiTheme.XL * scale,
			rect.position.y + 41.0 * scale, UiTheme.bold_font(),
			UiTheme.size(UiTheme.BODY, scale),
			UiTheme.GOLD if is_selected else UiTheme.TEXT_DIM)
		if is_selected:
			UiTheme.label(self, "<", Vector2(rect.end.x - UiTheme.XL * scale
				- UiTheme.text_width(value, UiTheme.bold_font(),
				UiTheme.size(UiTheme.BODY, scale)) - 22.0 * scale,
				rect.position.y + 41.0 * scale), UiTheme.bold_font(),
				UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)
			UiTheme.label(self, ">", Vector2(rect.end.x - UiTheme.M * scale,
				rect.position.y + 41.0 * scale), UiTheme.bold_font(),
				UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)


## Right-hand detail area. Screens override it to show context for the
## highlighted row.
func _draw_side_panel(_scale: float) -> void:
	pass


func _draw_footer(scale: float) -> void:
	var y := view().y - 44.0 * scale
	draw_line(Vector2(content_left(scale), y - 26.0 * scale),
		Vector2(view().x - content_left(scale), y - 26.0 * scale),
		UiTheme.LINE, UiTheme.HAIRLINE)
	UiTheme.label(self, footer, Vector2(content_left(scale), y),
		UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)


func content_left(scale: float) -> float:
	return maxf(view().x * 0.08, 48.0 * scale)


func rows_top(scale: float) -> float:
	return 190.0 * scale


func detail_rect(scale: float) -> Rect2:
	var left := content_left(scale) + (PANEL_WIDTH + UiTheme.XXL) * scale
	return Rect2(Vector2(left, rows_top(scale)),
		Vector2(view().x - left - content_left(scale),
			view().y - rows_top(scale) - 110.0 * scale))
