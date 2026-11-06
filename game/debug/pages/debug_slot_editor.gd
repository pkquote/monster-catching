class_name DebugSlotEditor
extends DebugPage
## One creature of the custom-battle team builder: species, level, moves, held item
## and passive. Every move and passive in the game is offered, each labelled by
## whether the species normally has it (CreatureSpec.move_label / passive_label).
## Edits a copy: Done writes it back to the builder page, Cancel drops it.

const EMPTY := "(empty)"
const NONE := "(none)"
const CHOOSE := "(choose a move)"

## The builder page this slot belongs to; Done and Cancel show it again.
var owner_page: DebugCustomBattlePage
## DebugCustomBattlePage.MINE or FOES, and the slot's index in that team.
var side: int
var index: int
## The working copy.
var spec: CreatureSpec

var _species: OptionButton
var _moves: Array = []  # of OptionButton, one per move slot
var _passive: OptionButton
var _held: OptionButton
var _summary: Label
var _errors: Label
var _done: Button


func _init(page: DebugCustomBattlePage, side_: int, index_: int) -> void:
	owner_page = page
	side = side_
	index = index_
	spec = _copy(page.team(side_)[index_])


static func _copy(s: CreatureSpec) -> CreatureSpec:
	var c: CreatureSpec = CreatureSpec.new()
	c.species = s.species
	c.level = s.level
	c.moves = s.moves.duplicate()
	c.held_item = s.held_item
	c.passive = s.passive
	c.moves_edited = s.moves_edited
	return c


func title() -> String:
	return "%s %d" % ["Your creature" if side == DebugCustomBattlePage.MINE else "Foe", index + 1]


func width() -> float:
	return 340.0


func build(box: VBoxContainer) -> void:
	var db: Database = DataRegistry.db
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	box.add_child(grid)
	_species = _picker(grid, "Species", _sorted_ids("creatures"), "",
		func(id: String) -> String: return db.creature(id).name)
	_select_id(_species, spec.species)
	_species.item_selected.connect(func(_i: int) -> void:
		spec.retarget(db, _id(_species), spec.level)
		_show_moves()
		_refresh())
	var level: SpinBox = menu.spin_row(grid, "Level", 1, db.balance.level_cap, spec.level)
	level.value_changed.connect(func(v: float) -> void:
		spec.retarget(db, spec.species, int(v))
		_show_moves()
		_refresh())
	_moves = []
	var move_ids: Array = _sorted_ids("moves")
	for slot: int in db.balance.max_moves:
		var o: OptionButton = _picker(grid, "Move %d" % (slot + 1), move_ids, EMPTY if slot > 0 else CHOOSE,
			func(id: String) -> String: return db.move(id).name)
		o.item_selected.connect(func(_i: int) -> void:
			spec.moves_edited = true
			spec.moves = _picked_moves()
			_refresh())
		_moves.append(o)
	_show_moves()
	var held_ids: Array = _sorted_ids("items").filter(
		func(id: String) -> bool: return db.item(id).category == "held")
	_held = _picker(grid, "Held item", held_ids, NONE, func(id: String) -> String: return db.item(id).name)
	_select_id(_held, spec.held_item)
	_held.item_selected.connect(func(_i: int) -> void:
		spec.held_item = _id(_held)
		_refresh())
	_passive = _picker(grid, "Passive", _sorted_ids("passives"), NONE,
		func(id: String) -> String: return db.passive(id).name)
	_select_id(_passive, spec.passive)
	_passive.item_selected.connect(func(_i: int) -> void:
		spec.passive = _id(_passive)
		_refresh())
	_summary = UIKit.label(box, "", 11, UIKit.MUTED)
	_errors = UIKit.label(box, "", 11, UIKit.DANGER, true)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	UIKit.button(row, "Reset to natural", _reset)
	_done = UIKit.button(row, "Done", _commit)
	UIKit.button(row, "Cancel", func() -> void: menu.show_page(owner_page))
	_refresh()


## Ids of `category` sorted by display name.
func _sorted_ids(category: String) -> Array:
	var db: Database = DataRegistry.db
	var ids: Array = Array(db.ids(category))
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _name_of(db, category, a).naturalnocasecmp_to(_name_of(db, category, b)) < 0)
	return ids


static func _name_of(db: Database, category: String, id: String) -> String:
	match category:
		"creatures":
			return db.creature(id).name
		"moves":
			return db.move(id).name
		"passives":
			return db.passive(id).name
		"items":
			return db.item(id).name
	return id


## A label and a drop-down of `ids` (metadata = id), led by `blank` (metadata "") when given.
func _picker(grid: GridContainer, text: String, ids: Array, blank: String, label_of: Callable) -> OptionButton:
	UIKit.label(grid, text)
	var o: OptionButton = OptionButton.new()
	o.fit_to_longest_item = false
	o.clip_text = true
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if blank != "":
		o.add_item(blank)
		o.set_item_metadata(o.item_count - 1, "")
	for id: String in ids:
		o.add_item(label_of.call(id))
		o.set_item_metadata(o.item_count - 1, id)
	grid.add_child(o)
	return o


func _id(o: OptionButton) -> String:
	return str(o.get_item_metadata(o.selected)) if o.selected >= 0 else ""


## Selects the item for `id` without emitting item_selected.
func _select_id(o: OptionButton, id: String) -> void:
	for i: int in o.item_count:
		if str(o.get_item_metadata(i)) == id:
			o.select(i)
			return


## Shows spec.moves in the move slots (empty slots past the end).
func _show_moves() -> void:
	for slot: int in _moves.size():
		_select_id(_moves[slot], spec.moves[slot] if slot < spec.moves.size() else "")


func _picked_moves() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for o: OptionButton in _moves:
		var id: String = _id(o)
		if id != "":
			out.append(id)
	return out


## Relabels the choices for the current species and level, and re-checks the slot.
func _refresh() -> void:
	var db: Database = DataRegistry.db
	for o: OptionButton in _moves:
		for i: int in o.item_count:
			var id: String = str(o.get_item_metadata(i))
			if id != "":
				o.set_item_text(i, CreatureSpec.move_label(db, spec.species, spec.level, id))
		_warn(o)
	for i: int in _passive.item_count:
		var id: String = str(_passive.get_item_metadata(i))
		if id != "":
			_passive.set_item_text(i, CreatureSpec.passive_label(db, spec.species, id))
	_warn(_passive)
	_summary.text = spec.summary(db)
	var problems: PackedStringArray = spec.validate(db)
	_errors.text = "\n".join(problems)
	_errors.visible = not problems.is_empty()
	_done.disabled = not problems.is_empty()
	if menu != null:
		menu.set_status("Fix the slot to finish: %s." % problems[0] if not problems.is_empty() else "")


## Warning colour on a drop-down whose current choice is "✗" (not normal for the species).
func _warn(o: OptionButton) -> void:
	if o.selected >= 0 and o.get_item_text(o.selected).contains("✗"):
		o.add_theme_color_override("font_color", UIKit.DANGER)
		o.add_theme_color_override("font_focus_color", UIKit.DANGER)
	else:
		o.remove_theme_color_override("font_color")
		o.remove_theme_color_override("font_focus_color")


## Natural moves, a freshly rolled passive and no item, for the current species and level.
func _reset() -> void:
	spec = CreatureSpec.natural(DataRegistry.db, spec.species, spec.level, menu.rng)
	menu.refresh_page()


func _commit() -> void:
	if not spec.validate(DataRegistry.db).is_empty():
		return
	owner_page.team(side)[index] = spec
	menu.show_page(owner_page)
