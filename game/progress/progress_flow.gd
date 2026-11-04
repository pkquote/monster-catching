class_name ProgressFlow
extends RefCounted
## The after-battle step: for each creature that levelled, a Learn Move screen
## per offered move, then the Grow screen if it is ready.


static func run(parent: Node, progress: Array) -> void:
	for entry: Dictionary in progress:
		var c: CreatureInstance = entry.creature
		for move in entry.offered_moves:
			await LearnMoveScreen.run(parent, c, move)
		if entry.growth_due:
			await GrowScreen.run(parent, c)
