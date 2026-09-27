@tool
extends Node2D
## Texture-ready scenery. Art size is independent of the separate collision shapes.

enum Placeholder { BLOCK, PILLAR, THRONE, BANNER }

@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var art_size: Vector2 = Vector2(64, 64):
	set(value):
		art_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		queue_redraw()
@export var art_offset: Vector2 = Vector2.ZERO:
	set(value):
		art_offset = value
		queue_redraw()
@export var tile_texture: bool = false:
	set(value):
		tile_texture = value
		queue_redraw()
@export var placeholder: Placeholder = Placeholder.BLOCK:
	set(value):
		placeholder = value
		queue_redraw()
@export var placeholder_color: Color = Color(0.22, 0.23, 0.28):
	set(value):
		placeholder_color = value
		queue_redraw()
@export var trim_color: Color = Color(0.6, 0.48, 0.26):
	set(value):
		trim_color = value
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(art_offset - art_size * 0.5, art_size)
	if texture != null:
		draw_texture_rect(texture, rect, tile_texture)
		return

	match placeholder:
		Placeholder.PILLAR:
			var radius := minf(art_size.x, art_size.y) * 0.5
			draw_circle(art_offset, radius, placeholder_color)
			draw_arc(art_offset, radius - 1.0, 0.0, TAU, 32, trim_color, 2.0)
			draw_arc(art_offset, radius * 0.65, 0.0, TAU, 32, trim_color, 1.0)
		Placeholder.THRONE:
			draw_rect(rect, placeholder_color)
			draw_rect(rect, trim_color, false, 3.0)
			var seat := Rect2(rect.position + art_size * Vector2(0.18, 0.5), art_size * Vector2(0.64, 0.4))
			draw_rect(seat, Color(0.42, 0.08, 0.12))
			draw_rect(seat, trim_color, false, 2.0)
		Placeholder.BANNER:
			var points := PackedVector2Array([
				rect.position, rect.position + Vector2(art_size.x, 0),
				rect.end - Vector2(0, art_size.y * 0.2),
				art_offset + Vector2(0, art_size.y * 0.5),
				rect.position + Vector2(0, art_size.y * 0.8),
			])
			draw_colored_polygon(points, placeholder_color)
			points.append(points[0])
			draw_polyline(points, trim_color, 2.0)
		Placeholder.BLOCK:
			draw_rect(rect, placeholder_color)
			draw_rect(rect, trim_color, false, 2.0)
