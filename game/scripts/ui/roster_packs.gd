extends MenuScreen

# Roster packs are user-authored JSON. Nothing ships with the game; this screen
# lists what is in the packs folder, toggles which are active, and can drop an
# example file to start from.

var _packs: Array[Dictionary] = []
var _enabled: Array[String] = []
var _status := ""


func _ready() -> void:
	super()
	title = "ROSTER PACKS"
	subtitle = "Your own teams and players"
	footer = "Toggle  Enter    Back  Esc"
	chosen.connect(_on_chosen)
	cancelled.connect(func(): Game.goto("res://scenes/main_menu.tscn"))
	_reload()


func _reload() -> void:
	_packs = PlayerPacks.list_available()
	_enabled = PlayerPacks.enabled_ids()
	rows = []
	for pack in _packs:
		rows.append({
			"id": "pack:%s" % String(pack["id"]),
			"label": String(pack["name"]).to_upper(),
			"value": "ON" if _enabled.has(String(pack["id"])) else "OFF",
		})
	if _packs.is_empty():
		rows.append({"id": "none", "label": "NO PACKS FOUND", "enabled": false})
	rows.append({"id": "example", "label": "WRITE EXAMPLE PACK"})
	rows.append({"id": "folder", "label": "SHOW PACKS FOLDER"})
	rows.append({"id": "back", "label": "BACK"})
	selected = clampi(selected, 0, rows.size() - 1)


func _on_chosen(id: String) -> void:
	if id.begins_with("pack:"):
		var pack_id := id.substr(5)
		if _enabled.has(pack_id):
			_enabled.erase(pack_id)
		else:
			_enabled.append(pack_id)
		PlayerPacks.set_enabled(_enabled)
		_status = "Packs apply when a new season is started."
		_reload()
		return
	match id:
		"example":
			_write_example()
		"folder":
			OS.shell_open(ProjectSettings.globalize_path(PlayerPacks.packs_dir()))
		"back":
			Game.goto("res://scenes/main_menu.tscn")


func _write_example() -> void:
	var path := PlayerPacks.packs_dir().path_join("example.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status = "Could not write %s" % path
		return
	file.store_string(PlayerPacks.example_pack_json())
	file.close()
	_status = "Wrote example.json"
	_reload()


func _draw_side_panel(scale: float) -> void:
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.78)
	var pad := UiTheme.XL * scale
	var y := rect.position.y + 48.0 * scale

	UiTheme.label(self, "HOW PACKS WORK", Vector2(rect.position.x + pad, y),
		UiTheme.display_font(), UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
	y += 34.0 * scale

	var lines := [
		"Drop a .json file into the packs folder and it shows up here.",
		"A pack can rename a team, restyle its colours and replace its roster.",
		"Ratings are clamped to 25-99 and anything malformed is rejected whole,",
		"so a bad file can never half-apply to your league.",
		"",
		"The game ships no real names or likenesses. What you put in a pack is",
		"yours, stays on your machine, and is not distributed with the project.",
		"",
		"Format reference: docs/player-packs.md",
	]
	for line in lines:
		UiTheme.label(self, line, Vector2(rect.position.x + pad, y),
			UiTheme.text_font(), UiTheme.size(UiTheme.BODY, scale), UiTheme.TEXT_DIM)
		y += 26.0 * scale

	UiTheme.label(self, ProjectSettings.globalize_path(PlayerPacks.DIR),
		Vector2(rect.position.x + pad, rect.end.y - 46.0 * scale),
		UiTheme.text_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
	if not _status.is_empty():
		UiTheme.label(self, _status,
			Vector2(rect.position.x + pad, rect.end.y - 20.0 * scale),
			UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.GOLD)
