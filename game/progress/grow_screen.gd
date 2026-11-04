class_name GrowScreen
extends ProgressScreen
## Offers a ready creature the chance to grow, plays a placeholder flash, then
## offers any moves the new species brings that have no free slot.

const FLASH_SECONDS := 0.4

var _swatch: ColorRect
var _flash: ColorRect


## True if the creature grew. Returns false at once if it isn't ready.
static func run(parent: Node, c: CreatureInstance, db: Database = null) -> bool:
	var into := Progression.growth_target(db if db != null else DataRegistry.db, c)
	if into == "":
		return false
	var screen := GrowScreen.new()
	screen.use_game(null, db)
	parent.add_child(screen)
	var grew := await screen._ask(parent, c, into)
	screen.close()
	return grew


func _ready() -> void:
	super()
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(48, 48)
	_info.add_child(_swatch)
	_info.move_child(_swatch, 0)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_flash)


func _ask(parent: Node, c: CreatureInstance, into: String) -> bool:
	var db := _db
	var old_name := c.display_name(db)  # before growing: no nickname means the species name
	var new_name := db.creature(into).name
	_show_species(c.species)
	_title.text = old_name
	var branch := Progression.growth_branch(db, c)
	var side: String = branch.get("affinity", "") if branch.get("into", "") == into else ""
	if side != "":
		_body.text = "%s is ready to grow! Its %s side is strongest: it will become %s." % [old_name, db.affinity(side).name, new_name]
	else:
		_body.text = "%s is ready to grow! It will become %s." % [old_name, new_name]
	var choice = await menu.choose("", [{"label": "Grow now", "value": true},
		{"label": "Not yet", "value": false}], true, 1)
	if choice != true:
		return false
	await _play_flash()
	var result := Progression.apply_growth(db, c, into)
	_show_species(into)
	_body.text = "%s grew into %s!" % [old_name, new_name]
	await menu.choose("", [{"label": "OK", "value": null}], true, 1)
	for move in result.offered:
		await LearnMoveScreen.run(parent, c, move, false, _db)
	return true


func _show_species(species: String) -> void:
	_swatch.color = species_color(species, _db)


func _play_flash() -> void:
	if Overworld.instant:
		return
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 1.0, FLASH_SECONDS / 2.0)
	tween.tween_property(_flash, "color:a", 0.0, FLASH_SECONDS / 2.0)
	await tween.finished
