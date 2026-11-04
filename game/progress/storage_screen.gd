class_name StorageScreen
extends ProgressScreen
## The creature box: party on the left, the current box page on the right.
## Pick a creature, then Deposit / Withdraw, or Swap with one on the other side.

const PAGE_SIZE := 10
const LAST_HEALTHY_TEXT := "Keep at least one creature that can fight."
const PARTY_FULL_TEXT := "Your party is full."
const ROW_HEIGHT := 18.0

var page := 0

var _message := ""


## Runs until the player closes the screen.
static func run(world: Node) -> void:
	var screen := StorageScreen.new()
	world.add_child(screen)
	await screen._loop()
	screen.close()


## Number of box pages (at least one).
static func page_count(box_size: int) -> int:
	return maxi(1, ceili(float(box_size) / PAGE_SIZE))


static func refusal_text(reason: String) -> String:
	match reason:
		"last_healthy":
			return LAST_HEALTHY_TEXT
		"party_full":
			return PARTY_FULL_TEXT
	return ""


func _ready() -> void:
	super()
	_info.get_parent().position.y = 4  # as the Summary screen: leaves room for ten rows
	_bottom.position.y = 68


## One compact list row for a creature, `prefix` says which side it is on.
func _row(prefix: String, c: CreatureInstance, value: Variant) -> Dictionary:
	var db := DataRegistry.db
	var label := "%s%s  Lv %d  HP %d/%d" % [prefix, c.display_name(db), c.level, c.hp, c.max_hp(db)]
	return {"label": label, "value": value, "decorate": func(b: Button) -> void:
		b.custom_minimum_size.y = ROW_HEIGHT
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		img.fill(species_color(c.species))
		b.icon = ImageTexture.create_from_image(img)}


func _blank() -> Dictionary:
	return {"label": "", "value": null, "disabled": true,
		"decorate": func(b: Button) -> void: b.custom_minimum_size.y = ROW_HEIGHT}


func _plain(label: String, value: Variant) -> Dictionary:
	return {"label": label, "value": value,
		"decorate": func(b: Button) -> void: b.custom_minimum_size.y = ROW_HEIGHT}


func _show_header() -> void:
	var save := GameState.current
	page = clampi(page, 0, page_count(save.storage.size()) - 1)
	_title.text = "Box — page %d of %d" % [page + 1, page_count(save.storage.size())]
	if _message != "":
		_body.text = _message
	elif save.storage.is_empty():
		_body.text = "The box is empty."
	else:
		_body.text = "Pick a creature."


## Indices into the box for the current page.
func _page_range() -> Vector2i:
	var n := GameState.current.storage.size()
	var from := page * PAGE_SIZE
	return Vector2i(from, mini(from + PAGE_SIZE, n))


## Party rows on the left (then `extras`, so Back and paging take no extra rows),
## box rows on the right, side by side in a two-column grid.
func _grid_options(party: bool, box: bool, extras: Array) -> Array:
	var save := GameState.current
	var r := _page_range()
	var left: Array = []
	if party:
		for k in save.party.size():
			left.append(_row("Party: ", save.party[k], ["party", k]))
	left.append_array(extras)
	var right: Array = []
	if box:
		for k in range(r.x, r.y):
			right.append(_row("Box: ", save.storage[k], ["box", k]))
	var options: Array = []
	for k in maxi(left.size(), right.size()):
		options.append(left[k] if k < left.size() else _blank())
		options.append(right[k] if k < right.size() else _blank())
	return options


func _nav_extras() -> Array:
	var extras: Array = []
	if page > 0:
		extras.append(_plain("Previous page", ["prev", 0]))
	if _page_range().y < GameState.current.storage.size():
		extras.append(_plain("Next page", ["next", 0]))
	extras.append(_plain("Back", ["back", 0]))
	return extras


func _loop() -> void:
	menu.button_width = 305
	while true:
		_show_header()
		var pick = await menu.choose("", _grid_options(true, true, _nav_extras()), true, 2)
		if pick == null or pick[0] == "back":
			return
		match pick[0]:
			"prev":
				page -= 1
				_message = ""
			"next":
				page += 1
				_message = ""
			"party":
				await _party_creature(pick[1])
			"box":
				await _box_creature(pick[1])


func _party_creature(party_i: int) -> void:
	var save := GameState.current
	var c: CreatureInstance = save.party[party_i]
	_title.text = c.display_name(DataRegistry.db)
	_body.text = ""
	var choice = await _step([
		{"label": "Deposit", "value": "deposit"},
		{"label": "Swap with a box creature", "value": "swap",
			"disabled": save.storage.is_empty()},
		{"label": "Cancel", "value": null}])
	match choice:
		"deposit":
			_finish(Team.deposit(DataRegistry.db, save, party_i))
		"swap":
			_body.text = "Swap with which box creature?"
			var pick = await menu.choose("", _grid_options(false, true,
					[_plain("Cancel", ["back", 0])]), true, 2)
			if pick != null and pick[0] == "box":
				_finish(Team.swap(DataRegistry.db, save, party_i, pick[1]))
			else:
				_message = ""
		_:
			_message = ""


func _box_creature(box_i: int) -> void:
	var save := GameState.current
	var c: CreatureInstance = save.storage[box_i]
	_title.text = c.display_name(DataRegistry.db)
	_body.text = ""
	var choice = await _step([
		{"label": "Withdraw", "value": "withdraw"},
		{"label": "Swap with a party creature", "value": "swap"},
		{"label": "Cancel", "value": null}])
	match choice:
		"withdraw":
			_finish(Team.withdraw(DataRegistry.db, save, box_i))
		"swap":
			_body.text = "Swap with which party creature?"
			var pick = await menu.choose("", _grid_options(true, false,
					[_plain("Cancel", ["back", 0])]), true, 2)
			if pick != null and pick[0] == "party":
				_finish(Team.swap(DataRegistry.db, save, pick[1], box_i))
			else:
				_message = ""
		_:
			_message = ""


## A single-column action list.
func _step(options: Array) -> Variant:
	for o: Dictionary in options:
		o["decorate"] = func(b: Button) -> void: b.custom_minimum_size.y = ROW_HEIGHT
	return await menu.choose("", options, true, 1)


func _finish(reason: String) -> void:
	_message = refusal_text(reason)
