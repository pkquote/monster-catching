# M5c Summary redesign

Status: Implemented.
Roadmap: `documentation/specs/2026-11-05-roadmap-m5-m8.md` (5c). Depends on 5b (`CreatureCard`). 5d (Box and Party) comes after.

## Goal
Replace the three-tab Stats / Moves / Training Summary with a layout built around the 5b `CreatureCard`: the card is always
on screen on the left, and a menu on the right opens the actions. Every current action and rule stays.

## Decisions
- Layout: card on the left, info block and a one-column menu on the right (not tabs, not one flat list).
- Moves, training and held item open sub-lists in the right column, with Back to return.
- Left/Right switch to the previous/next creature on the top-level menu (the shoulder buttons already do); tabs are gone.
- The "(grown+trained)" stat breakdown is dropped: the radar shows totals with the growth ▲/▼ marks and the Train rows
  show the trained amount.
- Training changes show on the card live.

## Layout (640x360, 4px margin)
- `ProgressScreen` gains an optional side control: `set_side(control)` (called before the screen is added to the tree,
  or in `_ready` of a subclass before `super()` builds the column) puts it to the left of the existing info panel and menu
  column. Party, Storage, Grow, Learn Move and the other progress screens do not call it and are unchanged.
- `SummaryScreen` sets a `CreatureCard` (300x272) as the side control; its column is 332px wide, and `menu.button_width`
  is one column (about 316).
- Right column, top: the info block (the base's title and body, plus `_extra`):
  - title "Name  Lv N" with the position "(2 / 5)" when the party has more than one creature;
  - "XP to next level: N" (or "Max level") and "Bond: N" on one line;
  - active passive name and description; the other passive greyed, or "Affinity passive: unlocks when a track reaches N";
  - "Held item: name - description", one line, ellipsised at `HELD_LINE_MAX`;
  - the four affinity bars in a 2x2 grid (shorter bars than today);
  - the notice line.
- Right column, below: the menu.

## Menu flow
Top level, in order (entries shown only when they apply):
1. `Grow` (when `Progression.growth_target` is non-empty) -> `GrowScreen.run`, unchanged.
2. `Moves...` -> moves list.
3. `Train...` -> training list.
4. `Held item...` -> held list.
5. `Use <passive>` (when the other passive slot holds one) -> `Passives.set_active`.
6. `Previous creature` / `Next creature` (when the party has more than one creature; wrap).
7. `Back` (closes the screen).

Sub-lists (each ends with `Back`, which returns to the top level with focus on the entry that opened it):
- **Moves**: body shows "Equipped:" with `LearnMoveScreen.move_line` per move and "- empty -" slots; the options are the
  other known moves ("pick one to swap it in" / "No other known moves."); picking one runs `LearnMoveScreen.run(parent, c,
  move, true, db)`.
- **Train**: "Points to spend: N", then one row per `DataSchemas.TRAINABLE_STATS` ("+1 <Name>  (+k)" when trained), then
  "Use a Reset Seed (you have N)" (disabled at 0) with the existing `ResetSeedPrompt.confirm` and `FieldItems.use`. Each
  +1 calls `Training.train`; notices for `stat_capped` and `not_enough_points` as today. The card refreshes after each change.
- **Held item**: `Swap held item` / `Take back` / `Give held item` exactly as now (`HeldItems.give/take`, `_bag_held`).

## Input
- `ui_left` / `ui_right` act as previous / next creature only while the top-level menu is showing (not in a sub-list, not
  while a sub-screen is open). `next_creature` / `prev_creature` (shoulder buttons) work the same way.
- Up/Down keep the menu's own focus navigation.

## Code
- `game/progress/summary_screen.gd`: rewritten around the flow above. Removes `tab`, `TABS`, `TAB_NAMES`, `show_tab`,
  `next_tab`, `_render_stats/_render_moves/_render_training` in their current form. Keeps `run(parent, party, index, save,
  db)`, `creature()` and `show_creature(index)` (the party screen and tests use them).
- `game/progress/progress_screen.gd`: the side-control slot only.
- `game/ui/creature_card.gd`: no change expected; Summary calls `show_creature` after each change.
- `.claude/skills/run-godot-monster-catching-game/tours/progress.gd`: the Summary tab steps become menu-flow steps.

## Tests
- Rewrite `tests/world/test_summary_screen.gd` for the new flow: top-level entries by state (Grow present/absent, Use
  passive present/absent, Previous/Next only with >1 creature); Moves swap; Train +1 until the cap and out of points, with
  the notice and the card's radar changing; Reset Seed confirm and cancel; Held give/swap/take; Left/Right and shoulder
  buttons switch creature (and are ignored in sub-lists); Back from a sub-list returns to the top level; fits 640x360
  (`_assert_fits`) with a long nickname, a long held-item description and a full party.
- Update `tests/game/test_screens_smoke.gd` and `tests/world/test_party_screen.gd` where they touch the Summary.
- Add a `ProgressScreen` side-control test (other screens unchanged).
- `bash scripts/check.sh` stays green.

## Amendments
- The greyed passive line and the affinity bars sit in a panel under the card (the card leaves about 80px), not in the right column; the right column holds only the info lines and the menu.
- `HELD_LINE_MAX` is 48 (the info block is narrower than before).
- The fullest top level (grow, held item, use passive, previous/next, long text) scrolls inside its area; ordinary ones fit without scrolling.
- `Held item...` is shown only when the creature holds an item or the bag has one.

## Out of scope
Box and Party redesign (5d), real art (M7), changing training/growth/passive/held rules, editing the card's contents.
