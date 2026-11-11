# M7c Achievements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An achievements framework: a data category, four criteria kinds, an evaluator that reacts to tracked changes without costing frames, an Achievements pause-menu screen, placeholder icons, a debug page and docs.

**Architecture:** Every tracked change (counter, Codex, story flag, creature level/Bond/membership) pushes a key into a static `AchievementWatch` set. The `AchievementService` autoload drains the set once per frame and checks only the locked achievements that watch those keys, through a key-to-ids index built from the data. Criteria are small classes behind a registry; evaluation (`Achievements`) is pure. `AchievementsScreen` is a `ProgressScreen` with a left preview, like the Codex.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4 suites in `tests/`.

**Spec:** `documentation/specs/2026-11-11-m7c-achievements-design.md` (parent: `2026-11-11-m7-collection-achievements-design.md`; data from `2026-11-11-m7a-tracking-design.md`; screen pattern from `2026-11-11-m7b-codex-screens-design.md`)

## Adjustments to the spec (decided while planning; the user reviews these with the plan)
1. **No target cache.** The spec's "next unmet target" fast path is not built: the key index already limits a step to the achievements that watch `counter:steps`, and checking one is a single integer compare. A diagnostic `AchievementService.checks` counts defs checked so a test can pin this.
2. **Nothing is gated at the push site.** `core/` cannot see `GameState`, so `AchievementWatch.push` always records; the service drops the keys when no game is loaded. (The spec said nothing is pushed without a game.)
3. **Full pass = the key `AchievementWatch.ALL`** (`"*"`). The service pushes it when `GameState.current` changes (new game, load) and the debug page pushes it after a reset. It checks every locked achievement once.
4. **`creature` pushes come from the sources**, not from `apply_results`: `Bond.change` (when Bond actually changes), `Progression.award_xp` (on a level-up), `GrowScreen.record_growth`, `BattleLauncher.add_to_party`.
5. **Values the spec left to the plan:** `close_friends` is Bond 80 (the scale is -100..100); the hidden achievement is the `quick_draw_won` story flag, "Quick on the Draw".
6. **Debug unlock goes through the service** (`AchievementService.unlock(id)`), so the signal fires as in play.

## Global Constraints
- **Never `git commit`, `git add`, stash, or switch/create branches.** The user commits. The last task gives the commit message: title ends `(M7)`, then a bullet list, then the co-author line.
- Do not run two Godot or test processes at once (shared save files).
- Run one suite: `"/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<dir>/<file>.gd --ignoreHeadlessMode -c`. Full check: `bash scripts/check.sh` must end "All checks passed."
- Tours need `--fixed-fps 60` before `--script`; the mode goes after `--` (see the skill's `SKILL.md`).
- New `.gd` files get a `.uid` file from Godot on the next run; leave them in the tree.
- Names are exact: category `achievements` (folder `data/achievements/`), `AchievementDef`, `AchievementWatch`, `Criterion`, `CounterCriterion`, `CodexCriterion`, `FlagCriterion`, `CreatureCriterion`, `Criteria` (all in `core/achievements/` and `core/achievements/criteria/`), `Achievements`, autoload `AchievementService` (`game/autoload/achievement_service.gd`), `AchievementIconSlot` (`game/ui/`), `AchievementPreview`, `AchievementsScreen` (`game/progress/`), `DebugCollectionPage` (`game/debug/pages/`), `SaveGame.achievements`, save schema 8.
- Watch keys are exact: `counter:<id>`, `codex`, `flag:<id>`, `creature`, and `AchievementWatch.ALL` (`"*"`).
- Achievement ids starting `tp_` are test content: never listed on the screen or in the counts, but evaluated like the rest.
- Hidden rule: a locked `hidden` achievement shows only `???`: no name, description, kind icon or progress anywhere (list, preview).
- Files keep their existing line endings; edit with tools that preserve them.

## Review Focus
1. An idle frame (no keys) evaluates nothing, and one step evaluates only the achievements that watch `counter:steps` (Task 5).
2. An achievement unlocks exactly once, however many keys hit it in one frame or after a reset and re-earn (Task 5).
3. A hidden locked achievement leaks nothing in the list or preview; once unlocked it shows normally (Task 6).
4. An old save that already earned achievements unlocks them on load; a save listing an achievement id that no longer exists loads and does not count (Tasks 4, 5).
5. A `codex` achievement counts only species in the Codex list (no test content, no removed species), as the 7b header does (Task 2).
6. A malformed `achievements` value in a save (wrong types) loads without crashing (Task 4).

---

### Task 1: `AchievementWatch` and the push points

**Files:**
- Create: `core/achievements/achievement_watch.gd`
- Modify: `core/progress/counters.gd`, `core/progress/codex.gd`, `core/story/story_state.gd`, `core/progress/bond.gd`, `core/progress/progression.gd`, `game/progress/grow_screen.gd`, `game/battle/battle_launcher.gd`
- Test: `tests/achievements/test_achievement_watch.gd` (new), `tests/achievements/test_watch_pushes.gd` (new)

**Interfaces:**
- Produces: `AchievementWatch` (static): `const ALL := "*"`, `const CODEX := "codex"`, `const CREATURE := "creature"`; `static func counter_key(id: String) -> String` (`"counter:" + id`); `static func flag_key(id: String) -> String` (`"flag:" + id`); `static func push(key: String) -> void`; `static func drain() -> PackedStringArray` (returns the keys and empties the set); `static func is_empty() -> bool`; `static func clear() -> void`.

- [ ] **Step 1: Write the failing tests.**
  - `test_achievement_watch.gd`: `test_push_then_drain_returns_the_keys_and_empties` (push `"codex"` and `"creature"`, drain has both, `is_empty()` afterwards); `test_pushing_the_same_key_twice_keeps_one` (drain size 1); `test_key_helpers` (`counter_key("steps") == "counter:steps"`, `flag_key("a") == "flag:a"`). `before_test` calls `AchievementWatch.clear()`.
  - `test_watch_pushes.gd` (each test clears first, uses `SaveGame.new_game("T", 0, RandomNumberGenerator.new())` and `FixtureDB.build()`): `Counters.add(save, "steps")` pushes `counter:steps`; a refused unknown counter pushes nothing; `Codex.mark_seen` pushes `codex` when it changes and nothing on a repeat; same for `mark_caught`; `save.story.set_flag("f")` pushes `flag:f` and a repeat (already set) pushes nothing, clearing a set flag pushes `flag:f`; `Bond.change(db, c, "battle_won")` pushes `creature` when Bond changes and nothing when `delta` is 0 or Bond is already clamped; `Progression.award_xp` pushes `creature` when it levels up and not when it only adds XP; `BattleLauncher.add_to_party` pushes `creature` (and `codex`); `GrowScreen.record_growth(save, "x")` pushes `creature`, `codex` and `counter:creatures_evolved`.
- [ ] **Step 2: Run both suites; expect FAIL** (`AchievementWatch` not defined).
- [ ] **Step 3: Implement.** `AchievementWatch` keeps one static `Dictionary` used as a set. Add the pushes: `Counters.add` after `add_count` succeeds; `Codex.mark_seen`/`mark_caught` only on the branches that return true; `StoryState.set_flag` only when the stored value changes; `Bond.change` only when `c.bond - before != 0`; `Progression.award_xp` once after the loop when the level rose; `GrowScreen.record_growth` needs no extra code beyond its `Codex`/`Counters` calls but must push `creature` itself; `BattleLauncher.add_to_party` pushes `creature` at the top (after `Codex.mark_caught`).
- [ ] **Step 4: Run both suites plus `tests/progress/test_codex.gd`, `test_counters.gd`, `test_training_bond.gd`, `test_progression.gd`; expect PASS.**

---

### Task 2: Criteria classes and registry

**Files:**
- Create: `core/achievements/criteria/criterion.gd`, `counter_criterion.gd`, `codex_criterion.gd`, `flag_criterion.gd`, `creature_criterion.gd`, `criteria.gd`
- Test: `tests/achievements/test_criteria.gd` (new)

**Interfaces:**
- Produces: `Criterion` (base, `RefCounted`): `func kind() -> String`; `func watches(c: Dictionary) -> PackedStringArray`; `func progress(db: Database, save: SaveGame, c: Dictionary) -> Dictionary` returning `{"current": int, "target": int}` with `current` clamped to `0..target` (met when `current >= target`); `func problem(c: Dictionary) -> String` (cross-field errors, `""` when fine). `Criteria` (static): `static func for_kind(kind: String) -> Criterion` (null when unknown), `static func kinds() -> PackedStringArray`. A criterion dictionary is `{"kind": ..., ...}` exactly as in the JSON.
- Kinds: `counter` `{stat, target}` (value `Counters.value(save, stat)`, watches `counter:<stat>`); `codex` `{mode: "seen"|"caught"|"species", target?, species?}` (counts species in `Codex.order(db)` only; `species` mode is target 1, current 1 when `Codex.caught`; watches `codex`; `problem`: `species` mode needs `species`, the others need `target`); `flag` `{flag}` (target 1, current 1 when `save.story.flag`; watches `flag:<flag>`); `creature` `{what: "level"|"bond"|"evolved", target}` (highest level or Bond among `save.party + BoxStorage.all_creatures(save)`, 0 when none; `evolved` reads `creatures_evolved`; watches `creature`, and `counter:creatures_evolved` for `evolved`).

- [ ] **Step 1: Write the failing tests** (`FixtureDB.build()`, a `SaveGame.new_game`, creatures from `CreatureInstance.create`):
  - counter: progress at 0, mid, exactly the target (`current == target`) and above it (`current` clamped to `target`); watches `["counter:steps"]`.
  - codex `seen`/`caught`: counts only species in `Codex.order(db)` (mark a `tp_` id and an unknown id seen: neither counts); `species` mode flips to 1/1 when that species is caught, not when only seen.
  - codex `problem`: `species` without `species` and `seen` without `target` each return a message; valid ones return `""`.
  - flag: 0/1 then 1/1 after `set_flag`; watches `flag:<id>`.
  - creature: `level` uses the highest level across party and box; `bond` with a negative Bond shows `current == 0` and is not met; `evolved` follows the `creatures_evolved` counter; no creatures gives 0.
  - `Criteria.for_kind("nope")` is null; `kinds()` lists all four.
- [ ] **Step 2: Run the suite; expect FAIL.**
- [ ] **Step 3: Implement** the base class (methods return defaults / push no error) and the four subclasses and `Criteria` (a constant `KINDS` mapping kind to script, one cached instance each).
- [ ] **Step 4: Run the suite; expect PASS.**

---

### Task 3: The `achievements` data category

**Files:**
- Create: `core/data/defs/achievement_def.gd`, `data/achievements/achievements.json`
- Modify: `core/data/schemas.gd`, `core/data/validator.gd`, `core/data/database.gd`
- Test: `tests/data/test_achievements_data.gd` (new), `tests/data/test_validator.gd`

**Interfaces:**
- Consumes: `Criteria.for_kind`, `Criterion.problem` (Task 2).
- Produces: `AchievementDef`: `id: String`, `name: String`, `description: String`, `hidden: bool`, `criterion: Dictionary`, `static func from_dict(d: Dictionary) -> AchievementDef`. `Database.achievement(id) -> AchievementDef`; builder `"achievements": AchievementDef`. `DataSchemas.CATEGORIES["achievements"] = "folder"`; `DataSchemas.ENTRY["achievements"]` = `{id: id, name: string, description: string, hidden: bool opt, criterion: {"t": "criterion"}}`; `DataSchemas.CRITERIA` (per-kind field rules, like `EFFECT_OPS`): `counter {stat: enum Counters.BUILT_IN, target: int min 1}`, `codex {mode: enum [seen, caught, species], target: int opt min 1, species: ref creatures opt}`, `flag {flag: id}`, `creature {what: enum [level, bond, evolved], target: int min 1}`. The validator gains a `"criterion"` rule type (`_check_criterion`): an object with a known `kind`, fields checked against `CRITERIA[kind]` plus `kind`, then `Criteria.for_kind(kind).problem(c)`.

- [ ] **Step 1: Write the failing tests.**
  - `test_validator.gd` (use the file's existing way of adding an entry to a base raw set): an unknown `kind`; a `counter` with a `stat` outside `Counters.BUILT_IN`; `target: 0`; a `codex` `seen` target above the number of non-`tp_` species ("more than the N species"); `species` mode without `species`; a `species` naming an unknown creature; a duplicate id; `hidden: "yes"`; a valid entry of each kind produces no errors.
  - `test_achievements_data.gd`: loads `DataLoader.load_database("res://data", "res://dialogue")` ok; has the 11 starter ids; every kind is used at least once; exactly one is `hidden` and it is `quick_draw_won`; no `tp_` ids; every shipped `codex` target is at most the species count.
- [ ] **Step 2: Run both suites; expect FAIL.**
- [ ] **Step 3: Implement** the schema, validator, def, builder and accessor. `data/achievements/achievements.json` (`{"schema": 1, "entries": [...]}`, in this order): `first_steps` "First Steps" (counter `steps` 500, "Walk 500 steps."), `first_victory` "First Victory" (counter `battles_won` 1), `tamer_trouncer` "Tamer Trouncer" (counter `tamers_defeated` 1), `first_catch` "First Catch" (counter `creatures_caught` 1), `field_notes` "Field Notes" (codex `seen` 4), `collector` "Collector" (codex `caught` 8, "Catch every species."), `first_evolution` "First Evolution" (counter `creatures_evolved` 1... use the `creature` kind `evolved` 1 so that kind is exercised), `rising_star` "Rising Star" (creature `level` 20), `close_friends` "Close Friends" (creature `bond` 80), `big_spender` "Big Spender" (counter `money_earned` 1000), `quick_on_the_draw` "Quick on the Draw" (flag `quick_draw_won`, `hidden: true`; the test names this id). Write each `description` as one short sentence.
- [ ] **Step 4: Run both suites plus `tests/data/test_data_loader.gd` and `tests/data/test_testpack_removal.gd`; expect PASS.**

---

### Task 4: The `Achievements` evaluator and save schema 8

**Files:**
- Create: `core/achievements/achievements.gd`
- Modify: `core/save/save_game.gd`, `core/save/save_store.gd`
- Test: `tests/achievements/test_achievements.gd` (new), `tests/save/test_achievements_load.gd` (new, modelled on `tests/save/test_codex_load.gd`)

**Interfaces:**
- Consumes: `Database.achievement`, `Criteria`, `AchievementWatch.ALL` (Tasks 1-3).
- Produces: `SaveGame.achievements: Dictionary` (id to unlock time, Unix seconds `int`), `SaveGame.SCHEMA = 8`, `SaveStore._v7_to_v8` registered as `7: _v7_to_v8`. `Achievements` (static): `listed(db) -> PackedStringArray` (ids in table order, no `tp_`); `is_unlocked(save, id) -> bool`; `unlock_count(db, save) -> int` (over `listed` only); `progress(db, save, id) -> Dictionary` (`{current, target}`); `is_met(db, save, id) -> bool`; `watch_index(db) -> Dictionary` (key to `PackedStringArray` of ids); `check(db, save, ids: Array) -> PackedStringArray` (the ids among `ids` that are locked and met, no writes); `evaluate(db, save, keys: PackedStringArray) -> PackedStringArray` (builds the index, takes the union of ids for `keys`, or every id when `keys` contains `AchievementWatch.ALL` or is empty, and returns `check`); `unlock(save, id: String, unix: int) -> void`; `reset(save, id: String = "") -> void` (one id, or all when empty).

- [ ] **Step 1: Write the failing tests.**
  - `test_achievements.gd` (`FixtureDB` plus its own achievement entries added through `FixtureDB.raw()`, or the shipped db via `DataRegistry.db`): `listed` excludes `tp_`; `evaluate` with `["counter:steps"]` returns only the steps achievement when met and ignores a met achievement that watches another key; empty keys and `ALL` check everything; an unlocked id is never returned again; `unlock_count` counts listed ids only and ignores a save entry for an id not in the data; `unlock`/`reset` write and clear `save.achievements` (reset all vs one); `watch_index` maps `counter:steps` to the right ids and `codex` to every codex achievement.
  - `test_achievements_load.gd`: `to_dict`/`from_dict` round-trip `achievements`; a v7 dictionary migrates to schema 8 with `achievements == {}`; `from_dict` with `achievements` holding junk (`"x": "soon"`, `"y": null`, a non-dictionary) loads without error, keeping only entries whose value is a number (stored as `int`).
- [ ] **Step 2: Run both suites; expect FAIL.**
- [ ] **Step 3: Implement.** `SaveGame`: the field, `SCHEMA := 8`, `to_dict` (`achievements.duplicate()`), `from_dict` (numbers only). `SaveStore._v7_to_v8` sets `out["achievements"] = {}` and `out["schema"] = 8`; update the migrations table and any test that pins schema 7 (`grep -rn "schema.*7\|SCHEMA" tests`). `Achievements` as above, with `check` skipping ids unknown to the database.
- [ ] **Step 4: Run both suites plus all of `tests/save/`; expect PASS.**

---

### Task 5: `AchievementService`

**Files:**
- Create: `game/autoload/achievement_service.gd`
- Modify: `project.godot` (autoload after `Cutscene`, before `DebugMenu`)
- Test: `tests/achievements/test_achievement_service.gd` (new)

**Interfaces:**
- Consumes: `AchievementWatch`, `Achievements` (Tasks 1, 4); `GameState.current`, `DataRegistry.db`.
- Produces: autoload `AchievementService`: `signal unlocked(id: String)`; `var checks: int` (defs checked so far, a diagnostic); `func flush() -> PackedStringArray` (drains the keys and returns the ids unlocked by this call; `_process` calls it every frame); `func unlock(id: String) -> bool` (writes `save.achievements[id]` with `Time.get_unix_time_from_system()` as an int, emits `unlocked`, logs `Log.info(Log.SAVE, "Achievement unlocked", {"id": id})`, returns false if already unlocked or no game).
- Behaviour of `flush`: when `GameState.current` is not the save last seen, remember it and push `AchievementWatch.ALL`. With no keys, return at once. With no game, drain and drop. Otherwise keep an index (rebuilt when `DataRegistry.db` is a different object) and gather the ids of the drained keys (all ids for `ALL`), call `Achievements.check` on them (adding to `checks` the number of ids passed), and `unlock` each result.

- [ ] **Step 1: Write the failing tests** (`before_test`: `GameState.current = SaveGame.new_game("T", 0, RandomNumberGenerator.new())`, `AchievementWatch.clear()`, then `AchievementService.flush()` to take the initial pass; `after_test`: `GameState.current = null`, clear the watch; the suite uses `monitor_signals(AchievementService)`):
  - a `battles_won` counter bump (`Counters.add`) then `flush()` unlocks `first_victory`: it is in `save.achievements`, `unlocked` was emitted once with that id.
  - flushing again, or pushing the same key again, does not emit again (exactly once).
  - several keys in one flush that meet the same achievement (push `counter:steps` three times and `ALL`) emit once.
  - an idle `flush()` leaves `checks` unchanged.
  - one `Counters.add(save, "steps")` (500 not reached) adds exactly the number of achievements watching `counter:steps` (one, `first_steps`) to `checks`; it does not check the rest.
  - the load pass: set `save.story.counters["battles_won"] = 5` directly (no push), assign a different `SaveGame` to `GameState.current`, `flush()`; `first_victory` unlocks.
  - with no game (`GameState.current = null`) a flush drops the keys and does not error, and a later game does not see them.
  - `unlock` on an already unlocked id returns false and emits nothing; `unlock` with no game returns false.
  - a reset id re-earns once and emits once more (reset via `Achievements.reset`, push `ALL`, flush).
- [ ] **Step 2: Run the suite; expect FAIL.**
- [ ] **Step 3: Implement** the autoload and add `AchievementService="*res://game/autoload/achievement_service.gd"` to `project.godot`.
- [ ] **Step 4: Run the suite; expect PASS.** Then run `tests/world/test_progress_flow.gd` and `tests/battle/test_battle_launcher*.gd` (whatever matches `tests/**/test_battle_launcher*`) to confirm nothing else saw the autoload.

---

### Task 6: Icon, preview, screen and pause-menu row

**Files:**
- Create: `game/ui/achievement_icon_slot.gd`, `game/progress/achievement_preview.gd`, `game/progress/achievements_screen.gd`
- Modify: `game/overworld/ui/pause_menu.gd`
- Test: `tests/game/test_achievement_icon_slot.gd` (new), `tests/world/test_achievements_screen.gd` (new), `tests/world/test_pause_menu.gd`

**Interfaces:**
- Consumes: `Achievements`, `Criteria`, `AchievementDef` (Tasks 2-4); `ProgressScreen` (`set_side`, `menu`, `menu_area`, `use_game`, `_title`, `_body`, `_loop` pattern as in `CodexScreen`).
- Produces: `AchievementIconSlot` (`Control`): `configure(kind: String, icon_size: int = 48, unlocked: bool = true)`, `fill_color() -> Color`, `letter() -> String`; one colour and letter per criterion kind (`counter`, `codex`, `flag`, `creature`, and `unknown` shown as `?`), a locked icon drawn greyed. `AchievementPreview` (`PanelContainer`, size `Vector2(300, 272)`): `show_entry(db, save, id)`, `show_empty()`, `name_text()`, `description_text()`, `status_text()`, `is_masked() -> bool`. `AchievementsScreen` (`ProgressScreen`): `static func run(parent: Node, save: SaveGame = null, db: Database = null) -> void`; `static func row_label(db, save, id) -> String` (`"Name ✓"` unlocked, `"Name 7 / 10"` locked with progress, `"???"` hidden and locked); `static func header_text(db, save) -> String` (`"Unlocked 3 / 11"`, listed ones only); `preview() -> AchievementPreview`. The preview shows a large icon, the name, the description (clipped to 180 characters with `…`) and `"Unlocked 2026-11-11"` (`Time.get_date_string_from_unix_time`) or `"Progress 7 / 10"`; a hidden locked entry shows the `unknown` icon, `???`, "Hidden achievement." and no progress. `PauseMenu` gains an `Achievements` row (`"achievements"`) after Codex that awaits `AchievementsScreen.run(world)`; update its header comment.

- [ ] **Step 1: Write the failing tests.**
  - `test_achievement_icon_slot.gd`: each kind has a distinct colour and its letter; an unknown kind gives `?`; a locked slot's colour differs from the unlocked one.
  - `test_achievements_screen.gd` (like `test_codex_screen.gd`: `WorldTest.open(self, "test_b", "middle")`, `AchievementsScreen.run(world)`): `row_label` for locked with progress (`"First Steps 0 / 500"` after `AchievementService.flush()` with nothing earned), for unlocked (`"First Catch ✓"` after `AchievementService.unlock("first_catch")`), and for hidden locked (`"???"`) versus hidden unlocked (its name); the header counts listed ones only (add a `tp_` achievement to `DataRegistry.db._tables["achievements"]` and unlock it: the count does not change; remove it in `after_test`); the row list is in file order and ends with `Back`; hovering a row (`menu.hovered.emit(id)`) updates the preview: description and `Progress` for a locked one, `Unlocked <date>` for an unlocked one, `is_masked()` and no name/description/progress text for a hidden locked one; `Back` closes the screen; the screen fits 640x360 (`ScreenFit.problems(s)` empty), including with a `tp_` achievement whose name and description are very long (clipped).
  - `test_pause_menu.gd`: the label list contains `Achievements`, and picking it opens an `AchievementsScreen`, and Back returns to the menu choosing.
- [ ] **Step 2: Run the three suites; expect FAIL.**
- [ ] **Step 3: Implement** the three classes (draw the icon like `ItemIconSlot`; build the screen like `CodexScreen`: a `_loop` that builds options with `row_label`, `value`/`hint` = id, no sub-page, the preview following `menu.hovered`, `menu.button_width = COLUMN_WIDTH` 306; no scroll-reset workaround is needed, see the M7b review) and the pause-menu row.
- [ ] **Step 4: Run the three suites; expect PASS.**

---

### Task 7: Debug Collection page

**Files:**
- Create: `game/debug/pages/debug_collection_page.gd`
- Modify: `game/debug/pages/debug_main_page.gd`
- Test: `tests/game/test_debug_collection.gd` (new)

**Interfaces:**
- Consumes: `Codex.mark_seen`/`mark_caught`, `Counters.add`, `Achievements.reset`, `AchievementService.unlock`, `AchievementWatch.push` (Tasks 1-5); `DebugPage` helpers (`menu.option_row`, `menu.spin_row`, `menu.show_page`).
- Produces: `DebugCollectionPage` (`DebugPage`): title "Collection"; controls: a species picker (`Codex.order` ids) with **Mark seen** / **Mark caught**; a counter picker (`Counters.BUILT_IN`) with an amount spin box and **Add**; an achievement picker (`Achievements.listed`) with **Unlock** / **Reset**; **Reset all**; **Back**. Public action methods, which the buttons call and the test calls directly: `mark_species(id: String, caught: bool) -> void`, `add_counter(id: String, n: int) -> void`, `unlock(id: String) -> bool`, `reset(id: String) -> void` (resets then pushes `AchievementWatch.ALL`), `reset_all() -> void`. `DebugMainPage` gets a **Collection...** button (enabled with a game loaded, like the party tools) opening the page.

- [ ] **Step 1: Write the failing tests** (a `GameState.current` new game; instantiate the page and call the methods directly): `mark_species("tidepup", true)` sets Codex caught and pushes `codex`; `mark_species(..., false)` marks seen only; `add_counter("steps", 10)` raises the counter and pushes `counter:steps`; `unlock("first_catch")` returns true, the id is in `save.achievements` and `AchievementService.unlocked` fired; `reset` clears one and pushes `ALL`; `reset_all` clears every entry. Also a smoke test that building the page into a `VBoxContainer` (with `menu = DebugMenu`) adds buttons without errors.
- [ ] **Step 2: Run the suite; expect FAIL.**
- [ ] **Step 3: Implement** the page and the main-page button.
- [ ] **Step 4: Run the suite plus `tests/game/test_debug_menu*.gd`; expect PASS.**

---

### Task 8: Compendium, docs, tour, closing checks

**Files:**
- Create: `documentation/achievements.md`, `.claude/skills/run-godot-monster-catching-game/tours/achievements.gd`
- Modify: `tools/compendium_builder.gd`, `tests/data/test_compendium.gd`, `documentation/compendium.md` (regenerated by `scripts/check.sh`), `documentation/tracking.md`, `.claude/skills/run-godot-monster-catching-game/driver.gd` and `SKILL.md` (register `--mode=achievements` in the same places as `codex`), `documentation/specs/2026-11-11-m7c-achievements-design.md` (Status: Implemented, with the adjustments above), `documentation/specs/2026-11-11-m7-collection-achievements-design.md` (status line), `.superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: everything above.
- Produces: an `Achievements` section in the compendium (the last entry of `CompendiumBuilder.SECTIONS`): a table `| Achievement | Id | Needs |` with every achievement (hidden ones included, marked "(hidden)"), `Needs` written from the criterion (for example "Walk 500 steps", from a one-line sentence built from kind, stat and target; keep it plain and deterministic).

- [ ] **Step 1: Write the failing tests.** `test_compendium.gd`: add `"Achievements"` to its own `SECTIONS` constant at the end (the order test then fails), and a test that the section lists every shipped achievement id once and marks the hidden one.
- [ ] **Step 2: Run `tests/data/test_compendium.gd`; expect FAIL.**
- [ ] **Step 3: Implement** the compendium section (the contents-table count already reads `db.count("achievements")`). Write `documentation/achievements.md`: the data shape, the four kinds and their watch keys, how evaluation works (the diagram in words: push, drain, index, check, unlock, signal), how to add an achievement (JSON only) and a criterion kind (one `Criterion` subclass, one `DataSchemas.CRITERIA` entry, one `Criteria.KINDS` line, and a push where the watched thing changes), the debug page, and the performance rule (anything that changes often must use a narrow key). Add a short "Achievement watch pushes" note to `tracking.md`. Write the tour `achievements.gd` (modelled on `tours/codex.gd`): new game, `Story.give_creature("tidepup", 5)` (earns First Catch after a frame), Menu, Achievements, check the header "Unlocked 1 / 11", the First Catch row ends `✓`, a locked row shows progress, the hidden row reads `???` and its preview is masked, every screen fits (`ScreenFit`), Back out; screenshots `ach01_…` to `ach03_…`. Update the spec statuses and the handoff (new section, commit title, what is next).
- [ ] **Step 4: Run `tests/data/test_compendium.gd`; expect PASS.** Then run the tour: `timeout 200 "$GODOT" --path . --fixed-fps 60 --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=achievements --out="$TMPDIR/ach_shots" 2>&1 | grep "\[driver\]"`; expect `ALL CHECKS PASSED`, and read the screenshots for clipping.
- [ ] **Step 5: Run `bash scripts/check.sh`; expect "All checks passed."** Then give the user this commit message (the user commits):

  ```
  Add achievements: data, criteria, event-driven unlocks and a screen (M7)
  - Achievements data category with counter, codex, flag and creature criteria and eleven starter entries
  - Tracked changes push watch keys; one service drains them per frame and checks only the achievements that watch them
  - Save schema 8 records unlock times; a load pass catches up old saves; unlocked(id) is the seam for a toast or Steam
  - Achievements pause-menu screen with placeholder icons, hidden entries, a debug Collection page and a compendium section

  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
  ```
