class_name Jumbotron
extends Node3D

# Scoreboard hanging over centre court. One offscreen viewport is drawn once
# per frame and mapped onto all four faces.

const PANEL_SIZE := Vector2i(512, 256)
const BOX := Vector3(4.6, 2.4, 4.6)

var _panel: ScoreboardPanel


static func create(parent: Node3D, height: float, source: Node) -> Jumbotron:
	var board := Jumbotron.new()
	board.name = "Jumbotron"
	board.position = Vector3(0.0, height, 0.0)
	parent.add_child(board)
	board._build(source)
	return board


func _build(source: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = PANEL_SIZE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_panel = ScoreboardPanel.new()
	_panel.source = source
	_panel.size = Vector2(PANEL_SIZE)
	viewport.add_child(_panel)
	add_child(viewport)

	var shell := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = BOX
	shell.mesh = box
	shell.material_override = Materials.flat(Color(0.06, 0.06, 0.08), 0.7, 0.2)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)

	var screen := StandardMaterial3D.new()
	screen.albedo_texture = viewport.get_texture()
	screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.emission_enabled = true
	screen.emission_texture = viewport.get_texture()
	screen.emission_energy_multiplier = 1.25
	for i in 4:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(BOX.x * 0.94, BOX.y * 0.80)
		face.mesh = quad
		face.material_override = screen
		var angle := TAU * float(i) / 4.0
		face.position = Vector3(sin(angle), 0.0, cos(angle)) * (BOX.z * 0.5 + 0.02)
		face.rotation.y = angle
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(face)

	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var wire := MeshInstance3D.new()
			var rod := CylinderMesh.new()
			rod.top_radius = 0.04
			rod.bottom_radius = 0.04
			rod.height = 6.0
			rod.radial_segments = 6
			wire.mesh = rod
			wire.material_override = Materials.flat(Color(0.1, 0.1, 0.11), 0.5, 0.6)
			wire.position = Vector3(x * BOX.x * 0.35, BOX.y * 0.5 + 3.0, z * BOX.z * 0.35)
			wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wire)


class ScoreboardPanel extends Control:
	var source: Node

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.06))
		if source == null or not is_instance_valid(source):
			return
		var font := ThemeDB.fallback_font
		var clock: MatchClock = source.clock
		var box: BoxScore = source.box
		var setup: MatchSetup = source.setup

		_label(font, String(setup.home["abbr"]), Vector2(46.0, 76.0), 40,
			Color(setup.home["primary"]).lightened(0.45))
		_label(font, String(setup.away["abbr"]), Vector2(size.x - 150.0, 76.0), 40,
			Color(setup.away["primary"]).lightened(0.45))
		_label(font, str(box.team_points[0]), Vector2(46.0, 156.0), 64,
			Color(1.0, 0.92, 0.72))
		_label(font, str(box.team_points[1]), Vector2(size.x - 150.0, 156.0), 64,
			Color(1.0, 0.92, 0.72))

		_centred(font, clock.period_name(), 66.0, 28, Color(0.68, 0.72, 0.82))
		_centred(font, clock.format_remaining(), 126.0, 46, Color(0.95, 0.97, 1.0))
		var shot := "%02d" % int(ceilf(clock.shot_clock))
		_centred(font, shot, 190.0, 40,
			Color(1.0, 0.4, 0.25) if clock.shot_clock < 5.0 else Color(1.0, 0.78, 0.28))

	func _label(font: Font, text: String, at: Vector2, font_size: int,
			colour: Color) -> void:
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)

	func _centred(font: Font, text: String, y: float, font_size: int,
			colour: Color) -> void:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1,
			font_size).x
		draw_string(font, Vector2(size.x * 0.5 - width * 0.5, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
