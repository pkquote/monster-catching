@tool
class_name Npc
extends Piece
## A person on the map. Accept while facing them: they turn to the player and
## run `title` from `dialogue`. With `wander_tiles` > 0 they stroll around their
## starting tile whenever the player is free to move.

const FACINGS := {"up": Vector2i.UP, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "right": Vector2i.RIGHT}
const STEP_TIME := 0.25
const WANDER_EVERY := 2.0

## Name cutscenes use to move this NPC (Cutscene.move("guide", ...)).
@export var actor_id := ""
@export var display_name := ""
## .dialogue file path, e.g. res://dialogue/town_01/npcs.dialogue
@export_file("*.dialogue") var dialogue := ""
@export var title := ""
@export_enum("down", "up", "left", "right") var start_facing := "down":
	set(v):
		start_facing = v
		facing = FACINGS.get(v, Vector2i.DOWN)
		queue_redraw()
## How far (in tiles) this NPC may wander from where it starts; 0 = stands still.
@export_range(0, 10) var wander_tiles := 0
## Gone from the map once this story flag is set (someone who moves on).
@export var hide_when_flag := ""

var facing := Vector2i.DOWN
var _home := Vector2i.ZERO
var _moving := false
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	if hide_when_flag != "" and Story.flag(hide_when_flag):
		queue_free()
		return
	_home = tile()
	_rng.randomize()
	_timer = _rng.randf_range(0.5, WANDER_EVERY)
	add_blocker()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or wander_tiles <= 0 or Overworld.instant:
		return  # tests (instant mode) call wander_tick themselves
	var w := world()
	if w == null or w.is_locked():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(WANDER_EVERY * 0.6, WANDER_EVERY * 1.4)
		wander_tick(w, _rng)


func blocks() -> bool:
	return true


func on_interact(w: Node) -> void:
	face_toward(w.player.feet_tile())
	w.say(dialogue, title)  # not awaited: a script may change map and free this NPC


func home_tile() -> Vector2i:
	return _home


func face_toward(t: Vector2i) -> void:
	var d := t - tile()
	if d == Vector2i.ZERO:
		return
	facing = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	queue_redraw()


## One wander decision: maybe step one tile in a random direction, staying within
## `wander_tiles` of home, off solid tiles and off the player.
func wander_tick(w: Node, rng: RandomNumberGenerator) -> void:
	if _moving:
		return
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.ZERO]
	var d: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
	if d == Vector2i.ZERO:
		return
	facing = d
	queue_redraw()
	var target := tile() + d
	if maxi(absi(target.x - _home.x), absi(target.y - _home.y)) > wander_tiles:
		return
	if w.map.is_solid(target, self) or target == w.player.feet_tile():
		return
	await _step_to(target)


## Walks to `target` in straight lines (x first, then y). Used by cutscenes and tamers.
func walk_to(target: Vector2i) -> void:
	while tile() != target:
		var d := target - tile()
		var stepdir := Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(0, signi(d.y))
		facing = stepdir
		await _step_to(tile() + stepdir)


func _step_to(t: Vector2i) -> void:
	_moving = true
	var dest := GameMap.centre_of(t)
	if Overworld.instant:
		position = dest
	else:
		var tw := create_tween()
		tw.tween_property(self, "position", dest, STEP_TIME)
		await tw.finished
	_moving = false
	queue_redraw()


func _draw() -> void:
	super()
	# Placeholder sprite: a body tinted by actor id, with a nose for facing.
	var tint := Color.from_hsv(float(hash(actor_id if actor_id != "" else name) % 360) / 360.0, 0.45, 0.85)
	draw_rect(Rect2(-10, -12, 20, 26), tint)
	draw_rect(Rect2(-10, -12, 20, 26), tint.darkened(0.5), false, 1.0)
	draw_circle(Vector2(facing) * 7 + Vector2(0, 0), 3, Color("2b2b2b"))


func marker_color() -> Color:
	return Color("e0e060")


func marker_label() -> String:
	return display_name if display_name != "" else name
