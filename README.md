# Marble Engineer

A Godot 4.7 marble construction sandbox using the Kenney Marble Kit, measured connector resources, mesh collision and physical marbles. Run `scenes/main.tscn` through the existing editor; keep one editor open for this project.

The interface retains the dark teal/mint direction. Its visual definitions live in `resources/sandbox_theme.tres` and saved scenes under `scenes/ui/`. Your current fonts are Theme resources. The scene hierarchies can be inspected and edited without running reconstruction scripts.

Sandbox, Puzzle Authoring, Puzzle Play and Test as Player operate through `scenes/construction_workspace.tscn`. The workspace binds the shared World and HUD; ConstructionSession owns context transitions and their distinct persistence. GameManager hosts navigation and application dialogs.

## Building

Piece definitions are managed through YARD's Registry tab and `resources/registries/piece_registry.tres`. Tracks, mechanisms, supports and authoring scenery share this registry. Entry IDs match the persistent IDs in each `PieceDefinition`; keep them stable when editing content. Category and behavior queries use its property index, rebuilt automatically on editor Play and export. See [Architecture](docs/ARCHITECTURE.md#resource-registries) for runtime integration and headless testing.

| Action | Control |
| --- | --- |
| Select / move | Click a piece / drag past the pointer threshold |
| Select together | Shift-click; drag a box from empty space |
| Add with a box | Shift-drag from empty space |
| Select connected tracks | Double-click a piece |
| Select all editable pieces | Ctrl+A |
| Rotate the selection / preview | R |
| Duplicate the selection into placement | Ctrl+D |
| Delete the selection | Delete |
| Cancel placement or dragging | Escape |
| Clear selection | Click empty space or Escape when no operation is active |
| Undo / redo | Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z |
| Choose attachment alternatives | Tab; R also cycles attachment orientations |
| Free-placement height | Page Up / Page Down or level buttons: 0.5 m; hold Shift: 0.125 m |
| Return placement to ground | Ground button beside the level controls |
| Raise/lower a selected assembly | Selection card height buttons |
| Save / test or pause | Ctrl+S / Space |
| Orbit / pan / zoom | Right drag / middle drag / wheel |
| Vertical camera pan | Shift + middle drag |
| Keyboard pan | WASD |
| Frame selection / construction | F / Home |
| Grid / magnetic snapping | G / C |

Sandbox testing requires a marble release; finish catchers are optional. Runs have no time limit, so loops can keep running. A catcher still ends the run when a marble reaches it.

Choose a piece once and click repeatedly to build. Point near a visible exposed connector: attachment determines position, quarter-turn orientation and elevation automatically. Away from connectors, placement uses the active grid plane and manual rotation. Click a selected track's small `+` connector indicator to open a compatible-piece inventory.

Dragging moves a whole selection on a stable horizontal plane, preserving height differences. Connector snapping can change the group's elevation. The first selected piece is the rotation anchor. A preview is valid only when the complete group fits; cancellation leaves originals untouched. Each confirmed group edit creates one history entry. Restoring history retains selected piece identities when they still exist.

The menu's spiral showcase uses a separate SubViewport/World3D, the playable example and the same physical simulation as the sandbox. Its camera motion is authored in `scenes/showcase.tscn` using AnimationPlayer. The demonstration loops without writing user saves. A new session starts empty; example tracks are available separately.

Music switches when entering the menu or the playable World, rather than from `_ready()`: both scenes stay loaded, and the showcase also contains a World instance. Assign the menu playlist on MainMenu and the building playlist on World in the Inspector. Sandbox, campaign and puzzle editing use World music; the showcase does not start its own music.

The Bucket Elevator is available under Mechanisms, with a playable example. Select it to adjust output rise and bucket speed. Supports come as six complete assemblies that extend their matching middle sections; select a support to set bearing height or choose the other top variant. Kit thumbnails use the supplied model previews. See [Mechanisms](docs/MECHANISMS.md) for settings and saved scenes.

## Campaign and Puzzle Editor

Choose **Campaign** from the main menu for the preserved Introduction and registered campaign puzzles with restricted construction, physical objectives, and saved progression. Sandbox retains the same building controls and unlimited inventory.

Choose **Puzzle Editor** to author community content. In project runs, **Ctrl+Shift+P** enters official authoring; the Settings destination selector can switch the same draft between Community and Campaign. Build with the sandbox tools, then use **Authoring tools** to set permissions, inventory, boundaries, objectives and mechanism links. **Test as Player** applies the actual campaign rules. A successful physical run can be preserved as a separate solution reference; publishing requires a current validated reference.

See [Puzzle authoring](docs/PUZZLE_AUTHORING.md), [architecture rules](docs/ARCHITECTURE.md), and [UI design rules](docs/UI_DESIGN.md).

## Tests

Use the installed GUT plugin in Godot's bottom panel. `.gutconfig.json` discovers `tests/test_*.gd`; individual suites and cases can be selected in the panel.

Run the same tests from the command line:

```powershell
godot --headless --path . --script addons/gut/gut_cmdln.gd -gexit
```

To run just settings and input regressions, add `-gselect=settings_and_input`. GUT reports assertions, engine errors, and exit status. Physics integration tests use the project's 120 Hz simulation. Persistence tests use `tests/support/game_test.gd` for unique `user://gut-tests/` directories and safe teardown. Tests loading `main.tscn` use `scene_test.gd` to snapshot and restore settings and bindings through public APIs. Pure resource and camera tests extend `GutTest` and use GUT autofree. Tests set display dimensions only when their assertions require them; player tracks, progress, drafts, and settings are isolated. Publication regressions write only into the isolated fixture; tests never publish real campaign content or rewrite bundled solutions.

Official authors use **Add to Campaign** to write project content and register it directly. Community authors use **Publish locally**, then **Export puzzle**; recipients choose **Community puzzles > Import puzzle**. Both retain the versioned JSON puzzle format. See [Puzzle authoring](docs/PUZZLE_AUTHORING.md) for storage, compatibility and export filters.

Settings include audio bus volumes, window mode and size, VSync, frame limits, MSAA, 3D render resolution, camera sensitivity and axis inversion, and keyboard rebinding. Changes save automatically; Restore defaults resets settings and bindings. Escape cancels placement or clears selection; right drag always controls the camera.
