# Marble Engineer

A Godot 4.7 marble construction sandbox using the Kenney Marble Kit, measured connector resources, mesh collision and physical marbles. Run `scenes/main.tscn` through the existing editor. Hera is available for inspecting that editor and its running game; avoid opening a second editor for this project.

The interface retains the dark teal/mint direction. Its visual definitions live in `resources/sandbox_theme.tres` and saved scenes under `scenes/ui/`. Your current fonts are Theme resources. The scene hierarchies can be inspected and edited without running reconstruction scripts.

## Building

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
| Cancel placement or dragging | Escape; right-click cancels placement |
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

Choose a piece once and click repeatedly to build. Point near a visible exposed connector: attachment determines position, quarter-turn orientation and elevation automatically. Away from connectors, placement uses the active grid plane and manual rotation. Click a selected track's small `+` connector indicator to open a compatible-piece inventory.

Dragging moves a whole selection on a stable horizontal plane, preserving height differences. Connector snapping can change the group's elevation. The first selected piece is the rotation anchor. A preview is valid only when the complete group fits; cancellation leaves originals untouched. Each confirmed group edit creates one history entry. Restoring history retains selected piece identities when they still exist.

The menu's spiral showcase uses a separate SubViewport/World3D, the playable example and the same physical simulation as the sandbox. Its camera motion is authored in `scenes/showcase.tscn` using AnimationPlayer. The demonstration loops without writing user saves. A new session starts empty; example tracks are available separately.

Music switches when entering the menu or the playable World, rather than from `_ready()`: both scenes stay loaded, and the showcase also contains a World instance. Assign the menu playlist on MainMenu and the building playlist on World in the Inspector. Sandbox, campaign and puzzle editing use World music; the showcase does not start its own music.

The Bucket Elevator is available under Mechanisms, with a playable example. Select it to adjust output rise and bucket speed. Supports come as six complete assemblies that extend their matching middle sections; select a support to set bearing height or choose the other top variant. Kit thumbnails use the supplied model previews. See [Mechanisms](docs/MECHANISMS.md) for settings and saved scenes.

## Campaign and Puzzle Editor

Choose **Campaign** from the main menu for ten puzzles with restricted construction, physical objectives, and saved progression. Sandbox retains the same building controls and unlimited inventory.

Press **Ctrl+Shift+P** to enter the developer Puzzle Editor. Build with the sandbox tools, then use **Authoring tools** to set permissions, inventory, boundaries, objectives and mechanism links. **Test as Player** applies the actual campaign rules. A successful physical run can be preserved as a separate solution reference; publishing requires a current validated reference.

See [Puzzle authoring](docs/PUZZLE_AUTHORING.md), [architecture rules](docs/ARCHITECTURE.md), and [UI design rules](docs/UI_DESIGN.md).

Run every regression and all ten positive/negative campaign cases with:

```powershell
./tools/verify_campaign.ps1
```

## Sandbox verification

```powershell
$env:APPDATA = "$PWD/.local-user"
godot --headless --path . --fixed-fps 120 --script tests/run.gd
godot --headless --path . --script tools/benchmark_snapping.gd
```

Test saves and verification logs stay in the ignored `.local-user` directory. Edit the shared Theme and saved scenes directly in Godot.

The maintained utilities in `tools/` are the regression runner (`verify_campaign.ps1`), compiler warning check (`check_gdscript.gd`), snapping benchmark (`benchmark_snapping.gd`) and published campaign importer (`import_campaign.py`). One-off generation, inspection and screenshot scripts have been removed.
