class_name Player
extends CharacterBody2D

const DEAD_EFFECT = preload("res://objects/effects/dead_effect.tscn")
const HUD_SCENE = preload("res://ui/hud/hud.tscn")

@export var move_speed: float = 70.0
@export var normalize_diagonal: bool = false # Si es false, mantiene 100% de velocidad en cada eje estilo retro sin frenarse al pulsar diagonales
@export var sheath_time: float = 4.0
@export var max_health: int = 5
@export var current_health: int = 5

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox_area: Area2D = $HitboxArea
@onready var hitbox_shape: CollisionShape2D = $HitboxArea/HitboxShape
@onready var grab_area: Area2D = $GrabArea
@onready var sheath_timer: Timer = $SheathTimer
@onready var blink_timer: Timer = $BlinkTimer
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var camera: Camera2D = $Camera2D

# Synced variables
@export var sync_facing_dir: int = 1
@export var sync_is_attacking: bool = false
@export var sync_has_sword: bool = false
@export var sync_anim: String = "idle"

var is_attacking: bool = false
var has_sword_drawn: bool = false
var facing_direction: int = 1 # 1 = right, -1 = left
var carried_item: Node2D = null
var pulled_box: PushableBox = null
var current_room: Vector2i = Vector2i.ZERO
var respawn_position: Vector2 = Vector2.ZERO
var is_invulnerable: bool = false

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0

func _ready() -> void:
	# Modo flotante top-down sin fricción de suelo/pendientes
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0

	respawn_position = global_position
	current_health = max_health

	var peer_id = name.to_int()
	if peer_id != 0:
		set_multiplayer_authority(peer_id)

	var is_local = is_multiplayer_authority()
	camera.enabled = is_local

	if is_local:
		sheath_timer.wait_time = sheath_time
		sheath_timer.one_shot = true
		sheath_timer.timeout.connect(_on_sheath_timeout)

		blink_timer.one_shot = true
		blink_timer.timeout.connect(_on_blink_timeout)
		_start_random_blink_timer()

		animated_sprite.animation_finished.connect(_on_animation_finished)
		hitbox_area.monitoring = false
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)
		hitbox_area.area_entered.connect(_on_hitbox_area_entered)

		var hud = HUD_SCENE.instantiate()
		add_child(hud)

		Events.player_health_changed.emit(current_health, max_health)

	Events.player_spawned.emit(peer_id, self)
	_update_room_coords()

func _physics_process(_delta: float) -> void:
	if is_multiplayer_authority():
		_handle_local_input()
		_sync_network_state()
		_update_carried_item_position()
		_check_room_transition()
	else:
		_apply_remote_state()
		_update_carried_item_position()

func _handle_local_input() -> void:
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var is_holding_action = Input.is_action_pressed("interact")
	var is_action_just_pressed = Input.is_action_just_pressed("interact")
	var is_action_just_released = Input.is_action_just_released("interact")

	# 1. Jalar caja manteniendo presionado el botón de acción
	if is_holding_action and carried_item == null:
		if pulled_box == null:
			var candidate_box = _find_adjacent_box()
			if candidate_box != null:
				_grab_box(candidate_box)
		else:
			# Si la caja se aleja demasiado (por ejemplo por chocar contra un muro), soltar
			if global_position.distance_to(pulled_box.global_position) > 32.0:
				_release_box()
	elif pulled_box != null and (not is_holding_action or is_action_just_released):
		_release_box()

	# 2. Cargar o soltar items con un toque del botón de acción (solo si no estamos jalando una caja)
	if is_action_just_pressed and pulled_box == null:
		_handle_item_interaction()

	# Lectura de ejes independientes
	var input_x = Input.get_axis("move_left", "move_right")
	var input_y = Input.get_axis("move_up", "move_down")
	var raw_input = Vector2(input_x, input_y)

	if input_x > 0.1:
		facing_direction = 1
	elif input_x < -0.1:
		facing_direction = -1

	# Attack action (solo si no estamos jalando una caja)
	if Input.is_action_just_pressed("attack") and pulled_box == null:
		_start_attack()
		return

	# Movimiento con velocidad ajustada al jalar/mover caja
	var current_speed = move_speed
	if pulled_box != null:
		current_speed = move_speed * 0.65

	if raw_input != Vector2.ZERO:
		if normalize_diagonal:
			velocity = raw_input.normalized() * current_speed
		else:
			velocity = Vector2(input_x * current_speed, input_y * current_speed)
	else:
		velocity = Vector2.ZERO

	# Si estamos agarrando la caja, ambos avanzan juntos con física sólida
	if pulled_box != null and is_instance_valid(pulled_box):
		pulled_box.velocity = velocity
		pulled_box.move_and_slide()
		move_and_slide()
	else:
		move_and_slide()

		# Empuje directo al caminar contra una caja empujable
		if raw_input != Vector2.ZERO:
			for i in range(get_slide_collision_count()):
				var collision = get_slide_collision(i)
				var collider = collision.get_collider()
				if collider is PushableBox:
					var push_dir = -collision.get_normal()
					if raw_input.dot(push_dir) > 0.2:
						collider.push(push_dir * (move_speed * 0.55))

	_update_animation(velocity != Vector2.ZERO)

func _update_animation(is_moving: bool) -> void:
	if is_attacking:
		return

	if has_sword_drawn:
		if is_moving:
			_play_anim("walk_sword")
		else:
			_play_anim("idle_sword")
	else:
		if animated_sprite.animation == "blink" and animated_sprite.is_playing():
			# Mantener pestañeo activo mientras camina o está detenido
			pass
		else:
			_play_anim("idle")

	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2.ZERO

func _start_attack() -> void:
	is_attacking = true
	has_sword_drawn = true
	sheath_timer.stop()

	_play_anim("attack")
	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2(8.0 * facing_direction, 0.0)

	hitbox_shape.position = Vector2(12.0 * facing_direction, 0.0)
	hitbox_area.monitoring = true

	Events.attack_performed.emit(multiplayer.get_unique_id(), Vector2(facing_direction, 0))

func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack":
		is_attacking = false
		hitbox_area.monitoring = false
		animated_sprite.offset = Vector2.ZERO
		sheath_timer.start(sheath_time)
		_play_anim("idle_sword")
	elif animated_sprite.animation == "blink":
		_play_anim("idle")
		_start_random_blink_timer()

func _on_sheath_timeout() -> void:
	if not is_attacking:
		has_sword_drawn = false
		_play_anim("idle")
		_start_random_blink_timer()

func _start_random_blink_timer() -> void:
	if not has_sword_drawn and not is_attacking:
		blink_timer.start(randf_range(2.5, 5.5))

func _on_blink_timeout() -> void:
	if not has_sword_drawn and not is_attacking:
		_play_anim("blink")
	else:
		_start_random_blink_timer()

func _stop_blink() -> void:
	_start_random_blink_timer()

func _play_anim(anim_name: String) -> void:
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)

func _find_adjacent_box() -> PushableBox:
	var overlapping_areas = grab_area.get_overlapping_areas()
	var candidate_box: PushableBox = null
	var min_dist: float = 24.0

	for area in overlapping_areas:
		var parent = area.get_parent()
		if parent is PushableBox and parent.grabber == null:
			var d = global_position.distance_to(parent.global_position)
			if d < min_dist:
				min_dist = d
				candidate_box = parent

	return candidate_box

func _handle_item_interaction() -> void:
	if carried_item != null:
		drop_item()
	else:
		var overlapping_areas = grab_area.get_overlapping_areas()
		var candidate_item: Node2D = null
		var min_dist: float = 99999.0

		for area in overlapping_areas:
			var parent = area.get_parent()
			if parent is GrabbableItem and parent.carrier == null:
				var d = global_position.distance_to(parent.global_position)
				if d < min_dist:
					min_dist = d
					candidate_item = parent

		if candidate_item != null:
			grab_item(candidate_item)

func _grab_box(box: PushableBox) -> void:
	pulled_box = box
	box.grab_by(self)

func _release_box() -> void:
	if pulled_box != null:
		pulled_box.release()
		pulled_box = null

func grab_item(item: Node2D) -> void:
	carried_item = item
	if item is GrabbableItem:
		item.pick_up_by(self)
	Events.item_grabbed.emit(item, self)

func drop_item() -> void:
	if carried_item != null:
		var target_drop_pos = global_position + Vector2(facing_direction * 12.0, 0.0)
		var safe_drop_pos = _get_safe_drop_position(global_position, target_drop_pos)
		var item = carried_item
		carried_item = null
		if item is GrabbableItem:
			item.drop_at(safe_drop_pos)
		Events.item_dropped.emit(item, safe_drop_pos)

func _get_safe_drop_position(from_pos: Vector2, target_pos: Vector2) -> Vector2:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from_pos, target_pos, 1) # Layer 1: Muros
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	if result:
		var normal = result.normal
		var safe_pos = result.position + normal * 4.0
		# Si el punto seguro queda demasiado cerca o detrás del muro, soltar en la posición del jugador
		if from_pos.distance_to(safe_pos) > from_pos.distance_to(target_pos):
			return from_pos
		return safe_pos
	return target_pos

func _update_carried_item_position() -> void:
	if carried_item != null and is_instance_valid(carried_item):
		carried_item.global_position = global_position + Vector2(facing_direction * 10.0, -2.0)

func _check_room_transition() -> void:
	var new_room_x = int(floor(global_position.x / ROOM_WIDTH))
	var new_room_y = int(floor(global_position.y / ROOM_HEIGHT))
	var new_room = Vector2i(new_room_x, new_room_y)

	if new_room != current_room:
		current_room = new_room
		_update_camera_for_room()
		Events.room_changed.emit(multiplayer.get_unique_id(), current_room)

func _update_room_coords() -> void:
	current_room = Vector2i(int(floor(global_position.x / ROOM_WIDTH)), int(floor(global_position.y / ROOM_HEIGHT)))
	_update_camera_for_room()

func _update_camera_for_room() -> void:
	if is_multiplayer_authority():
		var room_center = Vector2(current_room.x * ROOM_WIDTH + ROOM_WIDTH / 2.0, current_room.y * ROOM_HEIGHT + ROOM_HEIGHT / 2.0)
		camera.global_position = room_center

func _sync_network_state() -> void:
	sync_facing_dir = facing_direction
	sync_is_attacking = is_attacking
	sync_has_sword = has_sword_drawn
	sync_anim = animated_sprite.animation

func _apply_remote_state() -> void:
	facing_direction = sync_facing_dir
	is_attacking = sync_is_attacking
	has_sword_drawn = sync_has_sword

	animated_sprite.flip_h = (facing_direction < 0)
	if sync_is_attacking:
		animated_sprite.offset = Vector2(8.0 * facing_direction, 0.0)
	else:
		animated_sprite.offset = Vector2.ZERO

	_play_anim(sync_anim)

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(1)

func _on_hitbox_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent and parent != self and parent.has_method("take_damage"):
		parent.take_damage(1)

func take_damage(amount: int = 1) -> void:
	if is_invulnerable or current_health <= 0:
		return

	current_health = max(0, current_health - amount)
	Events.player_health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die()
	else:
		is_invulnerable = true
		# Destello de invencibilidad (i-frames 0.8s)
		var tween = create_tween()
		for i in range(4):
			tween.tween_property(animated_sprite, "modulate:a", 0.3, 0.1)
			tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.1)
		tween.tween_callback(func():
			is_invulnerable = false
			if animated_sprite:
				animated_sprite.modulate.a = 1.0
		)

func die() -> void:
	var effect = DEAD_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(effect)

	Events.player_died.emit(self)

	# Soltar caja o item
	if pulled_box != null:
		_release_box()
	if carried_item != null:
		drop_item()

	# Reaparecer en el último checkpoint / spawn
	current_health = max_health
	global_position = respawn_position
	_update_room_coords()
	Events.player_health_changed.emit(current_health, max_health)

	# Periodo de gracia tras respawn
	is_invulnerable = true
	var tween = create_tween()
	for i in range(3):
		tween.tween_property(animated_sprite, "modulate:a", 0.3, 0.1)
		tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.1)
	tween.tween_callback(func():
		is_invulnerable = false
		if animated_sprite:
			animated_sprite.modulate.a = 1.0
	)

func set_checkpoint(pos: Vector2) -> void:
	respawn_position = pos
