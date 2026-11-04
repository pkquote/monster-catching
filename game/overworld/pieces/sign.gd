@tool
class_name Sign
extends Piece
## Accept while facing it: shows `text`.

@export_multiline var text := ""


func _ready() -> void:
	super()
	add_blocker()


func blocks() -> bool:
	return true


func on_interact(w: Overworld) -> void:
	await w.say_lines([{"speaker": "", "text": text}])


func _draw() -> void:
	super()
	draw_rect(Rect2(-11, -10, 22, 13), Color("a07a4f"))
	draw_rect(Rect2(-2, 3, 4, 10), Color("6b4a2f"))


func marker_color() -> Color:
	return Color("c0a080")
