class_name MatchHud
extends Control

# Broadcast score bug, shot clock, shot meter and call-outs. Everything is
# drawn rather than built from nodes so the layout can scale off one factor and
# stay pixel-consistent at any window size.

const BANNER_HOLD := 1.5
const RELEASE_HOLD := 0.85
const BANNER_FADE := 0.45
const BUG_WIDTH := 620.0
const BUG_HEIGHT := 76.0
const TEAM_BLOCK := 214.0
const SHOT_CLOCK_BLOCK := Vector2(104.0, 36.0)
const METER_SIZE := Vector2(300.0, 20.0)
const URGENT_SHOT_CLOCK := 5.0

var match_scene: Node

var _banner_text := ""
var _banner_time := 0.0
var _release_time := 0.0
var _release_charge := 0.0
var _release_verdict := ""
var _was_charging := false
var _banner_loud := false
var _final: Dictionary = {}


func bind(scene: Node) -> void:
	match_scene = scene
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func announce(text: String, loud: bool) -> void:
	_banner_text = text
	_banner_loud = loud
	_banner_time = BANNER_HOLD


func show_final(result: Dictionary) -> void:
	_final = result


func _process(delta: float) -> void:
	_banner_time = maxf(0.0, _banner_time - delta)
	_release_time = maxf(0.0, _release_time - delta)
	_watch_release()
	queue_redraw()


func _draw() -> void:
	if match_scene == null:
		return
	var scale := UiTheme.scale_for(size)
	_draw_score_bug(scale)
	_draw_shot_meter(scale)
	if _banner_time > 0.0:
		_draw_banner(scale)
	if not _final.is_empty():
		_draw_final(scale)


func _draw_score_bug(scale: float) -> void:
	var clock: MatchClock = match_scene.clock
	var box: BoxScore = match_scene.box
	var setup: MatchSetup = match_scene.setup
	var possession: int = match_scene.ctx.possession

	var bug := Rect2(
		Vector2(size.x * 0.5 - BUG_WIDTH * scale * 0.5, UiTheme.XXL * scale),
		Vector2(BUG_WIDTH, BUG_HEIGHT) * scale)
	UiTheme.panel(self, bug, UiTheme.SURFACE, 0.94)

	var block := TEAM_BLOCK * scale
	_draw_team_block(Rect2(bug.position, Vector2(block, bug.size.y)),
		setup.home, box.team_points[0], possession == 0, false, scale)
	_draw_team_block(Rect2(Vector2(bug.end.x - block, bug.position.y),
		Vector2(block, bug.size.y)),
		setup.away, box.team_points[1], possession == 1, true, scale)

	# Divider rules either side of the clock column.
	for x in [bug.position.x + block, bug.end.x - block]:
		draw_line(Vector2(x, bug.position.y + UiTheme.S * scale),
			Vector2(x, bug.end.y - UiTheme.S * scale), UiTheme.LINE, UiTheme.HAIRLINE)

	var centre_x := bug.position.x + bug.size.x * 0.5
	UiTheme.label_centred(self, clock.period_name(), centre_x,
		bug.position.y + 26.0 * scale, UiTheme.bold_font(),
		UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)
	UiTheme.label_centred(self, clock.format_remaining(), centre_x,
		bug.position.y + 62.0 * scale, UiTheme.display_font(),
		UiTheme.size(UiTheme.HEAD, scale), UiTheme.TEXT)

	_draw_shot_clock(bug, centre_x, clock, scale)


func _draw_team_block(rect: Rect2, team: Dictionary, points: int,
		has_ball: bool, mirrored: bool, scale: float) -> void:
	var colour := Color(team["primary"])
	var chip_width := 6.0 * scale
	var chip_x := rect.end.x - chip_width if mirrored else rect.position.x
	UiTheme.team_chip(self, Rect2(Vector2(chip_x, rect.position.y),
		Vector2(chip_width, rect.size.y)), colour.lightened(0.12))

	var pad := UiTheme.L * scale + chip_width
	var abbr_size := UiTheme.size(UiTheme.SUB, scale)
	var score_size := UiTheme.size(UiTheme.TITLE, scale)
	var abbr := String(team["abbr"])
	var score := str(points)

	if mirrored:
		UiTheme.label_right(self, abbr, rect.end.x - pad,
			rect.position.y + 32.0 * scale, UiTheme.display_font(), abbr_size,
			UiTheme.TEXT_DIM)
		UiTheme.label(self, score, Vector2(rect.position.x + UiTheme.L * scale,
			rect.position.y + 58.0 * scale), UiTheme.display_font(), score_size,
			UiTheme.TEXT)
	else:
		UiTheme.label(self, abbr, Vector2(rect.position.x + pad,
			rect.position.y + 32.0 * scale), UiTheme.display_font(), abbr_size,
			UiTheme.TEXT_DIM)
		UiTheme.label_right(self, score, rect.end.x - UiTheme.L * scale,
			rect.position.y + 58.0 * scale, UiTheme.display_font(), score_size,
			UiTheme.TEXT)

	if has_ball:
		# Possession reads as a lit bar under the team that has the ball.
		UiTheme.accent_edge(self, rect, colour.lightened(0.25), 3.0 * scale)


func _draw_shot_clock(bug: Rect2, centre_x: float, clock: MatchClock,
		scale: float) -> void:
	var block := SHOT_CLOCK_BLOCK * scale
	var rect := Rect2(Vector2(centre_x - block.x * 0.5, bug.end.y), block)
	var urgent := clock.shot_clock < URGENT_SHOT_CLOCK
	UiTheme.panel(self, rect, UiTheme.SURFACE_HI, 0.94)
	if urgent:
		UiTheme.accent_edge(self, rect, UiTheme.RED, 3.0 * scale)
	UiTheme.label_centred(self, "%02d" % int(ceilf(clock.shot_clock)), centre_x,
		rect.position.y + 28.0 * scale, UiTheme.display_font(),
		UiTheme.size(UiTheme.SUB, scale) + 4,
		UiTheme.RED if urgent else UiTheme.GOLD)


func _human_pawn() -> PlayerPawn:
	var humans: Array = match_scene.humans
	if humans.is_empty():
		return null
	return humans[0].active


# The meter used to vanish on the same frame as the release, so a player never
# saw where their own shot landed on it and had no way to learn the timing.
func _watch_release() -> void:
	var pawn := _human_pawn()
	var charging := pawn != null and pawn.state == PlayerPawn.State.SHOOT \
		and not pawn.shot_released_this_attempt and pawn.shot_charge > 0.0
	if _was_charging and not charging and pawn != null:
		_release_charge = pawn.shot_charge
		_release_verdict = _verdict_for(pawn.shot_charge)
		_release_time = RELEASE_HOLD
	_was_charging = charging


func _verdict_for(charge: float) -> String:
	var window := PlayerPawn.IDEAL_RELEASE
	if charge < window.x:
		return "EARLY"
	if charge > window.y:
		return "LATE"
	var centre := (window.x + window.y) * 0.5
	var half := (window.y - window.x) * 0.5
	if absf(charge - centre) < half * 0.45:
		return "PERFECT"
	return "GOOD"


func _draw_shot_meter(scale: float) -> void:
	if not bool(Settings.get_value("shot_meter_visible")):
		return
	var pawn := _human_pawn()
	if pawn == null:
		return
	var charging := pawn.state == PlayerPawn.State.SHOOT \
		and not pawn.shot_released_this_attempt and pawn.shot_charge > 0.0
	if not charging and _release_time <= 0.0:
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
	var inside := charge >= PlayerPawn.IDEAL_RELEASE.x \
		and charge <= PlayerPawn.IDEAL_RELEASE.y
	var bar := UiTheme.GREEN if inside else UiTheme.TEXT
	bar.a = alpha
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), bar)

	if not charging:
		var mark_x := rect.position.x + rect.size.x * fill
		draw_line(Vector2(mark_x, rect.position.y - 4.0 * scale),
			Vector2(mark_x, rect.end.y + 4.0 * scale),
			Color(UiTheme.TEXT, alpha), 2.0 * scale)
		var word := UiTheme.GREEN if inside else UiTheme.TEXT
		word.a = alpha
		UiTheme.label_centred(self, _release_verdict, rect.get_center().x,
			rect.position.y - UiTheme.M * scale, UiTheme.display_font(),
			UiTheme.size(UiTheme.BODY, scale), word)

	var edge := UiTheme.LINE
	edge.a = alpha
	draw_rect(rect, edge, false, UiTheme.HAIRLINE)


func _draw_banner(scale: float) -> void:
	var alpha := clampf(_banner_time / BANNER_FADE, 0.0, 1.0)
	var font := UiTheme.display_font()
	var font_size := UiTheme.size(UiTheme.DISPLAY if _banner_loud
		else UiTheme.HEAD, scale)
	var colour := UiTheme.GOLD if _banner_loud else UiTheme.TEXT
	colour.a = alpha

	var width := UiTheme.text_width(_banner_text, font, font_size)
	var centre_x := size.x * 0.5
	var baseline := size.y * 0.30
	var pad := UiTheme.L * scale
	var backing := Rect2(Vector2(centre_x - width * 0.5 - pad * 1.5,
		baseline - float(font_size) - pad * 0.4),
		Vector2(width + pad * 3.0, float(font_size) + pad * 1.2))
	var backing_colour := UiTheme.INK
	backing_colour.a = 0.72 * alpha
	draw_rect(backing, backing_colour)
	UiTheme.accent_edge(self, backing, Color(colour, alpha * 0.9), 3.0 * scale)
	UiTheme.label_centred(self, _banner_text, centre_x, baseline, font, font_size, colour)


func _draw_final(scale: float) -> void:
	var setup: MatchSetup = match_scene.setup
	var panel := Rect2(
		Vector2(size.x * 0.5 - 300.0 * scale, size.y * 0.5 - 160.0 * scale),
		Vector2(600.0, 320.0) * scale)
	UiTheme.panel(self, panel, UiTheme.SURFACE, 0.97)
	UiTheme.accent_edge(self, panel, UiTheme.ORANGE, 4.0 * scale)

	var centre_x := panel.position.x + panel.size.x * 0.5
	UiTheme.label_centred(self, "FINAL", centre_x, panel.position.y + 56.0 * scale,
		UiTheme.display_font(), UiTheme.size(UiTheme.HEAD, scale), UiTheme.TEXT_DIM)

	var rows := [
		[String(setup.home["abbr"]), int(_final["home_score"]), Color(setup.home["primary"])],
		[String(setup.away["abbr"]), int(_final["away_score"]), Color(setup.away["primary"])],
	]
	var winner: int = 0 if int(_final["home_score"]) > int(_final["away_score"]) else 1
	for i in rows.size():
		var row: Array = rows[i]
		var y := panel.position.y + (130.0 + float(i) * 74.0) * scale
		UiTheme.team_chip(self, Rect2(Vector2(panel.position.x + UiTheme.XL * scale,
			y - 30.0 * scale), Vector2(6.0 * scale, 40.0 * scale)), row[2])
		var tint: Color = UiTheme.TEXT if i == winner else UiTheme.TEXT_DIM
		UiTheme.label(self, row[0],
			Vector2(panel.position.x + UiTheme.HUGE * scale, y),
			UiTheme.display_font(), UiTheme.size(UiTheme.HEAD, scale), tint)
		UiTheme.label_right(self, str(row[1]), panel.end.x - UiTheme.XL * scale, y,
			UiTheme.display_font(), UiTheme.size(UiTheme.TITLE, scale),
			UiTheme.GOLD if i == winner else UiTheme.TEXT_DIM)

	UiTheme.label_centred(self, "PRESS ESC TO CONTINUE", centre_x,
		panel.end.y - UiTheme.XL * scale, UiTheme.bold_font(),
		UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)
