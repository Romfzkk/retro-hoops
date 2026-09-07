extends Node3D

# Front end. The arena is built for real behind the menu and the camera drifts
# around it, so the first thing you see is the game rather than a title card.

const ORBIT_RADIUS := 22.0
const ORBIT_HEIGHT := 9.5
const ORBIT_SPEED := 0.035

var _menu: MenuScreen
var _camera: Camera3D
var _angle := 0.6
var _league: Dictionary


func _ready() -> void:
	_league = Game.exhibition_league()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var team: Dictionary = _league["teams"][rng.randi() % (_league["teams"] as Array).size()]
	var away: Dictionary = _league["teams"][rng.randi() % (_league["teams"] as Array).size()]
	ArenaBuilder.build(self, team, away, Teams.ARENAS[0], int(team["id"]) * 31 + 7)

	_camera = Camera3D.new()
	_camera.fov = 42.0
	add_child(_camera)
	_place_camera(0.0)

	_menu = MenuScreen.new()
	_menu.title = "RETRO HOOPS"
	_menu.subtitle = "30 teams. One rock."
	_menu.footer = "Move  W/S    Select  Enter"
	_menu.dim_background = false
	_menu.art_slot = "hero"
	_menu.art_caption = "Season 1"
	_menu.rows = _build_rows()
	_menu.chosen.connect(_on_chosen)
	var layer := CanvasLayer.new()
	layer.add_child(_menu)
	add_child(layer)

	FrameCapture.attach(self)


func _build_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id": "quick", "label": "QUICK PLAY"},
		{"id": "online", "label": "ONLINE"},
	]
	if Game.has_career():
		rows.append({"id": "continue", "label": "CONTINUE SEASON"})
	rows.append({"id": "season", "label": "NEW SEASON"})
	rows.append_array([
		{"id": "packs", "label": "ROSTER PACKS"},
		{"id": "options", "label": "OPTIONS"},
		{"id": "quit", "label": "QUIT"},
	])
	return rows


func _process(delta: float) -> void:
	_angle += delta * ORBIT_SPEED
	_place_camera(_angle)


func _place_camera(angle: float) -> void:
	_camera.position = Vector3(cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT,
		sin(angle) * ORBIT_RADIUS)
	_camera.look_at(Vector3(0.0, 2.2, 0.0), Vector3.UP)


func _on_chosen(id: String) -> void:
	match id:
		"quick":
			Game.goto("res://scenes/exhibition_setup.tscn")
		"online":
			Game.goto("res://scenes/online_setup.tscn")
		"continue":
			if Game.load_career():
				Game.goto("res://scenes/season_hub.tscn")
		"season":
			Game.goto("res://scenes/new_season.tscn")
		"packs":
			Game.goto("res://scenes/roster_packs.tscn")
		"options":
			Game.goto("res://scenes/options.tscn")
		"quit":
			get_tree().quit()
