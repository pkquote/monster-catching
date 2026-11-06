# M5d Box and Party Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slot-addressed boxes (8 x 30, more unlockable), a grid Box screen with pick up / place / multi-select and a hover card, and a Party screen that shows the card and real sprite icons.

**Architecture:** `save.storage` becomes a fixed-length array of creature-or-null slots, owned by a new static `BoxStorage` helper, with a schema 5 -> 6 migration. `Team` gains `move` / `move_group` (old deposit/withdraw/swap become wrappers). The Box screen is a new full-screen layout built from `CreatureSlotButton`s and the 5b `CreatureCard`; the Party screen reuses `set_side` with the card.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit-style suites, the run-skill driver for tours.

**Spec:** `documentation/specs/2026-11-06-m5d-box-and-party-design.md`

## Global Constraints

- **Never commit, stage or stash.** The user writes every commit. Skip commit steps; at the end give a commit message in the handoff format (`{{title}}`, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Box is 30 slots (`BoxStorage.BOX_SIZE`), 6 columns, `START_BOXES` 8, `MAX_BOXES` 32. Save schema becomes 6. A creature must never be lost: any load or migration that would not fit raises `boxes_unlocked` instead.
- Keep every rule: a healthy creature must stay in the party (`last_healthy`), party size cap (`party_full`), `bad_index`, and the safe-places-only rule for the Box (`PartyScreen` disables Storage elsewhere). `Team.deposit/withdraw/swap` keep their names, signatures and meaning.
- Screen 640x360, 4px margin. Party column 2x6 of 36px slots, box grid 6x5 of 36px slots, `CreatureCard` (300x272) on the right.
- Mark action defaults: keyboard `V`, gamepad `JOY_BUTTON_Y`. (The spec said X / West; X is the default Cancel key and West is Run, so both were taken. The spec is amended in Task 1.)
- Box switching uses the existing `prev_creature` / `next_creature` shoulder actions (PageUp / PageDown).
- Test-pack rule stays: debug fills never add `tp_` creatures to a save. Godot test runs share save files: never run two Godot processes at once. In tour files `d` is untyped, so use `=` not `:=`.
- Godot console: `/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.

## Review Focus

- A schema-5 save with 0, 1, 30, 31 and 300 stored creatures loads with every creature present, in order, and `boxes_unlocked` large enough.
- A group move across a box boundary, into a nearly full box (short by 1), into the party with less room than the group, and one that would leave no healthy creature in the party.
- Picking up, then switching box or closing the screen / pressing Cancel: nothing is lost, duplicated or left half-moved; a held creature is never in two places.
- Marking then marking elsewhere clears the first marks; marking an empty slot does nothing; Accept on an empty slot with nothing held does nothing.
- A full party of 12 and 8 full boxes (240 creatures) with long nicknames: the screen fits, focus reaches every slot, and the card follows.
- Capture with the party full and every box full is refused with a reason; with one empty slot it is allowed and lands in it.

---

### Task 1: The `mark` input action

**Files:**
- Modify: `core/settings/game_settings.gd` (`ACTIONS`, `ACTION_LABELS`, `default_bindings`), `documentation/specs/2026-11-06-m5d-box-and-party-design.md` (mark default amendment)
- Test: the settings suites (find with `grep -rln "GameSettings" tests`), e.g. `tests/settings/`

**Interfaces:**
- Produces: action `"mark"` in `GameSettings.ACTIONS` (after `"run"`), label `"Mark"`, defaults `{"keyboard": [_key(KEY_V)], "gamepad": [_jbtn(JOY_BUTTON_Y)]}`; `Settings.apply_controls` registers it in the InputMap automatically.

- [ ] **Step 1: Write failing tests** in the existing settings test suite: `test_mark_is_a_rebindable_action_with_defaults` (in `ACTIONS`, has a label, default keyboard `V`, gamepad Y); `test_old_settings_without_mark_get_the_default` (a settings dict lacking `"mark"` loads with the default binding); `test_mark_is_registered_in_the_input_map` (after `Settings.apply_controls()` `InputMap.has_action("mark")`). Adapt any test that hard-codes the action list or its length.
- [ ] **Step 2: Run** the settings suites; Expected: FAIL.
- [ ] **Step 3: Implement** the three constants/defaults. Check `GameSettings.from_dict` fills a missing action from the defaults; if not, make it do so.
- [ ] **Step 4: Run** the settings suites and `tests/game` Controls-tab tests (`test_settings_scroll.gd`); Expected: PASS. Edit the spec's "Decisions" and "Box screen" lines to say the defaults are V / gamepad Y and why.

### Task 2: Slot-addressed storage, the save migration and every non-UI caller

**Files:**
- Create: `core/progress/box_storage.gd`, `tests/progress/test_box_storage.gd`
- Modify: `core/save/save_game.gd` (SCHEMA 6, `boxes_unlocked`, `_init`, `to_dict`, `from_dict`), `core/save/save_store.gd` (`_v5_to_v6`, migrations table), `core/progress/team.gd` (the three old operations use slots), `game/autoload/game_state.gd`, `game/autoload/story.gd`, `game/battle/battle_launcher.gd` (`add_to_party`, `fill_box`), `core/battle/battle_summary.gd`, `game/battle/battle_scene.gd`, `game/overworld/overworld.gd`, `game/overworld/pieces/storage_box.gd`, `tools/build_maps.gd` (only if they count or append to storage), every test that builds or reads `save.storage` (about 40 references in `tests/data/test_balance_party.gd`, `tests/game/test_battle_launcher.gd`, `test_debug_menu.gd`, `test_exhibition.gd`, `test_screens_smoke.gd`, `test_testpack_safety.gd`, `tests/log/test_log_coverage.gd`, `tests/progress/test_team.gd`, `tests/save/test_save_store.gd`, `tests/story/test_story_api.gd`, `tests/world/test_game_map.gd`, `test_party_screen.gd`, `test_storage_screen.gd`, `test_summary_screen.gd`)
- Test: `tests/progress/test_box_storage.gd`, `tests/save/test_save_store.gd`

**Interfaces:**
- Produces `class_name BoxStorage extends RefCounted` (all static): constants `BOX_SIZE := 30`, `COLUMNS := 6`, `START_BOXES := 8`, `MAX_BOXES := 32`; `slot_count(save) -> int` (`save.storage.size()`); `box_count(save) -> int` (`save.boxes_unlocked`); `box_of(slot: int) -> int`; `index_in_box(slot: int) -> int`; `slot_of(box: int, index: int) -> int`; `creature_at(save, slot: int) -> CreatureInstance` (null when empty or out of range); `first_empty(save, from: int = 0) -> int` (-1 when none; searches `from` to the end, no wrap); `empty_count(save) -> int`; `count(save) -> int`; `all_creatures(save) -> Array`; `add(save, c: CreatureInstance) -> bool`; `unlock_box(save) -> bool` (appends `BOX_SIZE` nulls and raises `boxes_unlocked`; false at `MAX_BOXES`); `ensure_boxes(save, boxes: int) -> void`.
- `SaveGame.boxes_unlocked: int` (default `START_BOXES`), `SaveGame._init()` sizes `storage` to `START_BOXES * BOX_SIZE` nulls; `to_dict` writes `null` for empty slots plus `boxes_unlocked`; `from_dict` keeps nulls, raises `boxes_unlocked` to fit all stored entries (capped at `MAX_BOXES`) and pads with nulls to `boxes_unlocked * BOX_SIZE`.
- `SaveStore._v5_to_v6(d) -> Dictionary`: packs the old list (order kept) into the first slots, pads with `null` to `max(START_BOXES, ceil(n / BOX_SIZE)) * BOX_SIZE`, sets `boxes_unlocked` accordingly and `schema = 6`.
- `Team.deposit` puts the creature in `BoxStorage.first_empty` (`bad_index` / `last_healthy` as before; a full box returns `"box_full"`); `Team.withdraw(db, save, slot)` and `Team.swap(db, save, party_i, slot)` take a slot index and null out / replace that slot.

- [ ] **Step 1: Write failing tests**: `tests/progress/test_box_storage.gd` (`box_of`/`index_in_box`/`slot_of` round trips at 0, 29, 30, 239; `creature_at` null for empty and out of range; `first_empty` with and without `from`, and -1 when full; `count` / `empty_count` / `all_creatures` order; `add` fills the first hole and returns false when full; `unlock_box` adds 30 slots and stops at `MAX_BOXES`; a fresh `SaveGame` has 8 boxes of nulls). In `tests/save/test_save_store.gd`: `test_schema_5_save_migrates_to_6` (build a schema-5 dict with 0, 1, 30, 31 and 300 stored creatures; each loads with every creature present in order, `boxes_unlocked == max(8, ceil(n/30))`), `test_schema_6_round_trip_keeps_holes` (creatures in slots 0, 7 and 30; save and load; same slots), `test_current_schema_is_6`.
- [ ] **Step 2: Run** the new/changed suites; Expected: FAIL (class missing).
- [ ] **Step 3: Implement** `BoxStorage`, the `SaveGame` and `SaveStore` changes, then move every caller in the Files list from `storage.append` / `.size()` / `remove_at` to `BoxStorage` calls (`BattleLauncher.add_to_party` and `fill_box` use `BoxStorage.add`; `fill_box` stops silently when full; `GameState` loops skip nulls). Adapt each existing test: building storage uses `BoxStorage.add(save, c)`, counts use `BoxStorage.count(save)`, "storage is empty" uses `count == 0`.
- [ ] **Step 4: Run** the whole test suite (`bash scripts/check.sh` or the GdUnit command over `res://tests`); Expected: PASS with no other behaviour change.

### Task 3: `Team.move`, `Team.move_group`, `BattleLauncher.room_left`

**Files:**
- Modify: `core/progress/team.gd` (new operations; wrappers), `game/battle/battle_launcher.gd` (`room_left`)
- Test: `tests/progress/test_team.gd`

**Interfaces:**
- Consumes: `BoxStorage` (Task 2).
- Produces: `Team.move(db: Database, save: SaveGame, from: Dictionary, to: Dictionary) -> String` where a location is `{"party": i}` or `{"box": slot}`: an empty box destination receives the creature; an occupied one swaps; `{"party": save.party.size()}` (one past the last member) appends when the party has room; another party index reorders (`Team.reorder` semantics, no swap). Reasons: `""`, `bad_index`, `last_healthy`, `party_full`, `same_slot` (from == to; nothing happens). `Team.move_group(db, save, froms: Array, to: Dictionary) -> Dictionary` returning `{reason: String, moved: int, short: int}`: places each source, in order, into the next empty slot starting at `to` (box: `BoxStorage.first_empty` from the destination slot, no wrap; party: appended while there is room), never swaps; if there are too few empty slots nothing moves, `reason = "no_room"`, `short = needed - available`; `last_healthy` when the group would take every healthy party member out and no healthy creature enters; `bad_index` for any bad source. `BattleLauncher.room_left(db, save) -> int` = free party room + `BoxStorage.empty_count(save)`.

- [ ] **Step 1: Write failing tests** in `tests/progress/test_team.gd`: `move` — party to empty box slot, box to party end, box to box (empty and occupied), party to occupied box slot swaps, party reorder, `last_healthy` when depositing the only healthy creature (but allowed when a healthy one swaps in), `party_full`, `bad_index`, `same_slot`; `move_group` — fills in reading order from the destination, skips occupied slots, crosses a box boundary, `no_room` with the right `short` and nothing moved, into the party with limited room (`no_room`), `last_healthy`, never swaps, moves from the party and from the box; `room_left` with a full party and a half-full box; the old `deposit/withdraw/swap` tests still pass unchanged apart from slot semantics.
- [ ] **Step 2: Run** `tests/progress/test_team.gd`; Expected: FAIL.
- [ ] **Step 3: Implement** `move`, `move_group` and `room_left`; make `deposit`, `withdraw` and `swap` thin wrappers over `move` (keeping `Team._report` logging for every operation so `tests/log/test_log_coverage.gd` stays satisfied; add log coverage for the new ops there if it checks per-op).
- [ ] **Step 4: Run** `tests/progress`, `tests/log` and `tests/world/test_party_screen.gd`; Expected: PASS.

### Task 4: Capture refusal when there is no room; F1 Unlock a box

**Files:**
- Modify: `game/battle/battle_scene.gd` (where capture items are disabled for tamer battles, around the item-menu code near line 255), `game/debug/pages/debug_main_page.gd` (Unlock a box button and status), `game/battle/battle_launcher.gd` (`fill_box` already moved in Task 2)
- Test: `tests/game/test_battle_scene_smoke.gd` or a new `tests/game/test_capture_room.gd`, `tests/game/test_debug_menu.gd`

**Interfaces:**
- Consumes: `BattleLauncher.room_left`, `BoxStorage.unlock_box`.
- Produces: capture items are disabled with the reason "No room for another creature." in the battle item menu when a non-exhibition game save is attached and `room_left == 0`; the F1 main page has `"Unlock a box"` (disabled without a game or at `MAX_BOXES`), status text `"%d boxes."` after pressing it.

- [ ] **Step 1: Write failing tests**: with a full party and 8 full boxes a capture item is disabled with that reason; with one empty box slot it is enabled; an exhibition battle is unaffected; the F1 button unlocks one box (`boxes_unlocked` 9, `slot_count` 270), shows the status, and is disabled at `MAX_BOXES`; Fill box stops at capacity.
- [ ] **Step 2: Run**; Expected: FAIL.
- [ ] **Step 3: Implement** both. Find the capture check in `battle_scene.gd` by `grep -n "capture" game/battle/battle_scene.gd`; keep the existing wild-only rule and add the no-room rule next to it.
- [ ] **Step 4: Run** `tests/game`; Expected: PASS.

### Task 5: `CreatureSlotButton`

**Files:**
- Create: `game/ui/creature_slot_button.gd`, `tests/game/test_creature_slot_button.gd`

**Interfaces:**
- Consumes: `CreatureSpriteSlot.configure(db, species, size)`.
- Produces: `class_name CreatureSlotButton extends Button`; `func configure(db: Database, creature: CreatureInstance, p_size: int = 36) -> void` (null creature = empty slot: dim outline, no sprite); `func creature() -> CreatureInstance`; `func set_marked(on: bool) -> void`; `func set_carried(on: bool) -> void`; `func is_marked() -> bool`; `func is_carried() -> bool`; `func badge_text() -> String` (status initial, "" if none; a fainted creature shows "F"); `func set_count_badge(n: int) -> void` (a "xN" badge, hidden for n < 2). Size is `Vector2(p_size, p_size)`, focus draws the standard focus style plus an accent border; marked draws an accent corner tick, carried dims the sprite.

- [ ] **Step 1: Write failing tests**: empty slot has no creature and the empty look (`creature() == null`); a creature slot embeds a `CreatureSpriteSlot`; `set_marked` / `set_carried` toggle state; `badge_text` for none/status/fainted; count badge hidden below 2; minimum size; draws without error for a long-named creature; focus emits `focus_entered`.
- [ ] **Step 2: Run**; Expected: FAIL.
- [ ] **Step 3: Implement** the button (child `CreatureSpriteSlot` and a small `Label` for the badge; styles via `StyleBoxFlat` overrides).
- [ ] **Step 4: Run** the suite; Expected: PASS.

### Task 6: Box screen layout, cursor, card and box switching (browse only)

**Files:**
- Modify: `game/progress/storage_screen.gd` (rewrite: full-screen overlay `extends CanvasLayer`, no `CommandMenu`)
- Test: `tests/world/test_storage_screen.gd` (rewrite the old list tests; keep what still applies: unsafe/disabled entry, `run` signature)

**Interfaces:**
- Consumes: `CreatureSlotButton`, `CreatureCard`, `BoxStorage`, `UIKit`.
- Produces: `class_name StorageScreen extends CanvasLayer` with `static func run(world: Node, save: SaveGame = null, db: Database = null) -> void` (runs until closed); `var box := 0` (current box index); `func show_box(index: int) -> void` (clamped to `BoxStorage.box_count`); `func step_box(step: int) -> void` (wraps); `func party_buttons() -> Array`, `func box_buttons() -> Array` (the 30 slot buttons of the current box, row-major); `func card() -> CreatureCard`; `func help_text() -> String`; `func focused_location() -> Dictionary` (`{party: i}` or `{box: slot}`, `{}` if none); `func close() -> void`. Focus moves with the arrows by geometry; focusing a slot refreshes the card (empty slot shows "Empty" and clears the creature). `prev_creature` / `next_creature` and the header arrows call `step_box`. Cancel closes the screen (Task 7 changes this while something is held).

- [ ] **Step 1: Write failing tests**: opens with 12 party slots-worth of party buttons for a full party and the right count of filled/empty slots; the grid shows the current box's 30 slots with creatures in the right cells; `show_box` / `step_box` change cells and header ("Box 3 / 8"), wrap, and clamp; focusing a creature slot shows it on the card (`card().header_text()`), an empty slot shows "Empty"; Down/Right from the party column reaches the grid and back (focus reaches every slot); shoulder actions switch box; Cancel closes; `focused_location` is right for party and box slots; layout fits 640x360 (all slot rects and the card inside the view) with a full party of 12 and 8 full boxes of long names; `PartyScreen`'s Storage entry still opens it and is disabled in unsafe places.
- [ ] **Step 2: Run** `tests/world/test_storage_screen.gd`; Expected: FAIL.
- [ ] **Step 3: Implement** the layout (party 2x6, box 6x5, header with focusable arrows, card right, help line bottom) and the browse behaviour. Rows beyond the party size are empty party slots (focusable; the first one past the last member is the append target in Task 7).
- [ ] **Step 4: Run** the suite and `tests/game/test_screens_smoke.gd`; Expected: PASS.

### Task 7: Pick up, place, marks and group moves in the Box screen

**Files:**
- Modify: `game/progress/storage_screen.gd`
- Test: `tests/world/test_storage_screen.gd`

**Interfaces:**
- Consumes: `Team.move`, `Team.move_group`, the `mark` action (Task 1), `CreatureSlotButton.set_marked/set_carried/set_count_badge`.
- Produces on `StorageScreen`: `func accept() -> void`, `func cancel() -> void`, `func mark() -> void` (what Accept / Cancel / `mark` do; input handlers call them); `func held() -> Array` (locations picked up, `[]` when none); `func marks() -> Array` (marked locations); behaviour: `mark` toggles the mark on the focused creature (empty slot: nothing), marks must share a source (party, or one box), marking elsewhere clears the old marks; `accept` with nothing held picks up the marks (or the focused creature) and does nothing on an empty slot; `accept` with something held places it (one: `Team.move`; several: `Team.move_group`), clears held and marks on success and shows the refusal text on failure (`last_healthy`: "Keep at least one creature that can fight.", `party_full`: "Your party is full.", `no_room`: "Need N more free slots.") leaving everything held; `cancel` with something held puts it down (clears held, keeps marks), with nothing held closes the screen. Held creatures are not in two places (the sources stay until placed).

- [ ] **Step 1: Write failing tests**: pick up and place on an empty box slot, onto an occupied slot (swap), party to box (deposit) and box to party (append at the first empty party slot), refusals (`last_healthy`, `party_full`) keep the creature held and show the text; Cancel puts it down; marks: toggle on/off, empty slot ignored, marking in another container clears the old marks; group pick up shows the count badge; group placed from the party into a box, within a box, across boxes after `step_box`, `no_room` text with the count and nothing moved; group into the party limited by room; Accept with nothing held on an empty slot does nothing; Cancel with nothing held closes; the `mark` and accept inputs (via pushed `InputEventAction`) reach the same behaviour; after every operation `BoxStorage.count + party.size()` is unchanged.
- [ ] **Step 2: Run**; Expected: FAIL.
- [ ] **Step 3: Implement** the state (held locations, marks), input handling (`_input`: Accept, Cancel, `mark`, shoulders), button looks (marked/carried/count), the help line text per state ("Accept: pick up   V: mark   PageUp/PageDown: box   Back: close" vs "Accept: place here   Back: put down"), and refusal messages.
- [ ] **Step 4: Run** `tests/world`, `tests/game`; Expected: PASS.

### Task 8: Party screen with the card and sprite icons

**Files:**
- Modify: `game/progress/party_screen.gd` (`_row_option` icon, card via `set_side`, hovered updates)
- Test: `tests/world/test_party_screen.gd`

**Interfaces:**
- Consumes: `ProgressScreen.set_side`, `CreatureCard`, `CreatureSpriteSlot`, `CommandMenu.hovered(hint)`.
- Produces: `PartyScreen.card() -> CreatureCard`; each row's `hint` is the party index; focusing a row shows that creature on the card; rows keep their text, bars, status and "Ready to grow"; the colour swatch icon is replaced by a `CreatureSpriteSlot` child of the row button (about 18px). The card is built before the screen joins the tree (as `SummaryScreen.run` does). The party list still fits 640x360 for a party of 12 (`ScreenFit`).

- [ ] **Step 1: Write failing tests**: opening shows the first creature on the card; moving focus to the third row shows that creature; a row button contains a `CreatureSpriteSlot`; the Back row clears or keeps the last creature without error; a party of 12 fits (`ScreenFit.check` with scrolling allowed if needed) and rows stay readable; Summary, Move and Storage flows still work (existing tests).
- [ ] **Step 2: Run** `tests/world/test_party_screen.gd`; Expected: FAIL.
- [ ] **Step 3: Implement** the card slot and hover wiring (connect `menu.hovered` when the list is up, as `PauseMenu._bag` does) and the icon.
- [ ] **Step 4: Run** `tests/world/test_party_screen.gd` and `tests/game/test_screens_smoke.gd`; Expected: PASS.

### Task 9: Tours, docs, full check

**Files:**
- Modify: `.claude/skills/run-godot-monster-catching-game/tours/party.gd` and `progress.gd` (Storage steps now use the grid), a new tour step set or `--mode=box` (`tours/box.gd`, registered in `driver.gd` and `SKILL.md`), `.superpowers/HANDOFF.md`, `documentation/specs/2026-11-06-m5d-box-and-party-design.md` (Status: Implemented), `documentation/specs/2026-11-05-roadmap-m5-m8.md` if it tracks status, `documentation/compendium.md` only if a generator input changed

- [ ] **Step 1: Update the existing tours** that used the old Storage list (`party.gd`, `progress.gd`): open Storage, check the grid and card, do a pick up and place with Accept, and close with Cancel; keep their other expectations.
- [ ] **Step 2: Add `--mode=box`**: new game, F1 test party and "Fill box" with 40 creatures, open Party -> Storage; screenshots: `bx01_browse`, a pick up and place (`bx02_carry`, `bx03_placed`), mark three creatures and carry them to another box (`bx04_group`, `bx05_group_placed`), a refusal message (`bx06_refusal`), "Unlock a box" status; Party screen with the card (`bx07_party`). Read every screenshot: nothing clipped, labels readable, focus visible, the card matches the cursor.
- [ ] **Step 3: Run** `--mode=box`, `--mode=party`, `--mode=progress`, `--mode=held`; Expected: ALL CHECKS PASSED. Fix layout problems found in the screenshots.
- [ ] **Step 4: Docs and handoff**: M5d paragraph (slot model, `BoxStorage`, schema 6, `Team.move/move_group`, marks, capture refusal, F1 Unlock a box, new tour), the "What's next" line (M5 done; M6 engine backlog next), note the old `StorageScreen` list was replaced.
- [ ] **Step 5: Run** `bash scripts/check.sh`; Expected: final line "All checks passed."
- [ ] **Step 6: Give the user** a commit message in the handoff format; do not commit.
