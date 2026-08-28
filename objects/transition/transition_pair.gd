@tool
class_name TransitionPair
extends Node2D

## Transition Pair Helper
## Al arrastrar este nodo a la escena en el editor, crea automáticamente
## dos TransitionArea conectadas entre sí (A <-> B).

func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_setup_in_editor")

func _setup_in_editor() -> void:
	var parent = get_parent()
	if not parent:
		return

	var scene_root = get_tree().edited_scene_root
	if not scene_root or scene_root == self:
		return

	var area_scene = load("res://objects/transition/transition_area.tscn")
	if not area_scene:
		printerr("No se pudo cargar res://objects/transition/transition_area.tscn")
		return

	var entrance = area_scene.instantiate()
	var exit = area_scene.instantiate()

	entrance.name = _get_unique_name(parent, "Transition_A")
	exit.name = _get_unique_name(parent, "Transition_B")

	entrance.position = position
	exit.position = position + Vector2(48, 0)

	parent.add_child(entrance)
	parent.add_child(exit)

	entrance.call_deferred("set_owner", scene_root)
	exit.call_deferred("set_owner", scene_root)

	# Conectar bidireccionalmente por defecto
	entrance.target_node = exit
	exit.target_node = entrance

	entrance.enabled = true
	entrance.exit_direction = "Derecha"
	exit.enabled = true
	exit.exit_direction = "Izquierda"

	entrance.queue_redraw()
	exit.queue_redraw()
	entrance.notify_property_list_changed()
	exit.notify_property_list_changed()

	print("--- TRANSICIÓN CREADA ---")
	print("Nodos conectados: ", entrance.name, " (Salida: Derecha) <-> ", exit.name, " (Salida: Izquierda)")
	print("-------------------------")

	queue_free()

func _get_unique_name(parent: Node, base_name: String) -> String:
	var name_to_try = base_name
	var counter = 1
	while parent.has_node(name_to_try):
		name_to_try = base_name + "_" + str(counter)
		counter += 1
	return name_to_try
