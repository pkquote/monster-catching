# M5b Shared Visual Pieces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the creature sprite slot, stat radar, HP/Stamina bars and creature summary card, plus an F1 "UI gallery" page and a tour to look at them.

**Architecture:** Four small `Control`s in `game/ui/` (like the existing `ItemIconSlot`), each with a `configure(...)` method and its logic in pure static helpers so tests don't depend on layout. `CreatureCard` assembles the other three. The battle's `creature_view` is changed only to call the shared sprite-drawing and HP-colour helpers.

**Tech Stack:** Godot 4.7.2, GDScript, GdUnit-style suites, the `run-godot-monster-catching-game` driver for tours.

**Spec:** `documentation/specs/2026-11-06-m5b-shared-visual-pieces-design.md`

## Global Constraints

- **Never commit, stage or stash.** The user writes every commit. Skip any commit step; at the end give a commit message in the handoff format (`{{title}}`, bullets, `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Screen is 640x360. No existing screen (Summary, Party, Box) changes; the battle's look must stay identical.
- Radar ceiling is `Stats.stat_at(100, balance.level_cap)` (203 at cap 99); values above clamp to the rim. Axes clockwise from the top: `patk, pdef, satk, sdef, spd, resolve, luck`. Values are `CreatureInstance.stat(db, key)` (base-plus-training); ▲/▼ from `db.creature(species).growth_tier(key)` via `db.balance.growth_tiers` (above 1.0 ▲, below 1.0 ▼), as `summary_screen.gd` `_render_stats` does.
- Placeholder art only. Type colours come from `TypeColors.type_color`.
- In tour files `d` is untyped, so use `=` not `:=`. Don't run two Godot processes at once.
- Godot console: `/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe`.

## Review Focus

- A species with one type, two types, and no types listed (unknown type colour): the sprite slot still draws.
- A creature at HP 0 / Stamina 0 and at max: bars draw without a divide-by-zero or negative width.
- A stat above the ceiling (heavy training, fast growth at Lv 99): the polygon clamps to the rim, the number still shows the real value.
- A creature with 0 moves, no passive and no held item, and one with a very long nickname and long move names: the card shows "none"/empty text and nothing spills outside its rect.
- Level 1 creature: radar polygon is tiny but non-degenerate (no NaN), numbers still readable.

---

### Task 1: CreatureSpriteSlot and the shared placeholder drawing

**Files:**
- Create: `game/ui/creature_sprite_slot.gd`
- Modify: `game/battle/creature_view.gd` (`_draw`, lines ~134-141: call the shared helper; keep highlight ring, flash and bars as they are)
- Test: `tests/game/test_creature_sprite_slot.gd`

**Interfaces:**
- Produces: `class_name CreatureSpriteSlot extends Control` with
  - `static func draw_placeholder(canvas: CanvasItem, center: Vector2, radius: float, types: PackedStringArray, initial: String) -> void` (outer ring in the second type's colour when there are two types, body in the first type's colour, 5px ring width scaled by `radius / 23.0`, initial letter centred, `Color(0, 0, 0, 0.65)`);
  - `func configure(db: Database, species_id: String, p_size: int = 48) -> void`;
  - `static func initial_for(name: String) -> String` (first character, "?" if empty);
  - `static func body_color(types: PackedStringArray) -> Color` (first type's colour, grey `Color("9aa0ae")` for no types) and `static func ring_color(types: PackedStringArray) -> Color` (second type's colour, or `Color(0, 0, 0, 0)` for one or none).

- [ ] **Step 1: Write the failing tests** in `tests/game/test_creature_sprite_slot.gd`: `test_body_color_is_the_first_types_colour` (`["water"]` → `TypeColors.type_color("water")`), `test_no_types_falls_back_to_grey`, `test_ring_color_only_for_two_types`, `test_initial_for` ("Tidepup" → "T", "" → "?"), `test_configure_sets_the_minimum_size` (size 48 → `custom_minimum_size == Vector2(48, 48)`), and `test_draws_for_a_real_species_without_error` (add the node to the tree, `configure(DataRegistry.db, "torrentusk", 56)`, await a frame).
- [ ] **Step 2: Run** `tests/game/test_creature_sprite_slot.gd`; Expected: FAIL (class not defined).
- [ ] **Step 3: Implement** `CreatureSpriteSlot` in `game/ui/creature_sprite_slot.gd` per the interface; `_draw` calls `draw_placeholder(self, Vector2(size/2), size/2, types, initial)`. Then change `CreatureView._draw` to call `CreatureSpriteSlot.draw_placeholder(self, center, SPRITE / 2.0, _types, _initial)` in place of the inline circles and letter, drawing the highlight ring and the flash circle exactly as before.
- [ ] **Step 4: Run** the new suite and `tests/game/test_battle_scene_smoke.gd`; Expected: PASS. Compare one battle tour screenshot against the old look in Task 5's tour (the battle sprites must not change).

### Task 2: StatRadar

**Files:**
- Create: `game/ui/stat_radar.gd`
- Test: `tests/game/test_stat_radar.gd`

**Interfaces:**
- Produces: `class_name StatRadar extends Control` with
  - `const KEYS := ["patk", "pdef", "satk", "sdef", "spd", "resolve", "luck"]` and `const NAMES := {"patk": "Phys Atk", "pdef": "Phys Def", "satk": "Spec Atk", "sdef": "Spec Def", "spd": "Speed", "resolve": "Resolve", "luck": "Luck"}`;
  - `static func ceiling(db: Database) -> int` → `Stats.stat_at(100, db.balance.level_cap)`;
  - `static func axes(db: Database, c: CreatureInstance) -> Array` of `{key: String, name: String, value: int, fraction: float (clamped 0..1), mark: String ("▲", "▼" or "")}` in `KEYS` order;
  - `static func vertex(index: int, fraction: float, radius: float) -> Vector2` (offset from the centre; index 0 points straight up, clockwise);
  - `func configure(db: Database, c: CreatureInstance, p_size: Vector2 = Vector2(180, 150)) -> void`.

- [ ] **Step 1: Write the failing tests** in `tests/game/test_stat_radar.gd`: `test_ceiling_matches_the_formula` (`== Stats.stat_at(100, db.balance.level_cap)`); `test_axes_follow_the_key_order_and_values` (creature at Lv 20, one stat trained: values equal `c.stat(db, key)`); `test_fraction_is_value_over_ceiling` (`is_equal_approx`); `test_fraction_clamps_at_the_rim` (set `c.training.patk = 500`; fraction 1.0, value still `c.stat`); `test_level_one_fraction_is_small_but_positive`; `test_marks_follow_growth_tier` (fixture or `db._tables`-edited creature with `fast`/`slow`/`steady` tiers for three stats → ▲ / ▼ / ""); `test_vertex_zero_points_up_and_one_is_clockwise` (`vertex(0, 1.0, 10)` ≈ (0, -10); `vertex(1, 1.0, 10).x > 0`); `test_draws_without_error` (in tree, await a frame).
- [ ] **Step 2: Run** `tests/game/test_stat_radar.gd`; Expected: FAIL.
- [ ] **Step 3: Implement** `StatRadar`. `_draw` draws the ring grid (4 polygons at 25/50/75/100% in a faint `UIKit.MUTED` alpha 0.35, plus spokes), the polygon filled `UIKit.ACCENT` alpha 0.35 with a solid outline, and each axis's "name value▲" text near its vertex using the theme font at size 9, nudged outward so text stays inside `size`. The radar radius leaves room for the text on the left and right. Growth marks use the same ▲/▼ glyphs as the Summary.
- [ ] **Step 4: Run** the suite; Expected: PASS.

### Task 3: ResourceBars (and the shared HP colour)

**Files:**
- Create: `game/ui/resource_bars.gd`
- Modify: `game/battle/creature_view.gd` (`_hp_color` delegates to `ResourceBars.hp_color`, or the call sites do; remove the duplicate)
- Test: `tests/game/test_resource_bars.gd`

**Interfaces:**
- Produces: `class_name ResourceBars extends Control` with
  - `static func hp_color(ratio: float) -> Color` (same thresholds and colours as `CreatureView._hp_color`: > 0.5 `6cc96a`, > 0.2 `e8c04a`, else `e2675c`);
  - `static func fill_fraction(current: int, maximum: int) -> float` (clamped 0..1, 0 when `maximum <= 0`);
  - `static func label(current: int, maximum: int) -> String` ("%d / %d");
  - `func configure(current_hp: int, max_hp: int, current_stamina: int, max_stamina: int, p_width: int = 180) -> void` (two bars, each a row "HP  ▇▇▇  cur / max" / "Stamina ...").

- [ ] **Step 1: Write the failing tests** in `tests/game/test_resource_bars.gd`: `test_fill_fraction_at_0_half_full_and_over`; `test_fill_fraction_with_zero_maximum_is_zero`; `test_hp_colour_thresholds` (0.6, 0.3, 0.1); `test_label_text`; `test_creature_view_uses_the_same_colour` (`CreatureView._hp_color(0.3) == ResourceBars.hp_color(0.3)` or the delegate's result); `test_draws_at_zero_and_full_without_error`.
- [ ] **Step 2: Run** the suite; Expected: FAIL.
- [ ] **Step 3: Implement** `ResourceBars`, then make `CreatureView` use `ResourceBars.hp_color`. Use the Stamina colour `Color("5fa8e8")` as the battle does.
- [ ] **Step 4: Run** the suite and `tests/game/test_battle_scene_smoke.gd`; Expected: PASS.

### Task 4: CreatureCard

**Files:**
- Create: `game/ui/creature_card.gd`
- Test: `tests/game/test_creature_card.gd`

**Interfaces:**
- Consumes: `CreatureSpriteSlot.configure`, `StatRadar.configure`, `ResourceBars.configure` (Tasks 1-3); `Passives.active_id(c)`, `db.passive(id).name`, `HeldItems.def_of(db, c)`, `db.move(id).name`, `TypeColors.type_color`.
- Produces: `class_name CreatureCard extends PanelContainer` with `const SIZE := Vector2(300, 340)`, `func show_creature(db: Database, c: CreatureInstance) -> void` (rebuilds its contents), and test accessors `func move_texts() -> Array`, `func passive_text() -> String`, `func held_text() -> String`, `func header_text() -> String` ("Name  Lv N").

- [ ] **Step 1: Write the failing tests** in `tests/game/test_creature_card.gd` (all add the card to the tree and await a frame): `test_header_shows_name_and_level`; `test_moves_listed_for_four_two_and_zero_moves` (4 names, 2 names, empty → no error and `move_texts()` has 0 entries); `test_passive_and_held_show_none_when_empty`; `test_passive_shows_the_active_slots_passive` (creature with both slots, `active_passive` set to the affinity slot → that passive's name); `test_held_item_name_shown` (give the creature `held_item = "oran_berry"` or a held item that exists in `data/`); `test_long_nickname_and_move_names_stay_inside_the_card` (`c.nickname` of 60 characters; every descendant `Control`'s global rect is inside the card's global rect); `test_card_has_the_fixed_size` (`size == CreatureCard.SIZE`); `test_show_creature_twice_replaces_the_contents` (second call with a different creature changes `header_text()` and doesn't add extra children).
- [ ] **Step 2: Run** the suite; Expected: FAIL.
- [ ] **Step 3: Implement** `CreatureCard`: a `UIKit`-style panel, top row (sprite slot 48px; name + level; type chips like `FieldView._chip`), the radar, the bars, a 2x2 grid of move labels (`clip_text`/ellipsis, one line each), then "Passive: ..." and "Held: ..." lines (each ellipsised to one line). Body font `UIKit.BODY_SIZE` or smaller where needed to fit 300x340; clip children to the card rect.
- [ ] **Step 4: Run** the suite; Expected: PASS.

### Task 5: Debug gallery page, tour, docs, full check

**Files:**
- Create: `game/debug/pages/debug_ui_gallery_page.gd` (`class_name DebugUiGalleryPage extends DebugPage`)
- Modify: `game/debug/pages/debug_main_page.gd` (a "UI gallery..." button after "Set passive...", enabled even without a game and while a battle is up)
- Create: `.claude/skills/run-godot-monster-catching-game/tours/ui.gd`; Modify: `driver.gd` (add `"ui"` to the tour modes list and the header comment) and `SKILL.md` (mention `--mode=ui`)
- Modify: `documentation/specs/2026-11-06-m5b-shared-visual-pieces-design.md` (Status: Implemented), `.superpowers/HANDOFF.md` (M5b paragraph, "What's next": 5c Summary, 5d Box/Party), `documentation/specs/2026-11-05-roadmap-m5-m8.md` if it tracks status
- Test: `tests/game/test_debug_ui_gallery.gd`

**Interfaces:**
- Consumes: `CreatureCard.show_creature`, `ItemIconSlot.configure`, `DebugPage.option_row` / `spin_row` (via `menu`), `CreatureInstance.create(db, species_id, level)`.
- Produces: `DebugUiGalleryPage.make_creature(db: Database, species_id: String, level: int, trained: int) -> CreatureInstance` (a throwaway creature at the level with `trained` points in every trainable stat via `c.training`; touches no save), and `func width() -> float` returning 620.0.

- [ ] **Step 1: Write the failing tests** in `tests/game/test_debug_ui_gallery.gd`: `test_make_creature_applies_level_and_training` (level 50, trained 10 → `c.level == 50`, `c.trained("patk") == 10`); `test_gallery_opens_without_a_game` (open the debug menu with no game loaded, `show_page(DebugUiGalleryPage.new())`, a `CreatureCard` exists in the page); `test_changing_the_level_changes_the_card` (set the level spin to 5 then 99; the card's `header_text()` changes and the radar's polygon fractions grow); `test_gallery_does_not_touch_the_save` (with a game loaded, party and bag unchanged after use). Mirror how `tests/game/test_debug_menu.gd` opens the menu.
- [ ] **Step 2: Run** the suite; Expected: FAIL.
- [ ] **Step 3: Implement** the page: controls on the left (species `option_row` over `db.ids("creatures")` including test-pack species when present, level `spin_row` 1..level cap, trained points `spin_row` 0..`training_cfg` max or 100, an `ItemIconSlot` strip for the item categories, and a Back button to `DebugMainPage`), the `CreatureCard` on the right; each control change rebuilds the card from `make_creature`. Add the button to `DebugMainPage`.
- [ ] **Step 4: Run** the suite and `tests/game/test_debug_menu.gd`; Expected: PASS.
- [ ] **Step 5: Write the tour** `tours/ui.gd`: new game, F1 → "UI gallery...", screenshots `u01_lv5`, `u02_lv50`, `u03_lv99` (set the level spin and fire its `value_changed`), a dual-type species with a long nickname if the page can set one (otherwise a dual-type species and the longest species name), and an `expect` that every `CreatureCard` child rect lies inside the card. Register `"ui"` in `driver.gd`. Run `--mode=ui` and Read the screenshots: no clipped text, radar numbers readable at 640x360, the card fits above the screen bottom. If the page plus the debug menu chrome can't show the 340-high card on the 360-high screen, shrink `CreatureCard.SIZE` (and re-run its tests) rather than scrolling.
- [ ] **Step 6: Re-run the battle tour** (`--mode=battle`) and check `b05_playback`/`b12`/`b13` still draw the creature circles and bars as before.
- [ ] **Step 7: Docs and handoff** edits listed under Files. Run `bash scripts/check.sh`; Expected: final line "All checks passed."
- [ ] **Step 8: Give the user** a commit message in the handoff format; do not commit.
