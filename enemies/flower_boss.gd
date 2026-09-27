extends "res://enemies/telegraph_boss.gd"

const FLOWER_TELEGRAPH = preload("res://enemies/flower_telegraph.gd")
enum FloralAttack { BLOOM_RING, PETAL_BURST, PETAL_STREAM, BLOOM_TRAIL }

@export_group("Flower Colors")
@export var orange: Color = Color(1.0, 0.43, 0.08)
@export var blue: Color = Color(0.12, 0.58, 1.0)
@export var purple: Color = Color(0.64, 0.22, 1.0)

@export_group("Bloom Ring")
@export var bloom_outer_radius: float = 145.0
@export var bloom_safe_radius: float = 72.0
@export var bloom_warning: float = 1.25
@export var bloom_damage: float = 25.0

@export_group("Petal Burst")
@export_range(3, 10, 1) var petal_count: int = 6
@export var petal_length: float = 210.0
@export var petal_half_width: float = 36.0
@export var petal_warning: float = 1.2
@export var petal_damage: float = 22.0

@export_group("Petal Stream")
@export_range(1, 12, 1) var stream_count: int = 7
@export_range(20.0, 180.0, 1.0) var stream_arc: float = 110.0
@export var stream_length: float = 250.0
@export var stream_half_width: float = 23.0
@export var stream_interval: float = 0.18
@export var stream_warning: float = 0.95
@export var stream_damage: float = 18.0

@export_group("Trailing Garden")
@export_range(1, 8, 1) var garden_count: int = 5
@export var garden_radius: float = 48.0
@export var garden_interval: float = 0.4
@export var garden_warning: float = 1.1
@export var garden_damage: float = 18.0

var floral_attack: FloralAttack = FloralAttack.BLOOM_RING
var next_floral_attack: FloralAttack = FloralAttack.BLOOM_RING
var marks_placed: int = 0
var cast_origin: Vector2
var cast_direction: float = 0.0


func _ready() -> void:
	idle_tint = Color.WHITE
	super._ready()
	boss_sprite.modulate = idle_tint
	$FacingIndicator/Arrow.color = orange
	# Duplicate styles so this instance cannot recolor the final boss's HUD.
	var health_bar := $BossHUD/Root/Panel/Health as ProgressBar
	var health_style := health_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	health_style.bg_color = purple
	health_bar.add_theme_stylebox_override("fill", health_style)
	var cast_bar := $BossHUD/Root/Panel/CastProgress as ProgressBar
	var cast_style := cast_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	cast_style.bg_color = blue
	cast_bar.add_theme_stylebox_override("fill", cast_style)
	$BossHUD/Root/Panel/CastName.add_theme_color_override("font_color", orange)


func begin_cast() -> void:
	state = State.CAST
	velocity = Vector2.ZERO
	cast_age = 0.0
	marks_placed = 0
	cast_origin = global_position
	cast_direction = facing.angle()
	floral_attack = next_floral_attack
	cast_parryable = floral_attack == FloralAttack.PETAL_STREAM
	match floral_attack:
		FloralAttack.BLOOM_RING:
			cast_name = "Bloom Ring"
			cast_duration = maxf(bloom_warning, 0.05)
			var ring := spawn_flower(cast_origin, FlowerTelegraph.Pattern.RING,
				bloom_outer_radius, bloom_warning, bloom_damage, orange)
			ring.inner_radius = clampf(bloom_safe_radius, 1.0, ring.radius - 1.0)
			next_floral_attack = FloralAttack.PETAL_BURST
			boss_sprite.modulate = Color.WHITE.lerp(orange, 0.3)
		FloralAttack.PETAL_BURST:
			cast_name = "Petal Burst"
			cast_duration = maxf(petal_warning, 0.05)
			for index in range(petal_count):
				var petal := spawn_flower(cast_origin, FlowerTelegraph.Pattern.PETAL,
					petal_length, petal_warning, petal_damage, blue)
				petal.petal_half_width = maxf(petal_half_width, 1.0)
				petal.global_rotation = cast_direction + TAU * float(index) / float(petal_count)
			next_floral_attack = FloralAttack.PETAL_STREAM
			boss_sprite.modulate = Color.WHITE.lerp(blue, 0.3)
		FloralAttack.PETAL_STREAM:
			cast_name = "Petal Stream"
			cast_duration = maxf(stream_warning, 0.05) + (stream_count - 1) * maxf(stream_interval, 0.05)
			place_stream_mark()
			next_floral_attack = FloralAttack.BLOOM_TRAIL
			boss_sprite.modulate = Color.WHITE.lerp(purple, 0.3)
		FloralAttack.BLOOM_TRAIL:
			cast_name = "Trailing Garden"
			cast_duration = maxf(garden_warning, 0.05) + (garden_count - 1) * maxf(garden_interval, 0.05)
			place_garden_mark()
			next_floral_attack = FloralAttack.BLOOM_RING
			boss_sprite.modulate = Color.WHITE.lerp(orange, 0.2)


func advance_cast() -> void:
	if floral_attack == FloralAttack.PETAL_STREAM:
		while marks_placed < stream_count and cast_age >= marks_placed * maxf(stream_interval, 0.05):
			place_stream_mark()
	elif floral_attack == FloralAttack.BLOOM_TRAIL:
		while marks_placed < garden_count and cast_age >= marks_placed * maxf(garden_interval, 0.05):
			place_garden_mark()


func place_stream_mark() -> void:
	# Each bud gathers for a full warning, then extends at the hit/parry moment.
	var progress := float(marks_placed) / float(stream_count - 1) if stream_count > 1 else 0.5
	var petal := spawn_flower(cast_origin, FlowerTelegraph.Pattern.PETAL,
		stream_length, stream_warning, stream_damage, purple)
	petal.petal_half_width = maxf(stream_half_width, 1.0)
	petal.global_rotation = cast_direction + deg_to_rad(stream_arc) * (progress - 0.5)
	petal.flowing_petals = true
	petal.parryable = true
	marks_placed += 1


func place_garden_mark() -> void:
	# Snapshot the player's position; marked flowers never chase them afterward.
	if has_line_of_sight():
		var colors: Array[Color] = [orange, blue, purple]
		var flower := spawn_flower(target.global_position, FlowerTelegraph.Pattern.FLOWER,
			garden_radius, garden_warning, garden_damage, colors[marks_placed % colors.size()])
		flower.global_rotation = float(marks_placed) * 0.45
	marks_placed += 1


func spawn_flower(center: Vector2, pattern: FlowerTelegraph.Pattern,
		size: float, warning: float, amount: float, color: Color) -> FlowerTelegraph:
	for index in range(active_telegraphs.size() - 1, -1, -1):
		if not is_instance_valid(active_telegraphs[index]):
			active_telegraphs.remove_at(index)
	var marker := FLOWER_TELEGRAPH.new() as FlowerTelegraph
	marker.pattern = pattern
	marker.radius = maxf(size, 2.0)
	marker.warning_seconds = maxf(warning, 0.05)
	marker.damage = amount
	marker.main_color = color
	marker.petal_colors = [orange, blue, purple]
	marker.attacker = self
	marker.target = target
	marker.obstruction_mask = sight_collision_mask
	marker.impact_lifetime = 0.55
	get_tree().current_scene.add_child(marker)
	marker.global_position = center
	active_telegraphs.append(marker)
	return marker
