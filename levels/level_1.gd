extends Node2D

func _ready() -> void:
	var camera := get_viewport().get_camera_2d()
	if is_instance_valid(camera):
		camera.limit_left = -126
		camera.limit_top = -35
		camera.limit_right = 792
		camera.limit_bottom = 1021
