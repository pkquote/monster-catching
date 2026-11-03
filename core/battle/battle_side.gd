class_name BattleSide
extends RefCounted
## One team in a battle: its roster, the field slots in use, and its field states.

var index: int
## Every battler on this team, in party order.
var battlers: Array[Battler] = []
## Field slots. Each entry is a Battler or null (empty). Size = creatures fielded.
var slots: Array = []
var max_active: int
var field := Field.new()
## item id -> count
var items: Dictionary = {}
## "" = actions come from the caller (the player); otherwise an AI style.
var ai: String = ""
var is_wild := false
## Fill empty slots automatically at end of round (AI and wild sides always do).
var auto_replace := false
## Current Underdog values (see Underdog.compute).
var underdog: Dictionary = {}


## Active, living battlers in slot order.
func active() -> Array[Battler]:
	var out: Array[Battler] = []
	for b in slots:
		if b != null and b.alive():
			out.append(b)
	return out


## Healthy battlers not currently on the field.
func bench() -> Array[Battler]:
	var out: Array[Battler] = []
	for b in battlers:
		if b.alive() and not b.active:
			out.append(b)
	return out


func defeated() -> bool:
	for b in battlers:
		if b.alive():
			return false
	return true


## Indices of slots that are empty or hold a fainted/captured battler.
func open_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] == null or not slots[i].alive():
			out.append(i)
	return out


func slot_of(b: Battler) -> int:
	return slots.find(b)


func is_ai() -> bool:
	return ai != ""
