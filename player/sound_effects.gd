extends Node

const SOUNDS = {
	"dash": preload("res://assets/dash.mp3"),
	"parry": preload("res://assets/parry.mp3"),
	"swing": preload("res://assets/player_and_enemy_sword_swing.mp3"),
	"flame_blade": preload("res://assets/sword_q_ability.mp3"),
	"flame_ring": preload("res://assets/sword_e_ability.mp3"),
	"flame_rush": preload("res://assets/sword_r_ability.mp3"),
	"flower_cast": preload("res://assets/flower_boss_cast.mp3"),
	"holy_cast": preload("res://assets/final_boss_spellcast.mp3"),
}

@export var effects_volume_db: float = -8.0
const VOICE_LIMIT: int = 12
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer2D] = []
var next_voice: int = 0

func _ready() -> void:
	for event in SOUNDS:
		var sound := SOUNDS[event].duplicate() as AudioStreamMP3
		sound.loop = false
		streams[event] = sound
	for index in range(VOICE_LIMIT):
		var voice := AudioStreamPlayer2D.new()
		voice.max_distance = 700.0
		voice.volume_db = effects_volume_db
		add_child(voice)
		voices.append(voice)

func play_at(event: String, origin: Vector2) -> void:
	if not streams.has(event):
		return
	var voice: AudioStreamPlayer2D = null
	for candidate in voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		# Bound simultaneous sounds during crowded fights.
		voice = voices[next_voice]
		next_voice = (next_voice + 1) % VOICE_LIMIT
	voice.stop()
	voice.stream = streams[event]
	voice.global_position = origin
	voice.volume_db = effects_volume_db
	voice.play()

func stop_all() -> void:
	for voice in voices:
		voice.stop()
