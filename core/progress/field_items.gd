class_name FieldItems
extends RefCounted
## Using items outside battle (the pause menu's Bag). Supports healing items whose
## effects are `heal` and/or `restore_energy` with a `fraction` of the maximum, and
## training items whose effect is `reset_training`.

const OPS := ["heal", "restore_energy"]


static func can_use(db: Database, item_id: String) -> bool:
	var it := db.item(item_id)
	if it == null or it.effects.is_empty():
		return false
	if it.category == "training":
		return it.effects.all(func(e): return e.op == "reset_training")
	if it.category != "heal":
		return false
	return it.effects.all(func(e): return e.op in OPS and e.has("fraction"))


## Whether `item_id` can be used from the bag right now, and why not. Returns { ok, reason }.
## Pure and consistent with `can_use`/`use`: ok means `use` would succeed on some party member
## (so it is false when the bag holds none of the item).
static func usability(db: Database, save: SaveGame, item_id: String) -> Dictionary:
	var it := db.item(item_id)
	if it == null:
		return _usability(false, "Unknown item.")
	match it.category:
		"held":
			return _usability(false, "Give it from the Summary.")
		"capture", "battle":
			return _usability(false, "Used in battle.")
		"key":
			return _usability(false, "Can't be used.")
	if not can_use(db, item_id):
		return _usability(false, "Can't be used here.")
	if int(save.inventory.get(item_id, 0)) <= 0:
		return _usability(false, "You don't have any.")
	if it.category == "training":
		for m: CreatureInstance in save.party:
			if Training.spent(m) > 0:
				return _usability(true, "Usable now.")
		return _usability(false, "No one has training points to return.")
	for m: CreatureInstance in save.party:
		if m.hp <= 0:
			continue
		if _would_gain(db, it, m):
			return _usability(true, "Usable now.")
	return _usability(false, "No one needs it right now.")


static func _would_gain(db: Database, it: ItemDef, m: CreatureInstance) -> bool:
	for e: Dictionary in it.effects:
		if e.op == "heal" and m.hp < m.max_hp(db):
			return true
		if e.op == "restore_energy" and m.energy < m.max_energy(db):
			return true
	return false


static func _usability(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}


## Uses one `item_id` from the bag on `c`. Returns { ok, error, healed, energy, refunded };
## errors: "not_usable", "none_left", "fainted", "no_effect" (nothing to restore),
## "nothing_to_refund" (Reset Seed on a creature with no training). A failed use spends nothing.
static func use(db: Database, save: SaveGame, item_id: String, c: CreatureInstance) -> Dictionary:
	var out := {"ok": false, "error": "", "healed": 0, "energy": 0, "refunded": 0}
	if not can_use(db, item_id):
		out.error = "not_usable"
		return out
	if int(save.inventory.get(item_id, 0)) <= 0:
		out.error = "none_left"
		return out
	if db.item(item_id).category == "training":
		if Training.spent(c) <= 0:
			out.error = "nothing_to_refund"
			return out
		out.refunded = Training.reset(db, c)
		_spend(save, item_id)
		out.ok = true
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
	_spend(save, item_id)
	out.ok = true
	return out


static func _spend(save: SaveGame, item_id: String) -> void:
	save.inventory[item_id] = int(save.inventory[item_id]) - 1
	if save.inventory[item_id] == 0:
		save.inventory.erase(item_id)
