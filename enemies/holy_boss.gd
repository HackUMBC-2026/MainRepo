extends "res://enemies/telegraph_boss.gd"

const HOLY_TELEGRAPH = preload("res://enemies/holy_telegraph.gd")
enum HolyAttack { JUDGMENT_RAY, HALO_BURST, HEAVENS_RAIN, CROSS_OF_LIGHT, SERAPH_LANCES, SACRED_SHACKLE }

@export_group("Judgment Ray")
@export var ray_length: float = 340.0
@export var ray_half_width: float = 23.0
@export var ray_warning: float = 1.15
@export var ray_damage: float = 26.0

@export_group("Halo Burst")
@export var halo_safe_radius: float = 58.0
@export var halo_band_width: float = 45.0
@export_range(1, 5, 1) var halo_count: int = 3
@export var halo_interval: float = 0.3
@export var halo_warning: float = 1.2
@export var halo_damage: float = 22.0

@export_group("Heaven's Rain")
@export_range(1, 8, 1) var rain_count: int = 4
@export var rain_radius: float = 42.0
@export var rain_interval: float = 0.4
@export var rain_warning: float = 1.05
@export var rain_damage: float = 18.0

@export_group("Cross of Light")
@export var cross_radius: float = 165.0
@export var cross_half_width: float = 20.0
@export var cross_warning: float = 1.3
@export var cross_damage: float = 25.0

@export_group("Seraph's Lances")
@export_range(3, 9, 1) var lance_count: int = 5
@export_range(30.0, 180.0, 1.0) var lance_arc: float = 140.0
@export var lance_length: float = 260.0
@export var lance_half_width: float = 9.0
@export var lance_warning: float = 1.3
@export var lance_damage: float = 20.0

@export_group("Sacred Shackle")
@export var shackle_radius: float = 48.0
@export var shackle_warning: float = 1.3
@export var shackle_duration: float = 1.5
@export var shackle_release_grace: float = 0.4

var holy_attack: HolyAttack = HolyAttack.JUDGMENT_RAY
var next_holy_attack: HolyAttack = HolyAttack.JUDGMENT_RAY
var rain_placed: int = 0


func _ready() -> void:
	add_to_group("final_boss")
	idle_tint = Color(1.0, 0.97, 0.85)
	super._ready()
	boss_sprite.modulate = idle_tint
	$FacingIndicator/Arrow.color = HolyTelegraph.GOLD
	# Per-instance styles preserve the Level 2 boss's palette.
	var health_bar := $BossHUD/Root/Panel/Health as ProgressBar
	var health_style := health_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	health_style.bg_color = Color(0.85, 0.62, 0.14)
	health_bar.add_theme_stylebox_override("fill", health_style)
	var cast_bar := $BossHUD/Root/Panel/CastProgress as ProgressBar
	var cast_style := cast_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	cast_style.bg_color = HolyTelegraph.LIGHT
	cast_bar.add_theme_stylebox_override("fill", cast_style)
	$BossHUD/Root/Panel/CastName.add_theme_color_override("font_color", HolyTelegraph.GOLD)


func begin_cast() -> void:
	# Never start another attack while the player is bound, even after an interruption.
	if target.binding_time_left > 0.0:
		state = State.RECOVER
		recovery_left = target.binding_time_left + maxf(shackle_release_grace, 0.0)
		return
	state = State.CAST
	velocity = Vector2.ZERO
	cast_age = 0.0
	holy_attack = next_holy_attack
	cast_parryable = holy_attack == HolyAttack.JUDGMENT_RAY
	boss_sprite.modulate = HolyTelegraph.LIGHT
	match holy_attack:
		HolyAttack.JUDGMENT_RAY:
			cast_name = "Judgment Ray"
			cast_duration = maxf(ray_warning, 0.05)
			var ray := spawn_holy(global_position, HolyTelegraph.Pattern.BEAM,
				ray_length, ray_warning, ray_damage, ray_half_width)
			ray.global_rotation = facing.angle()
			ray.parryable = true
			next_holy_attack = HolyAttack.HALO_BURST
		HolyAttack.HALO_BURST:
			cast_name = "Halo Burst"
			cast_duration = maxf(halo_warning, 0.05) + (halo_count - 1) * maxf(halo_interval, 0.05)
			for index in range(halo_count):
				var inner := maxf(halo_safe_radius, 1.0) + float(index) * maxf(halo_band_width, 1.0)
				spawn_holy(global_position, HolyTelegraph.Pattern.RING,
					inner + maxf(halo_band_width, 1.0),
					maxf(halo_warning, 0.05) + float(index) * maxf(halo_interval, 0.05),
					halo_damage, 20.0, inner)
			next_holy_attack = HolyAttack.HEAVENS_RAIN
		HolyAttack.HEAVENS_RAIN:
			cast_name = "Heaven's Rain"
			rain_placed = 0
			cast_duration = maxf(rain_warning, 0.05) + (rain_count - 1) * maxf(rain_interval, 0.05)
			place_rain_mark()
			next_holy_attack = HolyAttack.CROSS_OF_LIGHT
		HolyAttack.CROSS_OF_LIGHT:
			cast_name = "Cross of Light"
			cast_duration = maxf(cross_warning, 0.05)
			# This cross snapshots a position and orientation; it never tracks afterward.
			var cross := spawn_holy(target.global_position, HolyTelegraph.Pattern.CROSS,
				cross_radius, cross_warning, cross_damage, cross_half_width)
			cross.global_rotation = facing.angle()
			next_holy_attack = HolyAttack.SERAPH_LANCES
		HolyAttack.SERAPH_LANCES:
			cast_name = "Seraph's Lances"
			cast_duration = maxf(lance_warning, 0.05)
			for index in range(lance_count):
				var fraction := float(index) / float(maxi(lance_count - 1, 1))
				var lance := spawn_holy(global_position, HolyTelegraph.Pattern.BEAM,
					lance_length, lance_warning, lance_damage, lance_half_width)
				lance.global_rotation = facing.angle() + deg_to_rad(lance_arc) * (fraction - 0.5)
			next_holy_attack = HolyAttack.SACRED_SHACKLE
		HolyAttack.SACRED_SHACKLE:
			# Remove any old hazards before the non-damaging binding attempt.
			cancel_telegraphs()
			cast_name = "Sacred Shackle"
			cast_duration = maxf(shackle_warning, 0.05)
			var seal := spawn_holy(target.global_position, HolyTelegraph.Pattern.SEAL,
				shackle_radius, shackle_warning, 0.0)
			seal.binding_applied.connect(on_binding_applied)
			next_holy_attack = HolyAttack.JUDGMENT_RAY


func advance_cast() -> void:
	if holy_attack == HolyAttack.HEAVENS_RAIN:
		while rain_placed < rain_count and cast_age >= rain_placed * maxf(rain_interval, 0.05):
			place_rain_mark()


func place_rain_mark() -> void:
	if has_line_of_sight():
		spawn_holy(target.global_position, HolyTelegraph.Pattern.CIRCLE,
			rain_radius, rain_warning, rain_damage)
	rain_placed += 1


func on_binding_applied() -> void:
	# Time this rest from the actual hit, not from the cast's estimated finish time.
	state = State.RECOVER
	cast_name = ""
	cast_parryable = false
	velocity = Vector2.ZERO
	recovery_left = maxf(recovery_left, target.binding_time_left + maxf(shackle_release_grace, 0.0))
	boss_sprite.modulate = idle_tint


func cancel_telegraphs() -> void:
	super.cancel_telegraphs()
	if is_instance_valid(target):
		target.clear_holy_binding(self)


func spawn_holy(center: Vector2, pattern: HolyTelegraph.Pattern,
		size: float, warning: float, amount: float, width: float = 20.0,
		inner: float = 0.0) -> HolyTelegraph:
	for index in range(active_telegraphs.size() - 1, -1, -1):
		if not is_instance_valid(active_telegraphs[index]):
			active_telegraphs.remove_at(index)
	var marker := HOLY_TELEGRAPH.new() as HolyTelegraph
	marker.pattern = pattern
	marker.radius = maxf(size, 2.0)
	marker.beam_half_width = maxf(width, 1.0)
	marker.inner_radius = clampf(inner, 0.0, marker.radius - 1.0)
	marker.warning_seconds = maxf(warning, 0.05)
	marker.damage = amount
	marker.binding_seconds = maxf(shackle_duration, 0.05)
	marker.attacker = self
	marker.target = target
	marker.obstruction_mask = sight_collision_mask
	marker.impact_lifetime = 0.4
	get_tree().current_scene.add_child(marker)
	marker.global_position = center
	active_telegraphs.append(marker)
	return marker
