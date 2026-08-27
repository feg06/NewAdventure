class_name PlayerHUD
extends CanvasLayer

@export var max_hearts: int = 5
@export var current_hearts: int = 5

const HEART_TEXTURE = preload("res://ui/assets/Hud.png")

@onready var hearts_container: HBoxContainer = $MarginContainer/HeartsContainer

func _ready() -> void:
	Events.player_health_changed.connect(_on_player_health_changed)
	_rebuild_hearts()

func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	current_hearts = current_hp
	max_hearts = max_hp
	_update_hearts_display()

func _rebuild_hearts() -> void:
	if not hearts_container:
		return

	# Limpiar anteriores
	for child in hearts_container.get_children():
		child.queue_free()

	for i in range(max_hearts):
		var heart = TextureRect.new()
		heart.texture = HEART_TEXTURE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.custom_minimum_size = Vector2(10, 10)
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hearts_container.add_child(heart)

	_update_hearts_display()

func _update_hearts_display() -> void:
	if not hearts_container:
		return

	var heart_nodes = hearts_container.get_children()
	if heart_nodes.size() != max_hearts:
		_rebuild_hearts()
		return

	for i in range(heart_nodes.size()):
		var heart = heart_nodes[i] as TextureRect
		if i < current_hearts:
			heart.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			# Corazón vacío / dañado
			heart.modulate = Color(0.15, 0.15, 0.15, 0.4)
