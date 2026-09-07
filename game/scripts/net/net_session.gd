extends Node

# Autoload: the network session. One host, one visiting client, direct IP or
# found on the LAN. The host is authoritative - it runs physics, the AI and the
# rules, and the client uploads its intent and draws what it is sent.

signal peer_joined(id: int)
signal peer_left(id: int)
signal connection_failed(reason: String)
signal connected_to_host()
signal lobby_changed()

const DEFAULT_PORT := 27015
const DISCOVERY_PORT := 27016
const DISCOVERY_MAGIC := "RETROHOOPS/1"
const BROADCAST_INTERVAL := 1.0
const LOBBY_TIMEOUT := 4.0

enum Role { OFFLINE, HOST, CLIENT }

var role: Role = Role.OFFLINE
var client_id := 0
var host_team := 0
var lobby_name := ""
## Intent the visiting client uploaded this frame, applied by the host.
var remote_intent := PlayerIntent.new()
var remote_switch_requested := false

var _discovery: PacketPeerUDP
var _broadcast: PacketPeerUDP
var _broadcast_timer := 0.0
var _found: Dictionary = {}


# Dev entry points so the netcode can be exercised without two people at two
# keyboards: `-- --net-host` and `-- --net-join <address>`.
func _ready() -> void:
	if FrameCapture.has_flag("--net-host"):
		host_game(DEFAULT_PORT, 0, "smoke test")
		peer_joined.connect(func(_id):
			start_match({"home": 0, "away": 16, "host_team": 0, "arena": 0,
				"mode": MatchSetup.Mode.FIVE_V_FIVE, "quarters": 1,
				"seconds": 120, "difficulty": 1}))
	var address := FrameCapture.argument("--net-join")
	if not address.is_empty():
		join_game(address, DEFAULT_PORT)


# Both sides generate the same exhibition league from a fixed seed, so a match
# only needs team ids and rules on the wire, not roster data.
func start_match(config: Dictionary) -> void:
	if role != Role.HOST:
		return
	_begin_match.rpc(config)
	_apply_match(config)


@rpc("authority", "call_remote", "reliable")
func _begin_match(config: Dictionary) -> void:
	_apply_match(config)


func _apply_match(config: Dictionary) -> void:
	var teams: Array = Game.exhibition_league()["teams"]
	var setup := MatchSetup.new()
	setup.home = teams[int(config["home"]) % teams.size()]
	setup.away = teams[int(config["away"]) % teams.size()]
	setup.arena = int(config.get("arena", 0))
	setup.mode = int(config.get("mode", MatchSetup.Mode.FIVE_V_FIVE)) as MatchSetup.Mode
	setup.quarters = int(config.get("quarters", 4))
	setup.quarter_seconds = int(config.get("seconds", 300))
	setup.difficulty = int(config.get("difficulty", 1))
	setup.online = true
	host_team = int(config.get("host_team", 0))
	Game.setup = setup
	Game.goto("res://scenes/match.tscn")


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


## Team index the local player drives. The host keeps its chosen side.
func local_team() -> int:
	if role == Role.CLIENT:
		return 1 - host_team
	return host_team


func host_game(port: int, team_index: int, name: String) -> Error:
	shutdown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		connection_failed.emit("Cannot open port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	role = Role.HOST
	host_team = team_index
	lobby_name = name
	_start_broadcasting(port)
	lobby_changed.emit()
	return OK


func join_game(address: String, port: int) -> Error:
	shutdown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Cannot reach %s:%d" % [address, port])
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	role = Role.CLIENT
	lobby_changed.emit()
	return OK


func shutdown() -> void:
	_stop_broadcasting()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server",
			"connection_failed", "server_disconnected"]:
		for connection in multiplayer.get_signal_connection_list(signal_name):
			multiplayer.disconnect(signal_name, connection["callable"])
	role = Role.OFFLINE
	client_id = 0
	lobby_changed.emit()


func has_guest() -> bool:
	return role == Role.HOST and client_id != 0


func _on_peer_connected(id: int) -> void:
	client_id = id
	peer_joined.emit(id)
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if client_id == id:
		client_id = 0
	peer_left.emit(id)
	lobby_changed.emit()


func _on_connected() -> void:
	connected_to_host.emit()
	lobby_changed.emit()


func _on_connect_failed() -> void:
	connection_failed.emit("The host refused the connection")
	shutdown()


func _on_server_gone() -> void:
	connection_failed.emit("The host closed the game")
	shutdown()


# --- LAN discovery --------------------------------------------------------
# The host shouts a single line on a UDP port; browsers listen. Enough to find
# a game on the same network without typing an address.

func _start_broadcasting(port: int) -> void:
	_broadcast = PacketPeerUDP.new()
	_broadcast.set_broadcast_enabled(true)
	_broadcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0
	set_process(true)


func _stop_broadcasting() -> void:
	if _broadcast != null:
		_broadcast.close()
		_broadcast = null
	if _discovery != null:
		_discovery.close()
		_discovery = null


func start_browsing() -> void:
	_found.clear()
	_discovery = PacketPeerUDP.new()
	var err := _discovery.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LAN browse unavailable: %s" % error_string(err))
		_discovery = null
		return
	set_process(true)


func stop_browsing() -> void:
	if _discovery != null:
		_discovery.close()
		_discovery = null


## Hosts seen recently, as {address, port, name}.
func lobbies() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var list: Array = []
	for key in _found:
		var entry: Dictionary = _found[key]
		if now - float(entry["seen"]) <= LOBBY_TIMEOUT:
			list.append(entry)
	list.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	return list


func _process(delta: float) -> void:
	if _broadcast != null:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			var line := "%s|%s|%d" % [DISCOVERY_MAGIC, lobby_name, DEFAULT_PORT]
			_broadcast.put_packet(line.to_utf8_buffer())
	if _discovery != null:
		while _discovery.get_available_packet_count() > 0:
			var packet := _discovery.get_packet().get_string_from_utf8()
			var parts := packet.split("|")
			if parts.size() != 3 or parts[0] != DISCOVERY_MAGIC:
				continue
			var address := _discovery.get_packet_ip()
			_found[address] = {
				"address": address,
				"port": int(parts[2]),
				"name": parts[1],
				"seen": Time.get_ticks_msec() / 1000.0,
			}
