@tool
class_name Dispenser02
extends StaticBody2D

## Dispenser 02 - Directional Energy Relay Beacon & Synchronized Metronome
## Shoots energy bullets in a configurable direction.
## Supports two operation modes:
## 1. RELE_RECEPTOR: Absorbs incoming energy, waits relay_delay, and shoots forward.
## 2. METRONOMO_SINCRONIZADO: Fires on a strict rhythmic global beat (sync_interval + sync_offset) that never desyncs.

enum Direction {
	DERECHA,
	ABAJO,
	IZQUIERDA,
	ARRIBA
}

enum Mode {
	RELE_RECEPTOR,          ## Dispara al recibir una bala de otra baliza (o al inicio si auto_start_shoot es true)
	METRONOMO_SINCRONIZADO  ## Dispara a un compás rítmico fijo y continuo que nunca se desincroniza
}

const ENERGY_BULLET_SCENE = preload("res://objects/bullet/energy_bullet.tscn")

@export var mode: Mode = Mode.RELE_RECEPTOR:
	set(val):
		mode = val
		notify_property_list_changed()

@export var shoot_direction: Direction = Direction.DERECHA:
	set(val):
		shoot_direction = val
		_update_visual_orientation()

@export_group("Modo Metrónomo Sincronizado")
@export var sync_interval: float = 3.0 ## Duración del ciclo completo entre disparos (ej: 3.0 segundos)
@export var sync_offset: float = 0.0   ## Desfase de disparo dentro del ciclo (ej: 0.0s, 1.5s para disparos alternados)

@export_group("Modo Relé Receptor")
@export var auto_start_shoot: bool = false
@export var initial_delay: float = 0.5
@export var relay_delay: float = 1.0   ## Tiempo de espera (en segundos) al recibir una bala antes de reenviarla

@export_group("Parámetros Generales")
@export var bullet_speed: float = 70.0
@export var active: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var spawn_marker: Marker2D = $SpawnMarker
@onready var receptor_area: Area2D = $ReceptorArea

var is_holding_energy: bool = false
var _metronome_timer: Timer = null

func _ready() -> void:
	_update_visual_orientation()

	if Engine.is_editor_hint():
		return

	if receptor_area:
		receptor_area.area_entered.connect(_on_receptor_area_entered)

	if not active:
		return

	if mode == Mode.METRONOMO_SINCRONIZADO:
		_setup_metronome()
	elif mode == Mode.RELE_RECEPTOR and auto_start_shoot:
		get_tree().create_timer(max(0.1, initial_delay)).timeout.connect(func():
			if active and is_inside_tree():
				shoot_energy()
		)

func _setup_metronome() -> void:
	_metronome_timer = Timer.new()
	_metronome_timer.one_shot = false
	_metronome_timer.wait_time = max(0.3, sync_interval)
	_metronome_timer.timeout.connect(func():
		if active and is_inside_tree():
			shoot_energy()
	)
	add_child(_metronome_timer)

	if sync_offset > 0.0:
		get_tree().create_timer(sync_offset).timeout.connect(func():
			if active and is_inside_tree():
				shoot_energy()
				_metronome_timer.start()
		)
	else:
		shoot_energy()
		_metronome_timer.start()

func _update_visual_orientation() -> void:
	if not is_inside_tree():
		return

	# La baliza siempre se mantiene en su orientación vertical normal
	if sprite:
		sprite.rotation = 0.0

	var dir = get_direction_vector()
	if spawn_marker:
		spawn_marker.position = dir * 10.0

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

	# En modo metrónomo, el compás es autónomo; en modo relé, absorbe y reenvía
	if mode == Mode.RELE_RECEPTOR:
		is_holding_energy = true
		_play_charge_effect()

		get_tree().create_timer(relay_delay).timeout.connect(func():
			is_holding_energy = false
			if active and is_inside_tree():
				shoot_energy()
		)
	else:
		# En modo metrónomo, simplemente muestra el efecto visual de impacto/absorción
		_play_charge_effect()

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
		world_map.add_child.call_deferred(bullet)

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
