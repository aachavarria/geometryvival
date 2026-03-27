extends Control

enum View { LIST, INSIDE }

var current_view: View = View.LIST
var current_lobby: Dictionary = {}
var is_ready: bool = false

# List view
@onready var list_view: Control       = $ListViewContainer
@onready var lobbies_list: ItemList   = $ListViewContainer/VBox/LobbiesList
@onready var code_input: LineEdit     = $ListViewContainer/VBox/JoinRow/CodeInput
@onready var status_label: Label      = $ListViewContainer/VBox/StatusLabel
@onready var welcome_label: Label     = $ListViewContainer/VBox/WelcomeLabel

# Inside view
@onready var inside_view: Control      = $InsideViewContainer
@onready var players_list: ItemList    = $InsideViewContainer/VBox/PlayersList
@onready var lobby_code_label: Label   = $InsideViewContainer/VBox/LobbyCodeLabel
@onready var ready_btn: Button         = $InsideViewContainer/VBox/Buttons/ReadyButton
@onready var start_btn: Button         = $InsideViewContainer/VBox/Buttons/StartButton


func _ready() -> void:
	welcome_label.text = "Welcome, %s!" % SupabaseManager.current_account.get("username", "Player")
	SupabaseManager.lobby_updated.connect(_on_lobby_updated)
	SupabaseManager.match_started.connect(_on_match_started)
	_refresh_lobbies()


func _refresh_lobbies() -> void:
	status_label.text = "Loading lobbies..."
	var lobbies: Array = await SupabaseManager.list_lobbies()
	lobbies_list.clear()
	if lobbies.is_empty():
		lobbies_list.add_item("No public lobbies — create one!")
	else:
		for lobby: Dictionary in lobbies:
			var player_count: int = lobby.get("lobby_players", []).size()
			lobbies_list.add_item("Lobby %s  [%d players]" % [lobby.code, player_count])
			lobbies_list.set_item_metadata(lobbies_list.item_count - 1, lobby.id)
	status_label.text = ""


func _on_refresh_pressed() -> void:
	_refresh_lobbies()


func _on_create_pressed() -> void:
	status_label.text = "Creating lobby..."
	var lobby: Dictionary = await SupabaseManager.create_lobby()
	if lobby.is_empty():
		status_label.text = "Failed to create lobby"
		return
	await _enter_lobby(lobby)


func _on_join_list_pressed() -> void:
	var selected: PackedInt32Array = lobbies_list.get_selected_items()
	if selected.is_empty():
		status_label.text = "Select a lobby first"
		return
	var lobby_id: String = lobbies_list.get_item_metadata(selected[0])
	status_label.text = "Joining..."
	var lobby: Dictionary = await SupabaseManager.join_lobby(lobby_id)
	if lobby.is_empty():
		status_label.text = "Failed to join"
		return
	await _enter_lobby(lobby)


func _on_join_code_pressed() -> void:
	var code: String = code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Enter a lobby code"
		return
	status_label.text = "Joining by code..."
	var lobby: Dictionary = await SupabaseManager.join_lobby("", code)
	if lobby.is_empty():
		status_label.text = "Lobby not found"
		return
	await _enter_lobby(lobby)


func _enter_lobby(lobby: Dictionary) -> void:
	current_lobby = lobby
	_show_view(View.INSIDE)
	lobby_code_label.text = "Code: %s" % lobby.code
	start_btn.visible = lobby.owner_id == SupabaseManager.current_account.get("id")
	await SupabaseManager.subscribe_to_lobby(lobby.id)
	_refresh_inside()


func _refresh_inside() -> void:
	# Fetch current lobby state for the initial render before Realtime takes over.
	var lobbies: Array = await SupabaseManager.list_lobbies()
	for lobby: Dictionary in lobbies:
		if lobby.id == current_lobby.id:
			_on_lobby_updated(lobby)
			return


func _on_lobby_updated(lobby: Dictionary) -> void:
	current_lobby = lobby
	players_list.clear()
	for p: Dictionary in lobby.get("lobby_players", []):
		var label: String = "[%s] %s" % [p.team, p.username]
		if p.ready:
			label += " ✓"
		players_list.add_item(label)


func _on_ready_pressed() -> void:
	ready_btn.disabled = true
	is_ready = !is_ready
	await SupabaseManager.set_ready(current_lobby.id, is_ready)
	ready_btn.text = "Unready" if is_ready else "Ready"
	ready_btn.disabled = false


func _on_start_pressed() -> void:
	start_btn.disabled = true
	var result: Dictionary = await SupabaseManager.start_lobby(current_lobby.id)
	if result.has("error"):
		start_btn.disabled = false
		status_label.text = result.error


func _on_leave_pressed() -> void:
	await SupabaseManager.leave_lobby()
	current_lobby = {}
	is_ready = false
	_show_view(View.LIST)
	_refresh_lobbies()


func _on_match_started(address: String, port: int) -> void:
	var error: Error = NetworkManager.join_game(address, port)
	if error == OK:
		NetworkManager.connection_succeeded.connect(
			func() -> void: get_tree().change_scene_to_file("res://scenes/game.tscn"),
			CONNECT_ONE_SHOT
		)
	else:
		status_label.text = "Failed to connect to game server"


func _on_back_pressed() -> void:
	await SupabaseManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SupabaseManager.leave_lobby()
		get_tree().quit()


func _show_view(view: View) -> void:
	current_view = view
	list_view.visible  = view == View.LIST
	inside_view.visible = view == View.INSIDE
