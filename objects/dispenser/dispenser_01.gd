class_name Dispenser01
extends StaticBody2D

## Dispenser 01 - Horizontal/Dual Bullet Cannon Trap
## Shoots bullets from left and/or right sides, automatically detecting and skipping blocked wall sides.

const BULLET_SCENE = preload("res://objects/bullet/bullet.tscn")

@export var shoot_interval: float = 2.5
@export var initial_delay: float = 0.0
@export var active: bool = true
@export var shoot_left: bool = true
@export var shoot_right: bool = true
@export var bullet_speed: float = 75.0

@onready var timer: Timer = $Timer
@onready var sprite: Sprite2D = $Sprite2D
@onready var spawn_left: Marker2D = $SpawnLeft
@onready var spawn_right: Marker2D = $SpawnRight

func _ready() -> void:
	timer.wait_time = max(0.2, shoot_interval)
	timer.timeout.connect(_on_timer_timeout)

	if not active:
		return

	if initial_delay > 0.0:
		get_tree().create_timer(initial_delay).timeout.connect(func():
			if active and is_inside_tree():
				timer.start()
		)
	else:
		timer.start()

func _on_timer_timeout() -> void:
	if not active:
		return

	# Si es multijugador, solo el servidor/autoridad decide el spawn
	var is_multi = multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_multi and not multiplayer.is_server():
		return

	_shoot_active_sides()

func _shoot_active_sides() -> void:
	if shoot_left and not _is_blocked(Vector2.LEFT):
		_spawn_bullet(Vector2.LEFT, spawn_left.global_position)

	if shoot_right and not _is_blocked(Vector2.RIGHT):
		_spawn_bullet(Vector2.RIGHT, spawn_right.global_position)

func _is_blocked(dir: Vector2) -> bool:
	if not is_inside_tree():
		return false

	var space = get_world_2d().direct_space_state
	if not space:
		return false

	var norm_dir = dir.normalized()
	var start_pos = global_position
	var end_pos = start_pos + norm_dir * 18.0 # Escaneo de celda de 16px

	var params = PhysicsRayQueryParameters2D.create(start_pos, end_pos, 1) # Layer 1: Muros
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var result = space.intersect_ray(params)
	return not result.is_empty()

func _spawn_bullet(dir: Vector2, spawn_pos: Vector2) -> void:
	var bullet = BULLET_SCENE.instantiate()
	bullet.global_position = spawn_pos
	bullet.direction = dir.normalized()
	bullet.speed = bullet_speed
	bullet.launcher_node = self

	var world_map = get_tree().current_scene
	if world_map:
		world_map.add_child.call_deferred(bullet)
