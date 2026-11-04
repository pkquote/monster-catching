@tool
class_name UnsafeArea
extends Piece
## Marks a rectangle where it isn't safe to use the Storage box, switch the
## active creature or run other safe-zone-only actions. See GameMap.unsafe_at().

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
	return Color("e05050")


func marker_label() -> String:
	return "unsafe"
