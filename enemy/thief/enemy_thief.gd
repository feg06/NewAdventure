class_name EnemyThief
extends CharacterBody2D

## Enemy Thief (Ladrón) — v2 (fixes: item doble posición, huida por pasajes, glitches nav)
##
## Comportamiento:
##   1. PATROL_IDLE / PATROL_WALK  – Patrulla pacífica.
##   2. STALK_STEAL  – Ve al jugador con ítem: se acerca y roba.
##   3. FLEE         – Huye con el ítem a través de pasajes reales de la sala.
##   4. CHASE/ATTACK – Al recibir golpe: entra en combate con espada.
##   5. ALERT        – Pierde al jugador: busca su última pos y vuelve a PATROL.

const DEAD_EFFECT = preload("res://objects/effects/dead_effect.tscn")

enum State {
	PATROL_IDLE,
	PATROL_WALK,
	STALK_STEAL,
	FLEE,
	ALERT,
	INVESTIGATE,
	DODGE,
	CHASE,
	ATTACK
}

# --- Stats ---
@export_group("Combat & Stats")
@export var max_health: int = 2
@export var move_speed: float = 48.0
@export var stalk_speed_mult: float = 1.30
@export var flee_speed_mult: float = 1.55
@export var patrol_speed_mult: float = 0.55
@export var steal_distance: float = 14.0
@export var attack_distance: float = 18.0
@export var attack_cooldown: float = 2.8
@export var sheath_time: float = 4.0
@export var damage: int = 1

# --- Visión ---
@export_group("Vision")
@export var sight_radius: float = 85.0
@export var alert_duration: float = 2.8
@export var wall_scan_dist: float = 20.0
@export var box_move_threshold: float = 1.8
@export var investigate_duration: float = 4.0

# --- Nodos ---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = $HitboxArea
@onready var hitbox_shape: CollisionShape2D = $HitboxArea/HitboxShape
@onready var attack_timer: Timer = $AttackTimer
@onready var blink_timer: Timer = $BlinkTimer
@onready var sheath_timer: Timer = $SheathTimer
@onready var question_mark: Label = $QuestionMark

# --- Estado runtime ---
var current_state: State = State.PATROL_IDLE
var current_health: int
var has_sword_drawn: bool = false
var facing_direction: int = 1
var target_player: Player = null
var carried_item: Node2D = null
var current_room: Vector2i = Vector2i.ZERO
var is_invulnerable: bool = false

# Patrulla
var patrol_dir: Vector2 = Vector2.ZERO
var state_timer: float = 2.0
var alert_timer: float = 0.0

# Huida
var escape_target: Vector2 = Vector2.ZERO     # Objetivo actual de huida
var flee_phase: int = 0                        # 0=alinearse al pasaje, 1=cruzar, 2=interior sala
var flee_replan_timer: float = 0.0
var last_exit_dir: Vector2 = Vector2.ZERO      # Dirección del pasaje elegido

# Dodge
var dodge_dir: Vector2 = Vector2.ZERO
var dodge_timer: float = 0.0

# Anti-atascado
var stuck_timer: float = 0.0
var unstuck_dir: Vector2 = Vector2.ZERO
var unstuck_timer: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO

# Re-enganche
var re_engage_cooldown: float = 0.0
var last_known_player_pos: Vector2 = Vector2.ZERO
var has_current_los: bool = false

# Investigación caja
var box_positions: Dictionary = {}
var investigate_target: Vector2 = Vector2.ZERO
var investigate_orbit_dir: Vector2 = Vector2.ZERO
var investigate_timer: float = 0.0

const ROOM_WIDTH: float = 160.0
const ROOM_HEIGHT: float = 144.0
const WALL_LAYER_MASK: int = 33   # Layer 1 (muros) + Layer 6 (cajas)

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

	if question_mark:
		question_mark.visible = false
		question_mark.modulate.a = 0.0

	_update_room_coords()
	state_timer = randf_range(1.5, 3.0)
	_start_random_blink()
	_prev_pos = global_position

# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_update_room_coords()

	# 1. Evasión proyectiles (máxima prioridad)
	if current_state != State.ATTACK:
		_check_hazards()

	# 2. Visión y evaluación
	if current_state != State.ATTACK and current_state != State.DODGE:
		_check_player_vision(delta)

	# 3. Sospechas por cajas (solo en patrulla/alerta)
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

		State.STALK_STEAL:
			if target_player == null or not is_instance_valid(target_player) or target_player.carried_item == null:
				current_state = State.PATROL_IDLE
				state_timer = 1.0
			else:
				var to_player = target_player.global_position - global_position
				var dist = to_player.length()
				if dist <= steal_distance:
					_steal_item_from_player(target_player)
				else:
					var desired_dir = to_player.normalized()
					var steer_dir = _steer_with_obstacle_avoidance(desired_dir)
					if unstuck_timer > 0.0:
						steer_dir = unstuck_dir
					_update_facing_from_dir(steer_dir)
					velocity = steer_dir * (move_speed * stalk_speed_mult)

		State.FLEE:
			_process_flee(delta)

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
				if last_known_player_pos != Vector2.ZERO:
					var to_last = last_known_player_pos - global_position
					if to_last.length() > 10.0:
						var dir = _steer_with_obstacle_avoidance(to_last.normalized())
						velocity = dir * (move_speed * patrol_speed_mult)
						_update_facing_from_velocity(velocity)
					else:
						velocity = Vector2.ZERO
				else:
					velocity = Vector2.ZERO

		State.INVESTIGATE:
			investigate_timer -= delta
			if investigate_timer <= 0.0:
				current_state = State.PATROL_IDLE
				state_timer = randf_range(1.0, 2.0)
				investigate_target = Vector2.ZERO
			else:
				var to_target = investigate_target - global_position
				var dist_to_target = to_target.length()
				var orbit_speed = move_speed * patrol_speed_mult
				if dist_to_target > 30.0:
					velocity = to_target.normalized() * orbit_speed
				else:
					if _is_path_blocked(investigate_orbit_dir):
						investigate_orbit_dir = -investigate_orbit_dir
					velocity = investigate_orbit_dir * orbit_speed
					_update_facing_from_velocity(velocity)

		State.DODGE:
			dodge_timer -= delta
			velocity = dodge_dir * (move_speed * 1.3)
			if dodge_timer <= 0.0 or _is_path_blocked(dodge_dir):
				velocity = Vector2.ZERO
				current_state = State.PATROL_IDLE if target_player == null else (State.FLEE if carried_item != null else State.CHASE)
				state_timer = 1.0

		State.CHASE:
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
						var steer_dir = _steer_with_obstacle_avoidance(dir)
						if unstuck_timer > 0.0:
							steer_dir = unstuck_dir
						velocity = steer_dir * move_speed
				else:
					velocity = Vector2.ZERO
					stuck_timer = 0.0

		State.ATTACK:
			velocity = Vector2.ZERO

	move_and_slide()

	# Anti-atascado Universal
	var is_active_moving = (current_state == State.FLEE or current_state == State.CHASE or current_state == State.STALK_STEAL)
	if is_active_moving:
		var actual_moved = global_position.distance_to(_prev_pos)
		var wanted_to_move = velocity.length() > 2.0
		if wanted_to_move and actual_moved < 0.6:
			stuck_timer += get_physics_process_delta_time()
		else:
			if actual_moved > 0.8:
				stuck_timer = 0.0
				unstuck_timer = 0.0

		if stuck_timer > 0.28:
			stuck_timer = 0.0
			var base_dir = velocity.normalized() if velocity.length() > 0.1 else Vector2.RIGHT
			var perp = Vector2(-base_dir.y, base_dir.x)
			unstuck_dir = perp if not _is_path_blocked(perp) else -perp
			unstuck_timer = 0.45
			if current_state == State.FLEE:
				# Al atascarse en FLEE: forzar replanificación del escape
				escape_target = Vector2.ZERO
				flee_phase = 0

	if unstuck_timer > 0.0 and is_active_moving:
		unstuck_timer -= get_physics_process_delta_time()

	_prev_pos = global_position
	_update_carried_item_position()
	_update_animation(velocity.length() > 1.0)

# ---------------------------------------------------------------------------
# HUIDA INTELIGENTE — Sistema de waypoints para cruzar pasajes
# ---------------------------------------------------------------------------
# La huida usa una lista de waypoints: [align, cross, interior]
#   align   = punto justo dentro del hueco del pasaje (alinearse con él)
#   cross   = punto 28px fuera de la sala por ese pasaje (cruzar el umbral)
#   interior= punto seguro dentro de la nueva sala
# Fase 0: navegar a align  (con evitación de obstáculos)
# Fase 1: cruzar directo   (sin deflexión, empujar recto por el hueco)
# Fase 2: moverse al interior de nueva sala, luego replanificar

var _flee_waypoints: Array[Vector2] = []  # [align, cross, interior]

func _process_flee(delta: float) -> void:
	if carried_item == null:
		current_state = State.ALERT
		alert_timer = alert_duration
		escape_target = Vector2.ZERO
		flee_phase = 0
		_flee_waypoints.clear()
		return

	flee_replan_timer -= delta

	# Sin waypoints o tiempo de replan agotado → buscar nueva salida
	if _flee_waypoints.is_empty() or flee_replan_timer <= 0.0:
		_plan_flee_route()
		if _flee_waypoints.is_empty():
			# Sin ruta: alejarse del jugador dentro de la sala
			_flee_in_room_fallback()
			return

	escape_target = _flee_waypoints[0]
	var to_target = escape_target - global_position
	var dist = to_target.length()

	var arrival_threshold = 12.0 if flee_phase != 1 else 6.0

	if dist < arrival_threshold:
		_flee_waypoints.remove_at(0)
		flee_phase += 1
		if _flee_waypoints.is_empty():
			# Completamos la ruta: replanificar desde la nueva sala
			flee_phase = 0
			escape_target = Vector2.ZERO
			flee_replan_timer = 0.0
		return

	var desired_dir = to_target.normalized()
	if desired_dir == Vector2.ZERO:
		desired_dir = last_exit_dir if last_exit_dir != Vector2.ZERO else Vector2.RIGHT

	var steer_dir: Vector2
	if flee_phase == 1:
		# Cruzando el umbral: ir RECTO sin deflexión para no chocar con los bordes del pasaje
		steer_dir = desired_dir
	else:
		steer_dir = _steer_with_obstacle_avoidance(desired_dir)
		if unstuck_timer > 0.0:
			steer_dir = unstuck_dir

	velocity = steer_dir * (move_speed * flee_speed_mult)
	_update_facing_from_velocity(velocity)

## Construye la ruta de waypoints hacia la mejor salida disponible.
func _plan_flee_route() -> void:
	_flee_waypoints.clear()
	flee_phase = 0

	var space = get_world_2d().direct_space_state
	if not space:
		flee_replan_timer = 0.3
		return

	var player_pos = last_known_player_pos
	if target_player != null and is_instance_valid(target_player):
		player_pos = target_player.global_position
	if player_pos == Vector2.ZERO:
		player_pos = global_position - Vector2(40, 0)

	var player_room = Vector2i(int(floor(player_pos.x / ROOM_WIDTH)), int(floor(player_pos.y / ROOM_HEIGHT)))

	# Obtener salidas de la sala actual, filtradas por accesibilidad real
	var open_exits = _get_open_room_exits(space, current_room)
	var reachable = _filter_reachable_exits(space, open_exits)

	if reachable.is_empty():
		# Sin salidas accesibles: quedarse en la sala y alejarse del jugador
		flee_replan_timer = 0.8
		return

	if current_room == player_room:
		# --- MISMA SALA: MÁXIMA PRIORIDAD → ESCAPAR A OTRA SALA ---
		# Elegir salida con mayor puntuación:
		# +lejos del jugador, +lejos en dirección CONTRARIA al jugador, -lejos del ladrón
		var away_dir = (global_position - player_pos).normalized()
		var best: Dictionary = {}
		var best_score = -999999.0

		for ex in reachable:
			var dist_player = ex.align_pos.distance_to(player_pos)
			var dist_self   = ex.align_pos.distance_to(global_position)
			# Bonus si la salida está en la misma dirección que "alejarse del jugador"
			var alignment   = ex.direction.dot(away_dir)
			var score = dist_player * 2.0 - dist_self * 0.4 + alignment * 30.0
			if score > best_score:
				best_score = score
				best = ex

		last_exit_dir = best.direction
		var interior_new_room = best.cross_pos + best.direction * 28.0
		_flee_waypoints = [best.align_pos, best.cross_pos, interior_new_room]
	else:
		# --- EN SALA DIFERENTE: mantenerse alejado o buscar 3ra sala ---
		# Si el jugador ya entró en esta sala, buscar otra salida
		var player_nearby = player_pos.distance_to(global_position) < sight_radius * 0.8

		if player_nearby:
			# Buscar salida que aleje del jugador
			var best: Dictionary = {}
			var best_score = -999999.0
			for ex in reachable:
				var d = ex.align_pos.distance_to(player_pos)
				if d > best_score:
					best_score = d
					best = ex
			if not best.is_empty():
				last_exit_dir = best.direction
				var interior_new_room = best.cross_pos + best.direction * 28.0
				_flee_waypoints = [best.align_pos, best.cross_pos, interior_new_room]
		else:
			# Jugador lejos: ir al interior seguro de esta sala
			var room_center = _room_center(current_room)
			var safe = room_center + (room_center - player_pos).normalized() * 30.0
			_flee_waypoints = [safe]

	flee_replan_timer = 1.2

func _flee_in_room_fallback() -> void:
	# Sin salidas accesibles: moverse al rincón opuesto al jugador
	var player_pos = last_known_player_pos
	if target_player != null and is_instance_valid(target_player):
		player_pos = target_player.global_position

	var room_center = _room_center(current_room)
	var away = (room_center - player_pos).normalized()
	var target = room_center + away * 45.0

	var to_target = target - global_position
	if to_target.length() > 5.0:
		var steer = _steer_with_obstacle_avoidance(to_target.normalized())
		velocity = steer * (move_speed * flee_speed_mult)
		_update_facing_from_velocity(velocity)
	else:
		velocity = Vector2.ZERO

func _room_center(room: Vector2i) -> Vector2:
	return Vector2(room.x * ROOM_WIDTH + ROOM_WIDTH * 0.5, room.y * ROOM_HEIGHT + ROOM_HEIGHT * 0.5)

## Verifica si el ladrón puede llegar a cada salida sin muro en medio.
func _filter_reachable_exits(space: PhysicsDirectSpaceState2D, exits: Array) -> Array:
	var result: Array = []
	for ex in exits:
		var q = PhysicsRayQueryParameters2D.create(global_position, ex.align_pos, WALL_LAYER_MASK)
		q.exclude = [self]
		q.collide_with_bodies = true
		q.collide_with_areas = false
		if space.intersect_ray(q).is_empty():
			result.append(ex)
	return result

## Devuelve lista de {align_pos, cross_pos, direction} para cada pasaje abierto.
## Usa 3 rayos por dirección (offset -8, 0, +8) para detectar el hueco real.
## align_pos  = punto DENTRO de la sala a 16px del borde, en la apertura real
## cross_pos  = punto a 28px FUERA de la sala (umbral cruzado)
## direction  = vector unitario apuntando hacia afuera por ese pasaje
func _get_open_room_exits(space: PhysicsDirectSpaceState2D, room: Vector2i) -> Array:
	var exits: Array = []
	var left  = room.x * ROOM_WIDTH
	var right = (room.x + 1) * ROOM_WIDTH
	var top   = room.y * ROOM_HEIGHT
	var bot   = (room.y + 1) * ROOM_HEIGHT
	var cx    = left + ROOM_WIDTH * 0.5
	var cy    = top  + ROOM_HEIGHT * 0.5

	# Para cada dirección, probamos 3 rayos con offset para encontrar el hueco real
	var offsets = [-8.0, 0.0, 8.0]

	# Norte
	for off in offsets:
		var scan_x = cx + off
		if _is_passage_clear(space, Vector2(scan_x, top + 36.0), Vector2(scan_x, top - 8.0)):
			exits.append({
				"align_pos": Vector2(scan_x, top + 18.0),
				"cross_pos":  Vector2(scan_x, top - 28.0),
				"direction":  Vector2(0, -1)
			})
			break  # Un rayo libre ya confirma el pasaje

	# Sur
	for off in offsets:
		var scan_x = cx + off
		if _is_passage_clear(space, Vector2(scan_x, bot - 36.0), Vector2(scan_x, bot + 8.0)):
			exits.append({
				"align_pos": Vector2(scan_x, bot - 18.0),
				"cross_pos":  Vector2(scan_x, bot + 28.0),
				"direction":  Vector2(0, 1)
			})
			break

	# Oeste
	for off in offsets:
		var scan_y = cy + off
		if _is_passage_clear(space, Vector2(left + 36.0, scan_y), Vector2(left - 8.0, scan_y)):
			exits.append({
				"align_pos": Vector2(left + 18.0, scan_y),
				"cross_pos":  Vector2(left - 28.0, scan_y),
				"direction":  Vector2(-1, 0)
			})
			break

	# Este
	for off in offsets:
		var scan_y = cy + off
		if _is_passage_clear(space, Vector2(right - 36.0, scan_y), Vector2(right + 8.0, scan_y)):
			exits.append({
				"align_pos": Vector2(right - 18.0, scan_y),
				"cross_pos":  Vector2(right + 28.0, scan_y),
				"direction":  Vector2(1, 0)
			})
			break


	return exits


func _is_passage_clear(space: PhysicsDirectSpaceState2D, from_pt: Vector2, to_pt: Vector2) -> bool:
	var q = PhysicsRayQueryParameters2D.create(from_pt, to_pt, WALL_LAYER_MASK)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return space.intersect_ray(q).is_empty()

# ---------------------------------------------------------------------------
# VISIÓN DEL JUGADOR
# ---------------------------------------------------------------------------
func _check_player_vision(delta: float) -> void:
	var visible_player: Player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and is_instance_valid(p):
			if global_position.distance_to(p.global_position) <= sight_radius and _has_line_of_sight(p.global_position):
				visible_player = p
				break

	if visible_player != null:
		has_current_los = true
		target_player = visible_player
		last_known_player_pos = visible_player.global_position

		if has_sword_drawn or current_state == State.CHASE:
			if current_state != State.CHASE and current_state != State.ATTACK:
				if re_engage_cooldown <= 0.0:
					current_state = State.CHASE
					sheath_timer.stop()
				else:
					re_engage_cooldown = maxf(0.0, re_engage_cooldown - delta)
			else:
				re_engage_cooldown = 0.0

		elif carried_item != null:
			current_state = State.FLEE

		elif visible_player.carried_item != null:
			if current_state != State.STALK_STEAL:
				current_state = State.STALK_STEAL
	else:
		has_current_los = false
		re_engage_cooldown = maxf(0.0, re_engage_cooldown - delta)

# ---------------------------------------------------------------------------
# ROBO Y GESTIÓN DE ÍTEMS
# ---------------------------------------------------------------------------
func _steal_item_from_player(player: Player) -> void:
	if player == null or not is_instance_valid(player) or player.carried_item == null:
		return

	var item = player.carried_item
	# Desasociar del jugador
	player.carried_item = null
	if item is GrabbableItem:
		item.carrier = null   # ← FIX: el ladrón maneja la posición manualmente,
		                      #   evita el doble-update de item.gd
	carried_item = item
	Events.item_grabbed.emit(item, self)

	# Iniciar huida
	escape_target = Vector2.ZERO
	flee_phase = 0
	flee_replan_timer = 0.0
	current_state = State.FLEE

func drop_item() -> void:
	if carried_item == null:
		return
	var target_drop_pos = global_position + Vector2(facing_direction * 12.0, 0.0)
	var safe_drop_pos = _get_safe_drop_position(global_position, target_drop_pos)
	var item = carried_item
	carried_item = null
	if item is GrabbableItem:
		item.drop_at(safe_drop_pos)   # drop_at limpia carrier correctamente
	Events.item_dropped.emit(item, safe_drop_pos)

func _get_safe_drop_position(from_pos: Vector2, target_pos: Vector2) -> Vector2:
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return target_pos
	var query = PhysicsRayQueryParameters2D.create(from_pos, target_pos, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	if result:
		var normal = result.normal
		var safe_pos = result.position + normal * 4.0
		if from_pos.distance_to(safe_pos) > from_pos.distance_to(target_pos):
			return from_pos
		return safe_pos
	return target_pos

func _update_carried_item_position() -> void:
	# Solo actualiza posición si el ítem no tiene carrier asignado (lo maneja el ladrón)
	if carried_item != null and is_instance_valid(carried_item):
		carried_item.global_position = global_position + Vector2(facing_direction * 10.0, -2.0)

# ---------------------------------------------------------------------------
# SIGNO DE INTERROGACIÓN
# ---------------------------------------------------------------------------
func show_question_mark() -> void:
	if not question_mark:
		return
	question_mark.visible = true
	question_mark.modulate.a = 0.0
	question_mark.position = Vector2(-4, -18)

	var tween = create_tween()
	tween.tween_property(question_mark, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(question_mark, "position:y", -22.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(question_mark, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		question_mark.visible = false
	)

# ---------------------------------------------------------------------------
# EVITACIÓN DE OBSTÁCULOS (Feelers)
# ---------------------------------------------------------------------------
func _steer_with_obstacle_avoidance(desired_dir: Vector2) -> Vector2:
	if desired_dir == Vector2.ZERO:
		return Vector2.ZERO

	var space = get_world_2d().direct_space_state
	if not space:
		return desired_dir

	var center_query = PhysicsRayQueryParameters2D.create(
		global_position, global_position + desired_dir * wall_scan_dist, WALL_LAYER_MASK
	)
	center_query.exclude = [self]
	center_query.collide_with_bodies = true
	center_query.collide_with_areas = false
	var hit = space.intersect_ray(center_query)

	if hit.is_empty():
		return desired_dir

	var normal: Vector2 = hit.normal
	var slide_dir = (desired_dir - normal * desired_dir.dot(normal)).normalized()

	if slide_dir != Vector2.ZERO and not _is_path_blocked(slide_dir):
		return slide_dir

	var angles = [PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI * 0.75, -PI * 0.75]
	var best_feeler = desired_dir
	var best_score = -999.0

	for ang in angles:
		var test_dir = desired_dir.rotated(ang)
		if not _is_path_blocked(test_dir):
			var score = test_dir.dot(desired_dir)
			if score > best_score:
				best_score = score
				best_feeler = test_dir

	return best_feeler

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
# SOSPECHA POR CAJA MOVIDA
# ---------------------------------------------------------------------------
func _check_suspicious_boxes() -> void:
	for box in get_tree().get_nodes_in_group("boxes"):
		if not box is PushableBox or not is_instance_valid(box):
			continue
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

		if moved_dist > box_move_threshold:
			var to_box = (box.global_position - global_position).normalized()
			var orbit = Vector2(-to_box.y, to_box.x)
			investigate_target = box.global_position
			investigate_orbit_dir = orbit if not _is_path_blocked(orbit) else -orbit
			investigate_timer = investigate_duration
			current_state = State.INVESTIGATE
			return

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
	if current_state != State.CHASE and current_state != State.ATTACK and \
	   current_state != State.ALERT and current_state != State.INVESTIGATE and \
	   current_state != State.FLEE and current_state != State.STALK_STEAL:
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

	if carried_item != null:
		drop_item()
		show_question_mark()

	has_sword_drawn = true
	current_state = State.CHASE
	stuck_timer = 0.0
	unstuck_timer = 0.0
	escape_target = Vector2.ZERO
	flee_phase = 0
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
	if carried_item != null:
		drop_item()
	var effect = DEAD_EFFECT.instantiate()
	effect.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(effect)
	queue_free()
