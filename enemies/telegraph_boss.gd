extends Enemy

const TELEGRAPH = preload("res://enemies/boss_telegraph.gd")

enum State { IDLE, PURSUE, CAST, RECOVER }
enum Attack { SLAM, CLEAVE, BARRAGE }

@export_group("Boss")
@export var boss_name: String = "Ash Warden"
@export var engage_range: float = 280.0
@export var disengage_range: float = 650.0
@export var disengage_seconds: float = 3.0
@export var cast_range: float = 190.0
@export var attack_pause: float = 1.2
@export var recovery_seconds: float = 0.55
@export_flags_2d_physics var sight_collision_mask: int = 1

@export_group("Circle Slam")
@export var slam_radius: float = 105.0
@export var slam_warning: float = 1.15
@export var slam_damage: float = 25.0

@export_group("Cone Cleave")
@export var cleave_radius: float = 190.0
@export_range(10.0, 180.0, 1.0) var cleave_angle: float = 100.0
@export var cleave_warning: float = 1.0
@export var cleave_damage: float = 22.0

@export_group("Targeted Barrage")
@export var barrage_radius: float = 43.0
@export var barrage_warning: float = 1.1
@export var barrage_damage: float = 18.0
@export_range(1, 8, 1) var barrage_count: int = 3
@export var barrage_interval: float = 0.4

@onready var facing_indicator: Node2D = $FacingIndicator
@onready var boss_sprite: Sprite2D = $Sprite2D

var state: State = State.IDLE
var is_engaged: bool = false
var cast_name: String = ""
var cast_age: float = 0.0
var cast_duration: float = 1.0
var current_attack: Attack = Attack.SLAM
var next_attack: Attack = Attack.SLAM
var cooldown_left: float = 0.0
var recovery_left: float = 0.0
var disengage_left: float = 0.0
var barrage_placed: int = 0
var facing: Vector2 = Vector2.DOWN
var active_telegraphs: Array[BossTelegraph] = []


func _ready() -> void:
	super._ready()
	show_health_bar = false
	find_player()
	facing_indicator.global_rotation = facing.angle()


func find_player() -> void:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if health <= 0.0:
		return
	find_player()
	if not is_instance_valid(target) or target.health <= 0.0:
		end_encounter()
		return

	var distance := global_position.distance_to(target.global_position)
	if not is_engaged:
		if distance <= engage_range and has_line_of_sight():
			engage()
		else:
			velocity = Vector2.ZERO
			return

	if distance > disengage_range:
		disengage_left += delta
		if disengage_left >= disengage_seconds:
			end_encounter()
			return
	else:
		disengage_left = 0.0

	if stun_left > 0.0:
		stun_left = maxf(stun_left - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	match state:
		State.PURSUE:
			cooldown_left = maxf(cooldown_left - delta, 0.0)
			pursue(delta)
			if cooldown_left <= 0.0 and distance <= cast_range and has_line_of_sight():
				begin_cast()
		State.CAST:
			velocity = Vector2.ZERO
			move_and_slide()
			cast_age += delta
			if current_attack == Attack.BARRAGE:
				while (
					barrage_placed < barrage_count
					and cast_age >= barrage_placed * maxf(barrage_interval, 0.05)
				):
					place_barrage_mark()
			if cast_age >= cast_duration:
				state = State.RECOVER
				cast_name = ""
				recovery_left = recovery_seconds
				boss_sprite.modulate = Color(1.0, 0.5, 0.3)
		State.RECOVER:
			velocity = Vector2.ZERO
			move_and_slide()
			recovery_left = maxf(recovery_left - delta, 0.0)
			if recovery_left <= 0.0:
				state = State.PURSUE
				cooldown_left = attack_pause


func engage() -> void:
	is_engaged = true
	state = State.PURSUE
	cooldown_left = 0.8
	disengage_left = 0.0


func end_encounter() -> void:
	is_engaged = false
	state = State.IDLE
	cast_name = ""
	velocity = Vector2.ZERO
	cancel_telegraphs()


func has_line_of_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters2D.create(
		global_position, target.global_position, sight_collision_mask, [get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit["collider"] == target


func pursue(delta: float) -> void:
	var offset := target.global_position - global_position
	if offset.is_zero_approx():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	facing = offset.normalized()
	facing_indicator.global_rotation = facing.angle()
	if offset.length() <= stop_distance:
		velocity = Vector2.ZERO
	else:
		var steering := Vector2.ZERO
		for angle in [0.0, PI / 6.0, -PI / 6.0, PI / 3.0, -PI / 3.0, PI / 2.0, -PI / 2.0]:
			var candidate := facing.rotated(angle)
			if not test_move(global_transform, candidate * maxf(move_speed * delta, 14.0)):
				steering = candidate
				break
		velocity = steering * minf(move_speed, maxf(offset.length() - stop_distance, 0.0) / maxf(delta, 0.001))
	move_and_slide()


func begin_cast() -> void:
	state = State.CAST
	velocity = Vector2.ZERO
	cast_age = 0.0
	current_attack = next_attack
	boss_sprite.modulate = Color(1.0, 0.8, 0.45)
	match current_attack:
		Attack.SLAM:
			cast_name = "Seismic Slam"
			cast_duration = maxf(slam_warning, 0.05)
			spawn_telegraph(global_position, BossTelegraph.Shape.CIRCLE, slam_radius, slam_warning, slam_damage)
			next_attack = Attack.CLEAVE
		Attack.CLEAVE:
			cast_name = "Scorching Cleave"
			cast_duration = maxf(cleave_warning, 0.05)
			var marker := spawn_telegraph(
				global_position, BossTelegraph.Shape.CONE, cleave_radius, cleave_warning, cleave_damage
			)
			marker.global_rotation = facing.angle()
			marker.cone_angle = cleave_angle
			next_attack = Attack.BARRAGE
		Attack.BARRAGE:
			cast_name = "Cinder Rain"
			barrage_placed = 0
			cast_duration = maxf(barrage_warning, 0.05) + (barrage_count - 1) * maxf(barrage_interval, 0.05)
			place_barrage_mark()
			next_attack = Attack.SLAM


func place_barrage_mark() -> void:
	# Each mark locks onto the current position once. It never follows the player afterward.
	if has_line_of_sight():
		spawn_telegraph(
			target.global_position, BossTelegraph.Shape.CIRCLE,
			barrage_radius, barrage_warning, barrage_damage
		)
	barrage_placed += 1


func spawn_telegraph(
	center: Vector2, shape: BossTelegraph.Shape, size: float, warning: float, amount: float
) -> BossTelegraph:
	for index in range(active_telegraphs.size() - 1, -1, -1):
		if not is_instance_valid(active_telegraphs[index]):
			active_telegraphs.remove_at(index)
	var marker := TELEGRAPH.new() as BossTelegraph
	marker.shape = shape
	marker.radius = maxf(size, 1.0)
	marker.warning_seconds = maxf(warning, 0.05)
	marker.damage = amount
	marker.attacker = self
	marker.target = target
	marker.obstruction_mask = sight_collision_mask
	get_tree().current_scene.add_child(marker)
	marker.global_position = center
	active_telegraphs.append(marker)
	return marker


func cancel_telegraphs() -> void:
	for marker in active_telegraphs:
		if is_instance_valid(marker):
			marker.set_physics_process(false)
			marker.hide()
			marker.queue_free()
	active_telegraphs.clear()


func stun(duration: float) -> void:
	super.stun(duration)
	if duration <= 0.0:
		return
	cancel_telegraphs()
	cast_name = ""
	state = State.RECOVER if is_engaged else State.IDLE
	recovery_left = recovery_seconds
	boss_sprite.modulate = Color(1.0, 0.5, 0.3)


func take_damage(amount: float) -> void:
	super.take_damage(amount)
	if health <= 0.0:
		end_encounter()
	elif amount > 0.0 and not is_engaged:
		find_player()
		if is_instance_valid(target) and target.health > 0.0:
			engage()


func _exit_tree() -> void:
	cancel_telegraphs()
