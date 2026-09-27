@tool
extends Area2D

@export_file("*.tscn") var next_level: String = ""
@export var require_clear_level: bool = false
@export var stairs_texture: Texture2D:
	set(value):
		stairs_texture = value
		if is_node_ready():
			update_appearance()
@export var texture_scale: Vector2 = Vector2.ONE:
	set(value):
		texture_scale = value
		if is_node_ready():
			update_appearance()
@export var texture_offset: Vector2 = Vector2.ZERO:
	set(value):
		texture_offset = value
		if is_node_ready():
			update_appearance()
@export var trigger_size: Vector2 = Vector2(36.0, 40.0):
	set(value):
		trigger_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if is_node_ready():
			update_trigger()

var changing_level: bool = false
var nearby_player: Player
var gate_check_left: float = 0.0


func _ready() -> void:
	update_appearance()
	update_trigger()
	set_physics_process(false)
	if not Engine.is_editor_hint():
		body_entered.connect(on_body_entered)
		body_exited.connect(on_body_exited)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(nearby_player) or nearby_player.health <= 0.0:
		$LockedHint.hide()
		set_physics_process(false)
		return
	gate_check_left -= delta
	if gate_check_left <= 0.0:
		gate_check_left = 0.15
		try_enter_level()


func update_appearance() -> void:
	var sprite := $Sprite2D as Sprite2D
	sprite.texture = stairs_texture
	sprite.scale = texture_scale
	sprite.position = texture_offset
	queue_redraw()


func update_trigger() -> void:
	# Each stairs instance gets its own shape, so changing one does not resize the others.
	var shape := RectangleShape2D.new()
	shape.size = trigger_size
	$CollisionShape2D.shape = shape
	queue_redraw()


func on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if body.health <= 0.0:
		return
	nearby_player = body as Player
	gate_check_left = 0.15
	set_physics_process(true)
	try_enter_level()


func on_body_exited(body: Node2D) -> void:
	if body == nearby_player:
		nearby_player = null
		$LockedHint.hide()
		set_physics_process(false)


func living_enemies_remaining() -> int:
	if not require_clear_level:
		return 0
	var level := get_tree().current_scene
	var remaining := 0
	for candidate in get_tree().get_nodes_in_group("enemies"):
		if candidate is Enemy and level.is_ancestor_of(candidate) and candidate.health > 0.0:
			remaining += 1
	return remaining


func show_locked_hint(remaining: int) -> void:
	$LockedHint.text = "Defeat all enemies\n%d remaining" % remaining
	$LockedHint.show()


func try_enter_level() -> void:
	if changing_level or not is_instance_valid(nearby_player) or nearby_player.health <= 0.0:
		return
	var remaining := living_enemies_remaining()
	if remaining > 0:
		show_locked_hint(remaining)
		return
	$LockedHint.hide()
	if next_level.is_empty():
		push_warning("Choose a Next Level on this stairs instance in the Inspector.")
		set_physics_process(false)
		return
	changing_level = true
	change_level.call_deferred()


func change_level() -> void:
	# Leave the physics callback before replacing the scene and its collision objects.
	if not is_instance_valid(nearby_player) or nearby_player.health <= 0.0 or not overlaps_body(nearby_player):
		changing_level = false
		return
	# Recheck in case another enemy spawned before the deferred transition.
	var remaining := living_enemies_remaining()
	if remaining > 0:
		changing_level = false
		show_locked_hint(remaining)
		return
	var error := get_tree().change_scene_to_file(next_level)
	if error != OK:
		changing_level = false
		set_physics_process(false)
		push_error("Stairs could not load '%s': %s" % [next_level, error_string(error)])


func _draw() -> void:
	if stairs_texture != null:
		return
	# Temporary steps remain visible in the editor and game until artwork is assigned.
	var rect := Rect2(-trigger_size * 0.5, trigger_size)
	draw_rect(rect, Color(0.12, 0.1, 0.08, 0.95))
	draw_rect(rect, Color(0.95, 0.72, 0.3), false, 2.0)
	for step in range(5):
		var depth := float(step + 1) / 6.0
		var width := trigger_size.x * lerpf(0.35, 0.8, depth)
		var y := rect.position.y + depth * trigger_size.y
		draw_line(Vector2(-width * 0.5, y), Vector2(width * 0.5, y), Color(0.9, 0.75, 0.5), 2.0)
