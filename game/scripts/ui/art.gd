class_name UiArt
extends RefCounted

# Slots where authored artwork drops in. Nothing ships in them, and the game
# must look deliberate when they are empty, so a missing slot draws a framed
# placeholder naming the file it wants rather than a broken rectangle.

const DIR := "res://assets/art"

## Slot id to the file it looks for, and the shape it is drawn at. Aspect is
## width over height, so art can be authored to fit before it is dropped in.
const SLOTS := {
	"hero": {"file": "graphic1.png", "aspect": 0.72, "label": "MENU HERO"},
	"tipoff": {"file": "graphic2.png", "aspect": 1.78, "label": "MATCH SETUP"},
	"season": {"file": "graphic3.png", "aspect": 1.78, "label": "SEASON BANNER"},
	"champion": {"file": "graphic4.png", "aspect": 1.20, "label": "CHAMPIONS"},
}

static var _cache: Dictionary = {}


static func texture(slot: String) -> Texture2D:
	if _cache.has(slot):
		return _cache[slot]
	var found: Texture2D = null
	if SLOTS.has(slot):
		var path: String = DIR.path_join(SLOTS[slot]["file"])
		if ResourceLoader.exists(path):
			found = ResourceLoader.load(path) as Texture2D
	_cache[slot] = found
	return found


static func aspect(slot: String) -> float:
	return float(SLOTS[slot]["aspect"]) if SLOTS.has(slot) else 1.0


## Draws the slot into `rect`. Art is cropped to fill rather than letterboxed,
## so a slot never shows bars whatever the source is.
static func draw_slot(canvas: CanvasItem, rect: Rect2, slot: String,
		scale: float, tint: Color = Color.WHITE) -> void:
	var art := texture(slot)
	if art == null:
		_draw_placeholder(canvas, rect, slot, scale)
		return
	var source := Vector2(art.get_width(), art.get_height())
	if source.x <= 0.0 or source.y <= 0.0:
		_draw_placeholder(canvas, rect, slot, scale)
		return
	var cover := maxf(rect.size.x / source.x, rect.size.y / source.y)
	var drawn := source * cover
	var offset := rect.position + (rect.size - drawn) * 0.5
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var previous := canvas.get_canvas_item()
	RenderingServer.canvas_item_set_clip(previous, true)
	RenderingServer.canvas_item_set_custom_rect(previous, true, rect)
	canvas.draw_texture_rect(art, Rect2(offset, drawn), false, tint)
	RenderingServer.canvas_item_set_clip(previous, false)
	RenderingServer.canvas_item_set_custom_rect(previous, false, Rect2())


static func _draw_placeholder(canvas: CanvasItem, rect: Rect2, slot: String,
		scale: float) -> void:
	canvas.draw_rect(rect, UiTheme.SURFACE)
	# Diagonal hatch, so an empty slot reads as reserved space rather than as a
	# panel someone forgot to fill.
	var step := 22.0 * scale
	var hatch := UiTheme.LINE
	hatch.a = 0.45
	var offset := -rect.size.y
	while offset < rect.size.x:
		var from := Vector2(rect.position.x + offset, rect.position.y)
		var to := Vector2(rect.position.x + offset + rect.size.y, rect.end.y)
		# Clip to the panel so the hatch does not spill past its own frame.
		if from.x < rect.position.x:
			from = Vector2(rect.position.x, rect.position.y + (rect.position.x - from.x))
		if to.x > rect.end.x:
			to = Vector2(rect.end.x, rect.position.y + (rect.end.x - rect.position.x - offset))
		if from.y < rect.end.y and to.y > rect.position.y:
			canvas.draw_line(from, to, hatch, 1.0)
		offset += step
	canvas.draw_rect(rect, UiTheme.LINE, false, UiTheme.HAIRLINE)

	var entry: Dictionary = SLOTS.get(slot, {})
	var label := String(entry.get("label", slot.to_upper()))
	var file := String(entry.get("file", "?"))
	var centre := rect.get_center()
	UiTheme.label_centred(canvas, label, centre.x, centre.y - 2.0 * scale,
		UiTheme.display_font(), UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT_DIM)
	UiTheme.label_centred(canvas, "assets/art/%s" % file, centre.x,
		centre.y + 18.0 * scale, UiTheme.text_font(),
		UiTheme.size(UiTheme.MICRO, scale), UiTheme.LINE)
