extends Node2D

@onready var players_container: Node2D = $Players
@onready var items_container: Node2D = $Items
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

const PLAYER_SCENE = preload("res://player/player.tscn")

func _ready() -> void:
	multiplayer_spawner.spawn_path = players_container.get_path()
	multiplayer_spawner.spawn_function = _custom_spawn_player

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_spawn_player)
		multiplayer.peer_disconnected.connect(_despawn_player)

		# Spawn host/solo player
		_spawn_player(1)

func _custom_spawn_player(data: Variant) -> Node:
	var peer_id = data as int
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.global_position = Vector2(80, 72)
	return player

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Spawning player for peer: ", peer_id)
	multiplayer_spawner.spawn(peer_id)

func _despawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node = players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
