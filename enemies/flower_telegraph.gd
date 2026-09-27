extends BossTelegraph
class_name FlowerTelegraph

enum Pattern { RING, PETAL, FLOWER }

var pattern: Pattern = Pattern.FLOWER
var inner_radius: float = 72.0
var petal_half_width: float = 36.0
var main_color: Color = Color(1.0, 0.43, 0.08)
var petal_colors: Array[Color] = [Color(1.0, 0.43, 0.08), Color(0.12, 0.58, 1.0), Color(0.64, 0.22, 1.0)]
var flowing_petals: bool = false
const PARTICLE_SHADER = preload("res://enemies/flower_particles.gdshader")
static var shared_particle_mesh: QuadMesh

var particle_batch: MultiMeshInstance2D
var particle_material: ShaderMaterial
var showing_impact: bool = false


func contains_player() -> bool:
	var body_shape := target.get_node("CollisionShape2D") as CollisionShape2D
	var circle := body_shape.shape as CircleShape2D
	var body_radius := circle.radius * maxf(
		body_shape.global_transform.x.length(), body_shape.global_transform.y.length()
	)
	var center := to_local(body_shape.global_position)
	if pattern == Pattern.RING:
		# The player's entire body must fit inside the hole to be safe.
		return center.length() <= radius + body_radius and center.length() + body_radius >= inner_radius
	# Damage still uses the flower geometry, including the player's body edges.
	var polygon := pattern_points(radius)
	if Geometry2D.is_point_in_polygon(center, polygon):
		return true
	for index in range(polygon.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(
			center, polygon[index], polygon[(index + 1) % polygon.size()]
		)
		if nearest.distance_squared_to(center) <= body_radius * body_radius:
			return true
	return false


func pattern_points(size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if pattern == Pattern.PETAL:
		var start := minf(18.0, size * 0.15)
		var width := petal_half_width * size / radius
		for index in range(25):
			var progress := float(index) / 24.0
			points.append(Vector2(lerpf(start, size, progress), sin(PI * progress) * width))
		for index in range(23, 0, -1):
			var progress := float(index) / 24.0
			points.append(Vector2(lerpf(start, size, progress), -sin(PI * progress) * width))
	else:
		for index in range(80):
			var angle := TAU * float(index) / 80.0
			var lobe := 0.78 + 0.22 * cos(angle * 5.0)
			points.append(Vector2.RIGHT.rotated(angle) * size * lobe)
	return points


func _ready() -> void:
	super._ready()
	# The spawner sets lane width and ring radius immediately after add_child().
	# Initialize after those final parameters and the world transform are applied.
	setup_particle_batch.call_deferred()


func setup_particle_batch() -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return
	if shared_particle_mesh == null:
		shared_particle_mesh = QuadMesh.new()
		shared_particle_mesh.size = Vector2(2.0, 2.0)

	var count := 280
	if pattern == Pattern.RING:
		count = 720
	elif pattern == Pattern.PETAL:
		count = 220
	var maximum_count := int(float(count) * 1.5)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_custom_data = true
	batch.mesh = shared_particle_mesh
	# Shader motion is invisible to CPU culling. Include the entire attack and burst.
	var extent := maxf(radius, petal_half_width) + maxf(impact_lifetime, 0.0) * 72.0 + 16.0
	batch.custom_aabb = AABB(Vector3(-extent, -extent, -1.0), Vector3(extent * 2.0, extent * 2.0, 2.0))
	batch.instance_count = maximum_count
	batch.visible_instance_count = count
	# Upload fixed seeds once. No per-particle script work is needed during animation.
	for index in range(maximum_count):
		var seed_index := float(index + 1)
		batch.set_instance_transform_2d(index, Transform2D.IDENTITY)
		batch.set_instance_custom_data(index, Color(
			fposmod(seed_index * 0.618033989, 1.0),
			fposmod(seed_index * 0.754877666, 1.0),
			fposmod(seed_index * 0.569840291, 1.0),
			fposmod(seed_index * 0.438579021, 1.0)
		))

	particle_material = ShaderMaterial.new()
	particle_material.shader = PARTICLE_SHADER
	particle_material.set_shader_parameter("pattern", int(pattern))
	particle_material.set_shader_parameter("radius", radius)
	particle_material.set_shader_parameter("inner_radius", inner_radius)
	particle_material.set_shader_parameter("petal_half_width", petal_half_width)
	particle_material.set_shader_parameter("flowing_petals", flowing_petals)
	particle_material.set_shader_parameter("warning_seconds", warning_seconds)
	particle_material.set_shader_parameter("impact_lifetime", impact_lifetime)
	particle_material.set_shader_parameter("main_color", main_color)
	particle_material.set_shader_parameter("orange", petal_colors[0])
	particle_material.set_shader_parameter("blue", petal_colors[1])
	particle_material.set_shader_parameter("purple", petal_colors[2])

	particle_batch = MultiMeshInstance2D.new()
	particle_batch.name = "PetalParticles"
	particle_batch.multimesh = batch
	particle_batch.material = particle_material
	add_child(particle_batch)
	update_visuals()


func update_visuals() -> void:
	if particle_material == null:
		return
	particle_material.set_shader_parameter("phase", Vector3(age, impact_age, 1.0 if detonated else 0.0))
	if detonated and not showing_impact:
		showing_impact = true
		particle_batch.multimesh.visible_instance_count = particle_batch.multimesh.instance_count


func _draw() -> void:
	# Suppress the base boss's solid telegraph; the child renders all flower visuals.
	pass
