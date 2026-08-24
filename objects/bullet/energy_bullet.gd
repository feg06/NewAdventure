class_name EnergyBullet
extends Area2D

const DESTRUCTION_EFFECT = preload("res://objects/effects/destruction_effect.tscn")

@export var speed: float = 70.0
@export var damage: int = 1
@export var lifetime: float = 8.0

var direction: Vector2 = Vector2.RIGHT
var launcher_node: Node = null

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

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

	# Si choca contra otro Dispenser02 (baliza receptora)
	if body is Dispenser02:
		body.receive_energy_bullet(self)
		queue_free()
		return

	# Si choca contra el jugador
	if body.has_method("take_damage"):
		body.take_damage(damage)

	# Chocó contra un muro u obstáculo
	_destroy()

func _on_area_entered(area: Area2D) -> void:
	if area.get_parent() == launcher_node:
		return

	var parent = area.get_parent()
	if parent is Dispenser02:
		parent.receive_energy_bullet(self)
		queue_free()
		return
	elif parent and parent.has_method("take_damage"):
		parent.take_damage(damage)
		_destroy()

func _destroy() -> void:
	var effect = DESTRUCTION_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child(effect)
	queue_free()
