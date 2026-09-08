extends Node

# Autoload: the career save, the setup for the match about to be played, and
# the result of the one just finished.

const SAVE_PATH := "user://career.json"
const SAVE_VERSION := 1

var league: Dictionary = {}
var setup: MatchSetup = MatchSetup.new()
var last_box_score: Dictionary = {}

var _packs_applied: Array[String] = []
var _transition_pending := false
var _loading: CanvasLayer


## Deferred because most callers are inside a signal or a physics step, and
## swapping the scene there trips "parent node is busy adding/removing
## children".
func goto(scene_path: String) -> void:
	if _transition_pending:
		return
	_transition_pending = true
	_change_scene.call_deferred(scene_path)


func _change_scene(scene_path: String) -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 100
	var background := ColorRect.new()
	background.color = UiTheme.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(background)
	var label := Label.new()
	label.text = "LOADING..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.display_font())
	label.add_theme_font_size_override("font_size", 36)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(label)
	add_child(_loading)
	# Give the loading state a rendered frame before scene construction.
	await get_tree().process_frame
	await get_tree().process_frame
	var err := get_tree().change_scene_to_file(scene_path)
	_loading.queue_free()
	_loading = null
	_transition_pending = false
	if err != OK:
		report_error("Cannot open this screen: %s" % error_string(err))


func report_error(message: String) -> void:
	push_error(message)
	var dialog := AcceptDialog.new()
	dialog.title = "RETRO HOOPS"
	dialog.dialog_text = message
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 160))


func has_career() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func start_career(team_id: int, seed_value: int = 0) -> bool:
	var previous_league := league
	var previous_packs := _packs_applied.duplicate()
	var actual_seed := seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	league = League.new_league(actual_seed)
	league["user_team"] = team_id
	_packs_applied = PlayerPacks.apply_enabled(league)
	if save_career():
		return true
	league = previous_league
	_packs_applied = previous_packs
	return false


func save_career() -> bool:
	if league.is_empty():
		return false
	var temporary := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		report_error("Career save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"version": SAVE_VERSION,
		"packs": _packs_applied, "league": league}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		report_error("Career save failed: %s" % error_string(write_error))
		return false
	var target := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		var backup_error := DirAccess.copy_absolute(target, target + ".bak")
		if backup_error != OK:
			report_error("Cannot preserve the previous career save: %s" % error_string(backup_error))
			return false
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), target)
	if rename_error != OK:
		report_error("Cannot replace the career save: %s" % error_string(rename_error))
		return false
	return true


func load_career() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		report_error("Career load failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var problem := validate_save(parsed)
	if not problem.is_empty():
		report_error(problem)
		return false
	league = parsed["league"]
	_packs_applied.assign(parsed.get("packs", []))
	_repair_rosters()
	return true


func validate_save(parsed: Variant) -> String:
	if not parsed is Dictionary or not parsed.get("league") is Dictionary:
		return "Career save is not a valid league. The existing file has been kept."
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return "Career save uses an unsupported version."
	var saved: Dictionary = parsed["league"]
	if not saved.get("teams") is Array or not saved.get("schedule") is Array:
		return "Career save is missing its teams or schedule."
	var teams: Array = saved["teams"]
	if teams.is_empty() or int(saved.get("user_team", -1)) < 0 or int(saved.get("user_team", -1)) >= teams.size():
		return "Career save has no valid selected team."
	if not saved.has("seed") or not saved.has("day") or not parsed.get("packs", []) is Array:
		return "Career save is missing required fields."
	for team: Variant in teams:
		if not team is Dictionary or not team.get("roster") is Array:
			return "Career save contains an invalid roster."
	return ""


## Saves written before roster packs were bounds-checked can contain a team
## with too few players to field a lineup.
func _repair_rosters() -> void:
	var repaired := 0
	for team in league["teams"]:
		repaired += League.ensure_full_roster(team, int(league["seed"]))
	if repaired > 0:
		push_warning("Repaired %d missing roster slots in the save" % repaired)
		save_career()


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
		for team in scratch["teams"]:
			League.ensure_full_roster(team, 1337)
		return scratch
	return league
