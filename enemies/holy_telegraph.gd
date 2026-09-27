extends BossTelegraph
class_name HolyTelegraph

signal binding_applied

enum Pattern { CIRCLE, BEAM, RING, CROSS, SEAL }

const GOLD := Color(1.0, 0.78, 0.24)
const LIGHT := Color(1.0, 0.97, 0.82)

var pattern: Pattern = Pattern.CIRCLE
var beam_half_width: float = 20.0
var inner_radius: float = 60.0
var binding_seconds: float = 1.5


func apply_hit() -> void:
	if pattern == Pattern.SEAL:
		target.apply_holy_binding(binding_seconds, attacker)
		binding_applied.emit()
	else:
		super.apply_hit()


func contains_player() -> bool:
	var body_shape := target.get_node("CollisionShape2D") as CollisionShape2D
	var circle := body_shape.shape as CircleShape2D
	var body_radius := circle.radius * maxf(
		body_shape.global_transform.x.length(), body_shape.global_transform.y.length()
	)
	var center := to_local(body_shape.global_position)
	match pattern:
		Pattern.CIRCLE, Pattern.SEAL:
			return center.length() <= radius + body_radius
		Pattern.RING:
			return center.length() <= radius + body_radius and center.length() + body_radius >= inner_radius
		Pattern.BEAM:
			return overlaps_rect(center, body_radius, Rect2(0, -beam_half_width, radius, beam_half_width * 2.0))
		Pattern.CROSS:
			return (
				overlaps_rect(center, body_radius, Rect2(-radius, -beam_half_width, radius * 2.0, beam_half_width * 2.0))
				or overlaps_rect(center, body_radius, Rect2(-beam_half_width, -radius, beam_half_width * 2.0, radius * 2.0))
			)
	return false


func overlaps_rect(center: Vector2, body_radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(nearest) <= body_radius * body_radius


func cross_points(size: float) -> PackedVector2Array:
	var width := minf(beam_half_width, size)
	return PackedVector2Array([
		Vector2(-size, -width), Vector2(-width, -width), Vector2(-width, -size),
		Vector2(width, -size), Vector2(width, -width), Vector2(size, -width),
		Vector2(size, width), Vector2(width, width), Vector2(width, size),
		Vector2(-width, size), Vector2(-width, width), Vector2(-size, width),
	])


func draw_area(size: float, color: Color) -> void:
	if size <= 0.01:
		return
	match pattern:
		Pattern.CIRCLE, Pattern.SEAL:
			draw_circle(Vector2.ZERO, size, color)
		Pattern.BEAM:
			draw_rect(Rect2(0, -beam_half_width, size, beam_half_width * 2.0), color)
		Pattern.RING:
			if size > inner_radius:
				draw_arc(Vector2.ZERO, (size + inner_radius) * 0.5, 0.0, TAU, 64, color, size - inner_radius)
		Pattern.CROSS:
			if size <= beam_half_width:
				draw_rect(Rect2(Vector2(-size, -size), Vector2(size * 2.0, size * 2.0)), color)
			else:
				draw_colored_polygon(cross_points(size), color)


func draw_border(color: Color, width: float) -> void:
	match pattern:
		Pattern.CIRCLE, Pattern.SEAL:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, width)
		Pattern.BEAM:
			draw_rect(Rect2(0, -beam_half_width, radius, beam_half_width * 2.0), color, false, width)
		Pattern.RING:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, width)
			draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 64, color, width)
		Pattern.CROSS:
			var points := cross_points(radius)
			points.append(points[0])
			draw_polyline(points, color, width)


func _draw() -> void:
	var progress := clampf(age / maxf(warning_seconds, 0.05), 0.0, 1.0)
	if detonated:
		var fade := 1.0 - clampf(impact_age / impact_lifetime, 0.0, 1.0)
		draw_area(radius, Color(GOLD, fade * 0.45))
		draw_area(radius, Color(LIGHT, fade * fade * 0.5))
		draw_border(Color(LIGHT, fade), 3.0)
		draw_sigil(fade, true)
		return
	draw_area(radius, Color(GOLD, 0.12))
	var fill_size := lerpf(inner_radius, radius, progress) if pattern == Pattern.RING else radius * progress
	draw_area(fill_size, Color(GOLD, 0.25))
	draw_border(Color(GOLD, 0.75 + 0.25 * sin(age * 12.0)), 1.5)
	draw_sigil(0.4 + progress * 0.5, false)


func draw_sigil(opacity: float, impact: bool) -> void:
	var color := Color(LIGHT, opacity)
	if pattern == Pattern.BEAM:
		draw_line(Vector2.ZERO, Vector2(radius, 0), color, 4.0 if impact else 1.0)
		for index in range(1, 5):
			var center := Vector2(radius * float(index) / 5.0, 0.0)
			draw_line(center - Vector2(0, 6), center + Vector2(0, 6), color, 1.5)
	elif pattern == Pattern.RING:
		for index in range(12):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 12.0)
			draw_line(direction * (inner_radius + 5.0), direction * (radius - 5.0), color, 1.5)
	else:
		var size := minf(radius * 0.4, 18.0)
		draw_line(Vector2(-size, 0), Vector2(size, 0), color, 3.0 if impact else 1.5)
		draw_line(Vector2(0, -size), Vector2(0, size), color, 3.0 if impact else 1.5)
		if pattern == Pattern.SEAL:
			draw_arc(Vector2.ZERO, radius * 0.65, 0.0, TAU, 40, color, 1.5)
			for index in range(6):
				var direction := Vector2.RIGHT.rotated(TAU * float(index) / 6.0 + age * 0.4)
				draw_line(direction * radius * 0.6, direction * radius * 0.85, color, 2.0)
		elif impact and pattern == Pattern.CIRCLE:
			# A small number of beams suggests a descending pillar without a particle swarm.
			for index in range(5):
				var x := (float(index) - 2.0) * radius * 0.25
				draw_line(Vector2(x, 0), Vector2(x, -radius * (1.4 - impact_age)), Color(LIGHT, opacity * 0.45), 2.0)
