# M7b Codex Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Codex list and a per-species detail page on the pause menu, backed by a `dex` number on creatures and a generated `locations` data category.

**Architecture:** Pure `core/` pieces (`dex` ordering in `Codex`, `LocationDef`, a static `Locations` class) feed two `ProgressScreen` subclasses (`CodexScreen` list with a left preview pane, `CodexDetailPage`). `data/locations.json` is generated from the map scenes by a new tool and checked against them by `check_maps`.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4 suites in `tests/`.

**Spec:** `documentation/specs/2026-11-11-m7b-codex-screens-design.md` (parent: `2026-11-11-m7-collection-achievements-design.md`; data from `2026-11-11-m7a-tracking-design.md`)

## Adjustments to the spec (decided while planning; the user reviews these with the plan)
1. **`dex` is required by a data test, not the validator.** `FixtureDB` and the validator suites validate creatures that have no `dex`, so the schema field is optional; the validator rejects duplicates, and `tests/data/test_codex_data.gd` requires a unique `dex` on every shipped (non-`tp_`) creature in `data/`. Creatures without a `dex` (test pack, fixtures) sort after numbered ones, by id.
2. **`locations.json` stores map name and encounter ids only.** `{"id": map_id, "name": display_name, "areas": [encounter_id, ...]}`. The area label shown is the encounter table's own `name`, read from `db.encounter(id)`, so no text is duplicated.
3. **The generator reads the map scenes**, not `build_maps.gd`'s `maps()` list (hand-edited maps are removed from that list): new `tools/build_locations.tscn`. `check_maps` fails when the file differs from what the scenes give.
4. **Both screens extend `ProgressScreen`** so `ScreenFit` applies. The list scrolls (not pages). The detail page shows at most 6 location lines then "+N more places", instead of a scroll container.

## Global Constraints
- **Never `git commit`, `git add` or stash.** The user commits. Work stays in the tree on branch `milestone/M7b`. The last task gives the commit message: title ends `(M7)`, then a bullet list, then the co-author line.
- Ignore unrelated uncommitted work already in the tree (M6, M7a, `data/` edits); do not revert it.
- Do not run two Godot or test processes at once (shared save files).
- Run one suite: `"/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<dir>/<file>.gd --ignoreHeadlessMode -c`. Full check: `bash scripts/check.sh` must end "All checks passed."
- Tours need `--fixed-fps 60` before `--script`; the mode goes after `--` (see the skill's `SKILL.md`).
- Names are exact: `dex` (creature field, int ≥ 1), category `locations` (file category, `data/locations.json`), `LocationDef`, `Locations` (`core/progress/locations.gd`), `CodexPreview`, `CodexScreen`, `CodexDetailPage` (all in `game/progress/`), tool `tools/build_locations.gd`/`.tscn`.
- Reveal rule: an unseen species shows only `#NNN ???` and "Not seen yet"; no name, types, description or location anywhere, including the preview pane.
- Evolves-from line appears only when the source species is **caught**; no "evolves into" text.
- Test maps (ids starting `test_`) never appear in `locations`.
- Files keep their existing line endings; edit with tools that preserve them.

## Review Focus
1. An unseen species leaks nothing: not its name in the list or preview, not on the detail page path (activating it opens nothing) (Tasks 4, 5).
2. A species found in two tables of one map, or in the default table and an area table of the same map, gives the right rows with merged level ranges and no duplicates (Task 2).
3. A map whose encounter table does not list the species gives no row; a species with no wild source falls back to "Evolves from X" only if X is caught, else "No wild habitat known" (Tasks 2, 5).
4. Stale `locations.json` (a scene's encounter changed) fails `check_maps` (Task 3).
5. Creatures with no `dex` (pack, fixtures) still list, after numbered ones, without crashing (Tasks 1, 4).
6. An empty Codex (nothing seen) opens, shows "Seen 0 / N", and every row is `???` (Task 4).

---

### Task 1: `dex` field and Codex order

**Files:**
- Modify: `core/data/schemas.gd` (creatures entry), `core/data/validator.gd` (duplicate-dex rule in `_check_cross_rules`), `core/data/defs/creature_def.gd`, `core/progress/codex.gd`, `data/creatures/starter_line.json`, `data/creatures/route_01.json`
- Test: `tests/data/test_codex_data.gd` (new), `tests/data/test_validator.gd`, `tests/progress/test_codex.gd`

**Interfaces:**
- Produces: `CreatureDef.dex: int` (0 when absent). `Codex.order(db: Database) -> PackedStringArray` (creature ids: numbered by `dex` ascending, then the rest by id). `Codex.number_text(db: Database, species: String) -> String` (`"#001"`; `"#---"` when the creature has no `dex`).

- [ ] **Step 1: Write the failing tests**
  - `test_codex_data.gd`: `test_every_shipped_creature_has_a_unique_dex` loads `DataLoader.load_database("res://data", "res://dialogue")` and asserts every creature in the result has `dex >= 1` and the dex values are unique. `test_dex_numbers_are_contiguous_from_one` asserts the sorted dex values equal `1..N`.
  - `test_validator.gd`: `test_dex_must_be_unique` (two creatures with `dex: 1` → an error naming `dex`); `test_dex_below_one_is_rejected` (`dex: 0`); `test_dex_is_optional` (the base set with no `dex` has no errors).
  - `test_codex.gd` (uses `FixtureDB.build()`, whose creatures have no dex): `test_order_puts_numbered_species_first_then_by_id` builds a database from `FixtureDB.raw()` with `dex` set on `fish` (2) and `flame` (1), and asserts `Codex.order(db)` starts `["flame", "fish"]` followed by the rest sorted by id. `test_number_text_pads_to_three_digits` (`"#001"`, `"#012"`) and `test_number_text_without_dex_is_dashes` (`"#---"`).
- [ ] **Step 2: Run the three suites; expect FAIL** (`dex` unknown field, `Codex.order` not defined).
- [ ] **Step 3: Implement.** Schema: `"dex": {"t": "int", "opt": true, "min": 1}` after `description`. `CreatureDef.from_dict` sets `dex = int(d.get("dex", 0))`. Validator: in `_check_cross_rules`, error `"duplicate dex N (also on <id>)"` using the creature's `[creatures:id]` label. `Codex.order` and `number_text` as above. Number the eight shipped creatures: the starter line first in evolution order, then `route_01.json` species, 1..8 with no gaps (read both files for the order; keep each family together).
- [ ] **Step 4: Run the three suites plus `tests/data/test_testpack_removal.gd`; expect PASS.**

---

### Task 2: `locations` category, `LocationDef`, `Locations`

**Files:**
- Create: `core/data/defs/location_def.gd`, `core/progress/locations.gd`, `data/locations.json`
- Modify: `core/data/schemas.gd` (`CATEGORIES` and `ENTRY`), `core/data/database.gd` (builder and `location()` accessor)
- Test: `tests/progress/test_locations.gd` (new), `tests/data/test_validator.gd`

**Interfaces:**
- Consumes: `Database.encounter(id) -> EncounterDef` (`name`, `table` rows `{species, weight, min_level, max_level}`), `CreatureDef.growth` (`into`), `Codex.order(db)` from Task 1.
- Produces:
  - `LocationDef` (`id`, `name`, `areas: PackedStringArray` of encounter ids) and `Database.location(id)`.
  - `Locations.for_species(db: Database, species: String) -> Array` of `{"map": String, "area": String, "min": int, "max": int}`, one per (map, encounter table), maps in id order, a map's areas in file order, `area` = the encounter's `name`, `min`/`max` merged over every table row of that species.
  - `Locations.evolves_from(db: Database, species: String) -> String` (empty when none; with several sources, the first in `Codex.order`).
  - `Locations.line(row: Dictionary) -> String` → `"Route 1 – Route 1 tall grass, Lv 2–5"` (`"Lv 4"` when min equals max; en dash).
  - `Locations.build(maps: Dictionary, db: Database) -> Dictionary` (used by Task 3): `maps` is `{map_id: {"name": String, "default_encounter": String, "pieces": [{"type": String, "props": {}}]}}`; returns the file document `{"schema": 1, "entries": [{"id", "name", "areas"}]}`, maps sorted by id, ids starting `test_` skipped, maps with no encounters omitted, areas = default encounter first then each `EncounterArea` piece's `props.encounter` in order, duplicates dropped, empty ids dropped.

- [ ] **Step 1: Write the failing tests** (`test_locations.gd`, on a `FixtureDB.raw()` extended in-suite with two `locations` entries and two encounter tables)
  - `test_one_row_per_map_and_table` (species in a map's default table and one area table gives two rows).
  - `test_levels_merge_over_rows_of_one_table` (species twice in one table: min of mins, max of maxes).
  - `test_a_table_without_the_species_gives_no_row`.
  - `test_species_with_no_wild_source_has_no_rows`.
  - `test_same_table_as_default_and_area_counts_once` (build, below).
  - `test_evolves_from_finds_the_source` and `test_evolves_from_is_empty_for_a_base_species`.
  - `test_line_formats_range_and_single_level`.
  - `test_build_skips_test_maps_and_maps_without_encounters`, `test_build_orders_default_then_areas_and_drops_duplicates`.
  - `test_validator.gd`: `test_location_with_unknown_encounter_is_an_error` (`areas: ["nope"]` → an error naming `areas`).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.** Schema entry: `"locations": {"id": {"t": "id"}, "name": {"t": "string"}, "areas": {"t": "array", "min": 1, "of": {"t": "ref", "cat": "encounters"}}}`; `CATEGORIES["locations"] = "file"`; builder `"locations": LocationDef`. Hand-write `data/locations.json` as `{"schema": 1, "entries": [{"id": "route_01", "name": "Route 1", "areas": ["route_01_grass", "route_01_deep_grass"]}]}` (Task 3 regenerates it and must produce the same).
- [ ] **Step 4: Run `test_locations.gd`, `test_validator.gd`, `tests/data/test_testpack_removal.gd`, then `bash scripts/check.sh`'s data step; expect PASS.**

---

### Task 3: Generator tool and the stale-file check

**Files:**
- Create: `tools/build_locations.gd`, `tools/build_locations.tscn`
- Modify: `tools/check_maps.gd` (`describe` adds `"name": map.display_name`; compare after `MapRules.check`)
- Test: `tests/world/test_locations_file.gd` (new)

**Interfaces:**
- Consumes: `Locations.build(maps, db)` (Task 2), `CheckMaps.describe(map)` (existing static), `DataLoader.load_database`.
- Produces: `tools/build_locations.tscn` writes `res://data/locations.json` (tab-indented JSON like the other data files, trailing newline). `check_maps` prints an error and exits 1 when `Locations.build(maps, db)` differs from the loaded `locations` entries (compare as entry arrays).

- [ ] **Step 1: Write the failing test.** `test_locations_file.gd`: `test_shipped_locations_match_the_map_scenes` opens each non-`_` scene in `GameMap.MAPS_DIR` via `load(...).instantiate()` and `CheckMaps.describe`, calls `Locations.build(maps, DataRegistry.db)` and asserts its `entries` equal the real database's `locations` entries (id, name, areas) in order. `test_a_changed_scene_makes_the_file_stale` mutates the described `route_01` default encounter to another table id and asserts the built entries then differ from the database's.
- [ ] **Step 2: Run; expect FAIL** (`describe` has no `name`).
- [ ] **Step 3: Implement** the `name` key, the generator (`_ready`: load the database from `res://data`, describe every map scene, build, write the file, print "Wrote res://data/locations.json", quit 0), and the `check_maps` comparison with the message `data/locations.json is out of date: run tools/build_locations.tscn`. Run the generator once (`--headless --path . res://tools/build_locations.tscn`) and confirm it leaves the hand-written file unchanged (`git diff --stat data/locations.json` shows no change beyond formatting; if only formatting differs, keep the generated form).
- [ ] **Step 4: Run `test_locations_file.gd` and `check_maps` (`bash scripts/check.sh`'s Maps step); expect PASS.**

---

### Task 4: Silhouette sprite, `CodexPreview`, `CodexScreen`, pause menu entry

**Files:**
- Create: `game/progress/codex_preview.gd`, `game/progress/codex_screen.gd`
- Modify: `game/ui/creature_sprite_slot.gd` (silhouette), `game/overworld/ui/pause_menu.gd` (Codex row and `_codex()`)
- Test: `tests/game/test_creature_sprite_slot.gd`, `tests/game/test_codex_preview.gd` (new), `tests/world/test_codex_screen.gd` (new), `tests/world/test_pause_menu.gd`

**Interfaces:**
- Consumes: `Codex.order`, `Codex.number_text`, `Codex.status`, `Codex.seen_count`, `Codex.caught_count` (7a and Task 1); `ProgressScreen` (`set_side`, `use_game`, `menu`, `_title`, `_body`, `info_panel`, `menu_area`); `ScreenFit.problems`.
- Produces:
  - `CreatureSpriteSlot.configure_unknown(size: int = 48) -> void` (dark silhouette circle with "?", no type colours) and a `silhouette: bool` flag the draw respects.
  - `CodexPreview` (`VBoxContainer`): `show_entry(db: Database, save: SaveGame, species: String)`, `show_empty()`, `name_text() -> String`, `status_text() -> String`, `is_silhouette() -> bool`. Caught: sprite, `"#001 Name"`, "Caught"; seen: same with "Seen, not caught yet"; unseen: silhouette, `"#003 ???"`, "Not seen yet".
  - `CodexScreen.run(parent: Node, save: SaveGame = null, db: Database = null) -> void` (awaits until closed); `CodexScreen.row_label(db, save, species) -> String` (`"#001 Name ●"` caught, `"#002 Name ○"` seen, `"#003 ???"` unseen); `CodexScreen.header_text(db, save) -> String` (`"Seen 3 / 8 · Caught 2 / 8"`, total = `db.count("creatures")`).
  - Screen layout: title "Codex", body = header text, one-column menu with `menu.button_width = 306` (the Summary screen's `COLUMN_WIDTH`, so the left preview pane fits beside it), a final "Back" row (value `""`). Rows carry `"hint": species`; `menu.hovered` updates the preview; `"focus": true` on the last activated row keeps the position after the detail page closes. Activating an unseen row does nothing. Opening the detail page for a seen row is wired in Task 5; until then activating a seen row also does nothing.
  - `PauseMenu`: a `{"label": "Codex", "value": "codex"}` row between Bag and Save; `match` arm `"codex": await _codex()`; `_codex()` runs `CodexScreen.run(world)`-style via the same `world` the party uses (`await CodexScreen.run(_world_node)`; follow `_party`).

- [ ] **Step 1: Write the failing tests**
  - `test_creature_sprite_slot.gd`: `test_unknown_slot_is_a_silhouette_with_the_minimum_size` (`configure_unknown(64)` → `silhouette` true, `custom_minimum_size == Vector2(64, 64)`).
  - `test_codex_preview.gd`: `test_unseen_shows_a_silhouette_and_no_name` (name text contains `???` and not the species name; `is_silhouette()`), `test_seen_shows_name_and_status`, `test_caught_shows_caught`, `test_show_empty_clears`.
  - `test_codex_screen.gd` (uses `WorldTest.open(self, "test_b", "middle")` and real `DataRegistry.db`): `test_row_labels_by_status`, `test_header_counts`, `test_all_rows_are_unknown_on_a_fresh_game` (every non-Back label ends `???` and has no species name), `test_unseen_row_does_nothing` (pick it; the screen is still the Codex screen and no detail page exists), `test_hover_updates_the_preview` (focus the second row; the preview's name text matches), `test_list_fits_the_screen` (`ScreenFit.problems(screen)` is empty with every species seen), `test_species_without_dex_sort_last` (add a creature without `dex` to the in-memory database and mark it seen; its row is last before Back), `test_back_closes`.
  - `test_pause_menu.gd`: `test_codex_row_opens_the_codex_and_back_returns` (`_pick("Codex")`, then the Codex screen exists; pick "Back"; the pause menu is open again).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** per the Interfaces. The silhouette colour is a fixed dark grey (`Color("2a2f3c")`) with a muted "?" using the placeholder font path; the existing `_draw` branches on `silhouette`.
- [ ] **Step 4: Run the four suites; expect PASS.**

---

### Task 5: `CodexDetailPage` and wiring

**Files:**
- Create: `game/progress/codex_detail_page.gd`
- Modify: `game/progress/codex_screen.gd` (open the page on a seen row)
- Test: `tests/world/test_codex_detail_page.gd` (new), `tests/world/test_codex_screen.gd`

**Interfaces:**
- Consumes: `Locations.for_species`, `Locations.line`, `Locations.evolves_from` (Task 2); `Codex.status`, `Codex.number_text`; `ProgressScreen`; `CreatureSpriteSlot`; `TypeColors`.
- Produces:
  - `CodexDetailPage.MAX_LOCATION_LINES := 6`.
  - `CodexDetailPage.body_text(db: Database, save: SaveGame, species: String) -> String`: the description (or "No description yet."), a blank line, `Where to find it:` and one `- ` line per location (`Locations.line`), capped at `MAX_LOCATION_LINES` with a final `- +N more places`; with no rows: `Evolves from X` (X's name) when `Locations.evolves_from` is non-empty and `Codex.caught(save, X)`, else `No wild habitat known`; a seen-but-not-caught species ends with a line `Not caught yet`.
  - `CodexDetailPage.run(parent: Node, species: String, save: SaveGame = null, db: Database = null) -> void` (awaits until Back): title `"#001 Name"`, body = `body_text`, a large (128) `CreatureSpriteSlot` and the type names on the left (`set_side`), a single "Back" menu row. Refuses (returns at once) for an unseen species.

- [ ] **Step 1: Write the failing tests**
  - `body_text` on a `FixtureDB` database extended with a `locations` entry and encounter tables (as in Task 2's suite): `test_body_lists_each_location`, `test_body_uses_the_description_or_the_fallback`, `test_body_caps_long_location_lists` (8 tables → 6 lines plus `+2 more places`), `test_evolves_from_shows_only_when_the_source_is_caught` (both cases), `test_no_source_says_no_wild_habitat_known`, `test_not_caught_note_only_when_seen_not_caught`.
  - `test_codex_detail_page.gd` (open world): `test_page_shows_sprite_title_and_back`, `test_unseen_species_opens_nothing`, `test_page_fits_the_screen` (`ScreenFit.problems` empty for the species with the most locations and the longest description in the shipped data, and for a made-up species with a 400-character description and 8 locations), `test_back_returns_to_the_list_on_the_same_row`.
  - `test_codex_screen.gd`: `test_activating_a_seen_row_opens_its_page`.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** per the Interfaces and wire `CodexScreen` to call `CodexDetailPage.run` for rows whose status is not `unseen`.
- [ ] **Step 4: Run the suites; expect PASS.**

---

### Task 6: Compendium, docs, handoff

**Files:**
- Modify: `tools/compendium_builder.gd` (a `- **Found:**` line per creature), `documentation/compendium.md` (regenerated), `.superpowers/HANDOFF.md`
- Create: `documentation/codex.md`
- Test: `tests/data/test_compendium.gd` if it exists, else `tests/data/test_codex_data.gd`

**Interfaces:**
- Consumes: `Locations.for_species`, `Locations.line`, `Locations.evolves_from`.

- [ ] **Step 1: Write the failing test:** `test_compendium_lists_where_each_creature_is_found` builds the compendium text (follow how the existing compendium test calls the builder, or `CompendiumBuilder` directly) and asserts it contains `Found:` followed by the real `Locations.line` text for a species found on Route 1, and `Found: —` style fallback text (`Not found in the wild`) for a species with no rows.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** the `Found:` bullet right after the `Grows from` / `Grows into` bullets: the location lines joined with `; `, else `Not found in the wild`. Write `documentation/codex.md`: the `dex` rule, `locations.json` and how it is generated and checked, the two screens, the reveal rule, and what a new species needs to appear (a `dex`, a `description`, an encounter table on a map, then `tools/build_locations.tscn`). Update `.superpowers/HANDOFF.md`: add M7b to what is done and in the working tree (branch `milestone/M7b`), mark 7c as next, and keep the standing rules unchanged.
- [ ] **Step 4: Run the suite; run `bash scripts/check.sh` (regenerates the compendium); expect "All checks passed."**

---

### Task 7: Tour and final check

**Files:**
- Create: `.claude/skills/run-godot-monster-catching-game/tours/codex.gd`
- Modify: `.claude/skills/run-godot-monster-catching-game/driver.gd` (register `--mode=codex` in the mode list and the doc comment), `.claude/skills/run-godot-monster-catching-game/SKILL.md` (list the mode)

**Interfaces:**
- Consumes: the `bag.gd` tour as the pattern (`d.key`, `d.pick_menu`, `d._frames`, `d.shot`, `d.expect`).

- [ ] **Step 1: Write the tour.** New game; mark one species caught, one seen and leave the rest unseen via `Codex.mark_caught` / `mark_seen` on `gs.current`; Menu → Codex; screenshot the list; Down through a caught, a seen and an unseen row (preview follows); open the caught species' page and screenshot; Back; open the seen species' page and screenshot; try the unseen row (nothing opens); close back to the pause menu. `d.expect` the row labels and the page title text at each step.
- [ ] **Step 2: Run it:** `"$GODOT" --headless`-free (the tour needs a window): `Godot ... --path . --fixed-fps 60 --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=codex`. Expect every `expect` to pass; read the screenshots and confirm text is not cut off or overlapping.
- [ ] **Step 3: Run `bash scripts/check.sh`; expect "All checks passed."** Report the test-case count.
- [ ] **Step 4: Give the user the commit message** (not committed by you):
```
Add Codex screens with species pages and where-to-find data (M7)
- Codex list on the pause menu with seen and caught marks, a preview pane and numbered species (new `dex` field)
- Species detail page with sprite, description, and where to find it from a generated locations file
- Locations are built from the map scenes by tools/build_locations and checked by check_maps; compendium lists where each creature is found

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
```
