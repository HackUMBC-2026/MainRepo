extends ProgressBar

@export var player: Player


func _process(_delta: float) -> void:
	if is_instance_valid(player):
		max_value = 240.0
		value = player.stamina
