class_name CourtSurface
extends Control

# Draws the whole floor - boards, paint, markings, centre logo - into an
# offscreen viewport once at load. Baking it beats laying decal geometry over
# the floor: no z-fighting, and the lines stay sharp from any camera height.

const PIXELS_PER_METRE := 64.0
const FLOOR_LENGTH := 34.0
const FLOOR_WIDTH := 20.0
const TEXTURE_SIZE := Vector2i(int(FLOOR_LENGTH * PIXELS_PER_METRE),
	int(FLOOR_WIDTH * PIXELS_PER_METRE))

const PLANK_WIDTH_M := 0.24
const LINE_PX := CourtMetrics.LINE_WIDTH * PIXELS_PER_METRE

var team: Dictionary
var arena: Dictionary
var rng := RandomNumberGenerator.new()


static func render_to_texture(parent: Node, team_data: Dictionary,
		arena_data: Dictionary, seed_value: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = TEXTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	var surface := CourtSurface.new()
	surface.team = team_data
	surface.arena = arena_data
	surface.rng.seed = seed_value
	surface.size = Vector2(TEXTURE_SIZE)
	viewport.add_child(surface)
	parent.add_child(viewport)
	return viewport


func to_px(x: float, z: float) -> Vector2:
	return Vector2(TEXTURE_SIZE.x * 0.5 + x * PIXELS_PER_METRE,
		TEXTURE_SIZE.y * 0.5 + z * PIXELS_PER_METRE)


func _draw() -> void:
	_draw_apron()
	_draw_boards()
	_draw_paint()
	_draw_centre_logo()
	_draw_markings()


func _draw_apron() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(TEXTURE_SIZE)), Color(arena["wall"]).lightened(0.1))
	var accent := Color(team["accent"])
	var apron := _court_rect().grow(1.4 * PIXELS_PER_METRE)
	draw_rect(apron, accent)


func _draw_boards() -> void:
	var base := Color(arena["floor"])
	var rect := _court_rect()
	draw_rect(rect, base)
	var plank_px := PLANK_WIDTH_M * PIXELS_PER_METRE
	var y := rect.position.y
	while y < rect.end.y:
		# Wide tone spread with the occasional much darker board, which is what
		# a real sprung floor looks like once it has been refinished a few times.
		var tone := 1.0 + rng.randf_range(-0.10, 0.09)
		if rng.randf() < 0.08:
			tone -= rng.randf_range(0.06, 0.14)
		var strip := Rect2(rect.position.x, y, rect.size.x, minf(plank_px, rect.end.y - y))
		draw_rect(strip, Color(base.r * tone, base.g * tone, base.b * tone))
		# Grain: a couple of faint lengthwise streaks per board.
		for streak in 2:
			var streak_y := strip.position.y + rng.randf() * strip.size.y
			draw_line(Vector2(rect.position.x, streak_y), Vector2(rect.end.x, streak_y),
				Color(base.r, base.g, base.b, 0.10 * rng.randf()), 1.0)
		# Boards are laid end to end, so break each row with butt joints.
		var x := rect.position.x + rng.randf_range(0.0, 3.0) * PIXELS_PER_METRE
		while x < rect.end.x:
			draw_line(Vector2(x, strip.position.y), Vector2(x, strip.end.y),
				base.darkened(0.22), 1.0)
			x += rng.randf_range(2.2, 4.6) * PIXELS_PER_METRE
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y),
			base.darkened(0.18), 1.5)
		y += plank_px


func _draw_paint() -> void:
	var primary := Color(team["primary"])
	primary.a = 0.82
	for side: float in [1.0, -1.0]:
		var a := to_px(side * CourtMetrics.FREE_THROW_X, -CourtMetrics.PAINT_WIDTH * 0.5)
		var b := to_px(side * CourtMetrics.HALF_LENGTH, CourtMetrics.PAINT_WIDTH * 0.5)
		draw_rect(Rect2(a, b - a).abs(), primary)


func _draw_centre_logo() -> void:
	var centre := to_px(0.0, 0.0)
	var outer := CourtMetrics.CIRCLE_RADIUS * PIXELS_PER_METRE * 0.94
	var primary := Color(team["primary"])
	var secondary := Color(team["secondary"])
	primary.a = 0.9
	draw_circle(centre, outer, primary)
	draw_circle(centre, outer * 0.66, secondary)
	var font := ThemeDB.fallback_font
	var text := String(team["abbr"])
	var font_size := int(outer * 0.62)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(font, centre + Vector2(-width * 0.5, font_size * 0.36), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, primary)


func _draw_markings() -> void:
	var white := Color(0.95, 0.95, 0.93)
	draw_rect(_court_rect(), white, false, LINE_PX)
	_line(Vector2(0.0, -CourtMetrics.HALF_WIDTH), Vector2(0.0, CourtMetrics.HALF_WIDTH), white)
	_arc(Vector2.ZERO, CourtMetrics.CIRCLE_RADIUS, 0.0, TAU, white)
	_arc(Vector2.ZERO, 0.6, 0.0, TAU, white)

	for side: float in [1.0, -1.0]:
		var baseline_x := side * CourtMetrics.HALF_LENGTH
		var ft_x := side * CourtMetrics.FREE_THROW_X
		var rim_x := side * CourtMetrics.RIM_X
		var half_paint := CourtMetrics.PAINT_WIDTH * 0.5

		_line(Vector2(ft_x, -half_paint), Vector2(baseline_x, -half_paint), white)
		_line(Vector2(ft_x, half_paint), Vector2(baseline_x, half_paint), white)
		_line(Vector2(ft_x, -half_paint), Vector2(ft_x, half_paint), white)
		_arc(Vector2(ft_x, 0.0), CourtMetrics.CIRCLE_RADIUS, 0.0, TAU, white)
		_arc(Vector2(rim_x, 0.0), CourtMetrics.RESTRICTED_RADIUS,
			-PI * 0.5, PI * 0.5, white)

		# Corner threes are straight; the arc picks up where they end.
		var dx: float = sqrt(pow(CourtMetrics.THREE_ARC_RADIUS, 2.0)
			- pow(CourtMetrics.THREE_CORNER_Z, 2.0))
		var break_x := rim_x - side * dx
		for z: float in [CourtMetrics.THREE_CORNER_Z, -CourtMetrics.THREE_CORNER_Z]:
			_line(Vector2(baseline_x, z), Vector2(break_x, z), white)
		var span := acos(dx / CourtMetrics.THREE_ARC_RADIUS)
		if side > 0.0:
			_arc(Vector2(rim_x, 0.0), CourtMetrics.THREE_ARC_RADIUS,
				span, TAU - span, white)
		else:
			_arc(Vector2(rim_x, 0.0), CourtMetrics.THREE_ARC_RADIUS,
				-PI + span, PI - span, white)

		_draw_lane_marks(side, white)
		var board_x := side * (CourtMetrics.HALF_LENGTH - CourtMetrics.BACKBOARD_FROM_BASELINE)
		_line(Vector2(board_x, -CourtMetrics.BACKBOARD_WIDTH * 0.5),
			Vector2(board_x, CourtMetrics.BACKBOARD_WIDTH * 0.5), white)


func _draw_lane_marks(side: float, colour: Color) -> void:
	var half_paint := CourtMetrics.PAINT_WIDTH * 0.5
	var offsets: Array[float] = [1.75, 2.60, 3.45, 4.30]
	for i in offsets.size():
		var x := side * (CourtMetrics.HALF_LENGTH - offsets[i])
		var depth := 0.45 if i == 0 else 0.18
		for z: float in [half_paint, -half_paint]:
			_line(Vector2(x, z), Vector2(x, z + signf(z) * depth), colour)


func _court_rect() -> Rect2:
	var a := to_px(-CourtMetrics.HALF_LENGTH, -CourtMetrics.HALF_WIDTH)
	var b := to_px(CourtMetrics.HALF_LENGTH, CourtMetrics.HALF_WIDTH)
	return Rect2(a, b - a)


func _line(from_m: Vector2, to_m: Vector2, colour: Color) -> void:
	draw_line(to_px(from_m.x, from_m.y), to_px(to_m.x, to_m.y), colour, LINE_PX, true)


func _arc(centre_m: Vector2, radius_m: float, from_angle: float, to_angle: float,
		colour: Color) -> void:
	var steps := int(clampf(radius_m * 24.0, 24.0, 192.0))
	draw_arc(to_px(centre_m.x, centre_m.y), radius_m * PIXELS_PER_METRE,
		from_angle, to_angle, steps, colour, LINE_PX, true)
