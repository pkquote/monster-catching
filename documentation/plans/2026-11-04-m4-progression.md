# M4 Progression and Menus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Players learn and swap moves from a move pool, grow creatures by Affinity, manage a party of six against a storage box (blocked from the menu in unsafe zones), and spend or refund training points.

**Architecture:**
- **Rules:** new rules live in headless `core/` (`Progression`, new `Team`, `FieldItems`).
- **Battles:** `BattleLauncher.apply_results` reports which creatures levelled.
- **The after-battle step:** the overworld runs `ProgressFlow` before the post-battle autosave. It uses screens in `game/progress/` that the Party → Summary menus reuse.
- **Map pieces:** StorageBox and UnsafeArea follow the M3 piece pattern.

**Tech Stack:** Godot 4.7.2 .NET, typed GDScript, gdUnit4 6.2.3, Dialogue Manager 4.2.

**Spec:** [documentation/specs/2026-11-04-m4-progression-design.md](../specs/2026-11-04-m4-progression-design.md)

## Global Constraints

- `core/` stays pure logic (RefCounted, no nodes). Screens live in `game/`.
- `balance.max_moves` = 4, `balance.party_size` = 6, `training_cfg.max_per_stat` = 30, `growth_affinity_threshold` = 30. Read them from the Database, never hard-code them.
- The Reset Seed: id `reset_seed`, name "Reset Seed", category `training`, price 600, op `reset_training`, target `one_ally`.
- Save `SCHEMA` = 3. The v2→v3 step goes in `SaveStore.migrations()`.
- Every screen is awaitable `run(...)`, uses `UIKit` and `CommandMenu`, and fits 640×360. It is usable with keyboard or gamepad, and tests can drive it through `menu.pick_label(...)`.
- Exact copy:
  - "Tidepup wants to learn Riptide"
  - "Keep it for later"
  - "Tidepup is ready to grow! Its Striker side is strongest: it will become Torrentusk."
  - "Grow now" / "Not yet"
  - "Tidepup grew into Torrentusk!"
  - "It isn't safe to swap creatures here."
  - "Keep at least one creature that can fight."
  - "Your party is full."
- Tests use `Overworld.instant = true`, temp save stores (`user://test_<suite>_saves`), and free worlds directly.
- Run suites with `GdUnitCmdTool.gd --add res://tests/<path>`. Run the whole project with `bash scripts/check.sh`.
- Commits: none. The user authors every commit, so each task ends with the tree left uncommitted.

## Review Focus

1. **Reset Seed during battle:** a `training` item must not appear in the battle Items menu, and the engine must refuse it (Task 4).
2. **Growth into a species with a different learnset:** the moves it already knows stay usable even when the new species' learnset lacks them (Task 2).
3. **A loss with level-ups in it:** a defeat that still levelled creatures runs the step after the respawn message, then autosaves (Task 7).
4. **Storage with a fainted party:** depositing or swapping out the last healthy creature is refused even from a StorageBox (Task 3, Task 10).
5. **Pool editing in battle:** move slots can't change while a battle overlay is open, because the Party menu is unreachable then. A test confirms the Menu key does nothing while `in_battle()` (Task 8).

---

### Task 1: Move pool and save v3

**Files:**
- Modify: `core/progress/creature_instance.gd` (field, `create`, `copy_from`, `to_dict`, `from_dict`)
- Modify: `core/progress/progression.gd` (`award_xp`)
- Modify: `core/save/save_game.gd` (`SCHEMA` 3), `core/save/save_store.gd` (`_v2_to_v3`)
- Test: `tests/progress/test_move_pool.gd` (new), `tests/save/test_save_store.gd`

**Interfaces:**
- Produces: `CreatureInstance.move_pool: PackedStringArray`. `create` sets it to every learnset move ≤ level (the slots are the last 4 of those). It is saved as `"move_pool"`. `from_dict` without the key falls back to `moves`.
- Produces: `SaveStore._v2_to_v3(d: Dictionary) -> Dictionary`.

- [ ] **Step 1: Write failing tests** in `test_move_pool.gd`:
  - `test_create_pools_all_learnable_moves`: Tidepup Lv 14 → pool has all 6 learnset moves, and `moves` is the last 4.
  - `test_level_up_with_free_slot_learns_and_pools`: Tidepup Lv 4 with 2 moves, XP to Lv 5 → `drench` is in both lists, plus a `move_learned` event.
  - `test_level_up_with_full_slots_pools_and_offers`: 4 moves, reaching Lv 9 → `riptide` is in the pool but not in `moves`, plus a `move_offered` event.
  - `test_pool_round_trips_through_dict`.
  - `test_old_dict_without_pool_uses_moves`.

  In `test_save_store.gd`, add `test_v2_save_migrates_to_v3_pools`: a v2 dict with a Lv 9 Tidepup knowing `["tackle"]` loads with pool ⊇ `tackle, splash_jab, drench, riptide`.
- [ ] **Step 2: Run them.** Expected: FAIL, because `move_pool` doesn't exist.
- [ ] **Step 3: Implement** the field and the `award_xp` change (always append to the pool if missing; slot only when free). Implement `_v2_to_v3`: for every party and storage creature dict, set `move_pool` = `moves` + missing learnset moves ≤ level, using `DataRegistry.db`. Set `schema` 3.
- [ ] **Step 4: Run** `tests/progress` and `tests/save`. Expected: all pass.

### Task 2: set_moves, reset_training, growth moves, progress entries

**Files:**
- Modify: `core/progress/progression.gd`
- Test: `tests/progress/test_move_pool.gd`, `tests/progress/test_training_bond.gd`, `tests/progress/test_progression.gd`

**Interfaces:**
- Consumes: `move_pool` (Task 1).
- Produces:
  - `Progression.set_moves(db, c, slots: PackedStringArray) -> String`: returns `""`, `"empty"`, `"too_many"`, `"duplicate"` or `"not_in_pool"`.
  - `Progression.reset_training(db, c) -> int`: the points refunded.
  - `Progression.apply_growth(...)` now also returns `learned: Array[String]` and `offered: Array[String]`.
  - `Progression.progress_entry(db, c, level_before: int) -> Dictionary`: `{}` when `c.level <= level_before`. Otherwise `{creature, offered_moves: Array[String], growth_due: bool}`. `offered_moves` = pool moves with a learnset level in `(level_before, c.level]` that aren't in `moves`.

- [ ] **Step 1: Write failing tests:**
  - `test_set_moves_refusals`: each of the four reasons, plus success replacing `tackle` with `riptide`.
  - `test_reset_training_refunds_and_clamps`: 10 points in HP, then a reset → returns 10 and HP ≤ the new max (≥ 1 when it was > 0). Also a fainted creature stays at 0.
  - `test_growth_learns_moves_at_current_level`: Lv 16 Tidepup with 4 moves grows into Torrentusk → `quake_stomp` is in the pool and in `offered`. With 3 moves it's in `learned` and in a slot. This needs the data change in Step 3.
  - `test_growth_keeps_known_moves` (Review Focus 2).
  - `test_progress_entry_reports_offers_and_growth`: Tidepup Lv 15 with 30 striker Affinity, levelled to 16 → `growth_due` true.
  - `test_progress_entry_empty_without_level_gain`.
- [ ] **Step 2: Run.** Expected: FAIL, because the functions are missing.
- [ ] **Step 3: Implement** the four functions in `progression.gd`. In `data/creatures/starter_line.json`, move Torrentusk's `quake_stomp` and Mistcoil's `glacier_crash` from level 18 to 16, so growing at 16 teaches a signature move.
- [ ] **Step 4: Run** `tests/progress`. Expected: all pass.

### Task 3: Team rules

**Files:**
- Create: `core/progress/team.gd` (`class_name Team`)
- Test: `tests/progress/test_team.gd`

**Interfaces:**
- Produces static functions, each returning `""` or a reason:
  - `Team.reorder(save, from: int, to: int)`: `"bad_index"`.
  - `Team.deposit(db, save, party_i: int)`: `"bad_index"`, `"last_healthy"`.
  - `Team.withdraw(db, save, box_i: int)`: `"bad_index"`, `"party_full"`.
  - `Team.swap(db, save, party_i: int, box_i: int)`: `"bad_index"`, `"last_healthy"`.
- Produces `Team.healthy_after(save, removed: CreatureInstance, added: CreatureInstance) -> int`, a helper. Healthy means `hp > 0`.

- [ ] **Step 1: Write failing tests:**
  - `test_reorder_moves_lead`.
  - `test_deposit_refuses_last_healthy`: a party of two with one fainted → depositing the healthy one is refused, depositing the fainted one is allowed.
  - `test_withdraw_refuses_full_party`.
  - `test_swap_healthy_rule`: swapping the only healthy creature for a fainted box creature is refused, and for a healthy one it's allowed.
  - `test_bad_indices`.
  - `test_box_keeps_arrival_order`.
- [ ] **Step 2: Run.** Expected: FAIL, because `Team` is missing.
- [ ] **Step 3: Implement** `team.gd`. `withdraw` appends to the end of the party. `deposit` appends to the end of the box.
- [ ] **Step 4: Run** `tests/progress/test_team.gd`. Expected: all pass.

### Task 4: Reset Seed item

**Files:**
- Modify: `data/items/` (add `reset_seed` to a new `data/items/training.json`)
- Modify: `core/data/schemas.gd` (item category enum + `"training"`; `EFFECT_OPS["reset_training"] = {}`)
- Modify: `core/progress/field_items.gd` (`can_use`, `use`)
- Modify: `game/battle/battle_scene.gd:202` and `core/battle/action_runner.gd:168` (exclude or refuse `training`)
- Test: `tests/progress/test_field_items.gd`, `tests/battle/` (the existing item-action suite), `tests/data/`

**Interfaces:**
- Produces `FieldItems.use(db, save, "reset_seed", c)` → `{ok, error, refunded: int}`. Its new error is `"nothing_to_refund"`, and the item isn't spent when it fails.

- [ ] **Step 1: Write failing tests:**
  - `test_reset_seed_refunds_and_is_spent`.
  - `test_reset_seed_refused_without_spent_points`: the count is unchanged.
  - `test_reset_seed_works_on_fainted_creature`: it only refunds, and HP stays 0.
  - In the battle suite: `test_training_items_hidden_and_refused_in_battle` (Review Focus 1).
  - The data validator accepts the new file.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Description: "Returns all of a creature's training points so they can be spent again."
- [ ] **Step 4: Run** `tests/progress`, `tests/battle`, `tests/data`, and `--script res://tools/validate_data.gd`. Expected: pass, "Data OK" with 6 items.

### Task 5: Battles report progress

**Files:**
- Modify: `game/battle/battle_launcher.gd` (`apply_results`)
- Test: `tests/game/` (the existing launcher suite)

**Interfaces:**
- Consumes: `Progression.progress_entry` (Task 2).
- Produces: `summary.progress: Array` of entries in party order. It records each battler source's level before `engine.commit(0)`.

- [ ] **Step 1: Write failing tests:**
  - `test_results_report_levelled_creatures`: a scripted win that levels the lead → one entry, with an offered move when its slots are full.
  - `test_results_progress_empty_without_levels`.
- [ ] **Step 2: Run.** Expected: FAIL, because there's no `progress` key.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tests/game`. Expected: pass.

### Task 6: StorageBox, UnsafeArea and safe zones

**Files:**
- Create: `game/overworld/pieces/storage_box.gd/.tscn`, `game/overworld/pieces/unsafe_area.gd/.tscn`
- Modify: `game/overworld/game_map.gd` (`@export var unsafe := false`; `unsafe_at(tile) -> bool`)
- Modify: `game/overworld/overworld.gd` (`is_safe_here() -> bool`)
- Modify: `tools/map_builder.gd` (piece types `storage_box`, `unsafe_area`; a root prop `unsafe`)
- Modify: `tools/build_maps.gd` (an `--only=<id,id>` flag that force-rebuilds just those maps). Content:
  - A StorageBox in `town_01_center`, on a free counter or floor tile next to the shop.
  - An UnsafeArea at (13,6), size 5×4, on `route_01`.
  - `reset_seed` added to the centre ShopCounter's stock.
  - An UnsafeArea on `test_b`, at (2,2) size 2×2 (over the DeepGrass corner), for tests.
- Test: `tests/world/test_pieces.gd`, `tests/world/test_game_map.gd`

**Interfaces:**
- Produces `StorageBox`, whose `on_interact(w)` calls `w.open_storage()` (defined in Task 10; until then it's a stub that does nothing). `blocks()` is true.
- Produces `UnsafeArea`: `size: Vector2i`, a marker. The `size` setter clamps to ≥ 1 like `EncounterArea`.

- [ ] **Step 1: Write failing tests:**
  - `test_safe_here_follows_unsafe_area`: test_b (2,2) is unsafe and (6,4) is safe.
  - `test_unsafe_map_flag`: set `map.unsafe = true` → unsafe everywhere.
  - `test_unsafe_area_size_clamps`.
  - `test_maps_load` sees the StorageBox in `town_01_center`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Then rebuild only the changed maps: `godot --headless --path . res://tools/build_maps.tscn -- --only=town_01_center,route_01,test_b`. Before rebuilding, confirm with `git log --oneline -- game/maps` that those files have no edits since M3. If they do, edit those `.tscn` files by hand instead.
- [ ] **Step 4: Run** `tests/world` and `res://tools/check_maps.tscn`. Expected: pass, "Maps OK (7 maps)".

### Task 7: Learn Move and Grow screens, and the after-battle step

**Files:**
- Create: `game/progress/learn_move_screen.gd`, `game/progress/grow_screen.gd`, `game/progress/progress_flow.gd`
- Modify: `game/overworld/overworld.gd` (`run_progress`, `after_battle`)
- Test: `tests/world/test_progress_flow.gd` (new)

**Interfaces:**
- Consumes: Tasks 2 and 5.
- Produces:
  - `LearnMoveScreen.run(parent: Node, c: CreatureInstance, move: String) -> bool`: true if slotted. It's a CanvasLayer at layer 72 with a `menu: CommandMenu` holding options "Replace <Move>" ×4 and "Keep it for later".
  - `GrowScreen.run(parent: Node, c: CreatureInstance) -> bool`: true if grown. Options "Grow now" / "Not yet". Afterwards it runs `LearnMoveScreen` for each of `apply_growth(...).offered`.
  - `ProgressFlow.run(parent: Node, progress: Array) -> void`.
  - `Overworld.run_progress(progress: Array) -> void`: under the `"progress"` lock. `after_battle` calls it after the defeat message and before `GameState.autosave()`.
  - `Overworld.blocks_debug_menu()` also returns true while `"progress"` is held.

- [ ] **Step 1: Write failing tests:**
  - `test_learn_move_replace`.
  - `test_learn_move_keep`.
  - `test_grow_now_changes_species`.
  - `test_grow_not_yet_keeps_ready`.
  - `test_autosave_after_choices`: the saved file shows the replaced move.
  - `test_loss_with_levels_runs_after_respawn` (Review Focus 3).
  - `test_not_yet_reoffered_only_after_level_gain`: a second `after_battle` with an empty progress list shows no Grow screen.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **Layout:** a full-screen dim, a panel with the creature line, and the new move's type / category / power / cost / description above the menu.
  - **Grow animation:** a 0.4s white flash, skipped when `Overworld.instant`.
  - **Copy:** exactly as listed in Global Constraints. When the default branch applies, use "Tidepup is ready to grow! It will become Torrentusk."
- [ ] **Step 4: Run** `tests/world`. Expected: all pass.

### Task 8: Party screen

**Files:**
- Create: `game/progress/party_screen.gd`
- Modify: `game/overworld/ui/pause_menu.gd` (`_party` opens `PartyScreen`)
- Test: `tests/world/test_party_screen.gd` (new), `tests/world/test_pause_menu.gd`

**Interfaces:**
- Consumes: `Team.reorder`, `Overworld.is_safe_here`.
- Produces `PartyScreen.run(world: Overworld) -> void`.
  - **Layout:** rows of `PartyScreen.row_text(db, c) -> String` (name, level, HP, energy, status, and "Ready to grow").
  - **Row actions:** "Summary", "Move", "Storage", "Cancel".
  - **Storage:** opens `StorageScreen` (Task 10). It's disabled when not safe, and the page then shows the unsafe message.

- [ ] **Step 1: Write failing tests:**
  - `test_reorder_changes_lead`.
  - `test_storage_disabled_when_unsafe`: the player is in test_b's UnsafeArea.
  - `test_ready_to_grow_badge`.
  - `test_menu_key_ignored_in_battle` (Review Focus 5).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tests/world`. Expected: pass.

### Task 9: Summary screen

**Files:**
- Create: `game/progress/summary_screen.gd`
- Test: `tests/world/test_summary_screen.gd` (new)

**Interfaces:**
- Consumes: Tasks 2, 4 and 7.
- Produces `SummaryScreen.run(parent: Node, party: Array, index: int) -> void`, with `tab: String` (`"stats"`, `"moves"` or `"training"`) and `show_tab(name)`.
  - Left/Right switch tabs and Up/Down change creature.
  - **Stats:** shows "+n" for trained stats, XP to the next level, Bond, and four Affinity bars, plus "Grow" when ready.
  - **Moves:** slots and pool. Choosing a pool move runs `LearnMoveScreen`.
  - **Training:** "+1 <Stat>" for each `DataSchemas.TRAINABLE_STATS` and "Use a Reset Seed (you have n)".

- [ ] **Step 1: Write failing tests:**
  - `test_train_plus_one`.
  - `test_train_refused_at_cap_shows_reason`.
  - `test_reset_seed_from_summary`.
  - `test_swap_pool_move_into_slot`.
  - `test_grow_from_summary`.
  - `test_tabs_and_creature_switch`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Wire "Summary" in `PartyScreen` to it.
- [ ] **Step 4: Run** `tests/world`. Expected: pass.

### Task 10: Storage screen

**Files:**
- Create: `game/progress/storage_screen.gd`
- Modify: `game/overworld/overworld.gd` (`open_storage() -> void` under the `"menu"` lock), `game/overworld/pieces/storage_box.gd`, `game/progress/party_screen.gd`
- Test: `tests/world/test_storage_screen.gd` (new)

**Interfaces:**
- Consumes: `Team` (Task 3).
- Produces `StorageScreen.run(parent: Node) -> void`.
  - **Layout:** party on the left, box on the right, 10 per page (`page: int`, `PAGE_SIZE := 10`).
  - **Actions:** "Deposit", "Withdraw" or "Swap", depending on the selection.
  - **Refusals** are shown in plain words: `last_healthy` → "Keep at least one creature that can fight.", `party_full` → "Your party is full."

- [ ] **Step 1: Write failing tests:**
  - `test_deposit_and_withdraw`.
  - `test_refusal_messages`.
  - `test_paging_12_in_box`.
  - `test_storage_box_works_in_unsafe_zone`: place a StorageBox inside test_b's UnsafeArea in the test, then interact.
  - `test_storage_box_refuses_last_healthy` (Review Focus 4).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tests/world`. Expected: pass.

### Task 11: Bag uses the Reset Seed

**Files:**
- Modify: `game/overworld/ui/pause_menu.gd` (`_bag`)
- Test: `tests/world/test_pause_menu.gd`

- [ ] **Step 1: Write failing tests:**
  - `test_bag_reset_seed_confirms_and_refunds`: the page shows "Return 10 points from Tidepup?", and after Yes the creature's training is empty.
  - `test_bag_reset_seed_nothing_to_refund`: the page reads "It has no points to return."
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the confirmation: Yes / No through `menu.choose`.
- [ ] **Step 4: Run** `tests/world`. Expected: pass.

### Task 12: Debug tools

**Files:**
- Modify: `game/debug/debug_menu.gd`
- Test: `tests/game/` (the existing debug-menu suite)

**Interfaces:**
- Consumes: `Progression.award_xp`, `progress_entry`, `Overworld.run_progress`.
- Produces three buttons:
  - **"Give XP..."**: pick a creature, then "+1 level" or "To level 16". It closes the menu, then calls `world.run_progress([...])`.
  - **"Set Affinity..."**: pick a creature and a track. Sets that track to `growth_affinity_threshold + 10`.
  - **"Fill box"**: adds 12 random creatures at the party's average level.
  - All three are disabled while the overworld holds any lock.

- [ ] **Step 1: Write failing tests:**
  - `test_give_xp_to_16_runs_progress`.
  - `test_set_affinity_steers_growth`: mistcoil with catalyst.
  - `test_fill_box_adds_12`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tests/game`. Expected: pass.

### Task 13: Progress tour and docs

**Files:**
- Modify: `.claude/skills/run-godot-monster-catching-game/driver.gd` (`--mode=progress`), `.claude/skills/run-godot-monster-catching-game/SKILL.md`
- Modify: `documentation/map-building.md` (StorageBox, UnsafeArea, `unsafe`), the main spec's status line ("M0–M4 implemented"), the M4 spec's status ("Approved and implemented"), and the README if it lists features

- [ ] **Step 1: Add `--mode=progress`.** Each check below is an `expect(...)` with a screenshot (`p01_…` onward). It drives the real UI with key events, as the overworld tour does:
  1. New game with the test party.
  2. Debug "Give XP" Tidepup to 16 with striker Affinity.
  3. Learn Move: replace a move.
  4. Grow now → Torrentusk.
  5. Party: move Tidepup to second place.
  6. Summary: all three tabs.
  7. +1 Speed.
  8. Bag Reset Seed.
  9. Walk to the centre's StorageBox: deposit, then withdraw.
  10. Walk into Route 1's deep grass: Party → Storage shows the unsafe message.
- [ ] **Step 2: Run it twice.** Expected: all checks PASS both times. Look at every screenshot.
- [ ] **Step 3: Run the front-end, battle and overworld tours.** Expected: all PASS.
- [ ] **Step 4: Update the docs and SKILL.md** (the mode table and the statistics line). Run `bash scripts/check.sh`. Expected: "All checks passed.", "Maps OK (7 maps)", "Dialogue OK".
