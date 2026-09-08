extends MenuScreen

const CAMERA_NAMES := ["BROADCAST", "BEHIND", "HIGH", "COURTSIDE", "BASELINE"]
const SHOT_STYLE_NAMES := ["TIMING", "ASSISTED"]
const SHOT_STYLES := [Settings.ShotStyle.HYBRID, Settings.ShotStyle.AUTO]
const DIFFICULTY_NAMES := ["ROOKIE", "PRO", "ALL-STAR", "LEGEND"]
const TOUCH_NAMES := ["AUTO", "ALWAYS", "NEVER"]



func _ready() -> void:
	super()
	title = "OPTIONS"
	subtitle = "Saved as you change them"
	footer = "Change  A/D    Back  Esc"
	chosen.connect(func(id): on_adjust(id, 1))
	cancelled.connect(func(): Game.goto("res://scenes/main_menu.tscn"))
	_refresh()


func _refresh() -> void:
	rows = [
		{"id": "camera", "label": "CAMERA",
			"value": CAMERA_NAMES[int(Settings.get_value("camera_mode"))]},
		{"id": "shot_style", "label": "SHOT STYLE",
			"value": SHOT_STYLE_NAMES[1 if int(Settings.get_value("shot_style")) == Settings.ShotStyle.AUTO else 0]},
		{"id": "meter", "label": "SHOT METER",
			"value": _on_off(Settings.get_value("shot_meter_visible"))},
		{"id": "difficulty", "label": "DIFFICULTY",
			"value": DIFFICULTY_NAMES[int(Settings.get_value("difficulty"))]},
		{"id": "minutes", "label": "QUARTER LENGTH",
			"value": "%d MIN" % int(Settings.get_value("quarter_minutes"))},
		{"id": "fullscreen", "label": "FULLSCREEN",
			"value": _on_off(Settings.get_value("fullscreen"))},
		{"id": "shadows", "label": "SHADOWS",
			"value": _on_off(Settings.get_value("shadows"))},
		{"id": "touch", "label": "TOUCH CONTROLS",
			"value": TOUCH_NAMES[int(Settings.get_value("touch_controls"))]},
		{"id": "master", "label": "MASTER VOLUME",
			"value": _percent(Settings.get_value("master_volume"))},
		{"id": "sfx", "label": "EFFECTS", "value": _percent(Settings.get_value("sfx_volume"))},
		{"id": "music", "label": "MUSIC", "value": _percent(Settings.get_value("music_volume"))},
	]


func on_adjust(id: String, step: int) -> void:
	match id:
		"camera":
			_cycle("camera_mode", step, CAMERA_NAMES.size())
		"shot_style":
			var current := 1 if int(Settings.get_value("shot_style")) == Settings.ShotStyle.AUTO else 0
			Settings.set_value("shot_style", SHOT_STYLES[wrapi(current + step, 0, 2)])
		"meter":
			Settings.set_value("shot_meter_visible", not Settings.get_value("shot_meter_visible"))
		"difficulty":
			_cycle("difficulty", step, DIFFICULTY_NAMES.size())
		"minutes":
			Settings.set_value("quarter_minutes",
				clampi(int(Settings.get_value("quarter_minutes")) + step, 1, 12))
		"fullscreen":
			Settings.set_value("fullscreen", not Settings.get_value("fullscreen"))
			Settings.apply_window()
		"shadows":
			Settings.set_value("shadows", not Settings.get_value("shadows"))
		"touch":
			_cycle("touch_controls", step, TOUCH_NAMES.size())
		"master":
			_nudge("master_volume", step)
		"sfx":
			_nudge("sfx_volume", step)
		"music":
			_nudge("music_volume", step)
	_refresh()


func _cycle(key: String, step: int, count: int) -> void:
	Settings.set_value(key, wrapi(int(Settings.get_value(key)) + step, 0, count))


func _nudge(key: String, step: int) -> void:
	Settings.set_value(key, snappedf(clampf(float(Settings.get_value(key))
		+ float(step) * 0.05, 0.0, 1.0), 0.05))


func _on_off(value: Variant) -> String:
	return "ON" if bool(value) else "OFF"


func _percent(value: Variant) -> String:
	return "%d%%" % int(round(float(value) * 100.0))


func _draw_side_panel(scale: float) -> void:
	if rows.is_empty():
		return
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.78)
	var pad := UiTheme.XL * scale
	var id := String(rows[selected]["id"])

	UiTheme.label(self, String(rows[selected]["label"]),
		Vector2(rect.position.x + pad, rect.position.y + 52.0 * scale),
		UiTheme.display_font(), UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)

	var help := _help_for(id)
	var y := rect.position.y + 92.0 * scale
	for line in _wrap(help, rect.size.x - pad * 2.0, scale):
		UiTheme.label(self, line, Vector2(rect.position.x + pad, y),
			UiTheme.text_font(), UiTheme.size(UiTheme.BODY, scale), UiTheme.TEXT_DIM)
		y += 26.0 * scale


func _help_for(id: String) -> String:
	match id:
		"shot_style":
			return "Timing: hold to gather, then release in the green window. Assisted: ratings set release quality. Close finishes use positioning and reach."
		"camera":
			return "Broadcast follows the ball from the sideline. Behind sits over the shoulder of the player you control."
		"difficulty":
			return "Raises CPU pressure and makes shooting less forgiving for both teams."
		"touch":
			return "Auto shows the on-screen stick only on phones and tablets."
		"shadows":
			return "Turning shadows off is the cheapest win on older hardware."
	return "Applies immediately and is written to your settings file."


func _wrap(text: String, width: float, scale: float) -> Array[String]:
	var font := UiTheme.text_font()
	var font_size := UiTheme.size(UiTheme.BODY, scale)
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" "):
		var candidate := word if current.is_empty() else current + " " + word
		if UiTheme.text_width(candidate, font, font_size) > width and not current.is_empty():
			lines.append(current)
			current = word
		else:
			current = candidate
	if not current.is_empty():
		lines.append(current)
	return lines
