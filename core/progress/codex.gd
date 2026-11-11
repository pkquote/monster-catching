class_name Codex
extends RefCounted
## Which species the player has seen and caught. Lives in SaveGame.codex:
## species id -> { "seen": bool, "caught": bool }. Absence means unseen; caught implies seen.


## Marks `species` seen. Returns true when the record changed.
static func mark_seen(save: SaveGame, species: String) -> bool:
	var entry: Dictionary = save.codex.get(species, {})
	if entry.get("seen", false):
		return false
	save.codex[species] = {"seen": true, "caught": bool(entry.get("caught", false))}
	return true


## Marks `species` caught (and seen). Returns true when the record changed.
static func mark_caught(save: SaveGame, species: String) -> bool:
	var entry: Dictionary = save.codex.get(species, {})
	if entry.get("caught", false):
		return false
	save.codex[species] = {"seen": true, "caught": true}
	return true


static func seen(save: SaveGame, species: String) -> bool:
	return bool(save.codex.get(species, {}).get("seen", false))


static func caught(save: SaveGame, species: String) -> bool:
	return bool(save.codex.get(species, {}).get("caught", false))


## "unseen", "seen" or "caught".
static func status(save: SaveGame, species: String) -> String:
	if caught(save, species):
		return "caught"
	return "seen" if seen(save, species) else "unseen"


static func seen_count(save: SaveGame) -> int:
	return save.codex.values().filter(func(e: Dictionary) -> bool: return e.get("seen", false)).size()


static func caught_count(save: SaveGame) -> int:
	return save.codex.values().filter(func(e: Dictionary) -> bool: return e.get("caught", false)).size()


## Marks every creature in the party and every box as caught (used when an old save loads).
static func backfill(save: SaveGame) -> void:
	for c: CreatureInstance in save.party + BoxStorage.all_creatures(save):
		mark_caught(save, c.species)


## Every creature id in Codex order: numbered species by `dex`, then the rest (no `dex`) by id.
## Debug test content (`Database.is_test_content`) is not part of the Codex.
static func order(db: Database) -> PackedStringArray:
	var ids := Array(db.ids("creatures")).filter(func(id: String) -> bool: return not Database.is_test_content(id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da := db.creature(a).dex
		var dbb := db.creature(b).dex
		if da > 0 and dbb > 0:
			return da < dbb
		if da > 0 or dbb > 0:
			return da > 0
		return a < b)
	return PackedStringArray(ids)


## "#001" for a numbered species, "#---" for one without a `dex`.
static func number_text(db: Database, species: String) -> String:
	var def := db.creature(species)
	return "#%03d" % def.dex if def != null and def.dex > 0 else "#---"
