class_name BattlePart
extends RefCounted
## Base for the pieces BattleEngine delegates to (ActionRunner, FieldRules,
## BattleRewards). Holds the engine weakly: the engine owns its parts, and a
## strong reference back would be a cycle that RefCounted never frees.

var _engine: WeakRef

var engine: BattleEngine:
	get:
		return _engine.get_ref()


func _init(p_engine: BattleEngine) -> void:
	_engine = weakref(p_engine)
