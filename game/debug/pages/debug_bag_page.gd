class_name DebugBagPage
extends DebugPage
## The custom battle's bag (player side only): a 0-99 count for every item in the
## game, grouped by category. Edits the builder page's `bag` directly.

## Category order on the page; any other category follows, alphabetically.
const CATEGORIES := ["capture", "heal", "battle", "training", "held", "key"]
const MAX_COUNT := 99

var owner_page: DebugCustomBattlePage


func _init(page: DebugCustomBattlePage) -> void:
	owner_page = page


func title() -> String:
	return "Battle bag"


func width() -> float:
	return 340.0


func build(box: VBoxContainer) -> void:
	var db: Database = DataRegistry.db
	var by_cat: Dictionary = {}
	for id: String in db.ids("items"):
		var cat: String = db.item(id).category
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(id)
	var order: Array = CATEGORIES.filter(func(c: String) -> bool: return by_cat.has(c))
	var others: Array = by_cat.keys().filter(func(c: String) -> bool: return not CATEGORIES.has(c))
	others.sort()
	order.append_array(others)
	# The buttons go first: the menu focuses (and scrolls to) the first button on the page.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	UIKit.button(row, "Done", func() -> void: menu.show_page(owner_page))
	UIKit.button(row, "Reset to test bag", func() -> void:
		owner_page.bag = BattleLauncher.TEST_BAG.duplicate()
		menu.refresh_page("Test bag restored."))
	UIKit.button(row, "Clear all", func() -> void:
		owner_page.bag = {}
		menu.refresh_page("Bag emptied."))
	# One grid for every category, so the spinners line up.
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for cat: String in order:
		UIKit.label(grid, cat.capitalize(), UIKit.BODY_SIZE, UIKit.MUTED)
		grid.add_child(Control.new())
		var ids: Array = by_cat[cat]
		ids.sort_custom(func(a: String, b: String) -> bool:
			return db.item(a).name.naturalnocasecmp_to(db.item(b).name) < 0)
		for id: String in ids:
			var spin: SpinBox = menu.spin_row(grid, db.item(id).name, 0, MAX_COUNT,
				int(owner_page.bag.get(id, 0)))
			spin.set_meta("item", id)
			spin.value_changed.connect(func(v: float) -> void: set_count(id, int(v)))


## Sets one item's count (0 removes it from the bag).
func set_count(id: String, count: int) -> void:
	var n: int = clampi(count, 0, MAX_COUNT)
	if n == 0:
		owner_page.bag.erase(id)
	else:
		owner_page.bag[id] = n
