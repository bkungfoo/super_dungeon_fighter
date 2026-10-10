extends Node
## Runtime state shared between scenes (not persisted).

var hero_id: int = -1
var difficulty: float = 1.0
var difficulty_name: String = "Normal"
var last_result_lines: Array[String] = []
var last_result_won: bool = false


func dm_budget() -> int:
	var h: Dictionary = Save.hero_by_id(hero_id)
	var level: int = h.get("level", 1) if not h.is_empty() else 1
	var bonus: int = int((Save.dm_level() - 1) / 2)
	return maxi(2, int(ceil((level + 1) * difficulty)) + bonus)


## Dungeon level drives card rarity: it is simply the summoning budget.
func dungeon_level() -> int:
	return dm_budget()
