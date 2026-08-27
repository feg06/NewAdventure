class_name Checkpoint
extends Area2D

## Checkpoint Area / Respawn Point
## When a player touches this area, it updates their respawn point.

@export var is_active: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return

	if body is Player and is_instance_valid(body):
		body.set_checkpoint(global_position)
