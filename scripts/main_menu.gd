extends Control

@onready var ip_input: LineEdit = $VBox/DevSection/IPInput
@onready var port_input: LineEdit = $VBox/DevSection/PortInput
@onready var username_input: LineEdit = $VBox/OnlineSection/UsernameInput
@onready var status_label: Label = $VBox/StatusLabel
@onready var host_btn: Button = $VBox/DevSection/Buttons/HostButton
@onready var join_btn: Button = $VBox/DevSection/Buttons/JoinButton
@onready var online_btn: Button = $VBox/OnlineSection/OnlineButton

func _ready():
	ip_input.text = "127.0.0.1"
	port_input.text = "9999"
	status_label.text = ""
	SupabaseManager.auth_complete.connect(_on_auth_complete, CONNECT_ONE_SHOT)
	SupabaseManager.auth_failed.connect(_on_auth_failed, CONNECT_ONE_SHOT)

	if "--server" in OS.get_cmdline_args():
		_on_host_pressed()

# ─── Online flow ────────────────────────────────────────────────────────────

func _on_online_pressed():
	var username = username_input.text.strip_edges()
	if username.is_empty():
		status_label.text = "Enter a username to play online"
		return
	online_btn.disabled = true
	status_label.text = "Signing in..."
	SupabaseManager.login_anonymous(username)

func _on_auth_complete(_account: Dictionary) -> void:
	status_label.text = "Logged in! Loading lobby..."
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://scenes/lobby_menu.tscn")

func _on_auth_failed(error: String) -> void:
	status_label.text = "Auth failed: " + error
	online_btn.disabled = false

# ─── Local / dev flow ───────────────────────────────────────────────────────

func _on_host_pressed():
	host_btn.disabled = true
	join_btn.disabled = true
	var port = int(port_input.text)
	var error = NetworkManager.host_game(port)
	if error == OK:
		status_label.text = "Server started!"
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	else:
		status_label.text = "Failed to start server! Error: %d" % error
		host_btn.disabled = false
		join_btn.disabled = false

func _on_join_pressed():
	host_btn.disabled = true
	join_btn.disabled = true
	var ip = ip_input.text.strip_edges()
	var port = int(port_input.text)
	var error = NetworkManager.join_game(ip, port)
	if error == OK:
		status_label.text = "Connecting to %s:%d..." % [ip, port]
		NetworkManager.connection_succeeded.connect(_on_connected, CONNECT_ONE_SHOT)
		NetworkManager.connection_failed.connect(_on_failed, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to connect!"
		host_btn.disabled = false
		join_btn.disabled = false

func _on_connected():
	status_label.text = "Connected!"
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_failed():
	status_label.text = "Connection failed!"
	host_btn.disabled = false
	join_btn.disabled = false
