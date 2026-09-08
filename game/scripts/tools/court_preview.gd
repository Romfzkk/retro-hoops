extends Node3D

# Development scene: builds the arena and drops a ball so the geometry and
# lighting can be checked without the rest of the match running.
# Run with: godot --path game res://scenes/dev_preview.tscn -- --shot out.png

var ball: Ball


func _ready() -> void:
	var lg := League.new_league(7)
	var team: Dictionary = lg["teams"][0]
	var arena: Dictionary = Teams.ARENAS[0]

	ArenaBuilder.build(self, team, lg["teams"][1], arena, 7)
	add_child(Hoop.create(0, Color(team["primary"])))
	add_child(Hoop.create(1, Color(lg["teams"][1]["primary"])))

	ball = Ball.create()
	ball.position = Vector3(CourtMetrics.RIM_X - 5.0, 2.4, 1.0)
	ball.linear_velocity = Vector3(5.4, 5.2, -0.6)
	add_child(ball)

	var camera := Camera3D.new()
	# look_at needs the camera in the tree, so the target is aimed at after.
	var aim_at := Vector3.INF
	if OS.get_cmdline_user_args().has("--top"):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 32.0
		camera.position = Vector3(0.0, 14.0, 0.0)
		camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	elif OS.get_cmdline_user_args().has("--rim"):
		# The arena builder does not carry baskets; the match adds them. One is
		# needed here or the rim view frames an empty wall of crowd.
		var hoop := Hoop.create(0, Color(0.2, 0.45, 0.8))
		add_child(hoop)
		# Close on the ring, which is too small to judge from a court-wide shot.
		var rim := CourtMetrics.rim_position(0)
		camera.position = rim + Vector3(-1.9, 0.55, 1.5)
		aim_at = rim + Vector3(0.0, -0.12, 0.0)
		camera.fov = 38.0
	else:
		camera.position = Vector3(0.0, 9.5, 19.0)
		camera.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
		camera.fov = 55.0
	camera.current = true
	add_child(camera)
	if aim_at.is_finite():
		camera.look_at(aim_at)

	FrameCapture.attach(self)

