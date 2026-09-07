extends MenuScreen

# Season home: next fixture, conference table, and the controls to play or sim.

enum Panel { STANDINGS, SCHEDULE, BRACKET }

var _panel: Panel = Panel.STANDINGS
var _status := ""


func _ready() -> void:
	super()
	if Game.league.is_empty() and not Game.load_career():
		Game.goto("res://scenes/main_menu.tscn")
		return
	footer = "Move  W/S    Select  Enter    Panel  A/D    Back  Esc"
	chosen.connect(_on_chosen)
	cancelled.connect(func():
		Game.save_career()
		Game.goto("res://scenes/main_menu.tscn"))
	_refresh()


func _refresh() -> void:
	var team := Game.user_team()
	title = League.team_full(team).to_upper()
	_ensure_playoffs()

	if _in_playoffs():
		var playoffs := _playoffs()
		var champion := int(playoffs["champion"])
		if champion >= 0:
			subtitle = "%s win the title" % League.team_full(
				Game.team_by_id(champion)).to_upper()
		else:
			subtitle = "Playoffs   %s" % League.round_name(playoffs,
				int(playoffs["round"]))
		_panel = Panel.BRACKET
	else:
		var day := int(Game.league["day"]) + 1
		var total: int = (Game.league["schedule"] as Array).size()
		subtitle = "Season %d   Day %d of %d   %d-%d" % [int(Game.league["season"]),
			mini(day, total), total, int(team["w"]), int(team["l"])]
		if _panel == Panel.BRACKET:
			_panel = Panel.STANDINGS

	var fixture := _next_user_game()
	var playable := not fixture.is_empty() and not bool(fixture.get("played", false))
	var done := _season_complete()
	rows = [
		{"id": "play", "label": "PLAY NEXT GAME", "enabled": playable},
		{"id": "sim_game", "label": "SIM THIS GAME", "enabled": playable},
		{"id": "sim_day", "label": "SIM AHEAD", "enabled": not done},
		{"id": "panel", "label": "PANEL", "value": _panel_name()},
		{"id": "save", "label": "SAVE"},
		{"id": "menu", "label": "MAIN MENU"},
	]


func _panel_name() -> String:
	match _panel:
		Panel.SCHEDULE:
			return "SCHEDULE"
		Panel.BRACKET:
			return "BRACKET"
	return "STANDINGS"


func _playoffs() -> Dictionary:
	return Game.league.get("playoffs", {})


func _in_playoffs() -> bool:
	return not _playoffs().is_empty()


func _season_complete() -> bool:
	var playoffs := _playoffs()
	return not playoffs.is_empty() and int(playoffs["champion"]) >= 0


## The bracket is built the moment the regular season runs out of days.
func _ensure_playoffs() -> void:
	if _in_playoffs() or not League.regular_season_done(Game.league):
		return
	Game.league["playoffs"] = League.make_playoffs(Game.league)
	Game.save_career()


func _current_round() -> Array:
	var playoffs := _playoffs()
	if playoffs.is_empty() or int(playoffs["champion"]) >= 0:
		return []
	return playoffs["rounds"][int(playoffs["round"])]


func _next_user_game() -> Dictionary:
	if not _in_playoffs():
		return SeasonSim.find_user_game(Game.league)
	var user := int(Game.league["user_team"])
	for game in _current_round():
		if int(game["h"]) == user or int(game["a"]) == user:
			return game
	return {}


func on_adjust(id: String, step: int) -> void:
	if id != "panel":
		return
	var available: Array[Panel] = [Panel.STANDINGS, Panel.SCHEDULE]
	if _in_playoffs():
		available.append(Panel.BRACKET)
	var index := maxi(available.find(_panel), 0)
	_panel = available[wrapi(index + step, 0, available.size())]
	_refresh()


func _on_chosen(id: String) -> void:
	match id:
		"play":
			_start_user_game()
		"sim_game":
			_sim_user_game()
		"sim_day":
			_advance_day()
		"panel":
			on_adjust("panel", 1)
		"save":
			_status = "Saved." if Game.save_career() else "Save failed."
		"menu":
			Game.save_career()
			Game.goto("res://scenes/main_menu.tscn")


func _start_user_game() -> void:
	var fixture := _next_user_game()
	if fixture.is_empty():
		return
	var setup := MatchSetup.new()
	setup.home = Game.team_by_id(int(fixture["h"]))
	setup.away = Game.team_by_id(int(fixture["a"]))
	var user := int(Game.league["user_team"])
	setup.home_controller = MatchSetup.Controller.LOCAL_1 \
		if int(fixture["h"]) == user else MatchSetup.Controller.AI
	setup.away_controller = MatchSetup.Controller.LOCAL_1 \
		if int(fixture["a"]) == user else MatchSetup.Controller.AI
	setup.quarter_seconds = int(Settings.get_value("quarter_minutes")) * 60
	setup.difficulty = int(Settings.get_value("difficulty"))
	setup.season_day = int(Game.league["day"])
	setup.season_playoff_round = int(_playoffs()["round"]) if _in_playoffs() else -1
	Game.setup = setup
	Game.save_career()
	Game.goto("res://scenes/match.tscn")


func _sim_user_game() -> void:
	var fixture := _next_user_game()
	if fixture.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result := SeasonSim.play(Game.team_by_id(int(fixture["h"])),
		Game.team_by_id(int(fixture["a"])), rng)
	fixture["hs"] = result["home"]
	fixture["as"] = result["away"]
	fixture["played"] = true
	League.record_result(Game.league, int(fixture["h"]), int(fixture["a"]),
		int(result["home"]), int(result["away"]))
	_status = "%s %d - %d %s" % [
		String(Game.team_by_id(int(fixture["h"]))["abbr"]), int(result["home"]),
		int(result["away"]), String(Game.team_by_id(int(fixture["a"]))["abbr"])]
	_advance_day()


func _advance_day() -> void:
	if _in_playoffs():
		_advance_playoff_round()
	else:
		SeasonSim.advance_day(Game.league)
		if SeasonSim.day_complete(Game.league):
			Game.league["day"] = int(Game.league["day"]) + 1
	Game.save_career()
	_refresh()


func _advance_playoff_round() -> void:
	var playoffs := _playoffs()
	if playoffs.is_empty() or int(playoffs["champion"]) >= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for game in _current_round():
		if bool(game["played"]):
			continue
		var result := SeasonSim.play(Game.team_by_id(int(game["h"])),
			Game.team_by_id(int(game["a"])), rng)
		game["hs"] = result["home"]
		game["as"] = result["away"]
		game["played"] = true
	League.advance_playoffs(playoffs)
	if int(playoffs["champion"]) >= 0:
		var champion := Game.team_by_id(int(playoffs["champion"]))
		_status = "%s win it all." % League.team_full(champion)
		(Game.league["history"] as Array).append({
			"season": int(Game.league["season"]),
			"champion": int(playoffs["champion"]),
		})


func _process(delta: float) -> void:
	super(delta)
	_refresh()


func _draw_side_panel(scale: float) -> void:
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.78)
	match _panel:
		Panel.STANDINGS:
			_draw_standings(rect, scale)
		Panel.SCHEDULE:
			_draw_schedule(rect, scale)
		Panel.BRACKET:
			_draw_bracket(rect, scale)
	if not _status.is_empty():
		UiTheme.label(self, _status,
			Vector2(rect.position.x + UiTheme.XL * scale, rect.end.y - UiTheme.L * scale),
			UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.GOLD)


func _draw_standings(rect: Rect2, scale: float) -> void:
	var user := int(Game.league["user_team"])
	var conf := int(Game.user_team()["conf"])
	var table := League.standings(Game.league, conf)
	var pad := UiTheme.XL * scale

	UiTheme.label(self, "%s CONFERENCE" % Teams.conference_name(conf).to_upper(),
		Vector2(rect.position.x + pad, rect.position.y + 40.0 * scale),
		UiTheme.display_font(), UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
	UiTheme.label_right(self, "W    L    DIFF", rect.end.x - pad,
		rect.position.y + 40.0 * scale, UiTheme.bold_font(),
		UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)

	var y := rect.position.y + 70.0 * scale
	for i in mini(table.size(), 15):
		var team: Dictionary = table[i]
		var mine := int(team["id"]) == user
		var ink: Color = UiTheme.TEXT if mine else UiTheme.TEXT_DIM
		if mine:
			var band := UiTheme.SURFACE_HI
			band.a = 0.9
			draw_rect(Rect2(Vector2(rect.position.x + pad * 0.5, y - 15.0 * scale),
				Vector2(rect.size.x - pad, 22.0 * scale)), band)
		if i == League.PLAYOFF_SEEDS_PER_CONF:
			draw_line(Vector2(rect.position.x + pad, y - 18.0 * scale),
				Vector2(rect.end.x - pad, y - 18.0 * scale), UiTheme.ORANGE, 1.0)
		UiTheme.label(self, "%2d" % (i + 1), Vector2(rect.position.x + pad, y),
			UiTheme.text_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
		UiTheme.label(self, String(team["abbr"]),
			Vector2(rect.position.x + pad + 30.0 * scale, y), UiTheme.bold_font(),
			UiTheme.size(UiTheme.LABEL, scale), ink)
		UiTheme.label(self, League.team_full(team),
			Vector2(rect.position.x + pad + 84.0 * scale, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), ink)
		var diff := int(team["pf"]) - int(team["pa"])
		UiTheme.label_right(self, "%d   %d   %+d" % [int(team["w"]), int(team["l"]), diff],
			rect.end.x - pad, y, UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), ink)
		y += 22.0 * scale


func _draw_schedule(rect: Rect2, scale: float) -> void:
	var pad := UiTheme.XL * scale
	var day := int(Game.league["day"])
	var schedule: Array = Game.league["schedule"]
	UiTheme.label(self, "TODAY", Vector2(rect.position.x + pad,
		rect.position.y + 40.0 * scale), UiTheme.display_font(),
		UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
	if day >= schedule.size():
		UiTheme.label(self, "Regular season complete.",
			Vector2(rect.position.x + pad, rect.position.y + 76.0 * scale),
			UiTheme.text_font(), UiTheme.size(UiTheme.BODY, scale), UiTheme.TEXT_DIM)
		return

	var user := int(Game.league["user_team"])
	var y := rect.position.y + 72.0 * scale
	for game in schedule[day]:
		var home: Dictionary = Game.team_by_id(int(game["h"]))
		var away: Dictionary = Game.team_by_id(int(game["a"]))
		var mine := int(game["h"]) == user or int(game["a"]) == user
		var ink: Color = UiTheme.TEXT if mine else UiTheme.TEXT_DIM
		UiTheme.label(self, "%s  vs  %s" % [String(home["abbr"]), String(away["abbr"])],
			Vector2(rect.position.x + pad, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), ink)
		var line := "%d - %d" % [int(game["hs"]), int(game["as"])] \
			if bool(game["played"]) else "--"
		UiTheme.label_right(self, line, rect.end.x - pad, y, UiTheme.bold_font(),
			UiTheme.size(UiTheme.LABEL, scale),
			UiTheme.GOLD if mine and bool(game["played"]) else ink)
		y += 22.0 * scale


func _draw_bracket(rect: Rect2, scale: float) -> void:
	var playoffs := _playoffs()
	if playoffs.is_empty():
		return
	var pad := UiTheme.XL * scale
	var user := int(Game.league["user_team"])
	var rounds: Array = playoffs["rounds"]

	UiTheme.label(self, "PLAYOFFS", Vector2(rect.position.x + pad,
		rect.position.y + 40.0 * scale), UiTheme.display_font(),
		UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)

	var column_width := (rect.size.x - pad * 2.0) / maxf(float(rounds.size()), 1.0)
	for index in rounds.size():
		var games: Array = rounds[index]
		var x := rect.position.x + pad + column_width * float(index)
		UiTheme.label(self, League.round_name(playoffs, index).to_upper(),
			Vector2(x, rect.position.y + 78.0 * scale), UiTheme.bold_font(),
			UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)

		var y := rect.position.y + 108.0 * scale
		for game in games:
			var home: Dictionary = Game.team_by_id(int(game["h"]))
			var away: Dictionary = Game.team_by_id(int(game["a"]))
			var mine := int(game["h"]) == user or int(game["a"]) == user
			var ink: Color = UiTheme.TEXT if mine else UiTheme.TEXT_DIM
			var line := "%s v %s" % [String(home["abbr"]), String(away["abbr"])]
			if bool(game["played"]):
				line = "%s %d - %d %s" % [String(home["abbr"]), int(game["hs"]),
					int(game["as"]), String(away["abbr"])]
			UiTheme.label(self, line, Vector2(x, y), UiTheme.text_font(),
				UiTheme.size(UiTheme.LABEL, scale),
				UiTheme.GOLD if mine and bool(game["played"]) else ink)
			y += 26.0 * scale

	var champion := int(playoffs["champion"])
	if champion >= 0:
		UiTheme.label(self, "%s WIN THE TITLE" % String(
			Game.team_by_id(champion)["abbr"]),
			Vector2(rect.position.x + pad, rect.end.y - 34.0 * scale),
			UiTheme.display_font(), UiTheme.size(UiTheme.HEAD, scale), UiTheme.GOLD)
