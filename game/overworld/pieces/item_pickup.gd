@tool
class_name ItemPickup
extends Piece
## A visible item on the ground. Accept: it goes in the bag, once per playthrough.

@export var item := "":
	set(v):
		item = v
		queue_redraw()
@export_range(1, 99) var count := 1


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	if Story.is_done(save_key()):
		queue_free()
		return
	add_blocker()


func blocks() -> bool:
	return not Story.is_done(save_key())


func on_interact(w: Node) -> void:
	if Story.is_done(save_key()):
		return
	Story.give_item(item, count)
	Story.mark_done(save_key())
	visible = false
	remove_blocker()
	await w.say_lines([{"speaker": "", "text": found_text(item, count)}])
	queue_free()


static func found_text(item_id: String, n: int) -> String:
	var it := DataRegistry.db.item(item_id)
	var item_name: String = it.name if it != null else item_id
	return "Found a %s!" % item_name if n == 1 else "Found %s ×%d!" % [item_name, n]


func _draw() -> void:
	super()
	draw_circle(Vector2(0, 2), 8, Color("e2675c"))
	draw_rect(Rect2(-8, 1, 16, 2), Color("2b2b2b"))
	draw_circle(Vector2(0, 2), 2.5, Color("f0f0f0"))


func marker_color() -> Color:
	return Color("e2675c")


func marker_label() -> String:
	return item
