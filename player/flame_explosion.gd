extends Node2D

## A self-contained visual burst that stays at the impact point as the sword returns.
var burst_radius: float = 49.0
var lifetime: float = 0.65
var elapsed: float = 0.0
var embers: Array[Dictionary] = []
var flame_lengths: PackedFloat32Array = PackedFloat32Array()
var random := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 10
	random.randomize()
	for index in range(16):
		flame_lengths.append(random.randf_range(0.8, 1.25))
	for index in range(28):
		var direction := Vector2.RIGHT.rotated(TAU * index / 28.0 + random.randf_range(-0.1, 0.1))
		embers.append({
			"velocity": direction * random.randf_range(120.0, 300.0),
			"lifetime": random.randf_range(0.3, lifetime),
			"size": random.randf_range(1.0, 2.5)
		})


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	var expansion := 0.18 + 0.82 * (1.0 - exp(-18.0 * elapsed))
	var radius := burst_radius * expansion
	var flame_alpha := pow(1.0 - progress, 1.8)

	# Uneven radial tongues expand quickly, then burn away to embers.
	for index in range(flame_lengths.size()):
		var angle := TAU * index / flame_lengths.size()
		var direction := Vector2.RIGHT.rotated(angle)
		var side := direction.orthogonal()
		var reach := radius * flame_lengths[index]
		var curl := sin(elapsed * 24.0 + index * 1.7) * radius * 0.08
		var base := direction * radius * 0.25
		draw_colored_polygon(PackedVector2Array([
			base - side * radius * 0.16,
			direction * reach * 0.7 - side * radius * 0.12,
			direction * reach + side * curl,
			direction * reach * 0.6 + side * radius * 0.16,
			base + side * radius * 0.16
		]), Color(1.0, 0.16, 0.015, flame_alpha))
		draw_colored_polygon(PackedVector2Array([
			base - side * radius * 0.09,
			direction * reach * 0.8 + side * curl * 0.5,
			base + side * radius * 0.09
		]), Color(1.0, 0.58, 0.04, flame_alpha))

	draw_fireball(radius * 0.65, Color(1.0, 0.35, 0.02, flame_alpha))
	draw_fireball(radius * 0.45, Color(1.0, 0.78, 0.14, flame_alpha))
	var flash := maxf(1.0 - elapsed / 0.13, 0.0)
	draw_fireball(radius * 0.3, Color(1.0, 0.98, 0.75, flash))

	for ember in embers:
		var ember_progress: float = elapsed / ember["lifetime"]
		if ember_progress >= 1.0:
			continue
		var velocity: Vector2 = ember["velocity"]
		var position := velocity * (1.0 - exp(-4.0 * elapsed)) / 4.0
		var color := Color(1.0, 0.9, 0.35).lerp(Color(1.0, 0.17, 0.01, 0.0), ember_progress)
		draw_line(position, position - velocity.normalized() * 4.0, color, float(ember["size"]))


func draw_fireball(radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * index / 32.0
		var ripple := 1.0 + 0.1 * sin(angle * 7.0 + elapsed * 20.0)
		points.append(Vector2.RIGHT.rotated(angle) * radius * ripple)
	draw_colored_polygon(points, color)
