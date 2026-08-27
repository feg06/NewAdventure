class_name EnemyGuardian
extends CharacterBody2D

## Enemy Guardian - IA de Patrullaje Inteligente v2
##
## Estados:
##   PATROL_IDLE  → Se detiene, mira, pestañea (1.5-3s).
##   PATROL_WALK  → Camina en dirección libre unos pasos.
##   ALERT        → Perdió el rastro del jugador, busca activamente (2.5s).
##   CHASE        → Ve al jugador de frente: desenfunda y persigue.
##   ATTACK       → Lanza espadazo.
##   DODGE        → Esquiva proyectil lateralmente.
##
## Mejoras v2:
##   - Balas dañan al guardián (collision_mask correcto en bullet.tscn).
##   - _check_hazards() usa get_nodes_in_group("projectiles") en vez de get_children().
##   - Raycasts excluyen el propio cuerpo del guardián.
##   - Evaluación de dirección segura al elegir patrullaje (descarta ejes con balas activas).
##   - Estado ALERT para no perder el rastro de forma abrupta.
##   - is_attacking eliminado: se usa solo current_state == State.ATTACK.

const DEAD_EFFECT = preload("res://objects/effects/dead_effect.tscn")

enum State {
	PATROL_IDLE,
	PATROL_WALK,
	ALERT,
	DODGE,
	CHASE,
	ATTACK
}

# --- Propiedades exportables ---
@export_group("Combat")
@export var max_health: int = 2
@export var move_speed: float = 48.0
@export var patrol_speed_mult: float = 0.55
@export var attack_distance: float = 18.0
@export var attack_cooldown: float = 2.8
@export var sheath_time: float = 4.0
@export var damage: int = 1

@export_group("Vision")
@export var sight_radius: float = 75.0
@export var alert_duration: float = 2.5    ## Tiempo que busca al jugador antes de rendirse
@export var wall_scan_dist: float = 18.0   ## Distancia de escaneo frontal de muros

# --- Nodos ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = $HitboxArea
@onready var hitbox_shape: CollisionShape2D = $HitboxArea/HitboxShape
@onready var attack_timer: Timer = $AttackTimer
@onready var blink_timer: Timer = $BlinkTimer
@onready var sheath_timer: Timer = $SheathTimer

# --- Estado runtime ---
var current_state: State = State.PATROL_IDLE
var current_health: int
var has_sword_drawn: bool = false
var facing_direction: int = 1
var target_player: Player = null
var current_room: Vector2i = Vector2i.ZERO
var is_invulnerable: bool = false

var patrol_dir: Vector2 = Vector2.ZERO
var state_timer: float = 2.0
var alert_timer: float = 0.0
var dodge_dir: Vector2 = Vector2.ZERO
var dodge_timer: float = 0.0

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0

# Bitmask layer 1 (muros) para raycasts
const WALL_LAYER_MASK: int = 1

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	current_health = max_health

	hitbox_area.monitoring = false
	hitbox_area.body_entered.connect(_on_hitbox_body_entered)
	animated_sprite.animation_finished.connect(_on_animation_finished)

	attack_timer.one_shot = true
	sheath_timer.one_shot = true
	sheath_timer.timeout.connect(_on_sheath_timeout)
	blink_timer.one_shot = true
	blink_timer.timeout.connect(_on_blink_timeout)

	_update_room_coords()
	state_timer = randf_range(1.5, 3.0)
	_start_random_blink()

# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_update_room_coords()

	# 1. Evasión de proyectiles (prioridad máxima, interrumpe patrulla/alerta)
	if current_state != State.ATTACK:
		_check_hazards()

	# 2. Visión del jugador (no actúa si ya está atacando o esquivando)
	if current_state != State.ATTACK and current_state != State.DODGE:
		_check_player_vision(delta)

	# 3. Máquina de estados
	match current_state:
		State.PATROL_IDLE:
			velocity = Vector2.ZERO
			state_timer -= delta
			if state_timer <= 0.0:
				_pick_patrol_direction()

		State.PATROL_WALK:
			state_timer -= delta
			if _is_path_blocked(patrol_dir) or state_timer <= 0.0:
				current_state = State.PATROL_IDLE
				state_timer = randf_range(1.5, 3.0)
				velocity = Vector2.ZERO
			else:
				velocity = patrol_dir * (move_speed * patrol_speed_mult)
				_update_facing_from_velocity(velocity)

		State.ALERT:
			# Gira lentamente buscando al jugador, sin moverse
			velocity = Vector2.ZERO
			alert_timer -= delta
			if alert_timer <= 0.0:
				# Perdió el rastro completamente
				target_player = null
				has_sword_drawn = false
				current_state = State.PATROL_IDLE
				state_timer = randf_range(1.5, 3.0)
				sheath_timer.start(sheath_time)

		State.DODGE:
			dodge_timer -= delta
			velocity = dodge_dir * (move_speed * 1.3)
			if dodge_timer <= 0.0 or _is_path_blocked(dodge_dir):
				velocity = Vector2.ZERO
				# Volver a estado anterior sensato
				current_state = State.PATROL_IDLE if target_player == null else State.CHASE
				state_timer = 1.0

		State.CHASE:
			if target_player == null or not is_instance_valid(target_player):
				current_state = State.ALERT
				alert_timer = alert_duration
			else:
				var to_player = target_player.global_position - global_position
				var dist = to_player.length()
				if dist > 0.1:
					var dir = to_player.normalized()
					_update_facing_from_dir(dir)
					if dist <= attack_distance and attack_timer.is_stopped():
						_start_attack()
						return
					velocity = dir * move_speed
				else:
					velocity = Vector2.ZERO

		State.ATTACK:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_animation(velocity.length() > 1.0)

# ---------------------------------------------------------------------------
# VISIÓN DEL JUGADOR
# ---------------------------------------------------------------------------
func _check_player_vision(delta: float) -> void:
	var visible_player: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and is_instance_valid(p):
			var pr = Vector2i(int(floor(p.global_position.x / ROOM_WIDTH)), int(floor(p.global_position.y / ROOM_HEIGHT)))
			if pr == current_room:
				var dist = global_position.distance_to(p.global_position)
				if dist <= sight_radius and _has_line_of_sight(p.global_position):
					visible_player = p
					break

	if visible_player != null:
		target_player = visible_player
		alert_timer = alert_duration
		if current_state != State.CHASE and current_state != State.ATTACK:
			current_state = State.CHASE
			has_sword_drawn = true
			sheath_timer.stop()
	elif current_state == State.CHASE:
		# Perdió la línea de visión → entra en ALERTA
		alert_timer -= delta
		if alert_timer <= 0.0:
			target_player = null
			current_state = State.ALERT
			alert_timer = alert_duration

# ---------------------------------------------------------------------------
# EVASIÓN DE PROYECTILES
# ---------------------------------------------------------------------------
func _check_hazards() -> void:
	if current_state == State.DODGE:
		return

	# Escaneo de proyectiles activos usando el grupo, independientemente de su nodo padre
	var projectiles = get_tree().get_nodes_in_group("projectiles")
	for node in projectiles:
		if not is_instance_valid(node):
			continue
		var to_bot = global_position - node.global_position
		var dist = to_bot.length()
		if dist < 32.0:
			# Obtener dirección del proyectil (compatibilidad con ambos tipos)
			var bullet_dir: Vector2 = Vector2.ZERO
			if "direction" in node:
				bullet_dir = node.direction.normalized()
			if bullet_dir == Vector2.ZERO:
				continue
			# El proyectil viene hacia nosotros si la dirección apunta hacia el bot
			if bullet_dir.dot(to_bot.normalized()) > 0.15:
				# Calcular eje perpendicular libre de obstáculos
				var perp_a = Vector2(-bullet_dir.y, bullet_dir.x)
				var perp_b = -perp_a
				# Elegir la perpendicular que NO tenga otro proyectil en esa dirección
				var safe_perp = _pick_safe_dodge(perp_a, perp_b)
				if safe_perp != Vector2.ZERO:
					dodge_dir = safe_perp
					dodge_timer = 0.4
					current_state = State.DODGE
					break

func _pick_safe_dodge(a: Vector2, b: Vector2) -> Vector2:
	# Preferir la dirección que no esté bloqueada por muro y no tenga balas cerca
	var score_a = 0
	var score_b = 0
	if _is_path_blocked(a): score_a -= 10
	if _is_path_blocked(b): score_b -= 10
	# Penalizar si hay otro proyectil en esa dirección
	for node in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(node):
			continue
		var to_proj = (node.global_position - global_position).normalized()
		if to_proj.dot(a) > 0.5: score_a -= 3
		if to_proj.dot(b) > 0.5: score_b -= 3
	if score_a == score_b and score_a < 0:
		return Vector2.ZERO # Atrapado, no hay esquive seguro
	if score_a >= score_b:
		return a if not _is_path_blocked(a) else Vector2.ZERO
	return b if not _is_path_blocked(b) else Vector2.ZERO

# ---------------------------------------------------------------------------
# RAYCASTS
# ---------------------------------------------------------------------------
func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	if not space:
		return false
	var query = PhysicsRayQueryParameters2D.create(global_position, target_pos, WALL_LAYER_MASK)
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()

func _is_path_blocked(dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return false
	var space = get_world_2d().direct_space_state
	if not space:
		return false
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + dir * wall_scan_dist, WALL_LAYER_MASK)
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()

# ---------------------------------------------------------------------------
# PATRULLAJE
# ---------------------------------------------------------------------------
func _pick_patrol_direction() -> void:
	# Puntuar cada dirección: penalizar muros, penalizar proyectiles en esa dirección
	var dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var scores: Dictionary = {}

	for d in dirs:
		var s = 0
		if _is_path_blocked(d):
			s -= 100
		# Penalizar si hay proyectiles volando en esa dirección
		for node in get_tree().get_nodes_in_group("projectiles"):
			if not is_instance_valid(node):
				continue
			var to_proj = (node.global_position - global_position)
			if to_proj.length() < 60.0:
				var bullet_dir: Vector2 = node.direction.normalized() if "direction" in node else Vector2.ZERO
				if bullet_dir.dot(d) > 0.5:
					s -= 20
		scores[d] = s

	# Ordenar por puntaje descendente, elegir mejor opción
	var best_dir = Vector2.ZERO
	var best_score = -999
	dirs.shuffle() # Aleatoriedad para variedad
	for d in dirs:
		if scores[d] > best_score:
			best_score = scores[d]
			best_dir = d

	if best_score >= 0:
		patrol_dir = best_dir
		current_state = State.PATROL_WALK
		state_timer = randf_range(1.2, 3.0)
	else:
		# Todas las direcciones tienen amenaza/muro: quedarse quieto
		current_state = State.PATROL_IDLE
		state_timer = randf_range(1.0, 2.0)

# ---------------------------------------------------------------------------
# ANIMACIÓN Y ORIENTACIÓN
# ---------------------------------------------------------------------------
func _update_facing_from_velocity(vel: Vector2) -> void:
	if vel.x > 0.1: facing_direction = 1
	elif vel.x < -0.1: facing_direction = -1

func _update_facing_from_dir(dir: Vector2) -> void:
	if dir.x > 0.1: facing_direction = 1
	elif dir.x < -0.1: facing_direction = -1

func _update_animation(is_moving: bool) -> void:
	if current_state == State.ATTACK:
		return

	animated_sprite.flip_h = (facing_direction < 0)
	animated_sprite.offset = Vector2.ZERO

	if has_sword_drawn:
		_play_anim("walk_sword" if is_moving else "idle_sword")
	else:
		if animated_sprite.animation == "blink" and animated_sprite.is_playing():
			pass
		else:
			_play_anim("idle")

func _play_anim(anim_name: String) -> void:
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)

# ---------------------------------------------------------------------------
# COMBATE
# ---------------------------------------------------------------------------
func _start_attack() -> void:
	current_state = State.ATTACK
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
		hitbox_area.monitoring = false
		animated_sprite.offset = Vector2.ZERO
		_play_anim("idle_sword")
		current_state = State.CHASE if target_player != null else State.PATROL_IDLE
		state_timer = 1.0
		sheath_timer.start(sheath_time)
	elif animated_sprite.animation == "blink":
		# Al terminar el pestañeo siempre volver a idle y encadenar el próximo timer
		_play_anim("idle")
		_start_random_blink()

func _on_sheath_timeout() -> void:
	if current_state != State.CHASE and current_state != State.ATTACK and current_state != State.ALERT:
		has_sword_drawn = false
		_play_anim("idle")

func _start_random_blink() -> void:
	# Solo pestañear si está desarmado y no atacando (igual que el jugador)
	if is_instance_valid(blink_timer) and not has_sword_drawn and current_state != State.ATTACK:
		blink_timer.start(randf_range(2.5, 5.5))

func _on_blink_timeout() -> void:
	if not has_sword_drawn and current_state != State.ATTACK and is_inside_tree():
		_play_anim("blink")
	else:
		# Condición no cumplida: reiniciar el timer para intentarlo luego
		_start_random_blink()

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player and is_instance_valid(body):
		body.take_damage(damage)

func _update_room_coords() -> void:
	current_room = Vector2i(int(floor(global_position.x / ROOM_WIDTH)), int(floor(global_position.y / ROOM_HEIGHT)))

# ---------------------------------------------------------------------------
# DAÑO Y MUERTE
# ---------------------------------------------------------------------------
func take_damage(amount: int = 1) -> void:
	if is_invulnerable or current_health <= 0:
		return

	current_health -= amount
	is_invulnerable = true

	# Desenfunda y entra en combate inmediatamente
	has_sword_drawn = true
	current_state = State.CHASE
	sheath_timer.start(sheath_time)

	var tween = create_tween()
	tween.tween_property(animated_sprite, "modulate", Color(2.5, 0.3, 0.3, 1.0), 0.08)
	tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

	if current_health <= 0:
		die()
	else:
		get_tree().create_timer(0.35).timeout.connect(func():
			is_invulnerable = false
		)

func die() -> void:
	var effect = DEAD_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(effect)
	queue_free()
