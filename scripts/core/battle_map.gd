class_name BattleMap
extends RefCounted
## Continuous arena on the XZ plane with rectangular obstacles, plus a coarse
## occupancy grid used for A* pathfinding. Positions are Vector2(x, z).

const CELL := 0.5

var width: float = 36.0
var height: float = 36.0
var obstacles: Array[Rect2] = []
var hero_spawn: Vector2 = Vector2(18, 31)

var _cols: int = 0
var _rows: int = 0
var _blocked: PackedByteArray = PackedByteArray()
var _radius: float = 0.5


func _init(w: float = 36.0, h: float = 36.0) -> void:
	width = w
	height = h
	hero_spawn = Vector2(w * 0.5, h - 5.0)
	rebuild()


## Rebuilds the occupancy grid. Obstacles are inflated by `radius` so actor
## centres stay clear of walls.
func rebuild(radius: float = 0.5) -> void:
	_radius = radius
	_cols = int(ceil(width / CELL))
	_rows = int(ceil(height / CELL))
	_blocked.resize(_cols * _rows)
	for y in _rows:
		for x in _cols:
			var p := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			_blocked[y * _cols + x] = 1 if is_blocked_point(p, radius) else 0


func is_blocked_point(p: Vector2, radius: float = 0.5) -> bool:
	if p.x < radius or p.y < radius or p.x > width - radius or p.y > height - radius:
		return true
	for r in obstacles:
		if r.grow(radius).has_point(p):
			return true
	return false


func clamp_inside(p: Vector2, radius: float = 0.5) -> Vector2:
	return Vector2(clampf(p.x, radius, width - radius), clampf(p.y, radius, height - radius))


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, _cols - 1), clampi(int(p.y / CELL), 0, _rows - 1))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func _cell_blocked(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= _cols or c.y >= _rows:
		return true
	return _blocked[c.y * _cols + c.x] == 1


## Nearest unblocked cell to a point (searching outward in rings).
func nearest_free(p: Vector2) -> Vector2:
	var c := _cell_of(p)
	if not _cell_blocked(c):
		return p
	for ring in range(1, 40):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var n := c + Vector2i(dx, dy)
				if not _cell_blocked(n):
					return _cell_center(n)
	return p


## True if the straight segment a-b stays clear of obstacles.
func line_free(a: Vector2, b: Vector2, radius: float = -1.0) -> bool:
	var r := _radius if radius < 0.0 else radius
	var steps := maxi(1, int(ceil(a.distance_to(b) / (CELL * 0.5))))
	for i in range(steps + 1):
		if is_blocked_point(a.lerp(b, float(i) / steps), r):
			return false
	return true


## Binary min-heap of [priority, Vector2i] pairs for A*.
class _Heap:
	var items: Array = []

	func push(prio: float, cell: Vector2i) -> void:
		items.append([prio, cell])
		var i := items.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if items[parent][0] <= items[i][0]:
				break
			var tmp = items[parent]
			items[parent] = items[i]
			items[i] = tmp
			i = parent

	func pop() -> Array:
		var top: Array = items[0]
		var last: Array = items.pop_back()
		if not items.is_empty():
			items[0] = last
			var i := 0
			var n := items.size()
			while true:
				var l := 2 * i + 1
				var r := l + 1
				var smallest := i
				if l < n and items[l][0] < items[smallest][0]:
					smallest = l
				if r < n and items[r][0] < items[smallest][0]:
					smallest = r
				if smallest == i:
					break
				var tmp = items[smallest]
				items[smallest] = items[i]
				items[i] = tmp
				i = smallest
		return top

	func is_empty() -> bool:
		return items.is_empty()


## A* over the grid (8 directions, no corner cutting), then string-pulled.
## Returns waypoints after `from`, ending at `to` (or the nearest free spot).
func find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var goal := nearest_free(to)
	if line_free(from, goal):
		return [goal]
	var start_c := _cell_of(nearest_free(from))
	var goal_c := _cell_of(goal)
	var open := _Heap.new()
	open.push(0.0, start_c)
	var g := {start_c: 0.0}
	var came := {}
	var closed := {}
	var found := false
	var expansions := 0
	while not open.is_empty() and expansions < 12000:
		var cur: Vector2i = open.pop()[1]
		if cur == goal_c:
			found = true
			break
		if closed.has(cur):
			continue
		closed[cur] = true
		expansions += 1
		var gc: float = g[cur]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := cur + Vector2i(dx, dy)
				if closed.has(n) or _cell_blocked(n):
					continue
				if dx != 0 and dy != 0 and (_cell_blocked(cur + Vector2i(dx, 0)) or _cell_blocked(cur + Vector2i(0, dy))):
					continue
				var ng: float = gc + (1.41421 if (dx != 0 and dy != 0) else 1.0)
				if ng < g.get(n, INF):
					g[n] = ng
					came[n] = cur
					var ddx := absf(n.x - goal_c.x)
					var ddy := absf(n.y - goal_c.y)
					var h: float = maxf(ddx, ddy) + 0.41421 * minf(ddx, ddy)
					open.push(ng + h, n)
	if not found:
		return []
	var cells: Array[Vector2i] = []
	var c := goal_c
	while c != start_c:
		cells.push_front(c)
		c = came[c]
	var pts: Array[Vector2] = []
	for cc in cells:
		pts.append(_cell_center(cc))
	if not pts.is_empty():
		pts[pts.size() - 1] = goal
	# String pulling: skip waypoints we can reach directly.
	var out: Array[Vector2] = []
	var anchor := from
	var i := 0
	while i < pts.size():
		var j := i
		while j + 1 < pts.size() and line_free(anchor, pts[j + 1]):
			j += 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


func connected(a: Vector2, b: Vector2) -> bool:
	return not find_path(a, b).is_empty()


## Lays random box obstacles, keeping `keep` points mutually reachable.
func generate(rng: RandomNumberGenerator, count: int, keep: Array) -> void:
	obstacles.clear()
	rebuild()
	var tries := 0
	while obstacles.size() < count and tries < 200:
		tries += 1
		var w := rng.randf_range(1.5, 5.0)
		var h := rng.randf_range(1.5, 5.0)
		var r := Rect2(rng.randf_range(2.0, width - w - 2.0), rng.randf_range(2.0, height - h - 2.0), w, h)
		var ok := true
		for p in keep:
			if r.grow(1.2).has_point(p):
				ok = false
		if not ok:
			continue
		obstacles.append(r)
		rebuild()
		for p in keep:
			if not connected(keep[0], p):
				ok = false
		if not ok:
			obstacles.pop_back()
			rebuild()
