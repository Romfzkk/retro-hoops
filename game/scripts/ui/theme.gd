class_name UiTheme
extends RefCounted

# Shared fonts, palette, spacing and native control styles.

const DISPLAY_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"
const TEXT_FONT := "res://assets/fonts/Barlow-Regular.ttf"
const TEXT_FONT_BOLD := "res://assets/fonts/Barlow-SemiBold.ttf"

const INK := Color("#0a0d13")
const SURFACE := Color("#141922")
const SURFACE_HI := Color("#1e2531")
const LINE := Color("#2a3340")
const TEXT := Color("#f1f5fa")
const TEXT_DIM := Color("#93a0b4")
const ORANGE := Color("#ff6b2c")
const GOLD := Color("#ffc53d")
const GREEN := Color("#37d67a")
const RED := Color("#ff4d4f")
const BLUE := Color("#4c9aff")

const DISPLAY := 72
const TITLE := 44
const HEAD := 30
const SUB := 21
const BODY := 17
const LABEL := 14
const MICRO := 12

const XS := 4
const S := 8
const M := 12
const L := 16
const XL := 24
const XXL := 32
const HUGE := 48

const HAIRLINE := 1.0
const ACCENT_BAR := 3.0

static var _display: FontFile
static var _text: FontFile
static var _text_bold: FontFile


static func display_font() -> Font:
	if _display == null:
		_display = load(DISPLAY_FONT)
	return _display if _display != null else ThemeDB.fallback_font


static func text_font() -> Font:
	if _text == null:
		_text = load(TEXT_FONT)
	return _text if _text != null else ThemeDB.fallback_font


static func bold_font() -> Font:
	if _text_bold == null:
		_text_bold = load(TEXT_FONT_BOLD)
	return _text_bold if _text_bold != null else ThemeDB.fallback_font


## Multiplier that keeps the layout proportional on any window size.
static func scale_for(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.y / 850.0, viewport_size.x / 1280.0), 0.78, 1.9)


static func size(base: int, scale: float) -> int:
	var minimum := 14 if base <= LABEL else 16
	return maxi(minimum, int(round(float(base) * scale)))



## Flat block with a hairline edge. No rounded corners anywhere: the hard edge
## is what makes it read as a broadcast graphic rather than a phone app.
static func panel(canvas: CanvasItem, rect: Rect2, fill: Color = SURFACE,
		opacity: float = 0.92) -> void:
	var body := fill
	body.a = opacity
	canvas.draw_rect(rect, body)
	canvas.draw_rect(rect, LINE, false, HAIRLINE)


static func label(canvas: CanvasItem, text: String, at: Vector2, font: Font,
		font_size: int, colour: Color) -> void:
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


static func label_centred(canvas: CanvasItem, text: String, centre_x: float,
		baseline_y: float, font: Font, font_size: int, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	canvas.draw_string(font, Vector2(centre_x - width * 0.5, baseline_y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


static func label_right(canvas: CanvasItem, text: String, right_x: float,
		baseline_y: float, font: Font, font_size: int, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	canvas.draw_string(font, Vector2(right_x - width, baseline_y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


static func text_width(text: String, font: Font, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Readable ink for text sitting on an arbitrary team colour.
static func on_colour(background: Color) -> Color:
	return INK if background.get_luminance() > 0.55 else TEXT


static func button(text: String, scale: float = 1.0) -> Button:
	var result := Button.new()
	result.text = text
	result.add_theme_font_override("font", display_font())
	result.add_theme_font_size_override("font_size", size(HEAD, scale))
	result.add_theme_color_override("font_color", TEXT)
	result.add_theme_color_override("font_hover_color", TEXT)
	result.add_theme_color_override("font_focus_color", TEXT)
	result.add_theme_color_override("font_disabled_color", TEXT_DIM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = SURFACE_HI if state in ["hover", "pressed"] else Color(INK, 0.25)
		style.border_color = ORANGE if state == "focus" else LINE
		style.border_width_bottom = 2 if state == "focus" else 1
		style.content_margin_left = 12.0 * scale
		style.content_margin_right = 12.0 * scale
		style.content_margin_top = 6.0 * scale
		style.content_margin_bottom = 6.0 * scale
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
		result.add_theme_stylebox_override(state, style)
	return result
