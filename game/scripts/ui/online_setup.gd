extends MenuScreen

# Host a game or join one. Hosts announce themselves on the LAN, so the common
# case is picking a name off a list; the address field is there for anything
# that discovery cannot reach.

const REFRESH_INTERVAL := 0.6

var _hosting := true
var _teams: Array
var _home := 0
var _away := 1
var _address := "127.0.0.1"
var _status := ""
var _address_field: LineEdit
var _refresh := 0.0
var _connection_help: Label


func _ready() -> void:
	super()
	_teams = Game.exhibition_league()["teams"]
	_away = 16 % _teams.size()
	title = "ONLINE"
	subtitle = "Two players, one court"
	footer = "Change  A/D    Select  Enter    Back  Esc"
	chosen.connect(_on_chosen)
	cancelled.connect(_leave)

	Net.connection_failed.connect(func(reason): _status = reason)
	Net.peer_joined.connect(func(_id): _status = "Opponent connected.")
	Net.peer_left.connect(func(_id): _status = "Opponent left.")
	Net.connected_to_host.connect(func(): _status = "Connected. Waiting for tip off.")

	_connection_help = Label.new()
	_connection_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connection_help.add_theme_font_override("font", UiTheme.text_font())
	_connection_help.add_theme_color_override("font_color", UiTheme.TEXT)
	add_child(_connection_help)
	_build_address_field()
	Net.start_browsing()
	_refresh_rows()


func _build_address_field() -> void:
	_address_field = LineEdit.new()
	_address_field.text = _address
	_address_field.placeholder_text = "host address"
	_address_field.add_theme_font_override("font", UiTheme.text_font())
	_address_field.add_theme_color_override("font_color", UiTheme.TEXT)
	_address_field.text_changed.connect(func(value): _address = value)
	add_child(_address_field)


func _process(delta: float) -> void:
	super(delta)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_INTERVAL
		_refresh_rows()
	_position_address_field()


func _refresh_rows() -> void:
	var new_rows: Array[Dictionary] = [
		{"id": "mode", "label": "ROLE", "value": "HOST" if _hosting else "JOIN"},
	]
	if _hosting:
		new_rows.append_array([
			{"id": "home", "label": "YOUR TEAM", "value": String(_teams[_home]["abbr"])},
			{"id": "away", "label": "OPPONENT", "value": String(_teams[_away]["abbr"])},
			{"id": "open", "label": "OPEN LOBBY", "enabled": not Net.is_online()},
			{"id": "tip", "label": "TIP OFF", "enabled": Net.has_guest()},
		])
	else:
		for lobby in Net.lobbies():
			new_rows.append({
				"id": "lobby:%s:%d" % [String(lobby["address"]), int(lobby["port"])],
				"label": String(lobby["name"]).to_upper(),
				"value": String(lobby["address"]),
			})
		new_rows.append({"id": "connect", "label": "CONNECT TO ADDRESS"})
	new_rows.append({"id": "back", "label": "BACK"})
	rows = new_rows
	selected = clampi(selected, 0, rows.size() - 1)


func on_adjust(id: String, step: int) -> void:
	match id:
		"mode":
			_hosting = not _hosting
			Net.shutdown()
			if _hosting:
				Net.stop_browsing()
			else:
				Net.start_browsing()
			_status = ""
		"home":
			_home = wrapi(_home + step, 0, _teams.size())
			if _home == _away:
				_away = wrapi(_away + step, 0, _teams.size())
		"away":
			_away = wrapi(_away + step, 0, _teams.size())
			if _away == _home:
				_home = wrapi(_home + step, 0, _teams.size())
	_refresh_rows()


func _on_chosen(id: String) -> void:
	if id.begins_with("lobby:"):
		var parts := id.split(":")
		_join(parts[1], int(parts[2]))
		return
	match id:
		"mode", "home", "away":
			on_adjust(id, 1)
		"open":
			_open_lobby()
		"tip":
			_tip_off()
		"connect":
			_join(_address.strip_edges(), Net.DEFAULT_PORT)
		"back":
			_leave()


func _open_lobby() -> void:
	var name := "%s lobby" % String(Settings.get_value("player_name"))
	if Net.host_game(Net.DEFAULT_PORT, 0, name) == OK:
		_status = "Waiting for an opponent on port %d." % Net.DEFAULT_PORT
	_refresh_rows()


func _join(address: String, port: int) -> void:
	if address.is_empty():
		_status = "Enter an address first."
		return
	_status = "Connecting to %s..." % address
	Net.join_game(address, port)


func _tip_off() -> void:
	Net.start_match({
		"home": _home, "away": _away, "host_team": 0,
		"arena": 0, "mode": MatchSetup.Mode.FIVE_V_FIVE,
		"quarters": 4,
		"seconds": int(Settings.get_value("quarter_minutes")) * 60,
		"difficulty": int(Settings.get_value("difficulty")),
	})


func _leave() -> void:
	Net.stop_browsing()
	Net.shutdown()
	Game.goto("res://scenes/main_menu.tscn")


func _position_address_field() -> void:
	var scale := UiTheme.scale_for(view())
	var details_visible := _wide_details(scale) or _show_details
	var rect := detail_rect(scale)
	var pad := 20.0 * scale
	_address_field.visible = not _hosting and details_visible
	_address_field.position = rect.position + Vector2(pad, rect.size.y - 60.0 * scale)
	_address_field.size = Vector2(rect.size.x - pad * 2.0, 46.0 * scale)
	_address_field.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.BODY, scale))
	_connection_help.visible = details_visible
	_connection_help.position = rect.position + Vector2(pad, pad)
	_connection_help.size = Vector2(rect.size.x - pad * 2.0, maxf(60.0, rect.size.y - 100.0 * scale))
	_connection_help.add_theme_font_size_override("font_size", UiTheme.size(UiTheme.BODY, scale))
	_connection_help.text = "Host: open a lobby, then choose Tip Off when your opponent connects.\n\nJoin: select a nearby lobby or enter the host's address below. Internet games require the host to forward UDP port %d." % Net.DEFAULT_PORT
	if not _hosting and Net.lobbies().is_empty() and not Net.is_online():
		_connection_help.text += "\n\nNo nearby lobbies found."
	if not _status.is_empty():
		_connection_help.text += "\n\n" + _status


func _draw_side_panel(_scale: float) -> void:
	pass
