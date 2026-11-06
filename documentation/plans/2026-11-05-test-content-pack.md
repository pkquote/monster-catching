# Test Content Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a debug-only, removable `data_testpack/` of about 30 creatures, 100 moves, 25 items, 35 passives, 6 tamers and 4 encounter tables, loaded as a layered pack, guarded out of real saves, with coverage, mechanics and simulation tests.

**Architecture:** `DataLoader.load_database` takes extra pack roots merged into the same `RawData` before validation; `DataRegistry` adds `res://data_testpack` in debug builds only. Every pack id starts with `tp_` (`Database.is_test_content`); random generators that feed a save skip those ids. A `PackCoverage` test helper reads `DataSchemas` and reports what the pack does not exercise, and the content is built to make that report empty.

**Tech Stack:** Godot 4.7.2 GDScript, gdUnit4, JSON content validated by `core/data/schemas.gd` + `validator.gd`.

**Spec:** [documentation/specs/2026-11-05-test-content-pack-design.md](../specs/2026-11-05-test-content-pack-design.md)

## Global Constraints

- **Never `git commit`, stage or stash.** The user authors every commit. Tasks end with "leave uncommitted"; the final message includes a suggested commit message (title, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Type every local variable explicitly (`var x: int = ...`), including loop variables and lambda parameters; untyped inferred locals can hang headless Godot.
- Run only one Godot process at a time; never touch the user's own Godot editor/game processes.
- `bash scripts/check.sh` must end "All checks passed."
- `data/` (shipped content), the compendium, shops, maps and `data/balance.json` stay unchanged. The pack lives only in `data_testpack/`; pack ids all start with `tp_`; pack reuses types, statuses, field states, reactions and affinities from `data/`.
- Sizes (spec §1): about 30 creatures, 100 moves, 25 items, 35 passives, 6 tamers, 4 encounter tables. Coverage over polish; dummies named for what they test.
- Content JSON uses the same shapes as `data/` (`{"schema": 1, "entries": [...]}`); read `core/data/schemas.gd` for each category's exact fields and ranges before writing entries.
- Files in `core/`, `game/` use the neighbouring file's line endings; new JSON and tests use LF (`.gitattributes` `eol=lf`).

## Review Focus

- A missing `data_testpack/` (release build, fresh clone without it) must not break loading or `check.sh`. Test: Task 1.
- A pack id colliding with a shipped id, or a pack entry referencing a missing id, must be reported as a validation error rather than crash. Test: Task 1.
- Fill box, wild rolls and tamer rolls must never produce a `tp_` creature, even when the pack is loaded. Test: Task 2.
- A pack creature must be buildable into a battle in every format and not crash the engine for any of its moves, passives and held items. Test: Task 8.
- Removing the pack must leave `check.sh` green. Test: Task 8 (a documented removal checklist plus a test that runs the base-only validation).

---

### Task 1: Layered pack loader

**Files:**
- Modify: `core/data/data_loader.gd`, `core/data/database.gd`, `game/autoload/data_registry.gd`, `tools/validate_data.gd`, `scripts/check.sh`
- Create: `data_testpack/.gitkeep` (folder must exist; real content lands in later tasks)
- Test: `tests/data/test_testpack_loader.gd` (create)

**Interfaces:**
- Produces: `DataLoader.load_database(data_root: String, dialogue_root: String = "", packs: Array = []) -> LoadResult` (each pack is a root path with the same layout as `data/`; missing category folders and a missing pack root are skipped silently); `DataLoader.read_raw(root: String, errors: PackedStringArray, into: RawData = null, optional: bool = false) -> RawData`; `const Database.TEST_PREFIX: String = "tp_"`; `static func Database.is_test_content(id: String) -> bool`; `DataRegistry.PACK_ROOT: String = "res://data_testpack"`.
- `tools/validate_data.gd` validates `data/` alone and, if `data_testpack/` has entries, `data/` plus the pack, printing one result line for each (`Data OK` and `Data+pack OK`).

- [ ] **Step 1: Write failing tests** in `tests/data/test_testpack_loader.gd`, building temporary pack roots under `user://testpack_<n>/` in the test (write small JSON files with `FileAccess`) and removing them afterwards: `test_pack_entries_merge_into_the_database` (a one-move pack adds `tp_probe` to `db.ids("moves")` with the base ids still present); `test_missing_pack_root_is_ignored` (a non-existent path in `packs` loads fine, no errors); `test_missing_category_folders_are_skipped` (a pack with only `moves/`); `test_duplicate_id_across_pack_and_base_is_an_error` (a pack move reusing a base move id gives an error naming the id); `test_dangling_reference_in_pack_is_an_error` (a pack creature learning an unknown move gives an error); `test_is_test_content` (`tp_x` true, `tidepup` false, `""` false); `test_registry_pack_root_constant` (`DataRegistry.PACK_ROOT == "res://data_testpack"`).
- [ ] **Step 2: Run** the suite: `"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/data/test_testpack_loader.gd --ignoreHeadlessMode -c`. Expected: FAIL (signature/constants missing).
- [ ] **Step 3: Implement** the signatures above. `load_database` runs `read_raw(data_root, ...)` then `read_raw(pack, errors, raw, true)` for each existing pack root, then validates once. `DataRegistry` passes `[PACK_ROOT]` only when `OS.is_debug_build()` and `DirAccess.dir_exists_absolute(PACK_ROOT)`. `validate_data.gd` gets the second pass; `scripts/check.sh` keeps its current `grep` patterns but also accepts the `Data+pack OK` line.
- [ ] **Step 4: Run** the suite, then `bash scripts/check.sh`. Expected: PASS, "All checks passed." Leave uncommitted.

### Task 2: Save-safety filters and the coverage helper

**Files:**
- Modify: `game/debug/pages/debug_main_page.gd` (Fill box), `game/battle/battle_launcher.gd` (`roll_wild_pack` already uses encounter tables; guard `custom` random picks outside the builder), any other call that picks a random species into a save (grep `db.ids("creatures")` and `ids("creatures")` in `game/` and `core/`)
- Create: `tests/helpers/pack_coverage.gd`
- Test: `tests/game/test_testpack_safety.gd` (create), `tests/helpers/test_pack_coverage.gd` (create)

**Interfaces:**
- Consumes: `Database.is_test_content` (Task 1).
- Produces: `class_name PackCoverage extends RefCounted` with `static func report(raw: RawData) -> Dictionary` returning family name → `PackedStringArray` of uncovered names, for the families `effect_ops`, `move_targets`, `trigger_on`, `when_keys`, `use_kinds`, `types_single`, `types_dual_count` (reports `"need 10, have N"` if fewer than 10 dual-typed pack creatures), `statuses`, `field_states`. Only entries whose id starts with `tp_` count. The names compared come from `DataSchemas` (`EFFECT_OPS` keys that are move-legal, `MOVE_TARGETS`, `TRIGGER_ON`, the `WHEN` fields, the held `use` values, the type, status and field-state ids in the base data).
- Also produces (game layer): `static func BattleLauncher.save_safe_species(db: Database) -> Array` returning sorted creature ids without `tp_`; Fill box and every save-feeding random pick use it.

- [ ] **Step 1: Write failing tests.** `test_testpack_safety.gd`: with a pack-loaded database that contains at least one `tp_` creature (build it in the test via the Task 1 loader and a temp pack), `save_safe_species` contains no `tp_` id and still contains every base id; running F1 Fill box ten times (call the page's fill function with a seeded `RandomNumberGenerator`) adds no `tp_` creature to `save.storage`; `roll_wild_pack` over a base encounter table never yields `tp_` ids even with the pack loaded. `test_pack_coverage.gd`: build a synthetic `RawData` from `FixtureDB.raw()` with two `tp_` moves (one `damage` op `one_enemy`, one `heal` op `self`) and assert `report` lists the other ops/targets as uncovered and omits `damage`, `heal`, `one_enemy`, `self`; a non-`tp_` entry using `stat_stage` is ignored; entries using every `when` key mark that family empty.
- [ ] **Step 2: Run** both suites. Expected: FAIL.
- [ ] **Step 3: Implement** `PackCoverage`, `save_safe_species` and the filters. Keep the builder's foe randomiser and `simulate.gd` on the full pool (they never write a save).
- [ ] **Step 4: Run** the suites and `bash scripts/check.sh`. Expected: PASS. Leave uncommitted.

### Task 3: Moves (about 100)

**Files:**
- Create: `data_testpack/moves/tp_<group>.json` files grouped by theme (for example `tp_damage.json`, `tp_status.json`, `tp_field.json`, `tp_targets.json`, `tp_edges.json`)
- Test: `tests/data/test_testpack_moves.gd` (create)

**Interfaces:** Consumes the loader (Task 1) and `PackCoverage` (Task 2). Produces move ids `tp_*` for creatures to learn (Task 5).

- [ ] **Step 1: Write failing tests** in `test_testpack_moves.gd` (loads `data/` + `data_testpack` via `DataLoader.load_database("res://data", "", ["res://data_testpack"])`): `test_move_count` (between 90 and 110 pack moves); `test_every_pack_move_id_starts_with_tp`; `test_every_target_kind_is_used` (every value in `DataSchemas.MOVE_TARGETS` appears among pack moves); `test_every_move_legal_effect_op_is_used`; `test_two_moves_for_every_type` (each of the 14 types has at least two pack moves); `test_every_status_and_field_state_is_applied_by_some_pack_move`; `test_edge_cases_present` (named assertions: a priority > 0 and a priority < 0 move; an `always_hits` move; a power-0 status move; a move with 3 or more effects; stat stages at -3 and +3; a `heal` fraction of 1.0 and a `damage_fraction` of 1.0; a move with `skip_chance`; one using `scrap_power`; one using `restore_energy`; costs ranging from 0 to above 20).
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Write the moves** to satisfy the tests, following the spec §3.2 coverage list. Name them for what they test (for example `tp_hit_all_foes`, `tp_priority_plus`, `tp_stage_max_up`). Validate with `"$GODOT" --headless --path . --script res://tools/validate_data.gd` until "Data+pack OK".
- [ ] **Step 4: Run** the suite and the validator. Expected: PASS. Leave uncommitted.

### Task 4: Passives (about 35) and items (about 25)

**Files:**
- Create: `data_testpack/passives/tp_*.json`, `data_testpack/items/tp_held.json`, `tp_healing.json`, `tp_capture.json`, `tp_training.json`
- Test: `tests/data/test_testpack_passives_items.gd` (create)

**Interfaces:** Produces passive ids `tp_*` (creatures list them in Task 5) and item ids `tp_*`.

- [ ] **Step 1: Write failing tests**: `test_passive_count` (30–40), `test_item_count` (20–30); every `TRIGGER_ON` value is used by at least one pack passive and one pack held item; `contact` true and false `hit` triggers both present; `chance` values 1, 50 and a trigger with no chance (100); every `WHEN` field used at least once; every held `use` kind (`permanent`, `consumed`, `per_battle`) present; at least one aura (`scope: allies`) among passives and one among held items; at least one passive with an overworld `field` op for each of `encounter_rate`, `xp_mult`, `bond_gain`; every persistent-effect op named in spec §3.3 is used; a pair of passives whose trigger effects cause the other's trigger (documented in their descriptions as the depth-guard case); healing items span a small and a full heal and a status cure; capture items include a multiplier below 1 and a guaranteed catch; at least one training item; all ids start with `tp_`.
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Write the content** following spec §3.3–§3.4; descriptions are one plain sentence saying what each tests. Validate until "Data+pack OK".
- [ ] **Step 4: Run** the suite and validator. Expected: PASS. Leave uncommitted.

### Task 5: Creatures (about 30)

**Files:**
- Create: `data_testpack/creatures/tp_*.json` (for example `tp_types.json`, `tp_shapes.json`, `tp_chains.json`)
- Test: `tests/data/test_testpack_creatures.gd` (create)

**Interfaces:** Consumes the move and passive ids from Tasks 3–4 (verify each referenced id exists; the validator reports dangling ids).

- [ ] **Step 1: Write failing tests**: count 28–32; every one of the 14 types appears as a single type on a pack creature; at least 10 dual-type pack creatures; stat-shape creatures exist (assert by stat values: one with `patk` and `satk` both at least twice `pdef` and `sdef` and `hp` below 40; one with defences and `hp` at least twice the attacks; one with `spd` at least 120; one with every base stat 1; one with every base stat 255); every growth tier (`slow`, `steady`, `fast`) is used by several species and one species spends the full `balance.growth_budget`; at least two evolution chains (`growth` entries with an Affinity branch and a default branch), one with three stages, and every `into` exists; every creature lists 1–3 passives and a full `affinity_passives` map (every Affinity id); a creature with exactly one learnset move; a creature whose entire learnset is at level 1; a creature learning moves up to level 40 or higher; a creature whose learnset omits all four moves of some move group so the F1 builder's "can't learn" labels have a subject (document its id in the test).
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Write the creatures** per spec §3.1; encode all stat bounds against the schema ranges (1..255). Validate until "Data+pack OK".
- [ ] **Step 4: Run** the suite and validator. Expected: PASS. Leave uncommitted.

### Task 6: Tamers and encounter tables

**Files:**
- Create: `data_testpack/tamers/tp_tamers.json`, `data_testpack/encounters/tp_encounters.json`
- Test: `tests/data/test_testpack_tamers_encounters.gd` (create)

**Interfaces:** Consumes pack creatures and moves. Produces tamer ids `tp_*` and encounter ids `tp_*` for Task 8.

- [ ] **Step 1: Write failing tests**: exactly six pack tamers with the shapes in spec §3.5 (assert `max_active`, `ai` and party size for each: 1/basic, 2/tactician, 3/aggressive, a `max_active` 3 tamer with a 6-creature party, an Underdog trainer whose `max_active` is lower than the party's field expectation, and a single-creature stall trainer); four encounter tables with the shapes in spec §3.5 (single species, wide level range, `pack_min` = `pack_max` = 3, a table with one species weighted at least 90%); no shipped map, shop or story file references a `tp_` id (grep `res://game/maps`, `res://tools/build_maps.gd`, dialogue) so the pack stays unreachable from play.
- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Write** both files; tamer parties use pack creatures, custom `moves` and `held_item` where useful. Validate until "Data+pack OK".
- [ ] **Step 4: Run** the suite and validator. Expected: PASS. Leave uncommitted.

### Task 7: Coverage guard and per-mechanic battle tests

**Files:**
- Create: `tests/data/test_testpack_coverage.gd`, `tests/battle/test_testpack_mechanics.gd`

**Interfaces:** Consumes `PackCoverage.report` (Task 2) and the whole pack. Uses the real `Database` built with the pack and `BattleEngine` through `BattleSetup` like `tools/simulate.gd`.

- [ ] **Step 1: Write the tests.** `test_testpack_coverage.gd`: `PackCoverage.report(raw)` over the real `data/` plus pack returns an empty list for every family (assert each family separately so a failure names it); also the sizes from spec §1 (within 10% of the targets). `test_testpack_mechanics.gd`: for each move-legal effect op, build the smallest battle (1v1, fixed seed, two named pack creatures, `tp_` moves of that op) and assert the specific documented outcome, with the expected values taken from `documentation/battle-engine.md` and the schema (damage dealt and clamped; heal fraction of max HP; stat stage applied and clamped at ±3 the engine's limit; status applied with chance 100; field state applied and consumed by `bonus_if_field` with `consume`; `skip_chance`; priority ordering; `always_hits` ignoring accuracy; energy cost deducting energy and an unaffordable move being rejected; every target kind selecting the right battlers in a 2v3 layout). For passives and held items: each `TRIGGER_ON` kind fires once at the right moment with a `PASSIVE_TRIGGERED` event; each held `use` kind behaves per its design (consumed gone after firing and an `ITEM_CONSUMED` event, per_battle fires once, permanent persists); the depth-guard pair terminates; each of the 8 base reactions is triggered at least once by some pair of pack moves (assert the `reaction` event per reaction id).
- [ ] **Step 2: Run** both suites. A failure caused by wrong pack content is fixed in the pack (smallest edit, re-run the Task 3–6 suites). A failure caused by the engine is NOT bent around: record it (failing case, expected vs actual from the docs, suspected `file:line`) in the task report as an engine bug, keep the correct expectation, and return DONE_WITH_CONCERNS for the controller to decide.
- [ ] **Step 3: Mutation check** each file: break one rule (for example remove an op from the pack to see the coverage test name it; change a battle-engine constant used by a mechanic test), see a failure, restore from a saved copy and prove identical with `cmp`.
- [ ] **Step 4: Run** both suites and `bash scripts/check.sh`. Expected: PASS. Leave uncommitted.

### Task 8: Pack simulations, docs and check.sh

**Files:**
- Create: `tests/battle/test_testpack_simulations.gd`
- Modify: `tools/simulate.gd` (`--pack=1|0`, default 1; loads the pack roots through the new `packs` parameter when 1 and uses the full species pool), `documentation/battle-engine.md` (a "Test content pack" section: what it is, the `tp_` rule and `Database.is_test_content`, how to use it in the F1 builder and `simulate.gd`, the removal checklist), `README.md` (one line), `.superpowers/HANDOFF.md` (a section for this feature), `scripts/check.sh` (base-only validation and base+pack validation are both visible lines), spec status line to "Implemented (plan: ../plans/2026-11-05-test-content-pack.md)"

**Interfaces:** Consumes everything above. `simulate.gd` option `--pack` (int, default 1).

- [ ] **Step 1: Write the simulation test.** Over the whole pack (real `data/` + pack), formats {1v1, 2v2, 3v3, 1v3, 2v3, 3v6 using a 6-bench} x seeds 1..10, random pack and base species at levels 5 and 60, tactician vs aggressive vs basic AI in rotation, with passives and held items assigned from the pack by seed: after every round assert HP in [0, max], no event names an unknown bid, fainted battlers never act, the battle ends within `round_limit`; the same seed replays an identical `JSON.stringify` event log; every pack creature appears in at least one battle, and every pack move, passive and held item is used at least once across the run (collect from `MOVE_USED` and `PASSIVE_TRIGGERED` events, allowing a documented exemption list for moves the AI never selects, which the test prints rather than hides). Also a removal test: loading `data/` without the pack still builds a database with no `tp_` ids and the base 8 creatures.
- [ ] **Step 2: Run** it. Expected: FAIL until `--pack` and any data issues are fixed. Engine failures follow the Task 7 rule (report, do not bend).
- [ ] **Step 3: Implement** the `simulate.gd` option and the docs. Run `godot --headless --path . --script res://tools/simulate.gd -- --battles=50 --format=2v3 --party=6 --pack=1` and confirm it prints species win rates including `tp_` creatures and the same command with `--pack=0` prints only base creatures.
- [ ] **Step 4: Full check:** `bash scripts/check.sh`. Expected: ends "All checks passed." Keep the added runtime under about 30 s (reduce seeds if needed and say so). Leave everything uncommitted and report the suggested commit message.

---

## Self-review

- Spec coverage: §1 goals and decisions → Tasks 1, 2, 8; §2 units → Tasks 1–2; §3.1–3.5 content → Tasks 3–6; §4 tests → Tasks 1–2 (data/safety/loader), 7 (coverage, mechanics), 8 (simulations, removal); §5 out-of-scope respected (no new statuses, field states, types).
- Names are consistent across tasks (`DataLoader.load_database(..., packs)`, `Database.is_test_content`, `PackCoverage.report`, `BattleLauncher.save_safe_species`, `DataRegistry.PACK_ROOT`).
- Sizes: the plan carries decisions and test assertions; the JSON bodies are left to the implementers because the schemas and the coverage tests fully determine acceptable content.
