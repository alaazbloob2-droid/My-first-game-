extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemy_ship.tscn")

var wave := 0
var score := 0
var game_over := false

var _pending_spawn := 0
var _alive_count := 0

@onready var player: CharacterBody2D = $Player
@onready var enemies: Node2D = $Enemies
@onready var hud: CanvasLayer = $HUD
@onready var water: ColorRect = $WaterLayer/Water


func _ready() -> void:
	player.died.connect(_on_player_died)
	player.health_changed.connect(hud.set_health)
	_next_wave()


func _process(_delta: float) -> void:
	if is_instance_valid(player):
		water.material.set_shader_parameter("cam_pos", player.global_position)


func _next_wave() -> void:
	wave += 1
	hud.set_wave(wave)
	hud.show_message("WAVE %d" % wave, "Sink every enemy ship")
	_pending_spawn = 2 + wave
	_spawn_wave()


func _spawn_wave() -> void:
	while _pending_spawn > 0 and not game_over:
		await get_tree().create_timer(0.7).timeout
		if game_over:
			return
		_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate()
	enemy.is_big = wave >= 2 and randf() < clampf(0.15 + 0.05 * wave, 0.0, 0.5)
	enemy.died.connect(_on_enemy_died)
	var angle := randf() * TAU
	enemy.position = player.global_position + Vector2.RIGHT.rotated(angle) * randf_range(650.0, 900.0)
	enemies.add_child(enemy)
	_alive_count += 1
	_pending_spawn -= 1


func _on_enemy_died(score_value: int) -> void:
	score += score_value
	hud.set_score(score)
	_alive_count -= 1
	if not game_over and _pending_spawn <= 0 and _alive_count <= 0:
		hud.show_message("WAVE CLEAR", "")
		await get_tree().create_timer(2.0).timeout
		if not game_over:
			_next_wave()


func _on_player_died() -> void:
	game_over = true
	hud.show_message("GAME OVER", "Press R to restart", false)


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
