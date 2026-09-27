extends Node2D

@export var bar_width: float = 32.0
@export var bar_height: float = 5.0

@onready var enemy: Enemy = get_parent() as Enemy


func _process(_delta: float) -> void:
	visible = enemy.show_health_bar and enemy.health > 0.0
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(enemy) or enemy.max_health <= 0.0:
		return
	var rect := Rect2(Vector2(-bar_width * 0.5, -bar_height * 0.5), Vector2(bar_width, bar_height))
	draw_rect(rect.grow(1.0), Color(0.06, 0.04, 0.06, 0.95))
	draw_rect(rect, Color(0.25, 0.07, 0.08, 0.9))
	var fraction := clampf(enemy.health / enemy.max_health, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(bar_width * fraction, bar_height)), Color(0.95, 0.22, 0.2))
