class_name FieldCountPrompt
extends CanvasLayer
## "Send out how many?" before a battle. Fewer than the foe means Underdog.
## Shared by wild encounters, tamers, Story.start_battle and the debug menu.


## Asks how many creatures to field against a format of `format_size`. Returns
## the count, or null if cancelled. Skips the question when there's one choice.
static func ask(parent: Node, format_size: int, intro: String, allow_cancel := true) -> Variant:
	var most := BattleLauncher.max_fieldable(GameState.current, format_size)
	if most <= 1:
		return 1
	var layer := FieldCountPrompt.new()
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(layer)
	var root := Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := UIKit.panel(center, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(300, 0)
	panel.add_child(box)
	UIKit.label(box, intro, UIKit.BODY_SIZE, UIKit.TEXT, true)
	UIKit.label(box, "Send out how many? Fewer than the foe makes you the Underdog.", 11, UIKit.MUTED, true)
	var menu := CommandMenu.new()
	box.add_child(menu)
	var options: Array = []
	for i in range(most, 0, -1):
		var note := "" if i >= format_size else "  (Underdog)"
		options.append({"label": "%d creature%s%s" % [i, "" if i == 1 else "s", note], "value": i})
	var n = await menu.choose("", options, allow_cancel, 1)
	layer.queue_free()
	return n
