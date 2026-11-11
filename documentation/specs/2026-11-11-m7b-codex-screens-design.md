# M7b Codex screens — Design

Date: 2026-11-11
Status: Implemented, with amendments (plan: [documentation/plans/2026-11-11-m7b-codex-screens.md](../plans/2026-11-11-m7b-codex-screens.md)).

**Amendments made in the plan and implementation** (the text below is the original design):
- `dex` is optional in the schema and the validator rejects duplicates; "every shipped creature has one" is a data test (`test_codex_data.gd`), because validator fixtures have none.
- `data/locations.json` stores `{id, name, areas: [encounter ids]}` per map only; the area label is the encounter table's own `name`, read at runtime. It is generated from the map scenes by `tools/build_locations.tscn`, not `build_maps.gd`.
- Both screens extend `ProgressScreen`, not the side menu; the list scrolls instead of paging, and hides while a page is open.
- The page shows at most 4 location lines (then "N more places") and a description of at most 180 characters, instead of a scroll container.
- Debug test content (`tp_`) is not in the Codex; the header counts only listed species.
Parent: [M7 Collection and achievements](2026-11-11-m7-collection-achievements-design.md), sub-project 7b.
Builds on [7a Tracking](2026-11-11-m7a-tracking-design.md) (the Codex data) and the
[M5b shared visual pieces](2026-11-06-m5b-shared-visual-pieces-design.md) (`CreatureSpriteSlot`).

## Goal
Let the player open a **Codex** from the pause menu: a list of every species with its seen/caught state, and a
detail page per seen species showing its sprite, description and where it can be found. No gameplay changes.

**Success:** the pause menu opens the list; unseen species reveal nothing; a seen species opens a page with sprite,
name, number, types, description and where to find it; both screens fit 640x360 and work on keyboard and gamepad;
`bash scripts/check.sh` ends "All checks passed."

## Decisions
| Topic | Decision |
|---|---|
| Numbering | New required `dex` int on shipped creatures, unique; Codex order is `dex`, then id |
| List widget | The side-menu pattern (command list on the right, preview on the left, as the bag), not a new row widget |
| Unseen species | Row `#NNN ???`, does nothing when activated; preview is a dark silhouette and "Not seen yet" |
| Locations | Shown once the species is seen |
| No wild habitat | "Evolves from X" if X is caught, else "No wild habitat known"; no "evolves into" line |
| Gifts, starters, tamer teams | Not listed as locations (out of scope, as in the M7 design) |

## Data
- **`dex`:** `creatures` schema gains `"dex": {"t": "int", "min": 1}`. The validator requires it on shipped
  creatures and rejects duplicates; the test pack is exempt and sorts after shipped species. All eight shipped
  creatures get a number.
- **`description`:** already optional on creatures. A shipped creature without one is a validation warning. Every
  shipped creature currently has one.
- **`data/locations.json`:** new category `locations`, a "file" category, written by `tools/build_maps.gd`:
  `{"schema": 1, "maps": {map_id: {"name": display_name, "areas": [{"label": ..., "encounter": id}]}}}`. Each map
  contributes its `default_encounter` and one area per `encounter_area` piece; `label` is the encounter table's own
  `name`. The two test maps are skipped. The validator checks every encounter id exists. The existing map check
  fails when the scenes and the file disagree.
- **`Locations` (`core/progress/locations.gd`, static, pure):** `for_species(db, species) -> Array` returns one row
  per (map, encounter table) that can spawn the species: `{map: name, area: label, min: int, max: int}` with the
  level range taken from that table's entry for the species. A map with the same table as default and as an area
  yields one row.
- **Evolves from:** `Locations.evolves_from(db, species) -> String` returns the species whose `growth` has
  `into == species` (empty when none; with several sources, the lowest `dex`).

## Screens
Both are `SideMenu`-style (keyboard and gamepad navigation come with it).

- **Entry:** a **Codex** row in `PauseMenu`, between Bag and Save, run as `await _codex()`.
- **`CodexScreen` (`game/progress/codex_screen.gd`):** command list on the right, paged at the side menu's row
  count. Header: "Seen n / N · Caught n / N". Rows: `#001 Name ●` (caught), `#002 Name ○` (seen), `#003 ???`
  (unseen, activating does nothing). Hovering a row fills the left pane with a `CreatureSpriteSlot`, the name and
  the status; an unseen species shows a dark silhouette and "Not seen yet". Close returns to the pause menu.
- **`CodexDetailPage` (`game/progress/codex_detail_page.gd`):** opened by activating a seen row; a full 640x360
  panel over the dimmed map. Large `CreatureSpriteSlot`, name, number, type chips, the description ("No description
  yet." when absent), and **Where to find it**: one line per `Locations.for_species` row, e.g.
  "Route 1 – Route 1 tall grass, Lv 2–5"; with no rows, "Evolves from X" when X is caught, else "No wild habitat
  known". A seen-but-not-caught species adds "Not caught yet". The lines sit in a scroll container. Back returns to
  the list with the same row focused.
- **Reveal rule:** a page and any location text exist only for seen species; the unseen row and preview carry no
  name, types, description or location.

## Docs and tooling
- `documentation/compendium.md` (generated) gains a "Found:" line per creature from `Locations`.
- A short `documentation/codex.md` records `dex`, `locations.json` and what a new species needs to show up
  (a `dex`, a `description`, an encounter table in a map).
- Tour `--mode=codex`: list with caught, seen and unseen rows, then a detail page for a caught and a seen species.

## Tests
- `Locations`: one row per map and table, level range, default and area table counted once, no rows for a species
  with no wild source, `evolves_from`.
- Validator: `dex` required and unique on shipped, exempt on the pack; `locations.json` bad encounter id; shipped
  creature without a description warns.
- Map check: `locations.json` out of date with the scenes fails.
- `CodexScreen`: row labels by status, header counts, unseen row does nothing and leaks nothing, hover preview,
  paging with more species than rows.
- `CodexDetailPage`: sprite, description or fallback, locations, evolves-from only when the source is caught,
  "Not caught yet", scroll with many locations.
- Screen fit at 640x360 for both, using the longest description and the species with the most locations.
- Pause menu has the Codex row and returns to the menu.
- Existing suites stay green; the pack simulation tests are unaffected (no content added to the pack).

## Out of scope
Achievements (7c), per-sighting location tracking, gifts and tamer teams as locations, "evolves into" hints,
sorting or filtering the list, real art (M8).
