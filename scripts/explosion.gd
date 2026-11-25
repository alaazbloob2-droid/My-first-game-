extends Node2D


func setup(size: float) -> void:
	scale = Vector2(size, size)


func _ready() -> void:
	$Sparks.emitting = true
	var flash: Polygon2D = $Flash
	flash.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector2(1.2, 1.2), 0.18)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.25)
	await get_tree().create_timer(1.4).timeout
	queue_free()
