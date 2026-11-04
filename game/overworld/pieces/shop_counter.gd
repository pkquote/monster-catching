@tool
class_name ShopCounter
extends Piece
## Accept while facing it: opens the shop with `stock` (item ids; prices come
## from each item's `price`).

@export var stock: PackedStringArray = []


func on_interact(w: Node) -> void:
	w.open_shop(stock)


func marker_color() -> Color:
	return Color("80c0ff")


func marker_label() -> String:
	return "shop (%d)" % stock.size()
