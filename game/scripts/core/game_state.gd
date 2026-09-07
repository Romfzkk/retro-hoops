extends Node

# Autoload: the career save, the setup for the match about to be played, and
# the result of the one just finished.

const SAVE_PATH := "user://career.json"
const SAVE_VERSION := 1

var league: Dictionary = {}
var setup: MatchSetup = MatchSetup.new()
var last_box_score: Dictionary = {}

var _packs_applied: Array[String] = []


## Deferred because most callers are inside a signal or a physics step, and
## swapping the scene there trips "parent node is busy adding/removing
## children".
func goto(scene_path: String) -> void:
	_change_scene.call_deferred(scene_path)


func _change_scene(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Cannot open %s: %s" % [scene_path, error_string(err)])


func has_career() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func start_career(team_id: int, seed_value: int = 0) -> void:
	var actual_seed := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	league = League.new_league(actual_seed)
	league["user_team"] = team_id
	_packs_applied = PlayerPacks.apply_enabled(league)
	save_career()


func save_career() -> bool:
	if league.is_empty():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Career save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"packs": _packs_applied,
		"league": league,
	}))
	return true


func load_career() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Career load failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("league"):
		push_error("Career save is corrupt")
		return false
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		push_error("Career save is from an incompatible version")
		return false
	league = parsed["league"]
	_packs_applied.assign(parsed.get("packs", []))
	return true


func delete_career() -> void:
	if has_career():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	league = {}


func user_team() -> Dictionary:
	if league.is_empty():
		return {}
	return league["teams"][int(league["user_team"])]


func team_by_id(id: int) -> Dictionary:
	if league.is_empty():
		return {}
	return league["teams"][id]


# Teams for exhibition play when no career exists yet.
func exhibition_league() -> Dictionary:
	if league.is_empty():
		var scratch := League.new_league(1337)
		PlayerPacks.apply_enabled(scratch)
		return scratch
	return league
