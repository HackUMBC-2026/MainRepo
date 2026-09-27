extends CharacterBody2D
class_name Enemy

@export var target: Player
@export var move_speed: float = 90.0
@export var max_health: float = 3.0
@export var stop_distance: float = 24.0
@export var contact_damage: float = 10.0
@export var attack_interval: float = 0.8
@export var contact_attack_parryable: bool = true
@export var show_health_bar: bool = true

@export_group("Melee Sweep")
@export var sweep_radius: float = 46.0
@export var sweep_inner_radius: float = 12.0
@export_range(30.0, 360.0, 1.0) var sweep_angle_degrees: float = 220.0
@export var sweep_windup_seconds: float = 0.45
@export var sweep_seconds: float = 0.3
@export var sweep_recovery_seconds: float = 0.18
@export_flags_2d_physics var melee_obstruction_mask: int = 1

@export_group("Sweep Sword Appearance")
@export var sword_texture: Texture2D
@export var sword_display_height: float = 40.0
# Position of the grip within the texture, measured from its top-left corner (0 to 1).
@export var sword_texture_pivot: Vector2 = Vector2(0.5, 0.85)
# Default assumes the blade points up in the texture.
@export var sword_rotation_degrees: float = 0.0

@onready var melee_sweep = $MeleeSweep

var attack_cooldown_left: float = 0.0
var health: float
var stun_left: float = 0.0


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	if health <= 0.0:
		return
	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not is_instance_valid(target) or target.health <= 0.0:
		melee_sweep.cancel()
		velocity = Vector2.ZERO
		return
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	if update_melee_attack(delta):
		return

	var toward_player := target.global_position - global_position

	if toward_player.length() > stop_distance:
		velocity = toward_player.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	try_start_melee_attack()


func try_start_melee_attack() -> void:
	if attack_cooldown_left <= 0.0 and stun_left <= 0.0:
		melee_sweep.try_start()


func update_melee_attack(delta: float) -> bool:
	if not melee_sweep.active:
		return false
	velocity = Vector2.ZERO
	move_and_slide()
	melee_sweep.advance(delta)
	return true


func stun(duration: float) -> void:
	stun_left = maxf(stun_left, duration)
	velocity = Vector2.ZERO
	if duration > 0.0:
		melee_sweep.cancel()


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)

	if health <= 0.0:
		melee_sweep.cancel()
		queue_free()
