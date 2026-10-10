class_name DMAI
extends RefCounted
## The Dungeon Master's summoning: picks monsters within the budget. The
## monsters themselves are driven in real time by MonsterAI.

var rng: RandomNumberGenerator


func _init(r: RandomNumberGenerator = null) -> void:
	rng = r if r != null else RandomNumberGenerator.new()
	if r == null:
		rng.randomize()


# ------------------------------------------------------------------ dungeon

## Picks monsters worth up to `budget` summoning points from the DM's roster.
func choose_monsters(budget: int, dm_level: int) -> Array[String]:
	var pool := MonsterDB.available(dm_level)
	var picks: Array[String] = []
	var left := budget
	for k in pool:
		var d := MonsterDB.get_def(k)
		if d.get("boss", false) and d.value <= left and rng.randf() < 0.75:
			picks.append(k)
			left -= d.value
			break
	var guard := 0
	while left > 0 and guard < 100:
		guard += 1
		var options: Array[String] = []
		for k in pool:
			var d := MonsterDB.get_def(k)
			if d.value <= left and not d.get("boss", false):
				options.append(k)
		if options.is_empty():
			break
		var weighted: Array[String] = []
		for k in options:
			for i in MonsterDB.get_def(k).value:
				weighted.append(k)
		var k: String = weighted[rng.randi_range(0, weighted.size() - 1)]
		picks.append(k)
		left -= MonsterDB.get_def(k).value
	if picks.is_empty():
		picks.append("goblin")
	return picks
