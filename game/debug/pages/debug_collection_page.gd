class_name DebugCollectionPage
extends DebugPage
## F1 > Collection: mark species seen or caught, move a lifetime counter, unlock or reset achievements.
## Every action goes through the real tracking, so the achievement service reacts as it does in play.


func title() -> String:
	return "Collection"


func width() -> float:
	return 300.0


func build(box: VBoxContainer) -> void:
	var db := DataRegistry.db
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	var species_ids := Codex.order(db)
	var species := option_names(species_ids.size(), func(i: int) -> String: return db.creature(species_ids[i]).name)
	var species_pick: OptionButton = menu.option_row(grid, "Species", species, 0)
	UIKit.button(box, "Mark seen", func(): _act(func(): mark_species(species_ids[species_pick.selected], false),
		"Marked seen."))
	UIKit.button(box, "Mark caught", func(): _act(func(): mark_species(species_ids[species_pick.selected], true),
		"Marked caught."))
	UIKit.spacer(box, 4)
	var grid2 := GridContainer.new()
	grid2.columns = 2
	grid2.add_theme_constant_override("h_separation", 12)
	box.add_child(grid2)
	var counter_pick: OptionButton = menu.option_row(grid2, "Counter", Array(Counters.BUILT_IN), 0)
	var amount: SpinBox = menu.spin_row(grid2, "Amount", 1, 100000, 10)
	UIKit.button(box, "Add to counter", func(): _act(func(): add_counter(Counters.BUILT_IN[counter_pick.selected],
		int(amount.value)), "Counter raised."))
	UIKit.spacer(box, 4)
	var grid3 := GridContainer.new()
	grid3.columns = 2
	grid3.add_theme_constant_override("h_separation", 12)
	box.add_child(grid3)
	var ids := Achievements.listed(db)
	var names := option_names(ids.size(), func(i: int) -> String: return db.achievement(ids[i]).name)
	var ach_pick: OptionButton = menu.option_row(grid3, "Achievement", names, 0)
	UIKit.button(box, "Unlock", func(): _act(func(): unlock(ids[ach_pick.selected]), "Unlocked."))
	UIKit.button(box, "Reset", func(): _act(func(): reset(ids[ach_pick.selected]), "Reset."))
	UIKit.button(box, "Reset all", func(): _act(reset_all, "All achievements reset."))
	UIKit.button(box, "Back", func(): menu.show_page(DebugMainPage.new()))


func mark_species(id: String, caught: bool) -> void:
	if caught:
		Codex.mark_caught(GameState.current, id)
	else:
		Codex.mark_seen(GameState.current, id)


func add_counter(id: String, n: int) -> void:
	Counters.add(GameState.current, id, n)


func unlock(id: String) -> bool:
	return AchievementService.unlock(id)


## Locks `id` again and asks for a full pass, so it is earned again if it is still met.
func reset(id: String) -> void:
	Achievements.reset(GameState.current, id)
	AchievementWatch.push(AchievementWatch.ALL)


func reset_all() -> void:
	Achievements.reset(GameState.current)
	AchievementWatch.push(AchievementWatch.ALL)


## Runs `action`, saves, and shows the page again with `status`.
func _act(action: Callable, status: String) -> void:
	action.call()
	GameState.autosave()
	menu.show_page(DebugCollectionPage.new(), status)


static func option_names(count: int, name_of: Callable) -> Array:
	var out := []
	for i in count:
		out.append(name_of.call(i))
	return out
