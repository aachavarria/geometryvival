extends Control

@onready var username_input: LineEdit = $VBox/UsernameInput
@onready var status_label: Label      = $VBox/StatusLabel
@onready var online_btn: Button       = $VBox/OnlineButton


func _ready() -> void:
	status_label.text = ""
	SupabaseManager.auth_complete.connect(_on_auth_complete, CONNECT_ONE_SHOT)
	SupabaseManager.auth_failed.connect(_on_auth_failed, CONNECT_ONE_SHOT)

	if "--server" in OS.get_cmdline_args():
		_start_dedicated_server()


func _start_dedicated_server() -> void:
	NetworkManager.host_game(NetworkManager.DEFAULT_PORT)
	# call_deferred avoids modifying the scene tree during _ready.
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _on_online_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	if username.is_empty():
		status_label.text = "Enter a username"
		return
	online_btn.disabled = true
	status_label.text = "Signing in..."
	SupabaseManager.login_anonymous(username)


func _on_auth_complete(_account: Dictionary) -> void:
	status_label.text = "Loading lobby..."
	# Brief delay to let the Supabase auth state settle before switching scenes.
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://scenes/lobby_menu.tscn")


func _on_auth_failed(error: String) -> void:
	status_label.text = "Error: " + error
	online_btn.disabled = false
