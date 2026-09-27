extends CharacterBody2D
class_name Player

signal died

const FRONT_TEXTURE: Texture2D = preload("res://assets/FrontFeatherJoan.png")
const BACK_TEXTURE: Texture2D = preload("res://assets/Joan back.png")
const RIGHT_TEXTURE: Texture2D = preload("res://assets/ProfileJoan.png")
const LEFT_TEXTURE: Texture2D = preload("res://assets/ProfileLeftJoan.png")

@export_group("Health")
@export var max_health: float = 100.0
@export var health: float = 100.0
@export var invincibility_duration: float = 0.6
@export var is_invincible: bool = false

@export_group("Movement")
@export var move_speed: float = 150.0
@export var sprint_speed: float = 250.0
@export var acceleration_time: float = 0.05
@export var stopping_time: float = 0.03

@export_group("Stamina")
@export var stamina: float = 240.0
@export var C_MAX_STAMINA: float = 240.0
@export var sprint_start_threshold: float = 60.0
@export var sprint_drain_per_second: float = 60.0
@export var stamina_regen_per_second: float = 30.0

@export_group("Dash")
@export var C_DASH_SPEED: float = 1000.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.15
@export var dash_buffer_time: float = 0.1
@export var dash_stamina_cost: float = 60.0

@export_group("Visuals")
@export var dash_stretch: float = 0.08

@onready var sprite: Sprite2D = $Sprite2D
@onready var sword: Node2D = $"SwordAnchor (Node2D)/Sword (Node2D)"
@onready var specials: Node2D = $SpecialAttacks

var heavy_attack_locked: bool = false
var binding_time_left: float = 0.0
var binding_duration: float = 0.0
var binding_source: Node
var invincibility_left: float = 0.0
var is_sprinting: bool = false
var is_dashing: bool = false
var dash_movement_lock_time: float = 0.0
var dash_vector: Vector2 = Vector2.ZERO

var _facing_direction: Vector2 = Vector2.DOWN
var _dash_buffer_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _base_sprite_scale: Vector2


func _ready() -> void:
	add_to_group("player")
	sprite.rotation = 0.0
	sprite.texture = FRONT_TEXTURE
	_base_sprite_scale = sprite.scale


func _process(delta: float) -> void:
	if invincibility_left > 0.0:
		invincibility_left = maxf(invincibility_left - delta, 0.0)

		if invincibility_left <= 0.0:
			is_invincible = false


func take_damage(amount: float) -> void:
	if is_invincible or health <= 0.0:
		return

	health = maxf(health - amount, 0.0)

	if health <= 0.0:
		velocity = Vector2.ZERO
		is_sprinting = false
		is_dashing = false
		dash_movement_lock_time = 0.0
		heavy_attack_locked = false
		clear_holy_binding()
		died.emit()
		set_physics_process(false)
		return

	is_invincible = true
	invincibility_left = invincibility_duration


func receive_attack(
	amount: float,
	attacker: Node,
	parryable: bool = true
) -> void:
	if health <= 0.0:
		return
	var damage_multiplier := 1.0
	if is_instance_valid(sword) and sword.has_method("defend_against_attack"):
		damage_multiplier = float(
			sword.call("defend_against_attack", attacker, parryable)
		)

	if damage_multiplier <= 0.0:
		return

	take_damage(amount * damage_multiplier)


func _physics_process(delta: float) -> void:
	if specials.tick(delta):
		update_sprite_stretch(delta)
		return
	if binding_time_left > 0.0:
		if not is_instance_valid(binding_source) or binding_source.is_queued_for_deletion():
			clear_holy_binding()
		else:
			binding_time_left = maxf(binding_time_left - delta, 0.0)
			if binding_time_left <= 0.0:
				clear_holy_binding()
			else:
				velocity = Vector2.ZERO
				is_sprinting = false
				is_dashing = false
				dash_movement_lock_time = 0.0
				_dash_buffer_left = 0.0
				_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
				stamina = clampf(stamina, 0.0, C_MAX_STAMINA)
				update_stamina(Vector2.ZERO, delta)
				update_facing(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
				update_sprite_stretch(delta)
				queue_redraw()
				return
	if heavy_attack_locked:
		velocity = Vector2.ZERO
		is_sprinting = false
		is_dashing = false
		dash_movement_lock_time = 0.0
		move_and_slide()
		return
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	stamina = clampf(stamina, 0.0, C_MAX_STAMINA)

	_dash_buffer_left = maxf(_dash_buffer_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)

	if Input.is_action_just_pressed("dash"):
		_dash_buffer_left = maxf(dash_buffer_time, delta)

	update_sprint_state()

	if not is_dashing:
		update_facing(direction)

		if (
			_dash_buffer_left > 0.0
			and _dash_cooldown_left <= 0.0
			and stamina >= dash_stamina_cost
		):
			start_dash(direction)

	if is_dashing:
		process_dash(direction, delta)
	else:
		update_stamina(direction, delta)
		process_normal_movement(direction, delta)

	update_sprite_stretch(delta)


func update_sprint_state() -> void:
	if not Input.is_action_pressed("sprint"):
		is_sprinting = false
	elif Input.is_action_just_pressed("sprint"):
		is_sprinting = stamina > sprint_start_threshold

	if stamina <= 0.0:
		is_sprinting = false


func update_stamina(direction: Vector2, delta: float) -> void:
	if is_sprinting and direction != Vector2.ZERO:
		stamina = maxf(
			stamina - sprint_drain_per_second * delta,
			0.0
		)

		if stamina <= 0.0:
			is_sprinting = false
	else:
		stamina = minf(
			stamina + stamina_regen_per_second * delta,
			C_MAX_STAMINA
		)


func normal_speed() -> float:
	return sprint_speed if is_sprinting else move_speed


func process_normal_movement(direction: Vector2, delta: float) -> void:
	var current_speed := velocity.length()
	var target_speed := normal_speed() * direction.length()
	var rate: float

	if target_speed > current_speed:
		rate = normal_speed() / maxf(acceleration_time, 0.001)
	else:
		rate = sprint_speed / maxf(stopping_time, 0.001)

	if direction != Vector2.ZERO:
		var new_speed := move_toward(
			current_speed,
			target_speed,
			rate * delta
		)
		velocity = direction.normalized() * new_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, rate * delta)

	move_and_slide()


func start_dash(direction: Vector2) -> void:
	dash_vector = (
		direction.normalized()
		if direction != Vector2.ZERO
		else _facing_direction
	)

	stamina = maxf(stamina - dash_stamina_cost, 0.0)

	if stamina <= 0.0:
		is_sprinting = false

	is_dashing = true
	dash_movement_lock_time = maxf(dash_duration, 0.001)
	_dash_buffer_left = 0.0

	update_facing(dash_vector)


func process_dash(direction: Vector2, delta: float) -> void:
	var progress := clampf(
		1.0 - dash_movement_lock_time / maxf(dash_duration, 0.001),
		0.0,
		1.0
	)

	var curve := 1.0 - 0.3 * progress - 0.7 * pow(progress, 7.0)
	var speed := lerpf(normal_speed(), C_DASH_SPEED, curve)

	velocity = dash_vector * speed
	move_and_slide()

	dash_movement_lock_time = maxf(
		dash_movement_lock_time - delta,
		0.0
	)

	if dash_movement_lock_time <= 0.0:
		is_dashing = false
		_dash_cooldown_left = maxf(dash_cooldown, 0.0)

		velocity = direction * normal_speed()
		update_facing(direction)


func isMovementLocked() -> bool:
	return is_dashing or binding_time_left > 0.0


func apply_holy_binding(duration: float, source: Node) -> void:
	if health <= 0.0 or duration <= 0.0 or not is_instance_valid(source):
		return
	binding_source = source
	binding_duration = duration
	binding_time_left = duration
	velocity = Vector2.ZERO
	is_sprinting = false
	is_dashing = false
	dash_movement_lock_time = 0.0
	_dash_buffer_left = 0.0
	queue_redraw()


func clear_holy_binding(source: Node = null) -> void:
	if source != null and binding_source != source:
		return
	binding_time_left = 0.0
	binding_duration = 0.0
	binding_source = null
	queue_redraw()


func _draw() -> void:
	if binding_time_left <= 0.0:
		return
	var center := Vector2(0.0, 8.0)
	var gold := Color(1.0, 0.8, 0.3)
	var remaining := clampf(binding_time_left / maxf(binding_duration, 0.001), 0.0, 1.0)
	draw_circle(center, 28.0, Color(gold, 0.12))
	draw_arc(center, 28.0, 0.0, TAU, 48, Color(gold, 0.5), 1.5)
	draw_arc(center, 32.0, -PI * 0.5, -PI * 0.5 + TAU * remaining, 48, gold, 2.5)
	for index in range(4):
		var direction := Vector2.RIGHT.rotated(PI * 0.25 + float(index) * PI * 0.5)
		var across := direction.orthogonal()
		for link in range(4):
			var link_center := center + direction * (9.0 + float(link) * 6.0)
			draw_polyline(PackedVector2Array([
				link_center - direction * 4.0, link_center + across * 2.0,
				link_center + direction * 4.0, link_center - across * 2.0,
				link_center - direction * 4.0,
			]), gold, 1.5)


func facing_direction() -> Vector2:
	return _facing_direction


func facing_angle() -> float:
	return Vector2.UP.angle_to(_facing_direction)


func update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	var new_facing: Vector2
	if absf(direction.x) > absf(direction.y):
		new_facing = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	else:
		new_facing = Vector2.DOWN if direction.y > 0.0 else Vector2.UP

	if new_facing == _facing_direction:
		return

	_facing_direction = new_facing
	if new_facing == Vector2.RIGHT:
		sprite.texture = RIGHT_TEXTURE
	elif new_facing == Vector2.LEFT:
		sprite.texture = LEFT_TEXTURE
	elif new_facing == Vector2.DOWN:
		sprite.texture = FRONT_TEXTURE
	else:
		sprite.texture = BACK_TEXTURE


func update_sprite_stretch(delta: float) -> void:
	var target_scale := _base_sprite_scale

	if is_dashing:
		var local_direction := dash_vector.rotated(
			-sprite.global_rotation
		).abs()

		var stretch := Vector2(
			1.0 + dash_stretch * (local_direction.x - local_direction.y),
			1.0 + dash_stretch * (local_direction.y - local_direction.x)
		)

		target_scale *= stretch

	sprite.scale = sprite.scale.lerp(
		target_scale,
		1.0 - exp(-25.0 * delta)
	)
