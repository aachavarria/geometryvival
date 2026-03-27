extends Node

## Central manager for all Supabase backend calls. Access via the SupabaseManager autoload.

signal auth_complete(account: Dictionary)
signal auth_failed(error: String)
signal lobby_updated(lobby: Dictionary)
signal match_started(address: String, port: int)

## Derived from the Supabase addon config so it works for both local dev and production.
## Local dev:  http://127.0.0.1:54321/functions/v1  (set in addons/supabase/.env)
## Production: https://<project-ref>.supabase.co/functions/v1  (set in Project Settings)
var _functions_url: String:
	get: return Supabase.config.supabaseUrl + "/functions/v1"

var access_token: String = ""
var current_account: Dictionary = {}
var current_lobby_id: String = ""

var _realtime_client: RealtimeClient = null
var _lobby_channel: RealtimeChannel = null
var _lobbies_channel: RealtimeChannel = null


# ─── Auth ───────────────────────────────────────────────────────────────────

func login_anonymous(username: String) -> void:
	# Guard against double-connecting if the user returns to the main menu.
	if Supabase.auth.error.is_connected(_on_auth_error):
		Supabase.auth.error.disconnect(_on_auth_error)
	Supabase.auth.signed_in_anonymous.connect(_on_signed_in_anon.bind(username), CONNECT_ONE_SHOT)
	Supabase.auth.error.connect(_on_auth_error, CONNECT_ONE_SHOT)
	Supabase.auth.sign_in_anonymous()


func _on_signed_in_anon(user: SupabaseUser, username: String) -> void:
	access_token = user.access_token
	var result: Dictionary = await _call("auth-anonymous", HTTPClient.METHOD_POST, { "username": username })
	if result.has("account"):
		current_account = result.account
		auth_complete.emit(current_account)
	else:
		auth_failed.emit(result.get("error", "Unknown error"))


func _on_auth_error(error: Variant) -> void:
	auth_failed.emit(str(error))


# ─── Lobbies ────────────────────────────────────────────────────────────────

func list_lobbies() -> Array:
	var result: Dictionary = await _call("lobbies-list", HTTPClient.METHOD_GET, {})
	return result.get("lobbies", [])


func create_lobby(is_private: bool = false) -> Dictionary:
	var result: Dictionary = await _call("lobbies-create", HTTPClient.METHOD_POST, { "is_private": is_private })
	return result.get("lobby", {})


func join_lobby(lobby_id: String = "", code: String = "") -> Dictionary:
	var body: Dictionary = {}
	if lobby_id: body["lobby_id"] = lobby_id
	if code:     body["code"]     = code
	var result: Dictionary = await _call("lobbies-join", HTTPClient.METHOD_POST, body)
	return result.get("lobby", {})


func leave_lobby() -> void:
	if current_lobby_id.is_empty():
		return
	await _call("lobbies-leave", HTTPClient.METHOD_POST, { "lobby_id": current_lobby_id })
	_unsubscribe_lobby()
	current_lobby_id = ""


func set_ready(lobby_id: String, ready: bool) -> void:
	await _call("lobbies-ready", HTTPClient.METHOD_POST, { "lobby_id": lobby_id, "ready": ready })


func start_lobby(lobby_id: String) -> Dictionary:
	return await _call("lobbies-start", HTTPClient.METHOD_POST, { "lobby_id": lobby_id })


# ─── Realtime ───────────────────────────────────────────────────────────────

func subscribe_to_lobby(lobby_id: String) -> void:
	current_lobby_id = lobby_id
	_unsubscribe_lobby()

	_realtime_client = Supabase.realtime.client()

	# Set up channels before opening the connection.
	_lobby_channel = _realtime_client.channel("public", "lobby_players", "lobby_id=eq." + lobby_id)
	_lobby_channel.on("all", func(_old: Dictionary, _new: Dictionary, _ch: RealtimeChannel) -> void:
		_refresh_lobby()
	)

	_lobbies_channel = _realtime_client.channel("public", "lobbies", "id=eq." + lobby_id)
	_lobbies_channel.on("update", func(_old: Dictionary, new_rec: Dictionary, _ch: RealtimeChannel) -> void:
		if new_rec.get("status") == "started":
			match_started.emit(
				new_rec.get("server_address", ""),
				int(new_rec.get("server_port", 0))
			)
	)

	# Connect first, then subscribe once the WebSocket is open.
	_realtime_client.connect_client()
	await _realtime_client.connected

	_lobby_channel.subscribe()
	_lobbies_channel.subscribe()


func _refresh_lobby() -> void:
	# Fetches the full lobby list to find the current lobby and emit lobby_updated.
	# A dedicated lobbies-get endpoint would be more efficient, but this keeps the
	# edge function count minimal for a reference project.
	var result: Dictionary = await _call("lobbies-list", HTTPClient.METHOD_GET, {})
	for lobby: Dictionary in result.get("lobbies", []):
		if lobby.id == current_lobby_id:
			lobby_updated.emit(lobby)
			return


func _unsubscribe_lobby() -> void:
	if _lobby_channel:
		_lobby_channel.unsubscribe()
		_lobby_channel = null
	if _lobbies_channel:
		_lobbies_channel.unsubscribe()
		_lobbies_channel = null
	if _realtime_client:
		_realtime_client.disconnect_client()
		_realtime_client.queue_free()
		_realtime_client = null


# ─── HTTP helper ─────────────────────────────────────────────────────────────

func _call(fn: String, method: HTTPClient.Method, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + Supabase.config.supabaseKey,
	])
	if not access_token.is_empty():
		headers.append("Authorization: Bearer " + access_token)

	var payload: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	http.request(_functions_url + "/" + fn, headers, method, payload)

	var response: Array = await http.request_completed
	http.queue_free()

	# response = [result, http_code, headers, body_bytes]
	var code: int = response[1]
	var text: String = response[3].get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)

	if parsed == null:
		return { "error": "Invalid JSON: " + text }
	if code >= 400:
		print("[Supabase] Error %d on %s: %s" % [code, fn, text])
	return parsed
