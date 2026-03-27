## Shared constants for shape types, names, and colors.
## Access directly anywhere: GameConstants.SHAPE_NAMES, GameConstants.SHAPE_COLORS, etc.
class_name GameConstants

const SHAPE_NAMES: Array[String] = ["Circle", "Square", "Triangle"]

## Shape colors at full opacity (used by players).
const SHAPE_COLORS: Array[Color] = [
	Color(0.35, 0.55, 0.95),  # Blue  — Circle
	Color(0.95, 0.35, 0.35),  # Red   — Square
	Color(0.35, 0.95, 0.45),  # Green — Triangle
]

## Kill rule: a player of shape X kills enemies of shape (X + KILLS_OFFSET) % 3.
## Circle(0) → kills Square(1) → kills Triangle(2) → kills Circle(0)
const KILLS_OFFSET: int = 1
