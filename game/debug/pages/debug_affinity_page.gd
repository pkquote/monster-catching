class_name DebugAffinityPage
extends DebugPage
## Pick a party creature, then the Affinity track to push to the front (unlocking its passive).


func title() -> String:
	return "Set Affinity"


func build(box: VBoxContainer) -> void:
	var pick: OptionButton = menu.creature_picker(box)
	var db := DataRegistry.db
	for a: String in db.ids("affinities"):
		UIKit.button(box, db.affinity(a).name, func(): _set_affinity(pick.selected, a))
	UIKit.button(box, "Back", func(): menu.show_page(DebugMainPage.new()))


## Sets `track` to the growth threshold + 10, and strictly above every other track
## (so, if another track is higher, to that track's points + 10).
func _set_affinity(index: int, track: String) -> void:
	var db := DataRegistry.db
	var c: CreatureInstance = GameState.current.party[index]
	var value: int = db.balance.growth_affinity_threshold + 10
	for a: String in db.ids("affinities"):
		if a != track:
			value = maxi(value, int(c.affinity.get(a, 0)) + 10)
	c.affinity[track] = value
	var text := "%s: %s is now %d." % [c.display_name(db), db.affinity(track).name, value]
	var unlocked := Passives.try_unlock(db, c, track)  # as reaching the threshold in battle would
	if unlocked != "":
		text += " Unlocked %s." % db.passive(unlocked).name
	GameState.autosave()
	menu.show_page(DebugMainPage.new(), text)
