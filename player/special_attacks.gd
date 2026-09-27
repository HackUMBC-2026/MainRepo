extends Node2D

const FIRE = preload("res://player/special_fire.gd")
const WARP_VISUAL = preload("res://player/warp_visual.gd")
@export_group("Flaming Blade — Q")
@export var blade_cooldown: float = 5.0
@export var blade_duration: float = 5.0
@export var blade_damage_multiplier: float = 1.5
@export_group("Flame Ring — E")
@export var ring_cooldown: float = 10.0
@export var ring_radius: float = 150.0
@export var ring_damage: float = 2.0
@export var ring_stun: float = 0.5
@export_group("Flame Rush — R")
@export var rush_cooldown: float = 20.0
@export var rush_speed: float = 1800.0
@export var rush_damage: float = 3.0

@onready var player: Player = get_parent() as Player
var cooldowns := Vector3.ZERO
var blade_left: float = 0.0
var rushing: bool = false
var destination := Vector2.ZERO
var rush_hits: Dictionary = {}
var ghost_distance: float = 0.0
var blade_fire: FIRE
var cooldown_label: Label
var ring_age: float = -1.0
var ring_origin := Vector2.ZERO
var ring_hits: Dictionary = {}

func _ready() -> void:
	var sword := player.get_node("SwordAnchor (Node2D)/Sword (Node2D)")
	blade_fire = FIRE.new()
	blade_fire.kind = 1
	blade_fire.span = 44.0
	blade_fire.position = Vector2(-0.86, -27.0)
	blade_fire.visible = false
	sword.add_child(blade_fire)
	var hud := CanvasLayer.new()
	add_child(hud)
	cooldown_label = Label.new()
	cooldown_label.position = Vector2(180.0, 337.0)
	cooldown_label.add_theme_font_size_override("font_size", 12)
	cooldown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cooldown_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(cooldown_label)
	player.died.connect(_on_death)

func sword_damage_multiplier() -> float:
	return blade_damage_multiplier if blade_left > 0.0 else 1.0

# Called before ordinary movement so only one movement system runs per tick.
func tick(delta: float) -> bool:
	cooldowns = Vector3(maxf(0.0, cooldowns.x - delta), maxf(0.0, cooldowns.y - delta), maxf(0.0, cooldowns.z - delta))
	if blade_left > 0.0:
		blade_left = maxf(0.0, blade_left - delta)
		if blade_left <= 0.0:
			cooldowns.x = blade_cooldown
	if Input.is_action_just_pressed("flame_blade") and blade_left <= 0.0 and cooldowns.x <= 0.0:
		blade_left = blade_duration
	if Input.is_action_just_pressed("flame_ring") and cooldowns.y <= 0.0:
		cooldowns.y = ring_cooldown
		ring_origin = player.global_position
		ring_age = 0.0
		ring_hits.clear()
		spawn_fire(ring_origin, 0, ring_radius)
	if ring_age >= 0.0:
		ring_age += delta
		var shape := CircleShape2D.new()
		shape.radius = ring_radius * minf(ring_age / 0.22, 1.0)
		hit_shape(shape, Transform2D(0.0, ring_origin), ring_damage, ring_stun, ring_hits, true)
		if ring_age >= 0.22:
			ring_age = -1.0
	blade_fire.visible = blade_left > 0.0
	var blade_status := "Burning %.1fs" % blade_left if blade_left > 0.0 else cooldown_text(cooldowns.x)
	cooldown_label.text = "Q  %s     E  %s     R  %s" % [blade_status, cooldown_text(cooldowns.y), cooldown_text(cooldowns.z)]
	if player.binding_time_left > 0.0 or player.heavy_attack_locked:
		if rushing:
			finish_rush(false)
		return false
	if Input.is_action_just_pressed("flame_rush") and cooldowns.z <= 0.0 and not player.is_dashing:
		destination = player.get_global_mouse_position()
		if player.global_position.distance_to(destination) > 1.0:
			rushing = true
			rush_hits.clear()
			cooldowns.z = rush_cooldown
			player.is_dashing = true
			player.is_sprinting = false
			player.dash_vector = player.global_position.direction_to(destination)
			player.update_facing(player.dash_vector)
			ghost_distance = 0.0
			spawn_warp_burst(player.global_position)
			spawn_warp_ghost()
			player.sword.start_camera_shake()
	if rushing:
		move_rush(delta)
		return true
	return false

func cooldown_text(seconds: float) -> String:
	return "Ready" if seconds <= 0.0 else "%.1fs" % seconds

func enemy_exclusions() -> Array[RID]:
	var excluded: Array[RID] = [player.get_rid()]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Enemy:
			excluded.append(enemy.get_rid())
	return excluded

func move_rush(delta: float) -> void:
	var start := player.global_position
	var motion := (destination - start).limit_length(maxf(rush_speed, 1.0) * delta)
	var collider := player.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.motion = motion
	query.margin = 0.08
	query.collision_mask = player.collision_mask
	query.exclude = enemy_exclusions()
	# Sweep the full body against walls, excluding enemies only for this query.
	# A cast ignores existing overlaps; stop rather than cross a wall if already inside one.
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		finish_rush(false)
		return
	var fractions := get_world_2d().direct_space_state.cast_motion(query)
	var travel := motion * fractions[0]
	player.global_position += travel
	player.velocity = travel / maxf(delta, 0.001)
	if travel.length() > 0.01:
		var capsule := CapsuleShape2D.new()
		capsule.radius = 16.0
		capsule.height = travel.length() + 32.0
		hit_shape(capsule, Transform2D(travel.angle() - PI * 0.5, start + travel * 0.5), rush_damage, 0.0, rush_hits)
		spawn_fire(start, 2, travel.length(), travel.angle())
		var streak := WARP_VISUAL.new()
		streak.span = travel.length()
		get_tree().current_scene.add_child(streak)
		streak.global_position = start
		streak.global_rotation = travel.angle()
		ghost_distance += travel.length()
		if ghost_distance >= 36.0:
			ghost_distance = fmod(ghost_distance, 36.0)
			spawn_warp_ghost()
	if fractions[0] < 1.0 or player.global_position.distance_to(destination) <= 0.5:
		finish_rush()

func finish_rush(arrived: bool = true) -> void:
	if rushing and arrived and player.health > 0.0:
		spawn_warp_burst(player.global_position)
		player.sword.start_camera_shake()
	rushing = false
	player.is_dashing = false
	player.dash_movement_lock_time = 0.0
	player.velocity = Vector2.ZERO

func spawn_warp_burst(origin: Vector2) -> void:
	spawn_fire(origin, 3, 54.0)
	var burst := WARP_VISUAL.new()
	burst.burst = true
	get_tree().current_scene.add_child(burst)
	burst.global_position = origin
	burst.global_rotation = player.dash_vector.angle()

func spawn_warp_ghost() -> void:
	var afterimage := WARP_VISUAL.new()
	get_tree().current_scene.add_child(afterimage)
	afterimage.global_position = player.global_position
	afterimage.z_index = player.z_index
	afterimage.capture_sprite(player.sprite, player.dash_vector)

func hit_shape(shape: Shape2D, transform: Transform2D, damage: float, stun_seconds: float, hit: Dictionary, check_walls: bool = false) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = transform
	query.collision_mask = player.collision_mask
	var excluded: Array[RID] = [player.get_rid()]
	while true:
		query.exclude = excluded
		var results := get_world_2d().direct_space_state.intersect_shape(query, 32)
		for result in results:
			excluded.append(result["rid"])
			var enemy = result["collider"]
			if not enemy is Enemy or enemy.is_queued_for_deletion() or enemy.health <= 0.0 or hit.has(enemy):
				continue
			if check_walls:
				var ray := PhysicsRayQueryParameters2D.create(ring_origin, enemy.global_position, player.collision_mask, enemy_exclusions())
				if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
					continue
			else:
				# The damage capsule is slightly wider than the player. Keep it from
				# clipping enemies on the far side of a thin wall or corner.
				var capsule := shape as CapsuleShape2D
				var half_segment := (capsule.height - capsule.radius * 2.0) * 0.5
				var nearest := Geometry2D.get_closest_point_to_segment(enemy.global_position, transform * Vector2(0.0, -half_segment), transform * Vector2(0.0, half_segment))
				var ray := PhysicsRayQueryParameters2D.create(nearest, enemy.global_position, player.collision_mask, enemy_exclusions())
				if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
					continue
			hit[enemy] = true
			enemy.take_damage(damage)
			if enemy.health > 0.0 and stun_seconds > 0.0:
				enemy.stun(stun_seconds)
		if results.size() < 32:
			break

func spawn_fire(origin: Vector2, kind: int, size: float, angle: float = 0.0) -> void:
	var effect := FIRE.new()
	effect.kind = kind
	effect.reach = size
	effect.span = size
	get_tree().current_scene.add_child(effect)
	effect.global_position = origin
	effect.global_rotation = angle

func _on_death() -> void:
	finish_rush(false)
	blade_left = 0.0
	blade_fire.hide()
	cooldown_label.hide()
