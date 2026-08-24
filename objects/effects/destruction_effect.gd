class_name DestructionEffect
extends AnimatedSprite2D

func _ready() -> void:
	play("default")
	animation_finished.connect(queue_free)
