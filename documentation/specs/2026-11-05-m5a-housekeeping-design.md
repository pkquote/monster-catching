# M5a Housekeeping — Design

Date: 2026-11-05
Status: Implemented (plan: ../plans/2026-11-05-m5a-housekeeping.md)
Parent spec: [Roadmap M5–M8](2026-11-05-roadmap-m5-m8.md) (sub-project 5a). Builds on the
[M3 overworld design](2026-11-03-m3-overworld-design.md) (pause menu, bag), the
[M4 progression design](2026-11-04-m4-progression-design.md) (Reset Seed) and the
[held items design](2026-11-05-held-items-design.md).

## 1. Goal

Three small, independent fixes from the 2026-11-05 playtest notes: the Controls tab must scroll with the arrow
keys, the bag must show a summary of the focused item, and the compendium must be re-audited against the
systems added since it was last laid out.

**Success:**
- With the keyboard or a gamepad alone, a player can focus every binding on the Settings Controls tab; the view
  scrolls to keep the focused binding visible.
- In the bag, moving the cursor over an item shows its icon slot, name, category, owned count, price,
  description, generated effect lines and a "usable now?" line, before the item is picked.
- The effect text shown in the bag and in the compendium comes from one shared piece of code.
- The compendium has no duplicated sections, a complete contents table with working links, a reading order that
  puts rules before the content that uses them, and an entry for every current system.
- `bash scripts/check.sh` ends "All checks passed."

### Decisions

| Topic | Decision |
|---|---|
| Controls fix | Each Settings tab's `ScrollContainer` gets `follow_focus = true` |
| Bag pane content | Under a placeholder icon: name, category, owned count, price, description, generated effects, "Usable now?" line (option C from the brainstorm) |
| Effect text | Moved to a pure `core/data/effect_text.gd` (`EffectText`); the compendium tool and the bag both use it |
| Icon slot | `ItemIconSlot` (a `Control` in `game/ui/`): a category-coloured rounded square with the category's initial; 5b reuses it |
| Usability | New pure `FieldItems.usability(db, save, item_id)` returns `{ok: bool, reason: String}` |
| Compendium order | Rules and Balance, Types, Affinities, Statuses, Field States, Reactions, Passives, Held items, Moves, Items, Creatures, Tamers, Encounters |
| Refactor safety | The shared-text refactor is verified by regenerating the compendium and getting a byte-identical file before any audit change is applied |

## 2. Controls tab scrolling

`SettingsMenu._tab()` creates one `ScrollContainer` per tab (Audio, Display, Gameplay, Controls). None sets
`follow_focus`, so moving focus with the arrow keys to a binding below the visible area does not move the view.

- Set `scroll.follow_focus = true` in `_tab()`.
- Check by hand that Down from the tab bar enters the tab's content and Up from the first control returns to the
  tab bar; fix focus neighbours only if that does not already work.
- Test (`tests/game/test_screens_smoke.gd` or a new `test_settings_scroll.gd`): open the Settings scene, select the
  Controls tab, focus the last binding button, wait one frame, and assert the scroll container's
  `scroll_vertical` moved so that the button is inside the visible rectangle; repeat for the Gameplay tab if it
  overflows.

## 3. Bag item summary

`PauseMenu._bag()` is a two-pane `SideMenu`: the command list is on the right and an info page on the left.
Today the left page says "Pick an item." and shows an item only after it is chosen.

### 3.1 Behaviour

- Each bag option carries `hint: item_id`; the "Back" option carries no hint. The bag connects to
  `menu.hovered` while the list is up (as the shop already does) and redraws the left pane.
- The left pane shows, top to bottom: the `ItemIconSlot` (48x48) beside the name, category and "Owned: N"; the
  price; the description; the **Effect** lines from `EffectText`; the **Usable now?** line. With no hint it shows
  "Pick an item."
- The pane must fit 404x344 for any item, including the longest compendium description; long text wraps.
- After choosing an item the existing flow is unchanged: the "use on who?" list for usable items, the "can't be
  used" message otherwise.

### 3.2 Usability

`FieldItems.usability(db, save, item_id) -> Dictionary {ok: bool, reason: String}` (pure, no UI):

| Item | ok | reason |
|---|---|---|
| unknown id | false | "Unknown item." |
| category `held` | false | "Give it from the Summary." |
| category `capture` or `battle` | false | "Used in battle." |
| category `key` | false | "Can't be used." |
| `heal` item that `can_use` and at least one living party creature is below the item's target (HP below max for `heal`, energy below max for `restore_energy`) | true | "Usable now." |
| `heal` item that `can_use` but no living creature would gain anything | false | "No one needs it right now." |
| `training` item (Reset Seed) and at least one creature has spent training points | true | "Usable now." |
| `training` item and no creature has spent points | false | "No one has training points to return." |
| any other usable-by-category item that `can_use` rejects | false | "Can't be used here." |

### 3.3 Icon slot

`ItemIconSlot` draws a rounded square in a colour per category (capture, heal, battle, key, training, held)
with the category's initial in the centre, at a fixed size set by a property so the same slot can be used at
other sizes by 5b. The colours are constants in the class (no new data). Art replaces the drawing in M7.

## 4. Shared effect text

`tools/generate_compendium.gd` holds the code that turns data into text: `_effect`, `_effects`, `_when`,
`_triggers` (only the pieces that describe an effect), and the label tables they need (`SIDE_LABELS`,
`TARGET_LABELS`, `TRIGGER_LABELS`, `STAT_LABELS`) with helpers `_pct`, `_num`, `_signed`, `_state_name`.

- Move these into `core/data/effect_text.gd` (`class_name EffectText extends RefCounted`) as static functions
  taking the `Database`: `EffectText.effects(db, effects: Array) -> String`, `EffectText.effect(db, e: Dictionary)
  -> String`, `EffectText.when(db, w: Dictionary) -> String`, `EffectText.triggers(db, triggers: Array) ->
  String`, plus the label constants.
- The compendium tool calls `EffectText`; the private copies are deleted from the tool.
- Tests (`tests/data/test_effect_text.gd`): one assertion per effect op against its expected sentence, using the
  fixture database; `when` conditions; trigger text; every `EFFECT_OPS` op returns a non-empty string (so a new op
  without text fails the test).
- Refactor proof: before the refactor, save the generated `documentation/compendium.md`; after it, regenerate and
  require a byte-identical file. Only then apply the audit changes in §5.

## 5. Compendium audit

### 5.1 Known problems

- The Items table lists the five held items, and the Held items section lists them again.
- The Category/Count table at the top has no row for Held items and links only to some sections.

### 5.2 Layout

New reading order: **Rules and Balance**, Types, Affinities, Statuses, Field States, Reactions, Passives,
Held items, Moves, Items, Creatures, Tamers, Encounters. Rules come first because everything after refers to
them. The contents table lists every section in that order with its count and a working anchor. The Items section
lists only non-held items; Held items has its own table and notes.

### 5.3 Systems checklist

During implementation, read the generated file against each system and fix gaps in the generator, not by hand:
held items (use kinds, aura scope, overworld effects), passives (rolled and Affinity, triggers, `when`, chance,
contact), growth tiers (per-species markers and the tier multipliers), the "Two foes" target and the spread
table in Balance, `party_size` and the level cap in Balance, move priorities and energy cost, the Underdog
numbers, creature Lv 99 stats, and that no `tp_` test-pack id appears (the generator loads `data/` only).
Anything found is fixed or listed in the sub-project's report with the reason it was left.

### 5.4 Tests

`tests/data/test_compendium.gd`: generate the document into a string and assert section headings appear exactly
once and in the §5.2 order; the contents table has one row per section with an anchor that matches a heading;
no held item id appears in the Items table; every held item appears in Held items; no `tp_` string appears;
the file ends with a newline. The existing check.sh step that regenerates the compendium stays.

## 6. Testing and verification

- New and changed suites: `test_effect_text`, `test_compendium`, the Settings scroll test, a `FieldItems`
  usability test (one case per row of §3.2), an `ItemIconSlot` test (size, per-category colour), and a bag test
  (hover changes the pane text; Back shows "Pick an item.").
- Real-window tour (`--mode=bag` or an extension of an existing tour): open the bag, move over three items,
  screenshot; open Settings, focus the last Controls binding, screenshot.
- `bash scripts/check.sh` ends "All checks passed."

## 7. Out of scope

The creature sprite slot, radar chart, summary card and the Summary, Box and Party redesigns (5b–5d); real item art
(M7); shop menu changes (the shop already shows the focused item); new item categories or item effects.

## 8. Risks

- The effect-text move touches a 100-line block used to build the whole compendium; the byte-identical check is
  the guard.
- The bag pane's height with long descriptions is checked by a screen-fit test against 404x344.
- Compendium section reordering changes anchors that other docs may link to; a grep for `compendium.md#` in
  `documentation/` and `README.md` is part of the plan.

## Amendments

Where the implementation differs from the text above (the code and tests are authoritative):

- §3.1: the pane is a fixed 404x344 page (inner 384x324) while the bag is open, not sized to its content, so it does not jump as the cursor moves. Description, Effect and use lines are capped at 6, 4 and 2 wrapped lines and cut with an ellipsis, so any text fits.
- §3.1: the pane's last line has no label (not "Usable now?"): it is just the reason text. `BagSummary.use_line(usability)` shows the usability reason as is when it is "Usable now." or informational ("Give it from the Summary.", "Used in battle.", "Can't be used.", "Can't be used here.", "Unknown item."), and prefixes the other not-ok reasons with "Can't use: " (for example "Can't use: No one needs it right now.").
- §3.1: the Effect line reads "Effect: —" when an item has no effect wording; a held item's line joins its always-on effects, trigger text and field effects with "; ". A price of 0 shows "Price: —". An unknown id shows the raw id as the title with category "Unknown", "Owned: N" and "Unknown item.", and no price, effect or use lines.
- §3.1: `SideMenu.page_control(content)` mounts the pane in the info page until the next `page()`; the pane is a new `BagSummary` (`game/overworld/ui/bag_summary.gd`). A bag with no items shows "Your bag is empty." instead of "Pick an item.".
- §3.2: `FieldItems.usability` considers `save.party` only, and "Can't be used here." is also what a `heal` item with no effects returns. A test checks that `usability.ok` agrees with whether the real `use` succeeds, and that `BagSummary.use_line` covers every reason `field_items.gd` can return.
- §2: no focus neighbours had to be added; Down from the tab bar already reached the first control. The test is `tests/game/test_settings_scroll.gd`.
- §4: the builder code moved to `tools/compendium_builder.gd` (`CompendiumBuilder.build(db)`); `tools/generate_compendium.gd` is only a thin runner that writes the file. `EffectText` also exposes the helpers the builder shares (`state_name`, `signed`, `num`, `pct`, `or_dash`) and the label constants `SIDE_LABELS`, `TARGET_LABELS`, `TRIGGER_LABELS`, `STAT_LABELS`.
- §5.2: the contents table shows "—" as the count for Rules and Balance (it holds settings, not entries); Held items counts items of category `held` and Items counts the rest. The old "Balance" section is now "Rules and Balance" with Battle format, Turn order, Multi-target damage, Underdog and Growth tier subsections. Anchors follow GitHub's rules (lower case, punctuation dropped, `-1` suffix for duplicates), and the file now ends with exactly one newline.
- §5.3: Passives and Held items blurbs now explain the two passive slots, trigger notation, aura scope and the overworld lead rule; the Creatures blurb notes that no shipped species has a growth tier yet.
- §5.4: `tests/data/test_compendium.gd` has 18 tests (layout, links, systems wording checked against the engine); the determinism test moved there from `test_effect_text.gd`.
- §6: the real-window tour is `--mode=bag`; the bag screenshots were checked for clipping. The Settings check is in the frontend tour (screenshots `16_`/`17_`): at 640x360 the Controls tab does overflow, real Down keys walk to the last binding, and it scrolls into view (scroll_vertical 93, button inside the scroll area).
- Left as is: two tamers named "Rival" give duplicate `### Rival` headings (a data matter); learnset tables have no priority column (priority is in Moves); the item icon is a placeholder until M7.
