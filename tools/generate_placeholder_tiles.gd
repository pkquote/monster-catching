extends SceneTree
## Generates the placeholder overworld tileset: a 32px tile atlas PNG, its TileSet
## (collision on solid tiles, `encounter` custom data on tall grass) and TileIds.
##
##   godot --headless --path . --script res://tools/generate_placeholder_tiles.gd
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/generate_placeholder_tiles.gd
##
## The first run writes the PNG; Godot must import it before the second run can
## build the TileSet that references it. Real art can later replace the PNG with
## the same layout, and every map keeps working.

const DIR := "res://game/maps/tiles"
const PNG := DIR + "/placeholder.png"
const TILESET := DIR + "/placeholder_tileset.tres"
const IDS := DIR + "/tile_ids.gd"
const T := 32

## name, base colour, solid, encounter, glyph
const TILES := [
	["GRASS", "6fae4f", false, false, ""],
	["TALL_GRASS", "4c8a3a", false, true, "blades"],
	["PATH", "c9b07a", false, false, ""],
	["SAND", "e3d39a", false, false, "dots"],
	["WATER", "3d7cc9", true, false, "waves"],
	["WALL", "8a8f99", true, false, "bricks"],
	["ROOF", "b0473d", true, false, "stripes"],
	["DOOR", "6b4a2f", false, false, "door"],
	["FLOOR", "d8c7a6", false, false, "boards"],
	["CARPET", "8f4f7a", false, false, "border"],
	["COUNTER", "9c6b3f", true, false, "top"],
	["TABLE", "a8794b", true, false, "top"],
	["TREE", "2f6b2f", true, false, "circle"],
	["FENCE", "b8a07a", true, false, "rails"],
	["FLOWERS", "6fae4f", false, false, "flowers"],
	["SIGN", "a07a4f", true, false, "sign"],
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var img := _atlas()
	img.save_png(ProjectSettings.globalize_path(PNG))
	_write_ids()
	print("Wrote ", PNG, " and ", IDS)
	if not ResourceLoader.exists(PNG):
		print("Now run --import, then this tool again to build the TileSet.")
		quit(0)
		return
	var err := ResourceSaver.save(_tileset(load(PNG)), TILESET)
	print("Wrote ", TILESET) if err == OK else printerr("Couldn't save the TileSet: ", err)
	quit(0 if err == OK else 1)


func _atlas() -> Image:
	var img := Image.create(T * TILES.size(), T, false, Image.FORMAT_RGBA8)
	for i in TILES.size():
		var base := Color(TILES[i][1])
		var dark := base.darkened(0.3)
		var x0 := i * T
		img.fill_rect(Rect2i(x0, 0, T, T), base)
		_glyph(img, x0, TILES[i][4], base, dark)
		# 1px darker border so the grid reads while painting.
		for k in T:
			for p in [Vector2i(x0 + k, 0), Vector2i(x0 + k, T - 1), Vector2i(x0, k), Vector2i(x0 + T - 1, k)]:
				img.set_pixelv(p, base.darkened(0.12))
	return img


func _glyph(img: Image, x0: int, kind: String, base: Color, dark: Color) -> void:
	match kind:
		"blades":
			for bx in [4, 10, 16, 22, 27]:
				for h in 10:
					img.set_pixel(x0 + bx + (h % 3 - 1), 26 - h * 2 if h < 6 else 26 - h, dark)
					img.set_pixel(x0 + bx, 28 - h * 2 if h < 9 else 10, dark)
		"dots":
			for p in [Vector2i(6, 7), Vector2i(20, 12), Vector2i(12, 22), Vector2i(26, 25)]:
				img.set_pixel(x0 + p.x, p.y, dark)
		"waves":
			for row in [9, 21]:
				for k in 28:
					img.set_pixel(x0 + 2 + k, row + int(round(sin(k * 0.6) * 2.0)), base.lightened(0.35))
		"bricks":
			for row in [7, 15, 23]:
				img.fill_rect(Rect2i(x0, row, T, 1), dark)
			for row in 4:
				var off := 0 if row % 2 == 0 else 8
				for bx in range(off, T, 16):
					img.fill_rect(Rect2i(x0 + bx, row * 8, 1, 7), dark)
		"stripes":
			for row in range(3, T, 6):
				img.fill_rect(Rect2i(x0, row, T, 2), dark)
		"door":
			img.fill_rect(Rect2i(x0 + 6, 4, 20, 28), dark)
			img.set_pixel(x0 + 22, 18, Color("e0c060"))
		"boards":
			for row in range(7, T, 8):
				img.fill_rect(Rect2i(x0, row, T, 1), dark)
		"border":
			img.fill_rect(Rect2i(x0 + 3, 3, 26, 26), base.lightened(0.15))
			img.fill_rect(Rect2i(x0 + 6, 6, 20, 20), base)
		"top":
			img.fill_rect(Rect2i(x0, 0, T, 10), base.lightened(0.2))
			img.fill_rect(Rect2i(x0, 10, T, 2), dark)
		"circle":
			for y in T:
				for x in T:
					var d := Vector2(x - 15.5, y - 14.0).length()
					if d < 13.0:
						img.set_pixel(x0 + x, y, base.lightened(0.15) if d < 9.0 else base)
			img.fill_rect(Rect2i(x0 + 13, 26, 6, 6), Color("6b4a2f"))
		"rails":
			img.fill_rect(Rect2i(x0, 0, T, T), Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(x0, 10, T, 3), base)
			img.fill_rect(Rect2i(x0, 20, T, 3), base)
			for px in [3, 27]:
				img.fill_rect(Rect2i(x0 + px, 6, 3, 22), dark)
		"flowers":
			for p in [Vector2i(7, 8), Vector2i(22, 6), Vector2i(14, 18), Vector2i(25, 24), Vector2i(6, 25)]:
				for c in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
					img.set_pixelv(Vector2i(x0, 0) + p + c, Color("f0e060"))
				img.set_pixelv(Vector2i(x0, 0) + p, Color("e05a5a"))
		"sign":
			img.fill_rect(Rect2i(x0, 0, T, T), Color("6fae4f"))
			img.fill_rect(Rect2i(x0 + 4, 6, 24, 14), base)
			img.fill_rect(Rect2i(x0 + 14, 20, 4, 10), dark)


func _tileset(texture: Texture2D) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "encounter")
	ts.set_custom_data_layer_type(0, TYPE_BOOL)
	var src := TileSetAtlasSource.new()
	src.texture = texture
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)
	var half := T / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for i in TILES.size():
		var coord := Vector2i(i, 0)
		src.create_tile(coord)
		var data := src.get_tile_data(coord, 0)
		data.set_custom_data("encounter", TILES[i][3])
		if TILES[i][2]:
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
	return ts


func _write_ids() -> void:
	var lines := PackedStringArray([
		"class_name TileIds",
		"extends RefCounted",
		"## Atlas coordinates of the placeholder tiles. Generated by",
		"## tools/generate_placeholder_tiles.gd; don't edit by hand.",
		"",
		"const SOURCE := 0",
	])
	var solid := PackedStringArray()
	for i in TILES.size():
		lines.append("const %s := Vector2i(%d, 0)" % [TILES[i][0], i])
		if TILES[i][2]:
			solid.append(TILES[i][0])
	lines.append("const SOLID: Array[Vector2i] = [%s]" % ", ".join(solid))
	var f := FileAccess.open(IDS, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
