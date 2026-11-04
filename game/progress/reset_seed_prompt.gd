class_name ResetSeedPrompt
extends RefCounted
## The Reset Seed's question, shared by the Bag and the Summary screen's Training tab.


## "1 point" / "3 points".
static func points(n: int) -> String:
	return "%d point%s" % [n, "" if n == 1 else "s"]


## Asks before the seed is spent, through `say` (shows a line of text) and `menu`.
## False = nothing to return, or the player said No.
static func confirm(menu: CommandMenu, say: Callable, c: CreatureInstance, db: Database = null) -> bool:
	var spent := Training.spent(c)
	var cname := c.display_name(db if db != null else DataRegistry.db)
	if spent <= 0:
		say.call("It has no points to return.")
		await menu.choose("", [{"label": "OK", "value": null}], true, 1)
		return false
	say.call("Return %s from %s?" % [points(spent), cname])
	return await menu.choose("", [{"label": "Yes", "value": true}, {"label": "No", "value": false}], true, 1) == true
