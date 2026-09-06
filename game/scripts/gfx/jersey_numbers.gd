class_name JerseyNumbers
extends Control

# Numbers 0-99 rendered once into a 10x10 atlas. Jersey quads then index a cell
# with a UV offset, so ten players on court cost one texture, not ten.

const CELL := 96
const COLUMNS := 10
const ATLAS_SIZE := Vector2i(CELL * COLUMNS, CELL * COLUMNS)

static var _texture: Texture2D


static func atlas(host: Node) -> Texture2D:
	if _texture != null:
		return _texture
	var viewport := SubViewport.new()
	viewport.size = ATLAS_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := JerseyNumbers.new()
	painter.size = Vector2(ATLAS_SIZE)
	viewport.add_child(painter)
	host.add_child(viewport)
	_texture = viewport.get_texture()
	return _texture


static func uv_scale() -> Vector3:
	return Vector3(1.0 / float(COLUMNS), 1.0 / float(COLUMNS), 1.0)


static func uv_offset(number: int) -> Vector3:
	var n := clampi(number, 0, COLUMNS * COLUMNS - 1)
	return Vector3(float(n % COLUMNS) / float(COLUMNS),
		float(n / COLUMNS) / float(COLUMNS), 0.0)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for n in COLUMNS * COLUMNS:
		var cell := Rect2(Vector2(float(n % COLUMNS), float(n / COLUMNS)) * float(CELL),
			Vector2(CELL, CELL))
		var text := str(n)
		var font_size := CELL - 18 if text.length() < 2 else CELL - 34
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var origin := cell.position + Vector2(
			(cell.size.x - extent.x) * 0.5,
			(cell.size.y + extent.y * 0.62) * 0.5)
		# Outline first so the number reads on any jersey colour.
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, 10, Color(0.05, 0.05, 0.07, 0.9))
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, Color.WHITE)
