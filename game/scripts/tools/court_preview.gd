extends Node3D

# Development scene: builds the arena and drops a ball so the geometry and
# lighting can be checked without the rest of the match running.
# Run with: godot --path game res://scenes/dev_preview.tscn -- --shot out.png

var ball: Ball


func _ready() -> void:
	var lg := League.new_league(7)
	var team: Dictionary = lg["teams"][0]
	var arena: Dictionary = Teams.ARENAS[0]

	ArenaBuilder.build(self, team, arena, 7)
	add_child(Hoop.create(0, Color(team["primary"])))
	add_child(Hoop.create(1, Color(lg["teams"][1]["primary"])))

	ball = Ball.create()
	ball.position = Vector3(CourtMetrics.RIM_X - 5.0, 2.4, 1.0)
	ball.linear_velocity = Vector3(5.4, 5.2, -0.6)
	add_child(ball)

	var camera := Camera3D.new()
	if OS.get_cmdline_user_args().has("--top"):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 32.0
		camera.position = Vector3(0.0, 14.0, 0.0)
		camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		camera.position = Vector3(0.0, 9.5, 19.0)
		camera.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
		camera.fov = 55.0
	camera.current = true
	add_child(camera)

	FrameCapture.attach(self)

