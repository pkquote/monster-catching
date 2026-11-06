# M5a Housekeeping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings Controls tab scroll with focus, show a summary pane for the focused bag item, move effect-to-text code into shared core code, and re-audit and re-lay-out the compendium.

**Architecture:** `EffectText` (pure core code) holds the effect/trigger/`when` wording; the compendium builder (a pure class split out of the tool script) and the bag pane both use it. The bag pane is driven by `CommandMenu.hovered` hints and a pure `FieldItems.usability`. An `ItemIconSlot` control is the placeholder icon. The compendium builder is reordered and de-duplicated, guarded by a byte-identical refactor check and a layout test.

**Tech Stack:** Godot 4.7.2 GDScript, gdUnit4, the real-window run skill for tours.

**Spec:** [documentation/specs/2026-11-05-m5a-housekeeping-design.md](../specs/2026-11-05-m5a-housekeeping-design.md)

## Global Constraints

- **Never `git commit`, stage or stash.** The user authors every commit. Tasks end with "leave uncommitted"; the final message includes a suggested commit message (title, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Type every local variable explicitly (`var x: int = ...`), including loop variables and lambda parameters.
- Run only one Godot process at a time; never touch the user's own Godot editor. After adding a `class_name`, run `godot --headless --path . --import` once.
- `bash scripts/check.sh` must end "All checks passed."
- `core/` stays pure (RefCounted only, no nodes or autoloads). Tests under `tests/data`, `tests/progress`, `tests/battle` use LF; match each neighbouring file's line endings elsewhere.
- Screens are 640x360; the bag info pane is 404 wide (`SideMenu._page`); all screens stay fully keyboard/gamepad-navigable.
- Compendium section order (spec §5.2): Rules and Balance, Types, Affinities, Statuses, Field States, Reactions, Passives, Held items, Moves, Items, Creatures, Tamers, Encounters. The generator loads `data/` only (no `tp_` ids).
- Do not change `data/` content or `data/balance.json`.

## Review Focus

- A bag item with a very long description, an unknown id, or a count of 0 must not overflow or break the pane. Test: Task 4.
- The pane must reset to "Pick an item." when the cursor lands on Back, and must not keep stale text after the bag closes. Test: Task 4.
- An effect op with no wording must fail a test, not print an empty string in the compendium or the bag. Test: Task 2.
- The refactor must not change the compendium output. Test: Task 2 (byte-identical check).
- Reordering the compendium must not break links from other docs. Test: Task 5 (link grep).

---

### Task 1: Controls tab follows focus

**Files:**
- Modify: `game/menus/settings_menu.gd` (`_tab`)
- Test: `tests/game/test_settings_scroll.gd` (create)

**Interfaces:** none produced. Consumes `SettingsMenu.tabs`, `SettingsMenu.bind_buttons`.

- [ ] **Step 1: Write the failing test** `test_last_controls_binding_scrolls_into_view` (open the Settings scene the way `tests/game/test_screens_smoke.gd` does, set `tabs.current_tab` to the Controls tab, take the last action's keyboard `Button` from `bind_buttons`, call `grab_focus()`, await two frames, then find that tab's `ScrollContainer` and assert `scroll_vertical > 0` and that the button's global rect is inside the scroll container's global rect). Add `test_every_tab_scroll_follows_focus` (every tab's `ScrollContainer.follow_focus` is true) and `test_arrow_down_from_tab_bar_reaches_a_binding` (push `ui_down` from the focused tab bar through `Input.parse_input_event` and assert the focus owner is a descendant of the Controls tab).
- [ ] **Step 2: Run** `"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/game/test_settings_scroll.gd --ignoreHeadlessMode -c`. Expected: FAIL.
- [ ] **Step 3: Implement** `scroll.follow_focus = true` in `_tab()`. If the third test still fails, set focus neighbours on the first control so Down from the tab bar enters the tab, and Up from the first control returns to the tab bar.
- [ ] **Step 4: Run** the suite and `tests/game/test_screens_smoke.gd`. Expected: PASS. Leave uncommitted.

### Task 2: Shared effect text and a compendium builder class

**Files:**
- Create: `core/data/effect_text.gd`, `tools/compendium_builder.gd`
- Modify: `tools/generate_compendium.gd` (becomes a thin runner)
- Test: `tests/data/test_effect_text.gd` (create)

**Interfaces:**
- Produces (`class_name EffectText extends RefCounted`, all static): `effect(db: Database, e: Dictionary) -> String`, `effects(db: Database, effects: Array) -> String` (returns "—" for an empty list, as the compendium prints today), `when(db: Database, w: Dictionary) -> String`, `triggers(db: Database, triggers: Array) -> String`; constants `SIDE_LABELS`, `TARGET_LABELS`, `TRIGGER_LABELS`, `STAT_LABELS` moved unchanged.
- Produces (`class_name CompendiumBuilder extends RefCounted` in `tools/`): `static func build(db: Database) -> String` returning the whole document text (what the tool writes today, trailing newline included).
- Consumes: the private functions currently in `tools/generate_compendium.gd` (`_effect`, `_effects`, `_when`, `_triggers`, `_pct`, `_num`, `_signed`, `_state_name`, the label tables).

- [ ] **Step 1: Capture the baseline.** Run `godot --headless --path . --script res://tools/generate_compendium.gd`, copy `documentation/compendium.md` to `<scratchpad>/compendium-before.md` and record its checksum.
- [ ] **Step 2: Write the failing tests** `tests/data/test_effect_text.gd` using the real database (`DataLoader.load_database("res://data")`): `test_every_effect_op_has_wording` (build one minimal valid effect dictionary for every key of `DataSchemas.EFFECT_OPS`, using the lowest legal parameters from the schema, and assert `EffectText.effect` is non-empty and does not contain the raw op name for any op), `test_known_sentences` (exact strings for `heal` 0.33, `restore_energy` 0.5, `capture` mult 0.8 with a field bonus, `apply_status` with chance, `type_power`, `incoming_type_mod`, `field_boost`; copy the expected text from the current compendium output so the refactor is pinned), `test_when_conditions` (`hp_below`, `underdog`, and the other `DataSchemas.WHEN` fields), `test_triggers_text` (a hit trigger with `contact`, `chance` and a `when`; an enter trigger), `test_empty_list_is_dash`.
- [ ] **Step 3: Run** the suite. Expected: FAIL (class missing).
- [ ] **Step 4: Implement** `EffectText` by moving the code unchanged (taking `db` as a parameter instead of using the tool's member). Create `CompendiumBuilder` holding the rest of the generator (all section functions, `_w`, `_section`) as an instance with a `db` member and `static func build(db)`; it calls `EffectText`. `tools/generate_compendium.gd` keeps only loading the database, calling `CompendiumBuilder.build`, writing the file and printing "Wrote ...".
- [ ] **Step 5: Prove the refactor is output-neutral.** Regenerate; `cmp documentation/compendium.md <scratchpad>/compendium-before.md` must report identical. Add `test_builder_output_is_deterministic` (calling `CompendiumBuilder.build` twice on the same database gives the same string) to `tests/data/test_compendium.gd` (created in Task 5; for now put it in `test_effect_text.gd` and move it then).
- [ ] **Step 6: Run** the suite and `bash scripts/check.sh`. Expected: PASS. Leave uncommitted.

### Task 3: Item icon slot and bag usability rules

**Files:**
- Create: `game/ui/item_icon_slot.gd`
- Modify: `core/progress/field_items.gd`
- Test: `tests/progress/test_field_items.gd` (extend), `tests/game/test_item_icon_slot.gd` (create)

**Interfaces:**
- Produces: `class_name ItemIconSlot extends Control` with `var category: String`, `var icon_size: int = 48`, `func configure(p_category: String, p_icon_size: int = 48) -> void` (sets the minimum size and redraws), constants `CATEGORY_COLORS: Dictionary` (capture, heal, battle, key, training, held; plus an `"unknown"` fallback) and a static `initial_for(category: String) -> String`; `static func FieldItems.usability(db: Database, save: SaveGame, item_id: String) -> Dictionary` returning `{ok: bool, reason: String}` per spec §3.2.
- Consumes: `FieldItems.can_use`, `Training.spent`, `CreatureInstance` HP/energy accessors.

- [ ] **Step 1: Write failing tests.** `FieldItems.usability`: one case per row of spec §3.2 (reason text exact): unknown id; `held`; `capture`; `battle`; `key`; a `heal` item with a hurt party creature (ok true, "Usable now."); the same item when all creatures are full or fainted (ok false, "No one needs it right now."); a `restore_energy` item with a creature below max energy and with none; Reset Seed with and without spent points; an item the category allows but `can_use` rejects ("Can't be used here."). `ItemIconSlot`: `configure("heal", 32)` sets `custom_minimum_size` to 32x32; every category in the item schema has a distinct colour; unknown category uses the fallback; `initial_for("heal")` is "H".
- [ ] **Step 2: Run** both suites. Expected: FAIL.
- [ ] **Step 3: Implement** both. `ItemIconSlot` overrides `_draw` with a rounded `StyleBoxFlat`-style fill (or `draw_rect` with corner via a `StyleBoxFlat.draw`) and the initial as text in the theme font; colours are constants chosen to be readable on `UIKit.PANEL`.
- [ ] **Step 4: Run** the suites. Expected: PASS. Leave uncommitted.

### Task 4: Bag summary pane

**Files:**
- Modify: `game/overworld/ui/pause_menu.gd` (`_bag`), `game/overworld/ui/side_menu.gd` (only if a richer page API is needed)
- Create: `game/overworld/ui/bag_summary.gd`
- Test: `tests/game/test_bag_summary.gd` (create)

**Interfaces:**
- Produces: `class_name BagSummary extends VBoxContainer` with `func show_item(db: Database, save: SaveGame, item_id: String) -> void`, `func show_empty() -> void` (text "Pick an item."), and read accessors `title_text() -> String`, `body_text() -> String`, `icon_category() -> String` for tests. Layout: `ItemIconSlot` (48) beside name, category, "Owned: N", then price, description, the Effect lines (`EffectText.effects`), the "Usable now?" line from `FieldItems.usability`.
- Consumes: `ItemIconSlot` and `FieldItems.usability` (Task 3), `EffectText` (Task 2), `CommandMenu.hovered`, `SideMenu` page area (404x344).

- [ ] **Step 1: Write failing tests.** `BagSummary`: `show_item` for a heal item shows its name, "Owned: N", price, description, the exact effect sentence from `EffectText`, and "Usable now." when a creature is hurt; for a held item, the held effect text and "Give it from the Summary."; an unknown id shows "Unknown item."; `show_empty` shows "Pick an item."; the longest description among all real items fits inside 404x344 when laid out (use `tests/helpers/screen_fit.gd`). `PauseMenu` bag flow: with a populated bag open the bag, move focus between options (focus each button in turn) and assert `page_text()`/the summary changes to match; focus on Back shows "Pick an item."; closing the bag hides the summary; the existing choose-item flow (use on who, can't-use message) still works (reuse the existing pause-menu tests).
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Implement** `BagSummary` and hook it up: each bag option gets `hint: item_id`; connect `menu.hovered` to a handler that calls `show_item` or `show_empty` (disconnect when the list closes, as the shop does); mount the summary in the left page area in place of the plain text label while the bag is open. Keep the unusable-item message behaviour.
- [ ] **Step 4: Run** the suite, `tests/game`, and the existing bag tests. Expected: PASS.
- [ ] **Step 5: Real-window check** (run-godot skill, `--mode=overworld` or a new `--mode=bag` tour in `.claude/skills/run-godot-monster-catching-game/tours/`): open the Menu, then the Bag, focus three different items (a heal item, a held item, a capture item) and screenshot each; confirm nothing is clipped. Leave uncommitted.

### Task 5: Compendium re-layout and audit

**Files:**
- Modify: `tools/compendium_builder.gd`
- Test: `tests/data/test_compendium.gd` (create; also holds the determinism test from Task 2)

**Interfaces:** Consumes `CompendiumBuilder.build(db)` (Task 2).

- [ ] **Step 1: Write failing tests** in `tests/data/test_compendium.gd` (real `data/` database): `test_sections_appear_once_in_the_agreed_order` (the `## ` headings equal, in order: Rules and Balance, Types, Affinities, Statuses, Field States, Reactions, Passives, Held items, Moves, Items, Creatures, Tamers, Encounters); `test_contents_table_lists_every_section_with_a_matching_anchor` (each contents row links to an anchor equal to the lower-cased, hyphenated heading and the heading exists); `test_items_table_has_no_held_items` and `test_every_held_item_is_in_held_items` (use `ItemDef.category`); `test_no_test_pack_ids` (no `tp_` and no `data_testpack` text); `test_ends_with_one_newline`; `test_counts_match_database` (each contents row count equals `db.count` for its category, with Items counting non-held items and Held items counting held items).
- [ ] **Step 2: Run** the suite. Expected: FAIL (order, duplicate held items, missing contents row).
- [ ] **Step 3: Implement** in the builder: reorder `_build`, make `_items` skip `held` and show only non-held items, add the Held items and Rules and Balance rows to the contents table with correct anchors and counts, rename the Balance section to "Rules and Balance" and move it first, and update every in-document link that pointed at a moved anchor. Keep each section's content otherwise unchanged.
- [ ] **Step 4: Systems checklist (spec §5.3).** Regenerate and read `documentation/compendium.md` against each listed system: held items (use kinds, aura scope, overworld effects), passives (rolled and Affinity, triggers, `when`, chance, contact), growth tiers (markers and multipliers), "Two foes" target and the spread table, `party_size` and level cap, move priority and energy cost, Underdog numbers, Lv 99 stats, no `tp_` ids. For each gap, fix the builder and add a test line to `test_compendium.gd`; for anything intentionally left, list it in the task report with the reason.
- [ ] **Step 5: Link check.** `grep -rn "compendium.md#" documentation README.md .superpowers` and fix any link to an anchor that moved or vanished.
- [ ] **Step 6: Run** the suite and `bash scripts/check.sh`. Expected: PASS and the compendium regenerates. Leave uncommitted.

### Task 6: Docs and final check

**Files:** Modify `documentation/battle-engine.md` (only if it mentions the compendium tool), `README.md` (compendium and bag wording if it lists menus), `.superpowers/HANDOFF.md` (a 5a section), the 5a spec status line to "Implemented (plan: ../plans/2026-11-05-m5a-housekeeping.md)", and the roadmap's 5a row note.

- [ ] **Step 1:** Update the docs above; do not rewrite other HANDOFF sections.
- [ ] **Step 2: Full check:** `bash scripts/check.sh`. Expected: ends "All checks passed." Report the suggested commit message (title, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`). Leave everything uncommitted.

---

## Self-review

- Spec coverage: §2 Controls → Task 1; §3 bag (behaviour, usability, icon slot) → Tasks 3 and 4; §4 shared effect text and the refactor proof → Task 2; §5 compendium layout, systems checklist and tests → Task 5; §6 testing and tours → Tasks 1–5; §8 risks (byte-identical, pane fit, link grep) → Tasks 2, 4, 5.
- Names are consistent across tasks (`EffectText`, `CompendiumBuilder`, `ItemIconSlot`, `FieldItems.usability`, `BagSummary`).
- Order: Tasks 1 and 3 are independent; 2 before 4 and 5; 3 before 4.
