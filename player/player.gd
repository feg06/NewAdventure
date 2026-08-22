class_name Player
extends CharacterBody2D

@export var move_speed: float = 65.0
@export var sheath_time: float = 4.0

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
var current_room: Vector2i = Vector2i.ZERO

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0

func _ready() -> void:
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

	_update_room_coords()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_handle_local_input(delta)
		_sync_network_state()
		_update_carried_item_position()
		_check_room_transition()
	else:
		_apply_remote_state()
		_update_carried_item_position()

func _handle_local_input(_delta: float) -> void:
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input_vector.x > 0.1:
		facing_direction = 1
	elif input_vector.x < -0.1:
		facing_direction = -1

	# Attack action
	if Input.is_action_just_pressed("attack"):
		_start_attack()
		return

	# Carry / Grab / Drop action
	if Input.is_action_just_pressed("interact"):
		_handle_interaction()

	# Movement
	if input_vector != Vector2.ZERO:
		velocity = input_vector.normalized() * move_speed
		if animated_sprite.animation == "blink":
			_stop_blink()
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(input_vector != Vector2.ZERO)

func _update_animation(is_moving: bool) -> void:
	if is_attacking:
		return

	if animated_sprite.animation == "blink" and animated_sprite.is_playing():
		if not is_moving:
			return

	if has_sword_drawn:
		if is_moving:
			_play_anim("walk_sword")
		else:
			_play_anim("idle_sword")
	else:
		_play_anim("idle")

	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2.ZERO

func _start_attack() -> void:
	is_attacking = true
	has_sword_drawn = true
	sheath_timer.stop()
	if animated_sprite.animation == "blink":
		_stop_blink()

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
	if not has_sword_drawn and not is_attacking and velocity == Vector2.ZERO:
		_play_anim("blink")
	else:
		_start_random_blink_timer()

func _stop_blink() -> void:
	_start_random_blink_timer()

func _play_anim(anim_name: String) -> void:
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)

func _handle_interaction() -> void:
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

		if candidate_item:
			grab_item(candidate_item)

func grab_item(item: Node2D) -> void:
	carried_item = item
	if item is GrabbableItem:
		item.pick_up_by(self)
	Events.item_grabbed.emit(item, self)

func drop_item() -> void:
	if carried_item != null:
		var drop_pos = global_position + Vector2(facing_direction * 12.0, 0.0)
		var item = carried_item
		carried_item = null
		if item is GrabbableItem:
			item.drop_at(drop_pos)
		Events.item_dropped.emit(item, drop_pos)

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
