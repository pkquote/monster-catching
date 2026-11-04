class_name Grid
extends RefCounted
## Tile-grid helpers for the overworld (pure math, no nodes).


## The tiles a tamer at `from` facing `facing` can see: up to `length` tiles
## ahead, stopping before the first tile `is_solid` (Callable(Vector2i) -> bool) reports.
static func sight_tiles(from: Vector2i, facing: Vector2i, length: int, is_solid: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var t := from
	for i in length:
		t += facing
		if is_solid.call(t):
			break
		out.append(t)
	return out
