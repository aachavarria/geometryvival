extends Node2D

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_SCENE = preload("res://scenes/enemy.tscn")
const AGONES_SCENE = preload("res://addons/agones/agones_sdk.gd")

var _agones = null
const SHAPE_NAMES = ["Circle", "Square", "Triangle"]

var survival_time: float = 0.0
var spawn_interval: float = 1.5
var spawn_timer: float = 0.0
var enemy_id: int = 0
var difficulty_timer: float = 0.0
var game_over: bool = false

# Server-side damage cooldown per player
var damage_cooldown: Dictionary = {}
var health_timer: float = 0.0

@onready var players_node: Node2D = $Players
@onready var enemies_node: Node2D = $Enemies
@onready var time_label: Label = $HUD/TimeLabel
@onready var hp_label: Label = $HUD/HPLabel
@onready var shape_label: Label = $HUD/ShapeLabel
@onready var game_over_label: Label = $HUD/GameOverLabel
@onready var info_label: Label = $HUD/InfoLabel

func _ready():
	game_over_label.visible = false

	if multiplayer.is_server():
		if _is_dedicated_server():
			_agones = AGONES_SCENE.new()
			add_child(_agones)
			_agones.ready()

		# Dedicated server: don't spawn a player for the server itself
		if not _is_dedicated_server():
			_spawn_player(1)

		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_remove_player)
		info_label.text = "SERVER | Port %d" % NetworkManager.DEFAULT_PORT
	else:
		# Client arrived — ask server to spawn us
		_request_spawn.rpc_id(1)
		info_label.text = "CLIENT | ID: %d" % multiplayer.get_unique_id()

@rpc("any_peer", "reliable")
func _request_spawn():
	if not multiplayer.is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	if not players_node.has_node(str(id)):
		_spawn_player(id)

func _on_player_connected(id: int):
	if _agones: _agones.player_connect(str(id))

func _spawn_player(id: int):
	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = Vector2(640 + randf_range(-100, 100), 360 + randf_range(-50, 50))
	players_node.add_child(player, true)
	player.set_multiplayer_authority(id)
	print("[Game] Spawned player %d" % id)

func _is_dedicated_server() -> bool:
	return "--server" in OS.get_cmdline_args() or DisplayServer.get_name() == "headless"

func _remove_player(id: int):
	var player = players_node.get_node_or_null(str(id))
	if player:
		player.queue_free()
	damage_cooldown.erase(id)
	if _agones: _agones.player_disconnect(str(id))

func _physics_process(delta: float):
	survival_time += delta
	_update_hud()

	if not multiplayer.is_server():
		return
	if game_over:
		return

	# Agones health ping every 60 seconds
	health_timer += delta
	if health_timer >= 5.0:
		health_timer = 0.0
		if _agones: _agones.health()

	# Difficulty ramp: shorter spawn interval over time
	difficulty_timer += delta
	if difficulty_timer >= 10.0:
		difficulty_timer = 0.0
		spawn_interval = max(0.25, spawn_interval - 0.15)

	# Spawn enemies
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# Update damage cooldowns
	for pid in damage_cooldown.keys():
		damage_cooldown[pid] -= delta
		if damage_cooldown[pid] <= 0:
			damage_cooldown.erase(pid)

	# Collisions
	_check_collisions()
	_check_game_over()

func _spawn_enemy():
	var enemy = ENEMY_SCENE.instantiate()
	enemy.shape_type = randi() % 3
	enemy.speed = 80.0 + survival_time * 1.5

	# Spawn from a random screen edge
	var side = randi() % 4
	match side:
		0: enemy.position = Vector2(randf_range(0, 1280), -30)
		1: enemy.position = Vector2(randf_range(0, 1280), 750)
		2: enemy.position = Vector2(-30, randf_range(0, 720))
		3: enemy.position = Vector2(1310, randf_range(0, 720))

	enemy.name = "e%d" % enemy_id
	enemy_id += 1
	enemies_node.add_child(enemy, true)

func _check_collisions():
	var kill_radius = 32.0
	var enemies_to_kill: Array[Node2D] = []

	for player in players_node.get_children():
		if not (player is Node2D) or not player.has_method("get_shape"):
			continue
		if player.is_dead:
			continue

		var pid = int(str(player.name))
		var p_shape = player.get_shape()

		for enemy in enemies_node.get_children():
			if not (enemy is Node2D):
				continue
			if enemies_to_kill.has(enemy):
				continue

			var dist = player.position.distance_to(enemy.position)
			if dist < kill_radius:
				var e_shape = enemy.shape_type
				# Kill rule: shape X kills (X+1)%3
				var kills_shape = (p_shape + 1) % 3
				if e_shape == kills_shape:
					# Player kills this enemy
					enemies_to_kill.append(enemy)
				else:
					# Enemy damages player (with cooldown)
					if not damage_cooldown.has(pid):
						damage_cooldown[pid] = 0.5
						player.take_damage.rpc(1)
					enemies_to_kill.append(enemy)

	for enemy in enemies_to_kill:
		enemy.queue_free()

func _check_game_over():
	# Don't trigger if no players have joined yet
	if players_node.get_child_count() == 0 or survival_time < 3.0:
		return

	for player in players_node.get_children():
		if player is Node2D and player.has_method("get_shape"):
			if not player.is_dead:
				return

	# All players dead
	game_over = true
	_show_game_over.rpc(int(survival_time))

@rpc("any_peer", "call_local", "reliable")
func _show_game_over(time: int):
	game_over = true
	game_over_label.text = "GAME OVER\nSurvived: %d seconds\n\nPress ESC to return to menu" % time
	game_over_label.visible = true
	if multiplayer.is_server():
		if _agones: _agones.shutdown()

func _update_hud():
	time_label.text = "Time: %d s" % int(survival_time)

	var my_id = multiplayer.get_unique_id()
	var my_player = players_node.get_node_or_null(str(my_id))
	if my_player and my_player.has_method("get_shape"):
		hp_label.text = "HP: %d / 10" % my_player.hp
		var s = my_player.current_shape
		shape_label.text = "%s [SPACE]" % SHAPE_NAMES[s]
		shape_label.modulate = my_player.COLORS[s]

func _input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
