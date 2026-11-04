@tool
class_name HiddenItem
extends Piece
## An item nobody can see. Accept while facing its tile finds it, once per playthrough.

@export var item := "":
	set(v):
		item = v
		queue_redraw()
@export_range(1, 99) var count := 1


func on_interact(w: Node) -> void:
	if Story.is_done(save_key()):
		return
	Story.give_item(item, count)
	Story.mark_done(save_key())
	await w.say_lines([{"speaker": "", "text": ItemPickup.found_text(item, count)}])


func marker_color() -> Color:
	return Color("a060e0")


func marker_label() -> String:
	return "hidden: " + item
