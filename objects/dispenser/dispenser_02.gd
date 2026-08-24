@tool
class_name Dispenser02
extends StaticBody2D

## Dispenser 02 - Directional Energy Relay Beacon
## Shoots energy bullets in a configurable direction. If it receives an energy bullet from another beacon,
## it holds the energy for 1 second and then shoots it forward, creating circuits and ping-pong patterns.

enum Direction {
	DERECHA,
	ABAJO,
	IZQUIERDA,
	ARRIBA
}

const ENERGY_BULLET_SCENE = preload("res://objects/bullet/energy_bullet.tscn")

@export var shoot_direction: Direction = Direction.DERECHA:
	set(val):
		shoot_direction = val
		_update_visual_orientation()

@export var auto_start_shoot: bool = false
@export var initial_delay: float = 0.5
@export var relay_delay: float = 1.0 ## Tiempo de espera (en segundos) al recibir una bala antes de reenviarla
@export var bullet_speed: float = 70.0
@export var active: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var spawn_marker: Marker2D = $SpawnMarker
@onready var receptor_area: Area2D = $ReceptorArea

var is_holding_energy: bool = false

func _ready() -> void:
	_update_visual_orientation()

	if Engine.is_editor_hint():
		return

	if receptor_area:
		receptor_area.area_entered.connect(_on_receptor_area_entered)

	if auto_start_shoot and active:
		get_tree().create_timer(max(0.1, initial_delay)).timeout.connect(func():
			if active and is_inside_tree():
				shoot_energy()
		)

func _update_visual_orientation() -> void:
	if not is_inside_tree():
		return

	var angle: float = 0.0
	match shoot_direction:
		Direction.DERECHA:
			angle = 0.0
		Direction.ABAJO:
			angle = PI / 2.0
		Direction.IZQUIERDA:
			angle = PI
		Direction.ARRIBA:
			angle = -PI / 2.0

	if sprite:
		sprite.rotation = angle
	if spawn_marker:
		spawn_marker.position = Vector2.RIGHT.rotated(angle) * 10.0

func get_direction_vector() -> Vector2:
	match shoot_direction:
		Direction.DERECHA:
			return Vector2.RIGHT
		Direction.ABAJO:
			return Vector2.DOWN
		Direction.IZQUIERDA:
			return Vector2.LEFT
		Direction.ARRIBA:
			return Vector2.UP
	return Vector2.RIGHT

func receive_energy_bullet(_bullet: EnergyBullet) -> void:
	if not active or is_holding_energy:
		return

	is_holding_energy = true

	# Efecto visual de carga/retención de energía
	_play_charge_effect()

	# Esperar el tiempo de retención (1 segundo) y continuar el recorrido
	get_tree().create_timer(relay_delay).timeout.connect(func():
		is_holding_energy = false
		if active and is_inside_tree():
			shoot_energy()
	)

func _on_receptor_area_entered(area: Area2D) -> void:
	if area is EnergyBullet and area.launcher_node != self:
		receive_energy_bullet(area)
		area.queue_free()

func shoot_energy() -> void:
	if not active or _is_blocked():
		return

	var dir = get_direction_vector()
	var spawn_pos = spawn_marker.global_position if is_instance_valid(spawn_marker) else (global_position + dir * 10.0)

	var bullet = ENERGY_BULLET_SCENE.instantiate()
	bullet.global_position = spawn_pos
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.launcher_node = self

	var world_map = get_tree().current_scene
	if world_map:
		world_map.add_child(bullet)

func _is_blocked() -> bool:
	var space = get_world_2d().direct_space_state
	if not space:
		return false

	var dir = get_direction_vector()
	var start_pos = global_position
	var end_pos = start_pos + dir * 18.0

	var params = PhysicsRayQueryParameters2D.create(start_pos, end_pos, 1) # Layer 1: Muros
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var result = space.intersect_ray(params)
	return not result.is_empty()

func _play_charge_effect() -> void:
	if not sprite:
		return
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.8, 1.8, 1.2, 1.0), 0.15)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)
