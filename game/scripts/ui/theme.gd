class_name UiTheme
extends RefCounted

# The whole interface is drawn in code, so the design system lives here rather
# than in a .tres: one palette, one type scale, one spacing ramp.
#
# Direction is broadcast graphics - hard-edged blocks, condensed display type,
# tabular numbers, colour used for state rather than decoration. Surfaces are
# dark because the UI sits over a brightly lit court and has to stay readable
# without dimming the game.

const DISPLAY_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"
const TEXT_FONT := "res://assets/fonts/Barlow-Regular.ttf"
const TEXT_FONT_BOLD := "res://assets/fonts/Barlow-SemiBold.ttf"

# --- palette --------------------------------------------------------------
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

# --- type scale -----------------------------------------------------------
# Authored against a 1080p-tall viewport and scaled from there.
const REFERENCE_HEIGHT := 1080.0
const DISPLAY := 72
const TITLE := 44
const HEAD := 30
const SUB := 21
const BODY := 17
const LABEL := 14
const MICRO := 12

# --- spacing --------------------------------------------------------------
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
	return clampf(viewport_size.y / REFERENCE_HEIGHT, 0.62, 1.9)


static func size(base: int, scale: float) -> int:
	return int(round(float(base) * scale))


# --- drawing helpers ------------------------------------------------------

## Flat block with a hairline edge. No rounded corners anywhere: the hard edge
## is what makes it read as a broadcast graphic rather than a phone app.
static func panel(canvas: CanvasItem, rect: Rect2, fill: Color = SURFACE,
		opacity: float = 0.92) -> void:
	var body := fill
	body.a = opacity
	canvas.draw_rect(rect, body)
	canvas.draw_rect(rect, LINE, false, HAIRLINE)


static func accent_edge(canvas: CanvasItem, rect: Rect2, colour: Color,
		thickness: float = ACCENT_BAR) -> void:
	canvas.draw_rect(Rect2(rect.position.x, rect.end.y - thickness,
		rect.size.x, thickness), colour)


static func team_chip(canvas: CanvasItem, rect: Rect2, colour: Color) -> void:
	canvas.draw_rect(rect, colour)


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
