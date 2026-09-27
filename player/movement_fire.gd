extends Node2D

## Cosmetic explosion propulsion. Movement and stamina are controlled by Player.
@export var blast_radius: float = 44.0
@export var blast_lifetime: float = 0.34
@export var blast_offset: Vector2 = Vector2(0.0, 3.25)
@export var spark_count: int = 40
@export var smoke_lifetime: float = 1.0
@export var smoke_spacing: float = 7.0

@onready var player: Player = get_parent() as Player

var foreground: Node2D
var was_dashing: bool = false
var launch_bursts: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var smoke_puffs: Array[Dictionary] = []
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.randomize()
	foreground = Node2D.new()
	foreground.name = "DashForeground"
	foreground.z_index = 1
	add_child(foreground)
	foreground.draw.connect(draw_foreground)


func _physics_process(delta: float) -> void:
	var dashing := player.health > 0.0 and not player.heavy_attack_locked and player.is_dashing
	if dashing and not was_dashing:
		var direction := player.dash_vector.normalized()
		# Place the explosion at takeoff, before this tick's dash displacement.
		var origin := (
			player.global_position - player.get_real_velocity() * delta
			+ blast_offset - direction * 10.0
		)
		start_blast(origin, -direction, player.facing_direction() == Vector2.UP)
	if dashing:
		var direction := player.dash_vector.normalized()
		var end := player.global_position + blast_offset - direction * 10.0
		var start := end - player.get_real_velocity() * delta
		var distance := start.distance_to(end)
		if distance > 0.5 and distance < 240.0:
			var count := clampi(ceili(distance / maxf(smoke_spacing, 1.0)), 1, 32)
			for index in range(count):
				spawn_smoke(start.lerp(end, float(index + 1) / count), -direction)
	was_dashing = dashing


func spawn_smoke(origin: Vector2, exhaust: Vector2, size_multiplier: float = 1.0) -> void:
	smoke_puffs.append({
		"position": origin + Vector2(random.randf_range(-3.0, 3.0), random.randf_range(-3.0, 3.0)),
		"velocity": exhaust * random.randf_range(5.0, 14.0) + Vector2.UP * random.randf_range(2.0, 6.0),
		"age": 0.0, "lifetime": maxf(smoke_lifetime, 0.05),
		"radius": random.randf_range(7.0, 11.0) * size_multiplier,
		"angle": random.randf_range(0.0, TAU)
	})
	if smoke_puffs.size() > 160:
		smoke_puffs.pop_front()


func start_blast(origin: Vector2, exhaust: Vector2, in_front: bool) -> void:
	for index in range(5):
		spawn_smoke(origin + exhaust.rotated(random.randf_range(-1.0, 1.0)) * 12.0, exhaust, 1.4)
	var spikes := PackedFloat32Array()
	for index in range(24):
		spikes.append(random.randf_range(0.95, 1.25) if index % 2 == 0 else random.randf_range(0.5, 0.7))
	launch_bursts.append({
		"position": origin, "exhaust": exhaust, "in_front": in_front,
		"spikes": spikes, "age": 0.0
	})
	if launch_bursts.size() > 4:
		launch_bursts.pop_front()

	for index in range(spark_count):
		if sparks.size() >= 96:
			break
		var direction := exhaust.rotated(random.randf_range(-1.25, 1.25))
		sparks.append({
			"position": origin,
			"velocity": direction * random.randf_range(160.0, 340.0),
			"age": 0.0, "lifetime": random.randf_range(0.25, 0.5),
			"in_front": in_front, "width": random.randf_range(1.0, 2.0)
		})


func _process(delta: float) -> void:
	for index in range(smoke_puffs.size() - 1, -1, -1):
		var puff: Dictionary = smoke_puffs[index]
		puff["age"] += delta
		if puff["age"] >= puff["lifetime"]:
			smoke_puffs.remove_at(index)
			continue
		puff["position"] += puff["velocity"] * delta
		puff["velocity"] *= exp(-2.0 * delta)
	for index in range(launch_bursts.size() - 1, -1, -1):
		launch_bursts[index]["age"] += delta
		if launch_bursts[index]["age"] >= blast_lifetime:
			launch_bursts.remove_at(index)
	for index in range(sparks.size() - 1, -1, -1):
		var spark: Dictionary = sparks[index]
		spark["age"] += delta
		if spark["age"] >= spark["lifetime"]:
			sparks.remove_at(index)
			continue
		spark["position"] += spark["velocity"] * delta
		spark["velocity"] *= exp(-6.0 * delta)
	queue_redraw()
	foreground.queue_redraw()


func _draw() -> void:
	draw_smoke()
	draw_effects(self, false)


func draw_smoke() -> void:
	for puff in smoke_puffs:
		var progress: float = puff["age"] / puff["lifetime"]
		var center := to_local(puff["position"])
		var radius: float = puff["radius"] * lerpf(0.45, 1.6, progress)
		var color := Color(0.3, 0.22, 0.16).lerp(Color(0.4, 0.39, 0.38), minf(progress * 3.0, 1.0))
		color.a = minf(float(puff["age"]) / 0.05, 1.0) * pow(1.0 - progress, 1.5) * 0.32
		draw_circle(center, radius, color)
		var side := Vector2.RIGHT.rotated(float(puff["angle"])) * radius * 0.5
		draw_circle(center + side, radius * 0.7, color)
		draw_circle(center - side, radius * 0.65, color)


func draw_foreground() -> void:
	draw_effects(foreground, true)


func draw_effects(canvas: Node2D, in_front: bool) -> void:
	for burst in launch_bursts:
		if burst["in_front"] == in_front:
			draw_blast(canvas, burst)
	for spark in sparks:
		if spark["in_front"] != in_front:
			continue
		var progress: float = spark["age"] / spark["lifetime"]
		var color := Color(1.0, 0.96, 0.6).lerp(Color(1.0, 0.2, 0.02, 0.0), progress)
		var spark_position := canvas.to_local(spark["position"])
		var velocity: Vector2 = spark["velocity"]
		var streak := velocity.normalized().rotated(-canvas.global_rotation) * lerpf(9.0, 2.0, progress)
		canvas.draw_line(spark_position, spark_position - streak, color, float(spark["width"]))


func draw_blast(canvas: Node2D, burst: Dictionary) -> void:
	var progress: float = burst["age"] / maxf(blast_lifetime, 0.001)
	var expansion := 0.4 + 0.6 * (1.0 - exp(-progress * 12.0))
	var alpha := pow(1.0 - progress, 1.6)
	var origin := canvas.to_local(burst["position"])
	var exhaust: Vector2 = burst["exhaust"]
	exhaust = exhaust.rotated(-canvas.global_rotation)
	var side := exhaust.orthogonal()
	var radius := blast_radius * expansion
	var center := origin + exhaust * radius * 0.5
	var spikes: PackedFloat32Array = burst["spikes"]
	var outline := PackedVector2Array()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()

	# A broad, jagged fireball expands backward from the character, not a sustained nozzle plume.
	for index in range(spikes.size()):
		var angle := TAU * index / spikes.size()
		var offset := (
			exhaust * cos(angle) * radius * 1.15
			+ side * sin(angle) * radius * 0.85
		) * spikes[index]
		outline.append(center + offset * 1.1)
		outer.append(center + offset)
		inner.append(center + offset * 0.65)
	canvas.draw_colored_polygon(outline, Color(0.6, 0.08, 0.01, alpha * 0.7))
	canvas.draw_colored_polygon(outer, Color(1.0, 0.27, 0.02, alpha))
	canvas.draw_colored_polygon(inner, Color(1.0, 0.72, 0.12, alpha))
	var flash := maxf(1.0 - float(burst["age"]) / 0.09, 0.0)
	canvas.draw_circle(center, radius * 0.42, Color(1.0, 0.99, 0.8, flash))

	# A quick pressure arc and radial streaks sell the initial explosive impulse.
	canvas.draw_arc(
		origin, radius * 1.35, exhaust.angle() - PI * 0.6, exhaust.angle() + PI * 0.6,
		24, Color(1.0, 0.84, 0.3, alpha * 0.65), 3.0
	)
	canvas.draw_arc(
		origin, radius * 1.65, exhaust.angle() - PI * 0.5, exhaust.angle() + PI * 0.5,
		24, Color(1.0, 0.5, 0.08, alpha * 0.3), 2.0
	)
	for index in range(11):
		var direction := exhaust.rotated(lerpf(-1.25, 1.25, float(index) / 10.0))
		canvas.draw_line(
			origin + direction * radius,
			origin + direction * radius * (1.55 + progress * 0.5),
			Color(1.0, 0.78, 0.18, alpha * 0.65), 1.5
		)
