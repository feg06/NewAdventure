class_name GrabbableItem
extends Node2D

@export var item_id: String = "key_gold"
@export var item_display_name: String = "Gold Key"
@export var item_color: Color = Color(0.95, 0.8, 0.2, 1.0)
@export var custom_texture: Texture2D = null

@onready var area: Area2D = $Area2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var sprite: Sprite2D = $Sprite2D

# Network synced
@export var sync_pos: Vector2 = Vector2.ZERO
@export var sync_carrier_peer_id: int = 0

var carrier: CharacterBody2D = null

const KEY_TEXTURE = preload("res://items/assets/Key.png")

func _ready() -> void:
	if sync_pos != Vector2.ZERO:
		global_position = sync_pos
	else:
		sync_pos = global_position
	
	_update_visuals()

func _physics_process(_delta: float) -> void:
	if carrier != null and is_instance_valid(carrier):
		global_position = carrier.global_position + Vector2(carrier.facing_direction * 10.0, -2.0)
		sync_pos = global_position
	elif multiplayer.is_server():
		sync_pos = global_position

func pick_up_by(player: CharacterBody2D) -> void:
	carrier = player
	sync_carrier_peer_id = player.name.to_int()
	if sync_carrier_peer_id == 0:
		sync_carrier_peer_id = 1
	sync_pos = global_position

func drop_at(drop_pos: Vector2) -> void:
	carrier = null
	sync_carrier_peer_id = 0
	global_position = drop_pos
	sync_pos = drop_pos

func _update_visuals() -> void:
	if custom_texture != null:
		sprite.texture = custom_texture
		sprite.modulate = item_color
		sprite.visible = true
	elif item_id.begins_with("key"):
		sprite.texture = KEY_TEXTURE
		sprite.modulate = item_color
		sprite.visible = true
	else:
		sprite.visible = false
		queue_redraw()

func _draw() -> void:
	if sprite != null and sprite.visible:
		return

	match item_id:
		"chalice":
			var col = item_color
			draw_rect(Rect2(-5, -6, 10, 3), col)
			draw_rect(Rect2(-4, -3, 8, 4), col)
			draw_rect(Rect2(-2, 1, 4, 3), col)
			draw_rect(Rect2(-4, 4, 8, 2), col)
		_:
			draw_rect(Rect2(-4, -4, 8, 8), item_color)
