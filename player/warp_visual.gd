extends Node2D

# Brief warp streaks and a frozen silhouette; particles remain single pixels.
var span: float = 0.0
var burst: bool = false
var age: float = 0.0
var ghost: Sprite2D
var ghost_scale := Vector2.ONE

func capture_sprite(source: Sprite2D, direction: Vector2) -> void:
	ghost = Sprite2D.new()
	ghost.texture = source.texture
	ghost.hframes = source.hframes
	ghost.vframes = source.vframes
	ghost.frame = source.frame
	ghost.offset = source.offset
	ghost.centered = source.centered
	ghost.flip_h = source.flip_h
	ghost.flip_v = source.flip_v
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ghost)
	ghost.global_transform = source.global_transform
	var along := direction.rotated(-source.global_rotation).abs()
	ghost.scale *= Vector2.ONE + along * 0.75
	ghost_scale = ghost.scale
	ghost.modulate = Color(2.0, 0.95, 0.3, 0.65)

func _process(delta: float) -> void:
	age += delta
	var lifetime := 0.24 if burst else 0.18
	if age >= lifetime:
		queue_free()
		return
	if is_instance_valid(ghost):
		ghost.modulate.a = 0.65 * pow(1.0 - age / lifetime, 2.0)
		ghost.scale = ghost_scale * (1.0 + age * 0.5)
	queue_redraw()

func _draw() -> void:
	if is_instance_valid(ghost):
		return
	var fade := maxf(0.0, 1.0 - age / (0.24 if burst else 0.18))
	if burst:
		# A sharp directional flash collapses as sparks burst outwards.
		var length := 50.0 * fade
		draw_line(Vector2(-length, 0.0), Vector2(length, 0.0), Color(1.0, 0.9, 0.5, fade), 1.0)
		draw_line(Vector2(0.0, -length * 0.5), Vector2(0.0, length * 0.5), Color(1.0, 0.6, 0.1, fade), 1.0)
		for index in range(8):
			var direction := Vector2.RIGHT.rotated(float(index) * TAU / 8.0)
			var distance := 10.0 + age * 160.0
			draw_line(direction * distance, direction * (distance + 12.0 * fade), Color(1.0, 0.55, 0.12, fade), 1.0)
	else:
		# Thin parallel streaks make each traveled segment read as one fiery warp.
		draw_line(Vector2.ZERO, Vector2(span, 0.0), Color(1.0, 0.3, 0.02, fade * 0.3), 8.0 * fade)
		draw_line(Vector2.ZERO, Vector2(span, 0.0), Color(1.0, 0.96, 0.7, fade), 1.0)
		for side in [-1.0, 1.0]:
			draw_line(Vector2(0.0, side * 8.0), Vector2(span, side * 5.0), Color(1.0, 0.65, 0.15, fade * 0.65), 1.0)
