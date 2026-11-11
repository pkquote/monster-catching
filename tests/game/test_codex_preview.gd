extends GdUnitTestSuite
## The Codex list's left pane: what the focused row shows, and what an unseen species hides.

var save: SaveGame


func before_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	save = SaveGame.new_game("Ana", 1000, rng)


func _preview() -> CodexPreview:
	var p: CodexPreview = auto_free(CodexPreview.new())
	add_child(p)
	return p


func test_unseen_shows_a_silhouette_and_no_name() -> void:
	var p := _preview()
	p.show_entry(DataRegistry.db, save, "tidepup")
	assert_str(p.name_text()).is_equal("#001 ???")
	assert_str(p.name_text()).not_contains(DataRegistry.db.creature("tidepup").name)
	assert_str(p.status_text()).is_equal("Not seen yet")
	assert_bool(p.is_silhouette()).is_true()


func test_seen_shows_name_and_status() -> void:
	Codex.mark_seen(save, "tidepup")
	var p := _preview()
	p.show_entry(DataRegistry.db, save, "tidepup")
	assert_str(p.name_text()).is_equal("#001 " + DataRegistry.db.creature("tidepup").name)
	assert_str(p.status_text()).is_equal("Seen, not caught yet")
	assert_bool(p.is_silhouette()).is_false()


func test_caught_shows_caught() -> void:
	Codex.mark_caught(save, "tidepup")
	var p := _preview()
	p.show_entry(DataRegistry.db, save, "tidepup")
	assert_str(p.status_text()).is_equal("Caught")


func test_show_empty_clears() -> void:
	var p := _preview()
	p.show_entry(DataRegistry.db, save, "tidepup")
	p.show_empty()
	assert_str(p.name_text()).is_empty()
	assert_str(p.status_text()).is_empty()
