extends AudioStreamPlayer

const TRACK = preload("res://assets/mondamusic-8-bit-retro-589114.mp3")

func _ready() -> void:
	var music := TRACK.duplicate() as AudioStreamMP3
	music.loop = true
	stream = music
	volume_db = -10.0

func start_music() -> void:
	# The autoload survives level changes, preserving the current playback position.
	if not playing:
		play()
