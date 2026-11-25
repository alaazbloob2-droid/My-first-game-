extends Area2D

const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

var direction := Vector2.RIGHT
var damage := 10
var from_player := true

var _speed := 520.0
var _lifetime := 1.5
var _dead := false


func setup(dir: Vector2, dmg: int, player_owned: bool) -> void:
	direction = dir.normalized()
	damage = dmg
	from_player = player_owned


func _ready() -> void:
	if from_player:
		collision_layer = 4
		collision_mask = 2
	else:
		collision_layer = 8
		collision_mask = 1
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * _speed * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _dead:
		return

	var valid_target: bool = (
		(from_player and body.is_in_group("enemy"))
		or (not from_player and body.is_in_group("player"))
	)
	if not valid_target:
		return

	_dead = true
	if body.has_method("take_damage"):
		body.take_damage(damage)

	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.setup(0.5)
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	queue_free()
