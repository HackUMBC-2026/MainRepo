extends CharacterBody2D

class_name Player

@export var max_health: float = 100.0
@export var health: float = 100.0
@export var move_speed: float = 150.0
@export var sprint_speed: float = 250.0
@export var stamina: float = 240
@export var C_MAX_STAMINA: float = 240
@export var is_invincible: bool = false
@export var dash_movement_lock_time: float = 0
@export var is_dashing: bool = false
@export var C_DASH_SPEED: float = 1000.0
@export var C_DASH_DISTANCE: float = 20
var dash_vector: Vector2 = Vector2.ZERO
@onready var sprite: Sprite2D = $Sprite2D


var is_sprinting: bool = false
func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
        "move_down"
	)
	if(Input.is_action_pressed("dash") && stamina > 120.0 && !isMovementLocked()):
		dash_vector = direction
		dash_movement_lock_time = C_DASH_DISTANCE
		stamina -= 120
		is_dashing = true
	
	if(is_dashing):
		velocity = (dash_vector * C_DASH_SPEED) * (1.0 - 0.3 * (dash_movement_lock_time / 30.0) - 0.7 * pow(dash_movement_lock_time / 30.0, 7))
		dash_movement_lock_time -= 1
		move_and_slide()
		if(!dash_movement_lock_time):
			is_dashing = false
		return
		
	
	if not Input.is_action_pressed("sprint"):
		is_sprinting = false
	elif Input.is_action_just_pressed("sprint"):
		is_sprinting = stamina > 60

	if stamina <= 0:
		is_sprinting = false

	if is_sprinting and direction != Vector2.ZERO:
		stamina = maxf(stamina - 1, 0)

		if stamina <= 0:
			is_sprinting = false
	else:
		stamina = minf(stamina + 0.5, C_MAX_STAMINA)

	if is_sprinting:
		velocity = direction * sprint_speed
	else:
		velocity = direction * move_speed
	move_and_slide()

	update_facing(direction)

func isMovementLocked() -> bool:
	if(dash_movement_lock_time):
		return true
	return false
func update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	if absf(direction.x) > absf(direction.y):
		sprite.rotation_degrees = 90.0 if direction.x > 0.0 else -90.0
	else:
		sprite.rotation_degrees = 180.0 if direction.y > 0.0 else 0.0
