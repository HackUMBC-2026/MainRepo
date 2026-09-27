extends Enemy

enum State { WANDER, CHASE }

@export_group("Detection")
@export var auto_find_player: bool = true
@export var vision_range: float = 220.0
@export_range(1.0, 360.0, 1.0) var vision_angle_degrees: float = 110.0
@export_flags_2d_physics var sight_collision_mask: int = 1
@export var initial_facing: Vector2 = Vector2.DOWN
@export var turn_speed: float = 8.0
@export var show_vision_cone: bool = false

@export_group("Wandering")
@export var wander_speed: float = 40.0
@export var wander_radius: float = 100.0
@export var wander_walk_seconds: float = 2.5
@export var wander_pause_seconds: float = 0.7

@onready var facing_indicator: Node2D = $FacingIndicator

var state: State = State.WANDER
var facing: Vector2 = Vector2.DOWN
var last_known_position: Vector2
var wander_home: Vector2
var wander_destination: Vector2
var wander_time_left: float = 0.0
var wander_pause_left: float = 0.0
var target_retry_left: float = 0.0
var random := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	random.randomize()
	facing = initial_facing.normalized() if not initial_facing.is_zero_approx() else Vector2.DOWN
	wander_home = global_position
	wander_destination = global_position
	wander_pause_left = random.randf_range(0.1, maxf(wander_pause_seconds, 0.1))
	find_player()
	update_appearance()


func find_player() -> void:
	if auto_find_player and not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if health <= 0.0:
		return
	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	target_retry_left -= delta
	if target_retry_left <= 0.0:
		find_player()
		target_retry_left = 1.0
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	if update_melee_attack(delta):
		update_appearance()
		return

	if state == State.WANDER and can_see_player():
		state = State.CHASE
	if state != State.WANDER and (not is_instance_valid(target) or target.health <= 0.0):
		resume_wandering()

	match state:
		State.WANDER:
			update_wandering(delta)
		State.CHASE:
			# Once alerted, track the living player even outside the original vision cone.
			last_known_position = target.global_position
			move_toward_point(last_known_position, move_speed, stop_distance, delta)
			# The sweep itself still checks attack range and wall obstruction.
			try_start_melee_attack()
	update_appearance()


func can_see_player() -> bool:
	if not is_instance_valid(target) or target.health <= 0.0:
		return false
	var offset := target.global_position - global_position
	if offset.length_squared() > vision_range * vision_range:
		return false
	if not offset.is_zero_approx():
		var cone_edge := cos(deg_to_rad(vision_angle_degrees) * 0.5)
		if facing.dot(offset.normalized()) < cone_edge:
			return false
	var query := PhysicsRayQueryParameters2D.create(
		global_position, target.global_position, sight_collision_mask, [get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target


func update_wandering(delta: float) -> void:
	if wander_pause_left > 0.0:
		wander_pause_left = maxf(wander_pause_left - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		if wander_pause_left <= 0.0:
			choose_wander_destination()
		return

	wander_time_left = maxf(wander_time_left - delta, 0.0)
	if wander_time_left <= 0.0 or global_position.distance_to(wander_destination) <= 6.0:
		wander_pause_left = random.randf_range(
			maxf(wander_pause_seconds * 0.5, 0.1), maxf(wander_pause_seconds * 1.5, 0.1)
		)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	move_toward_point(wander_destination, wander_speed, 5.0, delta)


func choose_wander_destination() -> void:
	for attempt in range(12):
		var offset := Vector2.from_angle(random.randf_range(0.0, TAU))
		offset *= random.randf_range(0.2, 1.0) * maxf(wander_radius, 0.0)
		var candidate := wander_home + offset
		if not test_move(global_transform, candidate - global_position):
			wander_destination = candidate
			wander_time_left = maxf(wander_walk_seconds, 0.1) * random.randf_range(0.7, 1.3)
			return
	# In a tight corner, pause before trying another reachable destination.
	wander_destination = global_position
	wander_time_left = 0.0


func move_toward_point(destination: Vector2, speed: float, arrival_distance: float, delta: float) -> void:
	var offset := destination - global_position
	if offset.length() <= arrival_distance:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var desired := offset.normalized()
	var steering := Vector2.ZERO
	# Local body-sized probes steer around nearby obstacles without requiring a navigation map.
	for angle in [0.0, PI / 6.0, -PI / 6.0, PI / 3.0, -PI / 3.0, PI / 2.0, -PI / 2.0]:
		var candidate := desired.rotated(angle)
		if not test_move(global_transform, candidate * maxf(speed * delta, 12.0)):
			steering = candidate
			break
	var look_direction := steering if not steering.is_zero_approx() else desired
	facing = Vector2.from_angle(lerp_angle(facing.angle(), look_direction.angle(), 1.0 - exp(-turn_speed * delta)))
	velocity = steering * minf(speed, maxf(offset.length() - arrival_distance, 0.0) / maxf(delta, 0.001))
	move_and_slide()


func resume_wandering() -> void:
	state = State.WANDER
	wander_home = global_position
	wander_destination = global_position
	wander_pause_left = maxf(wander_pause_seconds, 0.1)
	velocity = Vector2.ZERO


func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if health <= 0.0 or amount <= 0.0:
		return
	find_player()
	if is_instance_valid(target) and target.health > 0.0:
		last_known_position = target.global_position
		facing = global_position.direction_to(last_known_position)
		if facing.is_zero_approx():
			facing = Vector2.DOWN
		state = State.CHASE
		update_appearance()


func update_appearance() -> void:
	facing_indicator.global_rotation = facing.angle()
	queue_redraw()


func _draw() -> void:
	if not show_vision_cone:
		return
	var half_angle := deg_to_rad(vision_angle_degrees) * 0.5
	var look_angle := facing.angle() - global_rotation
	var start := look_angle - half_angle
	var end := look_angle + half_angle
	var color := Color(1.0, 0.75, 0.2, 0.25)
	draw_arc(Vector2.ZERO, vision_range, start, end, 32, color)
	draw_line(Vector2.ZERO, Vector2.from_angle(start) * vision_range, color)
	draw_line(Vector2.ZERO, Vector2.from_angle(end) * vision_range, color)
