class_name EnemyGuardianFury
extends EnemyGuardian

## Enemy Guardian Fury - Variante de élite
##
## Diferencias con EnemyGuardian estándar:
##   - 3 puntos de salud (max_health = 3)
##   - Mayor velocidad de movimiento (move_speed = 58.0)
##   - Mayor rango de visión y detección (sight_radius = 100.0)

func _init() -> void:
	max_health = 3
	move_speed = 58.0
	sight_radius = 100.0
