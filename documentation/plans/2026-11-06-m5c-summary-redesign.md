# M5c Summary Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three-tab Summary with the 5b `CreatureCard` on the left and an info block plus a one-column action menu (with Moves / Train / Held item sub-lists) on the right.

**Architecture:** `ProgressScreen` gets an optional side control slot. `SummaryScreen` is rewritten as a small state machine (`top`, `moves`, `train`, `held` modes) that keeps its `_loop`/`menu.choose` structure, refreshes the card every iteration, and keeps every action and rule. No data or engine changes.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit-style suites, the run-skill driver for tours.

**Spec:** `documentation/specs/2026-11-06-m5c-summary-redesign-design.md`

## Global Constraints

- **Never commit, stage or stash.** The user writes every commit. Skip any commit step; at the end give a commit message in the handoff format (`{{title}}`, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Screen 640x360, 4px margin. Card is `CreatureCard.SIZE` (300x272); the right column is the rest (about 330px), menu buttons one column of `SummaryScreen.COLUMN_WIDTH` (306; adjust only if `ScreenFit` says it doesn't fit).
- Keep every rule: training cap (`stat_capped` notice), points, `not_enough_points` notice, Reset Seed confirm (`ResetSeedPrompt.confirm` + `FieldItems.use`), passive switch (`Passives.set_active`), held give/swap/take (`HeldItems.give/take`, bag counts), Grow (`GrowScreen.run`), move swap (`LearnMoveScreen.run(parent, c, move, true, db)`), previous/next wrap, `SummaryScreen.run(parent, party, index, save = null, db = null)`, `creature()`, `show_creature(index)`.
- Menu labels (tests and tours match on these exactly): top level `Grow`, `Moves...`, `Train...`, `Held item...`, `Use <Passive Name>`, `Previous creature`, `Next creature`, `Back`; Train rows `+1 <Stat Name>` (suffix `  (+k)` when trained) and `Use a Reset Seed (you have N)`; Held rows `Give held item`, `Swap held item`, `Take back`; every sub-list ends with `Back`.
- Other screens (Party, Storage, Grow, Learn Move, Passive Unlock) must look and behave exactly as before.
- Test and tour notes: Godot test runs share save files, so never run two Godot processes at once; in tour files `d` is untyped, so use `=` not `:=`.
- Godot console: `/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.

## Review Focus

- A party of 12 (or storage list of 12) with a long nickname, a long held-item description and every stat trained: the right column fits, or scrolls inside its area, and never leaves the screen.
- A creature with no passive, an unknown passive id, an unknown held id, 0-4 moves: no errors, sensible text.
- Left/Right and the shoulder buttons while a sub-list or a sub-screen (Grow, Learn Move, Reset Seed prompt) is open: ignored, no creature switch behind the prompt.
- Back out of a sub-list returns focus to the entry that opened it; a +1 keeps focus on the same row and the card's radar reflects the new total.
- A one-creature party: no Previous/Next entries, Left/Right do nothing.

---

### Task 1: ProgressScreen side-control slot

**Files:**
- Modify: `game/progress/progress_screen.gd` (`_ready`, new `set_side`, new `side_control`)
- Test: `tests/world/test_progress_screen_side.gd`

**Interfaces:**
- Produces: `func set_side(control: Control) -> void` (call before the screen is added to the tree; the control becomes the first child of a new `HBoxContainer` row inside the margin, with the existing column after it, `separation` `GAP`; the column takes the remaining width via `SIZE_EXPAND_FILL`); `func side_control() -> Control` (null when unset). Screens that never call `set_side` build exactly the layout they have today (no extra row).

- [ ] **Step 1: Write the failing tests** in `tests/world/test_progress_screen_side.gd` (build a bare `ProgressScreen`, add it to the tree, await frames): `test_without_a_side_control_nothing_changes` (`side_control()` is null; the info panel's rect starts at x = `MARGIN` and spans the full width as before, e.g. compare with a `LearnMoveScreen`-style screen opened normally via the existing helpers); `test_side_control_sits_left_of_the_column` (set a `ColorRect` of size 100x200; after layout its rect ends before the info panel's x and its top is at `MARGIN`; info panel and menu area still inside 640x360 via `ScreenFit.problems`).
- [ ] **Step 2: Run** `tests/world/test_progress_screen_side.gd`; Expected: FAIL (`set_side` not defined).
- [ ] **Step 3: Implement** `set_side` / `side_control` and build the optional row in `_ready` (put the `margin` child as `HBoxContainer` only when a side control was set).
- [ ] **Step 4: Run** the new suite plus `tests/world` and `tests/game/test_screens_smoke.gd`; Expected: PASS (other screens unaffected).

### Task 2: SummaryScreen layout, info block, top-level menu, creature switching

**Files:**
- Modify: `game/progress/summary_screen.gd` (rewrite the screen skeleton; see below)
- Test: `tests/world/test_summary_screen.gd` (replace the tab/layout/switching tests; the sub-list and action tests move in Tasks 3-4)

**Interfaces:**
- Consumes: `ProgressScreen.set_side`, `CreatureCard.show_creature(db, c)`.
- Produces on `SummaryScreen`: `var mode := "top"` (one of `"top"`, `"moves"`, `"train"`, `"held"`); `const COLUMN_WIDTH := 306`; `func card() -> CreatureCard`; `show_creature(index)` and `creature()` unchanged; `show_mode(name: String)` (sets `mode`, clears the notice, interrupts the menu with `REFRESH`) used by sub-list entries and tests; removed: `tab`, `TABS`, `TAB_NAMES`, `show_tab`, `next_tab`.

- [ ] **Step 1: Write failing tests** in `tests/world/test_summary_screen.gd` (use the existing helpers `_open`, `_pick`, `_press`, `_assert_fits`, `_texts`, `_pup_with_passives`): `test_top_level_entries_follow_the_creature` (Lv 5 Tidepup: `Moves...` and `Train...` present, `Grow` absent, no `Held item...` without a held item or bag item, no Previous/Next with one creature; Lv 16 Tidepup: `Grow` first; two creatures: `Previous creature` and `Next creature` before `Back`; `Held item...` appears once the bag holds a held item or the creature holds one); `test_title_shows_name_level_and_position` (`"Tidepup  Lv 5  (1 / 2)"`, no position with one creature); `test_card_shows_the_creature_and_follows_the switch` (`card().header_text()` follows `Next creature`); `test_info_block_lines` (`page_text()` contains "XP to next level: N" and "Bond: 0" on the first line, "Passive: " line, "Held item: none"); `test_max_level_line` (`"Max level"`); `test_passive_switch_entry_and_greyed_line` (move the existing `test_summary_shows_passives_and_switches` and `test_summary_locked_hint`, reading the greyed line from `_texts`, the entry `Use Finisher`); `test_left_right_and_shoulders_switch_creature_on_top_level` (Left/Right, `next_creature`, `prev_creature`; also from a focused button); `test_left_right_ignored_in_a_sub_list` (`show_mode("train")`, press `ui_right`, the title still names the first creature); `test_one_creature_left_right_do_nothing`; `test_every_mode_fits_the_screen` (all four modes with a Lv 14 and a Lv 5 creature, `ScreenFit.check` with `allow_scroll` true only if the layout truly needs it, preferring false); `test_summary_reads_the_bag_of_the_save_it_is_given` (adapt: `show_mode("train")`).
- [ ] **Step 2: Run** `tests/world/test_summary_screen.gd`; Expected: the new tests FAIL (old API gone or absent).
- [ ] **Step 3: Implement** the new `SummaryScreen`: `run` builds a `CreatureCard`, calls `screen.set_side(card)` before `parent.add_child(screen)`; `_ready` calls `super()`, sets `menu.button_width = COLUMN_WIDTH`, keeps `menu.linear_focus = true`; `_loop` renders per `mode` (title from `_title.text`, info via `_body.text`/`_extra`: reuse the affinity grid and greyed passive line code, affinity bars in a 2x2 grid with 90px bars), calls `card.show_creature(db, c)` every iteration, builds the top-level options in the order in Global Constraints, and `_input` handles `ui_left`/`ui_right`/`prev_creature`/`next_creature` only when `mode == "top"` and not `_busy`. Entries `Moves...`, `Train...` and `Held item...` set the mode (with `_last` set so focus returns to them on Back). Sub-list modes may be stubbed to a single `Back` in this task (their content lands in Task 3).
- [ ] **Step 4: Run** the suite; Expected: the Task 2 tests PASS (tests for sub-list content and actions still to be written in Tasks 3-4).

### Task 3: Moves, Train and Held item sub-lists

**Files:**
- Modify: `game/progress/summary_screen.gd`
- Test: `tests/world/test_summary_screen.gd`

**Interfaces:**
- Consumes: `show_mode`, `mode`, `card()` (Task 2).

- [ ] **Step 1: Write failing tests** (adapt the existing ones to enter through the top-level entries): `test_moves_list_shows_equipped_and_empty_slots` (body contains "Equipped:", `LearnMoveScreen.move_line` per move and "- empty -"); `test_swap_pool_move_into_slot` and `test_equipping_a_pool_move_is_not_worded_as_learning` (via `Moves...`); `test_moves_with_a_full_pool_fits`; `test_train_plus_one_updates_points_and_card` (`Train...` -> `+1 Physical Attack`; `c.trained("patk") == 1`, body "Points to spend: 8", the card's radar value for patk equals `c.stat`); `test_train_refused_at_cap_shows_reason`; `test_train_refused_with_no_points` (notice "No points left to spend."); `test_focus_stays_on_the_picked_row_after_training`; `test_down_and_up_reach_every_option_in_the_train_list` (single column now: Down visits every enabled button in order); the three Reset Seed tests (`_from_summary`, `_no_keeps_points`, `_refund_of_one_point_is_singular`) entering via `Train...`; `test_held_item_list_by_state` (nothing held and bag has an item: `Give held item`; holding one and bag has another: `Swap held item` and `Take back`; holding one, bag empty: `Take back` only); `test_give_swap_take_conserve_items`, `test_give_back_out_changes_nothing`, `test_unknown_held_id_shows_a_fallback` (fits, `Take back` returns the id to the bag), `test_held_item_works_for_a_fainted_creature`; `test_back_from_a_sub_list_returns_to_top_with_the_entry_focused` (focus text is `Moves...` / `Train...` / `Held item...`).
- [ ] **Step 2: Run** the suite; Expected: the new/adapted tests FAIL.
- [ ] **Step 3: Implement** the three modes in `_loop` using the existing helpers (`LearnMoveScreen.move_line`, `Training.available/train`, `DataSchemas.TRAINABLE_STATS`, `STAT_NAMES`, `_held`, `_bag_held`, `ResetSeedPrompt`): reuse `_act`, `_train` and `_held` bodies; after any action stay in the same sub-list; `Back` sets `mode = "top"` (and `_last` to the entry that opened it).
- [ ] **Step 4: Run** the suite; Expected: PASS.

### Task 4: Remaining flows, edge cases, other suites, tour, docs

**Files:**
- Modify: `tests/game/test_screens_smoke.gd` (Summary opens; no tab references), `tests/world/test_party_screen.gd` (`test_summary_opens_from_row`, the big-party Summary stepping, `Back`), `.claude/skills/run-godot-monster-catching-game/tours/progress.gd` (Summary steps ~lines 102-130: `p10_summary_top`, `Moves...` -> `p11_summary_moves` -> `Back`, `Train...` -> `p12_summary_training` -> `+1 Speed` -> `p13_trained_speed` -> `Back`; replace the `tab` expectations with menu-flow ones), `.claude/skills/run-godot-monster-catching-game/tours/party.gd` and `held.gd` if they use `tab` or tab keys, `.superpowers/HANDOFF.md`, `documentation/specs/2026-11-06-m5c-summary-redesign-design.md` (Status: Implemented), `documentation/specs/2026-11-05-roadmap-m5-m8.md` if it tracks status
- Test: `tests/world/test_summary_screen.gd`, `tests/world/test_party_screen.gd`, `tests/game/test_screens_smoke.gd`

- [ ] **Step 1: Write/adapt failing tests**: `test_grow_from_summary` (top-level `Grow`; after growing the entry is gone); `test_summary_of_a_stored_creature_with_odd_passives` (unknown rolled id, empty passive, `Next creature`); `test_summary_fits_with_a_long_item_name_and_description` and `test_every_stat_trained_and_marked_fits` (Lv 99, all 30s, held `test_long`, one bag item; `ScreenFit.check` in `top`, `train`, `held` modes); `test_big_party_summary_steps_through_everyone` (12 creatures, title name sequence as today); `test_prompts_ignore_left_right` (open `Reset Seed` prompt or Learn Move from the sub-list; press `ui_right`; the creature doesn't change); adapt the party and smoke tests to the new labels (a creature's Summary opens, title contains the name, `Back` closes).
- [ ] **Step 2: Run** `tests/world` and `tests/game`; Expected: FAIL where flows/labels differ.
- [ ] **Step 3: Implement** any remaining behaviour the tests expose in `summary_screen.gd`, and update the tours (`progress.gd`, plus `party.gd`/`held.gd` where they use tabs).
- [ ] **Step 4: Run** `tests/world`, `tests/game`; Expected: PASS.
- [ ] **Step 5: Real window.** Run `--mode=progress`, `--mode=held` and `--mode=party` tours; Read the Summary screenshots: card fully visible left, right column inside the screen, nothing clipped, long text ellipsised, the radar changing after +1 Speed. Fix layout (column width, affinity grid) if anything clips.
- [ ] **Step 6: Docs and handoff**: edits listed under Files (the handoff paragraph says the Summary is card-left with Moves.../Train.../Held item... sub-lists, tabs removed, `SummaryScreen.tab` gone, `ProgressScreen.set_side`; "What's next": 5d Box and Party). Run `bash scripts/check.sh`; Expected: final line "All checks passed."
- [ ] **Step 7: Give the user** a commit message in the handoff format; do not commit.
