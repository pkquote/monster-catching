# M9 groundwork: design

Status: Implemented, 2026-11-13. Prepares M9 (content expansion) in the [roadmap](2026-11-05-roadmap-m5-m8.md). Small: five
guards and one tool; the only content change is Cinderwisp learning `spirit_touch` (section 3).

## 1. Goal and context

M9 replaces the placeholder content with the real game: many more species, moves, items and encounter tables. Mistakes
at that scale are easy to make and hard to see (a species nobody can obtain, a move no one learns, an item that is never
sold). This piece adds the guards that catch them as they are authored, and a scaffold that starts a new species line
valid.

The HANDOFF listed a third item, "reorganize `data/creatures/` by evolution family and add tests for unique ids and
gap-free dex numbers". It is already done: the files are one per evolution line (`emberkit_line`, `sprigling_line`,
`starter_line`) plus `route_01.json` for the wild species; duplicate ids across files are a validator rule
(`duplicate id`), and duplicate dex numbers are a validator rule too, with `test_every_shipped_creature_has_a_unique_dex` and
`test_dex_numbers_are_contiguous_from_one`. With 12 species, subfolders would add nothing; the HANDOFF note is corrected.

Goals: a failing test when authored content is unreachable or dead; a one-command start for a new species line.
Non-goals: moving any data file; changing content; tests for the test pack (`data_testpack/` is retired in M9).

## 2. Decisions (user chose all three guards, and the type-based move rule, 2026-11-13)

| Topic | Decision |
|---|---|
| Where | `tests/data/test_content_reachability.gd` for the guards, with their logic in `tools/content_audit.gd` (`ContentAudit`, unit-tested on synthetic data in `tests/tools/test_content_audit.gd`); `tools/species_scaffold.gd` (class `SpeciesScaffold`: a pure `build` and a `write_line` that validates before writing) and `tools/new_species_line.gd` (the runner) for the scaffold |
| Data scanned | Shipped data only (`res://data`, `res://dialogue`). Map scenes `res://game/maps/*.tscn` as text, ignoring `test_*` maps |
| Reachability | Every shipped species is obtainable: given by dialogue (`Story.give_creature("id"`), found in an encounter table that some location uses (`data/locations.json`), or the evolution target (`growth.into`) of an obtainable species, repeated until nothing changes |
| Orphan passives | Every shipped passive is some species' `passives` entry or `affinity_passives` value |
| Orphan items | Every shipped item id appears (as text) in the dialogue or in a non-test map scene: given, sold, or placed |
| Unused tables | Every encounter table is used by a location |
| Orphan moves | A move is orphaned only if some species has the move's type and no species learns it. The fallback move (`balance.energy_cfg.fallback_move`, Scrap) is excluded. Moves of a type no species has yet pass (iron, light, magic, mental and virtual moves today); the rule bites as soon as M9 adds a species of that type |
| Scaffold | `godot --headless --path . --script res://tools/new_species_line.gd -- --name=wisp --types=fire --stages=3` writes `data/creatures/wisp_line.json` |
| Naming | Stage ids are `<name>_1`, `<name>_2`, `<name>_3` (valid snake_case), display names "Wisp 1"...; the author renames them |

## 3. The guards

Each is one test in `test_content_reachability.gd`, built on a small helper that reads every `.dialogue` file and
every non-test `.tscn` under `game/maps` into text. A failure message names the offending ids.

1. `test_every_species_can_be_obtained`
2. `test_every_passive_is_on_a_species`
3. `test_every_item_is_given_sold_or_placed`
4. `test_every_encounter_table_is_used`
5. `test_every_move_of_a_populated_type_is_learned`

Today all five pass (12 of 12 species reachable, 0 orphan passives or items, no unused table; the moves of unpopulated types pass. The first run found one real orphan, the ghost move `spirit_touch` (ghost is populated by Cinderwisp), now learned by Cinderwisp at level 20: the only content change).
Each test is also checked by a mutation (remove a gift line, a learnset entry...) in the plan.

## 4. The scaffold

`SpeciesScaffold.build(db: Database, name: String, types: Array, stages: int) -> Dictionary` returns the document
`{"schema": 1, "entries": [...]}` for a new line, without touching the disk:

- `stages` is 1 to 3; `types` are 1 to 2 existing type ids; `name` is snake_case and no `<name>_N` id exists yet.
- `dex` continues from the highest shipped number (stage 1 gets max + 1), so the dex stays contiguous.
- Required fields are filled with valid placeholders: `description` ("A new species. Replace this description."),
  `base_stats` (flat 50, +10 per stage), `catch_rate`, `xp_yield`, a `learnset` with a level-1 move of the first type
  (or the first neutral move) and a second move at level 8, one `passives` entry (the first passive in the data), and an
  `affinity_passives` entry for every Affinity track.
- `growth` for every stage but the last: `[{"level": 16 x stage, "default": true, "into": "<next id>"}]`.

The runner parses `--name`, `--types` (default `neutral`) and `--stages` (default 3), refuses to overwrite an existing
file, writes the document, reloads the data and prints any validation errors or warnings plus the dex range it used.

## 5. Tests

- The five guards (section 3).
- `tests/tools/test_species_scaffold.gd`: the built document, added to the shipped raw data, validates with no errors; the
  dex numbers are contiguous across the whole data; stage ids and growth chain are right for 1, 2 and 3 stages; a name that
  collides, an unknown type and a bad stage count are rejected with a clear message; `build` leaves the database unchanged.

## 6. Documentation

The developer guide's "Add or edit a creature" recipe mentions the scaffold and the guards; `battle-engine.md` is
untouched. The HANDOFF corrects the M9 note and records the piece. `check.sh` already runs the tests; the scaffold is not
part of it.

## 7. Risks

- **Text scanning.** Item and gift detection search source text; a rename in a dialogue or scene must keep the id
  string. The failure message names the id, so a false alarm is quick to read.
- **The type-based move rule is lenient** until a type is populated. It is the user's choice over an exemption list.
- **Scaffold placeholders** are valid, not good; they are meant to be replaced.
