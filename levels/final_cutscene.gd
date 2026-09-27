extends Control

@export_range(0.1, 10.0, 0.1) var fade_in_seconds: float = 2.0
@export_range(1.0, 120.0, 1.0) var display_seconds: float = 30.0
@export_range(0.1, 10.0, 0.1) var fade_out_seconds: float = 5.0

@onready var artwork: TextureRect = $Artwork
@onready var fade: ColorRect = $Fade
@onready var retry: Button = $Retry

func _ready() -> void:
	SoundEffects.stop_all()
	artwork.modulate.a = 0.0
	fade.modulate.a = 0.0
	retry.pressed.connect(show_credits)
	GameMusic.start_ending_music()
	var sequence := create_tween()
	sequence.tween_property(artwork, "modulate:a", 1.0, fade_in_seconds)
	sequence.tween_interval(display_seconds)
	# Fade into the credits' background color to avoid a flash on the scene change.
	sequence.tween_property(fade, "modulate:a", 1.0, fade_out_seconds)
	sequence.tween_callback(show_credits)

func show_credits() -> void:
	retry.disabled = true
	var error := get_tree().change_scene_to_file("res://levels/end_credits.tscn")
	if error != OK:
		retry.disabled = false
		retry.show()
		retry.grab_focus()
		push_error("Could not open the credits: %s" % error_string(error))
