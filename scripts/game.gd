extends Node2D

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_SCENE  = preload("res://scenes/enemy.tscn")
const AGONES_SCENE = preload("res://addons/agones/agones_sdk.gd")

var _agones = null  # AgonesSDK instance (untyped to avoid conflict with Node.ready signal)

var survival_time: float  = 0.0
var spawn_interval: float = 1.5
var spawn_timer: float    = 0.0
var enemy_id: int         = 0
var difficulty_timer: float = 0.0
var game_over: bool       = false
var surrendering: bool    = false

## Server-side per-player damage cooldown (seconds).
var damage_cooldown: Dictionary = {}
var health_timer: float = 0.0

@onready var players_node: Node2D      = $Players
@onready var enemies_node: Node2D      = $Enemies
@onready var time_label: Label         = $HUD/TimeLabel
@onready var hp_label: Label           = $HUD/HPLabel
@onready var shape_label: Label        = $HUD/ShapeLabel
@onready var game_over_label: Label    = $HUD/GameOverLabel
@onready var info_label: Label         = $HUD/InfoLabel
@onready var surrender_label: Label    = $HUD/SurrenderLabel
@onready var waiting_label: Label      = $HUD/WaitingLabel


func _ready() -> void:
	game_over_label.visible = false

	if multiplayer.is_server():
		if _is_dedicated_server():
			# Signal Agones that this server is ready to receive players.
			_agones = AGONES_SCENE.new()
			add_child(_agones)
			_agones.ready()
		else:
			# Local host: the host is also a player.
			_spawn_player(1)

		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_remove_player)
		info_label.text = "SERVER | Port %d" % NetworkManager.DEFAULT_PORT
	else:
		# Client: ask the server to spawn us.
		_request_spawn.rpc_id(1)
		info_label.text = "CLIENT | ID: %d" % multiplayer.get_unique_id()


@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not players_node.has_node(str(id)):
		_spawn_player(id)


func _on_player_connected(id: int) -> void:
	if _agones:
		_agones.player_connect(str(id))


func _spawn_player(id: int) -> void:
	var player: Node2D = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = Vector2(640 + randf_range(-100, 100), 360 + randf_range(-50, 50))
	players_node.add_child(player, true)
	player.set_multiplayer_authority(id)
	print("[Game] Spawned player %d" % id)


func _is_dedicated_server() -> bool:
	return "--server" in OS.get_cmdline_args() or DisplayServer.get_name() == "headless"


func _remove_player(id: int) -> void:
	var player: Node = players_node.get_node_or_null(str(id))
	if player:
		player.queue_free()
	damage_cooldown.erase(id)
	if _agones:
		_agones.player_disconnect(str(id))


func _physics_process(delta: float) -> void:
	_update_hud()

	if not multiplayer.is_server() or game_over:
		return

	# Agones health ping every 5 seconds.
	health_timer += delta
	if health_timer >= 5.0:
		health_timer = 0.0
		if _agones:
			_agones.health()

	# Pause all game logic until the first player connects.
	if players_node.get_child_count() == 0:
		return

	survival_time += delta

	# Ramp up difficulty every 10 seconds by reducing the spawn interval.
	difficulty_timer += delta
	if difficulty_timer >= 10.0:
		difficulty_timer = 0.0
		spawn_interval = max(0.25, spawn_interval - 0.15)

	# Spawn enemies on a timer.
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# Tick down per-player damage cooldowns.
	for pid in damage_cooldown.keys():
		damage_cooldown[pid] -= delta
		if damage_cooldown[pid] <= 0:
			damage_cooldown.erase(pid)

	_check_collisions()
	_check_game_over()


func _spawn_enemy() -> void:
	var enemy: Node2D = ENEMY_SCENE.instantiate()
	enemy.players_node = players_node
	enemy.shape_type = randi() % 3
	enemy.speed = 80.0 + survival_time * 1.5

	# Spawn from a random screen edge (30 px outside the viewport).
	var side: int = randi() % 4
	match side:
		0: enemy.position = Vector2(randf_range(0, 1280), -30)          # top
		1: enemy.position = Vector2(randf_range(0, 1280), 720 + 30)     # bottom
		2: enemy.position = Vector2(-30,          randf_range(0, 720))  # left
		3: enemy.position = Vector2(1280 + 30,    randf_range(0, 720))  # right

	enemy.name = "e%d" % enemy_id
	enemy_id += 1
	enemies_node.add_child(enemy, true)


func _check_collisions() -> void:
	var kill_radius: float = 32.0
	var enemies_to_kill: Array[Node2D] = []

	for player in players_node.get_children():
		if not (player is Node2D) or not player.has_method("get_shape"):
			continue
		if player.is_dead:
			continue

		var pid: int = int(str(player.name))
		var p_shape: int = player.get_shape()
		var kills_shape: int = (p_shape + GameConstants.KILLS_OFFSET) % 3

		for enemy in enemies_node.get_children():
			if not (enemy is Node2D) or enemies_to_kill.has(enemy):
				continue

			if player.position.distance_to(enemy.position) < kill_radius:
				if enemy.shape_type == kills_shape:
					# Player's shape beats this enemy's shape — enemy is destroyed.
					pass
				else:
					# Enemy damages the player (with invincibility cooldown).
					if not damage_cooldown.has(pid):
						damage_cooldown[pid] = 0.5
						player.take_damage.rpc(1)
				# Enemy is always consumed on contact, win or lose.
				enemies_to_kill.append(enemy)

	for enemy in enemies_to_kill:
		enemy.queue_free()


func _check_game_over() -> void:
	# Ignore until at least one player has joined and a few seconds have passed.
	if players_node.get_child_count() == 0 or survival_time < 3.0:
		return

	for player in players_node.get_children():
		if player is Node2D and player.has_method("get_shape") and not player.is_dead:
			return  # At least one player is still alive.

	# All players are dead.
	game_over = true
	_show_game_over.rpc(int(survival_time))


@rpc("any_peer", "call_local", "reliable")
func _show_game_over(time: int) -> void:
	game_over = true
	game_over_label.text = "GAME OVER\nSurvived: %d seconds\n\nPress ESC to return to menu" % time
	game_over_label.visible = true
	if multiplayer.is_server() and _agones:
		_agones.shutdown()


func _update_hud() -> void:
	time_label.text = "Time: %d s" % int(survival_time)

	var my_id: int = multiplayer.get_unique_id()
	var my_player: Node = players_node.get_node_or_null(str(my_id))
	if my_player and my_player.has_method("get_shape"):
		hp_label.text = "HP: %d / 10" % my_player.hp
		var s: int = my_player.current_shape
		shape_label.text = "%s [SPACE]" % GameConstants.SHAPE_NAMES[s]
		shape_label.modulate = GameConstants.SHAPE_COLORS[s]

		waiting_label.visible = my_player.is_dead and not game_over
		if waiting_label.visible:
			waiting_label.text = "You died — waiting for others...\n(ESC to leave)"


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		# Any non-ESC key press cancels a pending surrender.
		if surrendering and event is InputEventKey and event.pressed:
			surrendering = false
			surrender_label.visible = false
		return

	var my_id: int = multiplayer.get_unique_id()
	var my_player: Node = players_node.get_node_or_null(str(my_id))
	var i_am_dead: bool = my_player == null or my_player.is_dead

	if game_over:
		multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif i_am_dead:
		# Already dead — leave quietly while others continue.
		multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif surrendering:
		# Second ESC — confirmed surrender.
		surrendering = false
		surrender_label.visible = false
		if my_player:
			my_player.take_damage.rpc(my_player.hp)
	else:
		# First ESC — ask for confirmation.
		surrendering = true
		surrender_label.text = "Press ESC again to surrender  |  Any key to cancel"
		surrender_label.visible = true
