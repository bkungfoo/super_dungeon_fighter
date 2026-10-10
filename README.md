# Super Dungeon Fighter

A simultaneous-reveal tactics brawler built in **Godot 4.7** for iPhone and iPad
(it also runs on Android and desktop). Each hero brings a 30-card deck of
skills and holds a hand of 5. Heroes plan a move and a card face down, the
Dark Lord's monsters do the same, and everything resolves at once in priority
order: positioning, prediction and combo chains decide the fight. No dice.
Clearing a dungeon earns every hero a random card; deeper dungeons drop rarer,
stronger cards.

The design comes from `Super_Dungeon_Fighter_Board_Game.pdf`; the complete
rules as implemented, including every gap the document left open, are in
[RULES.md](RULES.md).

## Layout

| Path | What it is |
|---|---|
| `scripts/core/game_engine.gd` | The rules engine: phases, movement, skills, combo state machine, chains. Pure GDScript, no scene nodes. |
| `scripts/core/dm_ai.gd` | The Dungeon Master AI: summons monsters, lays walls, plays them each round. |
| `scripts/core/save_data.gd` | Persistent roster (levels, XP, card collections, decks), card rewards, and Dark Lord progression. JSON in `user://`. |
| `scripts/core/session.gd` | Runtime state shared between scenes (party, difficulty, last result). |
| `scripts/core/unit.gd`, `board_grid.gd` | Unit and grid data. |
| `scripts/data/skill_db.gd` | The skill table (ranks C/B/A/S, costs, priority, chains) and the card rarity formula. |
| `scripts/data/hero_db.gd`, `monster_db.gd` | Hero classes with starter decks, and the monster roster. |
| `scripts/ui/*.gd`, `scenes/*.tscn` | Touch UI: main menu, town, run setup, the dungeon screen. |
| `tests/run_tests.gd` | Headless rules tests and AI-vs-AI fuzzing. |
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

* The engine never touches scene nodes, so rules can be tested headless and the
  same engine could later drive a pass-and-play or networked Dungeon Master.
* Monster cards played face down are hidden from the log and the board shows
  only their load counters, preserving the board game's hidden information.
* **Shield Charge** from the design document is deliberately not implemented
  yet; its row in the table was left for later design.
