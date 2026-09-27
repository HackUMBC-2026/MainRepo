extends Node2D
class_name SwordHiltFire

## Cosmetic thrusters: observe sword motion without applying any forces.
@export var jet_length: float = 34.0
@export var jet_width: float = 5.0
@export var power_jet_length: float = 100.0
@export var power_jet_width: float = 12.0
@export var motion_sensitivity: float = 1.0
@export var idle_flicker_strength: float = 0.12
@export var spark_rate: float = 22.0

# All six ports sit on the grip/pommel. The side pairs also suggest torque.
const PORT_POSITIONS := [
	Vector2(-2.0, -3.0), Vector2(2.0, -3.0),
	Vector2(-2.0, 3.0), Vector2(2.0, 3.0),
	Vector2(0.0, -4.0), Vector2(0.0, 4.0)
]
const PORT_DIRECTIONS := [
	Vector2.LEFT, Vector2.RIGHT, Vector2.LEFT, Vector2.RIGHT,
	Vector2.UP, Vector2.DOWN
]

var enabled: bool = true
var has_motion_sample: bool = false
var previous_position: Vector2
var previous_angle: float = 0.0
var filtered_velocity: Vector2 = Vector2.ZERO
var filtered_turn_speed: float = 0.0
var thrust: Vector2 = Vector2.ZERO
var turning_thrust: float = 0.0
var attack_energy: float = 0.0
var elapsed: float = 0.0
var strengths: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
var spark_budget: float = 0.0
var sparks: Array[Dictionary] = []
var random := RandomNumberGenerator.new()
var power_jet_active: bool = false
var power_jet_age: float = 0.0
var power_exhaust_direction: Vector2 = Vector2.DOWN


func begin_power_release(attack_direction: Vector2) -> void:
	if not enabled:
		return
	power_jet_active = true
	power_jet_age = 0.0
	power_exhaust_direction = -attack_direction.normalized()


func end_power_release() -> void:
	power_jet_active = false


func _ready() -> void:
	show_behind_parent = true
	random.randomize()


func sample_motion(world_position: Vector2, world_angle: float, delta: float, energy: float) -> void:
	if not enabled or delta <= 0.0:
		return
	attack_energy = energy
	var displacement := world_position - previous_position
	if not has_motion_sample or displacement.length() > 240.0:
		# Initial placement and teleports must not produce a huge ignition burst.
		has_motion_sample = true
		previous_position = world_position
		previous_angle = world_angle
		filtered_velocity = Vector2.ZERO
		filtered_turn_speed = 0.0
		thrust = Vector2.ZERO
		turning_thrust = 0.0
		return

	var smoothing := 1.0 - exp(-24.0 * delta)
	var velocity := filtered_velocity.lerp(displacement / delta, smoothing)
	var acceleration := (velocity - filtered_velocity) / delta
	var turn_speed := lerpf(
		filtered_turn_speed, angle_difference(previous_angle, world_angle) / delta, smoothing
	)
	var turn_acceleration := (turn_speed - filtered_turn_speed) / delta
	# Acceleration creates launch/braking bursts; a little velocity keeps moving jets alive.
	var target_thrust := (
		(acceleration / 2400.0 + velocity / 900.0) * motion_sensitivity
	).limit_length(1.0)
	thrust = thrust.lerp(target_thrust, 1.0 - exp(-32.0 * delta))
	turning_thrust = lerpf(
		turning_thrust,
		clampf((turn_acceleration / 180.0 + turn_speed / 24.0) * motion_sensitivity, -1.0, 1.0),
		1.0 - exp(-32.0 * delta)
	)
	filtered_velocity = velocity
	filtered_turn_speed = turn_speed
	previous_position = world_position
	previous_angle = world_angle


func extinguish() -> void:
	end_power_release()
	enabled = false
	thrust = Vector2.ZERO
	turning_thrust = 0.0
	attack_energy = 0.0
	spark_budget = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	if power_jet_active:
		power_jet_age += delta
	var strongest_port := 0
	for port in range(PORT_POSITIONS.size()):
		var target_strength := 0.0
		if enabled:
			var exhaust: Vector2 = PORT_DIRECTIONS[port].rotated(global_rotation)
			# Exhaust points opposite the push needed to accelerate or brake.
			var translation := maxf(0.0, -exhaust.dot(thrust))
			var torque_sign := -signf(PORT_POSITIONS[port].cross(PORT_DIRECTIONS[port]))
			var rotation_burst := maxf(0.0, torque_sign * turning_thrust) * 0.55
			var pulse_phase := fposmod(elapsed * 6.0 + port * 0.173, 1.0)
			var idle_pulse := (1.0 - smoothstep(0.04, 0.24, pulse_phase)) * idle_flicker_strength
			var flutter := 0.85 + 0.15 * sin(elapsed * 83.0 + port * 2.7)
			target_strength = clampf(
				(maxf(translation, rotation_burst) * (0.65 + attack_energy * 0.65) + idle_pulse) * flutter,
				0.0, 1.4
			)
		var response := 65.0 if target_strength > strengths[port] else 22.0
		strengths[port] = lerpf(strengths[port], target_strength, 1.0 - exp(-response * delta))
		if strengths[port] > strengths[strongest_port]:
			strongest_port = port

	# Keep a small, bounded pool of world-space embers after the hilt moves away.
	for index in range(sparks.size() - 1, -1, -1):
		var spark: Dictionary = sparks[index]
		spark["age"] += delta
		if spark["age"] >= spark["lifetime"]:
			sparks.remove_at(index)
			continue
		spark["position"] += spark["velocity"] * delta
		spark["velocity"] *= exp(-4.0 * delta)

	if enabled and strengths[strongest_port] > 0.25:
		spark_budget = minf(spark_budget + delta * spark_rate * strengths[strongest_port], 3.0)
		while spark_budget >= 1.0 and sparks.size() < 24:
			spawn_spark(strongest_port)
			spark_budget -= 1.0
	else:
		spark_budget = 0.0
	queue_redraw()


func spawn_spark(port: int) -> void:
	var direction: Vector2 = PORT_DIRECTIONS[port].rotated(
		global_rotation + random.randf_range(-0.25, 0.25)
	)
	sparks.append({
		"position": to_global(PORT_POSITIONS[port]),
		"velocity": direction * random.randf_range(35.0, 85.0) + filtered_velocity * 0.12,
		"age": 0.0,
		"lifetime": random.randf_range(0.10, 0.22)
	})


func _draw() -> void:
	for port in range(PORT_POSITIONS.size()):
		var strength := strengths[port]
		if strength < 0.015:
			continue
		var origin: Vector2 = PORT_POSITIONS[port]
		var direction: Vector2 = PORT_DIRECTIONS[port]
		var length := 2.0 + jet_length * strength
		var width := jet_width * (0.3 + 0.7 * minf(strength, 1.0))
		var flicker := sin(elapsed * 67.0 + port * 1.9)
		var alpha := clampf(strength * 5.0, 0.0, 1.0)
		draw_flame(origin, direction, length, width, flicker, alpha)

	if power_jet_active:
		# A continuous hilt plume pushes opposite the locked slam direction, even when flipped.
		var direction := power_exhaust_direction.rotated(-global_rotation)
		var ignition := lerpf(0.65, 1.0, minf(power_jet_age / 0.025, 1.0))
		var length := power_jet_length * ignition * (1.0 + 0.12 * sin(elapsed * 93.0))
		var width := power_jet_width * (0.9 + 0.1 * sin(elapsed * 71.0))
		draw_flame(Vector2.ZERO, direction, length, width, sin(elapsed * 57.0), 1.0)
		# Smaller branching tongues give the main jet a ragged flame silhouette.
		for branch in [-1.0, 1.0]:
			draw_flame(
				direction * 5.0, direction.rotated(branch * 0.16),
				length * 0.6, width * 0.45, sin(elapsed * 81.0 + branch), 0.65
			)

	for spark in sparks:
		var progress: float = spark["age"] / spark["lifetime"]
		var color := Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.2, 0.02, 0.0), progress)
		draw_rect(Rect2(to_local(spark["position"]), Vector2.ONE), color)


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
