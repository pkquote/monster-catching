class_name ProgressEntry
extends RefCounted
## One creature that gained a level in a battle (or through a debug tool): the
## moves it was offered without a free slot, and whether it is now ready to grow.
## Built by Progression.progress_entry; shown by the after-battle step (ProgressFlow).

var creature: CreatureInstance
var offered_moves: Array[String] = []
var growth_due := false


func _init(p_creature: CreatureInstance = null, p_offered: Array[String] = [], p_growth_due := false) -> void:
	creature = p_creature
	offered_moves = p_offered.duplicate()
	growth_due = p_growth_due
