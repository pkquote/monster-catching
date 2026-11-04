class_name BattlePlayback
extends RefCounted
## Plays engine events one at a time on the battle scene: updates views, shows the
## message, and waits for animations. Never decides outcomes.

## Tests set this to skip all waiting.
static var instant := false

var scene: Node
var db: Database


func _init(p_scene: Node, p_db: Database) -> void:
	scene = p_scene
	db = p_db


## Duration scaled by the battle-speed setting; holding Accept plays 4x faster.
static func scaled(seconds: float) -> float:
	if instant:
		return 0.0
	var speed := 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Settings"):
		speed = float(tree.root.get_node("Settings").data.battle_speed)
	if InputMap.has_action("accept") and Input.is_action_pressed("accept"):
		speed *= 4.0
	return seconds / speed


func play(ev: Dictionary) -> void:
	var text := BattleText.describe(ev, db, Callable(scene, "display_name"), scene.tamer_name)
	var v: CreatureView = scene.views.get(int(ev.get("bid", -1)))
	match ev.type:
		"send_out":
			v = scene.place_view(ev.bid, ev.side, ev.slot)
			v.set_hp(ev.hp, ev.max_hp, false)
			v.set_energy(ev.get("energy", 0), ev.get("max_energy", 1))
			scene.message(text)
			await v.appear()
			await _pause(0.35)
		"swap_out":
			scene.message(text)
			if v != null:
				await v.vanish()
			scene.release_view(ev.bid)
		"move_used":
			scene.message(text)
			if v != null:
				await v.nudge()
			await _pause(0.3)
		"damage":
			if v != null:
				v.flash()
				await v.set_hp(ev.hp, ev.max_hp)
			if text != "":
				scene.message(text)
				await _pause(0.45)
		"heal":
			if v != null:
				await v.set_hp(ev.hp, ev.max_hp)
			await _say(text)
		"energy":
			if v != null:
				v.set_energy(ev.energy, ev.max_energy)
		"status_applied":
			if v != null:
				v.set_status(ev.status, db.status(ev.status).name)
			await _say(text)
		"status_ended":
			if v != null:
				v.set_status("", "")
			await _say(text)
		"field_applied":
			scene.fields[ev.side].applied(ev.state, ev.stacks, ev.turns)
			scene.stage.set_tint(ev.side, scene.fields[ev.side].newest_color())
			await _say(text)
		"field_removed":
			scene.fields[ev.side].removed(ev.state)
			scene.stage.set_tint(ev.side, scene.fields[ev.side].newest_color())
			await _say(text)
		"reaction":
			await scene.banner(db.reaction(ev.reaction).name.to_upper() + "!")
			await _say(text)
		"capture_attempt":
			var target: CreatureView = scene.views.get(int(ev.target))
			scene.message("You threw a %s..." % db.item(ev.item).name)
			var shakes := 3 if ev.success else clampi(int(float(ev.chance) * 3.0), 0, 2)
			if target != null:
				await target.capture_sequence(shakes, ev.success)
			if not ev.success:
				await _say("Oh no! It broke free!")
		"captured":
			if v != null:
				v.visible = false
			await _say(text)
		"faint":
			scene.message(text)
			if v != null:
				await v.vanish()
			await _pause(0.3)
		"underdog":
			scene.fields[ev.side].set_underdog(ev.bonus_actions, ev.ratio)
			await _say(text)
		"level_up":
			if v != null:
				v.set_level(scene.display_name(ev.bid), ev.level)
			await _say(text)
		_:
			await _say(text)
	scene.record(ev)


func _say(text: String) -> void:
	if text == "":
		return
	scene.message(text)
	await _pause(0.6)


func _pause(seconds: float) -> void:
	var d := scaled(seconds)
	if d <= 0.0:
		await scene.get_tree().process_frame
	else:
		await scene.get_tree().create_timer(d).timeout
