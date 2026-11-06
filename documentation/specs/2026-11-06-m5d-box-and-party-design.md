# M5d Box and Party

Status: Implemented. Plan: `documentation/plans/2026-11-06-m5d-box-and-party.md`.

Amendments made while implementing:
- The `mark` default is V / gamepad Y (X is Cancel, West is Run).
- `Team.move` also takes `{"party": party.size()}` from a party member to mean "the end of the party" (a reorder).
- Party rows show the name, level and HP on the first line and the status and "Ready to grow" badges on a second
  line, with the sprite on the left and the HP / Stamina bars on the right (the card takes the left of the screen).
  Energy is no longer in the row text; its bar remains.
- Loading a save with more creatures than `MAX_BOXES` boxes hold keeps them all (the box count rises past the
  ceiling for that save); `BattleLauncher.add_to_party` opens another box rather than lose a catch.
Roadmap: `documentation/specs/2026-11-05-roadmap-m5-m8.md` (5d). Depends on 5b (`CreatureSpriteSlot`, `CreatureCard`) and 5c.

## Goal
Replace the text-row Box with a set of boxes, each a grid of sprite slots; pick creatures up and place them (one or
several at a time) while the summary card follows the cursor; and show the Party with the same sprite slots and card.
Every current rule stays (a fighter must remain in the party, the party size cap, the safe-places-only rule).

## Decisions
- Slot-addressed boxes: 8 boxes of 30 slots (6x5) to start; `boxes_unlocked` in the save lets later content raise it
  (ceiling `MAX_BOXES = 32`). Creatures stay in the slot they were placed in; empty slots show as empty.
- Interaction is pick up and place, for one creature or a marked group.
- A group fills empty slots in reading order from the cursor and never swaps; too few empty slots refuses with a count.
- Box switching reuses the shoulder actions (`prev_creature` / `next_creature`, PageUp/PageDown).
- A new rebindable action `mark` (default V / gamepad Y; X is Cancel and West is Run) marks creatures for a group move.
- Capture is refused up front when the party and every unlocked box are full (no creature is ever lost).
- Out of scope: how boxes are earned (the F1 menu gets "Unlock a box" for testing), box names and wallpapers,
  sorting, party-to-party group moves, art (M7).

## Data (`core/`)
- `SaveGame.storage` becomes a fixed-length `Array` of `boxes_unlocked * BoxStorage.BOX_SIZE` entries, each a
  `CreatureInstance` or `null`; new `boxes_unlocked: int` (default `BoxStorage.START_BOXES = 8`). `to_dict` writes
  `null` for empty slots; `from_dict` pads or trims to the slot count (never dropping a creature: it raises
  `boxes_unlocked` first, up to `MAX_BOXES`).
- Schema 5 -> 6 migration in `core/save/save_store.gd`: the old list keeps its order, is packed into the first slots,
  padded with `null` to at least 8 boxes, and `boxes_unlocked = max(8, ceil(n / 30))`. A schema-5 fixture test.
- `core/progress/box_storage.gd` (`BoxStorage`, static): `BOX_SIZE := 30`, `COLUMNS := 6`, `START_BOXES := 8`,
  `MAX_BOXES := 32`; `slot_count(save)`, `box_count(save)`, `box_of(slot)`, `index_in_box(slot)`, `creature_at(save,
  slot)`, `first_empty(save, from := 0)`, `empty_count(save)`, `count(save)`, `all_creatures(save)`, `add(save, c) -> bool`
  (first empty slot; false when full), `unlock_box(save) -> bool` (false at `MAX_BOXES`).
- Callers move off `storage.append`: `BattleLauncher.add_to_party` (to `BoxStorage.add`), `BattleLauncher.fill_box`, and
  `GameState` (counts and loops skip `null`). `BattleLauncher.room_left(db, save) -> int` (party room plus empty box
  slots).
- Capture with no room: the battle's item menu disables capture items when a game save is attached and
  `room_left == 0`, with the reason "No room for another creature." Exhibitions are unaffected.

## Rules (`core/progress/team.gd`)
- A location is `{"party": i}` or `{"box": slot}`.
- `Team.move(db, save, from, to) -> String` (reason or ""): destination empty box slot -> move; occupied -> swap; the
  position just past the last party member -> append to the party; another party slot -> reorder. Refusals:
  `bad_index`, `last_healthy`, `party_full`. A swap/move that would leave the party without a healthy creature is
  `last_healthy`.
- `Team.move_group(db, save, froms: Array, to) -> Dictionary` `{reason, moved, short}`: places each source, in order, into
  the next empty slot from `to` (box: reading order across boxes starting at `to`'s box; party: the free room, appended).
  Never swaps. If there aren't enough empty slots nothing moves, `reason = "no_room"` and `short` says how many more
  are needed. `last_healthy` and `bad_index` as above.
- `Team.deposit`, `withdraw`, `swap` stay as thin wrappers over `move` (existing tests keep their meaning).

## Box screen (`game/progress/storage_screen.gd`, rewritten)
- Keeps `StorageScreen.run(world, save = null, db = null)` so `PartyScreen` and the tests still open it. It is a
  full-screen overlay of its own (not a `CommandMenu` list), still opened only where swapping is safe.
- Layout (640x360, 4px margin): the party as a 2x6 column of 36px slots on the left, the current box as a 6x5 grid of
  36px slots in the middle (header "Box 3 / 8" with focusable previous/next arrows), the 300x272 `CreatureCard` on the
  right, and a one-line help at the bottom (Accept, Mark, Box, Back).
- A slot is a focusable button: `CreatureSpriteSlot` placeholder, a small status/held mark, an empty look, a marked
  look, and a carried look for creatures picked up. Focus moves with the arrows by geometry across the party column
  and the grid. Focusing a slot shows its creature on the card ("Empty" for an empty slot).
- Interaction: Accept on a creature picks it up (or, with marks, the marked group, shown as a count badge on the
  cursor); Accept on a slot places it (`Team.move` / `Team.move_group`); Cancel puts it back; with nothing held,
  Cancel closes the screen. `mark` toggles a mark on the creature under the cursor; marks must come from one place
  (the party or the current box): marking elsewhere clears the old marks. A held group can be carried to another
  box (shoulders / header arrows) and placed there. Refusals show text in the help line (`last_healthy`,
  `party_full`, `no_room` with the count).
- The `mark` action is added to the Settings action table, rebindable in Settings > Controls (default V, gamepad Y).

## Party screen (`game/progress/party_screen.gd`)
- Same actions and rules (Summary, Move, Storage). The `CreatureCard` goes on the left through `set_side` and follows
  the focused row (the menu's `hovered` signal). Each row's flat colour swatch becomes a real `CreatureSpriteSlot`
  icon; HP and energy bars, status and "Ready to grow" stay on the rows.

## F1 debug
- Main page: "Unlock a box" (calls `BoxStorage.unlock_box`, status line shows "N boxes"). Fill box uses `BoxStorage.add`
  and stops when full. The test-pack safety rules (never put `tp_` creatures in a save) stay.

## Tests
- `tests/progress/test_box_storage.gd`: every helper, `unlock_box` and its ceiling, `add` when full.
- `tests/progress/test_team.gd` (extend): `move` to empty/occupied slots, into the party (append, reorder, full,
  last healthy), box-to-box; `move_group` fill order, across a box boundary, `no_room` with `short`, party room,
  last healthy, never swapping.
- Save: schema-6 round trip with holes; a schema-5 migration fixture (old list order preserved, boxes padded, many
  creatures raising `boxes_unlocked`); old tests that build `save.storage` adapt to the slot model.
- Capture: refused when the party and all boxes are full; allowed with one empty slot; exhibitions unaffected.
- Screens: the Box screen's cursor and card following, pick up/place/cancel, marks (one source, clearing, group
  placement, carry across boxes), box switching, refusals text, fits 640x360 (full party of 12, full boxes, long
  names); the Party screen's card following and icons; `PartyScreen` -> Storage still works and stays disabled in
  unsafe places.
- A tour (`--mode=party` / a new box tour): Box screen, a pick up and place, a marked group moved to another box,
  Party screen with the card; screenshots checked by eye. `bash scripts/check.sh` stays green.
