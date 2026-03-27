extends Node

## Manages ENet multiplayer connections. Access via the NetworkManager autoload.

signal player_connected(id: int)
signal player_disconnected(id: int)
signal connection_succeeded
signal connection_failed

const DEFAULT_PORT: int = 9999


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, 32)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_ZLIB)
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Server] Started on port %d" % port)
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, port)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_ZLIB)
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Client] Connecting to %s:%d..." % [ip, port])
	return OK


func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	player_disconnected.emit(id)


func _on_connected() -> void:
	print("[Client] Connected! My ID: %d" % multiplayer.get_unique_id())
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	print("[Client] Connection failed!")
	connection_failed.emit()
