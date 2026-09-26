extends CharacterBody2D

class_name Player

@export var max_health: float = 100.0
@export var health: float = 100.0
@export var move_speed: float = 150.0
@export var sprint_speed: float = 250.0
@export var stamina: float = 240
@export var C_MAX_STAMINA: float = 240
@export var is_invincible: bool = false
@onready var sprite: Sprite2D = $Sprite2D


var is_sprinting: bool = false
func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
        "move_down"
	)
	
	if(Input.is_action_pressed("sprint") && stamina > 60 && direction):
		is_sprinting = true
		stamina -= 1
	else:
		is_sprinting = false
		if(stamina < C_MAX_STAMINA):
			stamina += 0.5
	if(is_sprinting):
		velocity = direction * sprint_speed 
	else:
		velocity = direction * move_speed 
	move_and_slide()

	update_facing(direction)


func update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	if absf(direction.x) > absf(direction.y):
		sprite.rotation_degrees = 90.0 if direction.x > 0.0 else -90.0
	else:
		sprite.rotation_degrees = 180.0 if direction.y > 0.0 else 0.0
