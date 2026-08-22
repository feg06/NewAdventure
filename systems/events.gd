extends Node

## Global Events Bus

@warning_ignore("unused_signal")
signal player_spawned(peer_id: int, player: CharacterBody2D)
@warning_ignore("unused_signal")
signal player_despawned(peer_id: int)
@warning_ignore("unused_signal")
signal attack_performed(player_id: int, direction: Vector2)
@warning_ignore("unused_signal")
signal item_grabbed(item: Node2D, player: CharacterBody2D)
@warning_ignore("unused_signal")
signal item_dropped(item: Node2D, position: Vector2)
@warning_ignore("unused_signal")
signal room_changed(player_id: int, room_coords: Vector2i)
