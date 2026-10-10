# Super Dungeon Fighter

A real-time 3D dungeon brawler built in **Godot 4.7** for iPhone and iPad
(it also runs on Android and desktop). You control one hero with a 30-card
deck of skills and a hand of 5. Tap to move, tap enemies to attack, tap cards
to charge skills that fire when you tap a target. The camera follows you
across an arena larger than the screen. Clearing a dungeon earns a random
card; deeper dungeons drop rarer, stronger cards.

The design comes from `Super_Dungeon_Fighter_Board_Game.pdf` (originally a
turn-based board game); the complete rules as implemented, including every
gap the document left open, are in [RULES.md](RULES.md).

## Layout

| Path | What it is |
|---|---|
| `scripts/core/battle_sim.gd` | The real-time rules engine: movement, engagement, casting, combo state machine, chains. Pure GDScript, no scene nodes. |
| `scripts/core/battle_map.gd` | Arena with box obstacles and A* pathfinding on a coarse grid. |
| `scripts/core/monster_ai.gd` | Monster brains: chase, basic attacks, skill charging. |
| `scripts/core/dm_ai.gd` | The Dungeon Master's summoning within the budget. |
| `scripts/core/save_data.gd` | Persistent roster (levels, XP, card collections, decks), card rewards, Dark Lord progression. JSON in `user://`. |
| `scripts/core/session.gd` | Runtime state shared between scenes (chosen hero, difficulty, last result). |
| `scripts/core/actor.gd` | Hero / monster state. |
| `scripts/data/skill_db.gd` | The skill table (ranks C/B/A/S, costs, priority, chains) and the card rarity formula. |
| `scripts/data/hero_db.gd`, `monster_db.gd` | Hero classes with starter decks, and the monster roster. |
| `scripts/ui/battle_scene.gd` | The 3D battle: rendering, camera, tap/hold/double-tap input, HUD. |
| `scripts/ui/*.gd`, `scenes/*.tscn` | Menu, town (deck builder), run setup. |
| `tests/run_tests.gd` | Headless rules tests and scripted-hero fuzzing. |
| `tests/smoke_ui.*`, `tests/screenshot.*` | Drive the real scenes end to end; the latter saves screenshots. |

## Running on desktop

```bash
godot --path .            # or open the folder in the Godot 4.7 editor and press Play
```

The window is a 486 x 864 portrait preview of the 1080 x 1920 design
resolution; mouse clicks emulate touches.

## Tests

```bash
godot --headless --path . --import            # once, builds the class cache
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . res://tests/smoke_ui.tscn
godot --path . res://tests/screenshot.tscn -- /tmp/shots   # needs a display
```

## Building for iPhone / iPad

Godot exports an Xcode project; Apple's toolchain does the signing.

1. On a Mac with Xcode installed, open the project in Godot 4.7 and install the
   export templates (Editor > Manage Export Templates).
2. Project > Export > **iOS** (the preset is in `export_presets.cfg`). Set your
   Team ID and a bundle identifier, then **Export Project**.
3. Open the generated `.xcodeproj`, pick your device or simulator, and Run.
   Orientation is locked to portrait and the UI scales to any screen size.

The Android preset is also included: install the Android build template and
export an APK the same way.

## Design notes

* The simulation never touches scene nodes, so rules can be tested headless;
  the 3D scene only renders it and feeds it commands.
* Board-game numbers map to the real-time game through a few constants at the
  top of `battle_sim.gd`: one tile is 1.5 m, load time and cooldown turns are
  1.2 s each, stun turns are 1 s, down turns 1.3 s.
* **Shield Charge** from the design document is deliberately not implemented
  yet; its row in the table was left for later design.
