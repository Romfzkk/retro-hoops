extends MenuScreen

# Post-game. Reads the result the match left on Game and, when the game came
# from a season, writes it back into the league before moving on.

var _result: Dictionary
var _box: BoxScore
var _shown_team := 0
var _recorded := false
var _table: Tree

const COLUMNS := ["PLAYER", "PTS", "FG", "FT", "3P", "REB", "AST", "STL", "BLK", "TO", "PF"]


func _ready() -> void:
	art_banner = "champion"
	super()
	_result = Game.last_box_score
	if _result.is_empty():
		Game.goto("res://scenes/main_menu.tscn")
		return
	_box = _result["box"]
	_build_table()
	_record_into_season()

	title = "FINAL"
	subtitle = "%s %d   -   %d %s" % [
		String(_result_team(0)["abbr"]), int(_result["home_score"]),
		int(_result["away_score"]),
		String(_result_team(1)["abbr"])]
	footer = "Switch team  A/D    Continue  Enter"
	chosen.connect(_on_chosen)
	cancelled.connect(_on_continue)
	_refresh()


func _result_team(index: int) -> Dictionary:
	return _result["home_team" if index == 0 else "away_team"]


func _refresh() -> void:
	var home: Dictionary = _result_team(0)
	var away: Dictionary = _result_team(1)
	rows = [
		{"id": "team", "label": "BOX SCORE",
			"value": String(home["abbr"] if _shown_team == 0 else away["abbr"])},
		{"id": "continue", "label": "CONTINUE"},
	]
	_populate_table()


func on_adjust(id: String, _step: int) -> void:
	if id == "team":
		_shown_team = 1 - _shown_team
		_refresh()


func _on_chosen(id: String) -> void:
	if id == "team":
		on_adjust("team", 1)
	else:
		_on_continue()


func _on_continue() -> void:
	Net.shutdown()
	if int(_result.get("season_day", -1)) >= 0 and not Game.league.is_empty():
		Game.goto("res://scenes/season_hub.tscn")
	else:
		Game.goto("res://scenes/main_menu.tscn")


func _record_into_season() -> void:
	var day := int(_result.get("season_day", -1))
	if _recorded or day < 0 or Game.league.is_empty():
		return
	_recorded = true
	if _record_into_playoffs():
		return
	var schedule: Array = Game.league["schedule"]
	if day >= schedule.size():
		return
	for game in schedule[day]:
		if int(game["h"]) != int(_result["home"]) or int(game["a"]) != int(_result["away"]):
			continue
		if bool(game["played"]):
			return
		game["hs"] = int(_result["home_score"])
		game["as"] = int(_result["away_score"])
		game["played"] = true
		League.record_result(Game.league, int(game["h"]), int(game["a"]),
			int(game["hs"]), int(game["as"]))
		SeasonSim.advance_day(Game.league)
		if SeasonSim.day_complete(Game.league):
			Game.league["day"] = day + 1
		Game.save_career()
		return


# A playoff game goes into the bracket, and the rest of the round is simulated
# so the next opponent is known by the time you get back to the hub.
func _record_into_playoffs() -> bool:
	var playoffs: Dictionary = Game.league.get("playoffs", {})
	if playoffs.is_empty() or int(playoffs["champion"]) >= 0:
		return false
	var games: Array = playoffs["rounds"][int(playoffs["round"])]
	var found := false
	for game in games:
		if int(game["h"]) != int(_result["home"]) or int(game["a"]) != int(_result["away"]):
			continue
		if bool(game["played"]):
			return true
		game["hs"] = int(_result["home_score"])
		game["as"] = int(_result["away_score"])
		game["played"] = true
		found = true
		break
	if not found:
		return false

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for game in games:
		if bool(game["played"]):
			continue
		var simulated := SeasonSim.play(Game.team_by_id(int(game["h"])),
			Game.team_by_id(int(game["a"])), rng)
		game["hs"] = simulated["home"]
		game["as"] = simulated["away"]
		game["played"] = true
	League.advance_playoffs(playoffs)
	Game.save_career()
	return true


func _build_table() -> void:
	_table = Tree.new()
	_table.hide_root = true
	_table.columns = COLUMNS.size()
	_table.column_titles_visible = true
	_table.add_theme_font_override("font", UiTheme.text_font())
	_table.add_theme_font_override("title_button_font", UiTheme.bold_font())
	_table.add_theme_color_override("font_color", UiTheme.TEXT)
	_table.add_theme_constant_override("v_separation", 14)
	for column in COLUMNS.size():
		_table.set_column_title(column, COLUMNS[column])
		_table.set_column_custom_minimum_width(column, 170 if column == 0 else 54)
		_table.set_column_expand(column, column == 0)
	add_child(_table)


func _populate_table() -> void:
	_table.clear()
	var root := _table.create_item()
	for row in _box.team_rows(_shown_team):
		var item := _table.create_item(root)
		var values := ["#%d  %s" % [row["num"], row["name"]], str(row["pts"]),
			"%d/%d" % [row["fgm"], row["fga"]], "%d/%d" % [row["ftm"], row["fta"]],
			"%d/%d" % [row["tpm"], row["tpa"]], str(row["reb"]), str(row["ast"]),
			str(row["stl"]), str(row["blk"]), str(row["to"]), str(row["pf"])]
		for column in values.size():
			item.set_text(column, values[column])
			item.set_selectable(column, false)
			if column > 0:
				item.set_text_alignment(column, HORIZONTAL_ALIGNMENT_CENTER)


func _process(delta: float) -> void:
	super(delta)
	if _table == null:
		return
	var scale := UiTheme.scale_for(view())
	var rect := detail_rect(scale)
	_table.visible = _wide_details(scale) or _show_details
	_table.position = rect.position + Vector2(0.0, 50.0 * scale)
	_table.size = Vector2(rect.size.x, maxf(80.0, rect.size.y - 50.0 * scale))
	_table.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.BODY, scale))
	_table.add_theme_font_size_override("title_button_font_size", UiTheme.size(UiTheme.LABEL, scale))


func _draw_side_panel(scale: float) -> void:
	if _result.is_empty():
		return
	var rect := detail_rect(scale)
	var team := _result_team(_shown_team)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), Color(team["primary"]))
	draw_string(UiTheme.display_font(), rect.position + Vector2(0.0, 32.0 * scale),
		League.team_full(team).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x,
		UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
