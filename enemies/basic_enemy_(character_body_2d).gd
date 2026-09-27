extends CharacterBody2D
class_name Enemy

@export var target: Player
@export var move_speed: float = 90.0
@export var max_health: float = 3.0
@export var stop_distance: float = 24.0
@export var contact_damage: float = 10.0
@export var attack_interval: float = 0.8

@onready var attack_range: Area2D = $AttackRange

var attack_cooldown_left: float = 0.0
var health: float


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
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
		target.take_damage(contact_damage)
		attack_cooldown_left = attack_interval


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)

	if health <= 0.0:
		queue_free()
