extends Node
## Runtime state shared between scenes (not persisted).

var party_ids: Array = []
var difficulty: float = 1.0
var difficulty_name: String = "Normal"
var last_result_lines: Array[String] = []
var last_result_won: bool = false


func dm_budget() -> int:
	var total := 0
	for id in party_ids:
		var h: Dictionary = Save.hero_by_id(id)
		if not h.is_empty():
			total += h.level
	var bonus: int = int((Save.dm_level() - 1) / 2)
	return maxi(2, int(ceil(total * difficulty)) + bonus)
