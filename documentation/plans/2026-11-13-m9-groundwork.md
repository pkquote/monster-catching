# M9 Groundwork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five content guards (species reachability, orphan passives, orphan items, unused encounter tables, orphan moves) and a scaffold tool that starts a new species line valid, so M9's large content authoring cannot silently leave dead content.

**Architecture:** The guard logic lives in one pure class, `ContentAudit` (`tools/content_audit.gd`), whose functions take a `Database` and source text and return sorted lists of offending ids. Unit tests exercise it on small synthetic data (so each failure path is proven without editing shipped data); five guard tests run it on the shipped data. The scaffold is a pure `SpeciesScaffold.build` plus a thin runner. No engine, schema or content change.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit4. Checks: `bash scripts/check.sh`.

**Spec:** [documentation/specs/2026-11-13-m9-groundwork-design.md](../specs/2026-11-13-m9-groundwork-design.md)

**Commits:** the user writes every commit in this project. Do not `git commit`, stage or stash (restore mutated files from a `cp` backup, never `git checkout`); each task ends with its test run, and the final message gives a suggested commit message in the form `<title> (M9)`, bullets, then `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

**One suite:** run a single test file with
`"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/<path>.gd --ignoreHeadlessMode -c`
where `GODOT` is the console exe named in `scripts/check.sh`. Below this is written `RUN <path>`. A new `class_name` script needs the class cache refreshed once: `"$GODOT" --headless --path . --import` before its first run.

## Global Constraints

- Scan shipped data only: `res://data`, `res://dialogue`, and `res://game/maps/*.tscn` whose file name does not start with `test_`. Never the test pack (`data_testpack/`).
- A failure message names every offending id.
- The fallback move (`db.balance.energy_cfg.fallback_move`, `scrap`) is never reported as an orphan move.
- A move is orphaned only if some species has the move's type **and** no species learns it; moves of a type no species has pass.
- Scaffold names: stage ids `<name>_1` to `<name>_3`, display names "Wisp 1"... (`name.capitalize()` + " " + N); placeholder description `"A new species. Replace this description."`; base stats flat 50, +10 per stage; growth level `16 x stage`; second learnset move at level 8; file `data/creatures/<name>_line.json`; `stages` 1 to 3; `types` 1 to 2.
- Scaffold output must validate: `DataValidator.validate` returns no errors and the dex numbers stay contiguous from 1.
- No change to any file under `data/`, `game/` or `core/`.

## Review Focus

- A species reachable only through a chain of evolutions from an obtainable one (A gifted, A evolves to B, B to C): C counts as obtainable; an evolution cycle with no entry point does not loop forever and is reported.
- A species that is only the target of its own `growth.into` (self-loop) is not obtainable.
- An item id that is a substring of another (`tonic` inside `clear_tonic`) must not count as placed by the longer id's text: match the quoted whole id.
- A `test_*` map or a `.dialogue` under `tests/` that names an item or species does not make shipped content reachable.
- Scaffold with `stages=1` writes no `growth`; with a second type uses both types for the level-1 move choice order (first type first); a database with no Affinity entries yields no `affinity_passives`.
- Scaffold refuses a name that is not snake_case, an id collision, an unknown type, `stages` 0 or 4, and an existing output file, each with a clear message and no file written.
- `SpeciesScaffold.build` does not mutate the `Database` it is given.

---

### Task 1: `ContentAudit` and the five guards

**Files:**
- Create: `tools/content_audit.gd` (class `ContentAudit`, all `static`)
- Create: `tests/tools/test_content_audit.gd` (synthetic unit tests)
- Create: `tests/data/test_content_reachability.gd` (the five guards on shipped data)

**Interfaces:**
- Produces (all return a sorted `Array` of String ids; empty means clean):
  - `ContentAudit.shipped_text() -> String`: the text of every `*.dialogue` under `res://dialogue` (recursive) joined with the text of every `res://game/maps/*.tscn` not named `test_*`.
  - `ContentAudit.unobtainable_species(db: Database, text: String) -> Array`: species not given (`give_creature("id"` in `text`), not in the table of any encounter id listed in any location's `areas`, and not reached by repeatedly following `growth[].into` from those; terminates on cycles.
  - `ContentAudit.orphan_passives(db: Database) -> Array`: passives not in any species' `passives` nor any `affinity_passives` value.
  - `ContentAudit.orphan_items(db: Database, text: String) -> Array`: items whose quoted id (`"id"`) does not appear in `text`.
  - `ContentAudit.unused_encounters(db: Database) -> Array`: encounter ids in no location's `areas`.
  - `ContentAudit.orphan_moves(db: Database) -> Array`: per the Global Constraints rule.
- Consumes: `Database` accessors `ids(cat)`, `creature`, `move`, `encounter`, `location`, `balance.energy_cfg.fallback_move`; `EncounterDef.table` entries (`species`); `CreatureDef.growth/passives/affinity_passives/types/learnset`; `MoveDef.type`.

- [ ] **Step 1: Write `tests/tools/test_content_audit.gd` (RED).** Build databases from `FixtureDB.raw()` plus `raw.add_entry(...)` (read `tests/helpers/fixture_db.gd` for the species, the `e1` encounter and the `locations` file category; add a `locations` entry with `{"id","name","areas":[...]}` when a test needs one). One test per behaviour, each asserting the exact returned array:
  - `test_species_given_by_dialogue_is_obtainable` and `test_species_in_a_used_table_is_obtainable` and `test_unused_table_does_not_make_species_obtainable`
  - `test_evolution_target_of_an_obtainable_species_is_obtainable` (chain of three: only the first obtainable, all three reported clean) and `test_evolution_cycle_without_an_entry_is_reported` and `test_self_evolution_is_not_obtainable`
  - `test_orphan_passive_is_reported` (a passive named by `passives` of one species and another by an `affinity_passives` value are clean; a third is reported)
  - `test_item_is_matched_by_whole_quoted_id` (`text` contains `"clear_tonic"` only: `tonic` is reported, `clear_tonic` is not)
  - `test_unused_encounter_is_reported`
  - `test_move_of_a_populated_type_that_nobody_learns_is_orphan`, `test_move_of_an_unpopulated_type_passes`, `test_fallback_move_is_never_orphan`
  - `test_shipped_text_skips_test_maps` (assert `ContentAudit.shipped_text()` contains `Story.give_creature("tidepup"` and contains no text from a `test_*` map: compare against a `test_*.tscn` file's unique node name if one exists under `res://game/maps`, otherwise assert the helper's file list via a second function `ContentAudit.shipped_files() -> Array` returning paths with none whose base name starts with `test_`. Make `shipped_text()` build on `shipped_files()`.)
  Expected: RUN `tests/tools/test_content_audit.gd` fails because `ContentAudit` is not defined (after `--import`, a parse error naming `ContentAudit`).
- [ ] **Step 2: Implement `tools/content_audit.gd`** with the signatures above plus `static func shipped_files() -> Array`. Reachability is a fixpoint loop over a `reached` dictionary seeded from gifts and used tables, adding `growth[].into` until no change. Sort every result. Extends `RefCounted`; header comment names the five guards and that it scans source text. Run `--import` then RUN `tests/tools/test_content_audit.gd`. Expected: all pass.
- [ ] **Step 3: Write `tests/data/test_content_reachability.gd`.** `before()` loads `DataLoader.load_database("res://data", "res://dialogue")` (assert `ok()`) and `ContentAudit.shipped_text()`. Five tests, each `assert_array(ContentAudit.<fn>(...)).override_failure_message("<what is wrong>: " + ", ".join(list)).is_empty()`; names exactly: `test_every_species_can_be_obtained`, `test_every_passive_is_on_a_species`, `test_every_item_is_given_sold_or_placed`, `test_every_encounter_table_is_used`, `test_every_move_of_a_populated_type_is_learned`. Failure messages must say what to do (for example "add it to a gift, an encounter table or an evolution"). RUN `tests/data/test_content_reachability.gd`. Expected: 5 pass on today's data (12/12 species, no orphans; the 18 unpopulated-type moves pass).
- [ ] **Step 4: Mutation check each guard on shipped data.** For each, `cp` the file to the scratchpad, edit, RUN `tests/data/test_content_reachability.gd`, confirm exactly that guard fails with the right id in the message, then restore from the backup and re-run to green:
  1. delete the `Story.give_creature("sprigling"...` line in `dialogue/town_01/story.dialogue` (species guard; starter is only given there);
  2. remove `"ember_trail"` from every species using it in `data/creatures/emberkit_line.json` (passive guard);
  3. remove `"guard_banner"` from the `stock` of `game/maps/town_01_center.tscn` (item guard; if it is also elsewhere, pick an item that appears once);
  4. delete `"route_01"` from `areas` in `data/locations.json` so both tables become unused (table guard);
  5. remove a species' only learnset entry for one move of a populated type, e.g. `ember_flick` from every learnset (move guard).
  Expected: each mutation fails only its own guard; after each restore the suite is green.
- [ ] **Step 5: Run whole task.** RUN `tests/tools/test_content_audit.gd` and `tests/data/test_content_reachability.gd`. Expected: all pass.

### Task 2: `SpeciesScaffold` and the runner

**Files:**
- Create: `tools/species_scaffold.gd` (class `SpeciesScaffold`, `static`)
- Create: `tools/new_species_line.gd` (extends `SceneTree`, run with `--script`)
- Test: `tests/tools/test_species_scaffold.gd`

**Interfaces:**
- Produces: `SpeciesScaffold.build(db: Database, name: String, types: Array, stages: int) -> Dictionary`. Returns `{"ok": true, "doc": {"schema": 1, "entries": [...]}}` or `{"ok": false, "error": String}`; never touches the disk or `db`. `SpeciesScaffold.to_json(doc: Dictionary) -> String` (tab-indented `JSON.stringify(doc, "\t")` plus trailing newline).
- Consumes: `Database` (`ids`, `creature`, `move`, `passive`, `type_def`, `affinity`, `has`); the dex numbers of `db.ids("creatures")`.
- Entry shape per stage `i` (1-based): `id` `<name>_i`, `name`, `dex` = max shipped dex + i, `description`, `types`, `base_stats` (the nine stats, 50 + 10 (i-1)), `catch_rate` 0.45, `xp_yield` 50 x i, `learnset` (level-1 move: the first move in `db.ids("moves")` order whose type is `types[0]`, else the first with type `neutral`; plus a level-8 move: the first other move of `types[0]` or neutral), `passives` (the first id of `db.ids("passives")`), `affinity_passives` (every affinity id mapped to that same passive; omitted when the database has no affinities), `growth` for every stage but the last: `[{"level": 16*i, "default": true, "into": "<name>_(i+1)"}]`.

- [ ] **Step 1: Write `tests/tools/test_species_scaffold.gd` (RED).** Use `DataLoader.load_database("res://data", "res://dialogue")` for the shipped db and `DataLoader.read_raw("res://data", errs)` for the raw data. Tests:
  - `test_three_stage_line_validates_with_the_shipped_data`: add each built entry to the raw data (`raw.add_entry("creatures", e)`), assert `DataValidator.validate(raw)` is empty.
  - `test_dex_continues_from_the_shipped_maximum_and_stays_contiguous`: new dex numbers are max+1..max+3 and the sorted dex of shipped plus new equals `range(1, n+1)`.
  - `test_ids_names_and_growth_chain` for 3 stages (ids `wisp_1..3`, names "Wisp 1".., `wisp_1` grows into `wisp_2` at 16, `wisp_2` into `wisp_3` at 32, `wisp_3` has no `growth` key); `test_one_stage_has_no_growth`; `test_two_stages_has_one_growth_entry`.
  - `test_first_type_picks_the_level_one_move` (types `["fire"]`: level-1 move has type `fire`; types `["ghost", "fire"]`: ghost move; a type with no moves falls back to a neutral one).
  - `test_stats_rise_ten_per_stage`.
  - `test_rejections`: bad name (`"Wisp"`, `"wi sp"`), colliding name (a shipped stage 1 id minus its `_1` suffix is not a collision by itself; use a name whose `<name>_1` exists by adding such an entry to the db's raw before `Database.from_raw`), unknown type, 0 and 4 stages, 0 and 3 types; each `ok == false` with a non-empty `error` naming the problem.
  - `test_build_leaves_the_database_unchanged` (`db.count("creatures")` and the max dex before and after).
  Expected: RUN `tests/tools/test_species_scaffold.gd` fails because `SpeciesScaffold` is not defined.
- [ ] **Step 2: Implement `tools/species_scaffold.gd`.** Validate inputs first (snake_case via `^[a-z][a-z0-9_]*$` RegEx; ids must not exist), then build the entries per the shape above, `to_json` as specified. Run `--import`, then RUN `tests/tools/test_species_scaffold.gd`. Expected: all pass.
- [ ] **Step 3: Implement `tools/new_species_line.gd`.** Parse `OS.get_cmdline_user_args()` (`--name=`, `--types=` comma list default `neutral`, `--stages=` default 3); load the database as above (print the loader errors and `quit(1)` on failure); call `build`; refuse with a message and `quit(1)` when `res://data/creatures/<name>_line.json` exists or `build` fails; write the file; reload with `DataLoader.load_database` and print each validation error and warning, then `Wrote <path>: dex a-b, N species`; `quit(0)` only when no errors. Header comment shows the command: `godot --headless --path . --script res://tools/new_species_line.gd -- --name=wisp --types=fire --stages=3`.
- [ ] **Step 4: Run the runner for real, then undo.** Run it with `--name=zz_probe --types=fire --stages=3`; expected: prints `Wrote res://data/creatures/zz_probe_line.json: dex 13-15, 3 species` and exits 0; run `bash scripts/check.sh`'s data step (`--script res://tools/validate_data.gd`) and expect `Data OK`; run the same command again and expect the refusal and exit 1; then delete the probe file (a file you created, so `rm` is safe) and re-run `validate_data.gd` to confirm `Data OK: 12 creatures`.
- [ ] **Step 5: Run whole task.** RUN `tests/tools/test_species_scaffold.gd`. Expected: all pass.

### Task 3: Documentation, drift guard and full check

**Files:**
- Modify: `documentation/developer-guide.md` (the "Add or edit a creature" recipe, lines about step 2 and 3)
- Modify: `.superpowers/HANDOFF.md` (the M9 notes at lines about "Possible, none requested" and "To do as part of M9"; record the piece)
- Modify: `documentation/specs/2026-11-13-m9-groundwork-design.md` (Status line: Implemented, plus the one deviation below)
- Modify: `documentation/battle-engine.md` only if `tests/data/test_docs_drift.gd` demands the new suites in its Testing table (it names battle suites only, so expect no change)

- [ ] **Step 1: Developer guide.** In "Add or edit a creature", add: start a new evolution line with `godot --headless --path . --script res://tools/new_species_line.gd -- --name=<name> --types=<a,b> --stages=<1-3>` (writes `data/creatures/<name>_line.json` with valid placeholders to replace); and a short "Guards" note: `tests/data/test_content_reachability.gd` fails with the ids of any species nobody can obtain, passive on no species, item never given, sold or placed, unused encounter table, and move of a populated type that nobody learns; item and gift detection searches the dialogue and non-test map scenes for the quoted id.
- [ ] **Step 2: HANDOFF.** Replace the stale "reorganize `data/creatures/`" notes with: the layout and dex tests already exist; M9 groundwork done (guards in `tests/data/test_content_reachability.gd`, `ContentAudit`, `SpeciesScaffold` and `new_species_line.gd`); the type-based move rule goes live per type as M9 adds species. Keep the file's existing structure.
- [ ] **Step 3: Spec.** Set Status to "Implemented, 2026-11-13" and add a line under Decisions: the guard logic is in `tools/content_audit.gd` (`ContentAudit`) rather than a helper inside the test file, so each failure path is unit-tested on synthetic data.
- [ ] **Step 4: Full check.** `bash scripts/check.sh`. Expected: Data OK, Dialogue OK, Maps OK, all tests pass (previous total plus the new suites), compendium step succeeds.
