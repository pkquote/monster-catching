class_name StatRadar
extends Control
## Seven-axis stat radar on a fixed scale (a base-100 steady stat at the level cap is the rim), so
## the shape grows with the creature's level. Each axis shows its value, with the growth ▲/▼ marker
## when the species grows that stat faster or slower than steady. HP and Stamina are drawn by ResourceBars.

## Clockwise from the top.
const KEYS := ["patk", "pdef", "satk", "sdef", "spd", "resolve", "luck"]
const NAMES := {"patk": "Phys Atk", "pdef": "Phys Def", "satk": "Spec Atk", "sdef": "Spec Def",
	"spd": "Speed", "resolve": "Resolve", "luck": "Luck"}
const RINGS := [0.25, 0.5, 0.75, 1.0]
const FONT_SIZE := 9

var db: Database
var creature: CreatureInstance


## The stat value that reaches the rim.
static func ceiling(p_db: Database) -> int:
	return Stats.stat_at(100, p_db.balance.level_cap)


static func axes(p_db: Database, c: CreatureInstance) -> Array:
	var out: Array = []
	var top := float(ceiling(p_db))
	var def := p_db.creature(c.species)
	for key: String in KEYS:
		var value := c.stat(p_db, key)
		var mult: float = p_db.balance.growth_tiers.get(def.growth_tier(key), 1.0)
		out.append({"key": key, "name": NAMES[key], "value": value,
			"fraction": clampf(float(value) / top, 0.0, 1.0),
			"mark": "▲" if mult > 1.0 else "▼" if mult < 1.0 else ""})
	return out


## Offset from the centre of axis `index` at `fraction` of `radius` (axis 0 points up, then clockwise).
static func vertex(index: int, fraction: float, radius: float) -> Vector2:
	var angle := TAU * float(index) / float(KEYS.size())
	return Vector2(sin(angle), -cos(angle)) * radius * fraction


func configure(p_db: Database, c: CreatureInstance, p_size: Vector2 = Vector2(180, 150)) -> void:
	db = p_db
	creature = c
	custom_minimum_size = p_size
	size = p_size
	queue_redraw()


func _draw() -> void:
	if db == null or creature == null:
		return
	var center := size / 2.0
	var radius := minf(size.x * 0.27, size.y * 0.36)
	for ring: float in RINGS:
		var pts := PackedVector2Array()
		for i in KEYS.size():
			pts.append(center + vertex(i, ring, radius))
		pts.append(pts[0])
		draw_polyline(pts, Color(UIKit.MUTED, 0.35), 1.0)
	for i in KEYS.size():
		draw_line(center, center + vertex(i, 1.0, radius), Color(UIKit.MUTED, 0.25), 1.0)
	var data := axes(db, creature)
	var poly := PackedVector2Array()
	for i in data.size():
		poly.append(center + vertex(i, maxf(data[i].fraction, 0.02), radius))
	draw_colored_polygon(poly, Color(UIKit.ACCENT, 0.35))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, UIKit.ACCENT, 1.5)
	var font := get_theme_default_font()
	for i in data.size():
		var text := "%s %d%s" % [data[i].name, data[i].value, data[i].mark]
		var at := center + vertex(i, 1.0, radius + 6.0)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var dir := vertex(i, 1.0, 1.0)
		# Text hangs outward: left-aligned on the right side, right-aligned on the left, centred up top.
		var x := at.x - w / 2.0 + dir.x * w / 2.0
		var y := at.y + FONT_SIZE * 0.4 + dir.y * FONT_SIZE * 0.6
		x = clampf(x, 0.0, maxf(0.0, size.x - w))
		y = clampf(y, FONT_SIZE, size.y)
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, UIKit.TEXT)
