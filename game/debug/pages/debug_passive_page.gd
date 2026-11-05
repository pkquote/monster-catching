class_name DebugPassivePage
extends DebugPage
## Pick a party creature, any passive id (or none) and a slot, and whether to make it active.
## Any id may go in either slot, whatever the species lists.

const NONE := "(none)"
const SLOTS := [Passives.SLOT_ROLLED, Passives.SLOT_AFFINITY]
const SLOT_NAMES := ["Rolled", "Affinity"]


func title() -> String:
	return "Set passive"


func build(box: VBoxContainer) -> void:
	var db := DataRegistry.db
	var pick: OptionButton = menu.creature_picker(box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var ids := db.ids("passives")
	var names: Array = Array(ids).map(func(id: String): return db.passive(id).name)
	names.append(NONE)
	var passive: OptionButton = menu.option_row(grid, "Passive", names, 0)
	var slot: OptionButton = menu.option_row(grid, "Slot", SLOT_NAMES, 0)
	var active := CheckBox.new()
	active.text = "Make active"
	box.add_child(active)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	UIKit.button(row, "Apply", func():
		var id := ids[passive.selected] if passive.selected < ids.size() else ""
		_apply(pick.selected, id, SLOTS[slot.selected], active.button_pressed))
	UIKit.button(row, "Back", func(): menu.show_page(DebugMainPage.new()))


## Puts `id` ("" = empty) in `slot`, then makes that slot active if asked. An empty slot
## can't be active: the page stays open and says so.
func _apply(index: int, id: String, slot: String, make_active: bool) -> void:
	var db := DataRegistry.db
	var c: CreatureInstance = GameState.current.party[index]
	if slot == Passives.SLOT_AFFINITY:
		c.affinity_passive = id
	else:
		c.passive = id
	var slot_name: String = SLOT_NAMES[SLOTS.find(slot)]
	var text := "%s: %s passive is now %s." % [c.display_name(db), slot_name,
		db.passive(id).name if id != "" else "empty"]
	var refused := make_active and Passives.set_active(c, slot) != ""
	GameState.autosave()
	menu.refresh_world()
	if refused:
		menu.set_status(text + " An empty slot can't be made active.")
		return
	menu.show_page(DebugMainPage.new(), text)
