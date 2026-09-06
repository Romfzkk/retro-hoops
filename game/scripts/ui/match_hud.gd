class_name MatchHud
extends Control

# Scoreboard, shot clock, shot meter and the banner that calls out plays.

const BANNER_TIME := 1.6

var match_scene: Node
var _banner_text := ""
var _banner_time := 0.0
var _banner_loud := false
var _final: Dictionary = {}


func bind(scene: Node) -> void:
	match_scene = scene
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func announce(text: String, loud: bool) -> void:
	_banner_text = text
	_banner_loud = loud
	_banner_time = BANNER_TIME


func show_final(result: Dictionary) -> void:
	_final = result


func _process(delta: float) -> void:
	_banner_time = maxf(0.0, _banner_time - delta)
	queue_redraw()


func _draw() -> void:
	if match_scene == null:
		return
	var font := ThemeDB.fallback_font
	var clock: MatchClock = match_scene.clock
	var box: BoxScore = match_scene.box
	var setup: MatchSetup = match_scene.setup

	var bar := Rect2(size.x * 0.5 - 240.0, 18.0, 480.0, 62.0)
	draw_rect(bar, Color(0.05, 0.06, 0.09, 0.85))
	draw_rect(bar, Color(1, 1, 1, 0.12), false, 2.0)

	_text(font, String(setup.home["abbr"]), bar.position + Vector2(18.0, 30.0), 22,
		Color(setup.home["primary"]).lightened(0.35))
	_text(font, str(box.team_points[0]), bar.position + Vector2(96.0, 34.0), 30, Color.WHITE)
	_text(font, String(setup.away["abbr"]), bar.position + Vector2(bar.size.x - 96.0, 30.0),
		22, Color(setup.away["primary"]).lightened(0.35))
	_text(font, str(box.team_points[1]), bar.position + Vector2(bar.size.x - 130.0, 34.0),
		30, Color.WHITE)
	_text(font, clock.period_name(), bar.position + Vector2(bar.size.x * 0.5 - 14.0, 24.0),
		16, Color(0.75, 0.78, 0.85))
	_text(font, clock.format_remaining(),
		bar.position + Vector2(bar.size.x * 0.5 - 28.0, 50.0), 22, Color.WHITE)
	_text(font, "%02d" % int(ceilf(clock.shot_clock)),
		bar.position + Vector2(bar.size.x * 0.5 - 14.0, 84.0), 24,
		Color(1.0, 0.45, 0.25) if clock.shot_clock < 5.0 else Color(0.9, 0.9, 0.95))

	_draw_shot_meter()

	if _banner_time > 0.0:
		var alpha := clampf(_banner_time / 0.4, 0.0, 1.0)
		var colour := Color(1.0, 0.78, 0.25, alpha) if _banner_loud \
			else Color(1, 1, 1, alpha * 0.9)
		var font_size := 44 if _banner_loud else 26
		var width := font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1,
			font_size).x
		_text(font, _banner_text,
			Vector2(size.x * 0.5 - width * 0.5, size.y * 0.28), font_size, colour)

	if not _final.is_empty():
		_draw_final(font)


func _draw_shot_meter() -> void:
	if not bool(Settings.get_value("shot_meter_visible")):
		return
	var humans: Array = match_scene.humans
	if humans.is_empty() or humans[0].active == null:
		return
	var pawn: PlayerPawn = humans[0].active
	if pawn.state != PlayerPawn.State.SHOOT or pawn.shot_released_this_attempt:
		return

	var width := 220.0
	var origin := Vector2(size.x * 0.5 - width * 0.5, size.y - 96.0)
	draw_rect(Rect2(origin, Vector2(width, 16.0)), Color(0.06, 0.07, 0.1, 0.85))
	var window := Rect2(origin + Vector2(width * PlayerPawn.IDEAL_RELEASE.x
		/ PlayerPawn.OVERCHARGE, 0.0),
		Vector2(width * (PlayerPawn.IDEAL_RELEASE.y - PlayerPawn.IDEAL_RELEASE.x)
		/ PlayerPawn.OVERCHARGE, 16.0))
	draw_rect(window, Color(0.35, 0.9, 0.45, 0.55))
	var fill := clampf(pawn.shot_charge / PlayerPawn.OVERCHARGE, 0.0, 1.0)
	draw_rect(Rect2(origin, Vector2(width * fill, 16.0)), Color(0.95, 0.95, 1.0, 0.9))
	draw_rect(Rect2(origin, Vector2(width, 16.0)), Color(1, 1, 1, 0.25), false, 2.0)


func _draw_final(font: Font) -> void:
	var panel := Rect2(size.x * 0.5 - 260.0, size.y * 0.5 - 110.0, 520.0, 220.0)
	draw_rect(panel, Color(0.04, 0.05, 0.08, 0.94))
	draw_rect(panel, Color(1, 1, 1, 0.18), false, 2.0)
	var setup: MatchSetup = match_scene.setup
	_text(font, "FINAL", panel.position + Vector2(232.0, 44.0), 24, Color(0.8, 0.82, 0.9))
	_text(font, "%s  %d" % [String(setup.home["abbr"]), int(_final["home_score"])],
		panel.position + Vector2(60.0, 110.0), 34, Color.WHITE)
	_text(font, "%s  %d" % [String(setup.away["abbr"]), int(_final["away_score"])],
		panel.position + Vector2(60.0, 160.0), 34, Color.WHITE)


func _text(font: Font, value: String, at: Vector2, font_size: int, colour: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
