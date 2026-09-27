extends CharacterBody2D
class_name Enemy

@export var target: Player
@export var move_speed: float = 90.0
@export var max_health: float = 3.0
@export var stop_distance: float = 24.0
@export var contact_damage: float = 10.0
@export var attack_interval: float = 0.8
@export var contact_attack_parryable: bool = true

@onready var attack_range: Area2D = $AttackRange

var attack_cooldown_left: float = 0.0
var health: float
var stun_left: float = 0.0


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var toward_player := target.global_position - global_position

	if toward_player.length() > stop_distance:
		velocity = toward_player.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)

	if attack_cooldown_left <= 0.0 and attack_range.overlaps_body(target):
		target.receive_attack(
			contact_damage,
			self,
			contact_attack_parryable
		)
		attack_cooldown_left = attack_interval


func stun(duration: float) -> void:
	stun_left = maxf(stun_left, duration)
	velocity = Vector2.ZERO


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)

	if health <= 0.0:
		queue_free()
