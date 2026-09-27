extends Node2D

const FLAME_EXPLOSION = preload("res://player/flame_explosion.gd")

signal attack_window_started(hilt_first: bool)
signal attack_window_ended
signal heavy_impact(world_position: Vector2, charge: float)

enum SwordPosition { LEFT, CENTER, RIGHT }
enum AttackType { NONE, LEFT, CENTER, HEAVY }
enum LeftAttackPhase { WINDUP, FIRST_SWIPE, GAP, SECOND_SWIPE, RECOVERY }

@export var player_sprite: Sprite2D
@export var camera: Camera2D

@export_group("Floating")
@export var orbit_speed: float = 10.0
@export var blade_rotation_speed: float = 8.0
@export var hover_amount: float = 2.0
@export var hover_frequency: float = 0.8
@export var sprint_trail_distance: float = 7.0
@export var dash_trail_distance: float = 18.0
@export var trail_follow_speed: float = 14.0

@export_group("Side View")
@export var side_layer_switch_x: float = 8.0

@export_group("Left: Double Swipe")
@export var left_range: float = 100.0
@export var left_arc_degrees: float = 160.0
@export var left_windup_time: float = 0.06
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
@export var charged_damage_multiplier: float = 2.0
@export var charged_radius_multiplier: float = 1.75
@export var charged_stun_seconds: float = 0.5

@export_group("Parry")
@export var parry_window_seconds: float = 0.25
@export var parry_stun_seconds: float = 1.0
@export var block_distance: float = 28.0
@export var late_block_damage_multiplier: float = 0.5
@export_range(0.0, 360.0, 1.0) var block_arc_degrees: float = 120.0

@onready var anchor: Node2D = get_parent() as Node2D
@onready var player: Player = anchor.get_parent() as Player
@onready var positions_root: Node2D = player.get_node("SwordPositions") as Node2D
@onready var blade_hitbox: Area2D = $BladeHitbox
@onready var hilt_hitbox: Area2D = $HiltHitbox
@onready var blade_shape: CollisionShape2D = $BladeHitbox/CollisionShape2D
@onready var hilt_shape: CollisionShape2D = $HiltHitbox/CollisionShape2D
@onready var blade_tip: Marker2D = $BladeTip
@onready var hilt_tip: Marker2D = $HiltTip
@onready var visual: Sprite2D = $Visual
@onready var hilt_fire: SwordHiltFire = $Visual/HiltFire
@onready var charge_indicator: ProgressBar = player.get_node("HeavyCharge")

var damaged_this_window: Dictionary = {}
var pending_heavy_hit: bool = false
var pending_heavy_position: Vector2 = Vector2.ZERO
var pending_heavy_charge: float = 0.0
var previous_strike_transform: Transform2D
var has_previous_strike: bool = false

var selected_position := SwordPosition.RIGHT
var via_middle_key: bool = false
var transition_active: bool = false
var segment_start_position: int = SwordPosition.RIGHT
var waypoint_facing: Vector2 = Vector2.ZERO
var is_blocking: bool = false
var parry_window_left: float = 0.0
var hilt_first: bool = false
var is_attacking: bool = false
var is_striking: bool = false

var elapsed_time: float = 0.0
var orbit_angle: float = 0.0
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
var shake_active: bool = false

func _ready() -> void:
	if not is_instance_valid(player_sprite):
		push_error("Assign the player's Sprite2D to Player Sprite.")
		set_process(false)
		set_physics_process(false)
		return

	orbit_angle = resting_angle()
	current_orbit_radius = resting_radius()
	resting_rotation = rotation

	if is_instance_valid(camera):
		camera_rest_offset = camera.offset

	player.died.connect(on_player_died)
	update_combat_pose()


func _process(delta: float) -> void:
	elapsed_time += delta
	update_trail(delta)
	update_shake(delta)
	update_visuals(delta)
	charge_indicator.visible = is_attacking and attack_type == AttackType.HEAVY
	charge_indicator.value = charge
	charge_indicator.modulate = Color(1.0, 0.85, 0.3) if charge >= 0.999 else Color.WHITE


func _physics_process(delta: float) -> void:
	if player.health <= 0.0:
		on_player_died()
		return

	cooldown_left = maxf(cooldown_left - delta, 0.0)
	update_parry(delta)

	if not is_attacking and not is_blocking:
		read_sword_inputs()

		if Input.is_action_just_pressed("attack") and cooldown_left <= 0.0:
			start_attack()

	# Short steps follow curved swipes even when the physics rate is low.
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	for step in range(steps):
		advance_combat(delta / steps)


func advance_combat(delta: float) -> void:
	var was_striking := is_striking
	var damage := thrust_damage if attack_type == AttackType.CENTER else swipe_damage
	var hit_shape := hilt_shape if hilt_first else blade_shape
	var start_transform := (
		previous_strike_transform if has_previous_strike else hit_shape.global_transform
	)
	if is_attacking:
		update_attack(delta)
	elif is_blocking:
		update_block(delta)
	else:
		update_idle(delta)
	update_combat_pose()

	# Include the final pose before closing a window, but never sweep the windup.
	if was_striking or is_striking:
		if not was_striking:
			start_transform = hit_shape.global_transform
		damage_sweep(hit_shape, start_transform, hit_shape.global_transform, damage)
	previous_strike_transform = hit_shape.global_transform
	has_previous_strike = is_striking
	if pending_heavy_hit:
		pending_heavy_hit = false
		damage_heavy_impact()


func damage_sweep(
	hit_shape: CollisionShape2D, from: Transform2D, to: Transform2D, damage: float
) -> void:
	var rectangle := hit_shape.shape as RectangleShape2D
	var half_size := rectangle.size * 0.5
	var corners := PackedVector2Array([
		Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)
	])
	var turn := absf(angle_difference(from.get_rotation(), to.get_rotation()))
	var segments := maxi(1, ceili(turn / deg_to_rad(5.0)))
	var previous := from
	for segment in range(1, segments + 1):
		var current := from.interpolate_with(to, float(segment) / segments)
		var points := PackedVector2Array()
		for corner in corners:
			points.append(previous * corner)
			points.append(current * corner)
		var hull := Geometry2D.convex_hull(points)
		hull.remove_at(hull.size() - 1) # convex_hull repeats the first point.
		var swept_shape := ConvexPolygonShape2D.new()
		swept_shape.points = hull
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = swept_shape
		query.collision_mask = (hit_shape.get_parent() as Area2D).collision_mask
		damage_query(query, damage, damaged_this_window)
		previous = current


func damage_query(
	query: PhysicsShapeQueryParameters2D, damage: float, damaged: Dictionary,
	stun_seconds: float = 0.0
) -> void:
	var excluded: Array[RID] = [player.get_rid()]
	# Paginate so walls or a crowd cannot consume the result limit.
	while true:
		query.exclude = excluded
		var results := get_world_2d().direct_space_state.intersect_shape(query, 32)
		for result in results:
			excluded.append(result["rid"])
			var body = result["collider"]
			if body is Enemy and not body.is_queued_for_deletion() and not damaged.has(body):
				damaged[body] = true
				body.take_damage(damage * player.specials.sword_damage_multiplier())
				if stun_seconds > 0.0 and body.health > 0.0:
					body.stun(stun_seconds)
		if results.size() < 32:
			break


func update_parry(delta: float) -> void:
	if is_blocking:
		if not Input.is_action_pressed("parry"):
			is_blocking = false
			parry_window_left = 0.0
		else:
			parry_window_left = maxf(parry_window_left - delta, 0.0)

	elif not is_attacking and Input.is_action_just_pressed("parry"):
		is_blocking = true
		parry_window_left = parry_window_seconds


func defend_against_attack(attacker: Node, parryable: bool) -> float:
	if player.health <= 0.0 or not is_blocking or not parryable:
		return 1.0
	if not is_instance_valid(attacker) or not attacker is Node2D:
		return 1.0
	var toward_attacker := (attacker as Node2D).global_position - player.global_position
	var guard_direction := Vector2.UP.rotated(player.global_rotation + orbit_angle)
	if (
		toward_attacker.length_squared() > 0.001
		and guard_direction.dot(toward_attacker.normalized())
		< cos(deg_to_rad(block_arc_degrees) * 0.5) - 0.00001
	):
		return 1.0

	if parry_window_left > 0.0:
		parry_window_left = 0.0
		if is_instance_valid(attacker) and attacker.has_method("stun"):
			attacker.stun(parry_stun_seconds)
		spawn_block_particles(true)
		return 0.0

	spawn_block_particles(false)
	return late_block_damage_multiplier


func spawn_block_particles(perfect: bool) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.z_index = 10
	particles.amount = 14 if perfect else 9
	particles.lifetime = 0.18 if perfect else 0.30
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 50.0 if perfect else 12.0
	particles.initial_velocity_max = 100.0 if perfect else 35.0
	particles.scale_amount_min = 2.0 if perfect else 3.0
	particles.scale_amount_max = 3.0 if perfect else 5.0
	particles.color = (
		Color(1.0, 0.88, 0.4)
		if perfect
		else Color(0.65, 0.65, 0.65, 0.75)
	)
	particles.emitting = false

	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func update_block(delta: float) -> void:
	var mouse_offset := player.to_local(
		player.get_global_mouse_position()
	)

	if mouse_offset.length_squared() < 1.0:
		mouse_offset = Vector2.UP.rotated(player.facing_angle())

	var mouse_angle := Vector2.UP.angle_to(mouse_offset)
	var amount := 1.0 - exp(-orbit_speed * delta)

	orbit_angle = lerp_angle(orbit_angle, mouse_angle, amount)
	current_orbit_radius = lerpf(
		current_orbit_radius,
		block_distance,
		amount
	)


func read_sword_inputs() -> void:
	var old_position := selected_position
	var next_position := selected_position

	if Input.is_action_just_pressed("sword_left"):
		next_position = SwordPosition.LEFT
	elif Input.is_action_just_pressed("sword_center"):
		next_position = SwordPosition.CENTER
	elif Input.is_action_just_pressed("sword_right"):
		next_position = SwordPosition.RIGHT

	if next_position != selected_position:
		selected_position = next_position
		via_middle_key = (
			(old_position == SwordPosition.LEFT and next_position == SwordPosition.RIGHT)
			or (old_position == SwordPosition.RIGHT and next_position == SwordPosition.LEFT)
		)
		transition_active = true
		segment_start_position = old_position
		waypoint_facing = player.facing_direction()

	if Input.is_action_just_pressed("sword_flip"):
		hilt_first = not hilt_first


func is_side_facing() -> bool:
	return player.facing_direction().x != 0.0


func slot_for_position(key_position: int) -> int:
	if player.facing_direction() == Vector2.LEFT:
		if key_position == SwordPosition.LEFT:
			return SwordPosition.CENTER
		if key_position == SwordPosition.CENTER:
			return SwordPosition.LEFT
	return key_position


func resting_slot() -> int:
	return slot_for_position(selected_position)


func target_key_position() -> int:
	return SwordPosition.CENTER if via_middle_key else selected_position


func marker_for_slot(slot: int) -> Marker2D:
	var facing_name: String
	var facing := player.facing_direction()
	if facing == Vector2.UP:
		facing_name = "Up"
	elif facing == Vector2.DOWN:
		facing_name = "Down"
	elif facing == Vector2.LEFT:
		facing_name = "Left"
	else:
		facing_name = "Right"

	var slot_name: String
	match slot:
		SwordPosition.LEFT:
			slot_name = "Left"
		SwordPosition.RIGHT:
			slot_name = "Right"
		_:
			slot_name = "Center"

	return positions_root.get_node(NodePath("%s/%s" % [facing_name, slot_name])) as Marker2D


func marker_position(slot: int) -> Vector2:
	return player.to_local(marker_for_slot(slot).global_position)


func resting_center() -> Vector2:
	return marker_position(resting_slot())


func resting_angle() -> float:
	var center := resting_center()
	if center.length_squared() < 0.01:
		return orbit_angle
	return fposmod(Vector2.UP.angle_to(center), TAU)


func resting_radius() -> float:
	return resting_center().length()


func update_idle(delta: float) -> void:
	if transition_active and player.facing_direction() != waypoint_facing:
		via_middle_key = false
		transition_active = false

	var target_position := target_key_position()
	var target_center := marker_position(slot_for_position(target_position))
	var target_angle := fposmod(Vector2.UP.angle_to(target_center), TAU)
	var amount := 1.0 - exp(-orbit_speed * delta)
	var current_angle := fposmod(orbit_angle, TAU)

	# Use the upper arc where the screen positions and key order differ.
	var facing := player.facing_direction()
	var upper_arc_forward := transition_active and (
		(facing == Vector2.LEFT and segment_start_position == SwordPosition.CENTER and target_position == SwordPosition.RIGHT)
		or (facing == Vector2.RIGHT and segment_start_position == SwordPosition.LEFT and target_position == SwordPosition.CENTER)
	)
	var upper_arc_reverse := transition_active and (
		(facing == Vector2.LEFT and segment_start_position == SwordPosition.RIGHT and target_position == SwordPosition.CENTER)
		or (facing == Vector2.RIGHT and segment_start_position == SwordPosition.CENTER and target_position == SwordPosition.LEFT)
	)

	if upper_arc_forward:
		if current_angle < PI:
			current_angle += TAU
		orbit_angle = lerpf(current_angle, target_angle + TAU, amount)
	elif upper_arc_reverse:
		if current_angle > PI:
			current_angle -= TAU
		orbit_angle = lerpf(current_angle, target_angle - TAU, amount)
	elif is_side_facing() and current_angle >= PI / 2.0 and current_angle <= 3.0 * PI / 2.0:
		orbit_angle = lerpf(current_angle, target_angle, amount)
	else:
		orbit_angle = lerp_angle(orbit_angle, target_angle, amount)

	current_orbit_radius = lerpf(
		current_orbit_radius,
		target_center.length(),
		amount
	)

	if transition_active:
		var current_center := Vector2.UP.rotated(orbit_angle) * current_orbit_radius
		if current_center.distance_to(target_center) <= 3.0:
			if via_middle_key:
				via_middle_key = false
				segment_start_position = SwordPosition.CENTER
			else:
				transition_active = false


func striking_tip_distance() -> float:
	return absf(striking_tip().position.y)


func striking_tip() -> Marker2D:
	return hilt_tip if hilt_first else blade_tip


func capture_mouse_aim(max_range: float) -> void:
	var mouse_offset := player.to_local(
		player.get_global_mouse_position()
	)

	if mouse_offset.length_squared() < 1.0:
		mouse_offset = Vector2.UP.rotated(player.facing_angle())

	aim_direction = mouse_offset.normalized()
	aim_angle = Vector2.UP.angle_to(aim_direction)

	# This distance is measured to the striking tip.
	tip_target_distance = minf(mouse_offset.length(), max_range)

	# Put the sprite center behind that tip.
	strike_center_distance = (
		tip_target_distance - striking_tip_distance()
	)


func start_attack() -> void:
	if player.health <= 0.0 or is_attacking or is_blocking:
		return
	via_middle_key = false
	transition_active = false
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
	has_previous_strike = false

	match selected_position:
		SwordPosition.LEFT:
			attack_type = AttackType.LEFT
			capture_mouse_aim(left_range)
			attack_phase = LeftAttackPhase.WINDUP

		SwordPosition.CENTER:
			attack_type = AttackType.CENTER
			capture_mouse_aim(thrust_range)

		SwordPosition.RIGHT:
			attack_type = AttackType.HEAVY
			capture_mouse_aim(heavy_range)
			charge = 0.0
			player.heavy_attack_locked = true
	update_combat_pose()


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


func cancel_combat() -> void:
	hilt_fire.end_power_release()
	set_striking(false)
	is_attacking = false
	is_blocking = false
	attack_type = AttackType.NONE
	attack_phase = 0
	phase_time = 0.0
	parry_window_left = 0.0
	pending_heavy_hit = false
	pending_heavy_position = Vector2.ZERO
	pending_heavy_charge = 0.0
	has_previous_strike = false
	damaged_this_window.clear()
	player.heavy_attack_locked = false
	charge = 0.0
	attack_height = 0.0
	charge_indicator.hide()
	stop_camera_shake()


func on_player_died() -> void:
	cancel_combat()
	hilt_fire.extinguish()
	set_process(false)
	set_physics_process(false)


func update_left_attack() -> void:
	var half_arc := deg_to_rad(left_arc_degrees) / 2.0
	var swipe_start_angle := aim_angle - half_arc
	var swipe_end_angle := aim_angle + half_arc

	match attack_phase:
		LeftAttackPhase.WINDUP:
			# Reach the same starting edge from every resting slot without dealing damage.
			var progress := minf(
				phase_time / maxf(left_windup_time, 0.001),
				1.0
			)
			attack_angle = lerp_angle(
				attack_start_angle, swipe_start_angle, progress
			)
			attack_center = attack_start_center.lerp(
				Vector2.UP.rotated(swipe_start_angle) * strike_center_distance, progress
			)
			if progress >= 1.0:
				next_phase()
				set_striking(true)

		LeftAttackPhase.FIRST_SWIPE:
			var progress := minf(
				phase_time / maxf(left_swipe_time, 0.001),
				1.0
			)
			# Explicit endpoints keep the first swipe crossing the aim direction.
			attack_angle = lerpf(swipe_start_angle, swipe_end_angle, progress)
			attack_center = Vector2.UP.rotated(attack_angle) * strike_center_distance

			if progress >= 1.0:
				set_striking(false)
				next_phase()

		LeftAttackPhase.GAP:
			if phase_time >= left_gap_time:
				next_phase()
				set_striking(true)

		LeftAttackPhase.SECOND_SWIPE:
			# Second wide swipe back toward the left.
			var progress := minf(
				phase_time / maxf(left_swipe_time, 0.001),
				1.0
			)

			attack_angle = lerpf(swipe_end_angle, swipe_start_angle, progress)
			attack_center = (
				Vector2.UP.rotated(attack_angle)
				* strike_center_distance
			)

			if progress >= 1.0:
				set_striking(false)
				next_phase()

		LeftAttackPhase.RECOVERY:
			var progress := minf(
				phase_time / maxf(left_recovery_time, 0.001),
				1.0
			)

			attack_angle = lerp_angle(
				swipe_start_angle,
				resting_angle(),
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
					resting_angle()
				) * resting_radius()
			)

			attack_center = target_center.lerp(
				rest_center,
				progress
			)
			attack_angle = lerp_angle(
				aim_angle,
				resting_angle(),
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
				if charge >= 0.999:
					hilt_fire.begin_power_release(aim_direction.rotated(player.global_rotation))
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
					resting_angle()
				) * resting_radius()
			)

			attack_center = target_center.lerp(
				rest_center,
				progress
			)
			attack_angle = lerp_angle(
				aim_angle,
				resting_angle(),
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
	circle.radius = heavy_impact_radius * lerpf(1.0, charged_radius_multiplier, pending_heavy_charge)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, pending_heavy_position)
	query.collision_mask = blade_hitbox.collision_mask
	var damage := heavy_damage * lerpf(1.0, charged_damage_multiplier, pending_heavy_charge)
	var stun_seconds := charged_stun_seconds if pending_heavy_charge >= 0.999 else 0.0
	damage_query(query, damage, {}, stun_seconds)


func trigger_heavy_impact() -> void:
	hilt_fire.end_power_release()
	var impact_position := player.to_global(
		aim_direction * tip_target_distance
	)
	pending_heavy_position = impact_position
	pending_heavy_charge = charge
	pending_heavy_hit = true
	heavy_impact.emit(impact_position, charge)

	if charge < 0.999:
		return

	var explosion := FLAME_EXPLOSION.new()
	explosion.burst_radius = heavy_impact_radius * charged_radius_multiplier * 1.4
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = impact_position

	start_camera_shake()


func start_camera_shake() -> void:
	camera = get_viewport().get_camera_2d()

	if not is_instance_valid(camera):
		return

	if not shake_active:
		camera_rest_offset = camera.offset
	shake_active = true
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
		stop_camera_shake()


func stop_camera_shake() -> void:
	if shake_active and is_instance_valid(camera):
		camera.offset = camera_rest_offset
	shake_active = false
	shake_left = 0.0
	shake_offset = Vector2.ZERO


func update_draw_order(center: Vector2) -> void:
	var behind_player := false
	if not is_attacking and not is_blocking:
		var facing := player.facing_direction()
		if facing == Vector2.LEFT:
			var upper_arc_transition := transition_active and (
				(segment_start_position == SwordPosition.CENTER and target_key_position() == SwordPosition.RIGHT)
				or (segment_start_position == SwordPosition.RIGHT and target_key_position() == SwordPosition.CENTER)
			)
			behind_player = upper_arc_transition or center.x > side_layer_switch_x
		elif facing == Vector2.RIGHT:
			behind_player = center.x < 0.0
		elif facing == Vector2.UP and selected_position == SwordPosition.CENTER:
			behind_player = true

	z_index = player_sprite.z_index - anchor.z_index + (-1 if behind_player else 1)


func update_combat_pose() -> void:
	var center: Vector2

	if is_attacking:
		center = attack_center
	else:
		center = (
			Vector2.UP.rotated(orbit_angle)
			* current_orbit_radius
		)

	update_draw_order(center)

	var target_rotation: float

	if is_attacking:
		target_rotation = player.global_rotation + attack_angle
	elif is_blocking:
		# The blade lies sideways across the mouse direction.
		target_rotation = player.global_rotation + orbit_angle + PI / 2.0
	else:
		target_rotation = (player.global_rotation + player.facing_angle())

	target_rotation += resting_rotation

	if hilt_first:
		target_rotation += PI

	# Correct the small sideways offset of each tip as well as its reach.
	if is_attacking:
		center -= Vector2(striking_tip().position.x, 0.0).rotated(
			target_rotation - player.global_rotation
		)
	global_position = player.to_global(center)
	global_rotation = target_rotation


func update_visuals(delta: float) -> void:
	if is_attacking or is_blocking:
		# During combat the visible blade follows the collision pose exactly.
		visual.global_position = global_position + Vector2.UP * attack_height
		visual.rotation = 0.0
	else:
		var phase := elapsed_time * TAU * hover_frequency
		var hover_offset := Vector2(sin(phase), cos(phase * 0.7)) * hover_amount
		visual.global_position = global_position + hover_offset + trail_offset + shake_offset * 0.25
		visual.global_rotation = lerp_angle(
			visual.global_rotation, global_rotation, 1.0 - exp(-blade_rotation_speed * delta)
		)
