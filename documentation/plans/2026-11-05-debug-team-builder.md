# Debug Team Builder, Larger Parties and Battle Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the F1 Custom battle page with a from-scratch team builder (both sides, per-creature species/level/moves/held item/passive, bag editor, no save writes), raise the party-size ceiling to 12 under `balance.party_size`, and add rigorous headless battle-engine tests.

**Architecture:** A pure `CreatureSpec` (core/) describes one slot and builds a `CreatureInstance`; `BattleLauncher.exhibition_setup` turns two spec lists into a `BattleSetup` flagged `exhibition`, which the battle scene and overworld flow treat as "write nothing". The debug page and slot editor are UI over those. The party ceiling is one constant read by the schema. New test suites exercise the engine through `FixtureDB`.

**Tech Stack:** Godot 4.7.2 GDScript, gdUnit4 (`tests/`), JSON data validated by `core/data/schemas.gd` + `validator.gd`.

**Spec:** [documentation/specs/2026-11-05-debug-team-builder-design.md](../specs/2026-11-05-debug-team-builder-design.md)

## Global Constraints

- **Never `git commit`, stage or stash.** The user authors every commit. Tasks end with "leave uncommitted"; the final message to the user includes a suggested commit message (title, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Type every local variable explicitly (`var x: int = ...`); untyped inferred locals can hang headless Godot. In `tours/*.gd` the untyped `d` means `=` not `:=`.
- Run only one Godot process at a time; never touch the user's own editor/game processes. Test runs share save files.
- `bash scripts/check.sh` must end "All checks passed."
- Layers: `core/` pure (RefCounted, no nodes/autoloads); `game/` scenes/UI; tests under `tests/`.
- Read `balance.party_size`/`MAX_SIDE` rather than hard-coding 6 or 3. Ceiling `BalanceDef.MAX_PARTY_SIZE = 12`; at most `BattleLauncher.MAX_SIDE = 3` on the field per side; a swap is one action (existing, priority 6).
- Custom battles are exhibitions: no change to party, bag, money, flags, storage, no autosave, no defeat rules.
- Moves: any move in the game, labelled learned / learns later / can't learn. Passives: any, labelled rolls / affinity / not normal. Held items: any, no warning labels.

## Review Focus

- A custom battle where one side has a single creature and the other the maximum (1v3, 12-creature bench) must start and finish. Test: Task 5/6.
- Empty or duplicate move lists, an unknown species/move/passive/item id, or a level of 0 or 500 must be rejected or clamped, never crash. Test: Task 2.
- A save whose party is larger than a lowered `party_size` must load, display and battle normally. Test: Task 1.
- Closing the F1 menu mid-pick (Esc/F1) must not start a half-built battle or lose the save. Test: Task 4.
- A wild exhibition where the player captures a creature must leave `save.party`/`storage` untouched. Test: Task 3.

---

### Task 1: Party-size ceiling

**Files:**
- Modify: `core/data/defs/balance_def.gd`, `core/data/schemas.gd:335`
- Test: `tests/data/test_balance_party.gd` (create)

**Interfaces:**
- Produces: `BalanceDef.MAX_PARTY_SIZE: int = 12` (const). Schema accepts `party_size` 1..`BalanceDef.MAX_PARTY_SIZE`.

- [ ] **Step 1: Write failing tests** in `tests/data/test_balance_party.gd` (suite extends `GdUnitTestSuite`, builds `FixtureDB.raw()` with `balance.party_size` set per test and calls `DataValidator.validate`): `test_accepts_1_through_12` (1, 6, 12 → no errors), `test_rejects_0_and_13` (errors non-empty and mention `party_size`), `test_team_add_respects_changed_size` (db built with `party_size` 8: a save with 7 members accepts one more via `Team`/`BattleLauncher.add_to_party`, the next goes to `storage`), `test_oversized_party_in_save_is_kept` (db `party_size` 3, a save with 5 party members: `add_to_party` sends a new creature to storage, nothing is removed).
- [ ] **Step 2: Run** `bash scripts/check.sh` is slow; run only the suite: `"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/data/test_balance_party.gd --ignoreHeadlessMode -c`. Expected: FAIL on the 7–12 and 13 cases.
- [ ] **Step 3: Implement** the const in `BalanceDef` and set `"party_size": {"t": "int", "min": 1, "max": BalanceDef.MAX_PARTY_SIZE}` in `schemas.gd`. Confirm `tools/validate_data.gd` uses the schema (no separate limit); if it has one, point it at the const.
- [ ] **Step 4: Run** the suite again. Expected: PASS. Leave uncommitted.

### Task 2: `CreatureSpec`

**Files:**
- Create: `core/battle/creature_spec.gd`
- Test: `tests/battle/test_creature_spec.gd` (create)

**Interfaces:**
- Produces (`class_name CreatureSpec extends RefCounted`):
  - vars `species: String`, `level: int`, `moves: PackedStringArray`, `held_item: String` (""), `passive: String` ("" = none), `moves_edited: bool`
  - `static func natural(db: Database, species: String, level: int, rng: RandomNumberGenerator) -> CreatureSpec` (natural moves, `Passives.roll`, no item)
  - `static func from_instance(c: CreatureInstance) -> CreatureSpec` (`moves_edited` false)
  - `func to_instance(db: Database, rng: RandomNumberGenerator) -> CreatureInstance` (level clamped 1..`level_cap`; uses `CreatureInstance.create` with `moves`; sets `held_item`, `passive`)
  - `func natural_moves(db: Database) -> PackedStringArray` (identical to what `CreatureInstance.create` picks)
  - `func retarget(db: Database, new_species: String, new_level: int) -> void` (replaces moves with natural ones unless `moves_edited`)
  - `func validate(db: Database) -> PackedStringArray` (errors: unknown species/move/passive/held item, empty moves, duplicate moves, more than `balance.max_moves`, non-held `held_item`)
  - `const LEARNED := "learned"`, `LEARNS_LATER := "later"`, `NOT_LEARNABLE := "no"`; `static func move_standing(db, species, level, move_id) -> Dictionary` (`{state, level}`; `level` is the learn level or 0)
  - `const ROLLS := "rolls"`, `AFFINITY := "affinity"`, `NOT_NORMAL := "not_normal"`; `static func passive_standing(db, species, passive_id) -> String`
  - `static func move_label(db, species, level, move_id) -> String` → `"Name ✓ Lv N"`, `"Name Lv N (later)"`, `"Name ✗ can't learn"`; `static func passive_label(db, species, passive_id) -> String` → `"Name ★ rolls"`, `"Name (Affinity)"`, `"Name ✗ not normal"`; `func summary(db) -> String` → `"Natural at Lv N: A, B, C, D"`.

- [ ] **Step 1: Write failing tests**: natural moves equal `FixtureDB.make(...).moves` for levels 1, 5, 40; `move_standing` returns each of the three states for a fixture species with a known learnset (including a move learned exactly at the current level = LEARNED, and one level above = LEARNS_LATER with its level); `passive_standing` for a listed passive, an Affinity passive and an unrelated passive; `validate` rejects empty moves, duplicate moves, 5 moves, unknown ids, a non-held item as `held_item` and accepts a valid spec; `to_instance` clamps levels 0 and 500 to 1 and `level_cap`; `retarget` keeps hand-edited moves (`moves_edited` true) and resets otherwise; `from_instance(to_instance)` round-trips species, level, moves, item, passive; label strings match the three formats above exactly.
- [ ] **Step 2: Run** the suite. Expected: FAIL (class missing).
- [ ] **Step 3: Implement** `creature_spec.gd` against the interface. Learn level comes from `CreatureDef.learnset`; Affinity passives from `affinity_passives.values()`.
- [ ] **Step 4: Run** the suite. Expected: PASS. Leave uncommitted.

### Task 3: Exhibition battles

**Files:**
- Modify: `core/battle/battle_setup.gd`, `game/battle/battle_launcher.gd` (replace `custom_setup`), `game/battle/battle_scene.gd:_results`, `game/overworld/battle_flow.gd:run_battle`
- Test: `tests/game/test_battle_launcher.gd` (replace the two `custom_setup` tests), `tests/game/test_exhibition.gd` (create)

**Interfaces:**
- Consumes: `CreatureSpec` (Task 2).
- Produces: `BattleSetup.exhibition: bool = false`;
  `static func BattleLauncher.exhibition_setup(db: Database, mine: Array, mine_field: int, foes: Array, foe_field: int, wild: bool, bag: Dictionary, rng: RandomNumberGenerator) -> BattleSetup` where `mine`/`foes` are `Array[CreatureSpec]` (non-empty, each at most `db.balance.party_size`; wild foes clamped to `MAX_SIDE`); field counts clamped to 1..min(`MAX_SIDE`, team size). Side 0 uses `bag`; side 1 is `"basic"` (wild) or `"tactician"` (tamer, `foe_name = "Sparring Partner"`), `auto_replace` true, `exhibition = true`. Also `static func BattleLauncher.DEFAULT_BAG` is `TEST_BAG` (no new constant needed).

- [ ] **Step 1: Write failing tests.** `test_launcher`: formats 1v1, 2v2, 2v3, 3v3, 1v3 with teams larger than the field produce correct `field_count`, `party.size()`, bench sizes (party 12 vs field 3), wild/tamer AI and names, `exhibition` true, wild foe team clamped to 3. `test_exhibition`: after a finished exhibition run through `BattleScene` with `defeat_rules` (use `WorldTest`/the pattern in `tests/game/test_battle_scene_smoke.gd`) the `SaveGame` serialised before and after is identical (party, inventory, money, flags, storage); and a wild exhibition where a capture item is used leaves `party` and `storage` unchanged.
- [ ] **Step 2: Run** both suites. Expected: FAIL.
- [ ] **Step 3: Implement.** Add the flag; `exhibition_setup` per the Interface (instances from `spec.to_instance(db, rng)`); in `battle_scene._results` skip `apply_results` when `setup.exhibition` and build the summary with `BattleSummary.of(...)` from `engine.result()`, and show "Exhibition — nothing was saved." on the results panel; in `battle_flow.run_battle` return `summary.is_win()` immediately after the scene finishes when `setup.exhibition` (no `after_battle`, no autosave, no progress screens). Remove `custom_setup` and `party_level`'s only-caller assumptions only if unused (keep `party_level`; the page uses it).
- [ ] **Step 4: Run** both suites. Expected: PASS. Leave uncommitted.

### Task 4: Builder page, slot editor and bag editor

**Files:**
- Modify: `game/debug/pages/debug_custom_battle_page.gd` (rewrite)
- Create: `game/debug/pages/debug_slot_editor.gd` (`DebugSlotEditor extends DebugPage`), `game/debug/pages/debug_bag_page.gd` (`DebugBagPage extends DebugPage`)
- Modify: `game/debug/debug_menu.gd` only if the shared helpers need a spin-box row (`spin_row(grid, text, min, max, value) -> SpinBox`)
- Test: `tests/game/test_debug_custom_battle.gd` (create); keep `tests/game/test_debug_menu.gd` green

**Interfaces:**
- Consumes: `CreatureSpec` (Task 2), `BattleLauncher.exhibition_setup` (Task 3), `BattleLauncher.TEST_BAG`.
- Produces: `DebugCustomBattlePage` holding `mine: Array`, `foes: Array` (of `CreatureSpec`), `my_field`, `foe_field`, `wild`, `bag: Dictionary`; the page keeps this state when moving to the slot/bag pages and back (pass the page instance into `DebugSlotEditor.new(owner_page, side, index)` / `DebugBagPage.new(owner_page)`, which call `menu.show_page(owner_page)` on Done/Back; `show_page` must not rebuild state — the page's `build` re-reads its fields).

- [ ] **Step 1: Write failing tests** (pattern of `test_debug_menu.gd`, labels via the `_labels()` helper): with a one-creature party the page still offers "You field" 3 and Start builds a 3v3 (check the `BattleSetup` handed to `menu.go` via a stubbed `Overworld.active.battles`, or call the page's `make_setup()` method, which Start uses and which returns the `BattleSetup`); Fill-from-party copies up to `party_size` specs with moves, item, passive; "All levels" applies to one team only; Add creature stops at `party_size`; Remove stops at 1; slot editor: changing level resets non-edited moves and keeps edited ones; the move option labels contain "✓ Lv", "(later)" and "✗ can't learn" for a fixture species; passive labels contain "★ rolls"/"✗ not normal"; bag editor: counts round-trip, Reset to test bag, Clear all; closing the menu (`DebugMenu.close()`) while on the page does not call `run_battle` and leaves `GameState.current` untouched.
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Implement** per spec 3.1–3.5: format row, two tabs (Your team / Foe team), per-creature rows with species, level, Edit, Add/Remove, "bench" marker beyond the field count, All levels spinner + Apply, Fill from my party, Randomize (foe), Bag..., Start, Back. Slot editor: species, level 1..`level_cap`, four move drop-downs (every move in the game, items from `CreatureSpec.move_label`, plus "(empty)" for slots 2–4), held item list (+ "(none)"), passive list (+ "(none)") using `passive_label`, summary line, Reset to natural, Done (disabled with a message while `validate` has errors). Bag page: every item grouped by category with 0–99 spinners. Foe defaults: random species at `party_level` (or 5 with no party). `width()` 340 for these pages; keep within `MAX_PAGE_HEIGHT` scrolling.
- [ ] **Step 4: Run** `tests/game/test_debug_custom_battle.gd` and `tests/game/test_debug_menu.gd`. Expected: PASS.
- [ ] **Step 5: Real-window check** with the run-godot skill: open F1 → Custom battle at the 360px panel with a 12-creature team, the slot editor and the bag page; screenshot each, and play one 2v3 exhibition to the results panel and confirm the save is unchanged. Leave uncommitted.

### Task 5: Larger-party screens

**Files:**
- Modify as needed: `game/progress/storage_screen.gd`, `game/progress/summary_screen.gd`, `game/battle/battle_scene.gd` (`_swap_choices`, replacement menu), `game/battle/command_menu.gd`, the party/team page
- Test: `tests/game/test_screens_smoke.gd` (extend)

- [ ] **Step 1: Write failing smoke tests** that build each party-facing screen (Team/Summary/Storage, the battle swap and "Send out who?" menus, the item-target list) with a `party_size` 12 database and a full party of 12, asserting no control overflows the 360px-high screen (use the existing `tests/helpers/screen_fit.gd`) and every party member has a reachable button.
- [ ] **Step 2: Run** the suite. Expected: FAIL for the screens that overflow (likely Storage with 12 party rows; the battle menus with a long bench).
- [ ] **Step 3: Fix** by paging or scrolling the overflowing lists (`CommandMenu.choose` pages above a row limit with Previous/Next entries; Storage shows party rows in pages like the box). Keep six-creature layouts visually unchanged.
- [ ] **Step 4: Run** `tests/game`. Expected: PASS.
- [ ] **Step 5: Real-window check** at party sizes 6 and 12 (edit `balance.json` temporarily via a throwaway copy of the data folder or the run skill's option; restore it, the repo file must end `party_size: 6`). Screenshot Summary, Team, Storage and a battle swap menu. Leave uncommitted.

### Task 6: Engine tests: formats, swaps, targeting

**Files:**
- Create: `tests/battle/test_formats.gd`, `tests/battle/test_swaps.gd`, `tests/battle/test_targeting_matrix.gd`

**Interfaces:** Uses `FixtureDB.raw()/make/engine/events_of`, `BattleAction`, `BattleEngine.resolve_round`, `targets_for`, `second_targets_for`. Add a `FixtureDB` helper `static func team(db: Database, n: int, species := "blob", moves := ["hit"]) -> Array` if three or more tests need it.

- [ ] **Step 1: Write the tests.** `test_formats`: for each of 1v1, 1v2, 1v3, 2v2, 2v3, 3v3 and seeds 1..5, run to completion with a pass/`hit` script; assert `is_over()`, `rounds <= round_limit`, field counts at start equal the setup, benches of 0, 3 and 9 fill empty slots on faint (replacement rules), no duplicate bids on the field. `test_swaps`: swap costs the swapper's action (it cannot also move that round); swap resolves before moves (priority 6); stat stages of the creature leaving reset; rejected: swapping in a fainted creature, one already on the field, the same bench creature twice in one round; with a 12-creature party every bench bid is accepted once; a swap-in triggers `enter` once. `test_targeting_matrix`: for targets `self`, `enemy`, `all_enemies`, `ally`, `two_enemies` (add fixture moves like the `twin_strike` setup in `test_two_target_moves.gd`) with 1, 2 and 3 foes standing, and with a fainted slot in between: `targets_for` returns only standing opposite/same-side battlers as appropriate; `two_enemies` yields two distinct foes, one when only one remains; spread multiplier applied per `balance.spread_mults` for 2 and 3 hit targets and none for a single target; events list one damage event per target.
- [ ] **Step 2: Run** the three suites. Expected: PASS where the engine already behaves; any FAIL is a real engine bug: stop, report it with the failing case, and fix it in a separate sub-step with its own regression test before continuing.
- [ ] **Step 3: Confirm tests bite**: for each suite, temporarily break the rule under test (for example change the swap priority constant, the spread table lookup, or the bench refill) and see a test fail, then restore. Leave uncommitted.

### Task 7: Passives/held items in multi formats, simulations, docs

**Files:**
- Create: `tests/battle/test_multi_format_effects.gd`, `tests/battle/test_simulation_invariants.gd`
- Modify: `tools/simulate.gd` (clamp `--party` to 1..`db.balance.party_size`, accept up to the ceiling), `documentation/battle-engine.md` (a "Testing" subsection), `.superpowers/HANDOFF.md` (add this feature's status)

- [ ] **Step 1: Write tests.** `test_multi_format_effects` (real or fixture content via `FixtureDB`, like `test_passives_battle.gd`/`test_held_items_battle.gd`): an aura held item or passive helps every ally in 2v2 and 3v3 but not foes; a `consumed` item is used up once per holder when two holders trigger in the same round; a `per_battle` item fires once per battle even with swaps in and out; absorb on one of two targets of a spread/`two_enemies` move spares only that target and the others still take the spread-reduced damage; underdog bonuses (stat bonus, spread reduction, extra actions) scale for 1v2, 1v3, 2v3 and vanish at even sizes. `test_simulation_invariants`: for formats {1v1, 2v2, 3v3, 1v3, 2v3} × seeds 1..20, using the loop in `tools/simulate.gd` with the real database, `ai` tactician vs aggressive and random species at levels 5 and 40, assert after every round: every battler's HP within `[0, max_hp]`; no event names an unknown bid; a fainted battler has no action events after its faint (until revived by a replacement as a new placement); battle ends within `round_limit`; and replaying the same seed produces an identical event log (compare `JSON.stringify` of the event arrays).
- [ ] **Step 2: Run** them. As in Task 6, a FAIL is a real bug to report and fix with a regression test.
- [ ] **Step 3: Update** `tools/simulate.gd` and the docs; run `tools/simulate.gd --battles=20 --format=2v3 --party=12` to confirm it runs.
- [ ] **Step 4: Full check**: `bash scripts/check.sh`. Expected: ends "All checks passed." Leave everything uncommitted and report the suggested commit message.

---

## Self-review

- Spec coverage: §1 goals → Tasks 1–5; §2 units → Tasks 1–4; §3.1–3.5 → Tasks 3–4; §3.6 larger parties → Tasks 1, 5; §3.7 bugs-in-passing → any found are added to Task 4/5 notes; §4 tests → Tasks 1–4, 6, 7.
- Names are consistent across tasks (`CreatureSpec`, `exhibition_setup`, `BattleSetup.exhibition`, `DebugSlotEditor`, `DebugBagPage`, `BalanceDef.MAX_PARTY_SIZE`).
