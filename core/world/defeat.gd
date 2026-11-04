class_name Defeat
extends RefCounted
## Losing a battle: the team is patched up, some money is dropped, and the
## player wakes at the last heal spot they used (or where the game began).


## Applies the loss to `save`. Returns { lost_money, map, spawn } (where to wake up).
static func apply(db: Database, save: SaveGame) -> Dictionary:
	for c: CreatureInstance in save.party:
		c.heal_full(db)
	var lost := floori(save.money * float(db.balance.overworld_cfg.defeat_money_fraction))
	save.money -= lost
	var heal: Dictionary = save.story.last_heal
	var map: String = heal.get("map", "")
	if map == "":
		return {"lost_money": lost, "map": SaveGame.NEW_GAME_MAP, "spawn": SaveGame.NEW_GAME_SPAWN}
	return {"lost_money": lost, "map": map, "spawn": heal.get("spawn", "")}
