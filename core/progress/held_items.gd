class_name HeldItems
extends RefCounted
## Giving a creature a held item from the bag, and taking it back. One item per
## creature (`CreatureInstance.held_item`, "" = none). Pure logic.


## The item definition a creature holds; null when it holds nothing or the id is unknown.
static func def_of(db: Database, c: CreatureInstance) -> ItemDef:
	if c.held_item.is_empty():
		return null
	return db.item(c.held_item)


## Gives `c` one `item_id` from the bag. A held item already there goes back to the bag.
## Returns { ok, error, returned }; errors: "not_held_item", "none_left".
## `returned` is the previous item sent back to the bag ("" if none).
## A failed give changes nothing.
static func give(db: Database, save: SaveGame, c: CreatureInstance, item_id: String) -> Dictionary:
	var out := {"ok": false, "error": "", "returned": ""}
	var it := db.item(item_id)
	if it == null or it.category != "held":
		out.error = "not_held_item"
		return out
	if int(save.inventory.get(item_id, 0)) <= 0:
		out.error = "none_left"
		return out
	_spend(save, item_id)
	if not c.held_item.is_empty():
		_return(save, c.held_item)
		out.returned = c.held_item
	c.held_item = item_id
	out.ok = true
	return out


## Takes `c`'s held item back to the bag. Returns { ok, error }; error: "empty".
static func take(save: SaveGame, c: CreatureInstance) -> Dictionary:
	if c.held_item.is_empty():
		return {"ok": false, "error": "empty"}
	_return(save, c.held_item)
	c.held_item = ""
	return {"ok": true, "error": ""}


static func _spend(save: SaveGame, item_id: String) -> void:
	save.inventory[item_id] = int(save.inventory[item_id]) - 1
	if save.inventory[item_id] == 0:
		save.inventory.erase(item_id)


static func _return(save: SaveGame, item_id: String) -> void:
	save.inventory[item_id] = int(save.inventory.get(item_id, 0)) + 1
