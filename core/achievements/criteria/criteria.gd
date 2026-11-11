class_name Criteria
extends RefCounted
## The registry of criterion kinds. One line here, one entry in `DataSchemas.CRITERIA` and one
## `Criterion` subclass add a kind.

const KINDS := {
	"counter": preload("res://core/achievements/criteria/counter_criterion.gd"),
	"codex": preload("res://core/achievements/criteria/codex_criterion.gd"),
	"flag": preload("res://core/achievements/criteria/flag_criterion.gd"),
	"creature": preload("res://core/achievements/criteria/creature_criterion.gd"),
}

static var _instances: Dictionary = {}


## The criterion for `kind`, or null when there is no such kind.
static func for_kind(kind: String) -> Criterion:
	if not KINDS.has(kind):
		return null
	if not _instances.has(kind):
		_instances[kind] = KINDS[kind].new()
	return _instances[kind]


static func kinds() -> PackedStringArray:
	return PackedStringArray(KINDS.keys())
