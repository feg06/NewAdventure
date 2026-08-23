class_name FloorButton
extends Area2D

## Action Floor Button / Pressure Plate
## Activates when a Player, a Pushable Box, or a Grabbable Item is on top of it.

signal pressed(button: FloorButton)
signal released(button: FloorButton)

@export var button_id: String = "btn_1"
@export var is_permanent: bool = false # If true, stays pressed forever once activated

@onready var sprite: Sprite2D = $Sprite2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

@export var is_pressed: bool = false:
	set(val):
		is_pressed = val
		if sprite:
			sprite.frame = 1 if is_pressed else 0

var overlapping_objects: Array[Node2D] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_update_state()

func _on_body_entered(body: Node2D) -> void:
	if _is_valid_body(body):
		if not overlapping_objects.has(body):
			overlapping_objects.append(body)
		_update_state()

func _on_body_exited(body: Node2D) -> void:
	overlapping_objects.erase(body)
	_update_state()

func _on_area_entered(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent is GrabbableItem:
		if not overlapping_objects.has(parent):
			overlapping_objects.append(parent)
		_update_state()

func _on_area_exited(area: Area2D) -> void:
	var parent = area.get_parent()
	if parent is GrabbableItem:
		overlapping_objects.erase(parent)
		_update_state()

func _is_valid_body(node: Node) -> bool:
	return node.is_in_group("players") or node.is_in_group("boxes") or node.is_in_group("pushable_boxes")

func _update_state() -> void:
	# Clean any freed references
	overlapping_objects = overlapping_objects.filter(func(obj): return is_instance_valid(obj))
	var should_be_pressed = (overlapping_objects.size() > 0) or (is_permanent and is_pressed)

	if should_be_pressed != is_pressed:
		is_pressed = should_be_pressed
		if is_pressed:
			pressed.emit(self)
			Events.button_state_changed.emit(button_id, true)
		else:
			released.emit(self)
			Events.button_state_changed.emit(button_id, false)
