# Debug Team Builder, Larger Parties and Battle Test Expansion — Design

Date: 2026-11-05
Status: Implemented (plan: ../plans/2026-11-05-debug-team-builder.md)
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md).
Builds on the [battle engine reference](../battle-engine.md), the [passives design](2026-11-04-passives-design.md),
the [held items design](2026-11-05-held-items-design.md) and the [two-target moves](../plans/2026-11-05-two-target-moves.md) work.

## 1. Goal

Replace the F1 "Custom battle" page with a team builder, so a tester can set up any battle format and
exactly the creatures in it; let the party grow past 6 under a balance-file setting, with at most 3 on the
field and the rest swapped in as one action; and widen the headless battle-engine tests.

**Why.** The current page caps your side at the number of healthy creatures in your party (a one-creature
party cannot field 2 or 3), cannot set your creatures' levels, and picks the foe's species at random. Moves,
held items and passives can only be changed on real party creatures through other pages.

**Success:**
- A tester can build a team of up to `balance.party_size` creatures per side, choose how many (1–3) each side
  fields, in any combination (1v1, 2v2, 2v3, 3v3...) and so test benches and swaps, independent of the real party.
- `balance.party_size` (default 6) can be raised in `data/balance.json` up to a hard ceiling of 12
  (`BalanceDef.MAX_PARTY_SIZE`, the schema maximum), and every party-facing screen works at any value.
- Each creature's species, level, 4 moves, held item and passive are settable, with natural defaults and clear
  labels for what the species can and cannot normally have.
- The player side's bag is editable.
- A custom battle never changes the save.
- The battle engine has a rigorous headless test suite, including seeded simulations that check invariants.

### Decisions

| Topic | Decision |
|---|---|
| Party size | `balance.party_size` stays the single setting (default 6, already in the file). The schema maximum rises from 6 to a hard ceiling of 12 (`BalanceDef.MAX_PARTY_SIZE`); the value is never hard-coded elsewhere |
| Active creatures | At most 3 per side on the field (`BattleLauncher.MAX_SIDE`), unchanged; the rest of the party is the bench |
| Swap | One action: a field creature uses its turn to swap with any bench creature. Already how the engine works (priority 6); kept, and covered by tests with large benches |
| Player team | Built from scratch; temporary creatures. "Fill from my party" copies the real party into the slots |
| Save safety | Custom battles are *exhibitions*: no XP/Bond/HP/bag/money/capture/progression writes, no autosave, no defeat rules |
| Moves | Any move in the game; each labelled by whether the species learns it (see 3.3) |
| Passives / held items | Any passive or held item, or none; labelled as normal or not for the species |
| Bag | Editable counts of every item for the player side; defaults to the test bag. Foe side has no bag |
| Foe kind | Wild (catchable, fleeable, basic AI) or Tamer (tactician AI; the team may have a bench up to `party_size`; no prize money) |
| Defaults | Species random (foe) or party creature (player fill), level = party average, natural moves, species-rolled passive, no held item |

## 2. Architecture

| Unit | Layer | Responsibility |
|---|---|---|
| `CreatureSpec` | `core/battle/` | One slot: species, level, moves, held item, passive. `to_instance(db, rng)`, `natural_moves(db)`, `from_instance(c)`, validation |
| `MoveStanding` / helpers in `CreatureSpec` | `core/battle/` | Classify a move for a species and level: `LEARNED`, `LEARNS_LATER` (with level), `NOT_LEARNABLE`; same for passives/held items. Pure, tested headless |
| `BalanceDef.MAX_PARTY_SIZE` | `core/data/` | The ceiling (12) the schema and validator enforce on `party_size`; `schemas.gd` reads it |
| `BattleLauncher.exhibition_setup` | `game/battle/` | Builds the `BattleSetup` from two spec arrays (up to `party_size` each), the field counts, the foe kind and a bag. Sets `setup.exhibition = true` |
| `BattleSetup.exhibition` | `core/battle/` | Flag read by the battle scene and overworld flow to suppress all save writes |
| `DebugCustomBattlePage` + `DebugSlotEditor` | `game/debug/pages/` | The UI. The page owns the format row, tabs and the Start button; the slot editor owns one creature's controls and the bag editor is a second page |

`DebugMenu.go()` continues to start battles on the autoload, so closing the menu mid-flow can't drop the pick.

## 3. Behaviour

### 3.1 Page layout

- Top row: **You field** (1–3), **Foes field** (1–3), **Foe kind** (Wild/Tamer). The note line keeps saying
  Even fight / Underdog.
- Tabs **Your team** and **Foe team**. Each lists its creatures (1 to `party_size`) with **Add creature** and
  **Remove** per row. The first N rows (N = the side's field count) start on the field and the rest start on
  the bench, marked "bench". Field counts above the team size are clamped to it. Wild foes are one pack that
  all fights at once, so a wild team is capped at 3. Row: species, level, "Edit" (opens the slot editor). A
  team-wide **All levels** spinner with Apply sets every creature of that team.
- Your team: **Fill from my party** (copies the party, up to `party_size`, with their moves, held item, passive)
  and **Bag...** (opens the bag editor). Foe team: **Randomize** (new random species).
- **Start**, **Back**.
- Pages keep within the 360px panel; the menu already scrolls tall pages.

### 3.2 Slot editor

Species, Level (1–`level_cap`), four move slots, Held item, Passive, **Reset to natural**, **Done**.

- Changing species or level resets moves to the natural set unless the moves were hand-edited, in which case
  they are kept and the labels update.
- A move slot may be empty only if at least one other slot has a move (a creature needs a move; validation
  rejects zero moves). Duplicate moves are rejected.

### 3.3 Labelling (what the species can and cannot normally have)

Every choice list marks each option, and a summary line is shown under the slot.

- **Moves:** `✓ Lv N` learned at or below the current level; `Lv N (later)` learned above the current level;
  `✗ can't learn` not in the species' learnset (warning colour). The summary reads
  "Natural at Lv N: A, B, C, D".
- **Passive:** `★ rolls` is in the species' passive list; `Affinity` is one of its Affinity-track passives;
  `✗ not normal` otherwise (warning colour). Default is the species' rolled passive.
- **Held item:** held items have no per-species rules, so every one is available to every species and none
  carries a warning label. The default is "(none)".

### 3.4 Bag editor

A page listing every item with a count spinner (0–99), grouped by category. **Reset to test bag** restores
`BattleLauncher.TEST_BAG`; **Clear all** sets every count to 0. The bag is used only for the player side.

### 3.5 Exhibition rules

`BattleSetup.exhibition == true`:
- `battle_scene._results()` skips `BattleLauncher.apply_results` and uses a summary built from the result only.
- `battle_flow.after_battle` skips defeat handling, progress screens and the autosave; `run_battle` is called
  with defeat rules off.
- The results panel states that nothing was saved. A caught wild creature is shown but discarded.
- XP is still awarded in the battle (so level-up behaviour is visible) but never persisted.

### 3.6 Larger parties

- `schemas.gd` allows `party_size` 1–`MAX_PARTY_SIZE`; the validator and `tools/validate_data.gd` reject
  values outside it with the existing error format. Nothing else hard-codes 6 (checked: the only uses are
  `Team`, `BattleLauncher.add_to_party`, the save-slot summary and the compendium, all reading the balance).
- Screens that list the party get a real-window check at party sizes 6 and 12: the Summary and Team pages,
  Storage (party rows plus box rows must still fit the 360px screen, paging if needed), the battle's swap and
  "send out who?" menus (scroll or page when the bench is long) and the item target list.
- Shrinking `party_size` below an existing save's party is allowed: the save keeps its creatures, no new ones
  can be added until the party is under the limit, and the validator warns only on data, never on saves.
- Simulations and tests read `db.balance.party_size`; `tools/simulate.gd --party N` is clamped to it.
  The engine suites (`tests/battle/test_formats.gd` and friends) deliberately hard-code benches of 9 and do not read the fixture's `party_size` (6): the engine has no cap, so those suites test benches independent of it.

### 3.7 Bugs to fix in passing

- Player side capped by party size (the reported issue).
- Foe level was the only editable level (the reported issue).
- Any further F1 problem found while building is listed in the plan's task for it, not fixed silently.

## 4. Testing

New headless suites under `tests/battle/` plus one for the builder:

- **Builder** (`tests/battle/test_creature_spec.gd`): defaults, `natural_moves` equals `CreatureInstance.create`,
  classification of moves/passives, validation (no moves, duplicate moves, unknown ids, level clamp),
  `from_instance` round trip.
- **Exhibition** (`tests/game/test_debug_custom_battle.gd`): the save is byte-identical after a finished
  exhibition (party, bag, money, flags); a one-creature party can start 3v3; bag editor round trip; level
  "All" applies to the right team.
- **Formats** (`tests/battle/test_formats.gd`): every combination 1v1...3v3 runs to completion for several
  seeds with scripted actions; bench and replacement rules hold, including benches of 3 to 9 (parties up to 12).
- **Swaps** (`tests/battle/test_swaps.gd`): a swap costs the swapper's action; it resolves at priority 6 before
  moves; stat stages reset on the creature leaving; swapping in a fainted or on-field creature is rejected;
  every bench slot of a 12-creature party is reachable; replacement after a faint picks from a long bench.
- **Party size** (`tests/data/test_balance_party.gd`): schema accepts 1–12 and rejects 0 and 13;
  `Team.add`/`BattleLauncher.add_to_party` respect a changed `party_size`; storage overflow at the new limit.
- **Targeting** (`tests/battle/test_targeting_matrix.gd`): each move target type (self, one enemy, all
  enemies, ally, two_enemies) with 1–3 foes standing, including fainted slots; `two_enemies` valid pairs,
  fewer than two enemies left, and the spread multiplier table.
- **Passives / held items in multi-creature formats**: aura scope, consumed and per-battle limits across
  several holders, absorb effects with spread moves.
- **Seeded simulations** (`tests/battle/test_simulation_invariants.gd`, using the `simulate.gd` loop):
  over a fixed seed list and formats, every battle terminates within the round limit; HP stays in
  [0, max]; fainted battlers never act; no event references a missing battler; the same seed reproduces the
  same event log.
- `bash scripts/check.sh` must end "All checks passed." The battle-engine doc gains a short "Testing" note.

## 5. Out of scope

Rebalancing anything for bigger parties (XP split, encounter sizes), more than 3 active creatures,
a swap that is free or limited per turn, saving named teams, a foe bag/items, editing stat points or Affinity, nicknames, a foe move-by-turn script,
and changes to real-party tools (Set Affinity, Set passive, Give XP).

## 6. Risks and open assumptions

- Dependence on `apply_results` being skipped cleanly: covered by the byte-identical save test.
- Passive/held-item labelling assumes passive lists live on `CreatureDef.passives` and
  `affinity_passives`; verified against the current data.
- UI size on the 360px panel is checked in the real window with a screenshot before sign-off.
