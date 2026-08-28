@tool
class_name TransitionArea
extends Area2D

## Transition Area / Room Teleporter (Adventure Atari 2600 Style)
##
## Configuración de salida:
## - exit_direction: Hacia dónde entra el jugador a la sala al salir por este nodo.
##   - Si el nodo está en una pared izquierda -> pon "Derecha" (para entrar a la sala).
##   - Si el nodo está en una pared derecha -> pon "Izquierda" (para entrar a la sala).
##   - Si el nodo está en una pared superior -> pon "Abajo".
##   - Si el nodo está en una pared inferior -> pon "Arriba".
## - El recuadro verde en el editor muestra exactamente dónde aparecerá el jugador.

@export var enabled: bool = true:
	set(val):
		enabled = val
		queue_redraw()

@export var generar_destino: bool = false:
	set(val):
		if val:
			generar_destino = false
			if Engine.is_editor_hint():
				_create_destination_node_in_editor()

@export var target_position: Vector2
@export var target_node: Node2D:
	set(val):
		target_node = val
		queue_redraw()

@export_enum("Derecha", "Izquierda", "Arriba", "Abajo", "Ninguno") var exit_direction: String = "Derecha":
	set(val):
		exit_direction = val
		queue_redraw()

@export var exit_distance: float = 16.0:
	set(val):
		exit_distance = val
		queue_redraw()

@export var draw_color := Color(0.9, 0.5, 0.1, 0.7) # Naranja retro

var _teleport_cooldown: float = 0.0

func _ready() -> void:
	if not Engine.is_editor_hint():
		if enabled:
			body_entered.connect(_on_body_entered)
	else:
		queue_redraw()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
	elif _teleport_cooldown > 0.0:
		_teleport_cooldown -= delta

func _on_body_entered(body: Node2D) -> void:
	if not enabled or _teleport_cooldown > 0.0:
		return

	if body is Player and is_instance_valid(body):
		var dest = target_position
		var use_offset_dir = "Ninguno"
		var use_exit_dist = exit_distance

		if is_instance_valid(target_node):
			dest = target_node.global_position
			if "exit_direction" in target_node:
				use_offset_dir = target_node.exit_direction
			if "exit_distance" in target_node:
				use_exit_dist = target_node.exit_distance
			if "_teleport_cooldown" in target_node:
				target_node._teleport_cooldown = 0.35
		else:
			use_offset_dir = exit_direction

		# Calcular punto exacto de aparición en la sala destino
		var offset = Vector2.ZERO
		match use_offset_dir:
			"Arriba":
				offset = Vector2(0, -use_exit_dist)
			"Abajo":
				offset = Vector2(0, use_exit_dist)
			"Izquierda":
				offset = Vector2(-use_exit_dist, 0)
			"Derecha":
				offset = Vector2(use_exit_dist, 0)

		dest += offset
		dest = dest.round()

		_teleport_cooldown = 0.35
		if body.has_method("play_teleport_transition"):
			body.play_teleport_transition(dest, use_offset_dir)
		else:
			body.global_position = dest
			if body.has_method("_update_room_coords"):
				body._update_room_coords()

func _create_destination_node_in_editor() -> void:
	var parent = get_parent()
	if not parent:
		return

	var dest_scene = load("res://objects/transition/transition_area.tscn")
	if not dest_scene:
		return

	var dest_node = dest_scene.instantiate()
	var base_name = name + "_Dest"
	dest_node.name = base_name
	dest_node.position = position + Vector2(32, 0)
	dest_node.target_node = self
	dest_node.exit_direction = "Izquierda" if exit_direction == "Derecha" else ("Derecha" if exit_direction == "Izquierda" else "Abajo")
	dest_node.exit_distance = exit_distance

	target_node = dest_node
	parent.add_child(dest_node)

	var scene_root = owner
	if not scene_root and get_tree():
		scene_root = get_tree().edited_scene_root
	if scene_root:
		dest_node.call_deferred("set_owner", scene_root)

	queue_redraw()
	dest_node.queue_redraw()
	notify_property_list_changed()
	dest_node.notify_property_list_changed()

func _draw() -> void:
	if Engine.is_editor_hint():
		var shape_node = get_node_or_null("CollisionShape2D")
		if shape_node and shape_node.shape is RectangleShape2D:
			var rect_shape = shape_node.shape as RectangleShape2D
			var rect_size = rect_shape.size

			var current_draw_color = draw_color if enabled else Color(0.2, 0.9, 0.4, 0.7)

			# Contorno y relleno de la zona de entrada
			draw_rect(Rect2(-rect_size / 2.0, rect_size), current_draw_color, false, 1.5)
			draw_rect(Rect2(-rect_size / 2.0, rect_size), Color(current_draw_color.r, current_draw_color.g, current_draw_color.b, 0.12), true)

			# Línea de conexión al nodo destino
			if is_instance_valid(target_node):
				var local_target_pos = to_local(target_node.global_position)
				draw_line(Vector2.ZERO, local_target_pos, Color(current_draw_color.r, current_draw_color.g, current_draw_color.b, 0.4), 1.2)

			if enabled:
				# Ícono de portal / entrada
				draw_line(Vector2(0, 4), Vector2(0, -4), current_draw_color, 1.5)
				draw_line(Vector2(0, -4), Vector2(-3, -1), current_draw_color, 1.5)
				draw_line(Vector2(0, -4), Vector2(3, -1), current_draw_color, 1.5)
				draw_circle(Vector2.ZERO, 1.5, current_draw_color)
			else:
				draw_arc(Vector2.ZERO, 3.0, 0, TAU, 16, current_draw_color, 1.0, true)
				draw_circle(Vector2.ZERO, 1.0, current_draw_color)

			# Recuadro verde: muestra dónde aparecerá el jugador al salir por este nodo
			if exit_direction != "Ninguno":
				var offset = Vector2.ZERO
				match exit_direction:
					"Arriba": offset = Vector2(0, -exit_distance)
					"Abajo": offset = Vector2(0, exit_distance)
					"Izquierda": offset = Vector2(-exit_distance, 0)
					"Derecha": offset = Vector2(exit_distance, 0)

				# Línea verde y recuadro de spawn
				draw_line(Vector2.ZERO, offset, Color(0.2, 0.9, 0.4, 0.7), 1.0)
				draw_rect(Rect2(offset - Vector2(4, 5), Vector2(8, 10)), Color(0.2, 0.9, 0.4, 0.8), false, 1.0)
