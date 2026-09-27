extends Control

@onready var play_again: Button = $Center/Content/Buttons/PlayAgain
@onready var error_label: Label = $Center/Content/Error


func _ready() -> void:
	play_again.pressed.connect(restart_game)
	$Center/Content/Buttons/Quit.pressed.connect(quit_game)
	play_again.grab_focus()


func restart_game() -> void:
	play_again.disabled = true
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		play_again.disabled = false
		error_label.show()
		play_again.grab_focus()
		push_error("Could not restart after victory: %s" % error_string(error))


func quit_game() -> void:
	get_tree().quit()
