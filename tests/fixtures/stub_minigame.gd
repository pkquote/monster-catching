extends Minigame
## Finishes straight away with a fixed result (tests the minigame hook).


func begin(params: Dictionary) -> void:
	finish.call_deferred({"won": true, "score": int(params.get("score", 7))})


func finish(result: Dictionary) -> void:
	finished.emit(result)
