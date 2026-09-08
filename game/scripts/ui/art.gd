class_name UiArt
extends RefCounted

const DIR := "res://assets/art"
const SLOTS := {
	"hero": {"file": "graphic1.png", "aspect": 1.78},
	"tipoff": {"file": "graphic2.png", "aspect": 1.78},
	"season": {"file": "graphic3.png", "aspect": 1.78},
	"champion": {"file": "graphic4.png", "aspect": 1.20},
}

static var _cache: Dictionary = {}


static func texture(slot: String) -> Texture2D:
	if not SLOTS.has(slot):
		return null
	if not _cache.has(slot):
		var path: String = DIR.path_join(SLOTS[slot]["file"])
		_cache[slot] = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	return _cache[slot]


static func aspect(slot: String) -> float:
	var art := texture(slot)
	if art != null:
		return float(art.get_width()) / float(art.get_height())
	return float(SLOTS.get(slot, {}).get("aspect", 1.0))


static func draw_slot(canvas: CanvasItem, rect: Rect2, slot: String,
		_scale: float, tint: Color = Color.WHITE) -> void:
	var art := texture(slot)
	if art == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var source := art.get_size()
	var cover := maxf(rect.size.x / source.x, rect.size.y / source.y)
	var crop := rect.size / cover
	canvas.draw_texture_rect_region(rect, art, Rect2((source - crop) * 0.5, crop), tint)
