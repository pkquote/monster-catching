# M7a Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record which species the player has seen and caught (the Codex data) and eight lifetime counters, with save schema 7 and a backfill for old saves.

**Architecture:** Two small static core classes (`Codex`, `Counters`) over `SaveGame.codex` and the existing `story.counters`; hooks at the existing choke points (`apply_results`, `Story`, `GrowScreen`, `FieldItems`, `Player`); a schema 6→7 migration, with the backfill run in `GameState.load_from` (core migrations can't see the database).

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4 suites in `tests/`.

**Spec:** `documentation/specs/2026-11-11-m7a-tracking-design.md` (parent: `2026-11-11-m7-collection-achievements-design.md`)

## Global Constraints
- **Never `git commit`, `git add` or stash.** The user commits. Leave every change in the working tree. The last task gives the commit message, which ends its title with `(M7)`.
- Ignore the uncommitted `data/` reshuffle already in the tree (moves split per type); do not touch `data/moves/*`.
- Do not run two Godot or test processes at once (shared save files).
- Run one suite: `"/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<dir>/<file>.gd --ignoreHeadlessMode -c`. Full check: `bash scripts/check.sh` must end "All checks passed."
- Tours in this environment need `--fixed-fps 60` before `--script`. (No tour is needed in 7a: no screen changes.)
- Names are exact: class `Codex` (`core/progress/codex.gd`), class `Counters` (`core/progress/counters.gd`), save field `codex`, schema 7. Counter ids: `battles_fought`, `battles_won`, `tamers_defeated`, `creatures_caught`, `creatures_evolved`, `items_used`, `money_earned`, `steps`.
- Seen reuses `Battler.participated` (no new Battler field). `Counters.value`, not `get`.
- Exhibition battles track nothing; a fled battle is not "fought" and not "won"; shop sales are not `money_earned`.
- Files use CRLF or LF as they already do; edit with tools that preserve line endings.

## Review Focus
1. A foe that was never fielded (bench creature of a tamer) stays unseen after the battle (Task 3).
2. A fled battle: foes that were fielded are seen, but no `battles_fought`/`battles_won` (Task 3).
3. An old schema-6 save with a creature in a high box slot loads with that species caught (Task 2).
4. Hooks must be no-ops when no game is loaded (`GrowScreen.run`, `Player.step` run in tests with `GameState.current == null`) (Tasks 4–5).
5. A loaded-then-saved game keeps its Codex and counters (round trip) (Task 1).
6. `Counters.add` with an unknown id must not silently create a counter (Task 1).

---

### Task 1: `Codex`, `Counters`, save field and schema 7

**Files:**
- Create: `core/progress/codex.gd`, `core/progress/counters.gd`
- Modify: `core/save/save_game.gd` (`SCHEMA`, `codex`, `to_dict`, `from_dict`), `core/save/save_store.gd` (`migrations`, `_v6_to_v7`)
- Test: `tests/progress/test_codex.gd` (new), `tests/progress/test_counters.gd` (new), `tests/save/test_save_store.gd`

**Interfaces:**
- Produces: `Codex.mark_seen(save: SaveGame, species: String) -> bool`, `Codex.mark_caught(save, species) -> bool` (both true when the entry changed), `Codex.status(save, species) -> String` (`"unseen"|"seen"|"caught"`), `Codex.seen(save, species) -> bool`, `Codex.caught(save, species) -> bool`, `Codex.seen_count(save) -> int`, `Codex.caught_count(save) -> int`, `Codex.backfill(save) -> void` (marks every creature in `save.party` and `BoxStorage.all_creatures(save)` caught). `Counters.BUILT_IN: PackedStringArray` (the eight ids), `Counters.add(save, id: String, n := 1) -> bool`, `Counters.value(save, id) -> int`. `SaveGame.codex: Dictionary` (species id → `{"seen": bool, "caught": bool}`).

- [ ] **Step 1: Write failing tests.**
  - `test_codex.gd` (`SaveGame.new_game("Ana", 1000, rng)`; species ids are plain strings): `test_unseen_by_default` (`status == "unseen"`); `test_mark_seen_then_caught` (`mark_seen` returns true then false on repeat; status `seen`; `mark_caught` returns true, status `caught`, `seen` stays true; repeat returns false); `test_caught_implies_seen` (`mark_caught` on a fresh species gives `seen()` true); `test_counts` (two seen, one of them caught: `seen_count == 2`, `caught_count == 1`); `test_backfill_marks_party_and_every_box_slot` (party creature `blob`, a creature `fish` placed in the last slot of the last unlocked box via `save.storage[save.storage.size() - 1] = c`; after `backfill` both are `caught`, nothing else is); `test_backfill_keeps_existing_marks` (a species already seen but not in the party stays `seen`). Build creatures with `FixtureDB.make(db, "blob", 5)` with `db = FixtureDB.build()`.
  - `test_counters.gd`: `test_built_in_ids_are_the_eight` (exact set, unique); `test_add_and_value` (`add` returns true; `value` 0 before, `n` after; `add(..., 3)`); `test_unknown_id_is_rejected` (`add(save, "bogus")` returns false and `save.story.counters` has no `"bogus"`); `test_counters_share_the_story_store` (after `add(save, "battles_won")`, `save.story.count("battles_won") == 1`).
  - `test_save_store.gd`: `test_codex_round_trips` (set `codex` entries on a save, write with `store.write(...)`, `read`, same dictionary back); `test_schema_6_save_migrates_with_empty_codex` (write a save, rewrite its JSON file with `schema` 6 and the `codex` key removed, `read` ok, `save.codex.is_empty()`); `test_malformed_codex_entries_are_dropped` (a `codex` JSON value that is not a dictionary, and an entry that is not a dictionary, load as empty / skipped).
- [ ] **Step 2: Run the three suites; expect FAIL** (missing classes, `codex` property).
- [ ] **Step 3: Implement.** `Codex` and `Counters` are `RefCounted` static classes as above (`mark_*` create `{"seen": true, "caught": bool}`; `seen_count` counts entries with `seen`, `caught_count` entries with `caught`). `Counters.add` pushes an error via `push_error` and returns false for ids not in `BUILT_IN`, else `save.story.add_count(id, n)`; `value` is `save.story.count(id)`. `SaveGame`: `SCHEMA := 7`, `var codex: Dictionary = {}`, `to_dict` adds `"codex": codex.duplicate(true)`, `from_dict` copies only entries that are dictionaries, normalised to `{"seen": bool(e.get("seen", false)) or bool(e.get("caught", false)), "caught": bool(e.get("caught", false))}`. `SaveStore.migrations()` gets `6: _v6_to_v7` which sets `out["codex"] = {}` and `out["schema"] = 7`.
- [ ] **Step 4: Run the three suites plus `tests/save/test_save_store.gd` fully and `tests/progress/test_field_items.gd`; expect PASS.** If an existing test asserts the old schema number, update it to 7 and note it.

### Task 2: Load backfill and `Story` hooks

**Files:**
- Modify: `game/autoload/game_state.gd` (`load_from`), `game/autoload/story.gd` (`give_creature`, `give_money`)
- Test: `tests/story/test_story_api.gd`, `tests/save/test_codex_load.gd` (new)

**Interfaces:**
- Consumes: Task 1's `Codex.backfill`, `Codex.mark_caught`, `Counters.add`.
- Produces: `GameState.load_from` leaves `current.codex` backfilled; `Story.give_creature` marks the species caught and bumps `creatures_caught`; `Story.give_money(n)` bumps `money_earned` by `n` when `n > 0`.

- [ ] **Step 1: Write failing tests.**
  - `tests/save/test_codex_load.gd`: `test_old_save_loads_with_codex_backfilled`: build a `SaveGame` with a party creature (`tidepup` from `DataLoader.load_database("res://data").db`) and a `pebblet` in the last box slot, write it with a temp `SaveStore` (`create_temp_dir`), rewrite the file as schema 6 without `codex`, point `GameState.store` at that store, call `GameState.load_from(path)`; assert it returns `""`, `Codex.caught(GameState.current, "tidepup")` and `"pebblet"` are true and `Codex.caught_count == 2`. Restore `GameState.current = null` and the original store in `after_test` (copy how `tests/world` suites save and restore `GameState`).
  - `test_story_api.gd`: extend `test_give_creature_party_then_storage` or add `test_give_creature_marks_codex_and_counts` (`Story.give_creature("emberkit", 5, true)` then `Codex.status(GameState.current, "emberkit") == "caught"` and `Counters.value(GameState.current, "creatures_caught") == 1`); `test_give_money_counts_earned` (`Story.give_money(50)` adds 50 to `money_earned`; `Story.take_money` does not change it; `Story.give_money(0)` or a negative value does not either).
- [ ] **Step 2: Run both suites; expect FAIL.**
- [ ] **Step 3: Implement.** In `load_from`, after `current = r.save` and the per-creature loop, call `Codex.backfill(current)`. In `give_creature`, after `add_to_party`, call `Codex.mark_caught(_save(), species)` and `Counters.add(_save(), "creatures_caught")`. In `give_money`, `if n > 0: Counters.add(_save(), "money_earned", n)`.
- [ ] **Step 4: Run both suites plus `tests/story/` and `tests/log/test_log_coverage.gd`; expect PASS.**

### Task 3: `apply_results` hooks

**Files:**
- Modify: `game/battle/battle_launcher.gd` (`apply_results`; a private static `_items_consumed`)
- Test: `tests/game/test_battle_launcher.gd`

**Interfaces:**
- Consumes: `Codex.mark_seen`, `Codex.mark_caught`, `Counters.add`.

- [ ] **Step 1: Write failing tests** (extend the suite; it already has `db = FixtureDB.build()`, `_save()`; `FixtureDB.engine` is not needed, use `BattleLauncher.wild_setup` and `BattleEngine` as the existing tests do; for a tamer battle use the fixture tamer `t1` via `BattleLauncher.tamer_setup(db, s, "t1", 1)`):
  - `test_wild_win_marks_foe_seen_and_counts`: win a wild battle (player `blob` with `hit` vs a level 1 `fish`, loop `resolve_round` until over); after `apply_results`: `Codex.status(s, "fish") == "seen"`, `battles_fought == 1`, `battles_won == 1`, `tamers_defeated == 0`, `money_earned == 0`.
  - `test_capture_marks_caught_and_counts` (reuse the master_cage setup of `test_results_write_back_items_catches_and_money`): `Codex.status(s, "fish") == "caught"`, `creatures_caught == 1`, `battles_won == 1`, `items_used == 1`.
  - `test_tamer_win_counts_tamer_and_money`: win vs tamer `t1` (reward 1): `tamers_defeated == 1`, `money_earned == 1`, `battles_won == 1`.
  - `test_bench_foe_never_fielded_stays_unseen`: tamer `t1` fields 1 of its 2 creatures (`blob` first, `fish` on the bench); player wins before the bench fish enters (give the player a strong level-50 creature so the first foe falls and the battle ends only when both fall: so instead assert on a battle that is fled early, see next); use a 1-field battle that the player **flees** after round 1 so only the first foe is fielded: `blob` is seen, `fish` is `unseen`.
  - `test_flee_marks_fielded_foes_but_is_not_fought_or_won`: flee a wild battle with `BattleAction.flee(actor)` (check the factory name in `core/battle/battle_action.gd`; the engine must report `res.reason == "fled"`; if fleeing can fail, use a seed or loop until fled): `Codex.status` of the fielded foe is `seen`, `battles_fought == 0`, `battles_won == 0`.
  - `test_loss_counts_fought_not_won`: reuse `test_loss_no_longer_heals`'s setup: `battles_fought == 1`, `battles_won == 0`.
  - `test_items_used_counts_battle_items`: bag `{"potion": 3}`, use `potion` twice in battle (`BattleAction.use_item`), `items_used == 2` after `apply_results`.
  - In `tests/game/test_exhibition.gd` add `test_exhibition_changes_no_codex_or_counters`: after the suite's existing exhibition flow completes (copy an existing test's pattern), the save's `codex` is empty and every `Counters.value(save, id)` is 0.
- [ ] **Step 2: Run the suites; expect FAIL.**
- [ ] **Step 3: Implement in `apply_results`.** At the top take `var bag_before := save.inventory.duplicate()`. After `engine.commit(0)`/`engine.result()` and before the captured loop: for every battler `b` in `engine.sides[1].battlers` with `b.participated`, `Codex.mark_seen(save, b.creature.species)`. In the captured loop add `Codex.mark_caught(save, c.species)` and `Counters.add(save, "creatures_caught")`. After `summary.outcome` is final: `battles_fought` unless `FLED`; `battles_won` when `WON` or `CAPTURED`; when `WON` with a `tamer_id`, `tamers_defeated`, and `money_earned` by `summary.money` when `> 0`. `items_used` by `_items_consumed(bag_before, save.inventory) -> int` (sum of `before[id] - after.get(id, 0)` where positive).
- [ ] **Step 4: Run `test_battle_launcher.gd`, `test_exhibition.gd`, `tests/log/test_log_coverage.gd`, `tests/world/test_progress_flow.gd`; expect PASS.**

### Task 4: Evolution and bag-use hooks

**Files:**
- Modify: `game/progress/grow_screen.gd` (`_ask`), `core/progress/field_items.gd` (`use`)
- Test: `tests/world/test_progress_flow.gd`, `tests/progress/test_field_items.gd`

**Interfaces:**
- Consumes: `Codex.mark_caught`, `Counters.add`.

- [ ] **Step 1: Write failing tests.**
  - `test_progress_flow.gd`: extend `test_grow_now_changes_species` or add `test_growing_marks_the_new_species_caught_and_counts`: after "Grow now" and OK, `Codex.status(GameState.current, "torrentusk") == "caught"` and `Counters.value(GameState.current, "creatures_evolved") == 1`; add `test_declining_growth_changes_nothing` (answer "Not yet": `torrentusk` stays `unseen`, counter 0).
  - `test_field_items.gd`: `test_successful_use_counts_an_item` (`FieldItems.use(db, save, "salve", c)` with `c.hp = 1`: `Counters.value(save, "items_used") == 1`); `test_failed_use_counts_nothing` (full-HP creature, `no_effect`: counter 0); `test_reset_seed_counts` (spent seed: counter 1).
  - A no-game guard test: `test_grow_screen_without_a_loaded_game_does_not_fail` — with `GameState.current == null`, `GrowScreen.run(parent, c, db)` for a ready creature and picking "Grow now" completes without error (follow `tests/world/test_summary_screen.gd`/`test_progress_flow.gd` helper patterns; if that screen cannot run without a game, instead assert the guard through a small static helper `GrowScreen.record_growth(save: SaveGame, into: String) -> void` that tolerates `save == null`, and test that helper with null and with a save).
- [ ] **Step 2: Run both suites; expect FAIL.**
- [ ] **Step 3: Implement.** In `GrowScreen._ask`, right after `Progression.apply_growth(...)`, call `record_growth(GameState.current if GameState.has_game() else null, into)`; add `static func record_growth(save: SaveGame, into: String) -> void` that does nothing for `null`, else `Codex.mark_caught(save, into)` and `Counters.add(save, "creatures_evolved")`. In `FieldItems.use`, call `Counters.add(save, "items_used")` just before each `out.ok = true; return out` success path (training and heal).
- [ ] **Step 4: Run `test_progress_flow.gd`, `test_field_items.gd`, `tests/world/test_summary_screen.gd`, `tests/world/test_pause_menu.gd`; expect PASS.**

### Task 5: Step counting

**Files:**
- Modify: `game/overworld/player.gd` (`step`; a private `_walked` accumulator)
- Test: `tests/world/test_player.gd`

**Interfaces:**
- Consumes: `Counters.add`, `GameState.has_game()`, `GameState.current`.

- [ ] **Step 1: Write failing tests** (the suite builds `map`/`player` in `before_test` and walks with `_walk(dir, seconds, run)`; save and restore `GameState.current` around the new tests, creating `GameState.current = SaveGame.new_game("Ana", 1000, rng)`):
  - `test_one_step_counted_per_tile_walked`: walk right until the player's travelled distance is `3 * GameMap.TILE` (+ a small margin under half a tile); assert `Counters.value(GameState.current, "steps") == 3`.
  - `test_partial_tile_counts_nothing_yet_then_completes`: walking `0.4 * TILE` leaves `steps == 0`; further walking past `1.0 * TILE` total gives 1.
  - `test_blocked_movement_counts_no_steps`: walking into a wall for a second adds nothing (compare against position change: the counter equals `floor(actual distance moved / TILE)`).
  - `test_stepping_without_a_loaded_game_is_safe`: with `GameState.current = null`, `_walk(Vector2.RIGHT, 1.0)` raises no error and moves the player.
- [ ] **Step 2: Run `test_player.gd`; expect FAIL** on the counter tests.
- [ ] **Step 3: Implement.** In `step`, record `position` before `move_and_collide`, add the distance actually moved (`position.distance_to(before)`, measured after all movement in the call) to `_walked`; while `_walked >= GameMap.TILE`, subtract it and, when `GameState.has_game()`, `Counters.add(GameState.current, "steps")`. `_walked` is not saved. Do not count `place()` teleports.
- [ ] **Step 4: Run `tests/world/test_player.gd`, `test_overworld.gd`, `test_pieces.gd`; expect PASS.**

### Task 6: Docs, handoff and full check

**Files:**
- Modify: `documentation/battle-engine.md` (no change expected), `.superpowers/HANDOFF.md`, `documentation/specs/2026-11-11-m7a-tracking-design.md` (Status: Implemented)
- Create: `documentation/tracking.md` (short reference: Codex and counters API, ids, hook points, how to add a counter)

- [ ] **Step 1: Write `documentation/tracking.md`** (under 60 lines): the Codex record shape, the eight counters and when each moves, where each hook lives, and "to add a counter: add the id to `Counters.BUILT_IN`, bump it at its hook, add a test".
- [ ] **Step 2: Update `.superpowers/HANDOFF.md`**: replace the "What's next" paragraph so it records M6 and 7a as done (7a uncommitted until the user commits), lists M7b and M7c as next with the spec links, and mentions the tag rule already in the standing rules. Set the 7a spec's Status to `Implemented`.
- [ ] **Step 3: Full check.** `bash scripts/check.sh`; expect it to end "All checks passed." Record the test-case count.
- [ ] **Step 4: Hand over.** Do not commit. Give the user this message:

```
Add Codex tracking and lifetime counters (M7)
- New Codex data (seen and caught per species) with a backfill for old saves; save schema 7
- Eight lifetime counters in the story store, bumped at battle results, gifts, evolution, item use, money and steps
- Hooks are no-ops without a loaded game and exhibitions track nothing

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
```

---

**Self-review notes:** every spec section maps to a task (Codex, Counters, schema: 1; backfill, Story hooks: 2; `apply_results` hooks: 3; growth and bag hooks: 4; steps: 5; docs and check: 6). `Battler.fielded` from the spec is replaced by the existing `participated` (spec amended). `Counters.get` became `Counters.value` (spec amended). Type names match across tasks: `Codex.mark_seen/mark_caught/status/backfill`, `Counters.add/value/BUILT_IN`.
