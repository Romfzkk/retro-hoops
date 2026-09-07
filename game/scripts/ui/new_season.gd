extends MenuScreen

# Pick a franchise and start a career. Overwriting an existing save needs a
# second press, since there is only one slot.

var _teams: Array
var _pick := 0
var _confirm_overwrite := false


func _ready() -> void:
	super()
	_teams = Game.exhibition_league()["teams"]
	title = "NEW SEASON"
	subtitle = "Choose a franchise"
	footer = "Change  A/D    Start  Enter    Back  Esc"
	chosen.connect(_on_chosen)
	cancelled.connect(func(): Game.goto("res://scenes/main_menu.tscn"))
	_refresh()


func _refresh() -> void:
	var label := "START SEASON"
	if Game.has_career():
		label = "OVERWRITE SAVE?" if _confirm_overwrite else "START SEASON"
	rows = [
		{"id": "team", "label": "FRANCHISE", "value": String(_teams[_pick]["abbr"])},
		{"id": "start", "label": label},
	]


func on_adjust(id: String, step: int) -> void:
	if id != "team":
		return
	_pick = wrapi(_pick + step, 0, _teams.size())
	_confirm_overwrite = false
	_refresh()


func _on_chosen(id: String) -> void:
	if id == "team":
		on_adjust("team", 1)
		return
	if Game.has_career() and not _confirm_overwrite:
		_confirm_overwrite = true
		_refresh()
		return
	Game.start_career(_pick)
	Game.goto("res://scenes/season_hub.tscn")


func _draw_side_panel(scale: float) -> void:
	var team: Dictionary = _teams[_pick]
	var rect := detail_rect(scale)
	UiTheme.panel(self, rect, UiTheme.SURFACE, 0.78)
	var pad := UiTheme.XL * scale

	draw_rect(Rect2(Vector2(rect.position.x + pad, rect.position.y + pad),
		Vector2(rect.size.x - pad * 2.0, 6.0 * scale)), Color(team["primary"]))
	UiTheme.label(self, League.team_full(team).to_upper(),
		Vector2(rect.position.x + pad, rect.position.y + 62.0 * scale),
		UiTheme.display_font(), UiTheme.size(UiTheme.HEAD, scale), UiTheme.TEXT)
	UiTheme.label(self, "%s CONFERENCE   TEAM RATING %d"
		% [Teams.conference_name(int(team["conf"])).to_upper(), League.team_ovr(team)],
		Vector2(rect.position.x + pad, rect.position.y + 88.0 * scale),
		UiTheme.text_font(), UiTheme.size(UiTheme.LABEL, scale), UiTheme.TEXT_DIM)

	var roster: Array = team["roster"]
	var y := rect.position.y + 132.0 * scale
	UiTheme.label(self, "ROTATION", Vector2(rect.position.x + pad, y),
		UiTheme.bold_font(), UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
	y += 24.0 * scale
	for i in mini(roster.size(), 10):
		var player: Dictionary = roster[i]
		UiTheme.label(self, "%2d  %s" % [int(player["num"]), League.player_name(player)],
			Vector2(rect.position.x + pad, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.LABEL, scale),
			UiTheme.TEXT if i < 5 else UiTheme.TEXT_DIM)
		UiTheme.label(self, League.POS_NAMES[int(player["pos"])],
			Vector2(rect.position.x + rect.size.x * 0.55, y), UiTheme.text_font(),
			UiTheme.size(UiTheme.MICRO, scale), UiTheme.TEXT_DIM)
		UiTheme.label_right(self, str(int(player["ovr"])), rect.end.x - pad, y,
			UiTheme.bold_font(), UiTheme.size(UiTheme.LABEL, scale),
			UiTheme.GOLD if i < 5 else UiTheme.TEXT_DIM)
		y += 26.0 * scale
