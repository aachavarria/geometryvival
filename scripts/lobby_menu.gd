extends Control

enum View { LIST, INSIDE }

var current_view: View = View.LIST
var current_lobby: Dictionary = {}

@onready var list_view = $ListViewContainer
@onready var inside_view = $InsideViewContainer

# List view nodes
@onready var lobbies_list = $ListViewContainer/VBox/LobbiesList
@onready var code_input = $ListViewContainer/VBox/JoinRow/CodeInput
@onready var status_label = $ListViewContainer/VBox/StatusLabel
@onready var welcome_label = $ListViewContainer/VBox/WelcomeLabel

# Inside view nodes
@onready var players_list = $InsideViewContainer/VBox/PlayersList
@onready var lobby_code_label = $InsideViewContainer/VBox/LobbyCodeLabel
@onready var ready_btn = $InsideViewContainer/VBox/Buttons/ReadyButton
@onready var start_btn = $InsideViewContainer/VBox/Buttons/StartButton

var is_ready: bool = false

func _ready():
	welcome_label.text = "Welcome, %s!" % SupabaseManager.current_account.get("username", "Player")
	SupabaseManager.lobby_updated.connect(_on_lobby_updated)
	SupabaseManager.match_started.connect(_on_match_started)
	_refresh_lobbies()

func _refresh_lobbies():
	status_label.text = "Loading lobbies..."
	var lobbies = await SupabaseManager.list_lobbies()
	lobbies_list.clear()
	if lobbies.is_empty():
		lobbies_list.add_item("No public lobbies — create one!")
	else:
		for lobby in lobbies:
			var players = lobby.get("lobby_players", [])
			lobbies_list.add_item("Lobby %s  [%d players]" % [lobby.code, players.size()])
			lobbies_list.set_item_metadata(lobbies_list.item_count - 1, lobby.id)
	status_label.text = ""

func _on_refresh_pressed():
	_refresh_lobbies()

func _on_create_pressed():
	status_label.text = "Creating lobby..."
	var lobby = await SupabaseManager.create_lobby()
	if lobby.is_empty():
		status_label.text = "Failed to create lobby"
		return
	await _enter_lobby(lobby)

func _on_join_list_pressed():
	var idx = lobbies_list.get_selected_items()
	if idx.is_empty():
		status_label.text = "Select a lobby first"
		return
	var lobby_id = lobbies_list.get_item_metadata(idx[0])
	status_label.text = "Joining..."
	var lobby = await SupabaseManager.join_lobby(lobby_id)
	if lobby.is_empty():
		status_label.text = "Failed to join"
		return
	await _enter_lobby(lobby)

func _on_join_code_pressed():
	var code = code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Enter a lobby code"
		return
	status_label.text = "Joining by code..."
	var lobby = await SupabaseManager.join_lobby("", code)
	if lobby.is_empty():
		status_label.text = "Lobby not found"
		return
	await _enter_lobby(lobby)

func _enter_lobby(lobby: Dictionary) -> void:
	current_lobby = lobby
	_show_view(View.INSIDE)
	lobby_code_label.text = "Code: %s" % lobby.code

	var is_owner = lobby.owner_id == SupabaseManager.current_account.get("id")
	start_btn.visible = is_owner

	await SupabaseManager.subscribe_to_lobby(lobby.id)
	_refresh_inside()

func _refresh_inside() -> void:
	var lobbies = await SupabaseManager.list_lobbies()
	for lobby in lobbies:
		if lobby.id == current_lobby.id:
			_on_lobby_updated(lobby)
			return

func _on_lobby_updated(lobby: Dictionary) -> void:
	current_lobby = lobby
	players_list.clear()
	for p in lobby.get("lobby_players", []):
		var label = "[%s] %s" % [p.team, p.username]
		if p.ready: label += " ✓"
		players_list.add_item(label)

func _on_ready_pressed():
	is_ready = !is_ready
	ready_btn.text = "Unready" if is_ready else "Ready"
	SupabaseManager.set_ready(current_lobby.id, is_ready)

func _on_start_pressed():
	start_btn.disabled = true
	var result = await SupabaseManager.start_lobby(current_lobby.id)
	if result.has("error"):
		start_btn.disabled = false
		status_label.text = result.error
		_show_view(View.INSIDE)

func _on_leave_pressed():
	await SupabaseManager.leave_lobby()
	current_lobby = {}
	is_ready = false
	_show_view(View.LIST)
	_refresh_lobbies()

func _on_match_started(address: String, port: int) -> void:
	# Connect to the GameFlow server and start playing
	var error = NetworkManager.join_game(address, port)
	if error == OK:
		NetworkManager.connection_succeeded.connect(func():
			get_tree().change_scene_to_file("res://scenes/game.tscn")
		, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to connect to game server"

func _show_view(view: View) -> void:
	current_view = view
	list_view.visible = view == View.LIST
	inside_view.visible = view == View.INSIDE

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
