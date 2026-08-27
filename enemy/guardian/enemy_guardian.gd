class_name EnemyGuardian
extends CharacterBody2D

## Enemy Guardian
## Human-like NPC AI:
## - Starts unarmed (walks/idles without sword).
## - Draws sword and slashes when attacking.
## - Keeps sword drawn during combat and idles/walks with sword drawn.
## - Only deals damage with actual sword swings (hitbox during attack animation).
## - Sizable cooldown between attacks for fair combat duels.
## - Sheaths sword after combat inactivity.
## - Blinks naturally like the player.

const DEAD_EFFECT = preload("res://objects/effects/dead_effect.tscn")

@export var max_health: int = 2
@export var current_health: int = 2
@export var move_speed: float = 45.0
@export var attack_distance: float = 18.0
@export var attack_cooldown: float = 2.8
@export var sheath_time: float = 4.0
@export var damage: int = 1

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox_area: Area2D = $HitboxArea
@onready var hitbox_shape: CollisionShape2D = $HitboxArea/HitboxShape
@onready var attack_timer: Timer = $AttackTimer
@onready var blink_timer: Timer = $BlinkTimer
@onready var sheath_timer: Timer = $SheathTimer

var is_attacking: bool = false
var has_sword_drawn: bool = false
var facing_direction: int = 1 # 1 = right, -1 = left
var target_player: Player = null
var current_room: Vector2i = Vector2i.ZERO
var is_invulnerable: bool = false

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0

	current_health = max_health

	if hitbox_area:
		hitbox_area.monitoring = false
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)

	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

	if attack_timer:
		attack_timer.one_shot = true

	if sheath_timer:
		sheath_timer.one_shot = true
		sheath_timer.timeout.connect(_on_sheath_timeout)

	if blink_timer:
		blink_timer.one_shot = true
		blink_timer.timeout.connect(_on_blink_timeout)
		_start_random_blink()

	_update_room_coords()

func _physics_process(_delta: float) -> void:
	_update_room_coords()
	_find_player_in_room()

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if target_player != null and is_instance_valid(target_player):
		var to_player = target_player.global_position - global_position
		var dist = to_player.length()

		if dist > 0.1:
			var dir = to_player.normalized()
			if dir.x > 0.1:
				facing_direction = 1
			elif dir.x < -0.1:
				facing_direction = -1

			# Comprobar si está en rango de ataque con espada y cooldown listo
			if dist <= attack_distance and attack_timer.is_stopped():
				_start_attack()
				return

			velocity = dir * move_speed
		else:
			velocity = Vector2.ZERO

		move_and_slide()
		_update_animation(velocity != Vector2.ZERO)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(false)

func _find_player_in_room() -> void:
	var players = get_tree().get_nodes_in_group("players")
	target_player = null

	for p in players:
		if p is Player and is_instance_valid(p):
			var player_room = Vector2i(int(floor(p.global_position.x / ROOM_WIDTH)), int(floor(p.global_position.y / ROOM_HEIGHT)))
			if player_room == current_room:
				target_player = p
				break

func _update_room_coords() -> void:
	current_room = Vector2i(int(floor(global_position.x / ROOM_WIDTH)), int(floor(global_position.y / ROOM_HEIGHT)))

func _update_animation(is_moving: bool) -> void:
	if is_attacking:
		return

	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2.ZERO

	if has_sword_drawn:
		if is_moving:
			_play_anim("walk_sword")
		else:
			_play_anim("idle_sword")
	else:
		if animated_sprite.animation == "blink" and animated_sprite.is_playing():
			pass
		else:
			_play_anim("idle")

func _play_anim(anim_name: String) -> void:
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)

func _start_attack() -> void:
	is_attacking = true
	has_sword_drawn = true
	sheath_timer.stop()
	attack_timer.start(attack_cooldown)

	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2(8.0 * facing_direction, 0.0)
	hitbox_shape.position = Vector2(12.0 * facing_direction, 0.0)
	hitbox_area.monitoring = true

	animated_sprite.play("attack")

func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack":
		is_attacking = false
		hitbox_area.monitoring = false
		animated_sprite.offset = Vector2.ZERO
		_play_anim("idle_sword")
		# Iniciar temporizador para enfundar la espada tras inactividad
		if is_instance_valid(sheath_timer):
			sheath_timer.start(sheath_time)
	elif animated_sprite.animation == "blink":
		if has_sword_drawn:
			_play_anim("idle_sword")
		else:
			_play_anim("idle")
		_start_random_blink()

func _on_sheath_timeout() -> void:
	if not is_attacking and target_player == null:
		has_sword_drawn = false
		_play_anim("idle")

func _start_random_blink() -> void:
	if is_instance_valid(blink_timer):
		blink_timer.start(randf_range(2.0, 5.0))

func _on_blink_timeout() -> void:
	if not is_attacking and is_inside_tree():
		_play_anim("blink")

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player and is_instance_valid(body):
		body.take_damage(damage)

func take_damage(amount: int = 1) -> void:
	if is_invulnerable or current_health <= 0:
		return

	current_health -= amount
	is_invulnerable = true

	# Al ser golpeado, desenfunda inmediatamente para contraatacar
	has_sword_drawn = true
	if is_instance_valid(sheath_timer):
		sheath_timer.start(sheath_time)

	# Efecto de impacto visual
	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color(2.5, 0.3, 0.3, 1.0), 0.1)
	tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

	if current_health <= 0:
		die()
	else:
		get_tree().create_timer(0.3).timeout.connect(func():
			is_invulnerable = false
		)

func die() -> void:
	var effect = DEAD_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(effect)
	queue_free()
