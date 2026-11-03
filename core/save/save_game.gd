class_name SaveGame
extends RefCounted
## Everything a save file holds. Pure data; SaveStore handles files.

const SCHEMA := 1
const KIND_MANUAL := "manual"
const KIND_AUTO := "auto"

var playthrough_id: String = ""
var kind: String = KIND_MANUAL
var player_name: String = ""
var created_unix: int = 0
var saved_unix: int = 0
var playtime_sec: float = 0.0
## Human-readable place name shown in the save browser.
var location: String = ""
## Array[CreatureInstance]
var party: Array = []
var storage: Array = []
## item id -> count
var inventory: Dictionary = {}
var money: int = 0
## Story flags and counters (see core/story later).
var flags: Dictionary = {}


static func new_game(player: String, now_unix: int, rng: RandomNumberGenerator) -> SaveGame:
	var s := SaveGame.new()
	s.playthrough_id = "%d_%06x" % [now_unix, rng.randi() & 0xFFFFFF]
	s.player_name = player
	s.created_unix = now_unix
	s.saved_unix = now_unix
	s.location = "Nowhere yet"
	return s


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"playthrough_id": playthrough_id,
		"kind": kind,
		"player_name": player_name,
		"created_unix": created_unix,
		"saved_unix": saved_unix,
		"playtime_sec": playtime_sec,
		"location": location,
		"party": party.map(func(c: CreatureInstance): return c.to_dict()),
		"storage": storage.map(func(c: CreatureInstance): return c.to_dict()),
		"inventory": inventory.duplicate(),
		"money": money,
		"flags": flags.duplicate(true),
	}


## Builds a SaveGame from a dictionary already migrated to SCHEMA.
## Returns null if required fields are missing or the wrong type.
static func from_dict(d: Dictionary) -> SaveGame:
	for key in ["playthrough_id", "player_name", "created_unix", "saved_unix"]:
		if not d.has(key):
			return null
	if not d.playthrough_id is String or (d.playthrough_id as String).is_empty():
		return null
	var s := SaveGame.new()
	s.playthrough_id = d.playthrough_id
	s.kind = d.get("kind", KIND_MANUAL)
	s.player_name = str(d.player_name)
	s.created_unix = int(d.created_unix)
	s.saved_unix = int(d.saved_unix)
	s.playtime_sec = float(d.get("playtime_sec", 0.0))
	s.location = str(d.get("location", ""))
	for c in d.get("party", []):
		s.party.append(CreatureInstance.from_dict(c))
	for c in d.get("storage", []):
		s.storage.append(CreatureInstance.from_dict(c))
	for k in d.get("inventory", {}):
		s.inventory[k] = int(d.inventory[k])
	s.money = int(d.get("money", 0))
	s.flags = d.get("flags", {}).duplicate(true)
	return s


## "1h 02m" / "12m 05s"
static func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	var sec := total % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, sec]
