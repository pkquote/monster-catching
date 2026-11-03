class_name Field
extends RefCounted
## The field states held by one side, oldest first.

## Array of { id: String, stacks: int, turns: int }
var states: Array = []


func has(id: String) -> bool:
	return _index(id) != -1


func stacks(id: String) -> int:
	var i := _index(id)
	return 0 if i == -1 else states[i].stacks


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in states:
		out.append(s.id)
	return out


func size() -> int:
	return states.size()


## Adds stacks to an existing state (refreshing its duration) or appends a new one.
## Returns the resulting stack count.
func add(id: String, add_stacks: int, turns: int, max_stacks: int) -> int:
	var i := _index(id)
	if i == -1:
		states.append({"id": id, "stacks": mini(add_stacks, max_stacks), "turns": turns})
		return states.back().stacks
	states[i].stacks = mini(states[i].stacks + add_stacks, max_stacks)
	states[i].turns = maxi(states[i].turns, turns)
	return states[i].stacks


## Removes a state; returns the stacks it had (0 if absent).
func remove(id: String) -> int:
	var i := _index(id)
	if i == -1:
		return 0
	var n: int = states[i].stacks
	states.remove_at(i)
	return n


## Removes and returns the oldest state id ("" if empty).
func pop_oldest() -> String:
	if states.is_empty():
		return ""
	var id: String = states[0].id
	states.remove_at(0)
	return id


## Counts every state down one round. Returns ids that expired.
func tick() -> PackedStringArray:
	var expired := PackedStringArray()
	for s in states:
		s.turns -= 1
		if s.turns <= 0:
			expired.append(s.id)
	for id in expired:
		remove(id)
	return expired


func snapshot() -> Array:
	return states.duplicate(true)


func _index(id: String) -> int:
	for i in states.size():
		if states[i].id == id:
			return i
	return -1
