class_name MenuScreen
extends Control

# Base for every menu. Handles the shared chrome (title block, footer hints),
# keyboard/pad navigation and the row drawing, so each screen only has to
# describe its own rows and react to a choice.

signal chosen(id: String)
signal cancelled()

const ROW_HEIGHT := 66.0
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
## Art slot drawn in the detail area, from UiArt.SLOTS. Empty draws nothing.
var art_slot := ""
## Shown under the art, if there is art.
var art_caption := ""
## Wide slot along the bottom of the detail area. Screens that already fill
## that area with their own content use this instead of `art_slot`; the detail
## rect shrinks to make room, so nothing has to be moved by hand.
var art_banner := ""

var _hold_direction := 0
var _hold_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	set_process(true)
	FrameCapture.attach(self)


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
	if next != selected:
		Sound.play("ui_move", -14.0)
	selected = next


func _adjust(step: int) -> void:
	if rows.is_empty() or not rows[selected].has("value"):
		return
	on_adjust(String(rows[selected]["id"]), step)


func _activate() -> void:
	if rows.is_empty() or not bool(rows[selected].get("enabled", true)):
		return
	Sound.play("ui_select", -12.0)
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
	_draw_art_banner(scale)
	_draw_footer(scale)


## Screens over live 3D keep the scene visible and rely on the column block
## for contrast; the rest tint the whole frame down.
func _draw_backdrop() -> void:
	var scale := UiTheme.scale_for(view())
	if dim_background:
		var wash := UiTheme.INK
		wash.a = 0.80
		draw_rect(Rect2(Vector2.ZERO, view()), wash)
		_draw_vignette()
		return
	# Broadcast lower-third. The band fades out rather than ending on a hard
	# edge, which is the difference between type sitting on the picture and a
	# panel pasted over it.
	var solid := content_left(scale) + (PANEL_WIDTH + UiTheme.S) * scale
	var ink := UiTheme.INK
	ink.a = 0.88
	draw_rect(Rect2(Vector2.ZERO, Vector2(solid, view().y)), ink)
	var fade := UiTheme.XXL * 5.0 * scale
	var steps := 14
	for i in steps:
		var t := float(i) / float(steps)
		var strip := UiTheme.INK
		strip.a = 0.88 * (1.0 - t)
		draw_rect(Rect2(Vector2(solid + fade * t, 0.0),
			Vector2(fade / float(steps) + 1.0, view().y)), strip)
	# A single accent hairline is enough to read as an edge.
	var edge := UiTheme.ORANGE
	edge.a = 0.55
	draw_rect(Rect2(Vector2(solid, 0.0), Vector2(2.0 * scale, view().y)), edge)
	_draw_vignette()


## Corners pulled down so the eye stays on the middle of the frame.
func _draw_vignette() -> void:
	var height := view().y
	var steps := 10
	for i in steps:
		var t := float(i) / float(steps)
		var shade := UiTheme.INK
		shade.a = 0.30 * t * t
		var band := height * 0.06 * (1.0 - t)
		draw_rect(Rect2(Vector2(0.0, height - band * float(steps - i)),
			Vector2(view().x, band)), shade)


func _draw_header(scale: float) -> void:
	var left := content_left(scale)
	var top := 118.0 * scale
	# Title carries the screen. A 44px heading on a 1080 frame was reading as a
	# web page's h1 rather than as a game's name.
	var size := UiTheme.size(UiTheme.DISPLAY, scale)
	UiTheme.label(self, title, Vector2(left, top), UiTheme.display_font(),
		size, UiTheme.TEXT)
	var width := UiTheme.text_width(title, UiTheme.display_font(), size)
	draw_rect(Rect2(Vector2(left, top + 14.0 * scale),
		Vector2(maxf(width, 120.0 * scale), UiTheme.ACCENT_BAR * scale)),
		UiTheme.ORANGE)
	if not subtitle.is_empty():
		UiTheme.label(self, subtitle.to_upper(),
			Vector2(left, top + 40.0 * scale), UiTheme.bold_font(),
			UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)


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
	# Only the highlighted row is a panel. Filling every row the same made the
	# list read as web navigation instead of a selection.
	if is_selected:
		UiTheme.panel(self, rect, UiTheme.SURFACE_HI, 0.98)
		draw_rect(Rect2(rect.position,
			Vector2(UiTheme.ACCENT_BAR * scale * 2.0, rect.size.y)), UiTheme.ORANGE)
		var glow := UiTheme.ORANGE
		glow.a = 0.10
		draw_rect(Rect2(rect.position,
			Vector2(rect.size.x * 0.45, rect.size.y)), glow)
	else:
		draw_line(Vector2(rect.position.x, rect.end.y),
			Vector2(rect.end.x, rect.end.y), UiTheme.LINE, UiTheme.HAIRLINE)

	var ink := UiTheme.TEXT if enabled else UiTheme.TEXT_DIM.darkened(0.25)
	if is_selected:
		ink = UiTheme.TEXT
	elif enabled:
		ink = UiTheme.TEXT_DIM
	var indent := (UiTheme.XXL if is_selected else UiTheme.XL) * scale
	var label_size := UiTheme.size(UiTheme.TITLE if is_selected else UiTheme.HEAD, scale)
	UiTheme.label(self, String(row["label"]),
		Vector2(rect.position.x + indent, rect.position.y + 44.0 * scale),
		UiTheme.display_font(), label_size, ink)

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
## highlighted row, or set `art_slot` to hang a piece of artwork there.
func _draw_side_panel(scale: float) -> void:
	if art_slot.is_empty():
		return
	var area := detail_rect(scale)
	# Kept to a poster on the right rather than filling the detail area. Art
	# that spans the whole right side buries the court it is sitting on.
	var cap := minf(area.size.x * 0.52, view().x * 0.22)
	area = Rect2(Vector2(area.end.x - cap, area.position.y),
		Vector2(cap, area.size.y * 0.82))
	if area.size.x < 80.0 * scale or area.size.y < 80.0 * scale:
		return
	# Sized to the slot's authored aspect and pinned to the top of the area, so
	# artwork is never stretched to fill whatever space is left over.
	var wanted := UiArt.aspect(art_slot)
	var height := minf(area.size.y, area.size.x / maxf(wanted, 0.01))
	var width := height * wanted
	if width > area.size.x:
		width = area.size.x
		height = width / maxf(wanted, 0.01)
	var frame := Rect2(Vector2(area.position.x + (area.size.x - width) * 0.5,
		area.position.y), Vector2(width, height))
	UiArt.draw_slot(self, frame, art_slot, scale)
	draw_rect(frame, UiTheme.LINE, false, UiTheme.HAIRLINE)
	draw_rect(Rect2(frame.position, Vector2(UiTheme.ACCENT_BAR * scale * 2.0,
		28.0 * scale)), UiTheme.ORANGE)
	if not art_caption.is_empty():
		UiTheme.label(self, art_caption.to_upper(),
			Vector2(frame.position.x, frame.end.y + 26.0 * scale),
			UiTheme.bold_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)


func _draw_footer(scale: float) -> void:
	var y := view().y - 46.0 * scale
	var left := content_left(scale)
	draw_line(Vector2(left, y - 24.0 * scale),
		Vector2(left + PANEL_WIDTH * scale, y - 24.0 * scale),
		UiTheme.LINE, UiTheme.HAIRLINE)
	draw_rect(Rect2(Vector2(left, y - 10.0 * scale),
		Vector2(UiTheme.ACCENT_BAR * scale, 14.0 * scale)), UiTheme.ORANGE)
	UiTheme.label(self, footer, Vector2(left + UiTheme.M * scale, y),
		UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)


func content_left(scale: float) -> float:
	return maxf(view().x * 0.08, 48.0 * scale)


func rows_top(scale: float) -> float:
	return 190.0 * scale


func detail_rect(scale: float) -> Rect2:
	var left := content_left(scale) + (PANEL_WIDTH + UiTheme.XXL) * scale
	var height := view().y - rows_top(scale) - 110.0 * scale
	if not art_banner.is_empty():
		height -= _banner_rect(scale).size.y + UiTheme.XL * scale
	return Rect2(Vector2(left, rows_top(scale)),
		Vector2(view().x - left - content_left(scale), height))


func _banner_rect(scale: float) -> Rect2:
	var left := content_left(scale) + (PANEL_WIDTH + UiTheme.XXL) * scale
	var width := view().x - left - content_left(scale)
	var height := minf(width / maxf(UiArt.aspect(art_banner), 0.01),
		view().y * 0.26)
	return Rect2(Vector2(left, view().y - 110.0 * scale - height),
		Vector2(width, height))


func _draw_art_banner(scale: float) -> void:
	if art_banner.is_empty():
		return
	var frame := _banner_rect(scale)
	if frame.size.x < 120.0 * scale or frame.size.y < 60.0 * scale:
		return
	UiArt.draw_slot(self, frame, art_banner, scale)
	draw_rect(frame, UiTheme.LINE, false, UiTheme.HAIRLINE)
	draw_rect(Rect2(frame.position,
		Vector2(UiTheme.ACCENT_BAR * scale * 2.0, 28.0 * scale)), UiTheme.ORANGE)
