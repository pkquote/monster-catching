class_name ShopMenu
extends SideMenu
## A shop counter: buy from its stock, or sell your items for half price.

const AMOUNTS := [1, 2, 3, 5, 10]
## Two columns of this width (+ the 4px gap) fill the side panel's 192px.
const BUY_BUTTON_WIDTH := 94


func run(stock: PackedStringArray) -> void:
	_open("Shop")
	while true:
		page("What can I get you?")
		var choice = await menu.choose("", [{"label": "Buy", "value": "buy"}, {"label": "Sell", "value": "sell"},
			{"label": "Leave", "value": null}], true, 1)
		if choice == null:
			break
		if choice == "buy":
			await _buy(stock)
		else:
			await _sell()
	_close()


func _buy(stock: PackedStringArray) -> void:
	var db := DataRegistry.db
	# A stocked item's price and description show on the page while it is focused: the list
	# is two narrow columns of names so a long stock (Back included) fits the window.
	var show_hint := func(hint: Variant) -> void:
		page(str(hint) if hint != null else "Buying. You have %d money." % Story.money())
	while true:
		var options: Array = []
		for id in stock:
			var it := db.item(id)
			if it != null:
				options.append({"label": it.name, "value": id,
					"hint": "%s - %d\n%s\nYou have %d money." % [it.name, it.price, it.description, Story.money()]})
		options.append({"label": "Back", "value": null})
		page("Buying. You have %d money." % Story.money())
		menu.button_width = BUY_BUTTON_WIDTH
		menu.hovered.connect(show_hint)  # only while the list is up: other menus focus with no hint
		var id = await menu.choose("", options, true, 2)
		menu.hovered.disconnect(show_hint)
		menu.button_width = 192
		if id == null:
			return
		var it := db.item(id)
		var amounts: Array = []
		for n in AMOUNTS:
			if it.price * n <= Story.money():
				amounts.append({"label": "×%d  %d" % [n, it.price * n], "value": n})
		if amounts.is_empty():
			page("You can't afford a %s." % it.name)
			await menu.choose("", [{"label": "OK", "value": null}], true, 1)
			continue
		amounts.append({"label": "Back", "value": null})
		page("%s\n%s\nYou have %d." % [it.name, it.description, int(GameState.current.inventory.get(id, 0))])
		var n = await menu.choose("", amounts, true, 1)
		if n == null:
			continue
		var r := Shop.buy(db, GameState.current, id, n)
		_refresh_money()
		page("Thank you! Bought %s ×%d." % [it.name, n] if r.ok else "That didn't work.")
		await menu.choose("", [{"label": "OK", "value": null}], true, 1)


func _sell() -> void:
	var db := DataRegistry.db
	while true:
		var options: Array = []
		for id in GameState.current.inventory:
			var each := Shop.sell_price(db, id)
			if each > 0:
				options.append({"label": "%s ×%d  %d each" % [db.item(id).name, GameState.current.inventory[id], each], "value": id})
		options.append({"label": "Back", "value": null})
		page("Selling. I pay half price." if options.size() > 1 else "You have nothing I can buy.")
		var id = await menu.choose("", options, true, 1)
		if id == null:
			return
		var owned := int(GameState.current.inventory.get(id, 0))
		var amounts: Array = []
		for n in AMOUNTS:
			if n <= owned:
				amounts.append({"label": "×%d  +%d" % [n, Shop.sell_price(db, id) * n], "value": n})
		amounts.append({"label": "Back", "value": null})
		var n = await menu.choose("", amounts, true, 1)
		if n == null:
			continue
		var r := Shop.sell(db, GameState.current, id, n)
		_refresh_money()
		page("Sold!" if r.ok else "That didn't work.")
		await menu.choose("", [{"label": "OK", "value": null}], true, 1)
