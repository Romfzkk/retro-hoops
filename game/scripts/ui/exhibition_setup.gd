extends MenuScreen

# Quick play setup. Every row is a setting except the last, and the detail
# panel shows the two rosters you are about to put on the floor.

var _league: Dictionary
var _teams: Array
var _home := 0
var _away := 1
var _mode := MatchSetup.Mode.FIVE_V_FIVE
var _arena := 0
var _quarters := 4
var _quarter_minutes := 5
var _opponent_is_human := false


func _ready() -> void:
	super()
	_league = Game.exhibition_league()
	_teams = _league["teams"]
	_away = 16 % _teams.size()
	_quarter_minutes = int(Settings.get_value("quarter_minutes"))
	title = "QUICK PLAY"
	subtitle = "Exhibition game"
	footer = "Change  A/D    Select  Enter    Back  Esc"
	chosen.connect(_on_chosen)
	cancelled.connect(func(): Game.goto("res://scenes/main_menu.tscn"))
	_refresh()


func _refresh() -> void:
	rows = [
		{"id": "home", "label": "HOME", "value": _team_label(_home)},
		{"id": "away", "label": "AWAY", "value": _team_label(_away)},
		{"id": "mode", "label": "MODE",
			"value": "5 ON 5" if _mode == MatchSetup.Mode.FIVE_V_FIVE else "3 ON 3"},
		{"id": "arena", "label": "ARENA", "value": String(Teams.ARENAS[_arena]["name"])},
		{"id": "quarters", "label": "PERIODS", "value": str(_quarters)},
		{"id": "length", "label": "MINUTES", "value": str(_quarter_minutes)},
		{"id": "opponent", "label": "OPPONENT",
			"value": "PLAYER 2" if _opponent_is_human else "CPU"},
		{"id": "tip", "label": "TIP OFF"},
	]


func _team_label(index: int) -> String:
	var team: Dictionary = _teams[index]
	return "%s  %d OVR" % [String(team["abbr"]), League.team_ovr(team)]


func on_adjust(id: String, step: int) -> void:
	match id:
		"home":
			_home = wrapi(_home + step, 0, _teams.size())
			if _home == _away:
				_away = wrapi(_away + step, 0, _teams.size())
		"away":
			_away = wrapi(_away + step, 0, _teams.size())
			if _away == _home:
				_home = wrapi(_home + step, 0, _teams.size())
		"mode":
			_mode = MatchSetup.Mode.THREE_V_THREE \
				if _mode == MatchSetup.Mode.FIVE_V_FIVE else MatchSetup.Mode.FIVE_V_FIVE
		"arena":
			_arena = wrapi(_arena + step, 0, Teams.ARENAS.size())
		"quarters":
			_quarters = clampi(_quarters + step, 1, 4)
		"length":
			_quarter_minutes = clampi(_quarter_minutes + step, 1, 12)
		"opponent":
			_opponent_is_human = not _opponent_is_human
	_refresh()


func _on_chosen(id: String) -> void:
	if id != "tip":
		on_adjust(id, 1)
		return
	var setup := MatchSetup.new()
	setup.home = _teams[_home]
	setup.away = _teams[_away]
	setup.mode = _mode
	setup.arena = _arena
	setup.quarters = _quarters
	setup.quarter_seconds = _quarter_minutes * 60
	setup.difficulty = int(Settings.get_value("difficulty"))
	setup.home_controller = MatchSetup.Controller.LOCAL_1
	setup.away_controller = MatchSetup.Controller.LOCAL_2 if _opponent_is_human \
		else MatchSetup.Controller.AI
	Game.setup = setup
	Game.goto("res://scenes/match.tscn")


func _draw_side_panel(scale: float) -> void:
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.78)
	var half := rect.size.x * 0.5
	_draw_roster(Rect2(rect.position, Vector2(half, rect.size.y)), _teams[_home], scale)
	_draw_roster(Rect2(Vector2(rect.position.x + half, rect.position.y),
		Vector2(half, rect.size.y)), _teams[_away], scale)
	draw_line(Vector2(rect.position.x + half, rect.position.y + UiTheme.L * scale),
		Vector2(rect.position.x + half, rect.end.y - UiTheme.L * scale),
		UiTheme.LINE, UiTheme.HAIRLINE)


func _draw_roster(rect: Rect2, team: Dictionary, scale: float) -> void:
	var pad := UiTheme.XL * scale
	var x := rect.position.x + pad
	draw_rect(Rect2(Vector2(x, rect.position.y + pad),
		Vector2(rect.size.x - pad * 2.0, 5.0 * scale)), Color(team["primary"]))

	UiTheme.label(self, League.team_full(team).to_upper(),
		Vector2(x, rect.position.y + 52.0 * scale), UiTheme.display_font(),
		UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
	UiTheme.label(self, "%s CONFERENCE" % Teams.conference_name(int(team["conf"])).to_upper(),
		Vector2(x, rect.position.y + 74.0 * scale), UiTheme.text_font(),
		UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)

	var roster: Array = team["roster"]
	var count := mini(roster.size(), 8)
	for i in count:
		var player: Dictionary = roster[i]
		var y := rect.position.y + (108.0 + float(i) * 26.0) * scale
		UiTheme.label(self, "%2d" % int(player["num"]), Vector2(x, y),
			UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)
		UiTheme.label(self, League.short_name(player),
			Vector2(x + 34.0 * scale, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT)
		UiTheme.label(self, League.POS_NAMES[int(player["pos"])],
			Vector2(x + 168.0 * scale, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
		UiTheme.label_right(self, str(int(player["ovr"])),
			rect.end.x - pad, y, UiTheme.bold_font(),
			UiTheme.size(UiTheme.LABEL, scale),
			UiTheme.GOLD if i < 5 else UiTheme.TEXT_DIM)
