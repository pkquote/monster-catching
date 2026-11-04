# M2 Battle Scene — Design

Date: 2026-11-03
Builds on: [monster RPG design spec](2026-11-03-monster-rpg-design.md) §2–3, §6 and
[battle engine reference](../battle-engine.md).

## 1. Goal

A playable battle screen on top of the headless engine. The scene **never computes outcomes**:
it sends the player's choices to `BattleEngine.resolve_round()` and plays back the returned events.
Success means every engine feature is reachable and readable on screen: 1v1 to 3v3 and uneven
formats, Underdog, field states and reactions, statuses, energy and Rest, Scrap, swaps, items,
catching, fleeing, Bond misbehaviour, XP and level-ups.

## 2. Getting into a battle (until M3)

- The placeholder world gets a **Test battles** panel:
  - **Wild encounter**: rolls a pack from `route_01_grass` (1–2 creatures).
  - **Scout Ana** (1v1 tamer).
  - **Rival** (2v2 tamer).
  - **Custom battle**: any format from 1v1 to 3v3, including uneven ones (1v3, 3v1, 2v3...).
    You pick how many you field (up to your healthy creatures), how many foes, wild or tamer,
    and the foes' level (defaults to your party's average). Foes are random species. Wild foes
    can be caught and fled from; a tamer ("Sparring Partner") uses the tactician AI and has no
    bench, items or prize money. Built by `BattleLauncher.custom_setup`.
- New games still start with an empty party (starter choice comes with M3). The world offers
  **Get test party** (clearly labeled as debug). It adds Tidepup (starter Bond), Emberkit and
  Voltmoth at level 8, and a bag (Lure Cage ×5, Tide Net ×3, Snare Vine ×3, Salve ×3, Tonic ×2),
  all saved to the playthrough.
- Before a battle starts, the player chooses **how many creatures to field** (1 up to the format,
  limited by healthy party members). Fielding fewer is how the player opts into Underdog.
- `game/battle/battle_launcher.gd` builds the `BattleSetup` from the save and the request, then
  opens the battle scene through `SceneRouter` with the setup in `params`.

## 3. Screen layout (640×360)

```
┌──────────────────────────────────────────────────────────────┐
│                         [enemy field chips]    UNDERDOG ×1.5 │
│                                   ◆ Foe 3                    │
│                              ◆ Foe 2                         │  stage (0–236)
│                         ◆ Foe 1           ← upper-right diagonal
│   ◆ Ally 1                                                    │
│        ◆ Ally 2         ← lower-left diagonal                 │
│             ◆ Ally 3                                          │
│ [ally field chips]                                            │
├──────────────────────────────────────────────────────────────┤
│ message line: "Tidepup used Riptide! It's super effective."  │  panel (236–360)
│ ┌ command menu / move list / target prompt / bench list ─────┐│
└──────────────────────────────────────────────────────────────┘
```

- **Creature view:** a placeholder sprite (a rounded shape in the primary type's colour with the
  species' initial; dual types get a second-colour ring), name, level, HP bar and status tag.
  Player creatures also show an energy bar and numeric HP. Effects: a flash on damage, a nudge on
  attack, fade-out on faint, drop-in on send-out.
- **Field chips** per side: `Soaked ×2 · 3` (stacks · rounds left). The ground band under each
  side is tinted by its newest state.
- **Underdog badge** on the outnumbered side, showing its extra actions.
- **Reactions** get a large centred banner ("CONDUCTION!") before their effects play.

## 4. Turn flow

1. **Command phase:** one prompt per action slot in `engine.actions_needed(0)` (Underdog repeats
   a creature). Top menu: **Fight · Items · Swap · Rest · Run** (Run only in wild battles).
   - **Fight:** the creature's moves plus Scrap, each showing type, category, power and cost.
     Moves it can't afford are disabled.
   - **Target:** asked only for `one_enemy` / `one_ally` moves and items. Left/right cycles,
     Accept confirms, the target is highlighted.
   - **Items:** usable items from the bag with counts. Capture items are hidden in tamer battles.
   - **Swap:** healthy benched creatures.
   - **Cancel** steps back. After the last slot, if `confirm_end_turn` is on, "End turn?" Yes/No.
2. **Resolve:** `engine.resolve_round(actions)`. AI sides choose inside the engine.
3. **Playback:** events play one at a time. Each event updates the views and shows a message.
   Timing is scaled by `Settings.battle_speed`, and holding Accept plays at ×4.
4. **Replacement:** if `engine.pending_replacements(0) > 0`, choose a benched creature or
   "Leave empty" (stay outnumbered).
5. Repeat until `engine.is_over()`, then show the **results** panel.

## 5. Catching

Using a capture item plays a short sequence: the item flies to the target, the target shrinks
into it, then shakes (more shakes for higher chance). Then either "Caught Sprigling!" or it breaks
free. Caught creatures join the party, or storage if the party is full (`balance.party_size`).

## 6. Results and persistence

- **Results panel:**
  - Outcome: victory, defeat, fled, captured, or draw.
  - XP gained per creature, and level-ups with new moves.
  - Bond changes and Affinity gains.
  - Money from tamers (`reward_money`).
- **The engine mutates the save's `CreatureInstance`s directly**, so HP, energy, status, XP and
  Bond are already up to date. The scene writes back the item bag, catches and money, then returns
  to the world, which autosaves.
- **Defeat (placeholder until M3):** the party is fully healed and you return to the world.

## 7. Code structure

| File | Responsibility |
|---|---|
| `game/battle/battle_launcher.gd` | Builds `BattleSetup` from the save + request; test party/bag grant |
| `game/battle/battle_scene.gd` (+ `.tscn`) | Owns the engine; runs command → resolve → playback → replace phases |
| `game/battle/battle_playback.gd` | Turns one engine event into view updates + message, awaiting animations |
| `game/battle/battle_text.gd` | Pure: event → message text (testable without UI) |
| `game/battle/creature_view.gd` | One battler's sprite, bars and effects |
| `game/battle/field_view.gd` | One side's field chips and ground tint |
| `game/battle/command_menu.gd` | Command / move / item / swap / target / confirm menus |
| `game/battle/type_colors.gd` | Placeholder colour per type |

## 8. Testing

- **Unit tests:**
  - `BattleText` covers every event type the engine emits.
  - `BattleLauncher` covers setup building: field count limits, tamer vs wild, and the test party
    grant being idempotent.
- **Smoke test:** the battle scene builds and runs one full round headlessly with scripted choices.
- **Driver:** a new `--mode=battle` drives a wild battle through command menu → move → target →
  playback → capture attempt → results, screenshotting each step. It's added to the run skill.

## 9. Out of scope for M2

Real sprites and animations, sound, the overworld, defeat consequences, move-learning choice UI
(`move_offered` shows a message only), the growth/evolution scene, and tamer item use by the AI.
