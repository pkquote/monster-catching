class_name FieldItems
extends RefCounted
## Using items outside battle (the pause menu's Bag). Supports healing items whose
## effects are `heal` and/or `restore_energy` with a `fraction` of the maximum.

const OPS := ["heal", "restore_energy"]


static func can_use(db: Database, item_id: String) -> bool:
	var it := db.item(item_id)
	if it == null or it.category != "heal" or it.effects.is_empty():
		return false
	return it.effects.all(func(e): return e.op in OPS and e.has("fraction"))


## Uses one `item_id` from the bag on `c`. Returns { ok, error, healed, energy };
## errors: "not_usable", "none_left", "fainted", "no_effect" (nothing to restore).
static func use(db: Database, save: SaveGame, item_id: String, c: CreatureInstance) -> Dictionary:
	var out := {"ok": false, "error": "", "healed": 0, "energy": 0}
	if not can_use(db, item_id):
		out.error = "not_usable"
		return out
	if int(save.inventory.get(item_id, 0)) <= 0:
		out.error = "none_left"
		return out
	if c.hp <= 0:
		out.error = "fainted"
		return out
	for e in db.item(item_id).effects:
		match e.op:
			"heal":
				var max_hp := c.max_hp(db)
				out.healed = mini(maxi(1, roundi(max_hp * float(e.fraction))), max_hp - c.hp)
			"restore_energy":
				var max_e := c.max_energy(db)
				out.energy = mini(maxi(1, roundi(max_e * float(e.fraction))), max_e - c.energy)
	if out.healed <= 0 and out.energy <= 0:
		out.healed = 0
		out.energy = 0
		out.error = "no_effect"
		return out
	c.hp += out.healed
	c.energy += out.energy
	save.inventory[item_id] = int(save.inventory[item_id]) - 1
	if save.inventory[item_id] == 0:
		save.inventory.erase(item_id)
	out.ok = true
	return out
