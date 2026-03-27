extends Node2D

## Shape types: 0 = Circle, 1 = Square, 2 = Triangle (same as player)

var shape_type: int = 0:
	set(value):
		shape_type = value
		queue_redraw()

var speed: float = 80.0

## Set by Game when spawning this enemy. Server-only — enemy AI runs only on the server.
var players_node: Node2D = null


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Move toward the nearest living player.
	var nearest_dist: float = INF
	var nearest_pos: Vector2 = position

	for player in players_node.get_children():
		if not (player is Node2D) or not player.has_method("get_shape"):
			continue
		if player.is_dead:
			continue
		var d: float = position.distance_to(player.position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_pos = player.position

	if nearest_dist < INF:
		position += (nearest_pos - position).normalized() * speed * delta


func _draw() -> void:
	# Enemies use the same shape colors as players but at 75% opacity.
	var color: Color = GameConstants.SHAPE_COLORS[shape_type]
	color.a = 0.75

	match shape_type:
		0:  # Circle
			draw_circle(Vector2.ZERO, 15, color)
			draw_arc(Vector2.ZERO, 15, 0, TAU, 32, Color.WHITE, 1.5)
		1:  # Square
			draw_rect(Rect2(-13, -13, 26, 26), color)
			draw_rect(Rect2(-13, -13, 26, 26), Color.WHITE, false, 1.5)
		2:  # Triangle
			var pts := PackedVector2Array([Vector2(0, -16), Vector2(15, 13), Vector2(-15, 13)])
			draw_colored_polygon(pts, color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.WHITE, 1.5)
