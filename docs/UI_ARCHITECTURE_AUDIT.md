# Native UI architecture audit

## Findings before the refactor

The shared `sandbox_theme.tres` and main menu, HUD, toolbox, inspector and browser scenes were a useful foundation, but did not meet the requested editor-maintainability standard.

| Area | Violation | Correction |
| --- | --- | --- |
| `ui_factory.gd` | Constructed controls and applied per-label font/color overrides | Remove the runtime presentation factory; use native saved scenes and Theme variations |
| `sandbox_hud.gd` | Built every toolbar button and manually positioned an editing strip | Saved file/build/edit toolbar scenes inside containers |
| `main_menu.gd` | Built its button hierarchy only at runtime | Saved named menu buttons |
| `toolbox.gd` | Rebuilt a Button/VBox/TextureRect/Label hierarchy with per-entry dimensions | Instantiate `piece_card.tscn`; bind only model thumbnail, name, tooltip and selection |
| `inspector.gd` | Built action buttons and elevation layout at runtime | Saved inspector controls with signal binding in the script |
| `game_manager.gd` | Constructed all dialogs and their settings/menu content in code | Saved reusable dialog scenes; manager connects existing controls |
| Theme application | Only the main UI root explicitly referenced the Theme | Project-wide `gui/theme/custom`, plus a shared Theme reference in reusable UI scene roots |
| Labels and states | Scene/script font/color overrides and inline success colors | Named Theme variations for headings, secondary text and success/failure states |
| Browser window | Unthemed viewport background visible behind content | Full-size themed PanelContainer inside the saved Window scene |

## Reference rules

Theme lookup and the project-wide custom Theme follow [Introduction to GUI skinning](https://docs.godotengine.org/en/stable/tutorials/ui/gui_skinning.html). Reusable visual presets follow [Theme type variations](https://docs.godotengine.org/en/stable/tutorials/ui/gui_theme_type_variations.html). Containers own their children's layout as described in [Using Containers](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html); anchors position the outer HUD/margin or modal surface.

Game logic, persistence, physics, snapping and editing history remain separate from presentation. Runtime UI scripts may bind content, connect signals, select Theme variations, enable/disable controls, and show/hide contextual panels. They do not create ordinary visual controls or StyleBoxes. Dynamic toolbox entries are the intentional instantiation case.

The `.tres` is editable directly in Godot; `tools/create_theme.gd` is an optional offline authoring utility, never called by the game. Static `.tscn` content must preview without `_ready()` reconstructing its layout.

## Verification

The runtime UI scripts and saved UI scenes contain no `add_theme_*_override` calls, one-off StyleBox construction, local theme overrides, or code-created ordinary controls. Toolbox cards instantiate the saved widget scene. Layout minimum sizes remain in scenes; reusable spacing, fonts, colors, icons and control states live in the Theme.

The regression suite passes 97 checks, including editing/history, save/reopen, modal binding, Theme variations, moving fan collision and successful physical traversal of both example tracks. The conflicting `BuildManager.rotate()` method is now `rotate_piece()`.

The graphical verification runner instantiates the actual main scene and captures seven states at each of 1280×720, 1600×900 and 1920×1080: menu, empty sandbox, selection inspector, placement preview, paused simulation, track browser and settings. The 21 screenshots and measured viewport/layout records are in `docs/qa/`. No buttons below their minimum sizes or panels outside the viewport were reported. Visual inspection found that the inspector originally pushed the HUD offscreen at 720p; its content now uses a native ScrollContainer.

Graphical captures use the compatibility renderer; live editor checks use the project's Forward+ renderer. The sandboxed standalone engine reports a Windows certificate-store initialization error; it reports no script, resource-loading or game-runtime errors after the corrections. This is a UI architecture audit, not a claim that every gameplay edge case has been exhaustively tested.
