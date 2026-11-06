---
name: run-godot-monster-catching-game
description: Run, launch, drive and screenshot the Godot monster-catching game, or run its tests and content checks. Use when asked to start the game, play through the menus or a battle, take screenshots of a screen (splash, title, new game, load, settings, world, battle), verify a UI change in the real window, or run the test suite.
---

Godot 4.7 game (typed GDScript). Agents drive the real game window with
`.claude/skills/run-godot-monster-catching-game/driver.gd`, a `SceneTree` script that boots the
game, sends real keyboard input, presses buttons, checks expectations and saves PNG
screenshots. **Look at the screenshots** with the Read tool; tests can't catch layout bugs.

All paths are relative to the repo root. Verified on Windows 11 with Godot 4.7.2 (.NET build)
from the Bash tool (Git Bash). Not yet tried on Linux.

## Prerequisites

Godot **4.7.x**. The project targets 4.7, and its addons need a recent Godot: Dialogue Manager
4.2.0 requires 4.6+, and gdUnit4 6.2.3 supports 4.5–4.7.
Use the **console** executable so output reaches the terminal:

```bash
GODOT="/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

## Setup

On a fresh clone (no `.godot/` folder), import once so Godot builds the global class list.
Without it, scripts fail with `Identifier "DataLoader" not declared`:

```bash
"$GODOT" --headless --path . --import
```

## Run (agent path)

Front-end tour: splash → title → New Game (types "Ana") → overworld (autosave; Menu → Save;
Menu → Quit to title) → Load browser → every Settings tab → Controls tab again with real Down keys to the last binding, which must scroll into view inside the 640x360
window → rebind Accept to K → Resume. It checks 10 expectations and exits 1 if any fail. It takes about 13 s, and a game window opens while it runs.

```bash
timeout 120 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd 2>&1 | grep "\[driver\]"
```

Expected tail: `[driver] ALL CHECKS PASSED`. Screenshots (`01_splash_credit.png` …
`15_resumed_world.png`) and `driver.log` go to
`%APPDATA%/Godot/app_userdata/Monster Catching Game/run_shots/`. The driver prints the
absolute path.

Battle tour: new game → F1 debug menu → Get test party → Rival's "how many?" prompt (cancel) →
wild battle (attack, F1 mid-battle, throw a Lure Cage, fight to the end) → results → world
(autosave) → a 1-vs-2 Rival battle showing Underdog → F1 → Custom battle set to a 3v1 tamer
fight. It checks 8 expectations. It takes about 40 s, and fights are random
(the wild pack and whether the cage catches).

```bash
timeout 240 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=battle --out="$TMPDIR/battle_shots" 2>&1 | grep "\[driver\]"
```

Overworld tour (M3): home → walk out the door into town → the professor's cutscene → pick a
starter in the lab → the lab rival battle → heal centre (rest, buy a Salve) → Route 1: walk up
the path into Scout Ana's sight line and win → step into tall grass (encounter rate forced to
100%) and run → Quick Draw → Menu → Save → Quit → Resume at the same tile. It checks 10
expectations and takes about 70 s. Long walks between buildings use `ow.change_map()`; the
starter is boosted to level 20 before Route 1 so the scripted fights are won (a loss sends you
to the heal centre and the tour would wander off).

```bash
timeout 400 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=overworld --out="$TMPDIR/ow_shots" 2>&1 | grep "\[driver\]"
```

Progress tour (M4): new game → F1 → Get test party → Set Affinity (Striker) → Give XP to level 16 →
Learn Move (replace one, keep the others) → Grow now (Tidepup → Torrentusk) → Menu → Party (move it to
second place) → Summary (all three tabs, +1 Speed) → Bag → Reset Seed → the heal centre's Storage Box
(deposit, withdraw) → Route 1's deep grass, where Party → a row says it isn't safe to swap. It checks
21 expectations and takes about 60 s. It places the player with `ow.player.place(...)` and uses
`ow.change_map()` for the trips (as the overworld tour does) and walks the last tiles into the grass.
Menu choices use `pick_menu(label)` (`CommandMenu.pick_label`); tabs use real Left/Right keys.

```bash
timeout 300 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=progress --out="$TMPDIR/progress_shots" 2>&1 | grep "\[driver\]"
```

Passives tour: new game → F1 → Get test party → Set passive... (Tidepup's Rolled slot = Undertow, made
active) → a wild battle against a level-5 Pebblet, opened with `router.goto(...)` and seed 7, where
Undertow's entry trigger shows the "Tidepup's Undertow!" banner and soaks the foe side → back to the
world → Set Affinity (Striker), which unlocks Finisher → the Passive Unlocked screen (Keep current) →
Menu → Party → Tidepup → Summary (Stats shows both passives) → Use Finisher. It checks 14 expectations
and takes about 10 s. The banner fades on its own, so the tour polls `last_passive_banner` every frame
and screenshots it once it is fully shown. The Passive Unlocked screen normally appears after a battle;
the tour calls `PassiveUnlockScreen.run(ow, creature, db)` directly after the debug unlock.

```bash
timeout 240 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=passives --out="$TMPDIR/passives_shots" 2>&1 | grep "\[driver\]"
```

**Held-items tour** (`--mode=held`): new game -> F1 test party -> an Oran Berry put in the bag -> Menu -> Party -> Tidepup ->
Summary -> Give held item -> Oran Berry (the Stats tab then reads "Held item: Oran Berry - ...") -> a seeded wild battle
with Tidepup under half HP: the berry fires (banner "Tidepup's Oran Berry!", then "Tidepup's Oran Berry was used up.") ->
back in the world the Summary reads "Held item: none". The tour puts the berry in the bag directly (there is no F1 give-item page).

```bash
timeout 300 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=held --out="$TMPDIR/held_shots" 2>&1 | grep "\[driver\]"
```

**Team-builder tour** (`--mode=builder`): new game -> F1 test party -> Custom battle -> grow your team to
`party_size`, All levels 40, You field 2 -> Foe team: Tamer, Foes field 3, `party_size` foes -> Edit foe 1 (a
"✗ can't learn" move, the move list open) -> Your team -> Bag... -> Start a 2v3 exhibition -> fight to the results
("Exhibition — nothing was saved.") -> the save is unchanged and nothing was autosaved. Every page is checked to
fit the 640x360 screen inside its 340px column. 25 expectations, about 30 s.

```bash
timeout 300 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=builder --out="$TMPDIR/builder_shots" 2>&1 | grep "\[driver\]"
```

**Party tour** (`--mode=party`, optional `--party-size=N`, 1-12): a new game with a full party of N (default
`balance.party_size`) and 12 creatures in the box -> Menu -> Party (Down to the last row) -> Summary -> Next creature
all the way round -> Bag -> Salve's "use on who?" list -> the centre's Storage Box (party page 2 when the party is
paged, the swap-with-party list) -> a singles wild battle's Swap menu (Next page, Accept wraps) and Salve's targets.
N is set on the loaded content in memory only, so `data/balance.json` is never edited. Screenshots are `qNN_01_...`
to `qNN_12_...` (NN = the party size), so runs at 6 and 12 can share a folder. About 15 s.

```bash
timeout 300 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=party --party-size=12 --out="$TMPDIR/party_shots" 2>&1 | grep "\[driver\]"
```

**Bag tour** (`--mode=bag`): new game -> F1 test party (Tidepup set to 1 HP) -> a Salve, an Oran Berry, a Lure Cage
and an item with a very long description (added to the loaded content in memory only, never to `data/`) in the bag ->
Menu -> Bag -> real Down keys through the list: the left pane shows each focused item (icon, name, category, count,
price, description, effect, usability line such as "Usable now." or "Can't use: ...") and must sit inside its 404x344 page; Back shows "Pick an item." ->
Salve's "use on who?" page replaces the pane -> Back -> the pane is gone after closing the bag. 12 expectations, about 10 s.

```bash
timeout 200 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=bag --out="$TMPDIR/bag_shots" 2>&1 | grep "\[driver\]"
```

Screenshot a single scene:

```bash
timeout 60 "$GODOT" --path . --script res://.claude/skills/run-godot-monster-catching-game/driver.gd -- --mode=scene --scene=res://game/menus/settings_menu.tscn --frames=30 --out="$TMPDIR/shots"
```

| option | meaning |
|---|---|
| `--mode=frontend` | default; the tour above |
| `--mode=battle` | the battle tour above (`b00_…` to `b13_…` screenshots) |
| `--mode=overworld` | the overworld tour above (`o01_…` to `o16_…` screenshots) |
| `--mode=progress` | the progress tour above (`p01_…` to `p21_…` screenshots) |
| `--mode=passives` | the passives tour above (`x01_…` to `x08_…` screenshots) |
| `--mode=held` | the held-items tour above (`h01_…` to `h06_…` screenshots) |
| `--mode=builder` | the team-builder tour above (`t01_…` to `t12_…` screenshots) |
| `--mode=party` | the party tour above (`qNN_01_…` to `qNN_12_…`); `--party-size=N` sets the party size in memory |
| `--mode=bag` | the bag tour above (`bag01_…` to `bag07_…` screenshots) |
| `--mode=scene` | open `--scene` (default: main scene), wait `--frames` (default 60), screenshot |
| `--out=<dir>` | screenshot folder; `user://` paths allowed (default `user://run_shots`) |

Each tour is its own file in `tours/` (`frontend.gd`, `battle.gd`, `overworld.gd`, `progress.gd`,
`passives.gd`, `held.gd`, `builder.gd`, `party.gd`, `bag.gd`):
a `RefCounted` with `var d` (the driver) and `func run()`. To drive a new flow, add
`tours/<name>.gd`, add `<name>` to the `match` in `driver.gd`'s `_initialize`, and call the
driver's helpers through `d.`: `wait_scene(name, max_frames)`,
`key(KEY_X)`, `type_text("abc")`, `press("Button text")`, `shot("name")`, `expect(ok, "what")`,
for battles `wait_battle(["command"])`, `fight_to_end()` and `pick_menu("Fight")` (`""` picks the
first enabled option), and for the overworld `hold(KEY_W, frames)` (real movement),
`talk_until(func(): ...)` (presses Accept through conversations) and `_battle()` (the battle node,
whether it's the scene or an overlay on the map). You can also open a battle directly:
`router.goto("res://game/battle/battle_scene.tscn", {"setup": BattleSetup, "seed": 11})`.
For any N-vs-M format (up to 3 per side on the field), build an exhibition (nothing saved) from
hand-built teams: `BattleLauncher.exhibition_setup(db, mine, mine_field, foes, foe_field, wild, bag, rng)`,
where `mine`/`foes` are arrays of `CreatureSpec.natural(db, species, level, rng)`.

## Run (human path)

```bash
"$GODOT" --path .   # opens the game at the splash screen; close the window to stop
```

## Test

```bash
bash scripts/check.sh
```

This validates the JSON content, compiles the dialogue, runs every gdUnit4 suite and regenerates
`documentation/compendium.md`. Expected: `All checks passed.` with one `Statistics:` line per test
suite, all `PASSED`.

## Gotchas

- **Read the game's log when something goes wrong.** Each windowed run writes
  `%APPDATA%/Godot/app_userdata/Monster Catching Game/logs/session_<date>_<time>.log` (newest 10
  kept; headless runs write none). It includes engine/script errors with stack traces. To trace
  more, put levels in `user://logging.cfg` (`[levels]` `battle="TRACE"`, `world="DEBUG"`) before
  the run; see `documentation/logging.md`.

- **Don't use `--headless` for screenshots.** The driver waits on
  `RenderingServer.frame_post_draw`, which never fires without a renderer, so the run hangs
  until `timeout` kills it (exit 124, no PNG). Headless is fine for `--import` and the tests.
- **`--script` replaces the main scene.** The driver has to `change_scene_to_file()` the main
  scene itself. Autoloads (`GameState`, `SceneRouter`, `Settings`) still load. From a
  `SceneTree` script, reach them through `root.get_node("GameState")`.
- **Wait for the fade.** `SceneRouter.goto()` fades out, swaps and fades back in. The new scene
  exists before input works, so `wait_scene()` also waits for `SceneRouter.is_busy()` to be false.
- **Typing into a LineEdit needs `unicode`** on the `InputEventKey`; keycodes alone type nothing.
- **Keep the player's data untouched.** The tour swaps `GameState.store` to `user://run_saves`
  and deletes it afterwards. It never presses Settings → Back, because Back writes
  `settings.json`; it calls `reset_bindings()` + `apply_controls()` instead. Keep this
  isolation when adding flows.
- **The driver lives in a dot folder Godot doesn't scan**, but `res://.claude/...` still works
  as a `--script` path, and the project's `class_name` types (`SaveStore` etc.) resolve normally.
- **The Godot editor can stay open** while you run the driver and tests. It regenerates `.uid`
  files on its own; that's expected.
- **The debug tools are an F1 overlay (autoload `DebugMenu`), not part of any scene.** Open it with
  `key(KEY_F1)`. `press()` and `pick_menu()` search the overlay first when it's open, then
  `current_scene`; a search of `current_scene` alone never finds its buttons. The overlay pauses
  the tree while open, so battle playback timers stop until it closes.
- **Overworld battles are overlays, not scenes.** Wild, tamer and debug battles open the battle
  scene over the paused map (`current_scene` stays `Overworld`). Use `_battle()` to find it and
  wait for `_battle() == null` afterwards; `wait_scene("BattleScene")` only works for battles
  opened directly with `router.goto(...)`.
- **Hold keys for movement.** `key()` taps for one frame; walking needs `hold(KEY_W, frames)`
  (4 tiles a second, so 8 frames per tile). Movement is locked during conversations, menus and
  fades, so a key held through a door doesn't carry on walking on the other side.
- **Map tools run as scenes, not `--script`.** Piece scripts use autoloads (`Story`), which don't
  compile under `--script` (the piece's Inspector settings are silently dropped). So it's
  `godot --headless --path . res://tools/build_maps.tscn` and `res://tools/check_maps.tscn`. The
  driver itself can't name `Overworld` or `SceneRouter.WORLD`; it uses untyped variables and
  `router.WORLD`.
- **Battle menus are `CommandMenu`s, not plain buttons.** Drive them with `pick_menu()`, which
  finds the menu that's currently choosing. Wait for `scene.phase` with `wait_battle()`: the menu
  only accepts picks once `menu.is_choosing()` is true. Playback between phases runs on timers.
- **Random content makes screenshots differ between runs.** The wild pack can be one or two
  creatures, so the "how many?" prompt doesn't always appear. Screenshot prompts from something
  deterministic (the Rival is always 2v2) or pass a `seed` when opening a battle directly.
- **Layout bugs only show in screenshots.** Labels with autowrap inside a `GridContainer`
  collapsed to one character per line and passed every test; the Controls-tab screenshot was
  what caught it.

## Troubleshooting

- **`ERROR: .NET Sdk not found. The required version is '8.0.20'.`** The .NET editor build
  wants the .NET SDK. It's harmless here (GDScript only); ignore it or use the non-.NET Godot.
- **`Parse Error: Identifier "DataLoader" not declared in the current scope`**: the class cache
  is missing or stale. Run the `--import` command from Setup (twice if the first run was
  interrupted).
- **`Failed to load script "res://addons/dialogue_manager/plugin.gd" with error "Compilation failed"`**:
  the Dialogue Manager version doesn't match the Godot version. This happened with Dialogue
  Manager 3.3.3 (built for 4.3) opened in 4.7. Keep the addons matched to the engine (see
  Prerequisites).
