class_name PushableBox
extends CharacterBody2D

## Pushable & Pullable Box
## Can be pushed by walking into it, or grabbed/pulled using the action button.

@export var push_speed: float = 45.0
@export var friction: float = 12.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var grab_area: Area2D = $GrabArea
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

# Network Synced
@export var sync_pos: Vector2 = Vector2.ZERO
@export var sync_grabber_peer_id: int = 0

var grabber: CharacterBody2D = null
var grab_offset: Vector2 = Vector2.ZERO
var is_being_pushed: bool = false
var push_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0

	if sync_pos != Vector2.ZERO:
		global_position = sync_pos
	else:
		sync_pos = global_position

func _physics_process(delta: float) -> void:
	if grabber != null and is_instance_valid(grabber):
		# Verificar si la caja quedó trabada contra una pared y el jugador se alejó
		var dist_to_player = global_position.distance_to(grabber.global_position)
		if dist_to_player > 26.0:
			release()
			return

		# Seguir al jugador manteniendo el offset con colisión física de paredes
		var target_pos = grabber.global_position + grab_offset
		var to_target = target_pos - global_position
		velocity = to_target / delta
		if velocity.length() > 90.0:
			velocity = velocity.normalized() * 90.0
		move_and_slide()
		sync_pos = global_position
	elif is_being_pushed:
		velocity = push_velocity
		move_and_slide()
		is_being_pushed = false
		push_velocity = Vector2.ZERO
		sync_pos = global_position
	else:
		# Apply friction when sliding
		if velocity.length() > 1.0:
			velocity = velocity.lerp(Vector2.ZERO, friction * delta)
			move_and_slide()
			sync_pos = global_position
		else:
			velocity = Vector2.ZERO
			if multiplayer.is_server():
				sync_pos = global_position

func push(force: Vector2) -> void:
	if grabber != null:
		return
	is_being_pushed = true
	push_velocity = force

func grab_by(player: CharacterBody2D) -> void:
	grabber = player
	grab_offset = global_position - player.global_position
	sync_grabber_peer_id = player.name.to_int()
	if sync_grabber_peer_id == 0:
		sync_grabber_peer_id = 1
	sync_pos = global_position
	Events.box_grabbed.emit(self, player)

func release() -> void:
	grabber = null
	grab_offset = Vector2.ZERO
	sync_grabber_peer_id = 0
	velocity = Vector2.ZERO
	sync_pos = global_position
	Events.box_released.emit(self)
