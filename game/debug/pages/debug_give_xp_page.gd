class_name DebugGiveXpPage
extends DebugPage
## Pick a party creature, then give it XP; the Learn Move / Grow screens follow.

const TARGET_LEVEL := 16


func title() -> String:
	return "Give XP"


func build(box: VBoxContainer) -> void:
	var pick: OptionButton = menu.creature_picker(box)
	var cap: int = DataRegistry.db.balance.level_cap
	UIKit.button(box, "+1 level", func(): _give_xp(pick.selected, -1))
	var to16 := UIKit.button(box, "To level %d" % mini(TARGET_LEVEL, cap), func(): _give_xp(pick.selected, mini(TARGET_LEVEL, cap)))
	var update := func():
		to16.disabled = GameState.current.party[pick.selected].level >= mini(TARGET_LEVEL, cap)
	pick.item_selected.connect(update.unbind(1))
	update.call()
	UIKit.button(box, "Back", func(): menu.show_page(DebugMainPage.new()))


## Raises a party creature to `to_level` (or one level when -1), then runs the
## progress screens. The menu closes first: the screens can't run in a paused tree.
func _give_xp(index: int, to_level: int) -> void:
	var world := Overworld.active
	if world == null or index >= GameState.current.party.size():
		return
	var db := DataRegistry.db
	var c: CreatureInstance = GameState.current.party[index]
	if c.level >= db.balance.level_cap:
		menu.show_page(DebugMainPage.new(), "%s is at the level cap." % c.display_name(db))
		return
	var goal: int = c.level + 1 if to_level < 0 else mini(to_level, db.balance.level_cap)
	var before := c.level
	var passive_before := c.affinity_passive
	Progression.award_xp(db, c, maxi(1, Stats.xp_for_level(goal) - c.xp))
	var entry := Progression.progress_entry(db, c, before, passive_before)
	menu.refresh_world()
	menu.close()  # drops this page: the rest runs in a static function that doesn't need it
	_progress_then_save(world, entry)


static func _progress_then_save(world: Overworld, entry: ProgressEntry) -> void:
	if entry != null:
		await world.battles.run_progress([entry])
	GameState.autosave()  # after the screens, so Learn Move / Grow choices are kept
