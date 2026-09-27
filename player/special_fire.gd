extends MultiMeshInstance2D

const FIRE_SHADER = preload("res://player/special_fire.gdshader")
var kind: int = 0
var reach: float = 150.0
var span: float = 20.0
var age: float = 0.0
var fire_material: ShaderMaterial

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	var extent := maxf(reach, span) + 80.0
	multimesh.custom_aabb = AABB(Vector3(-extent, -extent, -1.0), Vector3(extent * 2.0, extent * 2.0, 2.0))
	# Ring particles split between the moving rim and embers deposited behind it.
	multimesh.instance_count = 480 if kind == 0 else (70 if kind == 1 else (160 if kind == 3 else 72))
	for index in range(multimesh.instance_count):
		var seed := float(index + 1)
		multimesh.set_instance_transform_2d(index, Transform2D.IDENTITY)
		multimesh.set_instance_custom_data(index, Color(fposmod(seed * 0.618034, 1.0), fposmod(seed * 0.754878, 1.0), fposmod(seed * 0.569841, 1.0), fposmod(seed * 0.438579, 1.0)))
	fire_material = ShaderMaterial.new()
	fire_material.shader = FIRE_SHADER
	fire_material.set_shader_parameter("kind", kind)
	fire_material.set_shader_parameter("radius", reach)
	fire_material.set_shader_parameter("span", span)
	material = fire_material

func _process(delta: float) -> void:
	age += delta
	fire_material.set_shader_parameter("age", age)
	var lifetime := 1.1 if kind == 0 else 0.7
	if kind != 1 and age >= lifetime:
		queue_free()
