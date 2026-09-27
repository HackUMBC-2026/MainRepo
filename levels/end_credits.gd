extends Control

## Edit this text on the EndCredits root in the Inspector. Blank lines separate entries; BBCode links are supported.
@export_multiline var credits_text: String = "Sound effects\nDRAGON-STUDIO\n\nBackground music\n[url=https://pixabay.com/users/mondamusic-54713575/][b]MondaMusic[/b][/url]\n\nEnding music\n[b]Montogoronto[/b]\nA Night Full of Stars"
@export_range(10.0, 120.0, 1.0) var scroll_speed: float = 45.0

@onready var content: VBoxContainer = $Clip/Content
@onready var credits: RichTextLabel = $Clip/Content/Credits
@onready var continue_button: Button = $Continue
@onready var error_label: Label = $Error
var leaving: bool = false
var auto_advance: bool = true

func _ready() -> void:
	GameMusic.start_ending_music()
	SoundEffects.stop_all()
	credits.text = "[center]" + credits_text + "[/center]"
	credits.meta_clicked.connect(open_credit_link)
	content.position.y = size.y
	continue_button.pressed.connect(show_end_menu)
	continue_button.grab_focus()

func open_credit_link(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("https://"):
		OS.shell_open(url)

func _process(delta: float) -> void:
	if leaving or not auto_advance:
		return
	content.position.y -= scroll_speed * delta
	if content.position.y + content.size.y < -24.0:
		show_end_menu()

func show_end_menu() -> void:
	if leaving:
		return
	leaving = true
	continue_button.disabled = true
	var error := get_tree().change_scene_to_file("res://levels/victory_screen.tscn")
	if error != OK:
		leaving = false
		auto_advance = false
		continue_button.disabled = false
		error_label.show()
		continue_button.grab_focus()
		push_error("Could not open the end menu: %s" % error_string(error))
