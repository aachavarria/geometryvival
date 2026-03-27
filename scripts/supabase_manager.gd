extends Node

## Central manager for all Supabase backend calls.
## Access via SupabaseManager autoload.

signal auth_complete(account: Dictionary)
signal auth_failed(error: String)
signal lobby_updated(lobby: Dictionary)
signal match_started(address: String, port: int)

const FUNCTIONS_URL = "http://127.0.0.1:54321/functions/v1"

var access_token: String = ""
var current_account: Dictionary = {}
var current_lobby_id: String = ""

var _realtime_client: RealtimeClient = null
var _lobby_channel = null
var _lobbies_channel = null

# ─── Auth ───────────────────────────────────────────────────────────────────

func login_anonymous(username: String) -> void:
	Supabase.auth.signed_in_anonymous.connect(_on_signed_in_anon.bind(username), CONNECT_ONE_SHOT)
	Supabase.auth.error.connect(_on_auth_error, CONNECT_ONE_SHOT)
	Supabase.auth.sign_in_anonymous()

func _on_signed_in_anon(user: SupabaseUser, username: String) -> void:
	access_token = user.access_token
	var result = await _call("auth-anonymous", HTTPClient.METHOD_POST, { "username": username })
	if result.has("account"):
		current_account = result.account
		auth_complete.emit(current_account)
	else:
		auth_failed.emit(result.get("error", "Unknown error"))

func _on_auth_error(error) -> void:
	auth_failed.emit(str(error))

# ─── Lobbies ────────────────────────────────────────────────────────────────

func list_lobbies() -> Array:
	var result = await _call("lobbies-list", HTTPClient.METHOD_GET, {})
	return result.get("lobbies", [])

func create_lobby(is_private: bool = false) -> Dictionary:
	var result = await _call("lobbies-create", HTTPClient.METHOD_POST, { "is_private": is_private })
	return result.get("lobby", {})

func join_lobby(lobby_id: String = "", code: String = "") -> Dictionary:
	var body = {}
	if lobby_id: body["lobby_id"] = lobby_id
	if code:     body["code"] = code
	var result = await _call("lobbies-join", HTTPClient.METHOD_POST, body)
	return result.get("lobby", {})

func leave_lobby() -> void:
	if current_lobby_id.is_empty(): return
	await _call("lobbies-leave", HTTPClient.METHOD_POST, { "lobby_id": current_lobby_id })
	_unsubscribe_lobby()
	current_lobby_id = ""

func set_ready(lobby_id: String, ready: bool) -> void:
	await _call("lobbies-ready", HTTPClient.METHOD_POST, { "lobby_id": lobby_id, "ready": ready })

func start_lobby(lobby_id: String) -> Dictionary:
	return await _call("lobbies-start", HTTPClient.METHOD_POST, { "lobby_id": lobby_id })

# ─── Realtime ────────────────────────────────────────────────────────────────

func subscribe_to_lobby(lobby_id: String) -> void:
	current_lobby_id = lobby_id
	_unsubscribe_lobby()

	_realtime_client = Supabase.realtime.client()
	await _realtime_client.connected

	# Watch lobby_players changes
	_lobby_channel = _realtime_client.channel("public", "lobby_players", "lobby_id=eq." + lobby_id)
	_lobby_channel.on("all", func(_old, _new, _ch): _refresh_lobby())
	_lobby_channel.subscribe()

	# Watch lobbies change (for match:started with server info)
	_lobbies_channel = _realtime_client.channel("public", "lobbies", "id=eq." + lobby_id)
	_lobbies_channel.on("update", func(_old, new_rec, _ch):
		if new_rec.get("status") == "started":
			match_started.emit(new_rec.server_address, int(new_rec.server_port))
	)
	_lobbies_channel.subscribe()

	_realtime_client.connect_client()

func _refresh_lobby() -> void:
	var result = await _call("lobbies-list", HTTPClient.METHOD_GET, {})
	for lobby in result.get("lobbies", []):
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
	var http = HTTPRequest.new()
	add_child(http)

	var headers = PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + Supabase.config.supabaseKey,
	])
	if not access_token.is_empty():
		headers.append("Authorization: Bearer " + access_token)

	var payload = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	http.request(FUNCTIONS_URL + "/" + fn, headers, method, payload)

	var response = await http.request_completed
	http.queue_free()

	# response = [result, code, headers, body_bytes]
	var code = response[1]
	var text = response[3].get_string_from_utf8()
	var parsed = JSON.parse_string(text)

	if not parsed:
		return { "error": "Invalid JSON: " + text }
	if code >= 400:
		print("[Supabase] Error %d on %s: %s" % [code, fn, text])
	return parsed
