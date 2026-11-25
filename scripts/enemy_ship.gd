extends CharacterBody2D

signal died(score_value: int)

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

@export var max_health := 36
@export var score_value := 100
@export var speed := 150.0
@export var turn_speed := 1.8
@export var keep_distance := 240.0
@export var fire_range := 330.0
@export var fire_cooldown := 2.6
@export var bullet_damage := 8

var is_big := false

var health := 0

var _cooldown := 0.0
var _alive := true


func _ready() -> void:
	health = max_health
	_cooldown = randf_range(1.0, 2.5)
	if is_big:
		scale = Vector2(1.7, 1.7)
		health = 120
		speed = 95.0
		score_value = 250
		bullet_damage = 12
		fire_cooldown = 3.2


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	var player: Node2D = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return

	_cooldown -= delta
	var to_player: Vector2 = player.global_position - global_position
	var desired := to_player.angle()
	rotation = lerp_angle(rotation, desired, clampf(turn_speed * delta, 0.0, 1.0))

	var target_speed := speed if to_player.length() > keep_distance else speed * 0.35
	velocity = velocity.lerp(transform.x * target_speed, 1.0 - pow(0.05, delta))
	move_and_slide()

	if to_player.length() <= fire_range and _cooldown <= 0.0:
		_fire_broadside()
		_cooldown = fire_cooldown + randf_range(-0.4, 0.9)


func _fire_broadside() -> void:
	for side in [-1.0, 1.0]:
		var offsets: Array = [-12.0, 0.0, 12.0] if is_big else [-9.0, 9.0]
		for x in offsets:
			var bullet := BULLET_SCENE.instantiate()
			bullet.setup(
				(transform.y * side).rotated(randf_range(-0.06, 0.06)),
				bullet_damage,
				false
			)
			get_tree().current_scene.add_child(bullet)
			bullet.global_position = to_global(Vector2(x, side * 16.0))


func take_damage(amount: int) -> void:
	if not _alive:
		return

	health = maxi(0, health - amount)
	modulate = Color(2.0, 1.1, 1.1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)

	if health == 0:
		_die()


func _die() -> void:
	_alive = false
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.setup(1.9 if is_big else 1.2)
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	died.emit(score_value)
	queue_free()
