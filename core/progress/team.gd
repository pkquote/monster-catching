class_name Team
extends RefCounted
## Party and storage box rules. Each operation returns "" on success or a reason.
## The party must always keep at least one healthy (hp > 0) creature.


## Moves the creature at `from` to index `to`, shifting the others.
static func reorder(save: SaveGame, from: int, to: int) -> String:
	return _report("reorder", _reorder(save, from, to), {"from": from, "to": to})


## Moves a party creature to the end of the box.
static func deposit(db: Database, save: SaveGame, party_i: int) -> String:
	return _report("deposit", _deposit(db, save, party_i), {"party": party_i})


## Moves a box creature to the end of the party.
static func withdraw(db: Database, save: SaveGame, box_i: int) -> String:
	return _report("withdraw", _withdraw(db, save, box_i), {"box": box_i})


## Exchanges a party creature with a box creature, each taking the other's slot.
static func swap(db: Database, save: SaveGame, party_i: int, box_i: int) -> String:
	return _report("swap", _swap(db, save, party_i, box_i), {"party": party_i, "box": box_i})


static func _report(op: String, reason: String, data: Dictionary) -> String:
	data["op"] = op
	if reason == "":
		Log.debug(Log.PROGRESS, "Storage " + op, data)
	else:
		data["reason"] = reason
		Log.debug(Log.PROGRESS, "Storage refused", data)
	return reason


## Moves the creature at `from` to index `to`, shifting the others.
static func _reorder(save: SaveGame, from: int, to: int) -> String:
	var n := save.party.size()
	if from < 0 or from >= n or to < 0 or to >= n:
		return "bad_index"
	var c: CreatureInstance = save.party[from]
	save.party.remove_at(from)
	save.party.insert(to, c)
	return ""


## Moves a party creature to the end of the box.
static func _deposit(_db: Database, save: SaveGame, party_i: int) -> String:
	if party_i < 0 or party_i >= save.party.size():
		return "bad_index"
	if healthy_after(save, save.party[party_i], null) < 1:
		return "last_healthy"
	save.storage.append(save.party[party_i])
	save.party.remove_at(party_i)
	return ""


## Moves a box creature to the end of the party.
static func _withdraw(db: Database, save: SaveGame, box_i: int) -> String:
	if box_i < 0 or box_i >= save.storage.size():
		return "bad_index"
	if save.party.size() >= int(db.balance.party_size):
		return "party_full"
	save.party.append(save.storage[box_i])
	save.storage.remove_at(box_i)
	return ""


## Exchanges a party creature with a box creature, each taking the other's slot.
static func _swap(_db: Database, save: SaveGame, party_i: int, box_i: int) -> String:
	if party_i < 0 or party_i >= save.party.size() or box_i < 0 or box_i >= save.storage.size():
		return "bad_index"
	var out: CreatureInstance = save.party[party_i]
	var incoming: CreatureInstance = save.storage[box_i]
	if healthy_after(save, out, incoming) < 1:
		return "last_healthy"
	save.party[party_i] = incoming
	save.storage[box_i] = out
	return ""


## Healthy party count if `removed` left the party and `added` joined it (either may be null).
static func healthy_after(save: SaveGame, removed: CreatureInstance, added: CreatureInstance) -> int:
	var n := 0
	for c: CreatureInstance in save.party:
		if c != removed and c.hp > 0:
			n += 1
	if added != null and added.hp > 0:
		n += 1
	return n
