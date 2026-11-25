extends CharacterBody2D

signal health_changed(health: int, max_health: int)
signal died

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

@export var max_health := 100
@export var forward_speed := 300.0
@export var reverse_speed := 130.0
@export var turn_speed := 2.6
@export var broadside_cooldown := 0.7
@export var bullet_damage := 12

var health := 0

var _cooldown := 0.0
var _alive := true


func _ready() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_cooldown -= delta
	var thrust := Input.get_axis("move_back", "move_forward")
	var turn := Input.get_axis("turn_left", "turn_right")
	rotation += turn * turn_speed * delta

	var speed := reverse_speed if thrust < 0.0 else forward_speed
	var target_velocity := transform.x * thrust * speed
	velocity = velocity.lerp(target_velocity, 1.0 - pow(0.02, delta))
	move_and_slide()

	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_fire_broadside()
		_cooldown = broadside_cooldown


func _fire_broadside() -> void:
	for side in [-1.0, 1.0]:
		for x in [-10.0, 10.0]:
			_spawn_bullet(side, x)


func _spawn_bullet(side: float, x: float) -> void:
	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = to_global(Vector2(x, side * 16.0))
	bullet.setup(
		(transform.y * side).rotated(randf_range(-0.04, 0.04)),
		bullet_damage,
		true
	)


func take_damage(amount: int) -> void:
	if not _alive:
		return

	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	modulate = Color(2.0, 1.1, 1.1)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)

	if health == 0:
		_die()


func _die() -> void:
	_alive = false
	collision_layer = 0
	_spawn_explosion(2.4)
	hide()
	set_physics_process(false)
	died.emit()


func _spawn_explosion(size: float) -> void:
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.setup(size)
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
