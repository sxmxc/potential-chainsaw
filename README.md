# Marble Engineer

Marble Engineer is a 3D marble-track construction and physics puzzle game made with Godot and Kenney's Marble Kit. Build a machine, release its marbles, and watch where the design works—or where it needs another try. Tracks connect across elevations, and mechanisms can lift, launch, divert, or stop marbles.

**Sandbox** gives you unrestricted inventory and personal track saves. **Campaign** asks you to solve authored machines with limited pieces, fixed parts, and physical objectives. The current campaign registers ten optional Introduction puzzles and four Chapter 1 puzzles. **Puzzle Editor** uses the same building tools to create starting layouts, set player permissions, and test solutions before publishing.

Community puzzles can be shared as JSON files or through the optional online service. Local building, campaign play, authoring, and JSON sharing do not require an account. Online creator actions use Steam ticket verification when Steam is initialized, or an existing email/password account otherwise. Production Steam authentication still needs validation with the game's release AppID and credentials.

The project is in development; the configured game version is `0.0.1`.

## Run from source

1. Clone the repository and import `project.godot` in Godot **4.7**. The executable used for this documentation audit reports **4.7.2**. The game uses GDScript; .NET is not required.
2. Let Godot import assets and load the bundled addons. Keep the configured plugins enabled.
3. Press **F6** with `scenes/main.tscn` open, or **F5** to run the configured main scene.

From the repository root, with Godot on `PATH`:

```powershell
godot --path .
```

The project uses Forward Plus rendering and Jolt physics at 120 ticks per second. Bundled dependencies include GodotSteam 4.23.1, Phantom Camera 0.11.0.3, YARD 1.3.1, SoundManager 1.0, and GUT 9.7.1. Steam initialization currently uses development AppID `480`; an unavailable Steam client produces a warning, while local play remains available. GodotSteam's native library must still load for the platform running the project.

## Build and test a track

Choose a piece from the toolbox, then click to place it repeatedly. Point near an exposed connector to align position, rotation, and elevation automatically. Away from a connector, placement uses the grid and active building height. Click a selected track's `+` connector marker to choose a compatible extension.

Click to select and drag to move. Groups retain their relative positions and heights; each confirmed group edit is one undoable action. Add a marble release before testing. Ordinary Sandbox testing requires exactly one release, which can emit multiple marbles; a finish catcher is optional. Reset returns to building without discarding your layout.

| Action | Default control |
| --- | --- |
| Select together | Shift-click or drag a box from empty space |
| Select connected tracks / all editable pieces | Double-click / Ctrl+A |
| Rotate / duplicate / delete | R / Ctrl+D / Delete |
| Cancel an operation or clear selection | Escape |
| Undo / redo | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z |
| Cycle attachments | Tab |
| Change free-placement height | Page Up / Page Down; hold Shift for finer steps |
| Save / test or pause | Ctrl+S / Space |
| Orbit / pan / zoom | Right drag / middle drag / wheel |
| Vertical pan / keyboard pan | Shift + middle drag / WASD |
| Frame selection / construction | F / Home |
| Toggle grid / snapping | G / C |

Settings contains keyboard bindings, camera, audio, and graphics options. During a run, click an exposed marble or use the camera button to follow it; stop following to return to the free view.

## Development

Use the GUT panel in Godot, or run the focused suite:

```powershell
godot --headless --path . --script addons/gut/gut_cmdln.gd -gexit
```

Add `-gselect=settings_and_input` to select a file. Tests cover rules, construction operations, geometry, persistence, and service contracts without running the application or campaign routes. Persistence fixtures isolate player saves. See [Architecture](docs/ARCHITECTURE.md#verification) for verification boundaries.

The Windows Desktop export preset writes to `build/windows/`. Install matching Godot export templates and create that output directory before exporting through **Project → Export**. The preset includes campaign/example JSON and public Supabase configuration; backend source is excluded. Other platforms need their own export configuration and matching native dependencies.

- [Architecture and system ownership](docs/ARCHITECTURE.md)
- [Puzzle authoring, formats, and distribution](docs/PUZZLE_AUTHORING.md)
- [Mechanisms](docs/MECHANISMS.md) and [piece authoring](docs/PIECE_AUTHORING.md)
- [Community backend and Steam authentication](docs/COMMUNITY_SERVICE.md)
- [UI design](docs/UI_DESIGN.md)
- [Reusable Supabase client](addons/supabase_client/README.md)
- [Coding-agent instructions](AGENTS.md)
