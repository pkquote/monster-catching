class_name DebugCustomBattlePage
extends DebugPage
## The team builder: any format (1v1 ... 3v3), both teams creature by creature, the
## player's bag, and wild or tamer foes. Battles from here are exhibitions: nothing
## in them reaches the save (BattleLauncher.exhibition_setup).
##
## The slot editor (DebugSlotEditor) and the bag page (DebugBagPage) edit this page's
## fields and then show this same page again, so build() only draws the fields; they
## are set up once, the first time the page is built.

const MINE := 0
const FOES := 1
## Level of the default creatures when there is no party to take the level from.
const NO_PARTY_LEVEL := 5

## The player's team and the foe team (Array of CreatureSpec), 1 to cap() each.
var mine: Array = []
var foes: Array = []
## How many each side fields (1..MAX_SIDE), as picked; fielded() clamps to the team.
var my_field: int = 1
var foe_field: int = 1
## Wild foes (one catchable pack, all on the field) or a tactician tamer.
var wild: bool = true
## The player side's bag for the battle (item id -> count). The foe has none.
var bag: Dictionary = {}
## The team the tabs show: MINE or FOES.
var tab: int = MINE

var _state_ready: bool = false


func title() -> String:
	return "Custom battle"


func width() -> float:
	return 340.0


func team(side: int) -> Array:
	return mine if side == MINE else foes


## Most creatures `side` may have: party_size, or MAX_SIDE for a wild pack.
func cap(side: int) -> int:
	var n: int = DataRegistry.db.balance.party_size
	return mini(n, BattleLauncher.MAX_SIDE) if side == FOES and wild else n


## How many of `side`'s creatures start on the field. A wild pack fights all at once.
func fielded(side: int) -> int:
	var t: Array = team(side)
	if side == FOES and wild:
		return mini(t.size(), BattleLauncher.MAX_SIDE)
	var picked: int = my_field if side == MINE else foe_field
	return clampi(picked, 1, mini(BattleLauncher.MAX_SIDE, maxi(1, t.size())))


## The party's average level, or NO_PARTY_LEVEL without a party.
func default_level() -> int:
	var save: SaveGame = GameState.current
	if save == null or save.party.is_empty():
		return NO_PARTY_LEVEL
	return BattleLauncher.party_level(save)


# --- Team edits (the buttons call these) ------------------------------------------

## Copies the real party (up to party_size) with its moves, held items and passives.
func fill_from_party() -> void:
	var save: SaveGame = GameState.current
	if save == null or save.party.is_empty():
		return
	mine = []
	for c: CreatureInstance in save.party.slice(0, DataRegistry.db.balance.party_size):
		mine.append(CreatureSpec.from_instance(c))


## A random species at the level of the team's last creature.
func add_creature(side: int) -> void:
	var t: Array = team(side)
	if t.size() >= cap(side):
		return
	var level: int = (t[-1] as CreatureSpec).level if not t.is_empty() else default_level()
	t.append(_random_spec(level))


func remove_creature(side: int, index: int) -> void:
	var t: Array = team(side)
	if t.size() > 1 and index >= 0 and index < t.size():
		t.remove_at(index)


## Every creature of `side` to `level` (natural moves follow unless hand-edited).
func set_all_levels(side: int, level: int) -> void:
	for s: CreatureSpec in team(side):
		s.retarget(DataRegistry.db, s.species, level)


## New random species for every foe, keeping each slot's level.
func randomize_foes() -> void:
	var out: Array = []
	for s: CreatureSpec in foes:
		out.append(_random_spec(s.level))
	foes = out


## Problems that stop the battle, as "You 2: No moves"; empty when it can start.
## Rows past cap() (a wild pack's unused foes) don't fight, so they aren't checked.
func errors() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for side: int in [MINE, FOES]:
		var t: Array = team(side)
		for i: int in mini(t.size(), cap(side)):
			for e: String in (t[i] as CreatureSpec).validate(DataRegistry.db):
				out.append("%s %d: %s" % ["You" if side == MINE else "Foe", i + 1, e])
	return out


## The exhibition the Start button runs, or null while a creature is invalid.
func make_setup() -> BattleSetup:
	if not errors().is_empty() or mine.is_empty() or foes.is_empty():
		return null
	return BattleLauncher.exhibition_setup(DataRegistry.db, mine.slice(0, cap(MINE)), fielded(MINE),
		foes.slice(0, cap(FOES)), fielded(FOES), wild, bag, menu.rng)


# --- Drawing ----------------------------------------------------------------------

func build(box: VBoxContainer) -> void:
	if not _state_ready:
		_setup_state()
	_format_row(box)
	_tabs(box)
	_team_rows(box)
	_team_tools(box)
	var row: HBoxContainer = _row(box)
	UIKit.button(row, "Start", _start)
	UIKit.button(row, "Back", func() -> void: menu.show_page(DebugMainPage.new()))


func _setup_state() -> void:
	_state_ready = true
	bag = BattleLauncher.TEST_BAG.duplicate()
	fill_from_party()
	if mine.is_empty():
		mine = [_random_spec(NO_PARTY_LEVEL)]
	foes = [_random_spec(default_level())]
	my_field = mini(BattleLauncher.MAX_SIDE, mine.size())
	foe_field = 1


func _random_spec(level: int) -> CreatureSpec:
	var db: Database = DataRegistry.db
	var ids: Array = Array(db.ids("creatures"))
	ids.sort()
	var species: String = ids[menu.rng.randi_range(0, ids.size() - 1)]
	return CreatureSpec.natural(db, species, clampi(level, 1, db.balance.level_cap), menu.rng)


func _row(box: Container) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	return row


## You field / Foes field / Foe kind, and the "2v3  Underdog" note.
func _format_row(box: VBoxContainer) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	box.add_child(grid)
	# Only counts the team can actually field are offered, so the drop-down always
	# shows what will happen (a 1-creature team fields 1); the wanted value is kept.
	var you: OptionButton = menu.option_row(grid, "You field", _counts(MINE), fielded(MINE) - 1)
	you.item_selected.connect(func(i: int) -> void:
		my_field = i + 1
		menu.refresh_page())
	var them: OptionButton = menu.option_row(grid, "Foes field", _counts(FOES), fielded(FOES) - 1)
	them.disabled = wild  # a wild pack fights all at once
	them.item_selected.connect(func(i: int) -> void:
		foe_field = i + 1
		menu.refresh_page())
	var kind: OptionButton = menu.option_row(grid, "Foe kind", ["Wild", "Tamer"], 0 if wild else 1)
	kind.item_selected.connect(func(i: int) -> void:
		wild = i == 0
		menu.refresh_page())
	var a: int = fielded(MINE)
	var b: int = fielded(FOES)
	var who: String = "Even fight."
	if a < b:
		who = "You're the Underdog."
	elif a > b:
		who = "The foe is the Underdog."
	UIKit.label(box, "%dv%d   %s   Nothing here is saved." % [a, b, who], 11, UIKit.MUTED)


func _tabs(box: VBoxContainer) -> void:
	var row: HBoxContainer = _row(box)
	for side: int in [MINE, FOES]:
		var b: Button = UIKit.button(row, "Your team" if side == MINE else "Foe team", func() -> void:
			tab = side
			menu.refresh_page())
		b.toggle_mode = true
		b.set_pressed_no_signal(tab == side)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## One row per creature: "2. Tidepup Lv 8  bench  Edit  Remove".
func _team_rows(box: VBoxContainer) -> void:
	var db: Database = DataRegistry.db
	var t: Array = team(tab)
	for i: int in t.size():
		var s: CreatureSpec = t[i]
		var row: HBoxContainer = _row(box)
		var name: String = db.creature(s.species).name if db.has("creatures", s.species) else s.species
		var extra: String = ""
		if s.held_item != "":
			extra = " +item"
		var l: Label = UIKit.label(row, "%d. %s Lv %d%s" % [i + 1, name, s.level, extra])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		if i >= cap(tab):
			UIKit.label(row, "unused", 11, UIKit.DANGER)  # past a wild pack's limit
		elif i >= fielded(tab):
			UIKit.label(row, "bench", 11, UIKit.MUTED)
		var side: int = tab
		UIKit.button(row, "Edit", func() -> void: menu.show_page(DebugSlotEditor.new(self, side, i)))
		var remove: Button = UIKit.button(row, "Remove", func() -> void:
			remove_creature(side, i)
			menu.refresh_page())
		remove.disabled = t.size() <= 1


func _team_tools(box: VBoxContainer) -> void:
	var db: Database = DataRegistry.db
	var t: Array = team(tab)
	var side: int = tab
	var row: HBoxContainer = _row(box)
	var add: Button = UIKit.button(row, "Add creature", func() -> void:
		add_creature(side)
		menu.refresh_page())
	add.disabled = t.size() >= cap(tab)
	if tab == MINE:
		var save: SaveGame = GameState.current
		var fill: Button = UIKit.button(row, "Fill from my party", func() -> void:
			fill_from_party()
			menu.refresh_page("Copied your party."))
		fill.disabled = save == null or save.party.is_empty()
		UIKit.button(row, "Bag...", func() -> void: menu.show_page(DebugBagPage.new(self)))
	else:
		UIKit.button(row, "Randomize", func() -> void:
			randomize_foes()
			menu.refresh_page())
	var levels: HBoxContainer = _row(box)
	var first: CreatureSpec = t[0]
	var spin: SpinBox = menu.spin_row(levels, "All levels", 1, db.balance.level_cap, first.level)
	UIKit.button(levels, "Apply", func() -> void:
		set_all_levels(side, int(spin.value))
		menu.refresh_page())


func _start() -> void:
	var setup: BattleSetup = make_setup()
	if setup == null:
		var problems: PackedStringArray = errors()
		menu.set_status(problems[0] if not problems.is_empty() else "Both teams need a creature.")
		return
	menu.go(setup)


## The field counts offered for `side`: 1 to the most its team can field.
func _counts(side: int) -> Array:
	var out: Array = []
	for i: int in mini(BattleLauncher.MAX_SIDE, maxi(1, team(side).size())):
		out.append(str(i + 1))
	return out
