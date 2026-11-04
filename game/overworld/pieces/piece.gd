@tool
class_name Piece
extends Node2D
## Base for everything placed on a map's Entities node (doors, NPCs, items...).
## Snaps to the 32px tile grid in the editor and draws an editor-only marker.
## Pieces hold no rules: they call Story / the overworld.

## Tiles covered, counted from this piece's tile to the right and down.
var size_tiles := Vector2i.ONE


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_snap()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_snap()


func _snap() -> void:
	var snapped := GameMap.centre_of(GameMap.tile_of(position))
	if position != snapped:
		position = snapped
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var half := GameMap.TILE / 2.0
	var r := Rect2(Vector2(-half, -half), Vector2(size_tiles * GameMap.TILE))
	draw_rect(r, Color(marker_color(), 0.25))
	draw_rect(r, marker_color(), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-half + 2, -half + 10), marker_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9)


## The overworld this piece's map is in, or null (editor, tests without one).
func world() -> Node:
	var m := _map()
	return m.get_parent() if m != null and m.get_parent() != null and m.get_parent().has_method("change_map") else null


## Adds a solid body on this piece's tile at runtime (NPCs, item balls, signs).
func add_blocker() -> void:
	if Engine.is_editor_hint() or has_node("Blocker"):
		return
	var body := StaticBody2D.new()
	body.name = "Blocker"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 28)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)


func remove_blocker() -> void:
	if has_node("Blocker"):
		get_node("Blocker").queue_free()


## The tile this piece sits on (its top-left tile when it covers several).
func tile() -> Vector2i:
	return GameMap.tile_of(position)


func covers(t: Vector2i) -> bool:
	return Rect2i(tile(), size_tiles).has_point(t)


func area() -> int:
	return size_tiles.x * size_tiles.y


## "<map_id>/<path under Entities>", e.g. "route_01/Potion1". Used to remember
## collected items, beaten tamers and one-time triggers.
func save_key() -> String:
	var map := _map()
	if map == null:
		return name
	return "%s/%s" % [map.map_id(), map.entities().get_path_to(self)]


func _map() -> GameMap:
	var n := get_parent()
	while n != null and not n is GameMap:
		n = n.get_parent()
	return n as GameMap


# --- Overridden by piece types --------------------------------------------------

## Accept pressed while the player faces this piece's tile.
func on_interact(_world: Node) -> void:
	pass


## The player's feet entered one of this piece's tiles.
func on_enter(_world: Node) -> void:
	pass


## Markers (spawns, areas) only describe the map; piece_at() skips them.
func is_marker() -> bool:
	return false


## Whether the player can't walk through this tile (NPCs, counters).
func blocks() -> bool:
	return false


func marker_color() -> Color:
	return Color.WHITE


func marker_label() -> String:
	return name
