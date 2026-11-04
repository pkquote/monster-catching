extends Node
## Commands for scripted scenes in .dialogue files (autoload `Cutscene`), e.g.
##
##   $> Cutscene.lock_player()
##   $> Cutscene.move("prof", "lab_door")
##   $> Cutscene.face("player", "prof")
##
## Actors are "player" or an Npc's actor_id on the current map. Spots are a spawn
## id on the current map or a "x,y" tile. A typo pushes an error and returns
## straight away, so a broken cutscene never hangs the game.


func _world() -> Overworld:
	if Overworld.active == null:
		Log.error(Log.STORY, "Cutscene: no overworld open")
	return Overworld.active


func lock_player() -> void:
	Log.debug(Log.STORY, "Cutscene lock_player")
	var w := _world()
	if w != null:
		w.lock(Overworld.LOCK_CUTSCENE)


func unlock_player() -> void:
	Log.debug(Log.STORY, "Cutscene unlock_player")
	var w := _world()
	if w != null:
		w.unlock(Overworld.LOCK_CUTSCENE)


## Walks an actor to a spot in straight lines (x first, then y).
func move(actor: String, where: String) -> void:
	Log.debug(Log.STORY, "Cutscene move", {"actor": actor, "to": where})
	var w := _world()
	if w == null:
		return
	var a := _actor(w, actor)
	var spot = _spot(w, where)
	if a == null or spot == null:
		return
	await a.walk_to(spot)


## Turns an actor to "up"/"down"/"left"/"right", or toward another actor.
func face(actor: String, toward: String) -> void:
	Log.debug(Log.STORY, "Cutscene face", {"actor": actor, "toward": toward})
	var w := _world()
	if w == null:
		return
	var a := _actor(w, actor)
	if a == null:
		return
	var dir: Vector2i = Npc.FACINGS.get(toward, Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		var other := _actor(w, toward)
		if other == null:
			return
		var d: Vector2i = GameMap.tile_of(other.position) - GameMap.tile_of(a.position)
		dir = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	if a is Player:
		a.place(a.position, dir)
	else:
		a.facing = dir
		a.queue_redraw()


func emote(actor: String, kind: String) -> void:
	Log.debug(Log.STORY, "Cutscene emote", {"actor": actor, "kind": kind})
	var w := _world()
	if w == null:
		return
	var a := _actor(w, actor)
	if a != null:
		await Emote.show_over(a, kind)


func pan_camera(where: String) -> void:
	Log.debug(Log.STORY, "Cutscene pan_camera", {"to": where})
	var w := _world()
	if w == null:
		return
	var spot = _spot(w, where)
	if spot != null:
		w.camera_focus = GameMap.centre_of(spot)


func camera_back() -> void:
	Log.debug(Log.STORY, "Cutscene camera_back")
	var w := _world()
	if w != null:
		w.camera_focus = null


func fade_out() -> void:
	Log.debug(Log.STORY, "Cutscene fade_out")
	var w := _world()
	if w != null:
		await w.fade(1.0)


func fade_in() -> void:
	Log.debug(Log.STORY, "Cutscene fade_in")
	var w := _world()
	if w != null:
		await w.fade(0.0)


func wait(seconds: float) -> void:
	Log.debug(Log.STORY, "Cutscene wait", {"seconds": seconds})
	if not Overworld.instant:
		await get_tree().create_timer(seconds).timeout


func change_map(map_id: String, spawn_id: String) -> void:
	Log.debug(Log.STORY, "Cutscene change_map", {"map": map_id, "spawn": spawn_id})
	var w := _world()
	if w != null:
		await w.change_map(map_id, spawn_id)


# --- Lookups ------------------------------------------------------------------------

func _actor(w: Overworld, id: String) -> Node2D:
	if id == "player":
		return w.player
	for p in w.map.pieces():
		if p is Npc and (p as Npc).actor_id == id:
			return p
	Log.error(Log.STORY, "Cutscene: no such actor", {"actor": id, "map": w.map.map_id()})
	return null


## A spawn id or "x,y" -> tile, or null.
func _spot(w: Overworld, where: String) -> Variant:
	var parts := where.split(",")
	if parts.size() == 2 and parts[0].strip_edges().is_valid_int() and parts[1].strip_edges().is_valid_int():
		return Vector2i(int(parts[0]), int(parts[1]))
	var s := w.map.spawn(where)
	if s == null:
		Log.error(Log.STORY, "Cutscene: no such spawn", {"spawn": where, "map": w.map.map_id()})
		return null
	return s.tile()
