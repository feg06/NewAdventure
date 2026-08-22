extends Node

## Global Events Bus

signal player_spawned(peer_id: int, player: CharacterBody2D)
signal player_despawned(peer_id: int)
signal attack_performed(player_id: int, direction: Vector2)
signal item_grabbed(item: Node2D, player: CharacterBody2D)
signal item_dropped(item: Node2D, position: Vector2)
signal room_changed(player_id: int, room_coords: Vector2i)
