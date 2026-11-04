class_name GameMap
extends Node2D
## Root of every map scene in res://game/maps/. Holds the tile layers and the
## Entities node of pieces, and answers tile questions for the overworld.
##
##   Ground   (TileMapLayer)  floors, grass, paths, water
##   Decor    (TileMapLayer)  fences, flowers, signs; may carry collision
##   Entities (Node2D, y-sorted)  pieces, plus the player while on this map
##   Above    (TileMapLayer)  drawn over the player (roofs, treetops)
##
## See documentation/map-building.md.

const TILE := 32
const MAPS_DIR := "res://game/maps"

## Location label (banner, save browser).
@export var display_name := ""
## Encounter table used by grass tiles on this map ("" = none).
@export var default_encounter := ""
## Indoor maps never roll wild encounters, and the camera centres small ones.
@export var indoor := false
## Unsafe maps are unsafe everywhere (see unsafe_at); otherwise UnsafeArea pieces mark spots.
@export var unsafe := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		_add_edge_walls()


## Invisible walls just outside the painted area, so nobody walks off the map.
func _add_edge_walls() -> void:
	var b := bounds()
	if b.size == Vector2i.ZERO:
		return
	var body := StaticBody2D.new()
	body.name = "EdgeWalls"
	var r := Rect2(Vector2(b.position * TILE), Vector2(b.size * TILE))
	for wall in [
		Rect2(r.position.x - TILE, r.position.y - TILE, r.size.x + 2 * TILE, TILE),
		Rect2(r.position.x - TILE, r.end.y, r.size.x + 2 * TILE, TILE),
		Rect2(r.position.x - TILE, r.position.y, TILE, r.size.y),
		Rect2(r.end.x, r.position.y, TILE, r.size.y),
	]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = wall.size
		shape.shape = rect
		shape.position = wall.get_center()
		body.add_child(shape)
	add_child(body)


static func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


static func centre_of(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE / 2.0)


static func path_of(map_id: String) -> String:
	return MAPS_DIR.path_join(map_id + ".tscn")


static func exists(map_id: String) -> bool:
	return map_id != "" and ResourceLoader.exists(path_of(map_id))


func map_id() -> String:
	return scene_file_path.get_file().get_basename()


func entities() -> Node2D:
	return get_node("Entities")


func layers() -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	for n in ["Ground", "Decor"]:
		var l := get_node_or_null(n) as TileMapLayer
		if l != null:
			out.append(l)
	return out


## The painted area of Ground, in tiles.
func bounds() -> Rect2i:
	var g := get_node_or_null("Ground") as TileMapLayer
	return g.get_used_rect() if g != null else Rect2i()


## True for a tile with collision on any layer, a blocking piece (other than
## `ignore`), or outside the map.
func is_solid(tile: Vector2i, ignore: Piece = null) -> bool:
	if not bounds().has_point(tile):
		return true
	for l in layers():
		var d := l.get_cell_tile_data(tile)
		if d != null and d.get_collision_polygons_count(0) > 0:
			return true
	for p in pieces():
		if p != ignore and p.blocks() and p.covers(tile):
			return true
	return false


## True when a Ground or Decor cell at `tile` has the `encounter` custom data.
func is_encounter_tile(tile: Vector2i) -> bool:
	for l in layers():
		var d := l.get_cell_tile_data(tile)
		if d != null and d.get_custom_data("encounter"):
			return true
	return false


func pieces() -> Array[Piece]:
	var out: Array[Piece] = []
	var stack: Array = [entities()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Piece and not c.is_queued_for_deletion():
				out.append(c)
			stack.append(c)
	return out


## The piece covering `tile` (a Trigger or area may cover several), or null.
## When several overlap, the smallest-area one wins (a pickup inside a trigger).
## Markers (spawns) are never returned: they don't react to anything.
func piece_at(tile: Vector2i) -> Piece:
	var best: Piece = null
	for p in pieces():
		if not p.is_marker() and p.covers(tile) and (best == null or p.area() < best.area()):
			best = p
	return best


## The wild table for a grass tile: the EncounterArea covering it, else the map default.
func encounter_at(tile: Vector2i) -> String:
	for p in pieces():
		if p is EncounterArea and p.covers(tile):
			return (p as EncounterArea).encounter
	return default_encounter


## True when the whole map is unsafe or an UnsafeArea covers `tile`.
func unsafe_at(tile: Vector2i) -> bool:
	if unsafe:
		return true
	for p in pieces():
		if p is UnsafeArea and p.covers(tile):
			return true
	return false


func spawn(id: String) -> Spawn:
	for p in pieces():
		if p is Spawn and (p as Spawn).id == id:
			return p
	return null
