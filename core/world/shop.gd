class_name Shop
extends RefCounted
## Buying and selling items for money. Results are { ok: bool, error: String }:
## "bad_amount" (outside 1..99), "unknown_item", "not_enough_money",
## "not_enough_items", "cannot_sell" (items with no price).

const MAX_AMOUNT := 99


static func buy(db: Database, save: SaveGame, item_id: String, n: int) -> Dictionary:
	if n < 1 or n > MAX_AMOUNT:
		return _fail("bad_amount")
	var it := db.item(item_id)
	if it == null:
		return _fail("unknown_item")
	var cost := it.price * n
	if save.money < cost:
		return _fail("not_enough_money")
	save.money -= cost
	save.inventory[item_id] = int(save.inventory.get(item_id, 0)) + n
	return {"ok": true, "error": ""}


static func sell(db: Database, save: SaveGame, item_id: String, n: int) -> Dictionary:
	if n < 1 or n > MAX_AMOUNT:
		return _fail("bad_amount")
	var each := sell_price(db, item_id)
	if each <= 0:
		return _fail("cannot_sell")
	var owned := int(save.inventory.get(item_id, 0))
	if owned < n:
		return _fail("not_enough_items")
	save.inventory[item_id] = owned - n
	if save.inventory[item_id] == 0:
		save.inventory.erase(item_id)
	save.money += each * n
	return {"ok": true, "error": ""}


## What the shop pays for one: floor(price × sell_fraction); 0 = can't be sold.
static func sell_price(db: Database, item_id: String) -> int:
	var it := db.item(item_id)
	if it == null:
		return 0
	return floori(it.price * float(db.balance.overworld_cfg.sell_fraction))


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
