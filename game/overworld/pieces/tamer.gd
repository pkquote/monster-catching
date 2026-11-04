@tool
class_name Tamer
extends Npc
## An NPC tamer from data/tamers. Looks `sight` tiles along its facing; when the
## player steps into view it shows "!", walks up and runs `before_title`, whose
## script calls Story.start_battle(tamer_id). Beaten for good on a win; after
## that, talking runs `after_title`.

@export var tamer_id := ""
@export_range(0, 12) var sight := 4
@export var before_title := ""
@export var after_title := ""


func beaten() -> bool:
	return Story.is_done(save_key())


## Whether the player standing on `t` is in this tamer's view.
func sees(t: Vector2i, map: GameMap) -> bool:
	if beaten() or sight <= 0:
		return false
	return Grid.sight_tiles(tile(), facing, sight, func(x: Vector2i) -> bool: return map.is_solid(x, self)).has(t)


## "!", walk up to the player, talk, battle. The sequence runs on the overworld
## (BattleFlow.tamer_challenge), because losing can change map and free this tamer.
func challenge(w: Overworld) -> void:
	w.battles.tamer_challenge(self, true)


func on_interact(w: Overworld) -> void:
	face_toward(w.player.feet_tile())
	if beaten():
		w.say(dialogue, after_title)
	elif BattleLauncher.healthy_count(GameState.current) == 0:
		w.say_lines([{"speaker": display_name, "text": "Your team can't fight right now!"}])
	else:
		w.battles.tamer_challenge(self, false)


func marker_color() -> Color:
	return Color("f08040")


func marker_label() -> String:
	return "tamer: " + tamer_id
