extends AudioStreamPlayer

const TRACK = preload("res://assets/mondamusic-8-bit-retro-589114.mp3")
const ENDING_TRACK = preload("res://assets/montogoronto-a-night-full-of-stars-peaceful-electronic-8-bitpiano-track-321551.mp3")
var selected_track: AudioStreamMP3

func _ready() -> void:
	volume_db = -10.0

func start_music() -> void:
	play_track(TRACK)

func start_ending_music() -> void:
	play_track(ENDING_TRACK)

func play_track(track: AudioStreamMP3) -> void:
	if selected_track != track:
		stop()
		selected_track = track
		var music := track.duplicate() as AudioStreamMP3
		music.loop = true
		stream = music
	# The autoload survives level changes, preserving the current playback position.
	if not playing:
		play()
