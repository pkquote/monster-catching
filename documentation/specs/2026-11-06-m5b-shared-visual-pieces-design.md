# M5b Shared visual pieces

Status: Implemented.
Roadmap: `documentation/specs/2026-11-05-roadmap-m5-m8.md` (5b). Depends on nothing; 5c (Summary) and 5d (Box and Party) build on it.

## Goal
Reusable UI pieces for showing a creature: a sprite slot, a stat radar, HP/Stamina bars, and a summary card that
assembles them. `ItemIconSlot` already exists from M5a. Placeholder art only; M8 swaps real art into the slots.
Screen size is 640x360.

## Decisions
- **Radar scale (decided):** a fixed ceiling for every creature, `Stats.stat_at(100, balance.level_cap)` (203 at
  level cap 99). The polygon grows with level; values above the ceiling clamp to the rim.
- **Radar axes:** Physical Attack, Physical Defense, Special Attack, Special Defense, Speed, Resolve, Luck,
  clockwise from the top. HP and Stamina are the two bars under it. Values are base-plus-training totals
  (`CreatureInstance.stat`), as the Stats tab shows today, with the growth ▲/▼ marker from `growth_tier`.
- **Preview:** an F1 "UI gallery" debug page (no save changes), plus a tour.
- No existing screen changes (Summary, Party, Box are 5c/5d). The battle keeps its own `creature_view`.

## Components (`game/ui/`)
Each is a `Control` with a `configure(...)` method, like `ItemIconSlot`; drawing is separate from pure helpers.

- `CreatureSpriteSlot`: `configure(db, species_id, size)`. Draws the type-coloured circle used by
  `creature_view` (second ring for a dual type, species initial in the centre). The drawing moves into one static
  helper (`CreatureSpriteSlot.draw_placeholder(canvas, center, radius, types, initial)`) that `creature_view._draw`
  also calls, so there is one place to replace with art.
- `StatRadar`: `configure(db, creature)`. Ring grid at 25/50/75/100% of the ceiling, the polygon, and each axis's
  value (with ▲/▼) at its vertex. Pure helper `StatRadar.axes(db, creature) -> Array` of
  `{key, name, value, fraction, mark}` and `StatRadar.ceiling(db) -> int`; the Control only draws these.
- `ResourceBars`: `configure(current_hp, max_hp, current_stamina, max_stamina)`. HP bar coloured like the battle's
  (`creature_view._hp_color` logic shared), Stamina bar blue; each labelled "cur / max".
- `CreatureCard`: fixed size 300x272 (the F1 menu caps a page at 320px with its title, so it can't be taller). `show_creature(db, creature: CreatureInstance)` fills: sprite slot,
  name, level, type chips, radar, bars, moves (2x2, ellipsised), active passive, held item. Works with 0-4 moves,
  no passive and no held item.

## Debug gallery
`game/debug/pages/debug_ui_gallery_page.gd`, added to the F1 menu like the other pages: pick species, level, and
trained-stat amounts; shows one `CreatureCard` and (for reference) an `ItemIconSlot`. Builds a throwaway
`CreatureInstance`; never touches the save.

## Testing
- Unit (`tests/game/`): `StatRadar.axes` values, fractions, clamping above the ceiling, the ▲/▼ marks from growth
  tiers; `CreatureSpriteSlot` colours for single and dual types; `ResourceBars` at 0, 50 and 100%; `CreatureCard`
  fills every field for 0-4 moves, no passive, no held item; long names ellipsised, not overflowing the card
  (rect inside the card).
- Real window: a `--mode=ui` tour screenshots the gallery at Lv 5, Lv 50 and Lv 99 and with a dual-type creature
  with a long name; screenshots checked by eye.
- `bash scripts/check.sh` stays green.

## Amendments
- The sprite slot's drawing helper takes an optional hit-flash alpha so the battle's flash still sits under the letter.
- `CreatureView._hp_color` now delegates to `ResourceBars.hp_color`; the stamina colour is `ResourceBars.STAMINA_COLOR`.
- The gallery page also has Nickname and Held item controls, and shows the item category icons.

## Out of scope
Replacing Summary, Party or Box (5c/5d), real art (M8), radar animation, changing the battle's creature view.
