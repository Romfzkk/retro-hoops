extends MenuScreen

# Post-game. Reads the result the match left on Game and, when the game came
# from a season, writes it back into the league before moving on.

var _result: Dictionary
var _box: BoxScore
var _shown_team := 0
var _recorded := false


func _ready() -> void:
	art_banner = "champion"
	super()
	_result = Game.last_box_score
	if _result.is_empty():
		Game.goto("res://scenes/main_menu.tscn")
		return
	_box = _result["box"]
	_record_into_season()

	title = "FINAL"
	subtitle = "%s %d   -   %d %s" % [
		String(Game.team_by_id(int(_result["home"]))["abbr"]), int(_result["home_score"]),
		int(_result["away_score"]),
		String(Game.team_by_id(int(_result["away"]))["abbr"])]
	footer = "Switch team  A/D    Continue  Enter"
	chosen.connect(_on_chosen)
	cancelled.connect(_on_continue)
	_refresh()


func _refresh() -> void:
	var home: Dictionary = Game.team_by_id(int(_result["home"]))
	var away: Dictionary = Game.team_by_id(int(_result["away"]))
	rows = [
		{"id": "team", "label": "BOX SCORE",
			"value": String(home["abbr"] if _shown_team == 0 else away["abbr"])},
		{"id": "continue", "label": "CONTINUE"},
	]


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


func _draw_side_panel(scale: float) -> void:
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.80)
	var pad := UiTheme.L * scale
	var team: Dictionary = Game.team_by_id(int(_result["home" if _shown_team == 0 else "away"]))

	draw_rect(Rect2(Vector2(rect.position.x + pad, rect.position.y + pad),
		Vector2(rect.size.x - pad * 2.0, 5.0 * scale)), Color(team["primary"]))
	UiTheme.label(self, League.team_full(team).to_upper(),
		Vector2(rect.position.x + pad, rect.position.y + 52.0 * scale),
		UiTheme.display_font(), UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)

	var columns := [
		{"key": "pts", "title": "PTS", "x": 0.52},
		{"key": "reb", "title": "REB", "x": 0.62},
		{"key": "ast", "title": "AST", "x": 0.72},
		{"key": "stl", "title": "STL", "x": 0.82},
		{"key": "blk", "title": "BLK", "x": 0.90},
	]
	var header_y := rect.position.y + 84.0 * scale
	UiTheme.label(self, "PLAYER", Vector2(rect.position.x + pad, header_y),
		UiTheme.bold_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
	UiTheme.label(self, "FG", Vector2(rect.position.x + rect.size.x * 0.38, header_y),
		UiTheme.bold_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
	for column in columns:
		UiTheme.label(self, String(column["title"]),
			Vector2(rect.position.x + rect.size.x * float(column["x"]), header_y),
			UiTheme.bold_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)

	var y := header_y + 26.0 * scale
	for row in _box.team_rows(_shown_team):
		UiTheme.label(self, "%2d  %s" % [int(row["num"]), String(row["name"])],
			Vector2(rect.position.x + pad, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT)
		UiTheme.label(self, "%d/%d" % [int(row["fgm"]), int(row["fga"])],
			Vector2(rect.position.x + rect.size.x * 0.38, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)
		for column in columns:
			var value := int(row[String(column["key"])])
			UiTheme.label(self, str(value),
				Vector2(rect.position.x + rect.size.x * float(column["x"]), y),
				UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale),
				UiTheme.GOLD if String(column["key"]) == "pts" and value >= 15
				else UiTheme.TEXT)
		y += 24.0 * scale
