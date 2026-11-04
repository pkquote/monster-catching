@tool
class_name EncounterArea
extends Piece
## Tall grass inside this rectangle uses `encounter` instead of the map's
## default table (rarer creatures in a far patch, a cave corner...).

@export var encounter := "":
	set(v):
		encounter = v
		queue_redraw()
@export var size := Vector2i.ONE:
	set(v):
		size = Vector2i(maxi(1, v.x), maxi(1, v.y))
		size_tiles = size
		queue_redraw()


func _init() -> void:
	size_tiles = size


func is_marker() -> bool:
	return true


func marker_color() -> Color:
	return Color("60d080")


func marker_label() -> String:
	return "encounter: " + encounter
