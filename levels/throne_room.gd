extends Node2D

const FINAL_CUTSCENE = preload("res://levels/final_cutscene.tscn")

@export var final_boss: Enemy
@onready var completion: Label = $HUD/Completion

var victory_pending: bool = false


func _ready() -> void:
	var camera := $Player/Camera2D as Camera2D
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 768
	camera.limit_bottom = 960
	# An explicit reference survives editor renames; the group also supports older scenes.
	if not is_instance_valid(final_boss):
		for candidate in get_tree().get_nodes_in_group("final_boss"):
			if candidate is Enemy and is_ancestor_of(candidate):
				final_boss = candidate as Enemy
				break
	if not is_instance_valid(final_boss):
		push_warning("Level3 has no final boss. Assign Final Boss in the level's Inspector.")
		return
	final_boss.tree_exiting.connect(on_final_boss_exiting)


func on_final_boss_exiting() -> void:
	# Changing scenes also removes the boss; only a defeat completes the level.
	if is_instance_valid(final_boss) and final_boss.health <= 0.0 and get_tree().current_scene == self and not victory_pending:
		victory_pending = true
		# Finish freeing the boss before replacing the scene and its combat objects.
		show_cutscene.call_deferred()


func show_cutscene() -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	var error := get_tree().change_scene_to_packed(FINAL_CUTSCENE)
	if error != OK:
		# Keep a completion message visible if the cutscene cannot be opened.
		completion.show()
		push_error("Could not open the final cutscene: %s" % error_string(error))
