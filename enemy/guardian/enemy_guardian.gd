class_name EnemyGuardian
extends CharacterBody2D

## Enemy Guardian - IA de Patrullaje Inteligente v3
##
## Estados:
##   PATROL_IDLE  → Se detiene, mira, pestañea (1.5-3s).
##   PATROL_WALK  → Camina en dirección libre unos pasos.
##   ALERT        → Perdió el rastro del jugador, busca activamente (2.5s).
##   INVESTIGATE  → Sospecha por caja movida: rodea para ver qué hay.
##   DODGE        → Esquiva proyectil lateralmente.
##   CHASE        → Ve al jugador de frente: desenfunda y persigue.
##   ATTACK       → Lanza espadazo.
##
## v3:
##   - Anti-atascado en pared: tras 0.55s pegado a muro, rodea lateralmente.
##   - Sospecha por caja movida: si una caja se mueve >1.8px/frame → INVESTIGATE.
##   - INVESTIGATE: rodea la caja en órbita hasta ver al jugador o rendirse (4s).
##   - Parar en rango de ataque con cooldown activo (no empujar al jugador).
##   - Empuje de caja usando normal de colisión física (igual que el jugador).

const DEAD_EFFECT = preload("res://objects/effects/dead_effect.tscn")

enum State {
	PATROL_IDLE,
	PATROL_WALK,
	ALERT,
	INVESTIGATE,
	DODGE,
	CHASE,
	ATTACK
}

# --- Combat ---
@export_group("Combat")
@export var max_health: int = 2
@export var move_speed: float = 48.0
@export var patrol_speed_mult: float = 0.55
@export var attack_distance: float = 18.0
@export var attack_cooldown: float = 2.8
@export var sheath_time: float = 4.0
@export var damage: int = 1

# --- Vision ---
@export_group("Vision")
@export var sight_radius: float = 75.0
@export var alert_duration: float = 2.5
@export var wall_scan_dist: float = 18.0
@export var box_move_threshold: float = 1.8   ## px/frame para sospechar caja
@export var investigate_duration: float = 4.0## s rodeando la caja sospechosa

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

# Patrulla
var patrol_dir: Vector2 = Vector2.ZERO
var state_timer: float = 2.0
var alert_timer: float = 0.0

# Dodge
var dodge_dir: Vector2 = Vector2.ZERO
var dodge_timer: float = 0.0

# Anti-atascado (CHASE)
var stuck_timer: float = 0.0
var unstuck_dir: Vector2 = Vector2.ZERO
var unstuck_timer: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO  ## Posición del frame anterior para medir desplazamiento real

# Control de re-enganche tras re-aparecer
var re_engage_cooldown: float = 0.0

# Última posición conocida del jugador
var last_known_player_pos: Vector2 = Vector2.ZERO
var has_current_los: bool = false

# Investigación por caja sospechosa
var box_positions: Dictionary = {}         # PushableBox → Vector2 pos del frame anterior
var investigate_target: Vector2 = Vector2.ZERO
var investigate_orbit_dir: Vector2 = Vector2.ZERO
var investigate_timer: float = 0.0

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0

# Layer 1 (muros) + Layer 6 (cajas) → 1 + 32 = 33
# La caja bloquea la línea de visión igual que un muro.
const WALL_LAYER_MASK: int = 33

# ---------------------------------------------------------------------------
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
	_prev_pos = global_position

# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_update_room_coords()

	# 1. Evasión de proyectiles (prioridad máxima)
	if current_state != State.ATTACK:
		_check_hazards()

	# 2. Visión del jugador
	if current_state != State.ATTACK and current_state != State.DODGE:
		_check_player_vision(delta)

	# 3. Vigilar cajas sospechosas (solo cuando NO está en combate)
	if current_state == State.PATROL_IDLE or current_state == State.PATROL_WALK or current_state == State.ALERT:
		_check_suspicious_boxes()

	# 4. Máquina de estados
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
			alert_timer -= delta
			if alert_timer <= 0.0:
				target_player = null
				has_sword_drawn = false
				has_current_los = false
				last_known_player_pos = Vector2.ZERO
				current_state = State.PATROL_IDLE
				state_timer = randf_range(1.5, 3.0)
				sheath_timer.start(sheath_time)
			else:
				# ALERT activo: caminar hacia el úLTIMO punto donde se vio al jugador
				if last_known_player_pos != Vector2.ZERO:
					var to_last = last_known_player_pos - global_position
					var dist_last = to_last.length()
					if dist_last > 10.0:
						velocity = to_last.normalized() * (move_speed * patrol_speed_mult)
						_update_facing_from_velocity(velocity)
					else:
						velocity = Vector2.ZERO  # Llegó al punto: mirar alrededor
				else:
					velocity = Vector2.ZERO

		State.INVESTIGATE:
			investigate_timer -= delta
			if investigate_timer <= 0.0:
				# Tiempo agotado sin encontrar nada → volver a patrulla
				current_state = State.PATROL_IDLE
				state_timer = randf_range(1.0, 2.0)
				investigate_target = Vector2.ZERO
			else:
				var to_target = investigate_target - global_position
				var dist_to_target = to_target.length()
				var orbit_speed = move_speed * patrol_speed_mult
				if dist_to_target > 30.0:
					# Acercarse al punto sospechoso
					velocity = to_target.normalized() * orbit_speed
				else:
					# Orbitar perpendicularmente para rodear la caja
					if _is_path_blocked(investigate_orbit_dir):
						investigate_orbit_dir = -investigate_orbit_dir
					velocity = investigate_orbit_dir * orbit_speed
					_update_facing_from_velocity(velocity)

		State.DODGE:
			dodge_timer -= delta
			velocity = dodge_dir * (move_speed * 1.3)
			if dodge_timer <= 0.0 or _is_path_blocked(dodge_dir):
				velocity = Vector2.ZERO
				current_state = State.PATROL_IDLE if target_player == null else State.CHASE
				state_timer = 1.0

		State.CHASE:
			# CHASE solo funciona con LOS activa.
			# Si perdemos LOS → ALERT inmediato (sin frames de gracia, sin zig-zag).
			if not has_current_los or target_player == null or not is_instance_valid(target_player):
				current_state = State.ALERT
				alert_timer = alert_duration
				re_engage_cooldown = 0.5
				stuck_timer = 0.0
				unstuck_timer = 0.0
			else:
				var to_player = target_player.global_position - global_position
				var dist = to_player.length()
				if dist > 0.1:
					var dir = to_player.normalized()
					_update_facing_from_dir(dir)
					if dist <= attack_distance:
						if attack_timer.is_stopped():
							_start_attack()
							return
						else:
							velocity = Vector2.ZERO
							stuck_timer = 0.0
					else:
						velocity = dir * move_speed
						if unstuck_timer > 0.0:
							velocity = unstuck_dir * move_speed
				else:
					velocity = Vector2.ZERO
					stuck_timer = 0.0

		State.ATTACK:
			velocity = Vector2.ZERO

	move_and_slide()

	# Anti-atascado: medir desplazamiento REAL (post move_and_slide)
	# Si queríamos movernos pero apenas avanzamos, el NPC está atascado
	if current_state == State.CHASE and target_player != null:
		var actual_moved = global_position.distance_to(_prev_pos)
		var wanted_to_move = velocity.length() > 2.0
		if wanted_to_move and actual_moved < 0.8:
			stuck_timer += get_physics_process_delta_time()
		else:
			if actual_moved > 1.0:
				stuck_timer = 0.0
				unstuck_timer = 0.0
		if stuck_timer > 0.5:
			stuck_timer = 0.0
			# Dirección perpendicular libre para rodear el obstáculo
			var dir_to_player = Vector2.ZERO
			if is_instance_valid(target_player):
				dir_to_player = (target_player.global_position - global_position).normalized()
			var perp = Vector2(-dir_to_player.y, dir_to_player.x)
			unstuck_dir = perp if not _is_path_blocked(perp) else -perp
			unstuck_timer = 0.65
	_prev_pos = global_position

	# Aplicar dirección de desatasco si está activa
	if unstuck_timer > 0.0 and current_state == State.CHASE:
		unstuck_timer -= get_physics_process_delta_time()
		velocity = unstuck_dir * move_speed
		move_and_slide()

	_update_animation(velocity.length() > 1.0)

# ---------------------------------------------------------------------------
# VISIÓN DEL JUGADOR  (mínima, sin contadores extra)
# ---------------------------------------------------------------------------
func _check_player_vision(delta: float) -> void:
	var visible_player: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and is_instance_valid(p):
			if global_position.distance_to(p.global_position) <= sight_radius and _has_line_of_sight(p.global_position):
				visible_player = p
				break

	if visible_player != null:
		# Jugador visible: actualizar objetivo y úLTIMA posición conocida
		has_current_los = true
		target_player = visible_player
		last_known_player_pos = visible_player.global_position
		if current_state != State.CHASE and current_state != State.ATTACK:
			if re_engage_cooldown <= 0.0:
				current_state = State.CHASE
				has_sword_drawn = true
				sheath_timer.stop()
			else:
				re_engage_cooldown = maxf(0.0, re_engage_cooldown - delta)
		else:
			re_engage_cooldown = 0.0
	else:
		# Jugador no visible: apagar LOS, el estado CHASE reaccionará inmediatamente
		has_current_los = false
		re_engage_cooldown = maxf(0.0, re_engage_cooldown - delta)

# ---------------------------------------------------------------------------
# SOSPECHA POR CAJA MOVIDA
# ---------------------------------------------------------------------------
func _check_suspicious_boxes() -> void:
	for box in get_tree().get_nodes_in_group("boxes"):
		if not box is PushableBox or not is_instance_valid(box):
			continue
		# Solo vigilar cajas en la misma habitación
		var box_room = Vector2i(
			int(floor(box.global_position.x / ROOM_WIDTH)),
			int(floor(box.global_position.y / ROOM_HEIGHT))
		)
		if box_room != current_room:
			box_positions.erase(box)
			continue

		var last_pos: Vector2 = box_positions.get(box, box.global_position)
		var moved_dist = box.global_position.distance_to(last_pos)
		box_positions[box] = box.global_position

		# La caja se movió más del umbral → sospechar e investigar
		if moved_dist > box_move_threshold:
			var to_box = (box.global_position - global_position).normalized()
			var orbit = Vector2(-to_box.y, to_box.x)
			investigate_target = box.global_position
			investigate_orbit_dir = orbit if not _is_path_blocked(orbit) else -orbit
			investigate_timer = investigate_duration
			current_state = State.INVESTIGATE
			return  # Un trigger por frame es suficiente

# ---------------------------------------------------------------------------
# EVASIÓN DE PROYECTILES
# ---------------------------------------------------------------------------
func _check_hazards() -> void:
	if current_state == State.DODGE:
		return

	for node in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(node):
			continue
		var to_bot = global_position - node.global_position
		var dist = to_bot.length()
		if dist < 32.0:
			var bullet_dir: Vector2 = Vector2.ZERO
			if "direction" in node:
				bullet_dir = node.direction.normalized()
			if bullet_dir == Vector2.ZERO:
				continue
			if bullet_dir.dot(to_bot.normalized()) > 0.15:
				var perp_a = Vector2(-bullet_dir.y, bullet_dir.x)
				var perp_b = -perp_a
				var safe_perp = _pick_safe_dodge(perp_a, perp_b)
				if safe_perp != Vector2.ZERO:
					dodge_dir = safe_perp
					dodge_timer = 0.4
					current_state = State.DODGE
					break

func _pick_safe_dodge(a: Vector2, b: Vector2) -> Vector2:
	var score_a = 0
	var score_b = 0
	if _is_path_blocked(a): score_a -= 10
	if _is_path_blocked(b): score_b -= 10
	for node in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(node):
			continue
		var to_proj = (node.global_position - global_position).normalized()
		if to_proj.dot(a) > 0.5: score_a -= 3
		if to_proj.dot(b) > 0.5: score_b -= 3
	if score_a == score_b and score_a < 0:
		return Vector2.ZERO
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
	var query = PhysicsRayQueryParameters2D.create(
		global_position, global_position + dir * wall_scan_dist, WALL_LAYER_MASK
	)
	query.exclude = [self]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()

# ---------------------------------------------------------------------------
# PATRULLAJE
# ---------------------------------------------------------------------------
func _pick_patrol_direction() -> void:
	var dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var scores: Dictionary = {}

	for d in dirs:
		var s = 0
		if _is_path_blocked(d):
			s -= 100
		for node in get_tree().get_nodes_in_group("projectiles"):
			if not is_instance_valid(node):
				continue
			var to_proj = node.global_position - global_position
			if to_proj.length() < 60.0:
				var bullet_dir: Vector2 = node.direction.normalized() if "direction" in node else Vector2.ZERO
				if bullet_dir.dot(d) > 0.5:
					s -= 20
		scores[d] = s

	var best_dir = Vector2.ZERO
	var best_score = -999
	dirs.shuffle()
	for d in dirs:
		if scores[d] > best_score:
			best_score = scores[d]
			best_dir = d

	if best_score >= 0:
		patrol_dir = best_dir
		current_state = State.PATROL_WALK
		state_timer = randf_range(1.2, 3.0)
	else:
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
		sheath_timer.start(sheath_time)
		state_timer = 1.0
		# Volver a CHASE solo si hay jugador visible; si se escondió durante el ataque → ALERT
		if target_player != null and has_current_los:
			current_state = State.CHASE
		elif target_player != null:
			current_state = State.ALERT
			alert_timer = alert_duration
			re_engage_cooldown = 0.5
		else:
			current_state = State.PATROL_IDLE
	elif animated_sprite.animation == "blink":
		_play_anim("idle")
		_start_random_blink()

func _on_sheath_timeout() -> void:
	if current_state != State.CHASE and current_state != State.ATTACK and current_state != State.ALERT and current_state != State.INVESTIGATE:
		has_sword_drawn = false
		_play_anim("idle")

func _start_random_blink() -> void:
	if is_instance_valid(blink_timer) and not has_sword_drawn and current_state != State.ATTACK:
		blink_timer.start(randf_range(2.5, 5.5))

func _on_blink_timeout() -> void:
	if not has_sword_drawn and current_state != State.ATTACK and is_inside_tree():
		_play_anim("blink")
	else:
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

	has_sword_drawn = true
	current_state = State.CHASE
	stuck_timer = 0.0
	unstuck_timer = 0.0
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
