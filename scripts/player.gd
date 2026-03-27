extends Node2D

## Shape types: 0 = Circle, 1 = Square, 2 = Triangle
## Kill rule:   Circle kills Square, Square kills Triangle, Triangle kills Circle

const SPEED: float = 300.0

var current_shape: int = 0:
	set(value):
		current_shape = value
		queue_redraw()

var hp: int = 10:
	set(value):
		hp = value
		queue_redraw()

var is_dead: bool    = false
var invincible: bool = false
var invincible_timer: float = 0.0
var flash_timer: float      = 0.0


func _enter_tree() -> void:
	# Set authority before _ready so MultiplayerSynchronizer initializes correctly.
	# The server names each player node after the peer ID, so clients can derive it too.
	var peer_id: int = name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func get_shape() -> int:
	return current_shape


func _physics_process(delta: float) -> void:
	# Invincibility flash runs on all peers for visual feedback.
	if invincible:
		invincible_timer -= delta
		flash_timer += delta
		modulate.a = 0.3 if fmod(flash_timer, 0.15) < 0.075 else 1.0
		if invincible_timer <= 0:
			invincible = false
			modulate.a = 1.0

	if not is_multiplayer_authority() or is_dead:
		return

	# Movement (WASD or arrow keys)
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    input.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  input.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  input.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1
	if input.length_squared() > 0:
		position += input.normalized() * SPEED * delta
		position.x = clamp(position.x, 20, 1260)
		position.y = clamp(position.y, 20, 700)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	# Cycle shape on SPACE press (not hold — event.echo blocks key-repeat).
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed and not event.echo:
		current_shape = (current_shape + 1) % 3


@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int) -> void:
	if invincible or is_dead:
		return
	hp -= amount
	invincible = true
	invincible_timer = 0.5
	flash_timer = 0.0
	if hp <= 0:
		hp = 0
		is_dead = true
		modulate.a = 0.2


func _draw() -> void:
	var color: Color = GameConstants.SHAPE_COLORS[current_shape]

	match current_shape:
		0:  # Circle
			draw_circle(Vector2.ZERO, 20, color)
			draw_arc(Vector2.ZERO, 20, 0, TAU, 32, Color.WHITE, 2.0)
		1:  # Square
			draw_rect(Rect2(-18, -18, 36, 36), color)
			draw_rect(Rect2(-18, -18, 36, 36), Color.WHITE, false, 2.0)
		2:  # Triangle
			var pts := PackedVector2Array([Vector2(0, -22), Vector2(20, 18), Vector2(-20, 18)])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.WHITE, 2.0)

	# HP bar
	var bar_width: float = 40.0
	var bar_y: float = -34.0
	draw_rect(Rect2(-bar_width / 2, bar_y, bar_width, 5), Color(0.2, 0.2, 0.2))
	var hp_color: Color = Color.GREEN_YELLOW if hp > 3 else Color.RED
	draw_rect(Rect2(-bar_width / 2, bar_y, bar_width * (float(hp) / 10.0), 5), hp_color)
