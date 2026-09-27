extends Node2D

## Shared by basic and wandering enemies. The owning enemy advances this on physics ticks.
@onready var enemy: Enemy = get_parent() as Enemy

var active: bool = false
var age: float = 0.0
var start_angle: float = 0.0
var hit_registered: bool = false
var sword: Sprite2D


func _ready() -> void:
	sword = Sprite2D.new()
	sword.name = "SwordVisual"
	sword.centered = false
	add_child(sword)
	hide()


func try_start() -> void:
	if active or enemy.health <= 0.0 or not valid_target():
		return
	var reach := enemy.sweep_radius + player_radius()
	if global_position.distance_to(enemy.target.global_position) > reach or not clear_line():
		return
	var direction := global_position.direction_to(enemy.target.global_position)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	start_angle = direction.angle() - deg_to_rad(enemy.sweep_angle_degrees) * 0.5
	age = 0.0
	hit_registered = false
	active = true
	enemy.velocity = Vector2.ZERO
	show()
	update_sword()
	queue_redraw()


func valid_target() -> bool:
	return is_instance_valid(enemy.target) and enemy.target.health > 0.0


func advance(delta: float) -> void:
	if not active:
		return
	if not valid_target() or enemy.health <= 0.0 or enemy.stun_left > 0.0:
		cancel()
		return
	var previous_age := age
	age += delta
	var windup := maxf(enemy.sweep_windup_seconds, 0.05)
	var duration := maxf(enemy.sweep_seconds, 0.05)
	if previous_age < windup and age >= windup:
		SoundEffects.play_at("swing", global_position)
	if age >= windup and previous_age <= windup + duration and not hit_registered:
		var previous_progress := clampf((previous_age - windup) / duration, 0.0, 1.0)
		var progress := clampf((age - windup) / duration, 0.0, 1.0)
		var arc := deg_to_rad(enemy.sweep_angle_degrees)
		if intersects_player(start_angle + arc * previous_progress, start_angle + arc * progress) and clear_line():
			hit_registered = true
			enemy.target.receive_attack(enemy.contact_damage, enemy, enemy.contact_attack_parryable)
			# A perfect parry calls Enemy.stun(), which cancels this sweep immediately.
			if not active:
				return
	if age >= windup + duration + maxf(enemy.sweep_recovery_seconds, 0.0):
		cancel()
		return
	update_sword()
	queue_redraw()


func cancel() -> void:
	if active:
		enemy.attack_cooldown_left = maxf(enemy.attack_cooldown_left, enemy.attack_interval)
	active = false
	hide()
	queue_redraw()


func player_radius() -> float:
	var collision := enemy.target.get_node("CollisionShape2D") as CollisionShape2D
	var circle := collision.shape as CircleShape2D
	return circle.radius * maxf(collision.global_transform.x.length(), collision.global_transform.y.length())


func clear_line() -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		global_position, enemy.target.global_position, enemy.melee_obstruction_mask, [enemy.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == enemy.target


func current_angle() -> float:
	var progress := clampf(
		(age - maxf(enemy.sweep_windup_seconds, 0.05)) / maxf(enemy.sweep_seconds, 0.05), 0.0, 1.0
	)
	return start_angle + deg_to_rad(enemy.sweep_angle_degrees) * progress - global_rotation


func sweep_polygon(from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(1, ceili(absf(to - from) / deg_to_rad(8.0)))
	for index in range(steps + 1):
		var angle := lerpf(from, to, float(index) / steps) - global_rotation
		points.append(Vector2.from_angle(angle) * enemy.sweep_radius)
	for index in range(steps, -1, -1):
		var angle := lerpf(from, to, float(index) / steps) - global_rotation
		points.append(Vector2.from_angle(angle) * enemy.sweep_inner_radius)
	return points


func intersects_player(from: float, to: float) -> bool:
	var collision := enemy.target.get_node("CollisionShape2D") as CollisionShape2D
	var center := to_local(collision.global_position)
	var body_radius := player_radius() / maxf(
		minf(global_transform.x.length(), global_transform.y.length()), 0.001
	)
	var polygon := sweep_polygon(from, to)
	if absf(to - from) > 0.0001 and Geometry2D.is_point_in_polygon(center, polygon):
		return true
	# Include the path between ticks so a fast sweep cannot skip a player's body.
	for index in range(polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(
			center, polygon[index], polygon[(index + 1) % polygon.size()]
		)
		if nearest.distance_squared_to(center) <= body_radius * body_radius:
			return true
	return false


func update_sword() -> void:
	sword.texture = enemy.sword_texture
	sword.visible = sword.texture != null
	if not sword.visible:
		return
	var texture_size := sword.texture.get_size()
	sword.scale = Vector2.ONE * maxf(enemy.sword_display_height, 1.0) / maxf(texture_size.y, 1.0)
	sword.offset = -texture_size * enemy.sword_texture_pivot
	sword.position = Vector2.from_angle(current_angle()) * enemy.sweep_inner_radius
	sword.rotation = current_angle() + PI * 0.5 + deg_to_rad(enemy.sword_rotation_degrees)


func _draw() -> void:
	if not active:
		return
	var windup := maxf(enemy.sweep_windup_seconds, 0.05)
	var duration := maxf(enemy.sweep_seconds, 0.05)
	var arc := deg_to_rad(enemy.sweep_angle_degrees)
	var first := start_angle - global_rotation
	var angle := current_angle()
	var direction := Vector2.from_angle(angle)

	if age < windup:
		# Show the reach and start of the swing, then flash just before it becomes dangerous.
		var progress := age / windup
		var flash := age >= windup - 0.08
		draw_arc(Vector2.ZERO, enemy.sweep_radius, first, first + arc, 40, Color(1.0, 0.65, 0.2, 0.2), 1.0)
		draw_arc(Vector2.ZERO, enemy.sweep_inner_radius, first, first + arc * progress, 32, Color(1.0, 0.7, 0.2, 0.7), 2.0)
		var cue := Color(1.0, 0.98, 0.65) if flash else Color(1.0, 0.65, 0.15)
		draw_circle(direction * enemy.sweep_radius, 4.0 if flash else 2.0, cue)
		draw_line(direction * enemy.sweep_inner_radius, direction * enemy.sweep_radius, cue, 2.0)
		return

	var recovery := maxf(age - windup - duration, 0.0)
	var alpha := 1.0 - clampf(recovery / maxf(enemy.sweep_recovery_seconds, 0.001), 0.0, 1.0)
	var tail := maxf(first, angle - deg_to_rad(40.0))
	if angle - tail > 0.001:
		draw_colored_polygon(
			sweep_polygon(tail + global_rotation, angle + global_rotation), Color(1.0, 0.55, 0.12, alpha * 0.3)
		)
		draw_arc(Vector2.ZERO, enemy.sweep_radius, tail, angle, 16, Color(1.0, 0.8, 0.35, alpha), 3.0)
	draw_line(direction * enemy.sweep_inner_radius, direction * enemy.sweep_radius, Color(1.0, 0.96, 0.7, alpha), 2.0)
