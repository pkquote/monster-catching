class_name StorageScreen
extends CanvasLayer
## The creature boxes: the party as a 2-column strip on the left, the current box as a 6x5 grid of
## sprite slots in the middle and the creature card on the right, which follows the cursor.
## Switch boxes with the shoulder actions (or the header arrows).

signal closed

const MARGIN := 4
const SLOT := 36
const GAP := 3
const PARTY_COLUMNS := 2
const MAX_PARTY_SLOTS := 12
const HELP_BROWSE := "Accept: pick up   %s: mark several   %s: switch box   Back: close"
const HELP_MARKED := "%d marked. Accept: pick them up   %s: mark or unmark   Back: close"
const HELP_HOLDING := "Accept: place here   Back: put down"

## The box being shown (0-based).
var box := 0

var _save_override: SaveGame
var _db_override: Database
var _root: Control
var _party_cells: Array[CreatureSlotButton] = []
var _box_cells: Array[CreatureSlotButton] = []
var _card: CreatureCard
var _header: Label
var _prev: Button
var _next: Button
var _help: Label
var _message := ""
var _closed := false
## Locations picked up ({"party": i} / {"box": slot}); they stay where they are until placed.
var _held: Array = []
## Locations marked for a group move; all from one container (the party, or one box).
var _marks: Array = []

var _save: SaveGame:
	get:
		return _save_override if _save_override != null else GameState.current
var _db: Database:
	get:
		return _db_override if _db_override != null else DataRegistry.db


## Runs until the player closes the screen.
static func run(world: Node, save: SaveGame = null, db: Database = null) -> void:
	var screen := StorageScreen.new()
	screen.use_game(save, db)
	world.add_child(screen)
	await screen.closed
	screen.close()


## Points the screen at `save` / `db` (null keeps the current game's / the content).
func use_game(save: SaveGame, db: Database) -> void:
	if save != null:
		_save_override = save
	if db != null:
		_db_override = db


static func refusal_text(reason: String, short := 0) -> String:
	match reason:
		"last_healthy":
			return "Keep at least one creature that can fight."
		"party_full":
			return "Your party is full."
		"no_room":
			return "Need %d more free slot%s." % [short, "" if short == 1 else "s"]
		"box_full":
			return "The box is full."
	return ""


# --- Queries ----------------------------------------------------------------------------

func party_buttons() -> Array:
	return _party_cells.duplicate()


## The 30 slot buttons of the current box, row by row.
func box_buttons() -> Array:
	return _box_cells.duplicate()


## The locations picked up, [] when nothing is held.
func held() -> Array:
	return _held.duplicate()


func marks() -> Array:
	return _marks.duplicate()


func card() -> CreatureCard:
	return _card


func header_text() -> String:
	return _header.text


func help_text() -> String:
	return _help.text


## {"party": i} or {"box": slot} for the focused slot, {} when none.
func focused_location() -> Dictionary:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return _location_of(focus)


func _location_of(control: Control) -> Dictionary:
	var i := _party_cells.find(control)
	if i >= 0:
		return {"party": i}
	i = _box_cells.find(control)
	if i >= 0:
		return {"box": BoxStorage.slot_of(box, i)}
	return {}


# --- Building ---------------------------------------------------------------------------

func _ready() -> void:
	Log.debug(Log.UI, "Screen opened", {"screen": "StorageScreen"})
	layer = 72
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	margin.add_child(outer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)

	var party := GridContainer.new()
	party.columns = PARTY_COLUMNS
	party.add_theme_constant_override("h_separation", GAP)
	party.add_theme_constant_override("v_separation", GAP)
	row.add_child(party)
	var party_slots := clampi(maxi(int(_db.balance.party_size), _save.party.size()), 1, MAX_PARTY_SLOTS)
	for i in party_slots:
		_party_cells.append(_make_cell(party))

	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", GAP)
	row.add_child(middle)
	var head := HBoxContainer.new()
	middle.add_child(head)
	_prev = _arrow(head, "<", -1)
	_header = UIKit.label(head, "", UIKit.HEADING_SIZE, UIKit.ACCENT)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next = _arrow(head, ">", 1)
	var grid := GridContainer.new()
	grid.columns = BoxStorage.COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	middle.add_child(grid)
	for i in BoxStorage.BOX_SIZE:
		_box_cells.append(_make_cell(grid))

	_card = CreatureCard.new()
	_card.custom_minimum_size = CreatureCard.SIZE
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_card)
	_help = UIKit.label(outer, HELP_BROWSE % [_key_for("mark"), _key_for("prev_creature") + "/" + _key_for("next_creature")], 11, UIKit.MUTED)
	_help.clip_text = true
	_help.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	show_box(0)
	_refresh_party()
	_focus_first.call_deferred()


func _make_cell(parent: Node) -> CreatureSlotButton:
	var b := CreatureSlotButton.new()
	b.configure(_db, null, SLOT)
	parent.add_child(b)
	b.focus_entered.connect(_on_focus.bind(b))
	b.pressed.connect(accept)
	return b


func _arrow(parent: Node, text: String, step: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(SLOT, 22)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(step_box.bind(step))
	parent.add_child(b)
	return b


func _focus_first() -> void:
	if not is_inside_tree():
		return
	var target: Control = _party_cells[0]
	for b in _party_cells:
		if b.creature() != null:
			target = b
			break
	target.grab_focus()
	_on_focus(target)


# --- Box switching ----------------------------------------------------------------------

## Shows box `index` (clamped to the unlocked boxes).
func show_box(index: int) -> void:
	box = clampi(index, 0, maxi(BoxStorage.box_count(_save) - 1, 0))
	_refresh_box()


## Steps to the previous / next box, wrapping.
func step_box(step: int) -> void:
	_message = ""
	show_box(posmod(box + step, maxi(BoxStorage.box_count(_save), 1)))


func _refresh_box() -> void:
	_header.text = "Box %d / %d" % [box + 1, BoxStorage.box_count(_save)]
	for i in _box_cells.size():
		_box_cells[i].configure(_db, BoxStorage.creature_at(_save, BoxStorage.slot_of(box, i)), SLOT)
	_after_refresh()


func _refresh_party() -> void:
	for i in _party_cells.size():
		_party_cells[i].configure(_db, _save.party[i] if i < _save.party.size() else null, SLOT)
	_after_refresh()


func _after_refresh() -> void:
	_decorate()
	_show_card(focused_location())


## Marked, carried and count-badge looks, and the help line.
func _decorate() -> void:
	var here := focused_location()
	for i in _party_cells.size():
		_style_cell(_party_cells[i], {"party": i}, here)
	for i in _box_cells.size():
		_style_cell(_box_cells[i], {"box": BoxStorage.slot_of(box, i)}, here)
	if _help != null:
		_help.text = _message if _message != "" else _default_help()
		_help.add_theme_color_override("font_color", UIKit.DANGER if _message != "" else UIKit.MUTED)


func _default_help() -> String:
	if not _held.is_empty():
		return HELP_HOLDING
	if not _marks.is_empty():
		return HELP_MARKED % [_marks.size(), _key_for("mark")]
	return HELP_BROWSE % [_key_for("mark"), _key_for("prev_creature") + "/" + _key_for("next_creature")]


## The first keyboard key bound to `action` ("V" for Mark by default).
static func _key_for(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				return OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
	return action.capitalize()


func _style_cell(cell: CreatureSlotButton, loc: Dictionary, here: Dictionary) -> void:
	cell.set_marked(_marks.has(loc))
	cell.set_carried(_held.has(loc))
	cell.set_count_badge(_held.size() if _held.size() >= 2 and loc == here else 0)


# --- The card ---------------------------------------------------------------------------

func _on_focus(control: Control) -> void:
	_show_card(_location_of(control))
	_decorate()


func _show_card(loc: Dictionary) -> void:
	var c: CreatureInstance = null
	if loc.has("party"):
		var i: int = loc.party
		c = _save.party[i] if i < _save.party.size() else null
	elif loc.has("box"):
		c = BoxStorage.creature_at(_save, int(loc.box))
	if c == null:
		_card.show_empty()
	else:
		_card.show_creature(_db, c)


# --- Input ------------------------------------------------------------------------------

## `_input`, not `_unhandled_input`: the buttons' own focus handling would otherwise take Accept first.
func _input(event: InputEvent) -> void:
	if _closed:
		return
	var viewport := get_viewport()
	if event.is_action_pressed("ui_cancel"):
		cancel()
	elif event.is_action_pressed("ui_accept"):
		accept()
	elif event.is_action_pressed("mark"):
		mark()
	elif event.is_action_pressed("next_creature"):
		step_box(1)
	elif event.is_action_pressed("prev_creature"):
		step_box(-1)
	else:
		return
	viewport.set_input_as_handled()


## Picks up (the marked group, else the creature under the cursor), or places what is held.
func accept() -> void:
	var here := focused_location()
	if here.is_empty():
		return
	_message = ""
	if _held.is_empty():
		_pick_up(here)
	else:
		_place(here)
	_refresh_party()
	_refresh_box()


func _pick_up(here: Dictionary) -> void:
	if not _marks.is_empty():
		_held = _marks.duplicate()
		_held.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _order(a) < _order(b))
	elif _creature_at(here) != null:
		_held = [here]


func _place(here: Dictionary) -> void:
	var save := _save
	var to := here
	if to.has("party"):
		to = {"party": mini(int(to.party), save.party.size())}  # an empty party slot means "the next free place"
	var reason := ""
	var short := 0
	if _held.size() == 1:
		if _held[0] == to or (to.has("party") and _held[0].has("party") and int(_held[0].party) == int(here.party)):
			reason = "same_slot"
		else:
			reason = Team.move(_db, save, _held[0], to)
	else:
		var r := Team.move_group(_db, save, _held, to)
		reason = r.reason
		short = r.short
	match reason:
		"", "same_slot":
			_held = []
			_marks = []
		_:
			_message = refusal_text(reason, short)
			if _message == "":
				_message = "It can't go there."


## Reading order key: the party first, then box slots.
func _order(loc: Dictionary) -> int:
	return int(loc.party) if loc.has("party") else 1000 + int(loc.box)


func _creature_at(loc: Dictionary) -> CreatureInstance:
	if loc.has("party"):
		return _save.party[int(loc.party)] if int(loc.party) < _save.party.size() else null
	return BoxStorage.creature_at(_save, int(loc.get("box", -1)))


## Puts down what is held; with nothing held, closes the screen.
func cancel() -> void:
	if _held.is_empty():
		close()
		return
	_held = []
	_message = ""
	_decorate()


## Marks (or unmarks) the creature under the cursor for a group move.
func mark() -> void:
	var here := focused_location()
	if here.is_empty() or not _held.is_empty() or _creature_at(here) == null:
		return
	_message = ""
	if _marks.has(here):
		_marks.erase(here)
	else:
		if not _marks.is_empty() and _container(_marks[0]) != _container(here):
			_marks = []
		_marks.append(here)
	_decorate()


func _container(loc: Dictionary) -> String:
	return "party" if loc.has("party") else "box%d" % BoxStorage.box_of(int(loc.box))


## Detaches and frees the screen. Safe to call twice.
func close() -> void:
	if _closed:
		return
	_closed = true
	Log.debug(Log.UI, "Screen closed", {"screen": "StorageScreen"})
	closed.emit()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
