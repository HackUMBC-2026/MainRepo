extends CanvasLayer

@onready var boss = get_parent()
@onready var panel: Control = $Root/Panel
@onready var name_label: Label = $Root/Panel/BossName
@onready var health_bar: ProgressBar = $Root/Panel/Health
@onready var cast_label: Label = $Root/Panel/CastName
@onready var cast_bar: ProgressBar = $Root/Panel/CastProgress


func _process(_delta: float) -> void:
	panel.visible = boss.is_engaged and boss.health > 0.0
	if not panel.visible:
		return
	name_label.text = "%s   %d / %d" % [boss.boss_name, ceili(boss.health), ceili(boss.max_health)]
	health_bar.max_value = maxf(boss.max_health, 1.0)
	health_bar.value = boss.health
	var casting: bool = not boss.cast_name.is_empty()
	cast_bar.visible = casting
	cast_label.text = "%s  —  DODGE" % boss.cast_name if casting else ""
	cast_bar.value = clampf(boss.cast_age / maxf(boss.cast_duration, 0.05), 0.0, 1.0)
