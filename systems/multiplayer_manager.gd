extends Node

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const MAX_CLIENTS: int = 8

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_list_updated

var players: Dictionary = {}
var is_host: bool = false
var is_solo: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func start_solo_game() -> void:
	is_solo = true
	is_host = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 1)
	if error != OK:
		push_warning("Could not create local solo server: %s. Using local peer." % error)
	multiplayer.multiplayer_peer = peer
	players[1] = {"name": "Player 1"}
	_load_game_scene()

func host_game(port: int = DEFAULT_PORT) -> Error:
	is_solo = false
	is_host = true
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		push_error("Failed to host server on port %d: %s" % [port, error])
		return error
	multiplayer.multiplayer_peer = peer
	players[1] = {"name": "Host"}
	_load_game_scene()
	return OK

func join_game(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	is_solo = false
	is_host = false
	var peer = ENetMultiplayerPeer.new()
	var target_ip = ip if ip != "" else DEFAULT_IP
	var error = peer.create_client(target_ip, port)
	if error != OK:
		push_error("Failed to connect to %s:%d: %s" % [target_ip, port, error])
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func _load_game_scene() -> void:
	get_tree().change_scene_to_file("res://world/maps/world.tscn")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if multiplayer.is_server():
		players[id] = {"name": "Player %d" % id}
		player_list_updated.emit()

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	players.erase(id)
	player_list_updated.emit()
	Events.player_despawned.emit(id)

func _on_connected_to_server() -> void:
	print("Successfully connected to host server!")
	connection_succeeded.emit()
	_load_game_scene()

func _on_connection_failed() -> void:
	print("Connection failed.")
	connection_failed.emit()
	reset_network()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	server_disconnected.emit()
	reset_network()
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func reset_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	is_solo = false
