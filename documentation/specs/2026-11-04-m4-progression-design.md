# M4 — Progression and Menus: Design

Date: 2026-11-04
Status: Approved and implemented (plan: [documentation/plans/2026-11-04-m4-progression.md](../plans/2026-11-04-m4-progression.md))
Parent spec: [Monster-Catching RPG design](2026-11-03-monster-rpg-design.md) (milestone M4), §2.5 growth,
§2.10 training points. Builds on the [M3 overworld design](2026-11-03-m3-overworld-design.md).

## 1. Goal

Make creatures grow in ways the player can see and shape: new moves after level-ups, growth into a
new species chosen by how the creature fought, a team of six managed against a storage box, and
training points the player can spend and take back.

**Success:** a player levels Tidepup to 16, learns and swaps moves, watches it grow into Torrentusk or
Mistcoil depending on its strongest Affinity, reorders the party, swaps creatures with the box, spends
training points and refunds them with a Reset Seed. Every step is covered by tests and by a
real-window tour (`--mode=progress`).

Most rules already exist in `core/` since M1 (`Progression.award_xp`, `growth_target`, `apply_growth`,
`train`, the party/storage lists). M4 adds the missing rules (move pool, set moves, respec, team
moves), the screens, and the hand-off from battles to those screens.

### Decisions

| Topic | Decision |
|---|---|
| Growth timing | Offered after the battle where it becomes due ("Grow now?"). **Not yet** keeps it ready; the player can grow it later from the summary. Asked again after a battle only when the creature gained a level in it. |
| Moves | Every learned move stays in a **move pool**. The 4 battle slots can be changed from the pool at any time outside battle. Forgetting is never permanent. |
| Storage access | **StorageBox** map pieces open the box anywhere. The menu can also swap party ↔ box at any time, **except in unsafe zones**. |
| Unsafe zones | A map-wide `unsafe` checkbox plus an **UnsafeArea** rectangle piece. Only party ↔ box swapping from the menu is blocked there; reordering, moves and training stay allowed, and StorageBox pieces still work. |
| Respec | A **Reset Seed** consumable, sold in shops, refunds all of one creature's training points. |
| Where decisions happen | On the overworld after the battle overlay closes (the "after-battle step"), using screens shared with the menus. The battle scene does not change. |
| Battle lead | The first creature in the party leads. |

### Out of scope for M4

Real growth animation and art, nicknames, held items, move tutors or relearn NPCs (the move pool
replaces them), box sorting and search, named or decorated box pages.

## 2. Data and core rules

### 2.1 Creatures and saves

- `CreatureInstance.move_pool: PackedStringArray`: every move this creature has learned, in the order
  learned. `moves` (the battle slots, at most `balance.max_moves` = 4) is always a subset of the pool.
- **Save schema v3.** `SaveStore.migrations()` gains a v2 → v3 step: each creature (party and storage)
  gets `move_pool` = its current moves, then every learnset move at or below its level that's missing.
  This also returns moves that M2's text-only offer dropped.
- "Ready to grow" is not stored: it is `Progression.growth_target(db, c) != ""`.

### 2.2 Progression (`core/progress/progression.gd`)

- `award_xp`: a learnset move reached on level-up always joins the pool. If a slot is free it also goes
  into `moves` (`move_learned` event); otherwise the event is `move_offered` (already in the pool).
- `set_moves(c, slots: PackedStringArray) -> String`: replaces the battle slots. Returns `""` or a reason:
  `"empty"` (no moves), `"too_many"` (more than `max_moves`), `"duplicate"`, `"not_in_pool"`.
- `reset_training(db, c) -> int`: clears `training`, returns the points refunded. HP and energy above
  their new maximum are clamped; a creature with HP > 0 keeps at least 1 HP.
- `apply_growth` (existing) is followed by learning every move in the new species' learnset at or below
  the creature's current level that it doesn't already have, by the same pool/slot rule (this matches
  `backfill_pool`, which fills the pool the same way on load). It returns those events in the result as
  `learned: [move]` and `offered: [move]`. To make this happen in play, Torrentusk's `quake_stomp` and
  Mistcoil's `glacier_crash` move from level 18 to 16.

### 2.3 Team rules (new `core/progress/team.gd`, `class_name Team`)

Static functions on a `SaveGame`. Each returns `""` on success or a refusal reason.

| Function | Refused when |
|---|---|
| `reorder(save, from, to)` | an index is out of range |
| `deposit(save, party_i)` | it would leave no healthy creature in the party (`"last_healthy"`) |
| `withdraw(save, box_i)` | the party already has `balance.party_size` (6) (`"party_full"`) |
| `swap(save, party_i, box_i)` | the box creature has fainted and the party creature is the last healthy one (`"last_healthy"`) |

The box has no size limit; its order is arrival order.

### 2.4 Reset Seed

- New item in `data/items/`: `{"id": "reset_seed", "name": "Reset Seed", "category": "training",
  "price": 600, "target": "one_ally", "effects": [{"op": "reset_training"}]}`, with a description.
- `training` is a new item category; the validator accepts it and `reset_training` as a field-only op.
  It never appears in the battle Items menu.
- `FieldItems.can_use` / `use` handle it: refused (`"nothing_to_refund"`, item not spent) on a creature
  with no spent points.
- Added to the heal-centre shop's stock.

### 2.5 What a battle reports

`BattleLauncher.apply_results` returns a `BattleSummary` (core/battle/battle_summary.gd) whose `progress`
is an `Array[ProgressEntry]` in party order (`creature`, `offered_moves`, `growth_due`), one entry per player
creature that gained at least one level in the battle. `growth_due` is true when `growth_target` is not
empty after the battle. The list is empty when nobody levelled.

## 3. The after-battle step

`game/progress/progress_flow.gd` (`class_name ProgressFlow`):
`static func run(parent: Node, progress: Array[ProgressEntry]) -> void` (awaitable).

- `BattleFlow.after_battle` (`Overworld.battles`) calls it after any defeat respawn and **before** the autosave, so the save
  holds the player's choices. Story battles started from scripts get the same step; its screens draw
  over the conversation box and the script carries on afterwards.
- For each entry in order: one **Learn Move** screen per offered move, then the **Grow** screen if
  `growth_due`.
- The overworld holds `Overworld.LOCK_PROGRESS` while it runs.

### 3.1 Learn Move screen (`game/progress/learn_move_screen.gd`)

- Shows "Tidepup wants to learn Riptide", the new move's type, category, power, cost and description, and
  the 4 current slots with the same details.
- **Replace a slot**: picking a slot puts the new move there (via `set_moves`); the old move stays in the pool.
- **Keep it for later**: nothing changes; the move stays in the pool. Cancel means the same.
- Reused by the summary's Moves tab.

### 3.2 Grow screen (`game/progress/grow_screen.gd`)

- "Tidepup is ready to grow! Its Striker side is strongest: it will become Torrentusk." When the default
  branch applies: "…it will become Torrentusk." (no Affinity line). **Grow now** / **Not yet**.
- Grow now: a short placeholder animation (white flash, then the creature view redrawn in the new species'
  colours), "Tidepup grew into Torrentusk!", then a Learn Move screen for each move offered by the growth.
- Reused by the summary's Grow button.

## 4. Menus

All screens are built from `UIKit` and the existing side-menu/keyboard patterns, sized for 640×360, and
fully usable with keyboard or gamepad. Each is awaitable (`run(...)`) like the M3 pause and shop menus.

### 4.1 Party screen (Menu → Party; replaces the plain list)

- Up to 6 rows: placeholder sprite, name, level, HP and energy bars, status, and a **Ready to grow** badge.
- Choosing a row: **Summary** / **Move** / **Storage** / **Cancel**.
  - Move: pick the new position; `Team.reorder`. The first row leads in battle.
  - Storage: opens the Storage screen. Disabled while `Overworld.is_safe_here()` is false, with the
    message "It isn't safe to swap creatures here."

### 4.2 Summary screen (three tabs, Left/Right to switch)

- **Stats:** every stat with its value, training points shown as "+n"; XP to the next level; Bond;
  the four Affinity tracks as bars. A **Grow** button while growth is ready (opens the Grow screen).
- **Moves:** the 4 slots and the rest of the pool. Choosing a pool move opens Learn Move for it.
- **Training:** points available; **+1** for each trainable stat (refused at the 30-point cap with the
  reason shown); "Use a Reset Seed (you have n)", disabled with none.
- Shoulder buttons (L/R, also Page Up/Down) or the "Previous creature" / "Next creature" options move to the previous/next party member (Up/Down move the menu focus).

### 4.3 Storage screen

- Party on the left, the box on the right, 10 per page. Pick a creature on one side, then a spot on the
  other: deposit, withdraw or swap. Refusal reasons are shown in plain words ("Keep at least one
  creature that can fight.", "Your party is full.").
- Opened from the Party screen (safe zones only) or a StorageBox piece (anywhere).

### 4.4 Bag

Reset Seed is used on a chosen creature like a Salve, with a confirmation that shows the points that
will come back.

## 5. Map pieces and zones

| Piece / field | Fields | What it does |
|---|---|---|
| `StorageBox` piece | — | Solid. Accept opens the Storage screen, including in unsafe zones. |
| `GameMap.unsafe` | bool | The whole map is unsafe. |
| `UnsafeArea` piece | `size` | A marker rectangle (like `EncounterArea`): tiles inside are unsafe. |

`Overworld.is_safe_here() -> bool`: false if the map is unsafe or the player's feet tile is inside an
UnsafeArea. Its `size` is clamped to at least 1×1 (like `EncounterArea`), so a zero-size area can't exist.

**Content:** a StorageBox in `town_01_center`; Route 1's deep-grass corner (13,6, size 5×4) becomes an
UnsafeArea; the centre shop stocks Reset Seeds. The map-building guide documents both pieces and the flag.

## 6. Debug tools (F1)

- **Give XP**: for a chosen party creature, "+1 level" or "to level 16". Goes through `award_xp`, then the
  real after-battle step runs.
- **Set Affinity**: raises a chosen track above `growth_affinity_threshold` (30) for a chosen creature.
- **Fill box**: adds 12 random creatures to storage.

## 7. Testing

- **Core (gdUnit):** pool on level-up (free slot vs full set); `set_moves` refusals; `reset_training`
  refund and clamps; moves learned on growth; every `Team` rule including the last-healthy refusals;
  v2 → v3 migration; `reset_seed` field use and refusal; `summary.progress` contents.
- **Overworld and screens:** the after-battle step drives Learn Move (replace, keep) and Grow (now, not
  yet) and the autosave comes after them; Not yet is offered again only after a later level-up;
  reordering changes the lead; storage refused on an unsafe map and inside an UnsafeArea but allowed at a
  StorageBox there; summary training, Reset Seed, and growing from the summary.
- **Pieces:** UnsafeArea size clamps to at least 1×1.
- **Tour:** `--mode=progress` in the run skill's driver, screenshotting: debug-level Tidepup to 16 →
  Learn Move (replace) → Grow → party reorder → summary tabs → spend a point → Reset Seed → deposit and
  withdraw at the centre's box → menu storage refused in the deep grass. The front-end, battle and
  overworld tours must still pass.

## 8. Docs

This spec; the map-building guide (StorageBox, UnsafeArea, `unsafe`); the main spec's status line; the
run skill (new mode); the compendium picks up the new item automatically.
