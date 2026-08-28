class_name Checkpoint
extends Area2D

## Checkpoint Area / Flagpole Respawn Point
##
## Colisiones:
##   - ObstacleBody (StaticBody2D en Layer 1): Sólido para Enemigos, Cajas y Proyectiles.
##   - El Jugador tiene excepción de colisión (add_collision_exception_with), permitiéndole
##     atravesar y tocar el Area2D libremente sin trabarse.
##
## Mecánica de Bandera Clásica:
##   1. Inicial (Rojo): La bandera roja está arriba en el mástil.
##   2. Al tocarlo (Rojo -> Blanco):
##      - La bandera roja BAJA hasta la base del mástil.
##      - En la base cambia a color BLANCO.
##      - La bandera blanca SUBE hasta la cima.
##   3. Al activar otro checkpoint (Blanco -> Azul):
##      - Este checkpoint anterior pasa a color AZUL (visitado).
##   4. Al reactivar un checkpoint azul (Azul -> Blanco):
##      - La bandera azul BAJA hasta la base.
##      - Cambia a color BLANCO y SUBE hasta la cima.

enum State {
	UNVISITED,
	ACTIVE,
	VISITED
}

const COLOR_UNVISITED: Color = Color(0.95, 0.25, 0.25, 1.0) # Rojo
const COLOR_ACTIVE: Color = Color(1.0, 1.0, 1.0, 1.0)        # Blanco
const COLOR_VISITED: Color = Color(0.25, 0.65, 1.0, 1.0)     # Azul

const FLAG_POS_TOP: float = 0.0
const FLAG_POS_BOTTOM: float = 8.0

@export var state: State = State.UNVISITED:
	set(val):
		state = val
		_update_visuals()

@onready var pole_sprite: Sprite2D = $PoleSprite
@onready var flag_sprite: Sprite2D = $FlagSprite
@onready var obstacle_body: StaticBody2D = $ObstacleBody

var is_animating: bool = false
var current_tween: Tween = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	Events.checkpoint_activated.connect(_on_other_checkpoint_activated)
	Events.player_spawned.connect(_on_player_spawned)

	# Excluir a los jugadores de colisionar físicamente con el mástil
	for p in get_tree().get_nodes_in_group("players"):
		_ignore_player_collision(p)

	_update_visuals()

func _on_player_spawned(_peer_id: int, player: CharacterBody2D) -> void:
	_ignore_player_collision(player)

func _ignore_player_collision(player: CharacterBody2D) -> void:
	if obstacle_body and player and is_instance_valid(player):
		obstacle_body.add_collision_exception_with(player)

func _on_body_entered(body: Node2D) -> void:
	if body is Player and is_instance_valid(body):
		_ignore_player_collision(body)
		if state != State.ACTIVE and not is_animating:
			activate_checkpoint(body)

func activate_checkpoint(player: Player) -> void:
	is_animating = true
	state = State.ACTIVE
	player.set_checkpoint(global_position)
	Events.checkpoint_activated.emit(self, global_position)

	if flag_sprite:
		if current_tween and current_tween.is_valid():
			current_tween.kill()

		current_tween = create_tween()
		# 1. La bandera actual (roja o azul) baja hasta la base
		current_tween.tween_property(flag_sprite, "position:y", FLAG_POS_BOTTOM, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		# 2. Al llegar abajo, cambia inmediatamente a blanco
		current_tween.tween_callback(func():
			flag_sprite.modulate = COLOR_ACTIVE
		)
		
		# 3. La bandera blanca sube hasta la cima del mástil
		current_tween.tween_property(flag_sprite, "position:y", FLAG_POS_TOP, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# 4. Finalizar animación
		current_tween.tween_callback(func():
			is_animating = false
		)

func _on_other_checkpoint_activated(checkpoint_node: Node2D, _respawn_pos: Vector2) -> void:
	if checkpoint_node == self:
		return

	# Si se activa otro checkpoint y este estaba activo o visitado, se vuelve azul
	if state == State.ACTIVE or state == State.VISITED:
		state = State.VISITED
		if flag_sprite and not is_animating:
			if current_tween and current_tween.is_valid():
				current_tween.kill()
			current_tween = create_tween()
			current_tween.tween_property(flag_sprite, "modulate", COLOR_VISITED, 0.3)

func _update_visuals() -> void:
	if not is_node_ready() or flag_sprite == null or is_animating:
		return

	match state:
		State.UNVISITED:
			flag_sprite.modulate = COLOR_UNVISITED
			flag_sprite.position.y = FLAG_POS_TOP
		State.ACTIVE:
			flag_sprite.modulate = COLOR_ACTIVE
			flag_sprite.position.y = FLAG_POS_TOP
		State.VISITED:
			flag_sprite.modulate = COLOR_VISITED
			flag_sprite.position.y = FLAG_POS_TOP
