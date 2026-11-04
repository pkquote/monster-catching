class_name MapBuilder
extends RefCounted
## Builds a map .tscn from an ASCII layout and a list of pieces. Used by
## tools/build_maps.gd to rough out the starter maps; after that, maps are
## edited in the Godot editor like any other scene (the builder never
## overwrites an existing map unless forced).
##
## Layout legend (one character per tile):
##   .  floor        #  wall        g  grass       w  tall grass   p  path
##   s  sand         ~  water       R  roof        D  door         c  carpet
##   C  counter      T  table       t  tree*       f  fence*       F  flowers
##   S  sign*        (space) nothing
##   * drawn on Decor over grass.

const TILESET := "res://game/maps/tiles/placeholder_tileset.tres"
const PIECES := "res://game/overworld/pieces/%s.tscn"

## char -> [ground tile, decor tile or null]
static func legend() -> Dictionary:
	return {
		".": [TileIds.FLOOR, null], "#": [TileIds.WALL, null], "g": [TileIds.GRASS, null],
		"w": [TileIds.TALL_GRASS, null], "p": [TileIds.PATH, null], "s": [TileIds.SAND, null],
		"~": [TileIds.WATER, null], "R": [TileIds.ROOF, null], "D": [TileIds.DOOR, null],
		"c": [TileIds.CARPET, null], "C": [TileIds.COUNTER, null], "T": [TileIds.TABLE, null],
		"t": [TileIds.GRASS, TileIds.TREE], "f": [TileIds.GRASS, TileIds.FENCE],
		"F": [TileIds.FLOWERS, null], "S": [TileIds.GRASS, TileIds.SIGN],
	}


## def: { id, display_name, default_encounter?, indoor?, rows: Array[String],
##        pieces: Array[{ type, name, at: [x, y], props?: {} }] }
## Returns the saved path, or "" when the map exists and `force` is false.
static func build(def: Dictionary, force := false) -> String:
	var path := GameMap.path_of(def.id)
	if ResourceLoader.exists(path) and not force:
		return ""
	var root := make_empty(def.get("display_name", ""), def.get("default_encounter", ""), def.get("indoor", false))
	root.name = _pascal(def.id)
	var ground: TileMapLayer = root.get_node("Ground")
	var decor: TileMapLayer = root.get_node("Decor")
	var key := legend()
	for y in def.rows.size():
		var row: String = def.rows[y]
		for x in row.length():
			var ch := row[x]
			if not key.has(ch):
				continue
			ground.set_cell(Vector2i(x, y), TileIds.SOURCE, key[ch][0])
			if key[ch][1] != null:
				decor.set_cell(Vector2i(x, y), TileIds.SOURCE, key[ch][1])
	var entities: Node2D = root.get_node("Entities")
	for p in def.get("pieces", []):
		var node: Node2D = load(PIECES % p.type).instantiate()
		node.name = p.name
		node.position = GameMap.centre_of(Vector2i(p.at[0], p.at[1]))
		for prop in p.get("props", {}):
			node.set(prop, p.props[prop])
		entities.add_child(node)
		node.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, path)
	root.free()
	return path if err == OK else ""


## A GameMap with the four standard layers, ready to paint.
static func make_empty(display_name := "", default_encounter := "", indoor := false) -> GameMap:
	var root := GameMap.new()
	root.display_name = display_name
	root.default_encounter = default_encounter
	root.indoor = indoor
	var ts: TileSet = load(TILESET)
	for layer_name in ["Ground", "Decor"]:
		var l := TileMapLayer.new()
		l.name = layer_name
		l.tile_set = ts
		root.add_child(l)
		l.owner = root
	var entities := Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	root.add_child(entities)
	entities.owner = root
	var above := TileMapLayer.new()
	above.name = "Above"
	above.tile_set = ts
	above.z_index = 10
	root.add_child(above)
	above.owner = root
	return root


static func _pascal(id: String) -> String:
	return "".join(Array(id.split("_")).map(func(s: String): return s.capitalize()))
