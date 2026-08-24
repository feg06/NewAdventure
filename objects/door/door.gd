class_name CastleDoor
extends StaticBody2D

## Castle Door / Portcullis
## Can be opened by buttons, events, or by bringing the matching key.
## When open, disables its collision allowing the player to pass through.

signal opened()
signal closed()

@export var door_id: String = "door_1"
@export var is_open: bool = false:
	set(val):
		is_open = val
		_update_state_visuals()

@export var keep_open_once_unlocked: bool = true ## Si es true, una vez abierta permanece abierta para siempre
@export var open_on_button_id: String = ""       ## ID del botón de suelo que abre esta puerta (ej: "btn_1")
@export var requires_key: bool = false           ## Si requiere una llave para abrirse
@export var required_key_id: String = "key_01"   ## ID de la llave requerida (ej: "key_01", "key_02", etc.)
@export var consume_key_on_use: bool = true     ## Si la llave se consume/desaparece al abrir la puerta

# Network Synced
@export var sync_is_open: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var key_receptor_area: Area2D = $KeyReceptorArea
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	Events.button_state_changed.connect(_on_button_state_changed)

	if key_receptor_area:
		key_receptor_area.body_entered.connect(_on_key_receptor_body_entered)
		key_receptor_area.area_entered.connect(_on_key_receptor_area_entered)

	_update_state_visuals()

func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority() and sync_is_open != is_open:
		is_open = sync_is_open
		_update_state_visuals()

func open() -> void:
	if is_open:
		return
	is_open = true
	sync_is_open = true

	if animated_sprite:
		animated_sprite.play("opening")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	opened.emit()
	Events.door_opened.emit(door_id)

func close() -> void:
	if not is_open or keep_open_once_unlocked:
		return
	is_open = false
	sync_is_open = false

	if animated_sprite:
		animated_sprite.play("closing")
	if collision_shape:
		collision_shape.set_deferred("disabled", false)

	closed.emit()
	Events.door_closed.emit(door_id)

func _update_state_visuals() -> void:
	if not is_node_ready():
		return

	if animated_sprite:
		if is_open:
			animated_sprite.play("open")
		else:
			animated_sprite.play("closed")

	if collision_shape:
		collision_shape.set_deferred("disabled", is_open)

func _on_button_state_changed(btn_id: String, is_pressed: bool) -> void:
	if open_on_button_id != "" and btn_id == open_on_button_id:
		if is_pressed:
			open()
		else:
			close()

func _on_key_receptor_body_entered(body: Node2D) -> void:
	if not requires_key or is_open:
		return

	# Si el jugador entra cargando la llave requerida
	if body is CharacterBody2D and "carried_item" in body:
		var item = body.carried_item
		if _is_matching_key(item):
			_unlock_with_key(item)

func _on_key_receptor_area_entered(area: Area2D) -> void:
	if not requires_key or is_open:
		return

	var parent = area.get_parent()
	if _is_matching_key(parent):
		_unlock_with_key(parent)

func _unlock_with_key(item: Node) -> void:
	open()
	if consume_key_on_use and item != null and is_instance_valid(item):
		if item.has_method("consume"):
			item.consume()
		else:
			item.queue_free()

func _is_matching_key(item: Node) -> bool:
	if item is GrabbableItem:
		if required_key_id == "" or item.item_id == required_key_id:
			return true
	return false
