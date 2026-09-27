extends Sprite2D

signal attack_window_started(hilt_first: bool)
signal attack_window_ended
signal heavy_impact(world_position: Vector2, charge: float)

enum SwordPosition { LEFT, CENTER, RIGHT }
enum AttackType { NONE, LEFT, CENTER, HEAVY }

@export var player_sprite: Sprite2D
@export var camera: Camera2D

@export_group("Sword Tips")
@export var blade_tip_distance: float = 24.0
@export var hilt_tip_distance: float = 12.0

@export_group("Floating")
@export var orbit_speed: float = 10.0
@export var blade_rotation_speed: float = 8.0
@export var center_orbit_radius: float = 36.0
@export var hover_amount: float = 2.0
@export var hover_frequency: float = 0.8
@export var sprint_trail_distance: float = 7.0
@export var dash_trail_distance: float = 18.0
@export var trail_follow_speed: float = 14.0

@export_group("Left: Double Swipe")
@export var left_range: float = 100.0
@export var left_arc_degrees: float = 160.0
@export var left_swipe_time: float = 0.13
@export var left_gap_time: float = 0.05
@export var left_recovery_time: float = 0.10

@export_group("Center: Thrust")
@export var thrust_range: float = 200.0
@export var thrust_pullback: float = 10.0
@export var thrust_windup_time: float = 0.08
@export var thrust_out_time: float = 0.13
@export var thrust_return_time: float = 0.15

@export_group("Right: Heavy Slam")
@export var heavy_range: float = 120.0
@export var heavy_windback: float = 30.0
@export var heavy_lift: float = 20.0
@export var max_charge_time: float = 1.2
@export var heavy_slam_time: float = 0.20
@export var heavy_recovery_time: float = 0.32
@export var shake_time: float = 0.18
@export var shake_pixels: float = 5.0

@export_group("General")
@export var attack_cooldown: float = 0.10

@export_group("Damage")
@export var swipe_damage: float = 1.0
@export var thrust_damage: float = 2.0
@export var heavy_damage: float = 3.0
@export var heavy_impact_radius: float = 20.0

@onready var blade_hitbox: Area2D = $BladeHitbox
@onready var hilt_hitbox: Area2D = $HiltHitbox

var damaged_this_window: Dictionary = {}
var pending_heavy_hit: bool = false
var pending_heavy_position: Vector2 = Vector2.ZERO

var selected_position := SwordPosition.RIGHT
var hilt_first: bool = false
var is_attacking: bool = false
var is_striking: bool = false

var elapsed_time: float = 0.0
var orbit_angle: float = 0.0
var orbit_radius: float = 24.0
var current_orbit_radius: float = 24.0
var resting_rotation: float = 0.0
var trail_offset: Vector2 = Vector2.ZERO

var attack_type := AttackType.NONE
var attack_phase: int = 0
var phase_time: float = 0.0
var cooldown_left: float = 0.0

var aim_direction: Vector2 = Vector2.UP
var aim_angle: float = 0.0
var tip_target_distance: float = 0.0
var strike_center_distance: float = 0.0

var attack_start_angle: float = 0.0
var attack_start_center: Vector2 = Vector2.ZERO
var attack_angle: float = 0.0
var attack_center: Vector2 = Vector2.ZERO
var attack_height: float = 0.0
var slam_start_center: Vector2 = Vector2.ZERO
var charge: float = 0.0

var shake_left: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var camera_rest_offset: Vector2 = Vector2.ZERO

@onready var anchor: Node2D = get_parent() as Node2D
@onready var player: Player = anchor.get_parent() as Player


func _ready() -> void:
	if not is_instance_valid(player_sprite):
		push_error("Assign the player's Sprite2D to Player Sprite.")
		set_process(false)
		return

	var starting_offset := anchor.position + position

	if starting_offset.length() > 0.0:
		orbit_radius = starting_offset.length()
		orbit_angle = Vector2.UP.angle_to(starting_offset)

	current_orbit_radius = orbit_radius
	resting_rotation = rotation

	if is_instance_valid(camera):
		camera_rest_offset = camera.offset
		
func _physics_process(_delta: float) -> void:
	if is_striking:
		var hitbox := hilt_hitbox if hilt_first else blade_hitbox
		var damage := (
			thrust_damage
			if attack_type == AttackType.CENTER
			else swipe_damage
		)

		for body in hitbox.get_overlapping_bodies():
			if body is Enemy and not damaged_this_window.has(body):
				damaged_this_window[body] = true
				body.take_damage(damage)

	if pending_heavy_hit:
		pending_heavy_hit = false
		damage_heavy_impact()

func _process(delta: float) -> void:
	elapsed_time += delta
	cooldown_left = maxf(cooldown_left - delta, 0.0)

	if not is_attacking:
		read_sword_inputs()

		if Input.is_action_just_pressed("attack") and cooldown_left <= 0.0:
			start_attack()

	if is_attacking:
		update_attack(delta)
	else:
		update_idle(delta)

	update_trail(delta)
	update_shake(delta)
	update_visuals(delta)


func read_sword_inputs() -> void:
	if Input.is_action_just_pressed("sword_left"):
		selected_position = SwordPosition.LEFT
	elif Input.is_action_just_pressed("sword_center"):
		selected_position = SwordPosition.CENTER
	elif Input.is_action_just_pressed("sword_right"):
		selected_position = SwordPosition.RIGHT

	if Input.is_action_just_pressed("sword_flip"):
		hilt_first = not hilt_first


func position_angle() -> float:
	match selected_position:
		SwordPosition.LEFT:
			return -PI / 2.0
		SwordPosition.RIGHT:
			return PI / 2.0
		_:
			return 0.0


func resting_radius() -> float:
	if selected_position == SwordPosition.CENTER:
		return center_orbit_radius
	return orbit_radius


func update_idle(delta: float) -> void:
	var amount := 1.0 - exp(-orbit_speed * delta)

	orbit_angle = lerp_angle(
		orbit_angle,
		player_sprite.rotation + position_angle(),
		amount
	)
	current_orbit_radius = lerpf(
		current_orbit_radius,
		resting_radius(),
		amount
	)


func striking_tip_distance() -> float:
	return hilt_tip_distance if hilt_first else blade_tip_distance


func capture_mouse_aim(max_range: float) -> void:
	var mouse_offset := player.to_local(
		player.get_global_mouse_position()
	)

	if mouse_offset.length_squared() < 1.0:
		mouse_offset = Vector2.UP.rotated(player_sprite.rotation)

	aim_direction = mouse_offset.normalized()
	aim_angle = Vector2.UP.angle_to(aim_direction)

	# This distance is measured to the striking tip.
	tip_target_distance = minf(mouse_offset.length(), max_range)

	# Put the sprite center behind that tip.
	strike_center_distance = (
		tip_target_distance - striking_tip_distance()
	)


func start_attack() -> void:
	attack_start_angle = orbit_angle
	attack_start_center = (
		Vector2.UP.rotated(orbit_angle) * current_orbit_radius
	)
	attack_angle = orbit_angle
	attack_center = attack_start_center
	attack_height = 0.0

	attack_phase = 0
	phase_time = 0.0
	is_attacking = true

	match selected_position:
		SwordPosition.LEFT:
			attack_type = AttackType.LEFT
			capture_mouse_aim(left_range)
			set_striking(true)

		SwordPosition.CENTER:
			attack_type = AttackType.CENTER
			capture_mouse_aim(thrust_range)

		SwordPosition.RIGHT:
			attack_type = AttackType.HEAVY
			capture_mouse_aim(heavy_range)
			charge = 0.0
			player.heavy_attack_locked = true


func update_attack(delta: float) -> void:
	phase_time += delta

	match attack_type:
		AttackType.LEFT:
			update_left_attack()

		AttackType.CENTER:
			update_thrust()

		AttackType.HEAVY:
			update_heavy_attack(delta)


func next_phase() -> void:
	attack_phase += 1
	phase_time = 0.0


func finish_attack() -> void:
	set_striking(false)

	orbit_angle = attack_angle
	current_orbit_radius = attack_center.length()

	is_attacking = false
	attack_type = AttackType.NONE
	player.heavy_attack_locked = false
	cooldown_left = attack_cooldown


func update_left_attack() -> void:
	var half_arc := deg_to_rad(left_arc_degrees) / 2.0

	match attack_phase:
		0:
			# First wide swipe toward the right.
			var progress := minf(
				phase_time / maxf(left_swipe_time, 0.001),
				1.0
			)

			attack_angle = lerp_angle(
				attack_start_angle,
				aim_angle + half_arc,
				progress
			)
			var radius := lerpf(
				attack_start_center.length(),
				strike_center_distance,
				progress
			)
			attack_center = Vector2.UP.rotated(attack_angle) * radius

			if progress >= 1.0:
				set_striking(false)
				next_phase()

		1:
			if phase_time >= left_gap_time:
				next_phase()
				set_striking(true)

		2:
			# Second wide swipe back toward the left.
			var progress := minf(
				phase_time / maxf(left_swipe_time, 0.001),
				1.0
			)

			attack_angle = lerp_angle(
				aim_angle + half_arc,
				aim_angle - half_arc,
				progress
			)
			attack_center = (
				Vector2.UP.rotated(attack_angle)
				* strike_center_distance
			)

			if progress >= 1.0:
				set_striking(false)
				next_phase()

		3:
			var progress := minf(
				phase_time / maxf(left_recovery_time, 0.001),
				1.0
			)

			attack_angle = lerp_angle(
				aim_angle - half_arc,
				player_sprite.rotation + position_angle(),
				progress
			)
			var radius := lerpf(
				strike_center_distance,
				resting_radius(),
				progress
			)
			attack_center = Vector2.UP.rotated(attack_angle) * radius

			if progress >= 1.0:
				finish_attack()


func update_thrust() -> void:
	var pullback_center := (
		aim_direction * (resting_radius() - thrust_pullback)
	)
	var target_center := (
		aim_direction * strike_center_distance
	)

	match attack_phase:
		0:
			# Pull back slightly before the thrust.
			var progress := minf(
				phase_time / maxf(thrust_windup_time, 0.001),
				1.0
			)

			attack_center = attack_start_center.lerp(
				pullback_center,
				progress
			)
			attack_angle = lerp_angle(
				attack_start_angle,
				aim_angle,
				progress
			)

			if progress >= 1.0:
				next_phase()
				set_striking(true)

		1:
			# Extend toward the mouse, capped at 200 px to the tip.
			var progress := minf(
				phase_time / maxf(thrust_out_time, 0.001),
				1.0
			)
			var eased := 1.0 - pow(1.0 - progress, 3.0)

			attack_center = pullback_center.lerp(
				target_center,
				eased
			)
			attack_angle = aim_angle

			if progress >= 1.0:
				set_striking(false)
				next_phase()

		2:
			var progress := minf(
				phase_time / maxf(thrust_return_time, 0.001),
				1.0
			)

			var rest_center := (
				Vector2.UP.rotated(
					player_sprite.rotation + position_angle()
				) * resting_radius()
			)

			attack_center = target_center.lerp(
				rest_center,
				progress
			)
			attack_angle = lerp_angle(
				aim_angle,
				player_sprite.rotation + position_angle(),
				progress
			)

			if progress >= 1.0:
				finish_attack()


func update_heavy_attack(delta: float) -> void:
	match attack_phase:
		0:
			# Keep following the mouse while the button is held.
			capture_mouse_aim(heavy_range)
			charge = minf(
				phase_time / maxf(max_charge_time, 0.001),
				1.0
			)

			var windback_center := (
				-aim_direction * heavy_windback
			)
			var amount := 1.0 - exp(-orbit_speed * delta)

			attack_center = attack_center.lerp(
				windback_center,
				amount
			)
			attack_angle = lerp_angle(
				attack_angle,
				aim_angle,
				amount
			)
			attack_height = lerpf(
				attack_height,
				heavy_lift,
				amount
			)

			# Full charge stays held. Only releasing starts the slam.
			if not Input.is_action_pressed("attack"):
				slam_start_center = attack_center
				next_phase()

		1:
			# Bring the raised sword down toward the target.
			var progress := minf(
				phase_time / maxf(heavy_slam_time, 0.001),
				1.0
			)
			var eased := 1.0 - pow(1.0 - progress, 3.0)

			var target_center := (
				aim_direction * strike_center_distance
			)

			attack_center = slam_start_center.lerp(
				target_center,
				eased
			)
			attack_angle = aim_angle
			attack_height = lerpf(
				heavy_lift,
				0.0,
				eased
			)

			if progress >= 1.0:
				trigger_heavy_impact()
				next_phase()

		2:
			# The player remains stopped briefly after impact.
			var progress := minf(
				phase_time / maxf(heavy_recovery_time, 0.001),
				1.0
			)

			var target_center := (
				aim_direction * strike_center_distance
			)
			var rest_center := (
				Vector2.UP.rotated(
					player_sprite.rotation + position_angle()
				) * resting_radius()
			)

			attack_center = target_center.lerp(
				rest_center,
				progress
			)
			attack_angle = lerp_angle(
				aim_angle,
				player_sprite.rotation + position_angle(),
				progress
			)

			if progress >= 1.0:
				finish_attack()


func set_striking(value: bool) -> void:
	if is_striking == value:
		return

	is_striking = value
	if value:
		damaged_this_window.clear()
	if value:
		attack_window_started.emit(hilt_first)
	else:
		attack_window_ended.emit()

func damage_heavy_impact() -> void:
	var circle := CircleShape2D.new()
	circle.radius = heavy_impact_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, pending_heavy_position)
	query.exclude = [player.get_rid()]

	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var body = result["collider"]

		if body is Enemy:
			if body.global_position.distance_to(player.global_position) <= heavy_range:
				body.take_damage(heavy_damage)
				
func trigger_heavy_impact() -> void:
	var impact_position := player.to_global(
		aim_direction * tip_target_distance
	)
	pending_heavy_position = impact_position
	pending_heavy_hit = true
	heavy_impact.emit(impact_position, charge)

	if charge < 0.999:
		return

	camera = get_viewport().get_camera_2d()

	if not is_instance_valid(camera):
		push_warning("Heavy attack cannot shake: no active Camera2D.")
		return

	camera_rest_offset = camera.offset
	shake_left = shake_time


func update_trail(delta: float) -> void:
	var distance := 0.0

	if not is_attacking:
		if player.is_dashing:
			distance = dash_trail_distance
		elif player.is_sprinting:
			distance = sprint_trail_distance

	var target := Vector2.ZERO
	var movement := player.get_real_velocity()

	if movement != Vector2.ZERO:
		target = -movement.normalized() * distance

	trail_offset = trail_offset.lerp(
		target,
		1.0 - exp(-trail_follow_speed * delta)
	)


func update_shake(delta: float) -> void:
	if shake_left > 0.0:
		shake_left = maxf(shake_left - delta, 0.0)

		var strength := (
			shake_pixels
			* (0.5 + charge * 0.5)
			* shake_left
			/ maxf(shake_time, 0.001)
		)

		shake_offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)

		if is_instance_valid(camera):
			camera.offset = camera_rest_offset + shake_offset
	else:
		shake_offset = Vector2.ZERO

		if is_instance_valid(camera) and camera.offset != camera_rest_offset:
			camera.offset = camera_rest_offset


func update_visuals(delta: float) -> void:
	var phase := elapsed_time * TAU * hover_frequency
	var hover_offset := Vector2(
		sin(phase),
		cos(phase * 0.7)
	) * hover_amount

	var center: Vector2

	if is_attacking:
		center = attack_center
	else:
		center = (
			Vector2.UP.rotated(orbit_angle)
			* current_orbit_radius
		)

	global_position = (
		player.to_global(center)
		+ hover_offset
		+ trail_offset
		+ shake_offset * 0.25
		+ Vector2.UP * attack_height
	)

	var target_rotation: float

	if is_attacking:
		# Point the striking end outward during attacks.
		target_rotation = player.global_rotation + attack_angle
	else:
		target_rotation = player_sprite.global_rotation

	target_rotation += resting_rotation

	if hilt_first:
		target_rotation += PI

	global_rotation = lerp_angle(
		global_rotation,
		target_rotation,
		1.0 - exp(-blade_rotation_speed * delta)
	)
