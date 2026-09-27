extends Node2D
class_name SwordHiltFire

## A compact cloud of fiery motes that stays centered on the hilt.
@export var orb_radius: float = 9.0
@export var power_jet_length: float = 100.0
@export var power_jet_width: float = 12.0
@export var spark_rate: float = 50.0
@export var trail_spacing: float = 4.0
@export var trail_lifetime: float = 0.5

var enabled: bool = true
var elapsed: float = 0.0
var glow_strength: float = 1.0
var spark_budget: float = 0.0
var sparks: Array[Dictionary] = []
var trail_motes: Array[Dictionary] = []
var previous_hilt_position: Vector2
var has_trail_position: bool = false
var random := RandomNumberGenerator.new()
var power_jet_active: bool = false
var power_jet_age: float = 0.0
var power_exhaust_direction: Vector2 = Vector2.DOWN


func _ready() -> void:
	show_behind_parent = true
	random.randomize()
	# Start with a full cloud, with staggered particle ages to avoid synchronized flicker.
	for index in range(24):
		spawn_mote(true)


func spawn_mote(prewarm: bool = false) -> void:
	var direction := Vector2.RIGHT.rotated(random.randf_range(0.0, TAU))
	var lifetime := random.randf_range(0.4, 0.75)
	sparks.append({
		"position": direction * sqrt(random.randf()) * orb_radius * 0.8,
		"velocity": direction * random.randf_range(1.0, 4.0),
		"swirl": random.randf_range(-1.5, 1.5),
		"size": random.randf_range(1.0, 2.3),
		"age": random.randf_range(0.08, lifetime * 0.9) if prewarm else 0.0,
		"lifetime": lifetime
	})


func begin_power_release(attack_direction: Vector2) -> void:
	if not enabled:
		return
	power_jet_active = true
	power_jet_age = 0.0
	power_exhaust_direction = -attack_direction.normalized()


func end_power_release() -> void:
	power_jet_active = false


func extinguish() -> void:
	end_power_release()
	enabled = false
	spark_budget = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	update_ember_trail(delta)
	glow_strength = move_toward(glow_strength, 1.0 if enabled else 0.0, delta * 7.0)
	if power_jet_active:
		power_jet_age += delta
	for index in range(sparks.size() - 1, -1, -1):
		var spark: Dictionary = sparks[index]
		spark["age"] += delta
		if spark["age"] >= spark["lifetime"]:
			sparks.remove_at(index)
			continue
		# Local positions keep the ball attached during swings; there is no upward gravity.
		var mote_position: Vector2 = spark["position"]
		mote_position = mote_position.rotated(float(spark["swirl"]) * delta)
		mote_position += spark["velocity"] * delta
		spark["position"] = mote_position.limit_length(orb_radius)

	if enabled:
		spark_budget = minf(spark_budget + delta * spark_rate, 3.0)
		while spark_budget >= 1.0 and sparks.size() < 40:
			spawn_mote()
			spark_budget -= 1.0
	queue_redraw()


func update_ember_trail(delta: float) -> void:
	for index in range(trail_motes.size() - 1, -1, -1):
		var mote: Dictionary = trail_motes[index]
		mote["age"] += delta
		if mote["age"] >= mote["lifetime"]:
			trail_motes.remove_at(index)
			continue
		mote["position"] += mote["velocity"] * delta
		mote["velocity"] *= exp(-3.0 * delta)

	if enabled and has_trail_position:
		var distance := previous_hilt_position.distance_to(global_position)
		# Fill the path during fast swings, but do not connect teleports.
		if distance > 0.5 and distance < 240.0:
			var count := clampi(ceili(distance / maxf(trail_spacing, 1.0)), 1, 48)
			for index in range(count):
				var along := (float(index) + random.randf()) / count
				trail_motes.append({
					"position": previous_hilt_position.lerp(global_position, along)
						+ Vector2.from_angle(random.randf() * TAU) * random.randf_range(0.0, 3.0),
					"velocity": Vector2.from_angle(random.randf() * TAU) * random.randf_range(3.0, 10.0),
					"age": 0.0, "lifetime": maxf(trail_lifetime, 0.05) * random.randf_range(0.8, 1.2),
					"size": random.randf_range(1.0, 2.2)
				})
	while trail_motes.size() > 128:
		trail_motes.pop_front()
	previous_hilt_position = global_position
	has_trail_position = true


func _draw() -> void:
	# These embers stay in world space while the central particle ball follows the hilt.
	for mote in trail_motes:
		var progress: float = mote["age"] / mote["lifetime"]
		var color := Color(1.0, 0.9, 0.35).lerp(Color(1.0, 0.13, 0.015, 0.0), progress)
		var center := to_local(mote["position"])
		var size: float = mote["size"] * (1.0 - progress * 0.5)
		draw_circle(center, size * 2.0, Color(1.0, 0.25, 0.02, color.a * 0.12))
		draw_rect(Rect2(center - Vector2.ONE * size * 0.5, Vector2.ONE * size), color)

	if glow_strength > 0.01:
		var pulse := 0.92 + 0.08 * sin(elapsed * 5.0)
		draw_circle(Vector2.ZERO, orb_radius * pulse, Color(1.0, 0.2, 0.025, glow_strength * 0.07))
		draw_circle(Vector2.ZERO, orb_radius * 0.55, Color(1.0, 0.5, 0.05, glow_strength * 0.08))

	if power_jet_active:
		var direction := power_exhaust_direction.rotated(-global_rotation)
		var ignition := lerpf(0.65, 1.0, minf(power_jet_age / 0.025, 1.0))
		var length := power_jet_length * ignition * (1.0 + 0.12 * sin(elapsed * 93.0))
		var width := power_jet_width * (0.9 + 0.1 * sin(elapsed * 71.0))
		draw_flame(Vector2.ZERO, direction, length, width, sin(elapsed * 57.0), 1.0)
		for branch in [-1.0, 1.0]:
			draw_flame(
				direction * 5.0, direction.rotated(branch * 0.16),
				length * 0.6, width * 0.45, sin(elapsed * 81.0 + branch), 0.65
			)

	for spark in sparks:
		var progress: float = spark["age"] / spark["lifetime"]
		var color := Color(1.0, 0.95, 0.5).lerp(Color(1.0, 0.16, 0.015), progress)
		color.a = minf(float(spark["age"]) / 0.08, 1.0) * (1.0 - progress) * glow_strength
		var mote_position: Vector2 = spark["position"]
		var size: float = spark["size"]
		draw_circle(mote_position, size * 1.5, Color(1.0, 0.3, 0.02, color.a * 0.12))
		draw_rect(Rect2(mote_position - Vector2.ONE * size * 0.5, Vector2.ONE * size), color)


func draw_flame(
	origin: Vector2, direction: Vector2, length: float, width: float, flicker: float, alpha: float
) -> void:
	var side := direction.orthogonal()
	var tip := origin + direction * length + side * flicker * width * 0.65
	draw_colored_polygon(PackedVector2Array([
		origin - side * width * 0.5,
		origin + direction * length * 0.3 - side * width,
		tip,
		origin + direction * length * 0.48 + side * width * 0.75,
		origin + side * width * 0.5
	]), Color(1.0, 0.18, 0.025, alpha * 0.85))
	draw_colored_polygon(PackedVector2Array([
		origin - side * width * 0.4,
		origin + direction * length * 0.22 - side * width * 0.55,
		origin + direction * length * 0.7 + side * flicker * width * 0.2,
		origin + side * width * 0.5
	]), Color(1.0, 0.55, 0.06, alpha))
	draw_colored_polygon(PackedVector2Array([
		origin - side * width * 0.25,
		origin + direction * length * 0.4,
		origin + side * width * 0.25
	]), Color(1.0, 0.96, 0.6, alpha))
