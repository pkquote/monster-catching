# Test Content Pack — Design

Date: 2026-11-05
Status: Implemented (plan: ../plans/2026-11-05-test-content-pack.md)
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md).
Builds on the [battle engine reference](../battle-engine.md), the [debug team builder](2026-11-05-debug-team-builder-design.md)
(the F1 builder and `simulate.gd` are the pack's main consumers), the [passives](2026-11-04-passives-design.md) and
[held items](2026-11-05-held-items-design.md) designs.

## 1. Goal

Add a larger body of creatures, moves, items and passives, kept apart from the shipped content, so the battle engine
can be tested, simulated and poked at from the F1 builder against many more mechanics than the 8 real creatures use.
It is a scaffold: it is deleted as the real creature set is built out.

**Success:**
- A tester can pick any pack creature, move, item or passive in the F1 team builder and in `simulate.gd`.
- The pack covers every effect op, move target kind, passive/item trigger kind, `when` condition and held-item use kind
  the schemas define, and a test fails when a new one is added to the schemas without pack coverage.
- Seeded simulations over the whole pack keep every engine invariant (`test_simulation_invariants`).
- The shipped game, its save files, shops, encounters, compendium and release build are unaffected.
- Removing the pack is deleting `data_testpack/`, its `DataRegistry.PACK_ROOT` lines, the pack tests and helper, and the
  `check.sh`/tools lines; see the removal checklist in [battle-engine.md](../battle-engine.md#removal-checklist).

### Decisions

| Topic | Decision |
|---|---|
| Location | `data_testpack/`, same layout as `data/` (`creatures/`, `moves/`, `items/`, `passives/`, `tamers/`, `encounters/`), each folder optional |
| Loading | `DataLoader.load_database(root, dialogue_root, packs := [])`: pack entries are added to the same `RawData` before validation; a duplicate id is a normal validation error. `DataRegistry` adds the pack only in debug builds and only when the folder exists |
| Ids | Every pack id starts with `tp_`. `Database.is_test_content(id) -> bool` is a prefix check |
| Scope | Creatures, moves, items, passives, plus a few tamers and encounter tables. Types, statuses, field states, reactions, affinities and balance are reused from `data/` |
| Size | As built: 30 creatures, 92 moves, 27 items, 35 passives, 6 tamers, 4 encounter tables (targets were about 30 / 100 / 25 / 35 / 6 / 4). Coverage over polish |
| Naming | Dummies named for what they test (for example `tp_spreadbug`, `tp_absorb_wall`), not realistic monsters |
| Saves | Pickers that write into a real save skip `tp_` ids (F1 Fill box, F1 Set passive); wild and tamer rolls read only the shipped tables, which never name pack content; the F1 builder, battle-only paths and `simulate.gd` may use the whole pool |
| Compendium | Generated from `data/` only; unchanged |
| Phase-out | Follow the removal checklist in `battle-engine.md` (folder, `DataRegistry` pack lines, pack tests and helper, `check.sh`/tools lines, docs) |

## 2. Architecture

| Unit | Layer | Responsibility |
|---|---|---|
| `DataLoader.load_database(..., packs)` | `core/data/` | Reads each pack root with `read_raw` semantics (missing category folders skipped, not errors) and merges it into the base `RawData` |
| `Database.is_test_content(id)` | `core/data/` | `id.begins_with("tp_")` |
| `DataRegistry` | `game/autoload/` | Passes `res://data_testpack` when `OS.is_debug_build()` and the folder exists; if data/ plus the pack fails validation it logs the errors and loads `data/` alone (`load_with_fallback`) |
| `data_testpack/**` | content | The pack |
| `PackCoverage` (test helper) | `tests/helpers/` | Lists the ops, targets, triggers, `when` keys and use kinds in `DataSchemas` and reports which are not used by any pack entry |
| Callers that must skip pack ids | `game/battle/battle_launcher.gd`, `game/debug/pages/debug_passive_page.gd` | F1 Fill box (`BattleLauncher.fill_box` via `save_safe_species`) and F1 Set passive (`DebugPassivePage.save_safe_passives`) filter with `Database.is_test_content`. `BattleLauncher.roll_wild_pack` and the tamer paths have no filter: they read their encounter/tamer tables, and the base-only validation pass (`Data OK`) proves shipped tables can only name shipped content |

The F1 builder's species/move/item/passive lists and the foe randomiser use the whole database, so pack content
appears there with no change beyond the loader; the `tp_` prefix keeps it recognisable in the lists.

## 3. Content

### 3.1 Creatures (30)

- Types: every one of the 14 types as a single type at least once; at least 10 dual types; includes `neutral`.
- Stat shapes: glass cannon (high attack, low defence/HP), wall (high defences/HP, low attack), speedster, slow
  bruiser, a low-stamina/energy-starved creature, a high-luck/resolve creature, an all-minimum and an all-maximum
  stat creature (bounds).
- Growth tiers: every tier (`slow`, `steady`, `fast`) on at least one stat of several species, including a creature
  with the maximum `growth_budget`.
- Evolution: at least two chains with an Affinity branch and a default branch (`growth`), one three-stage.
- Passives and Affinity passives: each creature lists one or two passives (the schema allows at most 2) and a full
  `affinity_passives` map.
- Learnsets: some with all moves at level 1, some spread to level 40+, one with exactly one move (stall case), one
  with moves it can never learn through normal levelling (used with the F1 "can't learn" labels).

### 3.2 Moves (92)

Coverage by construction, tracked in the coverage test:
- Every effect op in `DataSchemas.EFFECT_OPS` used in at least one move where the op is move-legal.
- Every move target kind: `self`, `one_ally`, `one_enemy`, `all_allies`, `all_enemies`, `all`, `two_enemies`, and the
  side-targeting kinds the schema lists.
- Categories physical, special and status; powers across the 1–300 range; accuracy from 1 to 100 and `always_hits`.
- Edge cases: priority above and below 0; 0-power status moves; multi-effect moves (damage plus status plus stat
  stage); moves that apply, cash in (`bonus_if_field`, `consume`) and remove every field state; every status
  inflicted with and without `chance`; stat stages at the -3 and +3 limits; `heal` and `damage_fraction` at the
  fraction extremes; `skip_chance`; `scrap_power`; `restore_energy`; energy costs from free to above any creature's
  energy.
- Type coverage: at least two moves of every type, so every type matchup row is exercised.

### 3.3 Passives (35)

Every trigger `on` value (`enter`, `hit`, `round_end`, `knockout`, `faint`); `contact` and non-contact `hit`
triggers; every `when` condition the schema defines (`hp_below`, `underdog`, ...); `chance` at 1, 50 and 100;
persistent effects (`type_power`, `incoming_type_mod`, `absorb_type`, `status_immune`, `guard_stages`,
`field_shelter`, `field_boost`, `reaction_power`, `energy_discount`, `rest_bonus`, `scrap_power`, `stat_mod`); aura
(`scope: allies`) and self-only variants; overworld `field` ops (`encounter_rate`, `xp_mult`, `bond_gain`); passives
that chain into each other (a trigger that causes another passive's trigger) to exercise the depth guard.

### 3.4 Items (27)

- Held items: every `use` kind (`permanent`, `consumed`, `per_battle`) with each trigger and with auras; held
  items that overlap with a passive's effect (stacking checks).
- Healing, energy, training and capture items across their parameter ranges (small and large heals, a full
  restore, a capture item with a very high and a very low multiplier, a guaranteed catch). The engine has no
  status-cure op, so `tp_full_restore` (full heal plus full energy) stands in for the "full cure" item.

### 3.5 Tamers and encounters

Six `tp_` tamers: 1v1 basic, 2v2 tactician, 3v3 aggressive, a bench-heavy 3v6, an Underdog trainer fielding fewer
than the player, and a single-creature stall trainer. Four encounter tables: one with a single species, one with a
wide level range, one that always rolls a pack of 3, one weighted heavily to a single rare species. They are used by
tests and simulations only; no map or shop references them.

## 4. Testing

- `tests/data/test_testpack_loader.gd` (plus per-category `test_testpack_*.gd` suites and
  `test_testpack_removal.gd`, which proves the removal checklist): the pack loads and validates alone and with `data/`; no pack id collides with
  a shipped id; every pack id starts with `tp_`; `Database.is_test_content` is true only for pack ids; the loader
  tolerates a missing pack folder and missing category folders; a duplicate id across pack and base is reported.
- `tests/data/test_testpack_coverage.gd`: `PackCoverage` reports nothing uncovered for effect ops, move target
  kinds, trigger kinds, `when` keys, held-item use kinds, types, statuses and field states. Reactions are not a
  `PackCoverage` family: `tests/battle/test_testpack_mechanics.gd` triggers each of the 8 reactions in a live battle.
- `tests/battle/test_testpack_mechanics.gd`: targeted checks per pack mechanic family, each pinning a specific
  documented behaviour (a move of each op does what the schema says; each passive trigger fires once with the
  right banner; each held-item use kind behaves per its design).
- `tests/battle/test_testpack_simulations.gd`: seeded simulations over the whole pack, every format 1v1 to 3v3
  and benches up to `party_size`, asserting the invariants from `test_simulation_invariants` plus: no event
  names an unknown bid and no creature ends with HP outside [0, max].
- `tests/game/test_testpack_safety.gd`: Fill box, Set passive and the shipped wild/tamer paths never produce `tp_`
  content.
- `scripts/check.sh` validates `data/` alone (as today) and `data/` plus the pack, and runs the new suites. It must
  end "All checks passed."
- Failures that show a real engine bug are reported with the failing case, fixed separately with a regression
  test, and not hidden by loosening the pack.

## 5. Out of scope

New statuses, field states, reactions, types or affinities; balance changes; map, shop or story references to
pack content; promoting pack content into `data/`; art or audio; a UI to browse the pack beyond what the F1
builder already shows.

## 6. Risks and open assumptions

- Real engine bugs surfaced by the broader content may need their own fixes; each is handled as a separate task
  with a regression test.
- The `tp_` prefix is the only guard keeping pack content out of saves; the safety test covers the generators that
  exist today, and a note in `documentation/battle-engine.md` tells future code to use `is_test_content` when picking random species.
- Pack size makes `check.sh` slower; simulation seed counts are chosen to keep the added time under about 30 s.
