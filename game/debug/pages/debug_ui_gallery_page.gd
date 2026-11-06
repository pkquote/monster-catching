class_name DebugUiGalleryPage
extends DebugPage
## Shows the shared UI pieces (CreatureCard with its sprite, radar and bars; ItemIconSlot) for any species,
## level, training amount, nickname and held item. Builds a throwaway creature: it needs no game and never
## touches a save.

const NO_ITEM := "(none)"
const MAX_TRAINED := 30

var card: CreatureCard
var species_pick: OptionButton
var level_spin: SpinBox
var trained_spin: SpinBox
var nickname_edit: LineEdit
var item_pick: OptionButton

var _species_ids: PackedStringArray
var _item_ids: PackedStringArray


## A throwaway creature at `level` with `trained` points in every trainable stat (HP and Stamina included),
## at full HP and Stamina.
static func make_creature(db: Database, species_id: String, level: int, trained: int,
		nickname := "", held_item := "") -> CreatureInstance:
	var c := CreatureInstance.create(db, species_id, level)
	for key: String in ["hp", "stamina"] + Array(StatRadar.KEYS):
		c.training[key] = trained
	c.nickname = nickname
	c.held_item = held_item
	c.hp = c.max_hp(db)
	c.energy = c.max_energy(db)
	return c


func title() -> String:
	return "UI gallery"


func width() -> float:
	return 620.0


func build(box: VBoxContainer) -> void:
	var db := DataRegistry.db
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	card = CreatureCard.new()
	row.add_child(card)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	left.add_child(grid)
	_species_ids = db.ids("creatures")
	species_pick = menu.option_row(grid, "Species",
		Array(_species_ids).map(func(id: String): return db.creature(id).name), 0)
	level_spin = menu.spin_row(grid, "Level", 1, db.balance.level_cap, 20)
	trained_spin = menu.spin_row(grid, "Trained", 0, MAX_TRAINED, 0)
	UIKit.label(grid, "Nickname")
	nickname_edit = LineEdit.new()
	nickname_edit.max_length = 80
	grid.add_child(nickname_edit)
	_item_ids = PackedStringArray()
	var item_names: Array = [NO_ITEM]
	for id: String in db.ids("items"):
		if db.item(id).category == "held":
			_item_ids.append(id)
			item_names.append(db.item(id).name)
	item_pick = menu.option_row(grid, "Held item", item_names, 0)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	left.add_child(icons)
	for category: String in ItemIconSlot.CATEGORY_COLORS:
		var slot := ItemIconSlot.new()
		slot.configure(category, 28)
		icons.add_child(slot)
	UIKit.button(left, "Back", func(): menu.show_page(DebugMainPage.new()))

	species_pick.item_selected.connect(func(_i: int): _refresh())
	level_spin.value_changed.connect(func(_v: float): _refresh())
	trained_spin.value_changed.connect(func(_v: float): _refresh())
	nickname_edit.text_changed.connect(func(_t: String): _refresh())
	item_pick.item_selected.connect(func(_i: int): _refresh())
	_refresh()


func _refresh() -> void:
	var item := "" if item_pick.selected <= 0 else _item_ids[item_pick.selected - 1]
	card.show_creature(DataRegistry.db, make_creature(DataRegistry.db, _species_ids[species_pick.selected],
		int(level_spin.value), int(trained_spin.value), nickname_edit.text, item))
