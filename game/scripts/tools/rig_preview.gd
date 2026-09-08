extends Node3D

# Development scene: lines up players in each animation state so the rig can be
# eyeballed without running a match.
# godot --path game res://scenes/dev_rig.tscn -- --shot out.png

const POSES := [
	{"label": "idle", "action": PlayerAnimator.Action.NONE, "speed": 0.0, "ball": false},
	{"label": "run", "action": PlayerAnimator.Action.NONE, "speed": 6.4, "ball": false},
	{"label": "dribble", "action": PlayerAnimator.Action.NONE, "speed": 3.2, "ball": true},
	{"label": "shoot", "action": PlayerAnimator.Action.SHOOT, "speed": 0.0, "ball": true,
		"t": 0.75, "air": true},
	{"label": "dunk", "action": PlayerAnimator.Action.DUNK, "speed": 0.0, "ball": true,
		"t": 1.0, "air": true},
	{"label": "defend", "action": PlayerAnimator.Action.NONE, "speed": 0.0,
		"ball": false, "defend": true},
	{"label": "gather", "action": PlayerAnimator.Action.NONE, "speed": 0.0,
		"ball": false, "gather": 0.9},
	{"label": "rising", "action": PlayerAnimator.Action.NONE, "speed": 0.0,
		"ball": false, "air": true, "airborne": 0.9},
]

var animators: Array[PlayerAnimator] = []


func _ready() -> void:
	var model_path := FrameCapture.argument("--player-model")
	if not model_path.is_empty():
		ModelRig.preview_asset(model_path)
	var selected_pose := FrameCapture.argument("--pose")
	if not selected_pose.is_empty() and not POSES.any(func(pose): return pose["label"] == selected_pose):
		push_error("Unknown pose. Use idle, run, dribble, shoot, dunk or defend.")
		get_tree().quit(1)
		return
	var lg := League.new_league(11)
	var team: Dictionary = lg["teams"][7]

	_add_ground()
	_add_light()

	for i in POSES.size():
		var pose: Dictionary = POSES[i]
		if not selected_pose.is_empty() and pose["label"] != selected_pose:
			continue
		var player: Dictionary = team["roster"][0]
		var holder := Node3D.new()
		var x := float(i) * 1.75 - float(POSES.size() - 1) * 0.875
		if not selected_pose.is_empty():
			x = 0.0
		holder.position = Vector3(x,
			1.0 if pose.get("air", false) else 0.0, 0.0)
		# Face the camera: the rig is modelled looking down -Z.
		holder.rotation.y = PI + (0.5 if i % 2 == 0 else -0.4)
		add_child(holder)

		var rig := PlayerRig.create(player, team, self)
		holder.add_child(rig)
		if rig._retarget == null:
			push_error("The imported player was rejected. Inspect the preceding asset errors.")
			get_tree().quit(1)
			return
		var animator := PlayerAnimator.new(rig)
		animator.speed = float(pose["speed"])
		animator.top_speed = 7.4
		animator.has_ball = bool(pose["ball"])
		animator.action = pose["action"]
		animator.action_t = float(pose.get("t", 0.0))
		animator.grounded = not bool(pose.get("air", false))
		animator.defending = bool(pose.get("defend", false))
		animator.gather = float(pose.get("gather", 0.0))
		animator.airborne = float(pose.get("airborne", 0.0))
		animator.stride_phase = 1.1
		animator.tick(0.016)
		rig.snap_to_target()
		animators.append(animator)

	var camera := Camera3D.new()
	if FrameCapture.has_flag("--closeup"):
		camera.position = Vector3(-4.35 if FrameCapture.argument("--pose").is_empty() else 0.0, 1.52, 1.9)
		camera.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		camera.fov = 32.0
	else:
		camera.position = Vector3(0.0, 1.7, 6.2)
		camera.rotation_degrees = Vector3(-5.0, 0.0, 0.0)
		camera.fov = 50.0
	camera.current = true
	add_child(camera)

	FrameCapture.attach(self)


func _add_ground() -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	mesh.mesh = plane
	mesh.material_override = Materials.flat(Color(0.34, 0.30, 0.28), 0.85)
	add_child(mesh)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment = env
	add_child(world)


func _add_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, 34.0, 0.0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	add_child(light)

