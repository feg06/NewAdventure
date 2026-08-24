class_name NormalBullet
extends Area2D

const DESTRUCTION_EFFECT = preload("res://objects/effects/destruction_effect.tscn")

@export var speed: float = 75.0
@export var damage: int = 1
@export var lifetime: float = 5.0

var direction: Vector2 = Vector2.LEFT
var launcher_node: Node = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	get_tree().create_timer(lifetime).timeout.connect(func():
		if is_inside_tree():
			_destroy()
	)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == launcher_node:
		return

	if body.has_method("take_damage"):
		body.take_damage(damage)

	_destroy()

func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() == launcher_node:
		return

	# Si choca con un escudo o área que recibe daño
	var parent = area.get_parent()
	if parent and parent.has_method("take_damage"):
		parent.take_damage(damage)
		_destroy()

func _destroy() -> void:
	var effect = DESTRUCTION_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(effect)
	queue_free()
