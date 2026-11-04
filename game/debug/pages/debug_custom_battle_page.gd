class_name DebugCustomBattlePage
extends DebugPage
## Any format (1v3, 3v1...), wild or tamer, and the foes' level.


func title() -> String:
	return "Custom battle"


func build(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var save := GameState.current
	var most := mini(BattleLauncher.MAX_SIDE, BattleLauncher.healthy_count(save))
	var mine: OptionButton = menu.option_row(grid, "You field", range(1, most + 1).map(func(i): return str(i)), most - 1)
	var theirs: OptionButton = menu.option_row(grid, "Foes", range(1, BattleLauncher.MAX_SIDE + 1).map(func(i): return str(i)), 0)
	var kind: OptionButton = menu.option_row(grid, "Foe kind", ["Wild", "Tamer"], 0)
	UIKit.label(grid, "Foe level")
	var level := SpinBox.new()
	level.min_value = 1
	level.max_value = DataRegistry.db.balance.level_cap
	level.value = BattleLauncher.party_level(save)
	grid.add_child(level)
	var note := UIKit.label(box, "", 11, UIKit.MUTED)
	var refresh := func():
		var a := mine.selected + 1
		var b := theirs.selected + 1
		var who := "Even fight."
		if a < b:
			who = "You're the Underdog."
		elif a > b:
			who = "The foe is the Underdog."
		note.text = "%dv%d   %s" % [a, b, who]
	for o: OptionButton in [mine, theirs]:
		o.item_selected.connect(refresh.unbind(1))
	refresh.call()
	UIKit.label(box, "Foes are random species. Wild foes can be caught; tamers use the tactician AI.",
		11, UIKit.MUTED, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	UIKit.button(row, "Start", func():
		menu.go(BattleLauncher.custom_setup(DataRegistry.db, GameState.current, mine.selected + 1,
			theirs.selected + 1, int(level.value), kind.selected == 0, menu.rng)))
	UIKit.button(row, "Back", func(): menu.show_page(DebugMainPage.new()))
