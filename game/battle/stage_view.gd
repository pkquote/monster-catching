class_name StageView
extends Control
## Battle backdrop: sky, and one ground patch per side tinted by its newest field state.

const SKY_TOP := Color("2b3550")
const SKY_BOTTOM := Color("3d4a63")
const GROUND := Color("4c5b4a")
## Ground patch centre and radii per side (stage coordinates).
const PATCHES := [
	{"center": Vector2(190, 200), "radius": Vector2(200, 34)},  # player, lower-left
	{"center": Vector2(450, 104), "radius": Vector2(185, 30)},  # enemy, upper-right
]

var tints: Array[Color] = [Color(0, 0, 0, 0), Color(0, 0, 0, 0)]


func set_tint(side: int, color: Color) -> void:
	tints[side] = color
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_BOTTOM, SKY_BOTTOM]))
	for side in 2:
		var p: Dictionary = PATCHES[side]
		var ground := GROUND.lerp(tints[side], 0.55) if tints[side].a > 0.0 else GROUND
		draw_colored_polygon(_ellipse(p.center, p.radius), ground)
		draw_colored_polygon(_ellipse(p.center, p.radius * 0.82), ground.lightened(0.06))


static func _ellipse(c: Vector2, rad: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return pts
