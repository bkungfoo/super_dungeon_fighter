class_name BoardGrid
extends RefCounted
## Static dungeon layout: size and wall cells.

var cols: int = 8
var rows: int = 8
var walls: Dictionary = {}  # Vector2i -> true

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _init(c: int = 8, r: int = 8) -> void:
	cols = c
	rows = r


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func is_wall(c: Vector2i) -> bool:
	return walls.has(c)


func passable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_wall(c)


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			out.append(Vector2i(x, y))
	return out


## True if every passable cell can reach every other passable cell.
func all_connected() -> bool:
	var start := Vector2i(-1, -1)
	var total := 0
	for c in all_cells():
		if passable(c):
			total += 1
			if start.x < 0:
				start = c
	if total == 0:
		return true
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in DIRS:
			var n := c + d
			if passable(n) and not seen.has(n):
				seen[n] = true
				frontier.append(n)
	return seen.size() == total


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
