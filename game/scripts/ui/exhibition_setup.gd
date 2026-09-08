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
var _rosters: Array[Tree] = []


func _ready() -> void:
	art_banner = "tipoff"
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
	_build_roster_tables()
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
			"value": "PAD 2" if _opponent_is_human else "CPU",
			"hint": "Player one: keyboard or first pad. Player two: second pad."},
		{"id": "tip", "label": "TIP OFF"},
	]
	_populate_rosters()


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


func _build_roster_tables() -> void:
	for index in 2:
		var table := Tree.new()
		table.hide_root = true
		table.columns = 3
		table.column_titles_visible = true
		table.set_column_title(0, "PLAYER")
		table.set_column_title(1, "POS")
		table.set_column_title(2, "OVR")
		table.set_column_custom_minimum_width(0, 150)
		for column in [1, 2]:
			table.set_column_custom_minimum_width(column, 42)
			table.set_column_expand(column, false)
		table.add_theme_font_override("font", UiTheme.text_font())
		table.add_theme_font_override("title_button_font", UiTheme.bold_font())
		table.add_theme_color_override("font_color", UiTheme.TEXT)
		table.add_theme_constant_override("v_separation", 12)
		add_child(table)
		_rosters.append(table)


func _populate_rosters() -> void:
	for index in _rosters.size():
		var table := _rosters[index]
		var team: Dictionary = _teams[_home if index == 0 else _away]
		table.clear()
		var root := table.create_item()
		for player: Dictionary in team["roster"]:
			var item := table.create_item(root)
			item.set_text(0, "#%d  %s" % [player["num"], League.short_name(player)])
			item.set_text(1, League.POS_NAMES[int(player["pos"])])
			item.set_text(2, str(player["ovr"]))
			for column in 3:
				item.set_selectable(column, false)


func _process(delta: float) -> void:
	super(delta)
	var scale := UiTheme.scale_for(view())
	var rect := detail_rect(scale)
	var gap := 16.0 * scale
	for index in _rosters.size():
		var table := _rosters[index]
		table.visible = _wide_details(scale) or _show_details
		table.position = rect.position + Vector2((rect.size.x + gap) * 0.5 * index, 44.0 * scale)
		table.size = Vector2((rect.size.x - gap) * 0.5, maxf(80.0, rect.size.y - 44.0 * scale))
		table.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.LABEL, scale))
		table.add_theme_font_size_override("title_button_font_size", UiTheme.size(UiTheme.LABEL, scale))


func _draw_side_panel(scale: float) -> void:
	var rect := detail_rect(scale)
	for index in 2:
		var team: Dictionary = _teams[_home if index == 0 else _away]
		var at := rect.position + Vector2((rect.size.x + 16.0 * scale) * 0.5 * index, 0.0)
		var width := (rect.size.x - 16.0 * scale) * 0.5
		draw_rect(Rect2(at, Vector2(width, 3.0)), Color(team["primary"]))
		draw_string(UiTheme.display_font(), at + Vector2(0.0, 30.0 * scale),
			League.team_full(team).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, width,
			UiTheme.size(UiTheme.SUB, scale), UiTheme.TEXT)
