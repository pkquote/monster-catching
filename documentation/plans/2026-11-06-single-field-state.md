# One Field State Per Side Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each side holds one field state by default (cap 1, still tunable), shown with the player's view back at the bottom-right of the battle stage.

**Architecture:** The existing cap logic in `FieldRules._apply` already pushes out the oldest state, so the rule change is mostly `data/balance.json` (3 → 1) plus renaming the removal reason to `replaced`. A validator rule keeps reactions from leaving two states, the tactician AI learns to value overwriting, and `FieldView` / the battle scene drop the stacked top-left column.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit-style suites (`tests/`), `bash scripts/check.sh`.

**Spec:** `documentation/specs/2026-11-06-single-field-state-design.md`

## Global Constraints

- **Never commit, stage or stash.** The user writes every commit. Skip any "commit" step; at the end give the user a commit message in the handoff format (`{{title}}`, bullet points, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- `balance.max_field_states` stays in the schema, `BalanceDef` and docs; only `data/balance.json` changes (3 → 1). `tests/helpers/fixture_db.gd` keeps its cap of 3; new cap-1 tests use `FixtureDB.build({"max_field_states": 1})`.
- Overwriting is unconditional; re-applying the same state still stacks and refreshes.
- `field_removed` reason `pushed_out` is renamed `replaced` everywhere (engine, log text, docs).
- In tour files `d` is untyped, so use `=` not `:=`. Don't run two Godot processes at once.
- Godot console: `/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.

## Review Focus

- Applying a state with a cap of 1 and no existing state: just lands, no `replaced` event.
- A reaction that consumes only the incoming state leaves the existing one (soaked + charged keeps soaked); one that consumes both leaves the side empty (steam).
- The same state re-applied at cap 1 stacks, with no `replaced` event.
- Cap 2 still holds two states (the tuning option isn't broken).
- Foe's and player's views with the longest effect text (radiant, haunted) plus the Underdog badge fit the stage without overlapping creatures or the command panel.

---

### Task 1: Rule change, event rename, log text

**Files:**
- Modify: `data/balance.json:56` (`max_field_states` 3 → 1)
- Modify: `core/battle/field_rules.gd:53` (reason `"replaced"`)
- Modify: `game/battle/battle_text.gd:73` (`"replaced"` → "The %s on %s was replaced.")
- Modify: `tests/battle/test_field_reactions.gd` (rename/extend `test_fourth_state_pushes_out_oldest`, line 70)
- Test: `tests/battle/test_field_reactions.gd`, a shipped-data assertion in `tests/data/test_balance_party.gd`

**Interfaces:**
- Produces: `field_removed` events with `reason: "replaced"` (consumed by Task 4's docs and any UI using the reason).

- [ ] **Step 1: Write failing tests** in `tests/battle/test_field_reactions.gd`, each building the engine with `FixtureDB.build({"max_field_states": 1})` and the existing helpers in that file:
  - `test_new_state_replaces_the_old_one_at_cap_one`: apply `soaked` then `scorched` to side 1 (non-reacting pair in the fixture; pick two fixture states with no reaction); assert `field.ids() == ["scorched"]` and exactly one `field_removed` event with `state == "soaked"`, `reason == "replaced"`.
  - `test_first_state_at_cap_one_replaces_nothing`: apply one state; assert no `field_removed` event.
  - `test_same_state_restacks_at_cap_one`: apply the same state twice; assert stacks 2 and no `field_removed`.
  - `test_reaction_keeping_existing_state_at_cap_one`: soaked then charged (conduction); assert ids `["soaked"]`.
  - `test_reaction_consuming_both_empties_the_side_at_cap_one`: scorched then frosted (steam); assert `field.size() == 0`.
  - `test_cap_two_still_holds_two_states`: cap 2, two non-reacting states; assert both present.
  - Rename the existing "fourth state" test's expected reason to `replaced`.
  In `tests/data/test_balance_party.gd` (or the nearest shipped-balance test) add `test_shipped_balance_allows_one_field_state`: `Database` from `data/` has `balance.max_field_states == 1`.
- [ ] **Step 2: Run** `bash scripts/check.sh` or the single suite; expected: the new tests FAIL (reason is `pushed_out`, balance is 3).
- [ ] **Step 3: Implement** the three edits listed under Files.
- [ ] **Step 4: Run** the same suites; expected PASS. Then run the full tests and fix any other suite that assumed 3 states on a shipped-data side (expected: few or none, since most use the fixture db).

### Task 2: Validator rule — a reaction must consume an input

**Files:**
- Modify: `core/data/validator.gd:302-309` (reactions loop)
- Test: `tests/data/test_validator.gd`

**Interfaces:**
- Produces: validator error key `"consumes"` with message "must consume at least one of its inputs".

- [ ] **Step 1: Write failing test** `test_reaction_must_consume_an_input` in `tests/data/test_validator.gd`, mirroring the neighbouring reaction tests: a reaction with `"consumes": []` errors with key `consumes`; one with `"consumes": ["a"]` (a valid input) passes.
- [ ] **Step 2: Run** the suite; expected FAIL.
- [ ] **Step 3: Implement** inside the reactions loop: if `inputs is Array` and `r.get("consumes", [])` is empty, `_err("consumes", ...)`.
- [ ] **Step 4: Run** `tests/data` suites and `tools/validate_data.gd` (via `scripts/check.sh` data step); expected PASS, `Data OK` and `Data+pack OK`. If a test-pack reaction (`data_testpack/`) consumes nothing, change it to consume one input and keep `tests/battle/test_testpack_mechanics.gd` passing.

### Task 3: AI values overwriting

**Files:**
- Modify: `core/battle/ai/battle_ai.gd` (`_setup_value`, the `apply_field_state` branch around line 288–330; new constant near line 22)
- Modify: `_best_follow_up` only if it assumes more than one existing state (it takes `state` already present; confirm no change is needed)
- Test: `tests/battle/test_ai.gd`

**Interfaces:**
- Consumes: `state_benefit(engine, state) -> float` (> 0 helps its holder), `Field.states[0].id` (the oldest, which is what gets pushed out), `balance.max_field_states`.
- Produces: `const REPLACE := 0.2  # x ref, value of knocking out a state the holder (not the caster) cares about`.

- [ ] **Step 1: Write failing tests** in `tests/battle/test_ai.gd` using a cap-1 fixture db and the tactician, comparing scores of the same setup move across two engines:
  - `test_tactician_avoids_overwriting_its_own_buff`: its side holds a helpful state, move applies a different non-reacting helpful state to its own side → scores lower than when the side is empty.
  - `test_tactician_likes_overwriting_its_own_harmful_state`: own side holds a harmful state → scores higher than when empty.
  - `test_tactician_likes_overwriting_an_enemy_buff`: enemy side holds a helpful state, move applies a hostile non-reacting state there → higher than on an empty enemy side.
  - `test_tactician_avoids_overwriting_an_enemy_debuff`: enemy side holds a harmful state → lower than on an empty enemy side.
- [ ] **Step 2: Run** `tests/battle/test_ai.gd`; expected the four FAIL.
- [ ] **Step 3: Implement** in `_setup_value`, after the reaction check (`fired`) and before the existing benefit logic: if `field.size() >= engine.db.balance.max_field_states`, let `lost = state_benefit(engine, field.states[0].id)`. When `s == b.side`: `value -= lost * REPLACE * ref` is wrong in sign for harmful states, so use `value -= REPLACE * ref` if `lost > 0.0`, else `value += REPLACE * ref` if `lost < 0.0`. When `s != b.side`: `value += REPLACE * ref` if `lost > 0.0`, else `value -= REPLACE * ref` if `lost < 0.0`. Then the existing own-buff / enemy-buff / new-state logic runs unchanged (the REPLACE term is added on top).
- [ ] **Step 4: Run** `tests/battle/test_ai.gd`, `test_ai_passives.gd` and `tests/battle/test_testpack_simulations.gd`; expected PASS. If the simulations' 0-draw or exemption-list guards trip, report the numbers rather than loosening the guard.

### Task 4: FieldView and battle scene layout

**Files:**
- Modify: `game/battle/field_view.gd` (label above/below by side, comments)
- Modify: `game/battle/battle_scene.gd:533-545` (remove `field_column`; foe's view at `Vector2(8, 6)`, yours pinned to the stage's bottom-right)
- Modify: `tests/game/test_field_view.gd` (`test_label_sits_under_the_chip_on_both_sides` line 122; `test_three_states_on_both_sides_fit_the_top_left_corner` line 145)
- Modify: `.claude/skills/run-godot-monster-catching-game/tours/battle.gd` steps `b14`/`b15` (lines ~126–170)

**Interfaces:**
- Produces: in `FieldView`, the effect label is added above the chip when `side == 0` and below it when `side == 1`. `FieldView.effect_labels()` unchanged.

- [ ] **Step 1: Update/write failing tests** in `tests/game/test_field_view.gd`:
  - Replace the under-the-chip test with `test_label_is_above_the_chip_for_you_and_below_for_the_foe`: side 0 label `end.y <= chip.y + 0.5`; side 1 label `y >= chip end.y - 0.5`.
  - Replace the three-states-in-a-column test with `test_your_view_fits_the_bottom_right_of_the_stage`: build the view with the scene's anchoring (via a `BattleScene` helper, or the same function the scene calls if extracted as `static func anchor_player_field(f: FieldView, stage_h: int)`), apply `radiant` plus the Underdog badge, and assert the rect is inside the `SCREEN` rect and above `STAGE_H`. Add a matching top-left test for the foe. Keep a test that a cap-2 view with two chips still renders both (`effect_labels().size() == 2`).
- [ ] **Step 2: Run** `tests/game/test_field_view.gd`; expected FAIL.
- [ ] **Step 3: Implement** the label ordering in `FieldView._rebuild`, then in `battle_scene.gd` position the foe's view at `(8, 6)` and yours with its right edge at x=632 and bottom edge at `STAGE_H - 4` (re-pin on `resized`, since the view shrinks and grows). Remove `field_column`. Update the class comment in `field_view.gd`.
- [ ] **Step 4: Run** `tests/game/test_field_view.gd` and `tests/game/test_screens_smoke.gd`; expected PASS.
- [ ] **Step 5: Update the tour** (`tours/battle.gd`): `b14`/`b15` apply one state per side through the view (use the longest-text state), plus a replacement step calling `fields[0].removed(...)` then `applied(...)`; adjust the `effect_labels().size()` expectations to 1. Run `--mode=battle` through the `run-godot-monster-catching-game` skill and look at `b13`–`b15`: no overlap with creatures, the command panel or the message line, in 1v1, 3v1 and 3v3.

### Task 5: Docs, compendium, handoff, full verification

**Files:**
- Modify: `documentation/battle-engine.md:131` (cap text, now "Each side holds up to `max_field_states` states (shipped: 1). A new state that doesn't react replaces the oldest."), `:337` (`field_removed` reasons: `pushed_out` → `replaced`), AI section lines ~276–288 (overwrite scoring), and the "no chains" bullet if needed
- Modify: `documentation/specs/2026-11-03-monster-rpg-design.md:61` (default 3 → 1)
- Modify: `documentation/specs/2026-11-06-single-field-state-design.md` (Status: Implemented)
- Modify: `.superpowers/HANDOFF.md` (replace the uncommitted "Battle field-state labels" paragraph's layout sentence; add this change)
- Regenerate: `documentation/compendium.md` (its text already prints the cap; it follows from Task 1)

- [ ] **Step 1: Make the doc edits** above.
- [ ] **Step 2: Run** `bash scripts/check.sh`; expected final line "All checks passed." (This regenerates the compendium; confirm `git diff documentation/compendium.md` only shows the cap change.)
- [ ] **Step 3: Run the simulations** (`tools/simulate.gd`, with `--pack=1` and `--pack=0`, a few seeds) and report win rates and reaction counts before (git stash is forbidden: use the numbers from `documentation/battle-engine.md` if present, otherwise report after-only) so the user can judge the balance shift.
- [ ] **Step 4: Give the user** a commit message in the handoff format; do not commit.
