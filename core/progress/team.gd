class_name Team
extends RefCounted
## Party and storage box rules. Each operation returns "" on success or a reason.
## The party must always keep at least one healthy (hp > 0) creature.


## Moves the creature at `from` to index `to`, shifting the others.
static func reorder(save: SaveGame, from: int, to: int) -> String:
	return _report("reorder", _reorder(save, from, to), {"from": from, "to": to})


## Moves a party creature into the first empty box slot.
static func deposit(db: Database, save: SaveGame, party_i: int) -> String:
	var reason := ""
	if party_i < 0 or party_i >= save.party.size():
		reason = "bad_index"
	else:
		var slot := BoxStorage.first_empty(save)
		reason = "box_full" if slot < 0 else _move(db, save, {"party": party_i}, {"box": slot})
	return _report("deposit", reason, {"party": party_i})


## Moves a box creature (by slot) to the end of the party.
static func withdraw(db: Database, save: SaveGame, box_i: int) -> String:
	return _report("withdraw", _move(db, save, {"box": box_i}, {"party": save.party.size()}), {"box": box_i})


## Exchanges a party creature with a box creature (by slot), each taking the other's place.
static func swap(db: Database, save: SaveGame, party_i: int, box_i: int) -> String:
	var reason := "bad_index"
	if BoxStorage.creature_at(save, box_i) != null:
		reason = _move(db, save, {"party": party_i}, {"box": box_i})
	return _report("swap", reason, {"party": party_i, "box": box_i})


## Moves one creature between locations. A location is {"party": i} or {"box": slot};
## {"party": party.size()} is the place just past the last member. An empty destination
## receives the creature; an occupied one swaps; a party slot reorders. Returns "" or one of
## bad_index, same_slot, party_full, last_healthy.
static func move(db: Database, save: SaveGame, from: Dictionary, to: Dictionary) -> String:
	return _report("move", _move(db, save, from, to), {"from": from, "to": to})


## Places several creatures, in order, into the next empty slots from `to` (a box slot, reading
## order across boxes with no wrap; or {"party": _}, appended while there is room). Never swaps.
## Returns {reason, moved, short}; nothing moves unless reason is "".
static func move_group(db: Database, save: SaveGame, froms: Array, to: Dictionary) -> Dictionary:
	var r := _move_group(db, save, froms, to)
	_report("move_group", r.reason, {"count": froms.size(), "to": to, "moved": r.moved, "short": r.short})
	return r


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


static func _creature_at(save: SaveGame, loc: Dictionary) -> CreatureInstance:
	if loc.has("party"):
		var i: int = loc.party
		return save.party[i] if i >= 0 and i < save.party.size() else null
	return BoxStorage.creature_at(save, int(loc.get("box", -1)))


static func _is_party(loc: Dictionary) -> bool:
	return loc.has("party")


static func _move(db: Database, save: SaveGame, from: Dictionary, to: Dictionary) -> String:
	var mover := _creature_at(save, from)
	if mover == null:
		return "bad_index"
	var n := save.party.size()
	if _is_party(to):
		var ti: int = to.party
		if ti < 0 or ti > n:
			return "bad_index"
	else:
		var ts: int = int(to.get("box", -1))
		if ts < 0 or ts >= save.storage.size():
			return "bad_index"
	if from == to:
		return "same_slot"
	var target := _creature_at(save, to)
	if _is_party(from) and _is_party(to):
		var dest: int = mini(int(to.party), n - 1)  # "past the end" means the last place
		if dest == int(from.party):
			return "same_slot"
		return _reorder(save, int(from.party), dest)
	if _is_party(from):  # party -> box
		if healthy_after(save, mover, target) < 1:
			return "last_healthy"
		save.storage[int(to.box)] = mover
		if target != null:
			save.party[int(from.party)] = target
		else:
			save.party.remove_at(int(from.party))
		return ""
	if _is_party(to):  # box -> party
		if target == null:
			if n >= int(db.balance.party_size):
				return "party_full"
			save.party.append(mover)
			save.storage[int(from.box)] = null
			return ""
		if healthy_after(save, target, mover) < 1:
			return "last_healthy"
		save.party[int(to.party)] = mover
		save.storage[int(from.box)] = target
		return ""
	# box -> box
	save.storage[int(to.box)] = mover
	save.storage[int(from.box)] = target
	return ""


static func _move_group(db: Database, save: SaveGame, froms: Array, to: Dictionary) -> Dictionary:
	var fail := func(reason: String, short := 0) -> Dictionary:
		return {"reason": reason, "moved": 0, "short": short}
	var movers: Array = []
	var seen := {}
	for f: Dictionary in froms:
		var c := _creature_at(save, f)
		if c == null or seen.has(c):
			return fail.call("bad_index")
		seen[c] = true
		movers.append(c)
	if movers.is_empty():
		return fail.call("bad_index")
	var to_party := _is_party(to)
	if to_party:
		if froms.any(func(f: Dictionary) -> bool: return _is_party(f)):
			return fail.call("bad_index")  # party to party is a reorder, not a group move
	else:
		var ts: int = int(to.get("box", -1))
		if ts < 0 or ts >= save.storage.size():
			return fail.call("bad_index")
	# Healthy creatures left in the party once the group has moved.
	var leaving: Array = froms.filter(func(f: Dictionary) -> bool: return _is_party(f)).map(
		func(f: Dictionary) -> CreatureInstance: return save.party[int(f.party)])
	var healthy := 0
	for c: CreatureInstance in save.party:
		if not leaving.has(c) and c.hp > 0:
			healthy += 1
	if to_party:
		for c: CreatureInstance in movers:
			if c.hp > 0:
				healthy += 1
	if healthy < 1:
		return fail.call("last_healthy")
	var slots: Array = []
	if to_party:
		var room := maxi(int(db.balance.party_size) - save.party.size(), 0)
		if movers.size() > room:
			return fail.call("no_room", movers.size() - room)
	else:
		var at := int(to.box)
		while slots.size() < movers.size():
			at = BoxStorage.first_empty(save, at)
			if at < 0:
				break
			slots.append(at)
			at += 1
		if slots.size() < movers.size():
			return fail.call("no_room", movers.size() - slots.size())
	for f: Dictionary in froms:
		if not _is_party(f):
			save.storage[int(f.box)] = null
	for c: CreatureInstance in leaving:
		save.party.erase(c)
	for i in movers.size():
		if to_party:
			save.party.append(movers[i])
		else:
			save.storage[slots[i]] = movers[i]
	return {"reason": "", "moved": movers.size(), "short": 0}


## Healthy party count if `removed` left the party and `added` joined it (either may be null).
static func healthy_after(save: SaveGame, removed: CreatureInstance, added: CreatureInstance) -> int:
	var n := 0
	for c: CreatureInstance in save.party:
		if c != removed and c.hp > 0:
			n += 1
	if added != null and added.hp > 0:
		n += 1
	return n
