class_name PlayerHUD
extends CanvasLayer

@export var max_hearts: int = 5
@export var current_hearts: int = 5
@export var heart_separation: int = 1 ## Separación en píxeles entre corazones (estilo Zelda retro)

const HEART_TEXTURE = preload("res://ui/assets/Hud.png")

@onready var margin_container: MarginContainer = $MarginContainer
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

	hearts_container.add_theme_constant_override("separation", heart_separation)

	for child in hearts_container.get_children():
		child.queue_free()

	for i in range(max_hearts):
		var heart = TextureRect.new()
		var atlas = AtlasTexture.new()
		atlas.atlas = HEART_TEXTURE
		atlas.region = Rect2(4, 4, 7, 7) # Bounding box exacto de 7x7 px
		heart.texture = atlas
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP
		heart.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
			heart.modulate = Color(0.15, 0.15, 0.15, 0.35)
