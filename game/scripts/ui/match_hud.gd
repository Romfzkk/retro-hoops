class_name MatchHud
extends Control

signal pause_requested()
signal continue_requested()

const BANNER_HOLD := 1.5
const RELEASE_HOLD := 2.2
const BANNER_FADE := 0.45
const METER_SIZE := Vector2(300.0, 20.0)

var match_scene: Node

var _banner_text := ""
var _banner_time := 0.0
var _release_time := 0.0
var _release_charge := 0.0
var _release_verdict := ""
var _banner_loud := false
var _final: Dictionary = {}
var _score_panel: PanelContainer
var _score_line: HBoxContainer
var _home_score: Label
var _away_score: Label
var _clock: Label
var _phase: Label
var _shot_clock: Label
var _player: Label
var _stamina: ProgressBar
var _feedback: Label
var _pause: Button
var _continue: Button
var _banner: Label
var _final_panel: PanelContainer
var _final_text: Label
var _feedback_text := ""
var _release_has_meter := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_score_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.INK, 0.96)
	style.border_color = UiTheme.LINE
	style.border_width_bottom = 2
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	_score_panel.add_theme_stylebox_override("panel", style)
	add_child(_score_panel)
	_score_line = HBoxContainer.new()
	_score_line.add_theme_constant_override("separation", 20)
	_score_panel.add_child(_score_line)
	_home_score = _label(_score_line, UiTheme.display_font())
	_clock = _label(_score_line, UiTheme.display_font())
	_away_score = _label(_score_line, UiTheme.display_font())
	_phase = _label(self, UiTheme.bold_font())
	_shot_clock = _label(self, UiTheme.display_font())
	_player = _label(self, UiTheme.bold_font())
	_feedback = _label(self, UiTheme.bold_font())
	_banner = _label(self, UiTheme.display_font())
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.max_value = 1.0
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.LINE
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.ORANGE
	_stamina.add_theme_stylebox_override("background", track)
	_stamina.add_theme_stylebox_override("fill", fill)
	add_child(_stamina)
	_pause = UiTheme.button("PAUSE")
	_pause.pressed.connect(func(): pause_requested.emit())
	add_child(_pause)
	_final_panel = PanelContainer.new()
	_final_panel.add_theme_stylebox_override("panel", style.duplicate())
	add_child(_final_panel)
	var final_column := VBoxContainer.new()
	final_column.add_theme_constant_override("separation", 20)
	_final_panel.add_child(final_column)
	_final_text = _label(final_column, UiTheme.display_font())
	_continue = UiTheme.button("VIEW BOX SCORE")
	_continue.custom_minimum_size.y = 56.0
	_continue.pressed.connect(func(): continue_requested.emit())
	final_column.add_child(_continue)
	_final_panel.hide()


func _label(parent: Node, font: Font) -> Label:
	var result := Label.new()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_override("font", font)
	result.add_theme_color_override("font_color", UiTheme.TEXT)
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


func bind(scene: Node) -> void:
	match_scene = scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func announce(text: String, loud: bool) -> void:
	_banner_text = text
	_banner_loud = loud
	_banner_time = BANNER_HOLD


func show_final(result: Dictionary) -> void:
	_final = result
	_final_panel.show()
	_continue.grab_focus()


func _process(delta: float) -> void:
	_banner_time = maxf(0.0, _banner_time - delta)
	_release_time = maxf(0.0, _release_time - delta)
	_update_labels()
	queue_redraw()


func _draw() -> void:
	if match_scene == null:
		return
	var scale := UiTheme.scale_for(size)
	_draw_shot_meter(scale)


func _update_labels() -> void:
	if match_scene == null:
		return
	var scale := UiTheme.scale_for(size)
	var clock: MatchClock = match_scene.clock
	var box: BoxScore = match_scene.box
	var setup: MatchSetup = match_scene.setup
	var width := minf(700.0 * scale, size.x - 32.0)
	_score_panel.position = Vector2((size.x - width) * 0.5, 20.0 * scale)
	_score_panel.size = Vector2(width, 82.0 * scale)
	_home_score.text = "%s  %d" % [setup.home["abbr"], box.team_points[0]]
	_away_score.text = "%d  %s" % [box.team_points[1], setup.away["abbr"]]
	_clock.text = "%s\n%s" % [clock.period_name(), clock.format_remaining()]
	for label in [_home_score, _away_score]:
		label.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.TITLE, scale))
	_clock.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.HEAD, scale))
	var state_y := _score_panel.position.y + _score_panel.size.y + 4.0
	_phase.text = _phase_text()
	_place_label(_phase, Vector2(size.x * 0.5 - width * 0.5, state_y), Vector2(width, 28.0), UiTheme.size(UiTheme.LABEL, scale))
	_shot_clock.text = "SHOT %02d" % int(ceilf(clock.shot_clock))
	if clock.shot_in_flight and clock.shot_clock <= 0.0:
		_shot_clock.text = "IN AIR"
	_shot_clock.visible = match_scene.ctx.is_live() and not match_scene._period_pending
	_place_label(_shot_clock, Vector2(size.x * 0.5 - 80.0, state_y + 28.0), Vector2(160.0, 28.0), UiTheme.size(UiTheme.SUB, scale))
	_shot_clock.add_theme_color_override("font_color", UiTheme.RED if clock.shot_clock < 5.0 and not clock.shot_in_flight else UiTheme.GOLD)
	_pause.position = Vector2(size.x - 110.0 * scale - 20.0, 22.0 * scale)
	_pause.size = Vector2(110.0 * scale, 48.0 * scale)
	_pause.visible = _final.is_empty()
	# At narrow sizes keep pause below the score instead of covering a team.
	if _pause.position.x < _score_panel.position.x + _score_panel.size.x + 12.0:
		_pause.position.y = state_y + 36.0
	var pawn := _human_pawn()
	_player.visible = pawn != null and _final.is_empty()
	_stamina.visible = _player.visible
	if pawn != null:
		_player.text = "#%d  %s  |  %s" % [pawn.data["num"], League.short_name(pawn.data), League.POS_NAMES[int(pawn.data["pos"])]]
		_stamina.value = pawn.stamina
	_place_label(_player, Vector2(size.x * 0.5 - 230.0 * scale, size.y - 76.0 * scale), Vector2(460.0 * scale, 32.0 * scale), UiTheme.size(UiTheme.BODY, scale))
	_stamina.position = Vector2(size.x * 0.5 - 100.0 * scale, size.y - 36.0 * scale)
	_stamina.size = Vector2(200.0 * scale, 4.0)
	_feedback.visible = _release_time > 0.0 and _final.is_empty()
	_feedback.text = _feedback_text
	_place_label(_feedback, Vector2(size.x * 0.5 - 280.0 * scale, size.y - 166.0 * scale), Vector2(560.0 * scale, 32.0 * scale), UiTheme.size(UiTheme.LABEL, scale))
	_banner.text = _banner_text
	_banner.visible = _banner_time > 0.0 and _final.is_empty()
	_banner.modulate.a = clampf(_banner_time / BANNER_FADE, 0.0, 1.0)
	_place_label(_banner, Vector2(24.0, size.y * 0.27), Vector2(size.x - 48.0, 66.0 * scale), UiTheme.size(UiTheme.TITLE if _banner_loud else UiTheme.HEAD, scale))
	if not _final.is_empty():
		_final_panel.position = Vector2(size.x * 0.5 - width * 0.5, size.y * 0.32)
		_final_panel.size = Vector2(width, 230.0 * scale)
		_final_text.text = "FINAL\n%s  %d : %d  %s" % [setup.home["abbr"], box.team_points[0], box.team_points[1], setup.away["abbr"]]
		_final_text.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.TITLE, scale))


func _place_label(label: Label, position_: Vector2, size_: Vector2, font_size: int) -> void:
	label.position = position_
	label.size = size_
	label.add_theme_font_size_override("font_size", font_size)


func _phase_text() -> String:
	var ctx: MatchContext = match_scene.ctx
	if match_scene._period_pending and ctx.phase != MatchContext.Phase.FREE_THROW:
		return "HORN | WAITING FOR SHOT"
	match ctx.phase:
		MatchContext.Phase.TIPOFF: return "OPENING TIP"
		MatchContext.Phase.SHOT_IN_FLIGHT: return "SHOT IN FLIGHT"
		MatchContext.Phase.LOOSE_BALL: return "LOOSE BALL"
		MatchContext.Phase.DEAD, MatchContext.Phase.INBOUND: return "DEAD BALL"
		MatchContext.Phase.FREE_THROW:
			var sequence: Dictionary = match_scene._free_throws
			var total := int(sequence.get("total", 1))
			return "FREE THROW %d / %d" % [total - int(sequence.get("remaining", 1)) + 1, total]
		MatchContext.Phase.OVER: return "FINAL"
	var team: Dictionary = match_scene.setup.home if ctx.possession == 0 else match_scene.setup.away
	return "%s BALL" % team["abbr"]


func _human_pawn() -> PlayerPawn:
	var humans: Array = match_scene.humans
	if humans.is_empty():
		return null
	return humans[0].active


func record_release(pawn: PlayerPawn) -> void:
	if not pawn.is_user_controlled:
		return
	_release_charge = pawn.last_release_charge
	_release_has_meter = pawn.last_shot_kind in ["JUMPER", "FREE THROW"]
	_release_verdict = pawn.last_shot_kind
	if _release_has_meter:
		_release_verdict = "ASSISTED" if int(Settings.get_value("shot_style")) == Settings.ShotStyle.AUTO else _verdict_for(_release_charge)
	var contest := ShotSolver.contest_level(pawn.global_position, pawn.rig.shoulder_height, pawn.opponents)
	var pressure := "OPEN" if contest < 0.2 else ("CONTESTED" if contest < 0.6 else "HEAVILY CONTESTED")
	_feedback_text = "%s | %s | %.1f m" % [_release_verdict, pressure, pawn.distance_to_rim()]
	_release_time = RELEASE_HOLD


func _verdict_for(charge: float) -> String:
	var window := PlayerPawn.IDEAL_RELEASE
	if charge < window.x:
		return "EARLY"
	if charge > window.y:
		return "LATE"
	var centre := (window.x + window.y) * 0.5
	var half := (window.y - window.x) * 0.5
	if absf(charge - centre) < half * 0.45:
		return "CLEAN TIMING"
	return "GOOD TIMING"


func _draw_shot_meter(scale: float) -> void:
	if not _final.is_empty() or not bool(Settings.get_value("shot_meter_visible")) or int(Settings.get_value("shot_style")) == Settings.ShotStyle.AUTO:
		return
	var pawn := _human_pawn()
	if pawn == null:
		return
	var charging := pawn.state == PlayerPawn.State.SHOOT \
		and not pawn.shot_released_this_attempt and pawn.shot_charge > 0.0
	if not charging and (_release_time <= 0.0 or not _release_has_meter):
		return
	var charge: float = pawn.shot_charge if charging else _release_charge
	var alpha := 1.0 if charging else clampf(_release_time / RELEASE_HOLD, 0.0, 1.0)

	var meter := METER_SIZE * scale
	var rect := Rect2(Vector2(size.x * 0.5 - meter.x * 0.5,
		size.y - 120.0 * scale), meter)
	UiTheme.panel(self, rect, UiTheme.INK, 0.88 * alpha)

	# Green window is the release you are aiming for.
	var span := PlayerPawn.OVERCHARGE
	var window := Rect2(
		Vector2(rect.position.x + rect.size.x * PlayerPawn.IDEAL_RELEASE.x / span,
			rect.position.y),
		Vector2(rect.size.x * (PlayerPawn.IDEAL_RELEASE.y
			- PlayerPawn.IDEAL_RELEASE.x) / span, rect.size.y))
	var window_fill := UiTheme.GREEN
	window_fill.a = 0.55 * alpha
	draw_rect(window, window_fill)

	var fill := clampf(charge / span, 0.0, 1.0)
	var mark_x := rect.position.x + rect.size.x * fill
	draw_line(Vector2(mark_x, rect.position.y - 4.0 * scale),
		Vector2(mark_x, rect.end.y + 4.0 * scale), Color(UiTheme.TEXT, alpha), 3.0 * scale)

	var edge := UiTheme.LINE
	edge.a = alpha
	draw_rect(rect, edge, false, UiTheme.HAIRLINE)
