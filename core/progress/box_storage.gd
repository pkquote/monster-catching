class_name BoxStorage
extends RefCounted
## Slot-addressed creature boxes. `SaveGame.storage` is a fixed-length array of
## `boxes_unlocked * BOX_SIZE` entries, each a CreatureInstance or null (empty).
## Creatures stay in the slot they were placed in. All static.

const BOX_SIZE := 30
const COLUMNS := 6
const START_BOXES := 8
const MAX_BOXES := 32


static func slot_count(save: SaveGame) -> int:
	return save.storage.size()


static func box_count(save: SaveGame) -> int:
	return save.boxes_unlocked


static func box_of(slot: int) -> int:
	return slot / BOX_SIZE


static func index_in_box(slot: int) -> int:
	return slot % BOX_SIZE


static func slot_of(box: int, index: int) -> int:
	return box * BOX_SIZE + index


## The creature in `slot`, or null when it is empty or out of range.
static func creature_at(save: SaveGame, slot: int) -> CreatureInstance:
	if slot < 0 or slot >= save.storage.size():
		return null
	return save.storage[slot]


## The first empty slot at or after `from` (no wrap), or -1.
static func first_empty(save: SaveGame, from: int = 0) -> int:
	for i in range(maxi(from, 0), save.storage.size()):
		if save.storage[i] == null:
			return i
	return -1


static func count(save: SaveGame) -> int:
	var n := 0
	for c in save.storage:
		if c != null:
			n += 1
	return n


static func empty_count(save: SaveGame) -> int:
	return save.storage.size() - count(save)


## Every stored creature in slot order.
static func all_creatures(save: SaveGame) -> Array:
	return save.storage.filter(func(c): return c != null)


## Puts `c` in the first empty slot. False when every slot is taken.
static func add(save: SaveGame, c: CreatureInstance) -> bool:
	var i := first_empty(save)
	if i < 0:
		return false
	save.storage[i] = c
	return true


## Opens one more box. False at MAX_BOXES.
static func unlock_box(save: SaveGame) -> bool:
	if save.boxes_unlocked >= MAX_BOXES:
		return false
	ensure_boxes(save, save.boxes_unlocked + 1)
	return true


## Grows to at least `boxes` boxes (capped at MAX_BOXES); never shrinks.
static func ensure_boxes(save: SaveGame, boxes: int) -> void:
	var want := mini(boxes, MAX_BOXES)
	if want > save.boxes_unlocked:
		save.boxes_unlocked = want
	pad(save)


## Pads `storage` with nulls up to the unlocked slot count.
static func pad(save: SaveGame) -> void:
	var want := save.boxes_unlocked * BOX_SIZE
	while save.storage.size() < want:
		save.storage.append(null)
