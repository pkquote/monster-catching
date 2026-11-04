class_name Player
extends CharacterBody2D
## The player on the overworld: smooth 8-way movement, 4-way facing, and a
## `tile_entered` signal whenever the feet move onto a new tile (doors, triggers,
## grass and walking energy all hang off it). The node's origin is the feet.

signal tile_entered(tile: Vector2i)

const FACING_NAMES := {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}
const DIRS := {"move_up": Vector2i.UP, "move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT, "move_right": Vector2i.RIGHT}
## How far off a gap (in pixels) the player can be and still slip into it.
const SLIP_PX := 8

var facing := Vector2i.DOWN
## Set by the overworld while any lock is held (conversations, menus, fades).
var locked := false:
	set(v):
		locked = v
		if v:
			velocity = Vector2.ZERO

var _tile := Vector2i(-9999, -9999)
## Direction actions currently held, oldest first. Facing follows the newest.
var _held: Array[String] = []


func _ready() -> void:
	_tile = feet_tile()


func _unhandled_input(event: InputEvent) -> void:
	for action in DIRS:
		if event.is_action_pressed(action, false, true):
			press_dir(action, true)
		elif event.is_action_released(action, true):
			press_dir(action, false)


func _physics_process(delta: float) -> void:
	physics_step_from_input(delta)


func physics_step_from_input(delta: float) -> void:
	if locked:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	step(dir, Input.is_action_pressed("run"), delta)


## Records a direction press/release and updates facing (most recent held wins).
func press_dir(action: String, pressed: bool) -> void:
	_held.erase(action)
	if pressed:
		_held.append(action)
	if not _held.is_empty():
		_set_facing(DIRS[_held.back()])


## Moves by `dir` (normalised) for `delta` seconds, sliding along walls.
func step(dir: Vector2, run: bool, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	var cfg: Dictionary = DataRegistry.db.balance.overworld_cfg
	var speed := float(cfg.run_speed if run else cfg.walk_speed) * GameMap.TILE
	var motion := dir.normalized() * speed * delta
	var hit := move_and_collide(motion)
	if hit != null:
		if not _slip_round_corner(motion, hit):
			move_and_collide(hit.get_remainder().slide(hit.get_normal()))
	if _held.is_empty():
		# Gamepad sticks and tests move without press events: face the dominant axis.
		_set_facing(Vector2i(signi(roundi(dir.x)), 0) if absf(dir.x) >= absf(dir.y) else Vector2i(0, signi(roundi(dir.y))))
	_check_tile()


## Walking straight into a corner that's only a few pixels off a gap (a doorway,
## a path between trees) nudges the player sideways toward the gap instead of
## stopping them dead. Returns true when it nudged.
func _slip_round_corner(motion: Vector2, hit: KinematicCollision2D) -> bool:
	if motion.x != 0.0 and motion.y != 0.0:
		return false  # diagonal: the normal slide already handles corners
	var ahead := motion.normalized()
	if hit.get_normal().dot(ahead) > -0.9:
		return false  # not head-on
	var side := Vector2(absf(ahead.y), absf(ahead.x))
	for off in range(1, SLIP_PX + 1):
		for s in [-1.0, 1.0]:
			var shift: Vector2 = side * s * off
			if not test_move(global_transform, shift) \
					and not test_move(global_transform.translated(shift), ahead * 2.0):
				move_and_collide(side * s * minf(motion.length(), float(off)))
				return true
	return false


static func facing_name(f: Vector2i) -> String:
	return FACING_NAMES.get(f, "down")


static func facing_from_name(n: String) -> Vector2i:
	for f in FACING_NAMES:
		if FACING_NAMES[f] == n:
			return f
	return Vector2i.DOWN


func feet_tile() -> Vector2i:
	return GameMap.tile_of(position)


## Every tile the body's collision shape overlaps (one to four tiles).
func occupied_tiles() -> Array[Vector2i]:
	var feet := $Feet as CollisionShape2D
	var half: Vector2 = (feet.shape as RectangleShape2D).size / 2.0
	var c := position + feet.position
	var a := GameMap.tile_of(c - half)
	var b := GameMap.tile_of(c + half - Vector2(0.01, 0.01))
	var out: Array[Vector2i] = []
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			out.append(Vector2i(x, y))
	return out


## The tile Accept looks at: the one in front of the body's centre. (Walking down
## into a solid piece stops the feet a couple of pixels inside that piece's tile.)
func front_tile() -> Vector2i:
	return GameMap.tile_of(position + Vector2(0, -6)) + facing


## Walks to `target` in straight lines (x first, then y), one tile at a time.
## Used by cutscenes; doesn't fire tile_entered.
func walk_to(target: Vector2i) -> void:
	while feet_tile() != target:
		var d := target - feet_tile()
		var stepdir := Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(0, signi(d.y))
		_set_facing(stepdir)
		var dest := GameMap.centre_of(feet_tile() + stepdir)
		if Overworld.instant:
			position = dest
		else:
			var tw := create_tween()
			tw.tween_property(self, "position", dest, 0.2)
			await tw.finished
		_tile = feet_tile()


## Puts the player somewhere without firing tile_entered for the tile it lands on.
func place(pos: Vector2, facing_: Vector2i) -> void:
	position = pos
	velocity = Vector2.ZERO
	_set_facing(facing_)
	_tile = feet_tile()


func _check_tile() -> void:
	var t := feet_tile()
	if t != _tile:
		_tile = t
		tile_entered.emit(t)


func _set_facing(f: Vector2i) -> void:
	if f != Vector2i.ZERO and f != facing:
		facing = f
		queue_redraw()


func _draw() -> void:
	# Placeholder sprite: a body with a nose pointing where the player faces.
	draw_rect(Rect2(-10, -28, 20, 28), Color("f2b950"))
	draw_rect(Rect2(-10, -28, 20, 28), Color("6b4a2f"), false, 1.0)
	draw_circle(Vector2(facing) * 7 + Vector2(0, -16), 3, Color("2b2b2b"))
