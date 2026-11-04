@tool
class_name StorageBox
extends Piece
## A solid terminal. Accept while facing it opens the creature storage.


func _ready() -> void:
	super()
	add_blocker()


func blocks() -> bool:
	return true


func on_interact(w: Node) -> void:
	await w.open_storage()


func _draw() -> void:
	super()
	draw_rect(Rect2(-11, -11, 22, 22), Color("5070a0"))
	draw_rect(Rect2(-8, -8, 16, 6), Color("a0c0e0"))


func marker_color() -> Color:
	return Color("6090d0")


func marker_label() -> String:
	return "storage"
