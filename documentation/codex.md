# Codex screens and where-to-find data

Reference for M7b. Design: `specs/2026-11-11-m7b-codex-screens-design.md`. The seen and caught data it reads is in
`tracking.md`.

## Screens
- **Menu → Codex** (`game/progress/codex_screen.gd`, `CodexScreen`): every species in Codex order. Rows read
  `#001 Name ●` (caught), `#002 Name ○` (seen) or `#003 ???` (unseen; activating it does nothing). The title bar
  shows "Seen n / N · Caught n / N". The left pane (`CodexPreview`) follows the focused row: sprite, number, name
  and status; an unseen species is a dark disc, `#NNN ???` and "Not seen yet".
- **Species page** (`game/progress/codex_detail_page.gd`, `CodexDetailPage`): opens for a seen species. Sprite, number,
  name and status on the left; the type names, the description (clipped to `DESCRIPTION_MAX`), and **Where to
  find it** on the right. Locations show at most `MAX_LOCATION_LINES`, then "+N more places". A species with no wild
  habitat says "Evolves from X" when X is caught, else "No wild habitat known". A seen-but-not-caught species
  ends with "Not caught yet". There is no "evolves into" line.
- Both extend `ProgressScreen`, so `ScreenFit.problems(screen)` applies.

## Numbering: `dex`
Every shipped creature has a unique `dex` (1-based, no gaps; `tests/data/test_codex_data.gd` enforces it). It is
optional in the schema because fixtures and the test pack have none; the validator rejects duplicates. `Codex.order(db)`
lists numbered species by `dex`, then the rest by id; `Codex.number_text` gives `#001`, or `#---` without one.

## Locations: `data/locations.json`
A "file" category: `{id: map id, name: map display name, areas: [encounter table ids]}`, the map's default table first,
then each `EncounterArea` piece's. Test maps (`test_*`) and maps with no encounters are left out. It is generated from the
map scenes, not written by hand:

```bash
godot --headless --path . res://tools/build_locations.tscn
```

`tools/check_maps.gd` (part of `scripts/check.sh`) fails with "data/locations.json is out of date" when the file no longer
matches the scenes. `Locations.for_species(db, species)` turns the file and the encounter tables into rows (map name,
table name, level range merged over the table's rows); `Locations.line` formats one as
"Route 1 – Route 1 tall grass, Lv 2–5". The compendium lists the same lines as a "Found:" bullet per creature.

## Adding a species so it shows up
1. A `dex` (next free number), a `description`, and the usual creature fields.
2. An encounter table that lists it, on a map's default table or an `EncounterArea` piece.
3. Run `tools/build_locations.tscn` if a map's encounters changed, then `bash scripts/check.sh`.

A species nobody can meet in the wild (a starter, an evolution) still lists; its page shows where it evolves from.
