extends Node2D
class_name BossTelegraph

enum Shape { CIRCLE, CONE }

var shape: Shape = Shape.CIRCLE
var radius: float = 80.0
var cone_angle: float = 100.0
var warning_seconds: float = 1.1
var damage: float = 20.0
var parryable: bool = false
var attacker: Enemy
var target: Player
var obstruction_mask: int = 1
var age: float = 0.0
var detonated: bool = false
var impact_age: float = 0.0
var impact_lifetime: float = 0.3


func _ready() -> void:
	# Above the floor (-10), below characters and walls (0).
	z_index = -2


func _physics_process(delta: float) -> void:
	if (
		not is_instance_valid(attacker) or attacker.health <= 0.0
		or not is_instance_valid(target) or target.health <= 0.0
	):
		queue_free()
		return
	if detonated:
		impact_age += delta
		if impact_age >= impact_lifetime:
			queue_free()
	else:
		age += delta
		if age >= maxf(warning_seconds, 0.05):
			detonated = true
			if contains_player() and clear_line_to_player():
				apply_hit()
	update_visuals()


func apply_hit() -> void:
	# Selected directed attacks use the sword's normal guard/parry handling.
	target.receive_attack(damage, attacker, parryable)


func update_visuals() -> void:
	queue_redraw()


func clear_line_to_player() -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		global_position, target.global_position, obstruction_mask, [attacker.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target


func contains_player() -> bool:
	var body_shape := target.get_node("CollisionShape2D") as CollisionShape2D
	var circle := body_shape.shape as CircleShape2D
	var body_radius := circle.radius * maxf(
		body_shape.global_transform.x.length(), body_shape.global_transform.y.length()
	)
	var center := to_local(body_shape.global_position)
	if shape == Shape.CIRCLE:
		return center.length() <= radius + body_radius

	# Check the same sector polygon used for the warning, including the player's body edges.
	var polygon := sector_points(radius)
	if Geometry2D.is_point_in_polygon(center, polygon):
		return true
	for index in range(polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(
			center, polygon[index], polygon[(index + 1) % polygon.size()]
		)
		if nearest.distance_squared_to(center) <= body_radius * body_radius:
			return true
	return false


func sector_points(size: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	var half_angle := deg_to_rad(cone_angle) * 0.5
	for index in range(33):
		var angle := lerpf(-half_angle, half_angle, float(index) / 32.0)
		points.append(Vector2.RIGHT.rotated(angle) * size)
	return points


func draw_area(size: float, color: Color) -> void:
	if size <= 0.01:
		return
	if shape == Shape.CIRCLE:
		draw_circle(Vector2.ZERO, size, color)
	else:
		draw_colored_polygon(sector_points(size), color)


func draw_border(color: Color, width: float) -> void:
	if shape == Shape.CIRCLE:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, width)
	else:
		var points := sector_points(radius)
		points.append(Vector2.ZERO)
		draw_polyline(points, color, width)


func _draw() -> void:
	if detonated:
		var fade := 1.0 - clampf(impact_age / impact_lifetime, 0.0, 1.0)
		draw_area(radius, Color(1.0, 0.28, 0.03, fade * 0.65))
		draw_area(radius * 0.85, Color(1.0, 0.8, 0.3, fade * fade * 0.65))
		draw_border(Color(1.0, 0.9, 0.55, fade), 3.0)
		return
	var progress := clampf(age / maxf(warning_seconds, 0.05), 0.0, 1.0)
	# The full danger boundary is visible from the start; the growing fill is the countdown.
	draw_area(radius, Color(0.95, 0.08, 0.04, 0.16))
	draw_area(radius * progress, Color(1.0, 0.35, 0.03, 0.3))
	var pulse := 0.75 + 0.25 * sin(age * 14.0)
	draw_border(Color(1.0, 0.45, 0.12, pulse), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.75, 0.2))
