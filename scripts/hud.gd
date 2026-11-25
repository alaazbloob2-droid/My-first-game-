extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var message: Label = %Message
@onready var sub_message: Label = %SubMessage


func set_health(value: int, max_value: int) -> void:
	health_bar.max_value = max_value
	health_bar.value = value


func set_score(value: int) -> void:
	score_label.text = "SCORE %d" % value


func set_wave(value: int) -> void:
	wave_label.text = "WAVE %d" % value


func show_message(text: String, sub: String, fade: bool = true) -> void:
	message.text = text
	sub_message.text = sub
	message.modulate.a = 1.0
	sub_message.modulate.a = 1.0
	if fade:
		var tween := create_tween()
		tween.tween_interval(1.1)
		tween.tween_property(message, "modulate:a", 0.0, 0.4)
		tween.parallel().tween_property(sub_message, "modulate:a", 0.0, 0.4)
